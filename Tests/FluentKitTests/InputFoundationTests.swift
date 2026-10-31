import XCTest
@testable import FluentKit

final class InputFoundationTests: XCTestCase {
    // These driver-only tests inspect acquisition and motion; responder-chain replay is covered
    // with mounted controls in ScrollChainingTests.
    private func handle(_ driver: FluentPanGestureDriver, _ event: NSEvent) -> Bool {
        driver.handleScrollWheel(event, replayUnclaimed: { _ in })
    }

    private func mouse(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func scroll(_ delta: CGFloat, axisY: Bool = false, phase: Int64, time: TimeInterval) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: Int32(axisY ? delta : 0), wheel2: Int32(axisY ? 0 : delta), wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(axisY ? delta : 0))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(axisY ? 0 : delta))
        event.timestamp = CGEventTimestamp(time * 1_000_000_000)
        return NSEvent(cgEvent: event)!
    }

    func testEventsAreClassifiedLikeWinUIInputDeviceTypes() {
        _ = NSApplication.shared
        XCTAssertEqual(FluentInputDeviceTracker.deviceType(for: mouse(.leftMouseDown)), .mouse)
        XCTAssertEqual(FluentInputDeviceTracker.deviceType(for: scroll(-5, phase: 2, time: 0)), .mouse,
                       "A trackpad is a mouse, as touchpad pointers are in WinUI")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        XCTAssertEqual(FluentInputDeviceTracker.deviceType(for: key), .keyboard)
        XCTAssertEqual(FluentInputDeviceTracker.deviceType(for: mouse(.leftMouseUp)), .mouse, "Opening on release retains the actual pointer kind")
        XCTAssertTrue(FluentInputDeviceType.touch.prefersTouchLayout)
        XCTAssertTrue(FluentInputDeviceType.pen.prefersPrimaryCommands)
        XCTAssertFalse(FluentInputDeviceType.mouse.prefersPrimaryCommands)
    }

    func testRecordingPostsOnlyWhenTheWindowDeviceChanges() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        var notifications = 0
        let token = NotificationCenter.default.addObserver(forName: FluentInputDeviceTracker.didChangeNotification,
                                                           object: window, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        let tracker = FluentInputDeviceTracker.shared
        tracker.record(.touch, in: window)
        tracker.record(.touch, in: window)
        XCTAssertEqual(tracker.lastDeviceType(in: window), .touch)
        tracker.record(.mouse, in: window)
        XCTAssertEqual(notifications, 2)
        tracker.record(.none, in: window)
        XCTAssertEqual(tracker.lastDeviceType(in: window), .mouse)
    }

    @MainActor
    func testDriverOwnsAxisDominantTrackpadPansAndReportsVelocity() {
        _ = NSApplication.shared
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let driver = FluentPanGestureDriver(view: view, axis: .vertical)
        var translations: [CGFloat] = []
        var velocity: CGFloat?
        driver.onBegin = { 10 }
        driver.onChange = { translations.append($0) }
        driver.onEnd = { velocity = $0 }
        XCTAssertTrue(handle(driver, scroll(3, axisY: true, phase: 1, time: 1.00)))
        XCTAssertTrue(handle(driver, scroll(10, axisY: true, phase: 2, time: 1.01)))
        XCTAssertTrue(driver.isActive)
        XCTAssertTrue(handle(driver, scroll(10, axisY: true, phase: 2, time: 1.02)))
        XCTAssertEqual(translations, [23, 33], "Translations continue from the client's start value")
        XCTAssertTrue(handle(driver, scroll(0, axisY: true, phase: 4, time: 1.03)))
        XCTAssertFalse(driver.isActive)
        XCTAssertEqual(velocity ?? 0, 23 / 0.01, accuracy: 1)

        XCTAssertTrue(handle(driver, scroll(2, phase: 1, time: 2.0)))
        XCTAssertFalse(handle(driver, scroll(12, phase: 2, time: 2.01)), "Cross-axis gestures are rejected")
        XCTAssertFalse(handle(driver, scroll(12, phase: 2, time: 2.02)))
        XCTAssertFalse(handle(driver, scroll(0, phase: 4, time: 2.03)))
    }

    @MainActor
    func testHorizontalDriverMirrorsInRightToLeftAndDeclinedPansFallThrough() {
        _ = NSApplication.shared
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.userInterfaceLayoutDirection = .rightToLeft
        let driver = FluentPanGestureDriver(view: view, axis: .horizontal)
        var last: CGFloat = 0
        driver.onChange = { last = $0 }
        _ = handle(driver, scroll(-3, phase: 1, time: 1.0))
        _ = handle(driver, scroll(-10, phase: 2, time: 1.01))
        XCTAssertEqual(last, 13, "A physical leftward swipe moves content toward the trailing edge in RTL")
        _ = handle(driver, scroll(0, phase: 4, time: 1.02))

        driver.onBegin = { nil }
        _ = handle(driver, scroll(-3, phase: 1, time: 2.0))
        XCTAssertFalse(handle(driver, scroll(-10, phase: 2, time: 2.01)))
        XCTAssertFalse(driver.isActive)
    }
    @MainActor func testReleaseAfterHoldingStillHasNoStaleVelocityAndResetDetaches() {
        _ = NSApplication.shared
        let view = NSView(frame: NSRect(x:0, y:0, width:200, height:200))
        let driver = FluentPanGestureDriver(view: view, axis: .horizontal)
        var velocity: CGFloat?, cancellations = 0
        driver.onEnd = { velocity = $0 }; driver.onCancel = { cancellations += 1 }
        XCTAssertTrue(handle(driver, scroll(-80, phase:1, time:1)))
        XCTAssertTrue(handle(driver, scroll(0, phase:4, time:2)))
        XCTAssertEqual(velocity, 0)
        XCTAssertTrue(handle(driver, scroll(-10, phase:1, time:3)))
        driver.reset()
        XCTAssertFalse(driver.isActive); XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(handle(driver, scroll(-10, phase:2, time:3.01)))
        driver.detach(); XCTAssertTrue(view.gestureRecognizers.isEmpty)
    }

}
