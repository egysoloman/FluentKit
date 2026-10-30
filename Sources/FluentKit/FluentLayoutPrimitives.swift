import AppKit

/// The WinUI Canvas attached-property pair carried by a positioned declarative child.
///
/// Canvas.Left and Canvas.Top are stored on the mounted native view so heterogeneous children can
/// flow through `FluentAnyView` without introducing a second type-erased wrapper.
private struct FluentCanvasPosition: Equatable {
    var x: CGFloat
    var y: CGFloat

    static let zero = FluentCanvasPosition(x: 0, y: 0)
}

private var fluentCanvasPositionKey: UInt8 = 0

private extension NSView {
    var fluentCanvasPosition: FluentCanvasPosition {
        get {
            (objc_getAssociatedObject(self, &fluentCanvasPositionKey) as? NSValue)
                .flatMap { value -> FluentCanvasPosition? in
                    let point = value.pointValue
                    return FluentCanvasPosition(x: point.x, y: point.y)
                } ?? .zero
        }
        set {
            objc_setAssociatedObject(
                self,
                &fluentCanvasPositionKey,
                NSValue(point: NSPoint(x: newValue.x, y: newValue.y)),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

func fluentNaturalSize(of child: NSView, forceLayout: Bool = true) -> NSSize {
    if forceLayout {
        child.layoutSubtreeIfNeeded()
    }
    var size = child.intrinsicContentSize
    if size.width == NSView.noIntrinsicMetric {
        size.width = child.fittingSize.width
    }
    if size.height == NSView.noIntrinsicMetric {
        size.height = child.fittingSize.height
    }
    return NSSize(width: max(0, size.width), height: max(0, size.height))
}

/// Wraps a view with WinUI-style `Canvas.Left` and `Canvas.Top` layout offsets.
public struct FluentCanvasPositionedView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let position: FluentCanvasPosition

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        view.fluentCanvasPosition = position
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        view.fluentCanvasPosition = position
        view.superview?.needsLayout = true
        return content._update(view, in: context)
    }
}

public extension FluentView {
    /// Sets the `Canvas.Left` and `Canvas.Top` offsets applied by an enclosing `FluentCanvas`.
    func canvasPosition(x: CGFloat = 0, y: CGFloat = 0) -> FluentCanvasPositionedView<Self> {
        FluentCanvasPositionedView(content: self, position: FluentCanvasPosition(x: x, y: y))
    }
}

/// A WinUI Canvas: children are positioned by absolute top-left offsets and are not clipped to
/// the Canvas bounds. The Canvas itself contributes a zero desired size and relies on an
/// explicit layout slot, matching `CCanvas::MeasureOverride` and `CCanvas::ArrangeOverride`.
public struct FluentCanvasView: FluentUpdatablePrimitiveView {
    fileprivate let content: FluentAnyView

    fileprivate init(content: FluentAnyView) { self.content = content }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentCanvasHost()
        let children = content.children?.map { $0.mount(context) } ?? [content.mount(context)]
        host.setChildren(children)
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentCanvasHost else { return false }
        let children = content.children ?? [content]
        guard host.subviews.count == children.count else { return false }

        for index in children.indices {
            let nativeChild = host.subviews[index]
            let child = children[index]
            if !child._update(nativeChild, in: context) {
                host.replaceChild(at: index, with: child.mount(context))
            } else {
                host.applyPosition(for: nativeChild)
            }
        }
        return true
    }
}

public func FluentCanvas<Content: FluentView>(@FluentViewBuilder content: () -> Content) -> FluentCanvasView {
    FluentCanvasView(content: FluentAnyView(content()))
}

private final class FluentCanvasHost: NSView {
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { .zero }

    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Canvas")
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("Canvas")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setChildren(_ children: [NSView]) {
        children.forEach { child in
            addSubview(child)
            applyPosition(for: child)
        }
        needsLayout = true
    }

    func replaceChild(at index: Int, with child: NSView) {
        guard subviews.indices.contains(index) else { return }
        subviews[index].removeFromSuperview()
        addSubview(child, positioned: .above, relativeTo: index == 0 ? nil : subviews[index - 1])
        applyPosition(for: child)
        needsLayout = true
    }

