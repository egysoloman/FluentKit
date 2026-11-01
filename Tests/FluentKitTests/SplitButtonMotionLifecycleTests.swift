import XCTest
@testable import FluentKit

@MainActor
final class SplitButtonMotionLifecycleTests: XCTestCase {
    private let motionKey = "fluent.chevron.press"
    private final class BackingWindow: NSWindow {
        var simulatedScale: CGFloat?
        override var backingScaleFactor: CGFloat { simulatedScale ?? super.backingScaleFactor }
    }

    private func mount(checked: Bool = false, rtl: Bool = false) throws
        -> (NSWindow, FluentToggleSplitButton, FluentChevronPrimitiveLayer) {
        _ = NSApplication.shared
        let button = FluentToggleSplitButton("Save", isChecked: checked, items: [FluentMenuItem("Copy") {}])
        button.reduceMotion = false
        button.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
        let window = BackingWindow(contentRect: NSRect(x: 100, y: 200, width: 500, height: 280),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 280))
        window.contentView?.addSubview(button)
        button.frame = NSRect(x: 24, y: 180, width: 160, height: 32)
        window.makeKeyAndOrderFront(nil)
        button.layoutSubtreeIfNeeded()
        let chevron = try XCTUnwrap(button.layer?.sublayers?.compactMap { $0 as? FluentChevronPrimitiveLayer }.first)
        return (window, button, chevron)
    }

    private func point(_ button: NSView, secondary: Bool) -> NSPoint {
        let rtl = button.userInterfaceLayoutDirection == .rightToLeft
        return NSPoint(x: (secondary != rtl) ? button.bounds.maxX - 15 : 15, y: button.bounds.midY)
    }

    private func mouse(_ type: NSEvent.EventType, _ button: NSView, secondary: Bool = true,
                       outside: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type,
            location: button.convert(outside ? NSPoint(x: -10, y: -10) : point(button, secondary: secondary), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: button.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func key(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: 49))
    }

    func testLayoutThemeContentAndResizeKeepTheSamePressTimelineAndPosition() throws {
        for checked in [false, true] {
            for rtl in [false, true] {
                let (window, button, chevron) = try mount(checked: checked, rtl: rtl)
                defer { window.close() }
                button.mouseDown(with: try mouse(.leftMouseDown, button))
                let animation = try XCTUnwrap(chevron.animation(forKey: motionKey))
                let position = chevron.position
                for _ in 0..<3 {
                    button.needsLayout = true
                    button.layoutSubtreeIfNeeded()
                    XCTAssertEqual(chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
                    XCTAssertEqual(chevron.position, position, "Layout and state updates must share the same pixel geometry")
                }
                button.title = "Updated title"
                button.theme = .custom(colorScheme: .light)
                button.setFrameSize(NSSize(width: 211, height: 36))
                button.layoutSubtreeIfNeeded()
                XCTAssertEqual(chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
                XCTAssertEqual(button.isChecked, checked)
            }
        }
    }

    func testPressedChevronMovesVisuallyDownInTheUnflippedControl() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.reduceMotion = true
        XCTAssertFalse(button.isFlipped)
        let normal = chevron.position.y + chevron.transform.m42
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        let pressed = chevron.position.y + chevron.transform.m42
        XCTAssertEqual(pressed - normal, -1.875, accuracy: 0.001,
                       "WinUI DownSmall moves down; AppKit's unflipped local Y increases upward")
    }

    func testSharedPrimitiveMirrorsPressDisplacementWithItsPath() {
        for inverted in [false, true] {
            let chevron = FluentChevronPrimitiveLayer()
            chevron.update(frame: NSRect(x: 0, y: 0, width: 12, height: 12), color: .black,
                state: .pressed, visual: .downSmall, inverted: inverted, reduceMotion: true, animated: true)
            XCTAssertEqual(chevron.transform.m42, inverted ? -1.875 : 1.875, accuracy: 0.001)
        }
    }

    func testFlyoutChromeDoesNotHoldTheArrowInItsPointerPressedState() throws {
        for checked in [false, true] {
            let (window, button, chevron) = try mount(checked: checked)
            defer { window.close() }
            button.reduceMotion = true
            button.mouseDown(with: try mouse(.leftMouseDown, button))
            button.mouseUp(with: try mouse(.leftMouseUp, button))
            XCTAssertTrue(button.isFlyoutPresented)
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
            XCTAssertEqual(button.isChecked, checked, "Opening the menu must not toggle the primary state")
            let primary = button.layer?.sublayers?.first { $0.name == "FluentKit.SplitButton.Primary" }
            let secondary = button.layer?.sublayers?.first { $0.name == "FluentKit.SplitButton.Secondary" }
            XCTAssertEqual(primary?.backgroundColor, secondary?.backgroundColor)
            XCTAssertEqual(primary?.backgroundColor, (checked ? button.theme.accentFillTertiary : button.theme.controlFillTertiary).cgColor)
            button.hideFlyout(animated: false)
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
        }
    }

    func testKeyboardAndTouchChromeRemainDistinctFromSecondaryPointerMotion() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.reduceMotion = true
        var invocations = 0
        button.onPrimaryAction = { invocations += 1 }
        button.mouseDown(with: try mouse(.leftMouseDown, button, secondary: false))
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
        button.mouseUp(with: try mouse(.leftMouseUp, button, outside: true))
        window.makeFirstResponder(button)
        button.keyDown(with: try key(.keyDown, in: window))
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001,
                       "SplitButton's keyboard TouchPressed state does not set its child Button's IsPressed")
        button.keyUp(with: try key(.keyUp, in: window))
        XCTAssertEqual(invocations, 1)
        let touch = DirectTouchPointerFixture()
        touch.point = button.convert(point(button, secondary: false), to: nil)
        button.mouseDown(with: touch)
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
        button.mouseUp(with: try mouse(.leftMouseUp, button, outside: true))
        touch.point = button.convert(point(button, secondary: true), to: nil)
        button.mouseDown(with: touch)
        XCTAssertEqual(chevron.transform.m42, -1.875, accuracy: 0.001)
    }

    func testDisabledAndHiddenControlsSettleMotionWithoutReplay() throws {
        for hide in [false, true] {
            let (window, button, chevron) = try mount()
            defer { window.close() }
            button.mouseDown(with: try mouse(.leftMouseDown, button))
            XCTAssertNotNil(chevron.animation(forKey: motionKey))
            if hide { button.isHidden = true } else { button.isEnabled = false }
            XCTAssertNil(chevron.animation(forKey: motionKey))
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
            if hide { button.isHidden = false } else { button.isEnabled = true }
            button.layoutSubtreeIfNeeded()
            XCTAssertNil(chevron.animation(forKey: motionKey))
            button.mouseUp(with: try mouse(.leftMouseUp, button))
            XCTAssertFalse(button.isFlyoutPresented)
        }
    }

    func testMotionPolicySettlesAndAllowsTheNextRealPress() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        XCTAssertNotNil(chevron.animation(forKey: motionKey))
        button.reduceMotion = true
        XCTAssertNil(chevron.animation(forKey: motionKey))
        button.reduceMotion = false
        button.layoutSubtreeIfNeeded()
        XCTAssertNil(chevron.animation(forKey: motionKey))
        button.mouseUp(with: try mouse(.leftMouseUp, button, outside: true))
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        XCTAssertNotNil(chevron.animation(forKey: motionKey))
    }

    func testFocusLossCancelsBothPointerRegions() throws {
        for secondary in [false, true] {
            let (window, button, chevron) = try mount()
            defer { window.close() }
            var invoked = 0
            button.onPrimaryAction = { invoked += 1 }
            button.mouseDown(with: try mouse(.leftMouseDown, button, secondary: secondary))
            XCTAssertTrue(window.firstResponder === button)
            window.makeFirstResponder(nil)
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
            button.mouseUp(with: try mouse(.leftMouseUp, button, secondary: secondary))
            XCTAssertEqual(invoked, 0)
            XCTAssertFalse(button.isFlyoutPresented)
        }
    }

    func testBackingChangesRefreshScaleAndPreserveMotion() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        let backingWindow = try XCTUnwrap(window as? BackingWindow)
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        let animation = try XCTUnwrap(chevron.animation(forKey: motionKey))
        for scale: CGFloat in [1, 2] {
            backingWindow.simulatedScale = scale
            button.viewDidChangeBackingProperties()
            XCTAssertEqual(chevron.contentsScale, scale)
            XCTAssertEqual(chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
        }
    }

    func testSameWindowReparentCancelsCapturedPointerActivation() throws {
        for secondary in [false, true] {
            let (window, button, chevron) = try mount()
            defer { window.close() }
            var invocations = 0
            button.onPrimaryAction = { invocations += 1 }
            let destination = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 280))
            window.contentView?.addSubview(destination)
            button.mouseDown(with: try mouse(.leftMouseDown, button, secondary: secondary))
            destination.addSubview(button)
            XCTAssertTrue(button.window === window)
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
            XCTAssertNil(chevron.animation(forKey: motionKey))
            button.mouseUp(with: try mouse(.leftMouseUp, button, secondary: secondary))
            XCTAssertEqual(invocations, 0)
            XCTAssertFalse(button.isFlyoutPresented)
        }
    }
}
