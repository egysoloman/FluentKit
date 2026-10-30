import AppKit

/// A declarative, virtualized single-section ListView built on FluentCollection's native
/// `NSCollectionView` and WinUI-derived ListViewItem visuals.
public struct FluentListView<ItemID: Hashable, Content: FluentView>: FluentUpdatablePrimitiveView {
    private let itemIDs: [ItemID]
    private let selectionID: FluentBinding<ItemID?>?
    private let selectionIDs: FluentBinding<Set<ItemID>>?
    private let selectionMode: FluentListViewSelectionMode
    private let onItemInvoked: ((ItemID) -> Void)?
    private let selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility
    private let onItemsReordered: (([ItemID]) -> Void)?
    private let incrementalLoading: FluentIncrementalLoadingConfiguration?
    private let rowHeight: CGFloat
    private let spacing: CGFloat
    private let isEnabled: (ItemID) -> Bool
    private let itemStyle: any FluentCollectionItemStyle
    private let content: (ItemID) -> Content
    private var contentVersion: ((ItemID) -> AnyHashable)?

    public func contentVersion(_ version: @escaping (ItemID) -> AnyHashable) -> Self {
        var copy = self
        copy.contentVersion = version
        return copy
    }

    public init(
        _ itemIDs: [ItemID],
        selectionID: FluentBinding<ItemID?>? = nil,
        selectionMode: FluentListViewSelectionMode = .single,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: (([ItemID]) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        rowHeight: CGFloat = 40,
        spacing: CGFloat = 0,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.itemIDs = itemIDs
        self.selectionID = selectionID
        selectionIDs = nil
        self.selectionMode = selectionMode
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.rowHeight = rowHeight
        self.spacing = spacing
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = content
    }

    public init(
        _ itemIDs: [ItemID],
        selectionIDs: FluentBinding<Set<ItemID>>,
        selectionMode: FluentListViewSelectionMode = .multiple,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: (([ItemID]) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        rowHeight: CGFloat = 40,
        spacing: CGFloat = 0,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.itemIDs = itemIDs
        selectionID = nil
        self.selectionIDs = selectionIDs
        self.selectionMode = selectionMode
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.rowHeight = rowHeight
        self.spacing = spacing
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        base._mount(in: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        base._update(view, in: context)
    }

    private var base: FluentAnyView {
        let snapshot = FluentCollectionSnapshot(section: 0, items: itemIDs)
        let layout = FluentCollectionLayout.list(
            rowHeight: rowHeight,
            spacing: spacing
        )
        if let selectionIDs {
            return FluentAnyView(
                FluentCollection(
                    snapshot: snapshot,
                    layout: layout,
                    selectionIDs: selectionIDs,
                    selectionMode: selectionMode,
                    onItemInvoked: onItemInvoked,
                    selectionCheckmarkVisibility: selectionCheckmarkVisibility,
                    onItemsReordered: onItemsReordered.map { callback in
                        { callback($0.itemIdentifiers) }
                    },
                    incrementalLoading: incrementalLoading,
                    isEnabled: isEnabled,
                    itemStyle: itemStyle
                ) { item in FluentAnyView(content(item)) }
                .withOptionalContentVersion(contentVersion)
            )
        }
        return FluentAnyView(
            FluentCollection(
                snapshot: snapshot,
                layout: layout,
                selectionID: selectionID,
                selectionMode: selectionMode,
                onItemInvoked: onItemInvoked,
                selectionCheckmarkVisibility: selectionCheckmarkVisibility,
                onItemsReordered: onItemsReordered.map { callback in
                    { callback($0.itemIdentifiers) }
                },
                incrementalLoading: incrementalLoading,
                isEnabled: isEnabled,
                itemStyle: itemStyle
            ) { item in FluentAnyView(content(item)) }
                .withOptionalContentVersion(contentVersion)
        )
    }
}

/// A declarative, virtualized single-section GridView built on FluentCollection's adaptive-grid
/// layout and WinUI-derived GridViewItem visuals.
public struct FluentGridView<ItemID: Hashable, Content: FluentView>: FluentUpdatablePrimitiveView {
    private let itemIDs: [ItemID]
    private let selectionID: FluentBinding<ItemID?>?
    private let selectionIDs: FluentBinding<Set<ItemID>>?
    private let selectionMode: FluentListViewSelectionMode
    private let onItemInvoked: ((ItemID) -> Void)?
    private let selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility
    private let onItemsReordered: (([ItemID]) -> Void)?
    private let incrementalLoading: FluentIncrementalLoadingConfiguration?
    private let minimumItemWidth: CGFloat
    private let itemHeight: CGFloat
    private let spacing: CGFloat
    private let isEnabled: (ItemID) -> Bool
    private let itemStyle: any FluentCollectionItemStyle
    private let content: (ItemID) -> Content
    private var contentVersion: ((ItemID) -> AnyHashable)?

    public func contentVersion(_ version: @escaping (ItemID) -> AnyHashable) -> Self {
        var copy = self
        copy.contentVersion = version
        return copy
    }

    public init(
        _ itemIDs: [ItemID],
        selectionID: FluentBinding<ItemID?>? = nil,
        selectionMode: FluentListViewSelectionMode = .single,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: (([ItemID]) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        minimumItemWidth: CGFloat = 160,
        itemHeight: CGFloat = 88,
        spacing: CGFloat = 10,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.itemIDs = itemIDs
        self.selectionID = selectionID
        selectionIDs = nil
        self.selectionMode = selectionMode
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.minimumItemWidth = minimumItemWidth
        self.itemHeight = itemHeight
        self.spacing = spacing
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = content
    }

    public init(
        _ itemIDs: [ItemID],
        selectionIDs: FluentBinding<Set<ItemID>>,
        selectionMode: FluentListViewSelectionMode = .multiple,
        onItemInvoked: ((ItemID) -> Void)? = nil,
        selectionCheckmarkVisibility: FluentSelectionCheckmarkVisibility = .automatic,
        onItemsReordered: (([ItemID]) -> Void)? = nil,
        incrementalLoading: FluentIncrementalLoadingConfiguration? = nil,
        minimumItemWidth: CGFloat = 160,
        itemHeight: CGFloat = 88,
        spacing: CGFloat = 10,
        isEnabled: @escaping (ItemID) -> Bool = { _ in true },
        itemStyle: any FluentCollectionItemStyle = FluentAutomaticCollectionItemStyle(),
        @FluentViewBuilder content: @escaping (ItemID) -> Content
    ) {
        self.itemIDs = itemIDs
        selectionID = nil
        self.selectionIDs = selectionIDs
        self.selectionMode = selectionMode
        self.onItemInvoked = onItemInvoked
        self.selectionCheckmarkVisibility = selectionCheckmarkVisibility
        self.onItemsReordered = onItemsReordered
        self.incrementalLoading = incrementalLoading
        self.minimumItemWidth = minimumItemWidth
        self.itemHeight = itemHeight
        self.spacing = spacing
        self.isEnabled = isEnabled
        self.itemStyle = itemStyle
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        base._mount(in: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        base._update(view, in: context)
    }

    private var base: FluentAnyView {
        let snapshot = FluentCollectionSnapshot(section: 0, items: itemIDs)
        let layout = FluentCollectionLayout.adaptiveGrid(
            minimumItemWidth: minimumItemWidth,
            itemHeight: itemHeight,
            spacing: spacing
        )
        if let selectionIDs {
            return FluentAnyView(
                FluentCollection(
                    snapshot: snapshot,
                    layout: layout,
                    selectionIDs: selectionIDs,
                    selectionMode: selectionMode,
                    onItemInvoked: onItemInvoked,
                    selectionCheckmarkVisibility: selectionCheckmarkVisibility,
                    onItemsReordered: onItemsReordered.map { callback in
                        { callback($0.itemIdentifiers) }
                    },
                    incrementalLoading: incrementalLoading,
                    isEnabled: isEnabled,
                    itemStyle: itemStyle
                ) { item in FluentAnyView(content(item)) }
                .withOptionalContentVersion(contentVersion)
            )
        }
        return FluentAnyView(
            FluentCollection(
                snapshot: snapshot,
                layout: layout,
                selectionID: selectionID,
                selectionMode: selectionMode,
                onItemInvoked: onItemInvoked,
                selectionCheckmarkVisibility: selectionCheckmarkVisibility,
                onItemsReordered: onItemsReordered.map { callback in
                    { callback($0.itemIdentifiers) }
                },
                incrementalLoading: incrementalLoading,
                isEnabled: isEnabled,
                itemStyle: itemStyle
            ) { item in FluentAnyView(content(item)) }
                .withOptionalContentVersion(contentVersion)
        )
    }
}

private extension FluentCollection {
    func withOptionalContentVersion(_ version: ((ItemID) -> AnyHashable)?) -> Self {
        if let version { return contentVersion(version) }
        return self
    }
}
