import AppKit

/// A label placed on an AnnotatedScrollBar at a content scroll offset (`AnnotatedScrollBarLabel`).
public struct FluentAnnotatedScrollBarLabel: Hashable {
    public var text: String
    public var scrollOffset: CGFloat

    public init(_ text: String, scrollOffset: CGFloat) {
        self.text = text
        self.scrollOffset = scrollOffset
    }
}

/// `AnnotatedScrollBarScrollingEventKind`.
public enum FluentAnnotatedScrollBarScrollingKind: Hashable, Sendable {
    case click
    case drag
    case incrementButton
    case decrementButton
}

/// A vertically scrolling view paired with a WinUI-style AnnotatedScrollBar: labels at content
/// offsets along a rail, an accent thumb for the current position, a ghost thumb and an optional
/// detail label under the pointer, click/drag to jump, and step buttons.
///
/// `onScrolling` runs before every bar-initiated scroll; return `true` to cancel it.
public struct FluentAnnotatedScrollView<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let configuration: FluentAnnotatedScrollBarConfiguration
    private let content: Content

    public init(
        labels: [FluentAnnotatedScrollBarLabel],
        smallChange: CGFloat = 0,
        detailLabel: ((CGFloat) -> String?)? = nil,
        onScrolling: ((CGFloat, FluentAnnotatedScrollBarScrollingKind) -> Bool)? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        configuration = FluentAnnotatedScrollBarConfiguration(labels: labels, smallChange: smallChange,
                                                              detailLabel: detailLabel, onScrolling: onScrolling)
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentAnnotatedScrollViewControl(content: FluentAnyView(content), configuration: configuration, context: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentAnnotatedScrollViewControl else { return false }
        control.update(content: FluentAnyView(content), configuration: configuration, context: context)
        return true
    }
}

struct FluentAnnotatedScrollBarConfiguration {
    var labels: [FluentAnnotatedScrollBarLabel]
    var smallChange: CGFloat
    var detailLabel: ((CGFloat) -> String?)?
    var onScrolling: ((CGFloat, FluentAnnotatedScrollBarScrollingKind) -> Bool)?
}

/// Source-derived metrics (`AnnotatedScrollBar_themeresources.xaml`, `AnnotatedScrollBar.h/.xaml`).
enum FluentAnnotatedScrollBarMetrics {
    static let thumbSize = NSSize(width: 30, height: 3)
    static let thumbCornerRadius: CGFloat = 1.5
    static let labelsMinWidth: CGFloat = 44
    static let labelTopMargin: CGFloat = -5
    static let toolTipMaxWidth: CGFloat = 360
    static let toolTipMinHeight: CGFloat = 40
    static let toolTipTouchOffset: CGFloat = 22
    static let buttonGlyphSize: CGFloat = 8
    static let buttonHeight: CGFloat = 20
    static let viewportToSmallChangeRatio: CGFloat = 8
    static let repeatDelay: TimeInterval = 0.5
    static let repeatInterval: TimeInterval = 0.05
}

final class FluentAnnotatedScrollViewControl: NSView {
    override var isFlipped: Bool { true }

    let scrollView = NSScrollView()
    private let documentView = FluentAnnotatedFlippedView()
    let contentHost: FluentViewHost<FluentAnyView>
    let bar: FluentAnnotatedScrollBarView
    private var boundsObserver: Any?

