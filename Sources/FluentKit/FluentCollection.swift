import AppKit

/// WinUI ListView/GridView selection semantics.
public enum FluentListViewSelectionMode: String, CaseIterable, Hashable, Sendable {
    case none
    case single
    case multiple
    case extended
}

/// Controls the WinUI multi-select check visual owned by each collection item.
public enum FluentSelectionCheckmarkVisibility: String, CaseIterable, Hashable, Sendable {
    /// Shows the check visual for Multiple selection and hides it for the other modes.
    case automatic
    case visible
    case hidden
}

/// Near-end loading behavior shared by ListView and GridView.
public struct FluentIncrementalLoadingConfiguration {
    public let threshold: Int
    public let hasMoreItems: Bool
    public let isLoading: Bool
    /// Increment this value to explicitly retry a request that completed without adding items.
    public let retryToken: UInt
    public let loadMore: () -> Void

    public init(
        threshold: Int = 5,
        hasMoreItems: Bool = true,
        isLoading: Bool = false,
        retryToken: UInt = 0,
        loadMore: @escaping () -> Void
    ) {
        self.threshold = max(threshold, 1)
        self.hasMoreItems = hasMoreItems
        self.isLoading = isLoading
        self.retryToken = retryToken
        self.loadMore = loadMore
    }
}

/// Layout metrics for a sectioned Fluent collection.
public struct FluentCollectionLayout: Equatable {
    public enum Kind: Equatable {
        case list
        case adaptiveGrid
    }

    public let kind: Kind
    public let minimumItemWidth: CGFloat
    public let itemHeight: CGFloat
    public let spacing: CGFloat
    public let headerHeight: CGFloat

    private init(
        kind: Kind,
        minimumItemWidth: CGFloat,
        itemHeight: CGFloat,
        spacing: CGFloat,
        headerHeight: CGFloat
    ) {
        self.kind = kind
        self.minimumItemWidth = max(minimumItemWidth, 1)
        self.itemHeight = max(itemHeight, 20)
        self.spacing = max(spacing, 0)
        self.headerHeight = max(headerHeight, 0)
    }

    public static func list(
        rowHeight: CGFloat = 40,
        spacing: CGFloat = 0,
        headerHeight: CGFloat = 34
    ) -> FluentCollectionLayout {
        FluentCollectionLayout(
            kind: .list,
            minimumItemWidth: 1,
            itemHeight: rowHeight,
            spacing: spacing,
            headerHeight: headerHeight
        )
    }

    public static func adaptiveGrid(
        minimumItemWidth: CGFloat = 160,
        itemHeight: CGFloat = 88,
        spacing: CGFloat = 10,
        headerHeight: CGFloat = 34
    ) -> FluentCollectionLayout {
        FluentCollectionLayout(
            kind: .adaptiveGrid,
            minimumItemWidth: minimumItemWidth,
            itemHeight: itemHeight,
            spacing: spacing,
            headerHeight: headerHeight
        )
    }
}

/// A virtualized, sectioned collection backed by `NSCollectionView` and a native diffable data
/// source. Item and section identity comes from `FluentCollectionSnapshot`, so selection remains
/// stable while sections and items are inserted, deleted, or moved.
public struct FluentCollection<SectionID: Hashable, ItemID: Hashable>: FluentUpdatablePrimitiveView {
    private let snapshot: FluentCollectionSnapshot<SectionID, ItemID>
    private let layout: FluentCollectionLayout
    private let selectionMode: FluentListViewSelectionMode
    private let selection: FluentCollectionIdentityBinding?
    private let selections: FluentCollectionIdentitySetBinding?
    private let onItemInvoked: ((ItemID) -> Void)?
    private let selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility
    private let onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)?
    private let incrementalLoading: FluentIncrementalLoadingConfiguration?
    private let isEnabled: (ItemID) -> Bool
    private let itemStyle: any FluentCollectionItemStyle
    private let content: (ItemID) -> FluentAnyView
    private let header: ((SectionID) -> FluentAnyView)?

    private var contentVersion: ((ItemID) -> AnyHashable)?

    /// Opt in to skipping unchanged row content. Include every captured row dependency in the
    /// version. Without a version, visible rows update conservatively on each parent render.
    public func contentVersion(_ version: @escaping (ItemID) -> AnyHashable) -> Self {
        var copy = self
        copy.contentVersion = version
        return copy
    }

    public init<Content: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionID: FluentBinding<ItemID?>? = nil,
        selectionMode: FluentListViewSelectionMode = .single,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.snapshot = snapshot
        self.layout = layout
        self.selectionMode = selectionMode
        selection = selectionID.map(FluentCollectionIdentityBinding.init)
        selections = nil
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        header = nil
    }

    public init<Content: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionIDs: FluentBinding<Set<ItemID>>,
        selectionMode: FluentListViewSelectionMode = .multiple,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.snapshot = snapshot
        self.layout = layout
        self.selectionMode = selectionMode
        selection = nil
        selections = FluentCollectionIdentitySetBinding(selectionIDs)
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        header = nil
    }

    public init<Content: FluentView, Header: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionID: FluentBinding<ItemID?>? = nil,
        selectionMode: FluentListViewSelectionMode = .single,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content,
        @FluentViewBuilder header: @escaping (SectionID) -> Header
    ) {
        self.snapshot = snapshot
        self.layout = layout
        self.selectionMode = selectionMode
        selection = selectionID.map(FluentCollectionIdentityBinding.init)
        selections = nil
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        self.header = { FluentAnyView(header($0)) }
    }

    public init<Content: FluentView, Header: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionIDs: FluentBinding<Set<ItemID>>,
        selectionMode: FluentListViewSelectionMode = .multiple,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content,
        @FluentViewBuilder header: @escaping (SectionID) -> Header
    ) {
        self.snapshot = snapshot
        self.layout = layout
        self.selectionMode = selectionMode
        selection = nil
        selections = FluentCollectionIdentitySetBinding(selectionIDs)
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        self.header = { FluentAnyView(header($0)) }
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentSectionedCollectionView<SectionID, ItemID>(theme: context.theme)
        view.setData(
            snapshot: snapshot,
            layout: layout,
            selectionMode: selectionMode,
            selection: selection,
            selections: selections,
            onItemInvoked: onItemInvoked,
            selectionCheckmarkVisibility: selectionCheckmarkVisibility,
            onItemsReordered: onItemsReordered,
            incrementalLoading: incrementalLoading,
            isEnabled: isEnabled,
            itemStyle: itemStyle,
            content: content,
            contentVersion: contentVersion,
            header: header,
            context: context
        )
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let collection = view as? FluentSectionedCollectionView<SectionID, ItemID> else { return false }
        collection.update(
            snapshot: snapshot,
            layout: layout,
            selectionMode: selectionMode,
            selection: selection,
            selections: selections,
            onItemInvoked: onItemInvoked,
            selectionCheckmarkVisibility: selectionCheckmarkVisibility,
            onItemsReordered: onItemsReordered,
            incrementalLoading: incrementalLoading,
            isEnabled: isEnabled,
            itemStyle: itemStyle,
            content: content,
            contentVersion: contentVersion,
            header: header,
            context: context
        )
        return true
    }
}

