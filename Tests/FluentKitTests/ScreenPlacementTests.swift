import XCTest
@testable import FluentKit

final class ScreenPlacementTests: XCTestCase {
    func testTargetScreenCanDifferFromTheParentWindowsScreen() {
        let screens = [NSRect(x: 0, y: 0, width: 1000, height: 800), NSRect(x: 1000, y: 0, width: 1200, height: 900)]
        // A 900pt-wide window at x=400 mostly occupies screen 0; its right-side
        // ComboBox/menu target is on screen 1 and must use that screen's work area.
        XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: NSPoint(x: 1150, y: 400), frames: screens), 1)
        XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: NSPoint(x: 600, y: 400), frames: screens), 0)
    }

    func testAllMonitorArrangementsUseScreenCoordinates() {
        let screens = [NSRect(x: 0, y: 0, width: 1000, height: 800),
                       NSRect(x: -1200, y: -200, width: 1200, height: 900),
                       NSRect(x: 0, y: 800, width: 1200, height: 900),
                       NSRect(x: 0, y: -900, width: 1200, height: 900)]
        for (point, index) in [(NSPoint(x: 100, y: 100), 0), (NSPoint(x: -500, y: 0), 1),
                               (NSPoint(x: 400, y: 1000), 2), (NSPoint(x: 400, y: -400), 3)] {
            XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: point, frames: screens), index)
        }
    }

    func testOffscreenTargetUsesNearestEdgeRatherThanMonitorCenter() {
        let screens = [NSRect(x: -400, y: -100, width: 100, height: 200),
                       NSRect(x: 10, y: -1200, width: 3000, height: 2400)]
        XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: .zero, frames: screens), 1)
        XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: NSPoint(x: -500, y: 200), frames: screens), 0)
    }

    func testSeamsAndRTLUseTheActualTargetPoint() {
        let screens = [NSRect(x: 0, y: 0, width: 1000, height: 800), NSRect(x: 1000, y: 0, width: 1000, height: 800)]
        let anchor = NSRect(x: 950, y: 300, width: 100, height: 32)
        XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: NSPoint(x: 1000, y: 332), frames: screens), 1)
        for rtl in [false, true] {
            let target = FluentScreenPlacement.topLeading(of: anchor, rightToLeft: rtl)
            XCTAssertEqual(target, NSPoint(x: rtl ? 1050 : 950, y: 332))
            XCTAssertEqual(FluentScreenPlacement.nearestScreenIndex(to: target, frames: screens), rtl ? 1 : 0)
        }
    }

    func testMissingScreensAndInvalidPointsHaveNoSelection() {
        XCTAssertNil(FluentScreenPlacement.nearestScreenIndex(to: .zero, frames: []))
        XCTAssertNil(FluentScreenPlacement.nearestScreenIndex(to: NSPoint(x: CGFloat.nan, y: 0), frames: [.zero]))
        XCTAssertNil(FluentScreenPlacement.nearestScreenIndex(to: .zero, frames: [.zero]))
    }

    @MainActor private func mount(_ anchor: NSView) -> NSWindow {
        _ = NSApplication.shared
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView!.addSubview(anchor)
        anchor.frame = NSRect(x: 50, y: 220, width: 220, height: 48)
        window.orderFront(nil)
        window.contentView!.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor func testOpenComboRepositionsOnScreenChangeWithoutReopeningOrCommitting() throws {
        let anchor = NSView()
        let window = mount(anchor)
        var commits = 0
        var dismissals = 0
        let popup = FluentComboBoxPopup(titles: ["First", "Second", "Third"], selectedIndex: 1,
            theme: .current, layoutDirection: .leftToRight, reduceMotion: true,
            onMove: { _ in }, onCommit: { _ in commits += 1 }, onDismiss: { dismissals += 1 })
        defer { popup.dismiss(animated: false); window.close() }
        popup.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let original = panel.frame
        let responder = panel.firstResponder
        anchor.setFrameOrigin(NSPoint(x: 130, y: 220))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertEqual(panel.frame.minX - original.minX, 80, accuracy: 0.5)
        XCTAssertTrue(panel.firstResponder === responder)
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(dismissals, 0)
        popup.dismiss(animated: false)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testOpenMenuRepositionsOnScreenChangeWithoutRebuildingRows() throws {
        let anchor = NSView()
        let window = mount(anchor)
        let menu = FluentMenuFlyout(items: [FluentMenuItem("First") {}, FluentMenuItem("Second") {}], reduceMotion: true)
        defer { menu.dismiss(animated: false); window.close() }
        menu.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let original = panel.frame
        let content = panel.contentView
        anchor.setFrameOrigin(NSPoint(x: 130, y: 220))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertTrue(content === panel.contentView)
        XCTAssertEqual(panel.frame.minX - original.minX, 80, accuracy: 0.5)
    }

    @MainActor func testOpenCommandBarRepositionsOnScreenChangeAndReleasesObserver() throws {
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [FluentCommandBarItem("Action") {}])
        let window = mount(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        bar.reduceMotion = true
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let original = panel.frame
        // A frame-origin change does not invoke the bar's layout; the screen event
        // must refresh the already open panel against the current anchor.
        bar.setFrameOrigin(NSPoint(x: 130, y: 220))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertEqual(panel.frame.minX - original.minX, 80, accuracy: 0.5)
        bar.setOpen(false, animated: false)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertFalse(bar.isOpen)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testScreenObserverIsScopedToItsWindowAndLifetime() {
        _ = NSApplication.shared
        let first = NSWindow(), second = NSWindow()
        var callbacks = 0
        var observer: FluentPopupScreenObserver? = FluentPopupScreenObserver(window: first) { callbacks += 1 }
        XCTAssertNotNil(observer)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: second)
        XCTAssertEqual(callbacks, 0)
        NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: first)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertEqual(callbacks, 2)
        observer = nil
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: first)
        XCTAssertEqual(callbacks, 2)
    }

    @MainActor func testScreenNotificationsPreserveAutoSuggestEditorAndMarkedText() throws {
        let state = FluentState(wrappedValue: "")
        let host = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in
            [FluentAutoSuggestBoxSuggestion(id: 1, title: "Apple"), .init(id: 2, title: "Apricot")]
        })._makeView(in: .init(reduceMotion: true))
        let window = mount(host)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let field = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as? NSTextField)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Ap", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        waitForUI(window.childWindows?.first?.isVisible == true)
        let panel = try XCTUnwrap(window.childWindows?.first)
        editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let text = editor.string
        let marked = editor.markedRange()
        let selection = editor.selectedRange()
        XCTAssertTrue(editor.hasMarkedText())
        for name in [NSApplication.didChangeScreenParametersNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            NotificationCenter.default.post(name: name,
                object: name == NSApplication.didChangeScreenParametersNotification ? NSApp : window)
            XCTAssertTrue(panel === window.childWindows?.first)
            XCTAssertTrue(editor === field.currentEditor())
            XCTAssertEqual(editor.string, text)
            XCTAssertEqual(editor.markedRange(), marked)
            XCTAssertEqual(editor.selectedRange(), selection)
            XCTAssertEqual(state.wrappedValue, "Ap", "Screen geometry must not commit composition")
        }
    }
}
