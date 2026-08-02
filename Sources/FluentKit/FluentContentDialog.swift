import AppKit

public enum FluentContentDialogResult: Hashable, Sendable {
    case none
    case primary
    case secondary
}

public enum FluentContentDialogButton: Hashable, Sendable {
    case none
    case primary
    case secondary
    case close
}

public struct FluentContentDialogConfiguration: Hashable, Sendable {
    public var title: String
    public var primaryButtonText: String?
    public var secondaryButtonText: String?
    public var closeButtonText: String?
    public var defaultButton: FluentContentDialogButton
    public var isPrimaryButtonEnabled: Bool
    public var isSecondaryButtonEnabled: Bool

    public init(
        title: String,
        primaryButtonText: String? = nil,
        secondaryButtonText: String? = nil,
        closeButtonText: String? = nil,
        defaultButton: FluentContentDialogButton = .none,
        isPrimaryButtonEnabled: Bool = true,
        isSecondaryButtonEnabled: Bool = true
    ) {
        self.title = title
        self.primaryButtonText = primaryButtonText
        self.secondaryButtonText = secondaryButtonText
        self.closeButtonText = closeButtonText
        self.defaultButton = defaultButton
        self.isPrimaryButtonEnabled = isPrimaryButtonEnabled
        self.isSecondaryButtonEnabled = isSecondaryButtonEnabled
    }
}

public final class FluentContentDialogClosingDeferral {
    private let lock = NSLock()
    private var completion: (() -> Void)?

    fileprivate init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    public func complete() {
        let action: (() -> Void)? = lock.withLock {
            defer { completion = nil }
            return completion
        }
        action?()
    }
}

public final class FluentContentDialogClosingEventArgs {
    public let result: FluentContentDialogResult

    public var isCancelled: Bool {
        get { lock.withLock { cancelled } }
        set { lock.withLock { cancelled = newValue } }
    }

    private let lock = NSLock()
    private var cancelled = false
    private var pendingDeferrals = 0
    private var handlerReturned = false
    private var didResolve = false
    private var resolution: ((Bool) -> Void)?

    fileprivate init(result: FluentContentDialogResult) {
        self.result = result
    }

    public func getDeferral() -> FluentContentDialogClosingDeferral {
        lock.withLock { pendingDeferrals += 1 }
        return FluentContentDialogClosingDeferral { [self] in
            completeDeferral()
        }
    }

    fileprivate func finishHandler(_ resolution: @escaping (Bool) -> Void) {
        let outcome: Bool? = lock.withLock {
            guard !didResolve else { return nil }
            handlerReturned = true
            self.resolution = resolution
            guard pendingDeferrals == 0 else { return nil }
            didResolve = true
            self.resolution = nil
            return cancelled
        }
        if let outcome { dispatchResolution(resolution, cancelled: outcome) }
    }

    private func completeDeferral() {
        let resolved: (((Bool) -> Void), Bool)? = lock.withLock {
            guard pendingDeferrals > 0 else { return nil }
            pendingDeferrals -= 1
            guard handlerReturned, pendingDeferrals == 0, !didResolve, let resolution else { return nil }
            didResolve = true
            self.resolution = nil
            return (resolution, cancelled)
        }
        if let resolved { dispatchResolution(resolved.0, cancelled: resolved.1) }
    }

    private func dispatchResolution(_ resolution: @escaping (Bool) -> Void, cancelled: Bool) {
        if Thread.isMainThread {
            resolution(cancelled)
        } else {
            DispatchQueue.main.async { resolution(cancelled) }
        }
    }
}

