import AppKit

/// A stable description of a list reordering gesture. The destination uses the same semantics as
/// `FluentList.onMove`: it is an insertion offset in the collection before the source rows are
/// removed.
public struct FluentListMoveIntent: Equatable {
    public let sourceIndexes: IndexSet
    public let destination: Int

    public init(sourceIndexes: IndexSet, destination: Int) {
        self.sourceIndexes = sourceIndexes
        self.destination = destination
    }

    /// Returns a reordered copy while ignoring source indexes outside the collection.
    public func applying<Element>(to elements: [Element]) -> [Element] {
        let validSources = sourceIndexes.filter { elements.indices.contains($0) }
        guard !validSources.isEmpty else { return elements }

        let moved = validSources.map { elements[$0] }
        var remaining = elements.enumerated().compactMap { index, element in
            validSources.contains(index) ? nil : element
        }
        let boundedDestination = min(max(destination, 0), elements.count)
        let removedBeforeDestination = validSources.filter { $0 < boundedDestination }.count
        let insertionIndex = min(max(boundedDestination - removedBeforeDestination, 0), remaining.count)
        remaining.insert(contentsOf: moved, at: insertionIndex)
        return remaining
    }
}

/// A virtualized, selectable list backed by NSCollectionView.
///
/// Only visible rows receive native AppKit views. Stable row identities let the list distinguish a
/// content update from a structural change while preserving the scroll host and selection state.
public struct FluentList<Row: FluentView>: FluentUpdatablePrimitiveView {
    private let rows: [Row]
    private let rowIDs: [AnyHashable]?
    private let spacing: CGFloat
    private let rowHeight: CGFloat
    private let selection: FluentBinding<Int>?
    private let identitySelection: FluentListIdentityBinding?
    private let identitySelections: FluentListIdentitySetBinding?
    private let moveAction: ((IndexSet, Int) -> Void)?

    public init(
        rows: [Row],
        spacing: CGFloat = 2,
        rowHeight: CGFloat = 48,
        selection: FluentBinding<Int>? = nil,
        onMove: ((IndexSet, Int) -> Void)? = nil
    ) {
        self.rows = rows
        self.rowIDs = nil
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.selection = selection
        self.identitySelection = nil
        self.identitySelections = nil
        self.moveAction = onMove
    }

    /// Initializes a list with stable identities for each row.
    public init<ID: Hashable>(
        rows: [Row],
        id: @escaping (Row) -> ID,
        spacing: CGFloat = 2,
        rowHeight: CGFloat = 48,
        selection: FluentBinding<Int>? = nil,
        onMove: ((IndexSet, Int) -> Void)? = nil
    ) {
        self.rows = rows
        self.rowIDs = rows.map { AnyHashable(id($0)) }
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.selection = selection
        self.identitySelection = nil
        self.identitySelections = nil
        self.moveAction = onMove
    }

    /// Initializes a list whose selection is expressed with the same stable identity as its rows.
    public init<ID: Hashable>(
        rows: [Row],
        id: @escaping (Row) -> ID,
        spacing: CGFloat = 2,
        rowHeight: CGFloat = 48,
        selectionID: FluentBinding<ID?>,
        onMove: ((IndexSet, Int) -> Void)? = nil
    ) {
        self.rows = rows
        self.rowIDs = rows.map { AnyHashable(id($0)) }
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.selection = nil
        self.identitySelection = FluentListIdentityBinding(selectionID)
        self.identitySelections = nil
        self.moveAction = onMove
    }

