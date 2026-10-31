import AppKit

/// A stable-identity tree node whose row is composed from an ordinary Fluent view.
public struct FluentOutlineNode<ID: Hashable> {
    public let id: ID
    public let children: [FluentOutlineNode<ID>]
    /// `TreeViewNode.HasUnrealizedChildren`: shows the chevron before the children are loaded.
    /// Load them in `onExpanding` and supply them on the next update.
    public let hasUnrealizedChildren: Bool
    fileprivate let content: FluentAnyView

    public init<Content: FluentView>(
        id: ID,
        children: [FluentOutlineNode<ID>] = [],
        hasUnrealizedChildren: Bool = false,
        @FluentViewBuilder content: () -> Content
    ) {
        self.id = id
        self.children = children
        self.hasUnrealizedChildren = hasUnrealizedChildren
        self.content = FluentAnyView(content())
    }
}

/// `TreeViewSelectionMode`. Multiple selection uses tri-state check boxes: checking a node checks
/// its subtree, and a parent is checked, mixed or unchecked from its children.
public enum FluentTreeViewSelection<ID: Hashable> {
    case none
    case single(FluentBinding<ID?>?)
    case multiple(FluentBinding<Set<ID>>)
}

/// Where a dragged node was dropped: `index` is its position among `parentID`'s children (nil for
/// the roots) after it has been removed from its old place.
public struct FluentTreeViewMove<ID: Hashable> {
    public let id: ID
    public let parentID: ID?
    public let index: Int
}

/// One atomic subtree move. Remove all `ids` from their old parents, then insert them in this
/// order at `index` under `parentID` (nil means roots). Descendants of moved roots are omitted.
public struct FluentTreeViewItemsMove<ID: Hashable> {
    public let ids: [ID]
    public let parentID: ID?
    public let index: Int
}

public typealias FluentTreeView<ID: Hashable> = FluentOutline<ID>
public typealias FluentTreeViewNode<ID: Hashable> = FluentOutlineNode<ID>

/// A WinUI-style TreeView backed by `NSOutlineView`. Rows use the TreeViewItem template (32pt
/// rows with a 4,2 margin, 16pt indentation per level, a chevron column and the 3x16 accent
/// selection pill). The native host preserves expansion and selection by stable node ID while row
/// contents reconcile in place.
public struct FluentOutline<ID: Hashable>: FluentUpdatablePrimitiveView {
    private let nodes: [FluentOutlineNode<ID>]
    private let selection: FluentTreeViewSelection<ID>
    private let rowHeight: CGFloat
    private var expandedIDs: FluentBinding<Set<ID>>?
    private var onExpanding: ((ID) -> Void)?
    private var onCollapsed: ((ID) -> Void)?
    private var onItemInvoked: ((ID) -> Void)?
    private var onMove: ((FluentTreeViewMove<ID>) -> Void)?
    private var onMoveItems: ((FluentTreeViewItemsMove<ID>) -> Void)?

    public init(
        nodes: [FluentOutlineNode<ID>],
        selectionID: FluentBinding<ID?>? = nil,
        rowHeight: CGFloat = 32
    ) {
        self.init(nodes: nodes, selection: .single(selectionID), rowHeight: rowHeight)
    }

    public init(
        nodes: [FluentOutlineNode<ID>],
        selection: FluentTreeViewSelection<ID>,
        rowHeight: CGFloat = 32
    ) {
        self.nodes = nodes
        self.selection = selection
        self.rowHeight = max(rowHeight, 20)
        validateIDs()
    }

    /// Two-way expansion state by node ID. Changes after mounting raise expansion/collapse
    /// events; initial state and restoration after a data reload do not repeat those events.
    public func expandedIDs(_ binding: FluentBinding<Set<ID>>) -> Self {
        var copy = self
        copy.expandedIDs = binding
        return copy
    }

    /// `TreeView.Expanding`: runs before a node expands, the place to load unrealized children.
    public func onExpanding(_ action: @escaping (ID) -> Void) -> Self {
        var copy = self
        copy.onExpanding = action
        return copy
    }

    /// `TreeView.Collapsed`.
    public func onCollapsed(_ action: @escaping (ID) -> Void) -> Self {
        var copy = self
        copy.onCollapsed = action
        return copy
    }

    /// `TreeView.ItemInvoked`: a click, Return, or Space outside multiple selection.
    public func onItemInvoked(_ action: @escaping (ID) -> Void) -> Self {
        var copy = self
        copy.onItemInvoked = action
        return copy
    }

    /// `CanReorderItems`: enables drag-and-drop reordering. The tree is declarative, so the app
    /// applies the move to its data. This compatibility API moves the dragged row only.
    /// Use `onMoveItems` for checked-subtree moves. The last move handler modifier wins.
    public func onMove(_ action: @escaping (FluentTreeViewMove<ID>) -> Void) -> Self {
        var copy = self
        copy.onMove = action
        copy.onMoveItems = nil
        return copy
    }

    /// Moves the checked subtrees together in multiple-selection mode; with no checks, moves
    /// the dragged row. Selection order is preserved (initial Set bindings use tree order).
    /// The callback runs once, and the application applies the entire move to its data.
    public func onMoveItems(_ action: @escaping (FluentTreeViewItemsMove<ID>) -> Void) -> Self {
        var copy = self
        copy.onMoveItems = action
        copy.onMove = nil
        return copy
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentOutlineView<ID>(theme: context.theme)
        view.update(configuration, context: context, initial: true)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let outline = view as? FluentOutlineView<ID> else { return false }
        validateIDs()
        outline.update(configuration, context: context, initial: false)
        return true
    }

    private var configuration: FluentOutlineConfiguration<ID> {
        FluentOutlineConfiguration(nodes: nodes, selection: selection, rowHeight: rowHeight, expandedIDs: expandedIDs,
                                   onExpanding: onExpanding, onCollapsed: onCollapsed, onItemInvoked: onItemInvoked,
                                   onMove: onMove, onMoveItems: onMoveItems)
    }

    private func validateIDs() {
        func flatten(_ nodes: [FluentOutlineNode<ID>]) -> [ID] {
            nodes.flatMap { [$0.id] + flatten($0.children) }
        }
        let ids = flatten(nodes)
        precondition(Set(ids).count == ids.count, "Fluent outline node IDs must be unique")
    }
}

