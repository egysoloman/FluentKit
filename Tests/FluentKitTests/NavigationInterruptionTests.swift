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
        func coloredPixels(in layer: CALayer, includingGreen: Bool = false, includingBlue: Bool = false) -> Int {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 160,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            layer.render(in: cg)
            var count = 0
            for y in 0..<160 { for x in 0..<300 {
                let pixel = bitmap.bitmapData! + y * bitmap.bytesPerRow + x * 4
                let red = pixel[0] > 120 && pixel[1] < 80 && pixel[2] < 80
                let green = includingGreen && pixel[1] > 120 && pixel[0] < 80 && pixel[2] < 80
                let blue = includingBlue && pixel[2] > 120 && pixel[0] < 80 && pixel[1] < 80
                if (red || green || blue) && pixel[3] > 120 { count += 1 }
            }}
            return count
        }
        presenter.update(content: page(.green), identity: 1, direction: .forward, mode: .slide, context: context)
        CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
        let before = coloredPixels(in: presenter.layer!.presentation() ?? presenter.layer!)
        XCTAssertGreaterThan(before, 3000, "Fixture must interrupt while the original page is still visibly leaving")
        presenter.update(content: page(.blue), identity: 2, direction: .backward, mode: .slide, context: context)
        // Inspect the retained composite itself. A delayed compositor sample may already be
        // green or blue; red disappearing alone does not establish an empty viewport.
        let snapshot = try XCTUnwrap(presenter.subviews.compactMap { entry in
            entry.layer?.sublayers?.first { $0.name == "FluentKit.NavigationView.InterruptedSnapshot" }
        }.first)
        XCTAssertNotNil(snapshot.contents)
        XCTAssertEqual(snapshot.frame, presenter.bounds)
        XCTAssertGreaterThan(coloredPixels(in: snapshot, includingGreen: true), before / 2,
            "The retained composite must contain the visible outgoing scene, not an empty image")
        let opacity = try XCTUnwrap(snapshot.superlayer?.animation(forKey: "fluent.navigation.page.opacity") as? CABasicAnimation)
        XCTAssertEqual((opacity.fromValue as? NSNumber)?.doubleValue, 1,
            "A new snapshot must start visible while the replacement page is transparent")
        CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        XCTAssertGreaterThan(coloredPixels(in: presenter.layer!.presentation() ?? presenter.layer!,
            includingGreen: true, includingBlue: true), before / 2,
            "The presented viewport must stay populated as its page colors change")
        window.setContentSize(NSSize(width: 420, height: 180)); presenter.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(presenter.subviews.count, 1, "Resizing must settle the new page, not stretch a frozen outgoing image")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(presenter.subviews.count, 1)
        XCTAssertEqual(presenter.subviews.first?.layer?.opacity, 1)
    }
}
