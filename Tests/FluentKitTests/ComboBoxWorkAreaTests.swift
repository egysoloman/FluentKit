import XCTest
@testable import FluentKit

final class ComboBoxWorkAreaTests: XCTestCase {
    @MainActor private func mount() -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let work = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: work.minX + 100, y: work.minY + 100, width: 800, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 20, y: 200, width: 220, height: 32))
        window.contentView!.addSubview(anchor)
        window.orderFront(nil)
        return (window, anchor)
    }

    @MainActor func testLongTitlesFitTheTargetWorkAreaInBothDirections() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        for direction in [NSUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            let popup = FluentComboBoxPopup(titles: [String(repeating: "Long option 很长的选项 ", count: 40), "Second"],
                selectedIndex: 0, theme: .current, layoutDirection: direction, reduceMotion: true,
                onMove: { _ in }, onCommit: { _ in }, onDismiss: {})
            popup.present(relativeTo: anchor)
            let panel = try XCTUnwrap(window.childWindows?.first)
            let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let work = FluentScreenPlacement.visibleFrame(at: FluentScreenPlacement.topLeading(of: anchorRect,
                rightToLeft: direction == .rightToLeft), fallback: window)
            XCTAssertGreaterThanOrEqual(panel.frame.minX, work.minX)
            XCTAssertLessThanOrEqual(panel.frame.maxX, work.maxX)
            XCTAssertLessThanOrEqual(panel.frame.width, work.width)
            popup.dismiss(animated: false)
        }
    }

    @MainActor func testOpenPopupRemeasuresTheFaceplateMinimumWidth() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        let popup = FluentComboBoxPopup(titles: ["First", "Second"], selectedIndex: 0, theme: .current,
            layoutDirection: .leftToRight, reduceMotion: true, onMove: { _ in }, onCommit: { _ in }, onDismiss: {})
        defer { popup.dismiss(animated: false) }
        popup.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let content = panel.contentView, responder = panel.firstResponder
        anchor.setFrameSize(NSSize(width: 600, height: 32))
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        XCTAssertEqual(panel.frame.width, 600, accuracy: 0.5)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertTrue(panel.contentView === content)
        XCTAssertTrue(panel.firstResponder === responder)
    }
    func testConstrainedSizesHonorWorkAreaRowsAndFaceplateMinimum() {
        for rowHeight: CGFloat in [36, 48] {
            let work = NSRect(x: -500, y: 100, width: 360, height: 220)
            let size = FluentComboBoxPopupSizing.constrained(NSSize(width: 2000, height: 15 * rowHeight + 8),
                faceplateWidth: 220, rowHeight: rowHeight, workArea: work)
            XCTAssertEqual(size.width, 352)
            XCTAssertLessThanOrEqual(size.height, 212)
            XCTAssertEqual((size.height - 8).truncatingRemainder(dividingBy: rowHeight), 0)
            let range = FluentComboBoxPopupSizing.visibleRange(13..<28, centeredOn: 20, height: size.height, rowHeight: rowHeight)
            XCTAssertTrue(range.contains(20))
            XCTAssertEqual(CGFloat(range.count) * rowHeight + 8, size.height)
        }
        // WinUI's explicit faceplate MinWidth wins even if the control itself spans monitors.
        let size = FluentComboBoxPopupSizing.constrained(NSSize(width: 2000, height: 80),
            faceplateWidth: 600, rowHeight: 36, workArea: NSRect(x: 0, y: 0, width: 360, height: 220))
        XCTAssertEqual(size.width, 600)
    }

    @MainActor func testSmallerWorkAreaKeepsSelectionAndKeyboardReachability() throws {
        let (window, anchor) = mount()
        defer { window.close() }
        var moved: Int?, committed: Int?
        let popup = FluentComboBoxPopup(titles: (0..<40).map { "Option \($0)" }, selectedIndex: 20, theme: .current,
            layoutDirection: .leftToRight, reduceMotion: true, onMove: { moved = $0 },
            onCommit: { committed = $0 }, onDismiss: {})
        defer { popup.dismiss(animated: false) }
        popup.present(relativeTo: anchor)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let originalSize = panel.frame.size
        let content = panel.contentView, responder = panel.firstResponder
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let scroll = try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSScrollView }.first)
        let rows = try XCTUnwrap(scroll.documentView).subviews
        let point = window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).origin
        let smallWork = NSRect(x: point.x - 30, y: point.y - 100, width: 380, height: 220)
        popup.updateLayout(in: smallWork)
        XCTAssertTrue(smallWork.contains(panel.frame))
        XCTAssertLessThan(panel.frame.height, originalSize.height)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertTrue(scroll.documentVisibleRect.contains(rows[20].frame), "Selected row must remain reachable and fully visible")
        func key(_ code: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
            panel.firstResponder?.keyDown(with: event)
        }
        key(119) // End: the last option is reachable in the constrained viewport.
        XCTAssertEqual(moved, 39)
        XCTAssertTrue(scroll.documentVisibleRect.contains(rows[39].frame))
        popup.updateLayout(in: smallWork.insetBy(dx: 0, dy: 20))
        XCTAssertTrue(scroll.documentVisibleRect.contains(rows[39].frame), "Resize preserves keyboard focus visibility")
        XCTAssertNil(committed)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertTrue(content === panel.contentView)
        XCTAssertTrue(responder === panel.firstResponder)
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        XCTAssertEqual(host.revealMaskLayer.frame, host.bounds, "Resize must update the reveal clip too")
        popup.updateLayout(in: NSScreen.main!.visibleFrame)
        XCTAssertEqual(panel.frame.size, originalSize)
        XCTAssertTrue(scroll.documentVisibleRect.contains(rows[39].frame))
        key(115) // Home, then Enter commits normally.
        XCTAssertEqual(moved, 0)
        XCTAssertTrue(scroll.documentVisibleRect.contains(rows[0].frame))
        key(36)
        XCTAssertEqual(committed, 0)
    }

}
