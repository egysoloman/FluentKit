import AppKit

/// Semantic styles shipped with WinUI's InfoBadge resources.
public enum FluentInfoBadgeAppearance: Hashable, Sendable {
    case accent
    case attention
    case informational
    case success
    case caution
    case critical
}

/// A compact, non-interactive status marker matching WinUI InfoBadge's dot, icon, and value modes.
///
/// A nonnegative value takes precedence over an icon. With the default value of `-1`, an icon is
/// shown when supplied; otherwise the badge collapses to a four-point attention dot.
public struct FluentInfoBadge: FluentUpdatablePrimitiveView {
    private let value: Int
    private let systemImageName: String?
    private let image: NSImage?
    private let appearance: FluentInfoBadgeAppearance
    private let background: NSColor?
    private let foreground: NSColor?
    private let cornerRadius: CGFloat?
    private let accessibilityLabel: String?

    public init(
        value: Int = -1,
        systemImageName: String? = nil,
        image: NSImage? = nil,
        appearance: FluentInfoBadgeAppearance = .accent,
        background: NSColor? = nil,
        foreground: NSColor? = nil,
        cornerRadius: CGFloat? = nil,
        accessibilityLabel: String? = nil
    ) {
        precondition(value >= -1, "InfoBadge value must be equal to or greater than -1")
        self.value = value
        self.systemImageName = systemImageName
        self.image = image
        self.appearance = appearance
        self.background = background
        self.foreground = foreground
        self.cornerRadius = cornerRadius.map { max($0, 0) }
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentInfoBadgeHost(
            value: value,
            systemImageName: systemImageName,
            image: image,
            appearance: appearance,
            background: background,
            foreground: foreground,
            cornerRadius: cornerRadius,
            accessibilityLabel: accessibilityLabel,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentInfoBadgeHost else { return false }
        host.update(
            value: value,
            systemImageName: systemImageName,
            image: image,
            appearance: appearance,
            background: background,
            foreground: foreground,
            cornerRadius: cornerRadius,
            accessibilityLabel: accessibilityLabel,
            context: context
        )
        return true
    }
}

private final class FluentInfoBadgeHost: NSView {
    private enum DisplayKind: Equatable {
        case dot
        case icon
        case value
    }

    private enum Metrics {
        static let minimumSize: CGFloat = 4
        static let maximumHeight: CGFloat = 16
        static let valueFontSize: CGFloat = 11
        static let horizontalContentMargin: CGFloat = 4
        static let iconHorizontalMargin: CGFloat = 4
        static let iconVerticalMargin: CGFloat = 4
        static let iconMaximumWidth: CGFloat = 12
        static let iconMaximumHeightLight: CGFloat = 9
        static let iconMaximumHeightDark: CGFloat = 8
    }

    private let valueLabel = FluentInfoBadgeValueLabel(labelWithString: "")
    private let iconView = FluentInfoBadgeImageView()
    private var value: Int
    private var systemImageName: String?
    private var sourceImage: NSImage?
    private var badgeAppearance: FluentInfoBadgeAppearance
    private var customBackground: NSColor?
    private var customForeground: NSColor?
    private var explicitCornerRadius: CGFloat?
    private var explicitAccessibilityLabel: String?
    private var context: FluentRenderContext
    private var displayKind: DisplayKind = .dot

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { measuredSize() }

