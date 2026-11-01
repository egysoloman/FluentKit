import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxLivePopupTests: XCTestCase {
    private final class ClockWindow: NSWindow {
        var pausesPopupClock = false
        var initialPopupReduceMotion: Bool?
        override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
            super.addChildWindow(childWin, ordered: place)
            if let initialPopupReduceMotion, let host = childWin.contentView as? FluentPopupTransitionHost {
                host.animationCoordinator.reduceMotion = initialPopupReduceMotion
            }
            guard pausesPopupClock, let layer = childWin.contentView?.layer else { return }
            // Pause before the popup installs its entrance, so a slow native presentation
            // cannot finish the animation before the cancellation assertion observes it.
            let time = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = time
        }
    }
    private struct Fixture {
        let window: NSWindow
        let hosting: FluentViewHost<FluentComboBox<Int>>
        let control: NSView
        let bridge: NSComboBox
        let selection: FluentState<Int?>
        let mode: FluentComboBoxMode
        func definition(long: Bool = false) -> FluentComboBox<Int> {
            FluentComboBox(options: Array(0..<40), selection: selection.projectedValue, mode: mode,
                title: { long ? "Updated option \($0) with a substantially longer title" : "Option \($0)" })
        }
    }

    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    private func mount(_ mode: FluentComboBoxMode = .selection, reduced: Bool = true, pausePopupClock: Bool = false) throws -> Fixture {
        _ = NSApplication.shared
        let selection = FluentState<Int?>(wrappedValue: 20)
        let definition = FluentComboBox(options: Array(0..<40), selection: selection.projectedValue, mode: mode,
            title: { "Option \($0)" })
        let hosting = FluentViewHost(definition, context: .init(reduceMotion: reduced, layoutDirection: .leftToRight))
        let window = ClockWindow(contentRect: NSRect(x: 150, y: 180, width: 700, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.pausesPopupClock = pausePopupClock
        window.contentView?.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(x: 60, y: 220, width: 180, height: 32)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(all(hosting).first { $0.identifier?.rawValue == "FluentKit.ComboBox.Host" })
        let bridge = try XCTUnwrap(all(control).compactMap { $0 as? NSComboBox }.first)
        return Fixture(window: window, hosting: hosting, control: control, bridge: bridge, selection: selection, mode: mode)
    }

    private func open(_ f: Fixture) throws -> (NSWindow, FluentPopupTransitionHost, NSScrollView, [NSView]) {
        f.bridge.performClick(nil)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        let scroll = try XCTUnwrap(all(host).compactMap { $0 as? NSScrollView }.first)
        return (panel, host, scroll, try XCTUnwrap(scroll.documentView).subviews)
    }
    private func mouse(_ type: NSEvent.EventType, _ view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
            context: nil, eventNumber: 902, clickCount: 1, pressure: 1)!
    }
    private func key(_ code: UInt16, panel: NSWindow) {
        panel.firstResponder?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code)!)
    }

    func testLiveTitlesRemeasureRetainedRowsAndPreserveKeyboardPosition() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try mount(mode)
            defer { f.window.close() }
            let (panel, host, scroll, rows) = try open(f)
            key(119, panel: panel)
            let responder = panel.firstResponder
            let oldWidth = panel.frame.width
            f.hosting.update(f.definition(long: true), context: .init(reduceMotion: true, layoutDirection: .leftToRight))
            f.hosting.layoutSubtreeIfNeeded()
            XCTAssertTrue(panel === f.window.childWindows?.first)
            XCTAssertTrue(host === panel.contentView)
            XCTAssertTrue(responder === panel.firstResponder)
            XCTAssertTrue(zip(rows, scroll.documentView!.subviews).allSatisfy { $0 === $1 })
            XCTAssertEqual(rows[39].accessibilityTitle(), "Updated option 39 with a substantially longer title")
            XCTAssertGreaterThan(panel.frame.width, oldWidth)
            XCTAssertTrue(scroll.documentVisibleRect.contains(rows[39].frame))
            XCTAssertEqual(f.selection.wrappedValue, 20, "The default trigger keeps navigation as a preview until Enter.")
            key(36, panel: panel)
            XCTAssertEqual(f.selection.wrappedValue, 39)
            XCTAssertFalse(panel.isVisible)
        }
    }

    func testOpenDirectionChangeMirrorsPopupAlignmentAndSelectedPill() throws {
        let f = try mount()
        defer { f.window.close() }
        f.hosting.update(f.definition(long: true), context: .init(reduceMotion: true, layoutDirection: .leftToRight))
        let (panel, _, _, rows) = try open(f)
        let pill = try XCTUnwrap(rows[20].layer?.sublayers?.first { $0.name == "FluentKit.ComboBoxItem.SelectionPill" })
        XCTAssertLessThan(pill.frame.midX, rows[20].bounds.midX)
        f.hosting.update(f.definition(long: true), context: .init(reduceMotion: true, layoutDirection: .rightToLeft))
        f.hosting.layoutSubtreeIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(f.control.userInterfaceLayoutDirection, .rightToLeft)
        XCTAssertGreaterThan(pill.frame.midX, rows[20].bounds.midX)
        let anchor = f.window.convertToScreen(f.control.convert(f.control.bounds, to: nil))
        let work = FluentScreenPlacement.visibleFrame(at: FluentScreenPlacement.topLeading(of: anchor, rightToLeft: true), fallback: f.window)
        let expectedX = min(max(anchor.maxX - panel.frame.width, work.minX), work.maxX - panel.frame.width)
        XCTAssertEqual(panel.frame.minX, expectedX, accuracy: 0.5)
        XCTAssertEqual(f.selection.wrappedValue, 20)
    }

    func testLiveReduceMotionSettlesOpeningAndDoesNotReplay() throws {
        let f = try mount(reduced: false, pausePopupClock: true)
        defer { f.window.close() }
        try XCTUnwrap(f.window as? ClockWindow).initialPopupReduceMotion = true
        let (panel, host, _, _) = try open(f)
        XCTAssertFalse((host.revealMaskLayer.animationKeys() ?? []).isEmpty)
        f.hosting.update(f.definition(), context: .init(reduceMotion: true))
        XCTAssertNil(host.revealMaskLayer.animationKeys())
        XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds)
        f.hosting.update(f.definition(), context: .init(reduceMotion: false))
        XCTAssertNil(host.revealMaskLayer.animationKeys())
        XCTAssertTrue(panel.isVisible)
    }

    func testRowReleaseWithoutPressOrAfterResignationDoesNotCommit() throws {
        for cancelled in [false, true] {
            let f = try mount()
            defer { f.window.close() }
            let (panel, _, _, rows) = try open(f)
            let row = rows[21]
            if cancelled {
                row.mouseDown(with: mouse(.leftMouseDown, row))
                NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
            }
            row.mouseUp(with: mouse(.leftMouseUp, row))
            XCTAssertEqual(f.selection.wrappedValue, 20)
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testFaceplateDrawingAndNoOpUpdatePreserveBackgroundClock() throws {
        let f = try mount(reduced: false)
        defer { f.window.close() }
        f.control.mouseEntered(with: mouse(.mouseMoved, f.control))
        let layer = try XCTUnwrap(f.control.layer)
        let animation = try XCTUnwrap(layer.animation(forKey: "fluent.buttonChrome.background"))
        f.control.display()
        XCTAssertEqual(layer.animation(forKey: "fluent.buttonChrome.background")?.beginTime, animation.beginTime)
        f.hosting.update(f.definition(), context: .init(reduceMotion: false))
        f.hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(layer.animation(forKey: "fluent.buttonChrome.background")?.beginTime, animation.beginTime)
    }

    func testFreshRowClickCommitsOnceAndRetiredRowsCannotActivate() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try mount(mode)
            defer { f.window.close() }
            let (panel, _, scroll, rows) = try open(f)
            let row = rows[21]
            scroll.documentView?.scrollToVisible(row.frame)
            row.mouseDown(with: mouse(.leftMouseDown, row))
            XCTAssertEqual(f.selection.wrappedValue, 20)
            row.mouseUp(with: mouse(.leftMouseUp, row))
            XCTAssertEqual(f.selection.wrappedValue, 21)
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(rows[20].accessibilityPerformPress())
            rows[20].mouseDown(with: mouse(.leftMouseDown, rows[20]))
            rows[20].mouseUp(with: mouse(.leftMouseUp, rows[20]))
            XCTAssertEqual(f.selection.wrappedValue, 21)
        }
    }

    func testLiveMotionPolicyAppliesToSubsequentRowPresses() throws {
        let f = try mount(reduced: false)
        defer { f.window.close() }
        let (panel, _, _, rows) = try open(f)
        let row = rows[20]
        let pill = try XCTUnwrap(row.layer?.sublayers?.first { $0.name == "FluentKit.ComboBoxItem.SelectionPill" })
        f.hosting.update(f.definition(), context: .init(reduceMotion: true))
        row.mouseDown(with: mouse(.leftMouseDown, row))
        XCTAssertEqual(pill.bounds.height, 10)
        XCTAssertNil(pill.animationKeys())
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
        XCTAssertEqual(pill.bounds.height, 16)
        f.hosting.update(f.definition(), context: .init(reduceMotion: false))
        XCTAssertNil(pill.animationKeys())
        row.mouseDown(with: mouse(.leftMouseDown, row))
        XCTAssertNotNil(pill.animation(forKey: "fluent.combobox.pill.frame"))
        XCTAssertEqual(f.selection.wrappedValue, 20)
    }

    func testFaceplateMotionPolicySettlesWithoutReplayingOnEnable() throws {
        let f = try mount(reduced: false)
        defer { f.window.close() }
        f.control.mouseEntered(with: mouse(.mouseMoved, f.control))
        let layer = try XCTUnwrap(f.control.layer)
        XCTAssertNotNil(layer.animation(forKey: "fluent.buttonChrome.background"))
        f.hosting.update(f.definition(), context: .init(reduceMotion: true))
        XCTAssertNil(layer.animation(forKey: "fluent.buttonChrome.background"))
        f.hosting.update(f.definition(), context: .init(reduceMotion: false))
        XCTAssertNil(layer.animation(forKey: "fluent.buttonChrome.background"))
        f.control.mouseExited(with: mouse(.mouseMoved, f.control))
        XCTAssertNotNil(layer.animation(forKey: "fluent.buttonChrome.background"))
    }
}
