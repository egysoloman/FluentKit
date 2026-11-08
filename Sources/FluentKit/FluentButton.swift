import AppKit

public enum FluentButtonRole: Hashable, Sendable {
    case standard
    case primary
    case destructive
}

public final class FluentButton: NSButton {
    /// Fluent buttons participate in Tab navigation independently of the native NSButton
    /// keyboard preference. Applications can opt out with refusesFirstResponder.
    public override var canBecomeKeyView: Bool {
        acceptsFirstResponder && !refusesFirstResponder && !isHiddenOrHasHiddenAncestor
            && window?.canBecomeKey == true && !visibleRect.isEmpty
    }

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
            if let configuration = commandBarFlyoutConfiguration {
                commandBarFlyoutPresenter?.update(configuration: configuration)
            } else if commandBarFlyoutPresenter != nil {
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
    private lazy var pointerLifetime = FluentPointerLifetime { [weak self] in self?.clearPointerHover() }

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
        configureContentPriorities()
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
        configureContentPriorities()
        visualStateCoordinator.reduceMotion = reduceMotion
        configureElevationBorder()
        refreshAppearance(animated: false)
    }

    public override var image: NSImage? {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    public override var imagePosition: NSControl.ImagePosition {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private var measuredImageSize: NSSize {
        guard let image, imagePosition != .noImage else { return .zero }
        return image.size
    }

    private var resolvedImagePosition: NSControl.ImagePosition {
        switch imagePosition {
        case .imageLeading: return userInterfaceLayoutDirection == .rightToLeft ? .imageRight : .imageLeft
        case .imageTrailing: return userInterfaceLayoutDirection == .rightToLeft ? .imageLeft : .imageRight
        default: return imagePosition
        }
    }

    private var contentInsets: NSEdgeInsets {
        if imagePosition == .imageOnly {
            let scale = fluentControlSize.metricScale
            return NSEdgeInsets(top: 4 * scale, left: 8 * scale, bottom: 4 * scale, right: 8 * scale)
        }
        return resolvedAppearance().contentInsets
    }

    public override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        let icon = measuredImageSize
        let gap: CGFloat = icon != .zero && !title.isEmpty ? 8 : 0
        let size: NSSize
        switch resolvedImagePosition {
        case .imageOnly: size = icon
        case .imageLeft, .imageRight: size = NSSize(width: text.width + icon.width + gap, height: max(text.height, icon.height))
        case .imageAbove, .imageBelow: size = NSSize(width: max(text.width, icon.width), height: text.height + icon.height + gap)
        case .imageOverlaps: size = NSSize(width: max(text.width, icon.width), height: max(text.height, icon.height))
        default: size = text
        }
        let insets = contentInsets
        let height = max(theme.controlHeight(for: fluentControlSize), size.height + insets.top + insets.bottom)
        return NSSize(width: ceil(size.width + insets.left + insets.right), height: ceil(height))
    }

    func contentRects(in bounds: NSRect) -> (image: NSRect, title: NSRect) {
        let insets = contentInsets
        let available = NSRect(x: bounds.minX + insets.left, y: bounds.minY + insets.bottom,
                               width: max(0, bounds.width - insets.left - insets.right),
                               height: max(0, bounds.height - insets.top - insets.bottom))
        let natural = measuredImageSize
        guard natural.width > 0, natural.height > 0 else { return (.zero, available) }
        let scale = min(1, available.width / natural.width, available.height / natural.height)
        let icon = NSSize(width: natural.width * scale, height: natural.height * scale)
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        let gap: CGFloat = title.isEmpty ? 0 : 8
        var imageRect = NSRect(x: available.midX - icon.width / 2, y: available.midY - icon.height / 2, width: icon.width, height: icon.height)
        var titleRect = available
        switch resolvedImagePosition {
        case .imageOnly: titleRect = .zero
        case .imageLeft, .imageRight:
            let textWidth = min(text.width, max(0, available.width - icon.width - gap))
            let start = available.midX - (icon.width + gap + textWidth) / 2
            if resolvedImagePosition == .imageLeft {
                imageRect.origin.x = start
                titleRect = NSRect(x: imageRect.maxX + gap, y: available.minY, width: textWidth, height: available.height)
            } else {
                titleRect = NSRect(x: start, y: available.minY, width: textWidth, height: available.height)
                imageRect.origin.x = titleRect.maxX + gap
            }
        case .imageAbove, .imageBelow:
            let textHeight = min(text.height, max(0, available.height - icon.height - gap))
            let start = available.midY - (icon.height + gap + textHeight) / 2
            let above = resolvedImagePosition == .imageAbove
            imageRect.origin.y = above ? start + textHeight + gap : start
            titleRect = NSRect(x: available.minX, y: above ? start : imageRect.maxY + gap, width: available.width, height: textHeight)
        default: break
        }
        return (imageRect, titleRect)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        }
        if isPointerOver {
            let point = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
            if isHiddenOrHasHiddenAncestor || point.map({ !visibleRect.contains($0) }) != false {
                clearPointerHover()
            }
        }
    }

