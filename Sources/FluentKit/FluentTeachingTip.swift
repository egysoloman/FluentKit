import AppKit

/// WinUI TeachingTip's preferred target-relative placements. Left/right placements mirror with
/// the current flow direction; leading/trailing are retained as source-compatible logical aliases.
public enum FluentTeachingTipPlacement: Hashable, Sendable {
    case automatic
    case top
    case bottom
    case left
    case right
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
    case leftTop
    case leftBottom
    case rightTop
    case rightBottom
    case center
    case leading
    case trailing
}

public enum FluentTeachingTipTailVisibility: Hashable, Sendable {
    case automatic
    case visible
    case collapsed
}

public enum FluentTeachingTipHeroContentPlacement: Hashable, Sendable {
    case automatic
    case top
    case bottom
}

public enum FluentTeachingTipCloseReason: Hashable, Sendable {
    case closeButton
    case lightDismiss
    case programmatic
}

/// Mutable close arguments matching WinUI TeachingTipClosingEventArgs' cancellation contract.
public final class FluentTeachingTipClosingEventArgs {
    public let reason: FluentTeachingTipCloseReason
    public var cancel = false

    init(reason: FluentTeachingTipCloseReason) {
        self.reason = reason
    }
}

private struct FluentTeachingTipConfiguration {
    var title: String
    var subtitle: String
    var systemImageName: String?
    var tailVisibility: FluentTeachingTipTailVisibility
    var placement: FluentTeachingTipPlacement
    var heroContentPlacement: FluentTeachingTipHeroContentPlacement
    var placementMargin: NSEdgeInsets
    var shouldConstrainToRootBounds: Bool
    var isLightDismissEnabled: Bool
    var size: NSSize
    var actionButtonTitle: String?
    var closeButtonTitle: String?
    var heroContent: FluentAnyView?
    var onActionButtonClick: () -> Void
    var onCloseButtonClick: () -> Void
    var onClosing: (FluentTeachingTipClosingEventArgs) -> Void
    var onClosed: (FluentTeachingTipCloseReason) -> Void
    var onOpened: () -> Void
    var onDismiss: () -> Void

    var surfaceSize: NSSize {
        NSSize(
            width: min(max(size.width, 320), 336),
            height: min(max(size.height, 40), 520)
        )
    }

    var showsTail: Bool {
        switch tailVisibility {
        case .automatic, .visible: return true
        case .collapsed: return false
        }
    }

    var showsHeaderCloseButton: Bool {
        closeButtonTitle == nil && !isLightDismissEnabled
    }
}

/// A binding-driven, application-owned TeachingTip anchored to declarative content.
public struct FluentTeachingTip<Content: FluentView, TipContent: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let tipContent: TipContent
    private let isPresented: FluentBinding<Bool>
    private let configuration: FluentTeachingTipConfiguration

    public init(
        isPresented: FluentBinding<Bool>,
        title: String = "",
        subtitle: String = "",
        systemImageName: String? = nil,
        tailVisibility: FluentTeachingTipTailVisibility = .automatic,
        placement: FluentTeachingTipPlacement = .automatic,
        heroContentPlacement: FluentTeachingTipHeroContentPlacement = .automatic,
        placementMargin: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        shouldConstrainToRootBounds: Bool = true,
        isLightDismissEnabled: Bool = false,
        size: NSSize = NSSize(width: 320, height: 150),
        actionButtonTitle: String? = nil,
        closeButtonTitle: String? = nil,
        heroContent: FluentAnyView? = nil,
        onActionButtonClick: @escaping () -> Void = {},
        onCloseButtonClick: @escaping () -> Void = {},
        onClosing: @escaping (FluentTeachingTipClosingEventArgs) -> Void = { _ in },
        onClosed: @escaping (FluentTeachingTipCloseReason) -> Void = { _ in },
        onOpened: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder tip: () -> TipContent
    ) {
        self.content = content()
        tipContent = tip()
        self.isPresented = isPresented
        configuration = FluentTeachingTipConfiguration(
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            tailVisibility: tailVisibility,
            placement: placement,
            heroContentPlacement: heroContentPlacement,
            placementMargin: placementMargin,
            shouldConstrainToRootBounds: shouldConstrainToRootBounds,
            isLightDismissEnabled: isLightDismissEnabled,
            size: size,
            actionButtonTitle: actionButtonTitle,
            closeButtonTitle: closeButtonTitle,
            heroContent: heroContent,
            onActionButtonClick: onActionButtonClick,
            onCloseButtonClick: onCloseButtonClick,
            onClosing: onClosing,
            onClosed: onClosed,
            onOpened: onOpened,
            onDismiss: onDismiss
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentTeachingTipHost(
            content: content._mount(in: context),
            tipContent: tipContent,
            binding: isPresented,
            configuration: configuration,
            context: context
        )
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentTeachingTipHost<TipContent> else { return false }
        host.update(
            tipContent: tipContent,
            binding: isPresented,
            configuration: configuration,
            context: context
        )
        return content._update(host.anchorContent, in: context)
    }
}

