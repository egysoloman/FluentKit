import AppKit

/// `RefreshPullDirection`: the edge content is pulled away from to request a refresh.
public enum FluentRefreshPullDirection: Hashable, Sendable {
    case topToBottom
    case bottomToTop
    case leftToRight
    case rightToLeft
}

/// `RefreshVisualizerState`.
public enum FluentRefreshVisualizerState: Hashable, Sendable {
    case idle
    case peeking
    case interacting
    case pending
    case refreshing
}

/// Completes a refresh started by a RefreshContainer (`Deferral`). Completing twice is harmless.
public final class FluentRefreshDeferral {
    private var completion: (() -> Void)?

    init(completion: @escaping () -> Void) { self.completion = completion }

    public func complete() {
        let completion = self.completion
        self.completion = nil
        if Thread.isMainThread { completion?() } else { DispatchQueue.main.async { completion?() } }
    }
}

/// A WinUI-style RefreshContainer around scrolling content: pull the content away from its edge
/// (trackpad or macOS 27 touch, using the scroll view's elastic overscroll) past 80% of the
/// 100pt visualizer and release to refresh. `isRefreshing` is two-way: set it to `true` to start a
/// refresh programmatically (`RequestRefresh`); it returns to `false` when the deferral completes.
public struct FluentRefreshContainer<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let configuration: FluentRefreshConfiguration
    private let content: Content

    public init(
        pullDirection: FluentRefreshPullDirection = .topToBottom,
        isRefreshing: FluentBinding<Bool>? = nil,
        onRefreshRequested: @escaping (FluentRefreshDeferral) -> Void,
        @FluentViewBuilder content: () -> Content
    ) {
        configuration = FluentRefreshConfiguration(pullDirection: pullDirection, isRefreshing: isRefreshing,
                                                   onRefreshRequested: onRefreshRequested)
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentRefreshContainerView(content: FluentAnyView(content), configuration: configuration, context: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let view = view as? FluentRefreshContainerView else { return false }
        view.update(content: FluentAnyView(content), configuration: configuration, context: context)
        return true
    }
}

struct FluentRefreshConfiguration {
    var pullDirection: FluentRefreshPullDirection
    var isRefreshing: FluentBinding<Bool>?
    var onRefreshRequested: (FluentRefreshDeferral) -> Void
}

/// Source-derived metrics (`RefreshContainer.cpp`, `RefreshVisualizer.cpp`, the default animation handler).
enum FluentRefreshMetrics {
    /// `DEFAULT_PULL_DIMENSION_SIZE` / RefreshVisualizer Height.
    static let pullDimension: CGFloat = 100
    /// `DEFAULT_EXECUTION_RATIO`.
    static let executionRatio: CGFloat = 0.8
    /// `DEFAULT_INDICATOR_SIZE`.
    static let indicatorSize: CGFloat = 30
    static let glyphSize: CGFloat = 20
    /// `MINIMUM_INDICATOR_OPACITY`.
    static let minimumOpacity: Float = 0.4
    /// `PARALLAX_POSITION_RATIO`.
    static let parallaxRatio: CGFloat = 0.5
    /// `ExecuteScaleUpAnimation`: 1 → 1.5 at the midpoint → 1 over 300ms.
    static let scaleUpDuration: CFTimeInterval = 0.3
    /// `ExecuteExecutingRotationAnimation`: one turn every 500ms, linear, forever.
    static let refreshRotationDuration: CFTimeInterval = 0.5
    static let settleDuration: TimeInterval = 0.2
}

final class FluentRefreshContainerView: NSView {
    override var isFlipped: Bool { true }

    private(set) var configuration: FluentRefreshConfiguration
    private var context: FluentRenderContext
    let scrollView = FluentRefreshScrollView()
    private let documentView = FluentRefreshFlippedView()
    let contentHost: FluentViewHost<FluentAnyView>
    let indicator = FluentRefreshIndicatorView()
    private(set) var state: FluentRefreshVisualizerState = .idle
    private(set) var interactionRatio: CGFloat = 0
    private(set) var isInteractingForRefresh = false
    private var observers: [Any] = []
    private var bindingObserverID: UUID?
    private var observedBinding: FluentBinding<Bool>?
    private var bindingGeneration: UInt64 = 0
    private var isWritingBinding = false
    private var refreshGeneration: UInt64 = 0