struct FluentOutlineConfiguration<ID: Hashable> {
    var nodes: [FluentOutlineNode<ID>]
    var selection: FluentTreeViewSelection<ID>
    var rowHeight: CGFloat
    var expandedIDs: FluentBinding<Set<ID>>?
    var onExpanding: ((ID) -> Void)?
    var onCollapsed: ((ID) -> Void)?
    var onItemInvoked: ((ID) -> Void)?
    var onMove: ((FluentTreeViewMove<ID>) -> Void)?
    var onMoveItems: ((FluentTreeViewItemsMove<ID>) -> Void)?
}

/// TreeViewItem template metrics (`TreeView_themeresources.xaml`, `TreeViewItem.xaml`).
enum FluentTreeViewMetrics {
    static let presenterMarginX: CGFloat = 4
    static let presenterMarginY: CGFloat = 2
    static let contentPaddingTop: CGFloat = 3
    static let contentPaddingBottom: CGFloat = 5
    static let indentation: CGFloat = 16
    static let glyphSize: CGFloat = 12
    /// `ExpandCollapseChevron` padding 14,0; 0,0,14,0 in multiple selection.
    static let chevronPadding: CGFloat = 14
    /// `MultiSelectCheckBox`: Width 32, Margin 10,0,0,0.
    static let checkBoxLeading: CGFloat = 10
    static let checkBoxWidth: CGFloat = 32
    static let indicatorSize = NSSize(width: 3, height: 16)
    static let cornerRadius: CGFloat = 4

    static func chevronFrame(depth: Int, isMultiple: Bool, rowHeight: CGFloat) -> NSRect {
        var x = presenterMarginX + CGFloat(depth) * indentation
        if isMultiple { x += checkBoxLeading + checkBoxWidth } else { x += chevronPadding }
        return NSRect(x: x, y: (rowHeight - glyphSize) / 2, width: glyphSize, height: glyphSize)
    }

    static func checkBoxFrame(depth: Int, boxSize: CGFloat, rowHeight: CGFloat) -> NSRect {
        let x = presenterMarginX + CGFloat(depth) * indentation + checkBoxLeading + (checkBoxWidth - boxSize) / 2
        return NSRect(x: x, y: (rowHeight - boxSize) / 2, width: boxSize, height: boxSize)
    }

    static func contentLeading(depth: Int, isMultiple: Bool) -> CGFloat {
        chevronFrame(depth: depth, isMultiple: isMultiple, rowHeight: 0).maxX + chevronPadding
    }
}

enum FluentTreeCheckState: Equatable {
    case unchecked
    case checked
    case mixed
}

private final class FluentOutlineItem<ID: Hashable>: NSObject {
    let id: ID
    var content: FluentAnyView
    var hasUnrealizedChildren: Bool
    weak var parent: FluentOutlineItem<ID>?
    var children: [FluentOutlineItem<ID>] = []

    init(node: FluentOutlineNode<ID>, parent: FluentOutlineItem<ID>? = nil) {
        id = node.id
        content = node.content
        hasUnrealizedChildren = node.hasUnrealizedChildren
        self.parent = parent
        super.init()
    }

    var isExpandable: Bool { !children.isEmpty || hasUnrealizedChildren }

    var depth: Int {
        var depth = 0
        var current = parent
        while let next = current {
            depth += 1
            current = next.parent
        }
        return depth
    }

    func isDescendant(of other: FluentOutlineItem<ID>) -> Bool {
        var current = parent
        while let next = current {
            if next === other { return true }
            current = next.parent
        }
        return false
    }

    var subtree: [FluentOutlineItem<ID>] { [self] + children.flatMap(\.subtree) }
}

/// The outline view draws no native disclosure triangle or indentation; the cell lays both out.
final class FluentTreeNativeOutlineView: NSOutlineView {
    var keyHandler: ((NSEvent) -> Bool)?
    private weak var pressedCheckBox: FluentOutlineCellHost?
    private var pressedItem: AnyObject?
    private weak var pressWindow: NSWindow?
    private var consumesAccessoryMouse = false
    private var resignWindowObserver: NSObjectProtocol?

    deinit {
        if let resignWindowObserver { NotificationCenter.default.removeObserver(resignWindowObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelAccessoryPress()
        if let resignWindowObserver { NotificationCenter.default.removeObserver(resignWindowObserver) }
        resignWindowObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.cancelAccessoryPress()
            }
        }
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        return NSRect(x: 0, y: frame.minY, width: bounds.width, height: frame.height)
    }

    override func keyDown(with event: NSEvent) {
        if consumesAccessoryMouse {
            cancelAccessoryPress()
            if event.keyCode == 53 { return }
        }
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if consumesAccessoryMouse { cancelAccessoryPress() }
        else { super.cancelOperation(sender) }
    }

