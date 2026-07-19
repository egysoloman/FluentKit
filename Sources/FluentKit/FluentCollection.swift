import AppKit

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
        rowHeight: CGFloat = 44,
        spacing: CGFloat = 2,
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
    private let selection: FluentCollectionIdentityBinding?
    private let selections: FluentCollectionIdentitySetBinding?
    private let content: (ItemID) -> FluentAnyView
    private let header: ((SectionID) -> FluentAnyView)?

    public init<Content: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionID: FluentBinding<ItemID?>? = nil,
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = selectionID.map(FluentCollectionIdentityBinding.init)
        selections = nil
        self.content = { FluentAnyView(content($0)) }
        header = nil
    }

    public init<Content: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionIDs: FluentBinding<Set<ItemID>>,
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = nil
        selections = FluentCollectionIdentitySetBinding(selectionIDs)
        self.content = { FluentAnyView(content($0)) }
        header = nil
    }

    public init<Content: FluentView, Header: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionID: FluentBinding<ItemID?>? = nil,
        @FluentViewBuilder content: @escaping (ItemID) -> Content,
        @FluentViewBuilder header: @escaping (SectionID) -> Header
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = selectionID.map(FluentCollectionIdentityBinding.init)
        selections = nil
        self.content = { FluentAnyView(content($0)) }
        self.header = { FluentAnyView(header($0)) }
    }

    public init<Content: FluentView, Header: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionIDs: FluentBinding<Set<ItemID>>,
        @FluentViewBuilder content: @escaping (ItemID) -> Content,
        @FluentViewBuilder header: @escaping (SectionID) -> Header
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = nil
        selections = FluentCollectionIdentitySetBinding(selectionIDs)
        self.content = { FluentAnyView(content($0)) }
        self.header = { FluentAnyView(header($0)) }
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentSectionedCollectionView<SectionID, ItemID>(theme: context.theme)
        view.setData(
            snapshot: snapshot,
            layout: layout,
            selection: selection,
            selections: selections,
            content: content,
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
            selection: selection,
            selections: selections,
            content: content,
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

private final class FluentSectionedCollectionView<SectionID: Hashable, ItemID: Hashable>:
    NSScrollView, NSCollectionViewDelegate {
    // Keep the initial flow-layout geometry valid while the scroll host is still being mounted.
    private let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private let flowLayout = NSCollectionViewFlowLayout()
    private var snapshot = FluentCollectionSnapshot<SectionID, ItemID>()
    private var layoutSpec = FluentCollectionLayout.list()
    private var selection: FluentCollectionIdentityBinding?
    private var selections: FluentCollectionIdentitySetBinding?
    private var observedSelection: FluentCollectionIdentityBinding?
    private var observedSelections: FluentCollectionIdentitySetBinding?
    private var selectionObserverID: UUID?
    private var selectionsObserverID: UUID?
    private var content: ((ItemID) -> FluentAnyView)?
    private var header: ((SectionID) -> FluentAnyView)?
    private var context = FluentRenderContext()
    private var theme: FluentTheme
    private var isApplyingSelection = false
    private var needsInitialSnapshot = false
    private var diffableDataSource: NSCollectionViewDiffableDataSource<AnyHashable, AnyHashable>!

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
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            FluentSectionedCollectionItem.self,
            forItemWithIdentifier: fluentSectionedItemIdentifier
        )
        collectionView.register(
            FluentSectionedCollectionHeader.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: fluentSectionedHeaderIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        documentView = collectionView
        collectionView.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true

        diffableDataSource = NSCollectionViewDiffableDataSource<AnyHashable, AnyHashable>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identifier in
            self?.makeItem(in: collectionView, at: indexPath, identifier: identifier)
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
        updateAccessibilityRole()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let hasUsableViewport = updateLayoutMetrics()
        if hasUsableViewport, needsInitialSnapshot {
            needsInitialSnapshot = false
            applySnapshot(reloadingContent: false, animatingDifferences: false)
        }
    }

    func setData(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout,
        selection: FluentCollectionIdentityBinding?,
        selections: FluentCollectionIdentitySetBinding?,
        content: @escaping (ItemID) -> FluentAnyView,
        header: ((SectionID) -> FluentAnyView)?,
        context: FluentRenderContext
    ) {
        self.snapshot = snapshot
        layoutSpec = layout
        self.selection = selection
        self.selections = selections
        self.content = content
        self.header = header
        self.context = context
        theme = context.theme
        collectionView.allowsMultipleSelection = selections != nil
        configureLayout()
        installSelectionObservers()
        if hasUsableViewport {
            needsInitialSnapshot = false
            applySnapshot(reloadingContent: false, animatingDifferences: false)
        } else {
            needsInitialSnapshot = true
        }
    }

    func update(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout,
        selection: FluentCollectionIdentityBinding?,
        selections: FluentCollectionIdentitySetBinding?,
        content: @escaping (ItemID) -> FluentAnyView,
        header: ((SectionID) -> FluentAnyView)?,
        context: FluentRenderContext
    ) {
        let structureChanged = self.snapshot != snapshot
        let layoutChanged = layoutSpec != layout
        let headerVisibilityChanged = (self.header == nil) != (header == nil)
        self.snapshot = snapshot
        layoutSpec = layout
        self.selection = selection
        self.selections = selections
        self.content = content
        self.header = header
        self.context = context
        theme = context.theme
        collectionView.allowsMultipleSelection = selections != nil
        if layoutChanged || headerVisibilityChanged { configureLayout() }
        installSelectionObservers()
        guard hasUsableViewport else {
            needsInitialSnapshot = true
            needsLayout = true
            return
        }
        needsInitialSnapshot = false
        applySnapshot(reloadingContent: !structureChanged, animatingDifferences: structureChanged && window != nil)
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

    @discardableResult
    private func updateLayoutMetrics() -> Bool {
        let insets = flowLayout.sectionInset
        let viewportWidth = contentView.bounds.width
        guard viewportWidth > insets.left + insets.right + 1 else { return false }
        let availableWidth = viewportWidth - insets.left - insets.right
        let itemWidth: CGFloat
        switch layoutSpec.kind {
        case .list:
            itemWidth = availableWidth
        case .adaptiveGrid:
            let columns = max(Int((availableWidth + layoutSpec.spacing)
                / (layoutSpec.minimumItemWidth + layoutSpec.spacing)), 1)
            itemWidth = (availableWidth - CGFloat(columns - 1) * layoutSpec.spacing) / CGFloat(columns)
        }
        let itemSize = NSSize(width: floor(itemWidth), height: layoutSpec.itemHeight)
        if flowLayout.itemSize != itemSize {
            flowLayout.itemSize = itemSize
            flowLayout.invalidateLayout()
        }
        return true
    }

    private var hasUsableViewport: Bool {
        let insets = flowLayout.sectionInset
        return contentView.bounds.width > insets.left + insets.right + 1
    }

    private func updateAccessibilityRole() {
        let role: NSAccessibility.Role = layoutSpec.kind == .list ? .list : .grid
        setAccessibilityRole(role)
        setAccessibilityLabel("Collection")
        collectionView.setAccessibilityRole(role)
        collectionView.setAccessibilityLabel("Collection")
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

    private func applySnapshot(reloadingContent: Bool, animatingDifferences: Bool) {
        var native = nativeSnapshot()
        if reloadingContent {
            let existingSections = Set(diffableDataSource.snapshot().sectionIdentifiers)
            native.reloadSections(native.sectionIdentifiers.filter(existingSections.contains))
        }
        diffableDataSource.apply(native, animatingDifferences: animatingDifferences)
        applySelection()
        needsLayout = true
    }

    private func makeItem(
        in collectionView: NSCollectionView,
        at indexPath: IndexPath,
        identifier: AnyHashable
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: fluentSectionedItemIdentifier, for: indexPath)
        guard let host = item as? FluentSectionedCollectionItem,
              let itemID = identifier.base as? ItemID,
              let content else { return item }
        host.update(
            content: content(itemID),
            context: context,
            theme: theme,
            selected: collectionView.selectionIndexPaths.contains(indexPath)
        )
        host.view.setAccessibilityLabel("Item \(indexPath.item + 1)")
        return host
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
        let availableIDs = Set(snapshot.itemIdentifiers.map(AnyHashable.init))
        let selectedIDs: Set<AnyHashable>
        if let selections {
            selectedIDs = selections.get().intersection(availableIDs)
            if selections.get() != selectedIDs { selections.set(selectedIDs) }
        } else if let selected = selection?.get(), availableIDs.contains(selected) {
            selectedIDs = [selected]
        } else {
            selectedIDs = []
            if selection?.get() != nil { selection?.set(nil) }
        }
        let indexPaths = Set(selectedIDs.compactMap { diffableDataSource.indexPath(for: $0) })
        collectionView.selectionIndexPaths = indexPaths
        updateVisibleSelection()
    }

    private func updateVisibleSelection() {
        for item in collectionView.visibleItems() {
            guard let host = item as? FluentSectionedCollectionItem,
                  let indexPath = collectionView.indexPath(for: item) else { continue }
            host.setSelected(collectionView.selectionIndexPaths.contains(indexPath), theme: theme)
        }
    }

    private func synchronizeSelection() {
        let selectedIDs = Set(collectionView.selectionIndexPaths.compactMap {
            diffableDataSource.itemIdentifier(for: $0)
        })
        if let selections {
            selections.set(selectedIDs)
        } else {
            selection?.set(selectedIDs.first)
        }
        updateVisibleSelection()
        context.invalidate?()
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection else { return }
        synchronizeSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection else { return }
        synchronizeSelection()
    }

    deinit {
        if let selectionObserverID { observedSelection?.removeObserver?(selectionObserverID) }
        if let selectionsObserverID { observedSelections?.removeObserver?(selectionsObserverID) }
    }
}

private final class FluentSectionedCollectionItem: NSCollectionViewItem {
    private var cellView: FluentSectionedCollectionCell { view as! FluentSectionedCollectionCell }

    override func loadView() {
        view = FluentSectionedCollectionCell()
    }

    func update(content: FluentAnyView, context: FluentRenderContext, theme: FluentTheme, selected: Bool) {
        cellView.update(content: content, context: context)
        setSelected(selected, theme: theme)
    }

    func setSelected(_ selected: Bool, theme: FluentTheme) {
        isSelected = selected
        cellView.updateSelection(selected, theme: theme)
    }
}

private final class FluentSectionedCollectionCell: NSView {
    private var contentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
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
            mounted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            mounted.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            mounted.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mounted.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func updateSelection(_ selected: Bool, theme: FluentTheme) {
        layer?.backgroundColor = selected
            ? theme.accent.withAlphaComponent(0.16).cgColor
            : theme.controlFill.withAlphaComponent(0.36).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (selected ? theme.accent : theme.controlStroke)
            .withAlphaComponent(selected ? 0.6 : 0.45).cgColor
        setAccessibilitySelected(selected)
    }
}

private final class FluentSectionedCollectionHeader: NSView, NSCollectionViewElement {
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
        NSLayoutConstraint.activate([
            mounted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            mounted.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            mounted.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