    /// Initializes a stable-ID list with native multiple selection. Command-click toggles one
    /// row and Shift-click extends the selection from the most recent anchor.
    public init<ID: Hashable>(
        rows: [Row],
        id: @escaping (Row) -> ID,
        spacing: CGFloat = 2,
        rowHeight: CGFloat = 48,
        selectionIDs: FluentBinding<Set<ID>>,
        onMove: ((IndexSet, Int) -> Void)? = nil
    ) {
        self.rows = rows
        self.rowIDs = rows.map { AnyHashable(id($0)) }
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.selection = nil
        self.identitySelection = nil
        self.identitySelections = FluentListIdentitySetBinding(selectionIDs)
        self.moveAction = onMove
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let list = FluentListView<Row>(theme: context.theme, spacing: spacing, rowHeight: rowHeight)
        list.setRows(
            rows,
            rowIDs: rowIDs,
            selection: selection,
            identitySelection: identitySelection,
            identitySelections: identitySelections,
            moveAction: moveAction,
            context: context
        )
        return list
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let list = view as? FluentListView<Row> else { return false }
        list.update(
            rows: rows,
            rowIDs: rowIDs,
            selection: selection,
            identitySelection: identitySelection,
            identitySelections: identitySelections,
            moveAction: moveAction,
            context: context,
            spacing: spacing,
            rowHeight: rowHeight
        )
        return true
    }
}

private struct FluentListIdentityBinding {
    let get: () -> AnyHashable?
    let set: (AnyHashable?) -> Void
    let observe: ((@escaping (AnyHashable?) -> Void) -> UUID)?
    let removeObserver: ((UUID) -> Void)?

    init<ID: Hashable>(_ binding: FluentBinding<ID?>) {
        get = { binding.get().map(AnyHashable.init) }
        set = { value in binding.set(value.flatMap { $0.base as? ID }) }
        observe = binding.observe.map { observe in
            { observer in observe { observer($0.map(AnyHashable.init)) } }
        }
        removeObserver = binding.removeObserver
    }
}

private struct FluentListIdentitySetBinding {
    let get: () -> Set<AnyHashable>
    let set: (Set<AnyHashable>) -> Void
    let observe: ((@escaping (Set<AnyHashable>) -> Void) -> UUID)?
    let removeObserver: ((UUID) -> Void)?

    init<ID: Hashable>(_ binding: FluentBinding<Set<ID>>) {
        get = { Set(binding.get().map(AnyHashable.init)) }
        set = { values in binding.set(Set(values.compactMap { $0.base as? ID })) }
        observe = binding.observe.map { observe in
            { observer in observe { observer(Set($0.map(AnyHashable.init))) } }
        }
        removeObserver = binding.removeObserver
    }
}

private final class FluentCollectionView: NSCollectionView {
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !(keyHandler?(event) ?? false) {
            super.keyDown(with: event)
        }
    }
}

private final class FluentListFlowLayout: NSCollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        true
    }

    override func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if let flowContext = context as? NSCollectionViewFlowLayoutInvalidationContext {
            flowContext.invalidateFlowLayoutDelegateMetrics = true
            flowContext.invalidateFlowLayoutAttributes = true
        }
        return context
    }

    override func prepare() {
        guard let collectionView else { return }
        let contentInsets = collectionView.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let availableWidth = collectionView.bounds.width
            - sectionInset.left - sectionInset.right
            - contentInsets.left - contentInsets.right
        guard availableWidth > 1 else { return }
        super.prepare()
    }
}

private let fluentListItemIdentifier = NSUserInterfaceItemIdentifier("FluentKit.List.Row")
private let fluentListReorderPasteboardType = NSPasteboard.PasteboardType("com.fluentkit.list-reorder")

protocol FluentListRenderingSuspending: AnyObject {
    func setListRenderingSuspended(_ suspended: Bool)
}

