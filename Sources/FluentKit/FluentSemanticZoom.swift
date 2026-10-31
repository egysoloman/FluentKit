import AppKit

/// Lets a zoomed-out view hand a destination back to its SemanticZoom.
public struct FluentSemanticZoomProxy {
    fileprivate weak var control: FluentSemanticZoomControl?

    /// Switches to the zoomed-in view, reporting `destination` (for example the group the user
    /// picked) through `onViewChangeCompleted` so the app can bring it into view.
    public func zoomIn(to destination: AnyHashable? = nil) {
        control?.setZoomedIn(true, destination: destination, animated: true)
    }

    public func zoomOut() {
        control?.setZoomedIn(false, destination: nil, animated: true)
    }
}

/// A WinUI-style SemanticZoom: one detailed (zoomed-in) and one overview (zoomed-out) view of the
/// same content. Views switch by pinching (touch screen or trackpad), Ctrl/⌘ with minus or plus,
/// optional Ctrl+wheel, an optional zoom-out button, or the zoomed-out view's proxy.
public struct FluentSemanticZoom<ZoomedIn: FluentView, ZoomedOut: FluentView>: FluentUpdatablePrimitiveView {
    private let isZoomedInViewActive: FluentBinding<Bool>?
    private let canChangeViews: Bool
    private let isZoomOutButtonEnabled: Bool
    private let allowsWheelZoom: Bool
    private let onViewChangeCompleted: ((Bool, AnyHashable?) -> Void)?
    private let zoomedIn: () -> ZoomedIn
    private let zoomedOut: (FluentSemanticZoomProxy) -> ZoomedOut

    public init(
        isZoomedInViewActive: FluentBinding<Bool>? = nil,
        canChangeViews: Bool = true,
        isZoomOutButtonEnabled: Bool = false,
        allowsWheelZoom: Bool = false,
        onViewChangeCompleted: ((Bool, AnyHashable?) -> Void)? = nil,
        @FluentViewBuilder zoomedInView: @escaping () -> ZoomedIn,
        @FluentViewBuilder zoomedOutView: @escaping (FluentSemanticZoomProxy) -> ZoomedOut
    ) {
        self.isZoomedInViewActive = isZoomedInViewActive
        self.canChangeViews = canChangeViews
        self.isZoomOutButtonEnabled = isZoomOutButtonEnabled
        self.allowsWheelZoom = allowsWheelZoom
        self.onViewChangeCompleted = onViewChangeCompleted
        zoomedIn = zoomedInView
        zoomedOut = zoomedOutView
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let control = FluentSemanticZoomControl(context: context)
        control.update(configuration: configuration(for: control), context: context)
        return control
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentSemanticZoomControl else { return false }
        control.update(configuration: configuration(for: control), context: context)
        return true
    }

    private func configuration(for control: FluentSemanticZoomControl) -> FluentSemanticZoomConfiguration {
        FluentSemanticZoomConfiguration(
            zoomedIn: FluentAnyView(zoomedIn()),
            zoomedOut: FluentAnyView(zoomedOut(FluentSemanticZoomProxy(control: control))),
            isZoomedInViewActive: isZoomedInViewActive,
            canChangeViews: canChangeViews,
            isZoomOutButtonEnabled: isZoomOutButtonEnabled,
            allowsWheelZoom: allowsWheelZoom,
            onViewChangeCompleted: onViewChangeCompleted
        )
    }
}

struct FluentSemanticZoomConfiguration {
    var zoomedIn: FluentAnyView
    var zoomedOut: FluentAnyView
    var isZoomedInViewActive: FluentBinding<Bool>?
    var canChangeViews: Bool
    var isZoomOutButtonEnabled: Bool
    var allowsWheelZoom: Bool
    var onViewChangeCompleted: ((Bool, AnyHashable?) -> Void)?
}

/// Source-derived metrics (`SemanticZoom_Partial.cpp`, generic.xaml).
enum FluentSemanticZoomMetrics {
    /// `_zoomMin` / `_zoomMax`: the ScrollViewer zoom range used while pinching.
    static let zoomMin: CGFloat = 0.5
    static let zoomMax: CGFloat = 1.0
    /// `_lowerThresholdDelta` / `_upperThresholdDelta`: a pinch must change the zoom by 5%.
    static let thresholdDelta: CGFloat = 0.05
    static let buttonSize: CGFloat = 12
    static let buttonMargin: CGFloat = 19
    /// The ZoomOutButtonVisible → Hidden transition begins after three seconds.
    static let buttonHideDelay: TimeInterval = 3
    static let transition = FluentMotionToken(duration: 0.25, curve: .controlFastOutSlowIn)
}

final class FluentSemanticZoomControl: NSView {
    override var isFlipped: Bool { true }

