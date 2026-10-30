import AppKit

/// Native AppKit implementation of WinUI's RatingControl value, placeholder, pointer-preview,
/// clear, keyboard, and right-to-left contracts.
public final class FluentRatingControl: NSControl, FluentControlSizeConfigurable {
    public static let unsetValue = -1.0

    private enum Metrics {
        static let itemSize: CGFloat = 16
        static let itemSpacing: CGFloat = 8
        static let captionSpacing: CGFloat = 12
        static let captionFontSize: CGFloat = 12
        static let minimumHeight: CGFloat = 32
        static let pointerScale: CGFloat = 0.8
        static let restingScale: CGFloat = 0.5
        static let scaleFalloff: CGFloat = 0.0005
    }

    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            applyAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }

    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            if reduceMotion { removeVisualAnimations() }
            applyAppearance(animated: false)
        }
    }

    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            needsLayout = true
            applyAppearance(animated: false)
        }
    }

    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            needsLayout = true
            invalidateIntrinsicContentSize()
            applyAppearance(animated: false)
        }
    }

    public var value: Double {
        get { storedValue }
        set { setProgrammaticValue(newValue) }
    }

    public var placeholderValue: Double {
        get { storedPlaceholderValue }
        set {
            let coerced = coerceProgrammaticValue(newValue)
            guard !same(storedPlaceholderValue, coerced) else { return }
            storedPlaceholderValue = coerced
            applyAppearance(animated: true)
            updateAccessibilityState()
        }
    }

    public var maxRating: Int {
        get { storedMaxRating }
        set {
            let coerced = max(1, newValue)
            guard storedMaxRating != coerced else { return }
            storedMaxRating = coerced
            initialSetValue = min(max(initialSetValue, 1), coerced)
            let coercedValue = coerceProgrammaticValue(storedValue)
            storedPlaceholderValue = coerceProgrammaticValue(storedPlaceholderValue)
            if !same(storedValue, coercedValue) { commitValue(coercedValue) }
            rebuildItems()
            invalidateIntrinsicContentSize()
            updateAccessibilityState()
        }
    }

    public var initialSetValue: Int {
        didSet {
            let coerced = min(max(initialSetValue, 1), storedMaxRating)
            if initialSetValue != coerced { initialSetValue = coerced }
        }
    }

    public var isClearEnabled = true

    public var isReadOnly = false {
        didSet {
            guard oldValue != isReadOnly else { return }
            if isReadOnly { cancelPointerInteraction() }
            updateAccessibilityState()
            applyAppearance(animated: true)
        }
    }

    public var caption: String {
        didSet {
            guard oldValue != caption else { return }
            captionLabel.stringValue = caption
            captionLabel.isHidden = caption.isEmpty
            setAccessibilityLabel(caption.isEmpty ? "Rating" : caption)
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public var onValueChanged: ((Double) -> Void)?

    private final class ItemVisual {
        let container = CALayer()
        let background = CAShapeLayer()
        let foreground = CAShapeLayer()
        let foregroundMask = CALayer()

        init(index: Int, path: CGPath) {
            container.name = "FluentKit.RatingControl.Item.\(index)"
            container.bounds = CGRect(x: 0, y: 0, width: Metrics.itemSize, height: Metrics.itemSize)
            container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            container.masksToBounds = false
            background.name = "FluentKit.RatingControl.Background.\(index)"
            background.path = path
            background.fillColor = NSColor.clear.cgColor
            background.lineJoin = .round
            background.lineCap = .round
            foreground.name = "FluentKit.RatingControl.Foreground.\(index)"
            foreground.path = path
            foreground.lineJoin = .round
            foregroundMask.backgroundColor = NSColor.white.cgColor
            foreground.mask = foregroundMask
            container.addSublayer(background)
            container.addSublayer(foreground)
        }
    }

    private var storedValue: Double
    private var storedPlaceholderValue: Double
    private var storedMaxRating: Int
    private var itemVisuals: [ItemVisual] = []
    private let captionLabel = NSTextField(labelWithString: "")
    private let focusLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var pointerFraction: Double = 0
    private var pointerLocation = NSPoint.zero
    private var isPointerOverItems = false
    private var isPointerDown = false
    private var suppressesValueNotification = false

    public override var acceptsFirstResponder: Bool { isEnabled && !isReadOnly }

    public init(
        value: Double = FluentRatingControl.unsetValue,
        placeholderValue: Double = FluentRatingControl.unsetValue,
        maxRating: Int = 5,
        initialSetValue: Int = 1,
        isClearEnabled: Bool = true,
        isReadOnly: Bool = false,
        caption: String = ""
    ) {
        storedMaxRating = max(1, maxRating)
        storedValue = Self.coerce(value, maximum: max(1, maxRating))
        storedPlaceholderValue = Self.coerce(placeholderValue, maximum: max(1, maxRating))
        self.initialSetValue = min(max(initialSetValue, 1), max(1, maxRating))
        self.isClearEnabled = isClearEnabled
        self.isReadOnly = isReadOnly
        self.caption = caption
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        storedValue = Self.unsetValue
        storedPlaceholderValue = Self.unsetValue
        storedMaxRating = 5
        initialSetValue = 1
        caption = ""
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let scale = metricScale
        let ratingWidth = actualRatingWidth
        let captionWidth: CGFloat
        if caption.isEmpty {
            captionWidth = 0
        } else {
            captionWidth = Metrics.captionSpacing * scale + ceil(captionLabel.intrinsicContentSize.width)
        }
        return NSSize(
            width: ceil(ratingWidth + captionWidth),
            height: ceil(max(Metrics.minimumHeight * scale, Metrics.itemSize * scale))
        )
    }

    public override func layout() {
        super.layout()
        let scale = metricScale
        let size = Metrics.itemSize * scale
        let spacing = Metrics.itemSpacing * scale
        let ratingWidth = actualRatingWidth
        let startX = isRTL ? bounds.maxX - ratingWidth : bounds.minX
        let centerY = bounds.midY
        let starPath = Self.starPath(in: CGRect(
            x: 0.75 * scale,
            y: 0.75 * scale,
            width: max(size - 1.5 * scale, 1),
            height: max(size - 1.5 * scale, 1)
        ))
        for logicalIndex in itemVisuals.indices {
            let visualIndex = isRTL ? storedMaxRating - logicalIndex - 1 : logicalIndex
            let x = startX + CGFloat(visualIndex) * (size + spacing)
            let visual = itemVisuals[logicalIndex]
            visual.container.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            visual.container.position = CGPoint(x: x + size / 2, y: centerY)
            visual.background.frame = visual.container.bounds
            visual.foreground.frame = visual.container.bounds
            visual.background.path = starPath
            visual.foreground.path = starPath
        }
        if !caption.isEmpty {
            let x = isRTL
                ? startX - Metrics.captionSpacing * scale - captionLabel.intrinsicContentSize.width
                : startX + ratingWidth + Metrics.captionSpacing * scale
            captionLabel.frame = NSRect(
                x: x,
                y: centerY - captionLabel.intrinsicContentSize.height / 2,
                width: captionLabel.intrinsicContentSize.width,
                height: captionLabel.intrinsicContentSize.height
            )
        }
        focusLayer.frame = bounds.insetBy(dx: 0.5, dy: 1.5)
        focusLayer.path = CGPath(
            roundedRect: focusLayer.bounds,
            cornerWidth: 4 * scale,
            cornerHeight: 4 * scale,
            transform: nil
        )
        applyAppearance(animated: false)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) { updatePointer(with: event, animated: true) }
    public override func mouseMoved(with event: NSEvent) { updatePointer(with: event, animated: false) }

    public override func mouseExited(with event: NSEvent) {
        guard !isPointerDown else { return }
        isPointerOverItems = false
        applyAppearance(animated: true)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled, !isReadOnly else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard ratingFrame.contains(point) else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        _ = window?.makeFirstResponder(self)
        isPointerDown = true
        updatePointer(point: point, animated: false, permitsOutside: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isPointerDown else { return }
        updatePointer(point: convert(event.locationInWindow, from: nil), animated: false, permitsOutside: true)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isPointerDown else { return }
        let point = convert(event.locationInWindow, from: nil)
        updatePointer(point: point, animated: false, permitsOutside: true)
        isPointerDown = false
        setRatingTo(ceil(pointerFraction * Double(storedMaxRating)), originatedFromMouse: true)
        isPointerOverItems = ratingFrame.contains(point)
        applyAppearance(animated: true)
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled, !isReadOnly else {
            super.keyDown(with: event)
            return
        }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 123:
            changeRating(by: isRTL ? 1 : -1)
        case 124:
            changeRating(by: isRTL ? -1 : 1)
        case 126:
            changeRating(by: 1)
        case 125:
            changeRating(by: -1)
        case 115:
            setRatingTo(0, originatedFromMouse: false)
        case 119:
            setRatingTo(Double(storedMaxRating), originatedFromMouse: false)
        case 36, 49:
            if storedValue == Self.unsetValue { setRatingTo(Double(initialSetValue), originatedFromMouse: false) }
        default:
            super.keyDown(with: event)
            return
        }
        updateFocusRing()
    }

    public override func cancelOperation(_ sender: Any?) { cancelPointerInteraction() }

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled { cancelPointerInteraction() }
            setAccessibilityEnabled(isEnabled)
            applyAppearance(animated: true)
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

    public override func accessibilityValue() -> Any? {
        storedValue == Self.unsetValue ? 0 : storedValue
    }

    public override func accessibilityValueDescription() -> String? {
        storedValue == Self.unsetValue ? "Unrated" : "\(storedValue) of \(storedMaxRating)"
    }

    public override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled, !isReadOnly else { return false }
        changeRating(by: 1)
        return true
    }

    public override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled, !isReadOnly else { return false }
        changeRating(by: -1)
        return true
    }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isReadOnly else { return false }
        if storedValue == Self.unsetValue { setRatingTo(Double(initialSetValue), originatedFromMouse: false) }
        return true
    }

    func setValueFromBinding(_ newValue: Double) {
        suppressesValueNotification = true
        setProgrammaticValue(newValue)
        suppressesValueNotification = false
    }

    private var metricScale: CGFloat {
        theme.density.metricScale * fluentControlSize.metricScale
    }

    private var actualRatingWidth: CGFloat {
        let count = CGFloat(storedMaxRating)
        return count * Metrics.itemSize * metricScale
            + CGFloat(max(storedMaxRating - 1, 0)) * Metrics.itemSpacing * metricScale
    }

    private var ratingFrame: NSRect {
        let x = isRTL ? bounds.maxX - actualRatingWidth : bounds.minX
        return NSRect(x: x, y: bounds.midY - Metrics.minimumHeight * metricScale / 2,
                      width: actualRatingWidth, height: Metrics.minimumHeight * metricScale)
    }

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    private func configureView() {
        wantsLayer = true
        layer?.masksToBounds = false
        focusRingType = .none
        userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
        focusLayer.name = "FluentKit.RatingControl.FocusRing"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.lineWidth = theme.focusStrokeWidth
        focusLayer.opacity = 0
        layer?.addSublayer(focusLayer)
        captionLabel.stringValue = caption
        captionLabel.isHidden = caption.isEmpty
        captionLabel.setAccessibilityElement(false)
        addSubview(captionLabel)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(caption.isEmpty ? "Rating" : caption)
        setAccessibilityEnabled(isEnabled)
        rebuildItems()
        updateAccessibilityState()
    }

    private func rebuildItems() {
        itemVisuals.forEach { $0.container.removeFromSuperlayer() }
        let path = Self.starPath(in: CGRect(x: 0.75, y: 0.75, width: 14.5, height: 14.5))
        itemVisuals = (0..<storedMaxRating).map { index in
            let visual = ItemVisual(index: index, path: path)
            layer?.insertSublayer(visual.container, below: focusLayer)
            return visual
        }
        needsLayout = true
        applyAppearance(animated: false)
    }

    private func applyAppearance(animated: Bool) {
        let displayValue = resolvedDisplayValue
        let foreground = resolvedForegroundColor
        let scale = metricScale
        captionLabel.font = .systemFont(ofSize: Metrics.captionFontSize * fluentControlSize.metricScale)
        captionLabel.textColor = theme.ratingCaptionForeground
        focusLayer.strokeColor = theme.accent.cgColor
        focusLayer.lineWidth = theme.focusStrokeWidth

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, visual) in itemVisuals.enumerated() {
            let fraction = min(max(displayValue - Double(index), 0), 1)
            visual.background.strokeColor = theme.ratingUnselectedForeground.cgColor
            visual.background.lineWidth = 1.35 * scale
            visual.foreground.fillColor = foreground.cgColor
            visual.foreground.strokeColor = foreground.cgColor
            visual.foreground.lineWidth = 0.5 * scale
            let width = Metrics.itemSize * scale * CGFloat(fraction)
            visual.foregroundMask.frame = CGRect(
                x: isRTL ? Metrics.itemSize * scale - width : 0,
                y: 0,
                width: width,
                height: Metrics.itemSize * scale
            )
            let targetScale = pointerScale(for: visual.container.position.x)
            let oldTransform = visual.container.presentation()?.transform ?? visual.container.transform
            visual.container.setAffineTransform(CGAffineTransform(scaleX: targetScale, y: targetScale))
            if animated, !reduceMotion {
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = NSValue(caTransform3D: oldTransform)
                animation.toValue = NSValue(caTransform3D: visual.container.transform)
                animation.duration = FluentMotion.controlFast.duration
                animation.timingFunction = FluentMotion.controlFast.curve.timingFunction
                visual.container.add(animation, forKey: "fluent.rating.scale")
            }
        }
        CATransaction.commit()
        updateFocusRing()
    }

    private var resolvedDisplayValue: Double {
        if (isPointerOverItems || isPointerDown), isEnabled, !isReadOnly {
            return min(max(ceil(pointerFraction * Double(storedMaxRating)), 0), Double(storedMaxRating))
        }
        if storedValue >= 0 { return storedValue }
        if storedPlaceholderValue >= 0 { return storedPlaceholderValue }
        return 0
    }

    private var resolvedForegroundColor: NSColor {
        if !isEnabled { return theme.ratingDisabledSelectedForeground }
        if isPointerOverItems || isPointerDown {
            return storedValue >= 0
                ? theme.ratingPointerOverSelectedForeground
                : theme.ratingPointerOverPlaceholderForeground
        }
        if storedValue >= 0 { return theme.ratingSelectedForeground }
        if storedPlaceholderValue >= 0 { return theme.ratingPlaceholderForeground }
        return theme.ratingPointerOverUnselectedForeground
    }

    private func pointerScale(for centerX: CGFloat) -> CGFloat {
        guard (isPointerOverItems || isPointerDown), isEnabled, !isReadOnly else { return 1 }
        let delta = centerX - pointerLocation.x
        let sourceScale = max(
            -Metrics.scaleFalloff * Metrics.pointerScale * delta * delta + Metrics.pointerScale,
            Metrics.restingScale
        )
        return sourceScale / Metrics.restingScale
    }

    private func updatePointer(with event: NSEvent, animated: Bool) {
        updatePointer(point: convert(event.locationInWindow, from: nil), animated: animated, permitsOutside: false)
    }

    private func updatePointer(point: NSPoint, animated: Bool, permitsOutside: Bool) {
        guard isEnabled, !isReadOnly else { return }
        let frame = ratingFrame
        let inside = frame.contains(point)
        guard inside || permitsOutside else {
            if isPointerOverItems {
                isPointerOverItems = false
                applyAppearance(animated: true)
            }
            return
        }
        pointerLocation = point
        let raw = isRTL
            ? (frame.maxX - point.x) / max(frame.width, 1)
            : (point.x - frame.minX) / max(frame.width, 1)
        pointerFraction = min(max(Double(raw), 0), 1)
        isPointerOverItems = inside
        applyAppearance(animated: animated)
    }

    private func cancelPointerInteraction() {
        isPointerDown = false
        isPointerOverItems = false
        applyAppearance(animated: true)
    }

    private func changeRating(by change: Double) {
        guard change != 0 else { return }
        let next: Double
        if storedValue == Self.unsetValue {
            next = Double(initialSetValue)
        } else if storedValue.rounded(.towardZero) != storedValue {
            next = change < 0 ? floor(storedValue) : floor(storedValue) + 1
        } else {
            next = storedValue + change
        }
        setRatingTo(next, originatedFromMouse: false)
    }

    private func setRatingTo(_ proposed: Double, originatedFromMouse: Bool) {
        let candidate = min(max(proposed, 0), Double(storedMaxRating))
        let oldValue = storedValue
        guard oldValue > Self.unsetValue || candidate != 0 else { return }
        let newValue: Double
        if !isClearEnabled, candidate <= 0 {
            newValue = 1
        } else if same(candidate, oldValue), isClearEnabled,
                  candidate != Double(storedMaxRating) || originatedFromMouse {
            newValue = Self.unsetValue
        } else if candidate > 0 {
            newValue = candidate
        } else {
            newValue = Self.unsetValue
        }
        commitValue(newValue)
    }

    private func setProgrammaticValue(_ newValue: Double) {
        commitValue(coerceProgrammaticValue(newValue))
    }

    private func commitValue(_ newValue: Double) {
        guard !same(storedValue, newValue) else { return }
        storedValue = newValue
        applyAppearance(animated: true)
        updateAccessibilityState()
        guard !suppressesValueNotification else { return }
        sendAction(action, to: target)
        onValueChanged?(newValue)
    }

    private func coerceProgrammaticValue(_ value: Double) -> Double {
        Self.coerce(value, maximum: storedMaxRating)
    }

    private static func coerce(_ value: Double, maximum: Int) -> Double {
        guard value.isFinite else { return unsetValue }
        if value < 0 { return unsetValue }
        if value <= 1 { return 1 }
        return min(value, Double(maximum))
    }

    private func updateAccessibilityState() {
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(Double(storedMaxRating))
        setAccessibilityValue(storedValue == Self.unsetValue ? 0 : storedValue)
        setAccessibilityHelp(isReadOnly ? "Read-only rating" : "Use arrow keys to change the rating")
    }

    private func updateFocusRing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
        CATransaction.commit()
    }

    private func removeVisualAnimations() {
        itemVisuals.forEach { $0.container.removeAllAnimations() }
    }

    private static func same(_ lhs: Double, _ rhs: Double) -> Bool {
        if lhs.isNaN, rhs.isNaN { return true }
        return abs(lhs - rhs) < 0.000_001
    }

    private func same(_ lhs: Double, _ rhs: Double) -> Bool { Self.same(lhs, rhs) }

    private static func starPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.43
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            // AppKit/Core Animation uses an upward-positive local Y axis here. +pi/2 places
            // the first outer point at twelve o'clock; -pi/2 would turn every star upside down.
            let angle = CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

