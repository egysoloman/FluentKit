import AppKit

@resultBuilder
public enum FluentNSViewBuilder {
    public static func buildBlock(_ components: NSView...) -> [NSView] { components }
    public static func buildOptional(_ component: [NSView]?) -> [NSView] { component ?? [] }
    public static func buildEither(first component: [NSView]) -> [NSView] { component }
    public static func buildEither(second component: [NSView]) -> [NSView] { component }
    public static func buildArray(_ components: [[NSView]]) -> [NSView] { components.flatMap { $0 } }
}

public func FluentNSVStack(spacing: CGFloat = 12, alignment: NSLayoutConstraint.Attribute = .leading, @FluentNSViewBuilder content: () -> [NSView]) -> NSStackView {
    makeStack(orientation: .vertical, spacing: spacing, alignment: alignment, content: content())
}

public func FluentNSHStack(spacing: CGFloat = 12, alignment: NSLayoutConstraint.Attribute = .centerY, @FluentNSViewBuilder content: () -> [NSView]) -> NSStackView {
    makeStack(orientation: .horizontal, spacing: spacing, alignment: alignment, content: content())
}

private func makeStack(orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat, alignment: NSLayoutConstraint.Attribute, content: [NSView]) -> NSStackView {
    let stack = NSStackView(views: content)
    stack.orientation = orientation
    stack.spacing = spacing
    stack.alignment = switch alignment {
    case .trailing: .trailing
    case .centerX: .centerX
    case .top: .top
    case .bottom: .bottom
    default: orientation == .vertical ? .leading : .centerY
    }
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

public final class FluentCard: NSView {
    public var theme: FluentTheme = .current { didSet { applyStyle() } }
    public var style: any FluentCardStyle { didSet { applyStyle() } }
    public let contentView: NSView
    /// Nil keeps the card's preset fill unless the theme explicitly configures container materials.
    public var materialConfiguration: FluentMaterialConfiguration? {
        didSet { if oldValue != materialConfiguration { applyStyle() } }
    }
    private var materialView: FluentMaterialView?
    private var contentConstraints: [NSLayoutConstraint] = []

    public init(contentView: NSView, style: any FluentCardStyle = FluentAutomaticCardStyle(),
                materialConfiguration: FluentMaterialConfiguration? = nil) {
        self.contentView = contentView
        self.style = style
        self.materialConfiguration = materialConfiguration
        super.init(frame: .zero)
        wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        let contentSize = contentView.fittingSize
        let insets = style.appearance(for: theme).contentInsets
        return NSSize(
            width: contentSize.width + insets.left + insets.right,
            height: contentSize.height + insets.top + insets.bottom
        )
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = style.appearance(for: theme)
        let strokeInset = max(appearance.strokeWidth / 2, fluentHalfPixelInset())
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: strokeInset, dy: strokeInset),
            xRadius: max(appearance.cornerRadius - strokeInset, 0),
            yRadius: max(appearance.cornerRadius - strokeInset, 0)
        )
        if materialView == nil {
            appearance.fillColor.setFill()
            path.fill()
        }
        if appearance.strokeWidth > 0 {
            appearance.strokeColor.setStroke()
            path.lineWidth = appearance.strokeWidth
            path.stroke()
        }
    }

    public override func layout() {
        super.layout()
        let appearance = style.appearance(for: theme)
        materialView?.frame = bounds.insetBy(dx: appearance.strokeWidth, dy: appearance.strokeWidth)
    }

    private func updateMaterial() {
        guard materialConfiguration != nil || theme.materialConfigurations[.container] != nil else {
            materialView?.removeFromSuperview()
            materialView = nil
            return
        }
        let material: FluentMaterialView
        if let materialView { material = materialView }
        else {
            material = FluentMaterialView()
            material.identifier = NSUserInterfaceItemIdentifier("FluentKit.Card.Material")
            addSubview(material, positioned: .below, relativeTo: contentView)
            materialView = material
        }
        let style = self.style
        let appearance = style.appearance(for: theme)
        material.configure(theme: theme, role: .container, configuration: materialConfiguration,
            fallback: { style.appearance(for: $0).fillColor })
        material.layer?.cornerRadius = max(0, appearance.cornerRadius - appearance.strokeWidth)
        material.layer?.masksToBounds = true
        material.needsLayout = true
        needsLayout = true
    }

    private func applyStyle() {
        updateMaterial()
        contentConstraints.forEach { $0.isActive = false }
        let insets = style.appearance(for: theme).contentInsets
        contentConstraints = [
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(contentConstraints)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
}

extension FluentCard: FluentFillWidthProviding {}
