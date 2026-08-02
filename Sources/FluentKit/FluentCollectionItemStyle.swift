import AppKit

/// The semantic state supplied to a collection item style.
public struct FluentCollectionItemStyleConfiguration {
    public let layoutKind: FluentCollectionLayout.Kind
    public let controlState: FluentControlState
    public let isSelected: Bool
    public let isEnabled: Bool
    public let isFocused: Bool
    public let theme: FluentTheme

    public init(
        layoutKind: FluentCollectionLayout.Kind,
        controlState: FluentControlState = .normal,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        isFocused: Bool = false,
        theme: FluentTheme = .current
    ) {
        self.layoutKind = layoutKind
        self.controlState = controlState
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.theme = theme
    }
}

/// Stable visual metrics for a ListViewItem- or GridViewItem-like container.
public struct FluentCollectionItemAppearance {
    public let backgroundColor: NSColor
    public let contentInsets: NSEdgeInsets
    public let contentOpacity: CGFloat
    public let cornerRadius: CGFloat
    public let selectionIndicatorColor: NSColor
    public let selectionIndicatorSize: NSSize
    public let selectionIndicatorLeadingMargin: CGFloat
    public let selectionIndicatorPressedScale: CGFloat
    public let outerBorderColor: NSColor
    public let outerBorderWidth: CGFloat
    public let innerBorderColor: NSColor
    public let innerBorderWidth: CGFloat
    public let focusOuterColor: NSColor
    public let focusInnerColor: NSColor

    public init(
        backgroundColor: NSColor,
        contentInsets: NSEdgeInsets,
        contentOpacity: CGFloat = 1,
        cornerRadius: CGFloat = 4,
        selectionIndicatorColor: NSColor = .clear,
        selectionIndicatorSize: NSSize = NSSize(width: 3, height: 16),
        selectionIndicatorLeadingMargin: CGFloat = 4,
        selectionIndicatorPressedScale: CGFloat = 0.625,
        outerBorderColor: NSColor = .clear,
        outerBorderWidth: CGFloat = 0,
        innerBorderColor: NSColor = .clear,
        innerBorderWidth: CGFloat = 0,
        focusOuterColor: NSColor = .clear,
        focusInnerColor: NSColor = .clear
    ) {
        self.backgroundColor = backgroundColor
        self.contentInsets = contentInsets
        self.contentOpacity = min(max(contentOpacity, 0), 1)
        self.cornerRadius = max(cornerRadius, 0)
        self.selectionIndicatorColor = selectionIndicatorColor
        self.selectionIndicatorSize = NSSize(
            width: max(selectionIndicatorSize.width, 0),
            height: max(selectionIndicatorSize.height, 0)
        )
        self.selectionIndicatorLeadingMargin = max(selectionIndicatorLeadingMargin, 0)
        self.selectionIndicatorPressedScale = min(max(selectionIndicatorPressedScale, 0), 1)
        self.outerBorderColor = outerBorderColor
        self.outerBorderWidth = max(outerBorderWidth, 0)
        self.innerBorderColor = innerBorderColor
        self.innerBorderWidth = max(innerBorderWidth, 0)
        self.focusOuterColor = focusOuterColor
        self.focusInnerColor = focusInnerColor
    }
}

public protocol FluentCollectionItemStyle {
    func appearance(
        for configuration: FluentCollectionItemStyleConfiguration
    ) -> FluentCollectionItemAppearance
}

/// The source-derived ListViewItem and GridViewItem appearance.
public struct FluentAutomaticCollectionItemStyle: FluentCollectionItemStyle {
    public init() {}

    public func appearance(
        for configuration: FluentCollectionItemStyleConfiguration
    ) -> FluentCollectionItemAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let background: NSColor
        if configuration.isSelected {
            background = switch state {
            case .pressed: theme.subtleFillSecondary
            case .pointerOver: theme.subtleFillTertiary
            case .disabled: theme.subtleFillSecondary
            default: configuration.layoutKind == .adaptiveGrid
                ? theme.subtleFillTertiary
                : theme.subtleFillSecondary
            }
        } else {
            background = switch state {
            case .pointerOver: theme.subtleFillSecondary
            case .pressed: theme.subtleFillTertiary
            default: .clear
            }
        }

        let isGrid = configuration.layoutKind == .adaptiveGrid
        let gridBorderColor: NSColor
        let gridBorderWidth: CGFloat
        if isGrid, configuration.isSelected {
            gridBorderColor = switch state {
            case .pointerOver: theme.accentFillSecondary
            case .pressed: theme.accentFillTertiary
            case .disabled: theme.accentFillDisabled
            default: theme.accentFillDefault
            }
            gridBorderWidth = 2
        } else if isGrid, state == .pointerOver {
            gridBorderColor = theme.controlStrokeOnAccentTertiary
            gridBorderWidth = 1
        } else {
            gridBorderColor = .clear
            gridBorderWidth = 0
        }

        return FluentCollectionItemAppearance(
            backgroundColor: background,
            contentInsets: isGrid
                ? NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
                : NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 12),
            contentOpacity: configuration.isEnabled ? 1 : 0.3,
            cornerRadius: 4,
            selectionIndicatorColor: configuration.isEnabled
                ? theme.accentFillDefault
                : theme.accentFillDisabled,
            selectionIndicatorSize: NSSize(width: 3, height: 16),
            selectionIndicatorLeadingMargin: 4,
            selectionIndicatorPressedScale: 10.0 / 16.0,
            outerBorderColor: gridBorderColor,
            outerBorderWidth: gridBorderWidth,
            innerBorderColor: isGrid && configuration.isSelected ? theme.controlSolidFill : .clear,
            innerBorderWidth: isGrid && configuration.isSelected ? 1 : 0,
            focusOuterColor: configuration.isFocused ? theme.focusStrokeOuter : .clear,
            focusInnerColor: configuration.isFocused ? theme.focusStrokeInner : .clear
        )
    }
}

public extension FluentCollectionItemStyle where Self == FluentAutomaticCollectionItemStyle {
    static var automatic: FluentAutomaticCollectionItemStyle {
        FluentAutomaticCollectionItemStyle()
    }
}
