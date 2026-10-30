import AppKit

/// Compatibility projection of WinUI's independent `ShowPaused` and `ShowError` flags.
/// When both flags are set, WinUI gives the error visual state precedence.
public enum FluentProgressState: Hashable, Sendable {
    case normal
    case paused
    case error
}

/// A read-only linear progress indicator aligned with WinUI's `ProgressBar` range, state,
/// geometry, animation, RTL, and accessibility semantics.
public final class FluentProgressBar: NSView {
    private enum SourceMetrics {
        static let defaultWidth: CGFloat = 180
        static let primaryWidthFraction: CGFloat = 0.4
        static let secondaryWidthFraction: CGFloat = 0.6
        static let primaryStartTranslationFraction: CGFloat = -0.4
        static let primaryEndTranslationFraction: CGFloat = 1.2
        static let secondaryStartTranslationFraction: CGFloat = -0.9
        static let secondaryEndTranslationFraction: CGFloat = 0.996
        static let indeterminateDuration: CFTimeInterval = 2
        static let pausedTransitionDuration: CFTimeInterval = 0.75
        static let pausedFirstLegDuration: CFTimeInterval = 0.167
        static let resumeIndicatorDuration: CFTimeInterval = 0.333
        static let resumeTransitionDuration: CFTimeInterval = 0.5
    }

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
            guard oldValue != reduceMotion, !isApplyingDeclarativeConfiguration else { return }
            visualStateCoordinator.reduceMotion = reduceMotion
            if reduceMotion { removeVisualAnimations() }
            refreshVisualState(animated: false)
        }
    }

    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            invalidateLayoutCache()
        }
    }

    /// WinUI `ProgressBar.Padding`. Indicator width is calculated after subtracting padding and
    /// the individually layout-rounded border edges.
    public var contentInsets: NSEdgeInsets = NSEdgeInsetsZero {
        didSet {
            guard !sameInsets(oldValue, contentInsets), !isApplyingDeclarativeConfiguration else { return }
            invalidateLayoutCache()
            invalidateIntrinsicContentSize()
        }
    }

    public var isIndeterminate: Bool {
        didSet {
            guard oldValue != isIndeterminate, !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityState()
            refreshAppearance(animatedColor: false)
            refreshVisualState(animated: true)
        }
    }

    /// Matches WinUI's independent `ShowPaused` property.
    public var showPaused: Bool {
        get { progressShowPaused }
        set { setStateFlags(showPaused: newValue, showError: progressShowError) }
    }

    /// Matches WinUI's independent `ShowError` property. Error wins when both flags are true.
    public var showError: Bool {
        get { progressShowError }
        set { setStateFlags(showPaused: progressShowPaused, showError: newValue) }
    }

    /// Compatibility convenience for callers that prefer a mutually exclusive state.
    public var progressState: FluentProgressState {
        get { effectiveProgressState }
        set {
            switch newValue {
            case .normal: setStateFlags(showPaused: false, showError: false)
            case .paused: setStateFlags(showPaused: true, showError: false)
            case .error: setStateFlags(showPaused: false, showError: true)
            }
        }
    }

    /// Matches `RangeBase.Value`; the WinUI default range is 0...100.
    public var value: Double {
        get { progressValue }
        set {
            let previous = progressValue
            let coerced = coercedValue(newValue)
            guard !sameDouble(previous, coerced) else { return }
            progressValue = coerced
            guard !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityState()
            refreshAppearance(animatedColor: false)
            if !isIndeterminate {
                updateDeterminateGeometry(fromRawValue: previous, animated: true)
            }
        }
    }

    public var minimum: Double {
        get { progressMinimum }
        set {
            let previousValue = progressValue
            guard !sameDouble(progressMinimum, newValue) else { return }
            progressMinimum = newValue
            if progressMaximum < progressMinimum { progressMaximum = progressMinimum }
            progressValue = coercedValue(progressValue)
            guard !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityState()
            refreshAppearance(animatedColor: false)
            if !isIndeterminate {
                updateDeterminateGeometry(fromRawValue: previousValue, animated: true)
            }
        }
    }

    public var maximum: Double {
        get { progressMaximum }
        set {
            let previousValue = progressValue
            guard !sameDouble(progressMaximum, newValue) else { return }
            progressMaximum = newValue
            if progressMinimum > progressMaximum { progressMinimum = progressMaximum }
            progressValue = coercedValue(progressValue)
            guard !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityState()
            refreshAppearance(animatedColor: false)
            if !isIndeterminate {
                updateDeterminateGeometry(fromRawValue: previousValue, animated: true)
            }
        }
    }

    private struct LayoutMetrics: Equatable {
        let trackHeight: CGFloat
        let indicatorHeight: CGFloat
        let trackCornerRadius: CGFloat
        let indicatorCornerRadius: CGFloat
        let borderWidth: CGFloat
        let insetTop: CGFloat
        let insetLeft: CGFloat
        let insetBottom: CGFloat
        let insetRight: CGFloat
    }

    private let trackLayer = CALayer()
    private let determinateLayer = CALayer()
    private let primaryIndeterminateLayer = CALayer()
    private let secondaryIndeterminateLayer = CALayer()
    private var progressValue: Double
    private var progressMinimum: Double
    private var progressMaximum: Double
    private var progressShowPaused: Bool
    private var progressShowError: Bool
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?
    private var lastLayoutMetrics: LayoutMetrics?
    private var isApplyingDeclarativeConfiguration = false
    private var animationGeneration: UInt = 0
    private let visualStateCoordinator: FluentVisualStateCoordinator

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    private var effectiveProgressState: FluentProgressState {
        if progressShowError { return .error }
        if progressShowPaused { return .paused }
        return .normal
    }

    private var canRunIndeterminateAnimation: Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && !reduceMotion
    }

    public init(
        value: Double = 0,
        minimum: Double = 0,
        maximum: Double = 100,
        isIndeterminate: Bool = false,
        showPaused: Bool = false,
        showError: Bool = false
    ) {
        progressMinimum = minimum
        progressMaximum = max(maximum, minimum)
        if value.isNaN {
            progressValue = value
        } else {
            progressValue = min(max(value, progressMinimum), progressMaximum)
        }
        progressShowPaused = showPaused
        progressShowError = showError
        self.isIndeterminate = isIndeterminate
        visualStateCoordinator = FluentVisualStateCoordinator()
        super.init(frame: .zero)
        visualStateCoordinator.reduceMotion = reduceMotion
        configureView()
    }

    /// Compatibility initializer for the previous mutually-exclusive state API.
    public convenience init(
        value: Double = 0,
        minimum: Double = 0,
        maximum: Double = 100,
        isIndeterminate: Bool = false,
        state: FluentProgressState
    ) {
        self.init(
            value: value,
            minimum: minimum,
            maximum: maximum,
            isIndeterminate: isIndeterminate,
            showPaused: state == .paused,
            showError: state == .error
        )
    }

    /// Migration helper for the original FluentKit 0...1 value convention.
    public convenience init(
        valueFraction: Double,
        isIndeterminate: Bool = false,
        state: FluentProgressState = .normal
    ) {
        self.init(
            value: valueFraction,
            minimum: 0,
            maximum: 1,
            isIndeterminate: isIndeterminate,
            state: state
        )
    }

    required init?(coder: NSCoder) {
        progressValue = 0
        progressMinimum = 0
        progressMaximum = 100
        progressShowPaused = false
        progressShowError = false
        isIndeterminate = false
        visualStateCoordinator = FluentVisualStateCoordinator()
        super.init(coder: coder)
        visualStateCoordinator.reduceMotion = reduceMotion
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let border = layoutRounded(appearance.borderWidth)
        return NSSize(
            width: SourceMetrics.defaultWidth + contentInsets.left + contentInsets.right + border * 2,
            height: max(appearance.trackHeight, appearance.indicatorHeight)
                + contentInsets.top + contentInsets.bottom + border * 2
        )
    }

    public override var acceptsFirstResponder: Bool { false }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
        refreshVisualState(animated: false)
    }

    public override func viewDidHide() {
        super.viewDidHide()
        stopIndeterminateAnimation()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshVisualState(animated: false)
    }

    func applyDeclarativeConfiguration(from source: FluentProgressBar) {
        let previousValue = progressValue
        let rangeChanged = !sameDouble(progressMinimum, source.progressMinimum)
            || !sameDouble(progressMaximum, source.progressMaximum)
        let valueChanged = !sameDouble(progressValue, source.progressValue)
        let modeChanged = isIndeterminate != source.isIndeterminate
        let stateChanged = effectiveProgressState != source.effectiveProgressState
        let insetsChanged = !sameInsets(contentInsets, source.contentInsets)

        isApplyingDeclarativeConfiguration = true
        progressValue = source.progressValue
        progressMinimum = source.progressMinimum
        progressMaximum = source.progressMaximum
        progressShowPaused = source.progressShowPaused
        progressShowError = source.progressShowError
        isIndeterminate = source.isIndeterminate
        contentInsets = source.contentInsets
        fluentStyle = source.fluentStyle
        isApplyingDeclarativeConfiguration = false

        if insetsChanged { invalidateLayoutCache() }
        refreshAppearance(animatedColor: stateChanged)
        updateAccessibilityState()
        if modeChanged || stateChanged || insetsChanged {
            refreshVisualState(animated: true)
        } else if (valueChanged || rangeChanged), !isIndeterminate {
            updateDeterminateGeometry(fromRawValue: previousValue, animated: true)
        }
    }

    @discardableResult
    public func progressStyle(_ style: any FluentProgressStyle) -> FluentProgressBar {
        fluentStyle = style
        return self
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true

        trackLayer.name = "FluentKit.ProgressBar.Track"
        determinateLayer.name = "FluentKit.ProgressBar.Determinate"
        primaryIndeterminateLayer.name = "FluentKit.ProgressBar.Indeterminate.Primary"
        secondaryIndeterminateLayer.name = "FluentKit.ProgressBar.Indeterminate.Secondary"
        [trackLayer, determinateLayer, primaryIndeterminateLayer, secondaryIndeterminateLayer].forEach {
            $0.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "backgroundColor": NSNull(),
                "opacity": NSNull()
            ]
            layer?.addSublayer($0)
        }

        setAccessibilityRole(.progressIndicator)
        updateAccessibilityState()
        refreshAppearance(animatedColor: false)
    }

    private func setStateFlags(showPaused: Bool, showError: Bool) {
        let oldEffectiveState = effectiveProgressState
        guard progressShowPaused != showPaused || progressShowError != showError else { return }
        progressShowPaused = showPaused
        progressShowError = showError
        guard !isApplyingDeclarativeConfiguration else { return }
        let effectiveChanged = oldEffectiveState != effectiveProgressState
        updateAccessibilityState()
        refreshAppearance(animatedColor: effectiveChanged)
        if effectiveChanged { refreshVisualState(animated: true) }
    }

    private func resolvedAppearance() -> FluentProgressAppearance {
        fluentStyle.appearance(
            for: FluentProgressStyleConfiguration(
                valueFraction: normalizedValue(progressValue),
                isIndeterminate: isIndeterminate,
                state: effectiveProgressState,
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
            borderWidth: appearance.borderWidth,
            insetTop: contentInsets.top,
            insetLeft: contentInsets.left,
            insetBottom: contentInsets.bottom,
            insetRight: contentInsets.right
        )
    }

    private func refreshAppearance(animatedColor: Bool) {
        guard layer != nil else { return }
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
        let content = availableContentRect(for: appearance)
        let trackY = content.midY - appearance.trackHeight / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = NSRect(
            x: content.minX,
            y: trackY,
            width: content.width,
            height: appearance.trackHeight
        )
        configureDeterminateModelGeometry(appearance, content: content)
        configureIndeterminateModelGeometry(appearance, content: content)
        CATransaction.commit()
    }

    private func configureDeterminateModelGeometry(
        _ appearance: FluentProgressAppearance,
        content: CGRect? = nil
    ) {
        let content = content ?? availableContentRect(for: appearance)
        let width = layoutRounded(content.width * normalizedValue(progressValue))
        determinateLayer.anchorPoint = CGPoint(x: isRTL ? 1 : 0, y: 0.5)
        determinateLayer.bounds = CGRect(x: 0, y: 0, width: width, height: appearance.indicatorHeight)
        determinateLayer.position = CGPoint(x: isRTL ? content.maxX : content.minX, y: content.midY)
    }

    private func configureIndeterminateModelGeometry(
        _ appearance: FluentProgressAppearance,
        content: CGRect? = nil
    ) {
        let content = content ?? availableContentRect(for: appearance)
        let primaryWidth = layoutRounded(content.width * SourceMetrics.primaryWidthFraction)
        let secondaryFraction: CGFloat = effectiveProgressState == .normal
            ? SourceMetrics.secondaryWidthFraction
            : 1
        let secondaryWidth = layoutRounded(content.width * secondaryFraction)
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
        primaryIndeterminateLayer.position = CGPoint(
            x: indeterminateCenter(translation: 0, layerWidth: primaryWidth, content: content),
            y: content.midY
        )
        secondaryIndeterminateLayer.position = CGPoint(
            x: indeterminateCenter(translation: 0, layerWidth: secondaryWidth, content: content),
            y: content.midY
        )
    }

    private func updateDeterminateGeometry(fromRawValue previousValue: Double, animated: Bool) {
        guard bounds.width > 0,
              bounds.size == lastLayoutSize,
              lastLayoutDirection == userInterfaceLayoutDirection else {
            needsLayout = true
            return
        }

        let appearance = resolvedAppearance()
        let content = availableContentRect(for: appearance)
        let targetWidth = layoutRounded(content.width * normalizedValue(progressValue))
        let previousFractionWidth = layoutRounded(content.width * normalizedValue(previousValue))
        let presentationWidth = determinateLayer.presentation()?.bounds.width
        let previousWidth = presentationWidth ?? previousFractionWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        configureDeterminateModelGeometry(appearance, content: content)
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
            ? (effectiveProgressState == .normal
                ? FluentMotion.progressIndeterminate
                : FluentMotion.progressIndeterminateSettle)
            : FluentMotion.progressState
        visualStateCoordinator.transition(to: nextState, animated: animated, motion: motion) { [weak self] transition in
            self?.applyVisualState(transition)
        }
    }

    private func resolvedVisualState() -> FluentVisualState {
        var state: FluentVisualState = isIndeterminate ? .indeterminate : .determinate
        switch effectiveProgressState {
        case .normal: state.insert(.normal)
        case .paused: state.insert(.paused)
        case .error: state.insert(.error)
        }
        return state
    }

    private func applyVisualState(_ transition: FluentVisualStateTransition) {
        let appearance = resolvedAppearance()
        let content = availableContentRect(for: appearance)
        let previousPrimaryPosition = primaryIndeterminateLayer.presentation()?.position
        let previousSecondaryPosition = secondaryIndeterminateLayer.presentation()?.position

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isIndeterminate {
            determinateLayer.opacity = 0
            trackLayer.opacity = 0
            configureIndeterminateModelGeometry(appearance, content: content)
        } else {
            trackLayer.opacity = 1
            determinateLayer.opacity = 1
            primaryIndeterminateLayer.opacity = 0
            secondaryIndeterminateLayer.opacity = 0
            configureDeterminateModelGeometry(appearance, content: content)
        }
        CATransaction.commit()

        guard isIndeterminate else {
            stopIndeterminateAnimation()
            return
        }

        if effectiveProgressState == .normal {
            if reduceMotion || !canRunIndeterminateAnimation {
                showStaticIndeterminate(appearance, content: content)
            } else if transition.changed,
                      transition.from.contains(.indeterminate),
                      (transition.from.contains(.paused) || transition.from.contains(.error)) {
                resumeIndeterminateAnimation(
                    from: previousSecondaryPosition,
                    appearance: appearance,
                    content: content,
                    animated: transition.isAnimated
                )
            } else if primaryIndeterminateLayer.animation(
                forKey: "fluent.progress.indeterminate.primary"
            ) == nil {
                startIndeterminateAnimation()
            }
        } else {
            settleIndeterminateState(
                from: previousSecondaryPosition ?? previousPrimaryPosition,
                appearance: appearance,
                content: content,
                animated: transition.isAnimated
            )
        }
    }

    private func startIndeterminateAnimation() {
        guard bounds.width > 0,
              isIndeterminate,
              effectiveProgressState == .normal,
              canRunIndeterminateAnimation else { return }
        stopIndeterminateAnimation()
        let appearance = resolvedAppearance()
        let content = availableContentRect(for: appearance)
        let primaryWidth = layoutRounded(content.width * SourceMetrics.primaryWidthFraction)
        let secondaryWidth = layoutRounded(content.width * SourceMetrics.secondaryWidthFraction)
        let extent = bounds.width

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryIndeterminateLayer.opacity = 1
        secondaryIndeterminateLayer.opacity = 1
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
        primaryIndeterminateLayer.position = CGPoint(
            x: indeterminateCenter(
                translation: extent * SourceMetrics.primaryEndTranslationFraction,
                layerWidth: primaryWidth,
                content: content
            ),
            y: content.midY
        )
        secondaryIndeterminateLayer.position = CGPoint(
            x: indeterminateCenter(
                translation: extent * SourceMetrics.secondaryEndTranslationFraction,
                layerWidth: secondaryWidth,
                content: content
            ),
            y: content.midY
        )
        CATransaction.commit()

        let curve = FluentCubicBezier.progressIndeterminate.timingFunction
        let primary = CAKeyframeAnimation(keyPath: "position.x")
        primary.values = [
            indeterminateCenter(
                translation: extent * SourceMetrics.primaryStartTranslationFraction,
                layerWidth: primaryWidth,
                content: content
            ),
            indeterminateCenter(
                translation: extent * SourceMetrics.primaryEndTranslationFraction,
                layerWidth: primaryWidth,
                content: content
            ),
            indeterminateCenter(
                translation: extent * SourceMetrics.primaryEndTranslationFraction,
                layerWidth: primaryWidth,
                content: content
            )
        ]
        primary.keyTimes = [0, 0.75, 1]
        primary.timingFunctions = [curve, CAMediaTimingFunction(name: .linear)]
        primary.duration = SourceMetrics.indeterminateDuration
        primary.repeatCount = .infinity

        let secondary = CAKeyframeAnimation(keyPath: "position.x")
        secondary.values = [
            indeterminateCenter(
                translation: extent * SourceMetrics.secondaryStartTranslationFraction,
                layerWidth: secondaryWidth,
                content: content
            ),
            indeterminateCenter(
                translation: extent * SourceMetrics.secondaryStartTranslationFraction,
                layerWidth: secondaryWidth,
                content: content
            ),
            indeterminateCenter(
                translation: extent * SourceMetrics.secondaryEndTranslationFraction,
                layerWidth: secondaryWidth,
                content: content
            )
        ]
        secondary.keyTimes = [0, 0.375, 1]
        secondary.timingFunctions = [CAMediaTimingFunction(name: .linear), curve]
        secondary.duration = SourceMetrics.indeterminateDuration
        secondary.repeatCount = .infinity

        primaryIndeterminateLayer.add(primary, forKey: "fluent.progress.indeterminate.primary")
        secondaryIndeterminateLayer.add(secondary, forKey: "fluent.progress.indeterminate.secondary")
    }

    /// Reproduces WinUI's `IndeterminatePaused`/`IndeterminateError` storyboard: the visible
    /// secondary segment first exits, jumps to its start point, then decelerates into place.
    private func settleIndeterminateState(
        from sampledPosition: CGPoint?,
        appearance: FluentProgressAppearance,
        content: CGRect,
        animated: Bool
    ) {
        let previousX = sampledPosition?.x ?? secondaryIndeterminateLayer.position.x
        stopIndeterminateAnimation()
        let width = layoutRounded(content.width)
        let extent = bounds.width
        let restingX = indeterminateCenter(translation: 0, layerWidth: width, content: content)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryIndeterminateLayer.opacity = 0
        secondaryIndeterminateLayer.opacity = 1
        secondaryIndeterminateLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: appearance.indicatorHeight
        )
        secondaryIndeterminateLayer.position = CGPoint(x: restingX, y: content.midY)
        CATransaction.commit()

        guard animated, canRunIndeterminateAnimation else { return }
        let firstLeg = SourceMetrics.pausedFirstLegDuration / SourceMetrics.pausedTransitionDuration
        let jump = min(firstLeg + 0.000_001, 1)
        let endX = indeterminateCenter(
            translation: extent * SourceMetrics.secondaryEndTranslationFraction,
            layerWidth: width,
            content: content
        )
        let startX = indeterminateCenter(
            translation: extent * SourceMetrics.secondaryStartTranslationFraction,
            layerWidth: width,
            content: content
        )
        let position = CAKeyframeAnimation(keyPath: "position.x")
        position.values = [previousX, endX, startX, restingX]
        position.keyTimes = [0, NSNumber(value: firstLeg), NSNumber(value: jump), 1]
        position.timingFunctions = [
            FluentCubicBezier(1, 1, 0, 1).timingFunction,
            CAMediaTimingFunction(name: .linear),
            FluentCubicBezier(0, 0, 0, 1).timingFunction
        ]
        position.duration = SourceMetrics.pausedTransitionDuration
        secondaryIndeterminateLayer.add(position, forKey: "fluent.progress.indeterminate.settle")
    }

    /// WinUI does not start both moving segments immediately when leaving paused/error. The
    /// visible secondary segment exits first; only then does the normal 2-second loop begin.
    private func resumeIndeterminateAnimation(
        from sampledPosition: CGPoint?,
        appearance: FluentProgressAppearance,
        content: CGRect,
        animated: Bool
    ) {
        let previousX = sampledPosition?.x ?? secondaryIndeterminateLayer.position.x
        stopIndeterminateAnimation()
        let generation = animationGeneration
        let width = layoutRounded(content.width * SourceMetrics.secondaryWidthFraction)
        let endX = indeterminateCenter(
            translation: bounds.width * SourceMetrics.secondaryEndTranslationFraction,
            layerWidth: width,
            content: content
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryIndeterminateLayer.opacity = 0
        secondaryIndeterminateLayer.opacity = 1
        secondaryIndeterminateLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: appearance.indicatorHeight
        )
        secondaryIndeterminateLayer.position = CGPoint(x: endX, y: content.midY)
        CATransaction.commit()

        guard animated, !reduceMotion, canRunIndeterminateAnimation else {
            startIndeterminateAnimation()
            return
        }
        let position = CABasicAnimation(keyPath: "position.x")
        position.fromValue = previousX
        position.toValue = endX
        position.duration = SourceMetrics.resumeIndicatorDuration
        position.timingFunction = FluentCubicBezier(1, 0, 1, 1).timingFunction
        secondaryIndeterminateLayer.add(position, forKey: "fluent.progress.indeterminate.resume")

        let trackPosition = CABasicAnimation(keyPath: "transform.translation.x")
        trackPosition.fromValue = 0
        trackPosition.toValue = (isRTL ? -1 : 1)
            * bounds.width * SourceMetrics.primaryEndTranslationFraction
        trackPosition.duration = SourceMetrics.resumeTransitionDuration
        trackPosition.timingFunction = FluentCubicBezier(1, 0, 1, 1).timingFunction
        trackLayer.add(trackPosition, forKey: "fluent.progress.indeterminate.resume.track")

        // The secondary indicator finishes at 333ms, while WinUI's parallel (invisible) track
        // transition establishes a 500ms state-transition duration. Start the target state's
        // repeating storyboard only after that complete transition, preserving the source order.
        DispatchQueue.main.asyncAfter(deadline: .now() + SourceMetrics.resumeTransitionDuration) { [weak self] in
            guard let self,
                  self.animationGeneration == generation,
                  self.isIndeterminate,
                  self.effectiveProgressState == .normal,
                  self.canRunIndeterminateAnimation else { return }
            self.startIndeterminateAnimation()
        }
    }

    private func showStaticIndeterminate(_ appearance: FluentProgressAppearance, content: CGRect) {
        stopIndeterminateAnimation()
        let width = effectiveProgressState == .normal
            ? layoutRounded(content.width * SourceMetrics.primaryWidthFraction)
            : layoutRounded(content.width)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryIndeterminateLayer.opacity = 0
        secondaryIndeterminateLayer.opacity = 1
        secondaryIndeterminateLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: appearance.indicatorHeight
        )
        secondaryIndeterminateLayer.position = CGPoint(x: content.midX, y: content.midY)
        CATransaction.commit()
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

    private func availableContentRect(for appearance: FluentProgressAppearance) -> CGRect {
        let border = layoutRounded(appearance.borderWidth)
        let minX = bounds.minX + border + contentInsets.left
        let maxX = bounds.maxX - border - contentInsets.right
        let minY = bounds.minY + border + contentInsets.bottom
        let maxY = bounds.maxY - border - contentInsets.top
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0)
        )
    }

    private func indeterminateCenter(
        translation: CGFloat,
        layerWidth: CGFloat,
        content: CGRect
    ) -> CGFloat {
        let ltrCenter = content.minX + translation + layerWidth / 2
        return isRTL ? content.maxX - (ltrCenter - content.minX) : ltrCenter
    }

    private func normalizedValue(_ rawValue: Double) -> CGFloat {
        let range = progressMaximum - progressMinimum
        guard rawValue.isFinite, progressMinimum.isFinite, progressMaximum.isFinite,
              range.isFinite, range > Double.ulpOfOne else { return 0 }
        return min(max(CGFloat((rawValue - progressMinimum) / range), 0), 1)
    }

    private func coercedValue(_ candidate: Double) -> Double {
        guard !candidate.isNaN else { return candidate }
        if candidate > progressMaximum { return progressMaximum }
        if candidate < progressMinimum { return progressMinimum }
        return candidate
    }

    private func updateAccessibilityState() {
        if isIndeterminate {
            setAccessibilityMinValue(nil)
            setAccessibilityMaxValue(nil)
            fluentSetDefaultAccessibilityValue("Indeterminate")
        } else {
            setAccessibilityMinValue(progressMinimum)
            setAccessibilityMaxValue(progressMaximum)
            setAccessibilityValue(progressValue)
        }
        let help: String? = switch effectiveProgressState {
        case .error: "Error"
        case .paused: "Paused"
        case .normal: isIndeterminate ? "Indeterminate" : nil
        }
        setAccessibilityHelp(help)
    }

    private func layoutRounded(_ value: CGFloat) -> CGFloat {
        FluentPixelGeometry(
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ).align(value)
    }

    private func sameDouble(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs == rhs || (lhs.isNaN && rhs.isNaN)
    }

    private func sameInsets(_ lhs: NSEdgeInsets, _ rhs: NSEdgeInsets) -> Bool {
        lhs.top == rhs.top
            && lhs.left == rhs.left
            && lhs.bottom == rhs.bottom
            && lhs.right == rhs.right
    }

    private func invalidateLayoutCache() {
        lastLayoutSize = NSSize(width: -1, height: -1)
        lastLayoutDirection = nil
        lastLayoutMetrics = nil
        needsLayout = true
    }

    private func stopIndeterminateAnimation() {
        animationGeneration &+= 1
        primaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.primary")
        secondaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.secondary")
        secondaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.settle")
        secondaryIndeterminateLayer.removeAnimation(forKey: "fluent.progress.indeterminate.resume")
        trackLayer.removeAnimation(forKey: "fluent.progress.indeterminate.resume.track")
    }

    private func removeGeometryAnimations() {
        determinateLayer.removeAnimation(forKey: "fluent.progress.value")
        stopIndeterminateAnimation()
    }

    private func removeVisualAnimations() {
        animationGeneration &+= 1
        [trackLayer, determinateLayer, primaryIndeterminateLayer, secondaryIndeterminateLayer].forEach {
            $0.removeAllAnimations()
        }
    }
}
