import AppKit

private enum FluentComboBoxPopupMetrics {
    static let popupCornerRadius: CGFloat = 8
    static let popupHorizontalPadding: CGFloat = 0
    static let popupVerticalPadding: CGFloat = 4
    static let rowHeight: CGFloat = 36
    /// `ComboBoxItemThemeTouchPadding` (11,11,11,13) instead of the default 11,5,11,7: 12pt taller.
    static let touchRowHeight: CGFloat = 48
    static let rowHorizontalMargin: CGFloat = 5
    static let rowVerticalMargin: CGFloat = 2
    static let rowCornerRadius: CGFloat = 3
    static let rowContentLeadingPadding: CGFloat = 11
    static let rowContentTrailingPadding: CGFloat = 11
    static let pillWidth: CGFloat = 3
    static let pillHeight: CGFloat = 16
    static let pillPressedHeight: CGFloat = 10
    static let pillCornerRadius: CGFloat = 1.5
    static let popupMinimumWidth: CGFloat = 80
    /// `ComboBoxPopupThemeTouchMinWidth`.
    static let popupTouchMinimumWidth: CGFloat = 240
    static let maximumVisibleItemCount = 15
    static let maximumVisibleItemsOnOneSide = 7
}

/// WinUI caps popup content to the available work area, while the faceplate remains its
/// minimum width (ComboBox_Partial.cpp, ArrangePopup). Keep the existing 4pt edge inset.
enum FluentComboBoxPopupSizing {
    static func constrained(_ preferred: NSSize, faceplateWidth: CGFloat, rowHeight: CGFloat,
                            workArea: NSRect) -> NSSize {
        let width = max(1, workArea.width - 8)
        let height = max(1, workArea.height - 8)
        let padding = FluentComboBoxPopupMetrics.popupVerticalPadding * 2
        let rows = max(1, floor((height - padding) / rowHeight))
        return NSSize(width: max(faceplateWidth, min(preferred.width, width)),
                      height: min(preferred.height, height, padding + rows * rowHeight))
    }

    static func visibleRange(_ range: Range<Int>, centeredOn index: Int, height: CGFloat,
                             rowHeight: CGFloat) -> Range<Int> {
        let capacity = max(1, Int((height - FluentComboBoxPopupMetrics.popupVerticalPadding * 2) / rowHeight))
        guard range.count > capacity else { return range }
        let first = min(max(index - capacity / 2, range.lowerBound), range.upperBound - capacity)
        return first..<(first + capacity)
    }
}

enum FluentComboBoxPopupPlacement: Hashable, Sendable {
    /// The selected row occupies the closed control's faceplate and the popup splits around it.
    case selectionCentered
    /// Editable ComboBox uses a TextBox faceplate and opens below, flipping above if needed.
    case editable
}

final class FluentComboBoxPopup: NSObject {
    private var optionIDs: [AnyHashable]
    private var titles: [String]
    private var theme: FluentTheme
    private var reduceMotion: Bool
    private var layoutDirection: NSUserInterfaceLayoutDirection
    private let placement: FluentComboBoxPopupPlacement
    private var selectedIndex: Int?
    private var keyboardIndex: Int?
    private var panel: FluentComboBoxPopupPanel?
    private weak var popupView: FluentComboBoxPopupView?
    private weak var transitionHost: FluentPopupTransitionHost?
    private weak var anchor: NSView?
    private weak var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: FluentPopupScreenObserver?
    private var anchorObserver: FluentPopupAnchorObserver?
    private var selectionCenterFromTop: CGFloat = 0
    private var contentWidth: CGFloat = 0
    private var preferredVisibleItemCount = 0
    private let onMove: (Int) -> Void
    private let onCommit: (Int) -> Void
    private let onDismiss: () -> Void
    /// `ComboBox::m_inputDeviceTypeUsedToOpen`: touch opens use the TouchInputMode item padding
    /// and minimum popup width.
    private(set) var inputDeviceTypeUsedToOpen: FluentInputDeviceType = .none
    var rowHeight: CGFloat {
        inputDeviceTypeUsedToOpen == .touch ? FluentComboBoxPopupMetrics.touchRowHeight : FluentComboBoxPopupMetrics.rowHeight
    }

    init(
        optionIDs: [AnyHashable]? = nil,
        titles: [String],
        selectedIndex: Int?,
        placement: FluentComboBoxPopupPlacement = .selectionCentered,
        theme: FluentTheme,
        layoutDirection: NSUserInterfaceLayoutDirection,
        reduceMotion: Bool,
        onMove: @escaping (Int) -> Void,
        onCommit: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.optionIDs = optionIDs ?? titles.indices.map(AnyHashable.init)
        self.titles = titles
        self.selectedIndex = titles.indices.contains(selectedIndex ?? -1) ? selectedIndex : nil
        keyboardIndex = self.selectedIndex
        self.placement = placement
        self.theme = theme
        self.layoutDirection = layoutDirection
        self.reduceMotion = reduceMotion
        self.onMove = onMove
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        super.init()
    }

    var isPresented: Bool { panel?.isVisible == true }
    var presentedPanelSize: NSSize? { panel?.frame.size }