private struct FluentCollectionIdentityBinding {
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

private struct FluentCollectionIdentitySetBinding {
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

private let fluentSectionedItemIdentifier = NSUserInterfaceItemIdentifier("FluentKit.Collection.Item")
private let fluentSectionedHeaderIdentifier = NSUserInterfaceItemIdentifier("FluentKit.Collection.Header")
private let fluentCollectionDragType = NSPasteboard.PasteboardType("com.openai.FluentKit.collection-items")

struct FluentCollectionSelectionUpdate: Equatable {
    let selection: Set<IndexPath>
    let anchor: IndexPath?
}

func fluentCollectionSelectionAfterClick(
    current: Set<IndexPath>,
    clicked: IndexPath,
    anchor: IndexPath?,
    previousFocus: IndexPath?,
    mode: FluentListViewSelectionMode,
    modifiers: NSEvent.ModifierFlags,
    orderedEnabledItems: [IndexPath]
) -> FluentCollectionSelectionUpdate {
    if mode == .multiple {
        if modifiers.contains(.shift),
           let resolvedAnchor = anchor ?? previousFocus,
           let start = orderedEnabledItems.firstIndex(of: resolvedAnchor),
           let end = orderedEnabledItems.firstIndex(of: clicked) {
            let range = Set(orderedEnabledItems[min(start, end)...max(start, end)])
            let next = current.contains(resolvedAnchor)
                ? current.union(range)
                : current.subtracting(range)
            return FluentCollectionSelectionUpdate(selection: next, anchor: resolvedAnchor)
        }
        var next = current
        if next.contains(clicked) { next.remove(clicked) } else { next.insert(clicked) }
        return FluentCollectionSelectionUpdate(selection: next, anchor: clicked)
    }
    guard mode == .extended else {
        return FluentCollectionSelectionUpdate(selection: [clicked], anchor: clicked)
    }
    if modifiers.contains(.shift) {
        let resolvedAnchor = anchor ?? previousFocus ?? current.sorted {
            $0.section == $1.section ? $0.item < $1.item : $0.section < $1.section
        }.last ?? clicked
        guard let start = orderedEnabledItems.firstIndex(of: resolvedAnchor),
              let end = orderedEnabledItems.firstIndex(of: clicked) else {
            return FluentCollectionSelectionUpdate(selection: [clicked], anchor: clicked)
        }
        let range = Set(orderedEnabledItems[min(start, end)...max(start, end)])
        return FluentCollectionSelectionUpdate(
            selection: range,
            anchor: resolvedAnchor
        )
    }
    if modifiers.contains(.command) || modifiers.contains(.control) {
        var next = current
        if next.contains(clicked) { next.remove(clicked) } else { next.insert(clicked) }
        return FluentCollectionSelectionUpdate(selection: next, anchor: clicked)
    }
    return FluentCollectionSelectionUpdate(
        selection: current.contains(clicked) ? current : [clicked],
        anchor: clicked
    )
}

func fluentCollectionSelectionAfterKeyboardNavigation(
    current: Set<IndexPath>,
    target: IndexPath,
    anchor: IndexPath?,
    mode: FluentListViewSelectionMode,
    modifiers: NSEvent.ModifierFlags,
    orderedEnabledItems: [IndexPath]
) -> FluentCollectionSelectionUpdate {
    let additive = modifiers.contains(.command) || modifiers.contains(.control)
    guard mode != .none else {
        return FluentCollectionSelectionUpdate(selection: current, anchor: anchor)
    }
    if mode == .single {
        return FluentCollectionSelectionUpdate(
            selection: additive ? current : [target],
            anchor: additive ? anchor : target
        )
    }
    if modifiers.contains(.shift),
       let resolvedAnchor = anchor ?? current.sorted(by: fluentCollectionIndexPathPrecedes).last,
       let start = orderedEnabledItems.firstIndex(of: resolvedAnchor),
       let end = orderedEnabledItems.firstIndex(of: target) {
        let range = Set(orderedEnabledItems[min(start, end)...max(start, end)])
        if mode == .multiple {
            return FluentCollectionSelectionUpdate(
                selection: current.contains(resolvedAnchor)
                    ? current.union(range)
                    : current.subtracting(range),
                anchor: resolvedAnchor
            )
        }
        return FluentCollectionSelectionUpdate(
            selection: additive ? current.union(range) : range,
            anchor: resolvedAnchor
        )
    }
    if mode == .extended, !additive {
        return FluentCollectionSelectionUpdate(selection: [target], anchor: target)
    }
    return FluentCollectionSelectionUpdate(selection: current, anchor: anchor ?? target)
}

private func fluentCollectionIndexPathPrecedes(_ lhs: IndexPath, _ rhs: IndexPath) -> Bool {
    lhs.section == rhs.section ? lhs.item < rhs.item : lhs.section < rhs.section
}

private final class FluentCollectionNativeView: NSCollectionView {
    // AppKit prepares flow layout inside native resizing, before NSScrollView.layout and
    // bounds-change notifications. Resolve item metrics before that work sees the new width.
    var prepareForWidth: ((CGFloat) -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        if widthChanged { prepareForWidth?(newSize.width) }
        super.setFrameSize(newSize)
        if widthChanged { collectionViewLayout?.invalidateLayout() }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != bounds.width
        if widthChanged { prepareForWidth?(newSize.width) }
        super.setBoundsSize(newSize)
        if widthChanged { collectionViewLayout?.invalidateLayout() }
    }

    var onFocusVisibilityChange: (() -> Void)?
    var handleKeyDown: ((NSEvent) -> Bool)?
    var handleMouseDown: ((NSEvent) -> Bool)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusVisibilityChange?() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusVisibilityChange?() }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        onFocusVisibilityChange?()
        if handleKeyDown?(event) == true {
            onFocusVisibilityChange?()
            return
        }
        super.keyDown(with: event)
        onFocusVisibilityChange?()
    }

    override func mouseDown(with event: NSEvent) {
        FluentFocusVisibility.markPointerInteraction(in: window)
        onFocusVisibilityChange?()
        if handleMouseDown?(event) == true {
            onFocusVisibilityChange?()
            return
        }
        super.mouseDown(with: event)
        onFocusVisibilityChange?()
    }
}

