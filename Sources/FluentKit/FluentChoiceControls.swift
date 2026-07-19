import AppKit

public final class FluentCheckBox: NSControl {
    public var theme: FluentTheme = .current {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var fluentStyle: any FluentCheckBoxStyle = FluentAutomaticCheckBoxStyle() {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var title: String { didSet { setAccessibilityTitle(title); needsDisplay = true } }
    public var isChecked: Bool {
        didSet {
            guard oldValue != isChecked else { return }
            sendAction(action, to: target)
            onValueChanged?(isChecked)
            setAccessibilityValue(isChecked ? "On" : "Off")
            needsDisplay = true
        }
    }
    public var onValueChanged: ((Bool) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private var isPointerOver = false

    public init(title: String = "Check box", isChecked: Bool = false) {
        self.title = title
        self.isChecked = isChecked
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
        setAccessibilityRole(.checkBox)
        setAccessibilityTitle(title)
        setAccessibilityValue(isChecked ? "On" : "Off")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        title = "Check box"
        isChecked = false
        super.init(coder: coder)
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let text = (title as NSString).size(withAttributes: [.font: appearance.labelFont])
        return NSSize(
            width: appearance.boxSize + appearance.labelSpacing + text.width + 2,
            height: max(theme.controlHeight(for: fluentControlSize), appearance.boxSize + 2)
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
        let box = NSRect(
            x: 1,
            y: (bounds.height - appearance.boxSize) / 2,
            width: appearance.boxSize,
            height: appearance.boxSize
        )
        let path = NSBezierPath(roundedRect: box, xRadius: appearance.cornerRadius, yRadius: appearance.cornerRadius)
        appearance.fillColor.setFill()
        path.fill()
        if appearance.borderWidth > 0 {
            appearance.borderColor.setStroke()
            path.lineWidth = appearance.borderWidth
            path.stroke()
        }

        if isChecked {
            let check = NSBezierPath()
            check.move(to: NSPoint(x: box.minX + box.width * 0.23, y: box.midY))
            check.line(to: NSPoint(x: box.minX + box.width * 0.45, y: box.minY + box.height * 0.25))
            check.line(to: NSPoint(x: box.maxX - box.width * 0.18, y: box.maxY - box.height * 0.23))
            check.lineWidth = max(1.5, box.width * 0.1)
            appearance.markColor.setStroke()
            check.stroke()
        }

        let textRect = NSRect(
            x: box.maxX + appearance.labelSpacing,
            y: bounds.midY - appearance.labelFont.capHeight / 2,
            width: max(0, bounds.width - box.maxX - appearance.labelSpacing - 1),
            height: appearance.labelFont.pointSize + 6
        )
        (title as NSString).draw(in: textRect, withAttributes: [.font: appearance.labelFont, .foregroundColor: appearance.labelColor])
    }

    public override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }
    public override func mouseDown(with event: NSEvent) { guard isEnabled else { return }; isChecked.toggle() }
    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 36 || event.keyCode == 49 { isChecked.toggle() } else { super.keyDown(with: event) }
    }
    public override func accessibilityValue() -> Any? { isChecked ? "On" : "Off" }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func resolvedAppearance() -> FluentCheckBoxAppearance {
        fluentStyle.appearance(
            for: FluentCheckBoxStyleConfiguration(
                isChecked: isChecked,
                isEnabled: isEnabled,
                isPointerOver: isPointerOver,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    @discardableResult
    public func checkBoxStyle(_ style: any FluentCheckBoxStyle) -> FluentCheckBox {
        fluentStyle = style
        return self
    }
}

extension FluentCheckBox: FluentControlSizeConfigurable {}

public final class FluentRadioButton: NSControl {
    public var theme: FluentTheme = .current {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var fluentStyle: any FluentRadioButtonStyle = FluentAutomaticRadioButtonStyle() {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var title: String { didSet { setAccessibilityTitle(title); needsDisplay = true } }
    public var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            sendAction(action, to: target)
            onValueChanged?(isSelected)
            setAccessibilityValue(isSelected ? "On" : "Off")
            needsDisplay = true
        }
    }
    public var onValueChanged: ((Bool) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    public init(title: String = "Radio button", isSelected: Bool = false) {
        self.title = title
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
        setAccessibilityRole(.radioButton)
        setAccessibilityTitle(title)
        setAccessibilityValue(isSelected ? "On" : "Off")
    }

    required init?(coder: NSCoder) {
        title = "Radio button"
        isSelected = false
        super.init(coder: coder)
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let text = (title as NSString).size(withAttributes: [.font: appearance.labelFont])
        return NSSize(
            width: appearance.diameter + appearance.labelSpacing + text.width + 2,
            height: max(theme.controlHeight(for: fluentControlSize), appearance.diameter + 2)
        )
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let circle = NSRect(
            x: 1,
            y: (bounds.height - appearance.diameter) / 2,
            width: appearance.diameter,
            height: appearance.diameter
        )
        let path = NSBezierPath(ovalIn: circle)
        appearance.fillColor.setFill()
        path.fill()
        if appearance.borderWidth > 0 {
            appearance.borderColor.setStroke()
            path.lineWidth = appearance.borderWidth
            path.stroke()
        }
        if isSelected {
            appearance.dotColor.setFill()
            NSBezierPath(ovalIn: circle.insetBy(dx: circle.width * 0.28, dy: circle.height * 0.28)).fill()
        }
        let textRect = NSRect(
            x: circle.maxX + appearance.labelSpacing,
            y: bounds.midY - appearance.labelFont.capHeight / 2,
            width: max(0, bounds.width - circle.maxX - appearance.labelSpacing - 1),
            height: appearance.labelFont.pointSize + 6
        )
        (title as NSString).draw(in: textRect, withAttributes: [.font: appearance.labelFont, .foregroundColor: appearance.labelColor])
    }

    public override func mouseDown(with event: NSEvent) { guard isEnabled else { return }; isSelected = true }
    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 36 || event.keyCode == 49 { isSelected = true } else { super.keyDown(with: event) }
    }
    public override func accessibilityValue() -> Any? { isSelected ? "On" : "Off" }

    private func resolvedAppearance() -> FluentRadioButtonAppearance {
        fluentStyle.appearance(
            for: FluentRadioButtonStyleConfiguration(
                isSelected: isSelected,
                isEnabled: isEnabled,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    @discardableResult
    public func radioButtonStyle(_ style: any FluentRadioButtonStyle) -> FluentRadioButton {
        fluentStyle = style
        return self
    }
}

extension FluentRadioButton: FluentControlSizeConfigurable {}

public final class FluentProgressRing: NSView {
    public var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    public var isAnimating: Bool = false {
        didSet { isAnimating ? startAnimating() : stopAnimating() }
    }

    private var rotation: CGFloat = 0
    private var timer: Timer?

    public init(isAnimating: Bool = true) {
        self.isAnimating = isAnimating
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.progressIndicator)
        if isAnimating { startAnimating() }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit { timer?.invalidate() }

    public override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    public override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: rotation, endAngle: rotation + 250, clockwise: false)
        path.lineWidth = 3
        path.lineCapStyle = .round
        theme.accent.setStroke()
        path.stroke()
    }

    private func startAnimating() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            guard let self, self.isAnimating else { return }
            self.rotation += 6
            if self.rotation >= 360 { self.rotation -= 360 }
            self.needsDisplay = true
        }
    }

    private func stopAnimating() { timer?.invalidate(); timer = nil; needsDisplay = true }
}
