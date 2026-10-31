import XCTest
@testable import FluentKit

final class RefreshContainerTests: XCTestCase {
    private final class Log { var requests: [FluentRefreshDeferral] = [] }

    @MainActor
    private func makeContainer(direction: FluentRefreshPullDirection = .topToBottom, binding: FluentBinding<Bool>? = nil,
                               log: Log) throws -> FluentRefreshContainerView {
        _ = NSApplication.shared
        let view = FluentRefreshContainer(pullDirection: direction, isRefreshing: binding, onRefreshRequested: { log.requests.append($0) }) {
            FluentText("Inbox").frame(width: 300, height: 800)
        }
        let container = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentRefreshContainerView)
        container.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        container.layoutSubtreeIfNeeded()
        return container
    }

    @MainActor
    func testStatesFollowTheSourceStateMachine() throws {
        let log = Log()
        let container = try makeContainer(log: log)
        XCTAssertEqual(container.state, .idle)
        container.interactingChanged(true)
        container.interactionRatioChanged(0.3)
        XCTAssertEqual(container.state, .interacting)
        XCTAssertEqual(container.indicator.glyphOpacity, 0.4, "MINIMUM_INDICATOR_OPACITY")
        container.interactionRatioChanged(0.85)
        XCTAssertEqual(container.state, .pending)
        XCTAssertEqual(container.indicator.glyphOpacity, 1)
        container.interactionRatioChanged(0.5)
        XCTAssertEqual(container.state, .interacting, "Dropping back under the execution ratio leaves Pending")
        container.interactingChanged(false)
        XCTAssertEqual(container.state, .idle, "Releasing before Pending does not refresh")
        XCTAssertTrue(log.requests.isEmpty)
    }

    @MainActor
    func testReleasingInPendingRefreshesHoldsContentAndCompletes() throws {
        let log = Log()
        let state = FluentState(wrappedValue: false)
        let container = try makeContainer(binding: state.projectedValue, log: log)
        container.interactingChanged(true)
        container.interactionRatioChanged(0.9)
        container.interactingChanged(false)
        XCTAssertEqual(container.state, .refreshing)
        XCTAssertEqual(log.requests.count, 1)
        XCTAssertTrue(state.wrappedValue, "isRefreshing reports the running refresh")
        XCTAssertEqual(container.scrollView.contentInsets.top, 80, "Content is held at 100 x 0.8 while refreshing")
        XCTAssertEqual(container.pullDistance, 80, accuracy: 0.5)
        XCTAssertFalse(container.indicator.isHidden)
        container.interactingChanged(true)
        container.interactingChanged(false)
        XCTAssertEqual(container.state, .refreshing, "A running refresh is not interrupted")
        log.requests[0].complete()
        log.requests[0].complete()
        XCTAssertEqual(container.state, .idle)
        XCTAssertFalse(state.wrappedValue)
        XCTAssertEqual(container.scrollView.contentInsets.top, 0)
        XCTAssertEqual(container.pullDistance, 0)
    }

    @MainActor
    func testFirstJumpPastExecutionAndPeekingFromIdle() throws {
        let log = Log()
        let container = try makeContainer(log: log)
        container.interactingChanged(true)
        container.interactionRatioChanged(0.95)
        XCTAssertEqual(container.state, .pending, "A first value already past 0.8 goes straight to Pending")
        container.interactingChanged(false)
        log.requests.first?.complete()

        let peeking = try makeContainer(log: log)
        peeking.interactionRatioChanged(0.2)
        peeking.interactingChanged(true)
        peeking.interactionRatioChanged(0.3)
        XCTAssertEqual(peeking.state, .peeking, "A non-zero start while interacting peeks")
    }

    @MainActor
    func testIndicatorRotatesOneTurnAtTheExecutionRatioWithParallax() throws {
        let log = Log()
        let container = try makeContainer(log: log)
        container.interactingChanged(true)
        container.interactionRatioChanged(0.4)
        XCTAssertEqual(container.indicator.rotation, .pi, accuracy: 0.0001, "Half the execution ratio is half a turn")
        container.interactionRatioChanged(1)
        XCTAssertEqual(container.indicator.rotation, 2 * .pi, accuracy: 0.0001, "Clamped at the execution ratio")
        XCTAssertEqual(container.indicator.frame.size, NSSize(width: 30, height: 30))
    }

    @MainActor
    func testProgrammaticRefreshAndOtherDirections() throws {
        let log = Log()
        let state = FluentState(wrappedValue: false)
        let container = try makeContainer(binding: state.projectedValue, log: log)
        state.wrappedValue = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(container.state, .refreshing, "Setting isRefreshing requests a refresh")
        log.requests.last?.complete()
        XCTAssertFalse(state.wrappedValue)

        let left = try makeContainer(direction: .leftToRight, log: log)
        left.requestRefresh()
        XCTAssertEqual(left.scrollView.contentInsets.left, 80)
        XCTAssertEqual(left.indicator.startingRotation, -.pi / 2)
        XCTAssertEqual(left.indicator.frame.midY, left.bounds.midY, accuracy: 0.5)

        let bottom = try makeContainer(direction: .bottomToTop, log: log)
        bottom.requestRefresh()
        XCTAssertEqual(bottom.scrollView.contentInsets.bottom, 80)
        XCTAssertEqual(bottom.pullDistance, 80, accuracy: 0.5)
    }
}
