import AppKit

enum FluentSelectionIndicatorAxis {
    case horizontal
    case vertical
}

/// Owns the moving selection rail shared by lists and navigation panes. Lists retain the compact
/// single-rail transition; NavigationView can opt into the source-compatible two-rail transition.
final class FluentSelectionIndicatorAnimator {
    private enum ResolvedTransition {
        case continuous
        case jump
        case depthChange
    }

    private static let compactConnectedDimension: CGFloat = 56
    private static let adaptiveDistanceThreshold: CGFloat = 96

    private var axis: FluentSelectionIndicatorAxis
    private var mode: FluentNavigationSelectionIndicatorMode = .continuous
    private let previousLayer = CALayer()
    private let currentLayer = CALayer()
    private var lastTarget: NSRect?
    private var activeTransitionUsesTwoRails = false

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

    func setMode(_ mode: FluentNavigationSelectionIndicatorMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        removeAnimations()
        activeTransitionUsesTwoRails = false
        if let lastTarget {
            setModelFrames(source: nil, target: lastTarget)
        }
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

        // A nearby continuous transition is interruptible and resumes from its presentation
        // geometry. The distant WinUI-style jump owns an outgoing/incoming rail pair, so a new
        // selection starts from the pair's last committed destination.
        let isAnimating = currentLayer.animation(forKey: currentAnimationKey) != nil
        let previous = isAnimating && !activeTransitionUsesTwoRails
            ? (currentLayer.presentation()?.frame ?? lastTarget)
            : lastTarget
        removeAnimations()
        setModelFrames(source: previous, target: target)

        if animated, !reduceMotion, let previous, previous != target {
            let transition = resolvedTransition(from: previous, to: target)
            activeTransitionUsesTwoRails = transition != .continuous
            switch transition {
            case .continuous:
                animateContinuous(from: previous, to: target)
            case .jump:
                animateJump(from: previous, to: target)
            case .depthChange:
                animateDepthChange(from: previous, to: target)
            }
        } else {
            activeTransitionUsesTwoRails = false
        }
        lastTarget = target
    }

    /// Moves the active rail with a containing layout transition without treating that geometry
    /// change as a new selection. NavigationView uses this while its header/list shifts during a
    /// pane open or close transition.
    func relayout(
        target: NSRect?,
        color: NSColor,
        animated: Bool,
        reduceMotion: Bool,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        previousLayer.backgroundColor = color.cgColor
        currentLayer.backgroundColor = color.cgColor
        guard let target else {
            hideAndReset()
            return
        }
        let previousFrame = currentLayer.presentation()?.frame ?? currentLayer.frame
        removeAnimations()
        setModelFrames(source: nil, target: target)
        lastTarget = target
        activeTransitionUsesTwoRails = false
        guard animated, !reduceMotion, duration > 0, previousFrame != target else { return }

        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: NSPoint(x: previousFrame.midX, y: previousFrame.midY))
        position.toValue = NSValue(point: NSPoint(x: target.midX, y: target.midY))
        let bounds = CABasicAnimation(keyPath: "bounds.size")
        bounds.fromValue = NSValue(size: previousFrame.size)
        bounds.toValue = NSValue(size: target.size)
        let group = CAAnimationGroup()
        group.animations = [position, bounds]
        group.duration = duration
        group.timingFunction = timingFunction
        group.isRemovedOnCompletion = true
        currentLayer.add(group, forKey: currentAnimationKey)
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
        activeTransitionUsesTwoRails = false
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

    private func resolvedTransition(from source: NSRect, to destination: NSRect) -> ResolvedTransition {
        let sameDepth = axis == .vertical
            ? abs(destination.midX - source.midX) < 0.5
            : abs(destination.midY - source.midY) < 0.5
        if mode != .continuous, !sameDepth { return .depthChange }

        if mode == .jump { return .jump }
        if mode == .continuous { return .continuous }
        let distance = axis == .vertical
            ? abs(destination.midY - source.midY)
            : abs(destination.midX - source.midX)
        return distance <= Self.adaptiveDistanceThreshold ? .continuous : .jump
    }