final class FluentSectionedCollectionView<SectionID: Hashable, ItemID: Hashable>:
    NSScrollView, NSCollectionViewDelegate, NSDraggingSource, FluentFillWidthProviding {
    // Keep the initial flow-layout geometry valid while the scroll host is still being mounted.
    private let collectionView = FluentCollectionNativeView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private let flowLayout = NSCollectionViewFlowLayout()
    private var snapshot = FluentCollectionSnapshot<SectionID, ItemID>()
    private var layoutSpec = FluentCollectionLayout.list()
    private var selectionMode: FluentListViewSelectionMode = .single
    private var selection: FluentCollectionIdentityBinding?
    private var selections: FluentCollectionIdentitySetBinding?
    private var onItemInvoked: ((ItemID) -> Void)?
    private var selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic
    private var onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)?
    private var incrementalLoading: FluentIncrementalLoadingConfiguration?
    private var isItemEnabled: (ItemID) -> Bool = { _ in true }
    private var itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle()
    private var observedSelection: FluentCollectionIdentityBinding?
    private var observedSelections: FluentCollectionIdentitySetBinding?
    private var selectionObserverID: UUID?
    private var selectionsObserverID: UUID?
    private var content: ((ItemID) -> FluentAnyView)?
    private var header: ((SectionID) -> FluentAnyView)?
    private var contentVersion: ((ItemID) -> AnyHashable)?
    private var availableIDs = Set<AnyHashable>()
    private(set) var snapshotApplicationCount = 0
    private var context = FluentRenderContext()
    private var theme: FluentTheme
    private var isApplyingSelection = false
    private var needsInitialSnapshot = false
    private var hasAppliedSelection = false
    private var pressedIndexPath: IndexPath?
    private var pointerDownPoint: NSPoint?
    private var manualDragStarted = false
    private var pendingClickSelectionUpdate: FluentCollectionSelectionUpdate?
    private var focusedIndexPath: IndexPath?
    private var rangeAnchorIndexPath: IndexPath?
    private var draggedIndexPaths: Set<IndexPath> = []
    private var reorderTargetIndexPath: IndexPath?
    private var lastLoadRequestItemCount: Int?
    private var lastLoadRequestRetryToken: UInt?
    private var lastNearEndEvaluationItemCount: Int?
    private var lastViewportWasNearEnd = false
    private var boundsObserver: NSObjectProtocol?
    private var pointerEventMonitor: Any?
    private var lastViewportWidth: CGFloat = -1
    private var lastResolvedColumnCount = 0
    private var diffableDataSource: NSCollectionViewDiffableDataSource<AnyHashable, AnyHashable>!
    private let loadingIndicator = NSProgressIndicator()
    private let reorderInsertionLayer = CALayer()

    init(theme: FluentTheme) {
        self.theme = theme
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true

        flowLayout.minimumLineSpacing = layoutSpec.spacing
        flowLayout.minimumInteritemSpacing = layoutSpec.spacing
        flowLayout.sectionInset = NSEdgeInsets(top: 2, left: 2, bottom: 8, right: 2)
        flowLayout.itemSize = NSSize(width: 1, height: layoutSpec.itemHeight)
        collectionView.collectionViewLayout = flowLayout
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.focusRingType = .none
        collectionView.backgroundColors = [.clear]
        collectionView.wantsLayer = true
        reorderInsertionLayer.name = "FluentKit.Collection.ReorderInsertion"
        reorderInsertionLayer.cornerRadius = 1
        reorderInsertionLayer.zPosition = 100
        reorderInsertionLayer.opacity = 0
        collectionView.layer?.addSublayer(reorderInsertionLayer)
        collectionView.registerForDraggedTypes([fluentCollectionDragType])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.register(
            FluentSectionedCollectionItem.self,
            forItemWithIdentifier: fluentSectionedItemIdentifier
        )
        collectionView.register(
            FluentSectionedCollectionHeader.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: fluentSectionedHeaderIdentifier
        )
        collectionView.prepareForWidth = { [weak self] width in
            _ = self?.updateLayoutMetrics(viewportWidth: width)
        }
        // The clip view resizes its document synchronously. A width Auto Layout constraint
        // arrives after flow layout has already used the old item width during a resize.
        collectionView.translatesAutoresizingMaskIntoConstraints = true
        collectionView.autoresizingMask = [.width]
        collectionView.setFrameSize(NSSize(width: contentView.bounds.width, height: collectionView.frame.height))
        documentView = collectionView
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.isHidden = true
        addSubview(loadingIndicator)
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateLayoutMetrics()
            self.maybeRequestMoreItems()
        }

        diffableDataSource = NSCollectionViewDiffableDataSource<AnyHashable, AnyHashable>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, _ in
            self?.makeItem(in: collectionView, at: indexPath)
                ?? NSCollectionViewItem()
        }
        diffableDataSource.supplementaryViewProvider = { [weak self] (
            collectionView: NSCollectionView,
            kind: NSCollectionView.SupplementaryElementKind,
            indexPath: IndexPath
        ) -> (NSView & NSCollectionViewElement)? in
            self?.makeHeader(in: collectionView, kind: kind, at: indexPath)
        }
        collectionView.dataSource = diffableDataSource
        collectionView.onFocusVisibilityChange = { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.updateVisibleItemStates(animated: false) }
        }
        collectionView.handleKeyDown = { [weak self] event in
            self?.handleCollectionKeyDown(event) ?? false
        }
        collectionView.handleMouseDown = { [weak self] event in
            self?.handleCollectionMouseDown(event) ?? false
        }
        installPointerEventMonitor()
        updateAccessibilityRole()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        loadingIndicator.frame = NSRect(
            x: bounds.midX - 8,
            y: bounds.minY + 8,
            width: 16,
            height: 16
        )
        let metrics = updateLayoutMetrics()
        if metrics.changed {
            collectionView.needsLayout = true
            collectionView.visibleItems().forEach { $0.view.needsLayout = true }
        }
        if metrics.usable, needsInitialSnapshot {
            needsInitialSnapshot = false
            applySnapshot(animatingDifferences: false)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        lastViewportWidth = -1
        needsLayout = true
    }

    fileprivate func setData(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout,
        selectionMode: FluentListViewSelectionMode,
        selection: FluentCollectionIdentityBinding?,
        selections: FluentCollectionIdentitySetBinding?,
        onItemInvoked: ((ItemID) -> Void)?,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility,
        onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)?,
        incrementalLoading: FluentIncrementalLoadingConfiguration?,
        isEnabled: @escaping (ItemID) -> Bool,
        itemStyle: any FluentCollectionItemStyle,
        content: @escaping (ItemID) -> FluentAnyView,
        contentVersion: ((ItemID) -> AnyHashable)?,
        header: ((SectionID) -> FluentAnyView)?,
        context: FluentRenderContext
    ) {
        self.snapshot = snapshot
        layoutSpec = layout
        self.selectionMode = selectionMode
        self.selection = selection
        self.selections = selections
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        isItemEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = content
        self.contentVersion = contentVersion
        self.header = header
        self.context = context
        theme = context.theme
        collectionView.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        configureSelectionMode()
        configureLayout()
        installSelectionObservers()
        updateIncrementalLoadingState()
        if hasUsableViewport {
            needsInitialSnapshot = false
            applySnapshot(animatingDifferences: false)
        } else {
            needsInitialSnapshot = true
        }
    }

    fileprivate func update(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout,
        selectionMode: FluentListViewSelectionMode,
        selection: FluentCollectionIdentityBinding?,
        selections: FluentCollectionIdentitySetBinding?,
        onItemInvoked: ((ItemID) -> Void)?,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility,
        onItemsReordered: ((FluentCollectionSnapshot<SectionID, ItemID>) -> Void)?,
        incrementalLoading: FluentIncrementalLoadingConfiguration?,
        isEnabled: @escaping (ItemID) -> Bool,
        itemStyle: any FluentCollectionItemStyle,
        content: @escaping (ItemID) -> FluentAnyView,
        contentVersion: ((ItemID) -> AnyHashable)?,
        header: ((SectionID) -> FluentAnyView)?,
        context: FluentRenderContext
    ) {
        let structureChanged = self.snapshot != snapshot
        let environmentChanged = self.context.theme != context.theme
            || self.context.locale != context.locale
            || self.context.localizationBundle != context.localizationBundle
            || self.context.layoutDirection != context.layoutDirection
            || self.context.reduceMotion != context.reduceMotion
        let layoutChanged = layoutSpec != layout
        let headerVisibilityChanged = (self.header == nil) != (header == nil)
        self.snapshot = snapshot
        layoutSpec = layout
        self.selectionMode = selectionMode
        self.selection = selection
        self.selections = selections
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        isItemEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = content
        self.contentVersion = contentVersion
        self.header = header
        self.context = context
        theme = context.theme
        collectionView.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        configureSelectionMode()
        if layoutChanged || headerVisibilityChanged { configureLayout() }
        installSelectionObservers()
        updateIncrementalLoadingState()
        guard hasUsableViewport else {
            needsInitialSnapshot = true
            needsLayout = true
            return
        }
        let mustApply = structureChanged || needsInitialSnapshot
        needsInitialSnapshot = false
        if mustApply {
            applySnapshot(animatingDifferences: structureChanged && window != nil && !context.reduceMotion)
        }
        refreshVisibleContent(force: environmentChanged)
        if !mustApply { applySelection() }
    }

    private func configureLayout() {
        flowLayout.minimumLineSpacing = layoutSpec.spacing
        flowLayout.minimumInteritemSpacing = layoutSpec.spacing
        flowLayout.headerReferenceSize = header == nil
            ? .zero
            : NSSize(width: 1, height: layoutSpec.headerHeight)
        updateAccessibilityRole()
        updateLayoutMetrics()
        flowLayout.invalidateLayout()
    }

    private func configureSelectionMode() {
        collectionView.isSelectable = selectionMode != .none
        collectionView.allowsMultipleSelection = selectionMode == .multiple || selectionMode == .extended
        collectionView.allowsEmptySelection = selectionMode != .single
    }

    @discardableResult
    private func updateLayoutMetrics(viewportWidth proposedWidth: CGFloat? = nil) -> (usable: Bool, changed: Bool) {
        let viewportWidth = max(0, proposedWidth ?? contentView.bounds.width)
        // Retain a valid one-point layout slot while a viewport collapses; the clip view
        // still owns visibility. Horizontal padding yields before the item becomes negative.
        let horizontalInset = min(2, max(0, (viewportWidth - 1) / 2))
        let insets = NSEdgeInsets(top: 2, left: horizontalInset, bottom: 8, right: horizontalInset)
        let availableWidth = viewportWidth > 0 ? viewportWidth - insets.left - insets.right : 1
        let itemWidth: CGFloat
        let columns: Int
        switch layoutSpec.kind {
        case .list:
            columns = 1
            itemWidth = availableWidth
        case .adaptiveGrid:
            columns = max(Int((availableWidth + layoutSpec.spacing)
                / (layoutSpec.minimumItemWidth + layoutSpec.spacing)), 1)
            itemWidth = (availableWidth - CGFloat(columns - 1) * layoutSpec.spacing) / CGFloat(columns)
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let pixelScale = max(scale, 1)
        let alignedItemWidth = max(min(itemWidth, 1 / pixelScale), floor(itemWidth * pixelScale) / pixelScale)
        let itemSize = NSSize(width: alignedItemWidth, height: layoutSpec.itemHeight)
        let headerSize = header == nil
            ? NSSize.zero
            : NSSize(width: availableWidth, height: layoutSpec.headerHeight)
        let changed = abs(lastViewportWidth - viewportWidth) > 0.001
            || lastResolvedColumnCount != columns
            || flowLayout.itemSize != itemSize
            || flowLayout.headerReferenceSize != headerSize
        if changed {
            lastViewportWidth = viewportWidth
            lastResolvedColumnCount = columns
            flowLayout.sectionInset = insets
            flowLayout.itemSize = itemSize
            flowLayout.headerReferenceSize = headerSize
            flowLayout.invalidateLayout()
        }
        return (viewportWidth > 0, changed)
    }

    private var hasUsableViewport: Bool { contentView.bounds.width > 0 }

    private func updateAccessibilityRole() {
        let role: NSAccessibility.Role = layoutSpec.kind == .list ? .list : .grid
        setAccessibilityRole(role)
        fluentSetDefaultAccessibilityLabel("Collection")
        collectionView.setAccessibilityRole(role)
        collectionView.fluentSetDefaultAccessibilityLabel("Collection")
    }

    private func nativeSnapshot() -> NSDiffableDataSourceSnapshot<AnyHashable, AnyHashable> {
        var native = NSDiffableDataSourceSnapshot<AnyHashable, AnyHashable>()
        for section in snapshot.sectionIdentifiers {
            let sectionID = AnyHashable(section)
            native.appendSections([sectionID])
            native.appendItems(snapshot.itemIdentifiers(inSection: section).map(AnyHashable.init), toSection: sectionID)
        }
        return native
    }

    private func applySnapshot(animatingDifferences: Bool) {
        let native = nativeSnapshot()
        availableIDs = Set(native.itemIdentifiers)
        snapshotApplicationCount += 1
        diffableDataSource.apply(
            native,
            animatingDifferences: animatingDifferences
        ) { [weak self] in
            self?.maybeRequestMoreItems()
        }
        applySelection()
        needsLayout = true
    }

    private func makeItem(
        in collectionView: NSCollectionView,
        at indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: fluentSectionedItemIdentifier, for: indexPath)
        if let host = item as? FluentSectionedCollectionItem {
            configureItem(host, at: indexPath, forceContent: true)
        }
        return item
    }

    private func configureItem(_ host: FluentSectionedCollectionItem, at indexPath: IndexPath, forceContent: Bool) {
        guard let itemID = itemID(at: indexPath), let content else { return }
        let version = contentVersion?(itemID)
        let updateContent = forceContent || version == nil || host.contentVersion != version
            || host.configuredItemID != AnyHashable(itemID)
        host.update(
            content: updateContent ? content(itemID) : nil,
            context: context,
            theme: theme,
            layoutKind: layoutSpec.kind,
            itemStyle: itemStyle,
            enabled: isItemEnabled(itemID),
            selected: collectionView.selectionIndexPaths.contains(indexPath),
            focused: indexPath == focusedIndexPath && isKeyboardFocusVisible,
            showsSelectionCheckmark: showsSelectionCheckmark,
            reduceMotion: context.reduceMotion,
            onAccessibilityPress: { [weak self] in self?.performAccessibilityPress(at: indexPath) ?? false }
        )
        host.contentVersion = version
        host.configuredItemID = AnyHashable(itemID)
        host.view.setAccessibilityLabel("Item \(indexPath.item + 1)")
    }

    private func refreshVisibleContent(force: Bool) {
        for item in collectionView.visibleItems() {
            guard let host = item as? FluentSectionedCollectionItem,
                  let indexPath = collectionView.indexPath(for: item) else { continue }
            configureItem(host, at: indexPath, forceContent: force)
        }
        if let header {
            for view in collectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader) {
                guard let host = view as? FluentSectionedCollectionHeader,
                      let section = host.sectionIndex,
                      snapshot.sectionIdentifiers.indices.contains(section) else { continue }
                host.update(content: header(snapshot.sectionIdentifiers[section]), context: context)
            }
        }
    }

    private func makeHeader(
        in collectionView: NSCollectionView,
        kind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> (NSView & NSCollectionViewElement)? {
        guard kind == NSCollectionView.elementKindSectionHeader,
              let header,
              snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return nil }
        let view = collectionView.makeSupplementaryView(
            ofKind: kind,
            withIdentifier: fluentSectionedHeaderIdentifier,
            for: indexPath
        )
        guard let host = view as? FluentSectionedCollectionHeader else { return nil }
        host.sectionIndex = indexPath.section
        host.update(content: header(snapshot.sectionIdentifiers[indexPath.section]), context: context)
        host.setAccessibilityRole(.group)
        host.setAccessibilityLabel("Section \(indexPath.section + 1)")
        return host
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
        let previousIndexPaths = collectionView.selectionIndexPaths
        var selectedIDs: Set<AnyHashable>
        switch selectionMode {
        case .none:
            selectedIDs = []
            if selection?.get() != nil { selection?.set(nil) }
            if selections?.get().isEmpty == false { selections?.set([]) }
        case .single:
            if let selected = selection?.get(), availableIDs.contains(selected) {
                selectedIDs = [selected]
            } else if let first = selections?.get().first(where: availableIDs.contains) {
                selectedIDs = [first]
                if selections?.get() != selectedIDs { selections?.set(selectedIDs) }
            } else {
                selectedIDs = []
                if selection?.get() != nil { selection?.set(nil) }
                if selections?.get().isEmpty == false { selections?.set([]) }
            }
        case .multiple, .extended:
            if let selections {
                selectedIDs = selections.get().intersection(availableIDs)
                if selections.get() != selectedIDs { selections.set(selectedIDs) }
            } else if let selected = selection?.get(), availableIDs.contains(selected) {
                selectedIDs = [selected]
            } else {
                selectedIDs = []
                if selection?.get() != nil { selection?.set(nil) }
            }
        }
        let indexPaths = Set(selectedIDs.compactMap { diffableDataSource.indexPath(for: $0) })
        collectionView.selectionIndexPaths = indexPaths
        let shouldAnimate = hasAppliedSelection
            && previousIndexPaths != indexPaths
            && window != nil
        hasAppliedSelection = true
        updateVisibleItemStates(animated: shouldAnimate)
    }

    private var isKeyboardFocusVisible: Bool {
        collectionView.window?.firstResponder === collectionView
            && FluentFocusVisibility.isKeyboardFocusVisible(for: collectionView)
    }

    private var showsSelectionCheckmark: Bool {
        switch selectionCheckmarkVisibility {
        case .visible: true
        case .hidden: false
        case .automatic: selectionMode == .multiple
        }
    }

    private func updateVisibleItemStates(animated: Bool) {
        for item in collectionView.visibleItems() {
            guard let host = item as? FluentSectionedCollectionItem,
                  let indexPath = collectionView.indexPath(for: item) else { continue }
            let selected = collectionView.selectionIndexPaths.contains(indexPath)
            host.setSelected(selected, animated: animated)
            host.setFocused(indexPath == focusedIndexPath && isKeyboardFocusVisible)
            host.setPressed(indexPath == pressedIndexPath)
            host.setShowsSelectionCheckmark(showsSelectionCheckmark)
        }
    }

    private func synchronizeSelection() {
        let selectedIDs = Set(collectionView.selectionIndexPaths.compactMap {
            itemID(at: $0).map(AnyHashable.init)
        })
        if selectionMode == .none {
            selection?.set(nil)
            selections?.set([])
        } else if let selections {
            selections.set(selectedIDs)
        } else {
            selection?.set(selectedIDs.first)
        }
        updateVisibleItemStates(animated: true)
        context.invalidate?()
    }

    private func commitSelection(_ indexPaths: Set<IndexPath>) {
        isApplyingSelection = true
        collectionView.selectionIndexPaths = indexPaths
        isApplyingSelection = false
        synchronizeSelection()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        shouldSelectItemsAt indexPaths: Set<IndexPath>
    ) -> Set<IndexPath> {
        Set(indexPaths.filter { indexPath in
            guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return false }
            let sectionID = snapshot.sectionIdentifiers[indexPath.section]
            let items = snapshot.itemIdentifiers(inSection: sectionID)
            return items.indices.contains(indexPath.item) && isItemEnabled(items[indexPath.item])
        })
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection else { return }
        focusedIndexPath = indexPaths.sorted(by: indexPathPrecedes).last ?? focusedIndexPath
        synchronizeSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection else { return }
        synchronizeSelection()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard onItemsReordered != nil, itemIsEnabled(at: indexPath) else { return nil }
        let writer = NSPasteboardItem()
        writer.setString("\(indexPath.section):\(indexPath.item)", forType: fluentCollectionDragType)
        return writer
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>
    ) {
        draggedIndexPaths = indexPaths
        for path in indexPaths {
            (collectionView.item(at: path) as? FluentSectionedCollectionItem)?.setReordering(true)
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard onItemsReordered != nil,
              isLocalDraggingSource(draggingInfo.draggingSource),
              !draggedIndexPaths.isEmpty else { return [] }
        proposedDropOperation.pointee = .before
        let proposed = proposedDropIndexPath.pointee as IndexPath
        updateReorderTarget(proposed)
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let onItemsReordered,
              snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return false }
        let movedIDs = draggedIndexPaths.sorted(by: indexPathPrecedes).compactMap(itemID(at:))
        guard !movedIDs.isEmpty else { return false }
        let destinationSection = snapshot.sectionIdentifiers[indexPath.section]
        var next = snapshot
        next.moveItems(movedIDs, toSection: destinationSection, at: indexPath.item)
        guard next != snapshot else {
            resetReorderVisuals()
            return false
        }
        snapshot = next
        applySnapshot(animatingDifferences: !context.reduceMotion)
        resetReorderVisuals()
        onItemsReordered(next)
        context.invalidate?()
        return true
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        resetReorderVisuals()
    }

    private func updateReorderTarget(_ indexPath: IndexPath?) {
        guard reorderTargetIndexPath != indexPath else { return }
        reorderTargetIndexPath = indexPath
        updateReorderInsertion(at: indexPath)
    }

    private func updateReorderInsertion(at indexPath: IndexPath?) {
        guard let indexPath,
              snapshot.sectionIdentifiers.indices.contains(indexPath.section) else {
            reorderInsertionLayer.opacity = 0
            return
        }
        let sectionID = snapshot.sectionIdentifiers[indexPath.section]
        let itemCount = snapshot.itemIdentifiers(inSection: sectionID).count
        let insertionIndex = min(max(indexPath.item, 0), itemCount)
        let thickness = max(2 / max(window?.backingScaleFactor ?? 2, 1), 1)
        let frame: NSRect?
        switch layoutSpec.kind {
        case .list:
            let referenceIndex = insertionIndex < itemCount ? insertionIndex : itemCount - 1
            guard referenceIndex >= 0,
                  let attributes = collectionView.layoutAttributesForItem(
                    at: IndexPath(item: referenceIndex, section: indexPath.section)
                  ) else {
                reorderInsertionLayer.opacity = 0
                return
            }
            let y = insertionIndex < itemCount
                ? attributes.frame.minY - layoutSpec.spacing / 2
                : attributes.frame.maxY + layoutSpec.spacing / 2
            frame = NSRect(
                x: flowLayout.sectionInset.left + 4,
                y: y - thickness / 2,
                width: max(collectionView.bounds.width
                    - flowLayout.sectionInset.left - flowLayout.sectionInset.right - 8, 0),
                height: thickness
            )
        case .adaptiveGrid:
            let isRTL = collectionView.userInterfaceLayoutDirection == .rightToLeft
            if insertionIndex < itemCount,
               let attributes = collectionView.layoutAttributesForItem(
                at: IndexPath(item: insertionIndex, section: indexPath.section)
               ) {
                let x = isRTL
                    ? attributes.frame.maxX + layoutSpec.spacing / 2
                    : attributes.frame.minX - layoutSpec.spacing / 2
                frame = NSRect(
                    x: x - thickness / 2,
                    y: attributes.frame.minY + 4,
                    width: thickness,
                    height: max(attributes.frame.height - 8, 0)
                )
            } else if itemCount > 0,
                      let attributes = collectionView.layoutAttributesForItem(
                        at: IndexPath(item: itemCount - 1, section: indexPath.section)
                      ) {
                let startsNewRow = itemCount % max(lastResolvedColumnCount, 1) == 0
                let x: CGFloat
                let y: CGFloat
                if startsNewRow {
                    x = isRTL
                        ? collectionView.bounds.maxX - flowLayout.sectionInset.right
                        : flowLayout.sectionInset.left
                    y = attributes.frame.maxY + layoutSpec.spacing + 4
                } else {
                    x = isRTL
                        ? attributes.frame.minX - layoutSpec.spacing / 2
                        : attributes.frame.maxX + layoutSpec.spacing / 2
                    y = attributes.frame.minY + 4
                }
                frame = NSRect(
                    x: x - thickness / 2,
                    y: y,
                    width: thickness,
                    height: max(layoutSpec.itemHeight - 8, 0)
                )
            } else {
                frame = nil
            }
        }
        guard let frame else {
            reorderInsertionLayer.opacity = 0
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        reorderInsertionLayer.backgroundColor = theme.accentFillDefault.cgColor
        reorderInsertionLayer.frame = frame.integral
        reorderInsertionLayer.opacity = 1
        CATransaction.commit()
    }

    private func isLocalDraggingSource(_ source: Any?) -> Bool {
        guard let sourceObject = source as AnyObject? else { return false }
        return sourceObject === self || sourceObject === collectionView
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        resetReorderVisuals()
        manualDragStarted = false
    }

    private func resetReorderVisuals() {
        for path in draggedIndexPaths {
            (collectionView.item(at: path) as? FluentSectionedCollectionItem)?.setReordering(false)
        }
        updateReorderTarget(nil)
        reorderInsertionLayer.opacity = 0
        draggedIndexPaths = []
    }

    private func updateIncrementalLoadingState() {
        let loading = incrementalLoading?.isLoading == true
        loadingIndicator.isHidden = !loading
        if loading { loadingIndicator.startAnimation(nil) } else { loadingIndicator.stopAnimation(nil) }
        DispatchQueue.main.async { [weak self] in self?.maybeRequestMoreItems() }
    }

    private func maybeRequestMoreItems() {
        guard let incrementalLoading,
              incrementalLoading.hasMoreItems,
              !incrementalLoading.isLoading,
              lastLoadRequestItemCount != snapshot.numberOfItems
                || lastLoadRequestRetryToken != incrementalLoading.retryToken else { return }
        if snapshot.numberOfItems == 0 {
            lastLoadRequestItemCount = 0
            lastLoadRequestRetryToken = incrementalLoading.retryToken
            incrementalLoading.loadMore()
            context.invalidate?()
            return
        }
        let lastVisibleIndex = collectionView.indexPathsForVisibleItems().compactMap { path -> Int? in
            itemID(at: path).flatMap(snapshot.indexOfItem)
        }.max()
        if let lastVisibleIndex {
            lastNearEndEvaluationItemCount = snapshot.numberOfItems
            lastViewportWasNearEnd = lastVisibleIndex
                >= snapshot.numberOfItems - incrementalLoading.threshold
        }
        guard lastNearEndEvaluationItemCount == snapshot.numberOfItems,
              lastViewportWasNearEnd else { return }
        lastLoadRequestItemCount = snapshot.numberOfItems
        lastLoadRequestRetryToken = incrementalLoading.retryToken
        incrementalLoading.loadMore()
        context.invalidate?()
    }

    private func installPointerEventMonitor() {
        pointerEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self,
                  event.window === self.collectionView.window else { return event }
            let point = self.collectionView.convert(event.locationInWindow, from: nil)
            let nextIndexPath = self.collectionView.bounds.contains(point)
                ? self.collectionView.indexPathForItem(at: point)
                : nil
            switch event.type {
            case .leftMouseDown:
                self.pointerDownPoint = point
                self.manualDragStarted = false
                if let nextIndexPath, self.itemIsEnabled(at: nextIndexPath) {
                    self.setPressedIndexPath(nextIndexPath)
                } else {
                    self.setPressedIndexPath(nil)
                }
            case .leftMouseDragged:
                if !self.manualDragStarted,
                   self.onItemsReordered != nil,
                   self.selectionMode == .multiple || self.selectionMode == .extended,
                   let pointerDownPoint = self.pointerDownPoint,
                   hypot(point.x - pointerDownPoint.x, point.y - pointerDownPoint.y) >= 4,
                   self.beginManualDrag(with: event) {
                    self.manualDragStarted = true
                    self.pendingClickSelectionUpdate = nil
                    self.setPressedIndexPath(nil)
                    break
                }
                self.setPressedIndexPath(
                    nextIndexPath == self.pressedIndexPath ? self.pressedIndexPath : nil
                )
            case .leftMouseUp:
                self.pointerDownPoint = nil
                if self.manualDragStarted {
                    self.manualDragStarted = false
                    self.setPressedIndexPath(nil)
                    break
                }
                if let pending = self.pendingClickSelectionUpdate {
                    self.pendingClickSelectionUpdate = nil
                    self.rangeAnchorIndexPath = pending.anchor
                    self.commitSelection(pending.selection)
                }
                let invokedIndexPath = self.pressedIndexPath == nextIndexPath
                    ? self.pressedIndexPath
                    : nil
                self.setPressedIndexPath(nil)
                if let invokedIndexPath { self.invokeItem(at: invokedIndexPath) }
            default:
                break
            }
            return event
        }
    }

    private func beginManualDrag(with event: NSEvent) -> Bool {
        guard let pressedIndexPath,
              let item = collectionView.item(at: pressedIndexPath) as? FluentSectionedCollectionItem else {
            return false
        }
        draggedIndexPaths = collectionView.selectionIndexPaths.contains(pressedIndexPath)
            ? collectionView.selectionIndexPaths
            : [pressedIndexPath]
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("FluentKit.collection", forType: fluentCollectionDragType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let frame = item.view.convert(item.view.bounds, to: self)
        let image = NSImage(size: item.view.bounds.size)
        image.lockFocus()
        if let representation = item.view.bitmapImageRepForCachingDisplay(in: item.view.bounds) {
            item.view.cacheDisplay(in: item.view.bounds, to: representation)
            representation.draw(in: item.view.bounds)
        }
        image.unlockFocus()
        draggingItem.setDraggingFrame(frame, contents: image)
        for path in draggedIndexPaths {
            (collectionView.item(at: path) as? FluentSectionedCollectionItem)?.setReordering(true)
        }
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        return true
    }

    private func itemIsEnabled(at indexPath: IndexPath) -> Bool {
        guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return false }
        let sectionID = snapshot.sectionIdentifiers[indexPath.section]
        let items = snapshot.itemIdentifiers(inSection: sectionID)
        return items.indices.contains(indexPath.item) && isItemEnabled(items[indexPath.item])
    }

    private func itemID(at indexPath: IndexPath) -> ItemID? {
        guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return nil }
        let sectionID = snapshot.sectionIdentifiers[indexPath.section]
        let items = snapshot.itemIdentifiers(inSection: sectionID)
        guard items.indices.contains(indexPath.item) else { return nil }
        return items[indexPath.item]
    }

    private func invokeItem(at indexPath: IndexPath) {
        guard let onItemInvoked,
              let itemID = itemID(at: indexPath),
              isItemEnabled(itemID) else { return }
        onItemInvoked(itemID)
        context.invalidate?()
    }

    private func performAccessibilityPress(at indexPath: IndexPath) -> Bool {
        guard itemIsEnabled(at: indexPath) else { return false }
        let previousFocus = focusedIndexPath
        focusedIndexPath = indexPath
        var handled = onItemInvoked != nil
        if selectionMode != .none {
            let update = fluentCollectionSelectionAfterClick(
                current: collectionView.selectionIndexPaths,
                clicked: indexPath,
                anchor: rangeAnchorIndexPath,
                previousFocus: previousFocus,
                mode: selectionMode,
                modifiers: [],
                orderedEnabledItems: orderedEnabledIndexPaths
            )
            rangeAnchorIndexPath = update.anchor
            commitSelection(update.selection)
            handled = true
        }
        invokeItem(at: indexPath)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        return handled
    }

    private func handleCollectionMouseDown(_ event: NSEvent) -> Bool {
        guard selectionMode == .multiple || selectionMode == .extended else { return false }
        let point = collectionView.convert(event.locationInWindow, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              itemIsEnabled(at: indexPath) else { return false }
        window?.makeFirstResponder(collectionView)
        let previousFocus = focusedIndexPath
        focusedIndexPath = indexPath
        let update = fluentCollectionSelectionAfterClick(
            current: collectionView.selectionIndexPaths,
            clicked: indexPath,
            anchor: rangeAnchorIndexPath,
            previousFocus: previousFocus,
            mode: selectionMode,
            modifiers: event.modifierFlags,
            orderedEnabledItems: orderedEnabledIndexPaths
        )
        let preservesDragGroup = onItemsReordered != nil
            && collectionView.selectionIndexPaths.contains(indexPath)
            && !event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control)
        if preservesDragGroup {
            pendingClickSelectionUpdate = update
        } else {
            pendingClickSelectionUpdate = nil
            rangeAnchorIndexPath = update.anchor
            commitSelection(update.selection)
        }
        return true
    }

    private var orderedEnabledIndexPaths: [IndexPath] {
        snapshot.sectionIdentifiers.enumerated().flatMap { sectionIndex, sectionID in
            snapshot.itemIdentifiers(inSection: sectionID).indices.map {
                IndexPath(item: $0, section: sectionIndex)
            }
        }.filter(itemIsEnabled)
    }

    private func handleCollectionKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: // Return / keypad Enter
            guard let indexPath = focusedIndexPath
                ?? collectionView.selectionIndexPaths.sorted(by: indexPathPrecedes).first else {
                return false
            }
            return activateItem(at: indexPath, with: event)
        case 49: // Space is the primary interaction gesture in WinUI.
            guard let indexPath = focusedIndexPath
                ?? collectionView.selectionIndexPaths.sorted(by: indexPathPrecedes).first else {
                return false
            }
            return activateItem(at: indexPath, with: event)
        case 0 where event.charactersIgnoringModifiers?.lowercased() == "a":
            guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control),
                  selectionMode == .multiple || selectionMode == .extended else { return false }
            let enabled = Set(orderedEnabledIndexPaths)
            guard !enabled.isEmpty else { return true }
            focusedIndexPath = focusedIndexPath ?? enabled.sorted(by: indexPathPrecedes).first
            rangeAnchorIndexPath = focusedIndexPath
            commitSelection(enabled)
            return true
        case 123, 124, 125, 126: // Left, right, down, up.
            guard let target = adjacentKeyboardTarget(for: event.keyCode) else { return false }
            return moveKeyboardFocus(to: target, with: event)
        case 116, 121: // Page Up / Page Down.
            guard let target = pageKeyboardTarget(forward: event.keyCode == 121) else { return false }
            return moveKeyboardFocus(to: target, with: event)
        case 115: // Home
            return moveKeyboardFocusToBoundary(first: true, with: event)
        case 119: // End
            return moveKeyboardFocusToBoundary(first: false, with: event)
        default:
            return false
        }
    }

    private func activateItem(at indexPath: IndexPath, with event: NSEvent) -> Bool {
        guard itemIsEnabled(at: indexPath) else { return false }
        var handled = onItemInvoked != nil
        if selectionMode != .none {
            let update = fluentCollectionSelectionAfterClick(
                current: collectionView.selectionIndexPaths,
                clicked: indexPath,
                anchor: rangeAnchorIndexPath,
                previousFocus: focusedIndexPath,
                mode: selectionMode,
                modifiers: event.modifierFlags,
                orderedEnabledItems: orderedEnabledIndexPaths
            )
            rangeAnchorIndexPath = update.anchor
            commitSelection(update.selection)
            handled = true
        }
        focusedIndexPath = indexPath
        invokeItem(at: indexPath)
        updateVisibleItemStates(animated: false)
        return handled
    }

    private func moveKeyboardFocusToBoundary(first: Bool, with event: NSEvent) -> Bool {
        let paths = orderedEnabledIndexPaths
        guard let target = first ? paths.first : paths.last else { return false }
        return moveKeyboardFocus(to: target, with: event)
    }

    private func moveKeyboardFocus(to target: IndexPath, with event: NSEvent) -> Bool {
        focusedIndexPath = target
        let update = fluentCollectionSelectionAfterKeyboardNavigation(
            current: collectionView.selectionIndexPaths,
            target: target,
            anchor: rangeAnchorIndexPath,
            mode: selectionMode,
            modifiers: event.modifierFlags,
            orderedEnabledItems: orderedEnabledIndexPaths
        )
        rangeAnchorIndexPath = update.anchor
        if update.selection != collectionView.selectionIndexPaths {
            commitSelection(update.selection)
        } else {
            updateVisibleItemStates(animated: false)
        }
        collectionView.scrollToItems(at: [target], scrollPosition: .nearestVerticalEdge)
        return true
    }

    private func adjacentKeyboardTarget(for keyCode: UInt16) -> IndexPath? {
        let enabled = orderedEnabledIndexPaths
        guard !enabled.isEmpty else { return nil }
        if layoutSpec.kind == .list, keyCode == 125 || keyCode == 126 {
            guard let current = focusedIndexPath ?? collectionView.selectionIndexPaths.sorted(by: indexPathPrecedes).first,
                  let index = enabled.firstIndex(of: current) else { return keyCode == 125 ? enabled.first : enabled.last }
            let next = index + (keyCode == 125 ? 1 : -1)
            return enabled.indices.contains(next) ? enabled[next] : current
        }
        collectionView.layoutSubtreeIfNeeded()
        guard let current = focusedIndexPath
            ?? collectionView.selectionIndexPaths.sorted(by: indexPathPrecedes).first,
              let currentAttributes = collectionView.layoutAttributesForItem(at: current) else {
            return keyCode == 123 || keyCode == 126 ? enabled.last : enabled.first
        }
        let origin = NSPoint(x: currentAttributes.frame.midX, y: currentAttributes.frame.midY)
        return enabled.compactMap { candidate -> (IndexPath, CGFloat, CGFloat)? in
            guard candidate != current,
                  let attributes = collectionView.layoutAttributesForItem(at: candidate) else { return nil }
            let center = NSPoint(x: attributes.frame.midX, y: attributes.frame.midY)
            let dx = center.x - origin.x
            let dy = center.y - origin.y
            let primary: CGFloat
            let cross: CGFloat
            switch keyCode {
            case 123 where dx < -0.5: primary = -dx; cross = abs(dy)
            case 124 where dx > 0.5: primary = dx; cross = abs(dy)
            case 125 where dy > 0.5: primary = dy; cross = abs(dx)
            case 126 where dy < -0.5: primary = -dy; cross = abs(dx)
            default: return nil
            }
            return (candidate, primary, cross)
        }.min { lhs, rhs in
            let lhsScore = lhs.1 + lhs.2 * 2
            let rhsScore = rhs.1 + rhs.2 * 2
            return abs(lhsScore - rhsScore) > 0.001
                ? lhsScore < rhsScore
                : indexPathPrecedes(lhs.0, rhs.0)
        }?.0
    }

    private func pageKeyboardTarget(forward: Bool) -> IndexPath? {
        let enabled = orderedEnabledIndexPaths
        guard !enabled.isEmpty else { return nil }
        let current = focusedIndexPath
            ?? collectionView.selectionIndexPaths.sorted(by: indexPathPrecedes).first
            ?? (forward ? enabled.first : enabled.last)
        guard let current, let index = enabled.firstIndex(of: current) else {
            return forward ? enabled.first : enabled.last
        }
        let rowsPerPage = max(Int(contentView.bounds.height / max(layoutSpec.itemHeight + layoutSpec.spacing, 1)), 1)
        let pageSize = rowsPerPage * max(lastResolvedColumnCount, 1)
        let targetIndex = min(max(index + (forward ? pageSize : -pageSize), 0), enabled.count - 1)
        return enabled[targetIndex]
    }

    private func indexPathPrecedes(_ lhs: IndexPath, _ rhs: IndexPath) -> Bool {
        lhs.section == rhs.section ? lhs.item < rhs.item : lhs.section < rhs.section
    }

    private func setPressedIndexPath(_ indexPath: IndexPath?) {
        guard pressedIndexPath != indexPath else { return }
        if let pressedIndexPath,
           let oldItem = collectionView.item(at: pressedIndexPath) as? FluentSectionedCollectionItem {
            oldItem.setPressed(false)
        }
        pressedIndexPath = indexPath
        if let indexPath,
           let newItem = collectionView.item(at: indexPath) as? FluentSectionedCollectionItem {
            newItem.setPressed(true)
        }
    }

    deinit {
        if let pointerEventMonitor { NSEvent.removeMonitor(pointerEventMonitor) }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        if let selectionObserverID { observedSelection?.removeObserver?(selectionObserverID) }
        if let selectionsObserverID { observedSelections?.removeObserver?(selectionsObserverID) }
    }
}

