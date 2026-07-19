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

/// The visual metrics returned by a button style.
public struct FluentButtonAppearance {
    public let backgroundColor: NSColor
    public let foregroundColor: NSColor
    public let borderColor: NSColor
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let contentInsets: NSEdgeInsets
    public let focusRingColor: NSColor?
    public let focusRingWidth: CGFloat

    public init(
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        borderColor: NSColor,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 7,
        contentInsets: NSEdgeInsets = NSEdgeInsetsZero,
        focusRingColor: NSColor? = nil,
        focusRingWidth: CGFloat = 1.5
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.contentInsets = contentInsets
        self.focusRingColor = focusRingColor
        self.focusRingWidth = max(focusRingWidth, 0)
    }
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
            return FluentButtonAppearance(
                backgroundColor: theme.buttonBackground(for: state),
                foregroundColor: theme.buttonForeground(for: state),
                borderColor: theme.isHighContrast ? theme.controlStrokeStrong : theme.controlStroke,
                borderWidth: theme.controlStrokeWidth,
                cornerRadius: theme.buttonCornerRadius,
                contentInsets: theme.controlPadding,
                focusRingColor: theme.accent.withAlphaComponent(0.85),
                focusRingWidth: theme.focusStrokeWidth
            )
        case .primary:
            let alpha: CGFloat = state == .pressed ? 0.72 : (state == .pointerOver ? 0.88 : 1)
            return FluentButtonAppearance(
                backgroundColor: theme.accent.withAlphaComponent(configuration.isEnabled ? alpha : 0.35),
                foregroundColor: theme.textOnAccent,
                borderColor: theme.accent,
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
        let alpha: CGFloat = state == .pressed ? 0.72 : (state == .pointerOver ? 0.88 : 1)
        return FluentButtonAppearance(
            backgroundColor: theme.accent.withAlphaComponent(configuration.isEnabled ? alpha : 0.35),
            foregroundColor: theme.textOnAccent,
            borderColor: theme.accent,
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
        let foreground = configuration.isEnabled ? theme.accent : theme.textDisabled
        let background: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
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
        let foreground = configuration.isEnabled ? theme.accent : theme.textDisabled
        let background: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
        default: .clear
        }
        return FluentButtonAppearance(
            backgroundColor: background,
            foregroundColor: foreground,
            borderColor: configuration.isEnabled ? theme.accent : theme.controlStroke,
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
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isOn: Bool, isEnabled: Bool, isPointerOver: Bool, isPressed: Bool = false, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.isPointerOver = isPointerOver
        self.isPressed = isPressed
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentToggleAppearance {
    public let trackColor: NSColor
    public let trackBorderColor: NSColor
    public let trackBorderWidth: CGFloat
    public let knobColor: NSColor
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
        labelColor: NSColor,
        knobShadowColor: NSColor = NSColor.black.withAlphaComponent(0.32),
        trackSize: CGSize = CGSize(width: 36, height: 20),
        knobDiameter: CGFloat = 16,
        knobSize: CGSize? = nil,
        labelSpacing: CGFloat = 12
    ) {
        self.trackColor = trackColor
        self.trackBorderColor = trackBorderColor
        self.trackBorderWidth = max(trackBorderWidth, 0)
        self.knobColor = knobColor
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
        let enabledAlpha: CGFloat = configuration.isEnabled ? 1 : 0.45
        let offTrack = configuration.isPointerOver ? theme.controlFillSecondary : theme.controlFillTertiary
        let thumbSize: CGSize
        if configuration.isPressed {
            thumbSize = CGSize(width: 17 * scale, height: 14 * scale)
        } else if configuration.isPointerOver {
            thumbSize = CGSize(width: 14 * scale, height: 14 * scale)
        } else {
            thumbSize = CGSize(width: 12 * scale, height: 12 * scale)
        }
        return FluentToggleAppearance(
            trackColor: (configuration.isOn ? theme.accent : offTrack).withAlphaComponent(enabledAlpha),
            trackBorderColor: theme.controlStroke,
            trackBorderWidth: theme.controlStrokeWidth,
            knobColor: configuration.isOn ? theme.textOnAccent : theme.textPrimary,
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
        if configuration.isPressed {
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
    public let knobColor: NSColor
    public let haloColor: NSColor
    public let trackHeight: CGFloat
    public let knobDiameter: CGFloat
    public let haloDiameter: CGFloat

    public init(
        trackColor: NSColor,
        fillColor: NSColor,
        knobColor: NSColor,
        haloColor: NSColor,
        trackHeight: CGFloat = 4,
        knobDiameter: CGFloat = 14,
        haloDiameter: CGFloat = 22
    ) {
        self.trackColor = trackColor
        self.fillColor = fillColor
        self.knobColor = knobColor
        self.haloColor = haloColor
        self.trackHeight = max(trackHeight, 1)
        self.knobDiameter = max(knobDiameter, 1)
        self.haloDiameter = max(haloDiameter, knobDiameter)
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
        let alpha: CGFloat = configuration.isEnabled ? 1 : 0.4
        return FluentSliderAppearance(
            trackColor: theme.controlFillTertiary,
            fillColor: theme.accent.withAlphaComponent(alpha),
            knobColor: theme.accent.withAlphaComponent(alpha),
            haloColor: theme.accent.withAlphaComponent(configuration.isPointerOver || configuration.isDragging ? 0.28 : 0),
            trackHeight: (theme.isHighContrast ? 6 : 4) * scale,
            knobDiameter: (theme.isHighContrast ? 16 : 14) * scale,
            haloDiameter: (theme.isHighContrast ? 24 : 22) * scale
        )
    }
}

public struct FluentNeutralSliderStyle: FluentSliderStyle {
    public init() {}

    public func appearance(for configuration: FluentSliderStyleConfiguration) -> FluentSliderAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let alpha: CGFloat = configuration.isEnabled ? 1 : 0.4
        return FluentSliderAppearance(
            trackColor: theme.controlFillTertiary,
            fillColor: theme.controlStrokeStrong.withAlphaComponent(alpha),
            knobColor: theme.textPrimary.withAlphaComponent(alpha),
            haloColor: theme.controlStrokeStrong.withAlphaComponent(configuration.isPointerOver || configuration.isDragging ? 0.24 : 0),
            trackHeight: (theme.isHighContrast ? 6 : 4) * scale,
            knobDiameter: (theme.isHighContrast ? 16 : 14) * scale,
            haloDiameter: (theme.isHighContrast ? 24 : 22) * scale
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
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isEnabled: Bool, isFocused: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.controlSize = controlSize
        self.theme = theme
    }
}

public struct FluentTextFieldAppearance {
    public let backgroundColor: NSColor
    public let textColor: NSColor
    public let borderColor: NSColor
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let borderShape: FluentTextFieldBorderShape
    public let font: NSFont?

    public init(
        backgroundColor: NSColor,
        textColor: NSColor,
        borderColor: NSColor,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 7,
        borderShape: FluentTextFieldBorderShape = .rounded,
        font: NSFont? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.borderShape = borderShape
        self.font = font
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
            backgroundColor: theme.controlFill,
            textColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            borderColor: configuration.isFocused ? theme.controlStrokeStrong : theme.controlStroke,
            borderWidth: theme.controlStrokeWidth,
            cornerRadius: theme.buttonCornerRadius,
            font: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale)
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
            borderColor: configuration.isFocused ? theme.accent : theme.controlStrokeStrong,
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

    public init(
        labelColor: NSColor,
        labelFont: NSFont,
        spacing: CGFloat = 8,
        valueFieldWidth: CGFloat = 88,
        textFieldStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()
    ) {
        self.labelColor = labelColor
        self.labelFont = labelFont
        self.spacing = max(spacing, 0)
        self.valueFieldWidth = max(valueFieldWidth, 36)
        self.textFieldStyle = textFieldStyle
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

public extension FluentStepperStyle where Self == FluentAutomaticStepperStyle {
    static var automatic: FluentAutomaticStepperStyle { FluentAutomaticStepperStyle() }
}

public extension FluentStepperStyle where Self == FluentInlineStepperStyle {
    static var inline: FluentInlineStepperStyle { FluentInlineStepperStyle() }
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
    public let theme: FluentTheme

    public init(valueFraction: CGFloat, theme: FluentTheme) {
        self.valueFraction = min(max(valueFraction, 0), 1)
        self.theme = theme
    }
}

public struct FluentProgressAppearance {
    public let trackColor: NSColor
    public let progressColor: NSColor
    public let trackHeight: CGFloat
    public let cornerRadius: CGFloat

    public init(
        trackColor: NSColor,
        progressColor: NSColor,
        trackHeight: CGFloat = 4,
        cornerRadius: CGFloat = 2
    ) {
        self.trackColor = trackColor
        self.progressColor = progressColor
        self.trackHeight = max(trackHeight, 1)
        self.cornerRadius = max(cornerRadius, 0)
    }
}

public protocol FluentProgressStyle {
    func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance
}

public struct FluentAutomaticProgressStyle: FluentProgressStyle {
    public init() {}

    public func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance {
        let theme = configuration.theme
        return FluentProgressAppearance(
            trackColor: theme.controlFillTertiary,
            progressColor: theme.accent,
            trackHeight: (theme.isHighContrast ? 6 : 4) * theme.density.metricScale,
            cornerRadius: (theme.isHighContrast ? 3 : 2) * theme.density.metricScale
        )
    }
}

public struct FluentNeutralProgressStyle: FluentProgressStyle {
    public init() {}

    public func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance {
        let theme = configuration.theme
        return FluentProgressAppearance(
            trackColor: theme.controlFillTertiary,
            progressColor: theme.controlStrokeStrong,
            trackHeight: (theme.isHighContrast ? 7 : 5) * theme.density.metricScale,
            cornerRadius: (theme.isHighContrast ? 3.5 : 2.5) * theme.density.metricScale
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
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isChecked: Bool, isEnabled: Bool, isPointerOver: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.isPointerOver = isPointerOver
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
        let alpha: CGFloat = configuration.isEnabled ? 1 : 0.45
        let border = configuration.isChecked || theme.isHighContrast ? theme.controlStrokeStrong : theme.controlStroke
        return FluentCheckBoxAppearance(
            boxSize: 20 * scale,
            cornerRadius: 3 * scale,
            fillColor: (configuration.isChecked ? theme.accent : (configuration.isPointerOver ? theme.controlFillSecondary : theme.controlFill)).withAlphaComponent(alpha),
            borderColor: border.withAlphaComponent(alpha),
            borderWidth: theme.controlStrokeWidth,
            markColor: theme.textOnAccent,
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
        let alpha: CGFloat = configuration.isEnabled ? 1 : 0.45
        let bodyFont = theme.typography.font(for: .body)
        return FluentCheckBoxAppearance(
            boxSize: 20 * scale,
            cornerRadius: 3 * scale,
            fillColor: (configuration.isChecked ? theme.controlStrokeStrong : theme.controlFill).withAlphaComponent(alpha),
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
    public let controlSize: FluentControlSize
    public let theme: FluentTheme

    public init(isSelected: Bool, isEnabled: Bool, controlSize: FluentControlSize, theme: FluentTheme) {
        self.isSelected = isSelected
        self.isEnabled = isEnabled
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
        labelSpacing: CGFloat = 8
    ) {
        self.diameter = max(diameter, 1)
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.dotColor = dotColor
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
        let alpha: CGFloat = configuration.isEnabled ? 1 : 0.45
        let bodyFont = theme.typography.font(for: .body)
        return FluentRadioButtonAppearance(
            diameter: 20 * scale,
            fillColor: (configuration.isSelected ? theme.accent : theme.controlFill).withAlphaComponent(alpha),
            borderColor: (configuration.isSelected || theme.isHighContrast ? theme.controlStrokeStrong : theme.controlStroke).withAlphaComponent(alpha),
            borderWidth: theme.controlStrokeWidth,
            dotColor: theme.textOnAccent,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            labelSpacing: 8 * scale
        )
    }
}

public struct FluentMonochromeRadioButtonStyle: FluentRadioButtonStyle {
    public init() {}

    public func appearance(for configuration: FluentRadioButtonStyleConfiguration) -> FluentRadioButtonAppearance {
        let theme = configuration.theme
        let scale = theme.density.metricScale * configuration.controlSize.metricScale
        let alpha: CGFloat = configuration.isEnabled ? 1 : 0.45
        let bodyFont = theme.typography.font(for: .body)
        return FluentRadioButtonAppearance(
            diameter: 20 * scale,
            fillColor: (configuration.isSelected ? theme.controlStrokeStrong : theme.controlFill).withAlphaComponent(alpha),
            borderColor: theme.controlStrokeStrong.withAlphaComponent(alpha),
            borderWidth: theme.controlStrokeWidth,
            dotColor: theme.windowBackground,
            labelColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            labelFont: bodyFont.withSize(bodyFont.pointSize * configuration.controlSize.metricScale),
            labelSpacing: 8 * scale
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
    public let hoverColor: NSColor
    public let foregroundColor: NSColor
    public let selectedForegroundColor: NSColor
    public let borderColor: NSColor
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let font: NSFont
    public let segmentStyle: NSSegmentedControl.Style

    public init(
        backgroundColor: NSColor,
        selectedSegmentColor: NSColor,
        hoverColor: NSColor = .clear,
        foregroundColor: NSColor = .labelColor,
        selectedForegroundColor: NSColor = .white,
        borderColor: NSColor,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 7,
        font: NSFont,
        segmentStyle: NSSegmentedControl.Style = .rounded
    ) {
        self.backgroundColor = backgroundColor
        self.selectedSegmentColor = selectedSegmentColor
        self.hoverColor = hoverColor
        self.foregroundColor = foregroundColor
        self.selectedForegroundColor = selectedForegroundColor
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
            selectedSegmentColor: theme.accent,
            hoverColor: theme.controlFillSecondary,
            foregroundColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            selectedForegroundColor: theme.textOnAccent,
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
        return FluentSegmentedAppearance(
            backgroundColor: theme.controlFill,
            selectedSegmentColor: theme.controlStrokeStrong,
            hoverColor: theme.controlFillSecondary,
            foregroundColor: configuration.isEnabled ? theme.textPrimary : theme.textDisabled,
            selectedForegroundColor: theme.windowBackground,
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
            strokeColor: theme.controlStroke,
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
