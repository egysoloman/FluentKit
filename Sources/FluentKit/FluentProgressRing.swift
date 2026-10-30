import AppKit

/// A read-only circular progress indicator aligned with WinUI's `ProgressRing` range and state
/// semantics. The view keeps its layout slot while inactive, and supports both indeterminate and
/// determinate progress without a display-link or run-loop timer.
public final class FluentProgressRing: NSView {
    private enum Metrics {
        static let defaultSide: CGFloat = 32
        static let indeterminateRadiusFraction: CGFloat = 35.0 / 80.0
        static let indeterminateStrokeFraction: CGFloat = 7.5 / 80.0
        static let determinateRadiusFraction: CGFloat = (8.0 * 1.77) / 32.0
        static let determinateStrokeFraction: CGFloat = (1.5 * 1.77) / 32.0
        static let sourceDuration: CFTimeInterval = 2
        static let sourceCurve = FluentCubicBezier(0.167, 0.167, 0.833, 0.833)
        static let minimumVisibleTrim: CGFloat = 0.0001
    }

    public var theme: FluentTheme = .current {
        didSet { refreshAppearance() }
    }

    /// Overrides WinUI's `ProgressRingForegroundThemeBrush` when non-nil.
    public var foregroundColor: NSColor? {
        didSet { refreshAppearance() }
    }

