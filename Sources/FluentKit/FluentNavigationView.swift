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

/// Stable metadata for one primary or footer destination in a `FluentNavigationView`.
public struct FluentNavigationItem<ID: Hashable> {
    public let id: ID
    public let title: String
    public let systemImageName: String
    public let isEnabled: Bool

    public init(
        id: ID,
        title: String,
        systemImageName: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
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
    private var paneHeader: FluentAnyView?
    private var header: FluentAnyView?
    private var content: FluentAnyView
    private var onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?
    private var context: FluentRenderContext

    private let contentHost: FluentViewHost<FluentAnyView>
    private var headerHost: FluentViewHost<FluentAnyView>?
    private let paneView = FluentNavigationPaneBackgroundView()
    private let dimmingView = FluentNavigationDismissView()
    private let minimalToggleButton = FluentNavigationPaneToggleButton()
    private let paneToggleButton = FluentNavigationPaneToggleButton()
    private let topOverflowButton = FluentNavigationOverflowButton<ID>()
    private let mainScrollView = NSScrollView()
    private let mainItemsView = FluentNavigationItemsView()
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
    private var scrollObserver: NSObjectProtocol?
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
        self.paneHeader = paneHeader
        self.header = header
        self.content = content
        self.onDisplayModeChange = onDisplayModeChange
        self.context = context
        internalPaneOpen = isPaneOpen?.get() ?? true
        selectedID = selection.get()
        contentHost = FluentViewHost(content, context: context)
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Navigation view")

        contentHost.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Content")
        contentHost.translatesAutoresizingMaskIntoConstraints = true
        contentHost.wantsLayer = true
        paneView.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Pane")
        paneView.wantsLayer = true
        paneView.layer?.masksToBounds = true
        if let paneLayer = paneView.layer {
            indicatorAnimator.attach(to: paneLayer)
        }

        dimmingView.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.DismissLayer")
        dimmingView.onDismiss = { [weak self] in self?.setPaneOpen(false, userInitiated: true, animated: true) }
        dimmingView.isHidden = true

        paneToggleButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.PaneToggle")
        paneToggleButton.onToggle = { [weak self] in self?.togglePane() }
        minimalToggleButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.MinimalPaneToggle")
        minimalToggleButton.onToggle = { [weak self] in self?.togglePane() }

        mainScrollView.drawsBackground = false
        mainScrollView.hasVerticalScroller = true
        mainScrollView.hasHorizontalScroller = true
        mainScrollView.autohidesScrollers = true
        mainScrollView.borderType = .noBorder
        mainScrollView.documentView = mainItemsView
        mainScrollView.contentView.postsBoundsChangedNotifications = true

        sectionLabel.font = context.theme.typography.font(for: .caption)
        sectionLabel.textColor = context.theme.textSecondary
        sectionLabel.lineBreakMode = .byTruncatingTail
        sectionLabel.isSelectable = false
        sectionLabel.isEditable = false
        sectionLabel.isBordered = false
        sectionLabel.drawsBackground = false

        addSubview(contentHost)
        addSubview(dimmingView)
        reconcileHeader()
        addSubview(paneView)
        addSubview(minimalToggleButton)
        paneView.addSubview(paneToggleButton)
        paneView.addSubview(topOverflowButton)
        paneView.addSubview(sectionLabel)
        paneView.addSubview(mainScrollView)

        reconcilePaneHeader()
        reconcileButtons()
        installObservers()
        sanitizeSelectionIfNeeded()
        applySelection(selection.get(), animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let mode = resolveDisplayMode(for: bounds.width)
        if resolvedDisplayMode != mode {
            applyResolvedDisplayMode(mode)
        }
        layoutCurrentState()
        updateSelectionIndicator(animated: false)
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
        paneHeader: FluentAnyView?,
        header: FluentAnyView?,
        content: FluentAnyView,
        onDisplayModeChange: ((FluentNavigationViewDisplayMode) -> Void)?,
        context: FluentRenderContext
    ) {
        removeBindingObservers()
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
        self.paneHeader = paneHeader
        self.header = header
        self.content = content
        self.onDisplayModeChange = onDisplayModeChange
        self.context = context
        internalPaneOpen = isPaneOpen?.get() ?? internalPaneOpen
        panePresentationExpanded = resolvedDisplayMode == .top || internalPaneOpen

        contentHost.context = context
        contentHost.update(content)
        paneView.theme = context.theme
        paneView.layoutDirection = context.layoutDirection
        dimmingView.theme = context.theme
        paneToggleButton.update(theme: context.theme, layoutDirection: context.layoutDirection, isPaneOpen: internalPaneOpen)
        minimalToggleButton.update(theme: context.theme, layoutDirection: context.layoutDirection, isPaneOpen: internalPaneOpen)
        sectionLabel.font = context.theme.typography.font(for: .caption)
        sectionLabel.textColor = context.theme.textSecondary

        reconcileHeader()
        reconcilePaneHeader()
        reconcileButtons()
        installBindingObservers()
        sanitizeSelectionIfNeeded()
        applySelection(selection.get(), animated: selectedID != selection.get())
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
            host.wantsLayer = true
            addSubview(host, positioned: .below, relativeTo: dimmingView)
            headerHost = host
        }
    }

