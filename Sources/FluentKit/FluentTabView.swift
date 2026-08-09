import AppKit

/// Controls how `FluentTabView` distributes horizontal space between tab items.
public enum FluentTabViewWidthMode: Hashable, Sendable {
    /// Every tab receives the same clamped width and the strip scrolls when the minimum cannot fit.
    case equal
    /// Each tab is sized from its icon, title, and close affordance.
    case sizeToContent
    /// Unselected tabs with icons collapse to an icon-only presentation.
    case compact
}

/// Controls when close buttons are visible in a `FluentTabView` header.
public enum FluentTabViewCloseButtonOverlayMode: Hashable, Sendable {
    /// Matches WinUI's default: every closable tab reserves and shows its close button.
    case auto
    /// Shows the button for the selected tab and for the tab under the pointer.
    case onPointerOver
    /// Always shows the button for every closable tab.
    case always
}

/// Describes a tab move from one `FluentTabView` into another compatible tab strip.
///
/// The destination index is an insertion index in the destination collection. Both views remain
/// unchanged until the receiver commits the move and returns `true` from `onTabDropRequested`.
public struct FluentTabDropRequest {
    public let tabID: AnyHashable
    public let sourceIndex: Int
    public let destinationIndex: Int
    public let sourceContainerIdentifier: String?
    public let destinationContainerIdentifier: String?
    public let sourceWindow: NSWindow?
    public let destinationWindow: NSWindow?

    fileprivate init(
        tabID: AnyHashable,
        sourceIndex: Int,
        destinationIndex: Int,
        sourceContainerIdentifier: String?,
        destinationContainerIdentifier: String?,
        sourceWindow: NSWindow?,
        destinationWindow: NSWindow?
    ) {
        self.tabID = tabID
        self.sourceIndex = sourceIndex
        self.destinationIndex = destinationIndex
        self.sourceContainerIdentifier = sourceContainerIdentifier
        self.destinationContainerIdentifier = destinationContainerIdentifier
        self.sourceWindow = sourceWindow
        self.destinationWindow = destinationWindow
    }
}

/// Describes a completed tab drag that ended outside every compatible tab strip.
public struct FluentTabTearOutRequest {
    public let tabID: AnyHashable
    public let sourceIndex: Int
    public let sourceContainerIdentifier: String?
    public let sourceWindow: NSWindow?
    public let screenLocation: NSPoint
    /// Pointer position relative to the dragged tab's leading/top corner.
    public let pointerOffset: NSPoint

    fileprivate init(
        tabID: AnyHashable,
        sourceIndex: Int,
        sourceContainerIdentifier: String?,
        sourceWindow: NSWindow?,
        screenLocation: NSPoint,
        pointerOffset: NSPoint
    ) {
        self.tabID = tabID
        self.sourceIndex = sourceIndex
        self.sourceContainerIdentifier = sourceContainerIdentifier
        self.sourceWindow = sourceWindow
        self.screenLocation = screenLocation
        self.pointerOffset = pointerOffset
    }
}

/// Stable data and declarative content for one `FluentTabView` destination.
public struct FluentTabItem {
    public let id: AnyHashable
    public let title: String
    public let systemImageName: String?
    public let isClosable: Bool
    public let isEnabled: Bool
    public let content: FluentAnyView
    public let onCloseRequested: (() -> Void)?

    public init<ID: Hashable, Content: FluentView>(
        id: ID,
        title: String,
        systemImage: String? = nil,
        isClosable: Bool = true,
        isEnabled: Bool = true,
        onCloseRequested: (() -> Void)? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.id = AnyHashable(id)
        self.title = title
        systemImageName = systemImage
        self.isClosable = isClosable
        self.isEnabled = isEnabled
        self.onCloseRequested = onCloseRequested
        self.content = FluentAnyView(content())
    }

    /// Backwards-compatible initializer. Use the stable-ID initializer when titles can repeat or
    /// change while the view is mounted.
    public init<Content: FluentView>(
        _ title: String,
        systemImage: String? = nil,
        isClosable: Bool = true,
        isEnabled: Bool = true,
        onCloseRequested: (() -> Void)? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            id: title,
            title: title,
            systemImage: systemImage,
            isClosable: isClosable,
            isEnabled: isEnabled,
            onCloseRequested: onCloseRequested,
            content: content
        )
    }
}

/// A source-mapped WinUI TabView with native AppKit input, focus, and accessibility behavior.
public struct FluentTabView: FluentUpdatablePrimitiveView {
    public let items: [FluentTabItem]
    public let selectedIndex: FluentBinding<Int>?
    public let tabWidthMode: FluentTabViewWidthMode
    public let closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode
    public let isAddTabButtonVisible: Bool
    public let canDragTabs: Bool
    public let canReorderTabs: Bool
    public let allowsDropTabs: Bool
    /// Distance outside the tab strip before an in-strip reorder becomes a window tear-out drag.
    public let tearOutDistance: CGFloat
    public let dragScopeIdentifier: String?
    public let dragContainerIdentifier: String?
    public let onAddTabButtonClick: (() -> Void)?
    public let onTabCloseRequested: ((Int) -> Void)?
    public let onTabMoveRequested: ((_ fromIndex: Int, _ toIndex: Int) -> Void)?
    public let onTabDropRequested: ((FluentTabDropRequest) -> Bool)?
    public let onTabTearOutRequested: ((FluentTabTearOutRequest) -> Void)?
    public let onTabDroppedOutside: ((Int) -> Void)?
    public let onSelectionChanged: ((Int) -> Void)?

    fileprivate let tabStripHeader: FluentAnyView?
    fileprivate let tabStripFooter: FluentAnyView?

    public init(
        items: [FluentTabItem],
        selectedIndex: FluentBinding<Int>? = nil,
        tabWidthMode: FluentTabViewWidthMode = .equal,
        closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode = .auto,
        isAddTabButtonVisible: Bool = true,
        canDragTabs: Bool = false,
        canReorderTabs: Bool = true,
        allowsDropTabs: Bool = true,
        tearOutDistance: CGFloat = 24,
        dragScopeIdentifier: String? = nil,
        dragContainerIdentifier: String? = nil,
        onAddTabButtonClick: (() -> Void)? = nil,
        onTabCloseRequested: ((Int) -> Void)? = nil,
        onTabMoveRequested: ((_ fromIndex: Int, _ toIndex: Int) -> Void)? = nil,
        onTabDropRequested: ((FluentTabDropRequest) -> Bool)? = nil,
        onTabTearOutRequested: ((FluentTabTearOutRequest) -> Void)? = nil,
        onTabDroppedOutside: ((Int) -> Void)? = nil,
        onSelectionChanged: ((Int) -> Void)? = nil
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.tabWidthMode = tabWidthMode
        self.closeButtonOverlayMode = closeButtonOverlayMode
        self.isAddTabButtonVisible = isAddTabButtonVisible
        self.canDragTabs = canDragTabs
        self.canReorderTabs = canReorderTabs
        self.allowsDropTabs = allowsDropTabs
        self.tearOutDistance = max(tearOutDistance, 0)
        self.dragScopeIdentifier = dragScopeIdentifier
        self.dragContainerIdentifier = dragContainerIdentifier
        self.onAddTabButtonClick = onAddTabButtonClick
        self.onTabCloseRequested = onTabCloseRequested
        self.onTabMoveRequested = onTabMoveRequested
        self.onTabDropRequested = onTabDropRequested
        self.onTabTearOutRequested = onTabTearOutRequested
        self.onTabDroppedOutside = onTabDroppedOutside
        self.onSelectionChanged = onSelectionChanged
        tabStripHeader = nil
        tabStripFooter = nil
    }

