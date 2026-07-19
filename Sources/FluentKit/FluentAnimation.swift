import AppKit

/// A cubic-bezier timing curve with CSS/Core Animation compatible control points.
public struct FluentCubicBezier: Hashable, Sendable {
    public let x1: CGFloat
    public let y1: CGFloat
    public let x2: CGFloat
    public let y2: CGFloat

    public init(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        self.x1 = min(max(x1, 0), 1)
        self.y1 = y1
        self.x2 = min(max(x2, 0), 1)
        self.y2 = y2
    }

    public var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: Float(x1), Float(y1),
            Float(x2), Float(y2)
        )
    }

    public static let controlFastOutSlowIn = FluentCubicBezier(0, 0, 0, 1)
    public static let connectedDefault = FluentCubicBezier(0.8, 0, 0.2, 1)
    public static let direct = FluentCubicBezier(0.1, 0.9, 0.2, 1)
    public static let navigationExit = FluentCubicBezier(0.9, 0.1, 1, 0.2)
    public static let contract = FluentCubicBezier(0.7, 0, 1, 0.5)
}

/// Common timing curves used by FluentKit transitions and implicit animations.
public enum FluentAnimationCurve: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case cubicBezier(FluentCubicBezier)

    public var timingFunction: CAMediaTimingFunction {
        switch self {
        case .linear: return CAMediaTimingFunction(name: .linear)
        case .easeIn: return CAMediaTimingFunction(name: .easeIn)
        case .easeOut: return CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
        case let .cubicBezier(curve): return curve.timingFunction
        }
    }

    /// Returns the transformed progress for a normalized linear input.
    public func progress(at fraction: CGFloat) -> CGFloat {
        if case .linear = self { return min(max(fraction, 0), 1) }
        return timingFunction.fluentProgress(at: fraction)
    }
}

/// A scene-specific Fluent motion value consumed by controls and presentations.
public struct FluentMotionToken: Sendable {
    public let duration: TimeInterval
    public let curve: FluentCubicBezier
    public let delay: TimeInterval
    public let distance: CGFloat
    public let scale: CGFloat

    public init(
        duration: TimeInterval,
        curve: FluentCubicBezier,
        delay: TimeInterval = 0,
        distance: CGFloat = 0,
        scale: CGFloat = 1
    ) {
        self.duration = max(duration, 0)
        self.curve = curve
        self.delay = max(delay, 0)
        self.distance = distance
        self.scale = max(scale, 0.01)
    }

    public var transaction: FluentAnimationTransaction {
        FluentAnimationTransaction(duration: duration, curve: .cubicBezier(curve))
    }
}

/// Fluent motion tokens organized by interaction rather than one global duration.
public enum FluentMotion {
    public static let controlFaster = FluentMotionToken(duration: 0.083, curve: .controlFastOutSlowIn)
    public static let controlFast = FluentMotionToken(duration: 0.167, curve: .controlFastOutSlowIn)
    public static let controlNormal = FluentMotionToken(duration: 0.250, curve: .controlFastOutSlowIn)
    public static let connectedDefault = FluentMotionToken(duration: 0.300, curve: .connectedDefault)
    public static let connectedDirect = FluentMotionToken(duration: 0.200, curve: .direct)
    public static let connectedGravity = FluentMotionToken(duration: 0.300, curve: .connectedDefault, distance: 80, scale: 1.1)
    public static let navigationIndicator = FluentMotionToken(duration: 0.600, curve: .direct)
    public static let navigationIndicatorExit = FluentMotionToken(duration: 0.600, curve: .navigationExit)
    public static let navigationPaneOpen = FluentMotionToken(duration: 0.350, curve: .direct)
    public static let navigationPaneClose = FluentMotionToken(duration: 0.120, curve: .direct)
    public static let teachingTipOpen = FluentMotionToken(duration: 0.300, curve: .direct, distance: 8, scale: 0.97)
    public static let teachingTipClose = FluentMotionToken(duration: 0.200, curve: .contract, distance: 8, scale: 0.97)
}

public struct FluentAnimationTransaction {
    public let duration: TimeInterval
    public let timingFunction: CAMediaTimingFunction

