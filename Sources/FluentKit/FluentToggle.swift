import AppKit

/// A compact Fluent-style switch drawn with Core Animation rather than the system switch chrome.
public final class FluentToggle: NSControl {
    public var theme: FluentTheme = .current { didSet { refreshAppearance(animated: false); invalidateIntrinsicContentSize() } }
    public var fluentStyle: (any FluentToggleStyle)? { didSet { refreshAppearance(animated: false); invalidateIntrinsicContentSize() } }
    public var isOn: Bool {
        didSet {
            guard oldValue != isOn else { return }
            refreshAppearance(animated: true)
            onValueChanged?(isOn)
        }
    }
    public var onValueChanged: ((Bool) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet { invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true }
    }

    private var titleText: String
    public var title: String {
        get { titleText }
        set { titleText = newValue; setAccessibilityTitle(newValue); invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    private var titleFont: NSFont {
        let bodyFont = theme.typography.font(for: .body)
        return bodyFont.withSize(bodyFont.pointSize * fluentControlSize.metricScale)
    }
    private let trackLayer = CALayer()
    private let knobLayer = CALayer()
    private var isPointerOver = false
    private var isPressed = false

    public init(title: String = "Toggle", isOn: Bool = false) {
        self.titleText = title
        self.isOn = isOn
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(knobLayer)
        focusRingType = .none
        setAccessibilityRole(.checkBox)
        setAccessibilityTitle(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        refreshAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        titleText = "Toggle"
        isOn = false
        super.init(coder: coder)
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let textSize = (titleText as NSString).size(withAttributes: [.font: titleFont])
        return NSSize(
            width: ceil(textSize.width + appearance.labelSpacing + appearance.trackSize.width),
            height: ceil(max(theme.controlHeight(for: fluentControlSize), appearance.trackSize.height))
        )
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
        }
    }

    public override func layout() {
        super.layout()
        let appearance = resolvedAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGeometry(appearance)
        CATransaction.commit()
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let textRect = NSRect(
            x: 0,
            y: bounds.midY - titleFont.capHeight / 2,
            width: max(bounds.width - appearance.trackSize.width - appearance.labelSpacing, 0),
            height: titleFont.pointSize + 6
        )
        (titleText as NSString).draw(in: textRect, withAttributes: [.font: titleFont, .foregroundColor: appearance.labelColor])
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
        isPressed = true
        refreshAppearance(animated: true)
        isOn.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + FluentMotion.controlFaster.duration) { [weak self] in
            guard let self, self.isPressed else { return }
            self.isPressed = false
            self.refreshAppearance(animated: true)
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 36 || event.keyCode == 49 {
            isOn.toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    public override func accessibilityValue() -> Any? { isOn ? "On" : "Off" }

    public override var isEnabled: Bool {
        didSet { refreshAppearance(animated: false) }
    }

    func applyDeclarativeConfiguration(from source: FluentToggle) {
        titleText = source.titleText
        fluentStyle = source.fluentStyle
        fluentControlSize = source.fluentControlSize
        if isOn != source.isOn { setStateFromDeclarative(source.isOn) }
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    private func refreshAppearance(animated: Bool) {
        let motion = FluentMotion.controlFaster
        let appearance = resolvedAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? motion.duration : 0)
        CATransaction.setAnimationTimingFunction(motion.curve.timingFunction)
        trackLayer.backgroundColor = appearance.trackColor.cgColor
        trackLayer.borderColor = appearance.trackBorderColor.cgColor
        trackLayer.borderWidth = appearance.trackBorderWidth
        knobLayer.backgroundColor = appearance.knobColor.cgColor
        knobLayer.shadowColor = appearance.knobShadowColor.cgColor
        knobLayer.shadowOpacity = appearance.knobShadowColor.alphaComponent > 0 ? 1 : 0
        knobLayer.shadowRadius = 2
        knobLayer.shadowOffset = CGSize(width: 0, height: -1)
        applyGeometry(appearance)
        CATransaction.commit()
        needsDisplay = true
        needsLayout = true
    }

    private func resolvedAppearance() -> FluentToggleAppearance {
        let configuration = FluentToggleStyleConfiguration(
            isOn: isOn,
            isEnabled: isEnabled,
            isPointerOver: isPointerOver,
            isPressed: isPressed,
            controlSize: fluentControlSize,
            theme: theme
        )
        return fluentStyle?.appearance(for: configuration)
            ?? FluentAutomaticToggleStyle().appearance(for: configuration)
    }

    private func trackRect(for appearance: FluentToggleAppearance) -> NSRect {
        NSRect(
            x: bounds.maxX - appearance.trackSize.width,
            y: (bounds.height - appearance.trackSize.height) / 2,
            width: appearance.trackSize.width,
            height: appearance.trackSize.height
        )
    }

    private func applyGeometry(_ appearance: FluentToggleAppearance) {
        let trackRect = trackRect(for: appearance)
        trackLayer.frame = trackRect
        trackLayer.cornerRadius = trackRect.height / 2
        let knobWidth = min(appearance.knobSize.width, max(trackRect.width - 4, 1))
        let knobHeight = min(appearance.knobSize.height, max(trackRect.height - 4, 1))
        let knobX = isOn ? trackRect.maxX - knobWidth - 2 : trackRect.minX + 2
        knobLayer.frame = NSRect(
            x: knobX,
            y: trackRect.midY - knobHeight / 2,
            width: knobWidth,
            height: knobHeight
        )
        knobLayer.cornerRadius = min(knobWidth, knobHeight) / 2
    }

    private func setStateFromDeclarative(_ value: Bool) {
        let callback = onValueChanged
        onValueChanged = nil
        isOn = value
        onValueChanged = callback
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance(animated: false)
    }
}

extension FluentToggle: FluentControlSizeConfigurable {}
