import XCTest
@testable import FluentKit

final class FlipViewRegressionTests: XCTestCase {
    @MainActor
    func testRebindingDetachesOldSourceAndDiscardsQueuedNotifications() throws {
        _ = NSApplication.shared
        let first = FluentState(wrappedValue: 0)
        let second = FluentState(wrappedValue: 2)
        let context = FluentRenderContext(reduceMotion: true)
        var changes: [Int] = []
        let native = FluentFlipView(["A", "B", "C"], selection: first.projectedValue,
            onSelectionChanged: { changes.append($0) }) { FluentText($0) }._makeView(in: context)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        first.wrappedValue = 1 // Queued on the old source when the control is rebound.
        XCTAssertTrue(FluentFlipView(["A", "B", "C"], selection: second.projectedValue,
            onSelectionChanged: { changes.append($0) }) { FluentText($0) }._updateView(native, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(changes, [2], "A notification from a detached binding must not change the selection")
        first.wrappedValue = 0
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.accessibilityValue() as? String, "3 of 3")
        second.wrappedValue = 1
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.accessibilityValue() as? String, "2 of 3")
        XCTAssertTrue(FluentFlipView(["A", "B", "C"]) { FluentText($0) }._updateView(native, in: context))
        second.wrappedValue = 2
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.accessibilityValue() as? String, "2 of 3", "Removing a binding detaches its observer too")
    }

    @MainActor
    func testItemRemovalEmptyAndRefillKeepSelectionModelInSync() throws {
        _ = NSApplication.shared
        let selection = FluentState(wrappedValue: 4)
        let context = FluentRenderContext(reduceMotion: true)
        var changes: [Int] = []
        func control(_ items: [String]) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(items, selection: selection.projectedValue,
                onSelectionChanged: { changes.append($0) }) { FluentText($0) }
        }
        let native = control(["A", "B", "C", "D", "E"])._makeView(in: context)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertTrue(control(["A", "B"])._updateView(native, in: context))
        XCTAssertEqual(selection.wrappedValue, 1)
        XCTAssertEqual(native.accessibilityValue() as? String, "2 of 2")
        XCTAssertTrue(control([])._updateView(native, in: context))
        XCTAssertEqual(selection.wrappedValue, -1)
        XCTAssertTrue(control(["A", "B"])._updateView(native, in: context))
        XCTAssertEqual(selection.wrappedValue, 0)
        XCTAssertEqual(native.accessibilityValue() as? String, "1 of 2")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(changes, [1, -1, 0], "Each actual selection transition is reported once")
        let container = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" })
        XCTAssertEqual(container.subviews.filter { !$0.isHidden }.count, 1)
        XCTAssertFalse(try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Previous" } as? NSButton).isEnabled)
    }

    @MainActor
    func testRapidNavigationLeavesOnlyCurrentPageVisible() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: false)
        let native = FluentFlipView(["A", "B", "C"]) { FluentText($0) }._makeView(in: context)
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        native.layoutSubtreeIfNeeded()
        let container = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" })
        let next = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Next" } as? NSButton)
        next.performClick(nil)
        next.performClick(nil)
        XCTAssertLessThanOrEqual(container.subviews.count, 5, "An interrupted flip retains only the visible and destination neighborhoods")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        XCTAssertEqual(container.subviews.filter { !$0.isHidden }.map { $0.identifier?.rawValue }, ["FluentKit.FlipView.Page.2"])
        XCTAssertEqual(native.accessibilityValue() as? String, "3 of 3")
    }

    @MainActor
    func testBoundContentRefreshPreservesActiveTransition() throws {
        _ = NSApplication.shared
        let selection = FluentState(wrappedValue: 0)
        let context = FluentRenderContext(reduceMotion: false)
        let native = FluentFlipView(["A", "B", "C"], selection: selection.projectedValue) {
            FluentText($0)
        }._makeView(in: context)
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        native.layoutSubtreeIfNeeded()
        let next = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Next" } as? NSButton)
        let container = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" })
        next.performClick(nil)
        XCTAssertEqual(selection.wrappedValue, 1)
        // A parent's bound page label can cause this update immediately after the click.
        XCTAssertTrue(FluentFlipView(["A", "B", "C"], selection: selection.projectedValue) {
            FluentText("Updated \($0)")
        }._updateView(native, in: context))
        XCTAssertFalse(container.subviews[0].isHidden)
        XCTAssertGreaterThan(container.subviews[1].frame.minX, 0, "A content refresh must preserve the partial incoming page")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        XCTAssertEqual(container.subviews.filter { !$0.isHidden }, [container.subviews[1]])
    }

    @MainActor
    func testRTLTransitionAndArrowNavigationUseTheSameDirection() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
        let native = FluentFlipView(["A", "B", "C"]) { FluentText($0) }._makeView(in: context)
        native.userInterfaceLayoutDirection = .rightToLeft
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        native.layoutSubtreeIfNeeded()
        let next = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Next" } as? NSButton)
        XCTAssertEqual(next.frame.minX, 1)
        let left = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 123))
        native.keyDown(with: left)
        XCTAssertEqual(native.accessibilityValue() as? String, "2 of 3")
        let container = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" })
        XCTAssertLessThan(container.subviews[1].frame.minX, 0, "The next RTL page enters from the left, matching its navigation button")
    }
}