    private init(
        items: [FluentTabItem],
        selectedIndex: FluentBinding<Int>?,
        tabWidthMode: FluentTabViewWidthMode,
        closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode,
        isAddTabButtonVisible: Bool,
        canDragTabs: Bool,
        canReorderTabs: Bool,
        allowsDropTabs: Bool,
        tearOutDistance: CGFloat,
        dragScopeIdentifier: String?,
        dragContainerIdentifier: String?,
        onAddTabButtonClick: (() -> Void)?,
        onTabCloseRequested: ((Int) -> Void)?,
        onTabMoveRequested: ((_ fromIndex: Int, _ toIndex: Int) -> Void)?,
        onTabDropRequested: ((FluentTabDropRequest) -> Bool)?,
        onTabTearOutRequested: ((FluentTabTearOutRequest) -> Void)?,
        onTabDroppedOutside: ((Int) -> Void)?,
        onSelectionChanged: ((Int) -> Void)?,
        tabStripHeader: FluentAnyView?,
        tabStripFooter: FluentAnyView?
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.tabWidthMode = tabWidthMode
        self.closeButtonOverlayMode = closeButtonOverlayMode
        self.isAddTabButtonVisible = isAddTabButtonVisible
        self.canDragTabs = canDragTabs
        self.canReorderTabs = canReorderTabs
        self.allowsDropTabs = allowsDropTabs
        self.tearOutDistance = max(tearOutDistance, 0)
        self.dragScopeIdentifier = dragScopeIdentifier
        self.dragContainerIdentifier = dragContainerIdentifier
        self.onAddTabButtonClick = onAddTabButtonClick
        self.onTabCloseRequested = onTabCloseRequested
        self.onTabMoveRequested = onTabMoveRequested
        self.onTabDropRequested = onTabDropRequested
        self.onTabTearOutRequested = onTabTearOutRequested
        self.onTabDroppedOutside = onTabDroppedOutside
        self.onSelectionChanged = onSelectionChanged
        self.tabStripHeader = tabStripHeader
        self.tabStripFooter = tabStripFooter
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentTabViewHost(configuration: self, context: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentTabViewHost else { return false }
        host.update(configuration: self, context: context)
        return true
    }

    /// Places arbitrary declarative content before the scrollable tab strip.
    public func tabStripHeader<Content: FluentView>(
        @FluentViewBuilder _ content: () -> Content
    ) -> FluentTabView {
        replacing(header: FluentAnyView(content()), footer: tabStripFooter)
    }

    /// Places arbitrary declarative content in the trailing area after the add button.
    public func tabStripFooter<Content: FluentView>(
        @FluentViewBuilder _ content: () -> Content
    ) -> FluentTabView {
        replacing(header: tabStripHeader, footer: FluentAnyView(content()))
    }

    private func replacing(header: FluentAnyView?, footer: FluentAnyView?) -> FluentTabView {
        FluentTabView(
            items: items,
            selectedIndex: selectedIndex,
            tabWidthMode: tabWidthMode,
            closeButtonOverlayMode: closeButtonOverlayMode,
            isAddTabButtonVisible: isAddTabButtonVisible,
            canDragTabs: canDragTabs,
            canReorderTabs: canReorderTabs,
            allowsDropTabs: allowsDropTabs,
            tearOutDistance: tearOutDistance,
            dragScopeIdentifier: dragScopeIdentifier,
            dragContainerIdentifier: dragContainerIdentifier,
            onAddTabButtonClick: onAddTabButtonClick,
            onTabCloseRequested: onTabCloseRequested,
            onTabMoveRequested: onTabMoveRequested,
            onTabDropRequested: onTabDropRequested,
            onTabTearOutRequested: onTabTearOutRequested,
            onTabDroppedOutside: onTabDroppedOutside,
            onSelectionChanged: onSelectionChanged,
            tabStripHeader: header,
            tabStripFooter: footer
        )
    }
}

private struct FluentResolvedTabID: Hashable {
    let base: AnyHashable
    let occurrence: Int
}

private enum FluentTabViewMetrics {
    static let headerTopPadding: CGFloat = 8
    static let itemHeight: CGFloat = 32
    static let itemMinWidth: CGFloat = 100
    static let itemMaxWidth: CGFloat = 240
    static let compactItemWidth: CGFloat = 48
    static let itemHorizontalPadding: CGFloat = 8
    static let iconSize: CGFloat = 16
    static let iconSpacing: CGFloat = 10
    static let closeMargin: CGFloat = 4
    static let closeWidth: CGFloat = 32
    static let closeHeight: CGFloat = 24
    static let addContainerWidth: CGFloat = 35
    static let addWidth: CGFloat = 32
    static let addHeight: CGFloat = 24
    static let scrollContainerWidth: CGFloat = 38
    static let scrollWidth: CGFloat = 32
    static let scrollHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 4
    static let transitionDuration: TimeInterval = 0.2
}

enum FluentTabViewDragGeometry {
    static func centeredFrame(at pointer: NSPoint, size: NSSize) -> NSRect {
        NSRect(
            x: pointer.x - size.width / 2,
            y: pointer.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func inlineCenteredFrame(
        at pointer: NSPoint,
        size: NSSize,
        visibleFrame: NSRect,
        rowY: CGFloat
    ) -> NSRect {
        let x = min(
            max(pointer.x - size.width / 2, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - size.width)
        )
        return NSRect(x: x, y: rowY, width: size.width, height: size.height)
    }
}

private let fluentTabPasteboardType = NSPasteboard.PasteboardType("com.fluentkit.tab-transfer")

private enum FluentTabDragPreviewMode {
    case inline
    case window
}

private final class FluentTabDragPayload {
    let token = UUID().uuidString
    let scopeIdentifier: String
    let tabID: AnyHashable
    let sourceIndex: Int
    let sourceContainerIdentifier: String?
    let sourceWindow: NSWindow?
    let pointerOffset: NSPoint
    var tabPreviewImage: NSImage?
    var windowPreviewImage: NSImage?
    var windowPreviewFrameRelativeToPointer: NSRect?
    weak var sourceHost: FluentTabViewHost?
    weak var sourceTab: FluentTabItemControl?
    weak var draggingSource: FluentTabDraggingSource?

    init(
        scopeIdentifier: String,
        tabID: AnyHashable,
        sourceIndex: Int,
        sourceContainerIdentifier: String?,
        sourceWindow: NSWindow?,
        pointerOffset: NSPoint,
        sourceHost: FluentTabViewHost,
        sourceTab: FluentTabItemControl
    ) {
        self.scopeIdentifier = scopeIdentifier
        self.tabID = tabID
        self.sourceIndex = sourceIndex
        self.sourceContainerIdentifier = sourceContainerIdentifier
        self.sourceWindow = sourceWindow
        self.pointerOffset = pointerOffset
        self.sourceHost = sourceHost
        self.sourceTab = sourceTab
    }
}

private final class FluentTabDragRegistry {
    static let shared = FluentTabDragRegistry()
    private var payloads: [String: FluentTabDragPayload] = [:]

    func insert(_ payload: FluentTabDragPayload) { payloads[payload.token] = payload }
    func payload(for token: String) -> FluentTabDragPayload? { payloads[token] }
    func remove(_ token: String) { payloads.removeValue(forKey: token) }
}

private final class FluentTabViewHost: NSView, FluentFillWidthProviding {
    private var configuration: FluentTabView
    private var context: FluentRenderContext
    private var resolvedIDs: [FluentResolvedTabID] = []
    private var tabItemViews: [FluentTabItemControl] = []
    private var contentHosts: [FluentResolvedTabID: FluentViewHost<FluentAnyView>] = [:]
    private var headerHost: FluentViewHost<FluentAnyView>?
    private var footerHost: FluentViewHost<FluentAnyView>?
    private let tabViewport = FluentClippingView()
    private let contentContainer = NSView()
    private let addButton = FluentTabGlyphButton(kind: .add)
    private let scrollDecreaseButton = FluentTabGlyphButton(kind: .chevronLeft)
    private let scrollIncreaseButton = FluentTabGlyphButton(kind: .chevronRight)
    private var selectedIndex = -1
    private var selectedBinding: FluentBinding<Int>?
    private var observedSelectionBinding: FluentBinding<Int>?
    private var selectedObserverID: UUID?
    private var bindingGeneration = 0
    private var isWritingSelection = false
    private var scrollOffset: CGFloat = 0
    private var maxScrollOffset: CGFloat = 0
    private var tabBaseFrames: [NSRect] = []
    private var tabVisibleFrame: NSRect = .zero
    private var dropIndicatorX: CGFloat?
    private weak var draggedTab: FluentTabItemControl?
    private var draggedFromIndex: Int?
    private var draggedToIndex: Int?
    private var pendingPreviousFrames: [FluentResolvedTabID: NSRect]?
    private var pendingPreviousScrollOffset: CGFloat?
    private var pendingInsertedIDs = Set<FluentResolvedTabID>()
    private var pendingEnsureSelectedTabVisible = false
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private let localDragScopeIdentifier = "FluentKit.TabView.\(UUID().uuidString)"
    private var activeDraggingSource: FluentTabDraggingSource?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let contentHeight = selectedIndex >= 0
            ? contentHosts[resolvedIDs[selectedIndex]]?.intrinsicContentSize.height ?? 240
            : 160
        let resolvedHeight = contentHeight == NSView.noIntrinsicMetric ? 240 : max(contentHeight, 160)
        return NSSize(width: 560, height: FluentTabViewMetrics.headerTopPadding + FluentTabViewMetrics.itemHeight + resolvedHeight)
    }

    init(configuration: FluentTabView, context: FluentRenderContext) {
        self.configuration = configuration
        self.context = context
        selectedBinding = configuration.selectedIndex
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.TabView")
        wantsLayer = true
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Tabs")

        tabViewport.identifier = NSUserInterfaceItemIdentifier("FluentKit.TabView.TabStrip")
        contentContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.TabView.Content")
        addSubview(tabViewport)
        addSubview(contentContainer)
        addSubview(addButton)
        addSubview(scrollDecreaseButton)
        addSubview(scrollIncreaseButton)
        registerForDraggedTypes([fluentTabPasteboardType])

        addButton.setAccessibilityLabel("Add new tab")
        addButton.setAccessibilityTitle("Add new tab")
        addButton.onInvoke = { [weak self] in self?.configuration.onAddTabButtonClick?() }
        addButton.onCycleSelection = { [weak self] forward in self?.cycleSelection(forward: forward) }
        addButton.onCloseCurrent = { [weak self] in
            guard let self, self.configuration.items.indices.contains(self.selectedIndex) else { return }
            self.requestClose(self.selectedIndex)
        }
        scrollDecreaseButton.setAccessibilityLabel("Scroll tabs left")
        scrollDecreaseButton.setAccessibilityTitle("Scroll tabs left")
        scrollIncreaseButton.setAccessibilityLabel("Scroll tabs right")
        scrollIncreaseButton.setAccessibilityTitle("Scroll tabs right")
        scrollDecreaseButton.onInvoke = { [weak self] in self?.scrollByPage(forward: false) }
        scrollIncreaseButton.onInvoke = { [weak self] in self?.scrollByPage(forward: true) }
        scrollDecreaseButton.onCycleSelection = { [weak self] forward in self?.cycleSelection(forward: forward) }
        scrollIncreaseButton.onCycleSelection = { [weak self] forward in self?.cycleSelection(forward: forward) }
        scrollDecreaseButton.onCloseCurrent = { [weak self] in
            guard let self, self.configuration.items.indices.contains(self.selectedIndex) else { return }
            self.requestClose(self.selectedIndex)
        }
        scrollIncreaseButton.onCloseCurrent = scrollDecreaseButton.onCloseCurrent

        reconcileSupplementaryHosts()
        reconcileTabs(animated: false)
        installSelectionObserver()
        synchronizeSelectionFromBinding(writeCorrection: true, ensureVisible: false)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeSelectionObserver() }

    override func layout() {
        super.layout()
        layoutTabView()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let pixel = 1 / max(scale, 1)
        context.theme.cardStroke.setFill()
        NSRect(
            x: 0,
            y: FluentTabViewMetrics.headerTopPadding + FluentTabViewMetrics.itemHeight - pixel,
            width: bounds.width,
            height: pixel
        ).fill()
        if let dropIndicatorX {
            context.theme.accentFillDefault.setFill()
            NSRect(
                x: dropIndicatorX - pixel,
                y: FluentTabViewMetrics.headerTopPadding + 2,
                width: 2 * pixel,
                height: FluentTabViewMetrics.itemHeight - 4
            ).fill()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxScrollOffset > 0 else {
            super.scrollWheel(with: event)
            return
        }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        scrollOffset = min(max(scrollOffset - delta, 0), maxScrollOffset)
        needsLayout = true
    }

    func update(configuration: FluentTabView, context: FluentRenderContext) {
        let previousSelectedID = resolvedIDs.indices.contains(selectedIndex) ? resolvedIDs[selectedIndex] : nil
        self.configuration = configuration
        self.context = context
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        selectedBinding = configuration.selectedIndex
        cancelDrag()
        reconcileSupplementaryHosts()
        reconcileTabs(animated: !context.reduceMotion)
        installSelectionObserver()

        if selectedBinding == nil,
           let previousSelectedID,
           let preserved = resolvedIDs.firstIndex(of: previousSelectedID) {
            selectedIndex = preserved
        }
        synchronizeSelectionFromBinding(writeCorrection: true, ensureVisible: false)
        refreshAppearance()
        lastLayoutSize = NSSize(width: -1, height: -1)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func resolvedIDs(for items: [FluentTabItem]) -> [FluentResolvedTabID] {
        var occurrences: [AnyHashable: Int] = [:]
        return items.map { item in
            let occurrence = occurrences[item.id, default: 0]
            occurrences[item.id] = occurrence + 1
            return FluentResolvedTabID(base: item.id, occurrence: occurrence)
        }
    }

    private func reconcileTabs(animated: Bool) {
        let nextIDs = resolvedIDs(for: configuration.items)
        let oldFrames = Dictionary(
            uniqueKeysWithValues: tabItemViews.map { ($0.resolvedID, presentedFrame(of: $0)) }
        )
        let oldIDs = Set(tabItemViews.map(\.resolvedID))
        let nextIDSet = Set(nextIDs)
        let carriedInsertedIDs = pendingInsertedIDs.intersection(nextIDSet)
        tabItemViews.forEach(removeCollectionTransitionAnimations)
        var reusable = Dictionary(uniqueKeysWithValues: tabItemViews.map { ($0.resolvedID, $0) })
        var nextTabViews: [FluentTabItemControl] = []

        for index in configuration.items.indices {
            let resolvedID = nextIDs[index]
            let tabView = reusable.removeValue(forKey: resolvedID) ?? FluentTabItemControl(resolvedID: resolvedID)
            if tabView.superview == nil { tabViewport.addSubview(tabView) }
            tabView.onSelect = { [weak self, weak tabView] in
                guard let self, let tabView, let index = self.tabItemViews.firstIndex(where: { $0 === tabView }) else { return }
                self.commitSelection(index, writeBinding: true, notify: true, ensureVisible: true)
            }
            tabView.onClose = { [weak self, weak tabView] in
                guard let self, let tabView, let index = self.tabItemViews.firstIndex(where: { $0 === tabView }) else { return }
                self.requestClose(index)
            }
            tabView.onMoveFocus = { [weak self, weak tabView] forward in
                guard let self, let tabView, let index = self.tabItemViews.firstIndex(where: { $0 === tabView }) else { return }
                self.moveSelection(from: index, forward: forward)
            }
            tabView.onMoveToBoundary = { [weak self] last in self?.moveSelectionToBoundary(last: last) }
            tabView.onCycleSelection = { [weak self] forward in self?.cycleSelection(forward: forward) }
            tabView.onKeyboardReorder = { [weak self, weak tabView] forward in
                guard let self, let tabView, let index = self.tabItemViews.firstIndex(where: { $0 === tabView }) else { return }
                self.requestKeyboardMove(from: index, forward: forward)
            }
            tabView.onDrag = { [weak self, weak tabView] event, pointerOffset in
                guard let self, let tabView else { return }
                self.updateDrag(tabView, event: event, pointerOffset: pointerOffset)
            }
            tabView.onDrop = { [weak self, weak tabView] location in
                guard let self, let tabView else { return }
                self.finishDrag(tabView, locationInWindow: location)
            }
            nextTabViews.append(tabView)
        }
        for removedView in reusable.values {
            if let presentedFrame = oldFrames[removedView.resolvedID] {
                removedView.frame = presentedFrame
                removedView.updateSubviewFrames()
            }
            animateRemoval(of: removedView, animated: animated)
        }
        if animated {
            pendingPreviousFrames = oldFrames
            pendingPreviousScrollOffset = scrollOffset
            pendingInsertedIDs = carriedInsertedIDs.union(nextIDSet.subtracting(oldIDs))
        } else {
            pendingPreviousFrames = nil
            pendingPreviousScrollOffset = nil
            pendingInsertedIDs.removeAll()
        }

        let activeIDs = Set(nextIDs)
        let staleContentIDs = contentHosts.keys.filter { !activeIDs.contains($0) }
        for id in staleContentIDs {
            contentHosts.removeValue(forKey: id)?.removeFromSuperview()
        }
        for (index, item) in configuration.items.enumerated() {
            let id = nextIDs[index]
            if let host = contentHosts[id] {
                host.context = context
                host.update(item.content)
            } else {
                let host = FluentViewHost(item.content, context: context)
                host.identifier = NSUserInterfaceItemIdentifier("FluentKit.TabView.Content.\(index)")
                // TabView owns this host's frame directly in `layoutTabView`. FluentViewHost
                // normally opts into constraint-managed placement, but leaving that mode active
                // without parent constraints lets AppKit move a window-sized page toward the
                // bottom of an unflipped intermediate container.
                host.translatesAutoresizingMaskIntoConstraints = true
                host.autoresizingMask = [.width, .height]
                contentContainer.addSubview(host)
                contentHosts[id] = host
            }
        }

        resolvedIDs = nextIDs
        tabItemViews = nextTabViews
        if configuration.items.isEmpty {
            selectedIndex = -1
        } else if selectedIndex < 0 || selectedIndex >= configuration.items.count {
            selectedIndex = min(max(selectedIndex, 0), configuration.items.count - 1)
        }
        refreshTabConfigurations()
        updateVisibleContent()
    }

    private func reconcileSupplementaryHosts() {
        headerHost = reconcileSupplementaryHost(
            headerHost,
            content: configuration.tabStripHeader,
            identifier: "FluentKit.TabView.Header"
        )
        footerHost = reconcileSupplementaryHost(
            footerHost,
            content: configuration.tabStripFooter,
            identifier: "FluentKit.TabView.Footer"
        )
    }

    private func reconcileSupplementaryHost(
        _ existing: FluentViewHost<FluentAnyView>?,
        content: FluentAnyView?,
        identifier: String
    ) -> FluentViewHost<FluentAnyView>? {
        guard let content else {
            existing?.removeFromSuperview()
            return nil
        }
        if let existing {
            existing.context = context
            existing.update(content)
            return existing
        }
        let host = FluentViewHost(content, context: context)
        host.identifier = NSUserInterfaceItemIdentifier(identifier)
        host.translatesAutoresizingMaskIntoConstraints = true
        addSubview(host)
        return host
    }

    private func installSelectionObserver() {
        removeSelectionObserver()
        bindingGeneration += 1
        let generation = bindingGeneration
        observedSelectionBinding = selectedBinding
        selectedObserverID = selectedBinding?.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.bindingGeneration, !self.isWritingSelection else { return }
                self.applyExternalSelection(value)
            }
        }
    }

    private func removeSelectionObserver() {
        if let selectedObserverID { observedSelectionBinding?.removeObserver(selectedObserverID) }
        selectedObserverID = nil
        observedSelectionBinding = nil
    }

    private func synchronizeSelectionFromBinding(writeCorrection: Bool, ensureVisible: Bool) {
        let requested = selectedBinding?.get() ?? selectedIndex
        let corrected = correctedSelection(requested)
        commitSelection(corrected, writeBinding: false, notify: false, ensureVisible: ensureVisible)
        if writeCorrection, selectedBinding != nil, requested != corrected {
            writeSelectionBinding(corrected)
        }
    }

    private func applyExternalSelection(_ value: Int) {
        let corrected = correctedSelection(value)
        commitSelection(corrected, writeBinding: false, notify: false, ensureVisible: true)
        if corrected != value { writeSelectionBinding(corrected) }
    }

    private func correctedSelection(_ index: Int) -> Int {
        guard !configuration.items.isEmpty else { return -1 }
        if configuration.items.indices.contains(index), configuration.items[index].isEnabled { return index }
        if let enabled = configuration.items.indices.first(where: { configuration.items[$0].isEnabled }) {
            return enabled
        }
        return min(max(index, 0), configuration.items.count - 1)
    }

    private func commitSelection(_ index: Int, writeBinding: Bool, notify: Bool, ensureVisible: Bool) {
        let corrected = correctedSelection(index)
        guard corrected != selectedIndex else {
            if ensureVisible { ensureSelectedTabVisible() }
            return
        }
        selectedIndex = corrected
        refreshTabConfigurations()
        updateVisibleContent()
        if writeBinding { writeSelectionBinding(corrected) }
        if notify { configuration.onSelectionChanged?(corrected) }
        invalidateIntrinsicContentSize()
        needsLayout = true
        if ensureVisible { ensureSelectedTabVisible() }
    }

    private func writeSelectionBinding(_ value: Int) {
        guard let selectedBinding, selectedBinding.get() != value else { return }
        isWritingSelection = true
        selectedBinding.set(value)
        isWritingSelection = false
    }

    private func updateVisibleContent() {
        for (index, id) in resolvedIDs.enumerated() {
            guard let host = contentHosts[id] else { continue }
            // WinUI's TabContentPresenter swaps the selected TabViewItem content directly. The
            // ContentThemeTransition in TabView.xaml belongs to the tab-item collection rather
            // than the selected page presenter, so selection itself intentionally does not animate.
            host.isHidden = index != selectedIndex
        }
    }

    private func refreshTabConfigurations() {
        for (index, tabView) in tabItemViews.enumerated() {
            let selected = index == selectedIndex
            let hidesSeparator = selected || index == selectedIndex - 1
            tabView.update(
                item: configuration.items[index],
                theme: context.theme,
                selected: selected,
                widthMode: configuration.tabWidthMode,
                closeButtonOverlayMode: configuration.closeButtonOverlayMode,
                layoutDirection: context.layoutDirection,
                canDrag: configuration.canDragTabs,
                canReorder: configuration.canReorderTabs,
                hidesSeparator: hidesSeparator
            )
        }
    }

    private func refreshAppearance() {
        if context.reduceMotion {
            tabItemViews.forEach { $0.layer?.removeAllAnimations() }
            contentHosts.values.forEach { $0.layer?.removeAllAnimations() }
        }
        addButton.update(theme: context.theme, isEnabled: configuration.isAddTabButtonVisible)
        scrollDecreaseButton.update(theme: context.theme, isEnabled: scrollOffset > 0)
        scrollIncreaseButton.update(theme: context.theme, isEnabled: scrollOffset < maxScrollOffset)
        refreshTabConfigurations()
        needsDisplay = true
    }

    private func layoutTabView() {
        let stripHeight = FluentTabViewMetrics.headerTopPadding + FluentTabViewMetrics.itemHeight
        contentContainer.frame = NSRect(x: 0, y: stripHeight, width: bounds.width, height: max(0, bounds.height - stripHeight))
        for host in contentHosts.values { host.frame = contentContainer.bounds }

        let headerWidth = supplementaryWidth(headerHost)
        let footerWidth = supplementaryWidth(footerHost)
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        if rtl {
            headerHost?.frame = NSRect(x: bounds.width - headerWidth, y: 0, width: headerWidth, height: stripHeight)
            footerHost?.frame = NSRect(x: 0, y: 0, width: footerWidth, height: stripHeight)
        } else {
            headerHost?.frame = NSRect(x: 0, y: 0, width: headerWidth, height: stripHeight)
            footerHost?.frame = NSRect(x: bounds.width - footerWidth, y: 0, width: footerWidth, height: stripHeight)
        }

        let addWidth = configuration.isAddTabButtonVisible ? FluentTabViewMetrics.addContainerWidth : 0
        addButton.isHidden = !configuration.isAddTabButtonVisible
        let availableStart = rtl ? footerWidth : headerWidth
        let availableEnd = bounds.width - (rtl ? headerWidth : footerWidth)
        let tabAreaWidth = max(0, availableEnd - availableStart - addWidth)
        let addX = rtl ? availableStart : availableStart + tabAreaWidth
        addButton.frame = NSRect(
            x: addX + (rtl ? 3 : 0),
            y: FluentTabViewMetrics.headerTopPadding + 4,
            width: FluentTabViewMetrics.addWidth,
            height: FluentTabViewMetrics.addHeight
        )

        let desiredWidths = tabItemWidths(availableWidth: tabAreaWidth)
        let totalWidth = desiredWidths.reduce(0, +)
        let overflow = totalWidth > tabAreaWidth + 0.5
        let scrollControlsWidth = overflow ? 2 * FluentTabViewMetrics.scrollContainerWidth : 0
        let viewportWidth = max(0, tabAreaWidth - scrollControlsWidth)
        let viewportX = availableStart + (overflow ? FluentTabViewMetrics.scrollContainerWidth : 0)
        tabVisibleFrame = NSRect(
            x: viewportX,
            y: FluentTabViewMetrics.headerTopPadding,
            width: viewportWidth,
            height: FluentTabViewMetrics.itemHeight
        )
        tabViewport.frame = tabVisibleFrame

        scrollDecreaseButton.isHidden = !overflow
        scrollIncreaseButton.isHidden = !overflow
        if overflow {
            scrollDecreaseButton.frame = NSRect(
                x: availableStart + 3,
                y: FluentTabViewMetrics.headerTopPadding + 4,
                width: FluentTabViewMetrics.scrollWidth,
                height: FluentTabViewMetrics.scrollHeight
            )
            scrollIncreaseButton.frame = NSRect(
                x: availableStart + FluentTabViewMetrics.scrollContainerWidth + viewportWidth + 3,
                y: FluentTabViewMetrics.headerTopPadding + 4,
                width: FluentTabViewMetrics.scrollWidth,
                height: FluentTabViewMetrics.scrollHeight
            )
        }

        maxScrollOffset = max(0, totalWidth - viewportWidth)
        if lastLayoutSize.width < 0, rtl, maxScrollOffset > 0 { scrollOffset = maxScrollOffset }
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
        tabBaseFrames = baseFrames(widths: desiredWidths, totalWidth: totalWidth, rtl: rtl)
        if pendingEnsureSelectedTabVisible {
            resolveSelectedTabVisibility()
            pendingEnsureSelectedTabVisible = false
        }
        let scrollDelta = scrollOffset - (pendingPreviousScrollOffset ?? scrollOffset)
        for (index, tabView) in tabItemViews.enumerated() {
            let base = tabBaseFrames[index]
            tabView.frame = NSRect(
                x: base.minX - scrollOffset,
                y: 0,
                width: base.width,
                height: FluentTabViewMetrics.itemHeight
            )
            tabView.updateSubviewFrames()
            if pendingInsertedIDs.contains(tabView.resolvedID) {
                animateInsertion(of: tabView)
            } else if let previous = pendingPreviousFrames?[tabView.resolvedID] {
                // Bringing the selected item into view is viewport movement, not item reorder.
                // Excluding that shared delta prevents every existing label from sweeping across
                // the newly inserted label when tabs are added in quick succession.
                animateReposition(
                    of: tabView,
                    from: previous.offsetBy(dx: -scrollDelta, dy: 0)
                )
            }
        }
        pendingPreviousFrames = nil
        pendingPreviousScrollOffset = nil
        pendingInsertedIDs.removeAll()

        scrollDecreaseButton.update(theme: context.theme, isEnabled: scrollOffset > 0.5)
        scrollIncreaseButton.update(theme: context.theme, isEnabled: scrollOffset < maxScrollOffset - 0.5)
        lastLayoutSize = bounds.size
    }

    private func supplementaryWidth(_ host: FluentViewHost<FluentAnyView>?) -> CGFloat {
        guard let host else { return 0 }
        let intrinsic = host.intrinsicContentSize.width
        if intrinsic != NSView.noIntrinsicMetric, intrinsic.isFinite { return max(0, intrinsic) }
        return max(0, host.fittingSize.width)
    }

    private func tabItemWidths(availableWidth: CGFloat) -> [CGFloat] {
        guard !tabItemViews.isEmpty else { return [] }
        switch configuration.tabWidthMode {
        case .equal:
            let width = min(
                max(availableWidth / CGFloat(tabItemViews.count), FluentTabViewMetrics.itemMinWidth),
                FluentTabViewMetrics.itemMaxWidth
            )
            return Array(repeating: width, count: tabItemViews.count)
        case .sizeToContent:
            return tabItemViews.map { min(max($0.preferredWidth, FluentTabViewMetrics.itemMinWidth), FluentTabViewMetrics.itemMaxWidth) }
        case .compact:
            return tabItemViews.enumerated().map { index, view in
                if index != selectedIndex, configuration.items[index].systemImageName != nil {
                    return FluentTabViewMetrics.compactItemWidth
                }
                return min(max(view.preferredWidth, FluentTabViewMetrics.itemMinWidth), FluentTabViewMetrics.itemMaxWidth)
            }
        }
    }

    private func baseFrames(widths: [CGFloat], totalWidth: CGFloat, rtl: Bool) -> [NSRect] {
        var cursor: CGFloat = 0
        return widths.map { width in
            let x = rtl ? totalWidth - cursor - width : cursor
            cursor += width
            return NSRect(x: x, y: 0, width: width, height: FluentTabViewMetrics.itemHeight)
        }
    }

    private func ensureSelectedTabVisible() {
        pendingEnsureSelectedTabVisible = true
        needsLayout = true
    }

    private func resolveSelectedTabVisibility() {
        guard tabBaseFrames.indices.contains(selectedIndex), tabVisibleFrame.width > 0 else { return }
        let frame = tabBaseFrames[selectedIndex]
        if frame.minX < scrollOffset {
            scrollOffset = frame.minX
        } else if frame.maxX > scrollOffset + tabVisibleFrame.width {
            scrollOffset = frame.maxX - tabVisibleFrame.width
        }
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
    }

    private func scrollByPage(forward: Bool) {
        let amount = max(tabVisibleFrame.width * 0.75, FluentTabViewMetrics.itemMinWidth)
        scrollOffset = min(max(scrollOffset + (forward ? amount : -amount), 0), maxScrollOffset)
        needsLayout = true
    }

    private func moveSelection(from index: Int, forward: Bool) {
        guard !configuration.items.isEmpty else { return }
        var candidate = index
        for _ in configuration.items.indices {
            candidate = (candidate + (forward ? 1 : -1) + configuration.items.count) % configuration.items.count
            if configuration.items[candidate].isEnabled {
                commitSelection(candidate, writeBinding: true, notify: true, ensureVisible: true)
                window?.makeFirstResponder(tabItemViews[candidate])
                return
            }
        }
    }

    private func cycleSelection(forward: Bool) {
        moveSelection(from: max(selectedIndex, 0), forward: forward)
    }

    private func moveSelectionToBoundary(last: Bool) {
        let indices = last
            ? Array(configuration.items.indices.reversed())
            : Array(configuration.items.indices)
        guard let index = indices.first(where: { configuration.items[$0].isEnabled }) else { return }
        commitSelection(index, writeBinding: true, notify: true, ensureVisible: true)
        window?.makeFirstResponder(tabItemViews[index])
    }

    private func requestClose(_ index: Int) {
        guard configuration.items.indices.contains(index), configuration.items[index].isClosable else { return }
        configuration.items[index].onCloseRequested?()
        configuration.onTabCloseRequested?(index)
    }

    private func requestKeyboardMove(from index: Int, forward: Bool) {
        guard configuration.canReorderTabs, configuration.items.count > 1 else { return }
        let destination = min(max(index + (forward ? 1 : -1), 0), configuration.items.count - 1)
        guard destination != index else { return }
        configuration.onTabMoveRequested?(index, destination)
    }

    private func animateInsertion(of tab: FluentTabItemControl) {
        guard !context.reduceMotion, let layer = tab.layer else { return }
        removeCollectionTransitionAnimations(from: tab)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = FluentTabViewMetrics.transitionDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fluent.tabview.insert.opacity")
    }

    private func animateRemoval(of tab: FluentTabItemControl, animated: Bool) {
        guard animated, !context.reduceMotion, let layer = tab.layer else {
            tab.removeFromSuperview()
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = (layer.presentation() ?? layer).opacity
        fade.toValue = 0
        fade.duration = FluentTabViewMetrics.transitionDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let collapse = CABasicAnimation(keyPath: "transform.scale")
        collapse.fromValue = CGFloat(1)
        collapse.toValue = CGFloat(0.96)
        collapse.duration = FluentTabViewMetrics.transitionDuration
        collapse.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(fade, forKey: "fluent.tabview.remove.opacity")
        layer.add(collapse, forKey: "fluent.tabview.remove.scale")
        DispatchQueue.main.asyncAfter(deadline: .now() + FluentTabViewMetrics.transitionDuration) { [weak tab] in
            tab?.removeFromSuperview()
        }
    }

    private func animateReposition(of tab: FluentTabItemControl, from previous: NSRect) {
        guard !context.reduceMotion, let layer = tab.layer else { return }
        let delta = previous.minX - tab.frame.minX
        guard abs(delta) > 0.5 else { return }
        removeCollectionTransitionAnimations(from: tab)
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = delta
        animation.toValue = CGFloat(0)
        animation.duration = FluentTabViewMetrics.transitionDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "fluent.tabview.reorder")
    }

    private func presentedFrame(of tab: FluentTabItemControl) -> NSRect {
        guard let layer = tab.layer,
              let presentation = layer.presentation() else { return tab.frame }
        return tab.frame.offsetBy(dx: presentation.transform.m41, dy: presentation.transform.m42)
    }

    private func removeCollectionTransitionAnimations(from tab: FluentTabItemControl) {
        guard let layer = tab.layer else { return }
        layer.removeAnimation(forKey: "fluent.tabview.insert.opacity")
        layer.removeAnimation(forKey: "fluent.tabview.insert.position")
        layer.removeAnimation(forKey: "fluent.tabview.reorder")
    }

    private var effectiveDragScopeIdentifier: String {
        configuration.dragScopeIdentifier ?? localDragScopeIdentifier
    }

    private func beginSystemDrag(
        _ tab: FluentTabItemControl,
        event: NSEvent,
        pointerOffset: NSPoint
    ) {
        guard configuration.canDragTabs,
              activeDraggingSource == nil,
              let sourceIndex = tabItemViews.firstIndex(where: { $0 === tab }),
              configuration.items.indices.contains(sourceIndex) else { return }

        cancelDrag()
        let item = configuration.items[sourceIndex]
        let payload = FluentTabDragPayload(
            scopeIdentifier: effectiveDragScopeIdentifier,
            tabID: item.id,
            sourceIndex: sourceIndex,
            sourceContainerIdentifier: configuration.dragContainerIdentifier,
            sourceWindow: window,
            pointerOffset: pointerOffset,
            sourceHost: self,
            sourceTab: tab
        )
        FluentTabDragRegistry.shared.insert(payload)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(payload.token, forType: fluentTabPasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        payload.tabPreviewImage = tab.draggingImage()
        let preview = tearOutPreview(for: tab)
        payload.windowPreviewImage = preview.image
        payload.windowPreviewFrameRelativeToPointer = preview.frame
        // Lift the actual tab first. AppKit then animates this same dragging item around a
        // pointer-centered anchor in `draggingSession(_:willBeginAt:)`.
        draggingItem.setDraggingFrame(tab.bounds, contents: payload.tabPreviewImage)

        let source = FluentTabDraggingSource(payload: payload) { [weak self, weak tab] operation, screenPoint, cancelled in
            guard let self else { return }
            self.activeDraggingSource = nil
            tab?.finishSystemDrag(animated: !self.context.reduceMotion)
            self.clearSystemDropIndicator()
            guard operation.isEmpty, !cancelled else { return }
            let request = FluentTabTearOutRequest(
                tabID: payload.tabID,
                sourceIndex: payload.sourceIndex,
                sourceContainerIdentifier: payload.sourceContainerIdentifier,
                sourceWindow: payload.sourceWindow,
                screenLocation: screenPoint,
                pointerOffset: payload.pointerOffset
            )
            self.configuration.onTabTearOutRequested?(request)
            self.configuration.onTabDroppedOutside?(payload.sourceIndex)
        }
        payload.draggingSource = source
        activeDraggingSource = source
        tab.setSystemDragOutsideStrip(true, animated: !context.reduceMotion)
        tab.beginDraggingSession(with: [draggingItem], event: event, source: source)
    }

    private func tearOutPreview(for tab: FluentTabItemControl) -> (image: NSImage, frame: NSRect) {
        guard let contentView = window?.contentView,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            let image = tab.draggingImage()
            return (image, FluentTabViewDragGeometry.centeredFrame(at: .zero, size: image.size))
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let source = NSImage(size: contentView.bounds.size)
        source.addRepresentation(bitmap)

        let maximum = NSSize(width: 300, height: 210)
        let scale = min(
            0.36,
            maximum.width / max(source.size.width, 1),
            maximum.height / max(source.size.height, 1)
        )
        let renderedSize = NSSize(
            width: max(140, source.size.width * scale),
            height: max(96, source.size.height * scale)
        )
        let shadowInset: CGFloat = 10
        let canvasSize = NSSize(
            width: renderedSize.width + 2 * shadowInset,
            height: renderedSize.height + 2 * shadowInset
        )
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let contentRect = NSRect(
            x: shadowInset,
            y: shadowInset,
            width: renderedSize.width,
            height: renderedSize.height
        )
        let path = NSBezierPath(roundedRect: contentRect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 9
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        context.theme.windowBackground.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        source.draw(in: contentRect, from: .zero, operation: .sourceOver, fraction: 0.94)
        NSGraphicsContext.restoreGraphicsState()
        context.theme.cardStroke.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 0.75
        path.stroke()
        image.unlockFocus()

        // Match the macOS window-tab drag affordance: once the item becomes a window preview,
        // the pointer is the stable center anchor. Returning to an inline tab uses the same
        // center anchor, so the two shapes morph around the pointer instead of orbiting it.
        let frame = FluentTabViewDragGeometry.centeredFrame(at: .zero, size: canvasSize)
        return (image, frame)
    }

    private func payload(from draggingInfo: NSDraggingInfo) -> FluentTabDragPayload? {
        guard let token = draggingInfo.draggingPasteboard.string(forType: fluentTabPasteboardType),
              let payload = FluentTabDragRegistry.shared.payload(for: token),
              payload.scopeIdentifier == effectiveDragScopeIdentifier else { return nil }
        return payload
    }

    private func insertionPosition(for hostX: CGFloat) -> (index: Int, indicatorX: CGFloat) {
        guard !tabItemViews.isEmpty else {
            return (0, tabVisibleFrame.minX)
        }
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let frames = tabItemViews.map { tabViewport.convert($0.frame, to: self) }
        var candidates: [(index: Int, x: CGFloat)] = []
        candidates.reserveCapacity(frames.count + 1)
        candidates.append((0, rtl ? frames[0].maxX : frames[0].minX))
        if frames.count > 1 {
            for index in 1..<frames.count {
                let x = rtl
                    ? (frames[index - 1].minX + frames[index].maxX) / 2
                    : (frames[index - 1].maxX + frames[index].minX) / 2
                candidates.append((index, x))
            }
        }
        candidates.append((frames.count, rtl ? frames[frames.count - 1].minX : frames[frames.count - 1].maxX))
        return candidates.min { abs($0.x - hostX) < abs($1.x - hostX) }
            .map { ($0.index, $0.x) } ?? (0, tabVisibleFrame.minX)
    }

    private func validatedDrop(
        _ sender: NSDraggingInfo
    ) -> (payload: FluentTabDragPayload, insertionIndex: Int)? {
        guard configuration.allowsDropTabs,
              let payload = payload(from: sender) else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        let stripHeight = FluentTabViewMetrics.headerTopPadding + FluentTabViewMetrics.itemHeight
        guard point.x >= bounds.minX,
              point.x <= bounds.maxX,
              point.y >= 0,
              point.y <= stripHeight else { return nil }
        if payload.sourceHost === self, !configuration.canReorderTabs { return nil }
        return (payload, insertionPosition(for: point.x).index)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let validated = validatedDrop(sender) else {
            if let payload = payload(from: sender) {
                payload.sourceTab?.setSystemDragOutsideStrip(true, animated: !context.reduceMotion)
                updateSystemDragPreview(sender, payload: payload, insideStrip: false)
            }
            resetSystemReorderPreview(animated: !context.reduceMotion)
            clearSystemDropIndicator()
            return []
        }
        // Once AppKit owns the drag, the original tab is only a layout placeholder. The
        // NSDraggingItem itself changes between the tab snapshot and the window thumbnail,
        // avoiding two visible copies (or a scaled-up source tab) when the pointer returns.
        validated.payload.sourceTab?.setSystemDragOutsideStrip(true, animated: !context.reduceMotion)
        updateSystemDragPreview(sender, payload: validated.payload, insideStrip: true)
        let point = convert(sender.draggingLocation, from: nil)
        dropIndicatorX = insertionPosition(for: point.x).indicatorX
        updateSystemReorderPreview(
            payload: validated.payload,
            insertionIndex: validated.insertionIndex,
            animated: !context.reduceMotion
        )
        needsDisplay = true
        if validated.payload.sourceHost === self,
           let sourceIndex = tabItemViews.firstIndex(where: { $0 === validated.payload.sourceTab }) {
            let destination = validated.insertionIndex > sourceIndex
                ? validated.insertionIndex - 1
                : validated.insertionIndex
            if destination == sourceIndex { return .move }
        }
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let sender {
            if let payload = payload(from: sender) {
                payload.sourceTab?.setSystemDragOutsideStrip(true, animated: !context.reduceMotion)
                updateSystemDragPreview(sender, payload: payload, insideStrip: false)
            }
        }
        resetSystemReorderPreview(animated: !context.reduceMotion)
        clearSystemDropIndicator()
    }

    private func updateSystemDragPreview(
        _ sender: NSDraggingInfo,
        payload: FluentTabDragPayload,
        insideStrip: Bool
    ) {
        guard let destinationWindow = sender.draggingDestinationWindow ?? window else { return }
        let screenPoint = destinationWindow.convertPoint(toScreen: sender.draggingLocation)
        let image: NSImage
        let frame: NSRect
        if insideStrip,
           let tabImage = payload.tabPreviewImage,
           let sourceTab = payload.sourceTab {
            image = tabImage
            // Re-entering restores the row-constrained tab and resets the pointer hotspot to
            // the tab center, matching the centered window-preview anchor.
            let point = convert(sender.draggingLocation, from: nil)
            let localFrame = FluentTabViewDragGeometry.inlineCenteredFrame(
                at: point,
                size: sourceTab.bounds.size,
                visibleFrame: tabVisibleFrame,
                rowY: FluentTabViewMetrics.headerTopPadding
            )
            frame = destinationWindow.convertToScreen(convert(localFrame, to: nil))
        } else if let windowImage = payload.windowPreviewImage,
                  let windowFrame = payload.windowPreviewFrameRelativeToPointer {
            image = windowImage
            frame = windowFrame.offsetBy(dx: screenPoint.x, dy: screenPoint.y)
        } else if let tabImage = payload.tabPreviewImage,
                  let sourceTab = payload.sourceTab {
            image = tabImage
            frame = FluentTabViewDragGeometry.centeredFrame(
                at: screenPoint,
                size: sourceTab.bounds.size
            )
        } else {
            return
        }

        if let draggingSource = payload.draggingSource {
            draggingSource.updatePreview(
                mode: insideStrip ? .inline : .window,
                frame: frame,
                image: image
            )
            return
        }

        sender.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:]
        ) { draggingItem, _, _ in
            draggingItem.setDraggingFrame(frame, contents: image)
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        validatedDrop(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            resetSystemReorderPreview(animated: !context.reduceMotion)
            clearSystemDropIndicator()
        }
        guard let validated = validatedDrop(sender) else { return false }
        let payload = validated.payload
        if payload.sourceHost === self {
            guard let sourceIndex = tabItemViews.firstIndex(where: { $0 === payload.sourceTab }) else { return false }
            let destination = min(
                max(validated.insertionIndex > sourceIndex ? validated.insertionIndex - 1 : validated.insertionIndex, 0),
                max(configuration.items.count - 1, 0)
            )
            if destination != sourceIndex {
                configuration.onTabMoveRequested?(sourceIndex, destination)
            }
            return true
        }

        let request = FluentTabDropRequest(
            tabID: payload.tabID,
            sourceIndex: payload.sourceIndex,
            destinationIndex: min(max(validated.insertionIndex, 0), configuration.items.count),
            sourceContainerIdentifier: payload.sourceContainerIdentifier,
            destinationContainerIdentifier: configuration.dragContainerIdentifier,
            sourceWindow: payload.sourceWindow,
            destinationWindow: window
        )
        return configuration.onTabDropRequested?(request) == true
    }

    private func clearSystemDropIndicator() {
        guard dropIndicatorX != nil else { return }
        dropIndicatorX = nil
        needsDisplay = true
    }

    private func updateSystemReorderPreview(
        payload: FluentTabDragPayload,
        insertionIndex: Int,
        animated: Bool
    ) {
        guard payload.sourceHost === self,
              let sourceTab = payload.sourceTab,
              let from = tabItemViews.firstIndex(where: { $0 === sourceTab }) else {
            resetSystemReorderPreview(animated: animated)
            return
        }
        let destination = min(
            max(insertionIndex > from ? insertionIndex - 1 : insertionIndex, 0),
            max(tabItemViews.count - 1, 0)
        )
        let frames = tabItemViews.map { tabViewport.convert($0.frame, to: self) }
        for index in tabItemViews.indices where index != from {
            var translation: CGFloat = 0
            if from < destination, index > from, index <= destination {
                translation = frames[index - 1].minX - frames[index].minX
            } else if destination < from, index >= destination, index < from {
                translation = frames[index + 1].minX - frames[index].minX
            }
            tabItemViews[index].setDragTranslation(translation, animated: animated)
        }
    }

    private func resetSystemReorderPreview(animated: Bool) {
        tabItemViews.forEach { $0.setDragTranslation(0, animated: animated) }
    }

    private func updateDrag(
        _ tab: FluentTabItemControl,
        event: NSEvent,
        pointerOffset: NSPoint
    ) {
        guard (configuration.canDragTabs || configuration.canReorderTabs),
              let from = tabItemViews.firstIndex(where: { $0 === tab }) else { return }
        let point = convert(event.locationInWindow, from: nil)
        if draggedTab == nil {
            draggedTab = tab
            draggedFromIndex = from
            tab.setDragging(true, animated: !context.reduceMotion)
        }

        let tearOutBounds = NSRect(
            x: bounds.minX,
            y: 0,
            width: bounds.width,
            height: FluentTabViewMetrics.headerTopPadding + FluentTabViewMetrics.itemHeight
        ).insetBy(dx: -configuration.tearOutDistance, dy: -configuration.tearOutDistance)
        if configuration.canDragTabs, !tearOutBounds.contains(point) {
            beginSystemDrag(tab, event: event, pointerOffset: pointerOffset)
            return
        }

        let destination = configuration.canReorderTabs ? nearestTabIndex(to: point.x) : from
        draggedToIndex = destination
        let frames = tabItemViews.map { tabViewport.convert($0.frame, to: self) }
        if frames.indices.contains(from) {
            let sourceFrame = frames[from]
            let desiredX = min(
                max(point.x - pointerOffset.x, tabVisibleFrame.minX),
                max(tabVisibleFrame.minX, tabVisibleFrame.maxX - sourceFrame.width)
            )
            tab.setDragTranslation(desiredX - sourceFrame.minX, animated: false)
        }
        for index in tabItemViews.indices where index != from {
            var translation: CGFloat = 0
            if from < destination, index > from, index <= destination {
                translation = frames[index - 1].minX - frames[index].minX
            } else if destination < from, index >= destination, index < from {
                translation = frames[index + 1].minX - frames[index].minX
            }
            tabItemViews[index].setDragTranslation(translation, animated: !context.reduceMotion)
        }
        if tabItemViews.indices.contains(destination) {
            let target = frames[destination]
            let before = point.x < target.midX
            dropIndicatorX = before ? target.minX : target.maxX
        }
        needsDisplay = true
    }

    private func finishDrag(_ tab: FluentTabItemControl, locationInWindow: NSPoint) {
        guard activeDraggingSource == nil else { return }
        guard draggedTab === tab, let from = draggedFromIndex else {
            cancelDrag()
            return
        }
        let point = convert(locationInWindow, from: nil)
        let stripBounds = NSRect(
            x: bounds.minX,
            y: 0,
            width: bounds.width,
            height: FluentTabViewMetrics.headerTopPadding + FluentTabViewMetrics.itemHeight
        )
        if stripBounds.contains(point), let to = draggedToIndex, to != from {
            configuration.onTabMoveRequested?(from, to)
        }
        tab.setDragging(false, animated: !context.reduceMotion)
        cancelDrag()
    }

    private func nearestTabIndex(to hostX: CGFloat) -> Int {
        guard !tabItemViews.isEmpty else { return 0 }
        let localX = hostX - tabVisibleFrame.minX
        return tabItemViews.indices.min {
            abs(tabItemViews[$0].frame.midX - localX) < abs(tabItemViews[$1].frame.midX - localX)
        } ?? 0
    }

    private func cancelDrag() {
        draggedTab?.setDragging(false, animated: !context.reduceMotion)
        tabItemViews.forEach { $0.setDragTranslation(0, animated: !context.reduceMotion) }
        draggedTab = nil
        draggedFromIndex = nil
        draggedToIndex = nil
        dropIndicatorX = nil
        needsDisplay = true
    }
}

private final class FluentTabDraggingSource: NSObject, NSDraggingSource {
    private let payload: FluentTabDragPayload
    private let completion: (NSDragOperation, NSPoint, Bool) -> Void
    private var escapeMonitor: Any?
    private var wasCancelled = false
    private weak var activeSession: NSDraggingSession?
    private var latestScreenPoint = NSPoint.zero
    private var tearOutTimer: Timer?
    private var tearOutStartTime: CFTimeInterval = 0
    private var previewMode = FluentTabDragPreviewMode.window
    private var previewTransitionTimer: Timer?
    private var previewTransitionStartTime: CFTimeInterval = 0
    private var previewTransitionStartFrame = NSRect.zero
    private var previewTransitionTargetFrame = NSRect.zero
    private var previewTransitionImage: NSImage?

    init(
        payload: FluentTabDragPayload,
        completion: @escaping (NSDragOperation, NSPoint, Bool) -> Void
    ) {
        self.payload = payload
        self.completion = completion
        super.init()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.wasCancelled = true }
            return event
        }
    }