public struct FluentContentDialog<Content: FluentView, DialogContent: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let dialogContent: DialogContent
    fileprivate let isPresented: FluentBinding<Bool>
    fileprivate let configuration: FluentContentDialogConfiguration
    fileprivate let onClosing: (FluentContentDialogClosingEventArgs) -> Void
    fileprivate let onClosed: (FluentContentDialogResult) -> Void

    public init(
        isPresented: FluentBinding<Bool>,
        configuration: FluentContentDialogConfiguration,
        onClosing: @escaping (FluentContentDialogClosingEventArgs) -> Void = { _ in },
        onClosed: @escaping (FluentContentDialogResult) -> Void = { _ in },
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder dialogContent: () -> DialogContent
    ) {
        self.content = content()
        self.dialogContent = dialogContent()
        self.isPresented = isPresented
        self.configuration = configuration
        self.onClosing = onClosing
        self.onClosed = onClosed
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentContentDialogHost(
            content: content._mount(in: context),
            dialogContent: dialogContent,
            isPresented: isPresented,
            configuration: configuration,
            onClosing: onClosing,
            onClosed: onClosed,
            context: context
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentContentDialogHost<DialogContent> else { return false }
        host.update(
            dialogContent: dialogContent,
            isPresented: isPresented,
            configuration: configuration,
            onClosing: onClosing,
            onClosed: onClosed,
            context: context
        )
        return host.updateContent?(host.contentView, context) ?? false
    }
}

public extension FluentView {
    func contentDialog<DialogContent: FluentView>(
        isPresented: FluentBinding<Bool>,
        configuration: FluentContentDialogConfiguration,
        onClosing: @escaping (FluentContentDialogClosingEventArgs) -> Void = { _ in },
        onClosed: @escaping (FluentContentDialogResult) -> Void = { _ in },
        @FluentViewBuilder content: () -> DialogContent
    ) -> FluentContentDialog<Self, DialogContent> {
        FluentContentDialog(
            isPresented: isPresented,
            configuration: configuration,
            onClosing: onClosing,
            onClosed: onClosed,
            content: { self },
            dialogContent: content
        )
    }

    func contentDialog<DialogContent: FluentView>(
        _ title: String,
        isPresented: FluentBinding<Bool>,
        primaryButtonText: String? = nil,
        secondaryButtonText: String? = nil,
        closeButtonText: String? = nil,
        defaultButton: FluentContentDialogButton = .none,
        isPrimaryButtonEnabled: Bool = true,
        isSecondaryButtonEnabled: Bool = true,
        onClosing: @escaping (FluentContentDialogClosingEventArgs) -> Void = { _ in },
        onClosed: @escaping (FluentContentDialogResult) -> Void = { _ in },
        @FluentViewBuilder content: () -> DialogContent
    ) -> FluentContentDialog<Self, DialogContent> {
        contentDialog(
            isPresented: isPresented,
            configuration: FluentContentDialogConfiguration(
                title: title,
                primaryButtonText: primaryButtonText,
                secondaryButtonText: secondaryButtonText,
                closeButtonText: closeButtonText,
                defaultButton: defaultButton,
                isPrimaryButtonEnabled: isPrimaryButtonEnabled,
                isSecondaryButtonEnabled: isSecondaryButtonEnabled
            ),
            onClosing: onClosing,
            onClosed: onClosed,
            content: content
        )
    }
}