    init(content: FluentAnyView, configuration: FluentRefreshConfiguration, context: FluentRenderContext) {
        self.configuration = configuration
        self.context = context
        contentHost = FluentViewHost(content, context: context)
        super.init(frame: .zero)
        // Hosts are laid out by frame; FluentViewHost otherwise opts out of autoresizing constraints.
        contentHost.translatesAutoresizingMaskIntoConstraints = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.RefreshContainer")
        wantsLayer = true
        layer?.masksToBounds = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.hasVerticalScroller = isVertical
        scrollView.hasHorizontalScroller = !isVertical
        scrollView.autohidesScrollers = true
        documentView.addSubview(contentHost)
        scrollView.documentView = documentView
        scrollView.onViewportSizeChange = { [weak self] in self?.needsLayout = true }
        addSubview(scrollView)
        indicator.identifier = NSUserInterfaceItemIdentifier("FluentKit.RefreshContainer.Visualizer")
        addSubview(indicator)
        installScrollObservers()
        installBindingObserver()
        applyIndicator()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        removeBindingObserver()
    }

    private var isVertical: Bool {
        configuration.pullDirection == .topToBottom || configuration.pullDirection == .bottomToTop
    }

    func update(content: FluentAnyView, configuration next: FluentRefreshConfiguration, context: FluentRenderContext) {
        removeBindingObserver()
        configuration = next
        self.context = context
        contentHost.update(content, context: context)
        scrollView.hasVerticalScroller = isVertical
        scrollView.hasHorizontalScroller = !isVertical
        if next.isRefreshing?.get() == true, state != .refreshing { requestRefresh() }
        writeBinding()
        installBindingObserver()
        needsLayout = true
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let viewport = scrollView.contentSize
        let fitting = contentHost.fittingSize
        let size = isVertical
            ? NSSize(width: viewport.width, height: max(fitting.height, viewport.height))
            : NSSize(width: max(fitting.width, viewport.width), height: viewport.height)
        documentView.frame = NSRect(origin: .zero, size: size)
        contentHost.frame = documentView.bounds
        applyIndicator()
    }

    /// Distance the content currently stands away from its pull edge, including any held inset.
    var pullDistance: CGFloat {
        let origin = scrollView.contentView.bounds.origin
        let viewport = scrollView.contentView.bounds.size
        let document = documentView.frame.size
        switch configuration.pullDirection {
        case .topToBottom: return max(0, -origin.y)
        case .bottomToTop: return max(0, origin.y + viewport.height - max(document.height, viewport.height))
        case .leftToRight: return max(0, -origin.x)
        case .rightToLeft: return max(0, origin.x + viewport.width - max(document.width, viewport.width))
        }
    }

    // MARK: Interaction