public extension FluentView {
    /// Presents a WinUI-style TeachingTip while preserving the identity of the anchor view.
    func teachingTip<TipContent: FluentView>(
        isPresented: FluentBinding<Bool>,
        title: String = "",
        subtitle: String = "",
        systemImageName: String? = nil,
        tailVisibility: FluentTeachingTipTailVisibility = .automatic,
        placement: FluentTeachingTipPlacement = .automatic,
        heroContentPlacement: FluentTeachingTipHeroContentPlacement = .automatic,
        placementMargin: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        shouldConstrainToRootBounds: Bool = true,
        isLightDismissEnabled: Bool = false,
        size: NSSize = NSSize(width: 320, height: 150),
        actionButtonTitle: String? = nil,
        closeButtonTitle: String? = nil,
        heroContent: FluentAnyView? = nil,
        onActionButtonClick: @escaping () -> Void = {},
        onCloseButtonClick: @escaping () -> Void = {},
        onClosing: @escaping (FluentTeachingTipClosingEventArgs) -> Void = { _ in },
        onClosed: @escaping (FluentTeachingTipCloseReason) -> Void = { _ in },
        onOpened: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: @escaping () -> TipContent
    ) -> FluentTeachingTip<Self, TipContent> {
        FluentTeachingTip(
            isPresented: isPresented,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            tailVisibility: tailVisibility,
            placement: placement,
            heroContentPlacement: heroContentPlacement,
            placementMargin: placementMargin,
            shouldConstrainToRootBounds: shouldConstrainToRootBounds,
            isLightDismissEnabled: isLightDismissEnabled,
            size: size,
            actionButtonTitle: actionButtonTitle,
            closeButtonTitle: closeButtonTitle,
            heroContent: heroContent,
            onActionButtonClick: onActionButtonClick,
            onCloseButtonClick: onCloseButtonClick,
            onClosing: onClosing,
            onClosed: onClosed,
            onOpened: onOpened,
            onDismiss: onDismiss,
            content: { self },
            tip: content
        )
    }
}

private enum FluentTeachingTipResolvedPlacement: CaseIterable, Equatable {
    case top
    case bottom
    case left
    case right
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
    case leftTop
    case leftBottom
    case rightTop
    case rightBottom
    case center

    var isAbove: Bool {
        switch self {
        case .top, .topRight, .topLeft, .center: return true
        default: return false
        }
    }

    var isBelow: Bool {
        switch self {
        case .bottom, .bottomRight, .bottomLeft: return true
        default: return false
        }
    }

    var isLeft: Bool {
        switch self {
        case .left, .leftTop, .leftBottom: return true
        default: return false
        }
    }

    var isRight: Bool {
        switch self {
        case .right, .rightTop, .rightBottom: return true
        default: return false
        }
    }

    func mirrored() -> Self {
        switch self {
        case .left: return .right
        case .right: return .left
        case .topRight: return .topLeft
        case .topLeft: return .topRight
        case .bottomRight: return .bottomLeft
        case .bottomLeft: return .bottomRight
        case .leftTop: return .rightTop
        case .leftBottom: return .rightBottom
        case .rightTop: return .leftTop
        case .rightBottom: return .leftBottom
        case .top, .bottom, .center: return self
        }
    }
}

private final class FluentTeachingTipHost<TipContent: FluentView>: NSView {
    private enum TransitionState: Equatable {
        case opening
        case closing
    }

    var anchorContent: NSView { subviews[0] }

    private var tipContent: TipContent
    private var binding: FluentBinding<Bool>
    private var configuration: FluentTeachingTipConfiguration
    private var context: FluentRenderContext
    private var observerID: UUID?
    private var panel: FluentTeachingTipPanel?
    private var chrome: FluentTeachingTipChrome?
    private var tipHost: FluentViewHost<TipContent>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let animationCoordinator: FluentAnimationCoordinator
    private var transitionState: TransitionState?
    private var transitionGeneration: UInt64 = 0
    private var needsDeferredPosition = false
    private var pendingCloseReason: FluentTeachingTipCloseReason = .programmatic

