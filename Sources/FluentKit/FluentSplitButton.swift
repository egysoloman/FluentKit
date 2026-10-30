import AppKit

/// A WinUI-style compound button. The primary region invokes the application action while the
/// fixed-width trailing region opens the attached MenuFlyout.
open class FluentSplitButton: NSControl, FluentControlSizeConfigurable {
    public static let primaryMinimumWidth: CGFloat = 35
    public static let secondaryWidth: CGFloat = 35
    public static let separatorWidth: CGFloat = 1

    public var title: String {
        didSet {
            guard oldValue != title else { return }
            setAccessibilityTitle(title)
            invalidateIntrinsicContentSize()
            titleLabel.stringValue = title
            needsLayout = true
            needsDisplay = true
        }
    }
    public var items: [FluentMenuItem] {
        didSet {
            if items.isEmpty { dismissFlyout(animated: false) }
            updateAccessibilityValue()
        }
    }
    public var onPrimaryAction: (() -> Void)?
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            updateFont()
            invalidateIntrinsicContentSize()
            updateAppearance(animated: false)
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion {
                [layer, primaryLayer, secondaryLayer, dividerLayer, elevationBorderLayer, focusOuterLayer, focusInnerLayer, chevronLayer]
                    .compactMap { $0 }
                    .forEach { $0.removeAllAnimations() }
            }
            updateAppearance(animated: false)
        }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            updateFont()
            invalidateIntrinsicContentSize()
            updateAppearance(animated: false)
        }
    }
    public var flyoutPlacement: FluentMenuPlacement = .below
    public private(set) var isFlyoutPresented = false

    private enum HitRegion: Equatable { case none, primary, secondary }

    private var displayFont = FluentTheme.current.typography.font(for: .body)
    private var hoveredRegion: HitRegion = .none
    private var pressedRegion: HitRegion = .none
    private var isTrackingPress = false
    private var isKeyboardPressed = false
    private var menuFlyout: FluentMenuFlyout?
    private let primaryLayer = CALayer()
    private let secondaryLayer = CALayer()
    private let dividerLayer = CALayer()
    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let focusOuterLayer = CAShapeLayer()
    private let focusInnerLayer = CAShapeLayer()
    private let chevronLayer = FluentAnimatedChevronLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let animationCoordinator = FluentAnimationCoordinator()

    public init(
        _ title: String,
        items: [FluentMenuItem],
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        onPrimaryAction = action
        super.init(frame: .zero)
        configure()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    open var isCheckedForAppearance: Bool { false }
    public override var acceptsFirstResponder: Bool { isEnabled }

    public override var intrinsicContentSize: NSSize {
        let scale = fluentControlSize.metricScale
        let text = (title as NSString).size(withAttributes: [.font: displayFont])
        let primaryWidth = max(Self.primaryMinimumWidth * scale, ceil(text.width + 22 * scale))
        let height = max(theme.controlHeight(for: fluentControlSize), ceil(text.height + 13 * scale))
        return NSSize(
            width: primaryWidth + Self.separatorWidth + Self.secondaryWidth * scale,
            height: height
        )
    }

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                dismissFlyout(animated: false)
                hoveredRegion = .none
                pressedRegion = .none
                isKeyboardPressed = false
                isTrackingPress = false
            }
            updateAppearance(animated: true)
        }
    }

    public override func layout() {
        super.layout()
        synchronizeGeometry()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            ))
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        hoveredRegion = region(at: convert(event.locationInWindow, from: nil))
        updateAppearance(animated: true)
    }

    public override func mouseMoved(with event: NSEvent) {
        guard isEnabled, !isTrackingPress else { return }
        let next = region(at: convert(event.locationInWindow, from: nil))
        guard next != hoveredRegion else { return }
        hoveredRegion = next
        updateAppearance(animated: true)
    }

    public override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        hoveredRegion = .none
        if !isTrackingPress { pressedRegion = .none }
        updateAppearance(animated: true)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        let region = region(at: convert(event.locationInWindow, from: nil))
        guard region != .none else { return }
        isTrackingPress = true
        pressedRegion = region
        hoveredRegion = region
        updateAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        let current = region(at: convert(event.locationInWindow, from: nil))
        hoveredRegion = current
        // Preserve the initially captured semantic region while canceling its pressed visual
        // outside that region; moving back restores it, like ButtonBase pointer capture.
        updateAppearance(animated: true)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        let captured = pressedRegion
        let released = region(at: convert(event.locationInWindow, from: nil))
        isTrackingPress = false
        pressedRegion = .none
        hoveredRegion = released
        updateAppearance(animated: true)
        guard captured == released else { return }
        switch released {
        case .primary: invokePrimaryAction()
        case .secondary: presentFlyout()
        case .none: break
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 36 where !event.isARepeat,
             49 where !event.isARepeat:
            isKeyboardPressed = true
            updateAppearance(animated: true)
        case 53:
            isKeyboardPressed = false
            dismissFlyout(animated: true)
            updateAppearance(animated: true)
        default:
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard isEnabled else { return }
        if (event.keyCode == 36 || event.keyCode == 49), isKeyboardPressed {
            isKeyboardPressed = false
            updateAppearance(animated: true)
            invokePrimaryAction()
            return
        }
        if (event.keyCode == 125 && event.modifierFlags.contains(.option)) || event.keyCode == 118 {
            presentFlyout()
            return
        }
        super.keyUp(with: event)
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { updateAppearance(animated: true) }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        isKeyboardPressed = false
        let result = super.resignFirstResponder()
        if result { updateAppearance(animated: true) }
        return result
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        invokePrimaryAction()
        return true
    }

    open func invokePrimaryAction() {
        onPrimaryAction?()
    }

    public func showFlyout() { presentFlyout() }
    public func hideFlyout(animated: Bool = true) { dismissFlyout(animated: animated) }

    func checkedStateDidChange(animated: Bool) {
        updateAccessibilityValue()
        updateAppearance(animated: animated)
    }

    private var primaryFrame: CGRect {
        let secondary = secondaryFrame
        if userInterfaceLayoutDirection == .rightToLeft {
            return CGRect(x: secondary.maxX + Self.separatorWidth, y: 0, width: max(0, bounds.maxX - secondary.maxX - Self.separatorWidth), height: bounds.height)
        }
        return CGRect(x: 0, y: 0, width: max(0, secondary.minX - Self.separatorWidth), height: bounds.height)
    }

    private var secondaryFrame: CGRect {
        let width = min(bounds.width, Self.secondaryWidth * fluentControlSize.metricScale)
        return CGRect(
            x: userInterfaceLayoutDirection == .rightToLeft ? 0 : bounds.maxX - width,
            y: 0,
            width: width,
            height: bounds.height
        )
    }

    private func region(at point: CGPoint) -> HitRegion {
        guard bounds.contains(point) else { return .none }
        if secondaryFrame.contains(point) { return .secondary }
        if primaryFrame.contains(point) { return .primary }
        return .none
    }

    private var activePressedRegion: HitRegion {
        if isKeyboardPressed || isFlyoutPresented { return .secondary }
        guard isTrackingPress, hoveredRegion == pressedRegion else { return .none }
        return pressedRegion
    }

    private var baseBackground: NSColor {
        if !isEnabled { return isCheckedForAppearance ? theme.accentFillDisabled : theme.controlFillDisabled }
        if isFlyoutPresented || isKeyboardPressed {
            return isCheckedForAppearance ? theme.accentFillTertiary : theme.controlFillTertiary
        }
        return isCheckedForAppearance ? theme.accentFillDefault : theme.controlFill
    }

    private func regionBackground(_ region: HitRegion) -> NSColor {
        guard isEnabled else { return .clear }
        if isFlyoutPresented || isKeyboardPressed {
            return isCheckedForAppearance ? theme.accentFillTertiary : theme.controlFillTertiary
        }
        if activePressedRegion == region {
            return isCheckedForAppearance ? theme.accentFillTertiary : theme.controlFillTertiary
        }
        if hoveredRegion == region {
            return isCheckedForAppearance ? theme.accentFillSecondary : theme.controlFillSecondary
        }
        return baseBackground
    }

    private var primaryForeground: NSColor {
        if !isEnabled { return theme.textDisabled }
        if isCheckedForAppearance {
            return activePressedRegion == .primary || isFlyoutPresented || isKeyboardPressed
                ? theme.textOnAccentSecondary
                : theme.textOnAccent
        }
        return activePressedRegion == .primary || isFlyoutPresented || isKeyboardPressed
            ? theme.textSecondary
            : theme.textPrimary
    }

    private var secondaryForeground: NSColor {
        if !isEnabled { return theme.textDisabled }
        if isCheckedForAppearance {
            return activePressedRegion == .secondary || isFlyoutPresented || isKeyboardPressed
                ? theme.textOnAccentSecondary
                : theme.textOnAccent
        }
        if hoveredRegion == .secondary {
            return theme.textPrimary
        }
        return activePressedRegion == .secondary || isFlyoutPresented || isKeyboardPressed
            ? theme.textTertiary
            : theme.textSecondary
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        animationCoordinator.reduceMotion = reduceMotion
        for child in [primaryLayer, secondaryLayer, dividerLayer, elevationBorderLayer, chevronLayer, focusOuterLayer, focusInnerLayer] {
            layer?.addSublayer(child)
        }
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.isSelectable = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.setAccessibilityElement(false)
        titleLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.SplitButton.Title")
        addSubview(titleLabel)
        primaryLayer.name = "FluentKit.SplitButton.Primary"
        secondaryLayer.name = "FluentKit.SplitButton.Secondary"
        dividerLayer.name = "FluentKit.SplitButton.Divider"
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        elevationBorderLayer.name = "FluentKit.SplitButton.ElevationBorder"
        focusOuterLayer.name = "FluentKit.SplitButton.FocusOuter"
        focusInnerLayer.name = "FluentKit.SplitButton.FocusInner"
        for focus in [focusOuterLayer, focusInnerLayer] {
            focus.fillColor = NSColor.clear.cgColor
            focus.opacity = 0
        }
        setAccessibilityRole(.popUpButton)
        setAccessibilityTitle(title)
        updateAccessibilityValue()
        updateFont()
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        updateAppearance(animated: false)
    }

    private func updateFont() {
        let body = theme.typography.font(for: .body)
        displayFont = body.withSize(body.pointSize * fluentControlSize.metricScale)
        titleLabel.font = displayFont
    }

    private func synchronizeGeometry() {
        guard let layer else { return }
        let radius = theme.designTokens.controlCornerRadius * fluentControlSize.metricScale
        let backingScale = max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
        let pixel = 1 / backingScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        primaryLayer.frame = primaryFrame
        secondaryLayer.frame = secondaryFrame
        let titleInsets = 11 * fluentControlSize.metricScale
        let labelBounds = primaryFrame.insetBy(dx: min(titleInsets, max(0, primaryFrame.width / 2)), dy: 0)
        let labelHeight = min(max(titleLabel.intrinsicContentSize.height, 0), labelBounds.height)
        titleLabel.frame = CGRect(
            x: labelBounds.minX,
            y: floor(labelBounds.midY - labelHeight / 2),
            width: max(0, labelBounds.width),
            height: labelHeight
        )
        let dividerX = userInterfaceLayoutDirection == .rightToLeft ? secondaryFrame.maxX : secondaryFrame.minX - pixel
        dividerLayer.frame = CGRect(x: dividerX, y: pixel, width: pixel, height: max(0, bounds.height - pixel * 2))
        for (focus, inset, width) in [(focusOuterLayer, CGFloat(1), CGFloat(2)), (focusInnerLayer, CGFloat(3), CGFloat(1))] {
            focus.frame = bounds
            let rect = bounds.insetBy(dx: inset, dy: inset)
            focus.path = CGPath(roundedRect: rect, cornerWidth: max(0, radius - inset + 1), cornerHeight: max(0, radius - inset + 1), transform: nil)
            focus.lineWidth = width
        }
        let chevronSize: CGFloat = 12 * fluentControlSize.metricScale
        let chevronFrame = CGRect(
            x: floor(secondaryFrame.midX - chevronSize / 2),
            y: floor(secondaryFrame.midY - chevronSize / 2),
            width: chevronSize,
            height: chevronSize
        )
        CATransaction.commit()
        titleLabel.stringValue = title
        titleLabel.textColor = primaryForeground
        updateElevationBorder(animated: false)
        chevronLayer.update(
            frame: chevronFrame,
            color: secondaryForeground,
            state: activePressedRegion == .secondary || isFlyoutPresented ? .pressed : (hoveredRegion == .secondary ? .pointerOver : .normal),
            visual: .downSmall,
            inverted: true,
            backingScale: backingScale,
            animated: false
        )
    }

    private func updateAppearance(animated: Bool) {
        guard let layer else { return }
        synchronizeGeometry()
        // WinUI keeps RootGrid transparent and paints the faceplate only through the primary and
        // secondary background grids. Painting the root layer too would composite two translucent
        // ControlFill layers and make SplitButton's pad visibly heavier than Button.
        let base = NSColor.clear.cgColor
        let primary = regionBackground(.primary).cgColor
        let secondary = regionBackground(.secondary).cgColor
        let divider = (isCheckedForAppearance ? theme.controlStrokeOnAccentTertiary : theme.controlStrokeDefault).cgColor
        let changes = [
            FluentLayerAnimationChange(layer: layer, key: "fluent.split.base", keyPath: "backgroundColor", toValue: base) { [weak layer] in layer?.backgroundColor = base },
            FluentLayerAnimationChange(layer: primaryLayer, key: "fluent.split.primary", keyPath: "backgroundColor", toValue: primary) { [weak primaryLayer] in primaryLayer?.backgroundColor = primary },
            FluentLayerAnimationChange(layer: secondaryLayer, key: "fluent.split.secondary", keyPath: "backgroundColor", toValue: secondary) { [weak secondaryLayer] in secondaryLayer?.backgroundColor = secondary },
            FluentLayerAnimationChange(layer: dividerLayer, key: "fluent.split.divider", keyPath: "backgroundColor", toValue: divider) { [weak dividerLayer] in dividerLayer?.backgroundColor = divider }
        ]
        animationCoordinator.animateState(changes, motion: FluentMotion.controlFaster, animated: animated)
        updateElevationBorder(animated: animated)
        let showsFocus = FluentFocusVisibility.isKeyboardFocusVisible(for: self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusOuterLayer.strokeColor = theme.focusStrokeOuter.cgColor
        focusInnerLayer.strokeColor = theme.focusStrokeInner.cgColor
        focusOuterLayer.opacity = showsFocus ? 1 : 0
        focusInnerLayer.opacity = showsFocus ? 1 : 0
        CATransaction.commit()
        titleLabel.stringValue = title
        titleLabel.textColor = primaryForeground
        let chevronState: FluentControlState = activePressedRegion == .secondary || isFlyoutPresented
            ? .pressed
            : (hoveredRegion == .secondary ? .pointerOver : (!isEnabled ? .disabled : .normal))
        let chevronSize: CGFloat = 12 * fluentControlSize.metricScale
        chevronLayer.update(
            frame: CGRect(x: secondaryFrame.midX - chevronSize / 2, y: secondaryFrame.midY - chevronSize / 2, width: chevronSize, height: chevronSize),
            color: secondaryForeground,
            state: chevronState,
            visual: .downSmall,
            inverted: true,
            backingScale: window?.backingScaleFactor,
            animated: animated
        )
        needsDisplay = true
    }

    private var resolvedElevationColors: [NSColor] {
        if !isEnabled {
            return [theme.controlStrokeDefault, theme.controlStrokeDefault]
        }
        if isCheckedForAppearance {
            if activePressedRegion != .none || isFlyoutPresented || isKeyboardPressed {
                return [.clear, .clear]
            }
            return theme.accentElevationBorderColors
        }
        if activePressedRegion != .none || isFlyoutPresented || isKeyboardPressed {
            return [theme.controlStrokeDefault, theme.controlStrokeDefault]
        }
        return theme.controlElevationBorderColors
    }

    private func updateElevationBorder(animated: Bool) {
        let colors = resolvedElevationColors
        let appearance = FluentButtonAppearance(
            backgroundColor: .clear,
            foregroundColor: primaryForeground,
            borderColor: colors.last ?? theme.controlStrokeDefault,
            borderGradientColors: colors,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.designTokens.controlCornerRadius * fluentControlSize.metricScale,
            contentInsets: NSEdgeInsetsZero
        )
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: bounds,
            appearance: appearance,
            visualYAxis: .resolved(for: layer, fallbackView: self),
            backingScale: max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
        )
        CATransaction.commit()
    }

    private func presentFlyout() {
        guard isEnabled, !items.isEmpty else { return }
        if isFlyoutPresented {
            dismissFlyout(animated: true)
            return
        }
        let flyout = FluentMenuFlyout(items: items, theme: theme, reduceMotion: reduceMotion)
        menuFlyout = flyout
        isFlyoutPresented = true
        updateAccessibilityValue()
        updateAppearance(animated: true)
        flyout.onDismiss = { [weak self, weak flyout] in
            guard let self, self.menuFlyout === flyout else { return }
            self.menuFlyout = nil
            self.isFlyoutPresented = false
            self.updateAccessibilityValue()
            self.updateAppearance(animated: true)
        }
        flyout.present(relativeTo: self, placement: flyoutPlacement)
        if !flyout.isPresented {
            menuFlyout = nil
            isFlyoutPresented = false
            updateAccessibilityValue()
            updateAppearance(animated: false)
        }
    }

    private func dismissFlyout(animated: Bool) {
        menuFlyout?.dismiss(animated: animated)
        menuFlyout = nil
        isFlyoutPresented = false
        updateAccessibilityValue()
        updateAppearance(animated: animated)
    }

    private func updateAccessibilityValue() {
        let expansion = isFlyoutPresented ? "Expanded" : "Collapsed"
        setAccessibilityValue(isCheckedForAppearance ? "On, \(expansion)" : expansion)
    }
}

