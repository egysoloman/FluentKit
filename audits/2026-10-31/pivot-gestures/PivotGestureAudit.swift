import AppKit
import FluentKit

@main struct PivotGestureAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        var clock: TimeInterval = 10
        func scroll(_ dx: CGFloat, _ phase: Int64, dy: CGFloat = 0) -> NSEvent {
            clock += 0.01
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
            event.timestamp = CGEventTimestamp(clock * 1_000_000_000)
            return NSEvent(cgEvent: event)!
        }
        let headers = ["All", "Unread", "Flagged", "Urgent", "Archive"]
        for variant in ["light", "dark", "rtl"] {
            for (layout, width) in [("static", CGFloat(520)), ("carousel", CGFloat(300))] {
                let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
                let rtl = variant == "rtl"
                let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
                let selection = FluentState(wrappedValue: 0)
                let host = FluentViewHost(FluentAnyView(FluentPivot(headers, selection: selection.projectedValue, title: "EMAIL",
                    header: { $0 }) { name in
                    FluentVStack(spacing: 6) {
                        FluentText(name, style: .subtitle)
                        FluentText("\(name) messages", style: .body, color: theme.textSecondary)
                    }.padding(12).frame(width: width - 24, height: 80).background(theme.cardFill, cornerRadius: 8)
                }.frame(width: width, height: 200)), context: context)
                host.wantsLayer = true
                host.layer?.backgroundColor = theme.windowBackground.cgColor
                let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: width, height: 200),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                host.layoutSubtreeIfNeeded()
                let pivot = descendants(host).first { $0.identifier?.rawValue == "FluentKit.Pivot" }!
                // Physical deltas: a leading-edge swipe is negative in LTR and positive in RTL.
                let towardNext: CGFloat = rtl ? 1 : -1
                func capture(_ state: String) throws {
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    CATransaction.flush()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                    // Render the composited layer tree: cacheDisplay redraws views itself and
                    // does not reliably apply the layer transforms a pan uses.
                    let scale: CGFloat = 2
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                        pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                    context.scaleBy(x: scale, y: scale)
                    if host.isFlipped {
                        context.translateBy(x: 0, y: host.bounds.height)
                        context.scaleBy(x: 1, y: -1)
                    }
                    host.layer!.render(in: context)
                    try bitmap.representation(using: .png, properties: [:])!
                        .write(to: output.appendingPathComponent("\(variant)-\(layout)-\(state).png"))
                    let firstHeader = descendants(pivot).first { $0.identifier?.rawValue == "FluentKit.Pivot.Header.0" }!
                    let content = descendants(pivot).first { $0.identifier?.rawValue == "FluentKit.Pivot.Content" }!
                    fputs("\(variant)-\(layout)-\(state) header0=\(Int(firstHeader.frame.minX)) content=\(content.subviews.map { $0.isHidden ? "h" : "\(Int($0.frame.minX))" })\n", stderr)
                    let visible = descendants(pivot).filter {
                        ($0.identifier?.rawValue ?? "").isEmpty && $0.superview?.identifier?.rawValue == "FluentKit.Pivot.Content" && !$0.isHidden
                    }.count
                    records.append(["variant": variant, "layout": layout, "state": state,
                                    "selection": selection.wrappedValue, "visibleContentItems": visible,
                                    "touchScreen": "pending device", "windowsComparison": "pending"])
                }
                // Mid-pan toward the next item: content, neighbour and (carousel) headers move.
                pivot.scrollWheel(with: scroll(towardNext * 5, 1))
                for _ in 0..<6 { pivot.scrollWheel(with: scroll(towardNext * 15, 2)) }
                try capture("pan-next")
                // The finger rests before lifting, so the release carries no velocity.
                clock += 0.2
                pivot.scrollWheel(with: scroll(0, 2))
                pivot.scrollWheel(with: scroll(0, 4))
                precondition(selection.wrappedValue == 0, "A short slow pan snaps back")
                // Toward the previous item: static ends rubber-band, the carousel wraps.
                pivot.scrollWheel(with: scroll(-towardNext * 5, 1))
                for _ in 0..<8 { pivot.scrollWheel(with: scroll(-towardNext * 20, 2)) }
                try capture(layout == "static" ? "overpan" : "pan-previous-wrap")
                pivot.scrollWheel(with: scroll(0, 4))
                precondition(selection.wrappedValue == (layout == "static" ? 0 : 4), "Only the carousel wraps")
                // A quick swipe commits.
                pivot.scrollWheel(with: scroll(towardNext * 5, 1))
                for _ in 0..<6 { pivot.scrollWheel(with: scroll(towardNext * 40, 2)) }
                pivot.scrollWheel(with: scroll(0, 4))
                try capture("committed")
                // A vertical swipe is not taken.
                let before = selection.wrappedValue
                pivot.scrollWheel(with: scroll(0, 1, dy: -6))
                for _ in 0..<5 { pivot.scrollWheel(with: scroll(1, 2, dy: -20)) }
                pivot.scrollWheel(with: scroll(0, 4))
                precondition(selection.wrappedValue == before, "Vertical swipes do not switch items")
                window.close()
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
