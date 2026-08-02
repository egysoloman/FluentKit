import AppKit

/// The semantic inputs supplied to a button style for each native state.
public struct FluentButtonStyleConfiguration {
    public let title: String
    public let role: FluentButtonRole
    public let controlState: FluentControlState
    public let isEnabled: Bool
    public let theme: FluentTheme

    public init(
        title: String,
        role: FluentButtonRole = .standard,
        controlState: FluentControlState = .normal,
        isEnabled: Bool = true,
        theme: FluentTheme = .current
    ) {
        self.title = title
        self.role = role
        self.controlState = controlState
        self.isEnabled = isEnabled
        self.theme = theme
    }
}

/// The visual edge at which WinUI's absolute three-point elevation gradient is revealed.
public enum FluentElevationBorderEdge: Hashable, Sendable {
    case top
    case bottom
}

/// Visual coordinates used by control-owned geometry. Resolve this from the control view when
/// available, never from a child gradient or shape layer whose own flag does not describe the
/// host transform.
enum FluentVisualYAxis {
    case down
    case up

    var visualBottom: CGFloat { self == .down ? 1 : 0 }
    var visualTop: CGFloat { self == .down ? 0 : 1 }
    var visualDownSign: CGFloat { self == .down ? 1 : -1 }

    /// Resolves the control's local visual axis. The view's `isFlipped` is authoritative for
    /// control-owned drawing; a backing layer can inherit a flipped value from WindowShell even
    /// when the control itself still uses AppKit's unflipped view coordinates.
    static func resolved(for layer: CALayer?, fallbackView view: NSView? = nil) -> Self {
        if let view { return view.isFlipped ? .down : .up }
        if let layer { return layer.isGeometryFlipped ? .down : .up }
        return .up
    }
}

struct FluentPixelGeometry {
    let scale: CGFloat

    init(backingScale: CGFloat? = nil) {
        if let backingScale {
            scale = max(backingScale, 1)
        } else if let context = NSGraphicsContext.current?.cgContext {
            let deviceSize = context.convertToDeviceSpace(CGSize(width: 1, height: 1))
            scale = max(abs(deviceSize.width), abs(deviceSize.height), 1)
        } else {
            scale = max(NSScreen.main?.backingScaleFactor ?? 1, 1)
        }
    }

    var pixel: CGFloat { 1 / scale }
    var halfPixel: CGFloat { 0.5 / scale }

    func align(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    func containedAntialiasRect(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: halfPixel, dy: halfPixel)
    }
}

/// The visual metrics returned by a button style.
public struct FluentButtonAppearance {
    public let backgroundColor: NSColor
    public let foregroundColor: NSColor
    public let borderColor: NSColor
    public let borderGradientColors: [NSColor]?
    public let borderGradientEdge: FluentElevationBorderEdge
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let contentInsets: NSEdgeInsets
    public let focusRingColor: NSColor?
    public let focusRingWidth: CGFloat

    public init(
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        borderColor: NSColor,
        borderGradientColors: [NSColor]? = nil,
        borderGradientEdge: FluentElevationBorderEdge = .bottom,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 7,
        contentInsets: NSEdgeInsets = NSEdgeInsetsZero,
        focusRingColor: NSColor? = nil,
        focusRingWidth: CGFloat = 1.5
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.borderColor = borderColor
        self.borderGradientColors = borderGradientColors
        self.borderGradientEdge = borderGradientEdge
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.contentInsets = contentInsets
        self.focusRingColor = focusRingColor
        self.focusRingWidth = max(focusRingWidth, 0)
    }
}

@inline(__always)
func fluentHalfPixelInset(backingScale: CGFloat? = nil) -> CGFloat {
    FluentPixelGeometry(backingScale: backingScale).halfPixel
}

/// Applies the source brush geometry used by Button, DropDownButton, and ComboBox.
/// WinUI's `ControlElevationBorderBrush` is absolute, ending after three points rather
/// than spanning the entire control. The layer is still allowed to pad its final color
/// outside that interval, so the lower/upper edge reads as a shallow elevation lip.
@inline(__always)
func configureFluentElevationBorderLayer(_ layer: CAGradientLayer, mask: CAShapeLayer) {
    let scale = NSScreen.main?.backingScaleFactor ?? 1
    layer.contentsScale = scale
    mask.contentsScale = scale
    layer.startPoint = CGPoint(x: 0.5, y: 0)
    layer.endPoint = CGPoint(x: 0.5, y: 1)
    mask.fillColor = NSColor.black.cgColor
    mask.fillRule = .evenOdd
    mask.strokeColor = nil
    layer.mask = mask
    // Mounting can configure colors before the control has non-zero bounds. Keep the shared
    // gradient inert until the first explicit visual-geometry synchronization.
    layer.isHidden = true
    mask.isHidden = true
}

@inline(__always)
func updateFluentElevationBorderLayer(
    _ layer: CAGradientLayer,
    mask: CAShapeLayer,
    bounds: CGRect,
    appearance: FluentButtonAppearance,
    visualYAxis: FluentVisualYAxis,
    backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 1
) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    let borderWidth = appearance.borderWidth
    let extent = min(CGFloat(3), bounds.height)
    let normalizedExtent = extent / bounds.height
    // Gradient unit coordinates are local, but AppKit may flip the entire child layer when it is
    // composited into its control. Anchor the brush using the control root's actual visual axis.
    let visualBottom = visualYAxis.visualBottom
    let visualTop = visualYAxis.visualTop
    let inwardFromBottom = -normalizedExtent * visualYAxis.visualDownSign
    let inwardFromTop = normalizedExtent * visualYAxis.visualDownSign
    let sourceColors = (appearance.borderGradientColors
        ?? [appearance.borderColor, appearance.borderColor]).map(\.cgColor)
    // Keep the WinUI brush's source stop order stable. Mirroring the edge geometry and the
    // colors together cancels the correction and puts the stronger stop back on the visual top.
    layer.colors = sourceColors
    if appearance.borderGradientEdge == .bottom {
        layer.startPoint = CGPoint(x: 0.5, y: visualBottom)
        layer.endPoint = CGPoint(x: 0.5, y: visualBottom + inwardFromBottom)
    } else {
        layer.startPoint = CGPoint(x: 0.5, y: visualTop)
        layer.endPoint = CGPoint(x: 0.5, y: visualTop + inwardFromTop)
    }
    let resolvedScale = max(backingScale, 1)
    layer.contentsScale = resolvedScale
    mask.contentsScale = resolvedScale
    layer.locations = [0.33, 1]
    layer.frame = bounds
    mask.frame = bounds
    // Keep the rounded antialiasing footprint inside the layer at both 1x and 2x. The background
    // still owns the complete bounds; only the painted border ring is inset by half a device pixel.
    let visualBounds = FluentPixelGeometry(backingScale: resolvedScale)
        .containedAntialiasRect(in: bounds)
    let innerRect = visualBounds.insetBy(dx: borderWidth, dy: borderWidth)
    let ring = CGMutablePath()
    ring.addRoundedRect(
        in: visualBounds,
        cornerWidth: appearance.cornerRadius,
        cornerHeight: appearance.cornerRadius
    )
    if innerRect.width > 0, innerRect.height > 0 {
        ring.addRoundedRect(
            in: innerRect,
            cornerWidth: max(appearance.cornerRadius - borderWidth, 0),
            cornerHeight: max(appearance.cornerRadius - borderWidth, 0)
        )
    }
    mask.path = ring
    mask.isHidden = borderWidth <= 0
    layer.isHidden = borderWidth <= 0
}