/// SplitButton variant whose primary region toggles state before invoking its action.
public final class FluentToggleSplitButton: FluentSplitButton {
    public var isChecked: Bool {
        didSet {
            guard oldValue != isChecked else { return }
            checkedStateDidChange(animated: true)
            onIsCheckedChanged?(isChecked)
        }
    }
    public var onIsCheckedChanged: ((Bool) -> Void)?

    public init(
        _ title: String,
        isChecked: Bool = false,
        items: [FluentMenuItem],
        action: (() -> Void)? = nil
    ) {
        self.isChecked = isChecked
        super.init(title, items: items, action: action)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var isCheckedForAppearance: Bool { isChecked }

    public override func invokePrimaryAction() {
        isChecked.toggle()
        super.invokePrimaryAction()
    }

    func setCheckedFromBinding(_ value: Bool) {
        guard isChecked != value else { return }
        isChecked = value
    }
}

public struct FluentSplitButtonView: FluentUpdatablePrimitiveView {
    public let title: String
    public let items: [FluentMenuItem]
    public let action: (() -> Void)?
    public let placement: FluentMenuPlacement

    public init(
        _ title: String,
        placement: FluentMenuPlacement = .below,
        action: (() -> Void)? = nil,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) {
        self.title = title
        self.items = items()
        self.action = action
        self.placement = placement
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let button = FluentSplitButton(title, items: items, action: action)
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.flyoutPlacement = placement
        return button
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentSplitButton, !(button is FluentToggleSplitButton) else { return false }
        button.title = title
        button.items = items
        button.onPrimaryAction = action
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.flyoutPlacement = placement
        return true
    }
}

private final class FluentToggleSplitButtonHost: NSView {
    let button: FluentToggleSplitButton
    private var binding: FluentBinding<Bool>
    private var observerID: UUID?
    private var isApplyingBinding = false

