import XCTest
@testable import FluentKit

@MainActor
final class PopupMotionPolicyTests: XCTestCase {
    private func makeHost() -> FluentPopupTransitionHost {
        _ = NSApplication.shared
        let host = FluentPopupTransitionHost(content: NSView(), theme: .current,
            cornerRadius: 8, name: "PolicyTest")
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
        host.layoutSubtreeIfNeeded()
        // Keep the assertion independent of the runner's frame timing.
        let layer = host.layer!
        let time = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = time
        return host
    }

    func testSplitOpeningUsesResolvedPolicyInsteadOfAmbientCoordinatorDefault() throws {
        let host = makeHost()
        for reduced in [false, true, false] {
            // The coordinator can have captured a different system setting at construction.
            host.animationCoordinator.reduceMotion = !reduced
            fluentPreparePopupEntrance(host: host, edge: .top, motion: FluentMotion.comboBoxOpen,
                closedRatio: 0.5, baselineFromTop: 54, reduceMotion: reduced)
            let keys = host.revealMaskLayer.animationKeys() ?? []
            XCTAssertEqual(keys.isEmpty, reduced)
            XCTAssertTrue(host.revealMaskLayer.frame.contains(host.bounds))
            if !reduced {
                let animation = try XCTUnwrap(host.revealMaskLayer.animation(forKey: "fluent.popup.reveal.bounds") as? CABasicAnimation)
                XCTAssertEqual(animation.duration, FluentMotion.comboBoxOpen.duration)
            }
        }
    }

    func testMenuOpeningUsesResolvedPolicyInsteadOfAmbientCoordinatorDefault() throws {
        let host = makeHost()
        for reduced in [false, true, false] {
            host.animationCoordinator.reduceMotion = !reduced
            fluentPrepareMenuPopupEntrance(host: host, edge: .bottom, motion: FluentMotion.controlFast,
                closedRatio: 0.5, reduceMotion: reduced)
            for layer in [host.animationRoot.layer!, host.surface.layer!, host.revealMaskLayer] {
                XCTAssertEqual((layer.animationKeys() ?? []).isEmpty, reduced)
                XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, CATransform3DIdentity))
            }
        }
    }
}
