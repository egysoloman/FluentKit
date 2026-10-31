import XCTest
@testable import FluentKit

/// WinUI picks touch or pointer layouts from the device that opened a flyout
/// (`InputDeviceTypeUsedToOpen`); the next open follows the newest device.
final class InputModeLayoutTests: XCTestCase {
    @MainActor
    private func makeWindow() -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 20, y: 200, width: 120, height: 32))
        window.contentView?.addSubview(anchor)
        window.orderFront(nil)
        return (window, anchor)
    }

    @MainActor
    func testMenuFlyoutUsesNarrowRowsForPointersAndDefaultRowsForTouch() {
        let (window, anchor) = makeWindow()
        defer { window.close() }
        let items = [FluentMenuItem("Cut") {}, FluentMenuItem("Copy") {}, FluentMenuItem("Paste") {}]
        let flyout = FluentMenuFlyout(items: items, reduceMotion: true)

        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        flyout.present(relativeTo: anchor)
        XCTAssertEqual(flyout.inputDeviceTypeUsedToOpen, .mouse)
        XCTAssertEqual(flyout.itemHeight, 36, "NarrowPadding 11,4,11,5")
        flyout.dismiss(animated: false)

        FluentInputDeviceTracker.shared.record(.touch, in: window)
        flyout.present(relativeTo: anchor)
        XCTAssertEqual(flyout.itemHeight, 44, "Default padding 11,8,11,9 for touch")
        flyout.dismiss(animated: false)

        FluentInputDeviceTracker.shared.record(.keyboard, in: window)
        flyout.present(relativeTo: anchor)
        XCTAssertEqual(flyout.itemHeight, 36, "Keyboard opens are narrow too")
        flyout.dismiss(animated: false)

        let touchSize = FluentMenuPresenterViewProbe.size(items: items, itemHeight: 44)
        let narrowSize = FluentMenuPresenterViewProbe.size(items: items, itemHeight: 36)
        XCTAssertEqual(touchSize.height - narrowSize.height, 24, "Three rows, eight points each")
    }

    @MainActor
    func testComboBoxPopupUsesTouchPaddingAndMinimumWidth() {
        let (window, anchor) = makeWindow()
        defer { window.close() }
        let popup = FluentComboBoxPopup(titles: ["One", "Two"], selectedIndex: 0, theme: .current,
                                        layoutDirection: .leftToRight, reduceMotion: true,
                                        onMove: { _ in }, onCommit: { _ in }, onDismiss: {})
        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        popup.present(relativeTo: anchor)
        XCTAssertEqual(popup.rowHeight, 36)
        let mouseWidth = popup.presentedPanelSize?.width ?? 0
        popup.dismiss(animated: false)

        FluentInputDeviceTracker.shared.record(.touch, in: window)
        popup.present(relativeTo: anchor)
        XCTAssertEqual(popup.inputDeviceTypeUsedToOpen, .touch)
        XCTAssertEqual(popup.rowHeight, 48, "ComboBoxItemThemeTouchPadding 11,11,11,13")
        XCTAssertGreaterThanOrEqual(popup.presentedPanelSize?.width ?? 0, 240, "ComboBoxPopupThemeTouchMinWidth")
        XCTAssertLessThan(mouseWidth, 240)
        popup.dismiss(animated: false)
    }

    @MainActor
    func testCommandBarOverflowRowsGrowForTouch() {
        let (window, _) = makeWindow()
        defer { window.close() }
        let bar = FluentCommandBar(primaryCommands: [FluentCommandBarItem("Add") {}],
                                   secondaryCommands: [FluentCommandBarItem("Settings") {}, FluentCommandBarItem("Help") {}])
        bar.frame = NSRect(x: 0, y: 0, width: 300, height: 48)
        window.contentView?.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        bar.setOpen(true, animated: false)
        XCTAssertEqual(bar.overflowRowHeight, 40)
        bar.setOpen(false, animated: false)
        FluentInputDeviceTracker.shared.record(.touch, in: window)
        bar.setOpen(true, animated: false)
        XCTAssertEqual(bar.overflowInputDeviceType, .touch)
        XCTAssertEqual(bar.overflowRowHeight, 48, "AppBarButtonOverflowTextTouchMargin 0,9,0,12")
        bar.setOpen(false, animated: false)
    }

    @MainActor
    func testTextCommandsPreferPrimaryForTouchAndPenOnly() {
        let (window, _) = makeWindow()
        defer { window.close() }
        func click(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        XCTAssertFalse(FluentTextEditingSession.prefersPrimaryCommands(for: click(.rightMouseDown), in: window))
        XCTAssertFalse(FluentTextEditingSession.prefersPrimaryCommands(for: click(.leftMouseDown, flags: .control), in: window),
                       "A Ctrl-click is still a mouse")
        XCTAssertEqual(FluentInputDeviceTracker.shared.lastDeviceType(in: window), .mouse)
    }

    @MainActor
    func testFlipViewButtonsIgnoreTouchPointers() throws {
        let (window, _) = makeWindow()
        defer { window.close() }
        let flip = try XCTUnwrap(FluentFlipView(["A", "B"]) { FluentText($0) }._makeView(in: FluentRenderContext(reduceMotion: true)))
        flip.frame = NSRect(x: 0, y: 0, width: 300, height: 180)
        window.contentView?.addSubview(flip)
        flip.layoutSubtreeIfNeeded()
        let move = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 50, y: 50), modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        let next = try XCTUnwrap(flip.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Next" })
        FluentInputDeviceTracker.shared.record(.touch, in: window)
        flip.mouseMoved(with: move)
        XCTAssertTrue(next.isHidden, "Touch does not reveal FlipView buttons")
        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        flip.mouseMoved(with: move)
        XCTAssertFalse(next.isHidden, "A mouse pointer does")
    }
}
