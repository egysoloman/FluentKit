import XCTest
@testable import FluentKit

final class SemanticZoomTests: XCTestCase {
    private final class Log { var changes: [(Bool, AnyHashable?)] = [] }

    @MainActor
    private func makeZoom(binding: FluentBinding<Bool>? = nil, canChangeViews: Bool = true, button: Bool = false,
                          wheel: Bool = false, log: Log, reduceMotion: Bool = true) throws -> (FluentSemanticZoomControl, () -> FluentSemanticZoomProxy?) {
        _ = NSApplication.shared
        var proxy: FluentSemanticZoomProxy?
        let view = FluentSemanticZoom(isZoomedInViewActive: binding, canChangeViews: canChangeViews,
                                      isZoomOutButtonEnabled: button, allowsWheelZoom: wheel,
                                      onViewChangeCompleted: { log.changes.append(($0, $1)) },
                                      zoomedInView: { FluentText("Detail") },
                                      zoomedOutView: { p in proxy = p; return FluentText("Overview") })
        let control = try XCTUnwrap(view._makeView(in: FluentRenderContext(reduceMotion: reduceMotion)) as? FluentSemanticZoomControl)
        control.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        control.layoutSubtreeIfNeeded()
        return (control, { proxy })
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    @MainActor
    func testStartsZoomedInAndShowsOnlyTheActiveView() throws {
        let log = Log()
        let (zoom, _) = try makeZoom(log: log)
        XCTAssertTrue(zoom.isZoomedIn)
        XCTAssertEqual(zoom.zoomedInHost?.isHidden, false)
        XCTAssertEqual(zoom.zoomedOutHost?.isHidden, true)
        XCTAssertEqual(zoom.zoomedInHost?.frame, zoom.bounds)
    }

    @MainActor
    func testPinchPastFivePercentSwitchesAndSmallerPinchesSnapBack() throws {
        let log = Log()
        let (zoom, _) = try makeZoom(log: log)
        XCTAssertTrue(zoom.beginPinch())
        zoom.updatePinch(scale: 0.97)
        XCTAssertEqual(zoom.pinchScale, 0.97)
        zoom.endPinch(scale: 0.97)
        XCTAssertTrue(zoom.isZoomedIn, "A 3% pinch is below the threshold")
        XCTAssertEqual(zoom.pinchScale, 1)

        zoom.beginPinch()
        zoom.updatePinch(scale: 0.2)
        XCTAssertEqual(zoom.pinchScale, 0.5, "The zoomed-in view follows within the 0.5 zoom floor")
        zoom.endPinch(scale: 0.2)
        XCTAssertFalse(zoom.isZoomedIn)
        XCTAssertEqual(zoom.zoomedOutHost?.isHidden, false)
        XCTAssertEqual(zoom.zoomedInHost?.isHidden, true)

        zoom.beginPinch()
        zoom.endPinch(scale: 1.1)
        XCTAssertTrue(zoom.isZoomedIn, "Spreading in the zoomed-out view zooms back in")
        XCTAssertEqual(log.changes.map(\.0), [false, true])
    }

    @MainActor
    func testKeyboardZoomUsesControlOrCommandWithMinusAndPlus() throws {
        let log = Log()
        let (zoom, _) = try makeZoom(log: log)
        XCTAssertFalse(zoom.handleZoomKey(key(24, .control)), "Already zoomed in")
        XCTAssertFalse(zoom.handleZoomKey(key(27, [])), "Minus alone does nothing")
        XCTAssertTrue(zoom.handleZoomKey(key(27, .control)))
        XCTAssertFalse(zoom.isZoomedIn)
        XCTAssertTrue(zoom.handleZoomKey(key(69, .command)), "Keypad plus with Command zooms in")
        XCTAssertTrue(zoom.isZoomedIn)
        XCTAssertNil(FluentSemanticZoomControl.zoomDirection(for: key(27, [.control, .option])))
    }

    @MainActor
    func testProxyCarriesTheChosenDestinationAndCanChangeViewsBlocksEverything() throws {
        let log = Log()
        let (zoom, proxy) = try makeZoom(log: log)
        zoom.setZoomedIn(false, destination: nil, animated: false)
        try XCTUnwrap(proxy()).zoomIn(to: "M")
        XCTAssertTrue(zoom.isZoomedIn)
        XCTAssertEqual(log.changes.last?.1, AnyHashable("M"))

        let lockedLog = Log()
        let (locked, _) = try makeZoom(canChangeViews: false, log: lockedLog)
        XCTAssertFalse(locked.beginPinch())
        XCTAssertFalse(locked.handleZoomKey(key(27, .control)))
        locked.setZoomedIn(false, destination: nil, animated: false)
        XCTAssertTrue(locked.isZoomedIn)
        XCTAssertTrue(lockedLog.changes.isEmpty)
    }

    @MainActor
    func testBindingRoundTripsAndRebindingIgnoresQueuedNotifications() throws {
        let log = Log()
        let state = FluentState(wrappedValue: false)
        let (zoom, _) = try makeZoom(binding: state.projectedValue, log: log)
        XCTAssertFalse(zoom.isZoomedIn, "The bound value wins at creation")
        XCTAssertTrue(log.changes.isEmpty)
        zoom.setZoomedIn(true, destination: nil, animated: false)
        XCTAssertTrue(state.wrappedValue)
        state.wrappedValue = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertFalse(zoom.isZoomedIn)

        let other = FluentState(wrappedValue: false)
        state.wrappedValue = true
        let replacement = FluentSemanticZoom(isZoomedInViewActive: other.projectedValue,
                                             zoomedInView: { FluentText("Detail") }, zoomedOutView: { _ in FluentText("Overview") })
        XCTAssertTrue(replacement._updateView(zoom, in: FluentRenderContext(reduceMotion: true)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertFalse(zoom.isZoomedIn, "A queued notification from the replaced binding is ignored")
    }

    @MainActor
    func testZoomOutButtonIsOptInPointerOnlyAndHidesWhenZoomedOut() throws {
        let log = Log()
        let (plain, _) = try makeZoom(log: log)
        plain.showZoomOutButtonIfAllowed()
        XCTAssertTrue(plain.zoomOutButton.isHidden, "Disabled by default, as in generic.xaml")

        let (zoom, _) = try makeZoom(button: true, log: log)
        zoom.showZoomOutButtonIfAllowed()
        XCTAssertFalse(zoom.zoomOutButton.isHidden)
        XCTAssertEqual(zoom.zoomOutButton.frame, NSRect(x: 400 - 19 - 12, y: 300 - 19 - 12, width: 12, height: 12))
        XCTAssertTrue(zoom.zoomOutButton.accessibilityPerformPress())
        XCTAssertFalse(zoom.isZoomedIn)
        XCTAssertTrue(zoom.zoomOutButton.isHidden)
        zoom.showZoomOutButtonIfAllowed()
        XCTAssertTrue(zoom.zoomOutButton.isHidden, "Only shown in the zoomed-in view")
    }

    @MainActor
    func testAnimatedSwitchSettles() throws {
        let log = Log()
        let (zoom, _) = try makeZoom(log: log, reduceMotion: false)
        zoom.setZoomedIn(false, destination: nil, animated: true)
        XCTAssertTrue(zoom.isTransitioning)
        let deadline = Date(timeIntervalSinceNow: 2)
        while zoom.isTransitioning, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        XCTAssertFalse(zoom.isTransitioning)
        XCTAssertEqual(zoom.zoomedInHost?.isHidden, true)
        XCTAssertEqual(zoom.zoomedOutHost?.layer?.opacity, 1)
        XCTAssertTrue(CATransform3DIsIdentity(zoom.zoomedOutHost?.layer?.transform ?? CATransform3DIdentity))
    }
}