    func present(relativeTo anchor: NSView) {
        guard !titles.isEmpty, let anchorWindow = anchor.window else { return }
        self.anchor = anchor
        inputDeviceTypeUsedToOpen = FluentInputDeviceTracker.shared.deviceTypeForCurrentInteraction(in: anchorWindow)
        registerAppearanceUpdates(from: anchorWindow)
        let centeredIndex = selectedIndex ?? keyboardIndex ?? 0
        let preferredRange = placement == .selectionCentered
            ? initialVisibleRange(centeredOn: centeredIndex)
            : initialVisibleRangeFromStart()
        preferredVisibleItemCount = preferredRange.count
        measureContentWidth()
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visibleFrame = FluentScreenPlacement.visibleFrame(at: FluentScreenPlacement.topLeading(
            of: anchorRect, rightToLeft: layoutDirection == .rightToLeft), fallback: anchorWindow)
        let size = constrainedSize(in: visibleFrame)
        let visibleRange = FluentComboBoxPopupSizing.visibleRange(preferredRange,
            centeredOn: placement == .selectionCentered ? centeredIndex : preferredRange.lowerBound,
            height: size.height, rowHeight: rowHeight)
        let selectedRowCenter = rowCenterFromTop(for: centeredIndex, firstVisibleIndex: visibleRange.lowerBound)
        selectionCenterFromTop = selectedRowCenter
        let proposedOrigin: NSPoint
        switch placement {
        case .selectionCentered:
            proposedOrigin = NSPoint(
                x: layoutDirection == .rightToLeft ? anchorRect.maxX - size.width : anchorRect.minX,
                y: anchorRect.midY - size.height + selectedRowCenter
            )
        case .editable:
            proposedOrigin = editableOrigin(
                anchorRect: anchorRect,
                size: size,
                visibleFrame: visibleFrame
            )
        }
        let origin = clamped(proposedOrigin, size: size, visibleFrame: visibleFrame)

        let root = FluentComboBoxPopupView(
            optionIDs: optionIDs,
            titles: titles,
            selectedIndex: selectedIndex,
            keyboardIndex: keyboardIndex,
            theme: theme,
            layoutDirection: layoutDirection,
            reduceMotion: reduceMotion,
            rowHeight: rowHeight,
            initialVisibleRange: visibleRange,
            onMove: { [weak self] index in
                guard let self, self.isPresented, self.titles.indices.contains(index) else { return }
                self.keyboardIndex = index
                self.onMove(index)
            },
            onCommit: { [weak self] index in
                // Keep the popup alive across the commit. A commit can replace the declarative
                // anchor (for example when it changes the window theme), whose deinit dismisses
                // this popup reentrantly while the row's mouse-up callback is still running.
                guard let self, self.isPresented, self.titles.indices.contains(index) else { return }
                self.onCommit(index)
                self.dismiss(animated: true)
            },
            onDismiss: { [weak self] in self?.dismiss(animated: true) }
        )
        root.frame = NSRect(origin: .zero, size: size)

        let popup = FluentComboBoxPopupPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        popup.isOpaque = false
        popup.backgroundColor = .clear
        // Keep one edge owner. The stock NSPanel shadow otherwise stacks a black perimeter around
        // the temporary opaque popup surface.
        popup.hasShadow = false
        popup.level = .popUpMenu
        popup.collectionBehavior = [.transient, .fullScreenAuxiliary]
        popup.hidesOnDeactivate = true
        popup.appearance = fluentAppKitAppearance(for: theme) ?? anchorWindow.effectiveAppearance
        let transitionHost = FluentPopupTransitionHost(
            content: root,
            theme: theme,
            cornerRadius: FluentComboBoxPopupMetrics.popupCornerRadius,
            name: "FluentKit.ComboBoxPopup"
        )
        transitionHost.frame = NSRect(origin: .zero, size: size)
        transitionHost.autoresizingMask = [.width, .height]
        popup.contentView = transitionHost
        // Establish row hit regions before presentation, independently of the material backend.
        transitionHost.layoutSubtreeIfNeeded()
        popup.setFrameOrigin(origin)
        anchorWindow.addChildWindow(popup, ordered: .above)
        panel = popup
        popupView = root
        self.transitionHost = transitionHost
        let revealEdge: FluentPopupRevealEdge = origin.y + size.height <= anchorRect.minY ? .top : .bottom
        let entranceBaselineFromTop: CGFloat = switch placement {
        case .selectionCentered:
            selectedRowCenter
        case .editable:
            // Editable ComboBox uses the closed TextBox faceplate as SplitOpen's origin. Depending
            // on popup placement this origin intentionally lives above or below the popup bounds.
            origin.y + size.height - anchorRect.midY
        }
        prepareSurfaceEntrance(
            on: transitionHost,
            edge: revealEdge,
            baselineFromTop: entranceBaselineFromTop
        )
        // Ordering an application-owned transient panel must also work in tests, snapshots and
        // inactive auxiliary windows. `makeKeyAndOrderFront` immediately hides a panel whose
        // `hidesOnDeactivate` flag is set while NSApp is inactive. Keep the panel attached and
        // visible first; only transfer key-window status when the application can actually own it.
        popup.orderFront(nil)
        if NSApp.isActive { popup.makeKey() }
        popup.makeFirstResponder(root)
        installOutsideClickMonitors()
        screenObserver = FluentPopupScreenObserver(window: anchorWindow) { [weak self] in self?.reposition() }
        anchorObserver = FluentPopupAnchorObserver(anchor: anchor, onChange: { [weak self] in self?.reposition() },
            onUnavailable: { [weak self] in self?.dismiss(animated: false) })
    }