    deinit {
        cancelInitialTearOutAnimation()
        cancelPreviewTransition()
        removeEscapeMonitor()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        guard payload.sourceTab != nil,
              let image = payload.windowPreviewImage,
              let relativeFrame = payload.windowPreviewFrameRelativeToPointer else { return }
        // AppKit preserves the formation/hotspot established by the initial dragging item unless
        // the session is explicitly ungrouped. A custom draggingFrame is only authoritative in
        // `.none` formation; without this the centered preview is offset by the original tab's
        // pointer hotspot even though the frame math itself is centered.
        session.draggingFormation = .none
        activeSession = session
        latestScreenPoint = screenPoint
        tearOutStartTime = CACurrentMediaTime()
        previewMode = .window

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self,
                  let session = self.activeSession,
                  let sourceTab = self.payload.sourceTab,
                  let window = sourceTab.window else {
                self?.cancelInitialTearOutAnimation()
                return
            }
            let elapsed = CACurrentMediaTime() - self.tearOutStartTime
            let fraction = min(max(elapsed / FluentTabViewMetrics.transitionDuration, 0), 1)
            let progress = FluentAnimationCurve
                .cubicBezier(FluentCubicBezier(0.1, 0.9, 0.2, 1))
                .progress(at: CGFloat(fraction))
            let sourceFrameInWindow = sourceTab.convert(sourceTab.bounds, to: nil)
            let start = window.convertToScreen(sourceFrameInWindow)
                .offsetBy(
                    dx: self.latestScreenPoint.x - screenPoint.x,
                    dy: self.latestScreenPoint.y - screenPoint.y
                )
            let target = relativeFrame.offsetBy(
                dx: self.latestScreenPoint.x,
                dy: self.latestScreenPoint.y
            )
            let frame = NSRect(
                x: start.minX + (target.minX - start.minX) * progress,
                y: start.minY + (target.minY - start.minY) * progress,
                width: start.width + (target.width - start.width) * progress,
                height: start.height + (target.height - start.height) * progress
            )
            session.enumerateDraggingItems(
                options: [],
                for: nil,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { draggingItem, _, _ in
                draggingItem.setDraggingFrame(frame, contents: image)
            }
            if fraction >= 1 { self.cancelInitialTearOutAnimation() }
        }
        tearOutTimer = timer
        // Drag sessions run in NSEventTrackingRunLoopMode, so a default-mode timer would never
        // paint the transition while the mouse button is held.
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        latestScreenPoint = screenPoint
    }