    public init(duration: TimeInterval = FluentAnimation.content, timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)) {
        self.duration = duration
        self.timingFunction = timingFunction
    }

    public init(duration: TimeInterval = FluentAnimation.content, curve: FluentAnimationCurve) {
        self.init(duration: duration, timingFunction: curve.timingFunction)
    }

    /// Samples this transaction's cubic timing function at a normalized linear input.
    public func progress(at fraction: CGFloat) -> CGFloat {
        timingFunction.fluentProgress(at: fraction)
    }

    public func perform(_ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timingFunction)
        if let completion { CATransaction.setCompletionBlock(completion) }
        changes()
        CATransaction.commit()
    }
}

private extension CAMediaTimingFunction {
    func fluentProgress(at fraction: CGFloat) -> CGFloat {
        let x = min(max(fraction, 0), 1)
        if x == 0 || x == 1 { return x }

        var first = [Float](repeating: 0, count: 2)
        var second = [Float](repeating: 0, count: 2)
        getControlPoint(at: 1, values: &first)
        getControlPoint(at: 2, values: &second)
        let x1 = CGFloat(first[0])
        let y1 = CGFloat(first[1])
        let x2 = CGFloat(second[0])
        let y2 = CGFloat(second[1])

        func coordinate(_ t: CGFloat, _ firstControl: CGFloat, _ secondControl: CGFloat) -> CGFloat {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * firstControl
                + 3 * inverse * t * t * secondControl
                + t * t * t
        }

        var lower: CGFloat = 0
        var upper: CGFloat = 1
        var parameter = x
        for _ in 0..<14 {
            parameter = (lower + upper) / 2
            if coordinate(parameter, x1, x2) < x {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return min(max(coordinate(parameter, y1, y2), 0), 1)
    }
}

/// An edge used by a move transition. Values follow the native AppKit coordinate system.
public enum FluentTransitionEdge: Sendable {
    case leading
    case trailing
    case top
    case bottom
}

/// Controls how a declarative branch is replaced when its native view shape changes.
public indirect enum FluentTransition: Sendable {
    /// Replaces the branch immediately.
    case none
    /// Fades both the incoming and outgoing branches.
    case crossFade
    /// Preserves the original trailing slide-and-fade behavior.
    case slide
    /// Scales an inserted branch from 94 percent and scales/fades a removed branch.
    case scale
    /// Moves a branch by a compact platform-appropriate distance from or toward an edge.
    case move(edge: FluentTransitionEdge)
    /// Applies two effects to each transition phase.
    case combined(FluentTransition, FluentTransition)
    /// Uses independent effects for the incoming and outgoing branches.
    case asymmetric(insertion: FluentTransition, removal: FluentTransition)

    /// Combines this effect with another effect for both insertion and removal.
    public func combined(with other: FluentTransition) -> FluentTransition {
        .combined(self, other)
    }

    fileprivate var insertionState: FluentTransitionVisualState {
        switch self {
        case .none: return .identity
        case .crossFade: return FluentTransitionVisualState(opacity: 0)
        case .slide: return FluentTransitionVisualState(opacity: 0, transform: CGAffineTransform(translationX: 24, y: 0))
        case .scale: return FluentTransitionVisualState(transform: CGAffineTransform(scaleX: 0.94, y: 0.94))
        case .move(let edge): return FluentTransitionVisualState(transform: edge.translation)
        case .combined(let first, let second): return first.insertionState.combined(with: second.insertionState)
        case .asymmetric(let insertion, _): return insertion.insertionState
        }
    }

    fileprivate var removalState: FluentTransitionVisualState {
        switch self {
        case .none: return .identity
        case .crossFade: return FluentTransitionVisualState(opacity: 0)
        case .slide: return FluentTransitionVisualState(opacity: 0)
        case .scale: return FluentTransitionVisualState(opacity: 0, transform: CGAffineTransform(scaleX: 0.94, y: 0.94))
        case .move(let edge): return FluentTransitionVisualState(transform: edge.translation)
        case .combined(let first, let second): return first.removalState.combined(with: second.removalState)
        case .asymmetric(_, let removal): return removal.removalState
        }
    }
}

private struct FluentTransitionVisualState {
    let opacity: CGFloat
    let transform: CGAffineTransform

    static let identity = FluentTransitionVisualState(opacity: 1, transform: .identity)

    init(opacity: CGFloat = 1, transform: CGAffineTransform = .identity) {
        self.opacity = opacity
        self.transform = transform
    }

    var isIdentity: Bool {
        abs(opacity - 1) < 0.0001 &&
        abs(transform.a - 1) < 0.0001 &&
        abs(transform.b) < 0.0001 &&
        abs(transform.c) < 0.0001 &&
        abs(transform.d - 1) < 0.0001 &&
        abs(transform.tx) < 0.0001 &&
        abs(transform.ty) < 0.0001
    }

    func combined(with other: FluentTransitionVisualState) -> FluentTransitionVisualState {
        FluentTransitionVisualState(
            opacity: opacity * other.opacity,
            transform: transform.concatenating(other.transform)
        )
    }
}

private extension FluentTransitionEdge {
    var translation: CGAffineTransform {
        switch self {
        case .leading: return CGAffineTransform(translationX: -24, y: 0)
        case .trailing: return CGAffineTransform(translationX: 24, y: 0)
        case .top: return CGAffineTransform(translationX: 0, y: 24)
        case .bottom: return CGAffineTransform(translationX: 0, y: -24)
        }
    }
}

/// Keeps a stable host around a branch so incompatible updates can be animated instead of
/// replacing the parent hierarchy abruptly.
public struct FluentTransitionView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let transition: FluentTransition
    fileprivate let animation: FluentAnimationTransaction

    public init(
        content: Content,
        transition: FluentTransition,
        animation: FluentAnimationTransaction = FluentAnimationTransaction()
    ) {
        self.content = content
        self.transition = transition
        self.animation = animation
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        var animationContext = context
        animationContext.animationDuration = context.reduceMotion ? 0 : animation.duration
        animationContext.animationTimingFunction = animation.timingFunction
        return FluentTransitionHost(
            content: content._mount(in: animationContext),
            transition: transition,
            duration: context.reduceMotion ? 0 : animation.duration,
            timingFunction: animation.timingFunction
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentTransitionHost else { return false }
        var animationContext = context
        animationContext.animationDuration = context.reduceMotion ? 0 : animation.duration
        animationContext.animationTimingFunction = animation.timingFunction
        host.update(
            updateContent: { native, updateContext in content._update(native, in: updateContext) },
            makeContent: { content._mount(in: animationContext) },
            transition: transition,
            context: animationContext
        )
        return true
    }
}

private final class FluentTransitionHost: NSView {
    private var duration: TimeInterval
    private var current: FluentTransitionEntry
    private var isTransitioning = false
    private var pendingUpdate: (() -> Void)?
    private var timingFunction: CAMediaTimingFunction
    private var completionDelegate: FluentTransitionCompletionDelegate?
    private var completionWorkItem: DispatchWorkItem?
    private var transitionGeneration: UInt64 = 0

    init(content: NSView, transition: FluentTransition, duration: TimeInterval, timingFunction: CAMediaTimingFunction) {
        self.current = FluentTransitionEntry(content: content)
        self.duration = duration
        self.timingFunction = timingFunction
        super.init(frame: .zero)
        wantsLayer = true
        install(self.current)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        updateContent: @escaping (NSView, FluentRenderContext) -> Bool,
        makeContent: @escaping () -> NSView,
        transition: FluentTransition,
        context: FluentRenderContext
    ) {
        duration = context.animationDuration
        timingFunction = context.animationTimingFunction
        guard !isTransitioning else {
            pendingUpdate = { [weak self] in
                self?.update(updateContent: updateContent, makeContent: makeContent, transition: transition, context: context)
            }
            return
        }
        if updateContent(current.content, context) {
            needsLayout = true
            return
        }

        let replacement = FluentTransitionEntry(content: makeContent())
        install(replacement)

        let old = current
        let insertionState = transition.insertionState
        let removalState = transition.removalState
        guard duration > 0, !insertionState.isIdentity || !removalState.isIdentity else {
            old.removeFromSuperview()
            current = replacement
            return
        }

        isTransitioning = true
        transitionGeneration &+= 1
        let generation = transitionGeneration
        let matchedGeometryViews = fluentPrepareMatchedGeometry(from: old, to: replacement, in: self)
        let cleanupDuration = max(duration, matchedGeometryViews.map(\.duration).max() ?? 0)
        replacement.apply(insertionState)
        old.apply(.identity)
        NSAnimationContext.runAnimationGroup { animationContext in
            animationContext.duration = duration
            animationContext.timingFunction = timingFunction
            replacement.animate(to: .identity)
            old.animate(to: removalState)
            fluentAnimateMatchedGeometry(matchedGeometryViews)
        }
        let completeTransition: () -> Void = { [weak self, weak old, weak replacement] in
            guard let self,
                  self.transitionGeneration == generation,
                  self.isTransitioning,
                  let replacement else { return }
            self.isTransitioning = false
            self.completionWorkItem?.cancel()
            self.completionWorkItem = nil
            self.layer?.removeAnimation(forKey: "fluent.transition.cleanup")
            old?.removeFromSuperview()
            matchedGeometryViews.forEach { prepared in
                prepared.view.layer?.removeAnimation(forKey: "fluent.connected.transform")
                prepared.view.layer?.removeAnimation(forKey: "fluent.connected.gravity.shadow")
                prepared.view.layer?.setAffineTransform(.identity)
                prepared.view.layer?.shadowOpacity = 0
            }
            replacement.apply(.identity)
            self.current = replacement
            self.completionDelegate = nil
            self.finishTransition()
        }
        completionDelegate = FluentTransitionCompletionDelegate(completion: completeTransition)
        let completionAnimation = CABasicAnimation(keyPath: "opacity")
        completionAnimation.fromValue = 1
        completionAnimation.toValue = 1
        completionAnimation.duration = cleanupDuration
        completionAnimation.isRemovedOnCompletion = true
        completionAnimation.delegate = completionDelegate
        layer?.add(completionAnimation, forKey: "fluent.transition.cleanup")
        let completionWorkItem = DispatchWorkItem(block: completeTransition)
        self.completionWorkItem = completionWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + cleanupDuration,
            execute: completionWorkItem
        )
    }

    private func finishTransition() {
        isTransitioning = false
        let pending = pendingUpdate
        pendingUpdate = nil
        pending?()
    }

    deinit {
        completionWorkItem?.cancel()
        layer?.removeAnimation(forKey: "fluent.transition.cleanup")
    }

    private func install(_ entry: FluentTransitionEntry) {
        addSubview(entry)
        NSLayoutConstraint.activate([
            entry.leadingAnchor.constraint(equalTo: leadingAnchor),
            entry.trailingAnchor.constraint(equalTo: trailingAnchor),
            entry.topAnchor.constraint(equalTo: topAnchor),
            entry.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        entry.restoreContentTransforms()
    }
}

private final class FluentTransitionCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        completion()
    }
}

private final class FluentTransitionEntry: NSView {
    let content: NSView
    private let preservedTransforms: [(NSView, CGAffineTransform)]

