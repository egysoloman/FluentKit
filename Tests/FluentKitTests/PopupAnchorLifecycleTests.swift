import XCTest
@testable import FluentKit

final class PopupAnchorLifecycleTests: XCTestCase {
    @MainActor private func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }

    @MainActor private func mount(_ anchor: NSView) -> (NSWindow, NSLayoutConstraint) {
        _ = NSApplication.shared
        let frame = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: frame.minX + 100, y: frame.minY + 100, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = window.contentView!
        anchor.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(anchor)
        let width = anchor.widthAnchor.constraint(equalToConstant: 220)
        NSLayoutConstraint.activate([width, anchor.heightAnchor.constraint(equalToConstant: 32),
            anchor.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            anchor.topAnchor.constraint(equalTo: root.topAnchor, constant: 120)])
        window.makeKeyAndOrderFront(nil)
        root.layoutSubtreeIfNeeded()
        return (window, width)
    }

    @MainActor func testComboBoxFollowsItsActualAutoLayoutSizeChange() throws {
        let state = FluentState<String?>(wrappedValue: "First")
        let anchor = FluentComboBox(options: ["First", "Second"], selection: state.projectedValue)._makeView(in: .init(reduceMotion: true))
        let (window, width) = mount(anchor)
        defer { window.close() }
        let native = try XCTUnwrap(all(anchor).compactMap { $0 as? NSComboBox }.first)
        native.performClick(nil)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let content = panel.contentView, responder = panel.firstResponder
        width.constant = 400
        window.contentView!.layoutSubtreeIfNeeded()
        XCTAssertEqual(anchor.frame.width, 400, accuracy: 0.01)
        waitForUI(abs(panel.frame.width - anchor.frame.width) < 0.5)
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        XCTAssertEqual(panel.frame.minX, rect.minX, accuracy: 0.5)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertTrue(panel.contentView === content)
        XCTAssertTrue(panel.firstResponder === responder)
        XCTAssertEqual(state.wrappedValue, "First")
        native.performClick(nil)
    }

    @MainActor func testMenuTracksAutoLayoutAnchorAfterRootWindowResize() throws {
        let anchor = NSView()
        let (window, _) = mount(anchor)
        let menu = FluentMenuFlyout(items: [FluentMenuItem("One") {}], reduceMotion: true)
        defer { menu.dismiss(animated: false); window.close() }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let original = panel.frame, initial = anchor.frame
        window.setContentSize(NSSize(width: 760, height: 400))
        window.contentView!.layoutSubtreeIfNeeded()
        XCTAssertEqual(anchor.frame.minX - initial.minX, 160, accuracy: 0.5)
        waitForUI(abs(panel.frame.minX - original.minX - 160) < 0.5)
        XCTAssertTrue(panel === window.childWindows?.first)
    }

    @MainActor func testRetainedMenuTargetUnloadClosesPanel() throws {
        let anchor = NSView()
        let (window, _) = mount(anchor)
        let menu = FluentMenuFlyout(items: [FluentMenuItem("One") {}], reduceMotion: true)
        var dismissals = 0
        menu.onDismiss = { dismissals += 1 }
        defer { menu.dismiss(animated: false); window.close() }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        anchor.removeFromSuperview()
        waitForUI(!menu.isPresented)
        XCTAssertNil(panel.parent)
        XCTAssertEqual(dismissals, 1)
        withExtendedLifetime(anchor) {}
    }

    @MainActor func testRetainedComboBoxTargetUnloadClosesPanelWithoutChangingSelection() throws {
        let state = FluentState<String?>(wrappedValue: "First")
        let anchor = FluentComboBox(options: ["First", "Second"], selection: state.projectedValue)._makeView(in: .init(reduceMotion: true))
        let (window, _) = mount(anchor)
        defer { window.close() }
        let native = try XCTUnwrap(all(anchor).compactMap { $0 as? NSComboBox }.first)
        native.performClick(nil)
        let panel = try XCTUnwrap(window.childWindows?.first)
        anchor.removeFromSuperview()
        waitForUI(!panel.isVisible)
        XCTAssertNil(panel.parent)
        XCTAssertEqual(state.wrappedValue, "First")
        withExtendedLifetime(anchor) {}
    }
    @MainActor private func fixture(combo: Bool) -> (NSView, () -> Void, () -> Void, FluentState<String?>) {
        let state = FluentState<String?>(wrappedValue: "First")
        if combo {
            let anchor = FluentComboBox(options: ["First", "Second"], selection: state.projectedValue)._makeView(in: .init(reduceMotion: true))
            let native = all(anchor).compactMap { $0 as? NSComboBox }.first!
            return (anchor, { native.performClick(nil) }, {
                if anchor.window?.childWindows?.isEmpty == false { native.performClick(nil) }
            }, state)
        }
        let anchor = NSView()
        let menu = FluentMenuFlyout(items: [FluentMenuItem("One") {}], reduceMotion: true)
        return (anchor, { menu.present(relativeTo: anchor) }, { menu.dismiss(animated: false) }, state)
    }

    @MainActor func testMenuMatchesAnAnchorConstraintChangeWithoutSyntheticScreenEvents() throws {
        let (anchor, open, close, _) = fixture(combo: false)
        let (window, width) = mount(anchor)
        defer { close(); window.close() }
        open()
        let panel = try XCTUnwrap(window.childWindows?.first)
        width.constant = 400
        window.contentView!.layoutSubtreeIfNeeded()
        waitForUI(panel.frame.width == 400)
        XCTAssertEqual(panel.frame.minX, window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).minX, accuracy: 0.5)
    }

    @MainActor func testMovingTargetsToAnotherWindowClosesOldPanelsAndAllowsReopening() throws {
        for combo in [false, true] {
            let (anchor, open, close, state) = fixture(combo: combo)
            let (first, _) = mount(anchor)
            let (second, _) = mount(NSView())
            defer { close(); first.close(); second.close() }
            open()
            let old = try XCTUnwrap(first.childWindows?.first)
            let root = second.contentView!
            anchor.removeFromSuperview()
            root.addSubview(anchor)
            NSLayoutConstraint.activate([anchor.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                anchor.topAnchor.constraint(equalTo: root.topAnchor, constant: 120)])
            root.layoutSubtreeIfNeeded()
            waitForUI(old.parent == nil)
            XCTAssertFalse(old.isVisible)
            open()
            let reopened = try XCTUnwrap(second.childWindows?.first)
            XCTAssertTrue(reopened !== old)
            XCTAssertTrue(reopened.isVisible)
            XCTAssertEqual(state.wrappedValue, "First")
        }
    }

    @MainActor func testSameWindowReattachmentKeepsPanelAndObservesNewAncestors() throws {
        for combo in [false, true] {
            let (anchor, open, close, _) = fixture(combo: combo)
            let (window, _) = mount(anchor)
            defer { close(); window.close() }
            open()
            let panel = try XCTUnwrap(window.childWindows?.first), content = panel.contentView
            let group = NSView(frame: NSRect(x: 60, y: 30, width: 500, height: 350))
            window.contentView!.addSubview(group)
            anchor.removeFromSuperview()
            group.addSubview(anchor)
            NSLayoutConstraint.activate([anchor.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 24),
                anchor.topAnchor.constraint(equalTo: group.topAnchor, constant: 100)])
            window.contentView!.layoutSubtreeIfNeeded()
            waitForUI(abs(panel.frame.minX - window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).minX) < 0.5)
            XCTAssertTrue(panel === window.childWindows?.first)
            XCTAssertTrue(panel.contentView === content)
            let old = panel.frame
            group.setFrameOrigin(NSPoint(x: 90, y: 60))
            waitForUI(abs(panel.frame.minX - old.minX - 30) < 0.5)
            XCTAssertEqual(panel.frame.minY - old.minY, 30, accuracy: 0.5)
        }
    }

    @MainActor func testHiddenAncestorsAndOwnerCloseRemovePanels() throws {
        for combo in [false, true] {
            let (anchor, open, close, state) = fixture(combo: combo)
            let (window, _) = mount(anchor)
            defer { close(); window.close() }
            open()
            let first = try XCTUnwrap(window.childWindows?.first)
            window.contentView!.isHidden = true
            waitForUI(first.parent == nil)
            XCTAssertFalse(first.isVisible)
            window.contentView!.isHidden = false
            open()
            let second = try XCTUnwrap(window.childWindows?.first)
            window.close()
            XCTAssertNil(second.parent)
            XCTAssertFalse(second.isVisible)
            XCTAssertEqual(state.wrappedValue, "First")
        }
    }

    @MainActor func testAncestorScrollingRepositionsThenClosesFullyClippedTargets() throws {
        for combo in [false, true] {
            let (anchor, open, close, _) = fixture(combo: combo)
            let (window, _) = mount(anchor)
            defer { close(); window.close() }
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.hasVerticalScroller = true
            let document = PopupAnchorFlippedDocument(frame: NSRect(x: 0, y: 0, width: 600, height: 1000))
            scroll.documentView = document
            window.contentView!.addSubview(scroll)
            anchor.removeFromSuperview()
            document.addSubview(anchor)
            NSLayoutConstraint.activate([anchor.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
                anchor.topAnchor.constraint(equalTo: document.topAnchor, constant: 100)])
            window.contentView!.layoutSubtreeIfNeeded()
            open()
            let panel = try XCTUnwrap(window.childWindows?.first)
            let old = panel.frame
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 50))
            scroll.reflectScrolledClipView(scroll.contentView)
            waitForUI(abs(panel.frame.minY - old.minY - 50) < 0.5)
            XCTAssertTrue(panel === window.childWindows?.first)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertFalse(anchor.convert(anchor.bounds, to: scroll.contentView).intersects(scroll.contentView.bounds))
            waitForUI(panel.parent == nil)
            XCTAssertFalse(panel.isVisible)
        }
    }

    @MainActor func testObserverInvalidationPreservesNotificationFlagsAndRemovesAttachment() throws {
        let anchor = NSView()
        let (window, _) = mount(anchor)
        defer { window.close() }
        anchor.postsFrameChangedNotifications = false
        anchor.postsBoundsChangedNotifications = false
        var changes = 0, unavailable = 0
        var observer: FluentPopupAnchorObserver? = FluentPopupAnchorObserver(anchor: anchor,
            onChange: { changes += 1 }, onUnavailable: { unavailable += 1 })
        weak var weakObserver = observer
        let attachment = try XCTUnwrap(anchor.subviews.first { $0.identifier?.rawValue == "FluentKit.Popup.AnchorObserver" })
        XCTAssertNil(attachment.hitTest(.zero))
        XCTAssertFalse(attachment.isAccessibilityElement())
        XCTAssertFalse(anchor.postsFrameChangedNotifications)
        XCTAssertFalse(anchor.postsBoundsChangedNotifications)
        observer?.invalidate()
        observer = nil
        XCTAssertNil(weakObserver)
        weakObserver = nil
        XCTAssertNil(attachment.superview)
        NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: anchor)
        window.close()
        let drained = expectation(description: "Observer queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(unavailable, 0)
    }

    @MainActor func testReleasingAnOpenComboPopupRemovesItsChildWindowAndAttachment() throws {
        let anchor = NSView()
        let (window, _) = mount(anchor)
        defer { window.close() }
        var popup: FluentComboBoxPopup? = FluentComboBoxPopup(titles: ["First"], selectedIndex: 0,
            theme: .current, layoutDirection: .leftToRight, reduceMotion: true,
            onMove: { _ in }, onCommit: { _ in }, onDismiss: {})
        popup?.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        popup = nil
        XCTAssertNil(panel.parent)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(anchor.subviews.contains { $0.identifier?.rawValue == "FluentKit.Popup.AnchorObserver" })
    }
}

private final class PopupAnchorFlippedDocument: NSView {
    override var isFlipped: Bool { true }
}