    func updatePreview(
        mode: FluentTabDragPreviewMode,
        frame: NSRect,
        image: NSImage
    ) {
        if tearOutTimer != nil {
            if mode == .window { return }
            cancelInitialTearOutAnimation()
        }

        if mode == previewMode {
            if previewTransitionTimer != nil {
                previewTransitionTargetFrame = frame
                previewTransitionImage = image
            } else {
                setDraggingFrame(frame, image: image)
            }
            return
        }

        previewMode = mode
        startPreviewTransition(to: frame, image: image)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        cancelInitialTearOutAnimation()
        cancelPreviewTransition()
        removeEscapeMonitor()
        FluentTabDragRegistry.shared.remove(payload.token)
        completion(operation, screenPoint, wasCancelled)
    }

    func cancelInitialTearOutAnimation() {
        tearOutTimer?.invalidate()
        tearOutTimer = nil
    }

    private func startPreviewTransition(to frame: NSRect, image: NSImage) {
        guard let session = activeSession else { return }
        cancelPreviewTransition()
        var currentFrame: NSRect?
        session.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:]
        ) { draggingItem, _, _ in
            currentFrame = draggingItem.draggingFrame
        }
        previewTransitionStartFrame = currentFrame ?? frame
        previewTransitionTargetFrame = frame
        previewTransitionImage = image
        previewTransitionStartTime = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self,
                  let image = self.previewTransitionImage else {
                self?.cancelPreviewTransition()
                return
            }
            let elapsed = CACurrentMediaTime() - self.previewTransitionStartTime
            let fraction = min(max(elapsed / FluentTabViewMetrics.transitionDuration, 0), 1)
            let progress = FluentAnimationCurve.cubicBezier(.direct).progress(at: CGFloat(fraction))
            let start = self.previewTransitionStartFrame
            let target = self.previewTransitionTargetFrame
            let frame = NSRect(
                x: start.minX + (target.minX - start.minX) * progress,
                y: start.minY + (target.minY - start.minY) * progress,
                width: start.width + (target.width - start.width) * progress,
                height: start.height + (target.height - start.height) * progress
            )
            self.setDraggingFrame(frame, image: image)
            if fraction >= 1 { self.cancelPreviewTransition() }
        }
        previewTransitionTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func setDraggingFrame(_ frame: NSRect, image: NSImage) {
        activeSession?.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:]
        ) { draggingItem, _, _ in
            draggingItem.setDraggingFrame(frame, contents: image)
        }
    }

    private func cancelPreviewTransition() {
        previewTransitionTimer?.invalidate()
        previewTransitionTimer = nil
        previewTransitionImage = nil
    }

    private func removeEscapeMonitor() {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }
}

