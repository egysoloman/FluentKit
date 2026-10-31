import AppKit
import FluentKit

@main struct SwipeVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        var clock: TimeInterval = 10
        func scroll(_ dx: CGFloat, _ phase: Int64) -> NSEvent {
            clock += 0.01
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(dx), wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
            event.timestamp = CGEventTimestamp(clock * 1_000_000_000)
            return NSEvent(cgEvent: event)!
        }
        for variant in ["light", "dark", "rtl"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let rtl = variant == "rtl"
            let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            var invoked: [String] = []
            let host = FluentViewHost(FluentAnyView(FluentSwipeControl(
                leftItems: FluentSwipeItems(mode: .execute, [FluentSwipeItem("Archive", systemImage: "archivebox") { invoked.append("Archive") }]),
                rightItems: FluentSwipeItems([
                    FluentSwipeItem("Flag", systemImage: "flag") { invoked.append("Flag") },
                    FluentSwipeItem("Delete", systemImage: "trash", background: .systemRed, foreground: .white) { invoked.append("Delete") }
                ])
            ) {
                FluentText("Team meeting notes", style: .body).padding(12).frame(width: 360, height: 56).background(theme.cardFill, cornerRadius: 0)
            }.frame(width: 360, height: 56)), context: context)
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 360, height: 56), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let swipe = descendants(host).first { $0.identifier?.rawValue == "FluentKit.SwipeControl" }!
            let content = descendants(swipe).first { $0.identifier?.rawValue == "FluentKit.SwipeControl.Content" }!
            // Physical deltas toward the trailing/leading edges.
            let towardTrailingItems: CGFloat = rtl ? 1 : -1
            func capture(_ state: String) throws {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                let scale: CGFloat = 2
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                    pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: scale, y: scale)
                if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(state).png"))
                records.append(["variant": variant, "state": state, "contentMinX": content.frame.minX, "invoked": invoked,
                                "touchScreen": "pending device", "windowsComparison": "pending"])
            }
            // Reveal the trailing commands and leave them open.
            swipe.scrollWheel(with: scroll(towardTrailingItems * 5, 1))
            for _ in 0..<8 { swipe.scrollWheel(with: scroll(towardTrailingItems * 18, 2)) }
            clock += 0.2
            swipe.scrollWheel(with: scroll(0, 2))
            swipe.scrollWheel(with: scroll(0, 4))
            precondition(abs(content.frame.minX) > 100, "Past the threshold the commands stay open")
            try capture("reveal-open")
            // A content press closes it.
            let press = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 180, y: 28), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(press)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            precondition(content.frame.minX == 0, "Pressing the content closes the commands")
            // Execute: before and after the threshold, then release to invoke.
            swipe.scrollWheel(with: scroll(-towardTrailingItems * 5, 1))
            for _ in 0..<3 { swipe.scrollWheel(with: scroll(-towardTrailingItems * 15, 2)) }
            try capture("execute-before-threshold")
            for _ in 0..<6 { swipe.scrollWheel(with: scroll(-towardTrailingItems * 25, 2)) }
            try capture("execute-past-threshold")
            clock += 0.2
            swipe.scrollWheel(with: scroll(0, 2))
            swipe.scrollWheel(with: scroll(0, 4))
            precondition(invoked == ["Archive"], "Releasing past the threshold executes the item")
            precondition(content.frame.minX == 0, "Execute closes after invoking")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
