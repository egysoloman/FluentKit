import AppKit

/// Selects the pane layout used by `FluentNavigationView`.
public enum FluentNavigationPaneDisplayMode: String, CaseIterable, Hashable, Sendable {
    case automatic
    case left
    case leftCompact
    case leftMinimal
    case top
}

/// The resolved layout after applying the pane display mode and adaptive width thresholds.
public enum FluentNavigationViewDisplayMode: String, CaseIterable, Hashable, Sendable {
    case expanded
    case compact
    case minimal
    case top
}

/// Defines which surface owns the persistent NavigationView pane background.
public enum FluentNavigationPaneMaterialOwnership: String, CaseIterable, Hashable, Sendable {
    /// Inherit an enclosing WindowShell Mica when present; otherwise own a standalone Mica.
    case automatic
    /// The pane stays transparent and reveals its enclosing WindowShell backdrop.
    case inherited
    /// The pane owns one persistent Mica surface when used outside a WindowShell.
    case standalone
    /// The pane uses the theme's opaque window background without a material sampler.
    case solid
}

/// Selects how the NavigationView selection indicator travels between destinations.
public enum FluentNavigationSelectionIndicatorMode: String, CaseIterable, Hashable, Sendable {
    /// Uses a bounded two-rail jump at one depth and WinUI's in-place scale across depths.
    case jump
    /// Keeps one connected rail moving continuously between nearby destinations.
    case continuous
    /// FluentKit extension: continuous nearby, bounded jump far away, and in-place scale across depths.
    case adaptive
}

/// Stable metadata for one primary or footer destination in a `FluentNavigationView`.
public struct FluentNavigationItem<ID: Hashable> {
    public let id: ID
    public let title: String
    public let systemImageName: String
    public let isEnabled: Bool
    public let children: [FluentNavigationItem<ID>]
    public let selectsOnInvoked: Bool
    public let isExpanded: Bool

    public init(
        id: ID,
        title: String,
        systemImageName: String,
        isEnabled: Bool = true,
        children: [FluentNavigationItem<ID>] = [],
        selectsOnInvoked: Bool = true,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.children = children
        self.selectsOnInvoked = selectsOnInvoked
        self.isExpanded = isExpanded
    }
}

/// A responsive, stable-selection navigation shell with expanded, compact, overlay, and top modes.
public struct FluentNavigationView<ID: Hashable>: FluentUpdatablePrimitiveView {
    private let items: [FluentNavigationItem<ID>]
    private let footerItems: [FluentNavigationItem<ID>]
    private let selection: FluentBinding<ID?>
    private let isPaneOpen: FluentBinding<Bool>?
    private let paneDisplayMode: FluentNavigationPaneDisplayMode
    private let isPaneToggleButtonVisible: Bool
    private let openPaneLength: CGFloat
    private let compactPaneLength: CGFloat
    private let compactModeThresholdWidth: CGFloat
    private let expandedModeThresholdWidth: CGFloat
    private let rowHeight: CGFloat
    private let paneSectionTitle: String?
    private let contentTransition: FluentNavigationTransitionMode
    private let paneMaterialOwnership: FluentNavigationPaneMaterialOwnership
    private let selectionIndicatorMode: FluentNavigationSelectionIndicatorMode
    private let paneHeader: FluentAnyView?
    private let header: FluentAnyView?
    private let content: FluentAnyView
    private let onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?

    public init<Content: FluentView>(
        _ items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        paneDisplayMode: FluentNavigationPaneDisplayMode = .automatic,
        isPaneToggleButtonVisible: Bool = true,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        compactModeThresholdWidth: CGFloat = 641,
        expandedModeThresholdWidth: CGFloat = 1_008,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        contentTransition: FluentNavigationTransitionMode = .automatic,
        paneMaterialOwnership: FluentNavigationPaneMaterialOwnership = .automatic,
        selectionIndicatorMode: FluentNavigationSelectionIndicatorMode = .adaptive,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            paneDisplayMode: paneDisplayMode,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            compactModeThresholdWidth: compactModeThresholdWidth,
            expandedModeThresholdWidth: expandedModeThresholdWidth,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            contentTransition: contentTransition,
            paneMaterialOwnership: paneMaterialOwnership,
            selectionIndicatorMode: selectionIndicatorMode,
            paneHeader: nil,
            header: nil,
            onDisplayModeChange: onDisplayModeChange,
            content: FluentAnyView(content())
        )
    }

    public init<PaneHeader: FluentView, Content: FluentView>(
        _ items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        paneDisplayMode: FluentNavigationPaneDisplayMode = .automatic,
        isPaneToggleButtonVisible: Bool = true,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        compactModeThresholdWidth: CGFloat = 641,
        expandedModeThresholdWidth: CGFloat = 1_008,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        contentTransition: FluentNavigationTransitionMode = .automatic,
        paneMaterialOwnership: FluentNavigationPaneMaterialOwnership = .automatic,
        selectionIndicatorMode: FluentNavigationSelectionIndicatorMode = .adaptive,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)? = nil,
        @FluentViewBuilder paneHeader: () -> PaneHeader,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            paneDisplayMode: paneDisplayMode,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            compactModeThresholdWidth: compactModeThresholdWidth,
            expandedModeThresholdWidth: expandedModeThresholdWidth,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            contentTransition: contentTransition,
            paneMaterialOwnership: paneMaterialOwnership,
            selectionIndicatorMode: selectionIndicatorMode,
            paneHeader: FluentAnyView(paneHeader()),
            header: nil,
            onDisplayModeChange: onDisplayModeChange,
            content: FluentAnyView(content())
        )
    }

    public init<PaneHeader: FluentView, Header: FluentView, Content: FluentView>(
        _ items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        paneDisplayMode: FluentNavigationPaneDisplayMode = .automatic,
        isPaneToggleButtonVisible: Bool = true,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        compactModeThresholdWidth: CGFloat = 641,
        expandedModeThresholdWidth: CGFloat = 1_008,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        contentTransition: FluentNavigationTransitionMode = .automatic,
        paneMaterialOwnership: FluentNavigationPaneMaterialOwnership = .automatic,
        selectionIndicatorMode: FluentNavigationSelectionIndicatorMode = .adaptive,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)? = nil,
        @FluentViewBuilder paneHeader: () -> PaneHeader,
        @FluentViewBuilder header: () -> Header,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            paneDisplayMode: paneDisplayMode,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            compactModeThresholdWidth: compactModeThresholdWidth,
            expandedModeThresholdWidth: expandedModeThresholdWidth,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            contentTransition: contentTransition,
            paneMaterialOwnership: paneMaterialOwnership,
            selectionIndicatorMode: selectionIndicatorMode,
            paneHeader: FluentAnyView(paneHeader()),
            header: FluentAnyView(header()),
            onDisplayModeChange: onDisplayModeChange,
            content: FluentAnyView(content())
        )
    }

    private init(
        _ items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>?,
        paneDisplayMode: FluentNavigationPaneDisplayMode,
        isPaneToggleButtonVisible: Bool,
        openPaneLength: CGFloat,
        compactPaneLength: CGFloat,
        compactModeThresholdWidth: CGFloat,
        expandedModeThresholdWidth: CGFloat,
        rowHeight: CGFloat,
        paneSectionTitle: String?,
        contentTransition: FluentNavigationTransitionMode,
        paneMaterialOwnership: FluentNavigationPaneMaterialOwnership,
        selectionIndicatorMode: FluentNavigationSelectionIndicatorMode,
        paneHeader: FluentAnyView?,
        header: FluentAnyView?,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?,
        content: FluentAnyView
    ) {
        self.items = items
        self.footerItems = footerItems
        self.selection = selection
        self.isPaneOpen = isPaneOpen
        self.paneDisplayMode = paneDisplayMode
        self.isPaneToggleButtonVisible = isPaneToggleButtonVisible
        self.openPaneLength = max(openPaneLength, 0)
        self.compactPaneLength = max(compactPaneLength, 0)
        self.compactModeThresholdWidth = max(compactModeThresholdWidth, 0)
        self.expandedModeThresholdWidth = max(expandedModeThresholdWidth, self.compactModeThresholdWidth)
        self.rowHeight = max(rowHeight, 36)
        self.paneSectionTitle = paneSectionTitle
        self.contentTransition = contentTransition
        self.paneMaterialOwnership = paneMaterialOwnership
        self.selectionIndicatorMode = selectionIndicatorMode
        self.paneHeader = paneHeader
        self.header = header
        self.onDisplayModeChange = onDisplayModeChange
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentNavigationViewHost(
            items: items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            paneDisplayMode: paneDisplayMode,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            compactModeThresholdWidth: compactModeThresholdWidth,
            expandedModeThresholdWidth: expandedModeThresholdWidth,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            contentTransition: contentTransition,
            paneMaterialOwnership: paneMaterialOwnership,
            selectionIndicatorMode: selectionIndicatorMode,
            paneHeader: paneHeader,
            header: header,
            content: content,
            onDisplayModeChange: onDisplayModeChange,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNavigationViewHost<ID> else { return false }
        host.update(
            items: items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            paneDisplayMode: paneDisplayMode,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            compactModeThresholdWidth: compactModeThresholdWidth,
            expandedModeThresholdWidth: expandedModeThresholdWidth,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            contentTransition: contentTransition,
            paneMaterialOwnership: paneMaterialOwnership,
            selectionIndicatorMode: selectionIndicatorMode,
            paneHeader: paneHeader,
            header: header,
            content: content,
            onDisplayModeChange: onDisplayModeChange,
            context: context
        )
        return true
    }
}

private enum FluentNavigationFocusMove {
    case backward
    case end
    case forward
    case start
}

private struct FluentNavigationItemRow<ID: Hashable> {
    let item: FluentNavigationItem<ID>
    let depth: Int
    let parentID: ID?
}

private final class FluentNavigationViewHost<ID: Hashable>: NSView {
    private var items: [FluentNavigationItem<ID>]
    private var footerItems: [FluentNavigationItem<ID>]
    private var selection: FluentBinding<ID?>
    private var paneOpenBinding: FluentBinding<Bool>?
    private var paneDisplayMode: FluentNavigationPaneDisplayMode
    private var isPaneToggleButtonVisible: Bool
    private var openPaneLength: CGFloat
    private var compactPaneLength: CGFloat
    private var compactModeThresholdWidth: CGFloat
    private var expandedModeThresholdWidth: CGFloat
    private var rowHeight: CGFloat
    private var paneSectionTitle: String?
    private var contentTransition: FluentNavigationTransitionMode
    private var paneMaterialOwnership: FluentNavigationPaneMaterialOwnership
    private var selectionIndicatorMode: FluentNavigationSelectionIndicatorMode
    private var paneHeader: FluentAnyView?
    private var header: FluentAnyView?
    private var content: FluentAnyView
    private var onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?
    private var context: FluentRenderContext