    private func reposition() {
        guard let anchor, let window = anchor.window else { dismiss(animated: false); return }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = FluentScreenPlacement.visibleFrame(at: FluentScreenPlacement.topLeading(
            of: rect, rightToLeft: layoutDirection == .rightToLeft), fallback: window)
        updateLayout(in: visible)
    }

    /// Geometry application is separate from screen lookup so every screen notification uses
    /// the same resizing/scroll-preservation path, including a smaller target work area.
    func updateLayout(in visibleFrame: NSRect) {
        guard let panel else { return }
        guard let anchor, let window = anchor.window, panel.parent === window else {
            dismiss(animated: false)
            return
        }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = constrainedSize(in: visibleFrame)
        let center = min(selectionCenterFromTop, max(size.height / 2,
            size.height - FluentComboBoxPopupMetrics.popupVerticalPadding - rowHeight / 2))
        let proposed = placement == .editable ? editableOrigin(anchorRect: rect, size: size, visibleFrame: visibleFrame)
            : NSPoint(x: layoutDirection == .rightToLeft ? rect.maxX - size.width : rect.minX,
                      y: rect.midY - size.height + center)
        let origin = clamped(proposed, size: size, visibleFrame: visibleFrame)
        if size != panel.frame.size {
            popupView?.prepareForViewportResize()
            transitionHost?.settleForAppearanceChange()
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            transitionHost?.settlePresentation()
        } else {
            panel.setFrameOrigin(origin)
        }
    }

    func updateSelectedIndex(_ index: Int?) {
        let next = titles.indices.contains(index ?? -1) ? index : nil
        guard selectedIndex != next else { return }
        selectedIndex = next
        if keyboardIndex == nil { keyboardIndex = selectedIndex }
        popupView?.update(
            selectedIndex: selectedIndex,
            keyboardIndex: keyboardIndex
        )
    }

    /// Reconcile declarative options by their stable value, independently of their display text.
    /// The desktop popup owns its responder and scroll position until explicitly dismissed.
    func updatePresentation(optionIDs: [AnyHashable], titles: [String],
                            layoutDirection: NSUserInterfaceLayoutDirection, reduceMotion: Bool) {
        guard !titles.isEmpty else { dismiss(animated: false); return }
        let optionsChanged = optionIDs != self.optionIDs
        let titlesChanged = titles != self.titles
        let directionChanged = layoutDirection != self.layoutDirection
        let motionChanged = reduceMotion != self.reduceMotion
        guard optionsChanged || titlesChanged || directionChanged || motionChanged else { return }
        if optionsChanged {
            let oldKeyboardIndex = keyboardIndex
            selectedIndex = selectedIndex.flatMap { optionIDs.firstIndex(of: self.optionIDs[$0]) }
            keyboardIndex = keyboardIndex.flatMap { optionIDs.firstIndex(of: self.optionIDs[$0]) }
                ?? oldKeyboardIndex.map { min($0, optionIDs.count - 1) }
        }
        self.optionIDs = optionIDs
        self.titles = titles
        self.layoutDirection = layoutDirection
        self.reduceMotion = reduceMotion
        if optionsChanged || (motionChanged && reduceMotion) { transitionHost?.settlePresentation() }
        if optionsChanged {
            let range = placement == .selectionCentered
                ? initialVisibleRange(centeredOn: keyboardIndex ?? selectedIndex ?? 0) : initialVisibleRangeFromStart()
            preferredVisibleItemCount = range.count
            popupView?.reconcileOptions(optionIDs, titles: titles,
                                        selectedIndex: selectedIndex, keyboardIndex: keyboardIndex)
        }
        popupView?.updatePresentation(titles: titles, layoutDirection: layoutDirection, reduceMotion: reduceMotion)
        if titlesChanged || optionsChanged { measureContentWidth() }
        if optionsChanged || titlesChanged || directionChanged { reposition() }
    }

    func dismiss(animated _: Bool) {
        screenObserver = nil
        anchorObserver?.invalidate()
        anchorObserver = nil
        guard let popupPanel = panel else { return }
        popupView?.resetPointerState()
        removeOutsideClickMonitors()
        // Clear ownership before touching AppKit. `orderOut` and the external callback can both
        // re-enter dismissal, and the theme-changing commit may already be tearing down the
        // anchor host. The panel's local strong reference keeps it valid until cleanup finishes.
        panel = nil
        popupView = nil
        transitionHost = nil
        unregisterAppearanceUpdates()
        popupPanel.parent?.removeChildWindow(popupPanel)
        popupPanel.orderOut(nil)
        // ComboBox popup unload is intentionally immediate. Selection commits, Escape, trigger
        // toggles and outside clicks all remove the complete popup without a close storyboard.
        onDismiss()
    }

