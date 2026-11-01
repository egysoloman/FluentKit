import XCTest
@testable import FluentKit

private final class ToggleKeyReceiver: NSResponder {
    var keys: [UInt16] = []
    override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
    override func keyUp(with event: NSEvent) {}
}

final class ToggleKeyboardTests: XCTestCase {
    @MainActor private func mount(_ initial: Bool = false) -> (NSWindow, FluentToggle) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let toggle = FluentToggle(title: "Toggle", isOn: initial)
        toggle.reduceMotion = true
        toggle.frame = NSRect(x: 20, y: 20, width: 180, height: 40)
        window.contentView!.addSubview(toggle)
        toggle.layoutSubtreeIfNeeded()
        window.makeFirstResponder(toggle)
        return (window, toggle)
    }

    @MainActor private func key(_ type: NSEvent.EventType, _ code: UInt16 = 49, repeat isRepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: code == 49 ? " " : "\r",
            charactersIgnoringModifiers: code == 49 ? " " : "\r", isARepeat: isRepeat, keyCode: code)!
    }

    @MainActor private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, in toggle: FluentToggle) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: toggle.convert(NSPoint(x: x, y: toggle.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: toggle.window!.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @MainActor func testSpaceCommitsOnceOnReleaseWithoutPointerPressedVisuals() throws {
        for initial in [false, true] {
            for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
                let (window, toggle) = mount(initial)
                defer { window.close() }
                toggle.fluentLayoutDirection = direction
                var values: [Bool] = []
                toggle.onValueChanged = { values.append($0) }
                let knob = try XCTUnwrap(toggle.layer?.sublayers?.first { $0.name == "FluentKit.Toggle.Knob" })
                let restingSize = knob.bounds.size
                toggle.keyDown(with: key(.keyDown))
                toggle.keyDown(with: key(.keyDown, repeat: true))
                XCTAssertEqual(toggle.isOn, initial)
                XCTAssertTrue(values.isEmpty)
                XCTAssertEqual(knob.bounds.size, restingSize, "WinUI Space only arms a release; it does not enter pointer Pressed")
                toggle.keyUp(with: key(.keyUp))
                XCTAssertEqual(toggle.isOn, !initial)
                XCTAssertEqual(values, [!initial])
                toggle.keyUp(with: key(.keyUp))
                XCTAssertEqual(values, [!initial], "An unmatched release cannot commit again")
            }
        }
    }

    @MainActor func testReturnAndArrowKeysPropagateWithoutActivation() {
        let (window, toggle) = mount()
        defer { window.close() }
        let receiver = ToggleKeyReceiver()
        toggle.nextResponder = receiver
        let keys: [UInt16] = [36, 76, 123, 124, 125, 126, 115, 119]
        for code in keys {
            toggle.keyDown(with: key(.keyDown, code))
            toggle.keyUp(with: key(.keyUp, code))
            XCTAssertFalse(toggle.isOn, "Unsupported ToggleSwitch key \(code)")
        }
        XCTAssertEqual(receiver.keys, keys)
        toggle.keyDown(with: key(.keyDown))
        toggle.keyDown(with: key(.keyDown, 36))
        toggle.keyUp(with: key(.keyUp))
        XCTAssertFalse(toggle.isOn, "An intervening unsupported key clears the handled key-down, as in WinUI")
    }

    @MainActor func testCancellationCannotBeRearmedByAutoRepeat() {
        for escape in [false, true] {
            let (window, toggle) = mount()
            defer { window.close() }
            var values: [Bool] = []
            toggle.onValueChanged = { values.append($0) }
            toggle.keyDown(with: key(.keyDown))
            if escape { toggle.keyDown(with: key(.keyDown, 53)) }
            else { toggle.cancelOperation(nil) }
            toggle.keyDown(with: key(.keyDown, repeat: true))
            toggle.keyUp(with: key(.keyUp))
            XCTAssertFalse(toggle.isOn)
            XCTAssertTrue(values.isEmpty)
            toggle.keyDown(with: key(.keyDown))
            toggle.keyUp(with: key(.keyUp))
            XCTAssertEqual(values, [true], "A fresh key sequence still activates")
        }
    }

    @MainActor func testLifecycleChangesCancelPendingRelease() {
        for scenario in 0..<6 {
            let (window, toggle) = mount()
            defer { window.close() }
            toggle.keyDown(with: key(.keyDown))
            switch scenario {
            case 0: toggle.isEnabled = false; toggle.isEnabled = true
            case 1: toggle.isHidden = true; toggle.isHidden = false
            case 2: window.contentView!.isHidden = true; window.contentView!.isHidden = false
            case 3: window.makeFirstResponder(nil); window.makeFirstResponder(toggle)
            case 4:
                let parent = toggle.superview!
                toggle.removeFromSuperview(); parent.addSubview(toggle)
            default: NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            }
            toggle.keyUp(with: key(.keyUp))
            XCTAssertFalse(toggle.isOn, "Cancellation scenario \(scenario)")
        }
    }

    @MainActor func testPointerPressAndDragDoNotAcceptNewKeyboardActivation() {
        for drag in [false, true] {
            let (window, toggle) = mount()
            defer { window.close() }
            var values: [Bool] = []
            toggle.onValueChanged = { values.append($0) }
            toggle.mouseDown(with: mouse(.leftMouseDown, 8, in: toggle))
            if drag { toggle.mouseDragged(with: mouse(.leftMouseDragged, 28, in: toggle)) }
            toggle.keyDown(with: key(.keyDown))
            toggle.keyUp(with: key(.keyUp))
            XCTAssertFalse(toggle.isOn)
            XCTAssertTrue(values.isEmpty)
            toggle.mouseUp(with: mouse(.leftMouseUp, drag ? 28 : 8, in: toggle))
            XCTAssertEqual(values, [true], "Space must not cancel or prematurely commit the pointer operation")
        }
    }

    @MainActor func testOverlappingInputsFollowTheirReleaseOrder() {
        for keyboardReleasesFirst in [false, true] {
            let (window, toggle) = mount()
            defer { window.close() }
            var values: [Bool] = []
            toggle.onValueChanged = { values.append($0) }
            toggle.keyDown(with: key(.keyDown))
            toggle.mouseDown(with: mouse(.leftMouseDown, 8, in: toggle))
            if keyboardReleasesFirst { toggle.keyUp(with: key(.keyUp)) }
            XCTAssertTrue(values.isEmpty)
            toggle.mouseUp(with: mouse(.leftMouseUp, 8, in: toggle))
            if !keyboardReleasesFirst { toggle.keyUp(with: key(.keyUp)) }
            XCTAssertEqual(values, keyboardReleasesFirst ? [true] : [true, false],
                "WinUI suppresses a handled release during the pointer operation, not after it ends")
        }
    }

    @MainActor func testModelChangesKeepKeyboardIntentAndUseLatestValue() {
        let (window, toggle) = mount()
        defer { window.close() }
        var values: [Bool] = []
        toggle.onValueChanged = { values.append($0) }
        toggle.keyDown(with: key(.keyDown))
        toggle.setStateFromBinding(true)
        XCTAssertTrue(toggle.isOn)
        XCTAssertTrue(values.isEmpty, "A binding update does not emit a user change")
        toggle.keyUp(with: key(.keyUp))
        XCTAssertFalse(toggle.isOn, "Space release toggles the current model value")
        XCTAssertEqual(values, [false])
    }

    @MainActor func testAccessibilityActionCommitsImmediatelyAndConsumesPendingKeyboard() {
        let (window, toggle) = mount()
        defer { window.close() }
        var values: [Bool] = []
        toggle.onValueChanged = { values.append($0) }
        toggle.keyDown(with: key(.keyDown))
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertTrue(toggle.isOn)
        toggle.keyUp(with: key(.keyUp))
        XCTAssertEqual(values, [true])
        toggle.isEnabled = false
        XCTAssertFalse(toggle.accessibilityPerformPress())
        XCTAssertEqual(values, [true])
    }

    @MainActor func testReentrantCallbackCannotReuseTheSameKeyRelease() {
        let (window, toggle) = mount()
        defer { window.close() }
        var values: [Bool] = []
        toggle.onValueChanged = { value in
            values.append(value)
            toggle.keyUp(with: self.key(.keyUp))
        }
        toggle.keyDown(with: key(.keyDown))
        XCTAssertTrue(values.isEmpty)
        toggle.keyUp(with: key(.keyUp))
        XCTAssertEqual(values, [true])
    }
}