    private(set) var configuration: FluentSemanticZoomConfiguration?
    private var context: FluentRenderContext
    private(set) var zoomedInHost: FluentViewHost<FluentAnyView>?
    private(set) var zoomedOutHost: FluentViewHost<FluentAnyView>?
    let zoomOutButton = FluentSemanticZoomButton()
    private(set) var isZoomedIn = true
    private(set) var isTransitioning = false
    private(set) var pinchScale: CGFloat = 1
    private(set) var magnifyDriver: FluentMagnifyGestureDriver!
    private var observedBinding: FluentBinding<Bool>?
    private var observerID: UUID?
    private var observationGeneration: UInt64 = 0
    private var isWritingBinding = false
    private var buttonHideTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private let animationCoordinator = FluentAnimationCoordinator()
    private var transitionGeneration: UInt64 = 0
    private var lastWheelToggle: TimeInterval = 0

    init(context: FluentRenderContext) {
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.SemanticZoom")
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        zoomOutButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.SemanticZoom.ZoomOutButton")
        zoomOutButton.isHidden = true
        zoomOutButton.onPress = { [weak self] in self?.setZoomedIn(false, destination: nil, animated: true) }
        addSubview(zoomOutButton)
        animationCoordinator.reduceMotion = context.reduceMotion
        let driver = FluentMagnifyGestureDriver(view: self)
        driver.onBeginAllowed = { [weak self] in self?.canChangeViews ?? false }
        driver.onBegin = { [weak self] in self?.beginPinch() ?? false }
        driver.onChange = { [weak self] scale in self?.updatePinch(scale: scale) }
        driver.onEnd = { [weak self] scale in self?.endPinch(scale: scale) }
        driver.onCancel = { [weak self] in self?.endPinch(scale: 1) }
        magnifyDriver = driver
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        buttonHideTimer?.invalidate()
        removeObserver()
    }

    var canChangeViews: Bool { configuration?.canChangeViews ?? false }

    func update(configuration next: FluentSemanticZoomConfiguration, context: FluentRenderContext) {
        removeObserver()
        configuration = next
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        zoomedInHost = updateHost(zoomedInHost, with: next.zoomedIn, identifier: "FluentKit.SemanticZoom.ZoomedIn")
        zoomedOutHost = updateHost(zoomedOutHost, with: next.zoomedOut, identifier: "FluentKit.SemanticZoom.ZoomedOut")
        zoomOutButton.theme = context.theme
        if let requested = next.isZoomedInViewActive?.get(), requested != isZoomedIn {
            applyViewChange(zoomedIn: requested, destination: nil, animated: false, notify: false)
        } else {
            settlePresenters()
        }
        if !next.isZoomOutButtonEnabled { hideZoomOutButton() }
        installObserver()
        needsLayout = true
    }

    private func updateHost(_ host: FluentViewHost<FluentAnyView>?, with view: FluentAnyView, identifier: String) -> FluentViewHost<FluentAnyView> {
        if let host {
            host.update(view, context: context)
            return host
        }
        let created = FluentViewHost(view, context: context)
        created.identifier = NSUserInterfaceItemIdentifier(identifier)
        created.wantsLayer = true
        addSubview(created, positioned: .below, relativeTo: zoomOutButton)
        return created
    }

