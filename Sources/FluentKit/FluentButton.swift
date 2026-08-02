import AppKit

public enum FluentButtonRole: Hashable, Sendable {
    case standard
    case primary
    case destructive
}

public final class FluentButton: NSButton {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            font = theme.typography.font(for: .body).withSize(theme.typography.font(for: .body).pointSize * fluentControlSize.metricScale)
            invalidateIntrinsicContentSize()
            refreshAppearance(animated: false)
        }
    }
    public var fluentStyle: (any FluentButtonStyle)? { didSet { invalidateIntrinsicContentSize(); refreshAppearance(animated: false) } }
    public var controlState: FluentControlState = .normal {
        didSet {
            guard oldValue != controlState else { return }
            refreshAppearance(animated: true)
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            visualStateCoordinator.reduceMotion = reduceMotion
            if reduceMotion {
                layer?.removeAllAnimations()
                elevationBorderLayer.removeAllAnimations()
            }
            refreshAppearance(animated: false)
        }
    }
    public var role: FluentButtonRole { didSet { refreshAppearance(animated: false) } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            let bodyFont = theme.typography.font(for: .body)
            font = bodyFont.withSize(bodyFont.pointSize * fluentControlSize.metricScale)
            invalidateIntrinsicContentSize()
            refreshAppearance(animated: false)
        }
    }

    public var onClick: (() -> Void)?

    /// Declarative items for a button-owned in-app flyout. This mirrors WinUI's
    /// `Button.Flyout` contract while keeping the native button as the event target.
    public var flyoutItems: [FluentMenuItem]? {
        didSet {
            if flyoutItems == nil, menuFlyout != nil {
                dismissMenuFlyout(animated: false)
            }
            updateAttachedFlyoutAccessibility()
        }
    }
    public var flyoutPlacement: FluentMenuPlacement = .below
    public var commandBarFlyoutConfiguration: FluentCommandBarFlyoutConfiguration? {
        didSet {
            if commandBarFlyoutConfiguration == nil, commandBarFlyoutPresenter != nil {
                dismissCommandBarFlyout()
            }
            updateAttachedFlyoutAccessibility()
        }
    }

    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let visualStateCoordinator = FluentVisualStateCoordinator()
    private var menuFlyout: FluentMenuFlyout?
    private var commandBarFlyoutPresenter: FluentCommandBarFlyout?
    private var isPointerOver = false

    public init(title: String = "Button", role: FluentButtonRole = .standard) {
        self.role = role
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .regularSquare
        isBordered = false
        setButtonType(.momentaryPushIn)
        let bodyFont = FluentTheme.current.typography.font(for: .body)
        font = bodyFont
        target = self
        action = #selector(invoke)
        wantsLayer = true
        layer?.masksToBounds = false
        focusRingType = .none
        visualStateCoordinator.reduceMotion = reduceMotion
        configureElevationBorder()
        setAccessibilityRole(.button)
        setAccessibilityTitle(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        refreshAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        role = .standard
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
        focusRingType = .none
        visualStateCoordinator.reduceMotion = reduceMotion
        configureElevationBorder()
        refreshAppearance(animated: false)
    }

    public override var intrinsicContentSize: NSSize {
        let textSize = (title as NSString).size(withAttributes: [.font: font as Any])
        let appearance = resolvedAppearance()
        let insets = appearance.contentInsets
        let height = max(theme.controlHeight(for: fluentControlSize), textSize.height + insets.top + insets.bottom)
        return NSSize(width: ceil(textSize.width + insets.left + insets.right), height: ceil(height))
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
        }
    }

    public override func layout() {
        super.layout()
        updateElevationBorderGeometry(for: resolvedAppearance())
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateElevationBorderGeometry(for: resolvedAppearance())
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateElevationBorderGeometry(for: resolvedAppearance())
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateElevationBorderGeometry(for: resolvedAppearance())
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateElevationBorderGeometry(for: resolvedAppearance())
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        controlState = .pointerOver
    }

    public override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = false
        controlState = .normal
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        controlState = .pressed
        super.mouseDown(with: event)
        if isEnabled {
            controlState = isPointerOver ? .pointerOver : .normal
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
                controlState = .focused
            }
            needsDisplay = true
        }
        return result
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        if window?.firstResponder === self {
            controlState = .focused
            needsDisplay = true
        }
        if event.keyCode == 36 || event.keyCode == 49 {
            invoke()
        } else {
            super.keyDown(with: event)
        }
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { controlState = .normal; needsDisplay = true }
        return result
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)

        if FluentFocusVisibility.isKeyboardFocusVisible(for: self),
           let focusRingColor = appearance.focusRingColor {
            focusRingColor.setStroke()
            let focusPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: max(appearance.cornerRadius - 2, 0), yRadius: max(appearance.cornerRadius - 2, 0))
            focusPath.lineWidth = appearance.focusRingWidth
            focusPath.stroke()
        }

        let textSize = (title as NSString).size(withAttributes: [.font: font as Any])
        let textRect = fluentSingleLineTextRect(
            NSRect(x: bounds.midX - textSize.width / 2, y: 0, width: textSize.width, height: textSize.height),
            in: bounds,
            font: font
        )
        appearance.foregroundColor.set()
        (title as NSString).draw(in: textRect, withAttributes: [.font: font as Any, .foregroundColor: appearance.foregroundColor])
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { dismissAttachedFlyout() }
            controlState = isEnabled ? (isPointerOver ? .pointerOver : .normal) : .disabled
            needsDisplay = true
        }
    }

    @objc private func invoke() {
        onClick?()
        guard flyoutItems != nil || commandBarFlyoutConfiguration != nil else { return }
        if menuFlyout != nil || commandBarFlyoutPresenter != nil {
            dismissAttachedFlyout()
            return
        }
        // AppKit's button tracking must finish before the child panel is ordered above it.
        DispatchQueue.main.async { [weak self] in self?.presentFlyoutIfNeeded() }
    }

    func applyDeclarativeConfiguration(from source: FluentButton) {
        title = source.title
        role = source.role
        fluentControlSize = source.fluentControlSize
        font = source.font
        fluentStyle = source.fluentStyle
        onClick = source.onClick
        flyoutItems = source.flyoutItems
        flyoutPlacement = source.flyoutPlacement
        commandBarFlyoutConfiguration = source.commandBarFlyoutConfiguration
        isEnabled = source.isEnabled
        needsDisplay = true
        invalidateIntrinsicContentSize()
        refreshAppearance(animated: false)
    }

    private func presentFlyoutIfNeeded() {
        guard isEnabled, menuFlyout == nil, commandBarFlyoutPresenter == nil, window != nil else { return }
        if let configuration = commandBarFlyoutConfiguration {
            let presented = FluentCommandBarFlyout(
                primaryCommands: configuration.primaryCommands,
                secondaryCommands: configuration.secondaryCommands,
                alwaysExpanded: configuration.alwaysExpanded,
                theme: theme,
                reduceMotion: reduceMotion
            )
            commandBarFlyoutPresenter = presented
            presented.onDismiss = { [weak self, weak presented] in
                guard let self, self.commandBarFlyoutPresenter === presented else { return }
                self.commandBarFlyoutPresenter = nil
                self.controlState = self.isPointerOver ? .pointerOver : .normal
                self.setAccessibilityValue("Closed")
                self.needsDisplay = true
            }
            controlState = isPointerOver ? .pointerOver : .normal
            setAccessibilityValue("Open")
            presented.present(relativeTo: self, at: NSPoint(x: bounds.midX, y: bounds.minY))
            return
        }
        guard let flyoutItems, !flyoutItems.isEmpty else { return }
        let presented = FluentMenuFlyout(
            items: flyoutItems,
            theme: theme,
            reduceMotion: reduceMotion
        )
        menuFlyout = presented
        presented.onDismiss = { [weak self, weak presented] in
            guard let self, self.menuFlyout === presented else { return }
            self.menuFlyout = nil
            self.controlState = self.isPointerOver ? .pointerOver : .normal
            self.setAccessibilityValue("Closed")
            self.needsDisplay = true
        }
        controlState = isPointerOver ? .pointerOver : .normal
        setAccessibilityValue("Open")
        presented.present(relativeTo: self, placement: flyoutPlacement)
    }

    private func dismissMenuFlyout(animated: Bool) {
        menuFlyout?.dismiss(animated: animated)
        menuFlyout = nil
        restoreAfterFlyoutDismissal()
    }

    private func dismissCommandBarFlyout() {
        commandBarFlyoutPresenter?.dismiss()
        commandBarFlyoutPresenter = nil
        restoreAfterFlyoutDismissal()
    }

    private func dismissAttachedFlyout() {
        menuFlyout?.dismiss(animated: false)
        commandBarFlyoutPresenter?.dismiss()
        menuFlyout = nil
        commandBarFlyoutPresenter = nil
        restoreAfterFlyoutDismissal()
    }

    private func restoreAfterFlyoutDismissal() {
        guard menuFlyout == nil, commandBarFlyoutPresenter == nil else { return }
        controlState = isEnabled ? (isPointerOver ? .pointerOver : .normal) : .disabled
        setAccessibilityValue("Closed")
    }

    private func updateAttachedFlyoutAccessibility() {
        setAccessibilityRole(
            flyoutItems == nil && commandBarFlyoutConfiguration == nil ? .button : .popUpButton
        )
    }

    deinit {
        menuFlyout?.dismiss(animated: false)
        commandBarFlyoutPresenter?.dismiss()
    }

    private func resolvedAppearance() -> FluentButtonAppearance {
        resolvedAppearance(for: visualStateCoordinator.state.primaryControlState)
    }

    private func resolvedAppearance(for controlState: FluentControlState) -> FluentButtonAppearance {
        let configuration = FluentButtonStyleConfiguration(
            title: title,
            role: role,
            controlState: controlState,
            isEnabled: isEnabled,
            theme: theme
        )
        return fluentStyle?.appearance(for: configuration)
            ?? FluentAutomaticButtonStyle().appearance(for: configuration)
    }

    private func refreshAppearance(animated: Bool) {
        visualStateCoordinator.reduceMotion = reduceMotion
        visualStateCoordinator.transition(
            to: .forControlState(controlState),
            animated: animated,
            motion: FluentMotion.controlFaster
        ) { [weak self] transition in
            self?.applyVisualState(transition)
        }
    }

    private func applyVisualState(_ transition: FluentVisualStateTransition) {
        guard let layer else { needsDisplay = true; return }
        let appearance = resolvedAppearance(for: transition.to.primaryControlState)
        CATransaction.begin()
        CATransaction.setDisableActions(!transition.isAnimated)
        CATransaction.setAnimationDuration(transition.isAnimated ? transition.motion.duration : 0)
        CATransaction.setAnimationTimingFunction(transition.motion.curve.timingFunction)
        layer.backgroundColor = appearance.backgroundColor.cgColor
        layer.borderWidth = 0
        layer.cornerRadius = appearance.cornerRadius
        layer.cornerCurve = .continuous
        elevationBorderLayer.colors = (appearance.borderGradientColors
            ?? [appearance.borderColor, appearance.borderColor]).map(\.cgColor)
        CATransaction.commit()
        updateElevationBorderGeometry(for: appearance)
        needsDisplay = true
    }

    private func configureElevationBorder() {
        elevationBorderLayer.name = "FluentKit.Button.ElevationBorder"
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        elevationBorderLayer.isHidden = true
        layer?.addSublayer(elevationBorderLayer)
    }

    private func updateElevationBorderGeometry(for appearance: FluentButtonAppearance) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: bounds,
            appearance: appearance,
            visualYAxis: .resolved(for: self.layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        )
        CATransaction.commit()
    }
}

extension FluentButton: FluentControlSizeConfigurable {}