    /// Overrides WinUI's normally transparent `ProgressRingBackgroundThemeBrush` when non-nil.
    public var backgroundColor: NSColor? {
        didSet { refreshAppearance() }
    }

    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion, !isApplyingDeclarativeConfiguration else { return }
            refreshVisualState()
        }
    }

    /// Matches WinUI's default `IsActive=true`. Inactive rings retain their intrinsic size while
    /// becoming transparent and leaving the accessibility content tree.
    public var isActive: Bool {
        didSet {
            guard oldValue != isActive, !isApplyingDeclarativeConfiguration else { return }
            refreshVisualState()
        }
    }

    /// Matches WinUI's default `IsIndeterminate=true`.
    public var isIndeterminate: Bool {
        didSet {
            guard oldValue != isIndeterminate, !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityState()
            needsLayout = true
            refreshVisualState()
        }
    }

    public var value: Double {
        get { progressValue }
        set {
            let previous = progressValue
            let coerced = coercedValue(newValue)
            guard !sameDouble(previous, coerced) else { return }
            progressValue = coerced
            guard !isApplyingDeclarativeConfiguration else { return }
            updateAccessibilityState()
            if !isIndeterminate {
                updateDeterminateProgress(fromRawValue: previous, animated: true)
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
            if !isIndeterminate {
                updateDeterminateProgress(fromRawValue: previousValue, animated: true)
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
            if !isIndeterminate {
                updateDeterminateProgress(fromRawValue: previousValue, animated: true)
            }
        }
    }

    /// Compatibility spelling used by the original FluentKit implementation.
    @available(*, deprecated, renamed: "isActive")
    public var isAnimating: Bool {
        get { isActive }
        set { isActive = newValue }
    }

    private let trackLayer = CAShapeLayer()
    private let indicatorLayer = CAShapeLayer()
    private var progressValue: Double
    private var progressMinimum: Double
    private var progressMaximum: Double
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var isApplyingDeclarativeConfiguration = false

    public init(
        isActive: Bool = true,
        isIndeterminate: Bool = true,
        value: Double = 0,
        minimum: Double = 0,
        maximum: Double = 100
    ) {
        self.isActive = isActive
        self.isIndeterminate = isIndeterminate
        progressMinimum = minimum
        progressMaximum = max(maximum, minimum)
        if value.isNaN {
            progressValue = value
        } else {
            progressValue = min(max(value, progressMinimum), progressMaximum)
        }
        super.init(frame: .zero)
        configureView()
    }

    public convenience init(isAnimating: Bool) {
        self.init(isActive: isAnimating)
    }

    required init?(coder: NSCoder) {
        isActive = true
        isIndeterminate = true
        progressValue = 0
        progressMinimum = 0
        progressMaximum = 100
        super.init(coder: coder)
        configureView()
    }

    public override var isFlipped: Bool { true }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: Metrics.defaultSide, height: Metrics.defaultSide)
    }

    public override var acceptsFirstResponder: Bool { false }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func layout() {
        super.layout()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        applyGeometry()
        refreshVisualState()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshVisualState()
    }

    func applyDeclarativeConfiguration(from source: FluentProgressRing) {
        let previousValue = progressValue
        let stateChanged = isActive != source.isActive
            || isIndeterminate != source.isIndeterminate
        let progressChanged = !sameDouble(progressValue, source.progressValue)
            || !sameDouble(progressMinimum, source.progressMinimum)
            || !sameDouble(progressMaximum, source.progressMaximum)

        isApplyingDeclarativeConfiguration = true
        isActive = source.isActive
        isIndeterminate = source.isIndeterminate
        progressValue = source.progressValue
        progressMinimum = source.progressMinimum
        progressMaximum = source.progressMaximum
        foregroundColor = source.foregroundColor
        backgroundColor = source.backgroundColor
        isApplyingDeclarativeConfiguration = false

        refreshAppearance()
        updateAccessibilityState()
        if stateChanged {
            needsLayout = true
            refreshVisualState()
        } else if progressChanged, !isIndeterminate {
            updateDeterminateProgress(fromRawValue: previousValue, animated: true)
        }
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false

        trackLayer.name = "FluentKit.ProgressRing.Track"
        indicatorLayer.name = "FluentKit.ProgressRing.Indicator"
        for shape in [trackLayer, indicatorLayer] {
            shape.fillColor = NSColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer?.addSublayer(shape)
        }

        setAccessibilityRole(.progressIndicator)
        updateAccessibilityState()
        refreshAppearance()
        applyGeometry()
        refreshVisualState()
    }

    private func refreshAppearance() {
        guard layer != nil else { return }
        let trackColor = backgroundColor ?? theme.progressRingBackground
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.strokeColor = trackColor.cgColor
        indicatorLayer.strokeColor = (foregroundColor ?? theme.accentFillDefault).cgColor
        CATransaction.commit()
    }

    private func applyGeometry() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let side = min(bounds.width, bounds.height)
        let radiusFraction = isIndeterminate
            ? Metrics.indeterminateRadiusFraction
            : Metrics.determinateRadiusFraction
        let strokeFraction = isIndeterminate
            ? Metrics.indeterminateStrokeFraction
            : Metrics.determinateStrokeFraction
        let radius = side * radiusFraction
        let pathRect = CGRect(
            x: bounds.midX - radius,
            y: bounds.midY - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: pathRect.midX, y: pathRect.midY),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi,
            clockwise: true
        )
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [trackLayer, indicatorLayer] {
            shape.frame = bounds
            shape.contentsScale = scale
            shape.path = path
            shape.lineWidth = side * strokeFraction
        }
        indicatorLayer.setAffineTransform(.identity)
        CATransaction.commit()
    }

    private func refreshVisualState() {
        guard layer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = isActive ? 1 : 0
        CATransaction.commit()
        updateAccessibilityState()

        guard isActive else {
            stopIndeterminateAnimation()
            return
        }

        if isIndeterminate {
            if reduceMotion || window == nil {
                stopIndeterminateAnimation()
                setIndicatorTrim(start: 0, end: 0.5)
            } else {
                startIndeterminateAnimation()
            }
        } else {
            stopIndeterminateAnimation()
            setIndicatorTrim(start: 0, end: determinateTrim(for: normalizedValue(progressValue)))
        }
    }

    private func startIndeterminateAnimation() {
        guard isActive, isIndeterminate, !reduceMotion, window != nil else { return }
        indicatorLayer.removeAnimation(forKey: "fluent.progressRing.indeterminate")
        setIndicatorTrim(start: 0.5, end: 0.5)

        let curve = Metrics.sourceCurve.timingFunction
        let strokeEnd = CAKeyframeAnimation(keyPath: "strokeEnd")
        strokeEnd.values = [Metrics.minimumVisibleTrim, 0.5, 0.5]
        strokeEnd.keyTimes = [0, 0.5, 1]
        strokeEnd.timingFunctions = [curve, CAMediaTimingFunction(name: .linear)]

        let strokeStart = CAKeyframeAnimation(keyPath: "strokeStart")
        strokeStart.values = [0, 0, 0.5]
        strokeStart.keyTimes = [0, 0.5, 1]
        strokeStart.timingFunctions = [CAMediaTimingFunction(name: .linear), curve]

        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        // The hosting NSView is flipped, so positive Core Animation angles have the same visible
        // clockwise direction as WinUI Composition. Negating these values counter-rotated the
        // already-clockwise trim animation.
        rotation.values = [0, 5 * CGFloat.pi / 2, 5 * CGFloat.pi]
        rotation.keyTimes = [0, 0.5, 1]
        rotation.timingFunctions = [curve, curve]

        let group = CAAnimationGroup()
        group.animations = [strokeEnd, strokeStart, rotation]
        group.duration = Metrics.sourceDuration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        indicatorLayer.add(group, forKey: "fluent.progressRing.indeterminate")
    }

    private func stopIndeterminateAnimation() {
        indicatorLayer.removeAnimation(forKey: "fluent.progressRing.indeterminate")
    }

    private func updateDeterminateProgress(fromRawValue previousValue: Double, animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else {
            needsLayout = true
            return
        }
        let fromTimeline = normalizedValue(previousValue)
        let toTimeline = normalizedValue(progressValue)
        let targetTrim = determinateTrim(for: toTimeline)
        setIndicatorTrim(start: 0, end: targetTrim)
        indicatorLayer.removeAnimation(forKey: "fluent.progressRing.value")

        guard animated, isActive, !reduceMotion, !isIndeterminate,
              toTimeline > fromTimeline else { return }

        let duration = Metrics.sourceDuration * CFTimeInterval(toTimeline - fromTimeline)
        let sampleCount = max(Int(ceil(duration * 60)), 2)
        let animation = CAKeyframeAnimation(keyPath: "strokeEnd")
        animation.values = (0...sampleCount).map { index in
            let fraction = CGFloat(index) / CGFloat(sampleCount)
            let timeline = fromTimeline + (toTimeline - fromTimeline) * fraction
            return determinateTrim(for: timeline)
        }
        animation.keyTimes = (0...sampleCount).map {
            NSNumber(value: Double($0) / Double(sampleCount))
        }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.isRemovedOnCompletion = true
        indicatorLayer.add(animation, forKey: "fluent.progressRing.value")
    }

    private func setIndicatorTrim(start: CGFloat, end: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        indicatorLayer.strokeStart = start
        indicatorLayer.strokeEnd = end
        CATransaction.commit()
    }

    private func normalizedValue(_ rawValue: Double) -> CGFloat {
        let range = progressMaximum - progressMinimum
        guard rawValue.isFinite, progressMinimum.isFinite, progressMaximum.isFinite,
              range.isFinite, range > 0 else { return 0 }
        return min(max(CGFloat((rawValue - progressMinimum) / range), 0), 1)
    }

    /// Evaluates the generated WinUI determinate Lottie timeline. Most source points are linear,
    /// while each segment uses the exact `(0.167, 0.167, 0.833, 0.833)` easing curve.
    private func determinateTrim(for timeline: CGFloat) -> CGFloat {
        let keys: [(time: CGFloat, value: CGFloat)] = [
            (1.0 / 120.0, Metrics.minimumVisibleTrim),
            (0.25, 0.25),
            (0.5, 0.5),
            (0.75, 0.75),
            (59.0 / 60.0, 29.0 / 30.0),
            (119.0 / 120.0, 1),
            (1, 1)
        ]
        let clamped = min(max(timeline, 0), 1)
        // The generated visual keeps its foreground container at scale zero until this first
        // source keyframe, so an exact value of zero must not leave a round-cap dot behind.
        guard clamped >= keys[0].time else { return 0 }
        for index in 1..<keys.count {
            let lower = keys[index - 1]
            let upper = keys[index]
            guard clamped <= upper.time else { continue }
            let span = upper.time - lower.time
            guard span > 0 else { return upper.value }
            let local = (clamped - lower.time) / span
            let eased = Metrics.sourceCurve.timingFunction.fluentProgress(at: local)
            return lower.value + (upper.value - lower.value) * eased
        }
        return 1
    }

    private func coercedValue(_ candidate: Double) -> Double {
        guard !candidate.isNaN else { return candidate }
        if candidate > progressMaximum { return progressMaximum }
        if candidate < progressMinimum { return progressMinimum }
        return candidate
    }

    private func sameDouble(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs == rhs || (lhs.isNaN && rhs.isNaN)
    }

    private func updateAccessibilityState() {
        setAccessibilityElement(isActive)
        guard isActive else { return }
        if isIndeterminate {
            setAccessibilityMinValue(nil)
            setAccessibilityMaxValue(nil)
            setAccessibilityValue("Indeterminate")
        } else {
            setAccessibilityMinValue(progressMinimum)
            setAccessibilityMaxValue(progressMaximum)
            setAccessibilityValue(progressValue)
        }
    }
}