private final class FluentListView<Row: FluentView>: NSScrollView, NSCollectionViewDataSource,
    NSCollectionViewDelegateFlowLayout, FluentListRenderingSuspending {
    private let collectionView: FluentCollectionView
    private var theme: FluentTheme
    private var spacing: CGFloat
    private var rowHeight: CGFloat
    private var rows: [Row] = []
    private var rowIDs: [AnyHashable]?
    private var selection: FluentBinding<Int>?
    private var identitySelection: FluentListIdentityBinding?
    private var identitySelections: FluentListIdentitySetBinding?
    private var observedSelection: FluentBinding<Int>?
    private var selectionObserverID: UUID?
    private var observedIdentitySelection: FluentListIdentityBinding?
    private var identitySelectionObserverID: UUID?
    private var observedIdentitySelections: FluentListIdentitySetBinding?
    private var identitySelectionsObserverID: UUID?
    private var currentSelection: Int?
    private var currentSelections = Set<Int>()
    private var selectionAnchor: Int?
    private var moveAction: ((IndexSet, Int) -> Void)?
    private let reorderSessionID = UUID()
    private var context = FluentRenderContext()
    private var isApplyingSelection = false
    private var needsInitialReload = false
    private var needsDataSourceSetup = true
    private let flowLayout = FluentListFlowLayout()
    private let selectionIndicatorAnimator = FluentSelectionIndicatorAnimator(
        currentLayerName: "FluentKit.List.SelectionIndicator",
        previousLayerName: "FluentKit.List.PreviousSelectionIndicator",
        axis: .vertical
    )
    private var lastIndicatorIndex: Int?
    private var selectionGeometryObservers: [NSObjectProtocol] = []
    private var selectionGeometryUpdateScheduled = false

    init(theme: FluentTheme, spacing: CGFloat, rowHeight: CGFloat) {
        self.theme = theme
        self.spacing = spacing
        self.rowHeight = rowHeight
        // AppKit validates flow-layout item sizes when the layout is attached, before the host's
        // constraints have produced a real viewport. Use a tiny valid bootstrap viewport; the
        // normal layout pass immediately replaces it with the actual content width.
        collectionView = FluentCollectionView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        super.init(frame: .zero)

        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder

        flowLayout.minimumLineSpacing = spacing
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = NSEdgeInsetsZero
        flowLayout.itemSize = NSSize(width: 1, height: max(rowHeight, 1))
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.wantsLayer = true
        if let collectionLayer = collectionView.layer {
            selectionIndicatorAnimator.attach(to: collectionLayer)
        }
        collectionView.register(FluentCollectionItem.self, forItemWithIdentifier: fluentListItemIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        documentView = collectionView
        collectionView.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true

        contentView.postsBoundsChangedNotifications = true
        collectionView.postsBoundsChangedNotifications = true
        collectionView.postsFrameChangedNotifications = true
        let notificationCenter = NotificationCenter.default
        selectionGeometryObservers = [
            notificationCenter.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSelectionGeometryUpdate()
            },
            notificationCenter.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: collectionView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSelectionGeometryUpdate()
            },
            notificationCenter.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: collectionView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSelectionGeometryUpdate()
            }
        ]

        setAccessibilityRole(.list)
        setAccessibilityLabel("List")
        collectionView.setAccessibilityRole(.list)
        collectionView.setAccessibilityLabel("List")
        collectionView.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let viewportWidth = contentView.bounds.width
        let insets = NSEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
        guard viewportWidth > insets.left + insets.right + 1 else { return }
        let currentInsets = flowLayout.sectionInset
        let insetsChanged = currentInsets.top != insets.top
            || currentInsets.left != insets.left
            || currentInsets.bottom != insets.bottom
            || currentInsets.right != insets.right
        if insetsChanged {
            flowLayout.sectionInset = insets
            flowLayout.invalidateLayout()
        }
        setupDataSourceIfNeeded()
        if needsInitialReload {
            needsInitialReload = false
            collectionView.reloadData()
            applySelection()
        }
        updateSelectionIndicator(animated: false)
    }

    override func reflectScrolledClipView(_ cClipView: NSClipView) {
        super.reflectScrolledClipView(cClipView)
        scheduleSelectionGeometryUpdate()
    }

    private func scheduleSelectionGeometryUpdate() {
        guard !selectionGeometryUpdateScheduled else { return }
        selectionGeometryUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.selectionGeometryUpdateScheduled = false
            self.layoutSubtreeIfNeeded()
            self.collectionView.layoutSubtreeIfNeeded()
            self.updateSelectionIndicator(
                animated: self.lastIndicatorIndex != nil
                    && self.lastIndicatorIndex != self.currentSelection
            )
        }
    }

    private func setupDataSourceIfNeeded() {
        guard needsDataSourceSetup else { return }
        needsDataSourceSetup = false
        collectionView.collectionViewLayout = flowLayout
        collectionView.register(FluentCollectionItem.self, forItemWithIdentifier: fluentListItemIdentifier)
        collectionView.dataSource = self
    }

    func setListRenderingSuspended(_ suspended: Bool) {
        if suspended {
            guard !needsDataSourceSetup else { return }
            collectionView.dataSource = nil
            collectionView.collectionViewLayout = nil
            needsDataSourceSetup = true
            needsInitialReload = true
        } else {
            needsLayout = true
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let insets = (collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset ?? NSEdgeInsetsZero
        let contentInsets = collectionView.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let availableWidth = collectionView.bounds.width
            - insets.left - insets.right
            - contentInsets.left - contentInsets.right
        return NSSize(width: max(floor(availableWidth - 1), 1), height: max(rowHeight, 1))
    }

    func setRows(
        _ rows: [Row],
        rowIDs: [AnyHashable]?,
        selection: FluentBinding<Int>?,
        identitySelection: FluentListIdentityBinding?,
        identitySelections: FluentListIdentitySetBinding?,
        moveAction: ((IndexSet, Int) -> Void)?,
        context: FluentRenderContext
    ) {
        self.rows = rows
        self.rowIDs = rowIDs
        self.selection = selection
        self.identitySelection = identitySelection
        self.identitySelections = identitySelections
        self.moveAction = moveAction
        self.context = context
        currentSelection = resolvedSelection(index: selection?.get(), identity: identitySelection?.get(), rowIDs: rowIDs)
        currentSelections = resolvedSelections(identities: identitySelections?.get(), rowIDs: rowIDs)
        selectionAnchor = currentSelections.sorted().last ?? currentSelection
        collectionView.allowsMultipleSelection = identitySelections != nil
        configureReordering()
        installSelectionObserver()
        needsInitialReload = true
        needsLayout = true
    }

    func update(
        rows: [Row],
        rowIDs: [AnyHashable]?,
        selection: FluentBinding<Int>?,
        identitySelection: FluentListIdentityBinding?,
        identitySelections: FluentListIdentitySetBinding?,
        moveAction: ((IndexSet, Int) -> Void)?,
        context: FluentRenderContext,
        spacing: CGFloat,
        rowHeight: CGFloat
    ) {
        let oldRowIDs = self.rowIDs
        let oldSelection = currentSelection
        let oldSelectedID = oldSelection.flatMap { index in oldRowIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
        self.theme = context.theme
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.selection = selection
        self.identitySelection = identitySelection
        self.identitySelections = identitySelections
        self.moveAction = moveAction
        self.context = context
        collectionView.allowsMultipleSelection = identitySelections != nil
        configureReordering()
        installSelectionObserver()

        let structureChanged = self.rows.count != rows.count || oldRowIDs != rowIDs
        self.rows = rows
        self.rowIDs = rowIDs
        let requestedIndex = selection?.get()
        if identitySelections != nil {
            currentSelection = nil
            currentSelections = resolvedSelections(identities: identitySelections?.get(), rowIDs: rowIDs)
            if let selectionAnchor, !currentSelections.contains(selectionAnchor) {
                self.selectionAnchor = currentSelections.sorted().last
            }
        } else if identitySelection != nil {
            currentSelection = resolvedSelection(index: nil, identity: identitySelection?.get(), rowIDs: rowIDs)
        } else if let selection, requestedIndex != oldSelection {
            currentSelection = validSelection(selection.get(), rowCount: rows.count)
        } else if let oldSelectedID, let rowIDs, let newIndex = rowIDs.firstIndex(of: oldSelectedID) {
            currentSelection = newIndex
        } else {
            currentSelection = validSelection(requestedIndex ?? oldSelection, rowCount: rows.count)
        }

        synchronizeSelectionBindings()

        flowLayout.minimumLineSpacing = spacing
        flowLayout.itemSize.height = max(rowHeight, 1)

        if structureChanged {
            guard hasUsableViewport else {
                needsInitialReload = true
                needsLayout = true
                return
            }
            if !applyStableDifference(from: oldRowIDs, to: rowIDs) {
                collectionView.reloadData()
                applySelection()
            }
        } else {
            updateVisibleItems()
            collectionView.collectionViewLayout?.invalidateLayout()
            applySelection()
        }
    }

    private var hasUsableViewport: Bool {
        contentView.bounds.width > 5
    }

    private func installSelectionObserver() {
        if let selectionObserverID {
            observedSelection?.removeObserver?(selectionObserverID)
        }
        observedSelection = selection
        selectionObserverID = selection?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentSelection = self.validSelection(value, rowCount: self.rows.count)
                self.applySelection()
            }
        }

        if let identitySelectionObserverID {
            observedIdentitySelection?.removeObserver?(identitySelectionObserverID)
        }
        observedIdentitySelection = identitySelection
        identitySelectionObserverID = identitySelection?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentSelection = self.resolvedSelection(index: nil, identity: value, rowIDs: self.rowIDs)
                self.applySelection()
            }
        }

        if let identitySelectionsObserverID {
            observedIdentitySelections?.removeObserver?(identitySelectionsObserverID)
        }
        observedIdentitySelections = identitySelections
        identitySelectionsObserverID = identitySelections?.observe? { [weak self] values in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentSelections = self.resolvedSelections(identities: values, rowIDs: self.rowIDs)
                self.applySelection()
            }
        }
    }

    private func configureReordering() {
        if moveAction == nil {
            collectionView.unregisterDraggedTypes()
        } else {
            collectionView.registerForDraggedTypes([fluentListReorderPasteboardType])
            collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        }
    }

    private func resolvedSelection(index: Int?, identity: AnyHashable?, rowIDs: [AnyHashable]?) -> Int? {
        if let identity, let rowIDs {
            guard Set(rowIDs).count == rowIDs.count else { return nil }
            return rowIDs.firstIndex(of: identity)
        }
        return validSelection(index, rowCount: rows.count)
    }

    private func validSelection(_ value: Int?, rowCount: Int) -> Int? {
        guard rowCount > 0, let value else { return nil }
        return min(max(value, 0), rowCount - 1)
    }

    private func resolvedSelections(
        identities: Set<AnyHashable>?,
        rowIDs: [AnyHashable]?
    ) -> Set<Int> {
        guard let identities, let rowIDs, Set(rowIDs).count == rowIDs.count else { return [] }
        return Set(rowIDs.indices.filter { identities.contains(rowIDs[$0]) })
    }

    private func synchronizeSelectionBindings() {
        if let selection, selection.get() != currentSelection {
            if let currentSelection { selection.set(currentSelection) }
        }
        if let identitySelection {
            let selectedID = currentSelection.flatMap { index in rowIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
            if identitySelection.get() != selectedID {
                identitySelection.set(selectedID)
            }
        }
        if let identitySelections, let rowIDs {
            let selectedIDs = Set(currentSelections.compactMap { index in
                rowIDs.indices.contains(index) ? rowIDs[index] : nil
            })
            if identitySelections.get() != selectedIDs {
                identitySelections.set(selectedIDs)
            }
        }
    }

    private func applyStableDifference(from oldIDs: [AnyHashable]?, to newIDs: [AnyHashable]?) -> Bool {
        guard let oldIDs, let newIDs,
              Set(oldIDs).count == oldIDs.count,
              Set(newIDs).count == newIDs.count else { return false }

        let difference = newIDs.difference(from: oldIDs).inferringMoves()
        var deletions = Set<IndexPath>()
        var insertions = Set<IndexPath>()
        var moves: [(from: IndexPath, to: IndexPath)] = []

        for change in difference {
            switch change {
            case let .remove(offset, _, associatedWith):
                if let destination = associatedWith {
                    moves.append((IndexPath(item: offset, section: 0), IndexPath(item: destination, section: 0)))
                } else {
                    deletions.insert(IndexPath(item: offset, section: 0))
                }
            case let .insert(offset, _, associatedWith):
                if associatedWith == nil {
                    insertions.insert(IndexPath(item: offset, section: 0))
                }
            }
        }

        collectionView.performBatchUpdates {
            collectionView.deleteItems(at: deletions)
            collectionView.insertItems(at: insertions)
            for move in moves {
                collectionView.moveItem(at: move.from, to: move.to)
            }
        } completionHandler: { [weak self] _ in
            self?.updateVisibleItems()
            self?.collectionView.collectionViewLayout?.invalidateLayout()
            self?.applySelection()
        }
        return true
    }

    private func updateVisibleItems() {
        for item in collectionView.visibleItems() {
            guard let item = item as? FluentCollectionItem,
                  let indexPath = collectionView.indexPath(for: item),
                  indexPath.item < rows.count else { continue }
            item.configure(
                index: indexPath.item,
                theme: theme,
                selected: isSelected(indexPath.item),
                update: { [row = rows[indexPath.item], context] nativeView in row._update(nativeView, in: context) },
                make: { [row = rows[indexPath.item], context] in row._mount(in: context) },
                onSelect: { [weak self] modifiers in self?.select(index: indexPath.item, modifiers: modifiers) }
            )
        }
    }

    private func applySelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }

        let selectedIndices = identitySelections == nil
            ? Set(currentSelection.map { [$0] } ?? [])
            : currentSelections
        collectionView.deselectAll(nil)
        if !selectedIndices.isEmpty {
            let indexPaths = Set(selectedIndices.map { IndexPath(item: $0, section: 0) })
            collectionView.selectItems(at: indexPaths, scrollPosition: [])
        }
        for item in collectionView.visibleItems() {
            guard let item = item as? FluentCollectionItem,
                  let indexPath = collectionView.indexPath(for: item) else { continue }
            item.setSelected(selectedIndices.contains(indexPath.item))
        }
        updateSelectionIndicator(animated: lastIndicatorIndex != nil && lastIndicatorIndex != currentSelection)
        collectionView.needsLayout = true
        scheduleSelectionGeometryUpdate()
    }

    private func updateSelectionIndicator(animated: Bool) {
        guard identitySelections == nil,
              let currentSelection,
              rows.indices.contains(currentSelection) else {
            selectionIndicatorAnimator.update(
                target: nil,
                color: theme.accent,
                animated: false,
                reduceMotion: context.reduceMotion
            )
            lastIndicatorIndex = nil
            return
        }

        guard let layoutFrame = selectionItemFrame(at: currentSelection),
              let itemFrame = indicatorCoordinateFrame(for: layoutFrame) else {
            collectionView.needsLayout = true
            needsLayout = true
            scheduleSelectionGeometryUpdate()
            return
        }

        // The selection rail follows the leading edge so NavigationView-style lists mirror cleanly
        // when the render environment is right-to-left.
        let railX = context.layoutDirection.appKitValue == .rightToLeft
            ? itemFrame.maxX - 5
            : itemFrame.minX + 2
        let target = NSRect(x: railX, y: itemFrame.midY - 8, width: 3, height: 16)
        selectionIndicatorAnimator.update(
            target: target,
            color: theme.accent,
            animated: animated,
            reduceMotion: context.reduceMotion
        )
        lastIndicatorIndex = currentSelection
    }

    private func selectionItemFrame(at index: Int) -> NSRect? {
        let indexPath = IndexPath(item: index, section: 0)
        if let visibleFrame = collectionView.item(at: indexPath)?.view.frame,
           visibleFrame.width > 0,
           visibleFrame.height > 0 {
            return visibleFrame
        }
        guard let layoutFrame = flowLayout.layoutAttributesForItem(at: indexPath)?.frame,
              layoutFrame.width > 0,
              layoutFrame.height > 0 else { return nil }
        return layoutFrame
    }

    /// Converts flow-layout document coordinates into the collection view's view-owned layer
    /// coordinates. AppKit preserves the collection view's top-origin semantics for its sublayers,
    /// even while the backing layer's `isGeometryFlipped` value changes during attachment.
    private func indicatorCoordinateFrame(for layoutFrame: NSRect) -> NSRect? {
        guard let collectionLayer = collectionView.layer else { return nil }
        let viewBounds = collectionView.bounds
        let layerBounds = collectionLayer.bounds
        let localX = layoutFrame.minX - viewBounds.minX + layerBounds.minX
        let localY = layoutFrame.minY - viewBounds.minY + layerBounds.minY
        return NSRect(
            x: localX,
            y: localY,
            width: layoutFrame.width,
            height: layoutFrame.height
        )
    }

    private func isSelected(_ index: Int) -> Bool {
        identitySelections == nil ? currentSelection == index : currentSelections.contains(index)
    }

    private func select(index: Int, modifiers: NSEvent.ModifierFlags = []) {
        guard rows.indices.contains(index) else { return }
        if identitySelections != nil {
            if modifiers.contains(.shift), let selectionAnchor {
                currentSelections.formUnion(min(selectionAnchor, index)...max(selectionAnchor, index))
            } else if modifiers.contains(.command) {
                if currentSelections.contains(index) {
                    currentSelections.remove(index)
                } else {
                    currentSelections.insert(index)
                }
                selectionAnchor = index
            } else {
                currentSelections = [index]
                selectionAnchor = index
            }
            synchronizeSelectionBindings()
        } else {
            currentSelection = index
            selectionAnchor = index
            selection?.set(index)
            if let rowIDs { identitySelection?.set(rowIDs[index]) }
        }
        applySelection()
        context.invalidate?()
        window?.makeFirstResponder(collectionView)
        if let item = collectionView.item(at: IndexPath(item: index, section: 0)) {
            _ = collectionView.scrollToVisible(item.view.frame)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard !rows.isEmpty else { return false }
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return true
        }

        let current = currentSelection ?? 0
        let pageSize = max(collectionView.visibleItems().count - 1, 1)
        let next: Int?
        switch event.keyCode {
        case 125: next = currentSelection == nil ? 0 : min(current + 1, rows.count - 1)
        case 126: next = currentSelection == nil ? 0 : max(current - 1, 0)
        case 115: next = 0
        case 119: next = rows.count - 1
        case 116: next = max(current - pageSize, 0)
        case 121: next = min(current + pageSize, rows.count - 1)
        case 36, 49: next = currentSelection ?? 0
        default: next = nil
        }
        guard let next else { return false }
        select(index: next, modifiers: event.modifierFlags)
        return true
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.count
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: fluentListItemIdentifier, for: indexPath)
        guard let item = item as? FluentCollectionItem else { return item }
        let row = rows[indexPath.item]
        item.configure(
            index: indexPath.item,
            theme: theme,
            selected: isSelected(indexPath.item),
            update: { [context] nativeView in row._update(nativeView, in: context) },
            make: { [context] in row._mount(in: context) },
            onSelect: { [weak self] modifiers in self?.select(index: indexPath.item, modifiers: modifiers) }
        )
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection, let index = indexPaths.first?.item else { return }
        select(index: index)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard moveAction != nil else { return nil }
        let item = NSPasteboardItem()
        item.setString(
            reorderSessionID.uuidString + ":" + String(indexPath.item),
            forType: fluentListReorderPasteboardType
        )
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard moveAction != nil, sourceIndexes(from: draggingInfo.draggingPasteboard) != nil else { return [] }
        proposedDropOperation.pointee = .before
        let destination = min(max(proposedDropIndexPath.pointee.item, 0), rows.count)
        proposedDropIndexPath.pointee = NSIndexPath(forItem: destination, inSection: 0)
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let sourceIndexes = sourceIndexes(from: draggingInfo.draggingPasteboard),
              !sourceIndexes.isEmpty,
              let moveAction else { return false }
        let intent = FluentListMoveIntent(
            sourceIndexes: sourceIndexes,
            destination: min(max(indexPath.item, 0), rows.count)
        )
        moveAction(intent.sourceIndexes, intent.destination)
        return true
    }

    private func sourceIndexes(from pasteboard: NSPasteboard) -> IndexSet? {
        let prefix = reorderSessionID.uuidString + ":"
        let indexes = pasteboard.pasteboardItems?.compactMap { item -> Int? in
            guard let value = item.string(forType: fluentListReorderPasteboardType),
                  value.hasPrefix(prefix),
                  let index = Int(value.dropFirst(prefix.count)),
                  rows.indices.contains(index) else { return nil }
            return index
        } ?? []
        guard !indexes.isEmpty else { return nil }
        return IndexSet(indexes)
    }

    deinit {
        let notificationCenter = NotificationCenter.default
        selectionGeometryObservers.forEach { notificationCenter.removeObserver($0) }
        if let selectionObserverID {
            observedSelection?.removeObserver?(selectionObserverID)
        }
        if let identitySelectionObserverID {
            observedIdentitySelection?.removeObserver?(identitySelectionObserverID)
        }
        if let identitySelectionsObserverID {
            observedIdentitySelections?.removeObserver?(identitySelectionsObserverID)
        }
    }
}

