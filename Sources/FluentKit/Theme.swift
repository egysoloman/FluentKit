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
    /// System-owned glass for transient presenters. Unlike acrylic, FluentKit does not tint or
    /// paint this material itself.
    case liquidGlass
    case sidebar
}

/// Selects whether native material effects are used for a semantic surface. The switch lives in
/// `FluentTheme` so an application-level `FluentThemeStore` can update existing presenters in one
/// declarative refresh.
public enum FluentMaterialRole: Hashable, Sendable {
    case window
    case navigation
    case transient
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

/// The user's requested appearance. This is configuration state; controls receive the resolved
/// Light/Dark `FluentTheme` instead of carrying `.system` into their drawing code.
public enum FluentThemePreference: Hashable, Sendable {
    case system
    case light
    case dark

    public init(colorScheme: FluentThemeColorScheme) {
        switch colorScheme {
        case .system: self = .system
        case .light: self = .light
        case .dark: self = .dark
        }
    }

    public var colorScheme: FluentThemeColorScheme {
        switch self {
        case .system: return .system
        case .light: return .light
        case .dark: return .dark
        }
    }
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
public struct FluentTypography: Sendable, Equatable {
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

public struct FluentTheme: Equatable {
    /// WinUI's default `SystemAccentColor` (#0078D4). Controls do not consume this color
    /// directly; they resolve the theme-appropriate accent palette entry below.
    public static let defaultAccent = NSColor(
        calibratedRed: 0,
        green: 120.0 / 255.0,
        blue: 212.0 / 255.0,
        alpha: 1
    )

    public let accent: NSColor
    public let material: FluentMaterial
    public let density: FluentThemeDensity
    public let contrast: FluentThemeContrast
    public let colorScheme: FluentThemeColorScheme
    public let typography: FluentTypography
    public let materialEffectsEnabled: Bool

    public var designTokens: FluentDesignTokens { FluentDesignTokens(density: density) }

    public init(
        accent: NSColor = FluentTheme.defaultAccent,
        material: FluentMaterial = .mica,
        density: FluentThemeDensity = .regular,
        contrast: FluentThemeContrast = .system,
        colorScheme: FluentThemeColorScheme = .system,
        typography: FluentTypography = FluentTypography(),
        materialEffectsEnabled: Bool = true
    ) {
        self.accent = accent
        self.material = material
        self.density = density
        self.contrast = contrast
        self.colorScheme = colorScheme
        self.typography = typography
        self.materialEffectsEnabled = materialEffectsEnabled
    }

    public static func == (lhs: FluentTheme, rhs: FluentTheme) -> Bool {
        lhs.accent.isEqual(rhs.accent)
            && lhs.material == rhs.material
            && lhs.density == rhs.density
            && lhs.contrast == rhs.contrast
            && lhs.colorScheme == rhs.colorScheme
            && lhs.typography == rhs.typography
            && lhs.materialEffectsEnabled == rhs.materialEffectsEnabled
    }

    /// The legacy current theme is the actual Light/Dark result for the current AppKit
    /// appearance. Use `FluentThemePreference.system` or `FluentTheme()` for requested System
    /// configuration.
    public static var current: FluentTheme {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua) ?? NSAppearance()
        return FluentThemeResolver.resolve(
            preference: .system,
            appearance: appearance,
            baseTheme: FluentTheme(colorScheme: .light)
        )
    }

    public static func custom(
        accent: NSColor = FluentTheme.defaultAccent,
        material: FluentMaterial = .mica,
        density: FluentThemeDensity = .regular,
        contrast: FluentThemeContrast = .system,
        colorScheme: FluentThemeColorScheme = .system,
        typography: FluentTypography = FluentTypography(),
        materialEffectsEnabled: Bool = true
    ) -> FluentTheme {
        FluentTheme(
            accent: accent,
            material: material,
            density: density,
            contrast: contrast,
            colorScheme: colorScheme,
            typography: typography,
            materialEffectsEnabled: materialEffectsEnabled
        )
    }

    public func with(density: FluentThemeDensity) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    public func with(accent: NSColor) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    public func with(material: FluentMaterial) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    public func with(materialEffectsEnabled: Bool) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    public func with(contrast: FluentThemeContrast) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    public func with(colorScheme: FluentThemeColorScheme) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    public func with(typography: FluentTypography) -> FluentTheme {
        FluentTheme(accent: accent, material: material, density: density, contrast: contrast, colorScheme: colorScheme, typography: typography, materialEffectsEnabled: materialEffectsEnabled)
    }