    private let contentHost: FluentNavigationContentPresenter<ID>
    private var headerHost: FluentViewHost<FluentAnyView>?
    private let paneView = FluentNavigationPaneBackgroundView()
    private var paneMaterial: FluentMaterialView?
    private let dimmingView = FluentNavigationDismissView()
    private let minimalToggleButton = FluentNavigationPaneToggleButton()
    private let paneToggleButton = FluentNavigationPaneToggleButton()
    private let topOverflowButton = FluentNavigationOverflowButton<ID>()
    private let mainScrollView = NSScrollView()
    private let mainItemsView = FluentNavigationItemsView()
    private let sectionLabelHost = FluentNavigationSectionLabelHost()
    private let sectionLabel = NSTextField(labelWithString: "")
    private var paneHeaderHost: FluentViewHost<FluentAnyView>?
    private var mainButtons: [FluentNavigationItemButton<ID>] = []
    private var footerButtons: [FluentNavigationItemButton<ID>] = []
    private let indicatorAnimator = FluentSelectionIndicatorAnimator(
        currentLayerName: "FluentKit.NavigationView.SelectionIndicator",
        previousLayerName: "FluentKit.NavigationView.PreviousSelectionIndicator",
        axis: .vertical
    )

    private var observedSelection: FluentBinding<ID?>?
    private var selectionObserverID: UUID?
    private var observedPaneOpen: FluentBinding<Bool>?
    private var paneOpenObserverID: UUID?
    private var selectionGeometryObservers: [NSObjectProtocol] = []
    private var internalPaneOpen: Bool
    private var isSynchronizingPaneBinding = false
    private var resolvedDisplayMode: FluentNavigationViewDisplayMode?
    private var didResolveInitialMode = false
    private var wasForceClosed = false
    private var panePresentationExpanded = true
    private var retainsOverlayDuringAnimation = false
    private var selectedID: ID?
    private var paneAnimationGeneration = 0
    private var paneAnimationDelegate: FluentNavigationAnimationCompletionDelegate?
    private var isSanitizingSelection = false
    private var contentColumnFrame = NSRect.zero
    private var isApplyingSelectionTransition = false
    private var isStabilizingPaneGeometry = false
    private var selectionGeometryUpdateScheduled = false
    private var pendingIndicatorAnimation = false
    private var sectionLabelTransitionGeneration = 0
    private var expandedItemIDs: Set<ID> = []
    private var knownExpandableItemIDs: Set<ID> = []
    private var expansionAnimationGenerations: [ID: UInt64] = [:]
    private var pendingExpansionTargets: [ID: Bool] = [:]
    private var deferredRemovalButtons: [FluentNavigationItemButton<ID>] = []
    private var deferredRemovalDocumentHeight: CGFloat?
    private let expansionAnimationCoordinator = FluentAnimationCoordinator()
    private let navigationHoverCoordinator = FluentHoverCoordinator<FluentNavigationItemButton<ID>> {
        button,
        hovering in
        button.setPointerOver(hovering)
    }