    init(
        content: NSView,
        tipContent: TipContent,
        binding: FluentBinding<Bool>,
        configuration: FluentTeachingTipConfiguration,
        context: FluentRenderContext
    ) {
        self.tipContent = tipContent
        self.binding = binding
        self.configuration = configuration
        self.context = context
        animationCoordinator = FluentAnimationCoordinator(reduceMotion: context.reduceMotion)
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installObserver()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    override func layout() {
        super.layout()
        guard panel != nil else { return }
        if transitionState == nil {
            _ = positionPanel()
        } else {
            needsDeferredPosition = true
        }
    }

    func update(
        tipContent: TipContent,
        binding: FluentBinding<Bool>,
        configuration: FluentTeachingTipConfiguration,
        context: FluentRenderContext
    ) {
        if let observerID { self.binding.removeObserver(observerID) }
        self.tipContent = tipContent
        self.binding = binding
        self.configuration = configuration
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        tipHost?.update(tipContent, context: context)
        chrome?.update(configuration: configuration, context: context)
        panel?.appearance = fluentAppKitAppearance(for: context.theme)
        panel?.allowsKey = configuration.isLightDismissEnabled
        installObserver()
        synchronizePresentation()
        if transitionState == nil { _ = positionPanel() }
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func synchronizePresentation() {
        guard window != nil else { return }
        if binding.get() {
            if panel == nil {
                present()
            } else if transitionState == .closing, let panel, let chrome {
                if configuration.isLightDismissEnabled { installOutsideClickMonitors(panel: panel) }
                animate(opening: true, panel: panel, chrome: chrome, placement: chrome.placement)
            }
        } else if panel != nil, transitionState != .closing {
            beginDismissal(animated: true)
        }
    }

    private func present() {
        guard let parentWindow = window else { return }
        let host = FluentViewHost(tipContent, context: context)
        let chrome = FluentTeachingTipChrome(
            content: host,
            configuration: configuration,
            context: context
        )
        chrome.onRequestClose = { [weak self] reason in self?.requestDismissal(reason: reason) }
        let panel = FluentTeachingTipPanel(
            contentRect: NSRect(origin: .zero, size: chrome.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = fluentAppKitAppearance(for: context.theme)
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = chrome
        panel.alphaValue = 1
        panel.allowsKey = configuration.isLightDismissEnabled
        self.panel = panel
        self.chrome = chrome
        tipHost = host

        guard positionPanel(duringTransition: true) else {
            self.panel = nil
            self.chrome = nil
            tipHost = nil
            closeWithoutPresentation()
            return
        }

        parentWindow.addChildWindow(panel, ordered: .above)
        if configuration.isLightDismissEnabled {
            installOutsideClickMonitors(panel: panel)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(chrome.preferredInitialResponder ?? chrome)
        } else {
            panel.orderFront(nil)
        }
        animate(
            opening: true,
            panel: panel,
            chrome: chrome,
            placement: chrome.placement,
            preparesInitialState: true
        )
    }

    private func requestDismissal(reason: FluentTeachingTipCloseReason) {
        pendingCloseReason = reason
        if binding.get() {
            binding.set(false)
        } else {
            synchronizePresentation()
        }
    }

    private func beginDismissal(animated: Bool) {
        guard let panel, let chrome else { return }
        let reason = pendingCloseReason
        let args = FluentTeachingTipClosingEventArgs(reason: reason)
        configuration.onClosing(args)
        if args.cancel {
            pendingCloseReason = .programmatic
            if !binding.get() { binding.set(true) }
            if configuration.isLightDismissEnabled { installOutsideClickMonitors(panel: panel) }
            return
        }

        removeOutsideClickMonitors()
        let finish = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
            self.chrome = nil
            self.tipHost = nil
            self.needsDeferredPosition = false
            self.pendingCloseReason = .programmatic
            self.configuration.onClosed(reason)
            self.configuration.onDismiss()
            self.synchronizePresentation()
        }
        animate(
            opening: false,
            panel: panel,
            chrome: chrome,
            placement: chrome.placement,
            animated: animated,
            completion: finish
        )
    }

    private func closeWithoutPresentation() {
        let reason = FluentTeachingTipCloseReason.programmatic
        let args = FluentTeachingTipClosingEventArgs(reason: reason)
        configuration.onClosing(args)
        guard !args.cancel else { return }
        if binding.get() { binding.set(false) }
        configuration.onClosed(reason)
        configuration.onDismiss()
    }

    @discardableResult
    private func positionPanel(duringTransition: Bool = false) -> Bool {
        guard let parentWindow = window, let panel, let chrome else { return false }
        guard transitionState == nil || duringTransition else {
            needsDeferredPosition = true
            return true
        }
        let anchor = parentWindow.convertToScreen(convert(bounds, to: nil))
        let candidates = placementCandidates()
        let allowed = rootBoundsOnScreen(in: parentWindow)
        var selected: (FluentTeachingTipResolvedPlacement, FluentTeachingTipGeometry)?

        for candidate in candidates where heroAllows(candidate) {
            let geometry = makeGeometry(for: candidate, anchor: anchor, chrome: chrome)
            if !configuration.shouldConstrainToRootBounds || geometry.fits(in: allowed, chrome: chrome) {
                selected = (candidate, geometry)
                break
            }
        }
        guard let selected else { return false }

        chrome.placement = selected.0
        panel.setFrame(selected.1.panelFrame, display: false)
        chrome.tailOffset = selected.1.tailOffset
        needsDeferredPosition = false
        return true
    }

    private func placementCandidates() -> [FluentTeachingTipResolvedPlacement] {
        var priorities: [FluentTeachingTipResolvedPlacement] = [
            .top, .bottom, .left, .right,
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .leftTop, .leftBottom, .rightTop, .rightBottom, .center
        ]
        guard let preferred = resolvedPreferredPlacement() else { return flowAdjusted(priorities) }

        // TeachingTip.cpp first re-orients the entire priority table toward the requested edge,
        // then rotates the exact corner/edge preference into slot zero.
        if preferred.isBelow {
            priorities.swapAt(0, 1)
            priorities.swapAt(4, 6)
            priorities.swapAt(5, 7)
        } else if preferred.isLeft {
            priorities.swapAt(0, 2)
            priorities.swapAt(1, 3)
            priorities.swapAt(4, 8)
            priorities.swapAt(5, 9)
            priorities.swapAt(6, 10)
            priorities.swapAt(7, 11)
        } else if preferred.isRight {
            priorities.swapAt(0, 2)
            priorities.swapAt(1, 3)
            priorities.swapAt(4, 8)
            priorities.swapAt(5, 9)
            priorities.swapAt(6, 10)
            priorities.swapAt(7, 11)
            priorities.swapAt(0, 1)
            priorities.swapAt(4, 6)
            priorities.swapAt(5, 7)
        }
        if let pivot = priorities.firstIndex(of: preferred), pivot > 0 {
            let prefix = Array(priorities[0..<pivot])
            priorities.remove(at: pivot)
            priorities.insert(preferred, at: 0)
            priorities.replaceSubrange(1...prefix.count, with: prefix)
        }
        return flowAdjusted(priorities)
    }

    private func resolvedPreferredPlacement() -> FluentTeachingTipResolvedPlacement? {
        switch configuration.placement {
        case .automatic: return nil
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        case .topRight: return .topRight
        case .topLeft: return .topLeft
        case .bottomRight: return .bottomRight
        case .bottomLeft: return .bottomLeft
        case .leftTop: return .leftTop
        case .leftBottom: return .leftBottom
        case .rightTop: return .rightTop
        case .rightBottom: return .rightBottom
        case .center: return .center
        case .leading:
            return context.layoutDirection == .rightToLeft ? .right : .left
        case .trailing:
            return context.layoutDirection == .rightToLeft ? .left : .right
        }
    }

    private func flowAdjusted(
        _ placements: [FluentTeachingTipResolvedPlacement]
    ) -> [FluentTeachingTipResolvedPlacement] {
        guard context.layoutDirection == .rightToLeft else { return placements }
        // leading/trailing are already resolved logically above; only source-named physical cases
        // and the automatic fallback order need WinUI's FlowDirection mirroring. The preferred
        // logical alias is kept, while its remaining physical fallbacks still mirror.
        if configuration.placement == .leading || configuration.placement == .trailing {
            guard let first = placements.first else { return [] }
            return [first] + placements.dropFirst().map { $0.mirrored() }
        }
        return placements.map { $0.mirrored() }
    }

    private func heroAllows(_ placement: FluentTeachingTipResolvedPlacement) -> Bool {
        guard configuration.heroContent != nil else { return true }
        switch configuration.heroContentPlacement {
        case .automatic: return true
        case .top:
            return ![.bottom, .bottomLeft, .bottomRight, .leftBottom, .rightBottom]
                .contains(placement)
        case .bottom:
            return ![.top, .topLeft, .topRight, .leftTop, .rightTop, .center]
                .contains(placement)
        }
    }

    private func rootBoundsOnScreen(in parentWindow: NSWindow) -> NSRect {
        guard configuration.shouldConstrainToRootBounds,
              let root = parentWindow.contentView else {
            return parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        }
        return parentWindow.convertToScreen(root.convert(root.bounds, to: nil))
    }

    private func makeGeometry(
        for placement: FluentTeachingTipResolvedPlacement,
        anchor: NSRect,
        chrome: FluentTeachingTipChrome
    ) -> FluentTeachingTipGeometry {
        let panelSize = chrome.panelSize(for: placement)
        let surface = chrome.surfaceFrame(for: placement)
        let near: CGFloat = 18
        let gap: CGFloat
        let origin: NSPoint
        let tailOffset: CGFloat

        if placement.isAbove {
            gap = 4 + configuration.placementMargin.bottom
            let localTailX: CGFloat
            switch placement {
            case .topRight: localTailX = surface.minX + near
            case .topLeft: localTailX = surface.maxX - near
            default: localTailX = surface.midX
            }
            tailOffset = localTailX
            origin = NSPoint(
                x: anchor.midX - localTailX,
                y: anchor.maxY + gap - FluentTeachingTipChrome.shadowMargin
            )
        } else if placement.isBelow {
            gap = 4 + configuration.placementMargin.top
            let localTailX: CGFloat
            switch placement {
            case .bottomRight: localTailX = surface.minX + near
            case .bottomLeft: localTailX = surface.maxX - near
            default: localTailX = surface.midX
            }
            tailOffset = localTailX
            origin = NSPoint(
                x: anchor.midX - localTailX,
                y: anchor.minY - gap - panelSize.height + FluentTeachingTipChrome.shadowMargin
            )
        } else if placement.isLeft {
            gap = 4 + configuration.placementMargin.right
            let localTailY: CGFloat
            switch placement {
            case .leftTop: localTailY = surface.minY + near
            case .leftBottom: localTailY = surface.maxY - near
            default: localTailY = surface.midY
            }
            tailOffset = localTailY
            origin = NSPoint(
                x: anchor.minX - gap - panelSize.width + FluentTeachingTipChrome.shadowMargin,
                y: anchor.midY - localTailY
            )
        } else {
            gap = 4 + configuration.placementMargin.left
            let localTailY: CGFloat
            switch placement {
            case .rightTop: localTailY = surface.minY + near
            case .rightBottom: localTailY = surface.maxY - near
            default: localTailY = surface.midY
            }
            tailOffset = localTailY
            origin = NSPoint(
                x: anchor.maxX + gap - FluentTeachingTipChrome.shadowMargin,
                y: anchor.midY - localTailY
            )
        }

        return FluentTeachingTipGeometry(
            panelFrame: NSRect(origin: origin, size: panelSize),
            surfaceFrame: surface.offsetBy(dx: origin.x, dy: origin.y),
            tailOffset: tailOffset
        )
    }

    private func animate(
        opening: Bool,
        panel: NSPanel,
        chrome: FluentTeachingTipChrome,
        placement: FluentTeachingTipResolvedPlacement,
        preparesInitialState: Bool = false,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard let chromeLayer = chrome.layer else {
            completion?()
            return
        }
        transitionGeneration &+= 1
        let generation = transitionGeneration
        transitionState = opening ? .opening : .closing
        animationCoordinator.reduceMotion = context.reduceMotion
        panel.alphaValue = 1
        let motion = opening ? FluentMotion.teachingTipOpen : FluentMotion.teachingTipClose
        let offset = Self.offset(for: placement, distance: motion.distance)
        let anchor = CGPoint(
            x: chromeLayer.bounds.minX + chromeLayer.bounds.width * chromeLayer.anchorPoint.x,
            y: chromeLayer.bounds.minY + chromeLayer.bounds.height * chromeLayer.anchorPoint.y
        )
        let center = CGPoint(x: chromeLayer.bounds.midX, y: chromeLayer.bounds.midY)
        let compact = CGAffineTransform(
            a: motion.scale,
            b: 0,
            c: 0,
            d: motion.scale,
            tx: offset.x + (center.x - anchor.x) * (1 - motion.scale),
            ty: offset.y + (center.y - anchor.y) * (1 - motion.scale)
        )
        if preparesInitialState {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            chromeLayer.opacity = 0
            chromeLayer.setAffineTransform(compact)
            chromeLayer.shadowOpacity = 0
            CATransaction.commit()
        }
        let targetTransform = opening ? CATransform3DIdentity : CATransform3DMakeAffineTransform(compact)
        let targetOpacity: Float = opening ? 1 : 0
        let targetShadow: Float = opening ? 0.16 : 0
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: chromeLayer,
                    key: "fluent.teachingTip.opacity",
                    keyPath: "opacity",
                    toValue: targetOpacity
                ) { chromeLayer.opacity = targetOpacity },
                FluentLayerAnimationChange(
                    layer: chromeLayer,
                    key: "fluent.teachingTip.transform",
                    keyPath: "transform",
                    toValue: NSValue(caTransform3D: targetTransform)
                ) { chromeLayer.transform = targetTransform },
                FluentLayerAnimationChange(
                    layer: chromeLayer,
                    key: "fluent.teachingTip.shadow",
                    keyPath: "shadowOpacity",
                    toValue: targetShadow
                ) { chromeLayer.shadowOpacity = targetShadow }
            ],
            motion: motion,
            animated: animated,
            completion: { [weak self, weak panel] in
                guard let self,
                      let panel,
                      self.panel === panel,
                      self.transitionGeneration == generation else { return }
                self.transitionState = nil
                if opening {
                    self.pendingCloseReason = .programmatic
                    if self.needsDeferredPosition { _ = self.positionPanel() }
                    self.configuration.onOpened()
                    self.synchronizePresentation()
                }
                completion?()
            }
        )
    }

