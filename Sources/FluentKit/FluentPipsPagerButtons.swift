import AppKit

/// Native mouse tracking owns capture/highlight; Fluent owns keyboard release activation,
/// cancellation generations and the separately rendered foreground/chrome layers.
class FluentPipsPagerButton: NSButton, FluentControlSizeConfigurable {
    var theme: FluentTheme = .current { didSet { if oldValue != theme { refreshAppearance(animated: false) } } }
    var reduceMotion = false {
        didSet {
            guard oldValue != reduceMotion else { return }
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion { removeVisualAnimations() }
            refreshAppearance(animated: false)
        }
    }
    var fluentControlSize: FluentControlSize = .regular {
        didSet { if oldValue != fluentControlSize { refreshAppearance(animated: false) } }
    }
    var onFocusChanged: (() -> Void)?
    weak var hoverCoordinator: FluentHoverCoordinator<FluentPipsPagerButton>?
    private(set) var pointerOver = false
    private var generation: UInt64 = 0
    private var trackingGeneration: UInt64?
    private var pointerInvoked = false
    private var pressedKey: UInt16?
    private var windowObservers: [NSObjectProtocol] = []
    private lazy var trackingHost = FluentTrackingAreaHost(view: self,
        options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect])
    let animationCoordinator = FluentAnimationCoordinator(reduceMotion: false)

    var pressed: Bool {
        isEnabled && (pressedKey != nil || (trackingGeneration == generation && isHighlighted))
    }
    var canReceiveInput: Bool { isEnabled && window?.isVisible == true && !isHiddenOrHasHiddenAncestor }
    override var acceptsFirstResponder: Bool { isEnabled }

    init() {
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        title = ""
        target = self
        action = #selector(invoke)
        focusRingType = .none
        wantsLayer = true
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() { super.layout(); refreshAppearance(animated: false) }
    override func setFrameSize(_ size: NSSize) { super.setFrameSize(size); refreshAppearance(animated: false) }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refreshAppearance(animated: false) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); trackingHost.update() }

    override func draw(_ dirtyRect: NSRect) {
        if trackingGeneration == generation { updateHover(isHighlighted || pointerInvoked) }
        refreshAppearance(animated: true)
    }

    func setPointerHover(_ value: Bool) {
        guard pointerOver != value else { return }
        pointerOver = value
        refreshAppearance(animated: true)
    }

    private func updateHover(_ value: Bool) {
        if let hoverCoordinator { hoverCoordinator.update(self, hovering: value) }
        else { setPointerHover(value) }
    }

    override func mouseEntered(with event: NSEvent) { if canReceiveInput { updateHover(true) } }
    override func mouseMoved(with event: NSEvent) {
        if canReceiveInput { updateHover(visibleRect.contains(convert(event.locationInWindow, from: nil))) }
    }
    override func mouseExited(with event: NSEvent) { updateHover(false) }

    override func mouseDown(with event: NSEvent) {
        guard canReceiveInput, visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        pressedKey = nil
        let captured = generation
        trackingGeneration = captured
        pointerInvoked = false
        updateHover(true)
        defer {
            let retainHover = generation == captured && pointerInvoked
            trackingGeneration = nil
            pointerInvoked = false
            highlight(false)
            updateHover(retainHover)
            refreshAppearance(animated: generation == captured)
            if generation != captured { removeVisualAnimations() }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, !isHiddenOrHasHiddenAncestor else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        if [UInt16(49), 36, 76].contains(event.keyCode) {
            guard canReceiveInput, !event.isARepeat, pressedKey == nil, trackingGeneration == nil else { return }
            pressedKey = event.keyCode
            refreshAppearance(animated: true)
            return
        }
        pressedKey = nil
        refreshAppearance(animated: true)
        if event.keyCode == 53 { cancelOperation(nil); return }
        if handleNavigationKey(event.keyCode) { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard [UInt16(49), 36, 76].contains(event.keyCode) else { super.keyUp(with: event); return }
        guard pressedKey == event.keyCode else { return }
        pressedKey = nil
        refreshAppearance(animated: true)
        if canReceiveInput { performInvocation() }
    }

    func handleNavigationKey(_ keyCode: UInt16) -> Bool { false }
    func performInvocation() {}
    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        cancelInteraction()
        performInvocation()
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
    @objc private func invoke() {
        guard isEnabled else { return }
        if let trackingGeneration {
            guard trackingGeneration == generation, canReceiveInput else { return }
            pointerInvoked = true
            updateHover(true)
        }
        performInvocation()
    }

    override func cancelOperation(_ sender: Any?) { cancelInteraction() }
    func cancelInteraction() {
        generation &+= 1
        pressedKey = nil
        highlight(false)
        updateHover(false)
        refreshAppearance(animated: false)
        removeVisualAnimations()
    }
    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled { cancelInteraction() }
            else { refreshAppearance(animated: false) }
            setAccessibilityEnabled(isEnabled)
        }
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { cancelInteraction(); focusChanged() }
        return accepted
    }
    private func focusChanged() {
        refreshAppearance(animated: false)
        onFocusChanged?()
        DispatchQueue.main.async { [weak self] in self?.refreshAppearance(animated: false) }
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { cancelInteraction() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelInteraction() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() { super.viewDidHide(); cancelInteraction() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                    queue: .main) { [weak self] _ in self?.cancelInteraction() })
            }
        }
        refreshAppearance(animated: false)
    }

    func refreshAppearance(animated: Bool) {}
    func removeVisualAnimations() { animationCoordinator.cancelAll(on: [layer].compactMap { $0 }) }
    func animate(_ changes: [FluentLayerAnimationChange], animated: Bool) {
        animationCoordinator.reduceMotion = reduceMotion
        animationCoordinator.animateState(changes,
            motion: FluentMotionToken(duration: FluentAnimation.stateChange, curve: .controlFastOutSlowIn),
            animated: animated && canReceiveInput)
    }
    func updateFocus(_ focus: CAShapeLayer) {
        focus.frame = bounds.insetBy(dx: 1, dy: 1)
        focus.path = CGPath(roundedRect: focus.bounds,
            cornerWidth: theme.designTokens.controlCornerRadius * fluentControlSize.metricScale,
            cornerHeight: theme.designTokens.controlCornerRadius * fluentControlSize.metricScale, transform: nil)
        focus.fillColor = NSColor.clear.cgColor
        focus.strokeColor = theme.focusStrokeOuter.cgColor
        focus.lineWidth = theme.focusStrokeWidth
        focus.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
    }
    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
}

