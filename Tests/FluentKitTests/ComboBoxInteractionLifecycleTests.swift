import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxInteractionLifecycleTests: XCTestCase {
    private let motionKey = "fluent.chevron.press"
    private final class BackingWindow: NSWindow {
        var simulatedScale: CGFloat?
        override var backingScaleFactor: CGFloat { simulatedScale ?? super.backingScaleFactor }
    }
    private struct Fixture {
        let window: NSWindow
        let host: NSView
        let bridge: NSComboBox
        let field: NSTextField
        let chevron: FluentChevronPrimitiveLayer
        let selection: FluentState<String?>
        let mode: FluentComboBoxMode
        var target: NSView { mode == .selection ? host : field }
        var definition: FluentComboBox<String> {
            FluentComboBox(options: ["First", "Second"], selection: selection.projectedValue, mode: mode)
        }
    }

    private func mount(_ mode: FluentComboBoxMode, rtl: Bool = false) throws -> Fixture {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "First")
        let context = FluentRenderContext(reduceMotion: false, layoutDirection: rtl ? .rightToLeft : .leftToRight)
        let host = FluentComboBox(options: ["First", "Second"], selection: selection.projectedValue, mode: mode)._mount(in: context)
        let window = BackingWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 280),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 280))
        window.contentView?.addSubview(host)
        host.frame = NSRect(x: 24, y: 180, width: 220, height: 32)
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        let bridge = try XCTUnwrap(host.subviews.compactMap { $0 as? NSComboBox }.first)
        let field = try XCTUnwrap(host.subviews.first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
        let chevron = try XCTUnwrap(host.layer?.sublayers?.first { $0.name == "FluentKit.ComboBox.Chevron" } as? FluentChevronPrimitiveLayer)
        return Fixture(window: window, host: host, bridge: bridge, field: field, chevron: chevron, selection: selection, mode: mode)
    }

    private func mouse(_ type: NSEvent.EventType, _ fixture: Fixture, outsideY: Bool = false) throws -> NSEvent {
        let view = fixture.target
        let x: CGFloat = view.userInterfaceLayoutDirection == .rightToLeft ? 15 : view.bounds.maxX - 15
        let point = view.convert(NSPoint(x: x, y: outsideY ? -12 : view.bounds.midY), to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func drain() {
        var done = false
        DispatchQueue.main.async { done = true }
        waitForUI(done)
    }

    private func hasPopup(_ fixture: Fixture) -> Bool { fixture.window.childWindows?.contains { $0.isVisible } == true }

    func testBothModesPreservePressAcrossLayoutDrawingThemeAndContentUpdates() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try mount(mode)
            defer { f.window.close() }
            f.target.mouseDown(with: try mouse(.leftMouseDown, f))
            let animation = try XCTUnwrap(f.chevron.animation(forKey: motionKey))
            for _ in 0..<3 {
                f.host.needsLayout = true
                f.host.layoutSubtreeIfNeeded()
                f.host.needsDisplay = true
                f.host.displayIfNeeded()
                XCTAssertEqual(f.chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
            }
            f.host.setFrameSize(NSSize(width: 260, height: 36))
            f.host.viewDidChangeBackingProperties()
            XCTAssertEqual(f.chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
            XCTAssertTrue(f.definition._updateView(f.host, in: .init(theme: .custom(colorScheme: .light), reduceMotion: false)))
            XCTAssertEqual(f.chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
            XCTAssertEqual(f.chevron.transform.m42, 1.875, accuracy: 0.001)
            XCTAssertEqual(f.selection.wrappedValue, "First")
        }
    }

    func testMotionPolicySettlesAndDoesNotReplayThePress() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try mount(mode)
            defer { f.window.close() }
            f.target.mouseDown(with: try mouse(.leftMouseDown, f))
            XCTAssertNotNil(f.chevron.animation(forKey: motionKey))
            XCTAssertTrue(f.definition._updateView(f.host, in: .init(reduceMotion: true)))
            XCTAssertNil(f.chevron.animation(forKey: motionKey))
            XCTAssertEqual(f.chevron.transform.m42, 1.875, accuracy: 0.001)
            XCTAssertTrue(f.definition._updateView(f.host, in: .init(reduceMotion: false)))
            XCTAssertNil(f.chevron.animation(forKey: motionKey))
            f.target.mouseUp(with: try mouse(.leftMouseUp, f, outsideY: true))
            f.target.mouseDown(with: try mouse(.leftMouseDown, f))
            XCTAssertNotNil(f.chevron.animation(forKey: motionKey))
        }
    }

    func testBackingScaleUpdatesGeometryWithoutCancelingPress() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try mount(mode)
            defer { f.window.close() }
            f.target.mouseDown(with: try mouse(.leftMouseDown, f))
            let animation = try XCTUnwrap(f.chevron.animation(forKey: motionKey))
            let window = try XCTUnwrap(f.window as? BackingWindow)
            for scale: CGFloat in [1, 2] {
                window.simulatedScale = scale
                f.host.viewDidChangeBackingProperties()
                XCTAssertEqual(f.chevron.contentsScale, scale)
                XCTAssertEqual(f.chevron.animation(forKey: motionKey)?.beginTime, animation.beginTime)
            }
        }
    }

    func testDetachAndHideCancelCapturedPressInBothModes() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            for hide in [false, true] {
                let f = try mount(mode)
                defer { f.window.close() }
                f.target.mouseDown(with: try mouse(.leftMouseDown, f))
                if hide { f.host.isHidden = true } else { f.host.removeFromSuperview() }
                XCTAssertNil(f.chevron.animation(forKey: motionKey))
                XCTAssertEqual(f.chevron.transform.m42, 0, accuracy: 0.001)
                if hide { f.host.isHidden = false } else { f.window.contentView?.addSubview(f.host) }
                f.target.mouseUp(with: try mouse(.leftMouseUp, f))
                drain()
                XCTAssertFalse(hasPopup(f), "Release after cancellation opened \(mode)")
            }
        }
    }

    func testEditableDeferredOpenCannotSurviveLifecycleChanges() throws {
        for interruption in 0..<5 {
            let f = try mount(.editable)
            defer { f.window.close() }
            f.field.mouseDown(with: try mouse(.leftMouseDown, f))
            f.field.mouseUp(with: try mouse(.leftMouseUp, f))
            switch interruption {
            case 0: f.host.removeFromSuperview(); f.window.contentView?.addSubview(f.host)
            case 1: f.host.isHidden = true; f.host.isHidden = false
            case 2: f.bridge.isEnabled = false; f.field.isEnabled = false; f.bridge.isEnabled = true; f.field.isEnabled = true
            case 3:
                let selection = FluentComboBox(options: ["First", "Second"], selection: f.selection.projectedValue)
                XCTAssertTrue(selection._updateView(f.host, in: .init(reduceMotion: true)))
                XCTAssertTrue(f.definition._updateView(f.host, in: .init(reduceMotion: true)))
            default: f.window.close(); f.window.orderFront(nil)
            }
            drain()
            XCTAssertFalse(hasPopup(f), "Queued editable popup survived interruption \(interruption)")
        }
    }

    func testUncapturedDragCannotArmSelectionComboBox() throws {
        let f = try mount(.selection)
        defer { f.window.close() }
        f.host.mouseDragged(with: try mouse(.leftMouseDragged, f))
        f.host.mouseUp(with: try mouse(.leftMouseUp, f))
        drain()
        XCTAssertFalse(hasPopup(f))
        XCTAssertEqual(f.chevron.transform.m42, 0, accuracy: 0.001)
    }

    func testEditableGlyphReleaseOutsideBoundsDoesNotOpenInEitherDirection() throws {
        for rtl in [false, true] {
            let f = try mount(.editable, rtl: rtl)
            defer { f.window.close() }
            f.field.mouseDown(with: try mouse(.leftMouseDown, f))
            f.field.mouseDragged(with: try mouse(.leftMouseDragged, f, outsideY: true))
            XCTAssertEqual(f.chevron.transform.m42, 0, accuracy: 0.001)
            f.field.mouseUp(with: try mouse(.leftMouseUp, f, outsideY: true))
            drain()
            XCTAssertFalse(hasPopup(f))
        }
    }

    func testDisableClearsPressImmediatelyAndReleaseDoesNotActivateAfterReenable() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try mount(mode)
            defer { f.window.close() }
            f.target.mouseDown(with: try mouse(.leftMouseDown, f))
            f.bridge.isEnabled = false
            f.field.isEnabled = false
            XCTAssertNil(f.chevron.animation(forKey: motionKey))
            XCTAssertEqual(f.chevron.transform.m42, 0, accuracy: 0.001)
            f.bridge.isEnabled = true
            f.field.isEnabled = true
            f.target.mouseUp(with: try mouse(.leftMouseUp, f))
            drain()
            XCTAssertFalse(hasPopup(f))
        }
    }

    func testHiddenFaceplateDoesNotHitTestOrOpenThroughNativeBridge() throws {
        let f = try mount(.selection)
        defer { f.window.close() }
        f.host.isHidden = true
        XCTAssertNil(f.host.hitTest(f.host.convert(NSPoint(x: 20, y: 16), to: f.host.superview)))
        f.bridge.performClick(nil)
        drain()
        XCTAssertFalse(hasPopup(f))
    }

    func testOrdinaryPointerStatesKeepComboBoxSecondaryGlyphColor() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            for dark in [false, true] {
                let f = try mount(mode)
                defer { f.window.close() }
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light)
                XCTAssertTrue(f.definition._updateView(f.host, in: .init(theme: theme, reduceMotion: true)))
                let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: f.target.convert(NSPoint(x: 205, y: 16), to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: f.window.windowNumber, context: nil,
                    eventNumber: 0, trackingNumber: 0, userData: nil))
                f.target.mouseEntered(with: event)
                XCTAssertEqual(f.chevron.strokeColor, theme.textSecondary.cgColor)
                f.target.mouseDown(with: try mouse(.leftMouseDown, f))
                XCTAssertEqual(f.chevron.strokeColor, theme.textSecondary.cgColor)
            }
        }
    }

    func testValidReleaseStillOpensAndCommitsSelectionInBothModesAndDirections() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            for rtl in [false, true] {
                let f = try mount(mode, rtl: rtl)
                defer { f.window.close() }
                if mode == .editable { f.field.selectText(nil) }
                f.target.mouseDown(with: try mouse(.leftMouseDown, f))
                f.target.mouseUp(with: try mouse(.leftMouseUp, f))
                waitForUI(hasPopup(f))
                let panel = try XCTUnwrap(f.window.childWindows?.first)
                XCTAssertEqual(f.window.childWindows?.count, 1)
                for code: UInt16 in [125, 36] {
                    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                        timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "",
                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
                    panel.sendEvent(event)
                }
                XCTAssertEqual(f.selection.wrappedValue, "Second")
                waitForUI(!hasPopup(f))
                XCTAssertEqual(f.chevron.transform.m42, 0, accuracy: 0.001)
            }
        }
    }

    func testFocusLossCancelsBothCapturedAndQueuedEditablePresses() throws {
        for queued in [false, true] {
            let f = try mount(.editable)
            defer { f.window.close() }
            f.field.selectText(nil)
            XCTAssertNotNil(f.field.currentEditor())
            f.field.mouseDown(with: try mouse(.leftMouseDown, f))
            if queued { f.field.mouseUp(with: try mouse(.leftMouseUp, f)) }
            f.window.makeFirstResponder(nil)
            if !queued { f.field.mouseUp(with: try mouse(.leftMouseUp, f)) }
            drain()
            XCTAssertFalse(hasPopup(f))
            XCTAssertEqual(f.chevron.transform.m42, 0, accuracy: 0.001)
            XCTAssertEqual(f.selection.wrappedValue, "First")
        }
    }
}
