import AppKit

/// The CommandBar-wide label policy inherited by AppBar elements whose own label position is
/// `.default`.
public enum FluentCommandBarDefaultLabelPosition: Hashable, Sendable {
    case bottom
    case right
    case collapsed
}

/// AppBarButton's local label override. WinUI intentionally exposes only Default and Collapsed;
/// bottom/right are selected by the containing CommandBar.
public enum FluentCommandBarLabelPosition: Hashable, Sendable {
    case `default`
    case collapsed
}

/// The template branch currently used by an AppBar element.
public enum FluentAppBarPresentation: Hashable, Sendable {
    case fullSize
    case compact
    case labelOnRight
    case labelCollapsed
    case overflow
}

/// WinUI-style AppBarButton. It preserves the source 68×64 full-size geometry, compact and
/// label-position branches, overflow-row semantics, attached flyout, and release-time activation.
open class FluentAppBarButton: NSControl, FluentControlSizeConfigurable {
    public static let defaultWidth: CGFloat = 68
    public static let fullSizeHeight: CGFloat = 64
    public static let compactHeight: CGFloat = 48
    public static let iconSize: CGFloat = 16
    public static let backgroundTransitionDuration: TimeInterval = 0.083

    public var label: String {
        didSet {
            guard oldValue != label else { return }
            setAccessibilityTitle(label)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var systemImageName: String? {
        didSet { guard oldValue != systemImageName else { return }; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    public var icon: FluentIconSource? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// Optional application density for horizontal/compact commands. WinUI's default remains 48.
    public var commandHeight: CGFloat? { didSet { invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true } }
    private var resolvedIcon: FluentIconSource? { icon ?? systemImageName.map(FluentIconSource.systemSymbol) }
    public var isCompact = false {
        didSet { presentationDidChange(oldValue != isCompact) }
    }
    public var useOverflowStyle = false {
        didSet {
            guard oldValue != useOverflowStyle else { return }
            if !useOverflowStyle { dismissFlyout(animated: false) }
            presentationDidChange(true)
        }
    }
    public var labelPosition: FluentCommandBarLabelPosition = .default {
        didSet { presentationDidChange(oldValue != labelPosition) }
    }
    public var defaultLabelPosition: FluentCommandBarDefaultLabelPosition = .bottom {
        didSet { presentationDidChange(oldValue != defaultLabelPosition) }
    }
    public var dynamicOverflowOrder = 0
    public var keyboardAcceleratorTextOverride = "" {
        didSet { guard oldValue != keyboardAcceleratorTextOverride else { return }; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// Updates an open flyout in place; stable item IDs preserve rows and keyboard selection.
    /// Setting nil or an empty array dismisses the flyout.
    public var flyoutItems: [FluentMenuItem]? {
        didSet {
            if (oldValue?.isEmpty == false) != (flyoutItems?.isEmpty == false) {
                invalidateIntrinsicContentSize()
                needsLayout = true
            }
            if flyoutItems?.isEmpty != false { dismissFlyout(animated: false) }
            else { updatePresentedFlyout() }
            updateAccessibilityMetadata()
            needsDisplay = true
        }
    }
    public var flyoutPlacement: FluentMenuPlacement = .below
    public var onClick: (() -> Void)?
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            updateFonts()
            updateAppearance(animated: false)
            updatePresentedFlyout()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion { [surfaceLayer, checkedBorderLayer, focusOuterLayer, focusInnerLayer].forEach { $0.removeAllAnimations() } }
            updateAppearance(animated: false)
            if oldValue != reduceMotion { updatePresentedFlyout() }
        }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            updateFonts()
            invalidateIntrinsicContentSize()
            needsLayout = true
            needsDisplay = true
        }
    }
    public private(set) var isFlyoutPresented = false
    public var isInOverflow: Bool { useOverflowStyle }

    open var isCheckedForAppearance: Bool { false }
    open var reservesOverflowToggleSlot: Bool { false }

    private var labelFont = FluentTheme.current.typography.font(for: .caption)
    private var overflowFont = FluentTheme.current.typography.font(for: .body)
    private var isPointerOver = false
    private var isPressed = false
    private var isTrackingPress = false
    private var isKeyboardPressed = false
    weak var hoverCoordinator: FluentHoverCoordinator<NSControl>?
    private lazy var pointerLifetime = FluentPointerLifetime { [weak self] in self?.cancelInteraction() }
    private var menuFlyout: FluentMenuFlyout?
    private let surfaceLayer = CALayer()
    private let checkedBorderLayer = CAGradientLayer()
    private let checkedBorderMask = CAShapeLayer()
    private let focusOuterLayer = CAShapeLayer()
    private let focusInnerLayer = CAShapeLayer()
    private let foregroundView = FluentControlForegroundView(frame: .zero)
    private let animationCoordinator = FluentAnimationCoordinator()

    public init(
        _ label: String,
        systemImageName: String? = nil,
        flyoutItems: [FluentMenuItem]? = nil,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.systemImageName = systemImageName
        self.flyoutItems = flyoutItems
        onClick = action
        super.init(frame: .zero)
        configure()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { menuFlyout?.dismiss(animated: false) }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { isEnabled }
    open override var needsDisplay: Bool {
        didSet {
            if needsDisplay, !foregroundView.needsDisplay { foregroundView.needsDisplay = true }
        }
    }

    private var effectiveTheme: FluentTheme { fluentResolvedTheme(theme, using: effectiveAppearance) }

    public var presentation: FluentAppBarPresentation {
        useOverflowStyle ? .overflow : primaryPresentation
    }

    private var primaryPresentation: FluentAppBarPresentation {
        let effective: FluentCommandBarDefaultLabelPosition = labelPosition == .collapsed ? .collapsed : defaultLabelPosition
        switch effective {
        case .right: return .labelOnRight
        case .collapsed: return .labelCollapsed
        case .bottom: return isCompact ? .compact : .fullSize
        }
    }

    public override var intrinsicContentSize: NSSize { contentSize(for: presentation) }

    /// Dynamic overflow must measure the primary template even while this control is in a menu.
    var primaryContentSize: NSSize { contentSize(for: primaryPresentation) }

    private func contentSize(for presentation: FluentAppBarPresentation) -> NSSize {
        let scale = fluentControlSize.metricScale
        switch presentation {
        case .fullSize:
            return NSSize(width: Self.defaultWidth * scale, height: Self.fullSizeHeight * scale)
        case .compact, .labelCollapsed:
            return NSSize(width: Self.defaultWidth * scale, height: max(commandHeight ?? Self.compactHeight * scale, 24 * scale))
        case .labelOnRight:
            let labelWidth = ceil((label as NSString).size(withAttributes: [.font: overflowFont]).width)
            return NSSize(width: max(Self.defaultWidth * scale, labelWidth + (resolvedIcon == nil ? 24 : 48) * scale + flyoutChevronSpace), height: max(commandHeight ?? Self.compactHeight * scale, 24 * scale))
        case .overflow:
            let labelWidth = ceil((label as NSString).size(withAttributes: [.font: overflowFont]).width)
            let accelerator = ceil((keyboardAcceleratorTextOverride as NSString).size(withAttributes: [.font: labelFont]).width)
            let leading = overflowLeadingInset
            return NSSize(width: max(160 * scale, leading + labelWidth + (accelerator > 0 ? 24 * scale + accelerator : 0) + 12 * scale + flyoutChevronSpace), height: 40 * scale)
        }
    }

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                cancelInteraction()
                dismissFlyout(animated: false)
            }
            setAccessibilityEnabled(isEnabled)
            updateAppearance(animated: true)
        }
    }

    public override func layout() {
        super.layout()
        updateGeometry()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    public override func mouseEntered(with event: NSEvent) {
        updatePointerHover(true)
    }

    open override func mouseMoved(with event: NSEvent) {
        updatePointerHover(visibleRect.contains(convert(event.locationInWindow, from: nil)))
    }

    public override func mouseExited(with event: NSEvent) {
        if !isTrackingPress { isPressed = false }
        updatePointerHover(false)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        // WinUI AppBarButton has AllowFocusOnInteraction=False: pointer activation must not steal
        // keyboard focus from the current command target.
        FluentFocusVisibility.markPointerInteraction(in: window)
        isTrackingPress = true
        isPressed = true
        updatePointerHover(true)
        updateAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = inside
        updatePointerHover(inside)
        updateAppearance(animated: true)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isTrackingPress = false
        isPressed = false
        updatePointerHover(inside)
        updateAppearance(animated: true)
        if inside { invoke() }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        if (event.keyCode == 36 || event.keyCode == 49), !event.isARepeat {
            isKeyboardPressed = true
            updateInteractionLifetime()
            updateAppearance(animated: true)
        } else if event.keyCode == 53 {
            cancelInteraction()
        } else {
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard isEnabled else { return }
        if (event.keyCode == 36 || event.keyCode == 49), isKeyboardPressed {
            isKeyboardPressed = false
            updateInteractionLifetime()
            updateAppearance(animated: true)
            invoke()
        } else {
            super.keyUp(with: event)
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            pointerLifetime.observe(window)
            updateAppearance(animated: false)
        }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            cancelInteraction()
            pointerLifetime.invalidate()
        }
        return result
    }

    func setPointerHover(_ value: Bool) {
        // A disabled command still takes ownership so a missed exit cannot leave its sibling lit.
        let next = value && isEnabled
        let changed = isPointerOver != next
        isPointerOver = next
        updateInteractionLifetime()
        if changed { updateAppearance(animated: true) }
    }

    private func updatePointerHover(_ value: Bool) {
        if let hoverCoordinator { hoverCoordinator.update(self, hovering: value) }
        else { setPointerHover(value) }
    }

    private func updateInteractionLifetime() {
        if isPointerOver || isTrackingPress || isKeyboardPressed ||
            (window?.isVisible == true && window?.firstResponder === self) {
            pointerLifetime.observe(window)
        } else { pointerLifetime.invalidate() }
    }

    private func cancelInteraction() {
        isTrackingPress = false
        isPressed = false
        isKeyboardPressed = false
        updatePointerHover(false)
        // Checked and expanded states belong to the command, not the cancelled input.
        updateAppearance(animated: false)
    }

    open override func cancelOperation(_ sender: Any?) { cancelInteraction() }
    open override func viewDidHide() { super.viewDidHide(); cancelInteraction() }
    open override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { cancelInteraction() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    open override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelInteraction(); pointerLifetime.invalidate() }
        super.viewWillMove(toWindow: newWindow)
    }
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInteractionLifetime()
        updateAppearance(animated: false)
    }
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance(animated: false)
    }

    public override func draw(_ dirtyRect: NSRect) {
        // Backing contents render below every sublayer. Draw the label and icon in their
        // own transparent child so animated/opaque chrome cannot cover them.
        foregroundView.setNeedsDisplay(dirtyRect)
    }

    private func drawForeground(_ dirtyRect: NSRect) {
        let foreground = resolvedForeground
        switch presentation {
        case .fullSize:
            drawIcon(in: CGRect(x: (bounds.width - 16) / 2, y: 16, width: 16, height: 16), color: foreground)
            drawLabel(in: CGRect(x: 2, y: 39, width: max(0, bounds.width - 4), height: 18), font: labelFont, color: foreground, alignment: .center)
            drawAttachedFlyoutChevron(color: foreground, overflow: false)
        case .compact:
            drawIcon(in: CGRect(x: (bounds.width - 16) / 2, y: 12, width: 16, height: 16), color: foreground)
            drawAttachedFlyoutChevron(color: foreground, overflow: false)
        case .labelCollapsed:
            drawIcon(in: CGRect(x: (bounds.width - 16) / 2, y: 16, width: 16, height: 16), color: foreground)
            drawAttachedFlyoutChevron(color: foreground, overflow: false)
        case .labelOnRight:
            let geometry = horizontalContentGeometry
            drawIcon(in: geometry.icon, color: foreground)
            drawLabel(in: geometry.label, font: overflowFont, color: foreground,
                      alignment: userInterfaceLayoutDirection == .rightToLeft ? .right : .left)
            drawAttachedFlyoutChevron(color: foreground, overflow: false)
        case .overflow:
            drawOverflowContent(color: foreground)
        }
    }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        invoke()
        return true
    }

    public func showFlyout() { presentFlyout() }
    public func hideFlyout(animated: Bool = true) { dismissFlyout(animated: animated) }

    private func updatePresentedFlyout() {
        menuFlyout?.update(items: flyoutItems ?? [], theme: theme, reduceMotion: reduceMotion)
    }

    open func invokeAction() { onClick?() }

    func checkedAppearanceDidChange(animated: Bool) {
        updateAccessibilityMetadata()
        updateAppearance(animated: animated)
    }

    private var interactionState: FluentControlState {
        if !isEnabled { return .disabled }
        if isPressed || isKeyboardPressed { return .pressed }
        if isPointerOver || isFlyoutPresented { return .pointerOver }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) { return .focused }
        return .normal
    }

    private var resolvedBackground: NSColor {
        let theme = effectiveTheme
        if useOverflowStyle, isCheckedForAppearance {
            switch interactionState {
            case .pointerOver: return theme.subtleFillSecondary
            case .pressed: return theme.subtleFillTertiary
            default: return .clear
            }
        }
        if isCheckedForAppearance {
            return theme.accentFill(for: interactionState)
        }
        switch interactionState {
        case .pointerOver: return theme.subtleFillSecondary
        case .pressed: return theme.subtleFillTertiary
        // WinUI's disabled AppBarButton background remains transparent; only
        // the foreground changes to the disabled text/icon brush.
        case .disabled: return .clear
        default: return .clear
        }
    }

    private var resolvedForeground: NSColor {
        let theme = effectiveTheme
        if useOverflowStyle { // Overflow checked states retain normal text and expose a check slot.
            switch interactionState {
            case .pressed: return theme.textSecondary
            case .disabled: return theme.textDisabled
            default: return theme.textPrimary
            }
        }
        if isCheckedForAppearance {
            switch interactionState {
            case .pressed: return theme.textOnAccentSecondary
            case .disabled: return theme.textOnAccentDisabled
            default: return theme.textOnAccent
            }
        }
        switch interactionState {
        case .pressed: return theme.textSecondary
        case .disabled: return theme.textDisabled
        default: return theme.textPrimary
        }
    }

    private var surfaceFrame: CGRect {
        let scale = fluentControlSize.metricScale
        switch presentation {
        case .overflow:
            return inset(bounds, top: 0, left: 4 * scale, bottom: 0, right: 4 * scale)
        default:
            // WinUI's AppBarButton Root owns the complete state background and only applies
            // Margin="1,0". Compact/LabelCollapsed change content placement, not the hit or
            // background surface height.
            return inset(bounds, top: 0, left: 1 * scale, bottom: 0, right: 1 * scale)
        }
    }

    private func inset(
        _ rect: CGRect,
        top: CGFloat,
        left: CGFloat,
        bottom: CGFloat,
        right: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.minX + left,
            y: rect.minY + top,
            width: max(0, rect.width - left - right),
            height: max(0, rect.height - top - bottom)
        )
    }

    private var overflowLeadingInset: CGFloat {
        let scale = fluentControlSize.metricScale
        if reservesOverflowToggleSlot && resolvedIcon != nil { return 76 * scale }
        if reservesOverflowToggleSlot || resolvedIcon != nil { return 38 * scale }
        return 12 * scale
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = false
        surfaceLayer.name = "FluentKit.AppBarButton.InnerBorder"
        surfaceLayer.cornerCurve = .continuous
        layer?.addSublayer(surfaceLayer)
        checkedBorderLayer.name = "FluentKit.AppBarButton.CheckedElevationBorder"
        checkedBorderMask.fillColor = NSColor.clear.cgColor
        checkedBorderMask.strokeColor = NSColor.white.cgColor
        checkedBorderLayer.mask = checkedBorderMask
        layer?.addSublayer(checkedBorderLayer)
        for focus in [focusOuterLayer, focusInnerLayer] {
            focus.fillColor = NSColor.clear.cgColor
            focus.opacity = 0
            layer?.addSublayer(focus)
        }
        focusOuterLayer.name = "FluentKit.AppBarButton.FocusOuter"
        focusInnerLayer.name = "FluentKit.AppBarButton.FocusInner"
        foregroundView.drawContent = { [weak self] rect in self?.drawForeground(rect) }
        addSubview(foregroundView)
        animationCoordinator.reduceMotion = reduceMotion
        setAccessibilityRole(.button)
        setAccessibilityTitle(label)
        setAccessibilityEnabled(isEnabled)
        updateFonts()
        updateAccessibilityMetadata()
        updateAppearance(animated: false)
    }

    private func updateFonts() {
        let scale = fluentControlSize.metricScale
        labelFont = theme.typography.font(for: .caption).withSize(12 * scale)
        let body = theme.typography.font(for: .body)
        overflowFont = body.withSize(body.pointSize * scale)
        invalidateIntrinsicContentSize()
    }

    private func presentationDidChange(_ changed: Bool) {
        guard changed else { return }
        invalidateIntrinsicContentSize()
        needsLayout = true
        updateAccessibilityMetadata()
        updateAppearance(animated: false)
    }

    private func updateGeometry() {
        if foregroundView.frame != bounds { foregroundView.frame = bounds }
        let rect = surfaceFrame
        let radius = theme.designTokens.controlCornerRadius * fluentControlSize.metricScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = rect
        surfaceLayer.cornerRadius = radius
        checkedBorderLayer.frame = rect
        checkedBorderLayer.startPoint = CGPoint(x: 0.5, y: 0)
        checkedBorderLayer.endPoint = CGPoint(x: 0.5, y: 1)
        checkedBorderMask.frame = checkedBorderLayer.bounds
        checkedBorderMask.path = CGPath(roundedRect: checkedBorderLayer.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
        checkedBorderMask.lineWidth = 1
        let outer = rect.insetBy(dx: -3, dy: -3)
        focusOuterLayer.frame = bounds
        focusOuterLayer.path = CGPath(roundedRect: outer, cornerWidth: radius + 3, cornerHeight: radius + 3, transform: nil)
        focusOuterLayer.lineWidth = 2
        focusInnerLayer.frame = bounds
        focusInnerLayer.path = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: max(radius - 1, 0), cornerHeight: max(radius - 1, 0), transform: nil)
        focusInnerLayer.lineWidth = 1
        CATransaction.commit()
    }

    private func updateAppearance(animated: Bool) {
        updateGeometry()
        let requestedAppearance = fluentAppKitAppearance(for: theme)
        if foregroundView.appearance?.name != requestedAppearance?.name {
            foregroundView.appearance = requestedAppearance
        }
        let theme = effectiveTheme
        let drawingAppearance = fluentAppKitAppearance(for: theme) ?? effectiveAppearance
        // Resolve adaptive accent colors before caching CGColors. State updates can arrive
        // outside drawing, under the application's or another window's appearance.
        drawingAppearance.performAsCurrentDrawingAppearance {
            let background = resolvedBackground.cgColor
            animationCoordinator.animateState([
                FluentLayerAnimationChange(layer: surfaceLayer, key: "fluent.appbar.background", keyPath: "backgroundColor", toValue: background) { [weak surfaceLayer] in
                    surfaceLayer?.backgroundColor = background
                }
            ], motion: FluentMotionToken(duration: Self.backgroundTransitionDuration, curve: .linear), animated: animated)

            let checkedBorderVisible = isCheckedForAppearance && !useOverflowStyle && isEnabled && interactionState != .pressed
            let showsFocus = FluentFocusVisibility.isKeyboardFocusVisible(for: self)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            checkedBorderLayer.colors = theme.accentElevationBorderColors.map(\.cgColor)
            checkedBorderLayer.opacity = checkedBorderVisible ? 1 : 0
            focusOuterLayer.strokeColor = theme.focusStrokeOuter.cgColor
            focusInnerLayer.strokeColor = theme.focusStrokeInner.cgColor
            focusOuterLayer.opacity = showsFocus ? 1 : 0
            focusInnerLayer.opacity = showsFocus ? 1 : 0
            CATransaction.commit()
        }
        needsDisplay = true
    }

    var flyoutChevronSpace: CGFloat {
        flyoutItems?.isEmpty == false ? (useOverflowStyle ? 24 : 16) * fluentControlSize.metricScale : 0
    }

    var horizontalContentGeometry: (icon: CGRect, label: CGRect, chevron: CGRect) {
        let scale = fluentControlSize.metricScale
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let leading: CGFloat = resolvedIcon == nil ? 12 : 36
        let label = CGRect(x: leading * scale, y: bounds.midY - 10 * scale,
                           width: max(0, bounds.width - (leading + 12) * scale - flyoutChevronSpace), height: 20 * scale)
        let icon = CGRect(x: 12 * scale, y: bounds.midY - 8 * scale, width: 16 * scale, height: 16 * scale)
        let chevron = CGRect(x: bounds.maxX - 20 * scale, y: bounds.midY - 4 * scale, width: 8 * scale, height: 8 * scale)
        func mirror(_ r: CGRect) -> CGRect { rtl ? CGRect(x: bounds.maxX - r.maxX, y: r.minY, width: r.width, height: r.height) : r }
        return (mirror(icon), mirror(label), mirror(chevron))
    }

    private func drawIcon(in rect: CGRect, color: NSColor) {
        resolvedIcon?.draw(in: rect, color: color, layoutDirection: userInterfaceLayoutDirection)
    }

    private func drawLabel(in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (label as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func drawOverflowContent(color: NSColor) {
        let theme = effectiveTheme
        let scale = fluentControlSize.metricScale
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        if reservesOverflowToggleSlot, isCheckedForAppearance {
            let x = rtl ? bounds.maxX - 26 * scale : 12 * scale
            drawSystemGlyph("checkmark", in: CGRect(x: x, y: 13 * scale, width: 14 * scale, height: 14 * scale), color: color, pointSize: 14 * scale)
        }
        if resolvedIcon != nil {
            let x: CGFloat
            if rtl {
                x = bounds.maxX - (reservesOverflowToggleSlot ? 54 : 28) * scale
            } else {
                x = (reservesOverflowToggleSlot ? 38 : 12) * scale
            }
            drawIcon(in: CGRect(x: x, y: 12 * scale, width: 16 * scale, height: 16 * scale), color: color)
        }
        let leading = overflowLeadingInset
        let acceleratorWidth = (keyboardAcceleratorTextOverride as NSString).size(withAttributes: [.font: labelFont]).width
        let acceleratorSpace = keyboardAcceleratorTextOverride.isEmpty ? 0 : acceleratorWidth + 24 * scale
        let textX = rtl ? 12 * scale + acceleratorSpace + flyoutChevronSpace : leading
        drawLabel(
            in: CGRect(x: textX, y: 10 * scale, width: max(0, bounds.width - leading - 12 * scale - acceleratorSpace - flyoutChevronSpace), height: 20 * scale),
            font: overflowFont,
            color: color,
            alignment: rtl ? .right : .left
        )
        if !keyboardAcceleratorTextOverride.isEmpty {
            let x = rtl ? 12 * scale + flyoutChevronSpace : bounds.maxX - 12 * scale - acceleratorWidth - flyoutChevronSpace
            drawLabel(in: CGRect(x: x, y: 11 * scale, width: acceleratorWidth, height: 18 * scale), font: labelFont, color: interactionState == .pressed ? theme.textTertiary : theme.textSecondary, alignment: rtl ? .left : .right)
        }
        drawAttachedFlyoutChevron(color: color, overflow: true)
    }

    private func drawAttachedFlyoutChevron(color: NSColor, overflow: Bool) {
        guard flyoutItems?.isEmpty == false else { return }
        let size: CGFloat = overflow ? 12 : 8
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let symbol = overflow ? (rtl ? "chevron.left" : "chevron.right") : "chevron.down"
        let rect: CGRect
        if overflow {
            rect = CGRect(x: rtl ? 12 : bounds.maxX - 28, y: bounds.midY - size / 2, width: size, height: size)
        } else {
            rect = horizontalContentGeometry.chevron
        }
        drawSystemGlyph(symbol, in: rect, color: color, pointSize: size)
    }

    private func drawSystemGlyph(_ name: String, in rect: CGRect, color: NSColor, pointSize: CGFloat) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configured = image.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular).applying(.init(hierarchicalColor: color))) ?? image
        configured.draw(in: FluentIconSource.systemSymbol(name).fittedRect(imageSize: configured.size, in: rect), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func invoke() {
        invokeAction()
        guard flyoutItems?.isEmpty == false else { return }
        if isFlyoutPresented { dismissFlyout(animated: true) } else { presentFlyout() }
    }

    private func presentFlyout() {
        guard isEnabled, !isFlyoutPresented, let items = flyoutItems, !items.isEmpty, window != nil else { return }
        let flyout = FluentMenuFlyout(items: items, theme: theme, reduceMotion: reduceMotion)
        menuFlyout = flyout
        isFlyoutPresented = true
        updateAccessibilityMetadata()
        updateAppearance(animated: true)
        flyout.onDismiss = { [weak self, weak flyout] in
            guard let self, self.menuFlyout === flyout else { return }
            self.menuFlyout = nil
            self.isFlyoutPresented = false
            self.updateAccessibilityMetadata()
            self.updateAppearance(animated: true)
        }
        flyout.present(relativeTo: self, placement: flyoutPlacement)
    }

    private func dismissFlyout(animated: Bool) {
        menuFlyout?.dismiss(animated: animated)
        menuFlyout = nil
        isFlyoutPresented = false
        updateAccessibilityMetadata()
        updateAppearance(animated: false)
    }

    private func updateAccessibilityMetadata() {
        setAccessibilityTitle(label)
        setAccessibilityValue(isCheckedForAppearance ? "On" : nil)
        setAccessibilityExpanded(flyoutItems?.isEmpty == false && isFlyoutPresented)
        setAccessibilityHelp(keyboardAcceleratorTextOverride.isEmpty ? nil : keyboardAcceleratorTextOverride)
    }
}

