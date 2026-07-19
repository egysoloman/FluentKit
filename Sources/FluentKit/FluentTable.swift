import AppKit

/// A declarative native table column. Cell content is an ordinary Fluent view and participates in
/// compatible in-place updates when its row changes.
public struct FluentTableColumn<Row> {
    public let id: String
    public let title: String
    public let width: CGFloat?
    public let minimumWidth: CGFloat
    public let maximumWidth: CGFloat
    fileprivate let content: (Row) -> FluentAnyView

    public init<Content: FluentView>(
        _ id: String,
        title: String,
        width: CGFloat? = nil,
        minimumWidth: CGFloat = 60,
        maximumWidth: CGFloat = 1_000,
        @FluentViewBuilder content: @escaping (Row) -> Content
    ) {
        precondition(!id.isEmpty, "Fluent table column IDs must not be empty")
        precondition(minimumWidth > 0 && maximumWidth >= minimumWidth, "Invalid Fluent table column width range")
        self.id = id
        self.title = title
        self.width = width.map { min(max($0, minimumWidth), maximumWidth) }
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.content = { FluentAnyView(content($0)) }
    }
}

@resultBuilder
public enum FluentTableColumnBuilder<Row> {
    public static func buildExpression(_ column: FluentTableColumn<Row>) -> FluentTableColumn<Row> {
        column
    }

    public static func buildPartialBlock(first: FluentTableColumn<Row>) -> [FluentTableColumn<Row>] {
        [first]
    }

    public static func buildPartialBlock(
        accumulated: [FluentTableColumn<Row>],
        next: FluentTableColumn<Row>
    ) -> [FluentTableColumn<Row>] {
        accumulated + [next]
    }

    public static func buildBlock(_ columns: FluentTableColumn<Row>...) -> [FluentTableColumn<Row>] {
        columns
    }

    public static func buildOptional(_ columns: [FluentTableColumn<Row>]?) -> [FluentTableColumn<Row>] {
        columns ?? []
    }

    public static func buildEither(first columns: [FluentTableColumn<Row>]) -> [FluentTableColumn<Row>] { columns }
    public static func buildEither(second columns: [FluentTableColumn<Row>]) -> [FluentTableColumn<Row>] { columns }
    public static func buildArray(_ columns: [[FluentTableColumn<Row>]]) -> [FluentTableColumn<Row>] {
        columns.flatMap { $0 }
    }
}

/// A virtualized multi-column collection backed by `NSTableView` and its native diffable data
/// source. Stable row IDs preserve selection while the AppKit table animates insertions,
/// removals, and moves.
public struct FluentTable<Row, ID: Hashable>: FluentUpdatablePrimitiveView {
    private let rows: [Row]
    private let id: (Row) -> ID
    private let columns: [FluentTableColumn<Row>]
    private let rowHeight: CGFloat
    private let selection: FluentTableIdentityBinding?
    private let selections: FluentTableIdentitySetBinding?

    public init(
        rows: [Row],
        id: @escaping (Row) -> ID,
        rowHeight: CGFloat = 34,
        selectionID: FluentBinding<ID?>? = nil,
        @FluentTableColumnBuilder<Row> columns: () -> [FluentTableColumn<Row>]
    ) {
        self.rows = rows
        self.id = id
        self.columns = columns()
        self.rowHeight = max(rowHeight, 20)
        selection = selectionID.map(FluentTableIdentityBinding.init)
        selections = nil
        validateStructure()
    }

    public init(
        rows: [Row],
        id: @escaping (Row) -> ID,
        rowHeight: CGFloat = 34,
        selectionIDs: FluentBinding<Set<ID>>,
        @FluentTableColumnBuilder<Row> columns: () -> [FluentTableColumn<Row>]
    ) {
        self.rows = rows
        self.id = id
        self.columns = columns()
        self.rowHeight = max(rowHeight, 20)
        selection = nil
        selections = FluentTableIdentitySetBinding(selectionIDs)
        validateStructure()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentTableView<Row>(theme: context.theme)
        view.setData(
            rows: rows,
            rowIDs: rows.map { AnyHashable(id($0)) },
            columns: columns,
            rowHeight: rowHeight,
            selection: selection,
            selections: selections,
            context: context
        )
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let table = view as? FluentTableView<Row> else { return false }
        validateStructure()
        table.update(
            rows: rows,
            rowIDs: rows.map { AnyHashable(id($0)) },
            columns: columns,
            rowHeight: rowHeight,
            selection: selection,
            selections: selections,
            context: context
        )
        return true
    }

