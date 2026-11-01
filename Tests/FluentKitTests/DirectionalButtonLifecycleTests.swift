import XCTest
@testable import FluentKit

@MainActor
final class DirectionalButtonLifecycleTests: XCTestCase {
    private let colorKey = "fluent.chevron.color"
    private final class BackingWindow: NSWindow {
        var scale: CGFloat = 2
        override var backingScaleFactor: CGFloat { scale }
    }

    private func mount(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = BackingWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView?.addSubview(view)
        view.frame = NSRect(x: 20, y: 80, width: 200, height: 32)
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func mouse(_ type: NSEvent.EventType, _ view: NSView, inside: Bool = true) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type,
            location: view.convert(inside ? NSPoint(x: view.bounds.midX, y: view.bounds.midY) : NSPoint(x: -20, y: -20), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func key(_ type: NSEvent.EventType, _ window: NSWindow, code: UInt16 = 49, repeated: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: code == 49 ? " " : "\r",
            charactersIgnoringModifiers: code == 49 ? " " : "\r", isARepeat: repeated, keyCode: code))
    }

    private func glyph(_ view: NSView) throws -> FluentChevronPrimitiveLayer {
        try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? FluentChevronPrimitiveLayer }.first)
    }

    private func assertDirection(_ glyph: FluentChevronPrimitiveLayer, _ direction: FluentChevronDirection,
                                 flipped: Bool, file: StaticString = #filePath, line: UInt = #line) {
        var points: [CGPoint] = []
        glyph.path?.applyWithBlock { element in points.append(element.pointee.points[0]) }
        guard points.count == 3 else { return XCTFail("Expected a three-point arrow", file: file, line: line) }
        let x = points[1].x - (points[0].x + points[2].x) / 2
        let y = points[1].y - (points[0].y + points[2].y) / 2
        let t = glyph.transform
        let dx = x * t.m11 + y * t.m21
        let dy = (x * t.m12 + y * t.m22) * (flipped ? -1 : 1)
        switch direction {
        case .up: XCTAssertGreaterThan(dy, 0, file: file, line: line)
        case .down: XCTAssertLessThan(dy, 0, file: file, line: line)
        case .left: XCTAssertLessThan(dx, 0, file: file, line: line)
        case .right: XCTAssertGreaterThan(dx, 0, file: file, line: line)
        }
    }

    func testDirectionalPrimitivePreservesAllDirectionsInBothAxesWithoutPressTranslation() {
        for inverted in [false, true] {
            for direction: FluentChevronDirection in [.up, .down, .left, .right] {
                let glyph = FluentChevronPrimitiveLayer()
                glyph.update(frame: CGRect(x: 0, y: 0, width: 12, height: 12), color: .black,
                    state: .pressed, direction: direction, inverted: inverted, reduceMotion: true, animated: false)
                assertDirection(glyph, direction, flipped: !inverted)
                XCTAssertEqual(glyph.transform.m41, 0, accuracy: 0.001)
                XCTAssertEqual(glyph.transform.m42, 0, accuracy: 0.001,
                    "Directional FontIcon equivalents do not use DownSmall's pressed offset")
            }
        }
    }

    func testRepeatButtonArrowsMatchTheirNamesAndUpdateImmediately() throws {
        let button = FluentRepeatButton(systemImageName: "chevron.up")
        let window = mount(button)
        defer { window.close() }
        for (name, direction) in [("up", FluentChevronDirection.up), ("down", .down), ("left", .left), ("right", .right)] {
            button.systemImageName = "chevron." + name
            assertDirection(try glyph(button), direction, flipped: button.isFlipped)
        }
    }

    func testPipsPagerArrowsKeepHorizontalAndVerticalDirections() throws {
        let button = FluentPipsPagerNavigationButton()
        let window = mount(button)
        defer { window.close() }
        for direction: FluentChevronDirection in [.up, .down, .left, .right] {
            button.direction = direction
            assertDirection(try glyph(button), direction, flipped: button.isFlipped)
        }
    }

    func testNumberBoxInlineAndCompactArrowsPointOutward() throws {
        let number = FluentNumberBoxControl(value: 5, range: 0...10, spinButtonPlacement: .inline)
        let window = mount(number)
        defer { window.close() }
        assertDirection(try glyph(number.incrementButton), .up, flipped: number.incrementButton.isFlipped)
        assertDirection(try glyph(number.decrementButton), .down, flipped: number.decrementButton.isFlipped)
        for rtl in [false, true] {
            number.fluentLayoutDirection = rtl ? .rightToLeft : .leftToRight
            number.layoutSubtreeIfNeeded()
            if rtl { XCTAssertGreaterThan(number.incrementButton.frame.minX, number.decrementButton.frame.minX) }
            else { XCTAssertLessThan(number.incrementButton.frame.minX, number.decrementButton.frame.minX) }
            XCTAssertEqual(number.textField.frame.width, number.bounds.width - 76, accuracy: 0.001)
            XCTAssertEqual(number.incrementButton.frame.width, 32, accuracy: 0.001)
            XCTAssertEqual(abs(number.incrementButton.frame.midX - number.decrementButton.frame.midX), 36, accuracy: 0.001)
        }
        number.spinButtonPlacement = .compact
        number.layoutSubtreeIfNeeded()
        let indicator = try XCTUnwrap(number.subviews.first { $0.identifier?.rawValue == "FluentKit.NumberBox.PopupIndicator" })
        let glyphs = try XCTUnwrap(indicator.layer?.sublayers?.compactMap { $0 as? FluentChevronPrimitiveLayer })
        XCTAssertEqual(glyphs.count, 2)
        for glyph in glyphs {
            assertDirection(glyph, glyph.name?.contains("Up") == true ? .up : .down, flipped: indicator.isFlipped)
        }
        let upper = try XCTUnwrap(glyphs.first { $0.name?.contains("Up") == true })
        let lower = try XCTUnwrap(glyphs.first { $0.name?.contains("Down") == true })
        XCTAssertGreaterThan((upper.position.y - lower.position.y) * (indicator.isFlipped ? -1 : 1), 0,
                             "The up glyph must sit above the down glyph, with their tips pointing outward")
    }

    func testRepeatGlyphColorSurvivesDrawingLayoutContentAndBackingChanges() throws {
        let button = FluentRepeatButton(systemImageName: "chevron.down", delay: 10)
        button.reduceMotion = false
        let window = mount(button)
        defer { window.close() }
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        let glyph = try glyph(button)
        let animation = try XCTUnwrap(glyph.animation(forKey: colorKey))
        button.needsLayout = true; button.layoutSubtreeIfNeeded()
        button.display()
        button.title = "New title"
        button.setFrameSize(NSSize(width: 201, height: 36))
        for scale: CGFloat in [1, 2] {
            (window as? BackingWindow)?.scale = scale
            button.viewDidChangeBackingProperties()
            XCTAssertEqual(glyph.contentsScale, scale)
            XCTAssertEqual(glyph.animation(forKey: colorKey)?.beginTime, animation.beginTime)
        }
        XCTAssertEqual(glyph.transform.m42, 0, accuracy: 0.001)
    }

    func testResolvedMotionPolicySettlesThenAllowsNewColorTransition() throws {
        let button = FluentRepeatButton(systemImageName: "chevron.down", delay: 10)
        button.reduceMotion = false
        let window = mount(button)
        defer { window.close() }
        let glyph = try glyph(button)
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        XCTAssertNotNil(glyph.animation(forKey: colorKey))
        button.reduceMotion = true
        XCTAssertNil(glyph.animation(forKey: colorKey))
        button.reduceMotion = false
        XCTAssertNil(glyph.animation(forKey: colorKey))
        button.mouseUp(with: try mouse(.leftMouseUp, button, inside: false))
        XCTAssertNotNil(glyph.animation(forKey: colorKey))
    }

    func testHiddenAncestorStopsRepeatAndDoesNotResumeOnShowing() throws {
        let button = FluentRepeatButton(systemImageName: "chevron.down", delay: 0.01, interval: 0.01)
        button.allowsKeyboardFocus = false
        let window = mount(button)
        defer { window.close() }
        var count = 0
        button.onClick = { count += 1 }
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        waitForUI(count >= 2)
        window.contentView?.isHidden = true
        let stopped = count
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(count, stopped)
        window.contentView?.isHidden = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(count, stopped)
        XCTAssertNil(try glyph(button).animation(forKey: colorKey))
    }

    func testWindowResignationAndReparentStopNonFocusingRepeat() throws {
        for reparent in [false, true] {
            let button = FluentRepeatButton(systemImageName: "chevron.down", delay: 0.01, interval: 0.01)
            button.allowsKeyboardFocus = false
            let window = mount(button)
            defer { window.close() }
            var count = 0
            button.onClick = { count += 1 }
            button.mouseDown(with: try mouse(.leftMouseDown, button))
            if reparent {
                let parent = NSView(frame: window.contentView!.bounds)
                window.contentView?.addSubview(parent)
                parent.addSubview(button)
            } else {
                NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            }
            let stopped = count
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            XCTAssertEqual(count, stopped)
            XCTAssertNil(try glyph(button).animation(forKey: colorKey))
        }
    }

    func testActionCanHideItsOwnButtonWithoutSchedulingAnotherInvocation() throws {
        let button = FluentRepeatButton(delay: 0.01, interval: 0.01)
        let window = mount(button)
        defer { window.close() }
        var count = 0
        button.onClick = { count += 1; button.isHidden = true }
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(count, 1)
        button.mouseDown(with: try mouse(.leftMouseDown, button))
        button.keyDown(with: try key(.keyDown, window))
        XCTAssertEqual(count, 1, "Hidden controls reject stale pointer and key events")
    }

    func testSpaceRepeatsEnterInvokesOnceAndReleaseStops() throws {
        let button = FluentRepeatButton(delay: 0.01, interval: 0.01)
        let window = mount(button)
        defer { window.close() }
        var count = 0
        button.onClick = { count += 1 }
        window.makeFirstResponder(button)
        button.keyDown(with: try key(.keyDown, window))
        XCTAssertEqual(count, 1)
        button.keyDown(with: try key(.keyDown, window, repeated: true))
        XCTAssertEqual(count, 1)
        waitForUI(count >= 3)
        button.keyUp(with: try key(.keyUp, window))
        let stopped = count
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(count, stopped)
        button.keyDown(with: try key(.keyDown, window, code: 36))
        button.keyDown(with: try key(.keyDown, window, code: 36, repeated: true))
        XCTAssertEqual(count, stopped + 1)
    }

    func testRepeatCallbackCanRestartWithANewDelay() throws {
        let button = FluentRepeatButton(delay: 0.01, interval: 0.01)
        let window = mount(button)
        defer { window.close() }
        var count = 0
        let down = try mouse(.leftMouseDown, button)
        let up = try mouse(.leftMouseUp, button)
        var restartedAt: TimeInterval?
        var restartedRepeatElapsed: TimeInterval?
        button.onClick = {
            count += 1
            if count == 2 {
                button.mouseUp(with: up)
                button.delay = 0.2
                restartedAt = ProcessInfo.processInfo.systemUptime
                button.mouseDown(with: down)
            } else if count == 4, let restartedAt {
                restartedRepeatElapsed = ProcessInfo.processInfo.systemUptime - restartedAt
                button.mouseUp(with: up)
            }
        }
        button.mouseDown(with: down)
        waitForUI(restartedRepeatElapsed != nil)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(restartedRepeatElapsed), 0.19,
            "The old tick must not replace the restarted press's delay with the 10ms interval")
        XCTAssertEqual(count, 4)
    }

    func testPipsPagerGlyphColorKeepsItsClockAndResolvedPolicy() throws {
        let button = FluentPipsPagerNavigationButton()
        button.reduceMotion = false
        let window = mount(button)
        defer { window.close() }
        let glyph = try glyph(button)
        button.mouseEntered(with: try mouse(.mouseMoved, button))
        let animation = try XCTUnwrap(glyph.animation(forKey: colorKey))
        button.needsLayout = true; button.layoutSubtreeIfNeeded()
        XCTAssertEqual(glyph.animation(forKey: colorKey)?.beginTime, animation.beginTime)
        button.reduceMotion = true
        button.refreshAppearance(animated: false)
        XCTAssertNil(glyph.animation(forKey: colorKey))
        button.reduceMotion = false
        button.refreshAppearance(animated: false)
        XCTAssertNil(glyph.animation(forKey: colorKey))
        button.mouseExited(with: try mouse(.mouseMoved, button))
        XCTAssertNotNil(glyph.animation(forKey: colorKey))
    }

    func testNumberBoxIndicatorHonorsMotionPolicyDuringHighlightAndLayout() throws {
        let number = FluentNumberBoxControl(value: 5, range: 0...10, spinButtonPlacement: .compact)
        number.reduceMotion = false
        let window = mount(number)
        defer { window.close() }
        let indicator = try XCTUnwrap(number.subviews.first {
            $0.identifier?.rawValue == "FluentKit.NumberBox.PopupIndicator"
        } as? NSButton)
        let glyph = try glyph(indicator)
        indicator.highlight(true)
        indicator.mouseEntered(with: try mouse(.mouseMoved, indicator))
        let animation = try XCTUnwrap(glyph.animation(forKey: colorKey))
        indicator.needsLayout = true; indicator.layoutSubtreeIfNeeded()
        XCTAssertEqual(glyph.animation(forKey: colorKey)?.beginTime, animation.beginTime)
        XCTAssertEqual(glyph.transform.m42, 0, accuracy: 0.001)
        number.reduceMotion = true
        XCTAssertNil(glyph.animation(forKey: colorKey))
        number.reduceMotion = false
        XCTAssertNil(glyph.animation(forKey: colorKey))
        indicator.highlight(false)
        indicator.mouseExited(with: try mouse(.mouseMoved, indicator))
        XCTAssertNotNil(glyph.animation(forKey: colorKey))
    }

    func testPagerMotionPolicyReachesRetainedChildrenWithoutAnotherLayout() throws {
        let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2,
            previousButtonVisibility: .visible, nextButtonVisibility: .visible)
        pager.reduceMotion = false
        let window = mount(pager)
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let children = descendants(pager)
        let navigation = children.compactMap { $0 as? FluentPipsPagerNavigationButton }
        let pips = children.compactMap { $0 as? FluentPipsPagerPipButton }
        XCTAssertEqual(navigation.count, 2)
        XCTAssertFalse(pips.isEmpty)
        for reduced in [true, false] {
            pager.reduceMotion = reduced
            XCTAssertTrue(navigation.allSatisfy { $0.reduceMotion == reduced })
            XCTAssertTrue(pips.allSatisfy { $0.reduceMotion == reduced })
            XCTAssertEqual(pager.selectedPageIndex, 2)
        }
    }
}