    /// WinUI's non-same-depth branch does not translate a rail between rows. The old item-local
    /// visual contracts into the edge facing the destination while the destination visual grows
    /// out of the edge facing the source. Jump and adaptive modes preserve that branch.
    private func animateDepthChange(from source: NSRect, to destination: NSRect) {
        let sourceCenter = NSPoint(x: source.midX, y: source.midY)
        let destinationCenter = NSPoint(x: destination.midX, y: destination.midY)
        let direction: CGFloat
        if axis == .vertical {
            direction = destinationCenter.y < sourceCenter.y ? -1 : 1
        } else {
            direction = destinationCenter.x < sourceCenter.x ? -1 : 1
        }
        let sourceDimension = axis == .vertical ? source.height : source.width
        let destinationDimension = axis == .vertical ? destination.height : destination.width
        let sourceAnchor = axis == .vertical
            ? NSPoint(x: sourceCenter.x, y: sourceCenter.y + direction * sourceDimension / 2)
            : NSPoint(x: sourceCenter.x + direction * sourceDimension / 2, y: sourceCenter.y)
        let destinationAnchor = axis == .vertical
            ? NSPoint(x: destinationCenter.x, y: destinationCenter.y - direction * destinationDimension / 2)
            : NSPoint(x: destinationCenter.x - direction * destinationDimension / 2, y: destinationCenter.y)
        let collapsedSourceSize = axis == .vertical
            ? NSSize(width: source.width, height: 0)
            : NSSize(width: 0, height: source.height)
        let collapsedDestinationSize = axis == .vertical
            ? NSSize(width: destination.width, height: 0)
            : NSSize(width: 0, height: destination.height)

        func geometry(
            from startCenter: NSPoint,
            to endCenter: NSPoint,
            from startSize: NSSize,
            to endSize: NSSize
        ) -> [CAAnimation] {
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: startCenter)
            position.toValue = NSValue(point: endCenter)
            let bounds = CABasicAnimation(keyPath: "bounds.size")
            bounds.fromValue = NSValue(size: startSize)
            bounds.toValue = NSValue(size: endSize)
            return [position, bounds]
        }

        let outgoingOpacity = CABasicAnimation(keyPath: "opacity")
        outgoingOpacity.fromValue = Float(1)
        outgoingOpacity.toValue = Float(1)
        let outgoing = CAAnimationGroup()
        outgoing.animations = geometry(
            from: sourceCenter,
            to: sourceAnchor,
            from: source.size,
            to: collapsedSourceSize
        ) + [outgoingOpacity]
        outgoing.duration = FluentMotion.navigationIndicator.duration
        outgoing.timingFunction = CAMediaTimingFunction(name: .linear)
        outgoing.isRemovedOnCompletion = true

        let incoming = CAAnimationGroup()
        incoming.animations = geometry(
            from: destinationAnchor,
            to: destinationCenter,
            from: collapsedDestinationSize,
            to: destination.size
        )
        incoming.duration = FluentMotion.navigationIndicator.duration
        incoming.timingFunction = CAMediaTimingFunction(name: .linear)
        incoming.isRemovedOnCompletion = true

