import AppKit

enum FluentSelectionIndicatorAxis {
    case horizontal
    case vertical
}

/// Owns the two-layer NavigationView-style selection rail used by lists and navigation panes.
final class FluentSelectionIndicatorAnimator {
    private var axis: FluentSelectionIndicatorAxis
    private let previousLayer = CALayer()
    private let currentLayer = CALayer()
    private var lastTarget: NSRect?

    init(
        currentLayerName: String,
        previousLayerName: String,
        axis: FluentSelectionIndicatorAxis
    ) {
        self.axis = axis
        previousLayer.name = previousLayerName
        previousLayer.cornerRadius = 2
        previousLayer.zPosition = 999
        previousLayer.opacity = 0
        currentLayer.name = currentLayerName
        currentLayer.cornerRadius = 2
        currentLayer.zPosition = 1_000
        currentLayer.opacity = 0
    }

    func attach(to layer: CALayer) {
        guard currentLayer.superlayer !== layer else { return }
        previousLayer.removeFromSuperlayer()
        currentLayer.removeFromSuperlayer()
        layer.addSublayer(previousLayer)
        layer.addSublayer(currentLayer)
    }

    func setAxis(_ axis: FluentSelectionIndicatorAxis) {
        guard self.axis != axis else { return }
        self.axis = axis
        hideAndReset()
    }

    func update(
        target: NSRect?,
        color: NSColor,
        animated: Bool,
        reduceMotion: Bool
    ) {
        previousLayer.backgroundColor = color.cgColor
        currentLayer.backgroundColor = color.cgColor

        guard let target else {
            hideAndReset()
            return
        }

        if !animated,
           currentLayer.animation(forKey: currentAnimationKey) != nil,
           lastTarget == target {
            setModelFrames(source: nil, target: target)
            return
        }

        let previous = lastTarget
        removeAnimations()
        setModelFrames(source: previous, target: target)

        if animated, !reduceMotion, let previous, previous != target {
            animate(from: previous, to: target)
        }
        lastTarget = target
    }

    private var currentAnimationKey: String {
        "fluent.navigation.selection"
    }

    private var previousAnimationKey: String {
        "fluent.navigation.selection.outgoing"
    }

    private func hideAndReset() {
        removeAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previousLayer.opacity = 0
        currentLayer.opacity = 0
        CATransaction.commit()
        lastTarget = nil
    }

    private func removeAnimations() {
        previousLayer.removeAnimation(forKey: previousAnimationKey)
        currentLayer.removeAnimation(forKey: currentAnimationKey)
    }

    private func setModelFrames(source: NSRect?, target: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previousLayer.frame = source ?? target
        previousLayer.opacity = 0
        currentLayer.frame = target
        currentLayer.opacity = 1
        CATransaction.commit()
    }

    private func animate(from source: NSRect, to destination: NSRect) {
        let sourceCenter = NSPoint(x: source.midX, y: source.midY)
        let destinationCenter = NSPoint(x: destination.midX, y: destination.midY)
        let sourcePosition = axis == .vertical ? sourceCenter.y : sourceCenter.x
        let destinationPosition = axis == .vertical ? destinationCenter.y : destinationCenter.x
        let dimension = max(axis == .vertical ? destination.height : destination.width, 1)
        let connectedScale = 1 + abs(destinationPosition - sourcePosition) / dimension
        let keyTimes = [NSNumber(value: 0), NSNumber(value: 1.0 / 3.0), NSNumber(value: 1)]
        let timingFunctions = [
            FluentMotion.navigationIndicatorExit.curve.timingFunction,
            FluentMotion.navigationIndicator.curve.timingFunction
        ]

        let outgoing = animationGroup(
            sourceCenter: sourceCenter,
            destinationCenter: destinationCenter,
            connectedScale: connectedScale,
            fadesOut: true,
            keyTimes: keyTimes,
            timingFunctions: timingFunctions
        )
        let incoming = animationGroup(
            sourceCenter: sourceCenter,
            destinationCenter: destinationCenter,
            connectedScale: connectedScale,
            fadesOut: false,
            keyTimes: keyTimes,
            timingFunctions: timingFunctions
        )
        previousLayer.add(outgoing, forKey: previousAnimationKey)
        currentLayer.add(incoming, forKey: currentAnimationKey)
    }

    private func animationGroup(
        sourceCenter: NSPoint,
        destinationCenter: NSPoint,
        connectedScale: CGFloat,
        fadesOut: Bool,
        keyTimes: [NSNumber],
        timingFunctions: [CAMediaTimingFunction]
    ) -> CAAnimationGroup {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [
            NSValue(point: sourceCenter),
            NSValue(point: destinationCenter)
        ]
        position.keyTimes = [keyTimes[0], keyTimes[1]]
        position.timingFunctions = [timingFunctions[0]]

        let scale = CAKeyframeAnimation(
            keyPath: axis == .vertical ? "transform.scale.y" : "transform.scale.x"
        )
        scale.values = [1, connectedScale, 1]
        scale.keyTimes = keyTimes
        scale.timingFunctions = timingFunctions

        // The first position keyframe reaches the destination at one third, matching the
        // NavigationView composition path; the remaining two thirds are the scale settle.
        var animations: [CAAnimation] = [position, scale]
        if fadesOut {
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [1, 1, 0]
            opacity.keyTimes = keyTimes
            opacity.timingFunctions = [
                CAMediaTimingFunction(name: .linear),
                FluentMotion.navigationIndicator.curve.timingFunction
            ]
            animations.append(opacity)
        }

        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = FluentMotion.navigationIndicator.duration
        group.isRemovedOnCompletion = true
        return group
    }
}