/// AppBarButton whose click toggles a Boolean state. In overflow it uses WinUI's check slot rather
/// than carrying the accent-filled primary surface into the menu row.
public final class FluentAppBarToggleButton: FluentAppBarButton {
    public var isChecked: Bool {
        didSet {
            guard oldValue != isChecked else { return }
            checkedAppearanceDidChange(animated: true)
            onIsCheckedChanged?(isChecked)
        }
    }
    public var onIsCheckedChanged: ((Bool) -> Void)?

    public init(_ label: String, systemImageName: String? = nil, isChecked: Bool = false, action: ((Bool) -> Void)? = nil) {
        self.isChecked = isChecked
        super.init(label, systemImageName: systemImageName)
        onIsCheckedChanged = action
        setAccessibilityRole(.checkBox)
        checkedAppearanceDidChange(animated: false)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override var isCheckedForAppearance: Bool { isChecked }
    public override var reservesOverflowToggleSlot: Bool { true }

    public override func invokeAction() {
        isChecked.toggle()
        super.invokeAction()
    }

    func setCheckedFromBinding(_ value: Bool) {
        guard isChecked != value else { return }
        isChecked = value
    }
}

/// AppBarSeparator's source one-point divider with full-size, compact, and overflow branches.
public final class FluentAppBarSeparator: NSView, FluentControlSizeConfigurable {
    public var useOverflowStyle = false { didSet { if oldValue != useOverflowStyle { invalidateIntrinsicContentSize(); needsLayout = true } } }
    public var isCompact = false { didSet { if oldValue != isCompact { invalidateIntrinsicContentSize(); needsLayout = true } } }
    public var dynamicOverflowOrder = 0
    public var isInOverflow: Bool { useOverflowStyle }
    public var theme: FluentTheme = .current { didSet { updateAppearance() } }
    public var fluentControlSize: FluentControlSize = .regular { didSet { invalidateIntrinsicContentSize(); needsLayout = true } }
    private let dividerLayer = CALayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dividerLayer.name = "FluentKit.AppBarSeparator.Divider"
        layer?.addSublayer(dividerLayer)
        updateAppearance()
        setAccessibilityElement(false)
    }

