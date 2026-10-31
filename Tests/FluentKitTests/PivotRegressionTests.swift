import XCTest
@testable import FluentKit

final class PivotRegressionTests: XCTestCase {
    private let shortHeaders = ["All", "Unread", "Flagged"]
    private let longHeaders = ["Inbox", "Unread messages", "Flagged items", "Scheduled", "Archive"]

    @MainActor
    private func makePivot(
        _ headers: [String],
        selection: FluentBinding<Int>? = nil,
        width: CGFloat = 600,
        isLocked: Bool = false,
        carousel: Bool = true,
        title: String? = nil,
        context: FluentRenderContext = FluentRenderContext(reduceMotion: true)
    ) throws -> FluentPivotControl {
        _ = NSApplication.shared
        let view = FluentPivot(headers, selection: selection, title: title, isLocked: isLocked,
                               isHeaderItemsCarouselEnabled: carousel, header: { $0 }) { FluentText($0) }
        let pivot = try XCTUnwrap(view._makeView(in: context) as? FluentPivotControl)
        pivot.frame = NSRect(x: 0, y: 0, width: width, height: 240)
        pivot.layoutSubtreeIfNeeded()
        return pivot
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    @MainActor
    func testFittingHeadersAreStaticSourceGeometryAndDoNotWrap() throws {
        let pivot = try makePivot(shortHeaders)
        XCTAssertTrue(pivot.usesStaticHeaders)
        XCTAssertFalse(pivot.shouldWrap)
        let items = pivot.headerItems
        XCTAssertEqual(items.map { $0.frame.height }, [48, 48, 48])
        XCTAssertEqual(items[0].frame.minX, 0)
        XCTAssertEqual(items[1].frame.minX, items[0].frame.maxX, accuracy: 0.01)
        let first = items[0]
        XCTAssertEqual(first.frame.width, first.textWidth(theme: .current) + 24, accuracy: 0.01)
        let pipe = try XCTUnwrap(first.layer?.sublayers?.first { $0.name == "FluentKit.Pivot.SelectedPipe" })
        XCTAssertEqual(pipe.frame.height, 3)
        XCTAssertEqual(pipe.frame.maxY, 46, "Pipe sits 2pt above the 48pt header's bottom edge")
        XCTAssertEqual(pipe.frame.minX, 12)
        XCTAssertEqual(pipe.cornerRadius, 1.5)
        XCTAssertFalse(pipe.isHidden)
        XCTAssertTrue(items[1].layer?.sublayers?.first { $0.name == "FluentKit.Pivot.SelectedPipe" }?.isHidden == true)

        XCTAssertFalse(pivot.move(.previous, wrap: pivot.shouldWrap), "Static headers do not wrap")
        XCTAssertTrue(pivot.move(.next, wrap: pivot.shouldWrap))
        XCTAssertTrue(pivot.move(.next, wrap: pivot.shouldWrap))
        XCTAssertFalse(pivot.move(.next, wrap: pivot.shouldWrap))
        XCTAssertEqual(pivot.selectedIndex, 2)
    }

    @MainActor
    func testClippedHeadersUseCarouselWithSelectedHeaderFirstAndWrap() throws {
        let pivot = try makePivot(longHeaders, width: 320)
        XCTAssertFalse(pivot.usesStaticHeaders)
        XCTAssertTrue(pivot.shouldWrap)
        XCTAssertTrue(pivot.move(.previous, wrap: pivot.shouldWrap))
        XCTAssertEqual(pivot.selectedIndex, 4)
        pivot.layoutSubtreeIfNeeded()
        let items = pivot.headerItems
        XCTAssertEqual(items[4].frame.minX, 0, "The selected header leads the carousel")
        XCTAssertEqual(items[0].frame.minX, items[4].frame.maxX, accuracy: 0.01, "Remaining headers follow cyclically")
        XCTAssertTrue(pivot.move(.next, wrap: pivot.shouldWrap))
        XCTAssertEqual(pivot.selectedIndex, 0)
    }

    @MainActor
    func testDisabledCarouselKeepsStaticOrderAndUsesSourceShiftOffset() throws {
        let pivot = try makePivot(longHeaders, width: 320, carousel: false)
        XCTAssertTrue(pivot.usesStaticHeaders)
        pivot.select(3, animated: false)
        pivot.layoutSubtreeIfNeeded()
        let widths = pivot.headerItems.map { $0.frame.width }
        let before = widths[0..<3].reduce(0, +)
        let after = widths[4]
        let viewport = try XCTUnwrap(pivot.subviews.first { $0.identifier?.rawValue == "FluentKit.Pivot.Headers" }).bounds.width
        let shift = FluentPivotMetrics.headerShiftOffset(before: before, selected: widths[3], after: after, viewport: viewport)
        XCTAssertEqual(pivot.headerItems[3].frame.minX, before - shift, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(pivot.headerItems[3].frame.minX, 0)
        XCTAssertLessThanOrEqual(pivot.headerItems[3].frame.maxX, viewport + 0.01)
        XCTAssertEqual(FluentPivotMetrics.headerShiftOffset(before: 0, selected: 50, after: 0, viewport: 100), 0)
        XCTAssertEqual(FluentPivotMetrics.headerShiftOffset(before: 100, selected: 50, after: 100, viewport: 150), 50)
    }

    @MainActor
    func testLockedPivotHidesUnselectedHeadersAndIgnoresNavigation() throws {
        let pivot = try makePivot(shortHeaders, isLocked: true)
        XCTAssertFalse(pivot.move(.next, wrap: true))
        XCTAssertFalse(pivot.moveToEdge(first: false))
        XCTAssertTrue(pivot.handleSwitchShortcut(key(48, .control)), "The shortcut is consumed even while locked")
        XCTAssertEqual(pivot.selectedIndex, 0)
        let hidden = pivot.headerItems[1]
        XCTAssertEqual(hidden.layer?.opacity, 0)
        XCTAssertEqual(hidden.layer?.transform.m41, 40, "UnselectedLocked translates by PivotHeaderItemLockedTranslation")
        XCTAssertEqual(pivot.headerItems[0].layer?.opacity, 1)
        XCTAssertFalse(hidden.accessibilityPerformPress())
        pivot.setPointerOverHeaders(true)
        XCTAssertTrue(pivot.previousButton.isHidden && pivot.nextButton.isHidden)
    }

    @MainActor
    func testNavigationButtonsFollowSourceVisibilityStates() throws {
        let fitting = try makePivot(shortHeaders)
        fitting.setPointerOverHeaders(true)
        XCTAssertTrue(fitting.previousButton.isHidden && fitting.nextButton.isHidden, "Unclipped static headers hide both")

        let carousel = try makePivot(longHeaders, width: 320)
        XCTAssertTrue(carousel.previousButton.isHidden, "Hidden until the pointer is over the headers")
        carousel.setPointerOverHeaders(true)
        XCTAssertFalse(carousel.previousButton.isHidden || carousel.nextButton.isHidden)
        XCTAssertEqual(carousel.previousButton.frame.size, NSSize(width: 20, height: 36))
        XCTAssertEqual(carousel.previousButton.frame.minY, 6)

        let clippedStatic = try makePivot(longHeaders, width: 320, carousel: false)
        clippedStatic.setPointerOverHeaders(true)
        XCTAssertTrue(clippedStatic.previousButton.isHidden, "No previous button at the first item")
        XCTAssertFalse(clippedStatic.nextButton.isHidden)
        clippedStatic.moveToEdge(first: false)
        XCTAssertFalse(clippedStatic.previousButton.isHidden)
        XCTAssertTrue(clippedStatic.nextButton.isHidden)
        clippedStatic.setPointerOverHeaders(false)
        XCTAssertTrue(clippedStatic.previousButton.isHidden)
    }

    @MainActor
    func testKeyboardShortcutsAndRightToLeftArrows() throws {
        let pivot = try makePivot(shortHeaders)
        pivot.keyDown(with: key(124))
        XCTAssertEqual(pivot.selectedIndex, 1)
        pivot.keyDown(with: key(119))
        XCTAssertEqual(pivot.selectedIndex, 2)
        pivot.keyDown(with: key(115))
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertTrue(pivot.handleSwitchShortcut(key(48, .control)))
        XCTAssertEqual(pivot.selectedIndex, 1)
        XCTAssertTrue(pivot.handleSwitchShortcut(key(48, [.control, .shift])))
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertTrue(pivot.handleSwitchShortcut(key(121, .control)))
        XCTAssertEqual(pivot.selectedIndex, 1)
        XCTAssertTrue(pivot.handleSwitchShortcut(key(116, .control)))
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertFalse(pivot.handleSwitchShortcut(key(48)), "Plain Tab keeps key-view navigation")

        pivot.userInterfaceLayoutDirection = .rightToLeft
        pivot.needsLayout = true
        pivot.layoutSubtreeIfNeeded()
        pivot.keyDown(with: key(123))
        XCTAssertEqual(pivot.selectedIndex, 1, "Left advances in RTL")
        let headers = try XCTUnwrap(pivot.subviews.first { $0.identifier?.rawValue == "FluentKit.Pivot.Headers" })
        XCTAssertEqual(pivot.headerItems[0].frame.maxX, headers.bounds.width, accuracy: 0.01, "The first header is at the trailing physical edge")
    }

    @MainActor
    func testBindingSynchronizationClampingAndRebinding() throws {
        let first = FluentState(wrappedValue: 7)
        let pivot = try makePivot(shortHeaders, selection: first.projectedValue)
        XCTAssertEqual(pivot.selectedIndex, 2)
        XCTAssertEqual(first.wrappedValue, 2, "The clamped selection is written back")
        pivot.move(.previous, wrap: false)
        XCTAssertEqual(first.wrappedValue, 1)
        first.wrappedValue = 0
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(pivot.selectedIndex, 0)

        let second = FluentState(wrappedValue: 1)
        first.wrappedValue = 2
        let replacement = FluentPivot(shortHeaders, selection: second.projectedValue, header: { $0 }) { FluentText($0) }
        XCTAssertTrue(replacement._updateView(pivot, in: FluentRenderContext(reduceMotion: true)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(pivot.selectedIndex, 1, "A queued notification from the replaced binding is ignored")

        let shorter = FluentPivot(["All"], selection: second.projectedValue, header: { $0 }) { FluentText($0) }
        XCTAssertTrue(shorter._updateView(pivot, in: FluentRenderContext(reduceMotion: true)))
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertEqual(second.wrappedValue, 0)
        XCTAssertEqual(pivot.headerItems.count, 1)
    }

    @MainActor
    func testOnlySelectedContentIsVisibleAndDisabledStateHidesPipe() throws {
        var changes: [Int] = []
        _ = NSApplication.shared
        let view = FluentPivot(shortHeaders, onSelectionChanged: { changes.append($0) }, header: { $0 }) { FluentText($0) }
        let pivot = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentPivotControl)
        pivot.frame = NSRect(x: 0, y: 0, width: 600, height: 240)
        pivot.layoutSubtreeIfNeeded()
        XCTAssertEqual(pivot.contentHosts.map(\.isHidden), [false, true, true])
        XCTAssertEqual(pivot.contentHosts[0].frame.minX, 12, "PivotItemMargin")
        XCTAssertEqual(pivot.contentHosts[0].frame.minY, 0)
        XCTAssertTrue(changes.isEmpty, "Initial selection is not a change")
        XCTAssertTrue(pivot.headerItems[2].accessibilityPerformPress())
        XCTAssertEqual(changes, [2])
        XCTAssertEqual(pivot.contentHosts.map(\.isHidden), [true, true, false])
        XCTAssertEqual(pivot.accessibilityValue() as? String, "Flagged")
        XCTAssertEqual(pivot.headerItems[2].accessibilityValue() as? Bool, true)

        pivot.isEnabled = false
        XCTAssertFalse(pivot.headerItems[2].showsPipe)
        XCTAssertEqual(pivot.headerItems[0].foregroundColor.alphaComponent, 0.4, accuracy: 0.01)
        XCTAssertFalse(pivot.move(.previous, wrap: true))
        XCTAssertFalse(pivot.acceptsFirstResponder)
    }

    @MainActor
    func testTitleUsesSourcePaddingAndPushesHeadersDown() throws {
        let pivot = try makePivot(shortHeaders, title: "MAIL")
        let title = try XCTUnwrap(pivot.subviews.first { $0.identifier?.rawValue == "FluentKit.Pivot.Title" })
        XCTAssertFalse(title.isHidden)
        XCTAssertEqual(title.frame.minX, 12)
        XCTAssertEqual(title.frame.minY, 14)
        let headers = try XCTUnwrap(pivot.subviews.first { $0.identifier?.rawValue == "FluentKit.Pivot.Headers" })
        XCTAssertEqual(headers.frame.minY, title.frame.maxY + 13, accuracy: 0.5)
    }

    @MainActor
    func testAnimatedTransitionSettlesOnInterruption() throws {
        let pivot = try makePivot(shortHeaders, context: FluentRenderContext(reduceMotion: false))
        pivot.select(1, animated: true)
        XCTAssertTrue(pivot.isTransitioning)
        pivot.select(2, animated: true)
        let deadline = Date(timeIntervalSinceNow: 2)
        while pivot.isTransitioning, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        XCTAssertFalse(pivot.isTransitioning)
        XCTAssertEqual(pivot.contentHosts.map(\.isHidden), [true, true, false])
        XCTAssertEqual(pivot.contentHosts[2].layer?.opacity, 1)
        XCTAssertTrue(CATransform3DIsIdentity(pivot.contentHosts[2].layer?.transform ?? CATransform3DIdentity))
    }
}
