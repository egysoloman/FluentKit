import XCTest
@testable import FluentKit

@MainActor
final class CommandBarMotionPolicyTests: XCTestCase {
    private func mount(reduceMotion: Bool) -> (NSWindow, FluentCommandBar) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 120, y: 160, width: 520, height: 360),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [.init("Menu") {}, .init("Other") {}])
        bar.theme = .custom(colorScheme: .light, materialEffectsEnabled: false)
        bar.reduceMotion = reduceMotion
        window.contentView!.addSubview(bar)
        bar.frame = NSRect(x: 80, y: 240, width: 320, height: 48)
        window.orderFront(nil)
        bar.layoutSubtreeIfNeeded()
        bar.setOpen(true, animated: true)
        return (window, bar)
    }

    private func pauseEntrance(_ panel: NSWindow) throws -> FluentPopupTransitionHost {
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        let layer = try XCTUnwrap(host.layer)
        layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        fluentPrepareMenuPopupEntrance(host: host, edge: .top, motion: FluentMotion.menuOpen,
                                      closedRatio: 0.5, reduceMotion: false)
        XCTAssertNotNil(host.revealMaskLayer.animation(forKey: "fluent.popup.clip.open"))
        return host
    }

    private func assertSettled(_ host: FluentPopupTransitionHost,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(host.animationCoordinator.reduceMotion, file: file, line: line)
        for layer in [host.animationRoot.layer!, host.surface.layer!, host.revealMaskLayer] {
            XCTAssertTrue((layer.animationKeys() ?? []).isEmpty, file: file, line: line)
            XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, CATransform3DIdentity), file: file, line: line)
        }
        XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds, file: file, line: line)
    }

    func testReducedMotionSettlesTheOverflowAndItsOpenAttachedFlyout() throws {
        for withAttachedFlyout in [false, true] {
            let (window, bar) = mount(reduceMotion: false)
            defer { bar.setOpen(false, animated: false); window.close() }
            let panel = try XCTUnwrap(window.childWindows?.first)
            let row = try XCTUnwrap(bar.secondaryCommandViews.first as? FluentAppBarButton)
            var child: NSWindow?
            if withAttachedFlyout {
                row.flyoutItems = [FluentMenuItem("Leaf") {}]
                row.showFlyout()
                child = try XCTUnwrap(panel.childWindows?.first)
            }
            let rootHost = try pauseEntrance(panel)
            let childHost = try child.map(pauseEntrance)
            let responder = panel.firstResponder
            let childResponder = child?.firstResponder
            var changes = 0
            bar.onIsOpenChanged = { _ in changes += 1 }
            bar.reduceMotion = true
            assertSettled(rootHost)
            if let childHost { assertSettled(childHost) }
            XCTAssertTrue(window.childWindows?.first === panel)
            XCTAssertTrue(panel.firstResponder === responder)
            XCTAssertTrue(bar.secondaryCommandViews.first === row)
            if let child {
                XCTAssertTrue(panel.childWindows?.first === child)
                XCTAssertTrue(child.firstResponder === childResponder)
                XCTAssertTrue(row.isFlyoutPresented)
                row.hideFlyout(animated: false)
            }
            XCTAssertTrue(bar.isOpen)
            XCTAssertEqual(changes, 0)
        }
    }

    func testRestoringMotionDoesNotReplayAnAlreadyOpenOverflow() throws {
        let (window, bar) = mount(reduceMotion: true)
        defer { bar.setOpen(false, animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        assertSettled(host)
        bar.reduceMotion = false
        XCTAssertFalse(host.animationCoordinator.reduceMotion)
        XCTAssertNil(host.revealMaskLayer.animation(forKey: "fluent.popup.clip.open"))
        XCTAssertTrue(window.childWindows?.first === panel)
        bar.setOpen(false, animated: false)
        bar.setOpen(true, animated: true)
        let replacement = try XCTUnwrap(window.childWindows?.first)
        let nextHost = try XCTUnwrap(replacement.contentView as? FluentPopupTransitionHost)
        XCTAssertFalse(replacement === panel)
        XCTAssertFalse(nextHost.animationCoordinator.reduceMotion)
    }
}