    init(content: FluentAnyView, configuration: FluentAnnotatedScrollBarConfiguration, context: FluentRenderContext) {
        contentHost = FluentViewHost(content, context: context)
        bar = FluentAnnotatedScrollBarView(configuration: configuration, context: context)
        super.init(frame: .zero)
        // Hosts are laid out by frame; FluentViewHost otherwise opts out of autoresizing constraints.
        contentHost.translatesAutoresizingMaskIntoConstraints = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AnnotatedScrollView")
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        documentView.addSubview(contentHost)
        scrollView.documentView = documentView
        addSubview(scrollView)
        addSubview(bar)
        bar.onScrollTo = { [weak self] offset in self?.scroll(to: offset) }
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: scrollView.contentView, queue: .main) { [weak self] _ in
            self?.syncBar()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    func update(content: FluentAnyView, configuration: FluentAnnotatedScrollBarConfiguration, context: FluentRenderContext) {
        contentHost.update(content, context: context)
        bar.update(configuration: configuration, context: context)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let barWidth = bar.preferredWidth
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        bar.frame = NSRect(x: isRTL ? 0 : bounds.width - barWidth, y: 0, width: barWidth, height: bounds.height)
        scrollView.frame = NSRect(x: isRTL ? barWidth : 0, y: 0, width: max(0, bounds.width - barWidth), height: bounds.height)
        let width = scrollView.contentSize.width
        contentHost.frame.size.width = width
        let height = max(contentHost.fittingSize.height, scrollView.contentSize.height)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentHost.frame = documentView.bounds
        syncBar()
    }

    var maximumOffset: CGFloat { max(0, documentView.frame.height - scrollView.contentSize.height) }
    var scrollOffset: CGFloat { scrollView.contentView.bounds.origin.y }

    func scroll(to offset: CGFloat) {
        let clamped = min(max(offset, 0), maximumOffset)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncBar()
    }

    private func syncBar() {
        bar.setScrollState(value: scrollOffset, maximum: maximumOffset, viewport: scrollView.contentSize.height)
    }
}

final class FluentAnnotatedFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FluentAnnotatedScrollBarView: NSView {
    override var isFlipped: Bool { true }

    private(set) var configuration: FluentAnnotatedScrollBarConfiguration
    private var context: FluentRenderContext
    var onScrollTo: ((CGFloat) -> Void)?

    let incrementButton = FluentAnnotatedScrollButton(pointsUp: true)
    let decrementButton = FluentAnnotatedScrollButton(pointsUp: false)
    private let thumbLayer = CALayer()
    private let ghostLayer = CALayer()
    let detailBubble = FluentAnnotatedDetailBubble()
    private(set) var labelFrames: [NSRect] = []
    private(set) var visibleLabelIndices: [Int] = []
    private(set) var value: CGFloat = 0
    private(set) var maximum: CGFloat = 0
    private(set) var viewport: CGFloat = 0
    private(set) var isPressed = false
    private var trackingArea: NSTrackingArea?