private final class FluentClippingView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class FluentTabPassiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class FluentTabPassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class FluentTabItemControl: NSControl {
    let resolvedID: FluentResolvedTabID
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onMoveFocus: ((Bool) -> Void)?
    var onMoveToBoundary: ((Bool) -> Void)?
    var onCycleSelection: ((Bool) -> Void)?
    var onKeyboardReorder: ((Bool) -> Void)?
    var onDrag: ((NSEvent, NSPoint) -> Void)?
    var onDrop: ((NSPoint) -> Void)?

    private var item: FluentTabItem?
    private var theme: FluentTheme = .current
    private var selected = false
    private var widthMode: FluentTabViewWidthMode = .equal
    private var closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode = .auto
    private var layoutDirection: FluentLayoutDirection = .system
    private var canDrag = false
    private var canReorder = false
    private var hidesSeparator = false
    private var isPointerOver = false
    private var isPressed = false
    private var pointerDownLocation: NSPoint?
    private var didBeginDrag = false
    private var isDraggingVisual = false
    private var trackingAreaReference: NSTrackingArea?
    private let titleLabel = FluentTabPassiveLabel(labelWithString: "")
    private let iconView = FluentTabPassiveImageView()
    private let closeButton = FluentTabGlyphButton(kind: .close)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { item?.isEnabled == true }

