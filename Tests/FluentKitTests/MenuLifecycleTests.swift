import XCTest
@testable import FluentKit

final class MenuLifecycleTests: XCTestCase {
    @MainActor private func mount(_ bar: FluentMenuBar) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 320))
        window.contentView = stage
        stage.addSubview(bar)
        bar.frame = NSRect(x: 24, y: 240, width: 500, height: 40)
        bar.reduceMotion = true
        window.makeKeyAndOrderFront(nil)
        bar.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor private func rows(_ panel: NSWindow) -> [NSView] {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return panel.contentView.map { all($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } } ?? []
    }

    @MainActor private func key(_ code: UInt16, in panel: NSWindow, characters: String = "") throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        panel.sendEvent(event)
    }

    @MainActor
    func testDeclarativeRefreshKeepsOpenMenuRowsSelectionAndLatestAction() throws {
        _ = NSApplication.shared
        var actions: [String] = []
        func content(_ revision: String) -> FluentMenuBarView {
            FluentMenuBarView(items: [FluentMenuBarItem(id: "file", "File", items: [
                FluentMenuItem("First") {}, FluentMenuItem("Second") { actions.append(revision) }
            ])])
        }
        let context = FluentRenderContext(reduceMotion: true)
        let bar = try XCTUnwrap(content("old")._makeView(in: context) as? FluentMenuBar)
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        bar.openItem(at: 0)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let original = rows(panel)
        let responder = panel.firstResponder
        try key(119, in: panel)
        XCTAssertTrue(original[1].isAccessibilitySelected())
        for _ in 0..<5 { XCTAssertTrue(content("new")._updateView(bar, in: context)); bar.layoutSubtreeIfNeeded() }
        XCTAssertTrue(bar.isFlyoutOpen)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.firstResponder === responder)
        XCTAssertEqual(rows(panel).count, 2)
        XCTAssertTrue(rows(panel).last === original.last)
        XCTAssertTrue(original[1].isAccessibilitySelected())
        if bar.isFlyoutOpen { try key(36, in: panel) }
        XCTAssertEqual(actions, ["new"])
        XCTAssertFalse(bar.isFlyoutOpen)
    }

    @MainActor
    func testTopLevelReorderPreservesOpenAnchorAndUsesItsNewNavigationIndex() throws {
        _ = NSApplication.shared
        let file = FluentMenuBarItem(id: "file", "File", items: [FluentMenuItem("Open") {}])
        let view = FluentMenuBarItem(id: "view", "View", items: [FluentMenuItem("Zoom") {}])
        let help = FluentMenuBarItem(id: "help", "Help", items: [FluentMenuItem("About") {}])
        let bar = FluentMenuBar(items: [file, view, help])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        let original = bar.itemControlViews
        bar.openItem(at: 0)
        let panel = try XCTUnwrap(window.childWindows?.first)
        bar.items = [view, file, help]
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.itemControlViews[1] === original[0])
        XCTAssertTrue(bar.itemControlViews[0] === original[1])
        XCTAssertEqual(bar.openItemIndex, 1)
        XCTAssertTrue(window.childWindows?.first === panel)
        if bar.isFlyoutOpen { try key(124, in: panel) }
        XCTAssertEqual(bar.openItemIndex, 2)
    }
    @MainActor
    func testNestedStableIDsKeepPanelsRowsSelectionAndLatestLeafAction() throws {
        _ = NSApplication.shared
        var invoked = ""
        func export(_ revision: String, reversed: Bool) -> FluentMenuItem {
            let leaves = [FluentMenuItem(id: "png", "PNG") { invoked = "PNG \(revision)" },
                          FluentMenuItem(id: "svg", "SVG \(revision)") { invoked = "SVG \(revision)" }]
            return FluentMenuItem(id: "export", "Export", submenu: reversed ? leaves.reversed() : leaves, action: {})
        }
        let bar = FluentMenuBar(items: [FluentMenuBarItem(id: "file", "File", items: [export("old", reversed: false)])])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        bar.openItem(at: 0)
        let root = try XCTUnwrap(window.childWindows?.first)
        let branch = try XCTUnwrap(rows(root).first)
        try key(115, in: root)
        try key(124, in: root)
        let child = try XCTUnwrap(root.childWindows?.first)
        let svg = try XCTUnwrap(rows(child).last)
        let originalOrigin = child.frame.origin
        try key(119, in: child)
        bar.items = [FluentMenuBarItem(id: "file", "Renamed file", items: [
            FluentMenuItem(id: "new", "New item") {}, export("new with a much longer title", reversed: true)
        ])]
        XCTAssertTrue(window.childWindows?.first === root)
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(rows(root).contains { $0 === branch })
        XCTAssertTrue(rows(child).contains { $0 === svg })
        XCTAssertTrue(svg.isAccessibilitySelected())
        XCTAssertLessThan(svg.frame.minY, rows(child).first { $0 !== svg }!.frame.minY)
        XCTAssertNotEqual(child.frame.origin, originalOrigin)
        let host = try XCTUnwrap(child.contentView as? FluentPopupTransitionHost)
        XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds)
        try key(36, in: child)
        XCTAssertEqual(invoked, "SVG new with a much longer title")
        XCTAssertFalse(bar.isFlyoutOpen)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor
    func testDisabledBranchClosesOnlyItsSubmenuAndRecoversRootSelection() throws {
        _ = NSApplication.shared
        var invoked = false
        func content(enabled: Bool) -> [FluentMenuItem] {
            [FluentMenuItem(id: "export", "Export", isEnabled: enabled, submenu: [FluentMenuItem("PNG") {}], action: {}),
             FluentMenuItem(id: "other", "Other") { invoked = true }]
        }
        let bar = FluentMenuBar(items: [FluentMenuBarItem("File", items: content(enabled: true))])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        bar.openItem(at: 0)
        let root = try XCTUnwrap(window.childWindows?.first)
        try key(115, in: root); try key(124, in: root)
        XCTAssertEqual(root.childWindows?.count, 1)
        bar.items = [FluentMenuBarItem("File", items: content(enabled: false))]
        XCTAssertTrue(bar.isFlyoutOpen)
        XCTAssertTrue(root.childWindows?.isEmpty ?? true)
        XCTAssertTrue(rows(root).first { $0.accessibilityTitle() == "Other" }!.isAccessibilitySelected())
        try key(36, in: root)
        XCTAssertTrue(invoked)
    }

    @MainActor
    func testRemovedDisabledOrEmptyTopLevelItemsCloseTheirMenuSafely() throws {
        _ = NSApplication.shared
        let file = FluentMenuBarItem(id: "file", "File", items: [FluentMenuItem("Open") {}])
        let help = FluentMenuBarItem(id: "help", "Help", items: [FluentMenuItem("About") {}])
        let bar = FluentMenuBar(items: [help, file])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        for replacement in [[], [help], [help, FluentMenuBarItem(id: "file", "File", isEnabled: false, items: file.items)],
                            [help, FluentMenuBarItem(id: "file", "File", items: [])]] {
            bar.items = [help, file]
            bar.openItem(at: 1)
            bar.items = replacement
            XCTAssertFalse(bar.isFlyoutOpen)
            XCTAssertTrue(window.childWindows?.isEmpty ?? true)
            for index in bar.items.indices where !bar.items[index].isEnabled {
                XCTAssertFalse((bar.itemControlViews[index] as? NSControl)?.isEnabled ?? true)
            }
        }
        bar.items = [file]
        bar.openItem(at: 0)
        bar.removeFromSuperview()
        XCTAssertFalse(bar.isFlyoutOpen)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor
    func testStandaloneUpdateChangesSlotsStateAndSizeWithoutChangingOpeningDevice() throws {
        _ = NSApplication.shared
        let bar = FluentMenuBar(items: [FluentMenuBarItem("Anchor", items: [])])
        let window = mount(bar)
        let flyout = FluentMenuFlyout(items: [], reduceMotion: true)
        defer { flyout.dismiss(); window.close() }
        flyout.update(items: [FluentMenuItem(id: "a", "First") {}])
        FluentInputDeviceTracker.shared.record(.touch, in: window)
        flyout.present(relativeTo: bar.itemControlViews[0], placement: .below)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = try XCTUnwrap(rows(panel).first)
        let originalHeight = row.frame.height
        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        flyout.update(items: [FluentMenuItem(id: "a", "A much longer replacement label", systemImageName: "star", state: .on,
            selectionIndicator: .pill, keyEquivalent: "s") {}, FluentMenuItem("Second") {}])
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(rows(panel).first === row)
        XCTAssertEqual(row.accessibilityTitle(), "A much longer replacement label")
        XCTAssertEqual(row.accessibilityValue() as? String, "Selected")
        XCTAssertEqual(row.frame.height, originalHeight)
        XCTAssertEqual(flyout.inputDeviceTypeUsedToOpen, .touch)
        XCTAssertNotNil(row.subviews.first { $0 is NSImageView })
        XCTAssertNotNil(row.layer?.sublayers?.first { $0.name == "FluentKit.ComboBoxItem.SelectionPill" })
        flyout.update(items: [FluentMenuItem(id: "a", "Off", isEnabled: false) {}])
        XCTAssertFalse(row.isAccessibilityEnabled())
        XCTAssertNil(row.subviews.first { $0 is NSImageView })
        XCTAssertNil(row.layer?.sublayers?.first { $0.name == "FluentKit.ComboBoxItem.SelectionPill" })
        flyout.update(items: [])
        XCTAssertFalse(flyout.isPresented)
    }

    @MainActor
    func testOpenRootAndSubmenuFollowAnchorMovesAndDirectionChanges() throws {
        _ = NSApplication.shared
        let bar = FluentMenuBar(items: [FluentMenuBarItem("File", items: [
            .submenu("Export") { FluentMenuItem("PNG") {} }
        ])])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        bar.openItem(at: 0)
        let root = try XCTUnwrap(window.childWindows?.first)
        try key(115, in: root); try key(124, in: root)
        let child = try XCTUnwrap(root.childWindows?.first)
        let x = root.frame.minX
        bar.setFrameOrigin(NSPoint(x: 64, y: 240))
        XCTAssertEqual(root.frame.minX - x, 40, accuracy: 0.5)
        bar.userInterfaceLayoutDirection = .rightToLeft
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.childWindows?.first === root)
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertLessThan(child.frame.maxX, root.frame.maxX)
        XCTAssertTrue(rows(root).allSatisfy { $0.userInterfaceLayoutDirection == .rightToLeft })
        try key(124, in: child) // Physical Right closes an RTL submenu.
        XCTAssertTrue(root.childWindows?.isEmpty ?? true)
        XCTAssertTrue(bar.isFlyoutOpen)
    }

    @MainActor
    func testPendingHoverTracksRetainedIdentityAndNeverOpensAReplacementRow() throws {
        _ = NSApplication.shared
        let branch = FluentMenuItem.submenu(id: "export", "Export") { FluentMenuItem("PNG") {} }
        let other = FluentMenuItem(id: "other", "Other") {}
        let bar = FluentMenuBar(items: [FluentMenuBarItem("File", items: [branch, other])])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        bar.openItem(at: 0)
        let root = try XCTUnwrap(window.childWindows?.first)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: root.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        rows(root)[0].mouseEntered(with: event)
        bar.items = [FluentMenuBarItem("File", items: [other, branch])]
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(root.childWindows?.count, 1)
        try key(123, in: try XCTUnwrap(root.childWindows?.first))
        let retained = try XCTUnwrap(rows(root).first { $0.accessibilityTitle() == "Export" })
        retained.mouseEntered(with: event)
        bar.items = [FluentMenuBarItem("File", items: [other, .submenu(id: "replacement", "Different") { FluentMenuItem("Other child") {} }])]
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertTrue(root.childWindows?.isEmpty ?? true)
    }

    @MainActor
    func testMenuBuildersComposeConditionsLoopsArraysAndEmptyBranches() {
        func menu(showExtra: Bool) -> FluentMenuBarView {
            FluentMenuBarView {
                FluentMenuBarItem("File") {
                    FluentMenuItem("First") {}
                    if showExtra { FluentMenuItem("Extra") {} }
                    for number in 0..<2 { FluentMenuItem("Item \(number)") {} }
                    [FluentMenuItem("Array item") {}]
                    FluentMenuItem.submenu("Empty") {}
                }
                if showExtra { FluentMenuBarItem("Help", items: []) }
            }
        }
        XCTAssertEqual(menu(showExtra: false).items.count, 1)
        XCTAssertEqual(menu(showExtra: true).items.count, 2)
        XCTAssertEqual(menu(showExtra: true).items[0].items.map(\.title),
                       ["First", "Extra", "Item 0", "Item 1", "Array item", "Empty"])
        XCTAssertTrue(menu(showExtra: true).items[0].items.last!.submenu.isEmpty)
        XCTAssertTrue(FluentMenuBarView {}.items.isEmpty)
    }

    @MainActor
    func testContextMenuRefreshUpdatesWrappedContentAndOpenMenuAction() throws {
        _ = NSApplication.shared
        var invoked = ""
        func content(_ revision: String) -> FluentContextMenuView<FluentTextView> {
            FluentText(revision).contextMenu { FluentMenuItem(revision) { invoked = revision } }
        }
        let context = FluentRenderContext(reduceMotion: true)
        let bar = FluentMenuBar(items: [])
        let window = mount(bar)
        defer { window.close() }
        let host = content("Old")._makeView(in: context)
        window.contentView?.addSubview(host)
        host.frame = NSRect(x: 20, y: 100, width: 300, height: 40)
        host.layoutSubtreeIfNeeded()
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 60, y: 120), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        host.rightMouseDown(with: event)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = try XCTUnwrap(rows(panel).first)
        XCTAssertTrue(content("New")._updateView(host, in: context))
        func labels(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(labels) }
        XCTAssertEqual(labels(host).first?.stringValue, "New")
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual(row.accessibilityTitle(), "New")
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(invoked, "New")
        host.rightMouseDown(with: event)
        host.removeFromSuperview()
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor
    func testLiveTypographyChangeResizesAnchorAndMenuWithoutLosingSelection() throws {
        _ = NSApplication.shared
        let bar = FluentMenuBar(items: [FluentMenuBarItem("Document actions", items: [
            FluentMenuItem("A long command title that requires measuring") {}
        ])])
        let window = mount(bar)
        defer { bar.closeMenu(); window.close() }
        bar.openItem(at: 0)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = try XCTUnwrap(rows(panel).first)
        try key(115, in: panel)
        let buttonWidth = bar.itemControlViews[0].frame.width
        let popupWidth = panel.frame.width
        bar.theme = FluentTheme.custom(colorScheme: .dark, typography: FluentTypography(scale: 1.5), materialEffectsEnabled: false)
        bar.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(bar.itemControlViews[0].frame.width, buttonWidth)
        XCTAssertGreaterThan(panel.frame.width, popupWidth)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(row.isAccessibilitySelected())
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds)
    }

    @MainActor
    func testQueuedClickCannotInvokeAfterItsRowIsRemovedOrMenuIsDismissed() throws {
        _ = NSApplication.shared
        var actions = 0
        let bar = FluentMenuBar(items: [FluentMenuBarItem("Anchor", items: [])])
        let window = mount(bar)
        let flyout = FluentMenuFlyout(items: [FluentMenuItem(id: "first", "First") { actions += 1 }], reduceMotion: true)
        defer { flyout.dismiss(); window.close() }
        flyout.present(relativeTo: bar.itemControlViews[0])
        let panel = try XCTUnwrap(window.childWindows?.first)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let removed = try XCTUnwrap(rows(panel).first)
        removed.mouseDown(with: event)
        flyout.update(items: [FluentMenuItem(id: "second", "Second") { actions += 1 }])
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(actions, 0)
        let dismissed = try XCTUnwrap(rows(panel).first)
        dismissed.mouseDown(with: event)
        flyout.dismiss(animated: false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(actions, 0, "A queued action must lose authority when its presenter closes")
        flyout.present(relativeTo: bar.itemControlViews[0])
        try key(53, in: panel)
        XCTAssertTrue(flyout.isPresented, "Escape delivered to an old presenter must not close the new menu")
        withExtendedLifetime((panel, removed, dismissed)) {}
    }

}