    public convenience init(useOverflowStyle: Bool = false) {
        self.init(frame: .zero)
        self.useOverflowStyle = useOverflowStyle
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override var isFlipped: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let theme = fluentResolvedTheme(theme, using: effectiveAppearance)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dividerLayer.backgroundColor = theme.divider.cgColor
        CATransaction.commit()
    }

    public override var intrinsicContentSize: NSSize {
        let scale = fluentControlSize.metricScale
        if useOverflowStyle { return NSSize(width: 160 * scale, height: 9 * scale) }
        return NSSize(width: 5 * scale, height: (isCompact ? 48 : 64) * scale)
    }

    public override func layout() {
        super.layout()
        let scale = fluentControlSize.metricScale
        let pixel = FluentPixelGeometry(backingScale: window?.backingScaleFactor).pixel
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if useOverflowStyle {
            dividerLayer.frame = CGRect(x: 0, y: 4 * scale, width: bounds.width, height: pixel)
            dividerLayer.cornerRadius = pixel / 2
        } else {
            dividerLayer.frame = CGRect(x: (bounds.width - pixel) / 2, y: 8 * scale, width: pixel, height: max(0, bounds.height - 16 * scale))
            dividerLayer.cornerRadius = pixel / 2
        }
        CATransaction.commit()
    }
}

