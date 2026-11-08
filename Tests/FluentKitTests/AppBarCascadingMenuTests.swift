import XCTest
@testable import FluentKit

@MainActor
final class AppBarCascadingMenuTests: XCTestCase {
    private final class InputPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
    @MainActor private final class Fixture {
        let window: NSWindow
        let bar: FluentCommandBar
        var leafCalls = 0
        var commandCalls = 0
        var root: NSWindow { window.childWindows!.first! }
        var branch: FluentAppBarButton { bar.secondaryCommandViews[0] as! FluentAppBarButton }
        let rtl: Bool

        init(rtl: Bool = false, dark: Bool = false, withFlyout: Bool = true) {
            _ = NSApplication.shared
            self.rtl = rtl
            window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 700, height: 420),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [])
            bar.secondaryCommands = [
                FluentCommandBarItem(id: "branch", "Branch") { [weak self] in self?.commandCalls += 1 },
                FluentCommandBarItem(id: "other", "Other") {}
            ]
            bar.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            bar.reduceMotion = true
            bar.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            window.contentView!.addSubview(bar)
            bar.frame = NSRect(x: 200, y: 300, width: 260, height: 48)
            if withFlyout {
                branch.flyoutItems = [FluentMenuItem(id: "disabled", "Disabled", isEnabled: false) {},
                    FluentMenuItem(id: "leaf", "Leaf") { [weak self] in self?.leafCalls += 1 }]
            }
            window.orderFront(nil)
            bar.layoutSubtreeIfNeeded()
            bar.setOpen(true, animated: false)
            root.makeFirstResponder(branch)
        }

        func close() {
            (bar.primaryCommandViews + bar.secondaryCommandViews).compactMap { $0 as? FluentAppBarButton }
                .forEach { $0.hideFlyout(animated: false) }
            bar.setOpen(false, animated: false)
            window.close()
        }

        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func rows(_ panel: NSWindow) -> [NSView] {
            all(panel.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
                .sorted { $0.frame.minY < $1.frame.minY }
        }
        func viewport(_ panel: NSWindow) throws -> NSView {
            try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSScrollView }.first?.superview)
        }
        func key(_ code: UInt16, in panel: NSWindow, up: Bool = false) {
            NSApp.sendEvent(NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                characters: code == 49 ? " " : "", charactersIgnoringModifiers: code == 49 ? " " : "",
                isARepeat: false, keyCode: code)!)
        }
        func pointer(_ view: NSView, entering: Bool) {
            let point = entering ? view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) : NSPoint(x: -30, y: -30)
            let event = NSEvent.enterExitEvent(with: entering ? .mouseEntered : .mouseExited, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil)!
            if entering { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
        }
        func click(_ row: NSView, in panel: NSWindow) {
            let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
            }
        }
        func show() throws -> NSWindow {
            branch.showFlyout()
            return try XCTUnwrap(root.childWindows?.first)
        }
    }

    func testForwardReturnAndSpaceOpenTheBranchWithoutInvokingItsCommand() throws {
        for rtl in [false, true] { for code: UInt16 in [rtl ? 123 : 124, 36, 49] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = f.root
            f.key(code, in: root)
            f.key(code, in: root, up: true)
            XCTAssertTrue(f.bar.isOpen)
            XCTAssertTrue(f.branch.isFlyoutPresented)
            XCTAssertEqual(f.commandCalls, 0)
            let child = try XCTUnwrap(root.childWindows?.first)
            XCTAssertEqual(f.rows(child).filter { $0.isAccessibilitySelected() }.map { $0.accessibilityTitle() }, ["Leaf"])
        } }
    }

    func testAttachedOverflowMenuUsesTheSideAndKeepsItsPanelWhenMoved() throws {
        for rtl in [false, true] { for dark in [false, true] {
            let f = Fixture(rtl: rtl, dark: dark); defer { f.close() }
            let root = f.root, child = try f.show()
            XCTAssertTrue(child.frame.minX >= root.frame.maxX - 12 || child.frame.maxX <= root.frame.minX + 12)
            let before = child.frame.origin
            f.window.setFrameOrigin(NSPoint(x: f.window.frame.minX + 30, y: f.window.frame.minY + 20))
            waitForUI(child.frame.origin != before)
            XCTAssertTrue(root.childWindows?.first === child)
            XCTAssertTrue(child.frame.minX >= root.frame.maxX - 12 || child.frame.maxX <= root.frame.minX + 12)
        } }
    }

    func testBackAndEscapeCloseOnlyTheAttachedMenuAndRestoreItsAnchor() throws {
        for rtl in [false, true] { for code: UInt16 in [rtl ? 124 : 123, 53] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = f.root, child = try f.show(), anchor = f.branch
            f.key(code, in: child)
            XCTAssertTrue(f.bar.isOpen)
            XCTAssertTrue(f.window.childWindows?.first === root)
            XCTAssertFalse(anchor.isFlyoutPresented)
            XCTAssertFalse(child.isVisible)
            XCTAssertTrue(root.firstResponder === anchor)
            f.key(53, in: root)
            XCTAssertFalse(f.bar.isOpen)
        } }
    }

    func testEscapeUnwindsNestedMenusOneLevelAtATime() throws {
        let f = Fixture(); defer { f.close() }
        f.branch.flyoutItems = [.submenu("Deep") { FluentMenuItem("Leaf") {} }]
        let root = f.root, child = try f.show()
        _ = f.rows(child)[0].accessibilityPerformPress()
        let grandchild = try XCTUnwrap(child.childWindows?.first)
        f.key(53, in: grandchild)
        XCTAssertTrue(f.bar.isOpen)
        XCTAssertTrue(f.branch.isFlyoutPresented)
        XCTAssertFalse(grandchild.isVisible)
        XCTAssertTrue(child.isVisible)
        f.key(53, in: child)
        XCTAssertTrue(f.bar.isOpen)
        XCTAssertFalse(f.branch.isFlyoutPresented)
        XCTAssertTrue(root.firstResponder === f.branch)
    }

    func testNativeMouseDispatchReachesTheLeafBeforeClosingTheMenuChain() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let child = try f.show()
            // The test host may be inactive. Allow this fixture panel to receive native input
            // without activating the application; a plain inactive NSPanel discards this click.
            child.styleMask.insert(.nonactivatingPanel)
            child.makeKeyAndOrderFront(nil)
            XCTAssertTrue(child.isKeyWindow)
            f.click(f.rows(child)[1], in: child)
            waitForUI(f.leafCalls == 1)
            XCTAssertEqual(f.leafCalls, 1)
            XCTAssertFalse(f.bar.isOpen)
            XCTAssertFalse(f.branch.isFlyoutPresented)
            XCTAssertFalse(child.isVisible)
        }
    }

    func testAccessibilityLeafInvocationClosesTheWholeChain() throws {
        let f = Fixture(); defer { f.close() }
        let child = try f.show()
        XCTAssertTrue(f.rows(child)[1].accessibilityPerformPress())
        XCTAssertEqual(f.leafCalls, 1)
        XCTAssertFalse(f.bar.isOpen)
        XCTAssertFalse(child.isVisible)
    }

    func testEscapeInAnUnrelatedWindowCannotDismissThisChain() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.show()
        let other = InputPanel(contentRect: NSRect(x: 900, y: 120, width: 160, height: 160),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        XCTAssertTrue(other.isKeyWindow)
        f.key(53, in: other)
        XCTAssertTrue(f.bar.isOpen)
        XCTAssertTrue(f.branch.isFlyoutPresented)
        XCTAssertTrue(f.window.childWindows?.first === root)
        XCTAssertTrue(root.childWindows?.first === child)
    }

    func testHoverOpensWithAGracePeriodAndChildEntryCancelsPendingClosure() throws {
        let f = Fixture(); defer { f.close() }
        f.pointer(f.branch, entering: true)
        XCTAssertFalse(f.branch.isFlyoutPresented)
        waitForUI(f.branch.isFlyoutPresented)
        let child = try XCTUnwrap(f.root.childWindows?.first)
        f.pointer(f.branch, entering: false)
        XCTAssertTrue(child.isVisible)
        f.pointer(try f.viewport(child), entering: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.26))
        XCTAssertTrue(f.branch.isFlyoutPresented)
        f.pointer(try f.viewport(child), entering: false)
        waitForUI(!f.branch.isFlyoutPresented)
        XCTAssertTrue(f.bar.isOpen)
    }

    func testKeyboardSelectionOfAnotherCommandClosesTheOldBranch() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.show()
        f.key(125, in: root)
        XCTAssertTrue(root.firstResponder === f.bar.secondaryCommandViews[1])
        XCTAssertFalse(f.branch.isFlyoutPresented)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(f.bar.isOpen)
    }

    func testOpeningAnotherBranchClosesItsPeerAndOnlyOneBranchStaysExpanded() throws {
        let f = Fixture(); defer { f.close() }
        let first = try f.show()
        let other = try XCTUnwrap(f.bar.secondaryCommandViews[1] as? FluentAppBarButton)
        other.flyoutItems = [FluentMenuItem("Other leaf") {}]
        other.showFlyout()
        XCTAssertFalse(f.branch.isFlyoutPresented)
        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(other.isFlyoutPresented)
        XCTAssertEqual(f.root.childWindows?.count, 1)
    }

    func testClosingTheOuterMenuImmediatelyClosesChildrenAndCancelsPendingOpen() throws {
        for opened in [false, true] {
            let f = Fixture(); defer { f.close() }
            let root = f.root
            var child: NSWindow?
            if opened { child = try f.show() } else { f.pointer(f.branch, entering: true) }
            let branch = f.branch
            f.bar.setOpen(false, animated: false)
            XCTAssertFalse(branch.isFlyoutPresented)
            XCTAssertTrue(root.childWindows?.isEmpty ?? true)
            if let child { XCTAssertFalse(child.isVisible) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.26))
            XCTAssertFalse(branch.isFlyoutPresented)
        }
    }

    func testAnInvokedCommandCannotCloseAReplacementOpenedByItsCallback() throws {
        let f = Fixture(withFlyout: false); defer { f.close() }
        f.bar.secondaryCommands = [FluentCommandBarItem("Replace") { [weak bar = f.bar] in
            guard let bar else { return }
            bar.setOpen(false, animated: false)
            bar.secondaryCommands = [FluentCommandBarItem("Replacement") {}]
            bar.setOpen(true, animated: false)
        }]
        let original = f.root
        _ = (f.bar.secondaryCommandViews[0] as! FluentAppBarButton).accessibilityPerformPress()
        XCTAssertTrue(f.bar.isOpen)
        let replacement = try XCTUnwrap(f.window.childWindows?.first)
        XCTAssertFalse(replacement === original)
    }

    func testLeafCallbackCanOpenAReplacementWithoutTheOldChainClosingIt() throws {
        let f = Fixture(); defer { f.close() }
        f.branch.flyoutItems = [FluentMenuItem("Replace") { [weak bar = f.bar] in
            guard let bar else { return }
            bar.setOpen(false, animated: false)
            bar.secondaryCommands = [FluentCommandBarItem("Replacement") {}]
            bar.setOpen(true, animated: false)
        }]
        let root = f.root, child = try f.show()
        XCTAssertTrue(f.rows(child)[0].accessibilityPerformPress())
        XCTAssertTrue(f.bar.isOpen)
        XCTAssertFalse(child.isVisible)
        XCTAssertFalse(f.root === root)
    }

    func testStableCommandRefreshRetainsAnAttachedMenuAndItsUpdatedAction() throws {
        let f = Fixture(); defer { f.close() }
        let anchor = f.branch, root = f.root, child = try f.show()
        let leaf = f.rows(child)[1]
        f.bar.secondaryCommands = [
            FluentCommandBarItem(id: "other", "Renamed sibling") {},
            FluentCommandBarItem(id: "branch", "Renamed branch") {}
        ]
        anchor.flyoutItems = [FluentMenuItem(id: "disabled", "Disabled", isEnabled: false) {},
            FluentMenuItem(id: "leaf", "Updated leaf") { [weak f] in f?.leafCalls += 10 }]
        XCTAssertTrue(f.bar.secondaryCommandViews[1] === anchor)
        XCTAssertTrue(anchor.isFlyoutPresented)
        XCTAssertTrue(f.root === root)
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(f.rows(child)[1] === leaf)
        XCTAssertEqual(leaf.accessibilityTitle(), "Updated leaf")
        XCTAssertTrue(leaf.accessibilityPerformPress())
        XCTAssertEqual(f.leafCalls, 10)
        XCTAssertFalse(f.bar.isOpen)
    }

    func testDisabledHiddenOrRemovedAnchorsCancelOpenedAndPendingBranches() throws {
        for change in 0..<3 { for opened in [false, true] {
            let f = Fixture(); defer { f.close() }
            let anchor = f.branch
            var child: NSWindow?
            if opened { child = try f.show() } else { f.pointer(anchor, entering: true) }
            switch change {
            case 0: anchor.isEnabled = false
            case 1: anchor.isHidden = true
            default: f.bar.secondaryCommands = [FluentCommandBarItem(id: "other", "Other") {}]
            }
            XCTAssertFalse(anchor.isFlyoutPresented)
            if let child { XCTAssertFalse(child.isVisible) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.26))
            XCTAssertFalse(anchor.isFlyoutPresented)
            XCTAssertTrue(f.bar.isOpen)
        } }
    }

    func testEnteringADisabledSiblingCancelsAnOpenOrPendingBranch() throws {
        for opened in [false, true] {
            let f = Fixture(); defer { f.close() }
            if opened { _ = try f.show() } else { f.pointer(f.branch, entering: true) }
            let sibling = try XCTUnwrap(f.bar.secondaryCommandViews[1] as? FluentAppBarButton)
            sibling.isEnabled = false
            f.pointer(sibling, entering: true)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.26))
            XCTAssertFalse(f.branch.isFlyoutPresented)
            XCTAssertTrue(f.bar.isOpen)
        }
    }

    func testPrimaryAttachedMenuRetainsOrdinaryPlacementAndToggleBehavior() throws {
        let f = Fixture(); defer { f.close() }
        let button = f.branch
        f.bar.setOpen(false, animated: false)
        f.bar.setCommands(primary: [FluentCommandBarItem(id: "branch", "Branch") { [weak f] in f?.commandCalls += 1 }], secondary: [])
        f.bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(f.bar.primaryCommandViews[0] === button)
        XCTAssertFalse(button.isInOverflow)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(f.commandCalls, 1)
        let child = try XCTUnwrap(f.window.childWindows?.first)
        let anchor = f.window.convertToScreen(button.convert(button.bounds, to: nil))
        XCTAssertLessThanOrEqual(child.frame.maxY, anchor.minY + 2)
        button.flyoutPlacement = .comboBoxSelection
        XCTAssertTrue(f.window.childWindows?.first === child)
        let selectedRow = f.rows(child)[1]
        let rowCenter = child.convertPoint(toScreen: selectedRow.convert(
            NSPoint(x: selectedRow.bounds.midX, y: selectedRow.bounds.midY), to: nil))
        XCTAssertEqual(rowCenter.y, anchor.midY, accuracy: 1)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(f.commandCalls, 2)
        XCTAssertFalse(button.isFlyoutPresented)
        XCTAssertFalse(child.isVisible)
    }

    func testAddingAFlyoutDuringACommandPressCancelsTheOldRelease() throws {
        let f = Fixture(withFlyout: false); defer { f.close() }
        let anchor = f.branch, root = f.root
        let surface = try XCTUnwrap(anchor.layer?.sublayers?.first {
            $0.name == "FluentKit.AppBarButton.InnerBorder"
        })
        let idleFill = surface.backgroundColor
        f.key(49, in: root)
        XCTAssertNotEqual(surface.backgroundColor, idleFill)
        anchor.flyoutItems = [FluentMenuItem("New branch") {}]
        f.key(49, in: root, up: true)
        XCTAssertEqual(f.commandCalls, 0)
        XCTAssertFalse(anchor.isFlyoutPresented)
        XCTAssertEqual(surface.backgroundColor, idleFill)
        f.key(49, in: root)
        XCTAssertTrue(anchor.isFlyoutPresented, "The new branch must accept a fresh press")
        XCTAssertEqual(f.commandCalls, 0)
    }
}