    override func layout() {
        super.layout()
        if !isTransitioning, pinchScale == 1 {
            zoomedInHost?.frame = bounds
            zoomedOutHost?.frame = bounds
        }
        let size = FluentSemanticZoomMetrics.buttonSize
        let margin = FluentSemanticZoomMetrics.buttonMargin
        let x = userInterfaceLayoutDirection == .rightToLeft ? margin : bounds.width - margin - size
        zoomOutButton.frame = NSRect(x: x, y: bounds.height - margin - size, width: size, height: size)
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: View changes

    /// `put_IsZoomedInViewActive`, honouring `CanChangeViews`.
    func setZoomedIn(_ zoomedIn: Bool, destination: AnyHashable?, animated: Bool) {
        guard canChangeViews, zoomedIn != isZoomedIn else { return }
        applyViewChange(zoomedIn: zoomedIn, destination: destination, animated: animated, notify: true)
    }

    private func applyViewChange(zoomedIn: Bool, destination: AnyHashable?, animated: Bool, notify: Bool) {
        let restoreFocus = window.map { window in
            (window.firstResponder as? NSView).map { $0.isDescendant(of: self) } ?? false
        } ?? false
        isZoomedIn = zoomedIn
        writeBinding()
        hideZoomOutButton()
        animateSwitch(animated: animated)
        if restoreFocus { window?.makeFirstResponder(activeHost?.nextValidKeyView ?? self) }
        if notify { configuration?.onViewChangeCompleted?(zoomedIn, destination) }
        updateAccessibility()
    }

    var activeHost: FluentViewHost<FluentAnyView>? { isZoomedIn ? zoomedInHost : zoomedOutHost }
    private var inactiveHost: FluentViewHost<FluentAnyView>? { isZoomedIn ? zoomedOutHost : zoomedInHost }

    /// ZoomInView / ZoomOutView: the outgoing view fades out while shrinking (zooming out) or
    /// growing (zooming in); the incoming view fades in from the opposite scale.
    private func animateSwitch(animated: Bool) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        guard animated, !context.reduceMotion, let incoming = activeHost?.layer, let outgoing = inactiveHost?.layer else {
            settlePresenters()
            return
        }
        isTransitioning = true
        activeHost?.isHidden = false
        inactiveHost?.isHidden = false
        let shrink = CATransform3DMakeScale(0.8, 0.8, 1)
        let grow = CATransform3DMakeScale(1.25, 1.25, 1)
        let outgoingEnd = isZoomedIn ? grow : shrink
        let incomingStart = isZoomedIn ? shrink : grow
        let pinchStart = CATransform3DMakeScale(pinchScale, pinchScale, 1)
        for host in [activeHost, inactiveHost] { centerAnchor(host?.layer) }
        animationCoordinator.animateTransition([
            FluentLayerAnimationChange(layer: outgoing, key: "fluent.sezo.out.opacity", keyPath: "opacity", toValue: 0) { outgoing.opacity = 0 },
            FluentLayerAnimationChange(layer: outgoing, key: "fluent.sezo.out.transform", keyPath: "transform",
                fromValue: NSValue(caTransform3D: pinchStart), toValue: NSValue(caTransform3D: outgoingEnd)) { outgoing.transform = outgoingEnd },
            FluentLayerAnimationChange(layer: incoming, key: "fluent.sezo.in.opacity", keyPath: "opacity", fromValue: 0, toValue: 1) { incoming.opacity = 1 },
            FluentLayerAnimationChange(layer: incoming, key: "fluent.sezo.in.transform", keyPath: "transform",
                fromValue: NSValue(caTransform3D: incomingStart), toValue: NSValue(caTransform3D: CATransform3DIdentity)) { incoming.transform = CATransform3DIdentity }
        ], motion: FluentSemanticZoomMetrics.transition, animated: true) { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.settlePresenters()
        }
        pinchScale = 1
    }

    private func centerAnchor(_ layer: CALayer?) {
        guard let layer else { return }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
    }

    private func settlePresenters() {
        isTransitioning = false
        pinchScale = 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for host in [zoomedInHost, zoomedOutHost].compactMap({ $0 }) {
            animationCoordinator.cancelAll(on: [host.layer].compactMap { $0 })
            host.layer?.removeAllAnimations()
            host.layer?.transform = CATransform3DIdentity
            host.layer?.opacity = 1
            host.frame = bounds
        }
        activeHost?.isHidden = false
        inactiveHost?.isHidden = true
        CATransaction.commit()
        updateAccessibility()
    }

    // MARK: Pinch

    @discardableResult
    func beginPinch() -> Bool {
        guard canChangeViews else { return false }
        if isTransitioning { settlePresenters() }
        hideZoomOutButton()
        centerAnchor(activeHost?.layer)
        return true
    }

    /// The active view follows the pinch within the ScrollViewer's 0.5…1 zoom range (the
    /// zoomed-out view mirrors it toward 1…2), easing out beyond it.
    func updatePinch(scale: CGFloat) {
        pinchScale = isZoomedIn
            ? max(FluentSemanticZoomMetrics.zoomMin, min(FluentSemanticZoomMetrics.zoomMax, scale))
            : max(FluentSemanticZoomMetrics.zoomMax, min(1 / FluentSemanticZoomMetrics.zoomMin, scale))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeHost?.layer?.transform = CATransform3DMakeScale(pinchScale, pinchScale, 1)
        CATransaction.commit()
    }

    /// A pinch past the 5% threshold switches views; anything less snaps back.
    func endPinch(scale: CGFloat) {
        let threshold = FluentSemanticZoomMetrics.thresholdDelta
        if isZoomedIn, scale < 1 - threshold {
            setZoomedIn(false, destination: nil, animated: true)
        } else if !isZoomedIn, scale > 1 + threshold {
            setZoomedIn(true, destination: nil, animated: true)
        } else {
            let layer = activeHost?.layer
            let from = CATransform3DMakeScale(pinchScale, pinchScale, 1)
            pinchScale = 1
            if let layer {
                animationCoordinator.animateTransition([
                    FluentLayerAnimationChange(layer: layer, key: "fluent.sezo.snap", keyPath: "transform",
                        fromValue: NSValue(caTransform3D: from), toValue: NSValue(caTransform3D: CATransform3DIdentity)) {
                        layer.transform = CATransform3DIdentity
                    }
                ], motion: FluentSemanticZoomMetrics.transition, animated: true)
            }
        }
    }