    init(
        items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>?,
        paneDisplayMode: FluentNavigationPaneDisplayMode,
        isPaneToggleButtonVisible: Bool,
        openPaneLength: CGFloat,
        compactPaneLength: CGFloat,
        compactModeThresholdWidth: CGFloat,
        expandedModeThresholdWidth: CGFloat,
        rowHeight: CGFloat,
        paneSectionTitle: String?,
        contentTransition: FluentNavigationTransitionMode,
        paneMaterialOwnership: FluentNavigationPaneMaterialOwnership,
        selectionIndicatorMode: FluentNavigationSelectionIndicatorMode,
        paneHeader: FluentAnyView?,
        header: FluentAnyView?,
        content: FluentAnyView,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?,
        context: FluentRenderContext
    ) {
        self.items = items
        self.footerItems = footerItems
        self.selection = selection
        paneOpenBinding = isPaneOpen
        self.paneDisplayMode = paneDisplayMode
        self.isPaneToggleButtonVisible = isPaneToggleButtonVisible
        self.openPaneLength = openPaneLength
        self.compactPaneLength = compactPaneLength
        self.compactModeThresholdWidth = compactModeThresholdWidth
        self.expandedModeThresholdWidth = expandedModeThresholdWidth
        self.rowHeight = rowHeight
        self.paneSectionTitle = paneSectionTitle
        self.contentTransition = contentTransition
        self.paneMaterialOwnership = paneMaterialOwnership
        self.selectionIndicatorMode = selectionIndicatorMode
        self.paneHeader = paneHeader
        self.header = header
        self.content = content
        self.onDisplayModeChange = onDisplayModeChange
        self.context = context
        let initialExpandableItems = Self.flatten(items + footerItems).filter { !$0.children.isEmpty }
        knownExpandableItemIDs = Set(initialExpandableItems.map(\.id))
        expandedItemIDs = Set(initialExpandableItems.filter(\.isExpanded).map(\.id))
        internalPaneOpen = isPaneOpen?.get() ?? true
        selectedID = selection.get()
        contentHost = FluentNavigationContentPresenter(
            content: content,
            identity: selection.get(),
            context: context
        )
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Navigation view")

        // The presenter is manually arranged. Keep its autoresizing-mask constraints disabled
        // until the first non-empty Arrange slot so AppKit cannot turn the construction-time
        // zero frame into a required width == 0 constraint for the descendant measure pass.
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        paneView.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Pane")
        paneView.wantsLayer = true
        paneView.layer?.masksToBounds = true
        applyPaneMaterialOwnership()
        if let paneLayer = paneView.layer {
            indicatorAnimator.attach(to: paneLayer)
        }
        indicatorAnimator.setMode(selectionIndicatorMode)

        dimmingView.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.DismissLayer")
        dimmingView.onDismiss = { [weak self] in self?.setPaneOpen(false, userInitiated: true, animated: true) }
        dimmingView.isHidden = true

        paneToggleButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.PaneToggle")
        paneToggleButton.onToggle = { [weak self] in self?.togglePane() }
        minimalToggleButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.MinimalPaneToggle")
        minimalToggleButton.onToggle = { [weak self] in self?.togglePane() }
        paneToggleButton.update(
            theme: context.theme,
            layoutDirection: context.layoutDirection,
            isPaneOpen: internalPaneOpen
        )
        minimalToggleButton.update(
            theme: context.theme,
            layoutDirection: context.layoutDirection,
            isPaneOpen: internalPaneOpen
        )

        mainScrollView.drawsBackground = false
        mainScrollView.hasVerticalScroller = true
        mainScrollView.hasHorizontalScroller = true
        mainScrollView.autohidesScrollers = true
        mainScrollView.borderType = .noBorder
        mainScrollView.wantsLayer = true
        mainScrollView.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.PrimaryScroll")
        mainScrollView.documentView = mainItemsView
        mainScrollView.contentView.postsBoundsChangedNotifications = true
        mainItemsView.postsBoundsChangedNotifications = true
        mainItemsView.postsFrameChangedNotifications = true
        mainItemsView.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.PrimaryItems")

        sectionLabel.font = NSFont.systemFont(
            ofSize: 14 * context.theme.typography.scale,
            weight: .semibold
        )
        sectionLabel.textColor = context.theme.textSecondary
        sectionLabel.lineBreakMode = .byTruncatingTail
        sectionLabel.isSelectable = false
        sectionLabel.isEditable = false
        sectionLabel.isBordered = false
        sectionLabel.drawsBackground = false
        sectionLabel.wantsLayer = true
        sectionLabel.layer?.opacity = 1
        sectionLabelHost.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.SectionHeader")
        sectionLabelHost.layer?.masksToBounds = true
        sectionLabelHost.addSubview(sectionLabel)

        addSubview(contentHost)
        addSubview(dimmingView)
        reconcileHeader()
        addSubview(paneView)
        addSubview(minimalToggleButton)
        paneView.addSubview(paneToggleButton)
        paneView.addSubview(topOverflowButton)
        paneView.addSubview(sectionLabelHost)
        paneView.addSubview(mainScrollView)

        reconcilePaneHeader()
        reconcileButtons()
        installObservers()
        sanitizeSelectionIfNeeded()
        applySelection(selection.get(), animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyPaneMaterialOwnership()
    }

    override func layout() {
        super.layout()
        let mode = resolveDisplayMode(for: bounds.width)
        if resolvedDisplayMode != mode {
            applyResolvedDisplayMode(mode)
        }
        layoutCurrentState()
        stabilizePaneGeometry()
        if !isApplyingSelectionTransition {
            let shouldAnimateIndicator = pendingIndicatorAnimation && window != nil
            pendingIndicatorAnimation = false
            updateSelectionIndicator(animated: shouldAnimateIndicator)
        }
        refreshNavigationPointerState()
    }

    func update(
        items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>?,
        paneDisplayMode: FluentNavigationPaneDisplayMode,
        isPaneToggleButtonVisible: Bool,
        openPaneLength: CGFloat,
        compactPaneLength: CGFloat,
        compactModeThresholdWidth: CGFloat,
        expandedModeThresholdWidth: CGFloat,
        rowHeight: CGFloat,
        paneSectionTitle: String?,
        contentTransition: FluentNavigationTransitionMode,
        paneMaterialOwnership: FluentNavigationPaneMaterialOwnership,
        selectionIndicatorMode: FluentNavigationSelectionIndicatorMode,
        paneHeader: FluentAnyView?,
        header: FluentAnyView?,
        content: FluentAnyView,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?,
        context: FluentRenderContext
    ) {
        removeBindingObservers()
        let nextExpandableItems = Self.flatten(items + footerItems).filter { !$0.children.isEmpty }
        let nextExpandableIDs = Set(nextExpandableItems.map(\.id))
        expandedItemIDs.formIntersection(nextExpandableIDs)
        for item in nextExpandableItems where !knownExpandableItemIDs.contains(item.id) && item.isExpanded {
            expandedItemIDs.insert(item.id)
        }
        knownExpandableItemIDs = nextExpandableIDs
        self.items = items
        self.footerItems = footerItems
        self.selection = selection
        paneOpenBinding = isPaneOpen
        self.paneDisplayMode = paneDisplayMode
        self.isPaneToggleButtonVisible = isPaneToggleButtonVisible
        self.openPaneLength = openPaneLength
        self.compactPaneLength = compactPaneLength
        self.compactModeThresholdWidth = compactModeThresholdWidth
        self.expandedModeThresholdWidth = expandedModeThresholdWidth
        self.rowHeight = rowHeight
        self.paneSectionTitle = paneSectionTitle
        self.contentTransition = contentTransition
        self.paneMaterialOwnership = paneMaterialOwnership
        self.selectionIndicatorMode = selectionIndicatorMode
        indicatorAnimator.setMode(selectionIndicatorMode)
        self.paneHeader = paneHeader
        self.header = header
        self.content = content
        self.onDisplayModeChange = onDisplayModeChange
        self.context = context
        internalPaneOpen = isPaneOpen?.get() ?? internalPaneOpen
        panePresentationExpanded = resolvedDisplayMode == .top || internalPaneOpen

        dimmingView.theme = context.theme
        applyPaneMaterialOwnership()
        paneToggleButton.update(theme: context.theme, layoutDirection: context.layoutDirection, isPaneOpen: internalPaneOpen)
        minimalToggleButton.update(theme: context.theme, layoutDirection: context.layoutDirection, isPaneOpen: internalPaneOpen)
        sectionLabel.font = NSFont.systemFont(
            ofSize: 14 * context.theme.typography.scale,
            weight: .semibold
        )
        sectionLabel.textColor = context.theme.textSecondary

        reconcileHeader()
        reconcilePaneHeader()
        reconcileButtons()
        installBindingObservers()
        sanitizeSelectionIfNeeded()
        applySelection(selection.get(), animated: selectedID != selection.get())
        contentHost.update(
            content: content,
            identity: selectedID,
            orderedIDs: Self.flatten(items + footerItems).map(\.id),
            primaryIDs: Set(Self.flatten(items).map(\.id)),
            mode: contentTransition,
            isTopNavigation: paneDisplayMode == .top || resolvedDisplayMode == .top,
            context: context
        )
        needsLayout = true
    }

    private func reconcilePaneHeader() {
        guard let paneHeader else {
            paneHeaderHost?.removeFromSuperview()
            paneHeaderHost = nil
            return
        }
        if let paneHeaderHost {
            paneHeaderHost.context = context
            paneHeaderHost.update(paneHeader)
        } else {
            let host = FluentViewHost(paneHeader, context: context)
            host.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.PaneHeader")
            host.translatesAutoresizingMaskIntoConstraints = true
            paneView.addSubview(host)
            paneHeaderHost = host
        }
    }

    private func reconcileHeader() {
        guard let header else {
            headerHost?.removeFromSuperview()
            headerHost = nil
            return
        }
        if let headerHost {
            headerHost.context = context
            headerHost.update(header)
        } else {
            let host = FluentViewHost(header, context: context)
            host.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Header")
            host.translatesAutoresizingMaskIntoConstraints = true
            addSubview(host, positioned: .below, relativeTo: dimmingView)
            headerHost = host
        }
    }

    private func reconcileButtons() {
        mainButtons = reconcile(
            existing: mainButtons,
            rows: visibleRows(in: items),
            superview: mainItemsView
        )
        footerButtons = reconcile(
            existing: footerButtons,
            rows: visibleRows(in: footerItems),
            superview: paneView
        )
        updateButtonConfigurations()
    }

    private func reconcile(
        existing: [FluentNavigationItemButton<ID>],
        rows: [FluentNavigationItemRow<ID>],
        superview: NSView
    ) -> [FluentNavigationItemButton<ID>] {
        var available: [ID: [FluentNavigationItemButton<ID>]] = [:]
        for button in existing { available[button.itemID, default: []].append(button) }
        var result: [FluentNavigationItemButton<ID>] = []
        for row in rows {
            let item = row.item
            let button: FluentNavigationItemButton<ID>
            if var candidates = available[item.id], let reused = candidates.first {
                button = reused
                candidates.removeFirst()
                available[item.id] = candidates
            } else {
                button = FluentNavigationItemButton(item: item)
                superview.addSubview(button)
            }
            result.append(button)
        }
        available.values.flatMap { $0 }.forEach { button in
            // During a collapse the child rows remain mounted as a short-lived visual layer so
            // they can fade out while the rows below them move upward. They are removed by the
            // transition completion instead of disappearing during this reconciliation pass.
            if deferredRemovalButtons.contains(where: { $0 === button }) { return }
            navigationHoverCoordinator.remove(button)
            button.resetPointerState()
            button.removeFromSuperview()
        }
        return result
    }

    private func updateButtonConfigurations() {
        let mode = resolvedDisplayMode ?? resolveDisplayMode(for: bounds.width)
        let top = mode == .top
        let expanded = top || panePresentationExpanded || (mode == .expanded && internalPaneOpen)
        for (button, row) in zip(mainButtons, visibleRows(in: items)) {
            configure(button, row: row, expanded: expanded, top: top)
        }
        for (button, row) in zip(footerButtons, visibleRows(in: footerItems)) {
            configure(button, row: row, expanded: expanded, top: top)
        }
    }

    private func configure(
        _ button: FluentNavigationItemButton<ID>,
        row: FluentNavigationItemRow<ID>,
        expanded: Bool,
        top: Bool
    ) {
        let item = row.item
        button.update(
            item: item,
            selected: selectedID == item.id,
            expanded: expanded,
            top: top,
            depth: row.depth,
            hasChildren: !item.children.isEmpty,
            itemExpanded: expandedItemIDs.contains(item.id),
            theme: context.theme,
            layoutDirection: context.layoutDirection,
            onActivate: { [weak self] id in self?.activateNavigationItem(id) },
            onMoveFocus: { [weak self] id, move in self?.moveFocus(from: id, move: move) },
            onCancel: { [weak self] in self?.closeOverlayPaneIfNeeded() },
            onHoverChange: { [weak self] button, hovering in
                self?.setHoveredNavigationButton(button, hovering: hovering)
            }
        )
    }

    private static func flatten(_ source: [FluentNavigationItem<ID>]) -> [FluentNavigationItem<ID>] {
        source.flatMap { item in [item] + flatten(item.children) }
    }

    private func visibleRows(
        in source: [FluentNavigationItem<ID>],
        depth: Int = 0,
        parentID: ID? = nil
    ) -> [FluentNavigationItemRow<ID>] {
        source.flatMap { item in
            let row = FluentNavigationItemRow(item: item, depth: depth, parentID: parentID)
            guard !item.children.isEmpty, expandedItemIDs.contains(item.id) else { return [row] }
            return [row] + visibleRows(in: item.children, depth: depth + 1, parentID: item.id)
        }
    }

    private func item(withID id: ID) -> FluentNavigationItem<ID>? {
        Self.flatten(items + footerItems).first { $0.id == id }
    }

    private func activateNavigationItem(_ id: ID) {
        guard let item = item(withID: id), item.isEnabled else { return }
        if !item.children.isEmpty {
            let currentTarget = pendingExpansionTargets[id] ?? expandedItemIDs.contains(id)
            animateExpansion(of: id, expanding: !currentTarget)
        }
        if item.selectsOnInvoked { select(id) }
    }

    private func animateExpansion(of id: ID, expanding: Bool) {
        // A second click can arrive while the previous group is still moving. Capture the
        // presentation geometry before cancelling those animations; restarting from model
        // frames makes every row visibly snap to the previous destination first.
        let mountedButtons = mainButtons + footerButtons + deferredRemovalButtons
        let oldFrames = Dictionary(
            uniqueKeysWithValues: mountedButtons.map {
                (ObjectIdentifier($0), currentVisualFrame(of: $0))
            }
        )
        expansionAnimationCoordinator.cancelAll(on: mountedButtons.compactMap(\.layer))
        for pendingID in pendingExpansionTargets.keys {
            expansionAnimationGenerations[pendingID, default: 0] &+= 1
        }
        pendingExpansionTargets.removeAll()
        removeDeferredNavigationRows()

        let generation = expansionAnimationGenerations[id, default: 0] &+ 1
        expansionAnimationGenerations[id] = generation
        pendingExpansionTargets[id] = expanding
        expansionAnimationCoordinator.reduceMotion = context.reduceMotion
        let expansionMotion = expanding
            ? FluentMotion.navigationHeaderOpen
            : FluentMotion.navigationHeaderClose
        let childIDs = descendantIDs(of: id, in: items + footerItems)
        if expanding {
            expandedItemIDs.insert(id)
            resetNavigationPointerState()
            reconcileButtons()
            needsLayout = true
            layoutSubtreeIfNeeded()
            animateNavigationReflow(from: oldFrames, motion: expansionMotion)
            let children = (mainButtons + footerButtons).filter { childIDs.contains($0.itemID) }
            let changes = expansionChanges(for: children, expanding: true)
            expansionAnimationCoordinator.animateState(
                changes,
                motion: expansionMotion,
                animated: !context.reduceMotion,
                completion: { [weak self] in
                    guard let self, self.expansionAnimationGenerations[id] == generation else { return }
                    self.setLayerOpacity(children, to: 1)
                    self.pendingExpansionTargets[id] = nil
                    self.expansionAnimationGenerations[id] = nil
                }
            )
        } else {
            let children = (mainButtons + footerButtons).filter { childIDs.contains($0.itemID) }
            deferredRemovalButtons = children
            deferredRemovalDocumentHeight = mainItemsView.frame.height
            let changes = expansionChanges(for: children, expanding: false)
            expandedItemIDs.remove(id)
            reconcileButtons()
            needsLayout = true
            layoutSubtreeIfNeeded()
            animateNavigationReflow(from: oldFrames, motion: expansionMotion)
            expansionAnimationCoordinator.animateState(
                changes,
                motion: expansionMotion,
                animated: !context.reduceMotion,
                completion: { [weak self] in
                    guard let self, self.expansionAnimationGenerations[id] == generation else { return }
                    self.expandedItemIDs.remove(id)
                    self.pendingExpansionTargets[id] = nil
                    self.expansionAnimationGenerations[id] = nil
                    self.resetNavigationPointerState()
                    self.removeDeferredNavigationRows()
                    self.needsLayout = true
                    self.layoutSubtreeIfNeeded()
                    self.updateSelectionIndicator(animated: true)
                }
            )
        }
    }

    private func currentVisualFrame(of button: FluentNavigationItemButton<ID>) -> NSRect {
        guard let layer = button.layer else { return button.frame }
        let visualLayer = layer.presentation() ?? layer
        let size = layer.bounds.size
        return NSRect(
            x: visualLayer.position.x - size.width * layer.anchorPoint.x,
            y: visualLayer.position.y - size.height * layer.anchorPoint.y + visualLayer.transform.m42,
            width: size.width,
            height: size.height
        )
    }

    private func expansionChanges(
        for buttons: [FluentNavigationItemButton<ID>],
        expanding: Bool
    ) -> [FluentLayerAnimationChange] {
        buttons.flatMap { button -> [FluentLayerAnimationChange] in
            guard let layer = button.layer else { return [] }
            // WinUI reveals hierarchy rows as one translated branch. Collapsing every child
            // into the header point made long groups fan through one another. Keep their relative
            // spacing and use a short vertical reveal while following rows reflow separately.
            // Animate only the translation component: animating a view-backed layer's `position`
            // mixes AppKit's flipped view geometry with Core Animation coordinates and caused the
            // rows below an expanded group to fly horizontally outside the pane.
            let opacity = FluentLayerAnimationChange(
                layer: layer,
                key: "fluent.navigation.item.expansion",
                keyPath: "opacity",
                fromValue: expanding ? 0 : nil,
                toValue: expanding ? Float(1) : Float(0)
            ) { [weak layer] in layer?.opacity = expanding ? 1 : 0 }
            let position = FluentLayerAnimationChange(
                layer: layer,
                key: "fluent.navigation.item.expansion.position",
                keyPath: "transform.translation.y",
                fromValue: expanding ? -8 : 0,
                toValue: expanding ? 0 : -8,
                applyModelValue: {}
            )
            return [opacity, position]
        }
    }

    private func removeDeferredNavigationRows() {
        deferredRemovalButtons.forEach {
            navigationHoverCoordinator.remove($0)
            $0.removeFromSuperview()
        }
        deferredRemovalButtons.removeAll()
        deferredRemovalDocumentHeight = nil
    }

    /// Animates the row geometry after the flattened visible-item list changes. The model frames
    /// are already at their destination; explicit layer animations preserve that model while
    /// letting existing rows slide around the newly inserted/removed branch.
    private func animateNavigationReflow(
        from oldFrames: [ObjectIdentifier: NSRect],
        motion: FluentMotionToken
    ) {
        let changes = (mainButtons + footerButtons).flatMap { button -> [FluentLayerAnimationChange] in
            guard let layer = button.layer,
                  let oldFrame = oldFrames[ObjectIdentifier(button)],
                  oldFrame != button.frame else { return [] }
            // Group expansion is a vertical list operation. Keep each row's x coordinate and
            // width at the freshly arranged value; interpolating those as well can make a row
            // inherit a stale compact-pane coordinate and visibly slide sideways.
            let verticalOffset = oldFrame.midY - button.frame.midY
            return [FluentLayerAnimationChange(
                layer: layer,
                key: "fluent.navigation.item.reflow.position",
                keyPath: "transform.translation.y",
                fromValue: verticalOffset,
                toValue: 0,
                applyModelValue: {}
            )]
        }
        expansionAnimationCoordinator.animateState(
            changes,
            motion: motion,
            animated: !context.reduceMotion
        )
    }

    private func setLayerOpacity(_ buttons: [FluentNavigationItemButton<ID>], to opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        buttons.forEach { $0.layer?.opacity = opacity }
        CATransaction.commit()
    }

    private func descendantIDs(
        of id: ID,
        in source: [FluentNavigationItem<ID>]
    ) -> Set<ID> {
        for item in source {
            if item.id == id {
                return Set(Self.flatten(item.children).map(\.id))
            }
            let nested = descendantIDs(of: id, in: item.children)
            if !nested.isEmpty { return nested }
        }
        return []
    }

    private func visibleIndicatorID(for selected: ID) -> ID? {
        let visibleIDs = Set((visibleRows(in: items) + visibleRows(in: footerItems)).map { $0.item.id })
        if visibleIDs.contains(selected) { return selected }
        return nearestVisibleAncestor(of: selected, in: items + footerItems, visibleIDs: visibleIDs)
    }

    private func nearestVisibleAncestor(
        of selected: ID,
        in source: [FluentNavigationItem<ID>],
        visibleIDs: Set<ID>,
        ancestors: [ID] = []
    ) -> ID? {
        for item in source {
            if item.id == selected { return ancestors.reversed().first(where: visibleIDs.contains) }
            if let match = nearestVisibleAncestor(
                of: selected,
                in: item.children,
                visibleIDs: visibleIDs,
                ancestors: ancestors + [item.id]
            ) {
                return match
            }
        }
        return nil
    }

    private func resolveDisplayMode(for width: CGFloat) -> FluentNavigationViewDisplayMode {
        switch paneDisplayMode {
        case .automatic:
            if width >= expandedModeThresholdWidth { return .expanded }
            if width > 0, width < compactModeThresholdWidth { return .minimal }
            return .compact
        case .left: return .expanded
        case .leftCompact: return .compact
        case .leftMinimal: return .minimal
        case .top: return .top
        }
    }

    private func applyResolvedDisplayMode(_ mode: FluentNavigationViewDisplayMode) {
        let previousMode = resolvedDisplayMode
        resolvedDisplayMode = mode
        indicatorAnimator.setAxis(mode == .top ? .horizontal : .vertical)

        if !didResolveInitialMode {
            didResolveInitialMode = true
            if mode == .compact || mode == .minimal {
                assignPaneOpen(false, notifyBinding: true)
            }
        } else if previousMode == .expanded, mode == .compact || mode == .minimal {
            assignPaneOpen(false, notifyBinding: true)
        } else if mode == .expanded, !wasForceClosed {
            assignPaneOpen(true, notifyBinding: true)
        }

        panePresentationExpanded = mode == .top || (mode == .expanded && internalPaneOpen)
        retainsOverlayDuringAnimation = false
        onDisplayModeChange?(mode)
    }

    private func layoutCurrentState() {
        guard let mode = resolvedDisplayMode else { return }
        let isRTL = context.layoutDirection == .rightToLeft
        let overlayMode = mode == .compact || mode == .minimal
        let closedWidth: CGFloat = mode == .minimal ? 0 : compactPaneLength
        let paneWidth: CGFloat = mode == .top ? bounds.width : (internalPaneOpen ? openPaneLength : closedWidth)
        let reservedWidth: CGFloat = switch mode {
        case .expanded: paneWidth
        case .compact: compactPaneLength
        case .minimal, .top: 0
        }

        if mode == .top {
            paneView.frame = NSRect(x: 0, y: max(bounds.height - 48, 0), width: bounds.width, height: 48)
            contentColumnFrame = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height - 48, 0))
        } else if isRTL {
            paneView.frame = NSRect(x: bounds.width - paneWidth, y: 0, width: paneWidth, height: bounds.height)
            contentColumnFrame = NSRect(x: 0, y: 0, width: max(bounds.width - reservedWidth, 0), height: bounds.height)
        } else {
            paneView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: bounds.height)
            contentColumnFrame = NSRect(x: reservedWidth, y: 0, width: max(bounds.width - reservedWidth, 0), height: bounds.height)
        }
        paneMaterial?.frame = paneView.bounds
        layoutContentColumn(mode: mode)

        let showOverlay = overlayMode && (internalPaneOpen || retainsOverlayDuringAnimation)
        dimmingView.frame = contentColumnFrame
        dimmingView.isHidden = !showOverlay
        minimalToggleButton.isHidden = mode != .minimal || internalPaneOpen || !isPaneToggleButtonVisible
        minimalToggleButton.frame = NSRect(
            x: isRTL ? max(bounds.width - 44, 4) : 4,
            y: max(bounds.height - 40, 0),
            width: 40,
            height: 36
        )

        applyPaneMaterialOwnership()
        layoutPaneContent(mode: mode)
        stabilizePaneGeometry()
        refreshNavigationPointerState()
    }

    private func layoutContentColumn(mode: FluentNavigationViewDisplayMode) {
        guard let headerHost else {
            arrangeContentHost(in: contentColumnFrame)
            return
        }
        let headerHeight = min(max(headerHost.fittingSize.height, 0), 160)
        let avoidMinimalToggle = mode == .minimal && !internalPaneOpen && isPaneToggleButtonVisible
        let leadingInset = avoidMinimalToggle ? compactPaneLength : 0
        let isRTL = context.layoutDirection == .rightToLeft
        headerHost.frame = NSRect(
            x: contentColumnFrame.minX + (isRTL ? 0 : leadingInset),
            y: max(contentColumnFrame.maxY - headerHeight, contentColumnFrame.minY),
            width: max(contentColumnFrame.width - leadingInset, 0),
            height: headerHeight
        )
        arrangeContentHost(in: NSRect(
            x: contentColumnFrame.minX,
            y: contentColumnFrame.minY,
            width: contentColumnFrame.width,
            height: max(contentColumnFrame.height - headerHeight, 0)
        ))
    }

    private func arrangeContentHost(in frame: NSRect) {
        contentHost.frame = frame
        guard frame.width > 0, frame.height > 0,
              !contentHost.translatesAutoresizingMaskIntoConstraints else { return }
        contentHost.translatesAutoresizingMaskIntoConstraints = true
    }

    private var resolvedPaneMaterialOwnership: FluentNavigationPaneMaterialOwnership {
        guard paneMaterialOwnership == .automatic else { return paneMaterialOwnership }
        var ancestor = superview
        while let view = ancestor {
            if view.identifier?.rawValue == "FluentKit.WindowShell.MaterialSurface" {
                return .inherited
            }
            ancestor = view.superview
        }
        return .standalone
    }

    private func applyPaneMaterialOwnership() {
        switch resolvedPaneMaterialOwnership {
        case .automatic:
            break
        case .inherited:
            paneMaterial?.removeFromSuperview()
            paneMaterial = nil
            paneView.layer?.backgroundColor = nil
        case .standalone:
            let material: FluentMaterialView
            if let paneMaterial {
                material = paneMaterial
            } else {
                material = FluentMaterialView(material: .mica)
                material.autoresizingMask = [.width, .height]
                material.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.PaneMaterial")
                paneMaterial = material
            }
            if material.superview !== paneView {
                paneView.addSubview(material, positioned: .below, relativeTo: paneView.subviews.first)
            }
            material.frame = paneView.bounds
            material.materialStyle = .mica
            material.fluentTheme = context.theme
            material.isMaterialEnabled = context.theme.materialEffectsEnabled
            material.fallbackColor = context.theme.windowBackground
            material.tintColor = context.theme.micaTint
            paneView.layer?.backgroundColor = nil
        case .solid:
            paneMaterial?.removeFromSuperview()
            paneMaterial = nil
            paneView.layer?.backgroundColor = context.theme.windowBackground.cgColor
        }
    }

    private func layoutPaneContent(mode: FluentNavigationViewDisplayMode) {
        let top = mode == .top
        let expanded = top || panePresentationExpanded || (mode == .expanded && internalPaneOpen)
        paneToggleButton.isHidden = top || !isPaneToggleButtonVisible
        sectionLabel.stringValue = paneSectionTitle ?? ""
        // Section text has no compact representation. The header host is a clipped layout region,
        // matching NavigationViewItemHeader's InnerHeaderGrid rather than painting directly into
        // the pane while its width is collapsing.
        let shouldShowSectionLabel = !top && internalPaneOpen && expanded && paneSectionTitle != nil
        sectionLabelHost.isHidden = !shouldShowSectionLabel
        sectionLabel.isHidden = !shouldShowSectionLabel
        // Navigation search has a compact icon representation and therefore remains mounted when
        // the pane is closed. Other arbitrary pane headers keep the existing expanded-only rule.
        paneHeaderHost?.isHidden = !expanded && !paneHeaderContainsNavigationSearch
        updateButtonConfigurations()

        if top {
            layoutTopPane()
        } else {
            layoutLeftPane(expanded: expanded)
        }
    }

    private func layoutLeftPane(expanded: Bool) {
        topOverflowButton.isHidden = true
        mainScrollView.hasHorizontalScroller = false
        let mainRows = visibleRows(in: items)
        let footerRows = visibleRows(in: footerItems)
        let visibleMainPairs = Array(zip(mainButtons, mainRows)).filter { expanded || $0.1.depth == 0 }
        let visibleFooterPairs = Array(zip(footerButtons, footerRows)).filter { expanded || $0.1.depth == 0 }
        for (button, row) in zip(mainButtons, mainRows) { button.isHidden = !expanded && row.depth > 0 }
        for (button, row) in zip(footerButtons, footerRows) { button.isHidden = !expanded && row.depth > 0 }
        let paneWidth = max(paneView.bounds.width, expanded ? openPaneLength : compactPaneLength)
        var top: CGFloat = 4
        if !paneToggleButton.isHidden {
            paneToggleButton.frame = NSRect(x: 4, y: top, width: 40, height: 36)
            top += 40
        }

        if let paneHeaderHost, !paneHeaderHost.isHidden {
            let desiredHeight = min(max(paneHeaderHost.fittingSize.height, 0), 160)
            paneHeaderHost.frame = NSRect(x: 0, y: top, width: paneWidth, height: desiredHeight)
            top += desiredHeight
        }
        if !sectionLabelHost.isHidden {
            let headerHeight: CGFloat = 40
            sectionLabelHost.frame = NSRect(x: 0, y: top, width: paneWidth, height: headerHeight)
            sectionLabel.frame = NSRect(
                x: 16,
                y: 0,
                width: max(paneWidth - 32, 0),
                height: headerHeight
            )
            top += headerHeight
        } else {
            sectionLabelHost.frame = NSRect(x: 0, y: top, width: paneWidth, height: 0)
            sectionLabel.frame = .zero
        }

        let footerHeight = CGFloat(visibleFooterPairs.count) * (rowHeight + 2) + (visibleFooterPairs.isEmpty ? 0 : 8)
        let scrollBottom = max(paneView.bounds.height - footerHeight - 8, top)
        mainScrollView.frame = NSRect(x: 0, y: top, width: paneWidth, height: max(scrollBottom - top, 0))
        mainScrollView.tile()
        mainScrollView.layoutSubtreeIfNeeded()

        // Keep the compact 40pt icon column stable at the 48pt pane center. Expanded mode only
        // adds room to the trailing content; it must not move the icon or selection rail.
        let buttonWidth = max(paneWidth - 8, 40)
        let documentHeight = max(
            CGFloat(visibleMainPairs.count) * (rowHeight + 2) + 4,
            mainScrollView.contentSize.height,
            deferredRemovalDocumentHeight ?? 0
        )
        let previousScrollOrigin = mainScrollView.contentView.bounds.origin
        mainItemsView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: documentHeight)
        // NSScrollView may bottom-anchor a flipped document when its height changes. A hierarchy
        // toggle must keep the user's viewport anchored instead of revealing a clipped row at the
        // top or jumping several categories, as WinUI's ItemsRepeater scroll anchoring does.
        let maximumScrollY = max(documentHeight - mainScrollView.contentView.bounds.height, 0)
        let preservedScrollOrigin = NSPoint(
            x: 0,
            y: min(max(previousScrollOrigin.y, 0), maximumScrollY)
        )
        if mainScrollView.contentView.bounds.origin != preservedScrollOrigin {
            mainScrollView.contentView.scroll(to: preservedScrollOrigin)
            mainScrollView.reflectScrolledClipView(mainScrollView.contentView)
        }
        for (index, pair) in visibleMainPairs.enumerated() {
            let button = pair.0
            button.frame = NSRect(
                x: 4,
                y: 2 + CGFloat(index) * (rowHeight + 2),
                width: buttonWidth,
                height: rowHeight
            )
        }

        for (index, pair) in visibleFooterPairs.enumerated() {
            let button = pair.0
            button.frame = NSRect(
                x: 4,
                y: paneView.bounds.height - footerHeight + CGFloat(index) * (rowHeight + 2),
                width: buttonWidth,
                height: rowHeight
            )
        }
    }

    private var paneHeaderContainsNavigationSearch: Bool {
        guard let paneHeaderHost else { return false }
        return containsNavigationSearch(in: paneHeaderHost)
    }

    private func containsNavigationSearch(in view: NSView) -> Bool {
        if view.identifier?.rawValue == "FluentKit.NavigationView.Search" { return true }
        return view.subviews.contains(where: containsNavigationSearch(in:))
    }

    private func layoutTopPane() {
        let paneHeight: CGFloat = 48
        let isRTL = context.layoutDirection == .rightToLeft
        mainScrollView.hasHorizontalScroller = false
        let headerWidth: CGFloat
        if let paneHeaderHost, !paneHeaderHost.isHidden {
            headerWidth = min(max(paneHeaderHost.fittingSize.width, 0), 220)
            paneHeaderHost.frame = NSRect(
                x: isRTL ? paneView.bounds.width - headerWidth - 12 : 12,
                y: 0,
                width: headerWidth,
                height: paneHeight
            )
        } else {
            headerWidth = 0
        }

        var footerWidth: CGFloat = 0
        for button in footerButtons {
            footerWidth += topButtonWidth(button) + 4
        }
        let leading = headerWidth + (headerWidth > 0 ? 20 : 8)
        let availableWidth = max(paneView.bounds.width - leading - footerWidth - 8, 0)
        let itemWidths = mainButtons.map(topButtonWidth)
        let totalItemWidth = itemWidths.reduce(CGFloat(0), +) + CGFloat(max(mainButtons.count - 1, 0)) * 4
        let overflowWidth: CGFloat = 84
        var visibleIndices = Array(mainButtons.indices)
        if totalItemWidth > availableWidth {
            let itemBudget = max(availableWidth - overflowWidth - 4, 0)
            visibleIndices = []
            var used: CGFloat = 0
            for index in mainButtons.indices {
                let additional = itemWidths[index] + (visibleIndices.isEmpty ? 0 : 4)
                guard used + additional <= itemBudget else { break }
                visibleIndices.append(index)
                used += additional
            }
        }
        let visibleIndexSet = Set(visibleIndices)
        let topItems = visibleRows(in: items).map(\.item)
        let overflowItems = topItems.indices.compactMap { visibleIndexSet.contains($0) ? nil : topItems[$0] }
        for index in mainButtons.indices { mainButtons[index].isHidden = !visibleIndexSet.contains(index) }
        topOverflowButton.update(
            items: overflowItems,
            selectedID: selectedID,
            theme: context.theme,
            layoutDirection: context.layoutDirection.appKitValue,
            reduceMotion: context.reduceMotion,
            onSelect: { [weak self] id in self?.select(id) },
            onMoveFocus: { [weak self] move in
                guard let self else { return }
                self.moveFocus(from: self.topOverflowButton, move: move)
            }
        )
        topOverflowButton.isHidden = overflowItems.isEmpty
        let reservedOverflowWidth = overflowItems.isEmpty ? 0 : overflowWidth + 4
        let mainViewportWidth = max(availableWidth - reservedOverflowWidth, 0)
        mainScrollView.frame = NSRect(
            x: isRTL ? footerWidth + 8 + reservedOverflowWidth : leading,
            y: 4,
            width: mainViewportWidth,
            height: 40
        )
        mainScrollView.tile()
        mainScrollView.layoutSubtreeIfNeeded()
        mainItemsView.frame = NSRect(x: 0, y: 0, width: mainViewportWidth, height: 40)
        var itemX: CGFloat = isRTL ? mainViewportWidth : 0
        for index in visibleIndices {
            let button = mainButtons[index]
            let width = itemWidths[index]
            if isRTL {
                itemX -= width
                button.frame = NSRect(x: itemX, y: 0, width: width, height: 40)
                itemX -= 4
            } else {
                button.frame = NSRect(x: itemX, y: 0, width: width, height: 40)
                itemX += width + 4
            }
        }
        if !overflowItems.isEmpty {
            topOverflowButton.frame = NSRect(
                x: isRTL ? footerWidth + 8 : leading + mainViewportWidth + 4,
                y: 4,
                width: overflowWidth,
                height: 40
            )
        }

        var footerX = isRTL ? 8 : paneView.bounds.width - footerWidth
        for button in footerButtons {
            let width = topButtonWidth(button)
            button.frame = NSRect(x: footerX, y: 4, width: width, height: 40)
            footerX += width + 4
        }
    }

    private func topButtonWidth(_ button: FluentNavigationItemButton<ID>) -> CGFloat {
        min(max(button.titleWidth + 60, 64), 188)
    }

    private func installObservers() {
        installBindingObservers()
        let notificationCenter = NotificationCenter.default
        selectionGeometryObservers = [
            notificationCenter.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: mainScrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSelectionGeometryUpdate()
                self?.refreshNavigationPointerState()
            },
            notificationCenter.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: mainItemsView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSelectionGeometryUpdate()
                self?.refreshNavigationPointerState()
            },
            notificationCenter.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: mainItemsView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSelectionGeometryUpdate()
                self?.refreshNavigationPointerState()
            },
            notificationCenter.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object as? NSWindow === self?.window else { return }
                self?.resetNavigationPointerState()
            }
        ]
    }

    private func setHoveredNavigationButton(
        _ button: FluentNavigationItemButton<ID>,
        hovering: Bool
    ) {
        navigationHoverCoordinator.update(button, hovering: hovering)
    }

    private func resetNavigationPointerState() {
        let buttons = mainButtons + footerButtons
        navigationHoverCoordinator.reset(items: buttons)
        buttons.forEach { $0.resetPointerState() }
    }

    private func refreshNavigationPointerState() {
        guard let window, window.isVisible, window.isKeyWindow else {
            resetNavigationPointerState()
            return
        }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let buttons = (mainButtons + footerButtons).filter { !$0.isHidden && $0.isEnabled }
        guard let button = buttons.first(where: {
            $0.bounds.contains($0.convert(windowPoint, from: nil))
        }) else {
            resetNavigationPointerState()
            return
        }
        setHoveredNavigationButton(button, hovering: true)
    }

    private func scheduleSelectionGeometryUpdate(animated: Bool = false) {
        pendingIndicatorAnimation = pendingIndicatorAnimation || animated
        guard !selectionGeometryUpdateScheduled else { return }
        selectionGeometryUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.selectionGeometryUpdateScheduled = false
            let shouldAnimate = self.pendingIndicatorAnimation
            self.pendingIndicatorAnimation = false
            self.layoutSubtreeIfNeeded()
            self.stabilizePaneGeometry()
            self.updateSelectionIndicator(animated: shouldAnimate)
        }
    }

    private func stabilizePaneGeometry() {
        guard !isStabilizingPaneGeometry,
              paneView.bounds.width > 0,
              paneView.bounds.height > 0 else { return }
        isStabilizingPaneGeometry = true
        defer { isStabilizingPaneGeometry = false }

        paneView.layoutSubtreeIfNeeded()
        mainScrollView.tile()
        mainScrollView.layoutSubtreeIfNeeded()
        mainScrollView.contentView.layoutSubtreeIfNeeded()
        mainItemsView.layoutSubtreeIfNeeded()
    }

    private func installBindingObservers() {
        observedSelection = selection
        selectionObserverID = selection.observe { [weak self] value in
            self?.applySelection(value, animated: true)
        }
        observedPaneOpen = paneOpenBinding
        paneOpenObserverID = paneOpenBinding?.observe { [weak self] open in
            guard let self, !self.isSynchronizingPaneBinding else { return }
            self.wasForceClosed = !open
            self.setPaneOpen(open, userInitiated: false, animated: true, notifyBinding: false)
        }
    }

    private func removeBindingObservers() {
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
        if let paneOpenObserverID { observedPaneOpen?.removeObserver(paneOpenObserverID) }
        selectionObserverID = nil
        paneOpenObserverID = nil
        observedSelection = nil
        observedPaneOpen = nil
    }

    private func sanitizeSelectionIfNeeded() {
        guard !isSanitizingSelection, let selected = selection.get() else { return }
        let matches = Self.flatten(items + footerItems).filter { $0.id == selected && $0.isEnabled }
        guard matches.count != 1 else { return }
        isSanitizingSelection = true
        selection.set(nil)
        isSanitizingSelection = false
    }

    private func applySelection(_ id: ID?, animated: Bool) {
        let available = Self.flatten(items + footerItems).filter { $0.id == id && $0.isEnabled }
        let resolved = available.count == 1 ? id : nil
        if id != nil, resolved == nil, !isSanitizingSelection {
            isSanitizingSelection = true
            selection.set(nil)
            isSanitizingSelection = false
        }
        let changed = selectedID != resolved
        isApplyingSelectionTransition = animated && changed
        defer { isApplyingSelectionTransition = false }
        selectedID = resolved
        updateButtonConfigurations()
        guard bounds.width > 0, bounds.height > 0 else {
            // Match NavigationView's post-measure LayoutUpdated behavior: selection state may
            // commit immediately, but geometry and animation wait for a non-empty arrange slot.
            pendingIndicatorAnimation = pendingIndicatorAnimation || (animated && changed)
            needsLayout = true
            return
        }
        layoutSubtreeIfNeeded()
        stabilizePaneGeometry()
        updateSelectionIndicator(animated: animated && changed)
    }

    private func select(_ id: ID) {
        guard Self.flatten(items + footerItems).contains(where: { $0.id == id && $0.isEnabled }) else { return }
        if selection.get() != id { selection.set(id) }
        applySelection(id, animated: true)
        closeOverlayPaneIfNeeded()
        context.invalidate?()
    }

    private func selectionIndicatorTarget() -> NSRect? {
        guard let selectedID,
              paneView.bounds.width > 0,
              paneView.bounds.height > 0 else { return nil }
        let indicatorID = visibleIndicatorID(for: selectedID) ?? selectedID
        let selectedButton = (mainButtons + footerButtons).first(where: { $0.itemID == indicatorID && !$0.isHidden })
        let indicatorView: NSView? = selectedButton ?? (topOverflowButton.contains(indicatorID) ? topOverflowButton : nil)
        guard let indicatorView else { return nil }
        let frame = indicatorView.convert(indicatorView.bounds, to: paneView)
        if resolvedDisplayMode == .top {
            return NSRect(x: frame.midX - 8, y: frame.maxY - 5, width: 16, height: 3)
        }
        let x = context.layoutDirection == .rightToLeft ? frame.maxX - 5 : frame.minX + 2
        return NSRect(x: x, y: frame.midY - 8, width: 3, height: 16)
    }

    private func updateSelectionIndicator(animated: Bool) {
        guard let target = selectionIndicatorTarget() else {
            indicatorAnimator.update(
                target: nil,
                color: context.theme.accentFillDefault,
                animated: false,
                reduceMotion: context.reduceMotion
            )
            return
        }
        indicatorAnimator.update(
            target: target,
            color: context.theme.accentFillDefault,
            animated: animated,
            reduceMotion: context.reduceMotion
        )
    }

    private func moveFocus(from id: ID, move: FluentNavigationFocusMove) {
        guard let current = (mainButtons + footerButtons).first(where: { $0.itemID == id }) else { return }
        moveFocus(from: current, move: move)
    }

    private func moveFocus(from current: NSButton, move: FluentNavigationFocusMove) {
        let buttons: [NSButton]
        if resolvedDisplayMode == .top {
            var topButtons: [NSButton] = mainButtons.filter { $0.isEnabled && !$0.isHidden }
            if !topOverflowButton.isHidden { topButtons.append(topOverflowButton) }
            topButtons.append(contentsOf: footerButtons.filter(\.isEnabled))
            buttons = topButtons
        } else {
            buttons = (mainButtons + footerButtons).filter(\.isEnabled)
        }
        guard !buttons.isEmpty else { return }
        let currentIndex = buttons.firstIndex { $0 === current } ?? 0
        let targetIndex: Int = switch move {
        case .backward: max(currentIndex - 1, 0)
        case .forward: min(currentIndex + 1, buttons.count - 1)
        case .start: 0
        case .end: buttons.count - 1
        }
        let target = buttons[targetIndex]
        window?.makeFirstResponder(target)
        if let target = target as? FluentNavigationItemButton<ID>, target.superview === mainItemsView {
            mainItemsView.scrollToVisible(target.frame)
        }
    }

    private func togglePane() {
        setPaneOpen(!internalPaneOpen, userInitiated: true, animated: true)
    }

    private func closeOverlayPaneIfNeeded() {
        guard resolvedDisplayMode == .compact || resolvedDisplayMode == .minimal else { return }
        setPaneOpen(false, userInitiated: true, animated: true)
    }

    private func assignPaneOpen(_ open: Bool, notifyBinding: Bool) {
        internalPaneOpen = open
        paneToggleButton.update(theme: context.theme, layoutDirection: context.layoutDirection, isPaneOpen: open)
        minimalToggleButton.update(theme: context.theme, layoutDirection: context.layoutDirection, isPaneOpen: open)
        guard notifyBinding, paneOpenBinding?.get() != open else { return }
        isSynchronizingPaneBinding = true
        paneOpenBinding?.set(open)
        isSynchronizingPaneBinding = false
    }

    private func setPaneOpen(
        _ open: Bool,
        userInitiated: Bool,
        animated: Bool,
        notifyBinding: Bool = true
    ) {
        guard resolvedDisplayMode != .top, internalPaneOpen != open else { return }
        if userInitiated { wasForceClosed = !open }
        let oldPaneFrame = paneView.frame
        let oldContentFrame = contentHost.frame
        let oldHeaderFrame = headerHost?.frame
        let oldMainScrollFrame = mainScrollView.frame
        let hadVisibleSectionLabel = !sectionLabelHost.isHidden && paneSectionTitle != nil
        let oldDimmingOpacity = dimmingView.layer?.presentation()?.opacity ?? (dimmingView.isHidden ? 0 : 1)

        paneAnimationGeneration += 1
        let generation = paneAnimationGeneration
        sectionLabelTransitionGeneration += 1
        let sectionGeneration = sectionLabelTransitionGeneration
        paneView.layer?.removeAnimation(forKey: "fluent.navigation.pane.frame")
        contentHost.layer?.removeAnimation(forKey: "fluent.navigation.content.frame")
        dimmingView.layer?.removeAnimation(forKey: "fluent.navigation.dimming")
        mainScrollView.layer?.removeAnimation(forKey: "fluent.navigation.header.frame")
        sectionLabel.layer?.removeAnimation(forKey: "fluent.navigation.header.opacity")

        let shouldAnimateSectionLabel = animated && !context.reduceMotion && paneSectionTitle != nil
            && (hadVisibleSectionLabel || open)
        if shouldAnimateSectionLabel {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sectionLabel.layer?.opacity = open ? 0 : 1
            CATransaction.commit()
        }

        // The pane frame and its child layout must enter the same visual state before the
        // frame animation starts. Keeping expanded labels inside a 48pt model bounds causes
        // clipped section text and a visible jump on the first collapsed frame.
        panePresentationExpanded = open || resolvedDisplayMode == .top
        retainsOverlayDuringAnimation = resolvedDisplayMode == .compact || resolvedDisplayMode == .minimal
        assignPaneOpen(open, notifyBinding: notifyBinding)
        layoutCurrentState()

        guard animated, !context.reduceMotion else {
            // A manually closed `.left` pane still resolves to `.expanded`; its presenter must
            // nevertheless use compact item geometry while the model width is 48pt. Basing this
            // on the display mode re-enabled labels after the close animation completed.
            panePresentationExpanded = open || resolvedDisplayMode == .top
            retainsOverlayDuringAnimation = open && (resolvedDisplayMode == .compact || resolvedDisplayMode == .minimal)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sectionLabel.layer?.opacity = open && paneSectionTitle != nil ? 1 : 0
            CATransaction.commit()
            layoutCurrentState()
            updateSelectionIndicator(animated: false)
            return
        }

        let motion = open ? FluentMotion.navigationPaneOpen : FluentMotion.navigationPaneClose
        let headerMotion = open ? FluentMotion.navigationHeaderOpen : FluentMotion.navigationHeaderClose
        indicatorAnimator.relayout(
            target: selectionIndicatorTarget(),
            color: context.theme.accentFillDefault,
            animated: true,
            reduceMotion: context.reduceMotion,
            duration: headerMotion.duration,
            timingFunction: headerMotion.curve.timingFunction
        )
        animateFrame(
            of: paneView,
            from: oldPaneFrame,
            duration: motion.duration,
            timingFunction: motion.curve.timingFunction,
            key: "fluent.navigation.pane.frame"
        )
        animateFrame(
            of: contentHost,
            from: oldContentFrame,
            duration: motion.duration,
            timingFunction: motion.curve.timingFunction,
            key: "fluent.navigation.content.frame"
        )
        if oldMainScrollFrame != mainScrollView.frame {
            animateFrame(
                of: mainScrollView,
                from: oldMainScrollFrame,
                duration: headerMotion.duration,
                timingFunction: headerMotion.curve.timingFunction,
                key: "fluent.navigation.header.frame"
            )
        }
        if shouldAnimateSectionLabel {
            animateSectionLabel(open: open, generation: sectionGeneration)
        }
        if let headerHost, let oldHeaderFrame {
            animateFrame(
                of: headerHost,
                from: oldHeaderFrame,
                duration: motion.duration,
                timingFunction: motion.curve.timingFunction,
                key: "fluent.navigation.header.frame"
            )
        }
        animateDimming(
            from: oldDimmingOpacity,
            to: open && (resolvedDisplayMode == .compact || resolvedDisplayMode == .minimal) ? 1 : 0,
            duration: motion.duration,
            timingFunction: motion.curve.timingFunction
        )

        let delegate = FluentNavigationAnimationCompletionDelegate { [weak self] in
            guard let self, self.paneAnimationGeneration == generation else { return }
            self.panePresentationExpanded = open || self.resolvedDisplayMode == .top
            self.retainsOverlayDuringAnimation = open && (self.resolvedDisplayMode == .compact || self.resolvedDisplayMode == .minimal)
            self.layoutCurrentState()
            self.updateSelectionIndicator(animated: false)
            self.paneAnimationDelegate = nil
        }
        paneAnimationDelegate = delegate
        let completion = CABasicAnimation(keyPath: "opacity")
        completion.fromValue = 1
        completion.toValue = 1
        completion.duration = motion.duration
        completion.delegate = delegate
        paneView.layer?.add(completion, forKey: "fluent.navigation.pane.completion")
    }

    private func animateSectionLabel(open: Bool, generation: Int) {
        guard let layer = sectionLabel.layer else { return }
        let motion = open ? FluentMotion.navigationHeaderOpen : FluentMotion.navigationHeaderClose
        let targetOpacity: Float = open ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = targetOpacity
        CATransaction.commit()

        let opacity: CAAnimation
        if open {
            let keyframes = CAKeyframeAnimation(keyPath: "opacity")
            keyframes.values = [0, 0, 1]
            keyframes.keyTimes = [0, 0.5, 1]
            keyframes.duration = motion.duration
            // NavigationView.xaml holds HeaderText at zero for the first 100ms, then applies
            // the header spline only to the 100-200ms fade. A group-level timing function warps
            // the 0.5 key time and makes the label visible too early.
            keyframes.timingFunctions = [
                FluentCubicBezier.linear.timingFunction,
                motion.curve.timingFunction
            ]
            opacity = keyframes
        } else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = targetOpacity
            fade.duration = motion.duration
            fade.timingFunction = motion.curve.timingFunction
            opacity = fade
        }
        opacity.isRemovedOnCompletion = true
        layer.add(opacity, forKey: "fluent.navigation.header.opacity")

        guard !open else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + FluentMotion.navigationHeaderClose.duration) { [weak self] in
            guard let self,
                  self.sectionLabelTransitionGeneration == generation else { return }
            self.sectionLabelHost.isHidden = true
            self.sectionLabel.isHidden = true
            self.layoutCurrentState()
            self.updateSelectionIndicator(animated: false)
        }
    }

    private func animateFrame(
        of view: NSView,
        from oldFrame: NSRect,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        key: String
    ) {
        guard let layer = view.layer, oldFrame != view.frame else { return }
        let anchor = layer.anchorPoint
        let oldPosition = NSPoint(
            x: oldFrame.minX + oldFrame.width * anchor.x,
            y: oldFrame.minY + oldFrame.height * anchor.y
        )
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: oldPosition)
        position.toValue = NSValue(point: layer.position)
        let bounds = CABasicAnimation(keyPath: "bounds.size")
        bounds.fromValue = NSValue(size: oldFrame.size)
        bounds.toValue = NSValue(size: layer.bounds.size)
        let group = CAAnimationGroup()
        group.animations = [position, bounds]
        group.duration = duration
        group.timingFunction = timingFunction
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: key)
    }

    private func animateDimming(
        from: Float,
        to: Float,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        guard let layer = dimmingView.layer, from != to else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.commit()
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = from
        opacity.toValue = to
        opacity.duration = duration
        opacity.timingFunction = timingFunction
        opacity.isRemovedOnCompletion = true
        layer.add(opacity, forKey: "fluent.navigation.dimming")
    }

    deinit {
        removeBindingObservers()
        selectionGeometryObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

private final class FluentNavigationSectionLabelHost: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class FluentNavigationPaneBackgroundView: NSView {
    override var isFlipped: Bool { true }

}

private final class FluentNavigationItemsView: NSView {
    override var isFlipped: Bool { true }
}

private final class FluentNavigationDismissView: NSControl {
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    var onDismiss: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(theme.isDark ? 0.18 : 0.08).setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) { onDismiss?() }
}

