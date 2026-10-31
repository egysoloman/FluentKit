import XCTest
@testable import FluentKit

final class SwipeControlTests: XCTestCase {
    private final class Log { var invoked: [String] = [] }

    @MainActor
    private func makeSwipe(
        left: FluentSwipeItems? = nil,
        right: FluentSwipeItems? = nil,
        top: FluentSwipeItems? = nil,
        log: Log,
        size: NSSize = NSSize(width: 360, height: 48),
        reduceMotion: Bool = true
    ) throws -> FluentSwipeControlView {
        _ = NSApplication.shared
        let view = FluentSwipeControl(leftItems: left, rightItems: right, topItems: top) { FluentText("Message") }
        let swipe = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: reduceMotion)) as? FluentSwipeControlView)
        swipe.frame = NSRect(origin: .zero, size: size)
        swipe.layoutSubtreeIfNeeded()
        return swipe
    }

    private func items(_ log: Log, mode: FluentSwipeMode = .reveal, names: [String] = ["Archive", "Flag"],
                       behavior: FluentSwipeBehaviorOnInvoked = .automatic) -> FluentSwipeItems {
        FluentSwipeItems(mode: mode, names.map { name in
            FluentSwipeItem(name, systemImage: "archivebox", behaviorOnInvoked: behavior) { log.invoked.append(name) }
        })
    }

    @MainActor
    func testRevealOpensPastThresholdToTheItemsExtentAndSnapsBackBelowIt() throws {
        let log = Log()
        let swipe = try makeSwipe(right: items(log), log: log)
        XCTAssertEqual(swipe.beginSwipe(), 0)
        swipe.updateSwipe(translation: -50)
        XCTAssertEqual(swipe.contentHost.frame.minX, -50)
        XCTAssertEqual(swipe.itemButtons.count, 2)
        let extent = swipe.itemsExtent
        XCTAssertEqual(extent, 136, "Two items at the 68pt minimum width")
        XCTAssertEqual(swipe.itemButtons[0].frame.maxX, 360, "Right items start at the revealed (right) edge")
        swipe.endSwipe(velocity: 0)
        XCTAssertFalse(swipe.isOpen, "50pt is below min(extent - 1, 100)")
        XCTAssertEqual(swipe.contentHost.frame.minX, 0)
        XCTAssertTrue(swipe.itemButtons.isEmpty)

        swipe.beginSwipe()
        swipe.updateSwipe(translation: -110)
        swipe.endSwipe(velocity: 0)
        XCTAssertTrue(swipe.isOpen)
        XCTAssertEqual(swipe.offset, -extent)
        XCTAssertEqual(swipe.contentHost.frame.minX, -extent)
    }

    @MainActor
    func testOpenControlClosesOnAnyClosingMovementAndCannotCrossToTheOtherSide() throws {
        let log = Log()
        let swipe = try makeSwipe(left: items(log), right: items(log, names: ["Delete"]), log: log)
        swipe.beginSwipe(); swipe.updateSwipe(translation: 140); swipe.endSwipe(velocity: 0)
        XCTAssertTrue(swipe.isOpen)
        let start = try XCTUnwrap(swipe.beginSwipe())
        swipe.updateSwipe(translation: start - 400)
        XCTAssertEqual(swipe.offset, 0, "An open side blocks the opposite side within the gesture")
        swipe.updateSwipe(translation: start - 10)
        swipe.endSwipe(velocity: 0)
        XCTAssertFalse(swipe.isOpen, "Any closing movement closes an open control")
    }

    @MainActor
    func testFlickOpensAndSidesWithoutItemsStayClosed() throws {
        let log = Log()
        let swipe = try makeSwipe(right: items(log), log: log)
        swipe.beginSwipe()
        swipe.updateSwipe(translation: 80)
        XCTAssertEqual(swipe.offset, 0, "No left items: swiping right does nothing")
        swipe.updateSwipe(translation: -30)
        swipe.endSwipe(velocity: -1_000)
        XCTAssertTrue(swipe.isOpen, "A flick projects past the threshold")
    }

    @MainActor
    func testItemClickInvokesAndHonoursBehaviorOnInvoked() throws {
        let log = Log()
        let swipe = try makeSwipe(right: items(log), log: log)
        swipe.beginSwipe(); swipe.updateSwipe(translation: -140); swipe.endSwipe(velocity: 0)
        XCTAssertTrue(swipe.itemButtons[1].accessibilityPerformPress())
        XCTAssertEqual(log.invoked, ["Flag"])
        XCTAssertFalse(swipe.isOpen, "Automatic closes after invoking")

        let remain = try makeSwipe(right: items(log, behavior: .remainOpen), log: log)
        remain.beginSwipe(); remain.updateSwipe(translation: -140); remain.endSwipe(velocity: 0)
        remain.invokeItem(at: 0)
        XCTAssertTrue(remain.isOpen)
        remain.close()
        XCTAssertFalse(remain.isOpen)
    }

    @MainActor
    func testExecuteInvokesOnReleasePastThresholdAndRecolours() throws {
        let log = Log()
        let swipe = try makeSwipe(left: items(log, mode: .execute, names: ["Accept", "Ignored"]), log: log)
        swipe.beginSwipe()
        swipe.updateSwipe(translation: 40)
        XCTAssertEqual(swipe.itemButtons.count, 1, "Execute shows only the first item")
        XCTAssertEqual(swipe.itemButtons[0].frame.width, 40, "Its background fills the revealed area")
        XCTAssertFalse(swipe.isThresholdReached)
        XCTAssertEqual(swipe.itemButtons[0].backgroundColor, FluentTheme.current.controlFillTertiary)
        swipe.updateSwipe(translation: 200)
        XCTAssertTrue(swipe.isThresholdReached)
        XCTAssertEqual(swipe.itemButtons[0].foregroundColor, FluentTheme.current.textOnAccent)
        swipe.endSwipe(velocity: 0)
        XCTAssertEqual(log.invoked, ["Accept"])
        XCTAssertFalse(swipe.isOpen, "Execute closes after invoking unless RemainOpen")
    }

    @MainActor
    func testPressOutsideClosesAndContentPressesAreEaten() throws {
        let log = Log()
        let swipe = try makeSwipe(right: items(log), log: log)
        swipe.beginSwipe(); swipe.updateSwipe(translation: -140); swipe.endSwipe(velocity: 0)
        XCTAssertFalse(swipe.handleDismissingPress(at: NSPoint(x: 350, y: 20)), "Presses on items pass through")
        XCTAssertTrue(swipe.isOpen)
        XCTAssertTrue(swipe.handleDismissingPress(at: NSPoint(x: 20, y: 20)), "A content press closes and is eaten")
        XCTAssertFalse(swipe.isOpen)
    }

    @MainActor
    func testOnlyOneSwipeControlStaysOpen() throws {
        let log = Log()
        let first = try makeSwipe(right: items(log), log: log)
        let second = try makeSwipe(right: items(log), log: log)
        first.beginSwipe(); first.updateSwipe(translation: -140); first.endSwipe(velocity: 0)
        second.beginSwipe()
        XCTAssertFalse(first.isOpen, "Interacting with another SwipeControl closes the open one")
    }

    @MainActor
    func testRightToLeftMirrorsAndVerticalItemsStackDownward() throws {
        let log = Log()
        let rtl = try makeSwipe(left: items(log), log: log)
        rtl.userInterfaceLayoutDirection = .rightToLeft
        rtl.beginSwipe(); rtl.updateSwipe(translation: 140); rtl.endSwipe(velocity: 0)
        XCTAssertEqual(rtl.contentHost.frame.minX, -136, "Leading items open from the right in RTL")
        XCTAssertEqual(rtl.itemButtons[0].frame.maxX, 360)

        let vertical = try makeSwipe(top: items(log), log: log, size: NSSize(width: 200, height: 300))
        XCTAssertFalse(vertical.configuration.isHorizontal)
        XCTAssertEqual(vertical.panDriver.axis, .vertical)
        vertical.beginSwipe(); vertical.updateSwipe(translation: 120); vertical.endSwipe(velocity: 0)
        XCTAssertTrue(vertical.isOpen)
        XCTAssertEqual(vertical.contentHost.frame.minY, vertical.itemsExtent)
        XCTAssertEqual(vertical.itemButtons[0].frame.minY, 0)
        XCTAssertEqual(vertical.itemButtons[1].frame.minY, vertical.itemButtons[0].frame.maxY)
    }

    @MainActor
    func testVoiceOverActionsAndDisabledAncestors() throws {
        let log = Log()
        let swipe = try makeSwipe(left: items(log, mode: .execute, names: ["Accept", "Hidden"]), right: items(log), log: log)
        let actions = try XCTUnwrap(swipe.contentHost.accessibilityCustomActions())
        XCTAssertEqual(actions.map(\.name), ["Accept", "Archive", "Flag"])
        _ = actions[2].handler?()
        XCTAssertEqual(log.invoked, ["Flag"])

        let container = NSControl(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        container.addSubview(swipe)
        container.isEnabled = false
        XCTAssertNil(swipe.beginSwipe(), "A disabled ancestor blocks swiping")
    }

    @MainActor
    func testAnimatedSettleCompletes() throws {
        let log = Log()
        let swipe = try makeSwipe(right: items(log), log: log, reduceMotion: false)
        swipe.beginSwipe(); swipe.updateSwipe(translation: -120); swipe.endSwipe(velocity: 0)
        let deadline = Date(timeIntervalSinceNow: 2)
        while !swipe.isOpen, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        XCTAssertTrue(swipe.isOpen)
        XCTAssertEqual(swipe.offset, -swipe.itemsExtent)
    }
}
