import AppKit

/// A Fluent-style continuous slider with native keyboard and pointer interaction.
public final class FluentSlider: NSControl {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: (any FluentSliderStyle)? {
        didSet {
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion { animationCoordinator.cancelAll(on: [innerThumbLayer]) }
            refreshAppearance(animated: false)
        }
    }
    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            refreshAppearance(animated: false)
        }
    }
    public var minimumValue: Double {
        didSet {
            guard oldValue != minimumValue else { return }
            normalizeRange()
        }
    }
    public var maximumValue: Double {
        didSet {
            guard oldValue != maximumValue else { return }
            normalizeRange()
        }
    }
    public var value: Double = 0 {
        didSet { valueChanged(from: oldValue) }
    }
    public var onValueChanged: ((Double) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }

    private var isPointerOver = false
    private var isDragging = false
    private var interactionStartValue: Double?
    private let focusLayer = CALayer()
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let outerThumbLayer = CALayer()
    private let innerThumbLayer = CALayer()
    private let animationCoordinator = FluentAnimationCoordinator()
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?
    private var declarativeStyleSignature: String?

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public init(value: Double = 0, range: ClosedRange<Double> = 0...1) {
        minimumValue = range.lowerBound
        maximumValue = range.upperBound
        self.value = min(max(value, minimumValue), maximumValue)
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        minimumValue = 0
        maximumValue = 1
        value = 0
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(
            width: 220 * fluentControlSize.metricScale * theme.density.metricScale,
            height: max(
                theme.controlHeight(for: fluentControlSize),
                resolvedAppearance().outerThumbDiameter + 6
            )
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
        interactionStartValue = value
        isDragging = true
        let point = convert(event.locationInWindow, from: nil)
        isPointerOver = bounds.contains(point)
        updateValue(for: point.x)
        refreshAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        isPointerOver = bounds.contains(point)
        updateValue(for: point.x)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        interactionStartValue = nil
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        refreshAppearance(animated: true)
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        updateFocusRing()
        let step = (maximumValue - minimumValue) / 20
        switch event.keyCode {
        case 123: value += isRTL ? step : -step
        case 124: value += isRTL ? -step : step
        case 125: value -= step
        case 126: value += step
        case 115: value = minimumValue
        case 119: value = maximumValue
        case 53: cancelInteraction(restoreValue: true)
        default: super.keyDown(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        cancelInteraction(restoreValue: true)
    }

    public override func accessibilityValue() -> Any? { value }

    public override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        value += (maximumValue - minimumValue) / 20
        return true
    }

    public override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        value -= (maximumValue - minimumValue) / 20
        return true
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { cancelInteraction(restoreValue: true, refresh: false) }
            setAccessibilityEnabled(isEnabled)
            refreshAppearance(animated: true)
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

    func applyDeclarativeConfiguration(from source: FluentSlider) {
        if minimumValue != source.minimumValue { minimumValue = source.minimumValue }
        if maximumValue != source.maximumValue { maximumValue = source.maximumValue }
        applyDeclarativeStyle(source.fluentStyle)
        if fluentControlSize != source.fluentControlSize { fluentControlSize = source.fluentControlSize }
        if value != source.value {
            setValueFromBinding(source.value)
        }
    }

    func setValueFromBinding(_ newValue: Double, cancelInteraction: Bool = true) {
        let wasDragging = isDragging
        if cancelInteraction { self.cancelInteraction(restoreValue: false, refresh: false) }
        let callback = onValueChanged
        onValueChanged = nil
        let clamped = min(max(newValue, minimumValue), maximumValue)
        if value != clamped { value = clamped }
        onValueChanged = callback
        if wasDragging && cancelInteraction { refreshAppearance(animated: false) }
    }

    func applyDeclarativeStyle(_ style: (any FluentSliderStyle)?) {
        let signature = style.map { String(reflecting: $0) }
        guard signature != declarativeStyleSignature else { return }
        fluentStyle = style
        declarativeStyleSignature = signature
    }

    private func updateValue(for x: CGFloat) {
        let appearance = resolvedAppearance()
        let radius = appearance.outerThumbDiameter / 2
        let physicalFraction = min(max((x - radius) / max(bounds.width - appearance.outerThumbDiameter, 1), 0), 1)
        let logicalFraction = isRTL ? 1 - physicalFraction : physicalFraction
        value = minimumValue + Double(logicalFraction) * (maximumValue - minimumValue)
    }

    private func resolvedAppearance() -> FluentSliderAppearance {
        let fraction: CGFloat
        if maximumValue > minimumValue {
            fraction = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        } else {
            fraction = 0
        }
        let configuration = FluentSliderStyleConfiguration(
            valueFraction: fraction,
            isEnabled: isEnabled,
            isPointerOver: isPointerOver,
            isDragging: isDragging,
            controlSize: fluentControlSize,
            theme: theme
        )
        return fluentStyle?.appearance(for: configuration)
            ?? FluentAutomaticSliderStyle().appearance(for: configuration)
    }

    private func configureView() {
        wantsLayer = true
        focusRingType = .none
        userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
        setAccessibilityRole(.slider)
        setAccessibilityMinValue(minimumValue)
        setAccessibilityMaxValue(maximumValue)
        setAccessibilityValue(value)
        setAccessibilityEnabled(isEnabled)

        focusLayer.name = "FluentKit.Slider.FocusRing"
        trackLayer.name = "FluentKit.Slider.Track"
        fillLayer.name = "FluentKit.Slider.Fill"
        outerThumbLayer.name = "FluentKit.Slider.OuterThumb"
        innerThumbLayer.name = "FluentKit.Slider.InnerThumb"
        focusLayer.opacity = 0
        animationCoordinator.reduceMotion = reduceMotion
        layer?.addSublayer(focusLayer)
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(outerThumbLayer)
        outerThumbLayer.addSublayer(innerThumbLayer)
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

    private func refreshAppearance(animated: Bool) {
        let appearance = resolvedAppearance()
        applyModelAppearance(appearance, updateInnerGeometry: false)

        let innerDiameter = min(appearance.knobDiameter, appearance.outerThumbDiameter)
        let targetBounds = CGRect(x: 0, y: 0, width: innerDiameter, height: innerDiameter)
        let targetCornerRadius = innerDiameter / 2

        let motion = isPointerOver && isEnabled || isDragging
            ? FluentMotion.controlNormal
            : FluentMotion.controlFast
        animationCoordinator.reduceMotion = reduceMotion
        animationCoordinator.animateState(
            [
                FluentLayerAnimationChange(
                    layer: innerThumbLayer,
                    key: "fluent.slider.inner.bounds",
                    keyPath: "bounds",
                    toValue: NSValue(rect: targetBounds),
                    applyModelValue: { [innerThumbLayer] in innerThumbLayer.bounds = targetBounds }
                ),
                FluentLayerAnimationChange(
                    layer: innerThumbLayer,
                    key: "fluent.slider.inner.cornerRadius",
                    keyPath: "cornerRadius",
                    toValue: targetCornerRadius,
                    applyModelValue: { [innerThumbLayer] in innerThumbLayer.cornerRadius = targetCornerRadius }
                )
            ],
            motion: motion,
            animated: animated
        )
        updateFocusRing()
    }

    private func refreshPositionAndBrushes() {
        applyModelAppearance(resolvedAppearance(), updateInnerGeometry: false)
        updateFocusRing()
    }

    private func applyModelAppearance(
        _ appearance: FluentSliderAppearance,
        updateInnerGeometry: Bool
    ) {
        let outerDiameter = appearance.outerThumbDiameter
        let radius = outerDiameter / 2
        let trackRect = NSRect(
            x: radius,
            y: bounds.midY - appearance.trackHeight / 2,
            width: max(bounds.width - outerDiameter, 0),
            height: appearance.trackHeight
        )
        let fraction = valueFraction
        let thumbCenterX = radius + (isRTL ? 1 - fraction : fraction) * trackRect.width
        let fillWidth = fraction * trackRect.width
        let fillRect = NSRect(
            x: isRTL ? trackRect.maxX - fillWidth : trackRect.minX,
            y: trackRect.minY,
            width: fillWidth,
            height: trackRect.height
        )
        let outerRect = NSRect(
            x: thumbCenterX - radius,
            y: bounds.midY - radius,
            width: outerDiameter,
            height: outerDiameter
        )
        let focusRect = outerRect.insetBy(dx: -3, dy: -3)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = trackRect
        trackLayer.cornerRadius = trackRect.height / 2
        trackLayer.backgroundColor = appearance.trackColor.cgColor
        fillLayer.frame = fillRect
        fillLayer.cornerRadius = fillRect.height / 2
        fillLayer.backgroundColor = appearance.fillColor.cgColor
        fillLayer.isHidden = fillRect.width <= 0
        outerThumbLayer.frame = outerRect
        outerThumbLayer.cornerRadius = radius
        outerThumbLayer.backgroundColor = appearance.outerThumbColor.cgColor
        outerThumbLayer.borderColor = appearance.outerThumbBorderColor.cgColor
        outerThumbLayer.borderWidth = appearance.outerThumbBorderWidth
        innerThumbLayer.position = CGPoint(x: radius, y: radius)
        innerThumbLayer.backgroundColor = appearance.knobColor.cgColor
        if updateInnerGeometry {
            let innerDiameter = min(appearance.knobDiameter, outerDiameter)
            innerThumbLayer.bounds = CGRect(x: 0, y: 0, width: innerDiameter, height: innerDiameter)
            innerThumbLayer.cornerRadius = innerDiameter / 2
        }
        focusLayer.frame = focusRect
        focusLayer.cornerRadius = focusRect.height / 2
        focusLayer.borderColor = theme.accent.cgColor
        focusLayer.borderWidth = theme.focusStrokeWidth
        CATransaction.commit()
    }

    private var valueFraction: CGFloat {
        guard maximumValue > minimumValue else { return 0 }
        return min(max(CGFloat((value - minimumValue) / (maximumValue - minimumValue)), 0), 1)
    }

    private func cancelInteraction(restoreValue: Bool, refresh: Bool = true) {
        guard isDragging else { return }
        let original = interactionStartValue
        isDragging = false
        interactionStartValue = nil
        if restoreValue, let original, value != original {
            value = original
        }
        if refresh { refreshAppearance(animated: true) }
    }

    private func updateFocusRing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
        CATransaction.commit()
    }

    private func normalizeValue() {
        let clamped = min(max(value, minimumValue), maximumValue)
        if value != clamped { value = clamped }
        setAccessibilityMinValue(minimumValue)
        setAccessibilityMaxValue(maximumValue)
        refreshAppearance(animated: false)
    }

    private func normalizeRange() {
        if maximumValue < minimumValue { maximumValue = minimumValue }
        normalizeValue()
    }

    private func valueChanged(from oldValue: Double) {
        let clamped = min(max(value, minimumValue), maximumValue)
        if value != clamped {
            value = clamped
            return
        }
        guard oldValue != value else { return }
        sendAction(action, to: target)
        onValueChanged?(value)
        setAccessibilityValue(value)
        refreshPositionAndBrushes()
    }
}

extension FluentSlider: FluentControlSizeConfigurable {}
