import AppKit
import FluentKit

@main struct AutoSuggestInteractionAudit {
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
            let cg = NSGraphicsContext(bitmapImageRep: image)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
            view.layer!.render(in: cg)
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] {
            let state = FluentState(wrappedValue: "")
            let allValues = (0..<20).map { FluentAutoSuggestBoxSuggestion(id: $0, title: "Apple \($0)", subtitle: "Fruit", systemImageName: "leaf") }
            var values = allValues
            var height: CGFloat = 84
            let context = FluentRenderContext(theme: .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false),
                reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            func content() -> FluentAutoSuggestBox {
                FluentAutoSuggestBox(state.projectedValue, header: "Search fruit", querySystemImageName: "magnifyingglass",
                    suggestions: { query in query.isEmpty ? [] : values }, maxSuggestionListHeight: height)
            }
            let view = content()._makeView(in: context)
            view.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            let window = NSWindow(contentRect: NSRect(x: 100, y: 400, width: 460, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let stage = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 160)); stage.wantsLayer = true
            stage.layer?.backgroundColor = (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
            window.contentView = stage; stage.addSubview(view)
            view.frame = NSRect(x: 20, y: 40, width: 300, height: view.intrinsicContentSize.height)
            window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
            let field = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as! NSTextField
            field.selectText(nil)
            let editor = field.currentEditor() as! NSTextView
            editor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.22))
            let original = window.childWindows?.first
            let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")"
            func record(_ phase: String) throws {
                view.layoutSubtreeIfNeeded()
                let panel = window.childWindows?.first
                let root = panel?.contentView
                root?.layoutSubtreeIfNeeded(); root?.displayIfNeeded(); CATransaction.flush()
                let rows = root.map { all($0).filter { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Suggestion" } } ?? []
                let selected = rows.first { $0.isAccessibilitySelected() }
                let header = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Header" }!
                let query = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.QueryButton" }!
                let anchor = window.convertToScreen(field.convert(field.bounds, to: nil))
                func mask(_ layer: CALayer) -> CALayer? {
                    if let m = layer.mask, m.name?.hasSuffix("RevealClip") == true { return m }
                    return layer.sublayers?.compactMap(mask).first
                }
                let editing = field.currentEditor() as? NSTextView
                let glyphRect: NSRect
                if let editing, let manager = editing.layoutManager, let container = editing.textContainer {
                    manager.ensureLayout(for: container)
                    let range = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: editing.string.utf16.count), actualCharacterRange: nil)
                    var rect = manager.boundingRect(forGlyphRange: range, in: container)
                    rect.origin.x += editing.textContainerOrigin.x; rect.origin.y += editing.textContainerOrigin.y
                    glyphRect = rect
                } else { glyphRect = .zero }
                records.append(["variant": name, "phase": phase, "rows": rows.count,
                    "fieldBounds": NSStringFromRect(field.bounds), "cellText": NSStringFromRect(field.cell!.drawingRect(forBounds: field.bounds)),
                    "editorFrame": NSStringFromRect(editor.frame), "editorVisible": NSStringFromRect(editor.visibleRect),
                    "editorViewport": NSStringFromRect(editor.convert(editor.visibleRect, to: field)),
                    "editorClip": NSStringFromRect(editor.superview?.frame ?? .zero), "editorGlyph": NSStringFromRect(glyphRect),
                    "alignment": editor.alignment.rawValue,
                    "glyphVisible": editor.visibleRect.insetBy(dx: -0.5, dy: -0.5).contains(glyphRect),
                    "editorFocused": field.currentEditor() === editor && window.firstResponder === editor, "textContainerSize": NSStringFromSize(editor.textContainer!.size),
                    "clipBounds": NSStringFromRect(editor.superview?.bounds ?? .zero), "samePanel": panel === original,
                    "selected": selected?.accessibilityLabel() ?? "", "selectedVisibleHeight": selected?.visibleRect.height ?? 0,
                    "headerVisible": view.bounds.contains(header.frame), "queryX": query.frame.minX,
                    "height": panel?.frame.height ?? 0, "anchorGap": panel.map { anchor.minY - $0.frame.maxY } ?? -1,
                    "clipCovers": root.map { mask($0.layer!)?.frame.contains($0.bounds) == true } ?? false,
                    "open": panel?.isVisible == true, "text": state.wrappedValue,
                    "hasScroll": root.map { all($0).contains { $0 is NSScrollView } } ?? false])
                try capture(stage, "\(name)-\(phase)-field")
                if let root { try capture(root, "\(name)-\(phase)-popup") }
            }
            try record("open")
            for _ in 0..<20 { editor.doCommand(by: #selector(NSResponder.moveDown(_:))) }
            try record("last")
            values = allValues.reversed(); height = 164
            _ = content()._updateView(view, in: context)
            try record("resize")
            state.wrappedValue = ""
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            try record("reset")
            window.close()
        }}
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