private final class FluentSectionedCollectionItem: NSCollectionViewItem {
    var contentVersion: AnyHashable?
    var configuredItemID: AnyHashable?
    private var cellView: FluentSectionedCollectionCell { view as! FluentSectionedCollectionCell }

    override func loadView() {
        view = FluentSectionedCollectionCell()
    }

    func update(
        content: FluentAnyView?,
        context: FluentRenderContext,
        theme: FluentTheme,
        layoutKind: FluentCollectionLayout.Kind,
        itemStyle: any FluentCollectionItemStyle,
        enabled: Bool,
        selected: Bool,
        focused: Bool,
        showsSelectionCheckmark: Bool,
        reduceMotion: Bool,
        onAccessibilityPress: @escaping () -> Bool
    ) {
        cellView.updateConfiguration(
            theme: theme,
            layoutKind: layoutKind,
            itemStyle: itemStyle,
            enabled: enabled,
            selected: selected,
            focused: focused,
            showsSelectionCheckmark: showsSelectionCheckmark,
            reduceMotion: reduceMotion,
            onAccessibilityPress: onAccessibilityPress
        )
        if let content { cellView.update(content: content, context: context) }
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        isSelected = selected
        cellView.setSelected(selected, animated: animated)
    }

    func setFocused(_ focused: Bool) { cellView.setFocused(focused) }
    func setPressed(_ pressed: Bool) { cellView.setPressed(pressed) }
    func setShowsSelectionCheckmark(_ visible: Bool) { cellView.setShowsSelectionCheckmark(visible) }
    func setReordering(_ reordering: Bool) { cellView.setReordering(reordering) }
    func setReorderTarget(_ targeted: Bool) { cellView.setReorderTarget(targeted) }

