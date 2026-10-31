import XCTest
@testable import FluentKit

final class AnimatedVisualTests: XCTestCase {
    private struct StubSource: FluentAnimatedVisualSource {
        var duration: TimeInterval = 1
        var naturalSize = NSSize(width: 48, height: 48)
        var markers: [String: Double] = ["NormalToPointerOver_Start": 0.0, "NormalToPointerOver_End": 0.2,
                                         "PointerOverToNormal_Start": 0.3, "PointerOverToNormal_End": 0.5,
                                         "Checked": 0.9, "UncheckedToIndeterminate_End": 0.7]
        func makeVisual() -> FluentAnimatedVisual { StubVisual() }
    }
    private final class StubVisual: FluentAnimatedVisual {
        let rootLayer = CALayer()
        var progress: [Double] = []
        func setProgress(_ progress: Double) { self.progress.append(progress) }
        func setForeground(_ color: NSColor) {}
    }

    @MainActor
    private func makeIcon(_ source: FluentAnimatedVisualSource?, fallback: String? = nil, queue: FluentAnimatedIconQueueBehavior = .cut,
                          reduceMotion: Bool = true) throws -> FluentAnimatedIconView {
        _ = NSApplication.shared
        let icon = try XCTUnwrap(FluentAnimatedIcon(source: source, fallbackSymbol: fallback, state: "Normal", queueBehavior: queue)
            ._makeView(in: FluentRenderContext(reduceMotion: reduceMotion)) as? FluentAnimatedIconView)
        icon.frame = NSRect(x: 0, y: 0, width: 16, height: 16)
        icon.layoutSubtreeIfNeeded()
        return icon
    }

    @MainActor
    func testStateChangesPickSourceMarkersInWinUIOrder() throws {
        let icon = try makeIcon(StubSource())
        icon.setState("PointerOver"); icon.applyPendingState()
        XCTAssertEqual(icon.lastAnimationSegment, "NormalToPointerOver")
        XCTAssertEqual(icon.progress, 0.2, accuracy: 0.0001, "Reduce Motion cuts to the segment end")
        XCTAssertEqual(icon.currentState, "PointerOver")
        icon.setState("Checked"); icon.applyPendingState()
        XCTAssertEqual(icon.progress, 0.9, accuracy: 0.0001, "A marker named after the state")
        icon.setState("Indeterminate"); icon.applyPendingState()
        XCTAssertEqual(icon.progress, 0.7, accuracy: 0.0001, "Any segment ending in the state")
        icon.setState("0.42"); icon.applyPendingState()
        XCTAssertEqual(icon.progress, 0.42, accuracy: 0.0001, "A numeric state is a progress")
        icon.setState("Unknown"); icon.applyPendingState()
        XCTAssertEqual(icon.progress, 0, "Otherwise frame 0")
    }

    @MainActor
    func testRapidStateChangesCollapseIntoTheLastOne() throws {
        let icon = try makeIcon(StubSource())
        icon.setState("Pressed")
        icon.setState("PointerOver")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(icon.currentState, "PointerOver")
        XCTAssertEqual(icon.lastAnimationSegment, "NormalToPointerOver", "Normal→Pressed never plays")
    }