    init(content: NSView) {
        self.content = content
        preservedTransforms = fluentCaptureLayerTransforms(in: content)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        fluentRestoreLayerTransforms(preservedTransforms)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func restoreContentTransforms() {
        fluentRestoreLayerTransforms(preservedTransforms)
    }

    func apply(_ state: FluentTransitionVisualState) {
        alphaValue = state.opacity
        if state.isIdentity {
            layer?.setAffineTransform(.identity)
        } else {
            wantsLayer = true
            layer?.setAffineTransform(state.transform)
        }
        restoreContentTransforms()
    }

    func animate(to state: FluentTransitionVisualState) {
        animator().alphaValue = state.opacity
        animator().layer?.setAffineTransform(state.transform)
        restoreContentTransforms()
    }
}

public struct FluentAnimationView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let animation: FluentAnimationTransaction

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        view.wantsLayer = true
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard !context.reduceMotion else {
            return content._update(view, in: context)
        }
        var didUpdate = false
        NSAnimationContext.runAnimationGroup { animationContext in
            animationContext.duration = animation.duration
            animationContext.allowsImplicitAnimation = true
            CATransaction.begin()
            CATransaction.setAnimationDuration(animation.duration)
            CATransaction.setAnimationTimingFunction(animation.timingFunction)
            didUpdate = content._update(view, in: context)
            view.needsLayout = true
            view.needsDisplay = true
            CATransaction.commit()
        }
        return didUpdate
    }
}

public extension FluentView {
    func fluentAnimation(_ animation: FluentAnimationTransaction) -> FluentAnimationView<Self> {
        FluentAnimationView(content: self, animation: animation)
    }

    func transition(
        _ transition: FluentTransition,
        animation: FluentAnimationTransaction = FluentAnimationTransaction()
    ) -> FluentTransitionView<Self> {
        FluentTransitionView(content: self, transition: transition, animation: animation)
    }
}