    public override func viewDidHide() {
        super.viewDidHide()
        clearPointerHover()
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

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { clearPointerHover() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { clearPointerHover() }
        super.viewWillMove(toWindow: newWindow)
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
        pointerLifetime.observe(window)
        controlState = .pointerOver
    }

    public override func mouseExited(with event: NSEvent) {
        // Tracking still reports exits while disabled. Keep that state current so enabling
        // or reattaching the same native button cannot resurrect an old hover fill.
        clearPointerHover()
    }

    private func clearPointerHover() {
        pointerLifetime.invalidate()
        let hadPointerState = isPointerOver || controlState == .pointerOver || controlState == .pressed
        isPointerOver = false
        if hadPointerState { controlState = isEnabled ? .normal : .disabled }
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        pointerLifetime.observe(window)
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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let content = contentRects(in: bounds)
        if let image, !content.image.isEmpty {
            let renderedImage: NSImage
            if image.isTemplate {
                renderedImage = NSImage(size: image.size, flipped: false) { rect in
                    image.draw(in: rect)
                    appearance.foregroundColor.setFill()
                    rect.fill(using: .sourceAtop)
                    return true
                }
            } else {
                renderedImage = image
            }
            renderedImage.draw(in: content.image, from: .zero, operation: .sourceOver,
                               fraction: isEnabled || image.isTemplate ? 1 : 0.4, respectFlipped: true, hints: nil)
        }
        guard imagePosition != .imageOnly else { return }
        let textRect = fluentSingleLineTextRect(
            content.title, in: content.title, font: font,
            topInset: 0, bottomInset: 0
        )
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font as Any,
                .foregroundColor: appearance.foregroundColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        attributedTitle.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
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

    private func configureContentPriorities() {
        // Labels commonly sit beside buttons in an HStack. Make the label yield first so the
        // button keeps its title and Fluent horizontal padding instead of clipping both edges.
        setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultHigh.rawValue + 1),
            for: .horizontal
        )
    }

    func applyDeclarativeConfiguration(from source: FluentButton) {
        title = source.title
        image = source.image
        imagePosition = source.imagePosition
        imageScaling = source.imageScaling
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
            guard (configuration.primaryCommands + configuration.secondaryCommands).contains(where: { !$0.isSeparator }) else { return }
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
                self.fluentSetDefaultAccessibilityValue("Closed")
                self.needsDisplay = true
            }
            controlState = isPointerOver ? .pointerOver : .normal
            fluentSetDefaultAccessibilityValue("Open")
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
            self.fluentSetDefaultAccessibilityValue("Closed")
            self.needsDisplay = true
        }
        controlState = isPointerOver ? .pointerOver : .normal
        fluentSetDefaultAccessibilityValue("Open")
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
        fluentSetDefaultAccessibilityValue("Closed")
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