public struct FluentAppBarButtonView: FluentUpdatablePrimitiveView {
    public let label: String
    public let systemImageName: String?
    public let icon: FluentIconSource?
    public let commandHeight: CGFloat?
    public let isCompact: Bool
    public let useOverflowStyle: Bool
    public let labelPosition: FluentCommandBarLabelPosition
    public let defaultLabelPosition: FluentCommandBarDefaultLabelPosition
    public let keyboardAcceleratorText: String
    public let flyoutItems: [FluentMenuItem]?
    public let action: (() -> Void)?

    public init(
        _ label: String,
        systemImageName: String? = nil,
        icon: FluentIconSource? = nil,
        commandHeight: CGFloat? = nil,
        isCompact: Bool = false,
        useOverflowStyle: Bool = false,
        labelPosition: FluentCommandBarLabelPosition = .default,
        defaultLabelPosition: FluentCommandBarDefaultLabelPosition = .bottom,
        keyboardAcceleratorText: String = "",
        flyoutItems: [FluentMenuItem]? = nil,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.systemImageName = systemImageName
        self.icon = icon
        self.commandHeight = commandHeight
        self.isCompact = isCompact
        self.useOverflowStyle = useOverflowStyle
        self.labelPosition = labelPosition
        self.defaultLabelPosition = defaultLabelPosition
        self.keyboardAcceleratorText = keyboardAcceleratorText
        self.flyoutItems = flyoutItems
        self.action = action
    }

    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        let button = FluentAppBarButton(label, systemImageName: systemImageName, flyoutItems: flyoutItems, action: action)
        apply(to: button, context: context)
        return button
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentAppBarButton, !(button is FluentAppBarToggleButton) else { return false }
        button.label = label
        button.systemImageName = systemImageName
        button.flyoutItems = flyoutItems
        button.onClick = action
        apply(to: button, context: context)
        return true
    }
    private func apply(to button: FluentAppBarButton, context: FluentRenderContext) {
        button.icon = icon
        button.commandHeight = commandHeight
        button.isCompact = isCompact
        button.useOverflowStyle = useOverflowStyle
        button.labelPosition = labelPosition
        button.defaultLabelPosition = defaultLabelPosition
        button.keyboardAcceleratorTextOverride = keyboardAcceleratorText
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
    }
}

