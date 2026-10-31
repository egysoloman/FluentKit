import AppKit
import FluentKit

@main struct AutoSuggestAnchorAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func rect(_ value: NSRect) -> [CGFloat] { [value.minX, value.minY, value.width, value.height] }
        func image(_ view: NSView, _ name: String) throws {
            let size = view.bounds.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
            view.layer!.render(in: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] {
            let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")"
            let state = FluentState(wrappedValue: "")
            let context = FluentRenderContext(theme: .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false),
                                             reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in
                (0..<20).map { FluentAutoSuggestBoxSuggestion(id: $0, title: "Apple \($0)", subtitle: "Fruit") }
            }, maxSuggestionListHeight: 84)._makeView(in: context)
            let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 460, height: 360),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 400, height: 300))
            scroll.autoresizingMask = [.width, .height]
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
            document.wantsLayer = true
            document.addSubview(view); scroll.documentView = document
            view.frame = NSRect(x: 20, y: 150, width: 300, height: view.intrinsicContentSize.height)
            window.contentView!.wantsLayer = true
            window.contentView!.addSubview(scroll); window.makeKeyAndOrderFront(nil)
            scroll.contentView.scroll(to: .zero)
            view.layoutSubtreeIfNeeded()
            let field = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as! NSTextField
            func type(_ text: String) {
                field.selectText(nil)
                let editor = field.currentEditor() as! NSTextView
                editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            }
            func record(_ phase: String, capture: Bool = false) throws {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.015))
                window.contentView!.layoutSubtreeIfNeeded()
                let panel = window.childWindows?.first
                panel?.contentView?.layoutSubtreeIfNeeded()
                panel?.contentView?.displayIfNeeded(); CATransaction.flush()
                let anchor = window.convertToScreen(field.convert(field.bounds, to: nil))
                let visible = !view.bounds.intersection(view.visibleRect).isEmpty
                var row: [String: Any] = ["variant": name, "phase": phase, "anchor": rect(anchor),
                    "anchorVisible": visible, "popupOpen": panel?.isVisible == true, "text": state.wrappedValue,
                    "editorFocused": window.firstResponder === field.currentEditor()]
                if let panel {
                    row["popup"] = rect(panel.frame)
                    row["belowGap"] = anchor.minY - panel.frame.maxY
                    row["aboveGap"] = panel.frame.minY - anchor.maxY
                    row["horizontalError"] = rtl ? panel.frame.maxX - anchor.maxX : panel.frame.minX - anchor.minX
                }
                records.append(row)
                if capture {
                    try image(window.contentView!, name + "-" + phase)
                    if let root = panel?.contentView { try image(root, name + "-" + phase + "-popup") }
                }
            }
            type("Ap"); try record("open", capture: true)
            for step in 1...20 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(step % 10) * 7))
                scroll.reflectScrolledClipView(scroll.contentView)
                try record("scroll-\(step)", capture: step == 5)
            }
            scroll.setFrameOrigin(NSPoint(x: 35, y: 27)); try record("ancestor-move", capture: true)
            window.setContentSize(NSSize(width: 430, height: 330)); try record("resize", capture: true)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 500)); try record("clipped")
            scroll.contentView.scroll(to: .zero); try record("return")
            type("App"); try record("reopen", capture: true)
            (field.currentEditor() as! NSTextView).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            try record("escape")
            window.close()
        }}
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