    override func prepareForReuse() {
        super.prepareForReuse()
        cellView.prepareForReuse()
    }
}

private final class FluentSectionedCollectionCell: NSView {
    private var contentView: NSView?
    private var contentConstraints: [NSLayoutConstraint] = []
    private let surfaceLayer = CALayer()
    private let gridOuterBorderLayer = CAShapeLayer()
    private let gridInnerBorderLayer = CAShapeLayer()
    private let selectionIndicatorLayer = CALayer()
    private let multiSelectSquareLayer = CALayer()
    private let multiSelectCheckLayer = CAShapeLayer()
    private let reorderHintLayer = CALayer()
    private let focusOuterLayer = CAShapeLayer()
    private let focusInnerLayer = CAShapeLayer()
    private let animationCoordinator = FluentAnimationCoordinator()
    private var pointerTrackingArea: NSTrackingArea?
    private var theme = FluentTheme.current
    private var layoutKind = FluentCollectionLayout.Kind.list
    private var itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle()
    private var enabled = true
    private var selected = false
    private var focused = false
    private var pointerOver = false
    private var pressed = false
    private var showsSelectionCheckmark = false
    private var reordering = false
    private var reorderTarget = false
    private var reduceMotion = false
    private var onAccessibilityPress: (() -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        surfaceLayer.name = "FluentKit.CollectionItem.Surface"
        surfaceLayer.zPosition = -1
        layer?.addSublayer(surfaceLayer)
        gridOuterBorderLayer.name = "FluentKit.CollectionItem.GridOuterBorder"
        gridOuterBorderLayer.fillRule = .evenOdd
        gridOuterBorderLayer.zPosition = 10
        layer?.addSublayer(gridOuterBorderLayer)
        gridInnerBorderLayer.name = "FluentKit.CollectionItem.GridInnerBorder"
        gridInnerBorderLayer.fillRule = .evenOdd
        gridInnerBorderLayer.zPosition = 11
        layer?.addSublayer(gridInnerBorderLayer)
        selectionIndicatorLayer.name = "FluentKit.CollectionItem.SelectionIndicator"
        selectionIndicatorLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        selectionIndicatorLayer.zPosition = 12
        layer?.addSublayer(selectionIndicatorLayer)
        multiSelectSquareLayer.name = "FluentKit.CollectionItem.MultiSelectSquare"
        multiSelectSquareLayer.zPosition = 14
        multiSelectSquareLayer.cornerCurve = .continuous
        multiSelectSquareLayer.opacity = 0
        layer?.addSublayer(multiSelectSquareLayer)
        multiSelectCheckLayer.name = "FluentKit.CollectionItem.MultiSelectCheck"
        multiSelectCheckLayer.zPosition = 15
        multiSelectCheckLayer.fillColor = nil
        multiSelectCheckLayer.lineCap = .round
        multiSelectCheckLayer.lineJoin = .round
        multiSelectCheckLayer.opacity = 0
        multiSelectCheckLayer.strokeEnd = 0
        layer?.addSublayer(multiSelectCheckLayer)
        reorderHintLayer.name = "FluentKit.CollectionItem.ReorderHint"
        reorderHintLayer.zPosition = 18
        reorderHintLayer.cornerRadius = 1
        reorderHintLayer.opacity = 0
        layer?.addSublayer(reorderHintLayer)
        focusOuterLayer.name = "FluentKit.CollectionItem.FocusOuter"
        focusOuterLayer.fillRule = .evenOdd
        focusOuterLayer.zPosition = 20
        layer?.addSublayer(focusOuterLayer)
        focusInnerLayer.name = "FluentKit.CollectionItem.FocusInner"
        focusInnerLayer.fillRule = .evenOdd
        focusInnerLayer.zPosition = 21
        layer?.addSublayer(focusInnerLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
        setAccessibilityEnabled(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        guard enabled else { return }
        pointerOver = true
        applyAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        pressed = false
        applyAppearance(animated: true)
    }

    override func layout() {
        super.layout()
        updateLayerGeometry(for: resolvedAppearance())
    }

    override func accessibilityPerformPress() -> Bool {
        onAccessibilityPress?() ?? false
    }

    func updateConfiguration(
        theme: FluentTheme,
        layoutKind: FluentCollectionLayout.Kind,
        itemStyle: any FluentCollectionItemStyle,
        enabled: Bool,
        selected: Bool,
        focused: Bool,
        showsSelectionCheckmark: Bool,
        reduceMotion: Bool,
        onAccessibilityPress: @escaping () -> Bool
    ) {
        let layoutChanged = self.layoutKind != layoutKind
        self.theme = theme
        self.layoutKind = layoutKind
        self.itemStyle = itemStyle
        self.enabled = enabled
        self.selected = selected
        self.focused = focused
        self.showsSelectionCheckmark = showsSelectionCheckmark
        self.reduceMotion = reduceMotion
        self.onAccessibilityPress = onAccessibilityPress
        animationCoordinator.reduceMotion = reduceMotion
        userInterfaceLayoutDirection = superview?.userInterfaceLayoutDirection ?? userInterfaceLayoutDirection
        if !enabled {
            pointerOver = false
            pressed = false
        }
        setAccessibilityEnabled(enabled)
        setAccessibilitySelected(selected)
        setAccessibilityRole(layoutKind == .list ? .row : .cell)
        applyAppearance(animated: false)
        if layoutChanged { installContentConstraints() }
    }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        if let contentView, content._update(contentView, in: context) {
            contentView.alphaValue = resolvedAppearance().contentOpacity
            installContentConstraints()
            needsLayout = true
            return
        }
        contentView?.removeFromSuperview()
        let mounted = content._mount(in: context)
        contentView = mounted
        mounted.alphaValue = resolvedAppearance().contentOpacity
        addSubview(mounted)
        mounted.translatesAutoresizingMaskIntoConstraints = false
        installContentConstraints()
        needsLayout = true
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        guard self.selected != selected else { return }
        self.selected = selected
        setAccessibilitySelected(selected)
        applyAppearance(animated: animated, selectionChanged: true)
    }

    func setFocused(_ focused: Bool) {
        guard self.focused != focused else { return }
        self.focused = focused
        applyAppearance(animated: false)
    }

    func setPressed(_ pressed: Bool) {
        let next = enabled && pressed
        guard self.pressed != next else { return }
        self.pressed = next
        applyAppearance(animated: true, pressedChanged: true)
    }

    func setShowsSelectionCheckmark(_ visible: Bool) {
        guard showsSelectionCheckmark != visible else { return }
        showsSelectionCheckmark = visible
        applyAppearance(animated: true)
    }

    func setReordering(_ reordering: Bool) {
        guard self.reordering != reordering else { return }
        self.reordering = reordering
        applyReorderAppearance()
    }

    func setReorderTarget(_ targeted: Bool) {
        guard reorderTarget != targeted else { return }
        reorderTarget = targeted
        applyReorderAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pointerOver = false
        pressed = false
        focused = false
        selected = false
        showsSelectionCheckmark = false
        reordering = false
        reorderTarget = false
        onAccessibilityPress = nil
        animationCoordinator.cancelAll(on: [surfaceLayer, selectionIndicatorLayer, multiSelectSquareLayer, multiSelectCheckLayer])
        applyAppearance(animated: false)
        applyReorderAppearance()
    }

    private var controlState: FluentControlState {
        if !enabled { return .disabled }
        if pressed { return .pressed }
        if pointerOver { return .pointerOver }
        if focused { return .focused }
        return .normal
    }

    private func resolvedAppearance() -> FluentCollectionItemAppearance {
        itemStyle.appearance(
            for: FluentCollectionItemStyleConfiguration(
                layoutKind: layoutKind,
                controlState: controlState,
                isSelected: selected,
                isEnabled: enabled,
                isFocused: focused,
                theme: theme
            )
        )
    }

    private func applyAppearance(
        animated: Bool,
        selectionChanged: Bool = false,
        pressedChanged: Bool = false
    ) {
        let appearance = resolvedAppearance()
        animationCoordinator.reduceMotion = reduceMotion
        let usesMotion = animated && window != nil
        let previousBackground = (surfaceLayer.presentation() ?? surfaceLayer).backgroundColor
        let previousIndicatorOpacity = (selectionIndicatorLayer.presentation() ?? selectionIndicatorLayer).opacity
        let previousIndicatorScale = selectionIndicatorLayer.presentation()?.transform.m22
            ?? selectionIndicatorLayer.transform.m22
        let previousMarkerOpacity = (multiSelectSquareLayer.presentation()
            ?? multiSelectSquareLayer).opacity
        let previousCheckOpacity = (multiSelectCheckLayer.presentation()
            ?? multiSelectCheckLayer).opacity
        let previousCheckStrokeEnd = (multiSelectCheckLayer.presentation()
            ?? multiSelectCheckLayer).strokeEnd
        let indicatorVisible = layoutKind == .list && selected
        let targetIndicatorOpacity: Float = indicatorVisible ? 1 : 0
        let targetMarkerOpacity: Float = showsSelectionCheckmark ? 1 : 0
        let targetCheckOpacity: Float = showsSelectionCheckmark && selected ? 1 : 0
        let targetCheckStrokeEnd: CGFloat = showsSelectionCheckmark && selected ? 1 : 0
        let targetScale = pressed && selected ? appearance.selectionIndicatorPressedScale : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.backgroundColor = appearance.backgroundColor.cgColor
        surfaceLayer.cornerRadius = appearance.cornerRadius
        surfaceLayer.cornerCurve = .continuous
        alphaValue = appearance.containerOpacity
        contentView?.alphaValue = appearance.contentOpacity
        selectionIndicatorLayer.backgroundColor = appearance.selectionIndicatorColor.cgColor
        selectionIndicatorLayer.cornerRadius = appearance.selectionIndicatorSize.width / 2
        selectionIndicatorLayer.cornerCurve = .continuous
        selectionIndicatorLayer.opacity = targetIndicatorOpacity
        selectionIndicatorLayer.setAffineTransform(CGAffineTransform(scaleX: 1, y: targetScale))
        multiSelectSquareLayer.backgroundColor = (selected
            ? appearance.selectionIndicatorColor
            : theme.controlOnImageFillDefault).cgColor
        multiSelectSquareLayer.borderColor = (selected
            ? appearance.selectionIndicatorColor
            : theme.controlStrokeStrong).cgColor
        multiSelectSquareLayer.borderWidth = 1
        multiSelectSquareLayer.opacity = targetMarkerOpacity
        multiSelectCheckLayer.strokeColor = theme.textOnAccent.cgColor
        multiSelectCheckLayer.opacity = targetCheckOpacity
        multiSelectCheckLayer.strokeEnd = targetCheckStrokeEnd
        reorderHintLayer.backgroundColor = appearance.selectionIndicatorColor.cgColor
        CATransaction.commit()
        updateLayerGeometry(for: appearance)
        installContentConstraints(appearance: appearance)

        animationCoordinator.animateState(
            [
                FluentLayerAnimationChange(
                    layer: surfaceLayer,
                    key: "fluent.collectionItem.background",
                    keyPath: "backgroundColor",
                    fromValue: previousBackground,
                    toValue: appearance.backgroundColor.cgColor
                ) { [surfaceLayer] in
                    surfaceLayer.backgroundColor = appearance.backgroundColor.cgColor
                }
            ],
            motion: FluentMotion.controlFaster,
            animated: usesMotion
        )

        animationCoordinator.animateState(
            [
                FluentLayerAnimationChange(
                    layer: multiSelectSquareLayer,
                    key: "fluent.collectionItem.multiSelect.opacity",
                    keyPath: "opacity",
                    fromValue: previousMarkerOpacity,
                    toValue: targetMarkerOpacity
                ) { [multiSelectSquareLayer] in
                    multiSelectSquareLayer.opacity = targetMarkerOpacity
                }
            ],
            motion: FluentMotion.controlFast,
            animated: usesMotion
        )
        if selectionChanged || previousCheckOpacity != targetCheckOpacity {
            let checkMotion = selected ? FluentMotion.checkBoxGlyphOn : FluentMotion.checkBoxGlyphOff
            animationCoordinator.animateState(
                [
                    FluentLayerAnimationChange(
                        layer: multiSelectCheckLayer,
                        key: "fluent.collectionItem.multiSelect.check.opacity",
                        keyPath: "opacity",
                        fromValue: previousCheckOpacity,
                        toValue: targetCheckOpacity
                    ) { [multiSelectCheckLayer] in
                        multiSelectCheckLayer.opacity = targetCheckOpacity
                    },
                    FluentLayerAnimationChange(
                        layer: multiSelectCheckLayer,
                        key: "fluent.collectionItem.multiSelect.check.strokeEnd",
                        keyPath: "strokeEnd",
                        fromValue: previousCheckStrokeEnd,
                        toValue: targetCheckStrokeEnd
                    ) { [multiSelectCheckLayer] in
                        multiSelectCheckLayer.strokeEnd = targetCheckStrokeEnd
                    }
                ],
                motion: checkMotion,
                animated: usesMotion
            )
        }

        guard layoutKind == .list else {
            animationCoordinator.cancel(
                layer: selectionIndicatorLayer,
                key: "fluent.collectionItem.indicator.opacity"
            )
            animationCoordinator.cancel(
                layer: selectionIndicatorLayer,
                key: "fluent.collectionItem.indicator.scale"
            )
            return
        }
        if selectionChanged {
            animationCoordinator.animateState(
                [
                    FluentLayerAnimationChange(
                        layer: selectionIndicatorLayer,
                        key: "fluent.collectionItem.indicator.opacity",
                        keyPath: "opacity",
                        fromValue: previousIndicatorOpacity,
                        toValue: targetIndicatorOpacity
                    ) { [selectionIndicatorLayer] in
                        selectionIndicatorLayer.opacity = targetIndicatorOpacity
                    }
                ],
                motion: FluentMotion.collectionSelectionOpacity,
                animated: usesMotion
            )
            if selected {
                animationCoordinator.animateState(
                    [
                        FluentLayerAnimationChange(
                            layer: selectionIndicatorLayer,
                            key: "fluent.collectionItem.indicator.scale",
                            keyPath: "transform.scale.y",
                            fromValue: 0,
                            toValue: targetScale
                        ) { [selectionIndicatorLayer] in
                            selectionIndicatorLayer.setAffineTransform(
                                CGAffineTransform(scaleX: 1, y: targetScale)
                            )
                        }
                    ],
                    motion: FluentMotion.collectionSelectionReveal,
                    animated: usesMotion
                )
            } else {
                animationCoordinator.cancel(
                    layer: selectionIndicatorLayer,
                    key: "fluent.collectionItem.indicator.scale"
                )
            }
        } else if pressedChanged, selected {
            animationCoordinator.animateState(
                [
                    FluentLayerAnimationChange(
                        layer: selectionIndicatorLayer,
                        key: "fluent.collectionItem.indicator.scale",
                        keyPath: "transform.scale.y",
                        fromValue: previousIndicatorScale,
                        toValue: targetScale
                    ) { [selectionIndicatorLayer] in
                        selectionIndicatorLayer.setAffineTransform(
                            CGAffineTransform(scaleX: 1, y: targetScale)
                        )
                    }
                ],
                motion: FluentMotion.collectionSelectionPress,
                animated: usesMotion
            )
        }
    }

    private func applyReorderAppearance() {
        let targetOpacity: Float = reorderTarget ? 0.5 : (reordering ? 0.8 : 1)
        let targetScale: CGFloat = reorderTarget ? 0.95 : 1
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.2)
        layer?.opacity = targetOpacity
        layer?.setAffineTransform(CGAffineTransform(scaleX: targetScale, y: targetScale))
        reorderHintLayer.opacity = reorderTarget ? 1 : 0
        CATransaction.commit()
    }

