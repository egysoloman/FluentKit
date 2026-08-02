import AppKit

/// Changes a layer's transform origin without moving its untransformed frame. Call this before
/// installing a transform animation; once a non-identity transform is active, `frame` is no
/// longer a reliable geometry source.
func fluentSetAnchorPoint(_ anchorPoint: CGPoint, preservingFrameOf layer: CALayer) {
    let previousAnchor = layer.anchorPoint
    guard previousAnchor != anchorPoint else { return }
    let previousPosition = layer.position
    let size = layer.bounds.size
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.anchorPoint = anchorPoint
    layer.position = CGPoint(
        x: previousPosition.x + (anchorPoint.x - previousAnchor.x) * size.width,
        y: previousPosition.y + (anchorPoint.y - previousAnchor.y) * size.height
    )
    CATransaction.commit()
}

struct FluentLayerAnimationChange {
    let layer: CALayer
    let key: String
    let keyPath: String
    let fromValue: Any?
    let toValue: Any
    let applyModelValue: () -> Void

    init(
        layer: CALayer,
        key: String,
        keyPath: String,
        fromValue: Any? = nil,
        toValue: Any,
        applyModelValue: @escaping () -> Void
    ) {
        self.layer = layer
        self.key = key
        self.keyPath = keyPath
        self.fromValue = fromValue
        self.toValue = toValue
        self.applyModelValue = applyModelValue
    }
}

/// Executes explicit Core Animation changes while keeping model and presentation state coherent.
final class FluentLayerAnimator {
    private struct AnimationID: Hashable {
        let layer: ObjectIdentifier
        let key: String
    }

    private var generations: [AnimationID: UInt64] = [:]
    private var completionDelegates: [AnimationID: FluentLayerAnimationCompletionDelegate] = [:]
    private var completionWorkItems: [AnimationID: DispatchWorkItem] = [:]

    func animate(
        _ changes: [FluentLayerAnimationChange],
        motion: FluentMotionToken,
        reduceMotion: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard !changes.isEmpty else {
            completion?()
            return
        }

        let sampledValues = changes.map { change in
            change.fromValue
                ?? change.layer.presentation()?.value(forKeyPath: change.keyPath)
                ?? change.layer.value(forKeyPath: change.keyPath)
        }
        let animationIDs = changes.map { AnimationID(layer: ObjectIdentifier($0.layer), key: $0.key) }
        let animationGenerations = animationIDs.map(beginGeneration(for:))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes.forEach { $0.applyModelValue() }
        CATransaction.commit()

        guard !reduceMotion, motion.duration > 0 else {
            for change in changes {
                change.layer.removeAnimation(forKey: change.key)
            }
            completion?()
            return
        }

        let mediaStartTime = CACurrentMediaTime() + motion.delay
        for index in changes.indices {
            let change = changes[index]
            let animation = CABasicAnimation(keyPath: change.keyPath)
            animation.fromValue = sampledValues[index]
            animation.toValue = change.toValue
            animation.duration = motion.duration
            animation.timingFunction = motion.curve.timingFunction
            // A transition batch is one timeline even when its properties live on different
            // layers. Convert the shared media time into each layer's local time space.
            animation.beginTime = change.layer.convertTime(mediaStartTime, from: nil)
            if motion.delay > 0 {
                animation.fillMode = .backwards
            }
            if index == changes.count - 1, let completion {
                let id = animationIDs[index]
                let generation = animationGenerations[index]
                let completionNotBefore = CACurrentMediaTime() + motion.delay + motion.duration - 0.002
                let delegate = FluentLayerAnimationCompletionDelegate { [weak self] finished in
                    guard CACurrentMediaTime() >= completionNotBefore else { return }
                    self?.finish(id: id, generation: generation, finished: finished, completion: completion)
                }
                completionDelegates[id] = delegate
                animation.delegate = delegate
                let workItem = DispatchWorkItem { [weak self] in
                    self?.finish(id: id, generation: generation, finished: true, completion: completion)
                }
                completionWorkItems[id] = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + motion.delay + motion.duration + 0.01,
                    execute: workItem
                )
            }
            change.layer.add(animation, forKey: change.key)
        }
    }

    func cancel(layer: CALayer, key: String) {
        let id = AnimationID(layer: ObjectIdentifier(layer), key: key)
        generations[id, default: 0] &+= 1
        completionDelegates[id] = nil
        completionWorkItems[id]?.cancel()
        completionWorkItems[id] = nil
        layer.removeAnimation(forKey: key)
    }

    func cancelAll(on layers: [CALayer]) {
        let layerIDs = Set(layers.map(ObjectIdentifier.init))
        for id in generations.keys where layerIDs.contains(id.layer) {
            generations[id, default: 0] &+= 1
            completionDelegates[id] = nil
            completionWorkItems[id]?.cancel()
            completionWorkItems[id] = nil
        }
        layers.forEach { $0.removeAllAnimations() }
    }

    private func beginGeneration(for id: AnimationID) -> UInt64 {
        let generation = generations[id, default: 0] &+ 1
        generations[id] = generation
        completionDelegates[id] = nil
        completionWorkItems[id]?.cancel()
        completionWorkItems[id] = nil
        return generation
    }

    private func finish(
        id: AnimationID,
        generation: UInt64,
        finished: Bool,
        completion: () -> Void
    ) {
        guard generations[id] == generation else { return }
        generations[id] = generation &+ 1
        completionDelegates[id] = nil
        completionWorkItems[id]?.cancel()
        completionWorkItems[id] = nil
        if finished { completion() }
    }
}

private final class FluentLayerAnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion(flag)
    }
}