private final class FluentNavigationPaneToggleButton: NSButton {
    var onToggle: (() -> Void)?
    private var fluentTheme: FluentTheme = .current
    private var layoutDirection: FluentLayoutDirection = .leftToRight
    private var paneOpen = true
    private var pointerOver = false
    private var pressed = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(invoke)
        toolTip = "Toggle navigation pane"
        setAccessibilityRole(.button)
        setAccessibilityTitle("Toggle navigation pane")
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(theme: FluentTheme, layoutDirection: FluentLayoutDirection, isPaneOpen: Bool) {
        fluentTheme = theme
        self.layoutDirection = layoutDirection
        paneOpen = isPaneOpen
        setAccessibilityValue(isPaneOpen ? "Expanded" : "Collapsed")
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { pointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerOver = false; pressed = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        FluentFocusVisibility.markPointerInteraction(in: window)
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor = pressed
            ? fluentTheme.controlFillTertiary
            : (pointerOver ? fluentTheme.controlFillSecondary : .clear)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let symbol = "line.3.horizontal"
        let color = fluentTheme.textPrimary
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Toggle navigation pane") {
            let point = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let tint = NSImage.SymbolConfiguration(hierarchicalColor: color)
            image.withSymbolConfiguration(point.applying(tint))?.draw(
                in: NSRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
            )
        }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            fluentTheme.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = fluentTheme.focusStrokeWidth
            path.stroke()
        }
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        needsDisplay = true
        if event.keyCode == 36 || event.keyCode == 49 { performClick(nil) } else { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isHidden else { return false }
        performClick(nil)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { needsDisplay = true }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { needsDisplay = true }
        return result
    }