    var preferredWidth: CGFloat {
        guard let item else { return FluentTabViewMetrics.itemMinWidth }
        let font = resolvedFont
        var width = ceil((item.title as NSString).size(withAttributes: [.font: font]).width)
            + 2 * FluentTabViewMetrics.itemHorizontalPadding
        if item.systemImageName != nil { width += FluentTabViewMetrics.iconSize + FluentTabViewMetrics.iconSpacing }
        if item.isClosable { width += FluentTabViewMetrics.closeMargin + FluentTabViewMetrics.closeWidth }
        return width
    }

    init(resolvedID: FluentResolvedTabID) {
        self.resolvedID = resolvedID
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
        identifier = NSUserInterfaceItemIdentifier("FluentKit.TabView.Tab")
        setAccessibilityRole(.radioButton)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.alignment = .left
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(closeButton)
        closeButton.onInvoke = { [weak self] in self?.onClose?() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    func update(
        item: FluentTabItem,
        theme: FluentTheme,
        selected: Bool,
        widthMode: FluentTabViewWidthMode,
        closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode,
        layoutDirection: FluentLayoutDirection,
        canDrag: Bool,
        canReorder: Bool,
        hidesSeparator: Bool
    ) {
        self.item = item
        self.theme = theme
        self.selected = selected
        self.widthMode = widthMode
        self.closeButtonOverlayMode = closeButtonOverlayMode
        self.layoutDirection = layoutDirection
        self.canDrag = canDrag
        self.canReorder = canReorder
        self.hidesSeparator = hidesSeparator
        isEnabled = item.isEnabled
        userInterfaceLayoutDirection = layoutDirection.appKitValue
        titleLabel.stringValue = item.title
        titleLabel.font = resolvedFont
        titleLabel.textColor = resolvedForeground
        if let systemImageName = item.systemImageName,
           let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil) {
            image.isTemplate = true
            iconView.image = image
            iconView.contentTintColor = resolvedForeground
        } else {
            iconView.image = nil
        }
        setAccessibilityTitle(item.title)
        setAccessibilityValue(selected ? "On" : "Off")
        setAccessibilityEnabled(item.isEnabled)
        updateCloseButton()
        updateSubviewFrames()
        needsDisplay = true
    }

    func updateSubviewFrames() {
        guard let item else { return }
        let compact = widthMode == .compact && !selected && item.systemImageName != nil
        let closeVisible = !closeButton.isHidden
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        var leading = FluentTabViewMetrics.itemHorizontalPadding
        var trailing = bounds.width - FluentTabViewMetrics.itemHorizontalPadding

        if closeVisible {
            let closeX = rtl ? leading : trailing - FluentTabViewMetrics.closeWidth
            closeButton.frame = NSRect(
                x: closeX,
                y: (bounds.height - FluentTabViewMetrics.closeHeight) / 2,
                width: FluentTabViewMetrics.closeWidth,
                height: FluentTabViewMetrics.closeHeight
            )
            if rtl {
                leading = closeButton.frame.maxX + FluentTabViewMetrics.closeMargin
            } else {
                trailing = closeButton.frame.minX - FluentTabViewMetrics.closeMargin
            }
        } else {
            closeButton.frame = .zero
        }

        if item.systemImageName != nil {
            let iconX = compact
                ? bounds.midX - FluentTabViewMetrics.iconSize / 2
                : (rtl ? trailing - FluentTabViewMetrics.iconSize : leading)
            iconView.frame = NSRect(
                x: iconX,
                y: (bounds.height - FluentTabViewMetrics.iconSize) / 2,
                width: FluentTabViewMetrics.iconSize,
                height: FluentTabViewMetrics.iconSize
            )
            if !compact {
                if rtl {
                    trailing = iconView.frame.minX - FluentTabViewMetrics.iconSpacing
                } else {
                    leading = iconView.frame.maxX + FluentTabViewMetrics.iconSpacing
                }
            }
        } else {
            iconView.frame = .zero
        }

        titleLabel.isHidden = compact
        titleLabel.alignment = rtl ? .right : .left
        let lineHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        titleLabel.frame = NSRect(
            x: leading,
            y: floor((bounds.height - lineHeight) / 2),
            width: max(0, trailing - leading),
            height: lineHeight
        )
    }

    func setDragging(_ dragging: Bool, animated: Bool) {
        guard dragging != isDraggingVisual, let layer else { return }
        isDraggingVisual = dragging
        let targetScale: CGFloat = 1
        let targetOpacity: Float = dragging ? 0.86 : 1
        let currentScaleValue = (layer.presentation() ?? layer).value(forKeyPath: "transform.scale") as? NSNumber
        let currentScale = CGFloat(currentScaleValue?.doubleValue ?? 1)
        let currentOpacity = (layer.presentation() ?? layer).opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(targetScale, forKeyPath: "transform.scale")
        layer.opacity = targetOpacity
        CATransaction.commit()
        guard animated else {
            layer.removeAnimation(forKey: "fluent.tabview.drag.scale")
            layer.removeAnimation(forKey: "fluent.tabview.drag.opacity")
            return
        }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = currentScale
        scale.toValue = targetScale
        scale.duration = FluentTabViewMetrics.transitionDuration
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = currentOpacity
        opacity.toValue = targetOpacity
        opacity.duration = FluentTabViewMetrics.transitionDuration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(scale, forKey: "fluent.tabview.drag.scale")
        layer.add(opacity, forKey: "fluent.tabview.drag.opacity")
    }

    func setSystemDragOutsideStrip(_ outside: Bool, animated: Bool) {
        setDragging(false, animated: false)
        guard let layer else { return }
        let currentOpacity = (layer.presentation() ?? layer).opacity
        let targetOpacity: Float = outside ? 0 : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(CGFloat(1), forKeyPath: "transform.scale")
        layer.opacity = targetOpacity
        CATransaction.commit()
        layer.removeAnimation(forKey: "fluent.tabview.drag.scale")
        layer.removeAnimation(forKey: "fluent.tabview.drag.opacity")
        guard animated, abs(currentOpacity - targetOpacity) > 0.001 else { return }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = currentOpacity
        opacity.toValue = targetOpacity
        opacity.duration = FluentTabViewMetrics.transitionDuration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(opacity, forKey: "fluent.tabview.systemDrag.opacity")
    }

    func draggingImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        displayIgnoringOpacity(bounds, in: NSGraphicsContext.current!)
        image.unlockFocus()
        return image
    }

