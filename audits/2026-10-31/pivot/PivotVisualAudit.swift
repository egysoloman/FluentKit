import AppKit
import FluentKit

@main struct PivotVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let headers = ["All", "Unread", "Flagged", "Urgent", "Archive"]
        for variant in ["light", "dark", "rtl"] {
            for (layout, width) in [("static", CGFloat(520)), ("carousel", CGFloat(300))] {
                let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
                let context = FluentRenderContext(theme: theme, reduceMotion: true,
                    layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight)
                let selection = FluentState(wrappedValue: 0)
                var isLocked = false
                func content() -> FluentAnyView {
                    FluentAnyView(FluentPivot(headers, selection: selection.projectedValue, title: "EMAIL", isLocked: isLocked,
                        header: { $0 }) { name in
                        FluentText("\(name) messages", style: .body)
                    }.frame(width: width, height: 200))
                }
                let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: width, height: 200),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
                let host = FluentViewHost(content(), context: context)
                host.wantsLayer = true
                host.layer?.backgroundColor = theme.windowBackground.cgColor
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                host.layoutSubtreeIfNeeded()
                let pivot = descendants(host).first { $0.identifier?.rawValue == "FluentKit.Pivot" }!
                func header(_ index: Int) -> NSView {
                    descendants(pivot).first { $0.identifier?.rawValue == "FluentKit.Pivot.Header.\(index)" }!
                }
                func button(_ name: String) -> NSView {
                    descendants(pivot).first { $0.identifier?.rawValue == "FluentKit.Pivot.\(name)" }!
                }
                func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
                    pivot.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
                }
                func pointer(_ entered: Bool, on view: NSView) {
                    let event = NSEvent.enterExitEvent(with: entered ? .mouseEntered : .mouseExited, location: .zero,
                        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, trackingNumber: 0, userData: nil)!
                    if entered { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
                }
                func capture(_ state: String) throws {
                    host.layoutSubtreeIfNeeded()
                    precondition(descendants(host).allSatisfy {
                        [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height].allSatisfy(\.isFinite)
                    })
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!
                        .write(to: output.appendingPathComponent("\(variant)-\(layout)-\(state).png"))
                    let visibleHeaders = (0..<headers.count).filter { header($0).layer?.opacity ?? 1 > 0 }
                    records.append(["variant": variant, "layout": layout, "state": state,
                        "selection": selection.wrappedValue, "visibleHeaders": visibleHeaders,
                        "selectedHeaderMinX": header(selection.wrappedValue).frame.minX,
                        "previousButtonVisible": !button("Previous").isHidden,
                        "nextButtonVisible": !button("Next").isHidden,
                        "voiceOver": "pending", "windowsComparison": "pending"])
                }

                try capture("initial")
                pointer(true, on: pivot)
                pointer(true, on: header(1))
                try capture("hover")
                if layout == "carousel" {
                    precondition(!button("Previous").isHidden && !button("Next").isHidden, "Carousel shows both buttons on hover")
                } else {
                    precondition(button("Previous").isHidden && button("Next").isHidden, "Fitting static headers hide buttons")
                }
                pointer(false, on: header(1))
                pointer(false, on: pivot)
                _ = header(2).accessibilityPerformPress()
                precondition(selection.wrappedValue == 2)
                try capture("selected")
                key(variant == "rtl" ? 123 : 124)
                precondition(selection.wrappedValue == 3, "Arrow toward the trailing edge advances")
                key(48, [.control, .shift])
                precondition(selection.wrappedValue == 2)
                key(119)
                precondition(selection.wrappedValue == 4)
                key(variant == "rtl" ? 123 : 124)
                precondition(selection.wrappedValue == (layout == "carousel" ? 0 : 4), "Only the carousel wraps")
                try capture("edge")
                isLocked = true
                host.update(content(), context: context)
                key(48, .control)
                precondition(selection.wrappedValue == (layout == "carousel" ? 0 : 4), "Locked ignores navigation")
                try capture("locked")
                isLocked = false
                host.update(content(), context: context)
                (pivot as? NSControl)?.isEnabled = false
                try capture("disabled")
                window.close()
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