private final class FluentContentDialogHost<DialogContent: FluentView>: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    private var dialogContent: DialogContent
    private var isPresented: FluentBinding<Bool>
    private var configuration: FluentContentDialogConfiguration
    private var onClosing: (FluentContentDialogClosingEventArgs) -> Void
    private var onClosed: (FluentContentDialogResult) -> Void
    private var context: FluentRenderContext
    private var observerID: UUID?
    private weak var presentationCoordinator: FluentPresentationCoordinator?
    private var presentationToken: FluentPresentationCoordinator.Token?
    private weak var overlay: FluentContentDialogOverlay<DialogContent>?
    private var generation: UInt64 = 0
    private var closeDecisionPending = false
    private var isClosing = false

    init(
        content: NSView,
        dialogContent: DialogContent,
        isPresented: FluentBinding<Bool>,
        configuration: FluentContentDialogConfiguration,
        onClosing: @escaping (FluentContentDialogClosingEventArgs) -> Void,
        onClosed: @escaping (FluentContentDialogResult) -> Void,
        context: FluentRenderContext
    ) {
        self.dialogContent = dialogContent
        self.isPresented = isPresented
        self.configuration = configuration
        self.onClosing = onClosing
        self.onClosed = onClosed
        self.context = context
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            cancelPresentation()
            return
        }
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    func update(
        dialogContent: DialogContent,
        isPresented: FluentBinding<Bool>,
        configuration: FluentContentDialogConfiguration,
        onClosing: @escaping (FluentContentDialogClosingEventArgs) -> Void,
        onClosed: @escaping (FluentContentDialogResult) -> Void,
        context: FluentRenderContext
    ) {
        let reusesObservation = self.isPresented.observationIdentity != nil
            && self.isPresented.observationIdentity == isPresented.observationIdentity
        if !reusesObservation, let observerID { self.isPresented.removeObserver(observerID) }
        self.dialogContent = dialogContent
        self.isPresented = isPresented
        self.configuration = configuration
        self.onClosing = onClosing
        self.onClosed = onClosed
        self.context = context
        if !reusesObservation { installObserver() }
        overlay?.update(content: dialogContent, configuration: configuration, context: context)
        overlay?.setActionsEnabled(!(closeDecisionPending || isClosing))
        synchronizePresentation()
    }

    private func installObserver() {
        observerID = isPresented.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func synchronizePresentation() {
        guard let parentWindow = window else {
            cancelPresentation()
            return
        }

        if isPresented.get() {
            guard presentationToken == nil else {
                overlay?.update(content: dialogContent, configuration: configuration, context: context)
                return
            }
            let coordinator = FluentPresentationCoordinator.coordinator(for: parentWindow)
            presentationCoordinator = coordinator
            presentationToken = coordinator.enqueue(
                owner: self,
                present: { [weak self, weak parentWindow] in
                    guard let self, let parentWindow else { return }
                    self.beginPresentation(on: parentWindow)
                },
                cancel: { [weak self] in self?.endPresentationForCancellation() }
            )
        } else if overlay != nil {
            requestClose(result: .none)
        } else if let token = presentationToken {
            presentationCoordinator?.cancel(token)
            if presentationToken === token { presentationToken = nil }
        }
    }

    private func beginPresentation(on parentWindow: NSWindow) {
        guard let token = presentationToken else { return }
        guard isPresented.get(), let container = parentWindow.contentView else {
            presentationCoordinator?.finish(token)
            presentationToken = nil
            return
        }

        generation &+= 1
        let currentGeneration = generation
        var presentationContext = context
        if let appearanceCoordinator = parentWindow.fluentAppearanceCoordinator {
            presentationContext.theme = appearanceCoordinator.theme
            presentationContext.appearanceCoordinator = appearanceCoordinator
        }
        let presented = FluentContentDialogOverlay(
            content: dialogContent,
            configuration: configuration,
            context: presentationContext
        )
        overlay = presented
        presented.onRequestClose = { [weak self, weak presented] result in
            guard self?.overlay === presented else { return }
            self?.requestClose(result: result)
        }
        presented.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(presented, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            presented.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            presented.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            presented.topAnchor.constraint(equalTo: container.topAnchor),
            presented.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        container.layoutSubtreeIfNeeded()
        presented.prepareForPresentation()
        presented.present(animated: !context.reduceMotion) { [weak self, weak presented] in
            guard let self, self.generation == currentGeneration, self.overlay === presented else { return }
            presented?.moveFocusIntoDialog()
        }
    }

    private func requestClose(result: FluentContentDialogResult) {
        guard overlay != nil, !closeDecisionPending, !isClosing else { return }
        closeDecisionPending = true
        overlay?.setActionsEnabled(false)
        let args = FluentContentDialogClosingEventArgs(result: result)
        onClosing(args)
        let currentGeneration = generation
        args.finishHandler { [weak self] cancelled in
            guard let self, self.generation == currentGeneration, self.overlay != nil else { return }
            self.closeDecisionPending = false
            if cancelled {
                self.overlay?.setActionsEnabled(true)
                if !self.isPresented.get() { self.isPresented.set(true) }
                return
            }
            self.beginClose(result: result, generation: currentGeneration)
        }
    }

    private func beginClose(result: FluentContentDialogResult, generation: UInt64) {
        guard let token = presentationToken, let presented = overlay else { return }
        isClosing = true
        if isPresented.get() { isPresented.set(false) }
        presented.dismiss(animated: !context.reduceMotion) { [weak self, weak presented] in
            guard let self,
                  self.generation == generation,
                  self.presentationToken === token,
                  self.overlay === presented else { return }
            presented?.removeFromSuperview()
            self.overlay = nil
            self.presentationToken = nil
            self.isClosing = false
            self.closeDecisionPending = false
            self.presentationCoordinator?.finish(token)
            self.onClosed(result)
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func cancelPresentation() {
        guard let token = presentationToken else { return }
        presentationCoordinator?.cancel(token)
        if presentationToken === token { presentationToken = nil }
    }

    private func endPresentationForCancellation() {
        guard let token = presentationToken else { return }
        generation &+= 1
        overlay?.dismiss(animated: false)
        overlay?.removeFromSuperview()
        overlay = nil
        closeDecisionPending = false
        isClosing = false
        presentationToken = nil
        presentationCoordinator?.finish(token)
    }

    deinit {
        if let observerID { isPresented.removeObserver?(observerID) }
        if let token = presentationToken { presentationCoordinator?.cancel(token) }
    }
}

private final class FluentContentDialogOverlay<Content: FluentView>: NSView {
    var onRequestClose: ((FluentContentDialogResult) -> Void)?

    private let dimmingView = NSView()
    private let surfaceContainer = NSView()
    private let materialView: FluentMaterialView
    private let contentTintView = NSView()
    private let commandSurfaceView = NSView()
    private let commandSeparatorView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let documentView = FluentContentDialogDocumentView()
    private let contentHost: FluentViewHost<Content>
    private let buttonStack = NSStackView()
    private let animationCoordinator: FluentAnimationCoordinator
    private var configuration: FluentContentDialogConfiguration
    private var context: FluentRenderContext
    private var buttons: [(kind: FluentContentDialogButton, button: FluentButton)] = []
    private var titleToContentConstraint: NSLayoutConstraint!
    private var titleHeightConstraint: NSLayoutConstraint!
    private var materialToCommandConstraint: NSLayoutConstraint!
    private var materialToBottomConstraint: NSLayoutConstraint!
    private var commandHeightConstraint: NSLayoutConstraint!
    private var surfaceWidthConstraint: NSLayoutConstraint!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var escapeMonitor: Any?
    private var isUpdatingGeometry = false
    private weak var registeredAppearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    private var isTransitioning = false
    private var transitionPhase: TransitionPhase = .idle
    private var transitionCompletion: (() -> Void)?
    private var actionsEnabled = true

    private enum TransitionPhase: Equatable {
        case idle
        case presenting
        case dismissing
    }

    init(
        content: Content,
        configuration: FluentContentDialogConfiguration,
        context: FluentRenderContext
    ) {
        self.configuration = configuration
        self.context = context
        contentHost = FluentViewHost(content, context: context)
        materialView = FluentMaterialView(material: context.theme.material(for: .transient) ?? .liquidGlass)
        animationCoordinator = FluentAnimationCoordinator(reduceMotion: context.reduceMotion)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.Overlay")
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilitySubrole(.dialog)
        setAccessibilityModal(true)
        setAccessibilityLabel(configuration.title.isEmpty ? "Dialog" : configuration.title)
        buildViewHierarchy()
        apply(configuration: configuration, context: context, rebuildButtons: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEscapeMonitor()
            unregisterAppearanceUpdates()
        } else {
            installEscapeMonitor()
            registerAppearanceUpdates()
        }
    }

    override func layout() {
        super.layout()
        updateContentGeometry()
    }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?(.none)
    }

    func update(content: Content, configuration: FluentContentDialogConfiguration, context: FluentRenderContext) {
        let rebuildButtons = self.configuration != configuration
        self.configuration = configuration
        self.context = context
        contentHost.update(content)
        contentHost.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        apply(configuration: configuration, context: context, rebuildButtons: rebuildButtons)
        needsLayout = true
    }

    func present(animated: Bool, completion: (() -> Void)? = nil) {
        guard let surfaceLayer = surfaceContainer.layer, let dimmingLayer = dimmingView.layer else {
            completion?()
            return
        }
        prepareForPresentation()
        fluentSetAnchorPoint(
            CGPoint(x: 0.5, y: 0.5),
            preservingFrameOf: surfaceLayer
        )
        beginTransition(.presenting, completion: completion)
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: surfaceLayer,
                    key: "fluent.contentDialog.scale",
                    keyPath: "transform.scale",
                    fromValue: FluentMotion.contentDialogOpen.scale,
                    toValue: CGFloat(1),
                    applyModelValue: { surfaceLayer.setValue(CGFloat(1), forKeyPath: "transform.scale") }
                )
            ],
            motion: FluentMotion.contentDialogOpen,
            animated: animated,
            completion: { [weak self] in
                self?.completeTransition(if: .presenting)
            }
        )
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: surfaceLayer,
                    key: "fluent.contentDialog.opacity",
                    keyPath: "opacity",
                    fromValue: Float(0),
                    toValue: Float(1),
                    applyModelValue: { surfaceLayer.opacity = 1 }
                ),
                FluentLayerAnimationChange(
                    layer: dimmingLayer,
                    key: "fluent.contentDialog.dimming",
                    keyPath: "opacity",
                    fromValue: Float(0),
                    toValue: Float(1),
                    applyModelValue: { dimmingLayer.opacity = 1 }
                )
            ],
            motion: FluentMotion.contentDialogOpacity,
            animated: animated
        )
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        guard let surfaceLayer = surfaceContainer.layer, let dimmingLayer = dimmingView.layer else {
            completion?()
            return
        }
        beginTransition(.dismissing, completion: completion)
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: surfaceLayer,
                    key: "fluent.contentDialog.scale",
                    keyPath: "transform.scale",
                    toValue: FluentMotion.contentDialogClose.scale,
                    applyModelValue: {
                        surfaceLayer.setValue(FluentMotion.contentDialogClose.scale, forKeyPath: "transform.scale")
                    }
                )
            ],
            motion: FluentMotion.contentDialogClose,
            animated: animated,
            completion: { [weak self] in
                self?.completeTransition(if: .dismissing)
            }
        )
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: surfaceLayer,
                    key: "fluent.contentDialog.opacity",
                    keyPath: "opacity",
                    toValue: Float(0),
                    applyModelValue: { surfaceLayer.opacity = 0 }
                ),
                FluentLayerAnimationChange(
                    layer: dimmingLayer,
                    key: "fluent.contentDialog.dimming",
                    keyPath: "opacity",
                    toValue: Float(0),
                    applyModelValue: { dimmingLayer.opacity = 0 }
                )
            ],
            motion: FluentMotion.contentDialogOpacity,
            animated: animated
        )
    }

    func setActionsEnabled(_ enabled: Bool) {
        actionsEnabled = enabled
        applyActionsEnabled()
    }

    private func applyActionsEnabled() {
        for entry in buttons {
            switch entry.kind {
            case .primary:
                entry.button.isEnabled = actionsEnabled && configuration.isPrimaryButtonEnabled
            case .secondary:
                entry.button.isEnabled = actionsEnabled && configuration.isSecondaryButtonEnabled
            case .close:
                entry.button.isEnabled = actionsEnabled
            case .none:
                break
            }
        }
    }

    private func beginTransition(_ phase: TransitionPhase, completion: (() -> Void)?) {
        transitionPhase = phase
        transitionCompletion = completion
        isTransitioning = true
    }

    private func completeTransition(if expectedPhase: TransitionPhase) {
        guard transitionPhase == expectedPhase else { return }
        transitionPhase = .idle
        isTransitioning = false
        let completion = transitionCompletion
        transitionCompletion = nil
        completion?()
    }

    private func settleForAppearanceChange() {
        guard transitionPhase != .idle,
              let surfaceLayer = surfaceContainer.layer,
              let dimmingLayer = dimmingView.layer else { return }
        let phase = transitionPhase
        animationCoordinator.cancelAll(on: [surfaceLayer, dimmingLayer])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch phase {
        case .presenting:
            surfaceLayer.setValue(CGFloat(1), forKeyPath: "transform.scale")
            surfaceLayer.opacity = 1
            dimmingLayer.opacity = 1
        case .dismissing:
            surfaceLayer.setValue(FluentMotion.contentDialogClose.scale, forKeyPath: "transform.scale")
            surfaceLayer.opacity = 0
            dimmingLayer.opacity = 0
        case .idle:
            break
        }
        CATransaction.commit()
        completeTransition(if: phase)
    }

    /// Resolve the intrinsic content and command widths before Core Animation snapshots the
    /// surface. The first pass can change the width constraint; the second pass commits the
    /// resulting button frames so the opening animation never starts from the 320pt fallback.
    func prepareForPresentation() {
        guard superview != nil else { return }
        for _ in 0..<2 {
            needsLayout = true
            superview?.layoutSubtreeIfNeeded()
            layoutSubtreeIfNeeded()
        }
    }

    func moveFocusIntoDialog() {
        let focusable = focusableViews(in: contentHost) + buttons.map(\.button).filter(\.isEnabled)
        guard !focusable.isEmpty else {
            window?.makeFirstResponder(self)
            return
        }
        for index in focusable.indices {
            focusable[index].nextKeyView = focusable[(index + 1) % focusable.count]
        }
        let preferred = buttons.first(where: { $0.kind == configuration.defaultButton && $0.button.isEnabled })?.button
            ?? focusable.first
        window?.makeFirstResponder(preferred)
    }

    private func buildViewHierarchy() {
        dimmingView.identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.DimmingLayer")
        dimmingView.wantsLayer = true
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimmingView)

        surfaceContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.Surface")
        surfaceContainer.wantsLayer = true
        surfaceContainer.layer?.cornerRadius = 8
        surfaceContainer.layer?.cornerCurve = .circular
        surfaceContainer.layer?.masksToBounds = true
        surfaceContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceContainer)

        materialView.translatesAutoresizingMaskIntoConstraints = false
        surfaceContainer.addSubview(materialView)

        contentTintView.identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.ContentSurface")
        contentTintView.wantsLayer = true
        contentTintView.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(contentTintView)

        commandSurfaceView.identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.CommandSurface")
        commandSurfaceView.wantsLayer = true
        commandSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        surfaceContainer.addSubview(commandSurfaceView)

        commandSeparatorView.identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.CommandSeparator")
        commandSeparatorView.wantsLayer = true
        commandSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        commandSurfaceView.addSubview(commandSeparatorView)

        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentTintView.addSubview(titleLabel)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentTintView.addSubview(scrollView)

        documentView.addSubview(contentHost)
        contentHost.translatesAutoresizingMaskIntoConstraints = true
        contentHost.autoresizingMask = [.width]
        scrollView.documentView = documentView

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        commandSurfaceView.addSubview(buttonStack)

        surfaceWidthConstraint = surfaceContainer.widthAnchor.constraint(equalToConstant: 320)
        surfaceWidthConstraint.priority = .defaultHigh
        scrollHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 32)
        scrollHeightConstraint.priority = .defaultHigh
        titleToContentConstraint = scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12)
        titleHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: 0)
        materialToCommandConstraint = materialView.bottomAnchor.constraint(equalTo: commandSurfaceView.topAnchor)
        materialToBottomConstraint = materialView.bottomAnchor.constraint(equalTo: surfaceContainer.bottomAnchor)
        commandHeightConstraint = commandSurfaceView.heightAnchor.constraint(equalToConstant: 80)

        let minimumWidth = surfaceContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 320)
        let minimumHeight = surfaceContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 184)
        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            surfaceContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            surfaceContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            surfaceContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            surfaceContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            surfaceContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
            surfaceContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            surfaceWidthConstraint,
            minimumWidth,
            surfaceContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 548),
            minimumHeight,
            surfaceContainer.heightAnchor.constraint(lessThanOrEqualToConstant: 756),

            materialView.leadingAnchor.constraint(equalTo: surfaceContainer.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: surfaceContainer.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: surfaceContainer.topAnchor),

            contentTintView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            contentTintView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            contentTintView.topAnchor.constraint(equalTo: materialView.topAnchor),
            contentTintView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),

            commandSurfaceView.leadingAnchor.constraint(equalTo: surfaceContainer.leadingAnchor),
            commandSurfaceView.trailingAnchor.constraint(equalTo: surfaceContainer.trailingAnchor),
            commandSurfaceView.bottomAnchor.constraint(equalTo: surfaceContainer.bottomAnchor),
            commandHeightConstraint,

            commandSeparatorView.leadingAnchor.constraint(equalTo: commandSurfaceView.leadingAnchor),
            commandSeparatorView.trailingAnchor.constraint(equalTo: commandSurfaceView.trailingAnchor),
            commandSeparatorView.topAnchor.constraint(equalTo: commandSurfaceView.topAnchor),
            commandSeparatorView.heightAnchor.constraint(equalToConstant: 1),

            titleLabel.leadingAnchor.constraint(equalTo: contentTintView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentTintView.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: contentTintView.topAnchor, constant: 18),
            titleToContentConstraint,

            scrollView.leadingAnchor.constraint(equalTo: contentTintView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentTintView.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: contentTintView.bottomAnchor, constant: -24),
            scrollHeightConstraint,

            buttonStack.leadingAnchor.constraint(equalTo: commandSurfaceView.leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: commandSurfaceView.trailingAnchor, constant: -24),
            buttonStack.topAnchor.constraint(equalTo: commandSurfaceView.topAnchor, constant: 24),
            buttonStack.bottomAnchor.constraint(equalTo: commandSurfaceView.bottomAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 32)
        ])
        materialToBottomConstraint.isActive = true
    }

    private func apply(
        configuration: FluentContentDialogConfiguration,
        context: FluentRenderContext,
        rebuildButtons: Bool
    ) {
        setAccessibilityLabel(configuration.title.isEmpty ? "Dialog" : configuration.title)
        titleLabel.stringValue = configuration.title
        titleLabel.font = NSFont.systemFont(
            ofSize: 20 * context.theme.typography.scale,
            weight: .regular
        )
        titleLabel.textColor = context.theme.textPrimary
        titleLabel.isHidden = configuration.title.isEmpty
        titleHeightConstraint.isActive = configuration.title.isEmpty
        titleToContentConstraint.constant = configuration.title.isEmpty ? 0 : 12

        materialView.materialStyle = context.theme.material(for: .transient) ?? .liquidGlass
        materialView.fluentTheme = context.theme
        materialView.isMaterialEnabled = context.theme.materialEffectsEnabled
        materialView.fallbackColor = context.theme.contentDialogContentFill
        materialView.layer?.cornerRadius = 0
        materialView.layer?.masksToBounds = false

        contentTintView.layer?.backgroundColor = context.theme.contentDialogContentFill.cgColor
        commandSurfaceView.layer?.backgroundColor = context.theme.contentDialogCommandFill.cgColor
        commandSeparatorView.layer?.backgroundColor = context.theme.divider.cgColor
        surfaceContainer.layer?.cornerRadius = 8
        surfaceContainer.layer?.borderWidth = context.theme.isHighContrast ? 2 : 1
        surfaceContainer.layer?.borderColor = context.theme.surfaceStrokeFlyout.cgColor

        dimmingView.layer?.backgroundColor = context.theme.contentDialogSmokeFill.cgColor
        if rebuildButtons { rebuildActionButtons() }
        for entry in buttons {
            entry.button.theme = context.theme
            entry.button.reduceMotion = context.reduceMotion
        }
        applyActionsEnabled()
    }

    private func rebuildActionButtons() {
        for view in buttonStack.arrangedSubviews {
            buttonStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons.removeAll()

        appendButton(configuration.primaryButtonText, kind: .primary, result: .primary)
        appendButton(configuration.secondaryButtonText, kind: .secondary, result: .secondary)
        appendButton(configuration.closeButtonText, kind: .close, result: .none)
        buttonStack.isHidden = buttons.isEmpty
        commandSurfaceView.isHidden = buttons.isEmpty
        commandHeightConstraint.isActive = !buttons.isEmpty
        materialToCommandConstraint.isActive = !buttons.isEmpty
        materialToBottomConstraint.isActive = buttons.isEmpty
    }

    private func appendButton(
        _ text: String?,
        kind: FluentContentDialogButton,
        result: FluentContentDialogResult
    ) {
        guard let text, !text.isEmpty else { return }
        let role: FluentButtonRole = configuration.defaultButton == kind ? .primary : .standard
        let button = FluentButton(title: text, role: role)
        button.identifier = NSUserInterfaceItemIdentifier("FluentKit.ContentDialog.\(kind)")
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.onClick = { [weak self] in self?.onRequestClose?(result) }
        button.keyEquivalent = configuration.defaultButton == kind ? "\r" : (kind == .close ? "\u{1b}" : "")
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonStack.addArrangedSubview(button)
        buttons.append((kind, button))
    }

    private func updateContentGeometry() {
        guard !isUpdatingGeometry, !isTransitioning else { return }
        isUpdatingGeometry = true
        defer { isUpdatingGeometry = false }

        let availableWidth = max(min(bounds.width - 48, 548), min(bounds.width, 320))
        let widestButton = buttons.map { max($0.button.intrinsicContentSize.width, 130) }.max() ?? 0
        let buttonWidth = buttons.isEmpty
            ? CGFloat(0)
            : CGFloat(buttons.count) * widestButton + CGFloat(max(buttons.count - 1, 0) * 4)
        let naturalContentWidth = max(contentHost.fittingSize.width, 0)
        let titleWidth = configuration.title.isEmpty ? 0 : max(titleLabel.intrinsicContentSize.width, 0)
        let desiredWidth = min(max(max(naturalContentWidth, max(titleWidth, buttonWidth)) + 48, 320), availableWidth)
        if abs(surfaceWidthConstraint.constant - desiredWidth) > 0.5 {
            surfaceWidthConstraint.constant = desiredWidth
        }

        let contentWidth = max(desiredWidth - 48, 1)
        contentHost.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(contentHost.frame.height, 1))
        contentHost.layoutSubtreeIfNeeded()
        let fittingHeight = max(contentHost.fittingSize.height, 1)
        documentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: fittingHeight)
        contentHost.frame = documentView.bounds
        let titleHeight = configuration.title.isEmpty ? 0 : titleLabel.intrinsicContentSize.height + 12
        let commandHeight: CGFloat = buttons.isEmpty ? 0 : 80
        let maximumScrollHeight = max(
            min(bounds.height - 48 - 18 - titleHeight - commandHeight - 24, 650),
            1
        )
        scrollHeightConstraint.constant = min(fittingHeight, maximumScrollHeight)
        titleLabel.preferredMaxLayoutWidth = contentWidth
    }

    private func focusableViews(in root: NSView) -> [NSView] {
        var result: [NSView] = []
        func visit(_ view: NSView) {
            guard !view.isHidden else { return }
            if view.acceptsFirstResponder {
                if let control = view as? NSControl {
                    if control.isEnabled { result.append(view) }
                } else {
                    result.append(view)
                }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return result
    }

    private func registerAppearanceUpdates() {
        guard let coordinator = context.appearanceCoordinator ?? window?.fluentAppearanceCoordinator else { return }
        if registeredAppearanceCoordinator === coordinator, appearanceRegistration != nil { return }
        unregisterAppearanceUpdates()
        registeredAppearanceCoordinator = coordinator
        appearanceRegistration = coordinator.register(
            owner: self,
            prepareForAppearanceChange: { [weak self] in
                self?.settleForAppearanceChange()
            }
        ) { [weak self] theme in
            guard let self else { return }
            self.context.theme = theme
            guard self.superview != nil else { return }
            self.contentHost.context = self.context
            self.apply(configuration: self.configuration, context: self.context, rebuildButtons: false)
            self.needsLayout = true
        }
    }

    private func unregisterAppearanceUpdates() {
        if let appearanceRegistration {
            registeredAppearanceCoordinator?.unregister(appearanceRegistration)
        }
        appearanceRegistration = nil
        registeredAppearanceCoordinator = nil
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 53 else { return event }
            self.onRequestClose?(.none)
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    deinit {
        removeEscapeMonitor()
        unregisterAppearanceUpdates()
    }
}

private final class FluentContentDialogDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