    func finishSystemDrag(animated: Bool) {
        isPressed = false
        pointerDownLocation = nil
        didBeginDrag = false
        setDragTranslation(0, animated: animated)
        setSystemDragOutsideStrip(false, animated: animated)
        refreshInteractiveAppearance()
    }

    func setDragTranslation(_ translation: CGFloat, animated: Bool = false) {
        guard let layer else { return }
        let current = (layer.presentation() ?? layer).transform.m41
        let model = layer.transform.m41
        if abs(model - translation) < 0.25 { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(translation, forKeyPath: "transform.translation.x")
        CATransaction.commit()
        layer.removeAnimation(forKey: "fluent.tabview.drag.reorder")
        guard animated, abs(current - translation) > 0.25 else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = current
        animation.toValue = translation
        animation.duration = FluentTabViewMetrics.transitionDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "fluent.tabview.drag.reorder")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let rect = bounds
        if selected {
            tabSelectedFill.setFill()
            selectedPath(in: rect).fill()
            drawSelectedBorder(in: rect)
        } else if isPointerOver || isPressed {
            let fill = isPressed ? tabPressedFill : tabPointerOverFill
            fill.setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: FluentTabViewMetrics.cornerRadius,
                yRadius: FluentTabViewMetrics.cornerRadius
            ).fill()
        }
        if !hidesSeparator, !selected {
            theme.divider.setFill()
            let x = userInterfaceLayoutDirection == .rightToLeft ? rect.minX : rect.maxX - 1
            NSRect(x: x, y: 8, width: 1, height: max(0, rect.height - 16)).fill()
        }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            let focus = NSBezierPath(
                roundedRect: rect.insetBy(dx: 2.5, dy: 2.5),
                xRadius: FluentTabViewMetrics.cornerRadius,
                yRadius: FluentTabViewMetrics.cornerRadius
            )
            theme.focusStrokeOuter.setStroke()
            focus.lineWidth = theme.focusStrokeWidth
            focus.stroke()
        }
        if !item.isEnabled {
            theme.windowBackground.withAlphaComponent(0.05).setFill()
            rect.fill()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        refreshInteractiveAppearance()
    }

    override func mouseMoved(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPointerOver {
            isPointerOver = inside
            refreshInteractiveAppearance()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        refreshInteractiveAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard item?.isEnabled == true else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        pointerDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDrag = false
        isPressed = true
        onSelect?()
        refreshInteractiveAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed, (canDrag || canReorder), let pointerDownLocation else { return }
        let point = convert(event.locationInWindow, from: nil)
        if didBeginDrag || hypot(point.x - pointerDownLocation.x, point.y - pointerDownLocation.y) >= 4 {
            didBeginDrag = true
            onDrag?(event, pointerDownLocation)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        pointerDownLocation = nil
        if didBeginDrag { onDrop?(event.locationInWindow) }
        didBeginDrag = false
        refreshInteractiveAppearance()
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2,
              item?.isEnabled == true,
              item?.isClosable == true,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.otherMouseUp(with: event)
            return
        }
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        guard item?.isEnabled == true else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control), event.keyCode == 48 {
            onCycleSelection?(!modifiers.contains(.shift))
            return
        }
        if modifiers.contains(.control), event.keyCode == 118, item?.isClosable == true {
            onClose?()
            return
        }
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        switch event.keyCode {
        case 36, 49:
            onSelect?()
        case 123, 124:
            let physicalForward = event.keyCode == 124
            let logicalForward = rtl ? !physicalForward : physicalForward
            if modifiers.contains(.option), modifiers.contains(.shift) {
                onKeyboardReorder?(logicalForward)
            } else {
                onMoveFocus?(logicalForward)
            }
        case 115:
            onMoveToBoundary?(false)
        case 119:
            onMoveToBoundary?(true)
        default:
            super.keyDown(with: event)
        }
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

    override func accessibilityValue() -> Any? { selected ? "On" : "Off" }

    override func accessibilityPerformPress() -> Bool {
        guard item?.isEnabled == true else { return false }
        onSelect?()
        return true
    }

    private var resolvedFont: NSFont {
        NSFont.systemFont(ofSize: 12 * theme.density.metricScale, weight: selected ? .semibold : .regular)
    }

    private var resolvedForeground: NSColor {
        guard item?.isEnabled == true else { return theme.textDisabled }
        if selected { return theme.textPrimary }
        if isPressed { return theme.textTertiary }
        return theme.textSecondary
    }

    private var tabPointerOverFill: NSColor {
        if theme.isHighContrast { return .selectedContentBackgroundColor }
        return theme.isDark
            ? NSColor(calibratedWhite: 1, alpha: 15.0 / 255.0)
            : NSColor(calibratedWhite: 0, alpha: 10.0 / 255.0)
    }

    private var tabPressedFill: NSColor {
        if theme.isHighContrast { return .selectedContentBackgroundColor }
        return theme.isDark
            ? NSColor(calibratedRed: 58.0 / 255.0, green: 58.0 / 255.0, blue: 58.0 / 255.0, alpha: 115.0 / 255.0)
            : NSColor(calibratedWhite: 1, alpha: 179.0 / 255.0)
    }

    private var tabSelectedFill: NSColor {
        if theme.isHighContrast { return theme.windowBackground }
        return theme.isDark
            ? NSColor(calibratedWhite: 40.0 / 255.0, alpha: 1)
            : NSColor(calibratedWhite: 249.0 / 255.0, alpha: 1)
    }

    private func selectedPath(in rect: NSRect) -> NSBezierPath {
        let radius = min(FluentTabViewMetrics.cornerRadius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
        )
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + radius * 0.45)
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }

    private func drawSelectedBorder(in rect: NSRect) {
        let radius = min(FluentTabViewMetrics.cornerRadius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 0.5, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + 0.5, y: rect.minY + radius))
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY + 0.5),
            controlPoint1: NSPoint(x: rect.minX + 0.5, y: rect.minY + radius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY + 0.5)
        )
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY + 0.5))
        path.curve(
            to: NSPoint(x: rect.maxX - 0.5, y: rect.minY + radius),
            controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY + 0.5),
            controlPoint2: NSPoint(x: rect.maxX - 0.5, y: rect.minY + radius * 0.45)
        )
        path.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY))
        theme.cardStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func updateCloseButton() {
        guard let item else { return }
        let modeAllowsClose: Bool
        switch closeButtonOverlayMode {
        case .onPointerOver: modeAllowsClose = selected || isPointerOver
        case .auto, .always: modeAllowsClose = true
        }
        let visible = item.isClosable && modeAllowsClose
        closeButton.isHidden = !visible
        closeButton.setAccessibilityLabel("Close \(item.title)")
        closeButton.setAccessibilityTitle("Close \(item.title)")
        closeButton.update(theme: theme, isEnabled: item.isEnabled)
    }

    private func refreshInteractiveAppearance() {
        titleLabel.textColor = resolvedForeground
        iconView.contentTintColor = resolvedForeground
        updateCloseButton()
        updateSubviewFrames()
        needsDisplay = true
        superview?.superview?.needsLayout = true
    }
}