        previousLayer.add(outgoing, forKey: previousAnimationKey)
        currentLayer.add(incoming, forKey: currentAnimationKey)
    }

    /// Keeps one rail visually connected for nearby destinations. The rail follows the midpoint,
    /// grows only enough to bridge neighboring rows, then contracts into the destination.
    private func animateContinuous(from source: NSRect, to destination: NSRect) {
        let sourceCenter = NSPoint(x: source.midX, y: source.midY)
        let destinationCenter = NSPoint(x: destination.midX, y: destination.midY)
        let distance = axis == .vertical
            ? abs(destinationCenter.y - sourceCenter.y)
            : abs(destinationCenter.x - sourceCenter.x)
        let connectedDimension = min(
            max(axis == .vertical ? destination.height : destination.width, 1) + distance * 0.28,
            Self.compactConnectedDimension
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

    /// Adapts WinUI's two item-local indicators into FluentKit's distance-based jump mode. WinUI
    /// itself branches on visual depth, not distance: same-depth indicators stretch and contract,
    /// while different-depth indicators scale independently in place. Our flat-pane adaptive mode
    /// keeps the two segments bounded and leaves a visible gap for distant destinations.
    private func animateJump(from source: NSRect, to destination: NSRect) {
        let sourceCenter = NSPoint(x: source.midX, y: source.midY)
        let destinationCenter = NSPoint(x: destination.midX, y: destination.midY)
        let distance = axis == .vertical
            ? destinationCenter.y - sourceCenter.y
            : destinationCenter.x - sourceCenter.x
        let direction: CGFloat = distance < 0 ? -1 : 1
        let sourceDimension = axis == .vertical ? source.height : source.width
        let destinationDimension = axis == .vertical ? destination.height : destination.width
        let segmentDimension = min(
            max(max(sourceDimension, destinationDimension), 1) * 2.25,
            Self.compactConnectedDimension
        )
        let segmentSize = axis == .vertical
            ? NSSize(width: source.width, height: segmentDimension)
            : NSSize(width: segmentDimension, height: source.height)
        // WinUI animates an indicator that belongs to each item's template. Its scale origin
        // changes from the near edge to the far edge, but the visual never migrates into an
        // unrelated middle item. Simulate those two item-local masks on our shared pane layer:
        // the outgoing segment grows away from the source, the incoming segment grows back from
        // the destination, and the unselected rows between them stay clear.
        let outgoingShift = max(0, segmentDimension - sourceDimension) / 2
        let incomingShift = max(0, segmentDimension - destinationDimension) / 2
        let outgoingCenter = axis == .vertical
            ? NSPoint(x: sourceCenter.x, y: sourceCenter.y + direction * outgoingShift)
            : NSPoint(x: sourceCenter.x + direction * outgoingShift, y: sourceCenter.y)
        let incomingCenter = axis == .vertical
            ? NSPoint(x: destinationCenter.x, y: destinationCenter.y - direction * incomingShift)
            : NSPoint(x: destinationCenter.x - direction * incomingShift, y: destinationCenter.y)
        let keyTimes = [NSNumber(value: 0), NSNumber(value: 1.0 / 3.0), NSNumber(value: 1)]
        let timingFunctions = [
            FluentMotion.navigationIndicatorExit.curve.timingFunction,
            FluentMotion.navigationIndicator.curve.timingFunction
        ]

        func geometryAnimations(
            centers: [NSPoint],
            sizes: [NSSize]
        ) -> [CAAnimation] {
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = centers.map(NSValue.init(point:))
            position.keyTimes = keyTimes
            position.timingFunctions = timingFunctions

            let bounds = CAKeyframeAnimation(keyPath: "bounds.size")
            bounds.values = sizes.map(NSValue.init(size:))
            bounds.keyTimes = keyTimes
            bounds.timingFunctions = timingFunctions
            return [position, bounds]
        }

        let incomingOpacity = CAKeyframeAnimation(keyPath: "opacity")
        incomingOpacity.values = [Float(0), Float(0), Float(1)]
        incomingOpacity.keyTimes = keyTimes
        incomingOpacity.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            FluentMotion.navigationIndicator.curve.timingFunction
        ]
        let incoming = CAAnimationGroup()
        incoming.animations = geometryAnimations(
            // WinUI's scale reaches its maximum at 0.333 and then returns to endScale. The
            // destination mask must therefore enter already extended toward the source and
            // contract into the selected row. Growing from zero at the destination reverses
            // that relationship and produces a spurious bottom-to-top stretch after arrival.
            centers: [incomingCenter, incomingCenter, destinationCenter],
            sizes: [segmentSize, segmentSize, destination.size]
        ) + [incomingOpacity]
        incoming.duration = FluentMotion.navigationIndicator.duration
        incoming.isRemovedOnCompletion = true

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [Float(1), Float(1), Float(0)]
        opacity.keyTimes = [NSNumber(value: 0), NSNumber(value: 1.0 / 3.0), NSNumber(value: 1)]
        opacity.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            FluentMotion.navigationIndicator.curve.timingFunction
        ]
        let outgoing = CAAnimationGroup()
        outgoing.animations = geometryAnimations(
            centers: [sourceCenter, outgoingCenter, outgoingCenter],
            sizes: [source.size, segmentSize, segmentSize]
        ) + [opacity]
        outgoing.duration = FluentMotion.navigationIndicator.duration
        outgoing.isRemovedOnCompletion = true

        previousLayer.add(outgoing, forKey: previousAnimationKey)
        currentLayer.add(incoming, forKey: currentAnimationKey)
    }

}