    private func measureContentWidth() {
        let font = theme.typography.font(for: .body)
        contentWidth = ceil(titles.reduce(CGFloat(0)) { result, title in
            max(result, (title as NSString).size(withAttributes: [.font: font]).width)
        } + 58)
    }

    private func constrainedSize(in workArea: NSRect) -> NSSize {
        let width = max(contentWidth, inputDeviceTypeUsedToOpen == .touch
            ? FluentComboBoxPopupMetrics.popupTouchMinimumWidth : FluentComboBoxPopupMetrics.popupMinimumWidth)
        return FluentComboBoxPopupSizing.constrained(
            NSSize(width: width, height: FluentComboBoxPopupMetrics.popupVerticalPadding * 2
                   + CGFloat(preferredVisibleItemCount) * rowHeight),
            faceplateWidth: anchor?.bounds.width ?? 0, rowHeight: rowHeight, workArea: workArea)
    }

    private func initialVisibleRange(centeredOn index: Int) -> Range<Int> {
        guard !titles.isEmpty else { return 0..<0 }
        let center = min(max(index, 0), titles.count - 1)
        let first = max(center - FluentComboBoxPopupMetrics.maximumVisibleItemsOnOneSide, 0)
        let last = min(
            center + FluentComboBoxPopupMetrics.maximumVisibleItemsOnOneSide,
            titles.count - 1
        )
        return first..<(last + 1)
    }

    private func initialVisibleRangeFromStart() -> Range<Int> {
        0..<min(titles.count, FluentComboBoxPopupMetrics.maximumVisibleItemCount)
    }

    private func rowCenterFromTop(for index: Int, firstVisibleIndex: Int) -> CGFloat {
        FluentComboBoxPopupMetrics.popupVerticalPadding
            + CGFloat(max(index - firstVisibleIndex, 0)) * rowHeight
            + rowHeight / 2
    }

