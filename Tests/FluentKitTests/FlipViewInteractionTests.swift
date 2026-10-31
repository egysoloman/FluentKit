import XCTest
@testable import FluentKit

private final class FlipWheelParent: NSView {
    var forwarded = 0
    override func scrollWheel(with event: NSEvent) { forwarded += 1 }
}

final class FlipViewInteractionTests: XCTestCase {
    private func descendant(_ id: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        return view.subviews.lazy.compactMap { self.descendant(id, in: $0) }.first
    }
    private func pointer() throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil))
    }
    private func key(_ code: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }
    private func wheel(_ delta: Int32, time: Double, horizontal: Bool = false, control: Bool = false) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: horizontal ? 0 : delta, wheel2: horizontal ? delta : 0, wheel3: 0))
        event.timestamp = UInt64(time * 1_000_000_000)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if control { event.flags = .maskControl }
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    @MainActor
    func testSourceButtonGeometryVisibilityAndHoverTimeout() throws {
        _ = NSApplication.shared
        let native = FluentFlipView([0, 1, 2]) { FluentText(String($0)) }._makeView(in: .init(reduceMotion: true))
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        native.layoutSubtreeIfNeeded()
        let previous = try XCTUnwrap(descendant("FluentKit.FlipView.Previous", in: native) as? NSButton)
        let next = try XCTUnwrap(descendant("FluentKit.FlipView.Next", in: native) as? NSButton)
        XCTAssertEqual(previous.frame, NSRect(x: 1, y: 71, width: 16, height: 38))
        XCTAssertEqual(next.frame, NSRect(x: 303, y: 71, width: 16, height: 38))
        XCTAssertTrue(previous.isHidden)
        XCTAssertTrue(next.isHidden, "WinUI initializes navigation buttons hidden")
        native.mouseEntered(with: try pointer())
        XCTAssertTrue(previous.isHidden, "There is no previous page")
        XCTAssertFalse(next.isHidden)
        XCTAssertFalse(next.acceptsFirstResponder, "Source buttons are not tab stops")
        next.mouseEntered(with: try pointer())
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 3.08))
        XCTAssertFalse(next.isHidden, "Hovering a navigation button keeps it visible")
        next.mouseExited(with: try pointer())
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 3.08))
        XCTAssertTrue(next.isHidden, "Hide after three seconds without pointer activity")
        native.mouseMoved(with: try pointer())
        XCTAssertFalse(next.isHidden)
        next.performClick(nil)
        next.performClick(nil)
        XCTAssertTrue(next.isHidden, "The last page has no next button")
        XCTAssertFalse(previous.isHidden)
    }

    @MainActor
    func testWheelBurstDirectionChangeIdleAndBoundaryChaining() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: 0)
        let native = FluentFlipView([0, 1, 2], selection: state.projectedValue) { FluentText(String($0)) }
            ._makeView(in: .init(reduceMotion: true))
        let parent = FlipWheelParent()
        parent.addSubview(native)
        native.scrollWheel(with: try wheel(-10, time: 10))
        XCTAssertEqual(state.wrappedValue, 1)
        // Every delta, including suppressed ones, restarts the source's 200 ms quiet period.
        for time in [10.1, 10.25, 10.4] { native.scrollWheel(with: try wheel(-10, time: time)) }
        XCTAssertEqual(state.wrappedValue, 1)
        XCTAssertEqual(parent.forwarded, 0)
        native.scrollWheel(with: try wheel(10, time: 10.41))
        XCTAssertEqual(state.wrappedValue, 0, "Direction reversal is immediately eligible")
        native.scrollWheel(with: try wheel(10, time: 10.8))
        XCTAssertEqual(parent.forwarded, 1, "An eligible wheel at the boundary chains to the parent")
        native.scrollWheel(with: try wheel(-10, time: 11))
        native.scrollWheel(with: try wheel(-10, time: 11.3))
        XCTAssertEqual(state.wrappedValue, 2)
        native.scrollWheel(with: try wheel(10, time: 11.4, control: true))
        XCTAssertEqual(state.wrappedValue, 2)
        XCTAssertEqual(parent.forwarded, 2, "Control+wheel remains available to the parent")
    }

    @MainActor
    func testHorizontalWheelMirrorsInRTLButVerticalWheelRemainsLogical() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: 1)
        let native = FluentFlipView([0, 1, 2], selection: state.projectedValue) { FluentText(String($0)) }
            ._makeView(in: .init(reduceMotion: true))
        native.userInterfaceLayoutDirection = .rightToLeft
        native.scrollWheel(with: try wheel(12, time: 10, horizontal: true))
        XCTAssertEqual(state.wrappedValue, 2)
        native.scrollWheel(with: try wheel(12, time: 11))
        XCTAssertEqual(state.wrappedValue, 1)
    }

    @MainActor
    func testDisabledCompositeRejectsInputAndRestoresCurrentBoundaryState() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: 1)
        func content() -> some FluentView {
            FluentFlipView([0, 1, 2], selection: state.projectedValue) { FluentText(String($0)) }
        }
        let context = FluentRenderContext(reduceMotion: true)
        let wrapper = content().disabled()._makeView(in: context)
        let native = try XCTUnwrap(descendant("FluentKit.FlipView", in: wrapper))
        let previous = try XCTUnwrap(descendant("FluentKit.FlipView.Previous", in: native) as? NSButton)
        let next = try XCTUnwrap(descendant("FluentKit.FlipView.Next", in: native) as? NSButton)
        XCTAssertFalse(native.acceptsFirstResponder)
        native.keyDown(with: try key(124))
        native.scrollWheel(with: try wheel(-10, time: 10))
        XCTAssertEqual(state.wrappedValue, 1)
        state.wrappedValue = 2
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(native.accessibilityValue() as? String, "3 of 3", "Disabled controls still follow the model")
        XCTAssertFalse(previous.isEnabled)
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(content().disabled(false)._updateView(wrapper, in: context))
        native.mouseEntered(with: try pointer())
        XCTAssertTrue(previous.isEnabled)
        XCTAssertFalse(previous.isHidden)
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(next.isHidden)
    }

    @MainActor
    func testContentRebuiltWhileDisabledRestoresNewControlsAndPreservesIntrinsicDisabledState() throws {
        _ = NSApplication.shared
        var items = [0, 1, 2]
        func content() -> some FluentView {
            FluentFlipView(items) { FluentButtonView("Page \($0)").disabled($0 == 1) }
        }
        func pageButtons(_ root: NSView) -> [NSButton] {
            let current = (root as? NSButton).map { [$0] } ?? []
            return current + root.subviews.flatMap(pageButtons)
        }
        let context = FluentRenderContext(reduceMotion: true)
        let wrapper = content().disabled()._makeView(in: context)
        items = [0, 1] // Rebuild both page containers while the whole control is disabled.
        XCTAssertTrue(content().disabled()._updateView(wrapper, in: context))
        let pages = pageButtons(wrapper).filter { $0.title.hasPrefix("Page ") }
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(content().disabled(false)._updateView(wrapper, in: context))
        XCTAssertTrue(try XCTUnwrap(pages.first { $0.title == "Page 0" }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(pages.first { $0.title == "Page 1" }).isEnabled)
    }

    @MainActor
    func testCollapsedGeometryAndAccessibilityPaging() throws {
        _ = NSApplication.shared
        let native = FluentFlipView([0, 1, 2]) { FluentText(String($0)) }._makeView(in: .init(reduceMotion: true))
        for size in [NSSize.zero, NSSize(width: 0.5, height: 0.5), NSSize(width: 2, height: 2),
                     NSSize(width: 10, height: 18), NSSize(width: 320, height: 180)] {
            native.frame.size = size
            native.layoutSubtreeIfNeeded()
            for id in ["FluentKit.FlipView.Previous", "FluentKit.FlipView.Next"] {
                let frame = try XCTUnwrap(descendant(id, in: native)).frame
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertGreaterThanOrEqual(frame.minY, 0)
                XCTAssertGreaterThanOrEqual(frame.width, 0)
                XCTAssertGreaterThanOrEqual(frame.height, 0)
                XCTAssertLessThanOrEqual(frame.maxX, size.width)
                XCTAssertLessThanOrEqual(frame.maxY, size.height)
            }
        }
        XCTAssertFalse(native.accessibilityPerformDecrement())
        XCTAssertTrue(native.accessibilityPerformIncrement())
        XCTAssertTrue(native.accessibilityPerformIncrement())
        XCTAssertFalse(native.accessibilityPerformIncrement())
        XCTAssertEqual(native.accessibilityValue() as? String, "3 of 3")
        XCTAssertTrue(native.accessibilityPerformDecrement())
        XCTAssertEqual(native.accessibilityValue() as? String, "2 of 3")
    }

    @MainActor
    func testKeyboardFocusRevealsButtonsAndAccessibilityExcludesInactivePages() throws {
        _ = NSApplication.shared
        let native = FluentFlipView([0, 1, 2]) { FluentText(String($0)) }._makeView(in: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = native
        native.layoutSubtreeIfNeeded()
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        XCTAssertTrue(window.makeFirstResponder(native))
        let next = try XCTUnwrap(descendant("FluentKit.FlipView.Next", in: native))
        XCTAssertFalse(next.isHidden)
        let focus = native.layer?.sublayers?.first { $0.name == "FluentKit.FlipView.Focus" }
        XCTAssertEqual(focus?.opacity, 1)
        let container = try XCTUnwrap(descendant("FluentKit.FlipView.Content", in: native))
        let children = native.accessibilityChildren() as? [NSView] ?? []
        XCTAssertTrue(children.contains(container.subviews[0]))
        XCTAssertFalse(children.contains(container.subviews[1]))
        XCTAssertEqual(container.subviews.count, 2, "Only the current page and its neighbor are realized at the first page")
        native.keyDown(with: try key(119))
        XCTAssertEqual(native.accessibilityValue() as? String, "3 of 3")
        XCTAssertTrue(next.isHidden)
        let previous = try XCTUnwrap(descendant("FluentKit.FlipView.Previous", in: native) as? NSButton)
        window.makeKeyAndOrderFront(nil)
        let point = previous.convert(NSPoint(x: previous.bounds.midX, y: previous.bounds.midY), to: nil)
        func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }
        previous.mouseEntered(with: try pointer())
        let hoverColor = previous.layer?.backgroundColor
        NSApp.postEvent(try mouse(.leftMouseUp), atStart: true)
        previous.mouseDown(with: try mouse(.leftMouseDown))
        XCTAssertEqual(focus?.opacity, 0, "Pointer activation clears the keyboard focus visual even if first responder stays unchanged")
        XCTAssertEqual(native.accessibilityValue() as? String, "2 of 3")
        XCTAssertEqual(previous.layer?.backgroundColor, hoverColor, "NSButton's tracking loop must leave the pressed visual state")
        window.makeFirstResponder(nil)
        XCTAssertEqual(focus?.opacity, 0)
        window.close()
    }
}