    @objc private func invoke() { onToggle?() }
}

private final class FluentNavigationItemButton<ID: Hashable>: NSButton {
    private(set) var itemID: ID
    private var itemTitle: String
    private var systemImageName: String
    private var selected = false
    private var expanded = true
    private var top = false
    private var depth = 0
    private var hasChildren = false
    private var itemExpanded = false
    private var fluentTheme: FluentTheme = .current
    private var layoutDirection: FluentLayoutDirection = .leftToRight
    private var pointerState = FluentPointerInteractionState()
    private var onActivate: ((ID) -> Void)?
    private var onMoveFocus: ((ID, FluentNavigationFocusMove) -> Void)?
    private var onCancel: (() -> Void)?
    private var onHoverChange: ((FluentNavigationItemButton<ID>, Bool) -> Void)?
    private let chevronLayer = FluentChevronPrimitiveLayer()
    private lazy var pointerTrackingAreaHost = FluentTrackingAreaHost(
        view: self,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
    )

    var titleWidth: CGFloat {
        (itemTitle as NSString).size(withAttributes: [.font: fluentTheme.typography.font(for: .body)]).width
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    init(item: FluentNavigationItem<ID>) {
        itemID = item.id
        itemTitle = item.title
        systemImageName = item.systemImageName
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        chevronLayer.name = "FluentKit.NavigationView.ItemChevron"
        layer?.addSublayer(chevronLayer)
        target = self
        action = #selector(invoke)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Item")
        setAccessibilityRole(.button)
        setAccessibilityTitle(item.title)
        pointerTrackingAreaHost.update()
        isEnabled = item.isEnabled
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        pointerTrackingAreaHost.update()
    }

    func update(
        item: FluentNavigationItem<ID>,
        selected: Bool,
        expanded: Bool,
        top: Bool,
        depth: Int,
        hasChildren: Bool,
        itemExpanded: Bool,
        theme: FluentTheme,
        layoutDirection: FluentLayoutDirection,
        onActivate: @escaping (ID) -> Void,
        onMoveFocus: @escaping (ID, FluentNavigationFocusMove) -> Void,
        onCancel: @escaping () -> Void,
        onHoverChange: @escaping (FluentNavigationItemButton<ID>, Bool) -> Void
    ) {
        itemID = item.id
        itemTitle = item.title
        systemImageName = item.systemImageName
        let expansionChanged = self.itemExpanded != itemExpanded
        self.selected = selected
        self.expanded = expanded
        self.top = top
        self.depth = depth
        self.hasChildren = hasChildren
        self.itemExpanded = itemExpanded
        fluentTheme = theme
        self.layoutDirection = layoutDirection
        self.onActivate = onActivate
        self.onMoveFocus = onMoveFocus
        self.onCancel = onCancel
        self.onHoverChange = onHoverChange
        isEnabled = item.isEnabled
        if !isEnabled { resetPointerState() }
        toolTip = expanded || top ? nil : item.title
        setAccessibilityTitle(item.title)
        setAccessibilitySelected(selected)
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        chevronLayer.isHidden = !hasChildren || (!expanded && !top)
        updateChevron(animated: expansionChanged)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateChevron(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        onHoverChange?(self, true)
        updateChevron(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(self, false)
        updateChevron(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        pointerState.setPressed(true)
        needsDisplay = true
        super.mouseDown(with: event)
        pointerState.setPressed(false)
        onHoverChange?(self, bounds.contains(convert(event.locationInWindow, from: nil)))
        updateChevron(animated: true)
        needsDisplay = true
    }

    func setPointerOver(_ value: Bool) {
        let hoverChanged = pointerState.setPointerOver(value)
        let pressChanged = !value && pointerState.setPressed(false)
        guard hoverChanged || pressChanged else { return }
        updateChevron(animated: true)
        needsDisplay = true
    }

    func resetPointerState() {
        guard pointerState.reset() else { return }
        updateChevron(animated: false)
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { needsDisplay = true }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { needsDisplay = true }
        return result
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        needsDisplay = true
        let backwardsKey = top ? (layoutDirection == .rightToLeft ? 124 : 123) : 126
        let forwardsKey = top ? (layoutDirection == .rightToLeft ? 123 : 124) : 125
        switch Int(event.keyCode) {
        case backwardsKey: onMoveFocus?(itemID, .backward)
        case forwardsKey: onMoveFocus?(itemID, .forward)
        case 115: onMoveFocus?(itemID, .start)
        case 119: onMoveFocus?(itemID, .end)
        case 53: onCancel?()
        case 36, 49: performClick(nil)
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor
        if !isEnabled {
            background = selected ? fluentTheme.controlFillSecondary : .clear
        } else if selected, pointerState.isPressed {
            background = fluentTheme.controlFillSecondary
        } else if selected, pointerState.isPointerOver {
            background = fluentTheme.controlFillTertiary
        } else if selected {
            background = fluentTheme.controlFillSecondary
        } else if pointerState.isPressed {
            background = fluentTheme.controlFillTertiary
        } else if pointerState.isPointerOver {
            background = fluentTheme.controlFillSecondary
        } else {
            background = .clear
        }
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        let color = isEnabled ? fluentTheme.textPrimary : fluentTheme.textDisabled
        let iconSize: CGFloat = 18
        let isRTL = layoutDirection == .rightToLeft
        let indent = top ? 0 : CGFloat(depth) * 20
        let iconX: CGFloat
        if top {
            iconX = isRTL ? bounds.maxX - 28 : 10
        } else if expanded {
            iconX = isRTL ? bounds.maxX - 29 - indent : 11 + indent
        } else {
            iconX = bounds.midX - iconSize / 2
        }
        if let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: itemTitle) {
            let point = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let tint = NSImage.SymbolConfiguration(hierarchicalColor: color)
            image.withSymbolConfiguration(point.applying(tint))?.draw(
                in: NSRect(x: iconX, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)
            )
        }

        if expanded || top {
            let font = fluentTheme.typography.font(for: .body)
            let textSize = (itemTitle as NSString).size(withAttributes: [.font: font])
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = isRTL ? .right : .left
            let textX: CGFloat = isRTL ? 10 + (hasChildren ? 28 : 0) : 42 + indent
            (itemTitle as NSString).draw(
                in: NSRect(
                    x: textX,
                    y: bounds.midY - textSize.height / 2,
                    width: max(bounds.width - textX - (hasChildren ? 34 : 10), 0),
                    height: textSize.height
                ),
                withAttributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
            )
        }

        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            fluentTheme.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = fluentTheme.focusStrokeWidth
            path.stroke()
        }
    }

    private func updateChevron(animated: Bool) {
        guard hasChildren, expanded || top, bounds.width > 0, bounds.height > 0 else {
            chevronLayer.isHidden = true
            return
        }
        chevronLayer.isHidden = false
        let state: FluentControlState = !isEnabled
            ? .disabled
            : (pointerState.isPressed ? .pressed : (pointerState.isPointerOver ? .pointerOver : .normal))
        let color = isEnabled ? fluentTheme.textSecondary : fluentTheme.textDisabled
        let isRTL = layoutDirection == .rightToLeft
        chevronLayer.update(
            frame: NSRect(
                x: isRTL ? bounds.minX + 14 : bounds.maxX - 26,
                y: bounds.midY - 6,
                width: 12,
                height: 12
            ),
            color: color,
            state: state,
            visual: .upDownSmall,
            direction: itemExpanded ? .down : (isRTL ? .left : .right),
            backingScale: window?.backingScaleFactor,
            animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @objc private func invoke() { if isEnabled { onActivate?(itemID) } }
}

private final class FluentNavigationOverflowButton<ID: Hashable>: NSButton {
    private var items: [FluentNavigationItem<ID>] = []
    private var selectedID: ID?
    private var fluentTheme: FluentTheme = .current
    private var layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
    private var reduceMotion = false
    private var onSelect: ((ID) -> Void)?
    private var onMoveFocus: ((FluentNavigationFocusMove) -> Void)?
    private var pointerOver = false
    private var pressed = false
    private var flyout: FluentMenuFlyout?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(showOverflow)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Overflow")
        toolTip = "More navigation items"
        setAccessibilityRole(.popUpButton)
        setAccessibilityTitle("More")
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        items: [FluentNavigationItem<ID>],
        selectedID: ID?,
        theme: FluentTheme,
        layoutDirection: NSUserInterfaceLayoutDirection,
        reduceMotion: Bool,
        onSelect: @escaping (ID) -> Void,
        onMoveFocus: @escaping (FluentNavigationFocusMove) -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
        fluentTheme = theme
        self.layoutDirection = layoutDirection
        self.reduceMotion = reduceMotion
        userInterfaceLayoutDirection = layoutDirection
        self.onSelect = onSelect
        self.onMoveFocus = onMoveFocus
        let containsSelection = items.contains { $0.id == selectedID }
        setAccessibilitySelected(containsSelection)
        setAccessibilityValue(containsSelection ? "Contains selected item" : nil)
        needsDisplay = true
    }

    func contains(_ id: ID) -> Bool { items.contains { $0.id == id } }

    override func mouseEntered(with event: NSEvent) { pointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerOver = false; pressed = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        FluentFocusVisibility.markPointerInteraction(in: window)
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        needsDisplay = true
        let backwardKey: UInt16 = layoutDirection == .rightToLeft ? 124 : 123
        let forwardKey: UInt16 = layoutDirection == .rightToLeft ? 123 : 124
        switch event.keyCode {
        case backwardKey: onMoveFocus?(.backward)
        case forwardKey: onMoveFocus?(.forward)
        case 115: onMoveFocus?(.start)
        case 119: onMoveFocus?(.end)
        case 36, 49: performClick(nil)
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let containsSelection = selectedID.map(contains) ?? false
        let background: NSColor
        if pressed {
            background = fluentTheme.controlFillTertiary
        } else if pointerOver || containsSelection {
            background = fluentTheme.controlFillSecondary
        } else {
            background = .clear
        }
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        let color = fluentTheme.textPrimary
        let rightToLeft = layoutDirection == .rightToLeft
        if let image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More") {
            let point = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let tint = NSImage.SymbolConfiguration(hierarchicalColor: color)
            image.withSymbolConfiguration(point.applying(tint))?.draw(
                in: NSRect(x: rightToLeft ? bounds.maxX - 28 : 10, y: bounds.midY - 9, width: 18, height: 18)
            )
        }
        let font = fluentTheme.typography.font(for: .body)
        let text = "More" as NSString
        let textSize = text.size(withAttributes: [.font: font])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        text.draw(
            in: NSRect(
                x: rightToLeft ? 6 : 36,
                y: bounds.midY - textSize.height / 2,
                width: max(bounds.width - 42, 0),
                height: textSize.height
            ),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        )
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            fluentTheme.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = fluentTheme.focusStrokeWidth
            path.stroke()
        }
    }

    @objc private func showOverflow() {
        guard !items.isEmpty else { return }
        let menuItems = items.map { item in
            FluentMenuItem(
                item.title,
                systemImageName: item.systemImageName,
                isEnabled: item.isEnabled,
                state: item.id == selectedID ? .on : .off
            ) { [weak self] in self?.onSelect?(item.id) }
        }
        let flyout = FluentMenuFlyout(
            items: menuItems,
            theme: fluentTheme,
            minimumWidth: 180,
            reduceMotion: reduceMotion
        )
        self.flyout = flyout
        flyout.present(relativeTo: self, placement: .below)
    }
}

private final class FluentNavigationAnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: () -> Void

    init(completion: @escaping () -> Void) { self.completion = completion }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        completion()
    }
}
