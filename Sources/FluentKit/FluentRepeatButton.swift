import AppKit

public struct FluentRepeatButtonStyleConfiguration {
    public let title: String
    public let controlState: FluentControlState
    public let isEnabled: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(
        title: String,
        controlState: FluentControlState,
        isEnabled: Bool,
        controlSize: FluentControlSize,
        theme: FluentTheme
    ) {
        self.title = title
        self.controlState = controlState
        self.isEnabled = isEnabled
        self.controlSize = controlSize
        self.theme = theme
    }
}

public protocol FluentRepeatButtonStyle {
    func appearance(for configuration: FluentRepeatButtonStyleConfiguration) -> FluentButtonAppearance
}

/// Maps the WinUI RepeatButton resource family onto FluentKit's shared Button chrome.
public struct FluentAutomaticRepeatButtonStyle: FluentRepeatButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentRepeatButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let usesElevationBorder = state == .normal || state == .pointerOver || state == .focused
        return FluentButtonAppearance(
            backgroundColor: theme.buttonBackground(for: state),
            foregroundColor: theme.buttonForeground(for: state),
            borderColor: theme.isHighContrast ? theme.controlStrokeStrong : theme.controlStrokeDefault,
            borderGradientColors: usesElevationBorder ? theme.controlElevationBorderColors : nil,
            borderGradientEdge: .bottom,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            contentInsets: theme.controlPadding,
            focusRingColor: theme.accent.withAlphaComponent(0.85),
            focusRingWidth: theme.focusStrokeWidth
        )
    }
}

public extension FluentRepeatButtonStyle where Self == FluentAutomaticRepeatButtonStyle {
    static var automatic: FluentAutomaticRepeatButtonStyle { FluentAutomaticRepeatButtonStyle() }
}

/// A press-mode button that invokes immediately, then repeats while pointer or Space input remains active.
public final class FluentRepeatButton: NSControl, FluentControlSizeConfigurable {
    public static let defaultDelay: TimeInterval = 0.500
    public static let defaultInterval: TimeInterval = 0.033

