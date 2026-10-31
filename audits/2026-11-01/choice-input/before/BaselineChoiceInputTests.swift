import AppKit
import XCTest
@testable import FluentKit

private final class ChoicePressRecorder { var pressed = false }
// Bool storage is lock-protected by FluentObservable; delivery is marshalled to main.
private final class BackgroundStateWrite<Value: Sendable>: @unchecked Sendable {
    let state: FluentState<Value>
    init(_ state: FluentState<Value>) { self.state = state }
}
private struct RecordingCheckStyle: FluentCheckBoxStyle {
    let recorder: ChoicePressRecorder
    func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        recorder.pressed = configuration.isPressed
        return FluentAutomaticCheckBoxStyle().appearance(for: configuration)
    }
}

final class ChoiceInputTests: XCTestCase {
    @MainActor private func key(_ type: NSEvent.EventType, _ code: UInt16 = 49, repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: code == 49 ? " " : "\r",
            charactersIgnoringModifiers: code == 49 ? " " : "\r", isARepeat: repeatKey, keyCode: code)!
    }
    @MainActor private func pointer(_ type: NSEvent.EventType, _ view: NSView, inside: Bool = true) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: inside ? 10 : 230, y: 16), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }
    @MainActor private func prepare(_ view: NSView) {
        _ = NSApplication.shared
        view.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        view.layoutSubtreeIfNeeded()
    }
    @MainActor private func drainMainQueue() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @MainActor func testCheckBoxSpaceCommitsOnReleaseWithKeyboardPressedFeedback() {
        let box = FluentCheckBox(); prepare(box)
        let recorder = ChoicePressRecorder(); box.fluentStyle = RecordingCheckStyle(recorder: recorder)
        var values: [Bool] = []; box.onValueChanged = { values.append($0) }
        box.keyDown(with: key(.keyDown))
        XCTAssertFalse(box.isChecked); XCTAssertTrue(recorder.pressed); XCTAssertTrue(values.isEmpty)
        box.keyDown(with: key(.keyDown, repeatKey: true))
        XCTAssertFalse(box.isChecked)
        box.keyUp(with: key(.keyUp))
        XCTAssertTrue(box.isChecked); XCTAssertFalse(recorder.pressed); XCTAssertEqual(values, [true])
        box.keyUp(with: key(.keyUp)); XCTAssertEqual(values, [true])
    }

    @MainActor func testCheckBoxReturnAndKeypadSelectionMatchWinUI() {
        let box = FluentCheckBox(); prepare(box)
        for code: UInt16 in [36, 76] {
            box.isChecked = false
            box.keyDown(with: key(.keyDown, code)); box.keyUp(with: key(.keyUp, code))
            XCTAssertFalse(box.isChecked, "Return/Enter must not toggle CheckBox")
        }
        box.isChecked = false
        box.keyDown(with: key(.keyDown, 69)); XCTAssertTrue(box.isChecked, "keypad Add checks")
        box.keyDown(with: key(.keyDown, 69)); XCTAssertTrue(box.isChecked)
        box.keyDown(with: key(.keyDown, 78)); XCTAssertFalse(box.isChecked, "keypad Subtract unchecks")
        for control in [box as NSControl, FluentRadioButton()] {
            prepare(control)
            control.keyDown(with: key(.keyDown))
            control.keyDown(with: key(.keyDown, 36))
            control.keyUp(with: key(.keyUp))
            XCTAssertEqual(control.accessibilityValue() as? NSNumber, 0, "another key cancels held Space")
        }
    }

    @MainActor func testChoicePressIsCancelledOnFocusLossDetachDisableAndWindowDeactivation() {
        for radio in [false, true] { for reason in ["focus", "detach", "disable", "window"] {
            let control: NSControl = radio ? FluentRadioButton() : FluentCheckBox()
            prepare(control)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView!.addSubview(control)
            window.makeFirstResponder(control)
            control.mouseDown(with: pointer(.leftMouseDown, control))
            switch reason {
            case "focus": window.makeFirstResponder(nil)
            case "detach": control.removeFromSuperview()
            case "disable": control.isEnabled = false
            default: NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            }
            control.mouseUp(with: pointer(.leftMouseUp, control))
            XCTAssertEqual(control.accessibilityValue() as? NSNumber, 0, "\(radio ? "radio" : "check") \(reason)")
            window.close()
        } }
    }

    @MainActor func testExternalValueUpdatesPreserveAnOngoingGestureAndUseCurrentValueOnRelease() {
        for keyboard in [false, true] { for updated in [false, true] {
            let box = FluentCheckBox(); prepare(box)
            if keyboard { box.keyDown(with: key(.keyDown)) }
            else { box.mouseDown(with: pointer(.leftMouseDown, box)) }
            box.setStateFromBinding(updated)
            if keyboard { box.keyUp(with: key(.keyUp)) }
            else { box.mouseUp(with: pointer(.leftMouseUp, box)) }
            XCTAssertEqual(box.isChecked, !updated, "release toggles the current model value")
            let radio = FluentRadioButton(); prepare(radio)
            if keyboard { radio.keyDown(with: key(.keyDown)) }
            else { radio.mouseDown(with: pointer(.leftMouseDown, radio)) }
            radio.setStateFromBinding(updated)
            if keyboard { radio.keyUp(with: key(.keyUp)) }
            else { radio.mouseUp(with: pointer(.leftMouseUp, radio)) }
            XCTAssertTrue(radio.isSelected, "release selects regardless of an intervening property update")
        } }
    }

    @MainActor func testBoundChoicesUpdateImmediatelyAndRejectQueuedValuesFromAnOldBinding() async {
        for radio in [false, true] {
            let old = FluentState<Bool>(wrappedValue: false), new = FluentState<Bool>(wrappedValue: false)
            let check = FluentBoundCheckBox(old.projectedValue), choice = FluentBoundRadioButton(old.projectedValue)
            let control: NSControl = radio ? choice.radioButton : check.checkBox
            old.wrappedValue = true
            XCTAssertEqual(control.accessibilityValue() as? NSNumber, 1, "main-thread model updates are synchronous")
            old.wrappedValue = false
            let delivered = DispatchSemaphore(value: 0)
            let write = BackgroundStateWrite(old)
            DispatchQueue.global().async { write.state.wrappedValue = true; delivered.signal() }
            XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
            if radio { choice.update(binding: new.projectedValue, theme: .current, reduceMotion: true, layoutDirection: .leftToRight) }
            else { check.update(binding: new.projectedValue, theme: .current, reduceMotion: true, layoutDirection: .leftToRight) }
            await drainMainQueue()
            XCTAssertEqual(control.accessibilityValue() as? NSNumber, 0, "obsolete subscription must not overwrite the new model")
            XCTAssertFalse(new.wrappedValue)
        }
    }

    @MainActor func testQueuedOlderNotificationCannotOverwriteANewerMainThreadValue() async {
        let state = FluentState<Bool>(wrappedValue: true)
        let check = FluentBoundCheckBox(state.projectedValue), radio = FluentBoundRadioButton(state.projectedValue)
        let delivered = DispatchSemaphore(value: 0)
        let write = BackgroundStateWrite(state)
        DispatchQueue.global().async { write.state.wrappedValue = false; delivered.signal() }
        XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        state.wrappedValue = true
        await drainMainQueue()
        XCTAssertTrue(check.checkBox.isChecked); XCTAssertTrue(radio.radioButton.isSelected)
    }

    @MainActor func testRebindingCancelsOldPressButRefreshingTheSameBindingPreservesIt() {
        for radio in [false, true] { for replace in [false, true] {
            let old = FluentState<Bool>(wrappedValue: false), new = FluentState<Bool>(wrappedValue: false)
            let check = FluentBoundCheckBox(old.projectedValue), choice = FluentBoundRadioButton(old.projectedValue)
            let control: NSControl = radio ? choice.radioButton : check.checkBox; prepare(control)
            control.mouseDown(with: pointer(.leftMouseDown, control))
            let binding = replace ? new.projectedValue : old.projectedValue
            if radio { choice.update(binding: binding, theme: .current, reduceMotion: true, layoutDirection: .leftToRight) }
            else { check.update(binding: binding, theme: .current, reduceMotion: true, layoutDirection: .leftToRight) }
            control.mouseUp(with: pointer(.leftMouseUp, control))
            XCTAssertFalse(new.wrappedValue, "a press begun on the old model cannot write to the replacement")
            XCTAssertEqual(old.wrappedValue, !replace, "stable binding refresh preserves a valid press")
        } }
    }

    @MainActor func testRadioGroupModelChangeDoesNotCancelAnUnselectedMembersSpacePress() throws {
        let selection = FluentState<String?>(wrappedValue: "B")
        let group = FluentRadioButtons(["A", "B", "C"], selection: selection.projectedValue)._makeView(in: FluentRenderContext())
        let radios = try XCTUnwrap(group.accessibilityChildren() as? [FluentRadioButton])
        let a = radios[0]; prepare(a)
        a.keyDown(with: key(.keyDown))
        selection.wrappedValue = "C"
        XCTAssertEqual(selection.wrappedValue, "C")
        a.keyUp(with: key(.keyUp))
        XCTAssertEqual(selection.wrappedValue, "A", "subsequent user release is a new selection")
        XCTAssertEqual(radios.map(\.isSelected), [true, false, false])
        let feedback = try XCTUnwrap(a.layer?.sublayers?.first { $0.name == "FluentKit.RadioButton.PressedDot" })
        XCTAssertEqual(feedback.opacity, 0)
    }
    @MainActor func testRadioGroupRefreshPreservesPressButNewBindingCancelsIt() {
        for replace in [false, true] {
            let old = FluentState<String?>(wrappedValue: nil), new = FluentState<String?>(wrappedValue: nil)
            let group = FluentRadioButtons(["A", "B"], selection: old.projectedValue)
            let native = group._makeView(in: FluentRenderContext())
            let a = native.subviews.compactMap { $0 as? FluentRadioButton }[0]; prepare(a)
            a.keyDown(with: key(.keyDown))
            let updated = FluentRadioButtons(["A", "B"], selection: replace ? new.projectedValue : old.projectedValue)
            XCTAssertTrue(updated._updateView(native, in: FluentRenderContext()))
            a.keyUp(with: key(.keyUp))
            XCTAssertNil(new.wrappedValue)
            XCTAssertEqual(old.wrappedValue, replace ? nil : "A")
        }
    }

    @MainActor func testRadioGroupRejectsQueuedOlderSelectionFromTheSameBinding() async {
        let state = FluentState<String?>(wrappedValue: "A")
        let native = FluentRadioButtons(["A", "B", "C"], selection: state.projectedValue)._makeView(in: FluentRenderContext())
        let delivered = DispatchSemaphore(value: 0), write = BackgroundStateWrite(state)
        DispatchQueue.global().async { write.state.wrappedValue = "B"; delivered.signal() }
        XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        state.wrappedValue = "C"
        await drainMainQueue()
        XCTAssertEqual(state.wrappedValue, "C")
        XCTAssertEqual(native.subviews.compactMap { $0 as? FluentRadioButton }.map(\.isSelected), [false, false, true])
    }

}
