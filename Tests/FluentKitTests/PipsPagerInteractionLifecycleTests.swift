import XCTest
@testable import FluentKit

@MainActor
final class PipsPagerInteractionLifecycleTests: XCTestCase {
    private func mount(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView?.addSubview(view)
        view.frame = NSRect(x: 40, y: 80, width: view is NSButton ? 24 : 160, height: 24)
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func mouse(_ type: NSEvent.EventType, _ view: NSView, inside: Bool = true) -> NSEvent {
        NSEvent.mouseEvent(with: type,
            location: view.convert(inside ? NSPoint(x: view.bounds.midX, y: view.bounds.midY) : NSPoint(x: -20, y: -20), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
            context: nil, eventNumber: 801, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    private func key(_ type: NSEvent.EventType, _ window: NSWindow, code: UInt16 = 49, repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: code == 49 ? " " : "\r",
            charactersIgnoringModifiers: code == 49 ? " " : "\r", isARepeat: repeated, keyCode: code)!
    }

    private func trackedPress(_ button: NSButton, body: @escaping @MainActor () -> Void) {
        while let queued = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
            if queued.eventNumber != 801 { NSApp.postEvent(queued, atStart: true); break }
        }
        let release = mouse(.leftMouseUp, button)
        var sampled = false
        let sample: @MainActor @Sendable () -> Void = {
            sampled = true
            body()
            NSApp.postEvent(release, atStart: false)
        }
        let timer = Timer(timeInterval: 0.02, repeats: false) { _ in
            MainActor.assumeIsolated { sample() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        button.mouseDown(with: mouse(.leftMouseDown, button))
        timer.invalidate()
        XCTAssertTrue(sampled, "The native tracking loop must be active when sampling a held press")
    }

    private func pipGlyph(_ button: FluentPipsPagerPipButton) throws -> CAShapeLayer {
        try XCTUnwrap(button.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
    }

    func testNavigationPressScalesOnlyItsIconContainer() throws {
        let button = FluentPipsPagerNavigationButton()
        button.reduceMotion = true
        let window = mount(button)
        defer { window.close() }
        trackedPress(button) {
            XCTAssertEqual(button.layer?.transform.m11, 1)
            let icon = button.layer?.sublayers?.first { $0.name == "FluentKit.PipsPager.NavigationIcon" }
            XCTAssertEqual(icon?.transform.m11, 0.875)
            XCTAssertEqual(button.bounds.width, 24)
        }
        XCTAssertEqual(button.layer?.transform.m11, 1)
    }

    func testPipPressUsesFourPointGlyphAndRestoresSelectionSize() throws {
        for selected in [false, true] {
            let button = FluentPipsPagerPipButton(index: 0)
            button.reduceMotion = true
            button.isSelectedPip = selected
            let window = mount(button)
            defer { window.close() }
            let glyph = try pipGlyph(button)
            trackedPress(button) {
                XCTAssertEqual(glyph.path?.boundingBox.width, 4)
                XCTAssertEqual(button.layer?.transform.m11, 1)
            }
            button.mouseExited(with: mouse(.mouseMoved, button, inside: false))
            XCTAssertEqual(glyph.path?.boundingBox.width, selected ? 6 : 4)
        }
    }

    func testHiddenAndInactivePipsClearHoverWithoutLosingSelection() throws {
        for selected in [false, true] {
            for hide in [false, true] {
                let button = FluentPipsPagerPipButton(index: 0)
                button.reduceMotion = true
                button.isSelectedPip = selected
                let window = mount(button)
                defer { window.close() }
                let glyph = try pipGlyph(button)
                let normalColor = glyph.fillColor
                button.mouseEntered(with: mouse(.mouseMoved, button))
                if hide { window.contentView?.isHidden = true; window.contentView?.isHidden = false }
                else { NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window) }
                button.needsLayout = true; button.layoutSubtreeIfNeeded()
                XCTAssertEqual(glyph.path?.boundingBox.width, selected ? 6 : 4)
                XCTAssertEqual(glyph.fillColor, normalColor)
                XCTAssertEqual(button.isSelectedPip, selected)
            }
        }
    }

    func testPagerOwnsOnlyOneHoveredPipWhenExitIsMissing() throws {
        let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2)
        pager.reduceMotion = true
        let window = mount(pager)
        defer { window.close() }
        let first = try XCTUnwrap(pager.realizedPipButtons[0])
        let second = try XCTUnwrap(pager.realizedPipButtons[1])
        first.mouseEntered(with: mouse(.mouseMoved, first))
        second.mouseEntered(with: mouse(.mouseMoved, second))
        XCTAssertEqual(try pipGlyph(first).path?.boundingBox.width, 4)
        XCTAssertEqual(try pipGlyph(second).path?.boundingBox.width, 6)
        XCTAssertEqual(pager.selectedPageIndex, 2)
    }

    func testKeyboardActivationWaitsForReleaseAndIgnoresRepeats() {
        for code: UInt16 in [49, 36] {
            let button = FluentPipsPagerNavigationButton()
            button.reduceMotion = true
            let window = mount(button)
            defer { window.close() }
            window.makeFirstResponder(button)
            var count = 0
            button.onInvoke = { count += 1 }
            button.keyDown(with: key(.keyDown, window, code: code))
            XCTAssertEqual(count, 0)
            button.keyDown(with: key(.keyDown, window, code: code, repeated: true))
            XCTAssertEqual(count, 0)
            button.keyUp(with: key(.keyUp, window, code: code))
            XCTAssertEqual(count, 1)
            button.keyUp(with: key(.keyUp, window, code: code))
            XCTAssertEqual(count, 1)
        }
    }

    func testKeyboardFocusLossCancelsPendingActivation() {
        let button = FluentPipsPagerPipButton(index: 0)
        let window = mount(button)
        defer { window.close() }
        var count = 0
        button.onInvoke = { _ in count += 1 }
        window.makeFirstResponder(button)
        button.keyDown(with: key(.keyDown, window))
        window.makeFirstResponder(nil)
        button.keyUp(with: key(.keyUp, window))
        XCTAssertEqual(count, 0)
    }

    func testNativeCapturedReleaseCannotInvokeAfterLifecycleCancellation() {
        for reason in ["hide", "disable", "resign", "reparent", "escape", "orderOut", "deactivate"] {
            let button = FluentPipsPagerNavigationButton()
            button.reduceMotion = false
            let window = mount(button)
            defer { window.close() }
            var count = 0
            button.onInvoke = { count += 1 }
            trackedPress(button) {
                switch reason {
                case "hide": window.contentView?.isHidden = true; window.contentView?.isHidden = false
                case "disable": button.isEnabled = false; button.isEnabled = true
                case "resign": NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
                case "orderOut": window.orderOut(nil); window.orderFront(nil)
                case "deactivate": NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
                case "reparent":
                    button.removeFromSuperview()
                    window.contentView?.addSubview(button)
                default: button.cancelOperation(nil)
                }
            }
            XCTAssertEqual(count, 0, reason)
            XCTAssertFalse(button.pointerOver, reason)
            XCTAssertFalse(button.pressed, reason)
            let icon = button.layer?.sublayers?.first { $0.name == "FluentKit.PipsPager.NavigationIcon" }
            XCTAssertEqual(icon?.transform.m11, 1, reason)
            XCTAssertNil(icon?.animationKeys(), reason)
        }
    }

    func testNativeReleaseInvokesOnceAndSelectedPipSurvivesRebuild() {
        let pager = FluentPipsPager(numberOfPages: 40, selectedPageIndex: 20,
            previousButtonVisibility: .visible, nextButtonVisibility: .visible)
        pager.reduceMotion = true
        let window = mount(pager)
        defer { window.close() }
        var count = 0
        pager.onSelectedIndexChanged = { _, _ in count += 1 }
        trackedPress(pager.nextButton) { XCTAssertEqual(pager.selectedPageIndex, 20) }
        XCTAssertEqual(pager.selectedPageIndex, 21)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(pager.realizedPipButtons[21]?.isSelectedPip == true)
    }

    func testPointerOnlyNavigationClearsOnHideAndWindowResignation() {
        let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2,
            previousButtonVisibility: .visibleOnPointerOver, nextButtonVisibility: .visibleOnPointerOver)
        let window = mount(pager)
        defer { window.close() }
        for hide in [true, false] {
            pager.mouseEntered(with: mouse(.mouseMoved, pager))
            XCTAssertEqual(pager.nextButton.alphaValue, 1)
            if hide { window.contentView?.isHidden = true; window.contentView?.isHidden = false }
            else { NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window) }
            XCTAssertEqual(pager.nextButton.alphaValue, 0)
            XCTAssertEqual(pager.selectedPageIndex, 2)
        }
    }

    func testIconPressTimelineSurvivesDrawingLayoutAndBackingRefresh() throws {
        let button = FluentPipsPagerNavigationButton()
        button.reduceMotion = false
        let window = mount(button)
        defer { window.close() }
        window.makeFirstResponder(button)
        button.keyDown(with: key(.keyDown, window))
        let icon = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.PipsPager.NavigationIcon" })
        let animation = try XCTUnwrap(icon.animation(forKey: "fluent.pips.scale"))
        button.display()
        button.setFrameSize(NSSize(width: 28, height: 28))
        button.needsLayout = true; button.layoutSubtreeIfNeeded()
        button.viewDidChangeBackingProperties()
        XCTAssertEqual(icon.animation(forKey: "fluent.pips.scale")?.beginTime, animation.beginTime)
        XCTAssertEqual(button.layer?.transform.m11, 1)
        button.reduceMotion = true
        XCTAssertNil(icon.animation(forKey: "fluent.pips.scale"))
        XCTAssertEqual(icon.transform.m11, 0.875)
        button.reduceMotion = false
        XCTAssertNil(icon.animation(forKey: "fluent.pips.scale"))
        button.keyUp(with: key(.keyUp, window))
        XCTAssertEqual(icon.transform.m11, 1)
        XCTAssertNotNil(icon.animation(forKey: "fluent.pips.scale"))
    }

    func testPipHoverReversalPreservesSelectionAndSettlesOnCancellation() throws {
        let button = FluentPipsPagerPipButton(index: 0)
        button.reduceMotion = false
        let window = mount(button)
        defer { window.close() }
        let glyph = try pipGlyph(button)
        button.mouseEntered(with: mouse(.mouseMoved, button))
        let animation = try XCTUnwrap(glyph.animation(forKey: "fluent.pips.glyph"))
        button.needsLayout = true; button.layoutSubtreeIfNeeded()
        button.display()
        XCTAssertEqual(glyph.animation(forKey: "fluent.pips.glyph")?.beginTime, animation.beginTime)
        button.mouseExited(with: mouse(.mouseMoved, button, inside: false))
        XCTAssertEqual(glyph.path?.boundingBox.width, 4)
        button.isSelectedPip = true
        XCTAssertEqual(glyph.path?.boundingBox.width, 6)
        button.cancelInteraction()
        XCTAssertNil(glyph.animationKeys())
        XCTAssertEqual(glyph.path?.boundingBox.width, 6)
        XCTAssertTrue(button.isSelectedPip)
    }
}