    public var theme: FluentTheme = .current {
        didSet {
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: any FluentRepeatButtonStyle = FluentAutomaticRepeatButtonStyle() {
        didSet {
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            visualStateCoordinator.reduceMotion = reduceMotion
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion {
                layer?.removeAllAnimations()
                elevationBorderLayer.removeAllAnimations()
            }
            refreshAppearance(animated: false)
        }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
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
    public var systemImageName: String? {
        didSet {
            guard oldValue != systemImageName else { return }
            configureChevronLayer()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var systemImagePointSize: CGFloat? {
        didSet {
            guard oldValue != systemImagePointSize else { return }
            if let systemImagePointSize {
                precondition(systemImagePointSize > 0, "FluentRepeatButton.systemImagePointSize must be positive")
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Composite controls can keep their editor focused while retaining button pointer semantics.
    public var allowsKeyboardFocus = true {
        didSet {
            guard oldValue != allowsKeyboardFocus else { return }
            if !allowsKeyboardFocus, window?.firstResponder === self {
                _ = window?.makeFirstResponder(nil)
            }
            updateFocusGeometry()
        }
    }
    /// Initial pause before the first repeated invocation. The press invocation is immediate.
    public var delay: TimeInterval {
        didSet { precondition(delay >= 0, "FluentRepeatButton.delay cannot be negative") }
    }
    /// Pause between repeated invocations after the initial delay.
    public var interval: TimeInterval {
        didSet { precondition(interval > 0, "FluentRepeatButton.interval must be positive") }
    }
    public var onClick: (() -> Void)?

    private let visualStateCoordinator = FluentVisualStateCoordinator()
    private let animationCoordinator = FluentAnimationCoordinator()
    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private let chevronLayer = FluentChevronPrimitiveLayer()
    private var pointerTrackingArea: NSTrackingArea?
    private var repeatTimer: Timer?
    private var repeatGeneration: UInt = 0
    private var isPointerOver = false
    private var isPointerPressed = false
    private var isKeyboardPressed = false

    public override var acceptsFirstResponder: Bool { isEnabled && allowsKeyboardFocus }

    public init(
        title: String = "Repeat button",
        systemImageName: String? = nil,
        systemImagePointSize: CGFloat? = nil,
        delay: TimeInterval = FluentRepeatButton.defaultDelay,
        interval: TimeInterval = FluentRepeatButton.defaultInterval
    ) {
        precondition(delay >= 0, "FluentRepeatButton.delay cannot be negative")
        precondition(interval > 0, "FluentRepeatButton.interval must be positive")
        self.title = title
        self.systemImageName = systemImageName
        self.systemImagePointSize = systemImagePointSize
        self.delay = delay
        self.interval = interval
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        title = "Repeat button"
        systemImageName = nil
        systemImagePointSize = nil
        delay = Self.defaultDelay
        interval = Self.defaultInterval
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let text = (title as NSString).size(withAttributes: [.font: resolvedFont])
        let contentWidth = systemImageName == nil
            ? text.width
            : (systemImagePointSize ?? 12 * fluentControlSize.metricScale)
        return NSSize(
            width: ceil(contentWidth + appearance.contentInsets.left + appearance.contentInsets.right),
            height: ceil(max(
                theme.controlHeight(for: fluentControlSize),
                text.height + appearance.contentInsets.top + appearance.contentInsets.bottom
            ))
        )
    }

    public override func layout() {
        super.layout()
        synchronizeVisualGeometry()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeVisualGeometry()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        synchronizeVisualGeometry()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeVisualGeometry()
    }

    private func synchronizeVisualGeometry() {
        updateElevationBorderGeometry(for: resolvedAppearance())
        updateFocusGeometry()
        updateChevron(animated: false)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let font = resolvedFont
        if chevronDirection != nil {
            updateChevron(animated: false)
            return
        }
        if let systemImageName,
           let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title) {
            let pointSize = max(8, systemImagePointSize ?? 10 * fluentControlSize.metricScale)
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
                .applying(.init(hierarchicalColor: appearance.foregroundColor))
            let configuredImage = image.withSymbolConfiguration(configuration) ?? image
            let side = ceil(max(max(configuredImage.size.width, configuredImage.size.height), pointSize))
            configuredImage.draw(
                in: NSRect(
                    x: floor(bounds.midX - side / 2),
                    y: floor(bounds.midY - side / 2),
                    width: side,
                    height: side
                )
            )
            return
        }
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let textRect = fluentSingleLineTextRect(
            NSRect(
                x: bounds.midX - textSize.width / 2,
                y: 0,
                width: textSize.width,
                height: textSize.height
            ),
            in: bounds,
            font: font
        )
        (title as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: font,
                .foregroundColor: appearance.foregroundColor
            ]
        )
    }

    public override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        if isPointerPressed { startRepeatTimerIfNeeded() }
        refreshAppearance(animated: true)
    }

    public override func mouseMoved(with event: NSEvent) {
        guard isEnabled else { return }
        updatePointerLocation(event)
    }

    public override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        stopRepeatTimer()
        refreshAppearance(animated: true)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        if allowsKeyboardFocus { window?.makeFirstResponder(self) }
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        guard isPointerOver else { return }
        isPointerPressed = true
        refreshAppearance(animated: true)
        invoke()
        startRepeatTimerIfNeeded()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isPointerPressed else { return }
        updatePointerLocation(event)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isPointerPressed else { return }
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        isPointerPressed = false
        stopRepeatTimer()
        refreshAppearance(animated: true)
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 49:
            guard !event.isARepeat, !isKeyboardPressed else { return }
            isKeyboardPressed = true
            refreshAppearance(animated: true)
            invoke()
            startRepeatTimerIfNeeded()
        case 36:
            guard !event.isARepeat else { return }
            invoke()
        case 53:
            cancelInteraction()
        default:
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49, isKeyboardPressed else {
            super.keyUp(with: event)
            return
        }
        isKeyboardPressed = false
        stopRepeatTimer()
        refreshAppearance(animated: true)
    }

    public override func cancelOperation(_ sender: Any?) { cancelInteraction() }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        cancelInteraction(refresh: false)
        invoke()
        refreshAppearance(animated: false)
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
        if result { refreshAppearance(animated: false) }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            cancelInteraction(refresh: false)
            refreshAppearance(animated: false)
        }
        return result
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeVisualGeometry()
        if window == nil { cancelInteraction(refresh: false) }
        refreshAppearance(animated: false)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    private var resolvedFont: NSFont {
        let body = theme.typography.font(for: .body)
        return body.withSize(body.pointSize * fluentControlSize.metricScale)
    }

    private var visualState: FluentVisualState {
        guard isEnabled else { return .disabled }
        if (isPointerPressed && isPointerOver) || isKeyboardPressed { return [.normal, .pressed] }
        if isPointerOver { return [.normal, .pointerOver] }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) { return [.normal, .focused] }
        return .normal
    }

    private func resolvedAppearance() -> FluentButtonAppearance {
        resolvedAppearance(for: visualState)
    }

    private func resolvedAppearance(for state: FluentVisualState) -> FluentButtonAppearance {
        fluentStyle.appearance(
            for: FluentRepeatButtonStyleConfiguration(
                title: title,
                controlState: state.primaryControlState,
                isEnabled: isEnabled,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    private func configureView() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerCurve = .continuous
        focusRingType = .none
        visualStateCoordinator.reduceMotion = reduceMotion
        animationCoordinator.reduceMotion = reduceMotion
        setAccessibilityRole(.button)
        setAccessibilityTitle(title)
        setAccessibilityEnabled(isEnabled)

        elevationBorderLayer.name = "FluentKit.RepeatButton.ElevationBorder"
        elevationBorderLayer.zPosition = 1
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        layer?.addSublayer(elevationBorderLayer)
        configureChevronLayer()

        focusLayer.name = "FluentKit.RepeatButton.FocusRing"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.zPosition = 2
        focusLayer.opacity = 0
        layer?.addSublayer(focusLayer)
        refreshAppearance(animated: false)
    }

    private func updatePointerLocation(_ event: NSEvent) {
        let wasInside = isPointerOver
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        if isPointerPressed, isPointerOver != wasInside {
            if isPointerOver {
                startRepeatTimerIfNeeded()
            } else {
                stopRepeatTimer()
            }
        }
        if isPointerOver != wasInside { refreshAppearance(animated: true) }
    }

    private func invoke() {
        sendAction(action, to: target)
        onClick?()
    }

    private var shouldContinueRepeating: Bool {
        window != nil
            && isEnabled
            && ((isPointerPressed && isPointerOver) || isKeyboardPressed)
    }

    private func startRepeatTimerIfNeeded() {
        guard shouldContinueRepeating, repeatTimer == nil else { return }
        scheduleRepeat(after: delay)
    }

    private func scheduleRepeat(after duration: TimeInterval) {
        repeatGeneration &+= 1
        let generation = repeatGeneration
        let timer = Timer(timeInterval: max(duration, 0), repeats: false) { [weak self] _ in
            guard let self, self.repeatGeneration == generation else { return }
            self.repeatTimer = nil
            guard self.shouldContinueRepeating else { return }
            self.invoke()
            guard self.shouldContinueRepeating else { return }
            self.scheduleRepeat(after: self.interval)
        }
        timer.tolerance = min(max(duration * 0.05, 0), 0.005)
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRepeatTimer() {
        repeatGeneration &+= 1
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func cancelInteraction(refresh: Bool = true) {
        let changed = isPointerPressed || isKeyboardPressed || repeatTimer != nil
        isPointerPressed = false
        isKeyboardPressed = false
        stopRepeatTimer()
        if changed, refresh { refreshAppearance(animated: true) }
    }

    private func refreshAppearance(animated: Bool) {
        visualStateCoordinator.reduceMotion = reduceMotion
        visualStateCoordinator.transition(
            to: visualState,
            animated: animated,
            motion: FluentMotion.controlFaster
        ) { [weak self] transition in
            self?.applyVisualState(transition)
        }
    }

    private func applyVisualState(_ transition: FluentVisualStateTransition) {
        guard let layer else { return }
        let appearance = resolvedAppearance(for: transition.to)
        applyFluentButtonChrome(
            to: layer,
            elevationLayer: elevationBorderLayer,
            elevationMask: elevationBorderMask,
            bounds: bounds,
            appearance: appearance,
            visualYAxis: .resolved(for: layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1,
            animationCoordinator: animationCoordinator,
            motion: transition.motion,
            keyPrefix: "fluent.repeatButton",
            animated: transition.isAnimated
        )
        updateFocusGeometry(appearance: appearance)
        updateChevron(animated: transition.isAnimated)
        needsDisplay = true
    }

    private var chevronDirection: FluentChevronDirection? {
        switch systemImageName {
        case "chevron.up": .up
        case "chevron.down": .down
        case "chevron.left": .left
        case "chevron.right": .right
        default: nil
        }
    }

    private func configureChevronLayer() {
        guard chevronDirection != nil else {
            chevronLayer.removeFromSuperlayer()
            return
        }
        guard chevronLayer.superlayer == nil else { return }
        chevronLayer.name = "FluentKit.RepeatButton.Chevron"
        chevronLayer.zPosition = 3
        layer?.addSublayer(chevronLayer)
    }

    private func updateChevron(animated: Bool) {
        guard let direction = chevronDirection else { return }
        let appearance = resolvedAppearance()
        let pointSize = max(8, systemImagePointSize ?? 10 * fluentControlSize.metricScale)
        let size = min(pointSize, max(0, bounds.height - 4))
        guard size > 0 else { return }
        chevronLayer.update(
            frame: NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size),
            color: appearance.foregroundColor,
            state: visualState.primaryControlState,
            direction: direction,
            backingScale: window?.backingScaleFactor,
            animated: animated && !reduceMotion
        )
    }

    private func updateElevationBorderGeometry(for appearance: FluentButtonAppearance) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: bounds,
            appearance: appearance,
            visualYAxis: .resolved(for: self.layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        )
        CATransaction.commit()
    }

    private func updateFocusGeometry(appearance: FluentButtonAppearance? = nil) {
        let appearance = appearance ?? resolvedAppearance()
        let focusRect = bounds.insetBy(dx: 2.5, dy: 2.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.frame = bounds
        focusLayer.path = CGPath(
            roundedRect: focusRect,
            cornerWidth: max(appearance.cornerRadius - 2, 0),
            cornerHeight: max(appearance.cornerRadius - 2, 0),
            transform: nil
        )
        focusLayer.strokeColor = appearance.focusRingColor?.cgColor
        focusLayer.lineWidth = appearance.focusRingWidth
        focusLayer.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
        CATransaction.commit()
    }

    deinit { stopRepeatTimer() }
}

public struct FluentRepeatButtonView: FluentUpdatablePrimitiveView {
    public let title: String
    public let systemImageName: String?
    public let systemImagePointSize: CGFloat?
    public let delay: TimeInterval
    public let interval: TimeInterval
    public let action: (() -> Void)?
    public let style: any FluentRepeatButtonStyle

    public init(
        _ title: String,
        systemImageName: String? = nil,
        systemImagePointSize: CGFloat? = nil,
        delay: TimeInterval = FluentRepeatButton.defaultDelay,
        interval: TimeInterval = FluentRepeatButton.defaultInterval,
        style: any FluentRepeatButtonStyle = FluentAutomaticRepeatButtonStyle(),
        action: (() -> Void)? = nil
    ) {
        precondition(delay >= 0, "FluentRepeatButtonView.delay cannot be negative")
        precondition(interval > 0, "FluentRepeatButtonView.interval must be positive")
        self.title = title
        self.systemImageName = systemImageName
        self.systemImagePointSize = systemImagePointSize
        self.delay = delay
        self.interval = interval
        self.action = action
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let button = FluentRepeatButton(
            title: title,
            systemImageName: systemImageName,
            systemImagePointSize: systemImagePointSize,
            delay: delay,
            interval: interval
        )
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.fluentStyle = style
        button.onClick = action
        return button
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentRepeatButton else { return false }
        button.title = title
        button.systemImageName = systemImageName
        button.systemImagePointSize = systemImagePointSize
        button.delay = delay
        button.interval = interval
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.fluentStyle = style
        button.onClick = action
        return true
    }

    public func repeatButtonStyle(_ style: any FluentRepeatButtonStyle) -> FluentRepeatButtonView {
        FluentRepeatButtonView(
            title,
            systemImageName: systemImageName,
            systemImagePointSize: systemImagePointSize,
            delay: delay,
            interval: interval,
            style: style,
            action: action
        )
    }
}

extension FluentRepeatButton: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        reduceMotion = context.reduceMotion
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentRepeatButton else { return false }
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.title = title
        button.systemImageName = systemImageName
        button.systemImagePointSize = systemImagePointSize
        button.delay = delay
        button.interval = interval
        button.onClick = onClick
        button.fluentStyle = fluentStyle
        button.fluentControlSize = fluentControlSize
        return true
    }
}
