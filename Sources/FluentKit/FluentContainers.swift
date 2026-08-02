import AppKit

public enum FluentScrollAxis {
    case vertical
    case horizontal
    case both
}

/// The axis along which a divider renders.
public enum FluentDividerOrientation: Sendable {
    case horizontal
    case vertical
}

public struct FluentScrollView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let axis: FluentScrollAxis

    public init(_ axis: FluentScrollAxis = .vertical, @FluentViewBuilder content: () -> Content) {
        self.axis = axis
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let scroll = FluentScrollHost(axis: axis)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = axis != .horizontal
        scroll.hasHorizontalScroller = axis != .vertical
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let contentView = content._mount(in: context)
        let document = FluentScrollDocumentView(contentView: contentView)
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        if axis == .vertical {
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        } else if axis == .horizontal {
            document.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor).isActive = true
        } else {
            document.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor).isActive = true
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
        }
        return scroll
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let scroll = view as? NSScrollView,
              let document = scroll.documentView as? FluentScrollDocumentView else { return false }
        return content._update(document.contentView, in: context)
    }
}

private final class FluentScrollHost: NSScrollView, FluentFillWidthProviding {
    let axis: FluentScrollAxis

    init(axis: FluentScrollAxis) {
        self.axis = axis
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var fluentFillsAvailableWidth: Bool { axis != .horizontal }
}

private final class FluentScrollDocumentView: NSView {
    let contentView: NSView

    override var isFlipped: Bool { true }

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

public struct FluentSpacer: FluentPrimitiveView {
    public let minLength: CGFloat

    public init(minLength: CGFloat = 0) { self.minLength = minLength }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if minLength > 0 { spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: minLength).isActive = true }
        return spacer
    }
}

public struct FluentDivider: FluentPrimitiveView {
    public let orientation: FluentDividerOrientation

    /// Creates a one-point divider. Horizontal is the default for backwards compatibility.
    public init(orientation: FluentDividerOrientation = .horizontal) {
        self.orientation = orientation
    }
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let divider = FluentDividerView(color: context.theme.divider)
        divider.translatesAutoresizingMaskIntoConstraints = false
        switch orientation {
        case .horizontal:
            divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        case .vertical:
            divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        }
        return divider
    }
}

private final class FluentDividerView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}

public struct FluentGrid<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let columns: Int
    fileprivate let spacing: CGFloat
    fileprivate let content: Content

    public init(columns: Int, spacing: CGFloat = 12, @FluentViewBuilder content: () -> Content) {
        self.columns = max(columns, 1)
        self.spacing = spacing
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let anyContent = FluentAnyView(content)
        let children = anyContent.children ?? [anyContent]
        let views = children.map { $0.mount(context) }
        let rows = stride(from: 0, to: views.count, by: columns).map { index in
            Array(views[index ..< min(index + columns, views.count)])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = spacing
        grid.columnSpacing = spacing
        return grid
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let grid = view as? NSGridView,
              let children = FluentAnyView(content).children,
              grid.numberOfRows == Int(ceil(Double(children.count) / Double(columns))) else { return false }
        for row in 0..<grid.numberOfRows {
            for column in 0..<grid.numberOfColumns {
                let index = row * columns + column
                guard index < children.count else { continue }
                let cell = grid.cell(atColumnIndex: column, rowIndex: row)
                guard let native = cell.contentView else { return false }
                if !children[index]._update(native, in: context) { return false }
            }
        }
        return true
    }
}
