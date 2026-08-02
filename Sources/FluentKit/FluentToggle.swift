import AppKit

/// A compact Fluent-style switch with a native AppKit interaction surface and custom visual states.
public final class FluentToggle: NSControl {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: (any FluentToggleStyle)? {
        didSet {
            guard !appearancesMatch(oldValue, fluentStyle) else { return }
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion { removeVisualAnimations() }
            refreshAppearance(animated: false)
        }
    }
    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            refreshAppearance(animated: false)
            needsDisplay = true
        }
    }
    public var isOn: Bool {
        didSet {
            guard oldValue != isOn else { return }
            refreshAppearance(
                animated: true,
                motion: FluentMotion.controlFaster,
                repositionMotion: FluentMotion.controlFast
            )
            onValueChanged?(isOn)
        }
    }
    public var onValueChanged: ((Bool) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private var titleText: String
    public var title: String {
        get { titleText }
        set {
            guard titleText != newValue else { return }
            titleText = newValue
            setAccessibilityTitle(newValue)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private enum PointerState {
        case idle
        case pressed(origin: NSPoint, initialFraction: CGFloat)
        case dragging(origin: NSPoint, initialFraction: CGFloat, fraction: CGFloat)
    }

    private let focusLayer = CALayer()
    private let trackLayer = CALayer()
    private let knobLayer = CALayer()
    private lazy var animationCoordinator = FluentAnimationCoordinator(reduceMotion: reduceMotion)
    private var pointerState: PointerState = .idle
    private var isPointerOver = false
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?

    private var titleFont: NSFont {
        let bodyFont = theme.typography.font(for: .body)
        return bodyFont.withSize(bodyFont.pointSize * fluentControlSize.metricScale)
    }
    private var isPressed: Bool {
        if case .idle = pointerState { return false }
        return true
    }
    private var isDragging: Bool {
        if case .dragging = pointerState { return true }
        return false
    }
    private var dragFraction: CGFloat? {
        if case let .dragging(_, _, fraction) = pointerState { return fraction }
        return nil
    }
    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public init(title: String = "Toggle", isOn: Bool = false) {
        titleText = title
        self.isOn = isOn
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        titleText = "Toggle"
        isOn = false
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let textSize = (titleText as NSString).size(withAttributes: [.font: titleFont])
        return NSSize(
            width: ceil(textSize.width + appearance.labelSpacing + appearance.trackSize.width),
            height: ceil(max(theme.controlHeight(for: fluentControlSize), appearance.trackSize.height + 6))
        )
    }

    public override func layout() {
        super.layout()
        let direction = userInterfaceLayoutDirection
        guard bounds.size != lastLayoutSize || direction != lastLayoutDirection else { return }
        lastLayoutSize = bounds.size
        lastLayoutDirection = direction
        refreshAppearance(animated: false)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let track = trackRect(for: appearance)
        let textWidth = max(bounds.width - track.width - appearance.labelSpacing, 0)
        let textSize = (titleText as NSString).size(withAttributes: [.font: titleFont])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = isRTL ? .right : .left
        let textRect = NSRect(
            x: isRTL ? track.maxX + appearance.labelSpacing : 0,
            y: bounds.midY - textSize.height / 2,
            width: textWidth,
            height: textSize.height
        )
        (titleText as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: titleFont,
                .foregroundColor: appearance.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    public override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        refreshAppearance(animated: true)
    }

    public override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        refreshAppearance(animated: true)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        isPointerOver = bounds.contains(point)
        pointerState = .pressed(origin: point, initialFraction: isOn ? 1 : 0)
        refreshAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        isPointerOver = bounds.contains(point)

        let origin: NSPoint
        let initialFraction: CGFloat
        switch pointerState {
        case .idle:
            return
        case let .pressed(pressedOrigin, fraction):
            let delta = logicalHorizontalDelta(from: pressedOrigin, to: point)
            guard abs(delta) >= 3 else { return }
            origin = pressedOrigin
            initialFraction = fraction
        case let .dragging(dragOrigin, fraction, _):
            origin = dragOrigin
            initialFraction = fraction
        }

        let travel = max(resolvedAppearance().trackSize.width / 2, 1)
        let fraction = min(max(initialFraction + logicalHorizontalDelta(from: origin, to: point) / travel, 0), 1)
        pointerState = .dragging(origin: origin, initialFraction: initialFraction, fraction: fraction)
        refreshAppearance(animated: false)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)
        let targetValue: Bool

        switch pointerState {
        case .idle:
            return
        case .pressed:
            targetValue = inside ? !isOn : isOn
        case let .dragging(origin, initialFraction, fraction):
            let appearance = resolvedAppearance()
            let travel = max(appearance.trackSize.width / 2, 1)
            let delta = logicalHorizontalDelta(from: origin, to: point)
            if abs(delta) >= travel * 0.25 {
                targetValue = delta > 0
            } else if fraction == 0.5 {
                targetValue = initialFraction >= 0.5
            } else {
                targetValue = fraction > 0.5
            }
        }

        pointerState = .idle
        isPointerOver = inside
        if targetValue != isOn {
            isOn = targetValue
        } else {
            refreshAppearance(animated: true)
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        updateFocusRing()
        switch event.keyCode {
        case 36, 49:
            guard !event.isARepeat else { return }
            commitKeyboardToggle()
        case 53:
            cancelInteraction(animated: true)
        default:
            super.keyDown(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        cancelInteraction(animated: true)
    }

    public override func accessibilityValue() -> Any? { isOn ? "On" : "Off" }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        commitKeyboardToggle()
        return true
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { cancelInteraction(animated: false, refresh: false) }
            setAccessibilityEnabled(isEnabled)
            refreshAppearance(
                animated: true,
                motion: isEnabled ? FluentMotion.controlFaster : FluentMotion.controlNormal
            )
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { updateFocusRing() }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { updateFocusRing() }
        return result
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFocusRing()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    func applyDeclarativeConfiguration(from source: FluentToggle) {
        if titleText != source.titleText { title = source.titleText }
        if fluentStyle != nil || source.fluentStyle != nil { fluentStyle = source.fluentStyle }
        if fluentControlSize != source.fluentControlSize { fluentControlSize = source.fluentControlSize }
        if isOn != source.isOn { setStateFromBinding(source.isOn) }
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    func setStateFromBinding(_ value: Bool) {
        cancelInteraction(animated: false, refresh: false)
        let callback = onValueChanged
        onValueChanged = nil
        isOn = value
        onValueChanged = callback
    }

    private func configureView() {
        wantsLayer = true
        focusRingType = .none
        userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
        setAccessibilityRole(.checkBox)
        setAccessibilityTitle(titleText)
        setAccessibilityEnabled(isEnabled)

        focusLayer.name = "FluentKit.Toggle.FocusRing"
        trackLayer.name = "FluentKit.Toggle.Track"
        knobLayer.name = "FluentKit.Toggle.Knob"
        focusLayer.opacity = 0
        layer?.addSublayer(focusLayer)
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(knobLayer)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        refreshAppearance(animated: false)
    }

    private func commitKeyboardToggle() {
        cancelInteraction(animated: false, refresh: false)
        isOn.toggle()
    }

    private func cancelInteraction(animated: Bool, refresh: Bool = true) {
        guard isPressed else { return }
        pointerState = .idle
        if refresh { refreshAppearance(animated: animated) }
    }

    private func refreshAppearance(
        animated: Bool,
        motion: FluentMotionToken = FluentMotion.controlFaster,
        repositionMotion: FluentMotionToken? = nil
    ) {
        let appearance = resolvedAppearance()
        animationCoordinator.reduceMotion = reduceMotion
        animationCoordinator.transitionState(
            to: resolvedVisualState,
            animated: animated,
            motion: motion
        ) { [weak self] transition in
            self?.applyVisualState(
                appearance,
                animated: transition.isAnimated,
                motion: motion,
                repositionMotion: repositionMotion ?? motion
            )
        }
        needsDisplay = true
    }

    private var resolvedVisualState: FluentVisualState {
        var state: FluentVisualState = .normal
        if isOn { state.insert(.selected) }
        if !isEnabled {
            state.insert(.disabled)
        } else if isPressed || isDragging {
            state.insert(.pressed)
        } else if isPointerOver {
            state.insert(.pointerOver)
        }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) { state.insert(.focused) }
        return state
    }

    private func resolvedAppearance() -> FluentToggleAppearance {
        let configuration = FluentToggleStyleConfiguration(
            isOn: isOn,
            isEnabled: isEnabled,
            isPointerOver: isPointerOver,
            isPressed: isPressed,
            isDragging: isDragging,
            controlSize: fluentControlSize,
            theme: theme
        )
        return fluentStyle?.appearance(for: configuration)
            ?? FluentAutomaticToggleStyle().appearance(for: configuration)
    }

    private func appearancesMatch(
        _ lhs: (any FluentToggleStyle)?,
        _ rhs: (any FluentToggleStyle)?
    ) -> Bool {
        let configuration = FluentToggleStyleConfiguration(
            isOn: isOn,
            isEnabled: isEnabled,
            isPointerOver: isPointerOver,
            isPressed: isPressed,
            isDragging: isDragging,
            controlSize: fluentControlSize,
            theme: theme
        )
        let automatic = FluentAutomaticToggleStyle()
        let left = lhs?.appearance(for: configuration) ?? automatic.appearance(for: configuration)
        let right = rhs?.appearance(for: configuration) ?? automatic.appearance(for: configuration)
        return left.trackColor.isEqual(right.trackColor)
            && left.trackBorderColor.isEqual(right.trackBorderColor)
            && left.trackBorderWidth == right.trackBorderWidth
            && left.knobColor.isEqual(right.knobColor)
            && left.knobBorderColor.isEqual(right.knobBorderColor)
            && left.knobBorderWidth == right.knobBorderWidth
            && left.labelColor.isEqual(right.labelColor)
            && left.knobShadowColor.isEqual(right.knobShadowColor)
            && left.trackSize == right.trackSize
            && left.knobSize == right.knobSize
            && left.labelSpacing == right.labelSpacing
    }

    private func trackRect(for appearance: FluentToggleAppearance) -> NSRect {
        NSRect(
            x: isRTL ? 0 : bounds.maxX - appearance.trackSize.width,
            y: (bounds.height - appearance.trackSize.height) / 2,
            width: appearance.trackSize.width,
            height: appearance.trackSize.height
        )
    }

    private func knobRect(for appearance: FluentToggleAppearance, trackRect: NSRect) -> NSRect {
        let knobWidth = min(appearance.knobSize.width, max(trackRect.width - 4, 1))
        let knobHeight = min(appearance.knobSize.height, max(trackRect.height - 4, 1))
        let halfTrack = trackRect.width / 2
        let physicalOffX: CGFloat
        let physicalOnX: CGFloat

        if isPressed {
            let visibleScale = trackRect.height / 20
            let inset = min(3 * visibleScale, max((trackRect.width - knobWidth) / 2, 0))
            physicalOffX = trackRect.minX + inset
            physicalOnX = trackRect.maxX - knobWidth - inset
        } else {
            let alignmentNudge = 0.5 * (trackRect.height / 20)
            let centeredInset = max((halfTrack - knobWidth) / 2 - alignmentNudge, 0)
            physicalOffX = trackRect.minX + centeredInset
            physicalOnX = trackRect.minX + halfTrack + centeredInset
        }

        let offX = isRTL ? physicalOnX : physicalOffX
        let onX = isRTL ? physicalOffX : physicalOnX
        let fraction = dragFraction ?? (isOn ? 1 : 0)
        let knobX = offX + (onX - offX) * fraction
        return NSRect(
            x: knobX,
            y: trackRect.midY - knobHeight / 2,
            width: knobWidth,
            height: knobHeight
        )
    }

    private func applyVisualState(
        _ appearance: FluentToggleAppearance,
        animated: Bool,
        motion: FluentMotionToken,
        repositionMotion: FluentMotionToken
    ) {
        let trackRect = trackRect(for: appearance)
        let knobRect = knobRect(for: appearance, trackRect: trackRect)
        let visibleScale = trackRect.height / 20
        let focusRect = trackRect.insetBy(dx: -3 * visibleScale, dy: -3 * visibleScale)
        let knobBounds = NSRect(origin: .zero, size: knobRect.size)
        let knobPosition = NSPoint(x: knobRect.midX, y: knobRect.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = trackRect
        trackLayer.cornerRadius = trackRect.height / 2
        trackLayer.borderWidth = appearance.trackBorderWidth
        knobLayer.borderWidth = appearance.knobBorderWidth
        knobLayer.shadowColor = appearance.knobShadowColor.cgColor
        knobLayer.shadowOpacity = appearance.knobShadowColor.alphaComponent > 0 ? 1 : 0
        knobLayer.shadowRadius = 2 * visibleScale
        knobLayer.shadowOffset = CGSize(width: 0, height: -visibleScale)
        focusLayer.frame = focusRect
        focusLayer.cornerRadius = focusRect.height / 2
        focusLayer.borderColor = theme.accent.cgColor
        focusLayer.borderWidth = theme.focusStrokeWidth
        CATransaction.commit()

        animationCoordinator.animateState(
            [
                FluentLayerAnimationChange(
                    layer: trackLayer,
                    key: "fluent.toggle.track.background",
                    keyPath: "backgroundColor",
                    toValue: appearance.trackColor.cgColor
                ) { [trackLayer] in trackLayer.backgroundColor = appearance.trackColor.cgColor },
                FluentLayerAnimationChange(
                    layer: trackLayer,
                    key: "fluent.toggle.track.border",
                    keyPath: "borderColor",
                    toValue: appearance.trackBorderColor.cgColor
                ) { [trackLayer] in trackLayer.borderColor = appearance.trackBorderColor.cgColor },
                FluentLayerAnimationChange(
                    layer: knobLayer,
                    key: "fluent.toggle.knob.bounds",
                    keyPath: "bounds",
                    toValue: NSValue(rect: knobBounds)
                ) { [knobLayer] in knobLayer.bounds = knobBounds },
                FluentLayerAnimationChange(
                    layer: knobLayer,
                    key: "fluent.toggle.knob.cornerRadius",
                    keyPath: "cornerRadius",
                    toValue: min(knobRect.width, knobRect.height) / 2
                ) { [knobLayer] in
                    knobLayer.cornerRadius = min(knobRect.width, knobRect.height) / 2
                },
                FluentLayerAnimationChange(
                    layer: knobLayer,
                    key: "fluent.toggle.knob.background",
                    keyPath: "backgroundColor",
                    toValue: appearance.knobColor.cgColor
                ) { [knobLayer] in knobLayer.backgroundColor = appearance.knobColor.cgColor },
                FluentLayerAnimationChange(
                    layer: knobLayer,
                    key: "fluent.toggle.knob.border",
                    keyPath: "borderColor",
                    toValue: appearance.knobBorderColor.cgColor
                ) { [knobLayer] in knobLayer.borderColor = appearance.knobBorderColor.cgColor }
            ],
            motion: motion,
            animated: animated
        )
        animationCoordinator.animateState(
            [
                FluentLayerAnimationChange(
                    layer: knobLayer,
                    key: "fluent.toggle.knob.position",
                    keyPath: "position",
                    toValue: NSValue(point: knobPosition)
                ) { [knobLayer] in knobLayer.position = knobPosition }
            ],
            motion: repositionMotion,
            animated: animated
        )
        updateFocusRing()
    }

    private func removeVisualAnimations() {
        animationCoordinator.cancelAll(on: [trackLayer, knobLayer])
    }

    private func updateFocusRing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
        CATransaction.commit()
    }

    private func logicalHorizontalDelta(from origin: NSPoint, to point: NSPoint) -> CGFloat {
        let delta = point.x - origin.x
        return isRTL ? -delta : delta
    }
}

extension FluentToggle: FluentControlSizeConfigurable {}