    init(configuration: FluentAnnotatedScrollBarConfiguration, context: FluentRenderContext) {
        self.configuration = configuration
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AnnotatedScrollBar")
        wantsLayer = true
        for layer in [ghostLayer, thumbLayer] {
            layer.cornerRadius = FluentAnnotatedScrollBarMetrics.thumbCornerRadius
            self.layer?.addSublayer(layer)
        }
        ghostLayer.isHidden = true
        incrementButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.AnnotatedScrollBar.Increment")
        decrementButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.AnnotatedScrollBar.Decrement")
        incrementButton.onStep = { [weak self] in self?.scrollTo(nil, kind: .incrementButton) }
        decrementButton.onStep = { [weak self] in self?.scrollTo(nil, kind: .decrementButton) }
        addSubview(incrementButton)
        addSubview(decrementButton)
        detailBubble.isHidden = true
        setAccessibilityElement(false)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(configuration next: FluentAnnotatedScrollBarConfiguration, context: FluentRenderContext) {
        configuration = next
        self.context = context
        incrementButton.theme = context.theme
        decrementButton.theme = context.theme
        detailBubble.theme = context.theme
        updateColors()
        needsLayout = true
        needsDisplay = true
    }

    private func updateColors() {
        thumbLayer.backgroundColor = (context.theme.isHighContrast ? context.theme.accent : context.theme.accentFillDefault).cgColor
        ghostLayer.backgroundColor = context.theme.accentFillDisabled.cgColor
    }

    private var labelFont: NSFont { context.theme.typography.font(for: .body) }

    var preferredWidth: CGFloat {
        let widest = configuration.labels.map { ceil(($0.text as NSString).size(withAttributes: [.font: labelFont]).width) }.max() ?? 0
        return max(FluentAnnotatedScrollBarMetrics.labelsMinWidth, widest, FluentAnnotatedScrollBarMetrics.thumbSize.width)
    }

    /// `PART_VerticalGrid`: the rail between the step buttons.
    var railFrame: NSRect {
        let button = FluentAnnotatedScrollBarMetrics.buttonHeight
        return NSRect(x: 0, y: button, width: bounds.width, height: max(0, bounds.height - 2 * button))
    }

    var canScroll: Bool { maximum > 0 && isEnabledForInput }

    private var isEnabledForInput: Bool {
        var view: NSView? = self
        while let current = view {
            if let control = current as? NSControl, !control.isEnabled { return false }
            view = current.superview
        }
        return true
    }

    /// `UpdateScrollOffsetToLabelOffsetFactor`.
    var scrollOffsetToLabelOffsetFactor: CGFloat {
        let scrollable = maximum == 0 ? 1 : maximum
        return (railFrame.height - FluentAnnotatedScrollBarMetrics.thumbSize.height) / scrollable
            * (1 - viewport / (viewport + scrollable))
    }

    func setScrollState(value: CGFloat, maximum: CGFloat, viewport: CGFloat) {
        let changedExtent = maximum != self.maximum || viewport != self.viewport
        self.value = value
        self.maximum = maximum
        self.viewport = viewport
        if changedExtent { needsLayout = true; needsDisplay = true }
        positionThumb()
        incrementButton.isEnabled = canScroll
        decrementButton.isEnabled = canScroll
    }

    private func positionThumb() {
        let size = FluentAnnotatedScrollBarMetrics.thumbSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbLayer.frame = NSRect(x: thumbX, y: railFrame.minY + value * scrollOffsetToLabelOffsetFactor,
                                  width: size.width, height: size.height)
        CATransaction.commit()
    }

    /// Thumbs are right-aligned in the rail, mirrored in RTL.
    private var thumbX: CGFloat {
        userInterfaceLayoutDirection == .rightToLeft ? 0 : bounds.width - FluentAnnotatedScrollBarMetrics.thumbSize.width
    }

    override func layout() {
        super.layout()
        let button = FluentAnnotatedScrollBarMetrics.buttonHeight
        incrementButton.frame = NSRect(x: 0, y: 0, width: bounds.width, height: button)
        decrementButton.frame = NSRect(x: 0, y: max(0, bounds.height - button), width: bounds.width, height: button)
        layoutLabels()
        positionThumb()
        updateTracking()
    }

    /// Places labels at `scrollOffset * factor` and applies `CollapseCollidingAndOutOfBoundsLabels`:
    /// out-of-bounds labels hide; when two collide the lower stays, except that the first label wins
    /// over the second unless the one below it is the last label.
    private func layoutLabels() {
        let rail = railFrame
        let factor = scrollOffsetToLabelOffsetFactor
        let lineHeight = ceil(labelFont.ascender - labelFont.descender + labelFont.leading)
        // The container sits at `offset * factor`; its TextBlock has a -5,-2 margin, so the
        // container is 7pt shorter than a line and the text draws 5pt above it.
        let containerHeight = max(0, lineHeight + FluentAnnotatedScrollBarMetrics.labelTopMargin - 2)
        labelFrames = configuration.labels.map { label in
            NSRect(x: 0, y: rail.minY + label.scrollOffset * factor, width: bounds.width, height: containerHeight)
        }
        var visible = Set<Int>()
        var previousTop: CGFloat = -1
        var previousIndex = labelFrames.count
        for index in stride(from: labelFrames.count - 1, through: 0, by: -1) {
            let top = labelFrames[index].minY - rail.minY
            let bottom = top + containerHeight
            let outOfBounds = top < 0 || bottom > rail.height
            let colliding = previousTop >= 0 && previousTop <= bottom
            if outOfBounds { continue }
            if colliding {
                if index == 0, previousIndex < labelFrames.count - 1 {
                    visible.remove(previousIndex)
                    visible.insert(0)
                }
                continue
            }
            visible.insert(index)
            previousTop = top
            previousIndex = index
        }
        visibleLabelIndices = visible.sorted()
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = userInterfaceLayoutDirection == .rightToLeft ? .left : .right
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: context.theme.textPrimary,
                                                          .paragraphStyle: paragraph]
        let lineHeight = ceil(labelFont.ascender - labelFont.descender + labelFont.leading)
        for index in visibleLabelIndices {
            let container = labelFrames[index]
            let text = NSRect(x: container.minX, y: container.minY + FluentAnnotatedScrollBarMetrics.labelTopMargin,
                              width: container.width, height: lineHeight)
            (configuration.labels[index].text as NSString).draw(in: text, withAttributes: attributes)
        }
    }

