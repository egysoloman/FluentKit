import XCTest
@testable import FluentKit

final class SplitButtonInteractionTests: XCTestCase {
    @MainActor private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @MainActor private func mount(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 500, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 240)); window.contentView = stage
        view.translatesAutoresizingMaskIntoConstraints = true; stage.addSubview(view)
        view.frame = NSRect(x: 40, y: 140, width: 160, height: 32)
        window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        return window
    }
    @MainActor private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in button: FluentSplitButton) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: button.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: button.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }
    @MainActor private func key(_ type: NSEvent.EventType, code: UInt16, window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }
    @MainActor private func rows(_ panel: NSWindow) -> [NSView] { all(panel.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } }

    @MainActor func testHitTestingAtNonzeroOriginAndHiddenState() throws {
        var count = 0
        let button = FluentSplitButton("Save", items: [FluentMenuItem("Save as") {}]) { count += 1 }
        let window = mount(button); defer { window.close() }
        let primary = NSPoint(x: 30, y: 16)
        XCTAssertTrue(window.contentView?.hitTest(button.convert(primary, to: button.superview)) === button)
        let target = try XCTUnwrap(window.contentView?.hitTest(button.convert(primary, to: button.superview)))
        target.mouseDown(with: try mouse(.leftMouseDown, at: primary, in: button))
        target.mouseUp(with: try mouse(.leftMouseUp, at: primary, in: button))
        XCTAssertEqual(count, 1)
        button.isHidden = true
        XCTAssertNil(button.hitTest(button.convert(primary, to: button.superview)))
    }

    @MainActor func testOpenMenuRefreshKeepsRowsAndInvokesLatestAction() throws {
        var actions: [String] = []
        func content(_ version: String) -> FluentSplitButtonView {
            FluentSplitButtonView("Save", action: { actions.append("primary-" + version) }) {
                FluentMenuItem(id: "save", "Save " + version) { actions.append(version) }
                FluentMenuItem(id: "export", "Export") {}
            }
        }
        let context = FluentRenderContext(reduceMotion: true)
        let button = try XCTUnwrap(content("old")._makeView(in: context) as? FluentSplitButton)
        let window = mount(button); defer { window.close() }
        button.showFlyout()
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = rows(panel)[0]
        for _ in 0..<5 { XCTAssertTrue(content("new")._updateView(button, in: context)) }
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(rows(panel).first === row)
        XCTAssertEqual(row.accessibilityTitle(), "Save new")
        panel.sendEvent(try key(.keyDown, code: 125, window: panel))
        panel.sendEvent(try key(.keyDown, code: 36, window: panel))
        XCTAssertEqual(actions, ["new"])
        XCTAssertFalse(button.isFlyoutPresented)
    }

    @MainActor func testShowIsIdempotentAndPlacementFollowsAnchor() throws {
        let button = FluentSplitButton("Save", items: [FluentMenuItem("Save as") {}])
        button.reduceMotion = true
        let window = mount(button); defer { window.close() }
        button.showFlyout(); let panel = try XCTUnwrap(window.childWindows?.first)
        button.showFlyout()
        XCTAssertTrue(button.isFlyoutPresented)
        XCTAssertTrue(window.childWindows?.first === panel)
        if !button.isFlyoutPresented { button.showFlyout() }
        let current = try XCTUnwrap(window.childWindows?.first)
        let original = current.frame.origin
        button.setFrameOrigin(NSPoint(x: 70, y: 160)); button.layoutSubtreeIfNeeded()
        XCTAssertEqual(current.frame.minX, original.x + 30, accuracy: 0.5)
        XCTAssertEqual(current.frame.minY, original.y + 20, accuracy: 0.5)
        let beforePlacement = current.frame.minY
        button.flyoutPlacement = .comboBoxSelection
        XCTAssertNotEqual(current.frame.minY, beforePlacement)
    }

    @MainActor func testDetachAndWindowCloseDismissMenusAndCancelPointerPress() throws {
        var count = 0
        let button = FluentSplitButton("Save", items: [FluentMenuItem("Save as") {}]) { count += 1 }
        let window = mount(button); defer { window.close() }
        button.showFlyout(); let panel = try XCTUnwrap(window.childWindows?.first)
        button.removeFromSuperview()
        XCTAssertFalse(button.isFlyoutPresented); XCTAssertFalse(panel.isVisible)
        window.contentView?.addSubview(button)
        let down = try mouse(.leftMouseDown, at: NSPoint(x: 30, y: 16), in: button)
        let up = try mouse(.leftMouseUp, at: NSPoint(x: 30, y: 16), in: button)
        button.mouseDown(with: down); button.removeFromSuperview(); button.mouseUp(with: up)
        XCTAssertEqual(count, 0)
        window.contentView?.addSubview(button); button.showFlyout()
        window.close()
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testDisabledInvocationAndAccessibilityMenuActionAreIndependent() throws {
        var count = 0
        let button = FluentToggleSplitButton("Favorite", items: [FluentMenuItem("Manage") {}]) { count += 1 }
        let window = mount(button); defer { window.close() }
        button.isEnabled = false; button.invokePrimaryAction()
        XCTAssertFalse(button.isChecked); XCTAssertEqual(count, 0)
        XCTAssertFalse(button.accessibilityPerformShowMenu())
        button.isEnabled = true
        XCTAssertTrue(button.accessibilityPerformShowMenu())
        XCTAssertTrue(button.isAccessibilityExpanded())
        XCTAssertFalse(button.isChecked); XCTAssertEqual(count, 0)
        button.hideFlyout(animated: false)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertTrue(button.isChecked); XCTAssertEqual(count, 1)
    }

    @MainActor func testDetachedBindingDeliveryAndRejectingSetterCannotChangeCurrentToggle() throws {
        let old = FluentState(wrappedValue: false), new = FluentState(wrappedValue: false)
        func content(_ binding: FluentBinding<Bool>) -> FluentToggleSplitButtonView {
            FluentToggleSplitButtonView("Favorite", isChecked: binding) { FluentMenuItem("Manage") {} }
        }
        let context = FluentRenderContext(reduceMotion: true)
        let host = content(old.projectedValue)._makeView(in: context)
        let window = mount(host); defer { window.close() }
        let button = try XCTUnwrap(all(host).first { $0 is FluentToggleSplitButton } as? FluentToggleSplitButton)
        old.wrappedValue = true
        XCTAssertTrue(content(new.projectedValue)._updateView(host, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertFalse(button.isChecked); XCTAssertFalse(new.wrappedValue)
        var writes = 0
        let rejecting = FluentBinding<Bool>(get: { false }, set: { _ in writes += 1 })
        XCTAssertTrue(content(rejecting)._updateView(host, in: context))
        button.invokePrimaryAction()
        XCTAssertEqual(writes, 1); XCTAssertFalse(button.isChecked)
    }
}
