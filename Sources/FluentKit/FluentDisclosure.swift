import AppKit

/// The two directions exposed by WinUI's `Expander.ExpandDirection` property.
public enum FluentExpandDirection: Hashable, Sendable {
    case down
    case up
}

/// A source-aligned WinUI Expander with a templated header and arbitrary Fluent content.
public struct FluentExpanderView<Header: FluentView, Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<Bool>?
    fileprivate let expandDirection: FluentExpandDirection
    fileprivate let isEnabled: Bool
    fileprivate let accessibilityLabel: String?
    fileprivate let onExpanding: (() -> Void)?
    fileprivate let onCollapsed: (() -> Void)?
    fileprivate let header: Header
    fileprivate let content: Content

    public init(
        isExpanded: FluentBinding<Bool>? = nil,
        expandDirection: FluentExpandDirection = .down,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        onExpanding: (() -> Void)? = nil,
        onCollapsed: (() -> Void)? = nil,
        @FluentViewBuilder header: () -> Header,
        @FluentViewBuilder content: () -> Content
    ) {
        binding = isExpanded
        self.expandDirection = expandDirection
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.onExpanding = onExpanding
        self.onCollapsed = onCollapsed
        self.header = header()
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentExpanderHost(
            binding: binding,
            expandDirection: expandDirection,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel,
            onExpanding: onExpanding,
            onCollapsed: onCollapsed,
            headerView: header._mount(in: context),
            contentView: content._mount(in: context),
            context: context
        )
        host.updateHeader = { [header] nativeView, updateContext in
            header._update(nativeView, in: updateContext)
        }
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentExpanderHost,
              header._update(host.headerContentView, in: context),
              content._update(host.contentView, in: context) else { return false }
        host.update(
            binding: binding,
            expandDirection: expandDirection,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel,
            onExpanding: onExpanding,
            onCollapsed: onCollapsed,
            context: context
        )
        return true
    }
}

/// Convenience overload for the common text-header form of WinUI Expander.
public func FluentExpander<Content: FluentView>(
    _ title: String,
    isExpanded: FluentBinding<Bool>? = nil,
    expandDirection: FluentExpandDirection = .down,
    isEnabled: Bool = true,
    onExpanding: (() -> Void)? = nil,
    onCollapsed: (() -> Void)? = nil,
    @FluentViewBuilder content: () -> Content
) -> FluentExpanderView<FluentTextView, Content> {
    FluentExpanderView(
        isExpanded: isExpanded,
        expandDirection: expandDirection,
        isEnabled: isEnabled,
        accessibilityLabel: title,
        onExpanding: onExpanding,
        onCollapsed: onCollapsed,
        header: { FluentText(title, style: .body) },
        content: content
    )
}