    private func validateStructure() {
        let rowIDs = rows.map(id)
        precondition(Set(rowIDs).count == rowIDs.count, "Fluent table row IDs must be unique")
        let columnIDs = columns.map(\.id)
        precondition(!columns.isEmpty, "A Fluent table needs at least one column")
        precondition(Set(columnIDs).count == columnIDs.count, "Fluent table column IDs must be unique")
    }
}

private struct FluentTableIdentityBinding {
    let get: () -> AnyHashable?
    let set: (AnyHashable?) -> Void
    let observe: ((@escaping (AnyHashable?) -> Void) -> UUID)?
    let removeObserver: ((UUID) -> Void)?

    init<ID: Hashable>(_ binding: FluentBinding<ID?>) {
        get = { binding.get().map(AnyHashable.init) }
        set = { binding.set($0.flatMap { $0.base as? ID }) }
        observe = binding.observe.map { observe in
            { observer in observe { observer($0.map(AnyHashable.init)) } }
        }
        removeObserver = binding.removeObserver
    }
}

private struct FluentTableIdentitySetBinding {
    let get: () -> Set<AnyHashable>
    let set: (Set<AnyHashable>) -> Void
    let observe: ((@escaping (Set<AnyHashable>) -> Void) -> UUID)?
    let removeObserver: ((UUID) -> Void)?

    init<ID: Hashable>(_ binding: FluentBinding<Set<ID>>) {
        get = { Set(binding.get().map(AnyHashable.init)) }
        set = { binding.set(Set($0.compactMap { $0.base as? ID })) }
        observe = binding.observe.map { observe in
            { observer in observe { observer(Set($0.map(AnyHashable.init))) } }
        }
        removeObserver = binding.removeObserver
    }
}

private final class FluentTableView<Row>: NSScrollView, NSTableViewDelegate {
    private let tableView = NSTableView(frame: .zero)
    private var rows: [Row] = []
    private var rowIDs: [AnyHashable] = []
    private var rowIndexByID: [AnyHashable: Int] = [:]
    private var columns: [FluentTableColumn<Row>] = []
    private var context = FluentRenderContext()
    private var theme: FluentTheme
    private var selection: FluentTableIdentityBinding?
    private var selections: FluentTableIdentitySetBinding?
    private var observedSelection: FluentTableIdentityBinding?
    private var observedSelections: FluentTableIdentitySetBinding?
    private var selectionObserverID: UUID?
    private var selectionsObserverID: UUID?
    private var isApplyingSelection = false

    private lazy var diffableDataSource = NSTableViewDiffableDataSource<AnyHashable, AnyHashable>(
        tableView: tableView
    ) { [weak self] tableView, tableColumn, row, identifier in
        self?.makeCell(tableView: tableView, tableColumn: tableColumn, row: row, identifier: identifier)
            ?? NSView()
    }