    override func mouseDown(with event: NSEvent) {
        if handleAccessoryMouseDown(event) { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if handleAccessoryMouseDragged(event) { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if handleAccessoryMouseUp(event) { return }
        super.mouseUp(with: event)
    }

    /// NSOutlineView consumes row mouse events before plain NSView cell hosts receive them.
    /// Route our drawn accessories here, while leaving row content and native dragging to AppKit.
    func handleAccessoryMouseDown(_ event: NSEvent) -> Bool {
        cancelAccessoryPress()
        consumesAccessoryMouse = false
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0, let cell = view(atColumn: 0, row: row, makeIfNecessary: true) as? FluentOutlineCellHost else { return false }
        let local = cell.convert(point, from: self)
        guard let accessory = cell.accessory(at: local) else { return false }
        consumesAccessoryMouse = true
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        switch accessory {
        case .checkBox:
            pressedCheckBox = cell
            pressedItem = item(atRow: row) as AnyObject?
            pressWindow = window
            cell.beginCheckBoxPress()
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        case .chevron:
            // WinUI's chevron handles PointerPressed; CheckBox uses ButtonBase's Release mode.
            cell.performChevronClick()
        }
        return true
    }

    func handleAccessoryMouseDragged(_ event: NSEvent) -> Bool {
        guard consumesAccessoryMouse else { return false }
        if let cell = validPressedCheckBox {
            cell.updateCheckBoxPointer(at: cell.convert(event.locationInWindow, from: nil))
        } else { cancelAccessoryPress() }
        return true
    }

    func handleAccessoryMouseUp(_ event: NSEvent) -> Bool {
        guard consumesAccessoryMouse else { return false }
        let cell = validPressedCheckBox
        let commit = cell.map { $0.checkBoxHitFrame.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
        cancelAccessoryPress()
        consumesAccessoryMouse = false
        if let cell {
            cell.updateCheckBoxPointer(at: cell.convert(event.locationInWindow, from: nil))
            if commit { cell.performCheckBoxClick() }
        }
        return true
    }

    private var validPressedCheckBox: FluentOutlineCellHost? {
        guard let cell = pressedCheckBox, let item = pressedItem, cell.isTrackingCheckBox,
              cell.representedItem == ObjectIdentifier(item), cell.window === window, window === pressWindow,
              cell.layoutState?.isMultiple == true, !cell.isHiddenOrHasHiddenAncestor else { return nil }
        let row = row(forItem: item)
        guard row >= 0, view(atColumn: 0, row: row, makeIfNecessary: false) === cell else { return nil }
        return cell
    }

    private func cancelAccessoryPress() {
        pressedCheckBox?.cancelCheckBoxPress()
        pressedCheckBox = nil
        pressedItem = nil
        pressWindow = nil
    }
}

final class FluentOutlineView<ID: Hashable>: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let outlineView = FluentTreeNativeOutlineView(frame: .zero)
    private var roots: [FluentOutlineItem<ID>] = []
    private var itemsByID: [ID: FluentOutlineItem<ID>] = [:]
    private var configuration: FluentOutlineConfiguration<ID>?
    private var observedSingle: FluentBinding<ID?>?
    private var observedMultiple: FluentBinding<Set<ID>>?
    private var observedExpansion: FluentBinding<Set<ID>>?
    private var selectionObserverID: UUID?
    private var expansionObserverID: UUID?
    private var observerGeneration = 0
    private var context = FluentRenderContext()
    private var theme: FluentTheme
    private var isApplyingSelection = false
    private var isApplyingExpansion = false
    private var isRestoringExpansion = false
    /// Multiple selection: the IDs whose check box is fully checked.
    private(set) var checkedIDs: Set<ID> = []
    private var checkedOrder: [ID] = []
    private static var dragType: NSPasteboard.PasteboardType { NSPasteboard.PasteboardType("com.fluentkit.treeview.node") }
    private var draggedItems: [FluentOutlineItem<ID>] = []
    private var isBatchDrag = false
    private var topologyGeneration = 0
    private var validatedDrop: (generation: Int, parent: ObjectIdentifier?, index: Int)?

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
        outlineView.indentationPerLevel = 0
        outlineView.intercellSpacing = .zero
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .plain
        outlineView.autoresizesOutlineColumn = false
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.setAccessibilityRole(.outline)
        outlineView.fluentSetDefaultAccessibilityLabel("Outline")
        outlineView.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.registerForDraggedTypes([Self.dragType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.draggingDestinationFeedbackStyle = .regular
        documentView = outlineView
        setAccessibilityRole(.outline)
        fluentSetDefaultAccessibilityLabel("Outline")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeObservers() }

    var isMultiple: Bool {
        if case .multiple = configuration?.selection { return true }
        return false
    }

    private var isSelectionEnabled: Bool {
        if case .some(.none) = configuration?.selection { return false }
        return true
    }

    private var isRightToLeft: Bool { context.layoutDirection.appKitValue == .rightToLeft }

    func update(_ next: FluentOutlineConfiguration<ID>, context: FluentRenderContext, initial: Bool) {
        let wasRestoringExpansion = isRestoringExpansion
        isRestoringExpansion = wasRestoringExpansion || initial
        defer { isRestoringExpansion = wasRestoringExpansion }
        configuration = next
        self.context = context
        theme = context.theme
        outlineView.rowHeight = next.rowHeight
        outlineView.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        outlineView.allowsMultipleSelection = false
        rebuild(next.nodes, preservingExpansion: !initial)
        installObservers()
        applyExpansion()
        applySelection()
        refreshVisibleRows()
    }

    private func rebuild(_ nodes: [FluentOutlineNode<ID>], preservingExpansion: Bool) {
        let expanded = preservingExpansion ? expandedIDsInView() : []
        let selectedID = outlineView.selectedRow >= 0
            ? (outlineView.item(atRow: outlineView.selectedRow) as? FluentOutlineItem<ID>)?.id : nil
        let previousItems = itemsByID
        var nextItems: [ID: FluentOutlineItem<ID>] = [:]
        var structureChanged = roots.map(\.id) != nodes.map(\.id)
        func reconcile(_ node: FluentOutlineNode<ID>, parent: FluentOutlineItem<ID>?) -> FluentOutlineItem<ID> {
            let item: FluentOutlineItem<ID>
            if let existing = previousItems[node.id] {
                item = existing
                if item.children.map(\.id) != node.children.map(\.id)
                    || item.hasUnrealizedChildren != node.hasUnrealizedChildren { structureChanged = true }
                item.content = node.content
                item.hasUnrealizedChildren = node.hasUnrealizedChildren
                item.parent = parent
            } else {
                item = FluentOutlineItem(node: node, parent: parent)
                structureChanged = true
            }
            nextItems[item.id] = item
            item.children = node.children.map { reconcile($0, parent: item) }
            return item
        }
        roots = nodes.map { reconcile($0, parent: nil) }
        itemsByID = nextItems
        // Content and theme updates reconcile visible cells in place. Reload only when the tree
        // topology changes; otherwise NSOutlineView discards otherwise stable native rows.
        guard structureChanged else { return }
        // Hover expansion may load children during a drag. Keep the session, but require a new
        // native validation before accepting an insertion index from the changed topology.
        topologyGeneration += 1
        validatedDrop = nil
        let wasApplyingSelection = isApplyingSelection
        let wasApplyingExpansion = isApplyingExpansion
        let wasRestoringExpansion = isRestoringExpansion
        isApplyingSelection = true
        isApplyingExpansion = true
        isRestoringExpansion = true
        defer {
            isApplyingSelection = wasApplyingSelection
            isApplyingExpansion = wasApplyingExpansion
            isRestoringExpansion = wasRestoringExpansion
        }
        outlineView.reloadData()
        expand(expanded)
        if let selectedID, let item = itemsByID[selectedID] {
            let row = outlineView.row(forItem: item)
            if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
    }

    private func expandedIDsInView() -> Set<ID> {
        Set(itemsByID.compactMap { id, item in outlineView.isItemExpanded(item) ? id : nil })
    }

    /// Expands outer nodes first so inner ones have rows to expand into.
    private func expand(_ ids: Set<ID>) {
        let items = ids.compactMap { itemsByID[$0] }.sorted { $0.depth < $1.depth }
        for item in items { outlineView.expandItem(item) }
    }

    private func removeObservers() {
        if let selectionObserverID {
            observedSingle?.removeObserver(selectionObserverID)
            observedMultiple?.removeObserver(selectionObserverID)
        }
        if let expansionObserverID { observedExpansion?.removeObserver(expansionObserverID) }
        selectionObserverID = nil
        expansionObserverID = nil
    }

    private func installObservers() {
        removeObservers()
        observerGeneration += 1
        let generation = observerGeneration
        observedSingle = nil
        observedMultiple = nil
        switch configuration?.selection {
        case let .single(binding?):
            observedSingle = binding
            selectionObserverID = binding.observe { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.observerGeneration == generation else { return }
                    self.applySelection()
                }
            }
        case let .multiple(binding):
            observedMultiple = binding
            selectionObserverID = binding.observe { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.observerGeneration == generation else { return }
                    self.applySelection()
                    self.refreshVisibleRows()
                }
            }
        default:
            break
        }
        observedExpansion = configuration?.expandedIDs
        expansionObserverID = observedExpansion?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observerGeneration == generation else { return }
                self.applyExpansion()
            }
        }
    }

