import AppKit
import FluentKit

@main struct TreeViewGalleryAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        var results: [[String: Any]] = []
        for variant in ["light", "dark", "rtl"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true,
                layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight, locale: Locale(identifier: "en_US"))
            let host = FluentViewHost(TreeViewGallerySample(), context: context)
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let outline = descendants(host).compactMap { $0 as? NSOutlineView }.first!
            func pump() {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                host.layoutSubtreeIfNeeded()
            }
            func row(_ title: String) -> Int {
                for index in 0..<outline.numberOfRows {
                    if let view = outline.view(atColumn: 0, row: index, makeIfNecessary: true),
                       descendants(view).compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue == title }) { return index }
                }
                preconditionFailure("Missing tree row: \(title)")
            }
            func key(_ code: UInt16) {
                window.makeFirstResponder(outline)
                outline.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: code)!)
                pump()
            }
            func click(_ title: String) {
                descendants(host).compactMap { $0 as? FluentButton }.first { $0.title == title }!.performClick(nil)
                pump()
            }
            func capture(_ state: String, expectedRows: Int, checked: Int? = nil) throws {
                pump()
                precondition(outline.numberOfRows == expectedRows)
                precondition(descendants(host).allSatisfy { $0.frame.width >= 0 && $0.frame.height >= 0 })
                if let checked {
                    precondition(descendants(host).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Checked: \(checked)" })
                }
                host.displayIfNeeded()
                CATransaction.flush()
                let size = host.bounds.size
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: 2, y: 2)
                if host.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(state).png"))
                let buttonFrames = descendants(host).compactMap { $0 as? FluentButton }.map { button -> [String: Any] in
                    let rect = host.convert(button.bounds, from: button)
                    precondition(host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect), "Button outside host: \(button.title) \(rect)")
                    if let parent = button.superview {
                        precondition(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(button.frame), "Button outside stack: \(button.title)")
                    }
                    var chain: [String] = []
                    var parent = button.superview
                    while let view = parent { chain.append("\(type(of: view)): f=\(view.frame) b=\(view.bounds)"); parent = view.superview }
                    return ["ancestors": chain, "title": button.title, "frame": NSStringFromRect(rect), "hidden": button.isHidden,
                        "layerFrame": button.layer.map { NSStringFromRect($0.frame) } ?? "none"]
                }
                results.append(["buttons": buttonFrames, "variant": variant, "state": state, "rows": outline.numberOfRows,
                    "rowHeight": outline.rowHeight, "selectedRow": outline.selectedRow,
                    "renderMethod": "CALayer.render", "windowsComparison": "pending", "voiceOver": "pending"])
            }
            try capture("mixed", expectedRows: 5, checked: 1)
            outline.selectRowIndexes(IndexSet(integer: row("Work")), byExtendingSelection: false)
            key(49)
            try capture("checked", expectedRows: 5, checked: 4)
            outline.selectRowIndexes(IndexSet(integer: row("Remote")), byExtendingSelection: false)
            key(variant == "rtl" ? 123 : 124)
            try capture("lazy-loaded", expectedRows: 7, checked: 4)
            precondition(row("Shared document") >= 0)
            click("Collapse all")
            try capture("collapsed", expectedRows: 3, checked: 4)
            click("Reset tree")
            let toggle = descendants(host).compactMap { $0 as? FluentToggle }.first!
            precondition(toggle.accessibilityPerformPress())
            pump()
            outline.selectRowIndexes(IndexSet(integer: row("Notes")), byExtendingSelection: false)
            key(36)
            precondition(descendants(host).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Invoked notes" })
            try capture("single", expectedRows: 5)
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
