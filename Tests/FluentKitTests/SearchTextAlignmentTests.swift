import XCTest
@testable import FluentKit

final class SearchTextAlignmentTests: XCTestCase {
    // Inactive native cell contents may be absent from CALayer.render(in:) despite being
    // visible on screen. Draw that cell directly; the active editor is present in its layer.
    @MainActor private func glyphBounds(field: FluentSearchTextField, editor: NSTextView?) throws -> CGRect {
        let scale: CGFloat = 2
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 620, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let cell = try XCTUnwrap(field.cell as? NSSearchFieldCell)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.scaleBy(x: scale, y: scale)
        context.cgContext.translateBy(x: 0, y: 32)
        context.cgContext.scaleBy(x: 1, y: -1)
        if editor != nil {
            field.layer?.render(in: context.cgContext)
        } else {
            cell.draw(withFrame: field.bounds, in: field)
        }
        NSGraphicsContext.restoreGraphicsState()
        let area = cell.searchTextRect(forBounds: field.bounds)
        var points: [CGPoint] = []
        for y in Int(area.minY * scale)..<Int(area.maxY * scale) {
            for x in Int(area.minX * scale)..<Int(area.maxX * scale) {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let ink = field.theme.isDark
                    ? min(color.redComponent, color.greenComponent, color.blueComponent) > 0.6
                    : max(color.redComponent, color.greenComponent, color.blueComponent) < 0.4
                if color.alphaComponent > 0.5 && ink {
                    points.append(CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale))
                }
            }
        }
        XCTAssertFalse(points.isEmpty, "The renderer must contain visible glyphs")
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    @MainActor func testSearchGlyphsDoNotMoveWhenFocusChangesOrEditorIsReused() throws {
        _ = NSApplication.shared
        var fontNames: [String?] = [nil, "PingFangSC-Regular"]
        if NSFont(name: "MicrosoftYaHei", size: 14) != nil { fontNames.append("MicrosoftYaHei") }
        for fontName in fontNames {
        for dark in [false, true] { for rtl in [false, true] { for text in ["Search settings", "查找设置"] { for placeholder in [false, true] {
            let field = FluentSearchTextField(placeholder: text)
            field.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            if let fontName {
                field.theme = field.theme.with(typography: FluentTypography(fontProvider: FluentFontProvider { _, size, weight in
                    NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size, weight: weight)
                }))
            }
            field.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            field.frame = CGRect(x: 20, y: 20, width: 310, height: 32)
            field.stringValue = placeholder ? "" : text
            let other = FluentTextField(placeholder: "Other field")
            other.frame = CGRect(x: 20, y: 70, width: 310, height: 32)
            let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 350, height: 130),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView!.wantsLayer = true
            window.contentView!.addSubview(field)
            window.contentView!.addSubview(other)
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            window.makeFirstResponder(nil)
            let inactive = try glyphBounds(field: field, editor: nil)
            for _ in 0..<2 {
                other.selectText(nil)
                field.selectText(nil)
                let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
                editor.insertionPointColor = .clear
                window.contentView!.layoutSubtreeIfNeeded()
                window.contentView!.display()
                CATransaction.flush()
                let active = try glyphBounds(field: field, editor: editor)
                XCTAssertEqual(active.minX, inactive.minX, accuracy: 0.5, "\(dark), \(rtl), \(text)")
                XCTAssertEqual(active.minY, inactive.minY, accuracy: 0.5)
                XCTAssertEqual(active.maxX, inactive.maxX, accuracy: 0.5)
                XCTAssertEqual(active.maxY, inactive.maxY, accuracy: 0.5)
            }
        }}}}}
    }
}
