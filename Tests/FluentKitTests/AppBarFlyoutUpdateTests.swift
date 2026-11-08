import XCTest
@testable import FluentKit

@MainActor
final class AppBarFlyoutUpdateTests: XCTestCase {
    private func mount(_ items: [FluentMenuItem], reduceMotion: Bool = true) -> (NSWindow, FluentAppBarButton) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 520, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        let button = FluentAppBarButton("Menu", flyoutItems: items)
        button.theme = .custom(colorScheme: .light, materialEffectsEnabled: false)
        button.reduceMotion = reduceMotion
        window.contentView!.addSubview(button)
        button.frame = NSRect(x: 180, y: 220, width: 120, height: 64)
        window.orderFront(nil)
        button.showFlyout()
        return (window, button)
    }

    private func rows(_ panel: NSWindow) -> [NSView] {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return panel.contentView.map {
            all($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }.sorted { $0.frame.minY < $1.frame.minY }
        } ?? []
    }

    private func key(_ code: UInt16, in panel: NSWindow) throws {
        panel.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)))
    }

    private func preparePausedEntrance(_ panel: NSWindow) throws -> FluentPopupTransitionHost {
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        let layer = try XCTUnwrap(host.layer)
        layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        // Re-arm the real entrance on a fixed clock; runner delays must not decide whether
        // an animation survives a live policy change.
        fluentPrepareMenuPopupEntrance(host: host, edge: .top, motion: FluentMotion.menuOpen,
                                      closedRatio: 0.5, reduceMotion: false)
        XCTAssertNotNil(host.revealMaskLayer.animation(forKey: "fluent.popup.clip.open"))
        return host
    }

    private func assertSettled(_ host: FluentPopupTransitionHost,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(host.animationCoordinator.reduceMotion, file: file, line: line)
        for layer in [host.animationRoot.layer!, host.surface.layer!, host.revealMaskLayer] {
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty, file: file, line: line)
            XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, CATransform3DIdentity), file: file, line: line)
        }
        XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds, file: file, line: line)
    }

    func testLiveItemReplacementKeepsPanelRowsFocusAndUsesLatestAction() throws {
        var actions: [String] = []
        let (window, button) = mount([FluentMenuItem(id: "item", "Old") { actions.append("old") }])
        defer { button.hideFlyout(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = try XCTUnwrap(rows(panel).first)
        try key(115, in: panel)
        let responder = panel.firstResponder
        for revision in 1...3 {
            button.flyoutItems = [FluentMenuItem(id: "item", "Revision \(revision)", state: .on) {
                actions.append("revision \(revision)")
            }]
            XCTAssertTrue(window.childWindows?.first === panel)
            XCTAssertTrue(rows(panel).first === row)
            XCTAssertTrue(panel.firstResponder === responder)
            XCTAssertTrue(row.isAccessibilitySelected())
            XCTAssertEqual(row.accessibilityTitle(), "Revision \(revision)")
            XCTAssertTrue(button.isFlyoutPresented)
        }
        try key(36, in: panel)
        XCTAssertEqual(actions, ["revision 3"])
        XCTAssertFalse(button.isFlyoutPresented)
    }

    func testStableIDReorderRetainsSelectionAndResizesTheOpenClip() throws {
        var invoked = ""
        let (window, button) = mount([
            FluentMenuItem(id: "first", "First") {},
            FluentMenuItem(id: "second", "Second") { invoked = "old" }
        ])
        defer { button.hideFlyout(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        let original = rows(panel)
        try key(119, in: panel)
        let oldWidth = panel.frame.width
        button.flyoutItems = [
            FluentMenuItem(id: "second", "Second with a much longer updated title") { invoked = "new" },
            FluentMenuItem(id: "inserted", "Inserted") {},
            FluentMenuItem(id: "first", "First") {}
        ]
        XCTAssertEqual(rows(panel).count, 3)
        XCTAssertTrue(rows(panel).first === original[1])
        XCTAssertTrue(rows(panel).last === original[0])
        XCTAssertTrue(original[1].isAccessibilitySelected())
        XCTAssertGreaterThan(panel.frame.width, oldWidth)
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds)
        try key(36, in: panel)
        XCTAssertEqual(invoked, "new")
    }

    func testOpenSubmenuReceivesUpdatedLeafWithoutReplacingPresentation() throws {
        var invoked = ""
        let branch = FluentMenuItem(id: "branch", "Branch", submenu: [
            FluentMenuItem(id: "leaf", "Old leaf") { invoked = "old" }
        ], action: {})
        let (window, button) = mount([branch])
        defer { button.hideFlyout(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        _ = rows(panel)[0].accessibilityPerformPress()
        let child = try XCTUnwrap(panel.childWindows?.first)
        let leaf = try XCTUnwrap(rows(child).first)
        let responder = child.firstResponder
        button.flyoutItems = [FluentMenuItem(id: "branch", "Updated branch", submenu: [
            FluentMenuItem(id: "leaf", "Updated leaf") { invoked = "new" }
        ], action: {})]
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.childWindows?.first === child)
        XCTAssertTrue(rows(child).first === leaf)
        XCTAssertTrue(child.firstResponder === responder)
        XCTAssertEqual(leaf.accessibilityTitle(), "Updated leaf")
        try key(36, in: child)
        XCTAssertEqual(invoked, "new")
        XCTAssertFalse(button.isFlyoutPresented)
    }

    func testDisablingAnOpenBranchClosesItsChildAndDisablesTheRetainedRow() throws {
        let branch = FluentMenuItem(id: "branch", "Branch", submenu: [FluentMenuItem("Leaf") {}], action: {})
        let (window, button) = mount([branch, FluentMenuItem(id: "other", "Other") {}])
        defer { button.hideFlyout(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = rows(panel)[0]
        try key(115, in: panel)
        try key(124, in: panel)
        XCTAssertEqual(panel.childWindows?.count, 1)
        button.flyoutItems = [FluentMenuItem(id: "branch", "Disabled", isEnabled: false,
                                           submenu: branch.submenu, action: {}), FluentMenuItem(id: "other", "Other") {}]
        XCTAssertTrue(button.isFlyoutPresented)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.childWindows?.isEmpty ?? true)
        XCTAssertTrue(rows(panel).first === row)
        XCTAssertFalse(row.isAccessibilityEnabled())
        XCTAssertFalse(row.accessibilityPerformPress())
        XCTAssertTrue(rows(panel).last!.isAccessibilitySelected())
    }

    func testClearingItemsClosesAndRepopulatingDoesNotOpenUntilRequested() throws {
        for empty: [FluentMenuItem]? in [nil, []] {
            let (window, button) = mount([FluentMenuItem("Old") {}])
            defer { button.hideFlyout(animated: false); window.close() }
            button.flyoutItems = empty
            XCTAssertFalse(button.isFlyoutPresented)
            XCTAssertFalse(button.isAccessibilityExpanded())
            XCTAssertTrue(window.childWindows?.isEmpty ?? true)
            button.flyoutItems = [FluentMenuItem("New") {}]
            XCTAssertFalse(button.isFlyoutPresented)
            button.showFlyout()
            let panel = try XCTUnwrap(window.childWindows?.first)
            XCTAssertEqual(rows(panel).first?.accessibilityTitle(), "New")
        }
    }

    func testUpdatedActionCanReopenWithNewItemsWithoutOldDismissClearingIt() throws {
        var oldInvoked = false
        let (window, button) = mount([FluentMenuItem(id: "item", "Old") { oldInvoked = true }])
        defer { button.hideFlyout(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        button.flyoutItems = [FluentMenuItem(id: "item", "Reopen") { [weak button] in
            button?.hideFlyout(animated: false)
            button?.flyoutItems = [FluentMenuItem("Replacement") {}]
            button?.showFlyout()
        }]
        _ = rows(panel)[0].accessibilityPerformPress()
        XCTAssertFalse(oldInvoked)
        XCTAssertTrue(button.isFlyoutPresented)
        let replacement = try XCTUnwrap(window.childWindows?.first)
        XCTAssertFalse(replacement === panel)
        XCTAssertEqual(rows(replacement).first?.accessibilityTitle(), "Replacement")
    }

    func testLiveReducedMotionSettlesAllOpenLevelsAndGovernsFutureChildren() throws {
        let (window, button) = mount([FluentMenuItem(id: "branch", "Branch", submenu: [
            FluentMenuItem("Leaf") {}
        ], action: {})], reduceMotion: false)
        defer { button.hideFlyout(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        _ = rows(panel)[0].accessibilityPerformPress()
        let child = try XCTUnwrap(panel.childWindows?.first)
        let rootHost = try preparePausedEntrance(panel)
        let childHost = try preparePausedEntrance(child)
        let responder = child.firstResponder
        button.reduceMotion = true
        assertSettled(rootHost)
        assertSettled(childHost)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.childWindows?.first === child)
        XCTAssertTrue(child.firstResponder === responder)
        try key(53, in: child)
        _ = rows(panel)[0].accessibilityPerformPress()
        let reducedChild = try XCTUnwrap(panel.childWindows?.first)
        assertSettled(try XCTUnwrap(reducedChild.contentView as? FluentPopupTransitionHost))
        try key(53, in: reducedChild)
        button.reduceMotion = false
        XCTAssertFalse(rootHost.animationCoordinator.reduceMotion)
        XCTAssertNil(rootHost.revealMaskLayer.animation(forKey: "fluent.popup.clip.open"))
        _ = rows(panel)[0].accessibilityPerformPress()
        let restoredChild = try XCTUnwrap(panel.childWindows?.first?.contentView as? FluentPopupTransitionHost)
        XCTAssertFalse(restoredChild.animationCoordinator.reduceMotion)
    }

    func testDirectFlyoutUpdateAlsoSettlesAnExistingEntrance() throws {
        let (window, button) = mount([FluentMenuItem("Anchor") {}])
        button.hideFlyout(animated: false)
        let items = [FluentMenuItem("Item") {}]
        let flyout = FluentMenuFlyout(items: items, reduceMotion: false)
        defer { flyout.dismiss(animated: false); window.close() }
        flyout.present(relativeTo: button)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let host = try preparePausedEntrance(panel)
        flyout.update(items: items, reduceMotion: true)
        assertSettled(host)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(flyout.isPresented)
    }
}