    private func installScrollObservers() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
                guard let self else { return }
                if self.isInteractingForRefresh { self.interactionRatioChanged(min(1, self.pullDistance / FluentRefreshMetrics.pullDimension)) }
                self.applyIndicator()
            },
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
                self?.interactingChanged(true)
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
                self?.interactingChanged(false)
            }
        ]
    }

    /// `RefreshInfoProvider_InteractingForRefreshChanged`: releasing in Pending refreshes; releasing
    /// from Peeking or Interacting returns to Idle; a running refresh is never interrupted.
    func interactingChanged(_ interacting: Bool) {
        guard isInteractingForRefresh != interacting else { return }
        isInteractingForRefresh = interacting
        if interacting {
            FluentInputDeviceTracker.shared.record(FluentInputDeviceTracker.shared.lastDeviceType(in: window) == .touch ? .touch : .mouse, in: window)
            return
        }
        switch state {
        case .pending: requestRefresh()
        case .refreshing: break
        default: setState(.idle)
        }
    }

    /// `RefreshInfoProvider_InteractionRatioChanged`.
    func interactionRatioChanged(_ ratio: CGFloat) {
        let wasAtZero = interactionRatio == 0
        interactionRatio = ratio
        guard isInteractingForRefresh else { return }
        let execution = FluentRefreshMetrics.executionRatio
        switch state {
        case .idle:
            if wasAtZero {
                if ratio > execution { setState(.pending) } else if ratio > 0 { setState(.interacting) }
            } else if ratio > 0 {
                setState(.peeking)
            }
        case .interacting:
            if ratio <= 0 { setState(.idle) } else if ratio > execution { setState(.pending) }
        case .pending:
            if ratio <= execution { setState(.interacting) }
        case .peeking, .refreshing:
            break
        }
        applyIndicator()
    }

    /// `RefreshContainer::RequestRefresh` / `OnRefreshRequested`: the content is held at the
    /// execution offset while the app refreshes; completing the deferral releases it.
    func requestRefresh() {
        guard state != .refreshing else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        setState(.refreshing)
        holdContent(true)
        writeBinding()
        configuration.onRefreshRequested(FluentRefreshDeferral { [weak self] in
            guard let self, self.refreshGeneration == generation, self.state == .refreshing else { return }
            self.refreshCompleted()
        })
    }

    private func refreshCompleted() {
        setState(.idle)
        interactionRatio = 0
        holdContent(false)
        writeBinding()
    }

    private func holdContent(_ hold: Bool) {
        let distance = hold ? FluentRefreshMetrics.pullDimension * FluentRefreshMetrics.executionRatio : 0
        var insets = NSEdgeInsetsZero
        switch configuration.pullDirection {
        case .topToBottom: insets.top = distance
        case .bottomToTop: insets.bottom = distance
        case .leftToRight: insets.left = distance
        case .rightToLeft: insets.right = distance
        }
        scrollView.contentInsets = insets
        var origin = scrollView.contentView.bounds.origin
        switch configuration.pullDirection {
        case .topToBottom: origin.y = hold ? -distance : max(origin.y, 0)
        case .leftToRight: origin.x = hold ? -distance : max(origin.x, 0)
        case .bottomToTop:
            let maxY = max(0, documentView.frame.height - scrollView.contentView.bounds.height)
            origin.y = hold ? maxY + distance : min(origin.y, maxY)
        case .rightToLeft:
            let maxX = max(0, documentView.frame.width - scrollView.contentView.bounds.width)
            origin.x = hold ? maxX + distance : min(origin.x, maxX)
        }
        if context.reduceMotion || window == nil {
            scrollView.contentView.setBoundsOrigin(origin)
        } else {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = FluentRefreshMetrics.settleDuration
                animation.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(origin)
            }
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        applyIndicator()
    }

    private func setState(_ next: FluentRefreshVisualizerState) {
        guard state != next else { return }
        state = next
        indicator.apply(state: next, reduceMotion: context.reduceMotion)
        indicator.setAccessibilityValue(next == .refreshing ? fluentControlString("Refreshing") : nil)
    }

    /// Positions the 30pt indicator in the revealed gap at half the pull distance (parallax) and
    /// rotates it with the interaction ratio until the execution ratio (one full turn).
    func applyIndicator() {
        indicator.theme = context.theme
        let gap = state == .refreshing ? FluentRefreshMetrics.pullDimension * FluentRefreshMetrics.executionRatio : pullDistance
        let size = FluentRefreshMetrics.indicatorSize
        let along = gap * FluentRefreshMetrics.parallaxRatio - size / 2
        let frame: NSRect
        switch configuration.pullDirection {
        case .topToBottom: frame = NSRect(x: bounds.midX - size / 2, y: along, width: size, height: size)
        case .bottomToTop: frame = NSRect(x: bounds.midX - size / 2, y: bounds.height - along - size, width: size, height: size)
        case .leftToRight: frame = NSRect(x: along, y: bounds.midY - size / 2, width: size, height: size)
        case .rightToLeft: frame = NSRect(x: bounds.width - along - size, y: bounds.midY - size / 2, width: size, height: size)
        }
        indicator.frame = frame
        indicator.isHidden = gap <= 0 && state == .idle
        let starting: CGFloat
        switch configuration.pullDirection {
        case .topToBottom, .bottomToTop: starting = 0
        case .leftToRight: starting = -.pi / 2
        case .rightToLeft: starting = .pi / 2
        }
        indicator.startingRotation = starting
        if state != .refreshing {
            let execution = FluentRefreshMetrics.executionRatio
            indicator.rotation = starting + .pi * 2 * min(max(interactionRatio, 0), execution) / execution
        }
    }

    // MARK: Binding

    private func writeBinding() {
        guard let binding = configuration.isRefreshing, !isWritingBinding, binding.get() != (state == .refreshing) else { return }
        isWritingBinding = true
        binding.set(state == .refreshing)
        isWritingBinding = false
    }

    private func installBindingObserver() {
        guard let binding = configuration.isRefreshing else { return }
        let generation = bindingGeneration
        observedBinding = binding
        bindingObserverID = binding.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.bindingGeneration == generation, !self.isWritingBinding,
                      let binding = self.configuration.isRefreshing else { return }
                if binding.get(), self.state != .refreshing { self.requestRefresh() } else { self.writeBinding() }
            }
        }
    }

    private func removeBindingObserver() {
        bindingGeneration &+= 1
        if let bindingObserverID { observedBinding?.removeObserver(bindingObserverID) }
        bindingObserverID = nil
        observedBinding = nil
    }
}