    // MARK: Pointer

    private func updateTracking() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: railFrame, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func railOffset(for event: NSEvent) -> CGFloat {
        let point = convert(event.locationInWindow, from: nil)
        return min(max(point.y - railFrame.minY, 0), railFrame.height)
    }

    override func mouseMoved(with event: NSEvent) {
        guard canScroll else { return }
        showHoverVisuals(atRailOffset: railOffset(for: event), isTouch: FluentInputDeviceTracker.isTouch(event))
    }

    override func mouseExited(with event: NSEvent) {
        guard !isPressed else { return }
        hideHoverVisuals()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard canScroll, railFrame.contains(point) else { return }
        isPressed = true
        let offset = railOffset(for: event)
        showHoverVisuals(atRailOffset: offset, isTouch: FluentInputDeviceTracker.isTouch(event))
        scrollTo(offset / scrollOffsetToLabelOffsetFactor, kind: .click)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        let offset = railOffset(for: event)
        showHoverVisuals(atRailOffset: offset, isTouch: FluentInputDeviceTracker.isTouch(event))
        scrollTo(offset / scrollOffsetToLabelOffsetFactor, kind: .drag)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        // Non-mouse pointers hide their hover visuals on release (`OnVerticalGridPointerReleased`).
        if FluentInputDeviceTracker.isTouch(event) || !railFrame.contains(convert(event.locationInWindow, from: nil)) {
            hideHoverVisuals()
        }
    }

    /// `ShowHoverVisuals`: the ghost thumb at the pointer and, when the app supplies one, a detail
    /// label above it (raised by 22pt for touch so the finger does not cover it).
    func showHoverVisuals(atRailOffset offset: CGFloat, isTouch: Bool) {
        let size = FluentAnnotatedScrollBarMetrics.thumbSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostLayer.frame = NSRect(x: thumbX, y: railFrame.minY + offset, width: size.width, height: size.height)
        ghostLayer.isHidden = false
        CATransaction.commit()
        let scrollOffset = offset / scrollOffsetToLabelOffsetFactor
        guard let text = configuration.detailLabel?(scrollOffset), let host = superview else {
            detailBubble.removeFromSuperview()
            return
        }
        if detailBubble.superview !== host { host.addSubview(detailBubble) }
        detailBubble.text = text
        detailBubble.isHidden = false
        let bubble = detailBubble.preferredSize
        let anchorY = convert(NSPoint(x: 0, y: railFrame.minY + offset - (isTouch ? FluentAnnotatedScrollBarMetrics.toolTipTouchOffset : 0)), to: host).y
        let railX = convert(NSPoint(x: userInterfaceLayoutDirection == .rightToLeft ? 0 : bounds.width, y: 0), to: host).x
        var x = railX - bubble.width / 2 + 2
        x = min(max(x, 0), max(0, host.bounds.width - bubble.width))
        let y = max(0, anchorY - bubble.height - 4)
        detailBubble.frame = NSRect(x: x, y: host.isFlipped ? y : host.bounds.height - y - bubble.height,
                                    width: bubble.width, height: bubble.height)
    }

    func hideHoverVisuals() {
        ghostLayer.isHidden = true
        detailBubble.isHidden = true
    }

    // MARK: Scrolling

    var effectiveSmallChange: CGFloat {
        configuration.smallChange > 0 ? configuration.smallChange : viewport / FluentAnnotatedScrollBarMetrics.viewportToSmallChangeRatio
    }

