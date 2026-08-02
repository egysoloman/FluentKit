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
    private let selection: FluentCollectionIdentityBinding?
    private let selections: FluentCollectionIdentitySetBinding?
    private let isEnabled: (ItemID) -> Bool
    private let itemStyle: any FluentCollectionItemStyle
    private let content: (ItemID) -> FluentAnyView
    private let header: ((SectionID) -> FluentAnyView)?

    public init<Content: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionID: FluentBinding<ItemID?>? = nil,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = selectionID.map(FluentCollectionIdentityBinding.init)
        selections = nil
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        header = nil
    }

    public init<Content: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionIDs: FluentBinding<Set<ItemID>>,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = nil
        selections = FluentCollectionIdentitySetBinding(selectionIDs)
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        header = nil
    }

    public init<Content: FluentView, Header: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionID: FluentBinding<ItemID?>? = nil,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content,
        @FluentViewBuilder header: @escaping (SectionID) -> Header
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = selectionID.map(FluentCollectionIdentityBinding.init)
        selections = nil
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = { FluentAnyView(content($0)) }
        self.header = { FluentAnyView(header($0)) }
    }

    public init<Content: FluentView, Header: FluentView>(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout = .list(),
        selectionIDs: FluentBinding<Set<ItemID>>,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content,
        @FluentViewBuilder header: @escaping (SectionID) -> Header
    ) {
        self.snapshot = snapshot
        self.layout = layout
        selection = nil
        selections = FluentCollectionIdentitySetBinding(selectionIDs)
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
            selection: selection,
            selections: selections,
            isEnabled: isEnabled,
            itemStyle: itemStyle,
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
            isEnabled: isEnabled,
            itemStyle: itemStyle,
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

private final class FluentCollectionNativeView: NSCollectionView {
    var onFocusVisibilityChange: (() -> Void)?

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
        super.keyDown(with: event)
        onFocusVisibilityChange?()
    }

    override func mouseDown(with event: NSEvent) {
        FluentFocusVisibility.markPointerInteraction(in: window)
        onFocusVisibilityChange?()
        super.mouseDown(with: event)
        onFocusVisibilityChange?()
    }
}

private final class FluentSectionedCollectionView<SectionID: Hashable, ItemID: Hashable>:
    NSScrollView, NSCollectionViewDelegate, FluentFillWidthProviding {
    // Keep the initial flow-layout geometry valid while the scroll host is still being mounted.
    private let collectionView = FluentCollectionNativeView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private let flowLayout = NSCollectionViewFlowLayout()
    private var snapshot = FluentCollectionSnapshot<SectionID, ItemID>()
    private var layoutSpec = FluentCollectionLayout.list()
    private var selection: FluentCollectionIdentityBinding?
    private var selections: FluentCollectionIdentitySetBinding?
    private var isItemEnabled: (ItemID) -> Bool = { _ in true }
    private var itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle()
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
    private var hasAppliedSelection = false
    private var pressedIndexPath: IndexPath?
    private var pointerEventMonitor: Any?
    private var lastViewportWidth: CGFloat = -1
    private var lastResolvedColumnCount = 0
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
        collectionView.focusRingType = .none
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
        installPointerEventMonitor()
        updateAccessibilityRole()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let metrics = updateLayoutMetrics()
        if metrics.changed {
            collectionView.needsLayout = true
            collectionView.visibleItems().forEach { $0.view.needsLayout = true }
        }
        if metrics.usable, needsInitialSnapshot {
            needsInitialSnapshot = false
            applySnapshot(reloadingContent: false, animatingDifferences: false)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        lastViewportWidth = -1
        needsLayout = true
    }

    func setData(
        snapshot: FluentCollectionSnapshot<SectionID, ItemID>,
        layout: FluentCollectionLayout,
        selection: FluentCollectionIdentityBinding?,
        selections: FluentCollectionIdentitySetBinding?,
        isEnabled: @escaping (ItemID) -> Bool,
        itemStyle: any FluentCollectionItemStyle,
        content: @escaping (ItemID) -> FluentAnyView,
        header: ((SectionID) -> FluentAnyView)?,
        context: FluentRenderContext
    ) {
        self.snapshot = snapshot
        layoutSpec = layout
        self.selection = selection
        self.selections = selections
        isItemEnabled = isEnabled
        self.itemStyle = itemStyle
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
        isEnabled: @escaping (ItemID) -> Bool,
        itemStyle: any FluentCollectionItemStyle,
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
        isItemEnabled = isEnabled
        self.itemStyle = itemStyle
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
    private func updateLayoutMetrics() -> (usable: Bool, changed: Bool) {
        let insets = flowLayout.sectionInset
        let viewportWidth = contentView.bounds.width
        guard viewportWidth > insets.left + insets.right + 1 else { return (false, false) }
        let availableWidth = viewportWidth - insets.left - insets.right
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
        let alignedItemWidth = floor(itemWidth * max(scale, 1)) / max(scale, 1)
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
            flowLayout.itemSize = itemSize
            flowLayout.headerReferenceSize = headerSize
            flowLayout.invalidateLayout()
        }
        return (true, changed)
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
        at indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: fluentSectionedItemIdentifier, for: indexPath)
        guard let host = item as? FluentSectionedCollectionItem,
              snapshot.sectionIdentifiers.indices.contains(indexPath.section),
              let content else { return item }
        let sectionID = snapshot.sectionIdentifiers[indexPath.section]
        let sectionItems = snapshot.itemIdentifiers(inSection: sectionID)
        guard sectionItems.indices.contains(indexPath.item) else { return item }
        let itemID = sectionItems[indexPath.item]
        let selected = collectionView.selectionIndexPaths.contains(indexPath)
        host.update(
            content: content(itemID),
            context: context,
            theme: theme,
            layoutKind: layoutSpec.kind,
            itemStyle: itemStyle,
            enabled: isItemEnabled(itemID),
            selected: selected,
            focused: selected && isKeyboardFocusVisible,
            reduceMotion: context.reduceMotion
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
        let previousIndexPaths = collectionView.selectionIndexPaths
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

    private func updateVisibleItemStates(animated: Bool) {
        for item in collectionView.visibleItems() {
            guard let host = item as? FluentSectionedCollectionItem,
                  let indexPath = collectionView.indexPath(for: item) else { continue }
            let selected = collectionView.selectionIndexPaths.contains(indexPath)
            host.setSelected(selected, animated: animated)
            host.setFocused(selected && isKeyboardFocusVisible)
            host.setPressed(indexPath == pressedIndexPath)
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
        updateVisibleItemStates(animated: true)
        context.invalidate?()
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
        synchronizeSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelection else { return }
        synchronizeSelection()
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
                if let nextIndexPath, self.itemIsEnabled(at: nextIndexPath) {
                    self.setPressedIndexPath(nextIndexPath)
                } else {
                    self.setPressedIndexPath(nil)
                }
            case .leftMouseDragged:
                self.setPressedIndexPath(
                    nextIndexPath == self.pressedIndexPath ? self.pressedIndexPath : nil
                )
            case .leftMouseUp:
                self.setPressedIndexPath(nil)
            default:
                break
            }
            return event
        }
    }

    private func itemIsEnabled(at indexPath: IndexPath) -> Bool {
        guard snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return false }
        let sectionID = snapshot.sectionIdentifiers[indexPath.section]
        let items = snapshot.itemIdentifiers(inSection: sectionID)
        return items.indices.contains(indexPath.item) && isItemEnabled(items[indexPath.item])
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
        if let selectionObserverID { observedSelection?.removeObserver?(selectionObserverID) }
        if let selectionsObserverID { observedSelections?.removeObserver?(selectionsObserverID) }
    }
}

