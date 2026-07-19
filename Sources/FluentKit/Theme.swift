import AppKit

public enum FluentControlState: Hashable, Sendable {
    case normal
    case pointerOver
    case pressed
    case disabled
    case focused
    case selected
    case checked
}

public enum FluentControlSize: Hashable, Sendable {
    case small
    case regular
    case large

    public var height: CGFloat {
        switch self {
        case .small: return 26
        case .regular: return 32
        case .large: return 38
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: return 12
        case .regular: return 13
        case .large: return 14
        }
    }

    public var metricScale: CGFloat {
        switch self {
        case .small: return 0.8125
        case .regular: return 1
        case .large: return 1.1875
        }
    }

    var appKitSize: NSControl.ControlSize {
        switch self {
        case .small: return .small
        case .regular: return .regular
        case .large: return .large
        }
    }
}

public protocol FluentControlSizeConfigurable: AnyObject {
    var fluentControlSize: FluentControlSize { get set }
}

public enum FluentMaterial: Hashable, Sendable {
    case mica
    case acrylic
    case sidebar
}

/// Controls the semantic density of layout metrics without changing the view tree.
public enum FluentThemeDensity: Hashable, Sendable {
    case compact
    case regular
    case spacious

    fileprivate var scale: CGFloat {
        switch self {
        case .compact: return 0.875
        case .regular: return 1
        case .spacious: return 1.125
        }
    }

    public var metricScale: CGFloat { scale }
}

/// Selects standard, high-contrast, or system-derived semantic colors.
public enum FluentThemeContrast: Hashable, Sendable {
    case standard
    case high
    case system
}

public enum FluentThemeColorScheme: Hashable, Sendable {
    case system
    case light
    case dark
}

/// Geometry tokens shared by FluentKit surfaces and controls.
public struct FluentDesignTokens: Sendable {
    public let spacingXXSmall: CGFloat
    public let spacingXSmall: CGFloat
    public let spacingSmall: CGFloat
    public let spacingMedium: CGFloat
    public let spacingLarge: CGFloat
    public let spacingXLarge: CGFloat
    public let controlHeight: CGFloat
    public let compactControlHeight: CGFloat
    public let controlCornerRadius: CGFloat
    public let cardCornerRadius: CGFloat
    public let buttonHorizontalPadding: CGFloat
    public let navigationPaneWidth: CGFloat
    public let contentInset: CGFloat

    public init(density: FluentThemeDensity = .regular) {
        let scale = density.metricScale
        spacingXXSmall = 2 * scale
        spacingXSmall = 4 * scale
        spacingSmall = 8 * scale
        spacingMedium = 12 * scale
        spacingLarge = 16 * scale
        spacingXLarge = 24 * scale
        controlHeight = 32 * scale
        compactControlHeight = 24 * scale
        controlCornerRadius = 4 * scale
        cardCornerRadius = 8 * scale
        buttonHorizontalPadding = 12 * scale
        navigationPaneWidth = 240 * scale
        contentInset = 24 * scale
    }
}

public enum FluentTextStyle: Hashable, Sendable {
    case largeTitle
    case title
    case title2
    case headline
    case body
    case callout
    case caption
    case code
}

/// Semantic desktop typography with an application-configurable scale.
public struct FluentTypography: Sendable {
    public let scale: CGFloat

    public init(scale: CGFloat = 1) {
        self.scale = min(max(scale, 0.75), 2)
    }

    public func font(for style: FluentTextStyle) -> NSFont {
        let descriptor: (CGFloat, NSFont.Weight) = switch style {
        case .largeTitle: (28, .semibold)
        case .title: (22, .semibold)
        case .title2: (18, .semibold)
        case .headline: (15, .semibold)
        case .body: (14, .regular)
        case .callout: (13, .regular)
        case .caption: (12, .regular)
        case .code: (13, .regular)
        }
        let size = descriptor.0 * scale
        if style == .code { return NSFont.monospacedSystemFont(ofSize: size, weight: descriptor.1) }
        return NSFont.systemFont(ofSize: size, weight: descriptor.1)
    }
}

public enum FluentAnimation {
    public static let stateChange: TimeInterval = 0.083
    public static let emphasis: TimeInterval = 0.167
    public static let content: TimeInterval = 0.250
}

public struct FluentTheme {
    public static let defaultAccent = NSColor(calibratedRed: 0.0, green: 0.376, blue: 0.706, alpha: 1)

    public let accent: NSColor
    public let material: FluentMaterial
    public let density: FluentThemeDensity
    public let contrast: FluentThemeContrast
    public let colorScheme: FluentThemeColorScheme
    public let typography: FluentTypography

