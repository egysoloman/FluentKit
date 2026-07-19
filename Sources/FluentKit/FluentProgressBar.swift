import AppKit

public enum FluentProgressState: Hashable, Sendable {
    case normal
    case paused
    case error
}

public final class FluentProgressBar: NSView {
    public var theme: FluentTheme = .current {
        didSet { refreshAppearance(animatedColor: false) }
    }
    public var fluentStyle: any FluentProgressStyle = FluentAutomaticProgressStyle() {
        didSet {
            guard !isApplyingDeclarativeConfiguration else { return }
            refreshAppearance(animatedColor: false)
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            visualStateCoordinator.reduceMotion = reduceMotion
            if reduceMotion { removeVisualAnimations() }
            refreshVisualState(animated: false)
        }
    }
    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            lastLayoutDirection = nil
            needsLayout = true
        }
    }
    public var isIndeterminate: Bool {
        didSet {
            guard oldValue != isIndeterminate, !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityValue()
            refreshVisualState(animated: true)
        }
    }
    public var progressState: FluentProgressState {
        didSet {
            guard oldValue != progressState, !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityValue()
            refreshAppearance(animatedColor: true)
            refreshVisualState(animated: true)
        }
    }
    public var value: Double {
        get { progressValue }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard progressValue != clamped else { return }
            progressValue = clamped
            guard !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityValue()
            updateDeterminateGeometry(animated: !isIndeterminate)
        }
    }

    private struct LayoutMetrics: Equatable {
        let trackHeight: CGFloat
        let indicatorHeight: CGFloat
        let trackCornerRadius: CGFloat
        let indicatorCornerRadius: CGFloat
        let borderWidth: CGFloat
    }

    private let trackLayer = CALayer()
    private let determinateLayer = CALayer()
    private let primaryIndeterminateLayer = CALayer()
    private let secondaryIndeterminateLayer = CALayer()
    private var progressValue: Double
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?
    private var lastLayoutMetrics: LayoutMetrics?
    private var isApplyingDeclarativeConfiguration = false
    private let visualStateCoordinator: FluentVisualStateCoordinator

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    public init(
        value: Double = 0,
        isIndeterminate: Bool = false,
        state: FluentProgressState = .normal
    ) {
        progressValue = min(max(value, 0), 1)
        self.isIndeterminate = isIndeterminate
        progressState = state
        visualStateCoordinator = FluentVisualStateCoordinator()
        super.init(frame: .zero)
        visualStateCoordinator.reduceMotion = reduceMotion
        configureView()
    }

    required init?(coder: NSCoder) {
        progressValue = 0
        isIndeterminate = false
        progressState = .normal
        visualStateCoordinator = FluentVisualStateCoordinator()
        super.init(coder: coder)
        visualStateCoordinator.reduceMotion = reduceMotion
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        return NSSize(width: 180, height: max(appearance.trackHeight, appearance.indicatorHeight))
    }

    public override func layout() {
        super.layout()
        let appearance = resolvedAppearance()
        let metrics = layoutMetrics(for: appearance)
        let direction = userInterfaceLayoutDirection
        guard bounds.size != lastLayoutSize
            || direction != lastLayoutDirection
            || metrics != lastLayoutMetrics else { return }

        lastLayoutSize = bounds.size
        lastLayoutDirection = direction
        lastLayoutMetrics = metrics
        removeGeometryAnimations()
        applyLayerGeometry(appearance)
        refreshVisualState(animated: false)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard isIndeterminate, progressState == .normal, !reduceMotion else { return }
        startIndeterminateAnimation()
    }

    func applyDeclarativeConfiguration(from source: FluentProgressBar) {
        let valueChanged = progressValue != source.progressValue
        let modeChanged = isIndeterminate != source.isIndeterminate
        let stateChanged = progressState != source.progressState

        isApplyingDeclarativeConfiguration = true
        progressValue = source.progressValue
        isIndeterminate = source.isIndeterminate
        progressState = source.progressState
        fluentStyle = source.fluentStyle
        isApplyingDeclarativeConfiguration = false

        refreshAppearance(animatedColor: stateChanged)
        updateAccessibilityValue()
        if modeChanged || stateChanged {
            refreshVisualState(animated: true)
        } else if valueChanged {
            updateDeterminateGeometry(animated: !isIndeterminate)
        }
    }

    @discardableResult
    public func progressStyle(_ style: any FluentProgressStyle) -> FluentProgressBar {
        fluentStyle = style
        return self
    }

    private func configureView() {
        wantsLayer = true
        layer?.masksToBounds = true

        trackLayer.name = "FluentKit.ProgressBar.Track"
        determinateLayer.name = "FluentKit.ProgressBar.Determinate"
        primaryIndeterminateLayer.name = "FluentKit.ProgressBar.Indeterminate.Primary"
        secondaryIndeterminateLayer.name = "FluentKit.ProgressBar.Indeterminate.Secondary"
        [trackLayer, determinateLayer, primaryIndeterminateLayer, secondaryIndeterminateLayer].forEach {
            layer?.addSublayer($0)
        }

        setAccessibilityRole(.progressIndicator)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(1)
        updateAccessibilityValue()
        refreshAppearance(animatedColor: false)
    }

    private func resolvedAppearance() -> FluentProgressAppearance {
        fluentStyle.appearance(
            for: FluentProgressStyleConfiguration(
                valueFraction: progressValue,
                isIndeterminate: isIndeterminate,
                state: progressState,
                theme: theme
            )
        )
    }

    private func layoutMetrics(for appearance: FluentProgressAppearance) -> LayoutMetrics {
        LayoutMetrics(
            trackHeight: appearance.trackHeight,
            indicatorHeight: appearance.indicatorHeight,
            trackCornerRadius: appearance.trackCornerRadius,
            indicatorCornerRadius: appearance.cornerRadius,
            borderWidth: appearance.borderWidth
        )
    }

    private func refreshAppearance(animatedColor: Bool) {
        let appearance = resolvedAppearance()
        let metrics = layoutMetrics(for: appearance)
        if lastLayoutMetrics != metrics {
            lastLayoutMetrics = nil
            needsLayout = true
            invalidateIntrinsicContentSize()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.backgroundColor = appearance.trackColor.cgColor
        layer?.borderColor = appearance.borderColor.cgColor
        layer?.borderWidth = appearance.borderWidth
        trackLayer.cornerRadius = appearance.trackCornerRadius
        determinateLayer.cornerRadius = appearance.cornerRadius
        primaryIndeterminateLayer.cornerRadius = appearance.cornerRadius
        secondaryIndeterminateLayer.cornerRadius = appearance.cornerRadius
        CATransaction.commit()
        updateIndicatorColor(appearance.progressColor, animated: animatedColor)
    }

    private func applyLayerGeometry(_ appearance: FluentProgressAppearance) {
        let trackY = bounds.midY - appearance.trackHeight / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = NSRect(x: 0, y: trackY, width: bounds.width, height: appearance.trackHeight)
        configureDeterminateModelGeometry(appearance)
        configureIndeterminateModelGeometry(appearance)
        CATransaction.commit()
    }

    private func configureDeterminateModelGeometry(_ appearance: FluentProgressAppearance) {
        let width = bounds.width * CGFloat(progressValue)
        determinateLayer.anchorPoint = CGPoint(x: isRTL ? 1 : 0, y: 0.5)
        determinateLayer.bounds = CGRect(x: 0, y: 0, width: width, height: appearance.indicatorHeight)
        determinateLayer.position = CGPoint(x: isRTL ? bounds.maxX : bounds.minX, y: bounds.midY)
    }

    private func configureIndeterminateModelGeometry(_ appearance: FluentProgressAppearance) {
        let primaryWidth = bounds.width * 0.4
        let secondaryWidth = progressState == .normal ? bounds.width * 0.6 : bounds.width
        primaryIndeterminateLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: primaryWidth,
            height: appearance.indicatorHeight
        )
        secondaryIndeterminateLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: secondaryWidth,
            height: appearance.indicatorHeight
        )
        primaryIndeterminateLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        secondaryIndeterminateLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func updateDeterminateGeometry(animated: Bool) {
        guard bounds.width > 0,
              bounds.size == lastLayoutSize,
              lastLayoutDirection == userInterfaceLayoutDirection else {
            needsLayout = true
            return
        }

        let appearance = resolvedAppearance()
        let targetWidth = bounds.width * CGFloat(progressValue)
        let previousWidth = determinateLayer.presentation()?.bounds.width ?? determinateLayer.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        configureDeterminateModelGeometry(appearance)
        CATransaction.commit()

        determinateLayer.removeAnimation(forKey: "fluent.progress.value")
        guard animated, !reduceMotion, abs(previousWidth - targetWidth) > 0.001 else { return }

        let motion = FluentMotion.progressReposition
        let width = CABasicAnimation(keyPath: "bounds.size.width")
        width.fromValue = previousWidth
        width.toValue = targetWidth
        width.duration = motion.duration
        width.timingFunction = motion.curve.timingFunction
        determinateLayer.add(width, forKey: "fluent.progress.value")
    }

    private func refreshVisualState(animated: Bool) {
        guard bounds.width > 0 else {
            needsLayout = true
            return
        }

        let nextState = resolvedVisualState()
        let motion: FluentMotionToken = isIndeterminate
            ? (progressState == .normal ? FluentMotion.progressIndeterminate : FluentMotion.progressIndeterminateSettle)
            : FluentMotion.progressState
        visualStateCoordinator.transition(to: nextState, animated: animated, motion: motion) { [weak self] transition in
            self?.applyVisualState(transition)
        }
    }

    private func resolvedVisualState() -> FluentVisualState {
        var state: FluentVisualState = isIndeterminate ? .indeterminate : .determinate
        switch progressState {
        case .normal: state.insert(.normal)
        case .paused: state.insert(.paused)
        case .error: state.insert(.error)
        }
        return state
    }

    private func applyVisualState(_ transition: FluentVisualStateTransition) {
        let appearance = resolvedAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isIndeterminate {
            determinateLayer.opacity = 0
            trackLayer.opacity = 0
            configureIndeterminateModelGeometry(appearance)
        } else {
            trackLayer.opacity = 1
            determinateLayer.opacity = 1
            primaryIndeterminateLayer.opacity = 0
            secondaryIndeterminateLayer.opacity = 0
            configureDeterminateModelGeometry(appearance)
        }
        CATransaction.commit()

        if isIndeterminate {
            if progressState == .normal, !reduceMotion {
                if transition.changed || primaryIndeterminateLayer.animation(forKey: "fluent.progress.indeterminate.primary") == nil {
                    startIndeterminateAnimation()
                }
            } else {
                settleIndeterminateState(animated: transition.isAnimated)
            }
        } else {
            stopIndeterminateAnimation()
        }
    }

    private func startIndeterminateAnimation() {
        guard bounds.width > 0, isIndeterminate, progressState == .normal, !reduceMotion else { return }
        stopIndeterminateAnimation()
        let primaryWidth = bounds.width * 0.4
        let secondaryWidth = bounds.width * 0.6

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryIndeterminateLayer.opacity = 1
        secondaryIndeterminateLayer.opacity = 1
        primaryIndeterminateLayer.position = CGPoint(
            x: mirroredCenter(forLeftEdge: primaryWidth * 3, width: primaryWidth),
            y: bounds.midY
        )
        secondaryIndeterminateLayer.position = CGPoint(
            x: mirroredCenter(forLeftEdge: secondaryWidth * 1.66, width: secondaryWidth),
            y: bounds.midY
        )
        CATransaction.commit()

        let curve = FluentCubicBezier.progressIndeterminate.timingFunction
        let primary = CAKeyframeAnimation(keyPath: "position.x")
        primary.values = [
            mirroredCenter(forLeftEdge: -primaryWidth, width: primaryWidth),
            mirroredCenter(forLeftEdge: primaryWidth * 3, width: primaryWidth),
            mirroredCenter(forLeftEdge: primaryWidth * 3, width: primaryWidth)
        ]
        primary.keyTimes = [0, 0.75, 1]
        primary.timingFunctions = [curve, CAMediaTimingFunction(name: .linear)]
        primary.duration = FluentMotion.progressIndeterminate.duration
        primary.repeatCount = .infinity

        let secondary = CAKeyframeAnimation(keyPath: "position.x")
        secondary.values = [
            mirroredCenter(forLeftEdge: secondaryWidth * -1.5, width: secondaryWidth),
            mirroredCenter(forLeftEdge: secondaryWidth * -1.5, width: secondaryWidth),
            mirroredCenter(forLeftEdge: secondaryWidth * 1.66, width: secondaryWidth)
        ]
        secondary.keyTimes = [0, 0.375, 1]
        secondary.timingFunctions = [CAMediaTimingFunction(name: .linear), curve]
        secondary.duration = FluentMotion.progressIndeterminate.duration
        secondary.repeatCount = .infinity

        primaryIndeterminateLayer.add(primary, forKey: "fluent.progress.indeterminate.primary")
        secondaryIndeterminateLayer.add(secondary, forKey: "fluent.progress.indeterminate.secondary")
    }

    private func settleIndeterminateState(animated: Bool) {
        let appearance = resolvedAppearance()
        let target = CGPoint(x: bounds.midX, y: bounds.midY)
        let start = secondaryIndeterminateLayer.presentation()?.position ?? CGPoint(
            x: isRTL ? bounds.maxX + bounds.width / 2 : bounds.minX - bounds.width / 2,
            y: bounds.midY
        )
        stopIndeterminateAnimation()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryIndeterminateLayer.opacity = 0
        secondaryIndeterminateLayer.opacity = 1
        secondaryIndeterminateLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: reduceMotion && progressState == .normal ? bounds.width * 0.4 : bounds.width,
            height: appearance.indicatorHeight
        )
        secondaryIndeterminateLayer.position = target
        CATransaction.commit()

        guard animated, !reduceMotion, progressState != .normal, start != target else { return }
        let motion = FluentMotion.progressIndeterminateSettle
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: start)
        position.toValue = NSValue(point: target)
        position.duration = motion.duration
        position.timingFunction = motion.curve.timingFunction
        secondaryIndeterminateLayer.add(position, forKey: "fluent.progress.indeterminate.settle")
    }

    private func updateIndicatorColor(_ color: NSColor, animated: Bool) {
        let layers = [determinateLayer, primaryIndeterminateLayer, secondaryIndeterminateLayer]
        let previousColors = layers.map { $0.presentation()?.backgroundColor ?? $0.backgroundColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        for (index, layer) in layers.enumerated() {
            layer.removeAnimation(forKey: "fluent.progress.color")
            guard animated, !reduceMotion, let previous = previousColors[index] else { continue }
            let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
            colorAnimation.fromValue = previous
            colorAnimation.toValue = color.cgColor
            colorAnimation.duration = FluentMotion.progressState.duration
            colorAnimation.timingFunction = FluentMotion.progressState.curve.timingFunction
            layer.add(colorAnimation, forKey: "fluent.progress.color")
        }
    }

    private func mirroredCenter(forLeftEdge leftEdge: CGFloat, width: CGFloat) -> CGFloat {
        let center = leftEdge + width / 2
        return isRTL ? bounds.width - center : center
    }

    private func stopIndeterminateAnimation() {
        primaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.primary")
        secondaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.secondary")
        secondaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.settle")
    }

    private func removeGeometryAnimations() {
        determinateLayer.removeAnimation(forKey: "fluent.progress.value")
        stopIndeterminateAnimation()
    }

    private func removeVisualAnimations() {
        [trackLayer, determinateLayer, primaryIndeterminateLayer, secondaryIndeterminateLayer].forEach {
            $0.removeAllAnimations()
        }
    }

    private func updateAccessibilityValue() {
        if isIndeterminate {
            setAccessibilityValue("Indeterminate")
        } else {
            setAccessibilityValue(progressValue)
        }
        let status: String? = switch progressState {
        case .normal: nil
        case .paused: "Paused"
        case .error: "Error"
        }
        setAccessibilityHelp(status)
    }
}
