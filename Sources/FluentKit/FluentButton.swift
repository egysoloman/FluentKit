import AppKit

public enum FluentButtonRole: Hashable, Sendable {
    case standard
    case primary
    case destructive
}

public final class FluentButton: NSButton {
    public var theme: FluentTheme = .current {
        didSet {
            font = theme.typography.font(for: .body).withSize(theme.typography.font(for: .body).pointSize * fluentControlSize.metricScale)
            invalidateIntrinsicContentSize()
            refreshAppearance(animated: false)
        }
    }
    public var fluentStyle: (any FluentButtonStyle)? { didSet { invalidateIntrinsicContentSize(); refreshAppearance(animated: false) } }
    public var controlState: FluentControlState = .normal { didSet { refreshAppearance(animated: true) } }
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

    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()

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
        focusRingType = .none
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
        focusRingType = .none
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

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        controlState = .pointerOver
    }

    public override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        controlState = .normal
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        controlState = .pressed
        super.mouseDown(with: event)
        if isEnabled {
            controlState = .pointerOver
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
        let textRect = NSRect(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2 + 1, width: textSize.width, height: textSize.height)
        appearance.foregroundColor.set()
        (title as NSString).draw(in: textRect, withAttributes: [.font: font as Any, .foregroundColor: appearance.foregroundColor])
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override var isEnabled: Bool {
        didSet { controlState = isEnabled ? .normal : .disabled; needsDisplay = true }
    }

    @objc private func invoke() { onClick?() }

    func applyDeclarativeConfiguration(from source: FluentButton) {
        title = source.title
        role = source.role
        fluentControlSize = source.fluentControlSize
        font = source.font
        fluentStyle = source.fluentStyle
        onClick = source.onClick
        isEnabled = source.isEnabled
        needsDisplay = true
        invalidateIntrinsicContentSize()
        refreshAppearance(animated: false)
    }

    private func resolvedAppearance() -> FluentButtonAppearance {
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
        guard let layer else {
            needsDisplay = true
            return
        }
        let appearance = resolvedAppearance()
        let motion = FluentMotion.controlFaster
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? motion.duration : 0)
        CATransaction.setAnimationTimingFunction(motion.curve.timingFunction)
        layer.backgroundColor = appearance.backgroundColor.cgColor
        layer.borderWidth = 0
        layer.cornerRadius = appearance.cornerRadius
        elevationBorderLayer.colors = (appearance.borderGradientColors
            ?? [appearance.borderColor, appearance.borderColor]).map(\.cgColor)
        elevationBorderLayer.locations = [0.33, 1]
        CATransaction.commit()
        updateElevationBorderGeometry(for: appearance)
        needsDisplay = true
    }

    private func configureElevationBorder() {
        elevationBorderLayer.name = "FluentKit.Button.ElevationBorder"
        elevationBorderLayer.startPoint = CGPoint(x: 0.5, y: 0)
        elevationBorderLayer.endPoint = CGPoint(x: 0.5, y: 1)
        elevationBorderLayer.mask = elevationBorderMask
        elevationBorderMask.fillColor = NSColor.clear.cgColor
        elevationBorderMask.strokeColor = NSColor.black.cgColor
        layer?.addSublayer(elevationBorderLayer)
    }

    private func updateElevationBorderGeometry(for appearance: FluentButtonAppearance) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        elevationBorderLayer.frame = bounds
        elevationBorderMask.frame = bounds
        elevationBorderMask.lineWidth = appearance.borderWidth
        let inset = appearance.borderWidth / 2
        elevationBorderMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: max(appearance.cornerRadius - inset, 0),
            cornerHeight: max(appearance.cornerRadius - inset, 0),
            transform: nil
        )
        elevationBorderLayer.isHidden = appearance.borderWidth <= 0
        CATransaction.commit()
    }
}

extension FluentButton: FluentControlSizeConfigurable {}