    override func magnify(with event: NSEvent) {
        if !magnifyDriver.handleMagnify(event) { super.magnify(with: event) }
    }

    // MARK: Keyboard and wheel

    /// `ScrollViewer::GetKeyboardMessageZoomAction`: Ctrl with minus/subtract zooms out and with
    /// plus/add zooms in. ⌘ is accepted as the macOS equivalent.
    static func zoomDirection(for event: NSEvent) -> Bool? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers == .control || modifiers == .command else { return nil }
        switch event.keyCode {
        case 27, 78: return false
        case 24, 69: return true
        default: return nil
        }
    }

    @discardableResult
    func handleZoomKey(_ event: NSEvent) -> Bool {
        guard canChangeViews, let zoomIn = Self.zoomDirection(for: event), zoomIn != isZoomedIn else { return false }
        FluentInputDeviceTracker.shared.record(.keyboard, in: window)
        setZoomedIn(zoomIn, destination: nil, animated: true)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let responder = window?.firstResponder as? NSView,
              responder === self || responder.isDescendant(of: self) else {
            return super.performKeyEquivalent(with: event)
        }
        return handleZoomKey(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleZoomKey(event) { super.keyDown(with: event) }
    }

    /// Ctrl+wheel switches views only when wheel zoom is enabled (WinUI: ScrollViewer.ZoomMode).
    override func scrollWheel(with event: NSEvent) {
        guard configuration?.allowsWheelZoom == true, canChangeViews,
              event.modifierFlags.contains(.control), event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        guard event.timestamp - lastWheelToggle > 0.3 else { return }
        lastWheelToggle = event.timestamp
        setZoomedIn(event.scrollingDeltaY > 0, destination: nil, animated: true)
    }

    // MARK: Zoom-out button

    /// `OnPointerMoved`: a mouse or pen pointer (never touch) shows the button in the zoomed-in view.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard event.subtype != .touch, FluentInputDeviceTracker.shared.lastDeviceType(in: window) != .touch else { return }
        showZoomOutButtonIfAllowed()
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    func showZoomOutButtonIfAllowed() {
        guard isZoomedIn, canChangeViews, configuration?.isZoomOutButtonEnabled == true, !isTransitioning else { return }
        zoomOutButton.isHidden = false
        buttonHideTimer?.invalidate()
        let timer = Timer(timeInterval: FluentSemanticZoomMetrics.buttonHideDelay, repeats: false) { [weak self] _ in
            guard let self, !self.zoomOutButton.isPointerOver else { return }
            self.hideZoomOutButton()
        }
        RunLoop.main.add(timer, forMode: .common)
        buttonHideTimer = timer
    }

    func hideZoomOutButton() {
        buttonHideTimer?.invalidate()
        buttonHideTimer = nil
        zoomOutButton.isHidden = true
    }

    // MARK: Binding

    private func writeBinding() {
        guard let binding = configuration?.isZoomedInViewActive, !isWritingBinding, binding.get() != isZoomedIn else { return }
        isWritingBinding = true
        binding.set(isZoomedIn)
        isWritingBinding = false
    }

    private func installObserver() {
        guard let binding = configuration?.isZoomedInViewActive else { return }
        let generation = observationGeneration
        observedBinding = binding
        observerID = binding.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observationGeneration == generation, !self.isWritingBinding,
                      let binding = self.configuration?.isZoomedInViewActive else { return }
                let requested = binding.get()
                if requested != self.isZoomedIn {
                    if self.canChangeViews {
                        self.applyViewChange(zoomedIn: requested, destination: nil, animated: true, notify: true)
                    } else {
                        self.writeBinding()
                    }
                }
            }
        }
    }

    private func removeObserver() {
        observationGeneration &+= 1
        if let observerID { observedBinding?.removeObserver(observerID) }
        observerID = nil
        observedBinding = nil
    }

    // MARK: Accessibility

    private func updateAccessibility() {
        let visible: [Any] = [activeHost].compactMap { $0 } + (zoomOutButton.isHidden ? [] : [zoomOutButton])
        setAccessibilityChildren(visible)
    }
}

/// The 12×12 zoom-out button (`ZoomOutButton`, glyph E0B8) shown at the bottom trailing corner.
final class FluentSemanticZoomButton: NSView {
    var onPress: (() -> Void)?
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    private(set) var isPointerOver = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        fluentSetDefaultAccessibilityLabel("Zoom out")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        (isPressed ? theme.controlFillTertiary : isPointerOver ? theme.controlFillSecondary : theme.controlFill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
        theme.textPrimary.setFill()
        let bar = NSRect(x: bounds.midX - 3, y: bounds.midY - 0.5, width: 6, height: 1)
        bar.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; isPressed = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { isPressed = true; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
