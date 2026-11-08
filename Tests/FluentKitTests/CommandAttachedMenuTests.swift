import XCTest
@testable import FluentKit

@MainActor
final class CommandAttachedMenuTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let anchor = NSView(frame: NSRect(x: 180, y: 160, width: 180, height: 40))
        let flyout: FluentCommandBarFlyout
        private var originalRoot: NSWindow!
        init(primary: [FluentCommandBarItem] = [], secondary: [FluentCommandBarItem] = [], rtl: Bool = false) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 150, y: 180, width: 720, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            window.contentView!.addSubview(anchor)
            window.makeKeyAndOrderFront(nil)
            flyout = FluentCommandBarFlyout(primaryCommands: primary, secondaryCommands: secondary,
                                           alwaysExpanded: true, reduceMotion: true)
            flyout.present(relativeTo: anchor)
            originalRoot = window.childWindows?.first
        }
        var root: NSWindow { window.childWindows?.first ?? originalRoot }
        func close() { flyout.dismiss(); window.close() }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func button(_ title: String) throws -> NSButton {
            try XCTUnwrap(all(root.contentView!).compactMap { $0 as? NSButton }
                .first { $0.accessibilityTitle() == title })
        }
        func row(_ title: String, in panel: NSWindow) throws -> NSView {
            try XCTUnwrap(all(panel.contentView!).first {
                $0.identifier?.rawValue == "FluentKit.Menu.Item" && $0.accessibilityTitle() == title
            })
        }
        func child() throws -> NSWindow { try XCTUnwrap(root.childWindows?.first) }
        func key(_ code: UInt16, in panel: NSWindow) {
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                characters: code == 49 ? " " : "", charactersIgnoringModifiers: code == 49 ? " " : "",
                isARepeat: false, keyCode: code)!)
        }
        func pointer(_ view: NSView, enter: Bool) {
            let point = enter ? view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
                : NSPoint(x: -100, y: -100)
            let event = NSEvent.enterExitEvent(with: enter ? .mouseEntered : .mouseExited, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
                context: nil, eventNumber: 1, trackingNumber: 0, userData: nil)!
            if enter { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
        }
    }

    func testPrimaryAttachmentInvokesParentAndKeepsRootAfterLeaf() throws {
        var parents = 0, leaves = 0
        let f = Fixture(primary: [.init(id: "p", "Primary", systemImageName: "folder",
            flyoutItems: [.init("Leaf") { leaves += 1 }]) { parents += 1 }])
        defer { f.close() }
        let root = f.root, button = try f.button("Primary")
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(parents, 1)
        let child = try f.child()
        XCTAssertTrue(button.isAccessibilityExpanded())
        XCTAssertTrue(try f.row("Leaf", in: child).accessibilityPerformPress())
        XCTAssertEqual(leaves, 1)
        XCTAssertTrue(root.isVisible)
        XCTAssertFalse(child.isVisible)
        XCTAssertFalse(button.isAccessibilityExpanded())
    }

    func testSecondaryAttachmentOpensWithoutParentActionAndLeafClosesChain() throws {
        var parents = 0, leaves = 0
        let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Leaf") { leaves += 1 }]) { parents += 1 }])
        defer { f.close() }
        let root = f.root
        XCTAssertTrue(try f.button("Branch").accessibilityPerformPress())
        let child = try f.child()
        XCTAssertEqual(parents, 0)
        XCTAssertTrue(try f.row("Leaf", in: child).accessibilityPerformPress())
        XCTAssertEqual(leaves, 1)
        XCTAssertFalse(root.isVisible)
        XCTAssertFalse(f.flyout.isPresented)
    }

    func testKeyboardForwardAndBackMirrorWithDirectionAndEscapeReturnsToOwner() throws {
        for rtl in [false, true] { for back: UInt16 in [rtl ? 124 : 123, 53] {
            let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Leaf") {}])], rtl: rtl)
            defer { f.close() }
            let button = try f.button("Branch"), root = f.root
            // XCTest may run in an inactive process. Make the synthetic input target genuinely
            // key without activating the user's app, as in the public mouse-event probes.
            root.styleMask.insert(.nonactivatingPanel)
            root.makeKeyAndOrderFront(nil)
            XCTAssertTrue(root.isKeyWindow)
            XCTAssertEqual(button.userInterfaceLayoutDirection, rtl ? .rightToLeft : .leftToRight)
            XCTAssertTrue(root.makeFirstResponder(button))
            f.key(rtl ? 123 : 124, in: root)
            let child = try f.child()
            XCTAssertTrue(try f.row("Leaf", in: child).isAccessibilitySelected())
            f.key(back, in: child)
            XCTAssertTrue(root.isVisible)
            XCTAssertFalse(child.isVisible)
            XCTAssertTrue(root.firstResponder === button)
        } }
    }

    func testLiveItemsKeepChildAndSelectedRowAndReplaceAction() throws {
        var oldCalls = 0, newCalls = 0
        let f = Fixture(secondary: [.init(id: "branch", "Branch",
            flyoutItems: [.init(id: "leaf", "Old") { oldCalls += 1 }])])
        defer { f.close() }
        let button = try f.button("Branch")
        XCTAssertTrue(button.accessibilityPerformPress())
        let child = try f.child(), row = try f.row("Old", in: child)
        f.flyout.update(configuration: .init(primaryCommands: [], secondaryCommands: [
            .init(id: "other", "Other") {}, .init(id: "branch", "Renamed", keyEquivalent: "b",
                flyoutItems: [.init(id: "leaf", "New") { newCalls += 1 }])]))
        XCTAssertTrue(try f.button("Renamed") === button)
        XCTAssertTrue(try f.child() === child)
        XCTAssertTrue(try f.row("New", in: child) === row)
        XCTAssertTrue(row.isAccessibilitySelected())
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
    }

    func testMovingBetweenGroupsReanchorsTheLiveMenuAndChangesLeafClosure() throws {
        for toPrimary in [false, true] {
            let item = FluentCommandBarItem(id: "move", "Move", systemImageName: "folder",
                                           flyoutItems: [.init(id: 1, "Leaf") {}])
            let f = Fixture(primary: toPrimary ? [] : [item], secondary: toPrimary ? [item] : [])
            defer { f.close() }
            let old = try f.button("Move"), root = f.root
            XCTAssertTrue(old.accessibilityPerformPress())
            let child = try f.child(), row = try f.row("Leaf", in: child)
            f.flyout.update(configuration: .init(primaryCommands: toPrimary ? [item] : [],
                secondaryCommands: toPrimary ? [] : [item], alwaysExpanded: true))
            XCTAssertTrue(try f.child() === child)
            XCTAssertTrue(try f.row("Leaf", in: child) === row)
            XCTAssertTrue(try f.button("Move").isAccessibilityExpanded())
            XCTAssertFalse(old.isEnabled)
            XCTAssertTrue(row.accessibilityPerformPress())
            XCTAssertEqual(root.isVisible, toPrimary)
        }
    }

    func testDisablingOrRemovingAttachmentClosesChildWithoutRevivingRetiredInput() throws {
        for remove in [false, true] {
            let f = Fixture(secondary: [.init(id: 1, "Branch", flyoutItems: [.init("Leaf") {}])])
            defer { f.close() }
            let button = try f.button("Branch")
            XCTAssertTrue(button.accessibilityPerformPress())
            let child = try f.child()
            f.flyout.update(configuration: .init(primaryCommands: [], secondaryCommands: [
                .init(id: 1, "Branch", isEnabled: remove, flyoutItems: remove ? [] : [.init("Leaf") {}])]))
            XCTAssertFalse(child.isVisible)
            XCTAssertFalse(button.isAccessibilityExpanded())
            XCTAssertTrue(f.flyout.isPresented)
            if !remove { XCTAssertFalse(button.accessibilityPerformPress()) }
        }
    }

    func testDelayedHoverBridgesToChildAndPeerCancelsOldOpen() throws {
        let f = Fixture(secondary: [
            .init(id: 1, "Branch", flyoutItems: [.init("Leaf") {}]), .init(id: 2, "Peer") {}])
        defer { f.close() }
        let branch = try f.button("Branch"), peer = try f.button("Peer")
        f.pointer(branch, enter: true)
        f.pointer(peer, enter: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.22))
        XCTAssertTrue(f.root.childWindows?.isEmpty != false)
        f.pointer(branch, enter: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.22))
        let child = try f.child()
        f.pointer(branch, enter: false)
        let viewport = try XCTUnwrap(f.all(child.contentView!).compactMap { $0 as? NSScrollView }.first?.superview)
        f.pointer(viewport, enter: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.22))
        XCTAssertTrue(child.isVisible)
        f.pointer(peer, enter: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.22))
        XCTAssertFalse(child.isVisible)
    }

    func testLeafCallbackReplacingRootKeepsTheNewPresentation() throws {
        weak var captured: FluentCommandBarFlyout?
        weak var anchor: NSView?
        let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Replace") {
            captured?.update(configuration: .init(primaryCommands: [.init("New") {}]))
            if let anchor { captured?.present(relativeTo: anchor) }
        }])])
        defer { f.close() }
        captured = f.flyout; anchor = f.anchor
        let old = f.root
        XCTAssertTrue(try f.button("Branch").accessibilityPerformPress())
        XCTAssertTrue(try f.row("Replace", in: f.child()).accessibilityPerformPress())
        XCTAssertTrue(f.flyout.isPresented)
        XCTAssertFalse(old.isVisible)
        XCTAssertTrue(try f.button("New").isEnabled)
    }

    func testHiddenOwnerAndRootAnchorRemovalCloseAttachedMenus() throws {
        for hideOwner in [false, true] {
            let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Leaf") {}])])
            defer { f.close() }
            let button = try f.button("Branch")
            XCTAssertTrue(button.accessibilityPerformPress())
            let child = try f.child()
            if hideOwner { button.isHidden = true } else { f.anchor.removeFromSuperview() }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
            XCTAssertFalse(child.isVisible)
            XCTAssertFalse(button.isAccessibilityExpanded())
            XCTAssertEqual(f.flyout.isPresented, hideOwner)
        }
    }

    func testNativeModelPreservesManualAttachmentsUntilItOwnsTheConfiguration() throws {
        let bar = FluentCommandBar(primaryCommands: [.init(id: 1, "Native") {}])
        let button = try XCTUnwrap(bar.primaryCommandViews.first as? FluentAppBarButton)
        button.flyoutItems = [.init("Manual") {}]
        bar.primaryCommands = [.init(id: 1, "Renamed") {}]
        XCTAssertTrue(bar.primaryCommandViews.first === button)
        XCTAssertEqual(button.flyoutItems?.first?.title, "Manual")
        bar.primaryCommands = [.init(id: 1, "Model", flyoutItems: [.init("Model leaf") {}])]
        XCTAssertEqual(button.flyoutItems?.first?.title, "Model leaf")
        bar.primaryCommands = [.init(id: 1, "Cleared") {}]
        XCTAssertNil(button.flyoutItems)
        button.flyoutItems = [.init("Manual again") {}]
        bar.primaryCommands = [.init(id: 1, "Explicit clear", flyoutItems: [])]
        XCTAssertTrue(button.flyoutItems?.isEmpty == true)
    }

    func testNativeOverflowUsesSharedModelAndUpdatesItsOpenMenu() throws {
        var calls = 0
        let f = Fixture(primary: [.init("Unused") {}]); defer { f.close() }
        f.flyout.dismiss()
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [
            .init(id: "branch", "Branch", flyoutItems: [.init(id: "leaf", "Old") {}])])
        bar.reduceMotion = true
        bar.frame = NSRect(x: 120, y: 260, width: 260, height: 48)
        f.window.contentView!.addSubview(bar)
        bar.layoutSubtreeIfNeeded(); bar.setOpen(true, animated: false)
        defer { bar.setOpen(false, animated: false) }
        let button = try XCTUnwrap(bar.secondaryCommandViews.first as? FluentAppBarButton)
        XCTAssertTrue(button.accessibilityPerformPress())
        let root = try XCTUnwrap(f.window.childWindows?.first)
        let child = try XCTUnwrap(root.childWindows?.first)
        let row = try f.row("Old", in: child)
        bar.secondaryCommands = [.init(id: "branch", "Branch",
            flyoutItems: [.init(id: "leaf", "New") { calls += 1 }])]
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(try f.row("New", in: child) === row)
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(bar.isOpen)
    }

    func testPrimaryCallbackRemovingItsOwnerDoesNotOpenAnOrphan() throws {
        weak var target: FluentCommandBarFlyout?
        let f = Fixture(primary: [.init(id: 1, "Remove", flyoutItems: [.init("Leaf") {}]) {
            target?.update(configuration: .init(primaryCommands: [.init(id: 2, "Remaining") {}]))
        }]); defer { f.close() }
        target = f.flyout
        let old = try f.button("Remove")
        XCTAssertTrue(old.accessibilityPerformPress())
        XCTAssertTrue(f.flyout.isPresented)
        XCTAssertTrue(f.root.childWindows?.isEmpty != false)
        XCTAssertFalse(old.accessibilityPerformPress())
        XCTAssertTrue(try f.button("Remaining").isEnabled)
    }

    func testLeafOpeningAPeerAttachmentKeepsTheNewBranch() throws {
        weak var peer: NSButton?
        let f = Fixture(secondary: [
            .init(id: 1, "First", flyoutItems: [.init("Next") { _ = peer?.accessibilityPerformPress() }]),
            .init(id: 2, "Second", flyoutItems: [.init("Fresh") {}])])
        defer { f.close() }
        peer = try f.button("Second")
        XCTAssertTrue(try f.button("First").accessibilityPerformPress())
        let old = try f.child()
        XCTAssertTrue(try f.row("Next", in: old).accessibilityPerformPress())
        let current = try f.child()
        XCTAssertFalse(current === old)
        XCTAssertFalse(old.isVisible)
        XCTAssertTrue(f.flyout.isPresented)
        XCTAssertTrue(peer?.isAccessibilityExpanded() == true)
        XCTAssertNotNil(try f.row("Fresh", in: current))
    }

    func testAttachedMenuReceivesThemeChangesWithoutReplacingItsFocus() throws {
        let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Leaf") {}])])
        defer { f.close() }
        XCTAssertTrue(try f.button("Branch").accessibilityPerformPress())
        let child = try f.child(), row = try f.row("Leaf", in: child)
        let responder = child.firstResponder
        for dark in [true, false] {
            f.flyout.update(theme: .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false),
                            reduceMotion: true)
            XCTAssertTrue(try f.child() === child)
            XCTAssertTrue(try f.row("Leaf", in: child) === row)
            XCTAssertTrue(child.firstResponder === responder)
            XCTAssertEqual(child.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), dark ? .darkAqua : .aqua)
        }
    }

    func testAttachedMenuDensityUsesItsActualOpeningDevice() throws {
        for primary in [false, true] { for touch in [false, true] {
            let item = FluentCommandBarItem("Branch", flyoutItems: [.init("Leaf") {}])
            let f = Fixture(primary: primary ? [item] : [], secondary: primary ? [] : [item])
            defer { f.close() }
            FluentInputDeviceTracker.shared.record(touch ? .touch : .mouse, in: f.root)
            try f.button("Branch").performClick(nil)
            let row = try f.row("Leaf", in: f.child())
            // The menu layout is 36pt for pointer/keyboard and 44pt for direct touch, with
            // 2pt of vertical item inset. This is a device-policy check, not a touch-screen test.
            XCTAssertEqual(row.frame.height, touch ? 40 : 32)
        } }
    }

    func testUnrelatedEscapeDoesNotDismissTheRootOrItsAttachment() throws {
        let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Leaf") {}])])
        defer { f.close() }
        XCTAssertTrue(try f.button("Branch").accessibilityPerformPress())
        let child = try f.child()
        let other = NSPanel(contentRect: NSRect(x: 950, y: 200, width: 160, height: 120),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        XCTAssertTrue(other.isKeyWindow)
        f.key(53, in: other)
        XCTAssertTrue(f.flyout.isPresented)
        XCTAssertTrue(child.isVisible)
    }

    func testReparentedCommandCannotOpenMenusThroughItsFormerOwner() throws {
        let f = Fixture(secondary: [.init("Branch", flyoutItems: [.init("Leaf") {}])])
        defer { f.close() }
        let button = try f.button("Branch")
        XCTAssertTrue(button.accessibilityPerformPress())
        let child = try f.child()
        button.removeFromSuperview()
        f.window.contentView!.addSubview(button)
        XCTAssertFalse(child.isVisible)
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertFalse(button.isAccessibilityExpanded())
        XCTAssertTrue(f.flyout.isPresented)
    }

    func testNativeAcceleratorPaintUsesTheShortcutInsteadOfTheCommandTitle() throws {
        for dark in [false, true] { for rtl in [false, true] {
            let f = Fixture(primary: [.init("Unused") {}]); defer { f.close() }
            f.flyout.dismiss()
            let button = FluentAppBarButton("Alpha", flyoutItems: [.init("Leaf") {}])
            button.useOverflowStyle = true
            button.reduceMotion = true
            button.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            button.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            button.keyboardAcceleratorTextOverride = "⌘B"
            button.frame = NSRect(x: 40, y: 60, width: 320, height: 40)
            f.window.contentView!.addSubview(button)
            func pixels() throws -> [UInt8] {
                button.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
                button.cacheDisplay(in: button.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / button.bounds.width
                let x0: CGFloat = rtl ? 36 : 260
                var values: [UInt8] = []
                for y in Int(8 * scale)..<Int(32 * scale) {
                    for x in Int(x0 * scale)..<Int((x0 + 24) * scale) {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        // cacheDisplay has a transparent background. Alpha distinguishes black
                        // shortcut glyphs from transparent black pixels in the light theme.
                        values += [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map {
                            UInt8(max(0, min(255, ($0 * 255).rounded())))
                        }
                    }
                }
                return values
            }
            let original = try pixels()
            button.label = "Zulu"
            let renamed = try pixels()
            XCTAssertEqual(original, renamed, "Changing the title must not repaint it in the shortcut column")
            button.keyboardAcceleratorTextOverride = "⌘X"
            XCTAssertNotEqual(renamed, try pixels(), "The sampled column must contain the actual shortcut glyphs")
        } }
    }
}