    private func applyExpansion() {
        guard let wanted = configuration?.expandedIDs?.get() else { return }
        let wasApplyingExpansion = isApplyingExpansion
        isApplyingExpansion = true
        defer { isApplyingExpansion = wasApplyingExpansion }
        let current = expandedIDsInView()
        for id in current.subtracting(wanted) {
            if let item = itemsByID[id] { outlineView.collapseItem(item) }
        }
        expand(wanted.subtracting(current))
    }

    private func applySelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        switch configuration?.selection {
        case let .single(binding):
            checkedIDs = []; checkedOrder = []
            guard let binding else { return }
            guard let id = binding.get(), let item = itemsByID[id] else {
                outlineView.deselectAll(nil)
                if binding.get() != nil { binding.set(nil) }
                return
            }
            reveal(item)
            let row = outlineView.row(forItem: item)
            if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        case let .multiple(binding):
            let raw = binding.get()
            let normalized = normalizedChecks(raw)
            updateChecks(normalized)
            if normalized != raw {
                let generation = observerGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.observerGeneration == generation, binding.get() == raw else { return }
                    binding.set(normalized)
                }
            }
        case .some(.none), nil:
            checkedIDs = []; checkedOrder = []
            outlineView.deselectAll(nil)
        }
    }

    private func reveal(_ item: FluentOutlineItem<ID>) {
        var ancestors: [FluentOutlineItem<ID>] = []
        var parent = item.parent
        while let current = parent {
            ancestors.insert(current, at: 0)
            parent = current.parent
        }
        for ancestor in ancestors { outlineView.expandItem(ancestor) }
    }

    // MARK: Multiple selection

    private func updateChecks(_ next: Set<ID>) {
        checkedOrder.removeAll { !next.contains($0) }
        let existing = Set(checkedOrder)
        checkedOrder += roots.flatMap(\.subtree).map(\.id).filter { next.contains($0) && !existing.contains($0) }
        checkedIDs = next
    }

    /// `ViewModel::UpdateSelection`: a checked node checks its subtree, and each parent with
    /// children is checked only when every child is.
    private func normalizedChecks(_ ids: Set<ID>) -> Set<ID> {
        var result = Set<ID>()
        for id in ids {
            guard let item = itemsByID[id] else { continue }
            result.formUnion(item.subtree.map(\.id))
        }
        func settle(_ item: FluentOutlineItem<ID>) {
            guard !item.children.isEmpty else { return }
            item.children.forEach(settle)
            if item.children.allSatisfy({ result.contains($0.id) }) { result.insert(item.id) } else { result.remove(item.id) }
        }
        roots.forEach(settle)
        return result
    }

    func checkState(of id: ID) -> FluentTreeCheckState {
        guard let item = itemsByID[id] else { return .unchecked }
        return checkState(of: item)
    }

    private func checkState(of item: FluentOutlineItem<ID>) -> FluentTreeCheckState {
        if checkedIDs.contains(item.id) { return .checked }
        guard !item.children.isEmpty else { return .unchecked }
        return item.subtree.dropFirst().contains { checkedIDs.contains($0.id) } ? .mixed : .unchecked
    }

    /// `TreeViewItem::ToggleSelection`: mixed and unchecked nodes become checked.
    func toggleCheck(_ id: ID) {
        guard case let .multiple(binding) = configuration?.selection, let item = itemsByID[id] else { return }
        var next = checkedIDs
        let subtree = Set(item.subtree.map(\.id))
        if checkState(of: item) == .checked {
            next.subtract(subtree)
            var parent = item.parent
            while let current = parent {
                next.remove(current.id)
                parent = current.parent
            }
        } else {
            next.formUnion(subtree)
        }
        updateChecks(normalizedChecks(next))
        refreshVisibleRows()
        binding.set(checkedIDs)
        context.invalidate?()
    }

    // MARK: Expansion

    func toggleExpansion(_ id: ID) {
        guard let item = itemsByID[id], item.isExpandable else { return }
        if outlineView.isItemExpanded(item) {
            outlineView.collapseItem(item)
        } else {
            outlineView.expandItem(item)
        }
    }

    func isExpanded(_ id: ID) -> Bool {
        itemsByID[id].map { outlineView.isItemExpanded($0) } ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        // AppKit also asks this when accessibility clients query whether disclosure is allowed.
        // Eligibility must not load children or emit an expansion event.
        guard let item = item as? FluentOutlineItem<ID> else { return false }
        return itemsByID[item.id] === item && item.isExpandable
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard !isRestoringExpansion, notification.object as? NSOutlineView === outlineView,
              let item = notification.userInfo?["NSObject"] as? FluentOutlineItem<ID>,
              itemsByID[item.id] === item else { return }
        configuration?.onExpanding?(item.id)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        expansionDidChange(notification, collapsed: false)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        expansionDidChange(notification, collapsed: true)
    }

    private func expansionDidChange(_ notification: Notification, collapsed: Bool) {
        guard let item = notification.userInfo?["NSObject"] as? FluentOutlineItem<ID> else { return }
        refresh(item)
        if !isApplyingExpansion, let binding = configuration?.expandedIDs {
            var next = binding.get()
            if collapsed { next.remove(item.id) } else { next.insert(item.id) }
            if next != binding.get() { binding.set(next) }
        }
        // Publish the collapsed state before application code runs. A callback may reopen the
        // node, and its new binding value must not be overwritten by this completed transition.
        if collapsed && !isRestoringExpansion { configuration?.onCollapsed?(item.id) }
        if !isApplyingExpansion { context.invalidate?() }
    }

    // MARK: Input

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FluentOutlineItem<ID> else { return }
        invoke(item)
    }

    private func invoke(_ item: FluentOutlineItem<ID>) {
        configuration?.onItemInvoked?(item.id)
    }

    /// `TreeViewItem::OnKeyDown` and `HandleExpandCollapse`.
    func handleKey(_ event: NSEvent) -> Bool {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FluentOutlineItem<ID> else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.subtracting([.numericPad, .function]).isEmpty else { return false }
        let collapseKey: UInt16 = isRightToLeft ? 124 : 123
        let expandKey: UInt16 = isRightToLeft ? 123 : 124
        switch event.keyCode {
        case collapseKey:
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else if let parent = item.parent {
                select(parent)
            }
            return true
        case expandKey:
            if !outlineView.isItemExpanded(item), item.isExpandable {
                outlineView.expandItem(item)
            } else if let child = item.children.first {
                select(child)
            }
            return true
        case 49 where isMultiple:
            toggleCheck(item.id)
            return true
        case 36, 76, 49:
            invoke(item)
            return true
        default:
            return false
        }
    }

    private func select(_ item: FluentOutlineItem<ID>) {
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? FluentOutlineItem<ID>)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? FluentOutlineItem<ID>)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FluentOutlineItem<ID>)?.isExpandable ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let reuseID = NSUserInterfaceItemIdentifier("FluentKit.TreeView.Row")
        let row = outlineView.makeView(withIdentifier: reuseID, owner: self) as? FluentTreeRowView ?? FluentTreeRowView()
        row.identifier = reuseID
        return row
    }

    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let item = outlineView.item(atRow: row) as? FluentOutlineItem<ID> else { return }
        configureRow(rowView as? FluentTreeRowView, item: item)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? FluentOutlineItem<ID> else { return nil }
        let reuseID = NSUserInterfaceItemIdentifier("FluentKit.Outline.Cell")
        let cell = outlineView.makeView(withIdentifier: reuseID, owner: self) as? FluentOutlineCellHost
            ?? FluentOutlineCellHost()
        cell.identifier = reuseID
        configureCell(cell, item: item)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        isSelectionEnabled || isMultiple
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshVisibleRows()
        guard !isApplyingSelection, case let .single(binding) = configuration?.selection else { return }
        let selected: ID?
        if outlineView.selectedRow >= 0,
           let item = outlineView.item(atRow: outlineView.selectedRow) as? FluentOutlineItem<ID> {
            selected = item.id
        } else {
            selected = nil
        }
        binding?.set(selected)
        context.invalidate?()
    }

    // MARK: Drag reorder

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard canMove, let item = item as? FluentOutlineItem<ID> else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(outlineView.row(forItem: item)), forType: Self.dragType)
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                     forItems draggedItems: [Any]) {
        guard let item = draggedItems.first as? FluentOutlineItem<ID> else { return }
        beginDragging(item.id)
        guard isBatchDrag, isMultiple, checkedIDs.count > 1 else { return }
        let badge = Self.dragCountImage(checkedIDs.count, theme: theme)
        let row = outlineView.row(forItem: item)
        guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FluentOutlineCellHost else { return }
        let box = cell.checkBoxFrame
        session.enumerateDraggingItems(options: [], for: outlineView, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragging, index, _ in
            guard index == 0, let components = dragging.imageComponents else { return }
            let overlay = NSDraggingImageComponent(key: .init("FluentKit.TreeView.Count"))
            overlay.contents = badge
            overlay.frame = NSRect(x: box.midX - badge.size.width / 2, y: box.midY - badge.size.height / 2,
                                   width: badge.size.width, height: badge.size.height)
            dragging.imageComponentsProvider = { components + [overlay] }
        }
    }

    static func dragCountImage(_ count: Int, theme: FluentTheme) -> NSImage {
        let label = NSAttributedString(string: String(count), attributes: [.font: theme.typography.font(for: .caption),
                                                                          .foregroundColor: NSColor.white])
        let size = NSSize(width: max(20, ceil(label.size().width) + 8), height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            theme.accent.setFill(); path.fill()
            NSColor.white.setStroke(); path.lineWidth = 1; path.stroke()
            label.draw(at: NSPoint(x: (size.width - label.size().width) / 2, y: (size.height - label.size().height) / 2))
            return true
        }
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                     operation: NSDragOperation) {
        draggedItems = []
        validatedDrop = nil
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        validatedDrop = nil
        guard info.draggingSource as? NSOutlineView === outlineView,
              dropPlan(to: item, proposedIndex: index) != nil else { return [] }
        validatedDrop = (topologyGeneration, (item as? FluentOutlineItem<ID>).map(ObjectIdentifier.init), index)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard info.draggingSource as? NSOutlineView === outlineView, let validated = validatedDrop,
              validated.generation == topologyGeneration, validated.index == index,
              validated.parent == (item as? FluentOutlineItem<ID>).map(ObjectIdentifier.init) else { return false }
        return acceptMove(to: item, proposedIndex: index)
    }

    private var canMove: Bool { configuration?.onMove != nil || configuration?.onMoveItems != nil }

    @discardableResult
    func beginDragging(_ id: ID) -> [ID] {
        draggedItems = []
        validatedDrop = nil
        guard canMove, let anchor = itemsByID[id] else { return [] }
        if case let .multiple(binding) = configuration?.selection { updateChecks(normalizedChecks(binding.get())) }
        isBatchDrag = configuration?.onMoveItems != nil
        if isBatchDrag, isMultiple, !checkedIDs.isEmpty {
            var seen = Set<ID>()
            for id in checkedOrder {
                guard var item = itemsByID[id] else { continue }
                while let parent = item.parent, checkedIDs.contains(parent.id) { item = parent }
                if seen.insert(item.id).inserted { draggedItems.append(item) }
            }
        } else {
            draggedItems = [anchor]
        }
        return draggedItems.map(\.id)
    }

    private func dropPlan(to item: Any?, proposedIndex: Int) -> FluentTreeViewItemsMove<ID>? {
        guard canMove, !draggedItems.isEmpty, isBatchDrag == (configuration?.onMoveItems != nil),
              draggedItems.allSatisfy({ itemsByID[$0.id] === $0 }) else { return nil }
        let rootIDs = Set(draggedItems.map(\.id))
        for item in draggedItems {
            var ancestor = item.parent
            while let current = ancestor {
                if rootIDs.contains(current.id) { return nil }
                ancestor = current.parent
            }
        }
        let parent = item as? FluentOutlineItem<ID>
        if item != nil, parent == nil { return nil }
        if let parent, itemsByID[parent.id] !== parent { return nil }
        return Self.move(draggedItems, toParent: parent, proposedIndex: proposedIndex, roots: roots)
    }

    @discardableResult
    func acceptMove(to item: Any?, proposedIndex: Int) -> Bool {
        guard let move = dropPlan(to: item, proposedIndex: proposedIndex) else { return false }
        let batch = isBatchDrag
        draggedItems = [] // Clear before application code can reenter or rebuild this tree.
        validatedDrop = nil
        if batch { configuration?.onMoveItems?(move) }
        else { configuration?.onMove?(FluentTreeViewMove(id: move.ids[0], parentID: move.parentID, index: move.index)) }
        context.invalidate?()
        return true
    }

    /// Converts AppKit's proposed index (before removal; -1 for "onto the item") into the index
    /// after all moved roots have left their old places. Validation and acceptance share this plan.
    private static func move(_ dragged: [FluentOutlineItem<ID>], toParent parent: FluentOutlineItem<ID>?, proposedIndex: Int,
                             roots: [FluentOutlineItem<ID>]) -> FluentTreeViewItemsMove<ID>? {
        guard !dragged.isEmpty else { return nil }
        if let parent, dragged.contains(where: { parent === $0 || parent.isDescendant(of: $0) }) { return nil }
        let siblings = parent?.children ?? roots
        let proposed = proposedIndex == NSOutlineViewDropOnItemIndex ? siblings.count : proposedIndex
        guard (0...siblings.count).contains(proposed) else { return nil }
        let ids = Set(dragged.map(\.id))
        let index = proposed - siblings.prefix(proposed).filter { ids.contains($0.id) }.count
        var remaining = siblings.filter { !ids.contains($0.id) }.map(\.id)
        remaining.insert(contentsOf: dragged.map(\.id), at: index)
        if remaining == siblings.map(\.id) { return nil }
        return FluentTreeViewItemsMove(ids: dragged.map(\.id), parentID: parent?.id, index: index)
    }

    func simulateMove(_ id: ID, toParent parentID: ID?, proposedIndex: Int) -> FluentTreeViewMove<ID>? {
        guard let dragged = itemsByID[id] else { return nil }
        if let parentID, itemsByID[parentID] == nil { return nil }
        guard let move = Self.move([dragged], toParent: parentID.flatMap { itemsByID[$0] }, proposedIndex: proposedIndex, roots: roots) else { return nil }
        return FluentTreeViewMove(id: id, parentID: move.parentID, index: move.index)
    }

    // MARK: Row visuals

    private func refreshVisibleRows() {
        let range = outlineView.rows(in: outlineView.visibleRect)
        guard range.length > 0 else { return }
        for row in range.location..<(range.location + range.length) { refresh(row: row) }
    }

    private func refresh(_ item: FluentOutlineItem<ID>) {
        let row = outlineView.row(forItem: item)
        if row >= 0 { refresh(row: row) }
    }

    private func refresh(row: Int) {
        guard let item = outlineView.item(atRow: row) as? FluentOutlineItem<ID> else { return }
        configureRow(outlineView.rowView(atRow: row, makeIfNecessary: false) as? FluentTreeRowView, item: item)
        if let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FluentOutlineCellHost {
            configureCell(cell, item: item)
        }
    }

    private func configureRow(_ row: FluentTreeRowView?, item: FluentOutlineItem<ID>) {
        guard let row else { return }
        let checked = isMultiple && checkState(of: item) == .checked
        row.configure(theme: theme, isMultiple: isMultiple, isChecked: checked, isRightToLeft: isRightToLeft,
                      reduceMotion: context.reduceMotion)
    }

    private func configureCell(_ cell: FluentOutlineCellHost, item: FluentOutlineItem<ID>) {
        let id = item.id
        cell.update(
            representedItem: ObjectIdentifier(item),
            content: item.content,
            context: context,
            layout: FluentOutlineCellHost.Layout(
                depth: item.depth,
                isMultiple: isMultiple,
                isExpandable: item.isExpandable,
                isExpanded: outlineView.isItemExpanded(item),
                checkState: isMultiple ? checkState(of: item) : nil,
                rowHeight: outlineView.rowHeight,
                isRightToLeft: isRightToLeft
            ),
            onToggleExpansion: { [weak self] in self?.toggleExpansion(id) },
            onToggleCheck: { [weak self] in self?.toggleCheck(id) }
        )
    }
}

