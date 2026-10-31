import XCTest
@testable import FluentKit

final class ParallaxViewTests: XCTestCase {
    @MainActor
    private func makeParallax(vertical: FluentParallaxAxis) throws -> FluentParallaxControl {
        _ = NSApplication.shared
        let view = FluentParallaxView(vertical: vertical, background: { FluentText("Background") }) {
            FluentText("Content").frame(width: 300, height: 1_400)
        }
        let control = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentParallaxControl)
        control.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        control.layoutSubtreeIfNeeded()
        return control
    }

    func testSourceFormulaWithRelativeOffsetsAndOverpan() {
        let axis = FluentParallaxAxis(shift: 200)
        let range = FluentParallaxMath.range(axis: axis, contentSize: 1_400, viewportSize: 400)
        XCTAssertEqual(range.start, -40, "Relative start includes the 10% underpan")
        XCTAssertEqual(range.end, 1_040, "Scrollable extent plus the 10% overpan")
        XCTAssertEqual(FluentParallaxMath.translation(axis: axis, offset: -40, start: -40, end: 1_040), 0)
        XCTAssertEqual(FluentParallaxMath.translation(axis: axis, offset: 500, start: -40, end: 1_040), -100, accuracy: 0.001,
                       "Halfway through the range the background has moved half the shift")
        XCTAssertEqual(FluentParallaxMath.translation(axis: axis, offset: 5_000, start: -40, end: 1_040), -200, "Clamped at the shift")
        XCTAssertEqual(FluentParallaxMath.translation(axis: axis, offset: -500, start: -40, end: 1_040), 0, "Clamped before the start")
    }

    func testMaxRatioUnclampedAndAbsoluteOffsets() {
        let limited = FluentParallaxAxis(shift: 2_000, maxShiftRatio: 0.5)
        XCTAssertEqual(FluentParallaxMath.translation(axis: limited, offset: 100, start: 0, end: 1_000), -50,
                       "MaxShiftRatio caps the speed")
        let free = FluentParallaxAxis(shift: 100, isShiftClamped: false)
        XCTAssertEqual(FluentParallaxMath.translation(axis: free, offset: 2_000, start: 0, end: 1_000), -200,
                       "Unclamped shifts keep moving past the end")
        let absolute = FluentParallaxAxis(shift: 100, sourceOffsetKind: .absolute, sourceStartOffset: 200, sourceEndOffset: 600)
        let range = FluentParallaxMath.range(axis: absolute, contentSize: 1_400, viewportSize: 400)
        XCTAssertEqual(range.start, 200)
        XCTAssertEqual(range.end, 600)
        XCTAssertEqual(FluentParallaxMath.translation(axis: FluentParallaxAxis(), offset: 300, start: 0, end: 1_000), 0,
                       "No shift, no parallax")
    }

    @MainActor
    func testBackgroundIsArrangedLargerAndFollowsScrolling() throws {
        let control = try makeParallax(vertical: FluentParallaxAxis(shift: 200))
        XCTAssertEqual(control.backgroundHost.frame.size, NSSize(width: 300, height: 600), "Arranged taller by the shift")
        let document = try XCTUnwrap(control.scrollView.documentView).frame.height
        let range = (document - 400) + 80
        XCTAssertEqual(control.backgroundHost.frame.minY, -200 / range * 40, accuracy: 0.01,
                       "At rest the background already accounts for the underpan")
        control.scroll(to: NSPoint(x: 0, y: 500))
        XCTAssertEqual(control.backgroundHost.frame.minY, -200 / range * 540, accuracy: 0.01)
        XCTAssertGreaterThan(control.backgroundHost.frame.minY, -500, "The background moves slower than the content")
        control.scroll(to: NSPoint(x: 0, y: 1_000))
        XCTAssertGreaterThanOrEqual(control.backgroundHost.frame.minY, -200)
    }
}