    init(
        title: String,
        binding: FluentBinding<Bool>,
        items: [FluentMenuItem],
        action: (() -> Void)?,
        placement: FluentMenuPlacement,
        context: FluentRenderContext
    ) {
        self.binding = binding
        button = FluentToggleSplitButton(title, isChecked: binding.get(), items: items, action: action)
        super.init(frame: .zero)
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.flyoutPlacement = placement
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        button.onIsCheckedChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.binding.set(value)
        }
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { button.intrinsicContentSize }

    func update(
        title: String,
        binding: FluentBinding<Bool>,
        items: [FluentMenuItem],
        action: (() -> Void)?,
        placement: FluentMenuPlacement,
        context: FluentRenderContext
    ) {
        removeObserver()
        self.binding = binding
        button.title = title
        button.items = items
        button.onPrimaryAction = action
        button.flyoutPlacement = placement
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        isApplyingBinding = true
        button.setCheckedFromBinding(binding.get())
        isApplyingBinding = false
        installObserver()
        invalidateIntrinsicContentSize()
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.button.isChecked != value else { return }
                self.isApplyingBinding = true
                self.button.setCheckedFromBinding(value)
                self.isApplyingBinding = false
            }
        }
    }

    private func removeObserver() {
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    deinit { removeObserver() }
}

public struct FluentToggleSplitButtonView: FluentUpdatablePrimitiveView {
    public let title: String
    public let isChecked: FluentBinding<Bool>
    public let items: [FluentMenuItem]
    public let action: (() -> Void)?
    public let placement: FluentMenuPlacement

    public init(
        _ title: String,
        isChecked: FluentBinding<Bool>,
        placement: FluentMenuPlacement = .below,
        action: (() -> Void)? = nil,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) {
        self.title = title
        self.isChecked = isChecked
        self.items = items()
        self.action = action
        self.placement = placement
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentToggleSplitButtonHost(
            title: title,
            binding: isChecked,
            items: items,
            action: action,
            placement: placement,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentToggleSplitButtonHost else { return false }
        host.update(
            title: title,
            binding: isChecked,
            items: items,
            action: action,
            placement: placement,
            context: context
        )
        return true
    }
}
