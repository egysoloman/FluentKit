import XCTest
@testable import FluentKit

final class TextInputChromeTests: XCTestCase {
    @MainActor private func fields(theme: FluentTheme) -> [NSTextField] {
        let text = FluentTextField(placeholder: "查找设置"); text.theme = theme
        let search = FluentSearchTextField(placeholder: "查找设置"); search.theme = theme
        let secure = FluentSecureTextField(placeholder: "查找设置"); secure.theme = theme
        return [text, search, secure]
    }

    @MainActor func testExplicitFrameDoesNotCropCustomInputCorners() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .dark, materialEffectsEnabled: false)
        for width: CGFloat in [220, 480] { for field in fields(theme: theme) {
            let host = FluentViewHost(FluentNativeView(field).frame(width: width, height: 32).background(.clear), context: .init(theme: theme))
            host.frame = NSRect(x: 20, y: 20, width: width, height: 32); host.wantsLayer = true
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width + 40, height: 72),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView!.addSubview(host); window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            field.selectText(nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
            window.contentView!.layoutSubtreeIfNeeded(); window.contentView!.display(); CATransaction.flush()
            let frame = field.convert(field.bounds, to: host)
            XCTAssertEqual(frame.minX, 0, accuracy: 0.01, "\(type(of: field))")
            XCTAssertEqual(frame.width, width, accuracy: 0.01, "\(type(of: field))")
            XCTAssertEqual(frame.height, 32, accuracy: 0.01)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let cg = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
            cg.scaleBy(x: 2, y: 2); host.layer!.render(in: cg)
            for x in [0, Int(width * 2) - 1] { for y in [0, 63] {
                XCTAssertLessThan(bitmap.colorAt(x: x, y: y)!.alphaComponent, 0.02, "Clipped corner of \(type(of: field))")
            }}
        }}
    }

    @MainActor private func placeholderInkAlpha(_ field: NSTextField) throws -> CGFloat {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 440, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let cg = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        cg.scaleBy(x: 2, y: 2); cg.translateBy(x: 0, y: 32); cg.scaleBy(x: 1, y: -1)
        field.cell!.draw(withFrame: field.bounds, in: field)
        NSGraphicsContext.restoreGraphicsState()
        var maximum: CGFloat = 0
        for y in 10..<52 { for x in 64..<145 {
            maximum = max(maximum, bitmap.colorAt(x: x, y: y)!.alphaComponent)
        }}
        return maximum
    }

    @MainActor func testDisablingAndReenablingImmediatelyUpdatesPlaceholderInk() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            for field in fields(theme: theme) {
                field.frame = NSRect(x: 0, y: 0, width: 220, height: 32)
                let enabled = try placeholderInkAlpha(field)
                XCTAssertGreaterThan(enabled, 0.5)
                field.isEnabled = false
                XCTAssertLessThan(try placeholderInkAlpha(field), enabled * 0.7, "\(type(of: field))")
                field.isEnabled = true
                XCTAssertEqual(try placeholderInkAlpha(field), enabled, accuracy: 1 / 255)
            }
        }
    }
}
