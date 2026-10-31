import XCTest
@testable import FluentKit

final class NavigationInterruptionTests: XCTestCase {
    @MainActor func testRapidNavigationKeepsVisibleOutgoingPageUntilReplacementEnters() throws {
        _ = NSApplication.shared
        func page(_ color: NSColor) -> FluentAnyView {
            let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = color.cgColor
            return FluentAnyView(FluentNativeView(view))
        }
        let context = FluentRenderContext(reduceMotion: false)
        let presenter = FluentNavigationContentPresenter(content: page(.red), identity: 0, context: context)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 300, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = presenter; window.makeKeyAndOrderFront(nil)
        presenter.layoutSubtreeIfNeeded(); CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        func redPixels() -> Int {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 160,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            (presenter.layer!.presentation() ?? presenter.layer!).render(in: cg)
            var count = 0
            for y in 0..<160 { for x in 0..<300 {
                let pixel = bitmap.bitmapData! + y * bitmap.bytesPerRow + x * 4
                if pixel[0] > 120 && pixel[1] < 80 && pixel[2] < 80 && pixel[3] > 120 { count += 1 }
            }}
            return count
        }
        presenter.update(content: page(.green), identity: 1, direction: .forward, mode: .slide, context: context)
        CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
        let before = redPixels()
        XCTAssertGreaterThan(before, 3000, "Fixture must interrupt while the original page is still visibly leaving")
        presenter.update(content: page(.blue), identity: 2, direction: .backward, mode: .slide, context: context)
        CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        XCTAssertGreaterThan(redPixels(), before / 2, "Removing the visible original while the intermediate page is transparent flashes an empty viewport")
        window.setContentSize(NSSize(width: 420, height: 180)); presenter.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(presenter.subviews.count, 1, "Resizing must settle the new page, not stretch a frozen outgoing image")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(presenter.subviews.count, 1)
        XCTAssertEqual(presenter.subviews.first?.layer?.opacity, 1)
    }
}