/// TreeViewItem's `ContentPresenterGrid`: a rounded fill inset 4,2 and the selection pill.
final class FluentTreeRowView: NSTableRowView {
    override var isFlipped: Bool { true }
    let fillLayer = CALayer()
    let indicatorLayer = CALayer()
    private var theme = FluentTheme.current
    private var isMultiple = false
    private var isChecked = false
    private var isRightToLeft = false
    private var isPointerOver = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fillLayer.cornerRadius = FluentTreeViewMetrics.cornerRadius
        indicatorLayer.cornerRadius = 1.5
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(indicatorLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: FluentTheme, isMultiple: Bool, isChecked: Bool, isRightToLeft: Bool, reduceMotion: Bool) {
        self.theme = theme
        self.isMultiple = isMultiple
        self.isChecked = isChecked
        self.isRightToLeft = isRightToLeft
        applyAppearance()
    }

    override var isSelected: Bool {
        didSet { applyAppearance() }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        applyAppearance()
    }

    /// Whether the row shows the TreeViewItem "Selected" visual state.
    var showsSelected: Bool { isMultiple ? isChecked : isSelected }

    func applyAppearance() {
        let selected = showsSelected
        let fill: NSColor = switch (selected, isPointerOver) {
        case (true, true): theme.subtleFillTertiary
        case (true, false): theme.subtleFillSecondary
        case (false, true): theme.subtleFillSecondary
        case (false, false): .clear
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.backgroundColor = fill.cgColor
        if theme.isHighContrast, selected {
            fillLayer.borderColor = theme.textPrimary.cgColor
            fillLayer.borderWidth = 1
        } else {
            fillLayer.borderWidth = 0
        }
        indicatorLayer.backgroundColor = theme.accentFillDefault.cgColor
        // Multiple selection shows the check box instead of the pill.
        indicatorLayer.opacity = selected && !isMultiple ? 1 : 0
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let inset = bounds.insetBy(dx: FluentTreeViewMetrics.presenterMarginX, dy: FluentTreeViewMetrics.presenterMarginY)
        fillLayer.frame = inset
        let size = FluentTreeViewMetrics.indicatorSize
        let x = isRightToLeft ? inset.maxX - size.width : inset.minX
        indicatorLayer.frame = NSRect(x: x, y: inset.midY - size.height / 2, width: size.width, height: size.height)
        CATransaction.commit()
    }
}

final class FluentOutlineCellHost: NSTableCellView {
    enum Accessory { case checkBox, chevron }
    struct Layout: Equatable {
        var depth: Int
        var isMultiple: Bool
        var isExpandable: Bool
        var isExpanded: Bool
        var checkState: FluentTreeCheckState?
        var rowHeight: CGFloat
        var isRightToLeft: Bool
    }

