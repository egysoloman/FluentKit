import AppKit

public final class FluentProgressBar: NSView {
    public var theme: FluentTheme = .current {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var fluentStyle: any FluentProgressStyle = FluentAutomaticProgressStyle() {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var value: Double {
        get { progressValue }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard progressValue != clamped else { return }
            progressValue = clamped
            setAccessibilityValue(progressValue)
            invalidateIntrinsicContentSize()
            animateProgress()
        }
    }
    private var progressValue: Double = 0

    public init(value: Double = 0) {
        super.init(frame: .zero)
        progressValue = min(max(value, 0), 1)
        wantsLayer = true
        setAccessibilityRole(.progressIndicator)
        setAccessibilityValue(progressValue)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var intrinsicContentSize: NSSize {
        let appearance = fluentStyle.appearance(
            for: FluentProgressStyleConfiguration(valueFraction: progressValue, theme: theme)
        )
        return NSSize(width: 180, height: appearance.trackHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = fluentStyle.appearance(
            for: FluentProgressStyleConfiguration(valueFraction: progressValue, theme: theme)
        )
        let radius = min(appearance.cornerRadius, bounds.height / 2)
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        appearance.trackColor.setFill()
        track.fill()
        var fill = bounds
        fill.size.width *= progressValue
        let progress = NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius)
        appearance.progressColor.setFill()
        progress.fill()
    }

    private func animateProgress() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FluentAnimation.content
            context.allowsImplicitAnimation = true
            needsDisplay = true
        }
    }

    func applyDeclarativeConfiguration(from source: FluentProgressBar) {
        value = source.value
        fluentStyle = source.fluentStyle
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    @discardableResult
    public func progressStyle(_ style: any FluentProgressStyle) -> FluentProgressBar {
        fluentStyle = style
        return self
    }
}