    @MainActor
    func testSegmentsAnimateLinearlyAndQueueOneWaits() throws {
        let icon = try makeIcon(StubSource(), queue: .queueOne, reduceMotion: false)
        icon.setState("PointerOver"); icon.applyPendingState()
        XCTAssertTrue(icon.driver.isPlaying, "A 200ms segment animates")
        icon.setState("Normal"); icon.applyPendingState()
        XCTAssertEqual(icon.queuedStates, ["Normal"], "QueueOne waits for the running segment")
        let deadline = Date(timeIntervalSinceNow: 2)
        while (icon.driver.isPlaying || !icon.queuedStates.isEmpty), Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        XCTAssertEqual(icon.currentState, "Normal")
        XCTAssertEqual(icon.progress, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testFallbackSymbolWithoutSource() throws {
        let icon = try makeIcon(nil, fallback: "star")
        XCTAssertTrue(icon.isShowingFallback)
        XCTAssertNil(icon.visual)
    }

    @MainActor
    func testPlayerAutoPlaysLoopsAndControllerControlsPlayback() throws {
        _ = NSApplication.shared
        let controller = FluentAnimatedVisualPlayerController()
        let player = try XCTUnwrap(FluentAnimatedVisualPlayer(source: StubSource(), controller: controller)
            ._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentAnimatedVisualPlayerView)
        XCTAssertTrue(player.isAnimatedVisualLoaded)
        XCTAssertTrue(controller.isPlaying, "AutoPlay loops 0…1")
        controller.pause()
        XCTAssertFalse(controller.isPlaying)
        controller.setProgress(0.6)
        XCTAssertEqual(controller.progress, 0.6)
        var finished: Bool?
        controller.play(from: 0, to: 0.05, completion: { finished = $0 })
        let deadline = Date(timeIntervalSinceNow: 2)
        while finished == nil, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        XCTAssertEqual(finished, true)
        XCTAssertEqual(controller.progress, 0.05, accuracy: 0.0001)
        var stopped: Bool?
        controller.play(from: 0, to: 1, looped: true, completion: { stopped = $0 })
        controller.stop()
        XCTAssertEqual(stopped, false, "Stopping completes a looped play as cancelled")
        XCTAssertEqual(controller.progress, 0)
    }

    @MainActor
    func testPlayerFallbackAndStretch() throws {
        _ = NSApplication.shared
        let empty = try XCTUnwrap(FluentAnimatedVisualPlayer(source: nil, fallback: FluentAnyView(FluentText("No animation")))
            ._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentAnimatedVisualPlayerView)
        XCTAssertFalse(empty.isAnimatedVisualLoaded)
        XCTAssertNotNil(empty.fallbackHost)

        let player = try XCTUnwrap(FluentAnimatedVisualPlayer(source: StubSource(), autoPlay: false, stretch: .uniform)
            ._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentAnimatedVisualPlayerView)
        player.frame = NSRect(x: 0, y: 0, width: 96, height: 48)
        player.layoutSubtreeIfNeeded()
        XCTAssertEqual(player.visual?.rootLayer.affineTransform().a ?? 0, 1, accuracy: 0.0001, "Uniform fits the smaller axis")
        XCTAssertFalse(player.driver.isPlaying, "No AutoPlay")
    }

    func testBuiltInSourcesUseWinUIMarkerTimelinesAndPoses() {
        let back = FluentBuiltInAnimatedIconSource(.back)
        XCTAssertEqual(back.duration, 1.3333333, accuracy: 0.0001)
        XCTAssertEqual(back.markers["PressedToNormal_End"], 0.738125)
        XCTAssertEqual(back.pose(at: 0.113125).translation.x, -2, accuracy: 0.001, "End of NormalToPointerOver rests on PointerOver")
        XCTAssertEqual(back.pose(at: 0.0565625).translation.x, -1, accuracy: 0.001, "Halfway eases half the distance")
        XCTAssertEqual(back.pose(at: 0.738125).translation.x, 0, accuracy: 0.001)
        let chevron = FluentBuiltInAnimatedIconSource(.chevronDownSmall)
        XCTAssertEqual(chevron.pose(at: 0.312068965517241).translation.y, 2, accuracy: 0.001)
        XCTAssertEqual(chevron.pose(at: 0.967241379310345).translation.y, 0, accuracy: 0.001)
        let visual = FluentBuiltInAnimatedVisual(source: chevron)
        visual.setProgress(0.312068965517241)
        XCTAssertEqual(visual.rootLayer.sublayers?.first?.transform.m42 ?? 0, 2, accuracy: 0.001,
                       "Pressed moves the chevron down in the flipped host")
        XCTAssertEqual(FluentBuiltInAnimatedIconSource(.settings).duration, 2)
        for glyph in FluentBuiltInAnimatedIconSource.Glyph.allCases {
            XCTAssertEqual(FluentBuiltInAnimatedIconSource(glyph).markers.count, 12)
        }
    }
}
