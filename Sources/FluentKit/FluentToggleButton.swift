import AppKit

public enum FluentToggleButtonState: Hashable, Sendable {
    case off
    case on
    case mixed

    fileprivate func next(allowsMixedState: Bool) -> FluentToggleButtonState {
        switch self {
        case .off: return .on
        case .on: return allowsMixedState ? .mixed : .off
        case .mixed: return .off
        }
    }

    fileprivate var accessibilityValue: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .mixed: return "Mixed"
        }
    }
}

public struct FluentToggleButtonStyleConfiguration {
    public let title: String
    public let selectionState: FluentToggleButtonState
    public let controlState: FluentControlState
    public let isEnabled: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(
        title: String,
        selectionState: FluentToggleButtonState,
        controlState: FluentControlState,
        isEnabled: Bool,
        controlSize: FluentControlSize,
        theme: FluentTheme
    ) {
        self.title = title
        self.selectionState = selectionState
        self.controlState = controlState
        self.isEnabled = isEnabled
        self.controlSize = controlSize
        self.theme = theme
    }
}

public protocol FluentToggleButtonStyle {
    func appearance(for configuration: FluentToggleButtonStyleConfiguration) -> FluentButtonAppearance
}

/// WinUI ToggleButton resources mapped onto FluentKit's shared Button chrome.
public struct FluentAutomaticToggleButtonStyle: FluentToggleButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentToggleButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let isChecked = configuration.selectionState == .on
        let usesElevationBorder = state == .normal || state == .pointerOver || state == .focused

        if isChecked {
            let elevation = theme.accentElevationBorderColors
            let foreground: NSColor = switch state {
            case .pressed: theme.textOnAccentSecondary
            case .disabled: theme.textOnAccentDisabled
            default: theme.textOnAccent
            }
            return FluentButtonAppearance(
                backgroundColor: theme.accentFill(for: state),
                foregroundColor: foreground,
                borderColor: usesElevationBorder ? (elevation.last ?? .clear) : .clear,
                borderGradientColors: usesElevationBorder ? elevation : nil,
                borderGradientEdge: .bottom,
                borderWidth: theme.controlStrokeWidth,
                cornerRadius: theme.buttonCornerRadius,
                contentInsets: theme.controlPadding,
                focusRingColor: theme.accent,
                focusRingWidth: theme.focusStrokeWidth
            )
        }

        return FluentButtonAppearance(
            backgroundColor: theme.buttonBackground(for: state),
            foregroundColor: theme.buttonForeground(for: state),
            borderColor: theme.controlStrokeDefault,
            borderGradientColors: usesElevationBorder ? theme.controlElevationBorderColors : nil,
            borderGradientEdge: .bottom,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            contentInsets: theme.controlPadding,
            focusRingColor: theme.accent,
            focusRingWidth: theme.focusStrokeWidth
        )
    }
}

public extension FluentToggleButtonStyle where Self == FluentAutomaticToggleButtonStyle {
    static var automatic: FluentAutomaticToggleButtonStyle { FluentAutomaticToggleButtonStyle() }
}

