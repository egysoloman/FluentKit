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
            else { updatePresentedFlyout() }
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
            updatePresentedFlyout()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion { settleVisualAnimations() }
            updateAppearance(animated: false)
            updatePresentedFlyout()
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
    public var flyoutPlacement: FluentMenuPlacement = .below {
        didSet { menuFlyout?.reposition(placement: flyoutPlacement) }
    }
    public private(set) var isFlyoutPresented = false

    private enum HitRegion: Equatable { case none, primary, secondary }

    private var displayFont = FluentTheme.current.typography.font(for: .body)
    private var hoveredRegion: HitRegion = .none
    private var pressedRegion: HitRegion = .none
    private var isTrackingPress = false
    private var isKeyboardPressed = false
    private var lastPointerDevice: FluentInputDeviceType = .mouse
    private var windowObservers: [NSObjectProtocol] = []
    private var menuFlyout: FluentMenuFlyout?
    private let primaryLayer = CALayer()
    private let secondaryLayer = CALayer()
    private let dividerLayer = CALayer()
    private let primaryBorderClip = CALayer()
    private let secondaryBorderClip = CALayer()
    private let secondaryBorderLayer = CAGradientLayer()
    private let secondaryBorderMask = CAShapeLayer()
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
            if !isEnabled { cancelInteraction() }
            else { updateAppearance(animated: true) }
        }
    }

    public override func layout() {
        super.layout()
        synchronizeGeometry()
        updateChevron(animated: false)
        menuFlyout?.reposition()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeGeometry()
        updateChevron(animated: false)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeGeometry()
        updateChevron(animated: false)
    }

    public override var frame: NSRect {
        didSet { if oldValue != frame { menuFlyout?.reposition() } }
    }

    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        menuFlyout?.reposition()
    }

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { cancelInteraction() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            cancelInteraction()
            removeWindowObservers()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeGeometry()
        updateChevron(animated: false)
        removeWindowObservers()
        guard let window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                guard let self else { return }
                // The menu legitimately becomes key; only cancel the captured button press.
                self.cancelInteraction(dismissMenu: notification.name == NSWindow.willCloseNotification)
            })
        }
    }

    public override func viewDidHide() {
        super.viewDidHide()
        cancelInteraction()
    }

    private func cancelInteraction(dismissMenu: Bool = true) {
        isTrackingPress = false
        isKeyboardPressed = false
        pressedRegion = .none
        hoveredRegion = .none
        if dismissMenu { dismissFlyout(animated: false) }
        else { updateAppearance(animated: false) }
        settleVisualAnimations()
    }

    private func settleVisualAnimations() {
        animationCoordinator.cancelAll(on: [layer, primaryLayer, secondaryLayer, dividerLayer,
            elevationBorderLayer, secondaryBorderLayer, focusOuterLayer, focusInnerLayer].compactMap { $0 })
        chevronLayer.finishAnimations()
    }

    private func removeWindowObservers() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    deinit { removeWindowObservers() }

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
        updatePointerDevice(event)
        hoveredRegion = region(at: convert(event.locationInWindow, from: nil))
        updateAppearance(animated: true)
    }

    public override func mouseMoved(with event: NSEvent) {
        guard isEnabled, !isTrackingPress else { return }
        let previousDevice = lastPointerDevice
        updatePointerDevice(event)
        let next = region(at: convert(event.locationInWindow, from: nil))
        guard next != hoveredRegion || previousDevice != lastPointerDevice else { return }
        hoveredRegion = next
        updateAppearance(animated: true)
    }

    public override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        hoveredRegion = .none
        if !isTrackingPress { pressedRegion = .none }
        updateAppearance(animated: true)
    }

    private func updatePointerDevice(_ event: NSEvent) {
        let device = FluentInputDeviceTracker.deviceType(for: event)
            ?? FluentInputDeviceTracker.shared.lastDeviceType(in: window)
        if device == .mouse || device == .touch || device == .pen { lastPointerDevice = device }
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        lastPointerDevice = FluentInputDeviceTracker.deviceType(for: event) ?? .mouse
        FluentInputDeviceTracker.shared.record(lastPointerDevice, in: window)
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
        guard isEnabled, isTrackingPress else { return }
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
        case 36, 49:
            if !event.isARepeat {
                isKeyboardPressed = true
                updateAppearance(animated: true)
            }
        case 118:
            break
        case 125 where event.modifierFlags.contains(.option):
            break // Open on key-up without forwarding the opening key to AppKit's default handler.
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
        let result = super.resignFirstResponder()
        if result { cancelInteraction(dismissMenu: false) }
        return result
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        // NSView receives points in its superview coordinate system and handles hidden ancestors.
        super.hitTest(point) == nil ? nil : self
    }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        invokePrimaryAction()
        return true
    }

    public override func accessibilityPerformShowMenu() -> Bool {
        guard isEnabled, !items.isEmpty else { return false }
        presentFlyout()
        return isFlyoutPresented
    }

    open func invokePrimaryAction() {
        guard isEnabled else { return }
        performAcceptedPrimaryAction()
    }

    fileprivate func performAcceptedPrimaryAction() {
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

    private var isWholeControlPressed: Bool {
        isFlyoutPresented || isKeyboardPressed || (lastPointerDevice == .touch && activePressedRegion != .none)
    }

    private var baseBackground: NSColor {
        if !isEnabled { return isCheckedForAppearance ? theme.accentFillDisabled : theme.controlFillDisabled }
        if isWholeControlPressed {
            return isCheckedForAppearance ? theme.accentFillTertiary : theme.controlFillTertiary
        }
        return isCheckedForAppearance ? theme.accentFillDefault : theme.controlFill
    }

    private func regionBackground(_ region: HitRegion) -> NSColor {
        guard isEnabled else { return .clear }
        if isWholeControlPressed {
            return isCheckedForAppearance ? theme.accentFillTertiary : theme.controlFillTertiary
        }
        if activePressedRegion == region {
            return isCheckedForAppearance ? theme.accentFillTertiary : theme.controlFillTertiary
        }
        if lastPointerDevice != .touch, hoveredRegion == region {
            return isCheckedForAppearance ? theme.accentFillSecondary : theme.controlFillSecondary
        }
        return baseBackground
    }

    private var primaryForeground: NSColor {
        if !isEnabled { return theme.textDisabled }
        if isCheckedForAppearance {
            return activePressedRegion == .primary || isWholeControlPressed
                ? theme.textOnAccentSecondary
                : theme.textOnAccent
        }
        return activePressedRegion == .primary || isWholeControlPressed
            ? theme.textSecondary
            : theme.textPrimary
    }

    private var secondaryForeground: NSColor {
        if !isEnabled { return theme.textDisabled }
        if isCheckedForAppearance {
            return activePressedRegion == .secondary || isWholeControlPressed
                ? theme.textOnAccentSecondary
                : theme.textOnAccent
        }
        if lastPointerDevice != .touch, hoveredRegion == .secondary, activePressedRegion != .secondary, !isWholeControlPressed {
            return theme.textPrimary
        }
        return activePressedRegion == .secondary || isWholeControlPressed
            ? theme.textTertiary
            : theme.textSecondary
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        animationCoordinator.reduceMotion = reduceMotion
        for child in [primaryLayer, secondaryLayer, dividerLayer, primaryBorderClip, secondaryBorderClip, chevronLayer, focusOuterLayer, focusInnerLayer] {
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
        primaryBorderClip.masksToBounds = true
        secondaryBorderClip.masksToBounds = true
        primaryBorderClip.addSublayer(elevationBorderLayer)
        secondaryBorderClip.addSublayer(secondaryBorderLayer)
        configureFluentElevationBorderLayer(secondaryBorderLayer, mask: secondaryBorderMask)
        secondaryBorderLayer.name = "FluentKit.SplitButton.SecondaryElevationBorder"
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        elevationBorderLayer.name = "FluentKit.SplitButton.ElevationBorder"
        chevronLayer.name = "FluentKit.SplitButton.Chevron"
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
        // WinUI's primary background spans the separator column; avoid an unpainted 1pt seam.
        let primaryBackground = userInterfaceLayoutDirection == .rightToLeft
            ? CGRect(x: secondaryFrame.maxX, y: 0, width: max(0, bounds.width - secondaryFrame.width), height: bounds.height)
            : CGRect(x: 0, y: 0, width: max(0, bounds.width - secondaryFrame.width), height: bounds.height)
        primaryLayer.frame = primaryBackground
        secondaryLayer.frame = secondaryFrame
        primaryBorderClip.frame = primaryBackground
        secondaryBorderClip.frame = secondaryFrame
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
        CATransaction.commit()
        titleLabel.stringValue = title
        titleLabel.textColor = primaryForeground
        updateElevationBorder(animated: false)
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
        updateChevron(animated: animated)
        needsDisplay = true
    }

    private var chevronControlState: FluentControlState {
        guard isEnabled else { return .disabled }
        // AnimatedIcon is driven by the secondary child Button's pointer state. The parent
        // FlyoutOpen/TouchPressed states change faceplate colors without holding that glyph down.
        if isTrackingPress, pressedRegion == .secondary, hoveredRegion == .secondary { return .pressed }
        return lastPointerDevice != .touch && hoveredRegion == .secondary ? .pointerOver : .normal
    }

    private func updateChevron(animated: Bool) {
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelGeometry = FluentPixelGeometry(backingScale: backingScale)
        let size: CGFloat = 12 * fluentControlSize.metricScale
        let frame = CGRect(x: pixelGeometry.align(secondaryFrame.midX - size / 2),
                           y: pixelGeometry.align(secondaryFrame.midY - size / 2), width: size, height: size)
        let isActive = window != nil && !isHiddenOrHasHiddenAncestor && isEnabled && !reduceMotion
        chevronLayer.update(
            frame: frame,
            color: secondaryForeground,
            state: chevronControlState,
            visual: .downSmall,
            inverted: true,
            backingScale: backingScale,
            preservingUnchangedAnimations: isActive,
            reduceMotion: reduceMotion,
            animated: animated && isActive
        )
    }

    private func resolvedElevationColors(for region: HitRegion) -> [NSColor] {
        if !isEnabled {
            return [theme.controlStrokeDefault, theme.controlStrokeDefault]
        }
        if isCheckedForAppearance {
            if activePressedRegion == region || isWholeControlPressed {
                return [.clear, .clear]
            }
            return theme.accentElevationBorderColors
        }
        if activePressedRegion == region || isWholeControlPressed {
            return [theme.controlStrokeDefault, theme.controlStrokeDefault]
        }
        return theme.controlElevationBorderColors
    }

    private func updateElevationBorder(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        for (border, mask, clip, region) in [
            (elevationBorderLayer, elevationBorderMask, primaryBorderClip, HitRegion.primary),
            (secondaryBorderLayer, secondaryBorderMask, secondaryBorderClip, HitRegion.secondary)
        ] {
            let colors = resolvedElevationColors(for: region)
            let appearance = FluentButtonAppearance(
                backgroundColor: .clear, foregroundColor: primaryForeground,
                borderColor: colors.last ?? theme.controlStrokeDefault, borderGradientColors: colors,
                borderWidth: theme.controlStrokeWidth,
                cornerRadius: theme.designTokens.controlCornerRadius * fluentControlSize.metricScale,
                contentInsets: NSEdgeInsetsZero
            )
            updateFluentElevationBorderLayer(border, mask: mask, bounds: bounds, appearance: appearance,
                visualYAxis: .resolved(for: layer, fallbackView: self),
                backingScale: max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1))
            // Each half clips the same outer ring, retaining only the outer corners and edges.
            border.frame.origin.x = -clip.frame.minX
        }
        CATransaction.commit()
    }

    private func presentFlyout() {
        guard isEnabled, !items.isEmpty else { return }
        guard !isFlyoutPresented, window?.isVisible == true, !isHiddenOrHasHiddenAncestor else { return }
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

    private func updatePresentedFlyout() {
        menuFlyout?.update(items: items, theme: theme, reduceMotion: reduceMotion)
    }

    private func dismissFlyout(animated: Bool) {
        let previous = menuFlyout
        menuFlyout = nil
        isFlyoutPresented = false
        previous?.dismiss(animated: animated)
        updateAccessibilityValue()
        updateAppearance(animated: animated)
    }

    private func updateAccessibilityValue() {
        setAccessibilityExpanded(isFlyoutPresented)
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
        guard isEnabled else { return }
        isChecked.toggle()
        // WinUI raises Click after CheckedChanged even if that callback disables the control.
        performAcceptedPrimaryAction()
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
        button.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
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
        button.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
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
    private var observationGeneration: UInt64 = 0
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
        button = FluentToggleSplitButton(title, isChecked: FluentDependencyTracking.withoutTracking { binding.get() }, items: items, action: action)
        super.init(frame: .zero)
        button.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
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
            self.synchronizeFromBinding()
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
        let reusesObservation = self.binding.observationIdentity != nil
            && self.binding.observationIdentity == binding.observationIdentity
        if !reusesObservation { removeObserver() }
        self.binding = binding
        button.title = title
        button.items = items
        button.onPrimaryAction = action
        button.flyoutPlacement = placement
        button.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        synchronizeFromBinding()
        if !reusesObservation { installObserver() }
        invalidateIntrinsicContentSize()
    }

    private func synchronizeFromBinding() {
        isApplyingBinding = true
        button.setCheckedFromBinding(FluentDependencyTracking.withoutTracking { binding.get() })
        isApplyingBinding = false
    }

    private func installObserver() {
        observationGeneration &+= 1
        let generation = observationGeneration
        observerID = binding.observe { [weak self] value in
            let deliver = { [weak self] in
                guard let self, self.observationGeneration == generation,
                      FluentDependencyTracking.withoutTracking({ self.binding.get() }) == value else { return }
                self.synchronizeFromBinding()
            }
            if Thread.isMainThread { deliver() }
            else { DispatchQueue.main.async(execute: deliver) }
        }
    }

    private func removeObserver() {
        observationGeneration &+= 1
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
