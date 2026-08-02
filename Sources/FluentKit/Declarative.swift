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
    private var contentConstraints: [NSLayoutConstraint] = []

    public init(contentView: NSView, style: any FluentCardStyle = FluentAutomaticCardStyle()) {
        self.contentView = contentView
        self.style = style
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
        appearance.fillColor.setFill()
        path.fill()
        if appearance.strokeWidth > 0 {
            appearance.strokeColor.setStroke()
            path.lineWidth = appearance.strokeWidth
            path.stroke()
        }
    }

    private func applyStyle() {
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