    init(
        value: Int,
        systemImageName: String?,
        image: NSImage?,
        appearance: FluentInfoBadgeAppearance,
        background: NSColor?,
        foreground: NSColor?,
        cornerRadius: CGFloat?,
        accessibilityLabel: String?,
        context: FluentRenderContext
    ) {
        self.value = value
        self.systemImageName = systemImageName
        sourceImage = image
        badgeAppearance = appearance
        customBackground = background
        customForeground = foreground
        explicitCornerRadius = cornerRadius
        explicitAccessibilityLabel = accessibilityLabel
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBadge")
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        valueLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBadge.Value")
        valueLabel.alignment = .center
        valueLabel.isEditable = false
        valueLabel.isSelectable = false
        valueLabel.drawsBackground = false
        valueLabel.isBordered = false
        valueLabel.setAccessibilityElement(false)
        iconView.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBadge.Icon")
        iconView.setAccessibilityElement(false)
        [valueLabel, iconView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            addSubview($0)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = explicitCornerRadius ?? bounds.height / 2
        switch displayKind {
        case .dot:
            valueLabel.frame = .zero
            iconView.frame = .zero
        case .value:
            valueLabel.frame = NSRect(
                x: Metrics.horizontalContentMargin,
                y: 0,
                width: max(bounds.width - 2 * Metrics.horizontalContentMargin, 0),
                height: bounds.height
            )
            iconView.frame = .zero
        case .icon:
            let available = NSSize(
                width: max(bounds.width - 2 * Metrics.iconHorizontalMargin, 0),
                height: max(bounds.height - 2 * Metrics.iconVerticalMargin, 0)
            )
            let iconHeight = context.theme.isDark
                ? Metrics.iconMaximumHeightDark
                : Metrics.iconMaximumHeightLight
            let size = aspectFit(
                imageSize: iconView.image?.size ?? .zero,
                in: NSSize(
                    width: min(available.width, Metrics.iconMaximumWidth),
                    height: min(available.height, iconHeight)
                )
            )
            iconView.frame = NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            valueLabel.frame = .zero
        }
    }

    func update(
        value: Int,
        systemImageName: String?,
        image: NSImage?,
        appearance: FluentInfoBadgeAppearance,
        background: NSColor?,
        foreground: NSColor?,
        cornerRadius: CGFloat?,
        accessibilityLabel: String?,
        context: FluentRenderContext
    ) {
        precondition(value >= -1, "InfoBadge value must be equal to or greater than -1")
        self.value = value
        self.systemImageName = systemImageName
        sourceImage = image
        badgeAppearance = appearance
        customBackground = background
        customForeground = foreground
        explicitCornerRadius = cornerRadius
        explicitAccessibilityLabel = accessibilityLabel
        self.context = context
        refresh()
    }

    private func refresh() {
        let resolvedImage = sourceImage ?? systemImageName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: explicitAccessibilityLabel)
        }
        displayKind = value >= 0 ? .value : (resolvedImage == nil ? .dot : .icon)
        let foreground = customForeground
            ?? (context.theme.isHighContrast ? NSColor.white : context.theme.textOnAccent)
        valueLabel.stringValue = value >= 0 ? String(value) : ""
        valueLabel.font = .systemFont(ofSize: Metrics.valueFontSize, weight: .regular)
        valueLabel.textColor = foreground
        valueLabel.isHidden = displayKind != .value
        if let sourceImage {
            iconView.image = sourceImage
        } else {
            iconView.image = resolvedImage?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: Metrics.iconMaximumHeightLight, weight: .regular)
                    .applying(.init(hierarchicalColor: foreground))
            ) ?? resolvedImage
        }
        iconView.isHidden = displayKind != .icon
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = (customBackground ?? context.theme.infoBadgeBackground(for: badgeAppearance)).cgColor
        CATransaction.commit()
        updateAccessibility()
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func measuredSize() -> NSSize {
        switch displayKind {
        case .dot:
            return NSSize(width: Metrics.minimumSize, height: Metrics.minimumSize)
        case .icon:
            return NSSize(width: 20, height: Metrics.maximumHeight)
        case .value:
            let textWidth = ceil(valueLabel.attributedStringValue.size().width)
            let width = max(Metrics.maximumHeight, textWidth + 2 * Metrics.horizontalContentMargin)
            return NSSize(width: width, height: Metrics.maximumHeight)
        }
    }

    private func updateAccessibility() {
        let resolvedLabel: String = if let explicitAccessibilityLabel {
            explicitAccessibilityLabel
        } else {
            switch displayKind {
            case .dot: "Notification"
            case .icon: "Status"
            case .value: String(value)
            }
        }
        setAccessibilityLabel(resolvedLabel)
        setAccessibilityValue(displayKind == .value ? String(value) : nil)
    }

    private func aspectFit(imageSize: NSSize, in available: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0,
              available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        return NSSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
    }
}

/// Draw images in the host's top-down coordinate space. `respectFlipped: true` is important for
/// SF Symbols: opting out of the flipped destination rotates asymmetric glyphs by 180 degrees.
private final class FluentInfoBadgeImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        image?.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

/// WinUI's value presenter is a TextBlock and therefore has no native text-cell inset. A regular
/// `NSTextFieldCell` consumes additional horizontal padding, which clips a single digit inside the
/// exact 16pt badge after WinUI's own 4pt content margins are applied.
private final class FluentInfoBadgeValueLabel: NSTextField {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !stringValue.isEmpty, let font, let textColor else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil((stringValue as NSString).size(withAttributes: attributes).height)
        (stringValue as NSString).draw(
            in: NSRect(
                x: bounds.minX,
                y: bounds.midY - textHeight / 2,
                width: bounds.width,
                height: textHeight
            ),
            withAttributes: attributes
        )
    }
}
