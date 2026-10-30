import AppKit

/// A WinUI Border: a single-child container that owns a rounded, optionally bordered surface.
public struct FluentBorder<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let background: NSColor?
    fileprivate let borderColor: NSColor
    fileprivate let borderWidth: CGFloat
    fileprivate let cornerRadius: CGFloat
    fileprivate let padding: NSEdgeInsets
    fileprivate let content: Content

    public init(
        background: NSColor? = nil,
        borderColor: NSColor = .clear,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        padding: NSEdgeInsets = NSEdgeInsetsZero,
        @FluentViewBuilder content: () -> Content
    ) {
        self.background = background
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.padding = padding
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentBorderHost(
            contentView: content._mount(in: context),
            background: background,
            borderColor: borderColor,
            borderWidth: borderWidth,
            cornerRadius: cornerRadius,
            padding: padding
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentBorderHost,
              content._update(host.contentView, in: context) else { return false }
        host.update(
            background: background,
            borderColor: borderColor,
            borderWidth: borderWidth,
            cornerRadius: cornerRadius,
            padding: padding
        )
        return true
    }
}

private final class FluentBorderHost: NSView {
    let contentView: NSView
    private var background: NSColor?
    private var borderColor: NSColor
    private var borderWidth: CGFloat
    private var cornerRadius: CGFloat
    private var padding: NSEdgeInsets

    init(
        contentView: NSView,
        background: NSColor?,
        borderColor: NSColor,
        borderWidth: CGFloat,
        cornerRadius: CGFloat,
        padding: NSEdgeInsets
    ) {
        self.contentView = contentView
        self.background = background
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.padding = padding
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Border")
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        if let background {
            background.setFill()
            path.fill()
        }
        if borderWidth > 0 {
            borderColor.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
    }

    override func layout() {
        super.layout()
        contentView.frame = NSRect(
            x: padding.left,
            y: padding.bottom,
            width: max(0, bounds.width - padding.left - padding.right),
            height: max(0, bounds.height - padding.top - padding.bottom)
        )
    }

    func update(
        background: NSColor?,
        borderColor: NSColor,
        borderWidth: CGFloat,
        cornerRadius: CGFloat,
        padding: NSEdgeInsets
    ) {
        self.background = background
        self.borderColor = borderColor
        self.borderWidth = max(borderWidth, 0)
        self.cornerRadius = max(cornerRadius, 0)
        self.padding = padding
        layer?.cornerRadius = self.cornerRadius
        layer?.cornerCurve = .continuous
        needsDisplay = true
        needsLayout = true
    }
}

/// The WinUI Image.Stretch semantics.
public enum FluentImageScaling: Hashable, Sendable {
    case none
    case fill
    case aspectFit
    case aspectFill
}

/// A read-only image presenter backed by NSImageView.
public struct FluentImageView: FluentUpdatablePrimitiveView {
    fileprivate let image: NSImage?
    fileprivate let scaling: FluentImageScaling
    fileprivate let accessibilityLabel: String?

    public init(
        _ image: NSImage?,
        scaling: FluentImageScaling = .aspectFit,
        accessibilityLabel: String? = nil
    ) {
        self.image = image
        self.scaling = scaling
        self.accessibilityLabel = accessibilityLabel
    }

    public init(
        systemImageName: String,
        scaling: FluentImageScaling = .aspectFit,
        accessibilityLabel: String? = nil
    ) {
        image = NSImage(
            systemSymbolName: systemImageName,
            accessibilityDescription: accessibilityLabel
        )
        self.scaling = scaling
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentImageViewHost(
            image: image,
            scaling: scaling,
            accessibilityLabel: accessibilityLabel
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentImageViewHost else { return false }
        host.update(image: image, scaling: scaling, accessibilityLabel: accessibilityLabel)
        return true
    }
}

private final class FluentImageViewHost: NSImageView {
    init(image: NSImage?, scaling: FluentImageScaling, accessibilityLabel: String?) {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Image")
        imageAlignment = .alignCenter
        imageFrameStyle = .none
        setAccessibilityRole(.image)
        setAccessibilityLabel(accessibilityLabel ?? "Image")
        update(image: image, scaling: scaling, accessibilityLabel: accessibilityLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(image: NSImage?, scaling: FluentImageScaling, accessibilityLabel: String?) {
        self.image = image
        imageScaling = switch scaling {
        case .none: .scaleNone
        case .fill: .scaleAxesIndependently
        case .aspectFit: .scaleProportionallyUpOrDown
        case .aspectFill: .scaleProportionallyUpOrDown
        }
        setAccessibilityLabel(accessibilityLabel ?? "Image")
    }
}
