import XCTest
@testable import FluentKit

final class AnnotatedScrollBarTests: XCTestCase {
    private final class Log { var scrolls: [(CGFloat, FluentAnnotatedScrollBarScrollingKind)] = []; var cancel = false }

    @MainActor
    private func makeView(labels: [FluentAnnotatedScrollBarLabel], contentHeight: CGFloat = 2_000, smallChange: CGFloat = 0,
                          log: Log, detail: ((CGFloat) -> String?)? = nil) throws -> FluentAnnotatedScrollViewControl {
        _ = NSApplication.shared
        let view = FluentAnnotatedScrollView(labels: labels, smallChange: smallChange, detailLabel: detail,
                                             onScrolling: { log.scrolls.append(($0, $1)); return log.cancel }) {
            FluentText("Content").frame(width: 200, height: contentHeight)
        }
        let control = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentAnnotatedScrollViewControl)
        control.frame = NSRect(x: 0, y: 0, width: 300, height: 440)
        control.layoutSubtreeIfNeeded()
        return control
    }

    @MainActor
    func testRailGeometryAndSourceOffsetMapping() throws {
        let log = Log()
        let control = try makeView(labels: [], log: log)
        let bar = control.bar
        XCTAssertEqual(bar.frame.width, 44, "LabelsGridMinWidth")
        XCTAssertEqual(bar.frame.maxX, 300, "The bar sits at the trailing edge")
        XCTAssertEqual(control.maximumOffset, 1_560)
        let rail = bar.railFrame.height
        let expected = (rail - 3) / 1_560 * (1 - 440 / (440 + 1_560))
        XCTAssertEqual(bar.scrollOffsetToLabelOffsetFactor, expected, accuracy: 0.0001)
        control.scroll(to: 780)
        XCTAssertEqual(bar.value, 780)
        XCTAssertEqual(bar.effectiveSmallChange, 55, "Default SmallChange is a viewport divided by 8")
    }

    @MainActor
    func testClickAndDragScrollAndScrollingCanCancel() throws {
        let log = Log()
        let control = try makeView(labels: [], log: log)
        let bar = control.bar
        bar.scrollTo(400, kind: .click)
        XCTAssertEqual(control.scrollOffset, 400)
        bar.scrollTo(99_999, kind: .drag)
        XCTAssertEqual(control.scrollOffset, control.maximumOffset, "Targets clamp to the scrollable range")
        log.cancel = true
        bar.scrollTo(10, kind: .click)
        XCTAssertEqual(control.scrollOffset, control.maximumOffset, "A cancelled Scrolling event does not scroll")
        XCTAssertEqual(log.scrolls.map(\.1), [.click, .drag, .click])
    }

    @MainActor
    func testStepButtonsUseSmallChangeAndStopAtTheEnds() throws {
        let log = Log()
        let control = try makeView(labels: [], smallChange: 100, log: log)
        let bar = control.bar
        bar.scrollTo(nil, kind: .decrementButton)
        XCTAssertEqual(control.scrollOffset, 100, "The bottom (decrement) button moves down")
        bar.scrollTo(nil, kind: .incrementButton)
        bar.scrollTo(nil, kind: .incrementButton)
        XCTAssertEqual(control.scrollOffset, 0, "The top (increment) button stops at the start")
        XCTAssertEqual(log.scrolls.map(\.0), [100, 0, 0])
    }

    @MainActor
    func testCollidingAndOutOfBoundsLabelsCollapseLikeTheSource() throws {
        let log = Log()
        let labels = [FluentAnnotatedScrollBarLabel("A", scrollOffset: 0),
                      FluentAnnotatedScrollBarLabel("B", scrollOffset: 5),
                      FluentAnnotatedScrollBarLabel("M", scrollOffset: 800),
                      FluentAnnotatedScrollBarLabel("N", scrollOffset: 810),
                      FluentAnnotatedScrollBarLabel("Z", scrollOffset: 1_500),
                      FluentAnnotatedScrollBarLabel("Beyond", scrollOffset: 9_000)]
        let control = try makeView(labels: labels, log: log)
        let visible = control.bar.visibleLabelIndices
        XCTAssertFalse(visible.contains(5), "Out-of-bounds labels collapse")
        XCTAssertTrue(visible.contains(4), "The bottom-most label stays")
        XCTAssertTrue(visible.contains(0), "The first label wins over the second")
        XCTAssertFalse(visible.contains(1))
        XCTAssertTrue(visible.contains(3) != visible.contains(2), "Only one of a colliding pair is shown")
        XCTAssertTrue(visible.contains(3), "The lower of a colliding pair stays")
    }

    @MainActor
    func testHoverShowsGhostAndDetailLabelRaisedForTouch() throws {
        let log = Log()
        let control = try makeView(labels: [], log: log, detail: { "Offset \(Int($0))" })
        let bar = control.bar
        bar.showHoverVisuals(atRailOffset: 200, isTouch: false)
        let bubble = bar.detailBubble
        XCTAssertFalse(bubble.isHidden)
        XCTAssertTrue(bubble.text.hasPrefix("Offset "))
        XCTAssertGreaterThanOrEqual(bubble.frame.height, 40, "AnnotatedScrollBarTooltipMinHeight")
        let mouseY = bubble.frame.minY
        bar.showHoverVisuals(atRailOffset: 200, isTouch: true)
        XCTAssertEqual(bubble.frame.minY, mouseY - 22, accuracy: 0.5, "Touch raises the label by 22pt")
        bar.hideHoverVisuals()
        XCTAssertTrue(bubble.isHidden)
    }

    @MainActor
    func testShortContentCannotScrollAndRightToLeftMirrors() throws {
        let log = Log()
        let short = try makeView(labels: [], contentHeight: 100, log: log)
        XCTAssertFalse(short.bar.canScroll)
        short.bar.scrollTo(50, kind: .click)
        XCTAssertTrue(log.scrolls.isEmpty)
        XCTAssertFalse(short.bar.incrementButton.isEnabled)

        let rtl = try makeView(labels: [], log: log)
        rtl.userInterfaceLayoutDirection = .rightToLeft
        rtl.needsLayout = true
        rtl.layoutSubtreeIfNeeded()
        XCTAssertEqual(rtl.bar.frame.minX, 0)
        XCTAssertEqual(rtl.scrollView.frame.minX, 44)
    }
}