/// Applies the shared Button faceplate as one animation transaction. DropDownButton and the
/// closed ComboBox trigger intentionally use this helper instead of maintaining separate implicit
/// background and elevation animations.
func applyFluentButtonChrome(
    to layer: CALayer,
    elevationLayer: CAGradientLayer,
    elevationMask: CAShapeLayer,
    bounds: CGRect,
    appearance: FluentButtonAppearance,
    visualYAxis: FluentVisualYAxis,
    backingScale: CGFloat,
    animationCoordinator: FluentAnimationCoordinator,
    motion: FluentMotionToken,
    keyPrefix: String = "fluent.buttonChrome",
    animated: Bool
) {
    let colors = (appearance.borderGradientColors ?? [appearance.borderColor, appearance.borderColor]).map(\.cgColor)
    let targetCornerRadius = appearance.cornerRadius as NSNumber
    let changes = [
        FluentLayerAnimationChange(
            layer: layer,
            key: "\(keyPrefix).background",
            keyPath: "backgroundColor",
            toValue: appearance.backgroundColor.cgColor
        ) { layer.backgroundColor = appearance.backgroundColor.cgColor },
        FluentLayerAnimationChange(
            layer: layer,
            key: "\(keyPrefix).cornerRadius",
            keyPath: "cornerRadius",
            toValue: targetCornerRadius
        ) { layer.cornerRadius = appearance.cornerRadius },
        FluentLayerAnimationChange(
            layer: elevationLayer,
            key: "\(keyPrefix).elevation",
            keyPath: "colors",
            toValue: colors
        ) { elevationLayer.colors = colors }
    ]
    layer.borderWidth = 0
    layer.cornerCurve = .continuous
    elevationLayer.isHidden = false
    animationCoordinator.animateState(changes, motion: motion, animated: animated)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updateFluentElevationBorderLayer(
        elevationLayer,
        mask: elevationMask,
        bounds: bounds,
        appearance: appearance,
        visualYAxis: visualYAxis,
        backingScale: backingScale
    )
    CATransaction.commit()
}

/// Supplies state-dependent visual metrics to a native Fluent button.
public protocol FluentButtonStyle {
    func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance
}

/// The default role-aware Fluent button appearance.
public struct FluentAutomaticButtonStyle: FluentButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        switch configuration.role {
        case .standard:
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
        case .primary:
            let usesElevationBorder = state == .normal || state == .pointerOver || state == .focused
            let elevationBorder = theme.accentElevationBorderColors
            return FluentButtonAppearance(
                backgroundColor: theme.accentFill(for: state),
                foregroundColor: state == .pressed
                    ? theme.textOnAccentSecondary
                    : (state == .disabled ? theme.textOnAccentDisabled : theme.textOnAccent),
                borderColor: usesElevationBorder ? (elevationBorder.last ?? .clear) : .clear,
                borderGradientColors: usesElevationBorder ? elevationBorder : nil,
                borderGradientEdge: .bottom,
                borderWidth: theme.controlStrokeWidth,
                cornerRadius: theme.buttonCornerRadius,
                contentInsets: theme.controlPadding,
                focusRingColor: theme.accent,
                focusRingWidth: theme.focusStrokeWidth
            )
        case .destructive:
            let alpha: CGFloat = state == .pressed ? 0.72 : (state == .pointerOver ? 0.88 : 1)
            return FluentButtonAppearance(
                backgroundColor: NSColor.systemRed.withAlphaComponent(configuration.isEnabled ? alpha : 0.35),
                foregroundColor: .white,
                borderColor: NSColor.systemRed,
                borderWidth: theme.controlStrokeWidth,
                cornerRadius: theme.buttonCornerRadius,
                contentInsets: theme.controlPadding,
                focusRingColor: NSColor.systemRed,
                focusRingWidth: theme.focusStrokeWidth
            )
        }
    }
}

/// A filled accent style for primary actions.
public struct FluentAccentButtonStyle: FluentButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let usesElevationBorder = state == .normal || state == .pointerOver || state == .focused
        let elevationBorder = theme.accentElevationBorderColors
        return FluentButtonAppearance(
            backgroundColor: theme.accentFill(for: state),
            foregroundColor: state == .pressed
                ? theme.textOnAccentSecondary
                : (state == .disabled ? theme.textOnAccentDisabled : theme.textOnAccent),
            borderColor: usesElevationBorder ? (elevationBorder.last ?? .clear) : .clear,
            borderGradientColors: usesElevationBorder ? elevationBorder : nil,
            borderGradientEdge: .bottom,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            contentInsets: theme.controlPadding,
            focusRingColor: theme.accent,
            focusRingWidth: theme.focusStrokeWidth
        )
    }
}

/// A low-emphasis style for toolbar and inline commands.
public struct FluentBorderlessButtonStyle: FluentButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let foreground = configuration.isEnabled ? theme.accentTextPrimary : theme.textDisabled
        let background: NSColor = switch state {
        case .pointerOver: theme.subtleFillSecondary
        case .pressed: theme.subtleFillTertiary
        default: .clear
        }
        return FluentButtonAppearance(
            backgroundColor: background,
            foregroundColor: foreground,
            borderColor: .clear,
            borderWidth: 0,
            cornerRadius: theme.buttonCornerRadius,
            contentInsets: theme.controlPadding,
            focusRingColor: theme.accent,
            focusRingWidth: theme.focusStrokeWidth
        )
    }
}

/// An outlined style that keeps the button visually distinct without a filled surface.
public struct FluentOutlineButtonStyle: FluentButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let foreground = configuration.isEnabled ? theme.accentTextPrimary : theme.textDisabled
        let background: NSColor = switch state {
        case .pointerOver: theme.subtleFillSecondary
        case .pressed: theme.subtleFillTertiary
        default: .clear
        }
        return FluentButtonAppearance(
            backgroundColor: background,
            foregroundColor: foreground,
            borderColor: configuration.isEnabled ? theme.accentTextPrimary : theme.controlStroke,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            contentInsets: theme.controlPadding,
            focusRingColor: theme.accent,
            focusRingWidth: theme.focusStrokeWidth
        )
    }
}

public extension FluentButtonStyle where Self == FluentAutomaticButtonStyle {
    static var automatic: FluentAutomaticButtonStyle { FluentAutomaticButtonStyle() }
}

public extension FluentButtonStyle where Self == FluentAccentButtonStyle {
    static var accent: FluentAccentButtonStyle { FluentAccentButtonStyle() }
}

public extension FluentButtonStyle where Self == FluentBorderlessButtonStyle {
    static var borderless: FluentBorderlessButtonStyle { FluentBorderlessButtonStyle() }
}

