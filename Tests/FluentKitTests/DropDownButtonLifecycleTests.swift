import XCTest
@testable import FluentKit

@MainActor
final class DropDownButtonLifecycleTests: XCTestCase {
    private let motionKey = "fluent.chevron.press"

    private func mount() throws -> (NSWindow, FluentDropDownButton, FluentChevronPrimitiveLayer) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 280),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 280))
        let button = FluentDropDownButton(title: "Options", items: [FluentMenuItem("Item") {}])
        button.reduceMotion = false
        button.frame = NSRect(x: 24, y: 180, width: 160, height: 32)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)
        button.layoutSubtreeIfNeeded()
        let chevron = try XCTUnwrap(button.layer?.sublayers?.first {
            $0.name == "FluentKit.DropDownButton.Chevron"
        } as? FluentChevronPrimitiveLayer)
        return (window, button, chevron)
    }

    private func pointer(_ type: NSEvent.EventType, _ button: NSView) throws -> NSEvent {
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        if type == .mouseEntered || type == .mouseExited {
            return try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: button.window?.windowNumber ?? 0, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
        }
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: button.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func key(_ type: NSEvent.EventType, _ code: UInt16, in window: NSWindow,
                     repeatEvent: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: code == 49 ? " " : "\r",
            charactersIgnoringModifiers: code == 49 ? " " : "\r", isARepeat: repeatEvent, keyCode: code))
    }

    private func requestOpen(_ button: FluentDropDownButton) {
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
    }

    private func drainPendingOpen() {
        var drained = false
        DispatchQueue.main.async { drained = true }
        waitForUI(drained)
    }

    func testLayoutContentThemeAndBackingUpdatesPreservePressTimeline() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.mouseDown(with: try pointer(.leftMouseDown, button))
        let animation = try XCTUnwrap(chevron.animation(forKey: motionKey))
        for _ in 0..<3 {
            button.needsLayout = true
            button.layoutSubtreeIfNeeded()
            XCTAssertEqual(chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
        }
        button.setFrameSize(NSSize(width: 200, height: 36))
        button.viewDidChangeBackingProperties()
        XCTAssertEqual(chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
        let definition = FluentDropDownButton(title: "Updated", items: [FluentMenuItem("New") {}])
        XCTAssertTrue(definition._updateView(button, in: .init(theme: .custom(colorScheme: .dark), reduceMotion: false)))
        XCTAssertEqual(button.title, "Updated")
        XCTAssertEqual(chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
        XCTAssertEqual(chevron.transform.m42, 1.875, accuracy: 0.001)
        button.reduceMotion = true
        XCTAssertNil(chevron.animation(forKey: motionKey))
        button.reduceMotion = false
        button.layoutSubtreeIfNeeded()
        XCTAssertNil(chevron.animation(forKey: motionKey), "Changing policy must not replay a settled press")
    }

    func testDetachAndHideCancelCapturedPressAndDoNotReplayOnReturn() throws {
        for hide in [false, true] {
            let (window, button, chevron) = try mount()
            defer { window.close() }
            button.mouseDown(with: try pointer(.leftMouseDown, button))
            XCTAssertNotNil(chevron.animation(forKey: motionKey))
            if hide { window.contentView?.isHidden = true } else { button.removeFromSuperview() }
            XCTAssertNil(chevron.animation(forKey: motionKey))
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
            if hide { window.contentView?.isHidden = false } else { window.contentView?.addSubview(button) }
            XCTAssertNil(chevron.animation(forKey: motionKey))
            button.mouseUp(with: try pointer(.leftMouseUp, button))
            drainPendingOpen()
            XCTAssertFalse(button.isFlyoutPresented, "A release after cancellation cannot activate the control")
        }
    }

    func testPendingOpenCannotSurviveDetachHideDisableOrEmptyContent() throws {
        for interruption in 0..<4 {
            let (window, button, _) = try mount()
            defer { window.close() }
            button.reduceMotion = true
            requestOpen(button)
            switch interruption {
            case 0: button.removeFromSuperview(); window.contentView?.addSubview(button)
            case 1: window.contentView?.isHidden = true; window.contentView?.isHidden = false
            case 2: button.isEnabled = false; button.isEnabled = true
            default:
                button.applyDeclarativeConfiguration(from: FluentDropDownButton(title: "Empty", items: []))
                button.applyDeclarativeConfiguration(from: FluentDropDownButton(title: "Again", items: [FluentMenuItem("New") {}]))
            }
            drainPendingOpen()
            XCTAssertFalse(button.isFlyoutPresented, "Pending request survived interruption \(interruption)")
            XCTAssertEqual(button.accessibilityValue() as? String, button.fluentControlString("Closed"))
            if button.isFlyoutPresented { button.isEnabled = false; button.isEnabled = true }
            requestOpen(button)
            waitForUI(button.isFlyoutPresented)
            XCTAssertEqual(button.accessibilityValue() as? String, button.fluentControlString("Open"))
        }
    }

    func testUnattachedOrHiddenButtonNeverReportsAnOpenFlyout() throws {
        let (window, button, _) = try mount()
        defer { window.close() }
        button.removeFromSuperview()
        requestOpen(button)
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertEqual(button.accessibilityValue() as? String, button.fluentControlString("Closed"))
        window.contentView?.addSubview(button)
        button.isHidden = true
        requestOpen(button)
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertEqual(button.accessibilityValue() as? String, button.fluentControlString("Closed"))
    }

    func testSpaceAndReturnActivateOnReleaseAndIgnoreRepeats() throws {
        for code: UInt16 in [49, 36] {
            let (window, button, chevron) = try mount()
            defer { window.close() }
            window.makeFirstResponder(button)
            button.keyDown(with: try key(.keyDown, code, in: window))
            XCTAssertEqual(chevron.transform.m42, 1.875, accuracy: 0.001)
            button.keyDown(with: try key(.keyDown, code, in: window, repeatEvent: true))
            drainPendingOpen()
            XCTAssertFalse(button.isFlyoutPresented, "Default ButtonBase click mode releases before invoking")
            button.keyUp(with: try key(.keyUp, code, in: window))
            waitForUI(button.isFlyoutPresented)
            XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
        }
    }

    func testLosingKeyboardFocusCancelsActivation() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        window.makeFirstResponder(button)
        button.keyDown(with: try key(.keyDown, 49, in: window))
        window.makeFirstResponder(nil)
        button.keyUp(with: try key(.keyUp, 49, in: window))
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
    }

    func testWindowCloseCancelsPendingOpenAndCapturedPress() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.mouseDown(with: try pointer(.leftMouseDown, button))
        requestOpen(button)
        window.close()
        window.orderFront(nil)
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertNil(chevron.animation(forKey: motionKey))
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
        button.mouseUp(with: try pointer(.leftMouseUp, button))
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
    }

    func testLosingFocusAlsoCancelsCapturedPointerPress() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.mouseDown(with: try pointer(.leftMouseDown, button))
        XCTAssertTrue(window.firstResponder === button)
        window.makeFirstResponder(nil)
        button.mouseUp(with: try pointer(.leftMouseUp, button))
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertNil(chevron.animation(forKey: motionKey))
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
    }

    func testValidMouseReleaseOpensOnceAndRepeatedRequestsCanCancel() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.reduceMotion = true
        requestOpen(button)
        requestOpen(button)
        drainPendingOpen()
        XCTAssertFalse(button.isFlyoutPresented)
        button.mouseDown(with: try pointer(.leftMouseDown, button))
        button.mouseUp(with: try pointer(.leftMouseUp, button))
        waitForUI(button.isFlyoutPresented)
        XCTAssertEqual(window.childWindows?.count, 1)
        XCTAssertEqual(chevron.transform.m42, 0, accuracy: 0.001)
        requestOpen(button)
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertEqual(button.accessibilityValue() as? String, button.fluentControlString("Closed"))
    }

    func testExitWhileDisabledDoesNotRestoreStaleHover() throws {
        let (window, button, chevron) = try mount()
        defer { window.close() }
        button.reduceMotion = true
        let normal = chevron.strokeColor
        button.mouseEntered(with: try pointer(.mouseEntered, button))
        let hovered = chevron.strokeColor
        XCTAssertNotEqual(normal, hovered)
        button.isEnabled = false
        button.mouseExited(with: try pointer(.mouseExited, button))
        button.isEnabled = true
        XCTAssertEqual(chevron.strokeColor, normal)
        button.mouseEntered(with: try pointer(.mouseEntered, button))
        button.isEnabled = false
        button.isEnabled = true
        XCTAssertEqual(chevron.strokeColor, hovered, "Keeping the pointer inside should retain hover")
    }

    func testLiveMenuUsesUpdatedItemsThemeAndActionsWithoutReplacingRows() throws {
        let (window, button, _) = try mount()
        defer { window.close() }
        var invoked = ""
        func definition(_ revision: String) -> FluentDropDownButton {
            FluentDropDownButton(title: revision, items: [
                FluentMenuItem(id: "first", "First \(revision)") {},
                FluentMenuItem(id: "second", "Second \(revision)") { invoked = revision }
            ])
        }
        func rows(_ view: NSView) -> [NSView] {
            ([view] + view.subviews.flatMap(rows)).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
        }
        XCTAssertTrue(definition("old")._updateView(button, in: .init(theme: .custom(colorScheme: .light), reduceMotion: true)))
        requestOpen(button)
        waitForUI(button.isFlyoutPresented)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let content = try XCTUnwrap(panel.contentView)
        let oldRows = rows(content)
        XCTAssertEqual(oldRows.count, 2)
        panel.sendEvent(try key(.keyDown, 119, in: panel))
        let responder = panel.firstResponder
        XCTAssertTrue(definition("new")._updateView(button, in: .init(theme: .custom(colorScheme: .dark), reduceMotion: true)))
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.firstResponder === responder)
        XCTAssertTrue(rows(content).last === oldRows.last)
        XCTAssertEqual(rows(content).last?.accessibilityTitle(), "Second new")
        XCTAssertTrue(rows(content).last?.isAccessibilitySelected() == true)
        XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        panel.sendEvent(try key(.keyDown, 36, in: panel))
        XCTAssertEqual(invoked, "new")
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertEqual(button.accessibilityValue() as? String, button.fluentControlString("Closed"))
    }

    func testChevronColorsFollowWinUIResourceRoles() throws {
        for dark in [false, true] {
            for highContrast in [false, true] {
                let (window, button, chevron) = try mount()
                defer { window.close() }
                let theme = FluentTheme(contrast: highContrast ? .high : .standard, colorScheme: dark ? .dark : .light)
                button.reduceMotion = true
                button.theme = theme
                let normal = highContrast ? theme.resolvedHighContrastColor(.controlTextColor) : theme.textSecondary
                let interactive = highContrast ? theme.resolvedHighContrastColor(.selectedContentBackgroundColor) : theme.textTertiary
                XCTAssertEqual(chevron.strokeColor, normal.cgColor)
                button.mouseEntered(with: try pointer(.mouseEntered, button))
                XCTAssertEqual(chevron.strokeColor, interactive.cgColor)
                button.mouseDown(with: try pointer(.leftMouseDown, button))
                XCTAssertEqual(chevron.strokeColor, interactive.cgColor)
                button.isEnabled = false
                XCTAssertEqual(chevron.strokeColor, theme.textDisabled.cgColor)
                XCTAssertNil(chevron.animation(forKey: motionKey))
            }
        }
    }
}
