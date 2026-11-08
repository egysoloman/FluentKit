import XCTest
@testable import FluentKit

@MainActor
final class CommandPointerLifecycleTests: XCTestCase {
    private func mount(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 500, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        view.frame = NSRect(x: 20, y: 100, width: 360, height: 64)
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func mouse(_ type: NSEvent.EventType, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    private func key(_ type: NSEvent.EventType, in window: NSWindow, code: UInt16 = 49, repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: repeated, keyCode: code)!
    }

    private func moreButton(in bar: FluentCommandBar) throws -> NSControl {
        try XCTUnwrap(bar.subviews.first { $0.identifier?.rawValue == "FluentKit.CommandBar.MoreButton" } as? NSControl)
    }

    private func cancel(_ reason: String, view: NSView, window: NSWindow) {
        switch reason {
        case "orderOut":
            window.orderOut(nil)
            window.orderFront(nil)
        case "hide":
            window.contentView?.isHidden = true
            window.contentView?.isHidden = false
        case "reparent":
            let parent = NSView(frame: window.contentView!.bounds)
            window.contentView?.addSubview(parent)
            parent.addSubview(view)
        case "disable":
            (view as? NSControl)?.isEnabled = false
            (view as? NSControl)?.isEnabled = true
        case "deactivate":
            NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
        default:
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    func testAppBarHoverAndPendingPointerReleaseCancelAcrossLifecycle() throws {
        for reason in ["orderOut", "hide", "reparent", "deactivate", "resign"] {
            let button = FluentAppBarToggleButton("Pinned", isChecked: true)
            button.reduceMotion = true
            let window = mount(button)
            defer { window.close() }
            let surface = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
            let original = surface.backgroundColor
            var calls = 0
            button.onClick = { calls += 1 }
            button.mouseEntered(with: mouse(.mouseMoved, in: button))
            button.mouseDown(with: mouse(.leftMouseDown, in: button))
            cancel(reason, view: button, window: window)
            XCTAssertEqual(surface.backgroundColor, original, reason)
            button.mouseUp(with: mouse(.leftMouseUp, in: button))
            XCTAssertEqual(calls, 0, reason)
            XCTAssertTrue(button.isChecked, reason)
            button.mouseDown(with: mouse(.leftMouseDown, in: button))
            button.mouseUp(with: mouse(.leftMouseUp, in: button))
            XCTAssertEqual(calls, 1, "A new press must still work: \(reason)")
            XCTAssertFalse(button.isChecked, reason)
        }
    }

    func testAppBarKeyboardReleaseCannotInvokeAfterCancellation() {
        for reason in ["orderOut", "hide", "reparent", "deactivate", "resign"] {
            let button = FluentAppBarButton("Command")
            button.reduceMotion = true
            let window = mount(button)
            defer { window.close() }
            var calls = 0
            button.onClick = { calls += 1 }
            button.keyDown(with: key(.keyDown, in: window))
            cancel(reason, view: button, window: window)
            button.keyUp(with: key(.keyUp, in: window))
            XCTAssertEqual(calls, 0, reason)
            button.keyDown(with: key(.keyDown, in: window))
            button.keyUp(with: key(.keyUp, in: window))
            XCTAssertEqual(calls, 1, "A new key press must still work: \(reason)")
        }
    }

    func testMoreHoverAndPendingPointerReleaseCancelAcrossLifecycle() throws {
        for reason in ["orderOut", "hide", "deactivate", "resign", "disable"] {
            let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [.init("Command") {}])
            bar.reduceMotion = true
            let window = mount(bar)
            defer { bar.setOpen(false, animated: false); window.close() }
            let more = try moreButton(in: bar)
            let surface = try XCTUnwrap(more.layer?.sublayers?.first)
            more.mouseEntered(with: mouse(.mouseMoved, in: more))
            more.mouseDown(with: mouse(.leftMouseDown, in: more))
            cancel(reason, view: more, window: window)
            XCTAssertEqual(surface.backgroundColor?.alpha, 0, reason)
            more.mouseUp(with: mouse(.leftMouseUp, in: more))
            XCTAssertFalse(bar.isOpen, reason)
            more.mouseDown(with: mouse(.leftMouseDown, in: more))
            more.mouseUp(with: mouse(.leftMouseUp, in: more))
            XCTAssertTrue(bar.isOpen, "A new press must still open the menu: \(reason)")
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            XCTAssertTrue(bar.isOpen, reason)
            XCTAssertGreaterThan(surface.backgroundColor?.alpha ?? 0, 0, "Expanded paint survives input cancellation")
        }
    }

    func testMoreKeyboardReleaseCancelsOnHideDisableAndFocusLoss() throws {
        for reason in ["hide", "disable", "orderOut", "deactivate", "focus"] {
            let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [.init("Command") {}])
            bar.reduceMotion = true
            let window = mount(bar)
            defer { bar.setOpen(false, animated: false); window.close() }
            let more = try moreButton(in: bar)
            window.makeFirstResponder(more)
            more.keyDown(with: key(.keyDown, in: window))
            if reason == "focus" { window.makeFirstResponder(nil) }
            else { cancel(reason, view: more, window: window) }
            more.keyUp(with: key(.keyUp, in: window))
            XCTAssertFalse(bar.isOpen, reason)
        }
    }

    func testPipsWindowVisibilityClearsHoverAndPointerOnlyNavigation() throws {
        let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2,
            previousButtonVisibility: .visibleOnPointerOver, nextButtonVisibility: .visibleOnPointerOver)
        pager.reduceMotion = true
        let window = mount(pager)
        defer { window.close() }
        let pip = try XCTUnwrap(pager.realizedPipButtons[0])
        pager.mouseEntered(with: mouse(.mouseMoved, in: pager))
        pip.mouseEntered(with: mouse(.mouseMoved, in: pip))
        XCTAssertTrue(pip.pointerOver)
        XCTAssertEqual(pager.nextButton.alphaValue, 1)
        window.orderOut(nil)
        window.orderFront(nil)
        XCTAssertFalse(pip.pointerOver)
        XCTAssertEqual(pager.nextButton.alphaValue, 0)
        XCTAssertEqual(pager.selectedPageIndex, 2)
    }

