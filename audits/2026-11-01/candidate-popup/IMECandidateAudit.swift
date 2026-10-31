import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

/// Isolates the application's custom panel. This is not an IMK cross-process transport test.
@main struct IMECandidateAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let userData = FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-CandidateAudit-" + UUID().uuidString)
        let engine = try RimeEngine(sharedDirectory: URL(fileURLWithPath: CommandLine.arguments[2]), userDirectory: userData)
        defer { FIMFinalize() }
        let controller = try SettingsWindowController(engine: engine)
        controller.showWindow(nil)
        let window = controller.window!, root = window.contentView!
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let search = all(root).compactMap { $0 as? FluentSearchTextField }.first!
        search.selectText(nil)
        let editor = search.currentEditor() as! NSTextView
        editor.setMarkedText("hua", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: 0))
        var composition = Composition()
        composition.rawInput = "hua"; composition.preedit = "hua"; composition.cursorUTF16 = 3
        composition.candidates = ["花", "话", "画", "华", "化", "划", "滑"].map { Candidate($0) }
        let panel = CandidatePanel()
        func settle() {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
            root.layoutSubtreeIfNeeded(); panel.contentView?.layoutSubtreeIfNeeded()
            panel.contentView?.displayIfNeeded(); CATransaction.flush()
        }
        func caret() -> NSRect { editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil) }
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var records: [[String: Any]] = []
        func record(_ name: String) throws {
            settle()
            let fieldRect = window.convertToScreen(search.convert(search.bounds, to: nil))
            let line = caret()
            records.append(["state": name, "field": rect(fieldRect), "caret": rect(line), "panel": rect(panel.frame),
                "lineGap": line.minY - panel.frame.maxY, "fieldGap": fieldRect.minY - panel.frame.maxY,
                "xError": panel.frame.minX - line.minX, "isVisible": panel.isVisible,
                "canBecomeKey": panel.canBecomeKey, "editorFocused": window.firstResponder === editor,
                "marked": editor.hasMarkedText(), "visibleShadows": panel.childWindows?.filter(\.isVisible).count ?? 0])
            if panel.isVisible {
                let view = panel.contentView!, size = view.bounds.size
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: 2, y: 2)
                if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                view.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            }
        }
        settle(); panel.present(composition, caret: caret()); try record("present")
        window.setContentSize(NSSize(width: 1000, height: 800)); try record("resize-before-publish")
        panel.present(composition, caret: caret()); try record("resize-after-publish")
        panel.orderOut(nil); try record("dismiss")
        panel.present(composition, caret: caret()); try record("reopen")
        panel.present(Composition(), caret: caret()); try record("empty")
        window.close()
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
