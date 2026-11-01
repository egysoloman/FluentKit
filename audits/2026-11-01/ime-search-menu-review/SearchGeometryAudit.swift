import AppKit
import FluentKit

private final class SearchAuditRoot: NSView { override var isFlipped: Bool { true } }

@main struct SearchGeometryAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func rect(_ value: NSRect) -> [CGFloat] { [value.minX, value.minY, value.width, value.height] }
        var records: [[String: Any]] = []
        for imeFont in [false, true] { for dark in [false, true] { for rtl in [false, true] { for text in ["Search settings", "查找设置"] {
            let field = FluentSearchTextField(placeholder: text)
            field.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            if imeFont {
                field.theme = field.theme.with(typography: FluentTypography(fontProvider: FluentFontProvider { _, size, weight in
                    NSFont(name: "MicrosoftYaHei", size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
                }))
            }
            field.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            field.frame = NSRect(x: 20, y: 20, width: 310, height: 32)
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 350, height: 72),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = SearchAuditRoot(frame: NSRect(x: 0, y: 0, width: 350, height: 72))
            root.wantsLayer = true
            root.addSubview(field)
            window.contentView = root
            window.makeKeyAndOrderFront(nil)
            let cell = field.cell as! NSSearchFieldCell
            let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(text == "查找设置" ? "zh" : "en")-\(imeFont ? "ime" : "default")"
            func capture(_ state: String) throws {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
                // Hide the blinking caret only for stable glyph-ink measurement.
                (field.currentEditor() as? NSTextView)?.insertionPointColor = .clear
                root.layoutSubtreeIfNeeded(); field.needsDisplay = true; root.display(); CATransaction.flush()
                var row: [String: Any] = ["variant": name, "state": state,
                    "textRect": rect(cell.searchTextRect(forBounds: field.bounds)),
                    "searchButton": rect(cell.searchButtonRect(forBounds: field.bounds)),
                    "cancelButton": rect(cell.cancelButtonRect(forBounds: field.bounds)),
                    "font": field.font!.fontName, "pointSize": field.font!.pointSize,
                    "ascender": field.font!.ascender, "descender": field.font!.descender, "leading": field.font!.leading,
                    "cellType": String(describing: type(of: cell)),
                    "renderMode": field.currentEditor() == nil ? "native cell directly (no chrome)" : "layer tree"]
                if let editor = field.currentEditor() as? NSTextView {
                    row["editorFrame"] = rect(editor.convert(editor.bounds, to: field))
                    row["editorClipFrame"] = editor.superview.map { rect($0.convert($0.bounds, to: field)) } ?? []
                    row["padding"] = editor.textContainer?.lineFragmentPadding ?? -1
                    row["textOrigin"] = [editor.textContainerOrigin.x, editor.textContainerOrigin.y]
                    if let layout = editor.layoutManager, let container = editor.textContainer {
                        layout.ensureLayout(for: container)
                        var glyphs = layout.boundingRect(forGlyphRange: layout.glyphRange(for: container), in: container)
                        glyphs.origin.x += editor.textContainerOrigin.x
                        glyphs.origin.y += editor.textContainerOrigin.y
                        row["glyphFrame"] = rect(editor.convert(glyphs, to: field))
                    }
                    row["caretFrame"] = rect(field.convert(window.convertFromScreen(editor.firstRect(
                        forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)), from: nil))
                    row["marked"] = editor.hasMarkedText()
                }
                row["searchImage"] = cell.searchButtonCell?.image?.name() ?? "nil"
                row["cellString"] = cell.stringValue
                row["placeholder"] = cell.placeholderAttributedString?.string ?? cell.placeholderString ?? "nil"
                records.append(row)
                for scale: CGFloat in [1, 2] {
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(310 * scale), pixelsHigh: Int(32 * scale),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                    cg.scaleBy(x: scale, y: scale)
                    if field.currentEditor() == nil {
                        // Native inactive contents are not reliably captured by layer.render.
                        // Draw them directly on a fresh context, as in the pixel regression.
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                        cg.translateBy(x: 0, y: 32); cg.scaleBy(x: 1, y: -1)
                        cell.draw(withFrame: field.bounds, in: field)
                        NSGraphicsContext.restoreGraphicsState()
                    } else {
                        cg.translateBy(x: -20, y: -20)
                        cg.translateBy(x: 0, y: root.bounds.height); cg.scaleBy(x: 1, y: -1)
                        (root.layer!.presentation() ?? root.layer!).render(in: cg)
                    }
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(state)-\(Int(scale))x.png"))

                }
            }
            window.makeFirstResponder(nil); field.stringValue = ""
            try capture("placeholder")
            field.selectText(nil)
            try capture("focused-placeholder")
            let editor = field.currentEditor() as! NSTextView
            editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            try capture("editing")
            editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                 replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            try capture("marked")
            editor.unmarkText()
            window.makeFirstResponder(nil); field.stringValue = text
            try capture("unfocused-text")
            window.close()
        }}}}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self))
    }
}