/// Compatibility wrapper for FluentKit's original disclosure-group spelling.
public struct FluentDisclosureGroupView<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let expander: FluentExpanderView<FluentTextView, Content>

    public init(
        _ title: String,
        isExpanded: FluentBinding<Bool>? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        expander = FluentExpander(
            title,
            isExpanded: isExpanded,
            content: content
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        expander._makeView(in: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        expander._updateView(view, in: context)
    }
}

public func FluentDisclosureGroup<Content: FluentView>(
    _ title: String,
    isExpanded: FluentBinding<Bool>? = nil,
    @FluentViewBuilder content: () -> Content
) -> FluentDisclosureGroupView<Content> {
    FluentDisclosureGroupView(title, isExpanded: isExpanded, content: content)
}

private enum FluentExpanderMetrics {
    static let minimumWidth: CGFloat = 96
    static let minimumHeight: CGFloat = 48
    static let headerLeading: CGFloat = 16
    static let chevronSize: CGFloat = 32
    static let chevronLeadingMargin: CGFloat = 20
    static let chevronTrailingMargin: CGFloat = 8
    static let contentPadding: CGFloat = 16
    static let chevronGlyphSize: CGFloat = 12
}

private final class FluentExpanderHeader: NSButton {
    let contentView: NSView
    var context: FluentRenderContext { didSet { updateAppearance(animated: false) } }
    var isExpanded = false { didSet { updateAppearance(animated: oldValue != isExpanded) } }
    var expandDirection: FluentExpandDirection = .down {
        didSet { updateAppearance(animated: oldValue != expandDirection) }
    }

    private let chevronLayer = FluentAnimatedChevronLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var pointerOver = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize {
        let size = resolvedContentSize()
        return NSSize(
            width: max(
                FluentExpanderMetrics.minimumWidth,
                FluentExpanderMetrics.headerLeading + size.width
                    + FluentExpanderMetrics.chevronLeadingMargin
                    + FluentExpanderMetrics.chevronSize
                    + FluentExpanderMetrics.chevronTrailingMargin
            ),
            height: max(FluentExpanderMetrics.minimumHeight, size.height)
        )
    }

    init(contentView: NSView, context: FluentRenderContext) {
        self.contentView = contentView
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Expander.Header")
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        contentView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(contentView)
        layer?.addSublayer(chevronLayer)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        pointerOver = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        updateAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        needsDisplay = true
        super.mouseDown(with: event)
        needsDisplay = true
        updateAppearance(animated: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { needsDisplay = true }
        return resigned
    }

    override func layout() {
        super.layout()
        let contentSize = resolvedContentSize()
        let isRTL = context.layoutDirection == .rightToLeft
        let trailingSpan = FluentExpanderMetrics.chevronLeadingMargin
            + FluentExpanderMetrics.chevronSize
            + FluentExpanderMetrics.chevronTrailingMargin
        let availableWidth = max(bounds.width - FluentExpanderMetrics.headerLeading - trailingSpan, 0)
        contentView.frame = NSRect(
            x: isRTL
                ? trailingSpan
                : FluentExpanderMetrics.headerLeading,
            y: floor(bounds.midY - contentSize.height / 2),
            width: availableWidth,
            height: min(contentSize.height, bounds.height)
        )
        let chevronFrame = CGRect(
            x: isRTL
                ? FluentExpanderMetrics.chevronTrailingMargin
                : bounds.maxX - FluentExpanderMetrics.chevronTrailingMargin
                    - FluentExpanderMetrics.chevronSize,
            y: bounds.midY - FluentExpanderMetrics.chevronSize / 2,
            width: FluentExpanderMetrics.chevronSize,
            height: FluentExpanderMetrics.chevronSize
        )
        let glyphInset = (FluentExpanderMetrics.chevronSize - FluentExpanderMetrics.chevronGlyphSize) / 2
        chevronLayer.update(
            frame: chevronFrame.insetBy(dx: glyphInset, dy: glyphInset),
            color: isEnabled ? context.theme.textPrimary : context.theme.textDisabled,
            state: controlState,
            visual: .upDownSmall,
            direction: chevronDirection,
            backingScale: window?.backingScaleFactor,
            animated: !context.reduceMotion
        )
        contentView.alphaValue = isEnabled ? 1 : 0.45
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius = context.theme.designTokens.controlCornerRadius
        let corners: FluentExpanderCorners = if !isExpanded {
            .all
        } else if expandDirection == .down {
            .top
        } else {
            .bottom
        }
        drawExpanderSurface(
            in: bounds,
            fill: context.theme.cardFill,
            stroke: isEnabled ? context.theme.cardStroke : context.theme.textDisabled,
            strokeWidth: context.theme.controlStrokeWidth,
            radius: radius,
            corners: corners,
            omittedEdge: nil
        )

        if pointerOver || isHighlighted {
            let isRTL = context.layoutDirection == .rightToLeft
            let chevronRect = NSRect(
                x: isRTL
                    ? FluentExpanderMetrics.chevronTrailingMargin
                    : bounds.maxX - FluentExpanderMetrics.chevronTrailingMargin
                        - FluentExpanderMetrics.chevronSize,
                y: bounds.midY - FluentExpanderMetrics.chevronSize / 2,
                width: FluentExpanderMetrics.chevronSize,
                height: FluentExpanderMetrics.chevronSize
            )
            let fill = isHighlighted
                ? context.theme.subtleFillTertiary
                : context.theme.subtleFillSecondary
            fill.setFill()
            NSBezierPath(
                roundedRect: chevronRect,
                xRadius: radius,
                yRadius: radius
            ).fill()
        }

        if window?.firstResponder === self {
            context.theme.accent.setStroke()
            let focus = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                xRadius: max(radius - 1, 0),
                yRadius: max(radius - 1, 0)
            )
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    func updateAppearance(animated: Bool) {
        needsDisplay = true
        needsLayout = true
        layoutSubtreeIfNeeded()
        if !animated || context.reduceMotion {
            chevronLayer.removeAllAnimations()
        }
    }

    private var controlState: FluentControlState {
        if !isEnabled { return .disabled }
        if isHighlighted { return .pressed }
        return pointerOver ? .pointerOver : .normal
    }

    private var chevronDirection: FluentChevronDirection {
        let pointsUp = isExpanded == (expandDirection == .down)
        return pointsUp ? .up : .down
    }

    private func resolvedContentSize() -> NSSize {
        let intrinsic = contentView.intrinsicContentSize
        let fitting = contentView.fittingSize
        let width = intrinsic.width != NSView.noIntrinsicMetric ? intrinsic.width : fitting.width
        let height = intrinsic.height != NSView.noIntrinsicMetric ? intrinsic.height : fitting.height
        return NSSize(width: max(width, 0), height: max(height, 0))
    }
}

private final class FluentExpanderContentSurface: NSView {
    var context: FluentRenderContext { didSet { needsDisplay = true } }
    var direction: FluentExpandDirection = .down { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    init(context: FluentRenderContext) {
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Expander.Content")
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawExpanderSurface(
            in: bounds,
            fill: context.theme.cardFillSecondary,
            stroke: context.theme.cardStroke,
            strokeWidth: context.theme.controlStrokeWidth,
            radius: context.theme.designTokens.controlCornerRadius,
            corners: direction == .down ? .bottom : .top,
            omittedEdge: direction == .down ? .top : .bottom
        )
    }
}

private final class FluentExpanderHost: NSView, FluentFillWidthProviding {
    let headerContentView: NSView
    let contentView: NSView
    var updateHeader: ((NSView, FluentRenderContext) -> Bool)?
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?

    private let header: FluentExpanderHeader
    private let contentClip = NSView()
    private let contentSurface: FluentExpanderContentSurface
    private var binding: FluentBinding<Bool>?
    private var bindingObserverID: UUID?
    private var isWritingBinding = false
    private var context: FluentRenderContext
    private var expandDirection: FluentExpandDirection
    private var enabled: Bool
    private var explicitAccessibilityLabel: String?
    private var onExpanding: (() -> Void)?
    private var onCollapsed: (() -> Void)?
    private var expanded: Bool
    private var contentParticipatesInLayout: Bool
    private var transitionGeneration: UInt64 = 0
    private let animationCoordinator = FluentAnimationCoordinator()

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        let headerSize = header.intrinsicContentSize
        let contentSize = measuredContentSurfaceSize()
        return NSSize(
            width: max(
                FluentExpanderMetrics.minimumWidth,
                max(headerSize.width, contentSize.width)
            ),
            height: FluentExpanderMetrics.minimumHeight
                + (contentParticipatesInLayout ? contentSize.height : 0)
        )
    }

    init(
        binding: FluentBinding<Bool>?,
        expandDirection: FluentExpandDirection,
        isEnabled: Bool,
        accessibilityLabel: String?,
        onExpanding: (() -> Void)?,
        onCollapsed: (() -> Void)?,
        headerView: NSView,
        contentView: NSView,
        context: FluentRenderContext
    ) {
        self.binding = binding
        self.expandDirection = expandDirection
        enabled = isEnabled
        explicitAccessibilityLabel = accessibilityLabel
        self.onExpanding = onExpanding
        self.onCollapsed = onCollapsed
        headerContentView = headerView
        self.contentView = contentView
        self.context = context
        expanded = binding?.get() ?? false
        contentParticipatesInLayout = expanded
        header = FluentExpanderHeader(contentView: headerView, context: context)
        contentSurface = FluentExpanderContentSurface(context: context)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Expander")
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Natural content width is a measure preference, not a required allocation. A frame
        // or full-width stack must be able to constrain long header/body text to its row.
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        animationCoordinator.reduceMotion = context.reduceMotion
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue

        contentClip.identifier = NSUserInterfaceItemIdentifier("FluentKit.Expander.ContentClip")
        contentClip.wantsLayer = true
        contentClip.layer?.masksToBounds = true
        contentClip.translatesAutoresizingMaskIntoConstraints = true
        contentSurface.translatesAutoresizingMaskIntoConstraints = true
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentClip.addSubview(contentSurface)
        contentSurface.addSubview(contentView)
        addSubview(header)
        addSubview(contentClip)

        header.target = self
        header.action = #selector(toggleFromHeader)
        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
        installBindingObserver()
        applyState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let contentHeight = measuredContentSurfaceSize().height
        let headerY = expandDirection == .up && contentParticipatesInLayout ? contentHeight : 0
        header.frame = NSRect(
            x: 0,
            y: headerY,
            width: bounds.width,
            height: FluentExpanderMetrics.minimumHeight
        )
        let contentY = expandDirection == .down ? FluentExpanderMetrics.minimumHeight : 0
        contentClip.frame = NSRect(x: 0, y: contentY, width: bounds.width, height: contentHeight)
        contentSurface.frame = contentClip.bounds
        let desired = measuredContentViewSize()
        contentView.frame = NSRect(
            x: FluentExpanderMetrics.contentPadding,
            y: FluentExpanderMetrics.contentPadding,
            width: max(contentSurface.bounds.width - 2 * FluentExpanderMetrics.contentPadding, 0),
            height: min(
                desired.height,
                max(contentSurface.bounds.height - 2 * FluentExpanderMetrics.contentPadding, 0)
            )
        )
        header.layoutSubtreeIfNeeded()
        contentView.layoutSubtreeIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        toggleFromHeader()
        return true
    }

    override func accessibilityChildren() -> [Any]? {
        expanded ? [contentView] : []
    }

    func update(
        binding: FluentBinding<Bool>?,
        expandDirection: FluentExpandDirection,
        isEnabled: Bool,
        accessibilityLabel: String?,
        onExpanding: (() -> Void)?,
        onCollapsed: (() -> Void)?,
        context: FluentRenderContext
    ) {
        let bindingChanged = binding?.observationIdentity != self.binding?.observationIdentity
            || (binding?.observationIdentity == nil) != (self.binding?.observationIdentity == nil)
        if bindingChanged, let bindingObserverID {
            self.binding?.removeObserver?(bindingObserverID)
            self.bindingObserverID = nil
        }
        self.binding = binding
        self.expandDirection = expandDirection
        enabled = isEnabled
        explicitAccessibilityLabel = accessibilityLabel
        self.onExpanding = onExpanding
        self.onCollapsed = onCollapsed
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        header.context = context
        header.expandDirection = expandDirection
        header.isEnabled = isEnabled
        contentSurface.context = context
        contentSurface.direction = expandDirection
        installBindingObserver()
        if let binding, binding.get() != expanded {
            setExpanded(binding.get(), animated: window != nil, writesBinding: false)
        } else {
            refreshStaticState()
        }
        invalidateExpanderLayout()
    }

    @objc private func toggleFromHeader() {
        guard enabled else { return }
        setExpanded(!expanded, animated: true, writesBinding: true)
    }

    private func installBindingObserver() {
        guard bindingObserverID == nil, let binding else { return }
        bindingObserverID = binding.observe { [weak self] value in
            guard let self, !self.isWritingBinding else { return }
            let apply: () -> Void = { [weak self] in
                self?.setExpanded(value, animated: true, writesBinding: false)
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func setExpanded(_ value: Bool, animated: Bool, writesBinding: Bool) {
        guard value != expanded else { return }
        if value { onExpanding?() }
        expanded = value
        if writesBinding, let binding, binding.get() != value {
            isWritingBinding = true
            binding.set(value)
            isWritingBinding = false
        }
        applyState(animated: animated)
        if !value { onCollapsed?() }
    }

    private func applyState(animated: Bool) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        animationCoordinator.cancelAll(on: [contentSurface.layer].compactMap { $0 })
        let shouldAnimate = animated && window != nil && !context.reduceMotion
        let height = measuredContentSurfaceSize().height
        header.isExpanded = expanded
        header.expandDirection = expandDirection
        contentSurface.direction = expandDirection

        if expanded {
            contentParticipatesInLayout = true
            contentClip.isHidden = false
            contentSurface.isHidden = false
            invalidateExpanderLayout()
            layoutSubtreeIfNeeded()
            let sourceOffset = expandDirection == .down ? -height : height
            animateContent(
                from: CATransform3DMakeTranslation(0, sourceOffset, 0),
                to: CATransform3DIdentity,
                motion: FluentMotion.expanderExpand,
                animated: shouldAnimate,
                completion: nil
            )
        } else {
            guard contentParticipatesInLayout else {
                contentClip.isHidden = true
                contentSurface.isHidden = true
                refreshStaticState()
                return
            }
            let targetOffset = expandDirection == .down ? -height : height
            animateContent(
                from: nil,
                to: CATransform3DMakeTranslation(0, targetOffset, 0),
                motion: FluentMotion.expanderCollapse,
                animated: shouldAnimate
            ) { [weak self] in
                guard let self, self.transitionGeneration == generation, !self.expanded else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.contentSurface.layer?.transform = CATransform3DIdentity
                CATransaction.commit()
                self.contentParticipatesInLayout = false
                self.contentClip.isHidden = true
                self.contentSurface.isHidden = true
                self.invalidateExpanderLayout()
            }
        }
        updateAccessibilityState()
    }

    private func animateContent(
        from: CATransform3D?,
        to: CATransform3D,
        motion: FluentMotionToken,
        animated: Bool,
        completion: (() -> Void)?
    ) {
        guard let layer = contentSurface.layer else {
            completion?()
            return
        }
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: layer,
                    key: "fluent.expander.content.translation",
                    keyPath: "transform",
                    fromValue: from.map { NSValue(caTransform3D: $0) },
                    toValue: NSValue(caTransform3D: to),
                    applyModelValue: { layer.transform = to }
                )
            ],
            motion: motion,
            animated: animated,
            completion: completion
        )
    }

    private func refreshStaticState() {
        header.isExpanded = expanded
        header.expandDirection = expandDirection
        header.isEnabled = enabled
        contentSurface.direction = expandDirection
        contentClip.isHidden = !contentParticipatesInLayout
        contentSurface.isHidden = !contentParticipatesInLayout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentSurface.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        updateAccessibilityState()
        needsDisplay = true
        needsLayout = true
    }

    private func updateAccessibilityState() {
        setAccessibilityLabel(explicitAccessibilityLabel ?? "Expander")
        setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
        setAccessibilityEnabled(enabled)
        setAccessibilityChildren(expanded ? [contentView] : [])
    }

    private func measuredContentViewSize() -> NSSize {
        let intrinsic = contentView.intrinsicContentSize
        let fitting = contentView.fittingSize
        let width = intrinsic.width != NSView.noIntrinsicMetric ? intrinsic.width : fitting.width
        let height = intrinsic.height != NSView.noIntrinsicMetric ? intrinsic.height : fitting.height
        return NSSize(width: max(width, 0), height: max(height, 0))
    }

    private func measuredContentSurfaceSize() -> NSSize {
        let content = measuredContentViewSize()
        return NSSize(
            width: max(
                FluentExpanderMetrics.minimumWidth,
                content.width + 2 * FluentExpanderMetrics.contentPadding
            ),
            height: max(
                FluentExpanderMetrics.minimumHeight,
                content.height + 2 * FluentExpanderMetrics.contentPadding
            )
        )
    }

    private func invalidateExpanderLayout() {
        var current: NSView? = self
        while let view = current {
            view.invalidateIntrinsicContentSize()
            view.needsLayout = true
            current = view.superview
        }
        superview?.layoutSubtreeIfNeeded()
    }

    deinit {
        if let bindingObserverID { binding?.removeObserver?(bindingObserverID) }
    }
}

private enum FluentExpanderCorners {
    case all
    case top
    case bottom
}

private enum FluentExpanderOmittedEdge {
    case top
    case bottom
}

private func expanderSurfacePath(
    in rect: CGRect,
    radius: CGFloat,
    corners: FluentExpanderCorners
) -> CGPath {
    let r = min(max(radius, 0), min(rect.width, rect.height) / 2)
    let topRadius = corners == .all || corners == .top ? r : 0
    let bottomRadius = corners == .all || corners == .bottom ? r : 0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
    if topRadius > 0 {
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
    if bottomRadius > 0 {
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
    }
    path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
    if bottomRadius > 0 {
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
    }
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
    if topRadius > 0 {
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
    }
    path.closeSubpath()
    return path
}

private func drawExpanderSurface(
    in bounds: CGRect,
    fill: NSColor,
    stroke: NSColor,
    strokeWidth: CGFloat,
    radius: CGFloat,
    corners: FluentExpanderCorners,
    omittedEdge: FluentExpanderOmittedEdge?
) {
    guard let graphics = NSGraphicsContext.current?.cgContext else { return }
    let inset = strokeWidth / 2
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let path = expanderSurfacePath(in: rect, radius: max(radius - inset, 0), corners: corners)
    graphics.saveGState()
    graphics.addPath(path)
    graphics.setFillColor(fill.cgColor)
    graphics.fillPath()
    graphics.addPath(path)
    graphics.setStrokeColor(stroke.cgColor)
    graphics.setLineWidth(strokeWidth)
    graphics.strokePath()
    if let omittedEdge {
        graphics.setStrokeColor(fill.cgColor)
        graphics.setLineWidth(strokeWidth + 1)
        let y = omittedEdge == .top ? rect.minY : rect.maxY
        graphics.move(to: CGPoint(x: rect.minX + strokeWidth, y: y))
        graphics.addLine(to: CGPoint(x: rect.maxX - strokeWidth, y: y))
        graphics.strokePath()
    }
    graphics.restoreGState()
}