    public var designTokens: FluentDesignTokens { FluentDesignTokens(density: density) }

    public init(
        accent: NSColor = FluentTheme.defaultAccent,
        material: FluentMaterial = .mica,
        density: FluentThemeDensity = .regular,
        contrast: FluentThemeContrast = .system,
        colorScheme: FluentThemeColorScheme = .system,
        typography: FluentTypography = FluentTypography()
    ) {
        self.accent = accent
        self.material = material
        self.density = density
        self.contrast = contrast
        self.colorScheme = colorScheme
        self.typography = typography
    }

    public static let current = FluentTheme()

    public static func custom(
        accent: NSColor = FluentTheme.defaultAccent,
        material: FluentMaterial = .mica,
        density: FluentThemeDensity = .regular,
        contrast: FluentThemeContrast = .system,
        colorScheme: FluentThemeColorScheme = .system,
        typography: FluentTypography = FluentTypography()
    ) -> FluentTheme {
        FluentTheme(
            accent: accent,
            material: material,
            density: density,
            contrast: contrast,
            colorScheme: colorScheme,
            typography: typography
        )
    }

    public func with(density: FluentThemeDensity) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography)
    }

    public func with(accent: NSColor) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography)
    }

    public func with(material: FluentMaterial) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography)
    }

    public func with(contrast: FluentThemeContrast) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography)
    }

    public func with(colorScheme: FluentThemeColorScheme) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography)
    }

    public func with(typography: FluentTypography) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography)
    }

    public var isDark: Bool {
        switch colorScheme {
        case .light: return false
        case .dark: return true
        case .system: return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    public var isHighContrast: Bool {
        switch contrast {
        case .standard: return false
        case .high: return true
        case .system: return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    }

    public var windowBackground: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)
            : NSColor(calibratedRed: 0.953, green: 0.953, blue: 0.953, alpha: 1)
    }

    /// A stable tint layered over the native macOS material to keep Mica visually consistent.
    public var micaTint: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.16, alpha: 0.82)
            : NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 0.90)
    }

    public var textPrimary: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: isHighContrast ? 1 : 0.92)
            : NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.11, alpha: isHighContrast ? 1 : 0.90)
    }

    public var textSecondary: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: isHighContrast ? 0.84 : 0.68)
            : NSColor(calibratedRed: 0.24, green: 0.24, blue: 0.24, alpha: isHighContrast ? 0.88 : 0.72)
    }

    public var textDisabled: NSColor {
        isDark ? NSColor(calibratedWhite: 1, alpha: 0.36) : NSColor(calibratedWhite: 0, alpha: 0.36)
    }

    public var textOnAccent: NSColor {
        NSColor.white
    }

    public var controlFill: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.08)
            : NSColor(calibratedWhite: 1, alpha: 0.78)
    }

    public var controlFillSecondary: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.13)
            : NSColor(calibratedWhite: 0.98, alpha: 0.86)
    }

    public var controlFillTertiary: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.18)
            : NSColor(calibratedWhite: 0.90, alpha: 0.94)
    }

    /// WinUI-derived ToggleSwitch track fills kept separate from generic control surfaces.
    public func toggleTrackFill(isOn: Bool, state: FluentControlState) -> NSColor {
        if isOn {
            let alpha: CGFloat = switch state {
            case .pointerOver: 0.90
            case .pressed: 0.80
            case .disabled: 0.35
            default: 1
            }
            return accent.withAlphaComponent(alpha)
        }
        if isHighContrast {
            return state == .disabled
                ? controlFill.withAlphaComponent(0.35)
                : controlFill
        }
        if isDark {
            return switch state {
            case .pointerOver: NSColor(calibratedWhite: 1, alpha: 0.043)
            case .pressed: NSColor(calibratedWhite: 1, alpha: 0.071)
            case .disabled: .clear
            default: NSColor(calibratedWhite: 0, alpha: 0.098)
            }
        }
        return switch state {
        case .pointerOver: NSColor(calibratedWhite: 0, alpha: 0.059)
        case .pressed: NSColor(calibratedWhite: 0, alpha: 0.094)
        case .disabled: .clear
        default: NSColor(calibratedWhite: 0, alpha: 0.024)
        }
    }

    public func toggleTrackStroke(isOn: Bool, state: FluentControlState) -> NSColor {
        if isOn, !isHighContrast { return .clear }
        if state == .disabled {
            return isDark
                ? NSColor(calibratedWhite: 1, alpha: 0.157)
                : NSColor(calibratedWhite: 0, alpha: 0.216)
        }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.545)
            : NSColor(calibratedWhite: 0, alpha: 0.447)
    }

    public func toggleKnobFill(isOn: Bool, state: FluentControlState) -> NSColor {
        guard state != .disabled else { return textDisabled }
        if isOn {
            return isHighContrast
                ? textOnAccent
                : NSColor(calibratedWhite: isDark ? 0 : 1, alpha: 0.92)
        }
        return textSecondary
    }

    public func toggleKnobStroke(isOn: Bool, state: FluentControlState) -> NSColor {
        guard isOn, state != .disabled else { return .clear }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.08)
            : NSColor(calibratedWhite: 0, alpha: 0.08)
    }

    public var controlStroke: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: isHighContrast ? 0.42 : 0.20)
            : NSColor(calibratedWhite: 0, alpha: isHighContrast ? 0.40 : 0.14)
    }

    public var controlStrokeStrong: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: isHighContrast ? 0.86 : 0.62)
            : NSColor(calibratedWhite: 0, alpha: isHighContrast ? 0.78 : 0.48)
    }

    /// The two stops used by WinUI's ControlElevationBorderBrush, ordered top to bottom.
    public var controlElevationBorderColors: [NSColor] {
        if isHighContrast { return [controlStrokeStrong, controlStrokeStrong] }
        return isDark
            ? [
                NSColor(calibratedWhite: 1, alpha: 0.094),
                NSColor(calibratedWhite: 1, alpha: 0.071)
            ]
            : [
                NSColor(calibratedWhite: 0, alpha: 0.059),
                NSColor(calibratedWhite: 0, alpha: 0.161)
            ]
    }

    /// AccentControlElevationBorderBrush uses a pale upper edge and a darker lower edge.
    public var accentElevationBorderColors: [NSColor] {
        if isHighContrast { return [textOnAccent, textOnAccent] }
        return [
            NSColor(calibratedWhite: 1, alpha: 0.078),
            NSColor(calibratedWhite: 0, alpha: isDark ? 0.137 : 0.40)
        ]
    }

    public var controlStrokeDefault: NSColor {
        if isHighContrast { return controlStrokeStrong }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.071)
            : NSColor(calibratedWhite: 0, alpha: 0.059)
    }

    public var cardFill: NSColor {
        isDark ? NSColor(calibratedWhite: 1, alpha: 0.10) : NSColor(calibratedWhite: 1, alpha: 0.84)
    }

    public var divider: NSColor {
        isDark ? NSColor(calibratedWhite: 1, alpha: 0.15) : NSColor(calibratedWhite: 0, alpha: 0.12)
    }

    public func buttonBackground(for state: FluentControlState) -> NSColor {
        switch state {
        case .pointerOver: return controlFillSecondary
        case .pressed: return controlFillTertiary
        case .disabled: return controlFill.withAlphaComponent(controlFill.alphaComponent * 0.45)
        default: return controlFill
        }
    }

    public func buttonForeground(for state: FluentControlState) -> NSColor {
        switch state {
        case .pressed: return textSecondary
        case .disabled: return textDisabled
        default: return textPrimary
        }
    }

    public var buttonCornerRadius: CGFloat { designTokens.controlCornerRadius }
    public var controlStrokeWidth: CGFloat { isHighContrast ? 2 : 1 }
    public var focusStrokeWidth: CGFloat { isHighContrast ? 2 : 1.5 }
    public var controlHeight: CGFloat { designTokens.controlHeight }
    public func controlHeight(for size: FluentControlSize) -> CGFloat { controlHeight * size.metricScale }
    public var controlPadding: NSEdgeInsets {
        let vertical = 5 * density.scale
        let horizontal = designTokens.buttonHorizontalPadding
        return NSEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
    public var cardCornerRadius: CGFloat { designTokens.cardCornerRadius }
}

public extension NSColor {
    static var fluentAccent: NSColor { FluentTheme.current.accent }
}

/// An observable application-level theme source. Reading `theme` during rendering participates in
/// FluentKit dependency tracking, so replacing the theme updates existing native views in place.
public final class FluentThemeStore {
    public let observable: FluentObservable<FluentTheme>

    public init(_ theme: FluentTheme = .current) {
        observable = FluentObservable(theme)
    }

    public var theme: FluentTheme {
        get { observable.value }
        set { observable.value = newValue }
    }

    public var binding: FluentBinding<FluentTheme> {
        FluentBinding(
            get: { self.theme },
            set: { self.theme = $0 },
            observe: { self.observable.observe($0, notifyImmediately: false) },
            removeObserver: { self.observable.removeObserver($0) }
        )
    }
}
