import AppKit

/// `ParallaxSourceOffsetKind`: Relative offsets are measured from the source's natural start and
/// end of scrolling; Absolute offsets are raw scroll positions.
public enum FluentParallaxSourceOffsetKind: Hashable, Sendable {
    case relative
    case absolute
}

/// Shift settings for one axis of a ParallaxView (WinUI's Horizontal*/Vertical* properties).
public struct FluentParallaxAxis: Hashable, Sendable {
    /// `VerticalShift`/`HorizontalShift`: how much farther the background travels than it is tall.
    public var shift: CGFloat
    public var sourceOffsetKind: FluentParallaxSourceOffsetKind
    public var sourceStartOffset: CGFloat
    public var sourceEndOffset: CGFloat
    public var isShiftClamped: Bool
    public var maxShiftRatio: CGFloat

    public init(
        shift: CGFloat = 0,
        sourceOffsetKind: FluentParallaxSourceOffsetKind = .relative,
        sourceStartOffset: CGFloat = 0,
        sourceEndOffset: CGFloat = 0,
        isShiftClamped: Bool = true,
        maxShiftRatio: CGFloat = 1
    ) {
        self.shift = shift
        self.sourceOffsetKind = sourceOffsetKind
        self.sourceStartOffset = sourceStartOffset
        self.sourceEndOffset = sourceEndOffset
        self.isShiftClamped = isShiftClamped
        self.maxShiftRatio = maxShiftRatio
    }
}

/// A WinUI-style ParallaxView behind scrolling content: the background is arranged larger than
/// the view by the shift and translated more slowly than the content as it scrolls (the usual
/// `ParallaxView.Source = ScrollViewer` arrangement). Works with trackpad, wheel, touch and elastic
/// overscroll because it follows the scroll position, not the input.
public struct FluentParallaxView<Background: FluentView, Content: FluentView>: FluentUpdatablePrimitiveView {
    private let horizontal: FluentParallaxAxis
    private let vertical: FluentParallaxAxis
    private let background: Background
    private let content: Content

    public init(
        horizontal: FluentParallaxAxis = FluentParallaxAxis(),
        vertical: FluentParallaxAxis = FluentParallaxAxis(),
        @FluentViewBuilder background: () -> Background,
        @FluentViewBuilder content: () -> Content
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.background = background()
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentParallaxControl(background: FluentAnyView(background), content: FluentAnyView(content),
                              horizontal: horizontal, vertical: vertical, context: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentParallaxControl else { return false }
        control.update(background: FluentAnyView(background), content: FluentAnyView(content),
                       horizontal: horizontal, vertical: vertical, context: context)
        return true
    }
}

enum FluentParallaxMath {
    /// `ScrollInputHelper::UpdateOutOfBoundsPanSize`: a non-zooming ScrollViewer under/overpans up
    /// to 10% of its viewport.
    static let outOfBoundsRatio: CGFloat = 0.1

    /// Source start/end offsets for a ParallaxView outside its source (`UpdateStart/EndOffsetExpression`).
    static func range(axis: FluentParallaxAxis, contentSize: CGFloat, viewportSize: CGFloat) -> (start: CGFloat, end: CGFloat) {
        switch axis.sourceOffsetKind {
        case .relative:
            let outOfBounds = viewportSize * outOfBoundsRatio
            return (axis.sourceStartOffset - outOfBounds,
                    max(0, contentSize + axis.sourceEndOffset - viewportSize) + outOfBounds)
        case .absolute:
            return (axis.sourceStartOffset, axis.sourceEndOffset)
        }
    }