    override var isFlipped: Bool { true }
    private(set) var contentView: NSView?
    let chevronLayer = FluentChevronPrimitiveLayer()
    let checkBoxBackgroundLayer = CALayer()
    let checkBoxLayer = CALayer()
    let checkMarkLayer = CAShapeLayer()
    private(set) var layoutState: Layout?
    private(set) var representedItem: ObjectIdentifier?
    private(set) var isTrackingCheckBox = false
    private var isCheckBoxPointerOver = false
    private var pointerTrackingArea: NSTrackingArea?
    private var theme = FluentTheme.current
    private var reduceMotion = false
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var rtlLeadingConstraint: NSLayoutConstraint?
    private var rtlTrailingConstraint: NSLayoutConstraint?
    private var onToggleExpansion: (() -> Void)?
    private var onToggleCheck: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(chevronLayer)
        checkBoxBackgroundLayer.name = "FluentKit.TreeView.CheckBoxBackground"
        layer?.addSublayer(checkBoxBackgroundLayer)
        checkBoxLayer.addSublayer(checkMarkLayer)
        checkMarkLayer.fillColor = nil
        checkMarkLayer.lineCap = .round
        checkMarkLayer.lineJoin = .round
        layer?.addSublayer(checkBoxLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(representedItem: ObjectIdentifier, content: FluentAnyView, context: FluentRenderContext, layout: Layout,
                onToggleExpansion: @escaping () -> Void, onToggleCheck: @escaping () -> Void) {
        if self.representedItem != representedItem || !layout.isMultiple { cancelCheckBoxPress() }
        self.representedItem = representedItem
        let wasExpanded = layoutState?.isExpanded
        layoutState = layout
        theme = context.theme
        reduceMotion = context.reduceMotion
        self.onToggleExpansion = onToggleExpansion
        self.onToggleCheck = onToggleCheck
        mount(content, context: context)
        let leading = FluentTreeViewMetrics.contentLeading(depth: layout.depth, isMultiple: layout.isMultiple)
        // The content column sits inside the 4pt presenter margin on both sides.
        leadingConstraint?.constant = leading
        trailingConstraint?.constant = -FluentTreeViewMetrics.presenterMarginX
        rtlLeadingConstraint?.constant = FluentTreeViewMetrics.presenterMarginX
        rtlTrailingConstraint?.constant = -leading
        let ltr = [leadingConstraint, trailingConstraint].compactMap { $0 }
        let rtl = [rtlLeadingConstraint, rtlTrailingConstraint].compactMap { $0 }
        NSLayoutConstraint.deactivate(layout.isRightToLeft ? ltr : rtl)
        NSLayoutConstraint.activate(layout.isRightToLeft ? rtl : ltr)
        needsLayout = true
        applyLayers(animated: wasExpanded != nil && wasExpanded != layout.isExpanded && !reduceMotion)
        if let state = layout.checkState {
            setAccessibilityValue(state == .checked ? 1 : (state == .mixed ? 2 : 0))
        }
    }

    private func mount(_ content: FluentAnyView, context: FluentRenderContext) {
        if let contentView, content._update(contentView, in: context) { return }
        contentView?.removeFromSuperview()
        let mounted = content._mount(in: context)
        contentView = mounted
        addSubview(mounted)
        mounted.translatesAutoresizingMaskIntoConstraints = false
        // Use physical anchors: the tree explicitly mirrors its chevron/indentation metrics.
        // RTL needs a trailing equality, not a leading equality plus a trailing upper bound.
        leadingConstraint = mounted.leftAnchor.constraint(equalTo: leftAnchor)
        trailingConstraint = mounted.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor)
        rtlLeadingConstraint = mounted.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor)
        rtlTrailingConstraint = mounted.rightAnchor.constraint(equalTo: rightAnchor)
        NSLayoutConstraint.activate([
            mounted.topAnchor.constraint(greaterThanOrEqualTo: topAnchor,
                                         constant: FluentTreeViewMetrics.presenterMarginY + FluentTreeViewMetrics.contentPaddingTop),
            mounted.centerYAnchor.constraint(equalTo: centerYAnchor,
                                             constant: (FluentTreeViewMetrics.contentPaddingTop - FluentTreeViewMetrics.contentPaddingBottom) / 2)
        ])
    }