    /// `AnnotatedScrollBar::ScrollTo`: step buttons move by SmallChange; every request first raises
    /// Scrolling, which may cancel it.
    func scrollTo(_ offset: CGFloat?, kind: FluentAnnotatedScrollBarScrollingKind) {
        guard canScroll else { return }
        let target: CGFloat
        switch kind {
        case .incrementButton: target = max(value - effectiveSmallChange, 0)
        case .decrementButton: target = min(value + effectiveSmallChange, maximum)
        case .click, .drag: target = min(max(offset ?? value, 0), maximum)
        }
        if configuration.onScrolling?(target, kind) == true { return }
        onScrollTo?(target)
    }
}

/// `ScrollButtonStyle`: a borderless RepeatButton with an 8pt chevron, repeating while held.
final class FluentAnnotatedScrollButton: NSView {
    override var isFlipped: Bool { true }
    let pointsUp: Bool
    var onStep: (() -> Void)?
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { if oldValue != isEnabled { needsDisplay = true } } }
    private(set) var isPressed = false
    private var isPointerOver = false
    private var repeatTimer: Timer?
    private var trackingArea: NSTrackingArea?

    init(pointsUp: Bool) {
        self.pointsUp = pointsUp
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { repeatTimer?.invalidate() }

    var foregroundColor: NSColor {
        if !isEnabled { return theme.textDisabled }
        if isPressed { return theme.textTertiary }
        if isPointerOver { return theme.textSecondary }
        return theme.textPrimary
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = NSImage(systemSymbolName: pointsUp ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: FluentAnnotatedScrollBarMetrics.buttonGlyphSize, weight: .semibold)) else { return }
        let color = foregroundColor
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        // HorizontalAlignment="Right": the glyph sits over the thumb column.
        let x = userInterfaceLayoutDirection == .rightToLeft
            ? FluentAnnotatedScrollBarMetrics.thumbSize.width / 2 - image.size.width / 2
            : bounds.width - FluentAnnotatedScrollBarMetrics.thumbSize.width / 2 - image.size.width / 2
        tinted.draw(in: NSRect(x: x, y: bounds.midY - image.size.height / 2, width: image.size.width, height: image.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
        onStep?()
        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: FluentAnnotatedScrollBarMetrics.repeatDelay, repeats: false) { [weak self] _ in
            guard let self, self.isPressed else { return }
            let repeating = Timer(timeInterval: FluentAnnotatedScrollBarMetrics.repeatInterval, repeats: true) { [weak self] timer in
                guard let self, self.isPressed, self.isEnabled else { timer.invalidate(); return }
                self.onStep?()
            }
            RunLoop.main.add(repeating, forMode: .common)
            self.repeatTimer = repeating
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        repeatTimer?.invalidate()
        repeatTimer = nil
        needsDisplay = true
    }
}

/// The detail-label ToolTip: BaseTextBlockStyle text, MinHeight 40, MaxWidth 360.
final class FluentAnnotatedDetailBubble: NSView {
    override var isFlipped: Bool { true }
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    var text = "" { didSet { if oldValue != text { needsDisplay = true; setAccessibilityLabel(text) } } }
    private let padding = NSEdgeInsets(top: 6, left: 9, bottom: 8, right: 9)

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AnnotatedScrollBar.DetailLabel")
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var font: NSFont { theme.typography.font(for: .bodyStrong) }

    var preferredSize: NSSize {
        let maxText = FluentAnnotatedScrollBarMetrics.toolTipMaxWidth - padding.left - padding.right
        let measured = (text as NSString).boundingRect(with: NSSize(width: maxText, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin], attributes: [.font: font])
        return NSSize(width: ceil(measured.width) + padding.left + padding.right,
                      height: max(FluentAnnotatedScrollBarMetrics.toolTipMinHeight, ceil(measured.height) + padding.top + padding.bottom))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        theme.toolTipSurfaceFill.setFill()
        path.fill()
        theme.surfaceStrokeFlyout.setStroke()
        path.stroke()
        let rect = NSRect(x: padding.left, y: padding.top, width: bounds.width - padding.left - padding.right,
                          height: bounds.height - padding.top - padding.bottom)
        let measured = (text as NSString).boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], attributes: [.font: font])
        (text as NSString).draw(with: NSRect(x: rect.minX, y: rect.midY - measured.height / 2, width: rect.width, height: measured.height),
                                options: [.usesLineFragmentOrigin], attributes: [.font: font, .foregroundColor: theme.textPrimary])
    }
}
