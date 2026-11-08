import XCTest
@testable import FluentKit

@MainActor
final class MenuPointerHierarchyTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let anchor = NSView(frame: NSRect(x: 200, y: 250, width: 150, height: 32))
        let menu: FluentMenuFlyout
        var root: NSWindow { window.childWindows!.first! }
        init(rtl: Bool = false, dark: Bool = false) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 140, y: 140, width: 700, height: 450),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(anchor)
            anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            window.makeKeyAndOrderFront(nil)
            menu = FluentMenuFlyout(items: Self.items, theme: .custom(colorScheme: dark ? .dark : .light), reduceMotion: true)
            menu.present(relativeTo: anchor)
        }
        static var items: [FluentMenuItem] { [
            .submenu(id: "first", "First branch") {
                FluentMenuItem.submenu("Deep branch") { FluentMenuItem("Deep leaf") {} }
                FluentMenuItem("Leaf") {}
            },
            .submenu(id: "second", "Second branch") { FluentMenuItem("Second leaf") {} },
            FluentMenuItem(id: "disabled", "Disabled", isEnabled: false) {},
            FluentMenuItem(id: "leaf", "Root leaf") {}
        ] }
        func close() { menu.dismiss(animated: false); window.close() }
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func rows(_ panel: NSWindow) -> [NSView] { all(panel.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } }
        func viewport(_ panel: NSWindow) -> NSView { all(panel.contentView!).compactMap { $0 as? NSScrollView }.first!.superview! }
        func pointer(_ v: NSView, entering: Bool) {
            let event = NSEvent.enterExitEvent(with: entering ? .mouseEntered : .mouseExited,
                location: entering ? v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil) : NSPoint(x: -30, y: -30),
                modifierFlags: [], timestamp: 0, windowNumber: v.window!.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil)!
            if entering { v.mouseEntered(with: event) } else { v.mouseExited(with: event) }
        }
        func open(_ panel: NSWindow, index: Int = 0) throws -> NSWindow {
            pointer(viewport(panel), entering: true); pointer(rows(panel)[index], entering: true)
            waitForUI(panel.childWindows?.isEmpty == false)
            return try XCTUnwrap(panel.childWindows?.first)
        }
    }

    private func observePastPointerDelay() { RunLoop.main.run(until: Date().addingTimeInterval(0.26)) }

    func testHidingAndRevealingMenuClearsPointerHighlight() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let row = try XCTUnwrap(fixture.rows(fixture.root).last)
        fixture.pointer(row, entering: true)
        XCTAssertGreaterThan(try backgroundAlpha(row), 0)
        fixture.root.contentView?.isHidden = true
        fixture.root.contentView?.isHidden = false
        XCTAssertEqual(try backgroundAlpha(row), 0, accuracy: 0.001)
    }

    private func backgroundAlpha(_ row: NSView) throws -> CGFloat {
        let bitmap = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 4)).alphaComponent
    }

    func testLeavingRootChainClosesOnlyItsChildAfterTheDelay() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = f.root, child = try f.open(f.root)
            f.pointer(f.rows(root)[0], entering: false); f.pointer(f.viewport(root), entering: false)
            XCTAssertTrue(child.isVisible, "The gap crossing needs a grace period")
            waitForUI(child.parent == nil)
            XCTAssertFalse(child.isVisible); XCTAssertTrue(f.menu.isPresented)
        }
    }

    func testLeavingTheChildChainAlsoSchedulesItsClosure() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(f.root)
        f.pointer(f.rows(root)[0], entering: false); f.pointer(f.viewport(root), entering: false)
        f.pointer(f.viewport(child), entering: true); f.pointer(f.rows(child)[1], entering: true)
        f.pointer(f.rows(child)[1], entering: false); f.pointer(f.viewport(child), entering: false)
        waitForUI(child.parent == nil)
        XCTAssertTrue(f.menu.isPresented)
    }

    func testEnteringChildPaddingCancelsItsParentsCloseDelay() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(f.root)
        f.pointer(f.rows(root)[0], entering: false); f.pointer(f.viewport(root), entering: false)
        f.pointer(f.viewport(child), entering: true)
        observePastPointerDelay()
        XCTAssertTrue(root.childWindows?.first === child)
    }

    func testDescendantEntryCancelsPendingSiblingReplacementEvenAfterAMissedExit() throws {
        for rtl in [false, true] {
            let f = Fixture(rtl: rtl); defer { f.close() }
            let root = f.root, child = try f.open(f.root)
            f.pointer(f.rows(root)[1], entering: true)
            f.pointer(f.viewport(child), entering: true)
            f.pointer(f.rows(child)[1], entering: true)
            observePastPointerDelay()
            XCTAssertTrue(root.childWindows?.first === child)
            XCTAssertEqual(f.rows(child).last?.accessibilityTitle(), "Leaf")
        }
    }

    func testGrandchildEntryKeepsTheEntireAncestorChain() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(f.root), grandchild = try f.open(child)
        f.pointer(f.rows(root)[0], entering: false); f.pointer(f.viewport(root), entering: false)
        f.pointer(f.rows(child)[0], entering: false); f.pointer(f.viewport(child), entering: false)
        f.pointer(f.viewport(grandchild), entering: true)
        observePastPointerDelay()
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(child.childWindows?.first === grandchild)
    }

    func testDisabledSiblingDoesNotKeepThePreviousBranchOpen() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(f.root)
        f.pointer(f.rows(root)[0], entering: false)
        f.pointer(f.rows(root)[2], entering: true)
        waitForUI(child.parent == nil)
        XCTAssertTrue(f.menu.isPresented)
    }

    func testOpenBranchKeepsItsOwnPaintAndExpandedStateWhenPointerMovesToChild() throws {
        for dark in [false, true] {
            let f = Fixture(dark: dark); defer { f.close() }
            let root = f.root, row = f.rows(root)[0]
            let normal = try backgroundAlpha(row)
            let child = try f.open(root)
            f.pointer(row, entering: false); f.pointer(f.viewport(root), entering: false)
            f.pointer(f.viewport(child), entering: true)
            XCTAssertGreaterThan(try backgroundAlpha(row), normal)
            XCTAssertTrue(row.isAccessibilityExpanded())
            XCTAssertFalse(row.isAccessibilitySelected(), "Expansion is separate from keyboard selection")
        }
    }

    func testLeavingBeforeOpenAndLateOldExitDoNotOpenTheWrongBranch() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, first = f.rows(root)[0], second = f.rows(root)[1]
        f.pointer(first, entering: true); f.pointer(first, entering: false)
        observePastPointerDelay(); XCTAssertTrue(root.childWindows?.isEmpty ?? true)
        f.pointer(first, entering: true); f.pointer(second, entering: true); f.pointer(first, entering: false)
        waitForUI(root.childWindows?.isEmpty == false)
        let child = try XCTUnwrap(root.childWindows?.first)
        XCTAssertEqual(f.rows(child).first?.accessibilityTitle(), "Second leaf")
    }

    func testPendingPointerClosureCannotCloseAReopenedRoot() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root
        _ = try f.open(root)
        f.pointer(f.rows(root)[0], entering: false); f.pointer(f.viewport(root), entering: false)
        f.menu.present(relativeTo: f.anchor)
        let replacement = f.root
        let child = try f.open(replacement, index: 1)
        observePastPointerDelay()
        XCTAssertTrue(f.root === replacement); XCTAssertTrue(replacement.childWindows?.first === child)
    }

    func testStableRowReorderPreservesTheOpenBranchStateAndChild() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(f.root), row = f.rows(root)[0]
        f.pointer(row, entering: false); f.pointer(f.viewport(child), entering: true)
        f.menu.update(items: Fixture.items.reversed())
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(f.rows(root).contains { $0 === row })
        XCTAssertEqual(row.frame.minY, f.rows(root).map(\.frame.minY).max())
        XCTAssertTrue(row.isAccessibilityExpanded())
        XCTAssertGreaterThan(try backgroundAlpha(row), 0)
    }

    func testCloseDelayClearsOpenPaintButKeepsExpandedUntilActuallyClosed() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, row = f.rows(root)[0], child = try f.open(root)
        f.pointer(row, entering: false)
        XCTAssertEqual(try backgroundAlpha(row), 0)
        XCTAssertTrue(row.isAccessibilityExpanded())
        f.pointer(row, entering: true)
        XCTAssertGreaterThan(try backgroundAlpha(row), 0)
        observePastPointerDelay()
        XCTAssertTrue(root.childWindows?.first === child)
        f.pointer(row, entering: false)
        waitForUI(child.parent == nil)
        XCTAssertFalse(row.isAccessibilityExpanded())
    }

    func testChildKeyboardInputCancelsAncestorPointerClosure() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(root)
        f.pointer(f.rows(root)[0], entering: false); f.pointer(f.viewport(root), entering: false)
        child.firstResponder?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: child.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!)
        observePastPointerDelay()
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(f.rows(child)[0].isAccessibilitySelected())
    }

    func testSwitchingBranchesClearsTheOldExpandedState() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(root), first = f.rows(root)[0], second = f.rows(root)[1]
        f.pointer(first, entering: false); f.pointer(second, entering: true)
        waitForUI(root.childWindows?.first !== child && root.childWindows?.isEmpty == false)
        XCTAssertFalse(first.isAccessibilityExpanded()); XCTAssertTrue(second.isAccessibilityExpanded())
        XCTAssertFalse(child.isVisible)
        XCTAssertEqual(try backgroundAlpha(first), 0)
    }

    func testDisablingOrRemovingTheOpenOwnerClearsRetainedAccessibilityState() throws {
        for remove in [false, true] {
            let f = Fixture(); defer { f.close() }
            let root = f.root, child = try f.open(root), row = f.rows(root)[0]
            var items = Fixture.items
            if remove { items.removeFirst() }
            else { items[0] = FluentMenuItem(id: "first", "First branch", isEnabled: false, submenu: items[0].submenu) {} }
            f.menu.update(items: items)
            XCTAssertFalse(child.isVisible); XCTAssertFalse(row.isAccessibilityExpanded())
            observePastPointerDelay()
            XCTAssertTrue(root.childWindows?.isEmpty ?? true)
        }
    }

    func testVerticalScrollerKeepsTheOpenBranchAcrossTheRowExit() throws {
        let f = Fixture(); defer { f.close() }
        f.menu.update(items: Fixture.items + (0..<100).map { FluentMenuItem("Extra \($0)") {} })
        let root = f.root, child = try f.open(root), viewport = f.viewport(root)
        let scroll = try XCTUnwrap(f.all(viewport).compactMap { $0 as? NSScrollView }.first)
        scroll.scrollerStyle = .legacy; scroll.autohidesScrollers = false
        viewport.needsLayout = true; viewport.layoutSubtreeIfNeeded()
        let scroller = try XCTUnwrap(scroll.verticalScroller)
        XCTAssertFalse(scroller.isHidden); XCTAssertGreaterThan(scroller.frame.width, 0)
        f.pointer(f.rows(root)[0], entering: false)
        viewport.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved,
            location: scroller.convert(NSPoint(x: scroller.bounds.midX, y: scroller.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: root.windowNumber, context: nil,
            eventNumber: 1, clickCount: 0, pressure: 0)!)
        observePastPointerDelay()
        XCTAssertTrue(root.childWindows?.first === child)
    }

    func testHighContrastOpenBranchUsesTransparentFillInsteadOfHoverFill() throws {
        for dark in [false, true] {
            let f = Fixture(dark: dark); defer { f.close() }
            f.menu.update(items: Fixture.items, theme: .custom(contrast: .high, colorScheme: dark ? .dark : .light))
            let root = f.root, row = f.rows(root)[0]
            f.pointer(row, entering: true)
            XCTAssertGreaterThan(try backgroundAlpha(row), 0)
            waitForUI(root.childWindows?.isEmpty == false)
            XCTAssertEqual(try backgroundAlpha(row), 0)
            XCTAssertTrue(row.isAccessibilityExpanded())
        }
    }

    func testDismissedRetainedRowsCannotReopenAndHaveNoExpandedState() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, row = f.rows(root)[0], child = try f.open(root)
        f.pointer(row, entering: false); f.pointer(f.rows(root)[1], entering: true)
        f.menu.dismiss(animated: false)
        XCTAssertFalse(row.isAccessibilityExpanded())
        XCTAssertTrue(row.accessibilityPerformPress())
        observePastPointerDelay()
        XCTAssertFalse(f.menu.isPresented); XCTAssertFalse(child.isVisible)
    }

    func testOwnerRowExitStillClosesBranchAfterChildTakesKeyStatus() throws {
        let f = Fixture(); defer { f.close() }
        let root = f.root, child = try f.open(root)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: root)
        f.pointer(f.rows(root)[0], entering: false)
        waitForUI(child.parent == nil)
        XCTAssertTrue(f.menu.isPresented)
    }

    func testLateOwnerExitCannotOverrideChildEntryOrKeyboardNavigation() throws {
        for keyboard in [false, true] {
            let f = Fixture(); defer { f.close() }
            let root = f.root, child = try f.open(root), row = f.rows(root)[0]
            if keyboard {
                child.firstResponder?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: child.windowNumber, context: nil,
                    characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!)
            } else { f.pointer(f.viewport(child), entering: true) }
            f.pointer(row, entering: false)
            observePastPointerDelay()
            XCTAssertTrue(root.childWindows?.first === child)
        }
    }

    func testInitialPanelAndSubmenuResolveSystemColorsUsingTheirExplicitTheme() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 140, y: 140, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let anchor = NSView(frame: NSRect(x: 40, y: 250, width: 100, height: 32))
        window.contentView?.addSubview(anchor)
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            let menu = FluentMenuFlyout(items: Fixture.items, theme: theme, reduceMotion: true)
            defer { menu.dismiss(animated: false) }
            menu.present(relativeTo: anchor)
            let root = try XCTUnwrap(window.childWindows?.first)
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            let row = try XCTUnwrap(all(root.contentView!).first { $0.identifier?.rawValue == "FluentKit.Menu.Item" })
            XCTAssertTrue(row.accessibilityPerformPress())
            let child = try XCTUnwrap(root.childWindows?.first)
            for panel in [root, child] {
                XCTAssertEqual(panel.effectiveAppearance.name, fluentAppKitAppearance(for: theme)?.name)
                var color: NSColor?
                panel.effectiveAppearance.performAsCurrentDrawingAppearance {
                    color = NSColor.controlTextColor.usingColorSpace(.deviceRGB)
                }
                let brightness = try XCTUnwrap(color).brightnessComponent
                if dark { XCTAssertGreaterThan(brightness, 0.7) }
                else { XCTAssertLessThan(brightness, 0.3) }
            }
        }
    }

    func testHighContrastExpandedTextRemainsLegibleOnThePopupFallback() throws {
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            var foreground: NSColor?, background: NSColor?
            fluentAppKitAppearance(for: theme)?.performAsCurrentDrawingAppearance {
                foreground = theme.menuSubmenuOpenedForeground.usingColorSpace(.sRGB)
                background = theme.windowBackground.usingColorSpace(.sRGB)
            }
            func luminance(_ color: NSColor) -> CGFloat {
                let linear = [color.redComponent, color.greenComponent, color.blueComponent].map {
                    $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
                }
                return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
            }
            let f = luminance(try XCTUnwrap(foreground)), b = luminance(try XCTUnwrap(background))
            XCTAssertGreaterThanOrEqual((max(f, b) + 0.05) / (min(f, b) + 0.05), 4.5)
        }
    }
}