private final class FluentAppBarToggleButtonHost: NSView {
    let button: FluentAppBarToggleButton
    private var binding: FluentBinding<Bool>
    private var observerID: UUID?
    private var applying = false

    init(label: String, systemImageName: String?, binding: FluentBinding<Bool>, context: FluentRenderContext) {
        self.binding = binding
        button = FluentAppBarToggleButton(label, systemImageName: systemImageName, isChecked: binding.get())
        super.init(frame: .zero)
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        button.onIsCheckedChanged = { [weak self] value in
            guard let self, !self.applying else { return }
            self.binding.set(value)
        }
        update(label: label, systemImageName: systemImageName, binding: binding, context: context)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { button.intrinsicContentSize }
    func update(label: String, systemImageName: String?, binding: FluentBinding<Bool>, context: FluentRenderContext) {
        removeObserver()
        self.binding = binding
        button.label = label
        button.systemImageName = systemImageName
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        applying = true
        button.setCheckedFromBinding(binding.get())
        applying = false
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applying = true
                self.button.setCheckedFromBinding(value)
                self.applying = false
            }
        }
        invalidateIntrinsicContentSize()
    }
    private func removeObserver() { if let observerID { binding.removeObserver(observerID) }; observerID = nil }
    deinit { removeObserver() }
}