    init(theme: FluentTheme) {
        self.theme = theme
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true

        tableView.delegate = self
        tableView.dataSource = diffableDataSource
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = theme.controlStroke.withAlphaComponent(0.55)
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsEmptySelection = true
        tableView.setAccessibilityRole(.table)
        tableView.setAccessibilityLabel("Table")
        documentView = tableView
        setAccessibilityRole(.table)
        setAccessibilityLabel("Table")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setData(
        rows: [Row],
        rowIDs: [AnyHashable],
        columns: [FluentTableColumn<Row>],
        rowHeight: CGFloat,
        selection: FluentTableIdentityBinding?,
        selections: FluentTableIdentitySetBinding?,
        context: FluentRenderContext
    ) {
        self.rows = rows
        self.rowIDs = rowIDs
        self.columns = columns
        self.selection = selection
        self.selections = selections
        self.context = context
        theme = context.theme
        rowIndexByID = Dictionary(uniqueKeysWithValues: rowIDs.enumerated().map { ($0.element, $0.offset) })
        tableView.rowHeight = rowHeight
        tableView.allowsMultipleSelection = selections != nil
        configureColumns()
        installSelectionObservers()
        applySnapshot(animatingDifferences: false)
    }

    func update(
        rows: [Row],
        rowIDs: [AnyHashable],
        columns: [FluentTableColumn<Row>],
        rowHeight: CGFloat,
        selection: FluentTableIdentityBinding?,
        selections: FluentTableIdentitySetBinding?,
        context: FluentRenderContext
    ) {
        let structureChanged = self.rowIDs != rowIDs
        let columnsChanged = self.columns.map(\.id) != columns.map(\.id)
        self.rows = rows
        self.rowIDs = rowIDs
        self.columns = columns
        self.selection = selection
        self.selections = selections
        self.context = context
        theme = context.theme
        rowIndexByID = Dictionary(uniqueKeysWithValues: rowIDs.enumerated().map { ($0.element, $0.offset) })
        tableView.rowHeight = rowHeight
        tableView.allowsMultipleSelection = selections != nil
        tableView.gridColor = theme.controlStroke.withAlphaComponent(0.55)
        if columnsChanged { configureColumns() } else { updateColumnMetrics() }
        installSelectionObservers()
        if structureChanged {
            applySnapshot(animatingDifferences: window != nil)
        } else {
            let rowIndexes = IndexSet(integersIn: 0..<rows.count)
            let columnIndexes = IndexSet(integersIn: 0..<columns.count)
            tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
            applySelection()
        }
    }

    private func configureColumns() {
        tableView.tableColumns.forEach(tableView.removeTableColumn)
        for column in columns {
            let native = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            native.title = column.title
            native.minWidth = column.minimumWidth
            native.maxWidth = column.maximumWidth
            native.width = column.width ?? max(column.minimumWidth, 140)
            native.resizingMask = [.autoresizingMask, .userResizingMask]
            tableView.addTableColumn(native)
        }
    }

    private func updateColumnMetrics() {
        for (index, column) in columns.enumerated() where tableView.tableColumns.indices.contains(index) {
            let native = tableView.tableColumns[index]
            native.title = column.title
            native.minWidth = column.minimumWidth
            native.maxWidth = column.maximumWidth
            if let width = column.width { native.width = width }
        }
    }

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<AnyHashable, AnyHashable>()
        snapshot.appendSections([AnyHashable("FluentKit.Table.Main")])
        snapshot.appendItems(rowIDs)
        diffableDataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        applySelection()
    }

    private func makeCell(
        tableView: NSTableView,
        tableColumn: NSTableColumn?,
        row: Int,
        identifier: AnyHashable
    ) -> NSView? {
        guard let tableColumn,
              let columnIndex = columns.firstIndex(where: { $0.id == tableColumn.identifier.rawValue }),
              let rowIndex = rowIndexByID[identifier],
              rows.indices.contains(rowIndex) else { return nil }
        let reuseID = NSUserInterfaceItemIdentifier("FluentKit.Table.Cell." + tableColumn.identifier.rawValue)
        let cell = tableView.makeView(withIdentifier: reuseID, owner: self) as? FluentTableCellHost
            ?? FluentTableCellHost()
        cell.identifier = reuseID
        cell.update(content: columns[columnIndex].content(rows[rowIndex]), context: context)
        cell.setAccessibilityLabel(columns[columnIndex].title)
        cell.setAccessibilityValue(rowIndex + 1)
        return cell
    }

    private func installSelectionObservers() {
        if let selectionObserverID { observedSelection?.removeObserver?(selectionObserverID) }
        observedSelection = selection
        selectionObserverID = selection?.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applySelection() }
        }
        if let selectionsObserverID { observedSelections?.removeObserver?(selectionsObserverID) }
        observedSelections = selections
        selectionsObserverID = selections?.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applySelection() }
        }
    }

    private func applySelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        let selectedIDs: Set<AnyHashable>
        if let selections {
            selectedIDs = selections.get().intersection(rowIDs)
            if selections.get() != selectedIDs { selections.set(selectedIDs) }
        } else if let selected = selection?.get(), rowIndexByID[selected] != nil {
            selectedIDs = [selected]
        } else {
            selectedIDs = []
            if selection?.get() != nil { selection?.set(nil) }
        }
        let indexes = IndexSet(selectedIDs.compactMap { rowIndexByID[$0] })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let selectedIDs = Set(tableView.selectedRowIndexes.compactMap { index in
            rowIDs.indices.contains(index) ? rowIDs[index] : nil
        })
        if let selections {
            selections.set(selectedIDs)
        } else {
            selection?.set(selectedIDs.first)
        }
        context.invalidate?()
    }

    deinit {
        if let selectionObserverID { observedSelection?.removeObserver?(selectionObserverID) }
        if let selectionsObserverID { observedSelections?.removeObserver?(selectionsObserverID) }
    }
}

private final class FluentTableCellHost: NSTableCellView {
    private var contentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        if let contentView, content._update(contentView, in: context) { return }
        contentView?.removeFromSuperview()
        let mounted = content._mount(in: context)
        contentView = mounted
        addSubview(mounted)
        mounted.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mounted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mounted.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mounted.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            mounted.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}
