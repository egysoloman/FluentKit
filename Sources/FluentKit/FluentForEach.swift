import AppKit

/// A data-driven declarative collection that reuses native row views by stable identity.
/// It is intentionally separate from FluentList: ForEach participates in the surrounding layout,
/// while FluentList adds scrolling, selection, and virtualization.
public struct FluentForEach<Data: RandomAccessCollection, ID: Hashable, Content: FluentView>: FluentUpdatablePrimitiveView {
    private let data: Data
    private let id: (Data.Element) -> ID
    private let rowContent: (Data.Element) -> Content
    private let spacing: CGFloat

    public init(
        _ data: Data,
        id: @escaping (Data.Element) -> ID,
        spacing: CGFloat = 8,
        @FluentViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.rowContent = content
        self.spacing = spacing
    }

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        spacing: CGFloat = 8,
        @FluentViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, id: { $0[keyPath: id] }, spacing: spacing, content: content)
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentForEachHost(spacing: spacing)
        host.setRows(records(in: context), context: context)
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentForEachHost else { return false }
        host.update(rows: records(in: context), spacing: spacing, context: context)
        return true
    }

    private func records(in context: FluentRenderContext) -> [FluentForEachRecord] {
        data.map { element in
            let row = rowContent(element)
            return FluentForEachRecord(
                id: AnyHashable(id(element)),
                make: { row._mount(in: context) },
                update: { view, updateContext in row._update(view, in: updateContext) }
            )
        }
    }
}

private struct FluentForEachRecord {
    let id: AnyHashable
    let make: () -> NSView
    let update: (NSView, FluentRenderContext) -> Bool
}

private final class FluentForEachHost: NSView {
    private let stack = NSStackView()
    private var records: [FluentForEachRecord] = []
    private var views: [NSView] = []
    private var spacing: CGFloat
    private var context = FluentRenderContext()

    init(spacing: CGFloat) {
        self.spacing = spacing
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Items")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRows(_ records: [FluentForEachRecord], context: FluentRenderContext) {
        self.records = records
        self.context = context
        views = records.map { $0.make() }
        views.forEach(stack.addArrangedSubview)
        updateAccessibilityChildren()
    }

    func update(rows newRecords: [FluentForEachRecord], spacing: CGFloat, context: FluentRenderContext) {
        let oldIDs = records.map(\.id)
        let newIDs = newRecords.map(\.id)
        let canReuseByID = Set(oldIDs).count == oldIDs.count && Set(newIDs).count == newIDs.count
        let oldViewsByID = zip(records, views).reduce(into: [AnyHashable: NSView]()) { result, pair in
            result[pair.0.id] = pair.1
        }
        var nextViews: [NSView] = []
        var reusedIDs = Set<AnyHashable>()

        for record in newRecords {
            if canReuseByID, let existing = oldViewsByID[record.id], reusedIDs.insert(record.id).inserted {
                if record.update(existing, context) {
                    nextViews.append(existing)
                } else {
                    existing.removeFromSuperview()
                    nextViews.append(record.make())
                }
            } else {
                nextViews.append(record.make())
            }
        }

        for arranged in stack.arrangedSubviews {
            stack.removeArrangedSubview(arranged)
            if !nextViews.contains(where: { $0 === arranged }) {
                arranged.removeFromSuperview()
            }
        }
        for view in nextViews {
            stack.addArrangedSubview(view)
        }

        records = newRecords
        views = nextViews
        self.spacing = spacing
        self.context = context
        stack.spacing = spacing
        updateAccessibilityChildren()
    }

    private func updateAccessibilityChildren() {
        setAccessibilityChildren(views)
    }
}
