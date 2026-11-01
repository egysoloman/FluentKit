import AppKit

/// Ownership moves between hosts; stale host completions cannot close the new owner's panel.
final class FluentToolTipPresentation {
    let panel: FluentToolTipPanel
    let surface: FluentToolTipSurface
    // Each call supplies the resolved render-context policy. Do not apply a second,
    // stale system preference on top of an explicit context override.
    private let animator = FluentAnimationCoordinator(reduceMotion: false)
    private var targetFrame: NSRect?
    private var isMoving = false

    init(content: NSView, context: FluentRenderContext) {
        surface = FluentToolTipSurface(content: content, context: context)
        panel = FluentToolTipPanel(contentRect: .zero)
        panel.contentView = surface
    }

    func show(in window: NSWindow, frame: NSRect, motion: FluentToolTipMotion,
              animateGeometry: Bool, reduceMotion: Bool) {
        if !panel.isVisible {
            panel.setFrame(frame, display: false)
            panel.alphaValue = reduceMotion ? 1 : 0
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
        move(to: frame, animated: animateGeometry, contentChanged: true)
        fade(to: 1, motion: motion, reduceMotion: reduceMotion, animated: true)
    }

    func move(to frame: NSRect, animated: Bool, contentChanged: Bool) {
        if animated, frame == targetFrame, isMoving, !contentChanged { return }
        targetFrame = frame
        let start = panel.frame
        if start == frame, !surface.hasContentTransition {
            animator.cancelValueAnimation(key: "geometry")
            isMoving = false
            return
        }
        isMoving = animated
        animator.animateValue(key: "geometry", from: 0, to: 1,
            motion: FluentMotionToken(duration: FluentToolTipMetrics.continuousMoveDuration,
                                      curve: .controlFastOutSlowIn),
            animated: animated, update: { [weak self] progress in
                guard let self else { return }
                self.panel.setFrame(NSRect.interpolate(from: start, to: frame, fraction: progress), display: true)
                self.surface.setContentTransitionProgress(progress)
            }, completion: { [weak self] in
                self?.isMoving = false
                self?.surface.finishContentTransition()
            })
    }

    func fade(to alpha: CGFloat, motion: FluentToolTipMotion, reduceMotion: Bool,
              animated: Bool, completion: (() -> Void)? = nil) {
        animator.animateValue(key: "opacity", from: panel.alphaValue, to: alpha,
            motion: FluentMotionToken(duration: motion == .continuous
                ? FluentToolTipMetrics.continuousFadeDuration : FluentToolTipMetrics.fadeDuration, curve: .linear),
            animated: animated && !reduceMotion,
            update: { [weak self] in self?.panel.alphaValue = $0 }, completion: completion)
    }

    func close() {
        animator.cancelAllValueAnimations()
        surface.finishContentTransition()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        surface.content.removeFromSuperview()
    }

    deinit { close() }
}