final class FluentRefreshFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FluentRefreshScrollView: FluentViewportScrollView {}

/// The default RefreshVisualizer content: the Refresh symbol in a 30pt box.
final class FluentRefreshIndicatorView: NSView {
    var theme: FluentTheme = .current { didSet { if oldValue != theme { updateImage() } } }
    var startingRotation: CGFloat = 0
    var rotation: CGFloat = 0 { didSet { if oldValue != rotation { applyTransform() } } }
    private let glyphLayer = CALayer()
    private(set) var state: FluentRefreshVisualizerState = .idle

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(glyphLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        fluentSetDefaultAccessibilityLabel("Refresh")
        updateImage()
        apply(state: .idle, reduceMotion: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var glyphOpacity: Float { glyphLayer.opacity }
    var isSpinning: Bool { glyphLayer.animation(forKey: "fluent.refresh.spin") != nil }

    override func layout() {
        super.layout()
        let size = FluentRefreshMetrics.glyphSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        glyphLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    private func updateImage() {
        // RefreshContainerForegroundBrush: black (Light) / white (Dark) / HighlightText (High Contrast).
        let color: NSColor = theme.isHighContrast ? theme.textPrimary : (theme.isDark ? .white : .black)
        guard let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: FluentRefreshMetrics.glyphSize * 0.8, weight: .regular)) else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        glyphLayer.contents = tinted
        glyphLayer.contentsGravity = .resizeAspect
    }

    private func applyTransform() {
        guard state != .refreshing else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.transform = CATransform3DMakeRotation(-rotation, 0, 0, 1)
        CATransaction.commit()
    }

    /// `UpdateRefreshState`: opacity 0.4 while Idle/Interacting, 1 otherwise; Pending plays the
    /// scale-up pulse and Refreshing spins continuously.
    func apply(state next: FluentRefreshVisualizerState, reduceMotion: Bool) {
        let previous = state
        state = next
        glyphLayer.removeAnimation(forKey: "fluent.refresh.spin")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch next {
        case .idle, .interacting: glyphLayer.opacity = FluentRefreshMetrics.minimumOpacity
        case .peeking, .pending, .refreshing: glyphLayer.opacity = 1
        }
        if next != .refreshing { glyphLayer.transform = CATransform3DMakeRotation(-rotation, 0, 0, 1) }
        CATransaction.commit()
        guard !reduceMotion else { return }
        if next == .pending, previous != .pending {
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1, 1.5, 1]
            pulse.keyTimes = [0, 0.5, 1]
            pulse.duration = FluentRefreshMetrics.scaleUpDuration
            glyphLayer.add(pulse, forKey: "fluent.refresh.pulse")
        }
        if next == .refreshing {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = -startingRotation
            spin.toValue = -startingRotation - 2 * .pi
            spin.duration = FluentRefreshMetrics.refreshRotationDuration
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.repeatCount = .infinity
            glyphLayer.add(spin, forKey: "fluent.refresh.spin")
        }
    }
}
