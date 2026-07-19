import AppKit

/// A stable-identity tree node whose row is composed from an ordinary Fluent view.
public struct FluentOutlineNode<ID: Hashable> {
    public let id: ID
    public let children: [FluentOutlineNode<ID>]
    fileprivate let content: FluentAnyView

    public init<Content: FluentView>(
        id: ID,
        children: [FluentOutlineNode<ID>] = [],
        @FluentViewBuilder content: () -> Content
    ) {
        self.id = id
        self.children = children
        self.content = FluentAnyView(content())
    }
}

/// A native hierarchical collection backed by `NSOutlineView`. The native host preserves
/// expansion and selection by stable node ID while row contents reconcile in place.
public struct FluentOutline<ID: Hashable>: FluentUpdatablePrimitiveView {
    private let nodes: [FluentOutlineNode<ID>]
    private let selection: FluentBinding<ID?>?
    private let rowHeight: CGFloat

    public init(
        nodes: [FluentOutlineNode<ID>],
        selectionID: FluentBinding<ID?>? = nil,
        rowHeight: CGFloat = 32
    ) {
        self.nodes = nodes
        self.selection = selectionID
        self.rowHeight = max(rowHeight, 20)
        validateIDs()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentOutlineView<ID>(theme: context.theme)
        view.setNodes(nodes, selection: selection, rowHeight: rowHeight, context: context)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let outline = view as? FluentOutlineView<ID> else { return false }
        validateIDs()
        outline.update(nodes, selection: selection, rowHeight: rowHeight, context: context)
        return true
    }

    private func validateIDs() {
        func flatten(_ nodes: [FluentOutlineNode<ID>]) -> [ID] {
            nodes.flatMap { [$0.id] + flatten($0.children) }
        }
        let ids = flatten(nodes)
        precondition(Set(ids).count == ids.count, "Fluent outline node IDs must be unique")
    }
}

private final class FluentOutlineItem<ID: Hashable>: NSObject {
    let id: ID
    let content: FluentAnyView
    weak var parent: FluentOutlineItem<ID>?
    private(set) var children: [FluentOutlineItem<ID>] = []

    init(node: FluentOutlineNode<ID>, parent: FluentOutlineItem<ID>? = nil) {
        id = node.id
        content = node.content
        self.parent = parent
        super.init()
        children = node.children.map { FluentOutlineItem(node: $0, parent: self) }
    }
}

private final class FluentOutlineView<ID: Hashable>: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outlineView = NSOutlineView(frame: .zero)
    private var roots: [FluentOutlineItem<ID>] = []
    private var itemsByID: [ID: FluentOutlineItem<ID>] = [:]
    private var selection: FluentBinding<ID?>?
    private var observedSelection: FluentBinding<ID?>?
    private var selectionObserverID: UUID?
    private var context = FluentRenderContext()
    private var theme: FluentTheme
    private var isApplyingSelection = false

    init(theme: FluentTheme) {
        self.theme = theme
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FluentKit.Outline.Main"))
        column.title = "Outline"
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.backgroundColor = .clear
        outlineView.allowsEmptySelection = true
        outlineView.focusRingType = .none
        outlineView.setAccessibilityRole(.outline)
        outlineView.setAccessibilityLabel("Outline")
        documentView = outlineView
        setAccessibilityRole(.outline)
        setAccessibilityLabel("Outline")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setNodes(
        _ nodes: [FluentOutlineNode<ID>],
        selection: FluentBinding<ID?>?,
        rowHeight: CGFloat,
        context: FluentRenderContext
    ) {
        self.selection = selection
        self.context = context
        theme = context.theme
        outlineView.rowHeight = rowHeight
        rebuild(nodes, preservingExpansion: false)
        installSelectionObserver()
        applySelection()
    }

    func update(
        _ nodes: [FluentOutlineNode<ID>],
        selection: FluentBinding<ID?>?,
        rowHeight: CGFloat,
        context: FluentRenderContext
    ) {
        self.selection = selection
        self.context = context
        theme = context.theme
        outlineView.rowHeight = rowHeight
        rebuild(nodes, preservingExpansion: true)
        installSelectionObserver()
        applySelection()
    }

    private func rebuild(_ nodes: [FluentOutlineNode<ID>], preservingExpansion: Bool) {
        let expandedIDs = preservingExpansion ? Set(itemsByID.compactMap { id, item in
            outlineView.isItemExpanded(item) ? id : nil
        }) : []
        roots = nodes.map { FluentOutlineItem(node: $0) }
        itemsByID.removeAll(keepingCapacity: true)
        func index(_ items: [FluentOutlineItem<ID>]) {
            for item in items {
                itemsByID[item.id] = item
                index(item.children)
            }
        }
        index(roots)
        outlineView.reloadData()
        for id in expandedIDs {
            if let item = itemsByID[id] { outlineView.expandItem(item) }
        }
    }

    private func installSelectionObserver() {
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
        observedSelection = selection
        selectionObserverID = selection?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applySelection() }
        }
    }

    private func applySelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        guard let id = selection?.get(), let item = itemsByID[id] else {
            outlineView.deselectAll(nil)
            if selection?.get() != nil { selection?.set(nil) }
            return
        }
        var parent = item.parent
        while let current = parent {
            outlineView.expandItem(current)
            parent = current.parent
        }
        let row = outlineView.row(forItem: item)
        if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? FluentOutlineItem<ID>)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? FluentOutlineItem<ID>)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? FluentOutlineItem<ID> else { return false }
        return !item.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? FluentOutlineItem<ID> else { return nil }
        let reuseID = NSUserInterfaceItemIdentifier("FluentKit.Outline.Cell")
        let cell = outlineView.makeView(withIdentifier: reuseID, owner: self) as? FluentOutlineCellHost
            ?? FluentOutlineCellHost()
        cell.identifier = reuseID
        cell.update(content: item.content, context: context)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let selected: ID?
        if outlineView.selectedRow >= 0,
           let item = outlineView.item(atRow: outlineView.selectedRow) as? FluentOutlineItem<ID> {
            selected = item.id
        } else {
            selected = nil
        }
        selection?.set(selected)
        context.invalidate?()
    }

    deinit {
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
    }
}

private final class FluentOutlineCellHost: NSTableCellView {
    private var contentView: NSView?

    func update(content: FluentAnyView, context: FluentRenderContext) {
        if let contentView, content._update(contentView, in: context) { return }
        contentView?.removeFromSuperview()
        let mounted = content._mount(in: context)
        contentView = mounted
        addSubview(mounted)
        mounted.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mounted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            mounted.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            mounted.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            mounted.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }
}