    private static func offset(
        for placement: FluentTeachingTipResolvedPlacement,
        distance: CGFloat
    ) -> NSPoint {
        if placement.isAbove { return NSPoint(x: 0, y: -distance) }
        if placement.isBelow { return NSPoint(x: 0, y: distance) }
        if placement.isLeft { return NSPoint(x: distance, y: 0) }
        return NSPoint(x: -distance, y: 0)
    }

    private func installOutsideClickMonitors(panel: NSPanel) {
        removeOutsideClickMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak panel] event in
            if event.window !== panel { self?.requestDismissal(reason: .lightDismiss) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.requestDismissal(reason: .lightDismiss)
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit {
        if let observerID { binding.removeObserver(observerID) }
        removeOutsideClickMonitors()
        if let panel {
            animationCoordinator.cancelAll(on: [chrome?.layer].compactMap { $0 })
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}

private struct FluentTeachingTipGeometry {
    var panelFrame: NSRect
    var surfaceFrame: NSRect
    var tailOffset: CGFloat

    func fits(in allowed: NSRect, chrome: FluentTeachingTipChrome) -> Bool {
        let tolerance: CGFloat = 0.5
        return surfaceFrame.minX >= allowed.minX - tolerance
            && surfaceFrame.maxX <= allowed.maxX + tolerance
            && surfaceFrame.minY >= allowed.minY - tolerance
            && surfaceFrame.maxY <= allowed.maxY + tolerance
    }
}

private final class FluentTeachingTipPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
}

private final class FluentTeachingTipChrome: NSView {
    static let shadowMargin: CGFloat = 16
    private static let tailLength: CGFloat = 8
    private static let tailHalfWidth: CGFloat = 10

    private var configuration: FluentTeachingTipConfiguration
    private var context: FluentRenderContext
    var placement: FluentTeachingTipResolvedPlacement = .top {
        didSet {
            frame.size = panelSize
            needsLayout = true
            needsDisplay = true
        }
    }
    var tailOffset: CGFloat = 0 { didSet { needsLayout = true; updateShadowPath() } }
    var onRequestClose: ((FluentTeachingTipCloseReason) -> Void)?

    private let material = FluentMaterialView(material: .liquidGlass)
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let iconView = NSImageView()
    private let headerCloseButton = FluentTeachingTipHeaderCloseButton()
    private let actionButton = FluentButton()
    private let footerCloseButton = FluentButton()
    private let tailFillLayer = CAShapeLayer()
    private let tailOutlineLayer = CAShapeLayer()
    private let topHighlightLayer = CAShapeLayer()
    private let content: NSView
    private var heroHost: FluentViewHost<FluentAnyView>?

    var preferredInitialResponder: NSView? {
        if !actionButton.isHidden { return actionButton }
        if !footerCloseButton.isHidden { return footerCloseButton }
        if !headerCloseButton.isHidden { return headerCloseButton }
        return nil
    }

    var panelSize: NSSize { panelSize(for: placement) }

    init(
        content: NSView,
        configuration: FluentTeachingTipConfiguration,
        context: FluentRenderContext
    ) {
        self.content = content
        self.configuration = configuration
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.Chrome")
        frame.size = panelSize
        wantsLayer = true
        layer?.name = "FluentKit.TeachingTip.Chrome"
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowOpacity = 0.16
        tailFillLayer.name = "FluentKit.TeachingTip.TailFill"
        tailFillLayer.zPosition = 8
        tailOutlineLayer.name = "FluentKit.TeachingTip.TailOutline"
        tailOutlineLayer.fillColor = nil
        tailOutlineLayer.lineJoin = .round
        tailOutlineLayer.lineCap = .round
        tailOutlineLayer.zPosition = 9
        layer?.addSublayer(tailFillLayer)
        layer?.addSublayer(tailOutlineLayer)
        topHighlightLayer.fillColor = nil
        topHighlightLayer.lineCap = .round
        topHighlightLayer.zPosition = 10
        layer?.addSublayer(topHighlightLayer)

        material.wantsLayer = true
        addSubview(material)
        [content, titleLabel, subtitleLabel, iconView, headerCloseButton, actionButton, footerCloseButton]
            .forEach(material.addSubview)

        titleLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.Title")
        subtitleLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.Subtitle")
        iconView.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.Icon")
        headerCloseButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.HeaderCloseButton")
        actionButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.ActionButton")
        footerCloseButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.CloseButton")

        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.lineBreakMode = .byWordWrapping
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        headerCloseButton.onInvoke = { [weak self] in self?.invokeCloseButton() }
        actionButton.onClick = { [weak self] in self?.configuration.onActionButtonClick() }
        footerCloseButton.onClick = { [weak self] in self?.invokeCloseButton() }

        updateHero(configuration.heroContent)
        applyConfiguration()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { configuration.isLightDismissEnabled }

    func update(configuration: FluentTeachingTipConfiguration, context: FluentRenderContext) {
        self.configuration = configuration
        self.context = context
        updateHero(configuration.heroContent)
        applyConfiguration()
        frame.size = panelSize
        needsLayout = true
        needsDisplay = true
    }

    func panelSize(for placement: FluentTeachingTipResolvedPlacement) -> NSSize {
        let tail = configuration.showsTail ? Self.tailLength : 0
        if placement.isLeft || placement.isRight {
            return NSSize(
                width: configuration.surfaceSize.width + Self.shadowMargin * 2 + tail,
                height: configuration.surfaceSize.height + Self.shadowMargin * 2
            )
        }
        return NSSize(
            width: configuration.surfaceSize.width + Self.shadowMargin * 2,
            height: configuration.surfaceSize.height + Self.shadowMargin * 2 + tail
        )
    }

    func surfaceFrame(for placement: FluentTeachingTipResolvedPlacement) -> NSRect {
        let tail = configuration.showsTail ? Self.tailLength : 0
        if placement.isAbove {
            return NSRect(
                x: Self.shadowMargin,
                y: Self.shadowMargin + tail,
                width: configuration.surfaceSize.width,
                height: configuration.surfaceSize.height
            )
        }
        if placement.isBelow || placement == .center {
            return NSRect(
                x: Self.shadowMargin,
                y: Self.shadowMargin,
                width: configuration.surfaceSize.width,
                height: configuration.surfaceSize.height
            )
        }
        if placement.isLeft {
            return NSRect(
                x: Self.shadowMargin,
                y: Self.shadowMargin,
                width: configuration.surfaceSize.width,
                height: configuration.surfaceSize.height
            )
        }
        return NSRect(
            x: Self.shadowMargin + tail,
            y: Self.shadowMargin,
            width: configuration.surfaceSize.width,
            height: configuration.surfaceSize.height
        )
    }

    override func layout() {
        super.layout()
        material.frame = surfaceFrame(for: placement)
        layoutContent()
        updateTailLayers()
        updateShadowPath()
        updateTopHighlight()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        if configuration.isLightDismissEnabled {
            onRequestClose?(.lightDismiss)
        } else {
            invokeCloseButton()
        }
    }

    private func applyConfiguration() {
        let theme = context.theme
        titleLabel.stringValue = configuration.title
        titleLabel.font = theme.typography.font(for: .headline)
        titleLabel.textColor = theme.textPrimary
        titleLabel.isHidden = configuration.title.isEmpty
        subtitleLabel.stringValue = configuration.subtitle
        subtitleLabel.font = theme.typography.font(for: .body)
        subtitleLabel.textColor = theme.textSecondary
        subtitleLabel.isHidden = configuration.subtitle.isEmpty
        iconView.image = configuration.systemImageName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: configuration.title)
        }
        iconView.contentTintColor = theme.textPrimary
        iconView.isHidden = iconView.image == nil

        headerCloseButton.isHidden = !configuration.showsHeaderCloseButton
        headerCloseButton.theme = theme
        actionButton.title = configuration.actionButtonTitle ?? ""
        actionButton.isHidden = configuration.actionButtonTitle == nil
        actionButton.theme = theme
        actionButton.reduceMotion = context.reduceMotion
        footerCloseButton.title = configuration.closeButtonTitle ?? ""
        footerCloseButton.isHidden = configuration.closeButtonTitle == nil
        footerCloseButton.theme = theme
        footerCloseButton.reduceMotion = context.reduceMotion

        let lightDismiss = configuration.isLightDismissEnabled
        let selectedMaterial = theme.material(for: .transient)
        let presetTint = selectedMaterial == .mica || selectedMaterial == .acrylic ? nil
            : theme.micaTint.withAlphaComponent(theme.isDark ? 0.88 : 0.78)
        material.configure(theme: theme, role: .transient,
            preset: .init(tintColor: presetTint, isEnabled: lightDismiss),
            fallback: { lightDismiss ? $0.flyoutSurfaceFill : $0.teachingTipBackground })
        material.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        material.layer?.borderWidth = theme.controlStrokeWidth
        material.layer?.borderColor = theme.surfaceStrokeFlyout.cgColor
        material.layer?.masksToBounds = true
        tailFillLayer.fillColor = resolvedSurfaceFill.cgColor
        tailOutlineLayer.strokeColor = theme.surfaceStrokeFlyout.cgColor
        tailOutlineLayer.lineWidth = theme.controlStrokeWidth
        topHighlightLayer.strokeColor = theme.teachingTipTopHighlight.cgColor
        topHighlightLayer.isHidden = theme.isHighContrast

        setAccessibilityElement(true)
        setAccessibilityRole(configuration.isLightDismissEnabled ? .window : .group)
        setAccessibilityModal(configuration.isLightDismissEnabled)
        setAccessibilityLabel(configuration.title.isEmpty ? "Teaching tip" : configuration.title)
    }

    private var resolvedSurfaceFill: NSColor {
        if configuration.isLightDismissEnabled { return context.theme.flyoutSurfaceFill }
        return context.theme.teachingTipBackground
    }

    private func updateHero(_ heroContent: FluentAnyView?) {
        if let heroContent {
            if let heroHost {
                heroHost.update(heroContent, context: context)
            } else {
                let host = FluentViewHost(heroContent, context: context)
                host.identifier = NSUserInterfaceItemIdentifier("FluentKit.TeachingTip.HeroContent")
                material.addSubview(host)
                heroHost = host
            }
        } else if let heroHost {
            heroHost.removeFromSuperview()
            self.heroHost = nil
        }
    }

    private func layoutContent() {
        let bounds = material.bounds
        var body = bounds
        if let heroHost {
            let fitting = heroHost.fittingSize.height
            let heroHeight = min(max(fitting.isFinite && fitting > 0 ? fitting : 80, 40), bounds.height * 0.45)
            let placement = resolvedHeroPlacement
            if placement == .top {
                heroHost.frame = NSRect(x: 0, y: bounds.maxY - heroHeight, width: bounds.width, height: heroHeight)
                body.size.height -= heroHeight
            } else {
                heroHost.frame = NSRect(x: 0, y: 0, width: bounds.width, height: heroHeight)
                body.origin.y += heroHeight
                body.size.height -= heroHeight
            }
            heroHost.isHidden = false
        }

        let padding: CGFloat = 12
        var contentRect = body.insetBy(dx: padding, dy: padding)
        let hasFooter = !actionButton.isHidden || !footerCloseButton.isHidden
        if hasFooter {
            let footerHeight: CGFloat = 32
            let gap: CGFloat = 4
            if !actionButton.isHidden && !footerCloseButton.isHidden {
                let width = max((contentRect.width - gap) / 2, 0)
                actionButton.frame = NSRect(x: contentRect.minX, y: contentRect.minY, width: width, height: footerHeight)
                footerCloseButton.frame = NSRect(x: actionButton.frame.maxX + gap, y: contentRect.minY, width: width, height: footerHeight)
            } else if !actionButton.isHidden {
                actionButton.frame = NSRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: footerHeight)
            } else {
                footerCloseButton.frame = NSRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: footerHeight)
            }
            contentRect.origin.y += footerHeight + 12
            contentRect.size.height = max(contentRect.height - footerHeight - 12, 0)
        }

