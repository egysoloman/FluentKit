import AppKit

/// A unique scope for matched-geometry identifiers.
public struct FluentMatchedGeometryNamespace: Hashable, Sendable {
    fileprivate let rawValue: UUID

    public init() { rawValue = UUID() }
}

/// Declares a stable matched-geometry namespace as part of a declarative view value.
@propertyWrapper
public final class FluentNamespace {
    public let wrappedValue: FluentMatchedGeometryNamespace

    public init() { wrappedValue = FluentMatchedGeometryNamespace() }
}

/// Selects the choreography used when a matched marker moves between declarative branches.
public enum FluentMatchedGeometryConfiguration: Hashable, Sendable {
    case automatic
    case direct
    case gravity

    public var motion: FluentMotionToken {
        switch self {
        case .automatic: return FluentMotion.connectedDefault
        case .direct: return FluentMotion.connectedDirect
        case .gravity: return FluentMotion.connectedGravity
        }
    }
}

/// Marks a view as a participant in a cross-branch geometry animation.
///
/// The identifier is local to the supplied namespace. A transition host pairs matching markers
/// in its outgoing and incoming entries and animates the incoming marker from the old frame and
/// size to its new layout frame.
public struct FluentMatchedGeometryView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let id: AnyHashable
    fileprivate let namespace: FluentMatchedGeometryNamespace
    fileprivate let configuration: FluentMatchedGeometryConfiguration

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentMatchedGeometryHost(
            id: id,
            namespace: namespace,
            configuration: configuration,
            content: content._mount(in: context)
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentMatchedGeometryHost else { return false }
        return content._update(host.content, in: context)
    }
}

public extension FluentView {
    /// Participates in geometry interpolation with another view carrying the same identifier and
    /// namespace during a branch transition.
    func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: FluentMatchedGeometryNamespace,
        configuration: FluentMatchedGeometryConfiguration = .automatic
    ) -> FluentMatchedGeometryView<Self> {
        FluentMatchedGeometryView(
            content: self,
            id: AnyHashable(id),
            namespace: namespace,
            configuration: configuration
        )
    }
}

struct FluentMatchedGeometryKey: Hashable {
    let id: AnyHashable
    let namespace: FluentMatchedGeometryNamespace
}

final class FluentMatchedGeometryHost: NSView {
    let key: FluentMatchedGeometryKey
    let configuration: FluentMatchedGeometryConfiguration
    let content: NSView
    private let preservedTransforms: [(NSView, CGAffineTransform)]

    init(
        id: AnyHashable,
        namespace: FluentMatchedGeometryNamespace,
        configuration: FluentMatchedGeometryConfiguration,
        content: NSView
    ) {
        key = FluentMatchedGeometryKey(id: id, namespace: namespace)
        self.configuration = configuration
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
}

func fluentCaptureLayerTransforms(in root: NSView) -> [(NSView, CGAffineTransform)] {
    var transforms: [(NSView, CGAffineTransform)] = []
    if let transform = root.layer?.affineTransform() { transforms.append((root, transform)) }
    for child in root.subviews { transforms.append(contentsOf: fluentCaptureLayerTransforms(in: child)) }
    return transforms
}

func fluentRestoreLayerTransforms(_ transforms: [(NSView, CGAffineTransform)]) {
    for (view, transform) in transforms {
        view.wantsLayer = true
        view.layer?.setAffineTransform(transform)
    }
}

private func matchedGeometryHosts(in view: NSView) -> [FluentMatchedGeometryHost] {
    var hosts: [FluentMatchedGeometryHost] = []
    if let host = view as? FluentMatchedGeometryHost { hosts.append(host) }
    for child in view.subviews { hosts.append(contentsOf: matchedGeometryHosts(in: child)) }
    return hosts
}

struct FluentPreparedMatchedGeometry {
    let view: NSView
    let initialTransform: CGAffineTransform
    let configuration: FluentMatchedGeometryConfiguration