public struct FluentRatingControlView: FluentUpdatablePrimitiveView {
    private let binding: FluentBinding<Double>
    private let placeholderValue: Double
    private let maxRating: Int
    private let initialSetValue: Int
    private let isClearEnabled: Bool
    private let isReadOnly: Bool
    private let caption: String
    private let onValueChanged: ((Double) -> Void)?

    public init(
        value: FluentBinding<Double>,
        placeholderValue: Double = FluentRatingControl.unsetValue,
        maxRating: Int = 5,
        initialSetValue: Int = 1,
        isClearEnabled: Bool = true,
        isReadOnly: Bool = false,
        caption: String = "",
        onValueChanged: ((Double) -> Void)? = nil
    ) {
        binding = value
        self.placeholderValue = placeholderValue
        self.maxRating = maxRating
        self.initialSetValue = initialSetValue
        self.isClearEnabled = isClearEnabled
        self.isReadOnly = isReadOnly
        self.caption = caption
        self.onValueChanged = onValueChanged
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentBoundRatingControl(
            binding: binding,
            placeholderValue: placeholderValue,
            maxRating: maxRating,
            initialSetValue: initialSetValue,
            isClearEnabled: isClearEnabled,
            isReadOnly: isReadOnly,
            caption: caption,
            onValueChanged: onValueChanged,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentBoundRatingControl else { return false }
        host.update(
            binding: binding,
            placeholderValue: placeholderValue,
            maxRating: maxRating,
            initialSetValue: initialSetValue,
            isClearEnabled: isClearEnabled,
            isReadOnly: isReadOnly,
            caption: caption,
            onValueChanged: onValueChanged,
            context: context
        )
        return true
    }
}

private final class FluentBoundRatingControl: NSView {
    let control: FluentRatingControl
    private var binding: FluentBinding<Double>
    private var observedBinding: FluentBinding<Double>?
    private var observerID: UUID?
    private var subscriptionGeneration: UInt = 0
    private var applyingBinding = false

