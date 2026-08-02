import XCTest
@testable import FluentKit

final class FluentKitTests: XCTestCase {
    func testPublishedMotionDurations() {
        XCTAssertEqual(FluentMotion.controlFaster.duration, 0.083, accuracy: 0.000_001)
        XCTAssertEqual(FluentMotion.controlFast.duration, 0.167, accuracy: 0.000_001)
        XCTAssertEqual(FluentMotion.controlNormal.duration, 0.250, accuracy: 0.000_001)
    }

    func testCubicBezierClampsHorizontalControlPoints() {
        let curve = FluentCubicBezier(-0.5, -0.25, 1.5, 1.25)

        XCTAssertEqual(curve.x1, 0)
        XCTAssertEqual(curve.y1, -0.25)
        XCTAssertEqual(curve.x2, 1)
        XCTAssertEqual(curve.y2, 1.25)
    }

    func testMappedBindingReadsWritesAndObserves() {
        let state = FluentState(wrappedValue: 2)
        let mapped = state.projectedValue.map(String.init) { Int($0) ?? 0 }
        var observedValues: [String] = []
        let observerID = mapped.observe { observedValues.append($0) }

        XCTAssertEqual(mapped.wrappedValue, "2")
        mapped.wrappedValue = "7"
        XCTAssertEqual(state.wrappedValue, 7)
        XCTAssertEqual(observedValues, ["7"])

        if let observerID {
            mapped.removeObserver(observerID)
        }
        state.wrappedValue = 9
        XCTAssertEqual(observedValues, ["7"])
    }

    func testControlSizeMetricsRemainOrdered() {
        XCTAssertLessThan(FluentControlSize.small.height, FluentControlSize.regular.height)
        XCTAssertLessThan(FluentControlSize.regular.height, FluentControlSize.large.height)
        XCTAssertLessThan(FluentControlSize.small.metricScale, FluentControlSize.regular.metricScale)
        XCTAssertLessThan(FluentControlSize.regular.metricScale, FluentControlSize.large.metricScale)
    }
}