    /// Resolves the native material for a semantic transient or navigation surface. The
    /// application can disable effects globally without changing control ownership or layout.
    public func material(for role: FluentMaterialRole) -> FluentMaterial? {
        guard materialEffectsEnabled else { return nil }
        switch role {
        case .window, .navigation: return .mica
        case .transient: return .liquidGlass
        }
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
            ? NSColor(calibratedWhite: 32.0 / 255.0, alpha: 1)
            : NSColor(calibratedWhite: 243.0 / 255.0, alpha: 1)
    }

    /// A stable tint layered over the native macOS material to keep Mica visually consistent.
    public var micaTint: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.16, alpha: 0.52)
            : NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.97, alpha: 0.58)
    }

    /// A non-sampling overlay shared by WindowShell title-bar and navigation chrome.
    public var windowChromeTint: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 0.32)
            : NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 0.40)
    }

    public var textPrimary: NSColor {
        if isHighContrast { return isDark ? .white : .black }
        return isDark
            ? .white
            : NSColor(calibratedWhite: 0, alpha: 228.0 / 255.0)
    }

    public var textSecondary: NSColor {
        if isHighContrast { return isDark ? .white : .black }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 197.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 158.0 / 255.0)
    }

    /// The low-emphasis foreground used by pressed text and glyph states.
    public var textTertiary: NSColor {
        if isHighContrast { return textPrimary }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 135.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 114.0 / 255.0)
    }

    public var textDisabled: NSColor {
        if isHighContrast { return textSecondary }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 93.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 92.0 / 255.0)
    }

    public var textOnAccent: NSColor {
        if isHighContrast { return textPrimary }
        return isDark ? .black : .white
    }

    public var textOnAccentSecondary: NSColor {
        if isHighContrast { return textPrimary }
        return isDark
            ? NSColor(calibratedWhite: 0, alpha: 128.0 / 255.0)
            : NSColor(calibratedWhite: 1, alpha: 179.0 / 255.0)
    }

    public var textOnAccentDisabled: NSColor {
        if isHighContrast { return textDisabled }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 135.0 / 255.0)
            : .white
    }

    /// WinUI obtains these variants from the operating-system accent palette. FluentKit keeps
    /// the exact source fallback palette for its default blue. A custom macOS accent has no
    /// equivalent six-color system palette, so the source-suggested white/black blend fallback
    /// preserves the same ordering and contrast contract.
    public var accentDark1: NSColor { accentVariant(defaultRGB: (0, 90, 158), blendTarget: .black, fraction: 0.25) }
    public var accentDark2: NSColor { accentVariant(defaultRGB: (0, 66, 117), blendTarget: .black, fraction: 0.45) }
    public var accentDark3: NSColor { accentVariant(defaultRGB: (0, 38, 66), blendTarget: .black, fraction: 0.69) }
    public var accentLight1: NSColor { accentVariant(defaultRGB: (66, 156, 227), blendTarget: .white, fraction: 0.26) }
    public var accentLight2: NSColor { accentVariant(defaultRGB: (118, 185, 237), blendTarget: .white, fraction: 0.46) }
    public var accentLight3: NSColor { accentVariant(defaultRGB: (166, 216, 255), blendTarget: .white, fraction: 0.65) }

    /// `AccentFillColorDefaultBrush` uses Light2 in Dark and Dark1 in Light.
    public var accentFillDefault: NSColor {
        if isHighContrast { return accent }
        return isDark ? accentLight2 : accentDark1
    }

    public var accentFillSecondary: NSColor {
        if isHighContrast { return accent }
        return accentFillDefault.withAlphaComponent(0.90)
    }

    public var accentFillTertiary: NSColor {
        if isHighContrast { return accent }
        return accentFillDefault.withAlphaComponent(0.80)
    }

    public var accentFillDisabled: NSColor {
        if isHighContrast { return textDisabled }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 40.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 55.0 / 255.0)
    }

    public var accentTextPrimary: NSColor {
        if isHighContrast { return textPrimary }
        return isDark ? accentLight3 : accentDark2
    }

    public var accentTextSecondary: NSColor {
        if isHighContrast { return textPrimary }
        return isDark ? accentLight3 : accentDark3
    }

    public var accentTextTertiary: NSColor {
        if isHighContrast { return textSecondary }
        return isDark ? accentLight2 : accentDark1
    }

    public func accentFill(for state: FluentControlState) -> NSColor {
        switch state {
        case .pointerOver: return accentFillSecondary
        case .pressed: return accentFillTertiary
        case .disabled: return accentFillDisabled
        default: return accentFillDefault
        }
    }

    /// TextControlSelectionHighlightColor maps directly to
    /// AccentFillColorSelectedTextBackgroundBrush in the WinUI resources.
    public var textSelectionBackground: NSColor {
        isHighContrast ? windowBackground : accent
    }

    /// RichEdit's COLOR_HIGHLIGHTTEXT override is white outside High Contrast.
    public var textSelectionForeground: NSColor {
        isHighContrast ? textPrimary : .white
    }

    /// WinUI paints a white caret with DestInvert composition. AppKit does not expose that
    /// blend mode for its field editor, so the resolved foreground reproduces the same result
    /// on the standard Light and Dark TextControl surfaces while preserving native caret blink.
    public var textCaret: NSColor {
        isDark ? .white : .black
    }

    /// TextControlElevationBorderFocusedBrush uses Light2 in Dark and Dark1 in Light.
    public var textControlFocusStroke: NSColor {
        if isHighContrast { return accent }
        return isDark ? accentLight2 : accentDark1
    }

    public var controlFill: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: 15.0 / 255.0)
            : NSColor(calibratedWhite: 1, alpha: 179.0 / 255.0)
    }

    public var controlFillSecondary: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: 21.0 / 255.0)
            : NSColor(calibratedRed: 249.0 / 255.0, green: 249.0 / 255.0, blue: 249.0 / 255.0, alpha: 128.0 / 255.0)
    }

    public var controlFillTertiary: NSColor {
        isDark
            ? NSColor(calibratedWhite: 1, alpha: 8.0 / 255.0)
            : NSColor(calibratedRed: 249.0 / 255.0, green: 249.0 / 255.0, blue: 249.0 / 255.0, alpha: 77.0 / 255.0)
    }

    public var controlFillDisabled: NSColor {
        if isHighContrast { return controlFill }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 11.0 / 255.0)
            : NSColor(
                calibratedRed: 249.0 / 255.0,
                green: 249.0 / 255.0,
                blue: 249.0 / 255.0,
                alpha: 77.0 / 255.0
            )
    }

    /// WinUI's transparent subtle fill used by pointer-over list and flyout rows.
    public var subtleFillSecondary: NSColor {
        if isHighContrast { return controlFillSecondary }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 15.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 9.0 / 255.0)
    }

    /// WinUI's lower-opacity subtle fill used by pressed or selected-hover rows.
    public var subtleFillTertiary: NSColor {
        if isHighContrast { return controlFillTertiary }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 10.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 6.0 / 255.0)
    }

    /// WinUI-derived ToggleSwitch track fills kept separate from generic control surfaces.
    public func toggleTrackFill(isOn: Bool, state: FluentControlState) -> NSColor {
        if isOn {
            return accentFill(for: state)
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
        if isHighContrast { return controlStrokeStrong }
        return controlStrokeDefault
    }

    public var controlStrokeStrong: NSColor {
        if isHighContrast { return isDark ? .white : .black }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 139.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 114.0 / 255.0)
    }

    /// The two stops used by WinUI's ControlElevationBorderBrush, in source brush order.
    /// Shared Button chrome anchors this brush at the visual bottom without changing stop order.
    public var controlElevationBorderColors: [NSColor] {
        if isHighContrast { return [controlStrokeStrong, controlStrokeStrong] }
        return isDark
            ? [
                NSColor(calibratedWhite: 1, alpha: 0.094),
                NSColor(calibratedWhite: 1, alpha: 0.071)
            ]
            : [
                NSColor(calibratedWhite: 0, alpha: 0.161),
                NSColor(calibratedWhite: 0, alpha: 0.059)
            ]
    }

    /// WinUI TextControlElevationBorderBrush uses the strong/default control strokes over an
    /// absolute two-point extent. It is distinct from Button's three-point elevation brush.
    public var textControlElevationBorderColors: [NSColor] {
        if isHighContrast { return [controlStrokeStrong, controlStrokeStrong] }
        return [controlStrokeStrong, controlStrokeDefault]
    }

    /// TextControlElevationBorderFocusedBrush replaces the visual bottom edge with accent while
    /// retaining the ordinary one-point stroke on the other three sides.
    public var textControlFocusedElevationBorderColors: [NSColor] {
        if isHighContrast { return [textControlFocusStroke, controlStrokeStrong] }
        return [textControlFocusStroke, controlStrokeDefault]
    }

    public func textControlBackground(
        focused: Bool,
        pointerOver: Bool = false,
        enabled: Bool
    ) -> NSColor {
        guard enabled else { return controlFillDisabled }
        if focused {
            return isDark
                ? NSColor(calibratedRed: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0, alpha: 179.0 / 255.0)
                : .white
        }
        return pointerOver ? controlFillSecondary : controlFill
    }

    /// AccentControlElevationBorderBrush uses a pale upper edge and a darker lower edge.
    public var accentElevationBorderColors: [NSColor] {
        if isHighContrast { return [textOnAccent, textOnAccent] }
        return [
            NSColor(calibratedWhite: 0, alpha: isDark ? 0.137 : 0.40),
            NSColor(calibratedWhite: 1, alpha: 0.078)
        ]
    }

    public var controlStrokeDefault: NSColor {
        if isHighContrast { return controlStrokeStrong }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.071)
            : NSColor(calibratedWhite: 0, alpha: 0.059)
    }

    /// ControlSolidFillColorDefaultBrush, used as the inner edge of selected GridView items.
    public var controlSolidFill: NSColor {
        if isHighContrast { return windowBackground }
        return isDark
            ? NSColor(calibratedWhite: 69.0 / 255.0, alpha: 1)
            : .white
    }

    /// ControlStrokeColorOnAccentTertiaryBrush, used by an unselected GridViewItem hover edge.
    public var controlStrokeOnAccentTertiary: NSColor {
        if isHighContrast { return controlStrokeStrong }
        return NSColor(calibratedWhite: 0, alpha: 55.0 / 255.0)
    }

    public var focusStrokeOuter: NSColor {
        if isHighContrast { return textPrimary }
        return isDark
            ? .white
            : NSColor(calibratedWhite: 0, alpha: 228.0 / 255.0)
    }

    public var focusStrokeInner: NSColor {
        if isHighContrast { return windowBackground }
        return isDark
            ? NSColor(calibratedWhite: 0, alpha: 179.0 / 255.0)
            : NSColor(calibratedWhite: 1, alpha: 179.0 / 255.0)
    }

    /// WinUI SurfaceStrokeColorFlyout (#0F000000 light / #33000000 dark).
    /// A flyout border is deliberately weaker than a control border so the presenter reads as
    /// one glass surface instead of a stack of dark rectangles.
    public var surfaceStrokeFlyout: NSColor {
        if isHighContrast { return controlStrokeStrong }
        return NSColor(calibratedWhite: 0, alpha: isDark ? 0.20 : 0.06)
    }

    /// Opaque fallback used while transient material rendering is disabled.
    public var flyoutSurfaceFill: NSColor {
        if isHighContrast { return windowBackground }
        return isDark
            ? NSColor(calibratedWhite: 44.0 / 255.0, alpha: 1)
            : .white
    }

    /// ContentDialog's title/content surface (`LayerFillColorDefault` over the presenter).
    public var contentDialogContentFill: NSColor {
        if isHighContrast { return windowBackground }
        return isDark
            ? NSColor(calibratedWhite: 44.0 / 255.0, alpha: 0.96)
            : NSColor(calibratedWhite: 1, alpha: 0.96)
    }

    /// ContentDialog's command surface (`SolidBackgroundFillColorBase`).
    public var contentDialogCommandFill: NSColor { windowBackground }

    /// WinUI SmokeFillColorDefault. Smoke remains black in both color schemes.
    public var contentDialogSmokeFill: NSColor {
        NSColor.black.withAlphaComponent(isHighContrast ? 0.60 : 0.30)
    }

    /// MenuFlyoutItem resources are independent of the generic SubtleFill palette in High
    /// Contrast. WinUI maps hover and press to the system Highlight pair so every glyph and
    /// label remains legible under the user's selected contrast scheme.
    public func menuItemBackground(for state: FluentControlState) -> NSColor {
        switch state {
        case .pointerOver:
            return isHighContrast ? .selectedContentBackgroundColor : subtleFillSecondary
        case .pressed:
            return isHighContrast ? .selectedContentBackgroundColor : subtleFillTertiary
        default:
            return .clear
        }
    }

    public func menuItemForeground(for state: FluentControlState) -> NSColor {
        if isHighContrast {
            switch state {
            case .disabled: return .disabledControlTextColor
            case .pointerOver, .pressed: return .selectedMenuItemTextColor
            default: return .controlTextColor
            }
        }
        return state == .disabled ? textDisabled : textPrimary
    }

    public func menuAcceleratorForeground(for state: FluentControlState) -> NSColor {
        if isHighContrast {
            switch state {
            case .disabled: return .disabledControlTextColor
            case .pointerOver, .pressed: return .selectedMenuItemTextColor
            default: return .textColor
            }
        }
        return state == .disabled ? textDisabled : textSecondary
    }

    public var cardFill: NSColor {
        if isHighContrast { return windowBackground }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 13.0 / 255.0)
            : NSColor(calibratedWhite: 1, alpha: 179.0 / 255.0)
    }

    public var cardStroke: NSColor {
        if isHighContrast { return controlStrokeStrong }
        return NSColor(calibratedWhite: 0, alpha: isDark ? 25.0 / 255.0 : 15.0 / 255.0)
    }

    public var layerFill: NSColor {
        if isHighContrast { return windowBackground }
        return isDark
            ? NSColor(
                calibratedRed: 58.0 / 255.0,
                green: 58.0 / 255.0,
                blue: 58.0 / 255.0,
                alpha: 76.0 / 255.0
            )
            : NSColor(calibratedWhite: 1, alpha: 128.0 / 255.0)
    }

    public var divider: NSColor {
        if isHighContrast { return controlStrokeStrong }
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 21.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 15.0 / 255.0)
    }

    public func buttonBackground(for state: FluentControlState) -> NSColor {
        switch state {
        case .pointerOver: return controlFillSecondary
        case .pressed: return controlFillTertiary
        case .disabled: return controlFillDisabled
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

    private func accentVariant(
        defaultRGB: (CGFloat, CGFloat, CGFloat),
        blendTarget: NSColor,
        fraction: CGFloat
    ) -> NSColor {
        let source = accent.usingColorSpace(.deviceRGB) ?? accent
        let defaultSource = FluentTheme.defaultAccent.usingColorSpace(.deviceRGB) ?? FluentTheme.defaultAccent
        let tolerance: CGFloat = 0.5 / 255.0
        if abs(source.redComponent - defaultSource.redComponent) <= tolerance,
           abs(source.greenComponent - defaultSource.greenComponent) <= tolerance,
           abs(source.blueComponent - defaultSource.blueComponent) <= tolerance {
            return NSColor(
                calibratedRed: defaultRGB.0 / 255.0,
                green: defaultRGB.1 / 255.0,
                blue: defaultRGB.2 / 255.0,
                alpha: source.alphaComponent
            )
        }
        let target = blendTarget.usingColorSpace(.deviceRGB) ?? blendTarget
        let amount = min(max(fraction, 0), 1)
        return NSColor(
            calibratedRed: source.redComponent + (target.redComponent - source.redComponent) * amount,
            green: source.greenComponent + (target.greenComponent - source.greenComponent) * amount,
            blue: source.blueComponent + (target.blueComponent - source.blueComponent) * amount,
            alpha: source.alphaComponent
        )
    }
    public var controlPadding: NSEdgeInsets {
        // ButtonPadding in the WinUI template is 11,5,11,6. The asymmetric vertical inset keeps
        // the native macOS glyph baseline aligned with the Fluent content presenter.
        return NSEdgeInsets(
            top: 5 * density.scale,
            left: 11 * density.scale,
            bottom: 6 * density.scale,
            right: 11 * density.scale
        )
    }
    public var cardCornerRadius: CGFloat { designTokens.cardCornerRadius }
}

/// Resolves requested appearance independently from the rest of the theme design tokens.
public enum FluentThemeResolver {
    public static func resolve(
        preference: FluentThemePreference,
        appearance: NSAppearance,
        baseTheme: FluentTheme = FluentTheme()
    ) -> FluentTheme {
        let scheme: FluentThemeColorScheme
        switch preference {
        case .light:
            scheme = .light
        case .dark:
            scheme = .dark
        case .system:
            scheme = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
        return baseTheme.with(colorScheme: scheme)
    }

    public static func resolve(theme: FluentTheme, using appearance: NSAppearance) -> FluentTheme {
        resolve(
            preference: FluentThemePreference(colorScheme: theme.colorScheme),
            appearance: appearance,
            baseTheme: theme
        )
    }
}

func fluentDefaultAppearance() -> NSAppearance {
    NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua) ?? NSAppearance()
}

func fluentResolvedTheme(_ theme: FluentTheme, using appearance: NSAppearance? = nil) -> FluentTheme {
    FluentThemeResolver.resolve(theme: theme, using: appearance ?? fluentDefaultAppearance())
}

public extension NSColor {
    static var fluentAccent: NSColor { FluentTheme.current.accent }
}

/// An observable application-level theme source with separate requested and resolved appearance
/// state. `theme` remains as a source-compatible alias for `resolvedTheme`.
public final class FluentThemeStore {
    public let observable: FluentObservable<FluentTheme>
    private let preferenceObservable: FluentObservable<FluentThemePreference>
    private let requestObservable: FluentObservable<UInt64>
    private var configurationTheme: FluentTheme
    private var lastAppearance: NSAppearance
    private var generation: UInt64 = 0

    public init(_ theme: FluentTheme = FluentTheme()) {
        configurationTheme = theme
        lastAppearance = fluentDefaultAppearance()
        let preference = FluentThemePreference(colorScheme: theme.colorScheme)
        preferenceObservable = FluentObservable(preference)
        requestObservable = FluentObservable(0)
        observable = FluentObservable(
            FluentThemeResolver.resolve(
                preference: preference,
                appearance: lastAppearance,
                baseTheme: theme
            )
        )
    }

    public convenience init(
        preference: FluentThemePreference,
        resolvedTheme: FluentTheme = FluentTheme()
    ) {
        self.init(resolvedTheme.with(colorScheme: preference.colorScheme))
        self.preference = preference
        resolve(using: fluentDefaultAppearance())
    }

    public var preference: FluentThemePreference {
        get { preferenceObservable.value }
        set {
            guard preferenceObservable.value != newValue else { return }
            preferenceObservable.value = newValue
            requestResolution()
        }
    }

    public var resolvedTheme: FluentTheme { observable.value }

    public var theme: FluentTheme {
        get { resolvedTheme }
        set {
            let current = resolvedTheme
            let schemeWasChanged = newValue.colorScheme != current.colorScheme
            let nextPreference: FluentThemePreference
            if newValue.colorScheme == .system || schemeWasChanged || preference != .system {
                nextPreference = FluentThemePreference(colorScheme: newValue.colorScheme)
            } else {
                // `store.theme = store.theme.with(...)` must not silently turn System into the
                // currently resolved Light/Dark preference.
                nextPreference = preference
            }
            let nextConfiguration = newValue.with(colorScheme: .light)
            guard configurationTheme != nextConfiguration || preference != nextPreference else { return }
            configurationTheme = nextConfiguration
            if preference != nextPreference { preferenceObservable.value = nextPreference }
            requestResolution()
        }
    }

    /// Resolves the actual theme from a final AppKit appearance. Window coordinators call this
    /// after coalescing root appearance notifications.
    @discardableResult
    public func resolve(using appearance: NSAppearance) -> FluentTheme {
        lastAppearance = appearance
        let resolved = FluentThemeResolver.resolve(
            preference: preference,
            appearance: appearance,
            baseTheme: configurationTheme
        )
        if observable.value != resolved { observable.value = resolved }
        return resolved
    }

    var requestChanges: FluentObservable<UInt64> { requestObservable }

    private func requestResolution() {
        generation &+= 1
        requestObservable.value = generation
        resolve(using: lastAppearance)
    }

    public var binding: FluentBinding<FluentTheme> {
        FluentBinding(
            get: { self.theme },
            set: { self.theme = $0 },
            observe: { self.observable.observe($0, notifyImmediately: false) },
            removeObserver: { self.observable.removeObserver($0) }
        )
    }

    public var preferenceBinding: FluentBinding<FluentThemePreference> {
        FluentBinding(
            get: { self.preference },
            set: { self.preference = $0 },
            observe: { self.preferenceObservable.observe($0, notifyImmediately: false) },
            removeObserver: { self.preferenceObservable.removeObserver($0) }
        )
    }
}