    func testStandalonePipCancelsHoverAndKeyboardCaptureOnWindowHide() {
        for reason in ["orderOut", "deactivate"] {
            let pip = FluentPipsPagerPipButton(index: 2)
            pip.isSelectedPip = true
            pip.reduceMotion = true
            let window = mount(pip)
            defer { window.close() }
            var calls = 0
            pip.onInvoke = { _ in calls += 1 }
            pip.mouseEntered(with: mouse(.mouseMoved, in: pip))
            pip.keyDown(with: key(.keyDown, in: window))
            cancel(reason, view: pip, window: window)
            pip.keyUp(with: key(.keyUp, in: window))
            XCTAssertFalse(pip.pointerOver, reason)
            XCTAssertEqual(calls, 0, reason)
            XCTAssertTrue(pip.isSelectedPip)
            pip.keyDown(with: key(.keyDown, in: window))
            pip.keyUp(with: key(.keyUp, in: window))
            XCTAssertEqual(calls, 1, reason)
        }
    }

    func testEnteringDisabledPagerNavigationReleasesTheOldHover() throws {
        let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 4,
                                   previousButtonVisibility: .visible, nextButtonVisibility: .visible)
        pager.reduceMotion = true
        let window = mount(pager)
        defer { window.close() }
        let pip = try XCTUnwrap(pager.realizedPipButtons[3])
        pip.mouseEntered(with: mouse(.mouseMoved, in: pip))
        XCTAssertTrue(pip.pointerOver)
        XCTAssertFalse(pager.nextButton.isEnabled)
        pager.nextButton.mouseEntered(with: mouse(.mouseMoved, in: pager.nextButton))
        XCTAssertFalse(pip.pointerOver)
        XCTAssertFalse(pager.nextButton.pointerOver)
        XCTAssertEqual(pager.selectedPageIndex, 4)
    }

    func testCommandHoverOwnershipMovesAcrossDisabledCommandsAndMore() throws {
        let bar = FluentCommandBar(primaryCommands: [
            .init("First") {}, .init("Disabled", isEnabled: false) {}
        ], secondaryCommands: [.init("Overflow") {}])
        bar.reduceMotion = true
        let window = mount(bar)
        defer { window.close() }
        let first = try XCTUnwrap(bar.primaryCommandViews[0] as? FluentAppBarButton)
        let disabled = try XCTUnwrap(bar.primaryCommandViews[1] as? FluentAppBarButton)
        let more = try moreButton(in: bar)
        let firstSurface = try XCTUnwrap(first.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
        let disabledSurface = try XCTUnwrap(disabled.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
        let moreSurface = try XCTUnwrap(more.layer?.sublayers?.first)
        first.mouseEntered(with: mouse(.mouseMoved, in: first))
        XCTAssertGreaterThan(firstSurface.backgroundColor?.alpha ?? 0, 0)
        disabled.mouseEntered(with: mouse(.mouseMoved, in: disabled))
        XCTAssertEqual(firstSurface.backgroundColor?.alpha, 0)
        XCTAssertEqual(disabledSurface.backgroundColor?.alpha, 0)
        more.mouseEntered(with: mouse(.mouseMoved, in: more))
        first.mouseEntered(with: mouse(.mouseMoved, in: first))
        more.mouseExited(with: mouse(.mouseMoved, in: more))
        XCTAssertEqual(moreSurface.backgroundColor?.alpha, 0)
        XCTAssertGreaterThan(firstSurface.backgroundColor?.alpha ?? 0, 0)
    }

    func testMoreKeyboardActivationRequiresAMatchingFreshPress() throws {
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [.init("Command") {}])
        bar.reduceMotion = true
        let window = mount(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        let more = try moreButton(in: bar)
        more.keyDown(with: key(.keyDown, in: window, repeated: true))
        more.keyUp(with: key(.keyUp, in: window))
        XCTAssertFalse(bar.isOpen)
        more.keyDown(with: key(.keyDown, in: window))
        more.keyUp(with: key(.keyUp, in: window, code: 36))
        XCTAssertFalse(bar.isOpen)
        more.keyUp(with: key(.keyUp, in: window))
        XCTAssertTrue(bar.isOpen)
        more.keyUp(with: key(.keyUp, in: window))
        XCTAssertTrue(bar.isOpen, "A repeated release cannot toggle the popup")
    }

    func testAppBarCancellationRemovesRunningHoverAndPressAnimations() throws {
        let button = FluentAppBarToggleButton("Pinned", isChecked: true)
        button.reduceMotion = false
        let window = mount(button)
        defer { window.close() }
        let surface = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
        surface.speed = 0
        surface.timeOffset = surface.convertTime(CACurrentMediaTime(), from: nil)
        button.mouseEntered(with: mouse(.mouseMoved, in: button))
        button.mouseDown(with: mouse(.leftMouseDown, in: button))
        XCTAssertNotNil(surface.animationKeys())
        window.orderOut(nil)
        window.orderFront(nil)
        XCTAssertNil(surface.animationKeys())
        XCTAssertTrue(button.isChecked)
    }
}