    private func installContentConstraints(appearance: FluentCollectionItemAppearance? = nil) {
        guard let contentView else { return }
        NSLayoutConstraint.deactivate(contentConstraints)
        let insets = (appearance ?? resolvedAppearance()).contentInsets
        let trailing = contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right)
        let bottom = contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        // WinUI clamps the available content size at zero when padding consumes the slot.
        // Keep the leading/top inset, and allow the trailing/bottom inset to yield before
        // requesting a negative content size from AppKit.
        trailing.priority = .init(999)
        bottom.priority = .init(999)
        contentConstraints = [
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            trailing,
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            bottom,
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    private func updateLayerGeometry(for appearance: FluentCollectionItemAppearance) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = bounds
        for visualLayer in [gridOuterBorderLayer, gridInnerBorderLayer, focusOuterLayer, focusInnerLayer] {
            visualLayer.frame = bounds
            visualLayer.contentsScale = scale
            visualLayer.strokeColor = nil
        }

        gridOuterBorderLayer.path = ringPath(
            outer: bounds,
            width: appearance.outerBorderWidth,
            radius: appearance.cornerRadius
        )
        gridOuterBorderLayer.fillColor = appearance.outerBorderColor.cgColor
        gridOuterBorderLayer.isHidden = layoutKind != .adaptiveGrid || appearance.outerBorderWidth <= 0

        let innerOuter = bounds.insetBy(
            dx: appearance.outerBorderWidth,
            dy: appearance.outerBorderWidth
        )
        gridInnerBorderLayer.path = ringPath(
            outer: innerOuter,
            width: appearance.innerBorderWidth,
            radius: max(appearance.cornerRadius - appearance.outerBorderWidth, 0)
        )
        gridInnerBorderLayer.fillColor = appearance.innerBorderColor.cgColor
        gridInnerBorderLayer.isHidden = layoutKind != .adaptiveGrid || appearance.innerBorderWidth <= 0

        let indicatorHeight = min(appearance.selectionIndicatorSize.height, bounds.height)
        let indicatorX = userInterfaceLayoutDirection == .rightToLeft
            ? bounds.maxX - appearance.selectionIndicatorLeadingMargin - appearance.selectionIndicatorSize.width
            : bounds.minX + appearance.selectionIndicatorLeadingMargin
        selectionIndicatorLayer.frame = NSRect(
            x: indicatorX,
            y: bounds.midY - indicatorHeight / 2,
            width: appearance.selectionIndicatorSize.width,
            height: indicatorHeight
        )
        selectionIndicatorLayer.isHidden = layoutKind != .list

        let checkSize = CGFloat(20)
        let checkFrame = NSRect(
            x: userInterfaceLayoutDirection == .rightToLeft ? 4 : bounds.maxX - checkSize - 4,
            y: bounds.maxY - checkSize + 2,
            width: checkSize,
            height: checkSize
        )
        multiSelectSquareLayer.frame = checkFrame
        multiSelectSquareLayer.cornerRadius = 4
        multiSelectCheckLayer.frame = checkFrame
        multiSelectCheckLayer.contentsScale = scale
        multiSelectCheckLayer.lineWidth = 1.75
        let checkPath = CGMutablePath()
        checkPath.move(to: CGPoint(x: 5, y: 10))
        checkPath.addLine(to: CGPoint(x: 8.5, y: 6.5))
        checkPath.addLine(to: CGPoint(x: 15, y: 14))
        multiSelectCheckLayer.path = checkPath

        if layoutKind == .list {
            reorderHintLayer.frame = NSRect(x: 4, y: bounds.maxY - 2, width: max(bounds.width - 8, 0), height: 2)
        } else {
            reorderHintLayer.frame = NSRect(x: bounds.minX, y: 4, width: 2, height: max(bounds.height - 8, 0))
        }

        focusOuterLayer.path = ringPath(outer: bounds, width: 2, radius: appearance.cornerRadius)
        focusOuterLayer.fillColor = appearance.focusOuterColor.cgColor
        focusOuterLayer.isHidden = !focused
        let focusInnerRect = bounds.insetBy(dx: 2, dy: 2)
        focusInnerLayer.path = ringPath(
            outer: focusInnerRect,
            width: 1,
            radius: max(appearance.cornerRadius - 2, 0)
        )
        focusInnerLayer.fillColor = appearance.focusInnerColor.cgColor
        focusInnerLayer.isHidden = !focused
        CATransaction.commit()
    }

    private func ringPath(outer: CGRect, width: CGFloat, radius: CGFloat) -> CGPath? {
        guard width > 0, outer.width > 0, outer.height > 0 else { return nil }
        let path = CGMutablePath()
        path.addRoundedRect(in: outer, cornerWidth: radius, cornerHeight: radius)
        let inner = outer.insetBy(dx: width, dy: width)
        if inner.width > 0, inner.height > 0 {
            path.addRoundedRect(
                in: inner,
                cornerWidth: max(radius - width, 0),
                cornerHeight: max(radius - width, 0)
            )
        }
        return path
    }
}

private final class FluentSectionedCollectionHeader: NSView, NSCollectionViewElement {
    var sectionIndex: Int?
    private var contentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        if let contentView, content._update(contentView, in: context) { return }
        contentView?.removeFromSuperview()
        let mounted = content._mount(in: context)
        contentView = mounted
        addSubview(mounted)
        mounted.translatesAutoresizingMaskIntoConstraints = false
        mounted.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mounted.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            mounted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            mounted.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            mounted.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
