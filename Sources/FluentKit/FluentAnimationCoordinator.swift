import AppKit

/// Bridges named visual states and structural transitions to the Core Animation backend.
/// Coordinators are owned by a control or presenter; FluentKit deliberately does not serialize
/// unrelated animations through one process-wide queue.
final class FluentAnimationCoordinator {
    let visualStates: FluentVisualStateCoordinator
    var reduceMotion: Bool {
        didSet { visualStates.reduceMotion = reduceMotion }
    }

    private let layerAnimator = FluentLayerAnimator()
    private var valueAnimationTimers: [String: Timer] = [:]
    private var valueAnimationGenerations: [String: UInt64] = [:]

    init(
        state: FluentVisualState = .normal,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        visualStates = FluentVisualStateCoordinator(state: state, reduceMotion: reduceMotion)
        self.reduceMotion = reduceMotion
    }

    @discardableResult
    func transitionState(
        to next: FluentVisualState,
        animated: Bool,
        motion: FluentMotionToken,
        apply: (FluentVisualStateTransition) -> Void
    ) -> Bool {
        visualStates.transition(to: next, animated: animated, motion: motion, apply: apply)
    }

    func animateState(
        _ changes: [FluentLayerAnimationChange],
        motion: FluentMotionToken,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        layerAnimator.animate(
            changes,
            motion: motion,
            reduceMotion: reduceMotion || !animated,
            completion: completion
        )
    }

    func animateTransition(
        _ changes: [FluentLayerAnimationChange],
        motion: FluentMotionToken,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        layerAnimator.animate(
            changes,
            motion: motion,
            reduceMotion: reduceMotion || !animated,
            completion: completion
        )
    }

    func cancel(layer: CALayer, key: String) {
        layerAnimator.cancel(layer: layer, key: key)
    }

    func cancelAll(on layers: [CALayer]) {
        layerAnimator.cancelAll(on: layers)
    }

    /// Animates layout-owned scalar values on the same motion policy as layer transitions.
    /// This is used for constraints whose model value cannot be represented by a CALayer key path.
    func animateValue(
        key: String,
        from: CGFloat,
        to: CGFloat,
        motion: FluentMotionToken,
        animated: Bool,
        update: @escaping (CGFloat) -> Void,
        completion: (() -> Void)? = nil
    ) {
        cancelValueAnimation(key: key)
        let generation = valueAnimationGenerations[key, default: 0] &+ 1
        valueAnimationGenerations[key] = generation
        guard animated, !reduceMotion, motion.duration > 0 else {
            update(to)
            completion?()
            return
        }

        update(from)
        let startTime = CACurrentMediaTime() + motion.delay
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, self.valueAnimationGenerations[key] == generation else {
                timer.invalidate()
                return
            }
            let elapsed = CACurrentMediaTime() - startTime
            guard elapsed >= 0 else { return }
            let fraction = min(max(elapsed / motion.duration, 0), 1)
            let progress = FluentAnimationCurve.cubicBezier(motion.curve).progress(at: CGFloat(fraction))
            update(from + (to - from) * progress)
            guard fraction >= 1 else { return }
            timer.invalidate()
            self.valueAnimationTimers[key] = nil
            self.valueAnimationGenerations[key] = generation &+ 1
            update(to)
            completion?()
        }
        valueAnimationTimers[key] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancelValueAnimation(key: String) {
        valueAnimationGenerations[key, default: 0] &+= 1
        valueAnimationTimers[key]?.invalidate()
        valueAnimationTimers[key] = nil
    }

    func cancelAllValueAnimations() {
        for key in Array(valueAnimationTimers.keys) {
            cancelValueAnimation(key: key)
        }
    }

    deinit {
        valueAnimationTimers.values.forEach { $0.invalidate() }
    }
}