public extension FluentButtonStyle where Self == FluentOutlineButtonStyle {
    static var outline: FluentOutlineButtonStyle { FluentOutlineButtonStyle() }
}

public struct FluentToggleStyleConfiguration {
    public let isOn: Bool
    public let isEnabled: Bool
    public let isPointerOver: Bool
    public let isPressed: Bool
    public let isDragging: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(
        isOn: Bool,
        isEnabled: Bool,
        isPointerOver: Bool,
        isPressed: Bool = false,
        isDragging: Bool = false,
        controlSize: FluentControlSize,
        theme: FluentTheme
    ) {
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.isPointerOver = isPointerOver
        self.isPressed = isPressed
        self.isDragging = isDragging
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentToggleAppearance {
    public let trackColor: NSColor
    public let trackBorderColor: NSColor
    public let trackBorderWidth: CGFloat
    public let knobColor: NSColor
    public let knobBorderColor: NSColor
    public let knobBorderWidth: CGFloat
    public let labelColor: NSColor
    public let knobShadowColor: NSColor
    public let trackSize: CGSize
    public let knobDiameter: CGFloat
    public let knobSize: CGSize
    public let labelSpacing: CGFloat

    public init(
        trackColor: NSColor,
        trackBorderColor: NSColor,
        trackBorderWidth: CGFloat = 1,
        knobColor: NSColor,
        knobBorderColor: NSColor = .clear,
        knobBorderWidth: CGFloat = 0,
        labelColor: NSColor,
        knobShadowColor: NSColor = NSColor.black.withAlphaComponent(0.32),
        trackSize: CGSize = CGSize(width: 40, height: 20),
        knobDiameter: CGFloat = 12,
        knobSize: CGSize? = nil,
        labelSpacing: CGFloat = 12
    ) {
        self.trackColor = trackColor
        self.trackBorderColor = trackBorderColor
        self.trackBorderWidth = max(trackBorderWidth, 0)
        self.knobColor = knobColor
        self.knobBorderColor = knobBorderColor
        self.knobBorderWidth = max(knobBorderWidth, 0)
        self.labelColor = labelColor
        self.knobShadowColor = knobShadowColor
        self.trackSize = trackSize
        self.knobDiameter = max(knobDiameter, 1)
        let resolvedKnobSize = knobSize ?? CGSize(width: knobDiameter, height: knobDiameter)
        self.knobSize = CGSize(width: max(resolvedKnobSize.width, 1), height: max(resolvedKnobSize.height, 1))
        self.labelSpacing = max(labelSpacing, 0)
    }
}

public protocol FluentToggleStyle {
    func appearance(for configuration: FluentToggleStyleConfiguration) -> FluentToggleAppearance
}

public struct FluentAutomaticToggleStyle: FluentToggleStyle {
    public init() {}

    public func appearance(for configuration: FluentToggleStyleConfiguration) -> FluentToggleAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isPressed || configuration.isDragging {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let thumbSize: CGSize
        if configuration.isPressed || configuration.isDragging {
            thumbSize = CGSize(width: 17 * scale, height: 14 * scale)
        } else if configuration.isPointerOver {
            thumbSize = CGSize(width: 14 * scale, height: 14 * scale)
        } else {
            thumbSize = CGSize(width: 12 * scale, height: 12 * scale)
        }
        return FluentToggleAppearance(
            trackColor: theme.toggleTrackFill(isOn: configuration.isOn, state: state),
            trackBorderColor: theme.toggleTrackStroke(isOn: configuration.isOn, state: state),
            trackBorderWidth: configuration.isOn && !theme.isHighContrast ? 0 : theme.controlStrokeWidth,
            knobColor: theme.toggleKnobFill(isOn: configuration.isOn, state: state),
            knobBorderColor: theme.toggleKnobStroke(isOn: configuration.isOn, state: state),
            knobBorderWidth: configuration.isOn && configuration.isEnabled ? 1 : 0,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            trackSize: CGSize(width: 40 * scale, height: 20 * scale),
            knobDiameter: thumbSize.height,
            knobSize: thumbSize,
            labelSpacing: 12 * theme.density.metricScale
        )
    }
}

public struct FluentMonochromeToggleStyle: FluentToggleStyle {
    public init() {}

    public func appearance(for configuration: FluentToggleStyleConfiguration) -> FluentToggleAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let track = configuration.isOn ? theme.controlStrokeStrong : theme.controlFillTertiary
        let thumbSize: CGSize
        if configuration.isPressed || configuration.isDragging {
            thumbSize = CGSize(width: 17 * scale, height: 14 * scale)
        } else if configuration.isPointerOver {
            thumbSize = CGSize(width: 14 * scale, height: 14 * scale)
        } else {
            thumbSize = CGSize(width: 12 * scale, height: 12 * scale)
        }
        return FluentToggleAppearance(
            trackColor: track.withAlphaComponent(configuration.isEnabled ? 1 : 0.45),
            trackBorderColor: theme.controlStrokeStrong,
            trackBorderWidth: theme.controlStrokeWidth,
            knobColor: configuration.isOn ? theme.windowBackground : theme.textPrimary,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            knobShadowColor: .clear,
            trackSize: CGSize(width: 40 * scale, height: 20 * scale),
            knobDiameter: thumbSize.height,
            knobSize: thumbSize,
            labelSpacing: 12 * theme.density.metricScale
        )
    }
}

public struct FluentSliderStyleConfiguration {
    public let valueFraction: CGFloat
    public let isEnabled: Bool
    public let isPointerOver: Bool
    public let isDragging: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(valueFraction: CGFloat, isEnabled: Bool, isPointerOver: Bool, isDragging: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.valueFraction = min(max(valueFraction, 0), 1)
        self.isEnabled = isEnabled
        self.isPointerOver = isPointerOver
        self.isDragging = isDragging
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentSliderAppearance {
    public let trackColor: NSColor
    public let fillColor: NSColor
    /// The inner thumb fill. Kept under its original name for source compatibility.
    public let knobColor: NSColor
    /// Retained for custom styles compiled against the original single-layer slider.
    public let haloColor: NSColor
    public let trackHeight: CGFloat
    /// The current inner thumb diameter. Kept under its original name for source compatibility.
    public let knobDiameter: CGFloat
    /// Retained for custom styles compiled against the original single-layer slider.
    public let haloDiameter: CGFloat
    public let outerThumbColor: NSColor
    public let outerThumbBorderColor: NSColor
    public let outerThumbBorderWidth: CGFloat
    public let outerThumbDiameter: CGFloat

    public init(
        trackColor: NSColor,
        fillColor: NSColor,
        knobColor: NSColor,
        haloColor: NSColor,
        trackHeight: CGFloat = 4,
        knobDiameter: CGFloat = 14,
        haloDiameter: CGFloat = 22,
        outerThumbColor: NSColor = .windowBackgroundColor,
        outerThumbBorderColor: NSColor = .separatorColor,
        outerThumbBorderWidth: CGFloat = 1,
        outerThumbDiameter: CGFloat? = nil
    ) {
        self.trackColor = trackColor
        self.fillColor = fillColor
        self.knobColor = knobColor
        self.haloColor = haloColor
        self.trackHeight = max(trackHeight, 1)
        self.knobDiameter = max(knobDiameter, 1)
        self.haloDiameter = max(haloDiameter, knobDiameter)
        self.outerThumbColor = outerThumbColor
        self.outerThumbBorderColor = outerThumbBorderColor
        self.outerThumbBorderWidth = max(outerThumbBorderWidth, 0)
        self.outerThumbDiameter = max(outerThumbDiameter ?? max(knobDiameter + 4, 18), knobDiameter)
    }
}

public protocol FluentSliderStyle {
    func appearance(for configuration: FluentSliderStyleConfiguration) -> FluentSliderAppearance
}

public struct FluentAutomaticSliderStyle: FluentSliderStyle {
    public init() {}

    public func appearance(for configuration: FluentSliderStyleConfiguration) -> FluentSliderAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isDragging {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let innerDiameter: CGFloat = switch state {
        case .pointerOver, .disabled: 14
        case .pressed: 10
        default: 12
        }
        return FluentSliderAppearance(
            trackColor: theme.controlStrokeStrong.withAlphaComponent(configuration.isEnabled ? 1 : 0.35),
            fillColor: theme.accentFill(for: state),
            knobColor: theme.accentFill(for: state),
            haloColor: .clear,
            trackHeight: (theme.isHighContrast ? 6 : 4) * scale,
            knobDiameter: (theme.isHighContrast ? innerDiameter + 2 : innerDiameter) * scale,
            haloDiameter: (theme.isHighContrast ? 24 : 22) * scale,
            outerThumbColor: theme.isDark
                ? NSColor(calibratedWhite: 0.271, alpha: configuration.isEnabled ? 1 : 0.70)
                : NSColor(calibratedWhite: 1, alpha: configuration.isEnabled ? 1 : 0.70),
            outerThumbBorderColor: theme.controlStroke,
            outerThumbBorderWidth: theme.controlStrokeWidth,
            outerThumbDiameter: (theme.isHighContrast ? 20 : 18) * scale
        )
    }
}

public struct FluentNeutralSliderStyle: FluentSliderStyle {
    public init() {}

    public func appearance(for configuration: FluentSliderStyleConfiguration) -> FluentSliderAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isDragging {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let alpha: CGFloat = configuration.isEnabled ? (state == .pressed ? 0.70 : 0.90) : 0.35
        let innerDiameter: CGFloat = switch state {
        case .pointerOver, .disabled: 14
        case .pressed: 10
        default: 12
        }
        return FluentSliderAppearance(
            trackColor: theme.controlStrokeStrong.withAlphaComponent(configuration.isEnabled ? 1 : 0.35),
            fillColor: theme.controlStrokeStrong.withAlphaComponent(alpha),
            knobColor: theme.textPrimary.withAlphaComponent(alpha),
            haloColor: .clear,
            trackHeight: (theme.isHighContrast ? 6 : 4) * scale,
            knobDiameter: (theme.isHighContrast ? innerDiameter + 2 : innerDiameter) * scale,
            haloDiameter: (theme.isHighContrast ? 24 : 22) * scale,
            outerThumbColor: theme.isDark
                ? NSColor(calibratedWhite: 0.271, alpha: configuration.isEnabled ? 1 : 0.70)
                : NSColor(calibratedWhite: 1, alpha: configuration.isEnabled ? 1 : 0.70),
            outerThumbBorderColor: theme.controlStroke,
            outerThumbBorderWidth: theme.controlStrokeWidth,
            outerThumbDiameter: (theme.isHighContrast ? 20 : 18) * scale
        )
    }
}

public enum FluentTextFieldBorderShape: Hashable, Sendable {
    case rounded
    case underline
}

public struct FluentTextFieldStyleConfiguration {
    public let isEnabled: Bool
    public let isFocused: Bool
    public let isPointerOver: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(
        isEnabled: Bool,
        isFocused: Bool,
        isPointerOver: Bool = false,
        controlSize: FluentControlSize,
        theme: FluentTheme
    ) {
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.isPointerOver = isPointerOver
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentTextFieldAppearance {
    public let backgroundColor: NSColor
    public let textColor: NSColor
    public let borderColor: NSColor
    public let borderGradientColors: [NSColor]?
    public let borderGradientLocations: [CGFloat]
    public let borderGradientEdge: FluentElevationBorderEdge
    public let borderGradientExtent: CGFloat
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let borderShape: FluentTextFieldBorderShape
    public let font: NSFont?
    /// Optional focused-state accent drawn only along the visual bottom edge, matching the
    /// TextControlBorderThemeThicknessFocused 1,1,1,2 contract.
    public let focusIndicatorColor: NSColor?
    public let focusIndicatorWidth: CGFloat

    public init(
        backgroundColor: NSColor,
        textColor: NSColor,
        borderColor: NSColor,
        borderGradientColors: [NSColor]? = nil,
        borderGradientLocations: [CGFloat] = [0.5, 1],
        borderGradientEdge: FluentElevationBorderEdge = .bottom,
        borderGradientExtent: CGFloat = 2,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 7,
        borderShape: FluentTextFieldBorderShape = .rounded,
        font: NSFont? = nil,
        focusIndicatorColor: NSColor? = nil,
        focusIndicatorWidth: CGFloat = 0
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderGradientColors = borderGradientColors
        self.borderGradientLocations = borderGradientLocations
        self.borderGradientEdge = borderGradientEdge
        self.borderGradientExtent = max(borderGradientExtent, 0)
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.borderShape = borderShape
        self.font = font
        self.focusIndicatorColor = focusIndicatorColor
        self.focusIndicatorWidth = max(focusIndicatorWidth, 0)
    }
}

public protocol FluentTextFieldStyle {
    func appearance(for configuration: FluentTextFieldStyleConfiguration) -> FluentTextFieldAppearance
}

public struct FluentAutomaticTextFieldStyle: FluentTextFieldStyle {
    public init() {}

    public func appearance(for configuration: FluentTextFieldStyleConfiguration) -> FluentTextFieldAppearance {
        let theme = configuration.theme
        let bodyFont = theme.typography.font(for: .body)
        return FluentTextFieldAppearance(
            backgroundColor: theme.textControlBackground(
                focused: configuration.isFocused,
                pointerOver: configuration.isPointerOver,
                enabled: configuration.isEnabled
            ),
            textColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            borderColor: theme.controlStrokeDefault,
            borderGradientColors: configuration.isEnabled
                ? theme.textControlElevationBorderColors
                : nil,
            borderGradientLocations: [0.5, 1],
            borderGradientEdge: .bottom,
            borderGradientExtent: 2,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            font: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            focusIndicatorColor: configuration.isFocused ? theme.textControlFocusStroke : nil,
            focusIndicatorWidth: configuration.isFocused ? 2 : 0
        )
    }
}

public struct FluentUnderlineTextFieldStyle: FluentTextFieldStyle {
    public init() {}

    public func appearance(for configuration: FluentTextFieldStyleConfiguration) -> FluentTextFieldAppearance {
        let theme = configuration.theme
        let bodyFont = theme.typography.font(for: .body)
        return FluentTextFieldAppearance(
            backgroundColor: .clear,
            textColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            borderColor: configuration.isFocused ? theme.textControlFocusStroke : theme.controlStrokeStrong,
            borderWidth: configuration.isFocused ? max(2, theme.controlStrokeWidth) : theme.controlStrokeWidth,
            cornerRadius: 0,
            borderShape: .underline,
            font: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale)
        )
    }
}

public struct FluentStepperStyleConfiguration {
    public let isEnabled: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isEnabled: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isEnabled = isEnabled
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentStepperAppearance {
    public let labelColor: NSColor
    public let labelFont: NSFont
    public let spacing: CGFloat
    public let valueFieldWidth: CGFloat
    public let textFieldStyle: any FluentTextFieldStyle
    public let drawsContainerChrome: Bool
    public let arrowColumnWidth: CGFloat

    public init(
        labelColor: NSColor,
        labelFont: NSFont,
        spacing: CGFloat = 8,
        valueFieldWidth: CGFloat = 88,
        textFieldStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle(),
        drawsContainerChrome: Bool = false,
        arrowColumnWidth: CGFloat = 28
    ) {
        self.labelColor = labelColor
        self.labelFont = labelFont
        self.spacing = max(spacing, 0)
        self.valueFieldWidth = max(valueFieldWidth, 36)
        self.textFieldStyle = textFieldStyle
        self.drawsContainerChrome = drawsContainerChrome
        self.arrowColumnWidth = max(arrowColumnWidth, 20)
    }
}

public protocol FluentStepperStyle {
    func appearance(for configuration: FluentStepperStyleConfiguration) -> FluentStepperAppearance
}

public struct FluentAutomaticStepperStyle: FluentStepperStyle {
    public init() {}

    public func appearance(for configuration: FluentStepperStyleConfiguration) -> FluentStepperAppearance {
        let theme = configuration.theme
        let calloutFont = theme.typography.font(for: .callout)
        return FluentStepperAppearance(
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: calloutFont.withSize(calloutFont.pointSize * configuration.controlSize.metricScale),
            spacing: 8 * theme.density.metricScale,
            valueFieldWidth: 88 * theme.density.metricScale,
            textFieldStyle: FluentAutomaticTextFieldStyle()
        )
    }
}

public struct FluentInlineStepperStyle: FluentStepperStyle {
    public init() {}

    public func appearance(for configuration: FluentStepperStyleConfiguration) -> FluentStepperAppearance {
        let theme = configuration.theme
        let calloutFont = theme.typography.font(for: .callout)
        return FluentStepperAppearance(
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: calloutFont.withSize(calloutFont.pointSize * configuration.controlSize.metricScale),
            spacing: 6 * theme.density.metricScale,
            valueFieldWidth: 72 * theme.density.metricScale,
            textFieldStyle: FluentUnderlineTextFieldStyle()
        )
    }
}

/// A full-width NumberBox-like stepper surface with the label supplied by the surrounding layout.
/// The native value editor and incrementor remain separate semantic controls, while the visible
/// field uses the standard filled TextBox appearance.
public struct FluentNumberBoxStepperStyle: FluentStepperStyle {
    public let valueFieldWidth: CGFloat

    public init(valueFieldWidth: CGFloat = 248) {
        self.valueFieldWidth = max(valueFieldWidth, 120)
    }

    public func appearance(for configuration: FluentStepperStyleConfiguration) -> FluentStepperAppearance {
        let theme = configuration.theme
        let bodyFont = theme.typography.font(for: .body)
        return FluentStepperAppearance(
            labelColor: .clear,
            labelFont: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            spacing: 0,
            valueFieldWidth: valueFieldWidth * configuration.controlSize.metricScale,
            textFieldStyle: FluentAutomaticTextFieldStyle(),
            drawsContainerChrome: true,
            // NumberBox.xaml sets SpinButtonsColumn.Width to 72 in SpinButtonsVisible.
            arrowColumnWidth: 72 * configuration.controlSize.metricScale
        )
    }
}

public extension FluentStepperStyle where Self == FluentAutomaticStepperStyle {
    static var automatic: FluentAutomaticStepperStyle { FluentAutomaticStepperStyle() }
}

public extension FluentStepperStyle where Self == FluentInlineStepperStyle {
    static var inline: FluentInlineStepperStyle { FluentInlineStepperStyle() }
}

public extension FluentStepperStyle where Self == FluentNumberBoxStepperStyle {
    static var numberBox: FluentNumberBoxStepperStyle { FluentNumberBoxStepperStyle() }
}

public extension FluentToggleStyle where Self == FluentAutomaticToggleStyle {
    static var automatic: FluentAutomaticToggleStyle { FluentAutomaticToggleStyle() }
}

public extension FluentToggleStyle where Self == FluentMonochromeToggleStyle {
    static var monochrome: FluentMonochromeToggleStyle { FluentMonochromeToggleStyle() }
}

public extension FluentSliderStyle where Self == FluentAutomaticSliderStyle {
    static var automatic: FluentAutomaticSliderStyle { FluentAutomaticSliderStyle() }
}

public extension FluentSliderStyle where Self == FluentNeutralSliderStyle {
    static var neutral: FluentNeutralSliderStyle { FluentNeutralSliderStyle() }
}

public struct FluentProgressStyleConfiguration {
    public let valueFraction: CGFloat
    public let isIndeterminate: Bool
    public let state: FluentProgressState
    public let theme: FluentTheme

    public init(
        valueFraction: CGFloat,
        isIndeterminate: Bool = false,
        state: FluentProgressState = .normal,
        theme: FluentTheme
    ) {
        self.valueFraction = min(max(valueFraction, 0), 1)
        self.isIndeterminate = isIndeterminate
        self.state = state
        self.theme = theme
    }
}

public struct FluentProgressAppearance {
    public let trackColor: NSColor
    public let progressColor: NSColor
    public let trackHeight: CGFloat
    public let indicatorHeight: CGFloat
    public let trackCornerRadius: CGFloat
    public let cornerRadius: CGFloat
    public let borderColor: NSColor
    public let borderWidth: CGFloat

    public init(
        trackColor: NSColor,
        progressColor: NSColor,
        trackHeight: CGFloat = 4,
        indicatorHeight: CGFloat? = nil,
        trackCornerRadius: CGFloat? = nil,
        cornerRadius: CGFloat = 2,
        borderColor: NSColor = .clear,
        borderWidth: CGFloat = 0
    ) {
        self.trackColor = trackColor
        self.progressColor = progressColor
        self.trackHeight = max(trackHeight, 1)
        self.indicatorHeight = max(indicatorHeight ?? trackHeight, 1)
        self.trackCornerRadius = max(trackCornerRadius ?? min(cornerRadius, trackHeight / 2), 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
    }
}

public protocol FluentProgressStyle {
    func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance
}

public struct FluentAutomaticProgressStyle: FluentProgressStyle {
    public init() {}

    public func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance {
        let theme = configuration.theme
        let progressColor: NSColor = switch configuration.state {
        case .normal: theme.accentFillDefault
        case .paused: theme.isHighContrast ? theme.controlStrokeStrong : .systemYellow
        case .error: theme.isHighContrast ? NSColor.systemRed : .systemRed
        }
        let scale = theme.density.metricScale
        return FluentProgressAppearance(
            trackColor: theme.controlStrokeStrong,
            progressColor: progressColor,
            trackHeight: (theme.isHighContrast ? 2 : 1) * scale,
            indicatorHeight: (theme.isHighContrast ? 4 : 3) * scale,
            trackCornerRadius: (theme.isHighContrast ? 1 : 0.5) * scale,
            cornerRadius: (theme.isHighContrast ? 2 : 1.5) * scale,
            borderColor: theme.isHighContrast ? theme.controlStrokeStrong : .clear,
            borderWidth: theme.isHighContrast ? 1 : 0
        )
    }
}

public struct FluentNeutralProgressStyle: FluentProgressStyle {
    public init() {}

    public func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance {
        let theme = configuration.theme
        let progressColor: NSColor = switch configuration.state {
        case .normal: theme.controlStrokeStrong
        case .paused: .systemYellow
        case .error: .systemRed
        }
        let scale = theme.density.metricScale
        return FluentProgressAppearance(
            trackColor: theme.controlStrokeStrong.withAlphaComponent(0.45),
            progressColor: progressColor,
            trackHeight: (theme.isHighContrast ? 2 : 1) * scale,
            indicatorHeight: (theme.isHighContrast ? 4 : 3) * scale,
            trackCornerRadius: (theme.isHighContrast ? 1 : 0.5) * scale,
            cornerRadius: (theme.isHighContrast ? 2 : 1.5) * scale,
            borderColor: theme.isHighContrast ? theme.controlStrokeStrong : .clear,
            borderWidth: theme.isHighContrast ? 1 : 0
        )
    }
}

public extension FluentProgressStyle where Self == FluentAutomaticProgressStyle {
    static var automatic: FluentAutomaticProgressStyle { FluentAutomaticProgressStyle() }
}

public extension FluentProgressStyle where Self == FluentNeutralProgressStyle {
    static var neutral: FluentNeutralProgressStyle { FluentNeutralProgressStyle() }
}

public struct FluentCheckBoxStyleConfiguration {
    public let isChecked: Bool
    public let isEnabled: Bool
    public let isPointerOver: Bool
    public let isPressed: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isChecked: Bool, isEnabled: Bool, isPointerOver: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.init(
            isChecked: isChecked,
            isEnabled: isEnabled,
            isPointerOver: isPointerOver,
            isPressed: false,
            controlSize: controlSize,
            theme: theme
        )
    }

    public init(isChecked: Bool, isEnabled: Bool, isPointerOver: Bool, isPressed: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.isPointerOver = isPointerOver
        self.isPressed = isPressed
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentCheckBoxAppearance {
    public let boxSize: CGFloat
    public let cornerRadius: CGFloat
    public let fillColor: NSColor
    public let borderColor: NSColor
    public let borderWidth: CGFloat
    public let markColor: NSColor
    public let labelColor: NSColor
    public let labelFont: NSFont
    public let labelSpacing: CGFloat

    public init(
        boxSize: CGFloat = 18,
        cornerRadius: CGFloat = 4,
        fillColor: NSColor,
        borderColor: NSColor,
        borderWidth: CGFloat = 1,
        markColor: NSColor,
        labelColor: NSColor,
        labelFont: NSFont,
        labelSpacing: CGFloat = 8
    ) {
        self.boxSize = max(boxSize, 1)
        self.cornerRadius = max(cornerRadius, 0)
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.markColor = markColor
        self.labelColor = labelColor
        self.labelFont = labelFont
        self.labelSpacing = max(labelSpacing, 0)
    }
}

public protocol FluentCheckBoxStyle {
    func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance
}

public struct FluentAutomaticCheckBoxStyle: FluentCheckBoxStyle {
    public init() {}

    public func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isPressed {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let uncheckedFill: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
        case .disabled: theme.controlFill.withAlphaComponent(0.45)
        default: theme.controlFill
        }
        let fill = configuration.isChecked
            ? theme.accentFill(for: state)
            : uncheckedFill
        let border = configuration.isChecked && !theme.isHighContrast
            ? theme.accentFill(for: state)
            : theme.controlStrokeStrong.withAlphaComponent(state == .disabled ? 0.35 : 1)
        return FluentCheckBoxAppearance(
            boxSize: 20 * scale,
            cornerRadius: 3 * scale,
            fillColor: fill,
            borderColor: border,
            borderWidth: theme.controlStrokeWidth,
            markColor: state == .pressed
                ? theme.textOnAccentSecondary
                : (state == .disabled ? theme.textOnAccentDisabled : theme.textOnAccent),
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: theme.typography.font(for: .body).withSize(theme.typography.font(for: .body).pointSize * configuration.controlSize.metricScale),
            labelSpacing: 8 * scale
        )
    }
}

public struct FluentMonochromeCheckBoxStyle: FluentCheckBoxStyle {
    public init() {}

    public func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isPressed {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let alpha: CGFloat = configuration.isEnabled ? (state == .pressed ? 0.70 : 1) : 0.35
        let uncheckedFill: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
        default: theme.controlFill
        }
        let bodyFont = theme.typography.font(for: .body)
        return FluentCheckBoxAppearance(
            boxSize: 20 * scale,
            cornerRadius: 3 * scale,
            fillColor: (configuration.isChecked ? theme.controlStrokeStrong : uncheckedFill).withAlphaComponent(alpha),
            borderColor: theme.controlStrokeStrong.withAlphaComponent(alpha),
            borderWidth: theme.controlStrokeWidth,
            markColor: theme.windowBackground,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            labelSpacing: 8 * scale
        )
    }
}

public extension FluentCheckBoxStyle where Self == FluentAutomaticCheckBoxStyle {
    static var automatic: FluentAutomaticCheckBoxStyle { FluentAutomaticCheckBoxStyle() }
}

public extension FluentCheckBoxStyle where Self == FluentMonochromeCheckBoxStyle {
    static var monochrome: FluentMonochromeCheckBoxStyle { FluentMonochromeCheckBoxStyle() }
}

public struct FluentRadioButtonStyleConfiguration {
    public let isSelected: Bool
    public let isEnabled: Bool
    public let isPointerOver: Bool
    public let isPressed: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isSelected: Bool, isEnabled: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.init(
            isSelected: isSelected,
            isEnabled: isEnabled,
            isPointerOver: false,
            isPressed: false,
            controlSize: controlSize,
            theme: theme
        )
    }

    public init(isSelected: Bool, isEnabled: Bool, isPointerOver: Bool, isPressed: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isPointerOver = isPointerOver
        self.isPressed = isPressed
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentRadioButtonAppearance {
    public let diameter: CGFloat
    public let fillColor: NSColor
    public let borderColor: NSColor
    public let borderWidth: CGFloat
    public let dotColor: NSColor
    public let dotDiameter: CGFloat
    public let labelColor: NSColor
    public let labelFont: NSFont
    public let labelSpacing: CGFloat

    public init(
        diameter: CGFloat = 18,
        fillColor: NSColor,
        borderColor: NSColor,
        borderWidth: CGFloat = 1,
        dotColor: NSColor,
        labelColor: NSColor,
        labelFont: NSFont,
        labelSpacing: CGFloat = 8,
        dotDiameter: CGFloat? = nil
    ) {
        self.diameter = max(diameter, 1)
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.dotColor = dotColor
        self.dotDiameter = min(max(dotDiameter ?? diameter * 0.6, 1), max(diameter, 1))
        self.labelColor = labelColor
        self.labelFont = labelFont
        self.labelSpacing = max(labelSpacing, 0)
    }
}

public protocol FluentRadioButtonStyle {
    func appearance(for configuration: FluentRadioButtonStyleConfiguration) -> FluentRadioButtonAppearance
}

public struct FluentAutomaticRadioButtonStyle: FluentRadioButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentRadioButtonStyleConfiguration) -> FluentRadioButtonAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isPressed {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let uncheckedFill: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
        case .disabled: theme.controlFill.withAlphaComponent(0.45)
        default: theme.controlFill
        }
        let dotDiameter: CGFloat = switch state {
        case .pointerOver, .disabled: 14
        case .pressed: 10
        default: 12
        }
        let bodyFont = theme.typography.font(for: .body)
        return FluentRadioButtonAppearance(
            diameter: 20 * scale,
            fillColor: configuration.isSelected
                ? theme.accentFill(for: state)
                : uncheckedFill,
            borderColor: configuration.isSelected && !theme.isHighContrast
                ? theme.accentFill(for: state)
                : theme.controlStrokeStrong.withAlphaComponent(state == .disabled ? 0.35 : 1),
            borderWidth: theme.controlStrokeWidth,
            dotColor: theme.textOnAccent,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            labelSpacing: 8 * scale,
            dotDiameter: (theme.isHighContrast ? dotDiameter + 2 : dotDiameter) * scale
        )
    }
}

public struct FluentMonochromeRadioButtonStyle: FluentRadioButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentRadioButtonStyleConfiguration) -> FluentRadioButtonAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let state: FluentControlState = if !configuration.isEnabled {
            .disabled
        } else if configuration.isPressed {
            .pressed
        } else if configuration.isPointerOver {
            .pointerOver
        } else {
            .normal
        }
        let alpha: CGFloat = configuration.isEnabled ? (state == .pressed ? 0.70 : 1) : 0.35
        let uncheckedFill: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
        default: theme.controlFill
        }
        let dotDiameter: CGFloat = switch state {
        case .pointerOver, .disabled: 14
        case .pressed: 10
        default: 12
        }
        let bodyFont = theme.typography.font(for: .body)
        return FluentRadioButtonAppearance(
            diameter: 20 * scale,
            fillColor: (configuration.isSelected ? theme.controlStrokeStrong : uncheckedFill).withAlphaComponent(alpha),
            borderColor: theme.controlStrokeStrong.withAlphaComponent(alpha),
            borderWidth: theme.controlStrokeWidth,
            dotColor: theme.windowBackground,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            labelSpacing: 8 * scale,
            dotDiameter: (theme.isHighContrast ? dotDiameter + 2 : dotDiameter) * scale
        )
    }
}