private final class FluentSectionedCollectionItem: NSCollectionViewItem {
    private var cellView: FluentSectionedCollectionCell { view as! FluentSectionedCollectionCell }

    override func loadView() {
        view = FluentSectionedCollectionCell()
    }

    func update(
        content: FluentAnyView,
        context: FluentRenderContext,
        theme: FluentTheme,
        layoutKind: FluentCollectionLayout.Kind,
        itemStyle: any FluentCollectionItemStyle,
        enabled: Bool,
        selected: Bool,
        focused: Bool,
        reduceMotion: Bool
    ) {
        cellView.updateConfiguration(
            theme: theme,
            layoutKind: layoutKind,
            itemStyle: itemStyle,
            enabled: enabled,
            selected: selected,
            focused: focused,
            reduceMotion: reduceMotion
        )
        cellView.update(content: content, context: context)
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        isSelected = selected
        cellView.setSelected(selected, animated: animated)
    }

    func setFocused(_ focused: Bool) { cellView.setFocused(focused) }
    func setPressed(_ pressed: Bool) { cellView.setPressed(pressed) }

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
    private var reduceMotion = false

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

    func updateConfiguration(
        theme: FluentTheme,
        layoutKind: FluentCollectionLayout.Kind,
        itemStyle: any FluentCollectionItemStyle,
        enabled: Bool,
        selected: Bool,
        focused: Bool,
        reduceMotion: Bool
    ) {
        let layoutChanged = self.layoutKind != layoutKind
        self.theme = theme
        self.layoutKind = layoutKind
        self.itemStyle = itemStyle
        self.enabled = enabled
        self.selected = selected
        self.focused = focused
        self.reduceMotion = reduceMotion
        animationCoordinator.reduceMotion = reduceMotion
        userInterfaceLayoutDirection = superview?.userInterfaceLayoutDirection ?? userInterfaceLayoutDirection
        if !enabled {
            pointerOver = false
            pressed = false
        }
        setAccessibilityEnabled(enabled)
        setAccessibilitySelected(selected)
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

    override func prepareForReuse() {
        super.prepareForReuse()
        pointerOver = false
        pressed = false
        focused = false
        selected = false
        animationCoordinator.cancelAll(on: [surfaceLayer, selectionIndicatorLayer])
        applyAppearance(animated: false)
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
        let indicatorVisible = layoutKind == .list && selected
        let targetIndicatorOpacity: Float = indicatorVisible ? 1 : 0
        let targetScale = pressed && selected ? appearance.selectionIndicatorPressedScale : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.backgroundColor = appearance.backgroundColor.cgColor
        surfaceLayer.cornerRadius = appearance.cornerRadius
        surfaceLayer.cornerCurve = .continuous
        contentView?.alphaValue = appearance.contentOpacity
        selectionIndicatorLayer.backgroundColor = appearance.selectionIndicatorColor.cgColor
        selectionIndicatorLayer.cornerRadius = appearance.selectionIndicatorSize.width / 2
        selectionIndicatorLayer.cornerCurve = .continuous
        selectionIndicatorLayer.opacity = targetIndicatorOpacity
        selectionIndicatorLayer.setAffineTransform(CGAffineTransform(scaleX: 1, y: targetScale))
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

    private func installContentConstraints(appearance: FluentCollectionItemAppearance? = nil) {
        guard let contentView else { return }
        NSLayoutConstraint.deactivate(contentConstraints)
        let insets = (appearance ?? resolvedAppearance()).contentInsets
        contentConstraints = [
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
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