public final class FluentToggleButton: NSControl, FluentControlSizeConfigurable {
    public var theme: FluentTheme = .current {
        didSet {
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: any FluentToggleButtonStyle = FluentAutomaticToggleButtonStyle() {
        didSet {
            refreshAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            visualStateCoordinator.reduceMotion = reduceMotion
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
    public var selectionState: FluentToggleButtonState {
        didSet {
            guard oldValue != selectionState else { return }
            setAccessibilityValue(selectionState.accessibilityValue)
            refreshAppearance(animated: true)
            guard !suppressesValueNotification else { return }
            sendAction(action, to: target)
            onValueChanged?(selectionState)
        }
    }
    public var allowsMixedState: Bool {
        didSet {
            guard oldValue != allowsMixedState else { return }
            if !allowsMixedState, selectionState == .mixed { selectionState = .off }
        }
    }
    public var onValueChanged: ((FluentToggleButtonState) -> Void)?

    private let visualStateCoordinator = FluentVisualStateCoordinator()
    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private var pointerTrackingArea: NSTrackingArea?
    private var isPointerOver = false
    private var isPointerPressed = false
    private var isKeyboardPressed = false
    private var suppressesValueNotification = false

    public override var acceptsFirstResponder: Bool { isEnabled }

    public init(
        title: String = "Toggle button",
        state: FluentToggleButtonState = .off,
        allowsMixedState: Bool = false
    ) {
        self.title = title
        selectionState = state
        self.allowsMixedState = allowsMixedState
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        title = "Toggle button"
        selectionState = .off
        allowsMixedState = false
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let font = resolvedFont
        let text = (title as NSString).size(withAttributes: [.font: font])
        return NSSize(
            width: ceil(text.width + appearance.contentInsets.left + appearance.contentInsets.right),
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
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let font = resolvedFont
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
        refreshAppearance(animated: true)
    }

    public override func mouseMoved(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != isPointerOver else { return }
        isPointerOver = inside
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
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        isPointerPressed = true
        refreshAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isPointerPressed else { return }
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        refreshAppearance(animated: true)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isPointerPressed else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPointerPressed = false
        isPointerOver = inside
        if inside {
            advanceSelection()
        } else {
            refreshAppearance(animated: true)
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 36, 49:
            guard !event.isARepeat, !isKeyboardPressed else { return }
            isKeyboardPressed = true
            refreshAppearance(animated: true)
        case 53:
            cancelInteraction()
        default:
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard isEnabled else { return }
        switch event.keyCode {
        case 36 where isKeyboardPressed,
             49 where isKeyboardPressed:
            isKeyboardPressed = false
            advanceSelection()
        default:
            super.keyUp(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) { cancelInteraction() }

    public override func accessibilityValue() -> Any? { selectionState.accessibilityValue }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        cancelInteraction(refresh: false)
        advanceSelection()
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
        refreshAppearance(animated: false)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    public func setStateFromBinding(_ state: FluentToggleButtonState) {
        cancelInteraction(refresh: false)
        suppressesValueNotification = true
        selectionState = allowsMixedState || state != .mixed ? state : .off
        suppressesValueNotification = false
        refreshAppearance(animated: false)
    }

    private var resolvedFont: NSFont {
        let body = theme.typography.font(for: .body)
        return body.withSize(body.pointSize * fluentControlSize.metricScale)
    }

    private var visualState: FluentVisualState {
        var result: FluentVisualState = isEnabled ? .normal : .disabled
        switch selectionState {
        case .off: break
        case .on: result.insert(.selected)
        case .mixed: result.insert(.indeterminate)
        }
        guard isEnabled else { return result }
        if (isPointerPressed && isPointerOver) || isKeyboardPressed {
            result.insert(.pressed)
        } else if isPointerOver {
            result.insert(.pointerOver)
        } else if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            result.insert(.focused)
        }
        return result
    }

    private func resolvedAppearance() -> FluentButtonAppearance {
        resolvedAppearance(for: visualState)
    }

    private func resolvedAppearance(for state: FluentVisualState) -> FluentButtonAppearance {
        fluentStyle.appearance(
            for: FluentToggleButtonStyleConfiguration(
                title: title,
                selectionState: selectionState,
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
        setAccessibilityRole(.checkBox)
        setAccessibilityTitle(title)
        setAccessibilityValue(selectionState.accessibilityValue)
        setAccessibilityEnabled(isEnabled)

        elevationBorderLayer.name = "FluentKit.ToggleButton.ElevationBorder"
        elevationBorderLayer.zPosition = 1
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        layer?.addSublayer(elevationBorderLayer)

        focusLayer.name = "FluentKit.ToggleButton.FocusRing"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.zPosition = 2
        focusLayer.opacity = 0
        layer?.addSublayer(focusLayer)
        refreshAppearance(animated: false)
    }

    private func advanceSelection() {
        selectionState = selectionState.next(allowsMixedState: allowsMixedState)
    }

    private func cancelInteraction(refresh: Bool = true) {
        guard isPointerPressed || isKeyboardPressed else { return }
        isPointerPressed = false
        isKeyboardPressed = false
        if refresh { refreshAppearance(animated: true) }
    }

    private func refreshAppearance(animated: Bool) {
        visualStateCoordinator.reduceMotion = reduceMotion
        let next = visualState
        visualStateCoordinator.transition(
            to: next,
            animated: animated,
            motion: FluentMotion.controlFaster
        ) { [weak self] transition in
            self?.applyVisualState(transition)
        }
    }

    private func applyVisualState(_ transition: FluentVisualStateTransition) {
        guard let layer else { return }
        let appearance = resolvedAppearance(for: transition.to)
        let previousBackground = (layer.presentation() ?? layer).backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = appearance.backgroundColor.cgColor
        layer.cornerRadius = appearance.cornerRadius
        elevationBorderLayer.colors = (appearance.borderGradientColors
            ?? [appearance.borderColor, appearance.borderColor]).map(\.cgColor)
        CATransaction.commit()
        if transition.isAnimated, let previousBackground {
            let backgroundAnimation = CABasicAnimation(keyPath: "backgroundColor")
            backgroundAnimation.fromValue = previousBackground
            backgroundAnimation.toValue = appearance.backgroundColor.cgColor
            backgroundAnimation.duration = transition.motion.duration
            backgroundAnimation.timingFunction = transition.motion.curve.timingFunction
            layer.add(backgroundAnimation, forKey: "fluent.toggleButton.background")
        }
        updateElevationBorderGeometry(for: appearance)
        updateFocusGeometry(appearance: appearance)
        needsDisplay = true
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
}

private final class FluentToggleButtonHost: NSView {
    let button: FluentToggleButton
    private var binding: FluentBinding<FluentToggleButtonState>
    private var observerID: UUID?
    private var isApplyingBinding = false

    init(
        title: String,
        binding: FluentBinding<FluentToggleButtonState>,
        allowsMixedState: Bool,
        style: any FluentToggleButtonStyle,
        context: FluentRenderContext
    ) {
        self.binding = binding
        button = FluentToggleButton(
            title: title,
            state: binding.get(),
            allowsMixedState: allowsMixedState
        )
        super.init(frame: .zero)
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.fluentStyle = style
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        button.onValueChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.binding.set(value)
        }
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { button.intrinsicContentSize }

    func update(
        title: String,
        binding: FluentBinding<FluentToggleButtonState>,
        allowsMixedState: Bool,
        style: any FluentToggleButtonStyle,
        context: FluentRenderContext
    ) {
        removeObserver()
        self.binding = binding
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.title = title
        button.allowsMixedState = allowsMixedState
        button.fluentStyle = style
        let value = binding.get()
        if button.selectionState != value { button.setStateFromBinding(value) }
        installObserver()
        invalidateIntrinsicContentSize()
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.button.selectionState != value else { return }
                self.isApplyingBinding = true
                self.button.setStateFromBinding(value)
                self.isApplyingBinding = false
            }
        }
    }

    private func removeObserver() {
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    deinit { removeObserver() }
}

public struct FluentToggleButtonView: FluentUpdatablePrimitiveView {
    public let title: String
    public let state: FluentBinding<FluentToggleButtonState>
    public let allowsMixedState: Bool
    public let style: any FluentToggleButtonStyle

    public init(
        _ title: String,
        isOn: FluentBinding<Bool>,
        style: any FluentToggleButtonStyle = FluentAutomaticToggleButtonStyle()
    ) {
        self.title = title
        state = isOn.map(
            { $0 ? .on : .off },
            { $0 == .on }
        )
        allowsMixedState = false
        self.style = style
    }

    public init(
        _ title: String,
        state: FluentBinding<FluentToggleButtonState>,
        allowsMixedState: Bool = true,
        style: any FluentToggleButtonStyle = FluentAutomaticToggleButtonStyle()
    ) {
        self.title = title
        self.state = state
        self.allowsMixedState = allowsMixedState
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentToggleButtonHost(
            title: title,
            binding: state,
            allowsMixedState: allowsMixedState,
            style: style,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentToggleButtonHost else { return false }
        host.update(
            title: title,
            binding: state,
            allowsMixedState: allowsMixedState,
            style: style,
            context: context
        )
        return true
    }

    public func toggleButtonStyle(_ style: any FluentToggleButtonStyle) -> FluentToggleButtonView {
        FluentToggleButtonView(
            title,
            state: state,
            allowsMixedState: allowsMixedState,
            style: style
        )
    }
}

extension FluentToggleButton: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        reduceMotion = context.reduceMotion
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentToggleButton else { return false }
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.title = title
        button.selectionState = selectionState
        button.allowsMixedState = allowsMixedState
        button.fluentStyle = fluentStyle
        button.fluentControlSize = fluentControlSize
        return true
    }
}
