import XCTest
@testable import FluentKit

final class TeachingTipLifecycleTests: XCTestCase {
    @MainActor private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 160, width: 700, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    @MainActor private func host(_ state: FluentState<Bool>, reduceMotion: Bool = true,
                                onOpened: @escaping () -> Void = {}, onClosing: @escaping (FluentTeachingTipClosingEventArgs) -> Void = { _ in },
                                onClosed: @escaping (FluentTeachingTipCloseReason) -> Void = { _ in }) -> FluentViewHost<FluentAnyView> {
        let tip = FluentButtonView("Anchor").teachingTip(isPresented: state.projectedValue,
            placement: .top, shouldConstrainToRootBounds: false, size: NSSize(width: 320, height: 100),
            onClosing: onClosing, onClosed: onClosed, onOpened: onOpened) { FluentText("Tip") }
        return FluentViewHost(FluentAnyView(tip), context: .init(reduceMotion: reduceMotion))
    }

    @MainActor func testRetainedTargetUnloadClosesPanelAndResetsBinding() throws {
        let window = window(), state = FluentState(wrappedValue: true)
        var closed = 0, closing = 0
        let host = host(state, onClosing: { _ in closing += 1 }, onClosed: { _ in closed += 1 })
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(window.childWindows?.first?.isVisible == true)
        let panel = try XCTUnwrap(window.childWindows?.first)
        host.removeFromSuperview() // Retain the wrapper: this must not depend on deinit.
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.parent)
        XCTAssertFalse(state.wrappedValue)
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(closing, 0, "WinUI closes the Popup directly on Unloaded")
        withExtendedLifetime(host) {}
    }

    @MainActor func testMovingTargetToAnotherWindowDoesNotLeaveOldPanelBehind() throws {
        let first = window(), second = window(), state = FluentState(wrappedValue: true)
        let host = host(state)
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        first.contentView!.addSubview(host)
        defer { first.close(); second.close() }
        waitForUI(first.childWindows?.first?.isVisible == true)
        let oldPanel = try XCTUnwrap(first.childWindows?.first)
        second.contentView!.addSubview(host)
        XCTAssertNil(oldPanel.parent)
        XCTAssertFalse(oldPanel.isVisible)
        XCTAssertFalse(state.wrappedValue)
        state.wrappedValue = true
        waitForUI(second.childWindows?.first?.isVisible == true)
        XCTAssertTrue(second.childWindows?.first !== oldPanel)
        XCTAssertTrue(first.childWindows?.isEmpty ?? true)
    }

    @MainActor func testRootResizeRepositionsAfterTargetLayoutWithoutReopening() throws {
        let window = window(), state = FluentState(wrappedValue: true)
        var opened = 0
        let host = host(state, onOpened: { opened += 1 })
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.minXMargin]
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(opened == 1)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let frame = panel.frame, initialX = host.frame.minX
        let content = panel.contentView, responder = panel.firstResponder
        window.setContentSize(NSSize(width: 800, height: 400))
        window.contentView!.layoutSubtreeIfNeeded()
        waitForUI(abs(panel.frame.minX - frame.minX - (host.frame.minX - initialX)) < 0.5)
        XCTAssertEqual(host.frame.minX - initialX, 100, accuracy: 0.5)
        XCTAssertTrue(panel === window.childWindows?.first)
        XCTAssertTrue(content === panel.contentView)
        XCTAssertTrue(responder === panel.firstResponder)
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(state.wrappedValue)
    }

    @MainActor func testOwnerCloseClearsBindingAndReportsClosedOnce() {
        let window = window(), state = FluentState(wrappedValue: true)
        var closed = 0
        let host = host(state, onClosed: { _ in closed += 1 })
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        window.contentView!.addSubview(host)
        waitForUI(window.childWindows?.first?.isVisible == true)
        window.close()
        XCTAssertFalse(state.wrappedValue)
        XCTAssertEqual(closed, 1)
        withExtendedLifetime(host) {}
    }
    @MainActor func testUnloadDuringOpeningCancelsLateOpenedCallback() throws {
        let window = window(), state = FluentState(wrappedValue: true)
        var unloaded = false, closed = 0
        let staleOpened = expectation(description: "No Opened after unload")
        staleOpened.isInverted = true
        let host = host(state, reduceMotion: false, onOpened: { if unloaded { staleOpened.fulfill() } },
                        onClosed: { _ in closed += 1 })
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(window.childWindows?.first?.isVisible == true)
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertNotNil(panel.contentView?.layer?.animation(forKey: "fluent.teachingTip.opacity"),
                        "Exercise unloading while the entrance animation is actually active")
        unloaded = true
        host.removeFromSuperview()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(state.wrappedValue)
        XCTAssertEqual(closed, 1)
        wait(for: [staleOpened], timeout: FluentMotion.teachingTipOpen.duration + 0.15)
        XCTAssertEqual(closed, 1)
    }

    @MainActor func testUnloadInsideCancelledClosingCannotResurrectPopup() {
        let window = window(), state = FluentState(wrappedValue: true)
        var closed = 0, closing = 0
        weak var target: NSView?
        let host = host(state, onClosing: { args in
            closing += 1
            args.cancel = true
            target?.removeFromSuperview()
        }, onClosed: { _ in closed += 1 })
        target = host
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(window.childWindows?.first?.isVisible == true)
        state.wrappedValue = false
        waitForUI(closed == 1)
        XCTAssertEqual(closing, 1)
        XCTAssertFalse(state.wrappedValue)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testCloseCallbackCannotOpenAChildOfAClosedOwner() {
        let window = window(), state = FluentState(wrappedValue: true)
        var closed = 0, opened = 0
        let ghost = expectation(description: "No popup on closed window")
        ghost.isInverted = true
        var checkingClosedWindow = false
        let host = host(state, onOpened: {
            opened += 1
            if checkingClosedWindow { ghost.fulfill() }
        }, onClosed: { _ in
            closed += 1
            if closed == 1 { state.wrappedValue = true }
        })
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(opened == 1)
        checkingClosedWindow = true
        window.close()
        wait(for: [ghost], timeout: 0.1)
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        checkingClosedWindow = false
        window.orderFront(nil)
        state.wrappedValue = false
        state.wrappedValue = true
        waitForUI(opened == 2)
    }

    @MainActor func testUnconstrainedDefaultCanExtendBeyondRootWithoutFallback() throws {
        let window = window(), state = FluentState(wrappedValue: true)
        let host = host(state)
        window.setContentSize(NSSize(width: 700, height: 180))
        host.frame = NSRect(x: 280, y: 140, width: 100, height: 32)
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(window.childWindows?.first?.isVisible == true)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let anchor = window.convertToScreen(host.convert(host.bounds, to: nil))
        XCTAssertGreaterThan(panel.frame.midY, anchor.midY)
        let root = window.contentView!
        let rootFrame = window.convertToScreen(root.convert(root.bounds, to: nil))
        XCTAssertGreaterThan(panel.frame.maxY, rootFrame.maxY,
            "WinUI's default out-of-root mode uses the requested edge without root fallback")
    }

    @MainActor func testUnloadDuringClosingSuppressesDuplicateCompletion() throws {
        let window = window(), state = FluentState(wrappedValue: true)
        var opened = 0, closing = 0, closed = 0
        let duplicate = expectation(description: "No second Closed from obsolete animation")
        duplicate.isInverted = true
        let host = host(state, reduceMotion: false, onOpened: { opened += 1 }, onClosing: { _ in closing += 1 },
                        onClosed: { _ in closed += 1; if closed > 1 { duplicate.fulfill() } })
        host.frame = NSRect(x: 280, y: 180, width: 100, height: 32)
        window.contentView!.addSubview(host)
        defer { window.close() }
        waitForUI(opened == 1)
        let panel = try XCTUnwrap(window.childWindows?.first)
        state.wrappedValue = false
        waitForUI(closing == 1)
        XCTAssertEqual(closed, 0)
        XCTAssertNotNil(panel.contentView?.layer?.animation(forKey: "fluent.teachingTip.opacity"))
        host.removeFromSuperview()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.parent)
        XCTAssertEqual(closed, 1)
        wait(for: [duplicate], timeout: FluentMotion.teachingTipClose.duration + 0.15)
        XCTAssertEqual(closed, 1)
    }

}
