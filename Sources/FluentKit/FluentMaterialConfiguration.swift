import AppKit

/// Optional overrides for a preset material. Nil fields inherit the surrounding theme or the
/// control's preset. Use a clear tint to explicitly remove an inherited tint.
public struct FluentMaterialConfiguration: Equatable {
    public var material: FluentMaterial?
    public var tintColor: NSColor?
    public var fallbackColor: NSColor?
    public var blendingMode: NSVisualEffectView.BlendingMode?
    public var isEnabled: Bool?

    public init(material: FluentMaterial? = nil, tintColor: NSColor? = nil,
                fallbackColor: NSColor? = nil, blendingMode: NSVisualEffectView.BlendingMode? = nil,
                isEnabled: Bool? = nil) {
        self.material = material
        self.tintColor = tintColor
        self.fallbackColor = fallbackColor
        self.blendingMode = blendingMode
        self.isEnabled = isEnabled
    }

    func merging(_ override: Self?) -> Self {
        guard let override else { return self }
        return Self(material: override.material ?? material, tintColor: override.tintColor ?? tintColor,
            fallbackColor: override.fallbackColor ?? fallbackColor,
            blendingMode: override.blendingMode ?? blendingMode, isEnabled: override.isEnabled ?? isEnabled)
    }
}

extension FluentMaterialRole {
    func fallback(in theme: FluentTheme) -> NSColor {
        switch self {
        case .window, .navigation: return theme.windowBackground
        case .transient: return theme.flyoutSurfaceFill
        case .toolTip: return theme.toolTipSurfaceFill
        case .container: return theme.cardFill
        }
    }

    var defaultBlendingMode: NSVisualEffectView.BlendingMode {
        self == .container ? .withinWindow : .behindWindow
    }
}
