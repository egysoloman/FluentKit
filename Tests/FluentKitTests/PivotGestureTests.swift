import XCTest
@testable import FluentKit

final class PivotGestureTests: XCTestCase {
    private let shortHeaders = ["All", "Unread", "Flagged"]
    private let longHeaders = ["Inbox", "Unread messages", "Flagged items", "Scheduled", "Archive"]

    @MainActor
    private func makePivot(
        _ headers: [String],
        selection: FluentBinding<Int>? = nil,
        width: CGFloat = 600,
        carousel: Bool = true,
        isLocked: Bool = false,
        reduceMotion: Bool = true,
        onSelectionChanged: ((Int) -> Void)? = nil
    ) throws -> FluentPivotControl {
        _ = NSApplication.shared
        let view = FluentPivot(headers, selection: selection, isLocked: isLocked, isHeaderItemsCarouselEnabled: carousel,
                               onSelectionChanged: onSelectionChanged, header: { $0 }) { FluentText($0) }
        let pivot = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: reduceMotion)) as? FluentPivotControl)
        pivot.frame = NSRect(x: 0, y: 0, width: width, height: 240)
        pivot.layoutSubtreeIfNeeded()
        return pivot
    }

    private func scroll(dx: CGFloat, dy: CGFloat = 0, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [],
                        precise: Bool = true, time: TimeInterval) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
                            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        // CGScrollPhase and CGMomentumScrollPhase use their own numbering, not NSEvent.Phase bits.
        let scrollPhase: Int64 = phase.contains(.began) ? 1 : phase.contains(.changed) ? 2
            : phase.contains(.ended) ? 4 : phase.contains(.cancelled) ? 8 : 0
        let momentumPhase: Int64 = momentum.contains(.began) ? 1 : momentum.contains(.changed) ? 2
            : momentum.contains(.ended) ? 3 : 0
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        if precise {
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
        }
        event.timestamp = CGEventTimestamp(time * 1_000_000_000)
        return NSEvent(cgEvent: event)!
    }

    private func width(_ pivot: FluentPivotControl) -> CGFloat { try! XCTUnwrap(pivot.panSectionWidth) }

    @MainActor
    func testShortPanFollowsTheFingerShowsTheNeighbourAndSnapsBack() throws {
        let pivot = try makePivot(shortHeaders)
        XCTAssertEqual(pivot.beginInteractivePan(), 0)
        pivot.updateInteractivePan(translation: -120)
        XCTAssertEqual(pivot.panOffset, -120)
        XCTAssertEqual(pivot.panNeighbor, 1)
        XCTAssertEqual(pivot.contentHosts[0].frame.minX, 12 - 120, accuracy: 0.01)
        XCTAssertEqual(pivot.contentHosts[1].frame.minX, 12 - 120 + width(pivot), accuracy: 0.01)
        XCTAssertEqual(pivot.contentHosts.map(\.isHidden), [false, false, true])
        XCTAssertEqual(pivot.headerItems[0].frame.minX, 0, "Fitting static headers do not move with the content")
        pivot.endInteractivePan(velocity: 0)
        XCTAssertFalse(pivot.isPanning)
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertEqual(pivot.contentHosts.map(\.isHidden), [false, true, true])
        XCTAssertEqual(pivot.contentHosts[0].frame.minX, 12)
    }

    @MainActor
    func testPanPastHalfOrFlickCommitsOnceAndWritesTheBinding() throws {
        var changes: [Int] = []
        let state = FluentState(wrappedValue: 0)
        let pivot = try makePivot(shortHeaders, selection: state.projectedValue, onSelectionChanged: { changes.append($0) })
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -width(pivot) * 0.6)
        pivot.endInteractivePan(velocity: 0)
        XCTAssertEqual(pivot.selectedIndex, 1)
        XCTAssertEqual(state.wrappedValue, 1)
        XCTAssertEqual(changes, [1])
        XCTAssertEqual(pivot.contentHosts[1].frame.minX, 12)

        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: 40)
        pivot.endInteractivePan(velocity: 2_000)
        XCTAssertEqual(pivot.selectedIndex, 0, "A fast flick commits even below half the width")
        XCTAssertEqual(changes, [1, 0])

        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -width(pivot) * 0.6)
        pivot.endInteractivePan(velocity: 3_000)
        XCTAssertEqual(pivot.selectedIndex, 0, "A flick back against the drag snaps back")
        XCTAssertEqual(pivot.panOffset, 0)
    }

    @MainActor
    func testTravelIsLimitedToOneItemAndStaticEndsRubberBand() throws {
        let pivot = try makePivot(shortHeaders)
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -width(pivot) * 3)
        XCTAssertEqual(pivot.panOffset, -width(pivot), "MandatorySingle snapping limits a pan to one item")
        pivot.cancelInteractivePan(animated: false)

        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: 200)
        XCTAssertNil(pivot.panNeighbor, "Static headers do not wrap to the last item")
        XCTAssertGreaterThan(pivot.panOffset, 0)
        XCTAssertLessThan(pivot.panOffset, 200, "Overpan is damped")
        pivot.updateInteractivePan(translation: 10_000)
        XCTAssertLessThan(pivot.panOffset, width(pivot))
        pivot.endInteractivePan(velocity: 5_000)
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertFalse(pivot.isPanning)
    }

    @MainActor
    func testCarouselHeadersFollowThePanAndWrap() throws {
        let pivot = try makePivot(longHeaders, width: 320)
        XCTAssertFalse(pivot.usesStaticHeaders)
        let selectedWidth = pivot.headerItems[0].frame.width
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -width(pivot) / 2)
        XCTAssertEqual(pivot.headerItems[0].frame.minX, -selectedWidth / 2, accuracy: 0.01,
                       "Toward next, headers travel by the selected header's width per item")
        pivot.updateInteractivePan(translation: width(pivot) * 0.6)
        XCTAssertEqual(pivot.panNeighbor, 4, "The carousel wraps to the last item")
        let previous = pivot.headerItems[4]
        XCTAssertEqual(previous.frame.minX, -previous.frame.width * 0.4, accuracy: 0.01,
                       "The previous header enters from the leading edge by its own width per item")
        XCTAssertEqual(pivot.headerItems[0].frame.minX, previous.frame.width * 0.6, accuracy: 0.01)
        pivot.endInteractivePan(velocity: 0)
        XCTAssertEqual(pivot.selectedIndex, 4)
        XCTAssertEqual(pivot.panHeaderShift, 0)
        XCTAssertEqual(pivot.headerItems[4].frame.minX, 0)
    }

    @MainActor
    func testClippedStaticHeadersInterpolateTheirShiftDuringAPan() throws {
        let pivot = try makePivot(longHeaders, width: 320, carousel: false)
        pivot.select(2, animated: false)
        pivot.layoutSubtreeIfNeeded()
        let before = pivot.headerItems[0].frame.minX
        pivot.select(3, animated: false)
        pivot.layoutSubtreeIfNeeded()
        let after = pivot.headerItems[0].frame.minX
        pivot.select(2, animated: false)
        pivot.layoutSubtreeIfNeeded()
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -width(pivot) / 2)
        XCTAssertEqual(pivot.headerItems[0].frame.minX, (before + after) / 2, accuracy: 0.5)
        pivot.cancelInteractivePan(animated: false)
        XCTAssertEqual(pivot.headerItems[0].frame.minX, before, accuracy: 0.01)
    }

    @MainActor
    func testRightToLeftMirrorsPhysicalMotion() throws {
        let pivot = try makePivot(shortHeaders)
        pivot.userInterfaceLayoutDirection = .rightToLeft
        pivot.needsLayout = true
        pivot.layoutSubtreeIfNeeded()
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -100)
        XCTAssertEqual(pivot.contentHosts[0].frame.minX, 12 + 100, accuracy: 0.01, "Toward next moves content right in RTL")
        XCTAssertEqual(pivot.contentHosts[1].frame.minX, 12 + 100 - width(pivot), accuracy: 0.01)
        pivot.cancelInteractivePan(animated: false)
    }

    @MainActor
    func testLockedDisabledAndSingleItemPivotsDoNotPan() throws {
        XCTAssertNil(try makePivot(shortHeaders, isLocked: true).beginInteractivePan())
        XCTAssertNil(try makePivot(["Only"]).beginInteractivePan())
        let pivot = try makePivot(shortHeaders)
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -200)
        pivot.isEnabled = false
        XCTAssertFalse(pivot.isPanning, "Disabling cancels an active pan")
        XCTAssertEqual(pivot.contentHosts.map(\.isHidden), [false, true, true])
        XCTAssertNil(pivot.beginInteractivePan())
    }

    @MainActor
    func testTrackpadPhasesDriveThePanAndConsumeMomentum() throws {
        let pivot = try makePivot(shortHeaders)
        pivot.scrollWheel(with: scroll(dx: -3, phase: .began, time: 1.00))
        XCTAssertFalse(pivot.isPanning, "The axis is decided after the threshold")
        pivot.scrollWheel(with: scroll(dx: -20, phase: .changed, time: 1.01))
        XCTAssertTrue(pivot.isPanning)
        XCTAssertEqual(pivot.panOffset, -23, accuracy: 0.01)
        for step in 0..<10 { pivot.scrollWheel(with: scroll(dx: -25, phase: .changed, time: 1.02 + Double(step) * 0.01)) }
        pivot.scrollWheel(with: scroll(dx: 0, phase: .ended, time: 1.12))
        XCTAssertFalse(pivot.isPanning)
        XCTAssertEqual(pivot.selectedIndex, 1, "A fast two-finger swipe toward the leading edge advances")
        pivot.scrollWheel(with: scroll(dx: -30, momentum: .began, time: 1.13))
        pivot.scrollWheel(with: scroll(dx: -10, momentum: .changed, time: 1.14))
        pivot.scrollWheel(with: scroll(dx: 0, momentum: .ended, time: 1.15))
        XCTAssertEqual(pivot.selectedIndex, 1, "Momentum from an owned swipe does not move again")

        pivot.scrollWheel(with: scroll(dx: 1, dy: -6, phase: .began, time: 2.0))
        pivot.scrollWheel(with: scroll(dx: 1, dy: -20, phase: .changed, time: 2.01))
        XCTAssertFalse(pivot.isPanning, "Vertical swipes are left to enclosing scroll views")
        pivot.scrollWheel(with: scroll(dx: 0, phase: .ended, time: 2.02))
        XCTAssertEqual(pivot.selectedIndex, 1)
    }

    @MainActor
    func testDiscreteHorizontalWheelStepsOncePerBurst() throws {
        let pivot = try makePivot(shortHeaders)
        pivot.scrollWheel(with: scroll(dx: -1, precise: false, time: 5.0))
        XCTAssertEqual(pivot.selectedIndex, 1)
        pivot.scrollWheel(with: scroll(dx: -1, precise: false, time: 5.1))
        XCTAssertEqual(pivot.selectedIndex, 1, "Within 200ms the burst is suppressed")
        pivot.scrollWheel(with: scroll(dx: -1, precise: false, time: 5.4))
        XCTAssertEqual(pivot.selectedIndex, 2)
        pivot.scrollWheel(with: scroll(dx: 0, dy: -1, precise: false, time: 6.0))
        XCTAssertEqual(pivot.selectedIndex, 2, "Vertical wheel does not switch items")
    }

    @MainActor
    func testAnimatedSettleCanBeInterruptedByANewPan() throws {
        let pivot = try makePivot(shortHeaders, reduceMotion: false)
        pivot.beginInteractivePan()
        pivot.updateInteractivePan(translation: -width(pivot) * 0.7)
        pivot.endInteractivePan(velocity: 0)
        XCTAssertTrue(pivot.isPanning, "The finish is animated")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let resumed = try XCTUnwrap(pivot.beginInteractivePan())
        XCTAssertLessThan(resumed, -width(pivot) * 0.7, "A new touch takes over from the settling offset")
        pivot.updateInteractivePan(translation: resumed + 400)
        pivot.endInteractivePan(velocity: 0)
        let deadline = Date(timeIntervalSinceNow: 2)
        while pivot.isPanning, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        XCTAssertFalse(pivot.isPanning)
        XCTAssertEqual(pivot.selectedIndex, 0)
        XCTAssertEqual(pivot.contentHosts[0].frame.minX, 12)
    }

    @MainActor
    func testDirectTouchRecognizerConfiguration() throws {
        let pivot = try makePivot(shortHeaders)
        guard #available(macOS 27, *) else {
            XCTAssertNil(pivot.touchPanRecognizer)
            return
        }
        let recognizer = try XCTUnwrap(pivot.touchPanRecognizer)
        XCTAssertTrue(pivot.gestureRecognizers.contains { $0 === recognizer })
        XCTAssertEqual(recognizer.allowedTouchTypes, [.direct])
        XCTAssertEqual(recognizer.buttonMask, 0, "Mouse drags must not pan")
        XCTAssertEqual(recognizer.value(forKey: "minimumNumberOfTouches") as? Int, 1)
        XCTAssertEqual(recognizer.value(forKey: "maximumNumberOfTouches") as? Int, 1)
        XCTAssertEqual(recognizer.value(forKey: "cancellableByScrollGesture") as? Bool, true)
        XCTAssertTrue(recognizer.delegate === pivot.panDriver)
    }
}