    private func mirrored(_ rect: NSRect) -> NSRect {
        guard layoutState?.isRightToLeft == true else { return rect }
        return NSRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var chevronFrame: NSRect {
        guard let layoutState else { return .zero }
        return mirrored(FluentTreeViewMetrics.chevronFrame(depth: layoutState.depth, isMultiple: layoutState.isMultiple,
                                                           rowHeight: bounds.height))
    }

    var checkBoxFrame: NSRect {
        guard let layoutState, layoutState.isMultiple else { return .zero }
        let size = checkBoxAppearance(checked: false).boxSize
        return mirrored(FluentTreeViewMetrics.checkBoxFrame(depth: layoutState.depth, boxSize: size, rowHeight: bounds.height))
    }

    var chevronHitFrame: NSRect {
        guard let layoutState, layoutState.isExpandable else { return .zero }
        let glyph = FluentTreeViewMetrics.chevronFrame(depth: layoutState.depth, isMultiple: layoutState.isMultiple, rowHeight: bounds.height)
        let leading = layoutState.isMultiple ? 0 : FluentTreeViewMetrics.chevronPadding
        return mirrored(NSRect(x: glyph.minX - leading, y: FluentTreeViewMetrics.presenterMarginY,
            width: glyph.width + leading + FluentTreeViewMetrics.chevronPadding,
            height: max(0, bounds.height - 2 * FluentTreeViewMetrics.presenterMarginY))).intersection(bounds)
    }

    var checkBoxHitFrame: NSRect {
        guard let layoutState, layoutState.isMultiple else { return .zero }
        // The 32pt checkbox column is centered in the presenter, with MinHeight 28.
        let box = FluentTreeViewMetrics.checkBoxFrame(depth: layoutState.depth, boxSize: FluentTreeViewMetrics.checkBoxWidth, rowHeight: bounds.height)
        let height = min(max(28, checkBoxAppearance(checked: false).boxSize), max(0, bounds.height - 4))
        return mirrored(NSRect(x: box.minX, y: (bounds.height - height) / 2, width: box.width, height: height)).intersection(bounds)
    }

    private func checkBoxAppearance(checked: Bool) -> FluentCheckBoxAppearance {
        FluentAutomaticCheckBoxStyle().appearance(for: FluentCheckBoxStyleConfiguration(
            isChecked: checked, isEnabled: true, isPointerOver: isCheckBoxPointerOver,
            isPressed: isTrackingCheckBox && isCheckBoxPointerOver, isIndeterminate: layoutState?.checkState == .mixed,
            controlSize: .regular, theme: theme))
    }

    override func layout() {
        super.layout()
        applyLayers(animated: false)
    }

    private func applyLayers(animated: Bool) {
        guard let layoutState else { return }
        let direction: FluentChevronDirection = layoutState.isExpanded ? .down : (layoutState.isRightToLeft ? .left : .right)
        chevronLayer.isHidden = !layoutState.isExpandable
        chevronLayer.update(frame: chevronFrame, color: theme.textPrimary, state: .normal, direction: direction,
                            animated: animated)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let state = layoutState.checkState {
            let appearance = checkBoxAppearance(checked: state != .unchecked)
            checkBoxBackgroundLayer.isHidden = false
            // WinUI's High Contrast MultiSelectGrid adds a 1pt margin and 1pt border.
            // Clip the presenter's background to that inner slot when an explicit row
            // height cannot accommodate its minimum height; do not paint over the row border.
            let presenterInset = FluentTreeViewMetrics.presenterMarginY + (theme.isHighContrast ? 2 : 0)
            checkBoxBackgroundLayer.frame = checkBoxHitFrame.intersection(bounds.insetBy(dx: 0, dy: presenterInset))
            checkBoxBackgroundLayer.backgroundColor = appearance.backgroundColor.cgColor
            checkBoxBackgroundLayer.cornerRadius = appearance.cornerRadius
            checkBoxLayer.isHidden = false
            checkBoxLayer.frame = checkBoxFrame
            checkBoxLayer.cornerRadius = appearance.cornerRadius
            checkBoxLayer.backgroundColor = appearance.fillColor.cgColor
            checkBoxLayer.borderColor = appearance.borderColor.cgColor
            checkBoxLayer.borderWidth = appearance.borderWidth
            checkMarkLayer.frame = checkBoxLayer.bounds
            checkMarkLayer.strokeColor = appearance.markColor.cgColor
            checkMarkLayer.lineWidth = 1.5
            checkMarkLayer.path = Self.markPath(for: state, in: checkBoxLayer.bounds)
        } else {
            checkBoxBackgroundLayer.isHidden = true
            checkBoxLayer.isHidden = true
        }
        CATransaction.commit()
    }

    /// The CheckBox check glyph, or the indeterminate dash for a partly checked parent.
    static func markPath(for state: FluentTreeCheckState, in bounds: CGRect) -> CGPath? {
        let path = CGMutablePath()
        let w = bounds.width
        switch state {
        case .unchecked:
            return nil
        case .checked:
            path.move(to: CGPoint(x: w * 0.27, y: w * 0.52))
            path.addLine(to: CGPoint(x: w * 0.43, y: w * 0.68))
            path.addLine(to: CGPoint(x: w * 0.74, y: w * 0.34))
        case .mixed:
            path.move(to: CGPoint(x: w * 0.3, y: w * 0.5))
            path.addLine(to: CGPoint(x: w * 0.7, y: w * 0.5))
        }
        return path
    }

    override func mouseDown(with event: NSEvent) {
        if enclosingOutline?.handleAccessoryMouseDown(event) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if enclosingOutline?.handleAccessoryMouseDragged(event) == true { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if enclosingOutline?.handleAccessoryMouseUp(event) == true { return }
        super.mouseUp(with: event)
    }

    private var enclosingOutline: FluentTreeNativeOutlineView? {
        var ancestor = superview
        while let view = ancestor {
            if let outline = view as? FluentTreeNativeOutlineView { return outline }
            ancestor = view.superview
        }
        return nil
    }

    func accessory(at point: NSPoint) -> Accessory? {
        if checkBoxHitFrame.contains(point) { return .checkBox }
        if chevronHitFrame.contains(point) { return .chevron }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { updateCheckBoxPointer(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateCheckBoxPointer(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { isCheckBoxPointerOver = false; applyLayers(animated: false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelCheckBoxPress() }
    }

    func beginCheckBoxPress() {
        isTrackingCheckBox = true
        isCheckBoxPointerOver = true
        applyLayers(animated: false)
    }

    func updateCheckBoxPointer(at point: NSPoint) {
        let inside = checkBoxHitFrame.contains(point)
        guard inside != isCheckBoxPointerOver else { return }
        isCheckBoxPointerOver = inside
        applyLayers(animated: false)
    }

    func cancelCheckBoxPress() {
        guard isTrackingCheckBox || isCheckBoxPointerOver else { return }
        isTrackingCheckBox = false
        isCheckBoxPointerOver = false
        applyLayers(animated: false)
    }

    func performChevronClick() { onToggleExpansion?() }
    func performCheckBoxClick() { onToggleCheck?() }
}