    private func reconcileButtons() {
        mainButtons = reconcile(
            existing: mainButtons,
            items: items,
            superview: mainItemsView
        )
        footerButtons = reconcile(
            existing: footerButtons,
            items: footerItems,
            superview: paneView
        )
        updateButtonConfigurations()
    }

    private func reconcile(
        existing: [FluentNavigationItemButton<ID>],
        items: [FluentNavigationItem<ID>],
        superview: NSView
    ) -> [FluentNavigationItemButton<ID>] {
        var available: [ID: [FluentNavigationItemButton<ID>]] = [:]
        for button in existing { available[button.itemID, default: []].append(button) }
        var result: [FluentNavigationItemButton<ID>] = []
        for item in items {
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
        available.values.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        return result
    }

    private func updateButtonConfigurations() {
        let mode = resolvedDisplayMode ?? resolveDisplayMode(for: bounds.width)
        let top = mode == .top
        let expanded = top || panePresentationExpanded || (mode == .expanded && internalPaneOpen)
        for (button, item) in zip(mainButtons, items) {
            configure(button, item: item, expanded: expanded, top: top)
        }
        for (button, item) in zip(footerButtons, footerItems) {
            configure(button, item: item, expanded: expanded, top: top)
        }
    }

    private func configure(
        _ button: FluentNavigationItemButton<ID>,
        item: FluentNavigationItem<ID>,
        expanded: Bool,
        top: Bool
    ) {
        button.update(
            item: item,
            selected: selectedID == item.id,
            expanded: expanded,
            top: top,
            theme: context.theme,
            layoutDirection: context.layoutDirection,
            onActivate: { [weak self] id in self?.select(id) },
            onMoveFocus: { [weak self] id, move in self?.moveFocus(from: id, move: move) },
            onCancel: { [weak self] in self?.closeOverlayPaneIfNeeded() }
        )
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

        paneView.theme = context.theme
        paneView.layoutDirection = context.layoutDirection
        paneView.displayMode = mode
        paneView.needsDisplay = true
        layoutPaneContent(mode: mode)
    }

    private func layoutContentColumn(mode: FluentNavigationViewDisplayMode) {
        guard let headerHost else {
            contentHost.frame = contentColumnFrame
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
        contentHost.frame = NSRect(
            x: contentColumnFrame.minX,
            y: contentColumnFrame.minY,
            width: contentColumnFrame.width,
            height: max(contentColumnFrame.height - headerHeight, 0)
        )
    }

    private func layoutPaneContent(mode: FluentNavigationViewDisplayMode) {
        let top = mode == .top
        let expanded = top || panePresentationExpanded || (mode == .expanded && internalPaneOpen)
        paneToggleButton.isHidden = top || !isPaneToggleButtonVisible
        sectionLabel.stringValue = paneSectionTitle ?? ""
        sectionLabel.isHidden = top || !expanded || paneSectionTitle == nil
        paneHeaderHost?.isHidden = !expanded
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
        mainButtons.forEach { $0.isHidden = false }
        footerButtons.forEach { $0.isHidden = false }
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
        if !sectionLabel.isHidden {
            sectionLabel.frame = NSRect(x: 24, y: top + 4, width: max(paneWidth - 36, 0), height: 22)
            top += 30
        }

        let footerHeight = CGFloat(footerButtons.count) * (rowHeight + 2) + (footerButtons.isEmpty ? 0 : 8)
        let scrollBottom = max(paneView.bounds.height - footerHeight - 8, top)
        mainScrollView.frame = NSRect(x: 0, y: top, width: paneWidth, height: max(scrollBottom - top, 0))

        let buttonWidth = max((expanded ? openPaneLength : compactPaneLength) - 12, 0)
        let documentHeight = max(
            CGFloat(mainButtons.count) * (rowHeight + 2) + 4,
            mainScrollView.contentSize.height
        )
        mainItemsView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: documentHeight)
        for (index, button) in mainButtons.enumerated() {
            button.frame = NSRect(
                x: 6,
                y: 2 + CGFloat(index) * (rowHeight + 2),
                width: buttonWidth,
                height: rowHeight
            )
        }

        for (index, button) in footerButtons.enumerated() {
            button.frame = NSRect(
                x: 6,
                y: paneView.bounds.height - footerHeight + CGFloat(index) * (rowHeight + 2),
                width: buttonWidth,
                height: rowHeight
            )
        }
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
        let overflowItems = items.indices.compactMap { visibleIndexSet.contains($0) ? nil : items[$0] }
        for index in mainButtons.indices { mainButtons[index].isHidden = !visibleIndexSet.contains(index) }
        topOverflowButton.update(
            items: overflowItems,
            selectedID: selectedID,
            theme: context.theme,
            layoutDirection: context.layoutDirection.appKitValue,
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
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: mainScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateSelectionIndicator(animated: false)
        }
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
        let matches = (items + footerItems).filter { $0.id == selected && $0.isEnabled }
        guard matches.count != 1 else { return }
        isSanitizingSelection = true
        selection.set(nil)
        isSanitizingSelection = false
    }

    private func applySelection(_ id: ID?, animated: Bool) {
        let available = (items + footerItems).filter { $0.id == id && $0.isEnabled }
        let resolved = available.count == 1 ? id : nil
        if id != nil, resolved == nil, !isSanitizingSelection {
            isSanitizingSelection = true
            selection.set(nil)
            isSanitizingSelection = false
        }
        let changed = selectedID != resolved
        selectedID = resolved
        updateButtonConfigurations()
        layoutSubtreeIfNeeded()
        updateSelectionIndicator(animated: animated && changed)
    }

    private func select(_ id: ID) {
        guard (items + footerItems).contains(where: { $0.id == id && $0.isEnabled }) else { return }
        if selection.get() != id { selection.set(id) }
        applySelection(id, animated: true)
        closeOverlayPaneIfNeeded()
        context.invalidate?()
    }

    private func updateSelectionIndicator(animated: Bool) {
        guard let selectedID,
              paneView.bounds.width > 0,
              paneView.bounds.height > 0 else {
            indicatorAnimator.update(
                target: nil,
                color: context.theme.accent,
                animated: false,
                reduceMotion: context.reduceMotion
            )
            return
        }
        let selectedButton = (mainButtons + footerButtons).first(where: { $0.itemID == selectedID && !$0.isHidden })
        let indicatorView: NSView? = selectedButton ?? (topOverflowButton.contains(selectedID) ? topOverflowButton : nil)
        guard let indicatorView else {
            indicatorAnimator.update(
                target: nil,
                color: context.theme.accent,
                animated: false,
                reduceMotion: context.reduceMotion
            )
            return
        }
        let frame = indicatorView.convert(indicatorView.bounds, to: paneView)
        let target: NSRect
        if resolvedDisplayMode == .top {
            target = NSRect(x: frame.midX - 8, y: frame.maxY - 5, width: 16, height: 3)
        } else {
            let x = context.layoutDirection == .rightToLeft ? frame.maxX - 5 : frame.minX + 2
            target = NSRect(x: x, y: frame.midY - 8, width: 3, height: 16)
        }
        indicatorAnimator.update(
            target: target,
            color: context.theme.accent,
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
        let oldDimmingOpacity = dimmingView.layer?.presentation()?.opacity ?? (dimmingView.isHidden ? 0 : 1)

        paneAnimationGeneration += 1
        let generation = paneAnimationGeneration
        paneView.layer?.removeAnimation(forKey: "fluent.navigation.pane.frame")
        contentHost.layer?.removeAnimation(forKey: "fluent.navigation.content.frame")
        dimmingView.layer?.removeAnimation(forKey: "fluent.navigation.dimming")

        if open { panePresentationExpanded = true }
        retainsOverlayDuringAnimation = resolvedDisplayMode == .compact || resolvedDisplayMode == .minimal
        assignPaneOpen(open, notifyBinding: notifyBinding)
        layoutCurrentState()

        guard animated, !context.reduceMotion else {
            panePresentationExpanded = open || resolvedDisplayMode == .expanded
            retainsOverlayDuringAnimation = open && (resolvedDisplayMode == .compact || resolvedDisplayMode == .minimal)
            layoutCurrentState()
            updateSelectionIndicator(animated: false)
            return
        }

        let motion = open ? FluentMotion.navigationPaneOpen : FluentMotion.navigationPaneClose
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
            self.panePresentationExpanded = open || self.resolvedDisplayMode == .expanded
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
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }
}

private final class FluentNavigationPaneBackgroundView: NSView {
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    var layoutDirection: FluentLayoutDirection = .leftToRight { didSet { needsDisplay = true } }
    var displayMode: FluentNavigationViewDisplayMode = .expanded { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        theme.cardFill.setFill()
        dirtyRect.fill()
        theme.divider.setFill()
        if displayMode == .top {
            NSRect(x: 0, y: max(bounds.height - 1, 0), width: bounds.width, height: 1).fill()
        } else if layoutDirection == .rightToLeft {
            NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        } else {
            NSRect(x: max(bounds.width - 1, 0), y: 0, width: 1, height: bounds.height).fill()
        }
    }
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
        if window?.firstResponder === self {
            fluentTheme.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = fluentTheme.focusStrokeWidth
            path.stroke()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { performClick(nil) } else { super.keyDown(with: event) }
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
    private var fluentTheme: FluentTheme = .current
    private var layoutDirection: FluentLayoutDirection = .leftToRight
    private var pointerOver = false
    private var pressed = false
    private var onActivate: ((ID) -> Void)?
    private var onMoveFocus: ((ID, FluentNavigationFocusMove) -> Void)?
    private var onCancel: (() -> Void)?

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
        target = self
        action = #selector(invoke)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Item")
        setAccessibilityRole(.button)
        setAccessibilityTitle(item.title)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        isEnabled = item.isEnabled
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        item: FluentNavigationItem<ID>,
        selected: Bool,
        expanded: Bool,
        top: Bool,
        theme: FluentTheme,
        layoutDirection: FluentLayoutDirection,
        onActivate: @escaping (ID) -> Void,
        onMoveFocus: @escaping (ID, FluentNavigationFocusMove) -> Void,
        onCancel: @escaping () -> Void
    ) {
        itemID = item.id
        itemTitle = item.title
        systemImageName = item.systemImageName
        self.selected = selected
        self.expanded = expanded
        self.top = top
        fluentTheme = theme
        self.layoutDirection = layoutDirection
        self.onActivate = onActivate
        self.onMoveFocus = onMoveFocus
        self.onCancel = onCancel
        isEnabled = item.isEnabled
        toolTip = expanded || top ? nil : item.title
        setAccessibilityTitle(item.title)
        setAccessibilitySelected(selected)
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        pointerOver = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        pointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
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
        } else if selected, pressed {
            background = fluentTheme.controlFillSecondary
        } else if selected, pointerOver {
            background = fluentTheme.controlFillTertiary
        } else if selected {
            background = fluentTheme.controlFillSecondary
        } else if pressed {
            background = fluentTheme.controlFillTertiary
        } else if pointerOver {
            background = fluentTheme.controlFillSecondary
        } else {
            background = .clear
        }
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        let color = isEnabled ? fluentTheme.textPrimary : fluentTheme.textDisabled
        let iconSize: CGFloat = 18
        let isRTL = layoutDirection == .rightToLeft
        let iconX: CGFloat
        if top {
            iconX = isRTL ? bounds.maxX - 28 : 10
        } else if expanded {
            iconX = isRTL ? bounds.maxX - 30 : 12
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
            let textX: CGFloat = isRTL ? 10 : 42
            (itemTitle as NSString).draw(
                in: NSRect(
                    x: textX,
                    y: bounds.midY - textSize.height / 2,
                    width: max(bounds.width - 52, 0),
                    height: textSize.height
                ),
                withAttributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
            )
        }

        if window?.firstResponder === self {
            fluentTheme.accent.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = fluentTheme.focusStrokeWidth
            path.stroke()
        }
    }

    @objc private func invoke() { if isEnabled { onActivate?(itemID) } }
}

private final class FluentNavigationOverflowButton<ID: Hashable>: NSButton {
    private var items: [FluentNavigationItem<ID>] = []
    private var selectedID: ID?
    private var fluentTheme: FluentTheme = .current
    private var layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
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
        onSelect: @escaping (ID) -> Void,
        onMoveFocus: @escaping (FluentNavigationFocusMove) -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
        fluentTheme = theme
        self.layoutDirection = layoutDirection
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
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
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
        if window?.firstResponder === self {
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
                isEnabled: item.isEnabled,
                state: item.id == selectedID ? .on : .off
            ) { [weak self] in self?.onSelect?(item.id) }
        }
        let flyout = FluentMenuFlyout(items: menuItems, theme: fluentTheme, minimumWidth: 180)
        self.flyout = flyout
        flyout.present(relativeTo: self, at: NSPoint(x: bounds.minX, y: bounds.minY))
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
