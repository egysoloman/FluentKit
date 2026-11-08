import XCTest
@testable import FluentKit

@MainActor
final class HoverLifecycleTests: XCTestCase {
    private struct HoverStyle: FluentCollectionItemStyle {
        func appearance(for configuration: FluentCollectionItemStyleConfiguration) -> FluentCollectionItemAppearance {
            FluentCollectionItemAppearance(
                backgroundColor: configuration.controlState == .pointerOver ? .red : .clear,
                contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            )
        }
    }

    private func collection(_ layout: FluentCollectionLayout, disabled: Int? = nil) throws -> (NSWindow, FluentSectionedCollectionView<String, Int>) {
        _ = NSApplication.shared
        var snapshot = FluentCollectionSnapshot<String, Int>()
        snapshot.appendSections(["items"])
        snapshot.appendItems(Array(0..<100), toSection: "items")
        let collection = FluentCollection(snapshot: snapshot, layout: layout,
            isEnabled: { $0 != disabled }, itemStyle: HoverStyle()) {
            FluentText("Item \($0)")
        }
        let view = try XCTUnwrap(collection._makeView(in: FluentRenderContext(reduceMotion: true))
            as? FluentSectionedCollectionView<String, Int>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        return (window, view)
    }

    private func isHovered(_ view: NSView) throws -> Bool {
        let color = try XCTUnwrap(view.layer?.sublayers?.first {
            $0.name == "FluentKit.CollectionItem.Surface"
        }?.backgroundColor)
        return color.alpha > 0.5
    }

    private func event(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
    }

    func testButtonDropsOldHoverWhenRemovedAndReparentedWithoutAnExitEvent() throws {
        _ = NSApplication.shared
        let first = NSView(), second = NSView()
        let button = FluentButton(title: "Move")
        button.reduceMotion = true
        first.addSubview(button)
        button.mouseEntered(with: try event(.mouseEntered))
        XCTAssertEqual(button.controlState, .pointerOver)
        button.removeFromSuperview()
        XCTAssertEqual(button.controlState, .normal)
        first.addSubview(button)
        button.mouseEntered(with: try event(.mouseEntered))
        second.addSubview(button)
        XCTAssertEqual(button.controlState, .normal)
    }

    func testExitWhileDisabledDoesNotRestoreStaleHoverWhenEnabled() throws {
        _ = NSApplication.shared
        let button = FluentButton(title: "Enable")
        button.reduceMotion = true
        button.mouseEntered(with: try event(.mouseEntered))
        button.isEnabled = false
        XCTAssertEqual(button.controlState, .disabled)
        button.mouseExited(with: try event(.mouseExited))
        XCTAssertEqual(button.controlState, .disabled)
        button.isEnabled = true
        XCTAssertEqual(button.controlState, .normal)
        // Remaining over the button while disabling/re-enabling should still show hover.
        button.mouseEntered(with: try event(.mouseEntered))
        button.isEnabled = false
        button.isEnabled = true
        XCTAssertEqual(button.controlState, .pointerOver)
    }

    func testCollectionMissingExitAndLateExitKeepOnlyTheCurrentItemHovered() throws {
        for layout in [FluentCollectionLayout.list(), .adaptiveGrid(minimumItemWidth: 80)] {
            let (window, view) = try collection(layout)
            defer { window.close() }
            let first = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 0, section: 0)))
            let second = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 1, section: 0)))
            first.view.mouseEntered(with: try event(.mouseEntered))
            XCTAssertTrue(try isHovered(first.view))
            second.view.mouseEntered(with: try event(.mouseEntered))
            XCTAssertFalse(try isHovered(first.view), "Entering the next item must clear a missed exit")
            XCTAssertTrue(try isHovered(second.view))
            first.view.mouseExited(with: try event(.mouseExited))
            XCTAssertTrue(try isHovered(second.view), "A late exit belongs to the old item")
            first.prepareForReuse()
            XCTAssertTrue(try isHovered(second.view), "Reusing an old item must not clear the new owner")
            second.prepareForReuse()
            XCTAssertFalse(try isHovered(second.view))
        }
    }

    func testCollectionDetachClearsHoverWithoutChangingSelectionOrOtherCollections() throws {
        let (firstWindow, first) = try collection(.list())
        let (secondWindow, second) = try collection(.adaptiveGrid(minimumItemWidth: 80))
        defer { firstWindow.close(); secondWindow.close() }
        let path = IndexPath(item: 0, section: 0)
        let firstCell = try XCTUnwrap(first.nativeCollectionView.item(at: path)?.view)
        let secondCell = try XCTUnwrap(second.nativeCollectionView.item(at: path)?.view)
        first.nativeCollectionView.selectionIndexPaths = [path]
        firstCell.mouseEntered(with: try event(.mouseEntered))
        secondCell.mouseEntered(with: try event(.mouseEntered))
        XCTAssertTrue(try isHovered(firstCell))
        XCTAssertTrue(try isHovered(secondCell))
        first.removeFromSuperview()
        XCTAssertFalse(try isHovered(firstCell))
        XCTAssertTrue(try isHovered(secondCell))
        XCTAssertEqual(first.nativeCollectionView.selectionIndexPaths, [path])
    }

    func testCollectionViewportMovementClearsHoverWithoutMouseMotion() throws {
        let (window, view) = try collection(.list())
        defer { window.close() }
        let cell = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 0, section: 0))?.view)
        cell.mouseEntered(with: try event(.mouseEntered))
        XCTAssertTrue(try isHovered(cell))
        view.contentView.scroll(to: NSPoint(x: 0, y: 600))
        view.reflectScrolledClipView(view.contentView)
        XCTAssertFalse(try isHovered(cell), "A scrolled-away cell must not retain pointer paint")
    }

    func testHiddenAncestorClearsButtonAndCollectionHoverWithoutAnExit() throws {
        let (window, view) = try collection(.list())
        defer { window.close() }
        let cell = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 0, section: 0))?.view)
        let button = FluentButton(title: "Hover")
        button.reduceMotion = true
        view.addSubview(button)
        button.mouseEntered(with: try event(.mouseEntered))
        cell.mouseEntered(with: try event(.mouseEntered))
        view.isHidden = true
        view.isHidden = false
        XCTAssertEqual(button.controlState, .normal)
        XCTAssertFalse(try isHovered(cell), "Showing an unchanged hierarchy must not restore stale hover")
    }

    func testWindowResigningKeyClearsOnlyItsOwnCollectionHover() throws {
        let (window, view) = try collection(.adaptiveGrid(minimumItemWidth: 80))
        let (otherWindow, other) = try collection(.list())
        defer { window.close(); otherWindow.close() }
        let path = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(view.nativeCollectionView.item(at: path)?.view)
        let otherCell = try XCTUnwrap(other.nativeCollectionView.item(at: path)?.view)
        view.nativeCollectionView.selectionIndexPaths = [path]
        cell.mouseEntered(with: try event(.mouseEntered))
        otherCell.mouseEntered(with: try event(.mouseEntered))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(try isHovered(cell))
        XCTAssertTrue(try isHovered(otherCell))
        XCTAssertEqual(view.nativeCollectionView.selectionIndexPaths, [path])
    }

    func testButtonTrackingRefreshReconcilesAStationaryPointerAfterScrolling() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let button = FluentButton(title: "Scrolled away")
        window.contentView?.addSubview(button)
        button.frame = NSRect(x: 0, y: 600, width: 100, height: 32)
        button.mouseEntered(with: try event(.mouseEntered))
        button.updateTrackingAreas()
        XCTAssertEqual(button.controlState, .normal)
    }

    func testEnteringDisabledCollectionItemReleasesPreviousHoverWithoutAnExit() throws {
        let (window, view) = try collection(.list(), disabled: 1)
        defer { window.close() }
        let first = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 0, section: 0))?.view)
        let disabled = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 1, section: 0))?.view)
        first.mouseEntered(with: try event(.mouseEntered))
        disabled.mouseEntered(with: try event(.mouseEntered))
        XCTAssertFalse(try isHovered(first))
        XCTAssertFalse(try isHovered(disabled))
    }

    func testButtonWindowLifecycleClearsHoverButRetainsKeyboardFocusState() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let button = FluentButton(title: "Hover")
        window.contentView?.addSubview(button)
        for notification in [NSWindow.didResignKeyNotification, NSWindow.willMiniaturizeNotification,
                             NSWindow.didChangeOcclusionStateNotification] {
            button.mouseEntered(with: try event(.mouseEntered))
            NotificationCenter.default.post(name: notification, object: window)
            XCTAssertEqual(button.controlState, .normal)
        }
        button.controlState = .focused
        button.isHidden = true
        button.isHidden = false
        XCTAssertEqual(button.controlState, .focused)
    }

    func testNativeOrderOutClearsHoverWithoutKeyOrOcclusionNotifications() throws {
        let (window, view) = try collection(.list())
        defer { window.close() }
        let button = FluentButton(title: "Persistent panel")
        button.reduceMotion = true
        view.addSubview(button)
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(view.nativeCollectionView.item(at: IndexPath(item: 0, section: 0))?.view)
        button.mouseEntered(with: try event(.mouseEntered))
        cell.mouseEntered(with: try event(.mouseEntered))
        window.orderOut(nil)
        XCTAssertEqual(button.controlState, .normal)
        XCTAssertFalse(try isHovered(cell))
    }
}