    override var intrinsicContentSize: NSSize { control.intrinsicContentSize }

    init(
        binding: FluentBinding<Double>,
        placeholderValue: Double,
        maxRating: Int,
        initialSetValue: Int,
        isClearEnabled: Bool,
        isReadOnly: Bool,
        caption: String,
        onValueChanged: ((Double) -> Void)?,
        context: FluentRenderContext
    ) {
        self.binding = binding
        control = FluentRatingControl(
            value: binding.get(),
            placeholderValue: placeholderValue,
            maxRating: maxRating,
            initialSetValue: initialSetValue,
            isClearEnabled: isClearEnabled,
            isReadOnly: isReadOnly,
            caption: caption
        )
        super.init(frame: .zero)
        addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyContext(context)
        control.onValueChanged = { [weak self] value in
            guard let self, !self.applyingBinding else { return }
            self.binding.set(value)
            onValueChanged?(value)
        }
        normalizeBindingIfNeeded(requestedValue: binding.get())
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { removeObserver() }

    func update(
        binding: FluentBinding<Double>,
        placeholderValue: Double,
        maxRating: Int,
        initialSetValue: Int,
        isClearEnabled: Bool,
        isReadOnly: Bool,
        caption: String,
        onValueChanged: ((Double) -> Void)?,
        context: FluentRenderContext
    ) {
        let observationChanged = self.binding.observationIdentity != binding.observationIdentity
        if observationChanged { removeObserver() }
        self.binding = binding
        applyContext(context)
        control.maxRating = maxRating
        control.initialSetValue = initialSetValue
        control.placeholderValue = placeholderValue
        control.isClearEnabled = isClearEnabled
        control.isReadOnly = isReadOnly
        control.caption = caption
        control.onValueChanged = { [weak self] value in
            guard let self, !self.applyingBinding else { return }
            self.binding.set(value)
            onValueChanged?(value)
        }
        applyingBinding = true
        let requestedValue = binding.get()
        control.setValueFromBinding(requestedValue)
        applyingBinding = false
        normalizeBindingIfNeeded(requestedValue: requestedValue)
        if observationChanged { installObserver() }
        invalidateIntrinsicContentSize()
    }

    private func applyContext(_ context: FluentRenderContext) {
        control.theme = context.theme
        control.reduceMotion = context.reduceMotion
        control.fluentLayoutDirection = context.layoutDirection
    }

    private func installObserver() {
        subscriptionGeneration &+= 1
        let generation = subscriptionGeneration
        observedBinding = binding
        observerID = binding.observe? { [weak self] value in
            let apply = { [weak self] in
                guard let self, generation == self.subscriptionGeneration else { return }
                self.applyingBinding = true
                self.control.setValueFromBinding(value)
                self.applyingBinding = false
                self.normalizeBindingIfNeeded(requestedValue: value)
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func removeObserver() {
        subscriptionGeneration &+= 1
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observerID = nil
        observedBinding = nil
    }

    private func normalizeBindingIfNeeded(requestedValue: Double) {
        let normalized = control.value
        let matches = requestedValue.isFinite
            && abs(requestedValue - normalized) < 0.000_001
        if !matches { binding.set(normalized) }
    }
}
