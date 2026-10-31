import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

@main struct SettingsChromeAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let userData = FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-SearchAudit-" + UUID().uuidString)
        let engine = try RimeEngine(sharedDirectory: URL(fileURLWithPath: CommandLine.arguments[2]), userDirectory: userData)
        defer { FIMFinalize() }
        let controller = try SettingsWindowController(engine: engine)
        controller.showWindow(nil)
        let window = controller.window!, root = window.contentView!
        if ProcessInfo.processInfo.environment["CHROME_AUDIT_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            window.title = "Fluent Settings Chrome Audit"
            window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run(); return
        }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let search = all(root).compactMap { $0 as? FluentSearchTextField }.first!
        let cell = search.cell as! NSSearchFieldCell
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var records: [[String: Any]] = []
        func capture(_ state: String) throws {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
            var row: [String: Any] = ["state": state, "window": rect(root.bounds),
                "fieldFrame": rect(search.convert(search.bounds, to: root)),
                "textRect": rect(cell.searchTextRect(forBounds: search.bounds)),
                "sameSearchInstance": all(root).contains { $0 === search }, "text": search.stringValue]
            row["visibleRect"] = rect(search.visibleRect)
            row["bounds"] = rect(search.bounds)
            row["nativeBezel"] = search.isBezeled
            row["nativeBackground"] = search.drawsBackground
            let insets = search.alignmentRectInsets
            row["alignmentInsets"] = [insets.top, insets.left, insets.bottom, insets.right]
            row["radius"] = search.theme.buttonCornerRadius
            var ancestor: NSView? = search
            var ancestors: [[String: Any]] = []
            while let view = ancestor {
                ancestors.append(["type": String(describing: type(of: view)),
                    "frame": rect(view.frame), "bounds": rect(view.bounds),
                    "visibleRect": rect(view.visibleRect), "clips": view.clipsToBounds,
                    "layerMasks": view.layer?.masksToBounds ?? false])
                ancestor = view.superview
            }
            row["ancestors"] = ancestors
            if let editor = search.currentEditor() as? NSTextView {
                row["editorFrame"] = rect(editor.convert(editor.bounds, to: search))
                row["padding"] = editor.textContainer?.lineFragmentPadding ?? -1
                row["marked"] = editor.hasMarkedText()
                row["caretFrame"] = rect(search.convert(window.convertFromScreen(editor.firstRect(
                    forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)), from: nil))
            }
            records.append(row)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width * 2), pixelsHigh: Int(root.bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            if root.isFlipped { cg.translateBy(x: 0, y: root.bounds.height); cg.scaleBy(x: 1, y: -1) }
            (root.layer!.presentation() ?? root.layer!).render(in: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(state + ".png"))
        }
        window.makeFirstResponder(nil); try capture("unfocused")
        search.selectText(nil); try capture("focused")
        let editor = search.currentEditor() as! NSTextView
        editor.insertText("拼音", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try capture("input-and-page-update")
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try capture("marked")
        window.setContentSize(NSSize(width: 600, height: 800)); try capture("marked-narrow")
        window.setContentSize(NSSize(width: 1000, height: 800)); try capture("marked-wide")
        editor.unmarkText(); window.makeFirstResponder(nil); try capture("unfocused-text")
        window.close()
        try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys, .prettyPrinted])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
