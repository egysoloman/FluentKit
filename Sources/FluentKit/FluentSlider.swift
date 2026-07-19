import AppKit

/// A Fluent-style continuous slider with native keyboard and pointer interaction.
public final class FluentSlider: NSControl {
    public var theme: FluentTheme = .current { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    public var fluentStyle: (any FluentSliderStyle)? { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    public var minimumValue: Double {
        didSet { normalizeRange() }
    }
    public var maximumValue: Double {
        didSet { normalizeRange() }
    }
    public var value: Double = 0 {
        didSet { valueChanged(from: oldValue) }
    }
    public var onValueChanged: ((Double) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private var isPointerOver = false
    private var isDragging = false

    public init(value: Double = 0, range: ClosedRange<Double> = 0...1) {
        minimumValue = range.lowerBound
        maximumValue = range.upperBound
        self.value = min(max(value, minimumValue), maximumValue)
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
        setAccessibilityRole(.slider)
        setAccessibilityMinValue(minimumValue)
        setAccessibilityMaxValue(maximumValue)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        minimumValue = 0
        maximumValue = 1
        value = 0
        super.init(coder: coder)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(
            width: 220 * fluentControlSize.metricScale * theme.density.metricScale,
            height: theme.controlHeight(for: fluentControlSize)
        )
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let knobCenterX = knobCenterX(for: appearance)
        let knobRadius = appearance.knobDiameter / 2
        let track = NSRect(
            x: knobRadius,
            y: bounds.midY - appearance.trackHeight / 2,
            width: max(bounds.width - appearance.knobDiameter, 0),
            height: appearance.trackHeight
        )
        let progress = NSRect(x: track.minX, y: track.minY, width: max(knobCenterX - track.minX, 0), height: track.height)
        let knob = NSRect(
            x: knobCenterX - knobRadius,
            y: bounds.midY - knobRadius,
            width: appearance.knobDiameter,
            height: appearance.knobDiameter
        )

        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill(using: appearance.trackColor)
        NSBezierPath(roundedRect: progress, xRadius: track.height / 2, yRadius: track.height / 2).fill(using: appearance.fillColor)
        if isPointerOver || isDragging {
            let halo = NSRect(
                x: knobCenterX - appearance.haloDiameter / 2,
                y: bounds.midY - appearance.haloDiameter / 2,
                width: appearance.haloDiameter,
                height: appearance.haloDiameter
            )
            appearance.haloColor.setFill()
            NSBezierPath(ovalIn: halo).fill()
        }
        let knobPath = NSBezierPath(ovalIn: knob)
        appearance.knobColor.setFill()
        knobPath.fill()
    }

    public override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isDragging = true
        updateValue(for: convert(event.locationInWindow, from: nil).x)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(for: convert(event.locationInWindow, from: nil).x)
    }

    public override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        let step = (maximumValue - minimumValue) / 20
        switch event.keyCode {
        case 123: value -= step
        case 124: value += step
        case 115: value = minimumValue
        case 119: value = maximumValue
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }

    public override func accessibilityValue() -> Any? { value }

    public override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    func applyDeclarativeConfiguration(from source: FluentSlider) {
        minimumValue = source.minimumValue
        maximumValue = source.maximumValue
        fluentStyle = source.fluentStyle
        fluentControlSize = source.fluentControlSize
        if value != source.value {
            let callback = onValueChanged
            onValueChanged = nil
            value = source.value
            onValueChanged = callback
        }
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    private func knobCenterX(for appearance: FluentSliderAppearance) -> CGFloat {
        let radius = appearance.knobDiameter / 2
        guard maximumValue > minimumValue else { return radius }
        let fraction = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        return radius + fraction * max(bounds.width - appearance.knobDiameter, 0)
    }

    private func updateValue(for x: CGFloat) {
        let appearance = resolvedAppearance()
        let radius = appearance.knobDiameter / 2
        let fraction = min(max((x - radius) / max(bounds.width - appearance.knobDiameter, 1), 0), 1)
        value = minimumValue + Double(fraction) * (maximumValue - minimumValue)
        needsDisplay = true
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

    private func normalizeValue() {
        let clamped = min(max(value, minimumValue), maximumValue)
        if value != clamped { value = clamped }
        setAccessibilityMinValue(minimumValue)
        setAccessibilityMaxValue(maximumValue)
        needsDisplay = true
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
        needsDisplay = true
    }
}

extension FluentSlider: FluentControlSizeConfigurable {}

private extension NSBezierPath {
    func fill(using color: NSColor) {
        color.setFill()
        fill()
    }
}