    /// `UpdateExpressionAnimation`: P(X) = -min(maxRatio, shift / (end - start)) * (X - start),
    /// held at 0 before start and at -min(maxRatio * (end - start), shift) after end when clamped.
    static func translation(axis: FluentParallaxAxis, offset x: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard axis.shift != 0, end != start else { return 0 }
        let ratio = min(axis.maxShiftRatio, axis.shift / (end - start))
        if axis.isShiftClamped {
            if x <= start { return 0 }
            if x >= end { return -min(axis.maxShiftRatio * max(0, end - start), axis.shift) }
        }
        return -ratio * (x - start)
    }
}

final class FluentParallaxControl: NSView {
    override var isFlipped: Bool { true }

    private(set) var horizontal: FluentParallaxAxis
    private(set) var vertical: FluentParallaxAxis
    let backgroundClip = FluentParallaxFlippedView()
    let backgroundHost: FluentViewHost<FluentAnyView>
    let scrollView = NSScrollView()
    private let documentView = FluentParallaxFlippedView()
    let contentHost: FluentViewHost<FluentAnyView>
    private var boundsObserver: Any?

    init(background: FluentAnyView, content: FluentAnyView, horizontal: FluentParallaxAxis, vertical: FluentParallaxAxis,
         context: FluentRenderContext) {
        self.horizontal = horizontal
        self.vertical = vertical
        backgroundHost = FluentViewHost(background, context: context)
        contentHost = FluentViewHost(content, context: context)
        super.init(frame: .zero)
        // Hosts are laid out by frame; FluentViewHost otherwise opts out of autoresizing constraints.
        backgroundHost.translatesAutoresizingMaskIntoConstraints = true
        contentHost.translatesAutoresizingMaskIntoConstraints = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ParallaxView")
        backgroundClip.wantsLayer = true
        backgroundClip.layer?.masksToBounds = true
        backgroundClip.identifier = NSUserInterfaceItemIdentifier("FluentKit.ParallaxView.Background")
        backgroundClip.addSubview(backgroundHost)
        addSubview(backgroundClip)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        documentView.addSubview(contentHost)
        scrollView.documentView = documentView
        addSubview(scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: scrollView.contentView, queue: .main) { [weak self] _ in
            self?.applyParallax()
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    func update(background: FluentAnyView, content: FluentAnyView, horizontal: FluentParallaxAxis, vertical: FluentParallaxAxis,
                context: FluentRenderContext) {
        self.horizontal = horizontal
        self.vertical = vertical
        backgroundHost.update(background, context: context)
        contentHost.update(content, context: context)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        backgroundClip.frame = bounds
        scrollView.frame = bounds
        let viewport = scrollView.contentSize
        let fitting = contentHost.fittingSize
        documentView.frame = NSRect(x: 0, y: 0, width: max(viewport.width, fitting.width), height: max(viewport.height, fitting.height))
        contentHost.frame = documentView.bounds
        applyParallax()
    }

    /// The background is arranged at least `shift` larger than the view (`ArrangeOverride`).
    var backgroundSize: NSSize {
        NSSize(width: bounds.width + abs(horizontal.shift), height: bounds.height + abs(vertical.shift))
    }

    func applyParallax() {
        let origin = scrollView.contentView.bounds.origin
        let viewport = scrollView.contentView.bounds.size
        let document = documentView.frame.size
        let h = FluentParallaxMath.range(axis: horizontal, contentSize: document.width, viewportSize: viewport.width)
        let v = FluentParallaxMath.range(axis: vertical, contentSize: document.height, viewportSize: viewport.height)
        let dx = FluentParallaxMath.translation(axis: horizontal, offset: origin.x, start: h.start, end: h.end)
        let dy = FluentParallaxMath.translation(axis: vertical, offset: origin.y, start: v.start, end: v.end)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundHost.frame = NSRect(origin: NSPoint(x: dx, y: dy), size: backgroundSize)
        CATransaction.commit()
    }

    func scroll(to offset: NSPoint) {
        scrollView.contentView.setBoundsOrigin(offset)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        applyParallax()
    }
}

final class FluentParallaxFlippedView: NSView {
    override var isFlipped: Bool { true }
}
