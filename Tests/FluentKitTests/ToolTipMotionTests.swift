import XCTest
@testable import FluentKit

@MainActor
final class ToolTipMotionTests: XCTestCase {
    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 150, y: 180, width: 500, height: 250),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        window.orderFront(nil)
        return window
    }

    private func host(_ text: String, x: CGFloat, window: NSWindow,
                      reduced: Bool = false, motion: FluentToolTipMotion = .continuous) -> FluentToolTipHost {
        let context = FluentRenderContext(theme: .custom(colorScheme: .dark, materialEffectsEnabled: false), reduceMotion: reduced)
        let host = FluentToolTipHost(contentView: NSButton(title: text, target: nil, action: nil),
            toolTipView: FluentToolTipText(text)._mount(in: context), placement: .bottom,
            isEnabled: true, accessibilityText: text, context: context, motion: motion)
        host.frame = NSRect(x: x, y: 150, width: 100, height: 32)
        window.contentView?.addSubview(host)
        window.contentView?.layoutSubtreeIfNeeded()
        return host
    }

    private func event(_ host: FluentToolTipHost, point: NSPoint = NSPoint(x: 30, y: 16)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: host.convert(point, to: nil),
            modifierFlags: [], timestamp: 1, windowNumber: try XCTUnwrap(host.window).windowNumber,
            context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
    }

    private func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    func testContinuousToolTipReusesSurfaceAndRetargetsFromIntermediateFrame() throws {
        let window = window()
        let first = host("First", x: 30, window: window)
        let second = host("A much wider second tooltip", x: 190, window: window)
        let third = host("Third", x: 350, window: window)
        defer { third.dismiss(animated: false); second.dismiss(animated: false); first.dismiss(animated: false); window.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        wait(1.1)
        let panel = try XCTUnwrap(window.childWindows?.first as? FluentToolTipPanel)
        let start = panel.frame
        first.mouseExited(with: try event(first, point: NSPoint(x: 160, y: 16)))
        second.mouseEntered(with: try event(second))
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual(panel.frame, start, "handoff must start from the existing frame")
        wait(0.08)
        let intermediate = panel.frame
        XCTAssertGreaterThan(intermediate.midX, start.midX)
        XCTAssertGreaterThan(intermediate.width, start.width)
        XCTAssertLessThan(intermediate.midX, window.convertPoint(toScreen: second.convert(NSPoint(x: 30, y: 16), to: nil)).x)
        second.mouseExited(with: try event(second, point: NSPoint(x: 160, y: 16)))
        third.mouseEntered(with: try event(third))
        XCTAssertEqual(panel.frame, intermediate, "retargeting cannot jump to the prior destination")
        wait(0.28)
        XCTAssertEqual(window.childWindows?.count, 1)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual((panel.contentView as? FluentToolTipSurface)?.content, third.toolTipView)
        XCTAssertEqual(panel.frame.midX, window.convertPoint(toScreen: third.convert(NSPoint(x: 30, y: 16), to: nil)).x, accuracy: 1)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(third.toolTipView.alphaValue, 1, accuracy: 0.001)
        // Moving within the active target keeps the activation placement.
        let settled = panel.frame
        third.mouseMoved(with: try event(third, point: NSPoint(x: 75, y: 16)))
        wait(0.05)
        XCTAssertEqual(panel.frame, settled)
        third.mouseExited(with: try event(third, point: NSPoint(x: 400, y: -200)))
        wait(0.4)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }

    func testContinuousToolTipCancelsOldFadeWhenOwnershipChanges() throws {
        let window = window()
        let first = host("First", x: 30, window: window)
        let second = host("Second", x: 190, window: window)
        defer { second.dismiss(animated: false); first.dismiss(animated: false); window.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        wait(1.1)
        let panel = try XCTUnwrap(window.childWindows?.first)
        first.dismiss(animated: true)
        wait(0.05)
        XCTAssertLessThan(panel.alphaValue, 1)
        second.mouseEntered(with: try event(second))
        wait(0.3)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
        XCTAssertNotNil(second.toolTipView.superview)
        XCTAssertNil(first.toolTipView.superview)
    }

    func testContinuousToolTipReducedMotionIsImmediateAndWindowChangeClosesIt() throws {
        let window = window()
        let first = host("First", x: 30, window: window, reduced: true)
        let second = host("A wider target", x: 190, window: window, reduced: true)
        defer { second.dismiss(animated: false); first.dismiss(animated: false); window.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        wait(0.85)
        let panel = try XCTUnwrap(window.childWindows?.first)
        second.mouseEntered(with: try event(second))
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual(panel.alphaValue, 1)
        XCTAssertEqual(second.toolTipView.alphaValue, 1)
        XCTAssertEqual(panel.frame.midX, window.convertPoint(toScreen: second.convert(NSPoint(x: 30, y: 16), to: nil)).x, accuracy: 1)
        window.setContentSize(NSSize(width: 510, height: 260))
        XCTAssertTrue(window.childWindows?.isEmpty != false)
        wait(0.3)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }

    func testContinuousToolTipDoesNotTransferAcrossWindowsOrToStandardMode() throws {
        let firstWindow = window()
        let secondWindow = window()
        let first = host("First", x: 30, window: firstWindow, reduced: true)
        let second = host("Other window", x: 190, window: secondWindow, reduced: true)
        let standard = host("Standard", x: 350, window: secondWindow, reduced: true, motion: .standard)
        defer { first.dismiss(animated: false); second.dismiss(animated: false); standard.dismiss(animated: false); firstWindow.orderOut(nil); secondWindow.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        wait(0.85)
        let panel = try XCTUnwrap(firstWindow.childWindows?.first)
        second.mouseEntered(with: try event(second))
        XCTAssertTrue(firstWindow.childWindows?.isEmpty != false)
        XCTAssertTrue(secondWindow.childWindows?.isEmpty != false)
        wait(0.85)
        XCTAssertFalse(secondWindow.childWindows?.first === panel)
        XCTAssertNotNil(secondWindow.childWindows?.first)
        standard.mouseEntered(with: try event(standard))
        XCTAssertTrue(secondWindow.childWindows?.isEmpty != false)
        standard.isHidden = true
        wait(0.85)
        XCTAssertTrue(secondWindow.childWindows?.isEmpty != false)
    }

    func testCaptionButtonsExposeCustomToolTipsAndKeepNativeActions() throws {
        let window = window()
        let coordinator = FluentAppearanceCoordinator(theme: .custom(colorScheme: .dark))
        coordinator.attach(to: window)
        window.applyFluentWindowControlsStyle(.windows)
        defer { window.applyFluentWindowControlsStyle(.macOS); window.orderOut(nil) }
        let controls = try XCTUnwrap(window.titlebarAccessoryViewControllers.first?.view)
        controls.layoutSubtreeIfNeeded()
        let hosts = controls.subviews.compactMap { $0 as? FluentToolTipHost }
        XCTAssertEqual(hosts.count, 3)
        for host in hosts {
            let button = try XCTUnwrap(host.contentView as? NSButton)
            XCTAssertNil(button.toolTip, "only the custom surface should open")
            XCTAssertNotNil(button.action)
            XCTAssertNotNil(button.target)
            XCTAssertEqual(button.accessibilityHelp(), button.accessibilityLabel())
            XCTAssertEqual(host.frame.width, 46, accuracy: 0.001)
        }
        let second = try XCTUnwrap(hosts.dropFirst().first)
        XCTAssertEqual(second.contentView.identifier?.rawValue, "FluentKit.WindowControls.Maximize")
        second.mouseEntered(with: try event(second))
        wait(1.1)
        XCTAssertEqual(window.childWindows?.filter { $0 is FluentToolTipPanel }.count, 1)
        let panel = try XCTUnwrap(window.childWindows?.first as? FluentToolTipPanel)
        coordinator.setPreference(.light)
        let label = try XCTUnwrap(second.toolTipView as? NSTextField)
        XCTAssertTrue(label.textColor?.isEqual(coordinator.resolvedTheme.textPrimary) == true)
        XCTAssertTrue(window.childWindows?.contains { $0 === panel } == true, "appearance changes preserve the open panel")
        XCTAssertEqual(window.childWindows?.filter { $0 is FluentToolTipPanel }.count, 1)
        window.applyFluentWindowControlsStyle(.macOS)
        wait(0.02)
        XCTAssertTrue(window.childWindows?.filter { $0 is FluentToolTipPanel }.isEmpty != false)
    }

    func testContinuousToolTipScreenEdgesRTLAndRemovingActiveAnchor() throws {
        let window = window()
        let visible = try XCTUnwrap(window.screen?.visibleFrame)
        window.setFrameOrigin(NSPoint(x: visible.minX + 4, y: visible.minY + 40))
        let first = host("First", x: 0, window: window, reduced: true)
        let second = host(String(repeating: "Wrapped help text ", count: 12), x: 80, window: window, reduced: true)
        defer { first.dismiss(animated: false); second.dismiss(animated: false); window.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        wait(0.85)
        let panel = try XCTUnwrap(window.childWindows?.first as? FluentToolTipPanel)
        second.update(toolTipView: second.toolTipView, placement: .left, isEnabled: true,
            accessibilityText: "Wrapped help text", context: FluentRenderContext(reduceMotion: true, layoutDirection: .rightToLeft), motion: .continuous)
        second.mouseEntered(with: try event(second))
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(visible.contains(panel.frame), "long content remains inside the visible screen")
        XCTAssertLessThanOrEqual(panel.frame.width, 320)
        XCTAssertGreaterThan(panel.frame.height, 29)
        second.removeFromSuperview()
        wait(0.02)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
        wait(0.3)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }

    func testEnablingReducedMotionSettlesAnInFlightToolTip() throws {
        let window = window()
        let first = host("First", x: 0, window: window)
        let second = host("Second wider tooltip", x: 250, window: window)
        defer { first.dismiss(animated: false); second.dismiss(animated: false); window.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        wait(0.85)
        second.mouseEntered(with: try event(second))
        wait(0.04)
        second.update(toolTipView: second.toolTipView, placement: .bottom, isEnabled: true,
            accessibilityText: "Second", context: FluentRenderContext(reduceMotion: true), motion: .continuous)
        let panel = try XCTUnwrap(window.childWindows?.first as? FluentToolTipPanel)
        XCTAssertEqual(panel.alphaValue, 1)
        XCTAssertEqual(second.toolTipView.alphaValue, 1)
        let final = panel.frame
        wait(0.3)
        XCTAssertEqual(panel.frame, final)
        second.update(toolTipView: second.toolTipView, placement: .bottom, isEnabled: false,
            accessibilityText: "Second", context: FluentRenderContext(reduceMotion: true), motion: .continuous)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }

    func testCaptionToolTipWrappingPreservesActionsAndRestoreLabel() throws {
        _ = NSApplication.shared
        let window = CaptionActionWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.applyFluentWindowControlsStyle(.windows)
        defer { window.applyFluentWindowControlsStyle(.macOS) }
        let hosts = try XCTUnwrap(window.titlebarAccessoryViewControllers.first?.view)
            .subviews.compactMap { $0 as? FluentToolTipHost }
        XCTAssertEqual(hosts.count, 3)
        let buttons = try hosts.map { try XCTUnwrap($0.contentView as? NSButton) }
        let originalLabel = buttons[1].accessibilityLabel()
        buttons[0].performClick(nil)
        buttons[1].performClick(nil)
        XCTAssertNotEqual(buttons[1].accessibilityLabel(), originalLabel)
        XCTAssertEqual((hosts[1].toolTipView as? NSTextField)?.stringValue, buttons[1].accessibilityLabel())
        buttons[1].performClick(nil)
        XCTAssertEqual(buttons[1].accessibilityLabel(), originalLabel)
        buttons[2].performClick(nil)
        XCTAssertEqual(window.actions, ["minimize", "zoom", "zoom", "close"])
    }

    func testPendingToolTipCannotOpenAfterOwnerIsOrderedOut() throws {
        let window = window()
        let first = host("First", x: 0, window: window, reduced: true)
        defer { first.dismiss(animated: false); window.orderOut(nil) }
        first.mouseEntered(with: try event(first))
        window.orderOut(nil)
        wait(0.85)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }
}

private final class CaptionActionWindow: NSWindow {
    var actions: [String] = []
    private var simulatedZoomState = false
    override var isZoomed: Bool { simulatedZoomState }
    override func performZoom(_ sender: Any?) { actions.append("zoom"); simulatedZoomState.toggle() }
    override func performMiniaturize(_ sender: Any?) { actions.append("minimize") }
    override func performClose(_ sender: Any?) { actions.append("close") }
}