    var duration: TimeInterval { configuration.motion.duration }
}

/// Prepares incoming markers for a matched-geometry animation and returns the views that need to
/// be animated back to their laid-out state. The coordinate conversion is performed in the stable
/// transition host, so unrelated content transforms do not affect the computed delta.
func fluentPrepareMatchedGeometry(
    from old: NSView,
    to incoming: NSView,
    in coordinateView: NSView
) -> [FluentPreparedMatchedGeometry] {
    coordinateView.layoutSubtreeIfNeeded()
    let oldHosts = matchedGeometryHosts(in: old)
    let incomingHosts = matchedGeometryHosts(in: incoming)
    let oldByKey = Dictionary(oldHosts.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    var prepared: [FluentPreparedMatchedGeometry] = []

    for incomingHost in incomingHosts {
        guard let oldHost = oldByKey[incomingHost.key] else { continue }
        oldHost.layoutSubtreeIfNeeded()
        incomingHost.layoutSubtreeIfNeeded()
        let oldFrame = oldHost.convert(oldHost.bounds, to: coordinateView)
        let incomingFrame = incomingHost.convert(incomingHost.bounds, to: coordinateView)
        guard oldFrame.width > 0, oldFrame.height > 0,
              incomingFrame.width > 0, incomingFrame.height > 0 else { continue }

        let scaleX = oldFrame.width / incomingFrame.width
        let scaleY = oldFrame.height / incomingFrame.height
        let translationX = oldFrame.midX - incomingFrame.midX
        let translationY = oldFrame.midY - incomingFrame.midY
        let transform = CGAffineTransform(translationX: translationX, y: translationY)
            .scaledBy(x: scaleX, y: scaleY)
        incomingHost.wantsLayer = true
        incomingHost.layer?.setAffineTransform(transform)
        prepared.append(
            FluentPreparedMatchedGeometry(
                view: incomingHost,
                initialTransform: transform,
                configuration: incomingHost.configuration
            )
        )
    }
    return prepared
}

func fluentAnimateMatchedGeometry(_ preparedViews: [FluentPreparedMatchedGeometry]) {
    for prepared in preparedViews {
        guard let layer = prepared.view.layer else { continue }
        let motion = prepared.configuration.motion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(.identity)
        layer.shadowOpacity = 0
        CATransaction.commit()

        let transformAnimation: CAPropertyAnimation
        switch prepared.configuration {
        case .automatic, .direct:
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: CATransform3DMakeAffineTransform(prepared.initialTransform))
            animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            animation.timingFunction = motion.curve.timingFunction
            transformAnimation = animation
        case .gravity:
            let intermediate = fluentInterpolate(
                from: prepared.initialTransform,
                to: .identity,
                progress: 0.66
            )
            let peak = intermediate
                .translatedBy(x: 0, y: motion.distance)
                .scaledBy(x: motion.scale, y: motion.scale)
            let animation = CAKeyframeAnimation(keyPath: "transform")
            animation.values = [
                NSValue(caTransform3D: CATransform3DMakeAffineTransform(prepared.initialTransform)),
                NSValue(caTransform3D: CATransform3DMakeAffineTransform(peak)),
                NSValue(caTransform3D: CATransform3DIdentity)
            ]
            animation.keyTimes = [NSNumber(value: 0), NSNumber(value: 0.66), NSNumber(value: 1)]
            animation.timingFunctions = [
                FluentCubicBezier.direct.timingFunction,
                FluentCubicBezier.connectedDefault.timingFunction
            ]
            transformAnimation = animation

            layer.shadowColor = NSColor.black.cgColor
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: -4)
            let shadow = CAKeyframeAnimation(keyPath: "shadowOpacity")
            shadow.values = [0, 0.24, 0]
            shadow.keyTimes = animation.keyTimes
            shadow.timingFunctions = animation.timingFunctions
            shadow.duration = motion.duration
            layer.add(shadow, forKey: "fluent.connected.gravity.shadow")
        }

        transformAnimation.duration = motion.duration
        transformAnimation.isRemovedOnCompletion = true
        layer.add(transformAnimation, forKey: "fluent.connected.transform")
    }
}

private func fluentInterpolate(
    from start: CGAffineTransform,
    to end: CGAffineTransform,
    progress: CGFloat
) -> CGAffineTransform {
    let fraction = min(max(progress, 0), 1)
    func value(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        first + (second - first) * fraction
    }
    return CGAffineTransform(
        a: value(start.a, end.a),
        b: value(start.b, end.b),
        c: value(start.c, end.c),
        d: value(start.d, end.d),
        tx: value(start.tx, end.tx),
        ty: value(start.ty, end.ty)
    )
}