public struct FluentAppBarToggleButtonView: FluentUpdatablePrimitiveView {
    public let label: String
    public let systemImageName: String?
    public let isChecked: FluentBinding<Bool>
    public let isCompact: Bool
    public let useOverflowStyle: Bool
    public let labelPosition: FluentCommandBarLabelPosition
    public let defaultLabelPosition: FluentCommandBarDefaultLabelPosition

    public init(
        _ label: String,
        systemImageName: String? = nil,
        isChecked: FluentBinding<Bool>,
        isCompact: Bool = false,
        useOverflowStyle: Bool = false,
        labelPosition: FluentCommandBarLabelPosition = .default,
        defaultLabelPosition: FluentCommandBarDefaultLabelPosition = .bottom
    ) {
        self.label = label
        self.systemImageName = systemImageName
        self.isChecked = isChecked
        self.isCompact = isCompact
        self.useOverflowStyle = useOverflowStyle
        self.labelPosition = labelPosition
        self.defaultLabelPosition = defaultLabelPosition
    }
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentAppBarToggleButtonHost(label: label, systemImageName: systemImageName, binding: isChecked, context: context)
        apply(to: host.button)
        return host
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentAppBarToggleButtonHost else { return false }
        host.update(label: label, systemImageName: systemImageName, binding: isChecked, context: context)
        apply(to: host.button)
        return true
    }
    private func apply(to button: FluentAppBarToggleButton) {
        button.isCompact = isCompact
        button.useOverflowStyle = useOverflowStyle
        button.labelPosition = labelPosition
        button.defaultLabelPosition = defaultLabelPosition
    }
}

public struct FluentAppBarSeparatorView: FluentUpdatablePrimitiveView {
    public let isCompact: Bool
    public let useOverflowStyle: Bool
    public init(isCompact: Bool = false, useOverflowStyle: Bool = false) {
        self.isCompact = isCompact
        self.useOverflowStyle = useOverflowStyle
    }
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        let separator = FluentAppBarSeparator(useOverflowStyle: useOverflowStyle)
        separator.isCompact = isCompact
        separator.theme = context.theme
        return separator
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let separator = view as? FluentAppBarSeparator else { return false }
        separator.isCompact = isCompact
        separator.useOverflowStyle = useOverflowStyle
        separator.theme = context.theme
        return true
    }
}