    private func clamped(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX + 4), max(visibleFrame.maxX - size.width - 4, visibleFrame.minX + 4)),
            y: min(max(origin.y, visibleFrame.minY + 4), max(visibleFrame.maxY - size.height - 4, visibleFrame.minY + 4))
        )
    }

    private func editableOrigin(anchorRect: NSRect, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let gap: CGFloat = 2
        let below = anchorRect.minY - size.height - gap
        let above = anchorRect.maxY + gap
        let minimumY = visibleFrame.minY + 4
        let maximumY = visibleFrame.maxY - size.height - 4
        let y: CGFloat
        if below >= minimumY {
            y = below
        } else if above <= maximumY {
            y = above
        } else {
            y = below
        }
        return NSPoint(
            x: layoutDirection == .rightToLeft ? anchorRect.maxX - size.width : anchorRect.minX,
            y: y
        )
    }

    private func prepareSurfaceEntrance(
        on host: FluentPopupTransitionHost,
        edge: FluentPopupRevealEdge,
        baselineFromTop: CGFloat
    ) {
        fluentPreparePopupEntrance(
            host: host,
            edge: edge,
            motion: FluentMotion.comboBoxOpen,
            closedRatio: 0.5,
            baselineFromTop: baselineFromTop,
            reduceMotion: reduceMotion
        )
    }

    private func installOutsideClickMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self,
               event.window !== self.panel,
               !self.eventTargetsAnchor(event) {
                self.dismiss(animated: true)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss(animated: true)
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func eventTargetsAnchor(_ event: NSEvent) -> Bool {
        guard let anchor,
              event.window === anchor.window else { return false }
        return anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
    }

    private func registerAppearanceUpdates(from window: NSWindow) {
        guard let coordinator = window.fluentAppearanceCoordinator else { return }
        if appearanceCoordinator === coordinator, appearanceRegistration != nil { return }
        unregisterAppearanceUpdates()
        appearanceCoordinator = coordinator
        appearanceRegistration = coordinator.register(
            owner: self,
            prepareForAppearanceChange: { [weak self] in
                self?.transitionHost?.settleForAppearanceChange()
            }
        ) { [weak self] theme in self?.apply(theme: theme) }
    }

    private func unregisterAppearanceUpdates() {
        if let appearanceRegistration {
            appearanceCoordinator?.unregister(appearanceRegistration)
        }
        appearanceRegistration = nil
        appearanceCoordinator = nil
    }

    func apply(theme: FluentTheme) {
        guard self.theme != theme else { return }
        transitionHost?.settleForAppearanceChange()
        self.theme = theme
        transitionHost?.update(theme: theme)
        popupView?.update(theme: theme)
        measureContentWidth()
        reposition()
        panel?.appearance = fluentAppKitAppearance(for: theme)
        panel?.contentView?.needsDisplay = true
    }

    deinit {
        anchorObserver?.invalidate()
        removeOutsideClickMonitors()
        unregisterAppearanceUpdates()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}

private final class FluentComboBoxPopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FluentComboBoxPopupView: NSView {
    private var optionIDs: [AnyHashable]
    private var titles: [String]
    private var theme: FluentTheme
    private var layoutDirection: NSUserInterfaceLayoutDirection
    private var reduceMotion: Bool
    private let onMove: (Int) -> Void
    private let onCommit: (Int) -> Void
    private let onDismiss: () -> Void
    private var selectedIndex: Int?
    private var keyboardIndex: Int?
    private var rows: [FluentComboBoxPopupRow] = []
    private let scrollView = FluentViewportScrollView()
    private let rowsHost = FluentComboBoxPopupRowsView()
    private var pendingScrollIndex: Int?
    private var pendingScrollOffset: CGFloat = 0
    private var pendingRevealIndex: Int?
    private var showsKeyboardFocus = false
    private let hoverCoordinator = FluentHoverCoordinator<FluentComboBoxPopupRow> { row, hovering in
        row.setPointerOver(hovering)
    }
    private var geometryObservers: [NSObjectProtocol] = []
    let rowHeight: CGFloat

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(
        optionIDs: [AnyHashable],
        titles: [String],
        selectedIndex: Int?,
        keyboardIndex: Int?,
        theme: FluentTheme,
        layoutDirection: NSUserInterfaceLayoutDirection,
        reduceMotion: Bool,
        rowHeight: CGFloat = FluentComboBoxPopupMetrics.rowHeight,
        initialVisibleRange: Range<Int>,
        onMove: @escaping (Int) -> Void,
        onCommit: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.optionIDs = optionIDs
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.keyboardIndex = keyboardIndex
        self.theme = theme
        self.layoutDirection = layoutDirection
        self.reduceMotion = reduceMotion
        self.rowHeight = rowHeight
        self.onMove = onMove
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBoxPopup.ItemsPresenter")
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        fluentSetDefaultAccessibilityLabel("ComboBox options")
        scrollView.identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBoxPopup.ScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = titles.count > initialVisibleRange.count
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        rowsHost.identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBoxPopup.Rows")
        scrollView.documentView = rowsHost
        scrollView.onViewportSizeChange = { [weak self] in self?.needsLayout = true }
        addSubview(scrollView)
        for (index, title) in titles.enumerated() {
            let row = makeRow(index: index, title: title)
            rowsHost.addSubview(row)
            rows.append(row)
        }
        pendingScrollIndex = initialVisibleRange.lowerBound
        setAccessibilityChildren(rows)
        updateRows()
        installGeometryObservers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let insetX = FluentComboBoxPopupMetrics.popupHorizontalPadding
        let insetY = FluentComboBoxPopupMetrics.popupVerticalPadding
        let viewport = NSRect(x: insetX, y: insetY, width: max(0, bounds.width - insetX * 2),
                              height: max(0, bounds.height - insetY * 2))
        let needsScroller = CGFloat(titles.count) * rowHeight > viewport.height
        if scrollView.hasVerticalScroller != needsScroller { scrollView.hasVerticalScroller = needsScroller }
        scrollView.frame = viewport
        rowsHost.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: CGFloat(titles.count) * rowHeight
        )
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: 0,
                y: CGFloat(index) * rowHeight,
                width: rowsHost.bounds.width,
                height: rowHeight
            )
        }
        if let pendingScrollIndex {
            scrollView.contentView.scroll(
                to: NSPoint(
                    x: 0,
                    y: min(max(CGFloat(pendingScrollIndex) * rowHeight + pendingScrollOffset, 0),
                           max(0, rowsHost.bounds.height - scrollView.contentSize.height))
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            self.pendingScrollIndex = nil
            pendingScrollOffset = 0
        }
        if let index = pendingRevealIndex, rows.indices.contains(index) {
            pendingRevealIndex = nil
            rowsHost.scrollToVisible(rows[index].frame)
        }
        refreshPointerState()
    }

    func prepareForViewportResize() {
        if showsKeyboardFocus, let keyboardIndex {
            pendingRevealIndex = keyboardIndex
        } else if let selectedIndex, rows.indices.contains(selectedIndex),
                  scrollView.documentVisibleRect.intersects(rows[selectedIndex].frame) {
            pendingRevealIndex = selectedIndex
        }
    }

    func update(selectedIndex: Int?, keyboardIndex: Int?) {
        self.selectedIndex = selectedIndex
        self.keyboardIndex = keyboardIndex
        updateRows()
    }

    func update(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        rows.forEach { $0.update(theme: theme) }
        needsDisplay = true
    }

    private func makeRow(index: Int, title: String) -> FluentComboBoxPopupRow {
        FluentComboBoxPopupRow(index: index, title: title, theme: theme,
            layoutDirection: layoutDirection, reduceMotion: reduceMotion,
            onCommit: { [weak self] index in self?.onCommit(index) },
            onPointerInteraction: { [weak self] in self?.hideKeyboardFocus() },
            onHoverChange: { [weak self] row, hovering in self?.setHoveredRow(row, hovering: hovering) })
    }

    func reconcileOptions(_ optionIDs: [AnyHashable], titles: [String],
                          selectedIndex: Int?, keyboardIndex: Int?) {
        // Cancel before remapping: a mouse-up from the old geometry must not activate the
        // replacement at that index, even when the original row itself survives the update.
        resetPointerState()
        let origin = scrollView.documentVisibleRect.minY
        let firstIndex = min(max(Int(floor(origin / rowHeight)), 0), max(0, self.optionIDs.count - 1))
        let visibleID = self.optionIDs.indices.contains(firstIndex) ? self.optionIDs[firstIndex] : nil
        let retained = Dictionary(uniqueKeysWithValues: zip(self.optionIDs, rows))
        let nextIDs = Set(optionIDs)
        for (id, row) in retained where !nextIDs.contains(id) { row.removeFromSuperview() }
        self.optionIDs = optionIDs
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.keyboardIndex = keyboardIndex
        rows = optionIDs.enumerated().map { index, id in
            let row = retained[id] ?? makeRow(index: index, title: titles[index])
            row.index = index
            if row.superview == nil { rowsHost.addSubview(row) }
            return row
        }
        // Sorting changes the accessibility/drawing order without removing retained views.
        rowsHost.sortSubviews({ first, second, _ in
            guard let first = first as? FluentComboBoxPopupRow,
                  let second = second as? FluentComboBoxPopupRow else { return .orderedSame }
            return first.index < second.index ? .orderedAscending : .orderedDescending
        }, context: nil)
        setAccessibilityChildren(rows)
        pendingScrollIndex = visibleID.flatMap { optionIDs.firstIndex(of: $0) }
            ?? min(firstIndex, max(0, optionIDs.count - 1))
        pendingScrollOffset = origin - CGFloat(firstIndex) * rowHeight
        pendingRevealIndex = showsKeyboardFocus ? keyboardIndex : nil
        updateRows()
        needsLayout = true
    }

    func updatePresentation(titles: [String], layoutDirection: NSUserInterfaceLayoutDirection, reduceMotion: Bool) {
        guard titles.count == rows.count else { return }
        self.titles = titles
        self.layoutDirection = layoutDirection
        self.reduceMotion = reduceMotion
        userInterfaceLayoutDirection = layoutDirection
        scrollView.userInterfaceLayoutDirection = layoutDirection
        rowsHost.userInterfaceLayoutDirection = layoutDirection
        for (row, title) in zip(rows, titles) {
            row.updatePresentation(title: title, layoutDirection: layoutDirection, reduceMotion: reduceMotion)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        guard window?.isVisible == true else { return }
        switch event.keyCode {
        case 53: onDismiss()
        case 125: moveKeyboardSelection(by: 1)
        case 126: moveKeyboardSelection(by: -1)
        case 36, 49:
            if let keyboardIndex { onCommit(keyboardIndex) }
        case 115: moveKeyboardSelection(to: 0)
        case 119: moveKeyboardSelection(to: max(titles.count - 1, 0))
        default: super.keyDown(with: event)
        }
    }

    private func moveKeyboardSelection(by offset: Int) {
        guard !titles.isEmpty else { return }
        let current = keyboardIndex ?? selectedIndex ?? (offset > 0 ? -1 : titles.count)
        moveKeyboardSelection(to: (current + offset + titles.count) % titles.count)
    }

    private func moveKeyboardSelection(to index: Int) {
        guard titles.indices.contains(index) else { return }
        showsKeyboardFocus = true
        keyboardIndex = index
        updateRows()
        rowsHost.scrollToVisible(rows[index].frame)
        onMove(index)
        // The binding callback can synchronously remove/reorder the focused item or dismiss
        // the popup. Announce only the current retained focus, never a pre-callback index.
        if window?.isVisible == true, let current = keyboardIndex, rows.indices.contains(current) {
            NSAccessibility.post(element: rows[current], notification: .focusedUIElementChanged)
        }
    }

    private func updateRows() {
        for (index, row) in rows.enumerated() {
            row.isSelected = index == selectedIndex
            row.isKeyboardSelected = index == keyboardIndex
            row.isKeyboardFocused = showsKeyboardFocus && index == keyboardIndex
            row.setAccessibilitySelected(row.isSelected)
        }
        refreshPointerState()
        needsDisplay = true
    }

    private func hideKeyboardFocus() {
        guard showsKeyboardFocus else { return }
        showsKeyboardFocus = false
        updateRows()
    }

    private func setHoveredRow(_ row: FluentComboBoxPopupRow, hovering: Bool) {
        hoverCoordinator.update(row, hovering: hovering)
    }

    fileprivate func resetPointerState() {
        hoverCoordinator.reset(items: rows)
        rows.forEach { $0.resetPointerState() }
    }

    private func refreshPointerState() {
        guard let window, window.isVisible, window.isKeyWindow else {
            resetPointerState()
            return
        }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let point = convert(windowPoint, from: nil)
        guard scrollView.frame.contains(point) else {
            resetPointerState()
            return
        }
        let rowPoint = rowsHost.convert(windowPoint, from: nil)
        guard let row = rows.first(where: { !$0.isHidden && $0.frame.contains(rowPoint) }) else {
            resetPointerState()
            return
        }
        setHoveredRow(row, hovering: true)
    }

    private func installGeometryObservers() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        geometryObservers = [
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in self?.refreshPointerState() },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object as? NSWindow === self?.window else { return }
                self?.resetPointerState()
            }
        ]
    }

    deinit {
        geometryObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

private final class FluentComboBoxPopupRowsView: NSView {
    override var isFlipped: Bool { true }
}

private final class FluentComboBoxPopupRow: NSView {
    var index: Int
    private var title: String
    private var theme: FluentTheme
    private var layoutDirection: NSUserInterfaceLayoutDirection
    private let onCommit: (Int) -> Void
    private let onPointerInteraction: () -> Void
    private let onHoverChange: (FluentComboBoxPopupRow, Bool) -> Void
    private let surfaceLayer = CALayer()
    private let pillLayer = CALayer()
    private let focusLayer = CAShapeLayer()
    private let visualStateCoordinator = FluentVisualStateCoordinator()
    private lazy var pointerTrackingAreaHost = FluentTrackingAreaHost(
        view: self,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    )
    private var pointerState = FluentPointerInteractionState()
    var isSelected = false { didSet { updateVisualState(animated: false) } }
    var isKeyboardSelected = false { didSet { setAccessibilityFocused(isKeyboardSelected) } }
    var isKeyboardFocused = false { didSet { updateFocusVisual() } }

    override var isFlipped: Bool { true }

    init(
        index: Int,
        title: String,
        theme: FluentTheme,
        layoutDirection: NSUserInterfaceLayoutDirection,
        reduceMotion: Bool,
        onCommit: @escaping (Int) -> Void,
        onPointerInteraction: @escaping () -> Void,
        onHoverChange: @escaping (FluentComboBoxPopupRow, Bool) -> Void
    ) {
        self.index = index
        self.title = title
        self.theme = theme
        self.layoutDirection = layoutDirection
        self.onCommit = onCommit
        self.onPointerInteraction = onPointerInteraction
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(title)
        surfaceLayer.name = "FluentKit.ComboBoxItem.Background"
        surfaceLayer.cornerRadius = FluentComboBoxPopupMetrics.rowCornerRadius
        layer?.addSublayer(surfaceLayer)
        pillLayer.name = "FluentKit.ComboBoxItem.Pill.\(index)"
        pillLayer.cornerRadius = FluentComboBoxPopupMetrics.pillCornerRadius
        layer?.addSublayer(pillLayer)
        focusLayer.name = "FluentKit.ComboBoxItem.KeyboardFocus"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.strokeColor = theme.accent.cgColor
        focusLayer.lineWidth = theme.focusStrokeWidth
        focusLayer.opacity = 0
        layer?.addSublayer(focusLayer)
        visualStateCoordinator.reduceMotion = reduceMotion
        pointerTrackingAreaHost.update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        pointerTrackingAreaHost.update()
    }

    override func layout() {
        super.layout()
        let surface = bounds.insetBy(
            dx: FluentComboBoxPopupMetrics.rowHorizontalMargin,
            dy: FluentComboBoxPopupMetrics.rowVerticalMargin
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = surface
        pillLayer.frame = NSRect(
            x: layoutDirection == .rightToLeft ? surface.maxX - FluentComboBoxPopupMetrics.pillWidth - 1 : surface.minX + 1,
            y: bounds.midY - (pointerState.isPressed ? FluentComboBoxPopupMetrics.pillPressedHeight : FluentComboBoxPopupMetrics.pillHeight) / 2,
            width: FluentComboBoxPopupMetrics.pillWidth,
            height: pointerState.isPressed ? FluentComboBoxPopupMetrics.pillPressedHeight : FluentComboBoxPopupMetrics.pillHeight
        )
        let focusFrame = surface.insetBy(dx: -3, dy: -3)
        focusLayer.frame = focusFrame
        focusLayer.path = CGPath(
            roundedRect: focusLayer.bounds.insetBy(dx: 0.75, dy: 0.75),
            cornerWidth: FluentComboBoxPopupMetrics.rowCornerRadius + 2,
            cornerHeight: FluentComboBoxPopupMetrics.rowCornerRadius + 2,
            transform: nil
        )
        CATransaction.commit()
        updateVisualState(animated: false)
        updateFocusVisual()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerInteraction()
        onHoverChange(self, true)
    }

    override func mouseExited(with event: NSEvent) { onHoverChange(self, false) }

    override func mouseDown(with event: NSEvent) {
        guard canReceiveInput, visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPointerInteraction()
        onHoverChange(self, true)
        if pointerState.setPressed(true) {
            updateVisualState(animated: true)
            displayIfNeeded()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldCommit = pointerState.isPressed && canReceiveInput && visibleRect.contains(point)
        if pointerState.setPressed(false) { updateVisualState(animated: true) }
        if shouldCommit { onCommit(index) }
    }

    func setPointerOver(_ value: Bool) {
        guard pointerState.setPointerOver(value) else { return }
        updateVisualState(animated: false)
    }

    func resetPointerState() {
        guard pointerState.reset() else { return }
        updateVisualState(animated: false)
        pillLayer.removeAllAnimations()
    }

    private var canReceiveInput: Bool { window?.isVisible == true && !isHiddenOrHasHiddenAncestor }

    override func viewDidHide() { super.viewDidHide(); resetPointerState() }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { resetPointerState() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    func updatePresentation(title: String, layoutDirection: NSUserInterfaceLayoutDirection, reduceMotion: Bool) {
        if self.title != title {
            self.title = title
            setAccessibilityTitle(title)
            needsDisplay = true
        }
        if self.layoutDirection != layoutDirection {
            self.layoutDirection = layoutDirection
            userInterfaceLayoutDirection = layoutDirection
            needsLayout = true
            needsDisplay = true
        }
        visualStateCoordinator.reduceMotion = reduceMotion
        if reduceMotion { pillLayer.removeAllAnimations() }
    }

    func update(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.strokeColor = theme.accent.cgColor
        focusLayer.lineWidth = theme.focusStrokeWidth
        CATransaction.commit()
        updateAppearance(state: visualStateCoordinator.state, animated: false)
        updateFocusVisual()
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard canReceiveInput else { return false }
        onCommit(index)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = theme.typography.font(for: .body)
        let size = (title as NSString).size(withAttributes: [.font: font])
        let surface = bounds.insetBy(
            dx: FluentComboBoxPopupMetrics.rowHorizontalMargin,
            dy: FluentComboBoxPopupMetrics.rowVerticalMargin
        )
        let contentWidth = max(0, surface.width - FluentComboBoxPopupMetrics.rowContentLeadingPadding - FluentComboBoxPopupMetrics.rowContentTrailingPadding)
        let x = layoutDirection == .rightToLeft
            ? surface.maxX - FluentComboBoxPopupMetrics.rowContentTrailingPadding - contentWidth
            : surface.minX + FluentComboBoxPopupMetrics.rowContentLeadingPadding
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = layoutDirection == .rightToLeft ? .right : .left
        title.draw(
            in: NSRect(x: x, y: bounds.midY - size.height / 2, width: contentWidth, height: size.height),
            withAttributes: [
                .font: font,
                .foregroundColor: pointerState.isPressed ? theme.textSecondary : theme.textPrimary,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func updateVisualState(animated: Bool) {
        var state: FluentVisualState = .normal
        if isSelected { state.insert(.selected) }
        if pointerState.isPressed {
            state.insert(.pressed)
        } else if pointerState.isPointerOver {
            state.insert(.pointerOver)
        }
        visualStateCoordinator.transition(
            to: state,
            animated: animated,
            motion: FluentMotion.controlFast
        ) { [weak self] transition in
            self?.updateAppearance(state: transition.to, animated: transition.isAnimated)
        }
    }

    private func updateAppearance(state: FluentVisualState, animated: Bool) {
        updatePillFrame(animated: animated)
        let background: NSColor
        if state.contains(.selected) {
            background = state.contains(.pointerOver)
                ? theme.subtleFillTertiary
                : theme.subtleFillSecondary
        } else if state.contains(.pressed) {
            background = theme.subtleFillTertiary
        } else if state.contains(.pointerOver) {
            background = theme.subtleFillSecondary
        } else {
            background = .clear
        }
        surfaceLayer.backgroundColor = background.cgColor
        // WinUI ComboBoxItem pointer and pressed states are fills. A row stroke produces the
        // stacked dark rectangles called out in the visual audit.
        surfaceLayer.borderWidth = 0
        surfaceLayer.borderColor = nil
        pillLayer.name = isSelected
            ? "FluentKit.ComboBoxItem.SelectionPill"
            : "FluentKit.ComboBoxItem.Pill.\(index)"
        pillLayer.backgroundColor = theme.accentFillDefault.cgColor
        pillLayer.opacity = isSelected ? 1 : 0
        setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        needsDisplay = true
    }

    private func updateFocusVisual() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.opacity = isKeyboardFocused ? 1 : 0
        CATransaction.commit()
    }

    private func updatePillFrame(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let surface = bounds.insetBy(
            dx: FluentComboBoxPopupMetrics.rowHorizontalMargin,
            dy: FluentComboBoxPopupMetrics.rowVerticalMargin
        )
        let targetHeight = pointerState.isPressed
            ? FluentComboBoxPopupMetrics.pillPressedHeight
            : FluentComboBoxPopupMetrics.pillHeight
        let target = NSRect(
            x: layoutDirection == .rightToLeft ? surface.maxX - FluentComboBoxPopupMetrics.pillWidth - 1 : surface.minX + 1,
            y: bounds.midY - targetHeight / 2,
            width: FluentComboBoxPopupMetrics.pillWidth,
            height: targetHeight
        )
        let animationKey = "fluent.combobox.pill.frame"
        let activeAnimation = pillLayer.animation(forKey: animationKey) as? CABasicAnimation
        let activeTarget = (activeAnimation?.toValue as? NSValue)?.rectValue
        let presentationFrame = pillLayer.presentation()?.frame ?? pillLayer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.frame = target
        CATransaction.commit()
        // A layout pass can run immediately after mouseDown. Preserve the press animation when
        // layout is only reapplying the same destination frame; otherwise the animation is
        // removed before AppKit has a chance to display its first frame.
        if !animated, let activeTarget, activeTarget == target {
            return
        }
        pillLayer.removeAnimation(forKey: animationKey)
        guard animated, abs(presentationFrame.height - target.height) > 0.001 else { return }
        let animation = CABasicAnimation(keyPath: "frame")
        animation.fromValue = presentationFrame
        animation.toValue = target
        animation.duration = FluentMotion.controlFast.duration
        animation.timingFunction = FluentMotion.controlFast.curve.timingFunction
        pillLayer.add(animation, forKey: animationKey)
    }
}
