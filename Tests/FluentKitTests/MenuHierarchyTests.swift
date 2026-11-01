import XCTest
@testable import FluentKit

@MainActor
final class MenuHierarchyTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let anchor = NSView(frame: NSRect(x: 200, y: 230, width: 140, height: 32))
        let menu: FluentMenuFlyout
        let rtl: Bool
        var root: NSWindow? { window.childWindows?.first { $0.isVisible } }
        init(rtl: Bool = false, keyboard: Bool = false, items: [FluentMenuItem]? = nil) {
            _ = NSApplication.shared
            self.rtl = rtl
            window = NSWindow(contentRect: NSRect(x: 140, y: 160, width: 650, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(anchor)
            anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            window.makeKeyAndOrderFront(nil)
            menu = FluentMenuFlyout(items: items ?? [
                FluentMenuItem(id: "branch", "Branch", submenu: [
                    FluentMenuItem("Disabled", isEnabled: false) {}, .separator,
                    FluentMenuItem(id: "deep", "Deep", submenu: [FluentMenuItem("Leaf") {}], action: {}),
                    FluentMenuItem("Other leaf") {}
                ], action: {}), FluentMenuItem("Sibling") {}
            ], reduceMotion: true)
            FluentInputDeviceTracker.shared.record(keyboard ? .keyboard : .mouse, in: window)
            menu.present(relativeTo: anchor)
        }
        func close() { menu.dismiss(animated: false); window.close() }
        func key(_ code: UInt16, in panel: NSWindow, text: String = "") {
            panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!)
        }
        func rows(_ panel: NSWindow) -> [NSView] {
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            return panel.contentView.map { all($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } } ?? []
        }
        func open(_ panel: NSWindow) { key(115, in: panel); key(rtl ? 123 : 124, in: panel) }
    }

    private func drainSubmenuDelay() {
        // Observe beyond the documented 180ms hover delay; this checks absence of a timer
        // side effect, rather than assuming an animation has finished at a fixed time.
        RunLoop.main.run(until: Date().addingTimeInterval(0.26))
    }

    func testKeyboardSelectionNeverStartsThePointerOpenDelay() throws {
        for rtl in [false, true] { for command in ["home", "end", "down", "up", "typeahead"] {
            let f = Fixture(rtl: rtl, items: [FluentMenuItem("Branch", submenu: [FluentMenuItem("Leaf") {}], action: {})])
            defer { f.close() }
            let root = try XCTUnwrap(f.root)
            f.key(["home": 115, "end": 119, "down": 125, "up": 126, "typeahead": 11][command]!, in: root,
                text: command == "typeahead" ? "b" : "")
            drainSubmenuDelay()
            XCTAssertTrue(root.childWindows?.isEmpty ?? true, command)
            XCTAssertTrue(f.rows(root)[0].isAccessibilitySelected(), command)
        } }
    }

    func testKeyboardOpenFocusesFirstEnabledChildWithoutOpeningGrandchild() throws {
        for rtl in [false, true] { for command: UInt16 in [rtl ? 123 : 124, 36, 49] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = try XCTUnwrap(f.root)
            f.key(115, in: root); f.key(command, in: root)
            let child = try XCTUnwrap(root.childWindows?.first)
            XCTAssertEqual(f.rows(child).filter { $0.isAccessibilitySelected() }.map { $0.accessibilityTitle() }, ["Deep"])
            drainSubmenuDelay()
            XCTAssertTrue(child.childWindows?.isEmpty ?? true)
        } }
    }

    func testEscapeClosesOneLevelAndReturnsFocusToItsSurvivingOwner() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = try XCTUnwrap(f.root)
            let canTestSystemKeyWindow = root.isKeyWindow
            f.open(root)
            let child = try XCTUnwrap(root.childWindows?.first); f.open(child)
            let rootResponder = root.firstResponder, childResponder = child.firstResponder
            let grandchild = try XCTUnwrap(child.childWindows?.first)
            f.key(53, in: grandchild)
            XCTAssertTrue(f.root === root); XCTAssertTrue(root.childWindows?.first === child)
            XCTAssertFalse(grandchild.isVisible)
            XCTAssertTrue(child.firstResponder === childResponder)
            if canTestSystemKeyWindow { XCTAssertTrue(child.isKeyWindow) }
            XCTAssertTrue(f.rows(child).first { $0.accessibilityTitle() == "Deep" }!.isAccessibilitySelected())
            f.key(53, in: child)
            XCTAssertTrue(f.root === root); XCTAssertTrue(root.childWindows?.isEmpty ?? true)
            XCTAssertTrue(root.firstResponder === rootResponder)
            if canTestSystemKeyWindow { XCTAssertTrue(root.isKeyWindow) }
            XCTAssertTrue(f.rows(root)[0].isAccessibilitySelected())
            f.key(53, in: root)
            XCTAssertFalse(f.menu.isPresented)
        }
    }

    func testBackArrowAtStandaloneRootDoesNotDismissIt() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = try XCTUnwrap(f.root)
            f.key(115, in: root); f.key(rtl ? 124 : 123, in: root)
            XCTAssertTrue(f.root === root)
        }
    }

    func testKeyboardBackFromPointerOpenedChildRestoresItsOwnerSelection() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = try XCTUnwrap(f.root)
            XCTAssertTrue(f.rows(root)[0].accessibilityPerformPress())
            let child = try XCTUnwrap(root.childWindows?.first)
            f.key(rtl ? 124 : 123, in: child)
            XCTAssertTrue(f.root === root); XCTAssertTrue(root.childWindows?.isEmpty ?? true)
            XCTAssertTrue(f.rows(root)[0].isAccessibilitySelected())
        }
    }

    func testLeafCallbackCanReplaceTheRootWithoutOldInvocationClosingIt() throws {
        for nested in [false, true] {
            let f = Fixture(); defer { f.close() }
            var calls = 0
            let leaf = FluentMenuItem("Replace") { [weak menu = f.menu, weak anchor = f.anchor] in
                calls += 1
                guard let menu, let anchor else { return }
                menu.update(items: [FluentMenuItem("Replacement") {}]); menu.present(relativeTo: anchor)
            }
            f.menu.update(items: nested ? [FluentMenuItem("Branch", submenu: [leaf], action: {})] : [leaf])
            let root = try XCTUnwrap(f.root)
            let target: NSWindow
            if nested { f.open(root); target = try XCTUnwrap(root.childWindows?.first) } else { target = root }
            f.key(115, in: target); f.key(36, in: target)
            XCTAssertEqual(calls, 1); XCTAssertNotNil(f.root)
            XCTAssertFalse(f.root === root)
            XCTAssertEqual(f.root.map(f.rows)?.first?.accessibilityTitle(), "Replacement")
        }
    }

    func testKeyboardSelectionOfParentSiblingClosesItsOldChildImmediately() throws {
        let f = Fixture(); defer { f.close() }
        let root = try XCTUnwrap(f.root); f.open(root)
        let child = try XCTUnwrap(root.childWindows?.first)
        root.makeKeyAndOrderFront(nil); f.key(125, in: root)
        XCTAssertTrue(f.rows(root).last!.isAccessibilitySelected())
        XCTAssertFalse(child.isVisible)
    }

    func testKeyboardOpenedRootStartsAtFirstEnabledItem() throws {
        let f = Fixture(keyboard: true, items: [FluentMenuItem("Disabled", isEnabled: false) {}, .separator,
            FluentMenuItem("First") {}, FluentMenuItem("Second") {}]); defer { f.close() }
        let root = try XCTUnwrap(f.root)
        XCTAssertEqual(f.rows(root).filter { $0.isAccessibilitySelected() }.map { $0.accessibilityTitle() }, ["First"])
    }

    func testPointerDelayStillOpensAndKeyboardSelectionCancelsIt() throws {
        for cancel in [false, true] {
            let f = Fixture(); defer { f.close() }
            let root = try XCTUnwrap(f.root), row = f.rows(root)[0]
            row.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: root.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil)!)
            if cancel { f.key(115, in: root); drainSubmenuDelay() }
            else { waitForUI(root.childWindows?.isEmpty == false) }
            XCTAssertEqual(root.childWindows?.isEmpty ?? true, cancel)
            if let child = root.childWindows?.first {
                XCTAssertTrue(f.rows(child).allSatisfy { !$0.isAccessibilitySelected() })
                f.key(124, in: root)
                XCTAssertTrue(root.childWindows?.first === child)
                XCTAssertTrue(f.rows(child).first { $0.accessibilityTitle() == "Deep" }!.isAccessibilitySelected())
            }
        }
    }

    func testDismissCallbackReopeningSupersedesTheOldPresentCall() throws {
        let f = Fixture(); defer { f.menu.onDismiss = nil; f.close() }
        var reopened: NSWindow?
        f.menu.onDismiss = { [weak menu = f.menu, weak anchor = f.anchor, weak window = f.window] in
            guard let menu, let anchor else { return }
            menu.onDismiss = nil
            menu.update(items: [FluentMenuItem("Callback replacement") {}]); menu.present(relativeTo: anchor)
            reopened = window?.childWindows?.first
        }
        f.menu.present(relativeTo: f.anchor)
        XCTAssertEqual(f.window.childWindows?.count, 1)
        XCTAssertTrue(f.root === reopened)
        f.menu.dismiss(animated: false)
        XCTAssertTrue(f.window.childWindows?.isEmpty ?? true)
    }

    func testRetiredChildCannotInvokeOrCloseAReplacementMenu() throws {
        var calls = 0
        let f = Fixture(items: [FluentMenuItem("Branch", submenu: [FluentMenuItem("Leaf") { calls += 1 }], action: {})])
        defer { f.close() }
        let root = try XCTUnwrap(f.root); f.open(root)
        let child = try XCTUnwrap(root.childWindows?.first), row = f.rows(child)[0]
        f.menu.present(relativeTo: f.anchor)
        let replacement = try XCTUnwrap(f.root)
        f.key(36, in: child); f.key(53, in: child); _ = row.accessibilityPerformPress()
        XCTAssertEqual(calls, 0); XCTAssertTrue(f.root === replacement)
    }

    func testDismissCallbackCanCancelAnInFlightPresentRequest() {
        let f = Fixture(); defer { f.menu.onDismiss = nil; f.close() }
        f.menu.onDismiss = { [weak menu = f.menu] in menu?.dismiss(animated: false) }
        f.menu.present(relativeTo: f.anchor)
        XCTAssertFalse(f.menu.isPresented)
        XCTAssertTrue(f.window.childWindows?.isEmpty ?? true)
    }

    func testTabKeepsCurrentLevelAndDoesNotInvoke() throws {
        let f = Fixture(); defer { f.close() }
        let root = try XCTUnwrap(f.root); f.open(root)
        let child = try XCTUnwrap(root.childWindows?.first), responder = child.firstResponder
        f.key(48, in: child)
        XCTAssertTrue(f.root === root); XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(child.firstResponder === responder)
        XCTAssertTrue(f.rows(child).first { $0.accessibilityTitle() == "Deep" }!.isAccessibilitySelected())
    }
}