public extension FluentRadioButtonStyle where Self == FluentAutomaticRadioButtonStyle {
    static var automatic: FluentAutomaticRadioButtonStyle { FluentAutomaticRadioButtonStyle() }
}

public extension FluentRadioButtonStyle where Self == FluentMonochromeRadioButtonStyle {
    static var monochrome: FluentMonochromeRadioButtonStyle { FluentMonochromeRadioButtonStyle() }
}

public struct FluentSegmentedStyleConfiguration {
    public let selectedIndex: Int
    public let isEnabled: Bool
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(selectedIndex: Int, isEnabled: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.selectedIndex = selectedIndex
        self.isEnabled = isEnabled
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentSegmentedAppearance {
    public let backgroundColor: NSColor
    public let selectedSegmentColor: NSColor
    public let selectedHoverSegmentColor: NSColor
    public let selectedPressedSegmentColor: NSColor
    public let hoverColor: NSColor
    public let pressedColor: NSColor
    public let foregroundColor: NSColor
    public let hoverForegroundColor: NSColor
    public let pressedForegroundColor: NSColor
    public let selectedForegroundColor: NSColor
    public let selectedHoverForegroundColor: NSColor
    public let selectedPressedForegroundColor: NSColor
    public let borderColor: NSColor
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let font: NSFont
    public let segmentStyle: NSSegmentedControl.Style

    public init(
        backgroundColor: NSColor,
        selectedSegmentColor: NSColor,
        selectedHoverSegmentColor: NSColor? = nil,
        selectedPressedSegmentColor: NSColor? = nil,
        hoverColor: NSColor = .clear,
        pressedColor: NSColor? = nil,
        foregroundColor: NSColor = .labelColor,
        hoverForegroundColor: NSColor? = nil,
        pressedForegroundColor: NSColor? = nil,
        selectedForegroundColor: NSColor = .white,
        selectedHoverForegroundColor: NSColor? = nil,
        selectedPressedForegroundColor: NSColor? = nil,
        borderColor: NSColor,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 7,
        font: NSFont,
        segmentStyle: NSSegmentedControl.Style = .rounded
    ) {
        self.backgroundColor = backgroundColor
        self.selectedSegmentColor = selectedSegmentColor
        self.selectedHoverSegmentColor = selectedHoverSegmentColor ?? selectedSegmentColor
        self.selectedPressedSegmentColor = selectedPressedSegmentColor ?? selectedSegmentColor
        self.hoverColor = hoverColor
        self.pressedColor = pressedColor ?? hoverColor
        self.foregroundColor = foregroundColor
        self.hoverForegroundColor = hoverForegroundColor ?? foregroundColor
        self.pressedForegroundColor = pressedForegroundColor ?? foregroundColor
        self.selectedForegroundColor = selectedForegroundColor
        self.selectedHoverForegroundColor = selectedHoverForegroundColor ?? selectedForegroundColor
        self.selectedPressedForegroundColor = selectedPressedForegroundColor ?? selectedForegroundColor
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.font = font
        self.segmentStyle = segmentStyle
    }
}

public protocol FluentSegmentedStyle {
    func appearance(for configuration: FluentSegmentedStyleConfiguration) -> FluentSegmentedAppearance
}

public struct FluentAutomaticSegmentedStyle: FluentSegmentedStyle {
    public init() {}

    public func appearance(for configuration: FluentSegmentedStyleConfiguration) -> FluentSegmentedAppearance {
        let theme = configuration.theme
        let font = theme.typography.font(for: .callout).withSize(theme.typography.font(for: .callout).pointSize * configuration.controlSize.metricScale)
        return FluentSegmentedAppearance(
            backgroundColor: theme.controlFill,
            selectedSegmentColor: configuration.isEnabled ? theme.accentFillDefault : theme.accentFillDisabled,
            selectedHoverSegmentColor: configuration.isEnabled ? theme.accentFillSecondary : theme.accentFillDisabled,
            selectedPressedSegmentColor: configuration.isEnabled ? theme.accentFillTertiary : theme.accentFillDisabled,
            hoverColor: theme.controlFillSecondary,
            pressedColor: theme.controlFillTertiary,
            foregroundColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            hoverForegroundColor: configuration.isEnabled ? theme.textSecondary : theme.textDisabled,
            pressedForegroundColor: configuration.isEnabled ? theme.textSecondary.withAlphaComponent(0.72) : theme.textDisabled,
            selectedForegroundColor: configuration.isEnabled ? theme.textOnAccent : theme.textDisabled,
            selectedHoverForegroundColor: configuration.isEnabled ? theme.textOnAccent.withAlphaComponent(0.88) : theme.textDisabled,
            selectedPressedForegroundColor: configuration.isEnabled ? theme.textOnAccent.withAlphaComponent(0.72) : theme.textDisabled,
            borderColor: theme.isHighContrast ? theme.controlStrokeStrong : theme.controlStroke,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            font: font
        )
    }
}

public struct FluentNeutralSegmentedStyle: FluentSegmentedStyle {
    public init() {}

    public func appearance(for configuration: FluentSegmentedStyleConfiguration) -> FluentSegmentedAppearance {
        let theme = configuration.theme
        let font = theme.typography.font(for: .callout).withSize(theme.typography.font(for: .callout).pointSize * configuration.controlSize.metricScale)
        let selectedAlpha: CGFloat = configuration.isEnabled ? 1 : 0.35
        return FluentSegmentedAppearance(
            backgroundColor: theme.controlFill,
            selectedSegmentColor: theme.controlStrokeStrong.withAlphaComponent(selectedAlpha),
            selectedHoverSegmentColor: theme.controlStrokeStrong.withAlphaComponent(configuration.isEnabled ? 0.88 : 0.35),
            selectedPressedSegmentColor: theme.controlStrokeStrong.withAlphaComponent(configuration.isEnabled ? 0.72 : 0.35),
            hoverColor: theme.controlFillSecondary,
            pressedColor: theme.controlFillTertiary,
            foregroundColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            hoverForegroundColor: configuration.isEnabled ? theme.textSecondary : theme.textDisabled,
            pressedForegroundColor: configuration.isEnabled ? theme.textSecondary.withAlphaComponent(0.72) : theme.textDisabled,
            selectedForegroundColor: configuration.isEnabled ? theme.windowBackground : theme.textDisabled,
            selectedHoverForegroundColor: configuration.isEnabled ? theme.windowBackground.withAlphaComponent(0.88) : theme.textDisabled,
            selectedPressedForegroundColor: configuration.isEnabled ? theme.windowBackground.withAlphaComponent(0.72) : theme.textDisabled,
            borderColor: theme.controlStrokeStrong,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            font: font
        )
    }
}

public extension FluentSegmentedStyle where Self == FluentAutomaticSegmentedStyle {
    static var automatic: FluentAutomaticSegmentedStyle { FluentAutomaticSegmentedStyle() }
}

public extension FluentSegmentedStyle where Self == FluentNeutralSegmentedStyle {
    static var neutral: FluentNeutralSegmentedStyle { FluentNeutralSegmentedStyle() }
}

public extension FluentTextFieldStyle where Self == FluentAutomaticTextFieldStyle {
    static var automatic: FluentAutomaticTextFieldStyle { FluentAutomaticTextFieldStyle() }
}

public extension FluentTextFieldStyle where Self == FluentUnderlineTextFieldStyle {
    static var underline: FluentUnderlineTextFieldStyle { FluentUnderlineTextFieldStyle() }
}

/// The semantic metrics returned by a card/container style.
public struct FluentCardAppearance {
    public let fillColor: NSColor
    public let strokeColor: NSColor
    public let strokeWidth: CGFloat
    public let cornerRadius: CGFloat
    public let contentInsets: NSEdgeInsets

    public init(
        fillColor: NSColor,
        strokeColor: NSColor,
        strokeWidth: CGFloat = 1,
        cornerRadius: CGFloat = 11,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = max(strokeWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.contentInsets = contentInsets
    }
}

/// Supplies the visual metrics for a native Fluent card.
public protocol FluentCardStyle {
    func appearance(for theme: FluentTheme) -> FluentCardAppearance
}

/// The standard material card appearance.
public struct FluentAutomaticCardStyle: FluentCardStyle {
    public init() {}

    public func appearance(for theme: FluentTheme) -> FluentCardAppearance {
        FluentCardAppearance(
            fillColor: theme.cardFill,
            strokeColor: theme.cardStroke,
            strokeWidth: theme.controlStrokeWidth,
            cornerRadius: theme.cardCornerRadius,
            contentInsets: NSEdgeInsets(
                top: 16 * theme.density.metricScale,
                left: 18 * theme.density.metricScale,
                bottom: 16 * theme.density.metricScale,
                right: 18 * theme.density.metricScale
            )
        )
    }
}

/// A stronger surface style for emphasized content.
public struct FluentElevatedCardStyle: FluentCardStyle {
    public init() {}

    public func appearance(for theme: FluentTheme) -> FluentCardAppearance {
        FluentCardAppearance(
            fillColor: theme.controlFillSecondary,
            strokeColor: theme.controlStrokeStrong,
            strokeWidth: theme.controlStrokeWidth,
            cornerRadius: theme.cardCornerRadius,
            contentInsets: NSEdgeInsets(
                top: 18 * theme.density.metricScale,
                left: 20 * theme.density.metricScale,
                bottom: 18 * theme.density.metricScale,
                right: 20 * theme.density.metricScale
            )
        )
    }
}

/// A flat container style with no framed surface.
public struct FluentPlainCardStyle: FluentCardStyle {
    public init() {}

    public func appearance(for theme: FluentTheme) -> FluentCardAppearance {
        FluentCardAppearance(
            fillColor: .clear,
            strokeColor: .clear,
            strokeWidth: 0,
            cornerRadius: 0,
            contentInsets: NSEdgeInsetsZero
        )
    }
}

public extension FluentCardStyle where Self == FluentAutomaticCardStyle {
    static var automatic: FluentAutomaticCardStyle { FluentAutomaticCardStyle() }
}

public extension FluentCardStyle where Self == FluentElevatedCardStyle {
    static var elevated: FluentElevatedCardStyle { FluentElevatedCardStyle() }
}

public extension FluentCardStyle where Self == FluentPlainCardStyle {
    static var plain: FluentPlainCardStyle { FluentPlainCardStyle() }
}

/// A declarative card that keeps its native container and content identity across updates.
public struct FluentCardView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let style: any FluentCardStyle

    public init(style: any FluentCardStyle = FluentAutomaticCardStyle(), @FluentViewBuilder content: () -> Content) {
        self.content = content()
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let card = FluentCard(contentView: content._mount(in: context), style: style)
        card.theme = context.theme
        return card
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let card = view as? FluentCard else { return false }
        card.theme = context.theme
        card.style = style
        let updated = content._update(card.contentView, in: context)
        if updated { card.invalidateIntrinsicContentSize() }
        return updated
    }
}

public extension FluentView {
    /// Frames a view in a reusable, style-driven card container.
    func cardStyle(_ style: any FluentCardStyle) -> FluentCardView<Self> {
        FluentCardView(style: style) { self }
    }
}
