import AppKit
import FluentKit

@main struct SplitButtonInteractionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func capture(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); CATransaction.flush()
            let size = view.bounds.size
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: image)!.cgContext; cg.scaleBy(x: 2, y: 2)
            if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
            view.layer!.render(in: cg)
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func findLayer(_ name: String, in layer: CALayer) -> CALayer? {
            if layer.name == name { return layer }
            return layer.sublayers?.compactMap { findLayer(name, in: $0) }.first
        }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for toggle in [false, true] {
            var action = ""
            let items = [FluentMenuItem(id: "save", "Save old") { action = "old" }, FluentMenuItem(id: "export", "Export") {}]
            let button: FluentSplitButton = toggle ? FluentToggleSplitButton("Favorite", isChecked: true, items: items) : FluentSplitButton("Save", items: items)
            button.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            button.reduceMotion = true; button.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            let window = NSWindow(contentRect: NSRect(x: 100, y: 400, width: 400, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let stage = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 160)); stage.wantsLayer = true
            stage.layer?.backgroundColor = (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
            window.contentView = stage; stage.addSubview(button); button.frame = NSRect(x: 40, y: 80, width: 180, height: 32)
            window.makeKeyAndOrderFront(nil); button.layoutSubtreeIfNeeded()
            let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(toggle ? "toggle" : "regular")"
            var original: NSWindow?
            func record(_ phase: String) throws {
                let panel = window.childWindows?.first
                let rows = panel?.contentView.map { all($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } } ?? []
                let primary = button.convert(NSPoint(x: rtl ? 100 : 30, y: 16), to: stage)
                records.append(["variant": name, "phase": phase, "open": button.isFlyoutPresented,
                    "hit": stage.hitTest(primary) === button, "samePanel": panel != nil && panel === original,
                    "rows": rows.compactMap { $0.accessibilityTitle() }, "expanded": button.isAccessibilityExpanded(),
                    "panelX": panel?.frame.minX ?? -1, "panelY": panel?.frame.minY ?? -1,
                    "action": action,
                    "equalFills": findLayer("FluentKit.SplitButton.Primary", in: button.layer!)?.backgroundColor == findLayer("FluentKit.SplitButton.Secondary", in: button.layer!)?.backgroundColor,
                    "checked": (button as? FluentToggleSplitButton)?.isChecked ?? false])
                try capture(stage, name + "-" + phase + "-button")
                if let root = panel?.contentView { try capture(root, name + "-" + phase + "-popup") }
            }
            try record("idle")
            func mouse(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: button.convert(NSPoint(x: x, y: 16), to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            let primaryX: CGFloat = rtl ? 100 : 30
            button.mouseDown(with: mouse(.leftMouseDown, x: primaryX)); try record("mousePress")
            button.mouseUp(with: mouse(.leftMouseUp, x: -10))
            let touch = mouse(.leftMouseDown, x: primaryX).cgEvent!
            touch.setIntegerValueField(.mouseEventSubtype, value: Int64(NSEvent.EventSubtype.touch.rawValue))
            button.mouseDown(with: NSEvent(cgEvent: touch)!); try record("touchPress")
            button.mouseUp(with: mouse(.leftMouseUp, x: -10))
            button.showFlyout(); original = window.childWindows?.first; try record("open")
            button.showFlyout(); try record("repeat")
            if !button.isFlyoutPresented { button.showFlyout(); original = window.childWindows?.first }
            button.items = [FluentMenuItem(id: "save", "Publish revised action") { action = "new" }, FluentMenuItem(id: "export", "Export") {}]
            try record("update")
            button.setFrameOrigin(NSPoint(x: 70, y: 100)); button.layoutSubtreeIfNeeded(); try record("move")
            if let panel = window.childWindows?.first, let row = panel.contentView.flatMap({ all($0).first { $0.identifier?.rawValue == "FluentKit.Menu.Item" } }) {
                _ = row.accessibilityPerformPress()
            }
            try record("invoke")
            button.showFlyout(); button.isHidden = true; try record("hide")
            window.close()
        }}}
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