private final class FluentTabGlyphButton: NSControl {
    enum Kind {
        case add
        case close
        case chevronLeft
        case chevronRight
    }

    let kind: Kind
    var onInvoke: (() -> Void)?
    var onCycleSelection: ((Bool) -> Void)?
    var onCloseCurrent: (() -> Void)?
    private var theme: FluentTheme = .current
    private var controlIsEnabled = true
    private var isPointerOver = false
    private var isPressed = false
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { controlIsEnabled && kind != .close }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    func update(theme: FluentTheme, isEnabled: Bool) {
        self.theme = theme
        controlIsEnabled = isEnabled
        setAccessibilityEnabled(isEnabled)
        if !isEnabled {
            isPressed = false
            isPointerOver = false
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPointerOver || isPressed {
            let fill: NSColor
            if theme.isHighContrast {
                fill = .selectedContentBackgroundColor
            } else {
                fill = isPressed ? theme.subtleFillTertiary : theme.subtleFillSecondary
            }
            fill.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 1, dy: 1),
                xRadius: theme.buttonCornerRadius,
                yRadius: theme.buttonCornerRadius
            ).fill()
        }
        let color = controlIsEnabled ? (isPressed ? theme.textSecondary : theme.textPrimary) : theme.textDisabled
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = kind == .chevronLeft || kind == .chevronRight ? 1.4 : 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .add:
            path.move(to: NSPoint(x: center.x - 4, y: center.y))
            path.line(to: NSPoint(x: center.x + 4, y: center.y))
            path.move(to: NSPoint(x: center.x, y: center.y - 4))
            path.line(to: NSPoint(x: center.x, y: center.y + 4))
        case .close:
            path.move(to: NSPoint(x: center.x - 3.5, y: center.y - 3.5))
            path.line(to: NSPoint(x: center.x + 3.5, y: center.y + 3.5))
            path.move(to: NSPoint(x: center.x + 3.5, y: center.y - 3.5))
            path.line(to: NSPoint(x: center.x - 3.5, y: center.y + 3.5))
        case .chevronLeft:
            path.move(to: NSPoint(x: center.x + 2, y: center.y - 4))
            path.line(to: NSPoint(x: center.x - 2, y: center.y))
            path.line(to: NSPoint(x: center.x + 2, y: center.y + 4))
        case .chevronRight:
            path.move(to: NSPoint(x: center.x - 2, y: center.y - 4))
            path.line(to: NSPoint(x: center.x + 2, y: center.y))
            path.line(to: NSPoint(x: center.x - 2, y: center.y + 4))
        }
        path.stroke()
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            let focus = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 2.5, dy: 2.5),
                xRadius: theme.buttonCornerRadius,
                yRadius: theme.buttonCornerRadius
            )
            theme.focusStrokeOuter.setStroke()
            focus.lineWidth = theme.focusStrokeWidth
            focus.stroke()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard controlIsEnabled else { return }
        isPointerOver = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard controlIsEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        if acceptsFirstResponder { window?.makeFirstResponder(self) }
        isPressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        isPointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        isPointerOver = inside
        needsDisplay = true
        if inside { onInvoke?() }
    }

    override func keyDown(with event: NSEvent) {
        guard controlIsEnabled else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control), event.keyCode == 48 {
            onCycleSelection?(!modifiers.contains(.shift))
            return
        }
        if modifiers.contains(.control), event.keyCode == 118 {
            onCloseCurrent?()
            return
        }
        switch event.keyCode {
        case 36, 49:
            onInvoke?()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard controlIsEnabled else { return false }
        onInvoke?()
        return true
    }
}