private final class FluentCollectionItem: NSCollectionViewItem {
    private var rowView: FluentListItemView { view as! FluentListItemView }

    override func loadView() {
        view = FluentListItemView(index: 0, isSelected: false, theme: .current)
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        rowView.isSelected = selected
    }

    func configure(
        index: Int,
        theme: FluentTheme,
        selected: Bool,
        update: @escaping (NSView) -> Bool,
        make: @escaping () -> NSView,
        onSelect: @escaping (NSEvent.ModifierFlags) -> Void
    ) {
        let row = rowView
        row.index = index
        row.theme = theme
        row.isSelected = selected
        row.onSelect = onSelect
        row.updateContent(update: update, make: make)
        row.setAccessibilityTitle("Row \(index + 1)")
    }
}

private final class FluentListItemView: NSView {
    var index: Int
    var theme: FluentTheme { didSet { needsDisplay = true } }
    var isSelected: Bool {
        didSet {
            needsDisplay = true
            setAccessibilityValue(isSelected ? "Selected" : "Not selected")
            setAccessibilitySelected(isSelected)
        }
    }
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    private var isPointerOver = false
    private var contentView: NSView?

    init(index: Int, isSelected: Bool, theme: FluentTheme) {
        self.index = index
        self.isSelected = isSelected
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.row)
        setAccessibilityTitle("Row \(index + 1)")
        setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        setAccessibilitySelected(isSelected)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(_ view: NSView) {
        contentView?.removeFromSuperview()
        contentView = view
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            view.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    func updateContent(update: (NSView) -> Bool, make: () -> NSView) {
        if let contentView, update(contentView) { return }
        setContent(make())
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor = isSelected
            ? theme.controlFillSecondary
            : (isPointerOver ? theme.controlFill : .clear)
        fill.setFill()
        let radius = theme.designTokens.controlCornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override func accessibilityValue() -> Any? { isSelected ? "Selected" : "Not selected" }
    override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onSelect?(event.modifierFlags) }
}

public final class FluentMenuButton: NSButton {
    public var theme: FluentTheme = .current {
        didSet {
            font = theme.typography.font(for: .body)
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    private var menuItems: [FluentMenuItem]
    private var menuFlyout: FluentMenuFlyout?

    public init(title: String, items: [FluentMenuItem]) {
        self.menuItems = items
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        font = FluentTheme.current.typography.font(for: .body)
        focusRingType = .none
        setAccessibilityRole(.popUpButton)
        setAccessibilityTitle(title)
        target = self
        action = #selector(showMenu)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        return NSSize(width: text.width + 34, height: 32)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let radius = theme.designTokens.controlCornerRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        theme.controlFill.setFill(); path.fill()
        theme.controlStroke.setStroke(); path.lineWidth = 1; path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: font as Any, .foregroundColor: theme.textPrimary]
        let text = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(in: NSRect(x: 14, y: bounds.midY - text.height / 2 + 1, width: text.width, height: text.height), withAttributes: attrs)
        let chevronEndY = isFlipped ? bounds.midY - 2 : bounds.midY + 2
        let chevronTipY = isFlipped ? bounds.midY + 2 : bounds.midY - 2
        let chevron = NSBezierPath(); chevron.move(to: NSPoint(x: bounds.maxX - 18, y: chevronEndY)); chevron.line(to: NSPoint(x: bounds.maxX - 14, y: chevronTipY)); chevron.line(to: NSPoint(x: bounds.maxX - 10, y: chevronEndY)); chevron.lineWidth = 1.2; theme.textSecondary.setStroke(); chevron.stroke()
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { showMenu() } else { super.keyDown(with: event) }
    }

    func applyDeclarativeConfiguration(from source: FluentMenuButton) {
        title = source.title
        font = source.font
        menuItems = source.menuItems
        setAccessibilityTitle(title)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    @objc private func showMenu() {
        let flyout = FluentMenuFlyout(items: menuItems, theme: theme)
        menuFlyout = flyout
        flyout.present(relativeTo: self, at: NSPoint(x: bounds.minX, y: bounds.minY))
    }
}
