import AppKit

enum FluentSelectionIndicatorAxis {
    case horizontal
    case vertical
}

/// Owns the single moving NavigationView-style selection rail used by lists and navigation panes.
///
/// The previous rail is retained as a hidden compatibility layer so callers can keep a stable
/// layer tree, but transitions are rendered by one layer only. This prevents the outgoing and
/// incoming rails from briefly diverging and producing a visible jump.
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

        // When a new selection arrives during an active transition, continue from the rail's
        // presented geometry instead of snapping back to the previous target first.
        let previous = currentLayer.animation(forKey: currentAnimationKey) != nil
            ? (currentLayer.presentation()?.frame ?? lastTarget)
            : lastTarget
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
        let distance = axis == .vertical
            ? abs(destinationCenter.y - sourceCenter.y)
            : abs(destinationCenter.x - sourceCenter.x)
        let connectedDimension = min(
            max(axis == .vertical ? destination.height : destination.width, 1) + distance * 0.28,
            56
        )
        let connectedCenter = NSPoint(
            x: (sourceCenter.x + destinationCenter.x) / 2,
            y: (sourceCenter.y + destinationCenter.y) / 2
        )
        let connectedSize = axis == .vertical
            ? NSSize(width: destination.width, height: connectedDimension)
            : NSSize(width: connectedDimension, height: destination.height)
        let keyTimes = [NSNumber(value: 0), NSNumber(value: 1.0 / 3.0), NSNumber(value: 1)]
        let timingFunctions = [
            FluentMotion.navigationIndicatorExit.curve.timingFunction,
            FluentMotion.navigationIndicator.curve.timingFunction
        ]

        // Keep position and bounds on one timeline. The rail follows the old-to-new midpoint,
        // grows only enough to bridge the rows, and settles back to the normal 3 x 16 geometry.
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [
            NSValue(point: sourceCenter),
            NSValue(point: connectedCenter),
            NSValue(point: destinationCenter)
        ]
        position.keyTimes = keyTimes
        position.timingFunctions = timingFunctions

        let bounds = CAKeyframeAnimation(keyPath: "bounds.size")
        bounds.values = [
            NSValue(size: source.size),
            NSValue(size: connectedSize),
            NSValue(size: destination.size)
        ]
        bounds.keyTimes = keyTimes
        bounds.timingFunctions = timingFunctions

        let group = CAAnimationGroup()
        group.animations = [position, bounds]
        group.duration = FluentMotion.navigationIndicator.duration
        group.isRemovedOnCompletion = true
        currentLayer.add(group, forKey: currentAnimationKey)
    }

}
