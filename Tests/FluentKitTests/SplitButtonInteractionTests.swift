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
    @MainActor func testMouseAndTouchPaintCorrectRegionsInBothDirections() throws {
        func layer(_ name: String, in root: CALayer) -> CALayer? {
            if root.name == name { return root }
            return root.sublayers?.compactMap { layer(name, in: $0) }.first
        }
        for rtl in [false, true] { for checked in [false, true] {
            let button = FluentToggleSplitButton("Save", isChecked: checked, items: [FluentMenuItem("Copy") {}])
            button.theme = .custom(colorScheme: .light, materialEffectsEnabled: false); button.reduceMotion = true
            button.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            let window = mount(button); defer { window.close() }
            let primary = try XCTUnwrap(layer("FluentKit.SplitButton.Primary", in: button.layer!))
            let secondary = try XCTUnwrap(layer("FluentKit.SplitButton.Secondary", in: button.layer!))
            let secondaryBorder = try XCTUnwrap(layer("FluentKit.SplitButton.SecondaryElevationBorder", in: button.layer!) as? CAGradientLayer)
            let originalBorder = secondaryBorder.colors as? [CGColor]
            let point = NSPoint(x: rtl ? 90 : 30, y: 16)
            button.mouseDown(with: try mouse(.leftMouseDown, at: point, in: button))
            XCTAssertNotEqual(primary.backgroundColor, secondary.backgroundColor)
            XCTAssertEqual(secondaryBorder.colors as? [CGColor], originalBorder, "pressing primary must retain secondary elevation")
            button.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: -10, y: 16), in: button))
            let secondaryPoint = NSPoint(x: rtl ? 15 : 145, y: 16)
            button.mouseDown(with: try mouse(.leftMouseDown, at: secondaryPoint, in: button))
            XCTAssertNotEqual(primary.backgroundColor, secondary.backgroundColor)
            let primaryBorder = try XCTUnwrap(layer("FluentKit.SplitButton.ElevationBorder", in: button.layer!) as? CAGradientLayer)
            XCTAssertEqual(primaryBorder.colors as? [CGColor], originalBorder)
            button.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: -10, y: 16), in: button))
            let cg = try XCTUnwrap(try mouse(.leftMouseDown, at: point, in: button).cgEvent)
            cg.setIntegerValueField(.mouseEventSubtype, value: Int64(NSEvent.EventSubtype.touch.rawValue))
            let touch = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertTrue(FluentInputDeviceTracker.isTouch(touch))
            button.mouseDown(with: touch)
            XCTAssertEqual(primary.backgroundColor, secondary.backgroundColor)
            XCTAssertEqual(primary.backgroundColor, (checked ? button.theme.accentFillTertiary : button.theme.controlFillTertiary).cgColor)
            button.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: -10, y: 16), in: button))
            button.mouseMoved(with: try mouse(.mouseMoved, at: point, in: button))
            XCTAssertNotEqual(primary.backgroundColor, secondary.backgroundColor, "mouse hover resumes after touch")
        }}
    }

    @MainActor func testPointerCaptureCancellationAndKeyboardDismissal() throws {
        var count = 0
        let button = FluentSplitButton("Save", items: [FluentMenuItem("Copy") {}]) { count += 1 }
        button.reduceMotion = true
        let window = mount(button); defer { window.close() }
        button.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 30, y: 16), in: button))
        button.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: 145, y: 16), in: button))
        button.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: 145, y: 16), in: button))
        XCTAssertEqual(count, 0); XCTAssertFalse(button.isFlyoutPresented)
        button.keyDown(with: try key(.keyDown, code: 49, window: window))
        button.isHidden = true; button.isHidden = false
        button.keyUp(with: try key(.keyUp, code: 49, window: window))
        XCTAssertEqual(count, 0)
        button.keyUp(with: try key(.keyUp, code: 125, window: window, modifiers: .option))
        XCTAssertTrue(button.isFlyoutPresented)
        let panel = try XCTUnwrap(window.childWindows?.first)
        panel.sendEvent(try key(.keyDown, code: 53, window: panel))
        XCTAssertFalse(button.isFlyoutPresented)
        button.showFlyout(); button.superview?.isHidden = true
        XCTAssertFalse(button.isFlyoutPresented)
    }

    @MainActor func testObservationReuseAndStaleBackgroundDelivery() throws {
        let identity = NSObject()
        var model = false, subscriptions = 0, removals = 0
        var callback: ((Bool) -> Void)?
        let binding = FluentBinding<Bool>(get: { model }, set: { model = $0 }, observe: {
            subscriptions += 1; callback = $0; return UUID()
        }, removeObserver: { _ in removals += 1 }, observationIdentity: ObjectIdentifier(identity))
        let context = FluentRenderContext(reduceMotion: true)
        func content(_ binding: FluentBinding<Bool>) -> FluentToggleSplitButtonView {
            FluentToggleSplitButtonView("Favorite", isChecked: binding) { FluentMenuItem("Manage") {} }
        }
        let host = content(binding)._makeView(in: context)
        let window = mount(host); defer { window.close() }
        let button = try XCTUnwrap(all(host).first { $0 is FluentToggleSplitButton } as? FluentToggleSplitButton)
        for _ in 0..<30 { XCTAssertTrue(content(binding)._updateView(host, in: context)) }
        XCTAssertEqual(subscriptions, 1); XCTAssertEqual(removals, 0)
        model = true
        let oldCallback = try XCTUnwrap(callback)
        DispatchQueue.global().sync { oldCallback(true) }
        let fresh = FluentState(wrappedValue: false)
        XCTAssertTrue(content(fresh.projectedValue)._updateView(host, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertFalse(button.isChecked); XCTAssertEqual(removals, 1)
        oldCallback(true)
        XCTAssertFalse(button.isChecked)
        fresh.wrappedValue = true
        XCTAssertTrue(button.isChecked)
    }

    @MainActor func testLiveThemeEmptyItemsAndWindowMovement() throws {
        let button = FluentSplitButton("Save", items: [FluentMenuItem(id: "copy", "Copy") {}])
        button.reduceMotion = true
        let window = mount(button); defer { window.close() }
        button.showFlyout(); let panel = try XCTUnwrap(window.childWindows?.first)
        button.theme = .custom(colorScheme: .dark, materialEffectsEnabled: false)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual(panel.appearance?.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)
        let origin = panel.frame.origin
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 20, y: window.frame.minY + 20))
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)
        XCTAssertEqual(panel.frame.minX, origin.x + 20, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, origin.y + 20, accuracy: 0.5)
        button.items = []
        XCTAssertFalse(button.isFlyoutPresented); XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(button.accessibilityPerformShowMenu())
    }

    @MainActor func testCheckedCallbackMayDisableControlWithoutCancelingAcceptedClick() {
        var events: [String] = []
        let button = FluentToggleSplitButton("Favorite", items: [])
        button.onIsCheckedChanged = { value in
            events.append("checked-\(value)")
            button.isEnabled = false
        }
        button.onPrimaryAction = { events.append("click-\(button.isChecked)") }
        button.invokePrimaryAction()
        XCTAssertEqual(events, ["checked-true", "click-true"])
        button.invokePrimaryAction()
        XCTAssertEqual(events.count, 2, "a subsequent disabled invocation is rejected")
        button.onIsCheckedChanged = nil; button.onPrimaryAction = nil
    }

}