final class FluentPipsPagerPipButton: FluentPipsPagerButton {
    var index: Int
    var isSelectedPip = false { didSet { if oldValue != isSelectedPip { refreshAppearance(animated: true) } } }
    var orientation: FluentPipsPagerOrientation = .horizontal
    var onInvoke: ((Int) -> Void)?
    var onNavigationKey: ((UInt16, Int) -> Bool)?
    private let chromeLayer = CALayer()
    private let glyphLayer = CAShapeLayer()
    private let focusLayer = CAShapeLayer()

    init(index: Int) {
        self.index = index
        super.init()
        chromeLayer.name = "FluentKit.PipsPager.PipChrome"
        glyphLayer.name = "FluentKit.PipsPager.PipGlyph"
        focusLayer.name = "FluentKit.PipsPager.PipFocus"
        [chromeLayer, glyphLayer, focusLayer].forEach { layer?.addSublayer($0) }
        setAccessibilityRole(.radioButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityValue() -> Any? { isSelectedPip ? 1 : 0 }
    override func performInvocation() { onInvoke?(index) }
    override func handleNavigationKey(_ keyCode: UInt16) -> Bool { onNavigationKey?(keyCode, index) ?? false }

    override func refreshAppearance(animated: Bool) {
        guard layer != nil, bounds.width > 0, bounds.height > 0 else { return }
        let state: FluentControlState = !isEnabled ? .disabled : pressed ? .pressed : pointerOver ? .pointerOver : isSelectedPip ? .selected : .normal
        let scale = fluentControlSize.metricScale
        let side: CGFloat = (pressed ? 4 : (isSelectedPip || pointerOver) ? 6 : 4) * scale
        let localBounds = CGRect(x: 0, y: 0, width: 12 * scale, height: 12 * scale)
        let path = CGPath(ellipseIn: CGRect(x: localBounds.midX - side / 2, y: localBounds.midY - side / 2,
            width: side, height: side), transform: nil)
        let background = theme.pipsPagerIndicatorBackground(selected: isSelectedPip, state: state).cgColor
        let foreground = theme.pipsPagerIndicatorForeground(selected: isSelectedPip, state: state).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        chromeLayer.frame = bounds
        chromeLayer.cornerRadius = theme.designTokens.controlCornerRadius * scale
        chromeLayer.borderWidth = theme.isHighContrast ? theme.controlStrokeWidth : 0
        chromeLayer.borderColor = background
        glyphLayer.bounds = localBounds
        glyphLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateFocus(focusLayer)
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        [chromeLayer, glyphLayer, focusLayer].forEach { $0.contentsScale = backingScale }
        CATransaction.commit()
        var changes: [FluentLayerAnimationChange] = []
        if chromeLayer.backgroundColor != background {
            changes.append(FluentLayerAnimationChange(layer: chromeLayer, key: "fluent.pips.background", keyPath: "backgroundColor",
                toValue: background) { [weak self] in self?.chromeLayer.backgroundColor = background })
        }
        if glyphLayer.path?.boundingBox != path.boundingBox {
            changes.append(FluentLayerAnimationChange(layer: glyphLayer, key: "fluent.pips.glyph", keyPath: "path",
                toValue: path) { [weak self] in self?.glyphLayer.path = path })
        }
        if glyphLayer.fillColor != foreground {
            changes.append(FluentLayerAnimationChange(layer: glyphLayer, key: "fluent.pips.foreground", keyPath: "fillColor",
                toValue: foreground) { [weak self] in self?.glyphLayer.fillColor = foreground })
        }
        animate(changes, animated: animated)
    }
    override func removeVisualAnimations() {
        animationCoordinator.cancelAll(on: [layer, chromeLayer, glyphLayer, focusLayer].compactMap { $0 })
    }
}

final class FluentPipsPagerNavigationButton: FluentPipsPagerButton {
    var direction: FluentChevronDirection = .left {
        didSet { if oldValue != direction { refreshAppearance(animated: false) } }
    }
    var onInvoke: (() -> Void)?
    var onNavigationKey: ((UInt16) -> Bool)?
    private let chromeLayer = CALayer()
    private let iconLayer = CALayer()
    private let chevronLayer = FluentChevronPrimitiveLayer()
    private let focusLayer = CAShapeLayer()

    override init() {
        super.init()
        chromeLayer.name = "FluentKit.PipsPager.NavigationChrome"
        iconLayer.name = "FluentKit.PipsPager.NavigationIcon"
        chevronLayer.name = "FluentKit.PipsPager.NavigationChevron"
        focusLayer.name = "FluentKit.PipsPager.NavigationFocus"
        [chromeLayer, iconLayer, focusLayer].forEach { layer?.addSublayer($0) }
        iconLayer.addSublayer(chevronLayer)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func performInvocation() { onInvoke?() }
    override func handleNavigationKey(_ keyCode: UInt16) -> Bool { onNavigationKey?(keyCode) ?? false }

    override func refreshAppearance(animated: Bool) {
        guard layer != nil, bounds.width > 0, bounds.height > 0 else { return }
        let state: FluentControlState = !isEnabled ? .disabled : pressed ? .pressed : pointerOver ? .pointerOver : .normal
        let scale = fluentControlSize.metricScale
        let background = theme.pipsPagerNavigationBackground(for: state).cgColor
        let foreground = theme.pipsPagerNavigationForeground(for: state)
        let transform = pressed ? CATransform3DMakeScale(FluentPipsPager.Metrics.navigationPressedScale,
            FluentPipsPager.Metrics.navigationPressedScale, 1) : CATransform3DIdentity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        chromeLayer.frame = bounds
        chromeLayer.cornerRadius = theme.designTokens.controlCornerRadius * scale
        chromeLayer.borderWidth = theme.isHighContrast ? theme.controlStrokeWidth : 0
        chromeLayer.borderColor = theme.isHighContrast ? theme.controlStrokeStrong.cgColor : NSColor.clear.cgColor
        iconLayer.bounds = CGRect(x: 0, y: 0, width: 10 * scale, height: 10 * scale)
        iconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateFocus(focusLayer)
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        [chromeLayer, iconLayer, focusLayer].forEach { $0.contentsScale = backingScale }
        CATransaction.commit()
        var changes: [FluentLayerAnimationChange] = []
        if chromeLayer.backgroundColor != background {
            changes.append(FluentLayerAnimationChange(layer: chromeLayer, key: "fluent.pips.background", keyPath: "backgroundColor",
                toValue: background) { [weak self] in self?.chromeLayer.backgroundColor = background })
        }
        if !CATransform3DEqualToTransform(iconLayer.transform, transform) {
            changes.append(FluentLayerAnimationChange(layer: iconLayer, key: "fluent.pips.scale", keyPath: "transform",
                toValue: NSValue(caTransform3D: transform)) { [weak self] in self?.iconLayer.transform = transform })
        }
        animate(changes, animated: animated)
        chevronLayer.update(frame: iconLayer.bounds, color: foreground, state: state, direction: direction,
            inverted: !isFlipped, backingScale: backingScale,
            preservingUnchangedAnimations: canReceiveInput && !reduceMotion, reduceMotion: reduceMotion,
            animated: animated && canReceiveInput)
    }
    override func removeVisualAnimations() {
        animationCoordinator.cancelAll(on: [layer, chromeLayer, iconLayer, focusLayer].compactMap { $0 })
        chevronLayer.finishAnimations()
    }
}