    func applyPosition(for child: NSView) {
        child.needsLayout = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for child in subviews {
            let position = child.fluentCanvasPosition
            child.frame = NSRect(
                origin: NSPoint(x: position.x, y: position.y),
                size: fluentNaturalSize(of: child)
            )
        }
    }
}

/// The WinUI Viewbox.Stretch values.
public enum FluentViewboxStretch: Hashable, Sendable {
    case none
    case uniform
    case fill
    case uniformToFill
}

/// The WinUI Viewbox.StretchDirection values.
public enum FluentViewboxStretchDirection: Hashable, Sendable {
    case both
    case upOnly
    case downOnly
}

/// A WinUI Viewbox: a single-child container that scales its natural-size child to the available
/// slot using `Stretch` and `StretchDirection`. The child is arranged at its natural size and the
/// scale is applied from the visual top-left, matching the WinUI ScaleTransform defaults.
public struct FluentViewbox<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let stretch: FluentViewboxStretch
    fileprivate let stretchDirection: FluentViewboxStretchDirection

    public init(
        stretch: FluentViewboxStretch = .uniform,
        stretchDirection: FluentViewboxStretchDirection = .both,
        @FluentViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.stretch = stretch
        self.stretchDirection = stretchDirection
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentViewboxHost(
            contentView: content._mount(in: context),
            stretch: stretch,
            stretchDirection: stretchDirection
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentViewboxHost,
              content._update(host.contentView, in: context) else { return false }
        host.update(stretch: stretch, stretchDirection: stretchDirection)
        return true
    }
}

private final class FluentViewboxHost: NSView {
    let contentView: NSView
    private var stretch: FluentViewboxStretch
    private var stretchDirection: FluentViewboxStretchDirection

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        // WinUI measures the child against an infinite constraint, where ComputeScaleFactor
        // leaves the scale at one and the Viewbox desired size is the child's natural size.
        // Reading this property happens while AppKit is solving constraints, so forcing a full
        // subtree layout here would re-enter constraint solving and recurse indefinitely.
        fluentNaturalSize(of: contentView, forceLayout: false)
    }

    init(
        contentView: NSView,
        stretch: FluentViewboxStretch,
        stretchDirection: FluentViewboxStretchDirection
    ) {
        self.contentView = contentView
        self.stretch = stretch
        self.stretchDirection = stretchDirection
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Viewbox")
        translatesAutoresizingMaskIntoConstraints = false
        // The child's natural size is the Viewbox *desired* size, not a hard requirement:
        // WinUI recomputes the scale for the slot it is actually given. Keep the intrinsic
        // weakly compressible/stretchable so a fixed layout slot can shrink or expand it.
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Viewbox")
        contentView.wantsLayer = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(stretch: FluentViewboxStretch, stretchDirection: FluentViewboxStretchDirection) {
        self.stretch = stretch
        self.stretchDirection = stretchDirection
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let naturalSize = fluentNaturalSize(of: contentView)
        let scale = resolvedScale(availableSize: bounds.size, naturalSize: naturalSize)
        contentView.frame = NSRect(origin: .zero, size: naturalSize)
        contentView.layer?.anchorPoint = CGPoint.zero
        // Re-establish the frame after moving the anchor point so AppKit keeps the top-left
        // corner at the origin, then scale around that corner.
        contentView.frame = NSRect(origin: .zero, size: naturalSize)
        contentView.layer?.setAffineTransform(
            CGAffineTransform(scaleX: scale.width, y: scale.height)
        )
    }

    private func resolvedScale(availableSize: NSSize, naturalSize: NSSize) -> NSSize {
        guard stretch != .none else { return NSSize(width: 1, height: 1) }

        let constrainedWidth = availableSize.width.isFinite
        let constrainedHeight = availableSize.height.isFinite
        guard constrainedWidth || constrainedHeight else {
            return NSSize(width: 1, height: 1)
        }

        var scaleX: CGFloat = naturalSize.width <= 0 ? 0 : availableSize.width / naturalSize.width
        var scaleY: CGFloat = naturalSize.height <= 0 ? 0 : availableSize.height / naturalSize.height

        if !constrainedWidth {
            scaleX = scaleY
        } else if !constrainedHeight {
            scaleY = scaleX
        } else {
            switch stretch {
            case .uniform:
                let scale = min(scaleX, scaleY)
                scaleX = scale
                scaleY = scale
            case .uniformToFill:
                let scale = max(scaleX, scaleY)
                scaleX = scale
                scaleY = scale
            case .fill, .none:
                break
            }
        }

        switch stretchDirection {
        case .upOnly:
            scaleX = max(1, scaleX)
            scaleY = max(1, scaleY)
        case .downOnly:
            scaleX = min(1, scaleX)
            scaleY = min(1, scaleY)
        case .both:
            break
        }

        return NSSize(width: scaleX, height: scaleY)
    }
}
