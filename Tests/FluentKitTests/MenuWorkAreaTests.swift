import XCTest
@testable import FluentKit

final class MenuWorkAreaTests: XCTestCase {
    @MainActor private func mount() -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 700, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 250, y: 180, width: 160, height: 32))
        window.contentView!.addSubview(anchor)
        window.makeKeyAndOrderFront(nil)
        return (window, anchor)
    }

    @MainActor private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @MainActor private func key(_ code: UInt16, in panel: NSWindow, characters: String = "") throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
        panel.firstResponder?.keyDown(with: event)
    }

    @MainActor func testLongMenusFitWorkAreaAndKeyboardCanRevealAndInvokeTheLastItem() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        var invoked: Int?
        let menu = FluentMenuFlyout(items: (0..<50).map { (i: Int) in FluentMenuItem(id: i, "Option \(i)") { invoked = i } },
                                    matchesAnchorWidth: false, reduceMotion: true)
        defer { menu.dismiss(animated: false) }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let work = NSScreen.main!.visibleFrame
        XCTAssertGreaterThanOrEqual(panel.frame.minY, work.minY)
        XCTAssertLessThanOrEqual(panel.frame.maxY, work.maxY)
        XCTAssertLessThanOrEqual(panel.frame.height, work.height)
        let scroll = try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSScrollView }.first)
        XCTAssertTrue(scroll.hasVerticalScroller)
        let rows = all(panel.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
        XCTAssertEqual(rows.count, 50)
        try key(119, in: panel)
        let last = try XCTUnwrap(rows.last)
        XCTAssertTrue(last.isAccessibilitySelected())
        XCTAssertTrue(scroll.documentVisibleRect.contains(last.frame))
        try key(115, in: panel)
        XCTAssertTrue(scroll.documentVisibleRect.contains(rows[0].frame))
        try key(119, in: panel)
        try key(36, in: panel)
        XCTAssertEqual(invoked, 49)
        XCTAssertFalse(menu.isPresented)
    }

    @MainActor func testLongTitleDoesNotGrowPastWorkAreaInEitherDirection() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        for direction in [NSUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            anchor.userInterfaceLayoutDirection = direction
            let menu = FluentMenuFlyout(items: [FluentMenuItem(String(repeating: "Long title 很长的菜单标题 ", count: 40)) {}],
                                        matchesAnchorWidth: false, reduceMotion: true)
            menu.present(relativeTo: anchor)
            let panel = try XCTUnwrap(window.childWindows?.first)
            let work = NSScreen.main!.visibleFrame
            XCTAssertGreaterThanOrEqual(panel.frame.minX, work.minX)
            XCTAssertLessThanOrEqual(panel.frame.maxX, work.maxX)
            XCTAssertLessThanOrEqual(panel.frame.width, work.width)
            menu.dismiss(animated: false)
        }
    }
    @MainActor func testNestedMenusScrollToLastLeafAndCloseWhenTheirParentAnchorIsClipped() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        for rtl in [false, true] {
            anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            var invoked: Int?
            let leaves = (0..<50).map { (i: Int) in FluentMenuItem(id: i, "Leaf \(i)") { invoked = i } }
            let items = Array(leaves.prefix(40)) + [FluentMenuItem(id: "branch", "Last branch", submenu: leaves, action: {})]
            let menu = FluentMenuFlyout(items: items, matchesAnchorWidth: false, reduceMotion: true)
            menu.present(relativeTo: anchor)
            let panel = try XCTUnwrap(window.childWindows?.first)
            let scroll = try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSScrollView }.first)
            try key(119, in: panel)
            try key(rtl ? 123 : 124, in: panel)
            let child = try XCTUnwrap(panel.childWindows?.first)
            XCTAssertTrue(NSScreen.main!.visibleFrame.contains(child.frame))
            try key(119, in: child)
            let last = try XCTUnwrap(all(child.contentView!).last { $0.identifier?.rawValue == "FluentKit.Menu.Item" })
            XCTAssertTrue(last.visibleRect.contains(last.bounds))
            // Direct clip scrolling avoids AppKit's synthetic scrollWheel elastic-loop path.
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            let branch = all(panel.contentView!).last { $0.identifier?.rawValue == "FluentKit.Menu.Item" }!
            XCTAssertFalse(branch.visibleRect.intersects(branch.bounds))
            waitForUI(child.parent == nil)
            XCTAssertFalse(child.isVisible)
            XCTAssertTrue(menu.isPresented)
            try key(119, in: panel)
            try key(rtl ? 123 : 124, in: panel)
            let reopened = try XCTUnwrap(panel.childWindows?.first)
            try key(119, in: reopened)
            try key(36, in: reopened)
            XCTAssertEqual(invoked, 49)
            XCTAssertFalse(menu.isPresented)
        }
    }

    @MainActor func testUpdatesKeepSelectedRowIdentityAndRestoreShortViewport() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        let items = (0..<50).map { (i: Int) in FluentMenuItem(id: i, "Option \(i)") {} }
        let menu = FluentMenuFlyout(items: items, reduceMotion: true)
        defer { menu.dismiss(animated: false) }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first), content = panel.contentView, responder = panel.firstResponder
        let rows = all(content!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
        let selected = try XCTUnwrap(rows.last)
        try key(119, in: panel)
        menu.update(items: [FluentMenuItem(id: "prefix", "Inserted") {}] + items)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertTrue(panel.contentView === content)
        XCTAssertTrue(panel.firstResponder === responder)
        XCTAssertTrue(selected.isAccessibilitySelected())
        XCTAssertTrue(selected.visibleRect.contains(selected.bounds))
        menu.update(items: [items.last!])
        waitForUI(panel.frame.height == 40)
        XCTAssertTrue(all(content!).contains { $0 === selected })
        XCTAssertTrue(selected.isAccessibilitySelected())
        XCTAssertTrue(selected.visibleRect.contains(selected.bounds))
        let scroll = try XCTUnwrap(all(content!).compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.01)
        XCTAssertFalse(scroll.hasVerticalScroller)
    }

    @MainActor func testTypeaheadAndWrappingRevealRowsInTouchAndDesktopLayouts() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        for device in [FluentInputDeviceType.mouse, .touch] {
            FluentInputDeviceTracker.shared.record(device, in: window)
            let items = (0..<49).map { (i: Int) in FluentMenuItem("Option \(i)") {} } + [FluentMenuItem("Zebra") {}]
            let menu = FluentMenuFlyout(items: items, reduceMotion: true)
            menu.present(relativeTo: anchor)
            let panel = try XCTUnwrap(window.childWindows?.first)
            let rows = all(panel.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
            XCTAssertEqual(rows[0].frame.height, device == .touch ? 40 : 32)
            try key(6, in: panel, characters: "z")
            XCTAssertTrue(rows[49].isAccessibilitySelected())
            XCTAssertTrue(rows[49].visibleRect.contains(rows[49].bounds))
            try key(125, in: panel)
            XCTAssertTrue(rows[0].isAccessibilitySelected())
            XCTAssertTrue(rows[0].visibleRect.contains(rows[0].bounds))
            try key(126, in: panel)
            XCTAssertTrue(rows[49].isAccessibilitySelected())
            XCTAssertTrue(rows[49].visibleRect.contains(rows[49].bounds))
            menu.dismiss(animated: false)
        }
    }

    @MainActor func testLegacyScrollerRetilingAndAnchorResizePreserveContent() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        let items = (0..<50).map { (i: Int) in FluentMenuItem("Option \(i)") {} }
        let menu = FluentMenuFlyout(items: items, reduceMotion: true)
        defer { menu.dismiss(animated: false) }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let scroll = try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        for style in [NSScroller.Style.legacy, .overlay] {
            scroll.scrollerStyle = style
            scroll.tile()
            waitForUI(abs(document.frame.width - scroll.contentSize.width) < 0.01)
            anchor.setFrameSize(NSSize(width: 600, height: 32))
            menu.reposition()
            waitForUI(abs(document.frame.width - scroll.contentSize.width) < 0.01)
            XCTAssertEqual(panel.frame.width, 600)
            XCTAssertTrue(scroll.documentView === document)
            try key(119, in: panel)
            let last = try XCTUnwrap(all(document).last { $0.identifier?.rawValue == "FluentKit.Menu.Item" })
            XCTAssertTrue(last.visibleRect.contains(last.bounds))
            anchor.setFrameSize(NSSize(width: 160, height: 32))
            menu.reposition()
        }
    }

    @MainActor func testSelectionCenteredPlacementShowsCheckedRowInLongMenu() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        let items = (0..<50).map { (i: Int) in FluentMenuItem("Option \(i)", state: i == 45 ? .on : .off) {} }
        let menu = FluentMenuFlyout(items: items, reduceMotion: true)
        defer { menu.dismiss(animated: false) }
        menu.present(relativeTo: anchor, placement: .comboBoxSelection)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let rows = all(panel.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
        XCTAssertTrue(NSScreen.main!.visibleFrame.contains(panel.frame))
        XCTAssertTrue(rows[45].visibleRect.contains(rows[45].bounds))
    }

    @MainActor func testExplicitMinimumWidthWinsOverWorkAreaMaximum() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        let minimum = NSScreen.main!.visibleFrame.width + 100
        let menu = FluentMenuFlyout(items: [FluentMenuItem("One") {}], minimumWidth: minimum,
                                    matchesAnchorWidth: false, reduceMotion: true)
        defer { menu.dismiss(animated: false) }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.frame.width, minimum)
    }
}
