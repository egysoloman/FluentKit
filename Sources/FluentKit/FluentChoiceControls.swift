import AppKit

public final class FluentCheckBox: NSControl {
    public var theme: FluentTheme = .current {
        didSet {
            refreshAppearance()
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: any FluentCheckBoxStyle = FluentAutomaticCheckBoxStyle() {
        didSet {
            refreshAppearance()
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            if reduceMotion { glyphLayer.removeAllAnimations() }
            refreshAppearance(snapAnimations: true)
        }
    }
    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            refreshAppearance(snapAnimations: true)
            needsDisplay = true
        }
    }
    public var title: String {
        didSet {
            guard oldValue != title else { return }
            setAccessibilityTitle(title)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var isChecked: Bool {
        didSet {
            guard oldValue != isChecked else { return }
            setAccessibilityValue(isChecked ? "On" : "Off")
            refreshAppearance(selectionChanged: true)
            guard !suppressesValueNotification else { return }
            sendAction(action, to: target)
            onValueChanged?(isChecked)
        }
    }
    public var onValueChanged: ((Bool) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            refreshAppearance(snapAnimations: true)
            invalidateIntrinsicContentSize()
        }
    }

    private var isPointerOver = false
    private var isPressed = false
    private var suppressesValueNotification = false
    private let focusLayer = CALayer()
    private let boxLayer = CALayer()
    private let glyphLayer = CAShapeLayer()
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public init(title: String = "Check box", isChecked: Bool = false) {
        self.title = title
        self.isChecked = isChecked
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        title = "Check box"
        isChecked = false
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let text = (title as NSString).size(withAttributes: [.font: appearance.labelFont])
        return NSSize(
            width: appearance.boxSize + appearance.labelSpacing + text.width + 6,
            height: max(theme.controlHeight(for: fluentControlSize), appearance.boxSize + 2)
        )
    }

    public override func layout() {
        super.layout()
        let direction = userInterfaceLayoutDirection
        guard bounds.size != lastLayoutSize || direction != lastLayoutDirection else { return }
        lastLayoutSize = bounds.size
        lastLayoutDirection = direction
        refreshAppearance(snapAnimations: true)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let box = boxRect(for: appearance)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = isRTL ? .right : .left
        let textSize = (title as NSString).size(withAttributes: [.font: appearance.labelFont])
        let textRect = NSRect(
            x: isRTL ? 1 : box.maxX + appearance.labelSpacing,
            y: bounds.midY - textSize.height / 2,
            width: isRTL
                ? max(0, box.minX - appearance.labelSpacing - 1)
                : max(0, bounds.width - box.maxX - appearance.labelSpacing - 1),
            height: textSize.height
        )
        (title as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: appearance.labelFont,
                .foregroundColor: appearance.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    public override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        refreshAppearance()
    }

    public override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        refreshAppearance()
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = true
        refreshAppearance()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        refreshAppearance()
    }

    public override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)
        isPressed = false
        isPointerOver = inside
        if inside {
            isChecked.toggle()
        } else {
            refreshAppearance()
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        switch event.keyCode {
        case 36, 49:
            guard !event.isARepeat else { return }
            cancelInteraction(refresh: false)
            isChecked.toggle()
        case 53:
            cancelInteraction()
        default:
            super.keyDown(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) { cancelInteraction() }

    public override func accessibilityValue() -> Any? { isChecked ? "On" : "Off" }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        cancelInteraction(refresh: false)
        isChecked.toggle()
        return true
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { cancelInteraction(refresh: false) }
            setAccessibilityEnabled(isEnabled)
            refreshAppearance()
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
        refreshAppearance()
    }

    func setStateFromBinding(_ value: Bool) {
        cancelInteraction(refresh: false)
        suppressesValueNotification = true
        isChecked = value
        suppressesValueNotification = false
    }

    private func resolvedAppearance() -> FluentCheckBoxAppearance {
        fluentStyle.appearance(
            for: FluentCheckBoxStyleConfiguration(
                isChecked: isChecked,
                isEnabled: isEnabled,
                isPointerOver: isPointerOver,
                isPressed: isPressed,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    private func configureView() {
        wantsLayer = true
        focusRingType = .none
        userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
        setAccessibilityRole(.checkBox)
        setAccessibilityTitle(title)
        setAccessibilityValue(isChecked ? "On" : "Off")
        setAccessibilityEnabled(isEnabled)

        focusLayer.name = "FluentKit.CheckBox.FocusRing"
        boxLayer.name = "FluentKit.CheckBox.Box"
        glyphLayer.name = "FluentKit.CheckBox.Glyph"
        focusLayer.opacity = 0
        glyphLayer.fillColor = NSColor.clear.cgColor
        glyphLayer.lineCap = .round
        glyphLayer.lineJoin = .round
        layer?.addSublayer(focusLayer)
        layer?.addSublayer(boxLayer)
        layer?.addSublayer(glyphLayer)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        refreshAppearance(snapAnimations: true)
    }

    private func refreshAppearance(
        selectionChanged: Bool = false,
        snapAnimations: Bool = false
    ) {
        let appearance = resolvedAppearance()
        let oldGlyph = glyphLayer.presentation() ?? glyphLayer
        let oldStrokeEnd = oldGlyph.strokeEnd
        let oldOpacity = oldGlyph.opacity
        if selectionChanged || snapAnimations { glyphLayer.removeAllAnimations() }
        applyModelAppearance(appearance)

        if selectionChanged, !reduceMotion {
            let motion = isChecked ? FluentMotion.checkBoxGlyphOn : FluentMotion.checkBoxGlyphOff
            addGlyphAnimation(
                key: "fluent.checkbox.glyph.strokeEnd",
                keyPath: "strokeEnd",
                from: oldStrokeEnd,
                to: glyphLayer.strokeEnd,
                motion: motion
            )
            if !isChecked {
                addGlyphAnimation(
                    key: "fluent.checkbox.glyph.opacity",
                    keyPath: "opacity",
                    from: oldOpacity,
                    to: 1,
                    motion: motion
                )
            }
        }
        updateFocusRing()
        needsDisplay = true
    }

    private func applyModelAppearance(_ appearance: FluentCheckBoxAppearance) {
        let box = boxRect(for: appearance)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: box.width * 0.23, y: box.height * 0.50))
        path.addLine(to: CGPoint(x: box.width * 0.45, y: box.height * 0.25))
        path.addLine(to: CGPoint(x: box.width * 0.82, y: box.height * 0.77))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        boxLayer.frame = box
        boxLayer.cornerRadius = appearance.cornerRadius
        boxLayer.backgroundColor = appearance.fillColor.cgColor
        boxLayer.borderColor = appearance.borderColor.cgColor
        boxLayer.borderWidth = appearance.borderWidth
        glyphLayer.frame = box
        glyphLayer.path = path
        glyphLayer.strokeColor = appearance.markColor.cgColor
        glyphLayer.lineWidth = max(1.5, box.width * 0.10)
        glyphLayer.strokeEnd = isChecked ? 1 : 0
        glyphLayer.opacity = isChecked ? 1 : 0
        let focusRect = bounds.insetBy(dx: 0.5, dy: 2.5)
        focusLayer.frame = focusRect
        focusLayer.cornerRadius = max(appearance.cornerRadius + 2, 4)
        focusLayer.borderColor = theme.accent.cgColor
        focusLayer.borderWidth = theme.focusStrokeWidth
        CATransaction.commit()
    }

    private func boxRect(for appearance: FluentCheckBoxAppearance) -> NSRect {
        NSRect(
            x: isRTL ? bounds.maxX - appearance.boxSize - 1 : 1,
            y: (bounds.height - appearance.boxSize) / 2,
            width: appearance.boxSize,
            height: appearance.boxSize
        )
    }

    private func addGlyphAnimation(
        key: String,
        keyPath: String,
        from: Any,
        to: Any,
        motion: FluentMotionToken
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = motion.duration
        animation.timingFunction = motion.curve.timingFunction
        glyphLayer.add(animation, forKey: key)
    }

    private func cancelInteraction(refresh: Bool = true) {
        guard isPressed else { return }
        isPressed = false
        if refresh { refreshAppearance() }
    }

    private func updateFocusRing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.opacity = window?.firstResponder === self ? 1 : 0
        CATransaction.commit()
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
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: any FluentRadioButtonStyle = FluentAutomaticRadioButtonStyle() {
        didSet {
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            if reduceMotion { removeVisualAnimations() }
            refreshAppearance(animated: false, snapAnimations: true)
        }
    }
    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            refreshAppearance(animated: false, snapAnimations: true)
            needsDisplay = true
        }
    }
    public var title: String {
        didSet {
            guard oldValue != title else { return }
            setAccessibilityTitle(title)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            setAccessibilityValue(isSelected ? "On" : "Off")
            refreshAppearance(animated: true)
            guard !suppressesValueNotification else { return }
            sendAction(action, to: target)
            onValueChanged?(isSelected)
        }
    }
    public var onValueChanged: ((Bool) -> Void)?
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            refreshAppearance(animated: false, snapAnimations: true)
            invalidateIntrinsicContentSize()
        }
    }

    private var isPointerOver = false
    private var isPressed = false
    private var suppressesValueNotification = false
    private let focusLayer = CALayer()
    private let outerLayer = CALayer()
    private let dotLayer = CALayer()
    private let pressedDotLayer = CALayer()
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public init(title: String = "Radio button", isSelected: Bool = false) {
        self.title = title
        self.isSelected = isSelected
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        title = "Radio button"
        isSelected = false
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let text = (title as NSString).size(withAttributes: [.font: appearance.labelFont])
        return NSSize(
            width: appearance.diameter + appearance.labelSpacing + text.width + 6,
            height: max(theme.controlHeight(for: fluentControlSize), appearance.diameter + 2)
        )
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let circle = circleRect(for: appearance)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = isRTL ? .right : .left
        let textSize = (title as NSString).size(withAttributes: [.font: appearance.labelFont])
        let textRect = NSRect(
            x: isRTL ? 1 : circle.maxX + appearance.labelSpacing,
            y: bounds.midY - textSize.height / 2,
            width: isRTL
                ? max(0, circle.minX - appearance.labelSpacing - 1)
                : max(0, bounds.width - circle.maxX - appearance.labelSpacing - 1),
            height: textSize.height
        )
        (title as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: appearance.labelFont,
                .foregroundColor: appearance.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    public override func layout() {
        super.layout()
        let direction = userInterfaceLayoutDirection
        guard bounds.size != lastLayoutSize || direction != lastLayoutDirection else { return }
        lastLayoutSize = bounds.size
        lastLayoutDirection = direction
        refreshAppearance(animated: false, snapAnimations: true)
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
        window?.makeFirstResponder(self)
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = true
        refreshAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        refreshAppearance(animated: false)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)
        isPressed = false
        isPointerOver = inside
        if inside, !isSelected {
            isSelected = true
        } else {
            refreshAppearance(animated: true)
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        switch event.keyCode {
        case 36, 49:
            guard !event.isARepeat else { return }
            cancelInteraction(refresh: false)
            if !isSelected { isSelected = true }
        case 53:
            cancelInteraction()
        default:
            super.keyDown(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) { cancelInteraction() }

    public override func accessibilityValue() -> Any? { isSelected ? "On" : "Off" }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        cancelInteraction(refresh: false)
        if !isSelected { isSelected = true }
        return true
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { cancelInteraction(refresh: false) }
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
        refreshAppearance(animated: false)
    }

    func setStateFromBinding(_ value: Bool) {
        cancelInteraction(refresh: false)
        suppressesValueNotification = true
        isSelected = value
        suppressesValueNotification = false
    }

    private func resolvedAppearance() -> FluentRadioButtonAppearance {
        fluentStyle.appearance(
            for: FluentRadioButtonStyleConfiguration(
                isSelected: isSelected,
                isEnabled: isEnabled,
                isPointerOver: isPointerOver,
                isPressed: isPressed,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    private func configureView() {
        wantsLayer = true
        focusRingType = .none
        userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
        setAccessibilityRole(.radioButton)
        setAccessibilityTitle(title)
        setAccessibilityValue(isSelected ? "On" : "Off")
        setAccessibilityEnabled(isEnabled)

        focusLayer.name = "FluentKit.RadioButton.FocusRing"
        outerLayer.name = "FluentKit.RadioButton.Outer"
        dotLayer.name = "FluentKit.RadioButton.Dot"
        pressedDotLayer.name = "FluentKit.RadioButton.PressedDot"
        focusLayer.opacity = 0
        layer?.addSublayer(focusLayer)
        layer?.addSublayer(outerLayer)
        layer?.addSublayer(dotLayer)
        layer?.addSublayer(pressedDotLayer)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        refreshAppearance(animated: false, snapAnimations: true)
    }

    private func refreshAppearance(animated: Bool, snapAnimations: Bool = false) {
        let appearance = resolvedAppearance()
        let oldDot = dotLayer.presentation() ?? dotLayer
        let oldDotBounds = oldDot.bounds
        let oldDotCornerRadius = oldDot.cornerRadius
        let oldPressedDot = pressedDotLayer.presentation() ?? pressedDotLayer
        let oldPressedBounds = oldPressedDot.bounds
        let oldPressedCornerRadius = oldPressedDot.cornerRadius
        let shouldAnimatePressedDot = isPressed && !isSelected && oldPressedDot.opacity < 1
        if snapAnimations || animated { removeVisualAnimations() }
        applyModelAppearance(appearance)

        if animated, !reduceMotion {
            let motion = isEnabled && (isPointerOver || isPressed)
                ? FluentMotion.controlNormal
                : FluentMotion.controlFast
            addGeometryAnimation(
                to: dotLayer,
                key: "fluent.radio.dot.bounds",
                keyPath: "bounds",
                from: NSValue(rect: oldDotBounds),
                to: NSValue(rect: dotLayer.bounds),
                motion: motion
            )
            addGeometryAnimation(
                to: dotLayer,
                key: "fluent.radio.dot.cornerRadius",
                keyPath: "cornerRadius",
                from: oldDotCornerRadius,
                to: dotLayer.cornerRadius,
                motion: motion
            )
            if shouldAnimatePressedDot {
                addGeometryAnimation(
                    to: pressedDotLayer,
                    key: "fluent.radio.pressedDot.bounds",
                    keyPath: "bounds",
                    from: NSValue(rect: oldPressedBounds),
                    to: NSValue(rect: pressedDotLayer.bounds),
                    motion: FluentMotion.controlFast
                )
                addGeometryAnimation(
                    to: pressedDotLayer,
                    key: "fluent.radio.pressedDot.cornerRadius",
                    keyPath: "cornerRadius",
                    from: oldPressedCornerRadius,
                    to: pressedDotLayer.cornerRadius,
                    motion: FluentMotion.controlFast
                )
            }
        }
        updateFocusRing()
        needsDisplay = true
    }

    private func applyModelAppearance(_ appearance: FluentRadioButtonAppearance) {
        let circle = circleRect(for: appearance)
        let dotDiameter = min(appearance.dotDiameter, appearance.diameter)
        let pressedVisible = isPressed && !isSelected
        let pressedDiameter = pressedVisible ? dotDiameter : 4 * theme.density.metricScale * fluentControlSize.metricScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outerLayer.frame = circle
        outerLayer.cornerRadius = appearance.diameter / 2
        outerLayer.backgroundColor = appearance.fillColor.cgColor
        outerLayer.borderColor = appearance.borderColor.cgColor
        outerLayer.borderWidth = appearance.borderWidth
        dotLayer.position = CGPoint(x: circle.midX, y: circle.midY)
        dotLayer.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
        dotLayer.cornerRadius = dotDiameter / 2
        dotLayer.backgroundColor = appearance.dotColor.cgColor
        dotLayer.opacity = isSelected ? 1 : 0
        pressedDotLayer.position = CGPoint(x: circle.midX, y: circle.midY)
        pressedDotLayer.bounds = CGRect(x: 0, y: 0, width: pressedDiameter, height: pressedDiameter)
        pressedDotLayer.cornerRadius = pressedDiameter / 2
        pressedDotLayer.backgroundColor = appearance.dotColor.cgColor
        pressedDotLayer.opacity = pressedVisible ? 1 : 0
        let focusRect = bounds.insetBy(dx: 0.5, dy: 2.5)
        focusLayer.frame = focusRect
        focusLayer.cornerRadius = 5
        focusLayer.borderColor = theme.accent.cgColor
        focusLayer.borderWidth = theme.focusStrokeWidth
        CATransaction.commit()
    }

    private func circleRect(for appearance: FluentRadioButtonAppearance) -> NSRect {
        NSRect(
            x: isRTL ? bounds.maxX - appearance.diameter - 1 : 1,
            y: (bounds.height - appearance.diameter) / 2,
            width: appearance.diameter,
            height: appearance.diameter
        )
    }

    private func addGeometryAnimation(
        to layer: CALayer,
        key: String,
        keyPath: String,
        from: Any,
        to: Any,
        motion: FluentMotionToken
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = motion.duration
        animation.timingFunction = motion.curve.timingFunction
        layer.add(animation, forKey: key)
    }

    private func removeVisualAnimations() {
        dotLayer.removeAllAnimations()
        pressedDotLayer.removeAllAnimations()
    }

    private func cancelInteraction(refresh: Bool = true) {
        guard isPressed else { return }
        isPressed = false
        if refresh { refreshAppearance(animated: true) }
    }

    private func updateFocusRing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.opacity = window?.firstResponder === self ? 1 : 0
        CATransaction.commit()
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
