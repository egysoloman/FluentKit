import XCTest
@testable import FluentKit

@MainActor final class MenuBarInteractionTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        let bar: FluentMenuBar
        var root: NSWindow? { window.childWindows?.first }
        var controls: [NSView] { bar.itemControlViews }
        init(dark: Bool = false, rtl: Bool = false) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 700, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = stage
            bar = FluentMenuBar(items: [
                FluentMenuBarItem(id: "file", "File", accessKey: "f", items: [
                    FluentMenuItem("Disabled", isEnabled: false) {}, .separator, FluentMenuItem("Open") {}]),
                FluentMenuBarItem(id: "view", "View", accessKey: "v", items: [FluentMenuItem("Zoom") {}]),
                FluentMenuBarItem(id: "disabled", "Disabled", isEnabled: false, items: [FluentMenuItem("Unavailable") {}])
            ])
            bar.theme = .custom(contrast: .standard, colorScheme: dark ? .dark : .light)
            bar.reduceMotion = true
            bar.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            bar.frame = NSRect(x: 20, y: 280, width: 600, height: 40)
            stage.addSubview(bar)
            window.makeKeyAndOrderFront(nil); bar.layoutSubtreeIfNeeded()
            FluentInputDeviceTracker.shared.record(.mouse, in: window)
        }
        func close() { bar.closeMenu(); window.close() }
        func pointer(_ view: NSView, _ entering: Bool) {
            let event = NSEvent.enterExitEvent(with: entering ? .mouseEntered : .mouseExited,
                location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil)!
            if entering { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
        }
        func mouse(_ view: NSView, type: NSEvent.EventType) {
            let event = NSEvent.mouseEvent(with: type,
                location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        func key(_ responder: NSResponder, code: UInt16, in panel: NSWindow? = nil, repeating: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: (panel ?? window).windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: repeating, keyCode: code)!
            if panel != nil { NSApp.sendEvent(event) }
            else { responder.keyDown(with: event) }
        }
        func selectedRows() -> [String] {
            guard let root else { return [] }
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            return all(root.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" && $0.isAccessibilitySelected() }
                .compactMap { $0.accessibilityTitle() }
        }
    }

    private func alpha(_ view: NSView) throws -> CGFloat {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 4)).alphaComponent
    }

    func testOnlyTheLatestTopLevelItemKeepsHoverAfterAMissedExit() throws {
        for dark in [false, true] {
            let f = Fixture(dark: dark); defer { f.close() }
            let a = f.controls[0], b = f.controls[1]
            f.pointer(a, true); XCTAssertGreaterThan(try alpha(a), 0)
            f.pointer(b, true)
            XCTAssertEqual(try alpha(a), 0); XCTAssertGreaterThan(try alpha(b), 0)
            f.pointer(a, false)
            XCTAssertGreaterThan(try alpha(b), 0)
            XCTAssertFalse(f.bar.isFlyoutOpen)
        }
    }

    func testEnteringDisabledTopLevelClearsOldHoverWithoutOpeningIt() throws {
        let f = Fixture(); defer { f.close() }
        f.pointer(f.controls[0], true); f.pointer(f.controls[2], true)
        XCTAssertEqual(try alpha(f.controls[0]), 0)
        XCTAssertEqual(try alpha(f.controls[2]), 0)
        XCTAssertFalse(f.bar.isFlyoutOpen)
    }

    func testNativeWindowAndApplicationCancellationClearHover() throws {
        for name in [NSWindow.didResignKeyNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willCloseNotification, NSApplication.willResignActiveNotification] {
            let f = Fixture(); defer { f.close() }
            f.pointer(f.controls[0], true)
            NotificationCenter.default.post(name: name, object: name == NSApplication.willResignActiveNotification ? NSApp : f.window)
            XCTAssertEqual(try alpha(f.controls[0]), 0, name.rawValue)
        }
    }

    func testHiddenBarOrAncestorCannotRetainHoverAfterShowingAgain() throws {
        for ancestor in [false, true] {
            let f = Fixture(); defer { f.close() }
            f.pointer(f.controls[0], true)
            let hidden = ancestor ? f.stage : f.bar
            hidden.isHidden = true; hidden.isHidden = false
            XCTAssertEqual(try alpha(f.controls[0]), 0)
        }
    }

    func testSameWindowReparentClearsPointerState() throws {
        let f = Fixture(); defer { f.close() }
        let other = NSView(frame: f.stage.bounds); f.stage.addSubview(other)
        f.pointer(f.controls[0], true)
        other.addSubview(f.bar)
        XCTAssertEqual(try alpha(f.controls[0]), 0)
        XCTAssertFalse(f.bar.isFlyoutOpen)
    }

    func testClosingAfterPointerDownClearsPressAndRejectsOldDrag() throws {
        let f = Fixture(); defer { f.close() }
        let control = f.controls[0]
        f.mouse(control, type: .leftMouseDown); XCTAssertTrue(f.bar.isFlyoutOpen)
        f.pointer(control, false); f.bar.closeMenu()
        XCTAssertEqual(try alpha(control), 0)
        f.mouse(control, type: .leftMouseDragged)
        XCTAssertEqual(try alpha(control), 0)
        f.mouse(control, type: .leftMouseUp)
        XCTAssertFalse(f.bar.isFlyoutOpen)
    }

    func testPointerOpeningDoesNotInheritOldKeyboardFocus() throws {
        let f = Fixture(); defer { f.close() }
        FluentInputDeviceTracker.shared.record(.keyboard, in: f.window)
        f.mouse(f.controls[0], type: .leftMouseDown)
        XCTAssertTrue(f.bar.isFlyoutOpen)
        XCTAssertTrue(f.selectedRows().isEmpty)
    }

    func testKeyboardOpeningAfterMouseSelectsFirstEnabledRow() throws {
        for code: UInt16 in [125, 36, 49] {
            let f = Fixture(); defer { f.close() }
            f.key(f.controls[0], code: code)
            XCTAssertEqual(f.selectedRows(), ["Open"])
        }
    }

    func testAccessibilityOpeningAfterMouseSelectsFirstEnabledRow() throws {
        let f = Fixture(); defer { f.close() }
        XCTAssertTrue(f.controls[0].accessibilityPerformPress())
        XCTAssertEqual(f.selectedRows(), ["Open"])
    }

    func testAccessKeyOpeningAfterMouseSelectsFirstEnabledRow() throws {
        let f = Fixture(); defer { f.close() }
        XCTAssertTrue(f.bar.performAccessKey("f"))
        XCTAssertEqual(f.selectedRows(), ["Open"])
    }

    func testKeyboardCrossingFromPointerMenuSelectsFirstRowInTheNewRoot() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            f.bar.openItem(at: 0)
            let root = try XCTUnwrap(f.root)
            f.key(try XCTUnwrap(root.firstResponder), code: rtl ? 123 : 124, in: root)
            XCTAssertEqual(f.bar.openItemIndex, 1)
            XCTAssertEqual(f.selectedRows(), ["Zoom"])
        }
    }

    func testRepeatedOpeningKeysKeepTheSamePanelAndSelection() throws {
        let f = Fixture(); defer { f.close() }
        FluentInputDeviceTracker.shared.record(.keyboard, in: f.window)
        f.key(f.controls[0], code: 125)
        let root = try XCTUnwrap(f.root)
        f.key(f.controls[0], code: 125, repeating: true)
        XCTAssertTrue(f.root === root)
        f.key(f.controls[0], code: 36)
        XCTAssertTrue(f.root === root)
        XCTAssertEqual(f.selectedRows(), ["Open"])
    }

    func testPointerHandoffFromKeyboardMenuDoesNotSelectARow() throws {
        let f = Fixture(); defer { f.close() }
        FluentInputDeviceTracker.shared.record(.keyboard, in: f.window)
        f.bar.openItem(at: 0)
        XCTAssertEqual(f.selectedRows(), ["Open"])
        f.pointer(f.controls[1], true)
        XCTAssertEqual(f.bar.openItemIndex, 1)
        XCTAssertTrue(f.selectedRows().isEmpty)
    }

    func testRemovedControlCannotInvokeAReplacementItem() throws {
        let f = Fixture(); defer { f.close() }
        let removed = f.controls[0]
        f.bar.items = Array(f.bar.items.dropFirst())
        _ = removed.accessibilityPerformPress()
        XCTAssertFalse(f.bar.isFlyoutOpen)
    }

    func testApplicationDispatchedOpeningKeySelectsFirstRow() throws {
        let f = Fixture(); defer { f.close() }
        _ = FluentInputDeviceTracker.shared.lastDeviceType(in: f.window)
        f.window.makeFirstResponder(f.controls[0])
        f.key(f.controls[0], code: 125, in: f.window)
        XCTAssertEqual(f.selectedRows(), ["Open"])
    }

    func testRetainedHoveredItemSurvivesOrdinaryUpdatesWithoutDuplicatingHover() throws {
        let f = Fixture(); defer { f.close() }
        let control = f.controls[0]
        f.pointer(control, true)
        let initial = try alpha(control)
        f.bar.items = f.bar.items
        XCTAssertTrue(f.controls[0] === control)
        XCTAssertEqual(try alpha(control), initial)
        f.bar.items.reverse(); f.bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(f.controls.last === control)
        f.pointer(f.controls[1], true)
        XCTAssertEqual(try alpha(control), 0)
        XCTAssertGreaterThan(try alpha(f.controls[1]), 0)
    }

    func testSwitchingAnOpenTopLevelClearsPreviousPressAndHover() throws {
        let f = Fixture(); defer { f.close() }
        let old = f.controls[0], next = f.controls[1]
        f.pointer(old, true); f.mouse(old, type: .leftMouseDown)
        let root = try XCTUnwrap(f.root)
        f.pointer(next, true)
        XCTAssertEqual(f.bar.openItemIndex, 1); XCTAssertFalse(root.isVisible)
        XCTAssertEqual(try alpha(old), 0)
        XCTAssertFalse(old.isAccessibilityExpanded()); XCTAssertTrue(next.isAccessibilityExpanded())
        f.mouse(old, type: .leftMouseDragged)
        XCTAssertEqual(try alpha(old), 0)
    }

    func testHostKeyHandoffReleasesPointerWithoutClosingItsMenu() throws {
        let f = Fixture(); defer { f.close() }
        f.mouse(f.controls[0], type: .leftMouseDown)
        let root = try XCTUnwrap(f.root)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
        XCTAssertTrue(f.root === root)
        XCTAssertTrue(f.controls[0].isAccessibilityExpanded())
        f.bar.closeMenu(); f.mouse(f.controls[0], type: .leftMouseDragged)
        XCTAssertEqual(try alpha(f.controls[0]), 0)
    }

    func testHiddenDetachedAndDisabledItemsRejectStaleOpeningCommands() throws {
        for state in ["hidden", "detached", "disabled"] {
            let f = Fixture(); defer { f.close() }
            let control = f.controls[0]
            f.mouse(control, type: .leftMouseDown)
            switch state {
            case "hidden": f.bar.isHidden = true
            case "detached": f.bar.removeFromSuperview()
            default:
                f.bar.items = [FluentMenuBarItem(id: "file", "File", isEnabled: false, items: f.bar.items[0].items)]
            }
            f.key(control, code: 125)
            XCTAssertFalse(control.accessibilityPerformPress())
            XCTAssertFalse(f.bar.isFlyoutOpen)
            if state == "hidden" { f.bar.isHidden = false }
            if state == "detached" { f.stage.addSubview(f.bar) }
            f.mouse(control, type: .leftMouseDragged)
            XCTAssertEqual(try alpha(control), 0)
        }
    }

    func testPointerPressAcquiresHoverEvenWithoutAnEnterEvent() throws {
        let f = Fixture(); defer { f.close() }
        f.pointer(f.controls[0], true)
        f.mouse(f.controls[1], type: .leftMouseDown)
        XCTAssertEqual(f.bar.openItemIndex, 1)
        XCTAssertEqual(try alpha(f.controls[0]), 0)
    }

    func testInputOriginNotificationReorderKeepsTheOriginalTarget() throws {
        for action in ["pointer", "keyboard", "access", "hover"] {
            let f = Fixture(); defer { f.close() }
            FluentInputDeviceTracker.shared.record(action == "pointer" || action == "hover" ? .keyboard : .mouse, in: f.window)
            if action == "hover" { f.bar.openItem(at: 0) }
            let target = f.controls[action == "hover" ? 1 : 0]
            var changed = false
            let observer = NotificationCenter.default.addObserver(forName: FluentInputDeviceTracker.didChangeNotification,
                object: f.window, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        guard !changed else { return }; changed = true
                        let old = f.bar.items
                        f.bar.items = [old[1], old[0], old[2]]
                    }
                }
            defer { NotificationCenter.default.removeObserver(observer) }
            switch action {
            case "pointer": f.mouse(target, type: .leftMouseDown)
            case "keyboard": f.key(target, code: 125)
            case "access": XCTAssertTrue(f.bar.performAccessKey("f"))
            default: f.pointer(target, true)
            }
            XCTAssertTrue(changed)
            XCTAssertEqual(f.bar.openItemIndex, action == "hover" ? 0 : 1, action)
            XCTAssertTrue(f.controls[f.bar.openItemIndex!] === target)
        }
    }

    func testInputOriginCallbackReplacementSupersedesOldRootNavigation() throws {
        let f = Fixture(); defer { f.close() }
        f.bar.openItem(at: 0)
        let old = try XCTUnwrap(f.root)
        var replacement: NSWindow?
        let observer = NotificationCenter.default.addObserver(forName: FluentInputDeviceTracker.didChangeNotification,
            object: f.window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard replacement == nil else { return }
                    f.bar.openItem(at: 1)
                    replacement = f.root
                }
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        f.key(try XCTUnwrap(old.firstResponder), code: 124, in: old)
        XCTAssertNotNil(replacement)
        XCTAssertTrue(f.root === replacement)
        XCTAssertEqual(f.bar.openItemIndex, 1)
    }
}