        if !headerCloseButton.isHidden {
            headerCloseButton.frame = NSRect(
                x: body.maxX - 40,
                y: body.maxY - 40,
                width: 40,
                height: 40
            )
        }

        var textX = contentRect.minX
        var textWidth = contentRect.width - (configuration.showsHeaderCloseButton ? 32 : 0)
        var top = contentRect.maxY
        if !iconView.isHidden {
            iconView.frame = NSRect(x: textX, y: top - 20, width: 20, height: 20)
            textX += 32
            textWidth = max(textWidth - 32, 0)
        }
        if !titleLabel.isHidden {
            let height = measuredHeight(for: titleLabel, width: textWidth, maximum: 40)
            titleLabel.frame = NSRect(x: textX, y: top - height, width: textWidth, height: height)
            top -= height + 4
        }
        if !subtitleLabel.isHidden {
            let height = measuredHeight(for: subtitleLabel, width: textWidth, maximum: 54)
            subtitleLabel.frame = NSRect(x: textX, y: top - height, width: textWidth, height: height)
            top -= height + 8
        }
        content.frame = NSRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: contentRect.width,
            height: max(top - contentRect.minY, 0)
        )
    }

    private var resolvedHeroPlacement: FluentTeachingTipHeroContentPlacement {
        switch configuration.heroContentPlacement {
        case .top, .bottom: return configuration.heroContentPlacement
        case .automatic:
            return placement.isBelow ? .bottom : .top
        }
    }

    private func measuredHeight(for label: NSTextField, width: CGFloat, maximum: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: label.font as Any]
        let rect = (label.stringValue as NSString).boundingRect(
            with: NSSize(width: width, height: maximum),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return min(max(ceil(rect.height), label.font?.pointSize ?? 0), maximum)
    }

    private func invokeCloseButton() {
        configuration.onCloseButtonClick()
        onRequestClose?(.closeButton)
    }

    private func tailPath(overlap: CGFloat = 0) -> NSBezierPath {
        let surface = surfaceFrame(for: placement)
        let path = NSBezierPath()
        if placement.isAbove {
            let center = min(max(tailOffset, surface.minX + 18), surface.maxX - 18)
            path.move(to: NSPoint(x: center - Self.tailHalfWidth, y: surface.minY + overlap))
            path.line(to: NSPoint(x: center, y: Self.shadowMargin))
            path.line(to: NSPoint(x: center + Self.tailHalfWidth, y: surface.minY + overlap))
        } else if placement.isBelow {
            let center = min(max(tailOffset, surface.minX + 18), surface.maxX - 18)
            path.move(to: NSPoint(x: center - Self.tailHalfWidth, y: surface.maxY - overlap))
            path.line(to: NSPoint(x: center, y: bounds.maxY - Self.shadowMargin))
            path.line(to: NSPoint(x: center + Self.tailHalfWidth, y: surface.maxY - overlap))
        } else if placement.isLeft {
            let center = min(max(tailOffset, surface.minY + 18), surface.maxY - 18)
            path.move(to: NSPoint(x: surface.maxX - overlap, y: center - Self.tailHalfWidth))
            path.line(to: NSPoint(x: bounds.maxX - Self.shadowMargin, y: center))
            path.line(to: NSPoint(x: surface.maxX - overlap, y: center + Self.tailHalfWidth))
        } else {
            let center = min(max(tailOffset, surface.minY + 18), surface.maxY - 18)
            path.move(to: NSPoint(x: surface.minX + overlap, y: center - Self.tailHalfWidth))
            path.line(to: NSPoint(x: Self.shadowMargin, y: center))
            path.line(to: NSPoint(x: surface.minX + overlap, y: center + Self.tailHalfWidth))
        }
        path.close()
        return path
    }

    private func tailOutlinePath() -> NSBezierPath {
        let surface = surfaceFrame(for: placement)
        let path = NSBezierPath()
        if placement.isAbove {
            let center = min(max(tailOffset, surface.minX + 18), surface.maxX - 18)
            path.move(to: NSPoint(x: center - Self.tailHalfWidth, y: surface.minY))
            path.line(to: NSPoint(x: center, y: Self.shadowMargin))
            path.line(to: NSPoint(x: center + Self.tailHalfWidth, y: surface.minY))
        } else if placement.isBelow {
            let center = min(max(tailOffset, surface.minX + 18), surface.maxX - 18)
            path.move(to: NSPoint(x: center - Self.tailHalfWidth, y: surface.maxY))
            path.line(to: NSPoint(x: center, y: bounds.maxY - Self.shadowMargin))
            path.line(to: NSPoint(x: center + Self.tailHalfWidth, y: surface.maxY))
        } else if placement.isLeft {
            let center = min(max(tailOffset, surface.minY + 18), surface.maxY - 18)
            path.move(to: NSPoint(x: surface.maxX, y: center - Self.tailHalfWidth))
            path.line(to: NSPoint(x: bounds.maxX - Self.shadowMargin, y: center))
            path.line(to: NSPoint(x: surface.maxX, y: center + Self.tailHalfWidth))
        } else {
            let center = min(max(tailOffset, surface.minY + 18), surface.maxY - 18)
            path.move(to: NSPoint(x: surface.minX, y: center - Self.tailHalfWidth))
            path.line(to: NSPoint(x: Self.shadowMargin, y: center))
            path.line(to: NSPoint(x: surface.minX, y: center + Self.tailHalfWidth))
        }
        return path
    }

    private func updateTailLayers() {
        let visible = configuration.showsTail
        tailFillLayer.isHidden = !visible
        tailOutlineLayer.isHidden = !visible
        guard visible else {
            tailFillLayer.path = nil
            tailOutlineLayer.path = nil
            return
        }
        let scale = max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
        let overlap = max(context.theme.controlStrokeWidth, 1 / scale)
        tailFillLayer.path = tailPath(overlap: overlap).fluentCGPath
        tailOutlineLayer.path = tailOutlinePath().fluentCGPath
    }

    private func updateShadowPath() {
        let path = NSBezierPath(
            roundedRect: surfaceFrame(for: placement),
            xRadius: context.theme.designTokens.cardCornerRadius,
            yRadius: context.theme.designTokens.cardCornerRadius
        )
        if configuration.showsTail { path.append(tailPath()) }
        layer?.shadowPath = path.fluentCGPath
    }

    private func updateTopHighlight() {
        let surface = surfaceFrame(for: placement)
        let radius = context.theme.designTokens.cardCornerRadius
        let startX = surface.minX + radius
        let endX = surface.maxX - radius
        let y = surface.maxY - 0.5
        let path = CGMutablePath()
        if placement.isBelow && configuration.showsTail {
            let center = min(max(tailOffset, surface.minX + 18), surface.maxX - 18)
            let gap = Self.tailHalfWidth + 1
            if center - gap > startX {
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: center - gap, y: y))
            }
            if center + gap < endX {
                path.move(to: CGPoint(x: center + gap, y: y))
                path.addLine(to: CGPoint(x: endX, y: y))
            }
        } else {
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
        }
        topHighlightLayer.path = path
        topHighlightLayer.lineWidth = 1 / max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
    }
}

private final class FluentTeachingTipHeaderCloseButton: NSButton {
    var theme: FluentTheme = .current { didSet { updateAppearance() } }
    var onInvoke: (() -> Void)?
    private var hovering = false
    private var pressing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(invoke)
        wantsLayer = true
        layer?.cornerRadius = FluentTheme.current.designTokens.controlCornerRadius
        fluentSetDefaultAccessibilityLabel("Close")
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) {
        pressing = true
        updateAppearance()
        super.mouseDown(with: event)
        pressing = false
        updateAppearance()
    }

    @objc private func invoke() { onInvoke?() }

    private func updateAppearance() {
        contentTintColor = theme.textPrimary
        let fill: NSColor
        if pressing { fill = theme.subtleFillTertiary }
        else if hovering { fill = theme.subtleFillSecondary }
        else { fill = .clear }
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = theme.designTokens.controlCornerRadius
    }
}

private extension NSBezierPath {
    var fluentCGPath: CGPath {
        let result = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                result.move(to: points[0])
            case .lineTo:
                result.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                result.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                result.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                result.closeSubpath()
            @unknown default:
                break
            }
        }
        return result
    }
}
