import AppKit

private enum FluentComboBoxPopupMetrics {
    static let popupCornerRadius: CGFloat = 8
    static let popupHorizontalPadding: CGFloat = 0
    static let popupVerticalPadding: CGFloat = 4
    static let rowHeight: CGFloat = 36
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
    static let maximumVisibleItemCount = 15
    static let maximumVisibleItemsOnOneSide = 7
}

enum FluentComboBoxPopupPlacement: Hashable, Sendable {
    /// The selected row occupies the closed control's faceplate and the popup splits around it.
    case selectionCentered
    /// Editable ComboBox uses a TextBox faceplate and opens below, flipping above if needed.
    case editable
}

final class FluentComboBoxPopup: NSObject {
    private let titles: [String]
    private var theme: FluentTheme
    private let reduceMotion: Bool
    private let layoutDirection: NSUserInterfaceLayoutDirection
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
    private let onMove: (Int) -> Void
    private let onCommit: (Int) -> Void
    private let onDismiss: () -> Void

    init(
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

    func present(relativeTo anchor: NSView) {
        guard !titles.isEmpty, let anchorWindow = anchor.window else { return }
        self.anchor = anchor
        registerAppearanceUpdates(from: anchorWindow)
        let centeredIndex = selectedIndex ?? keyboardIndex ?? 0
        let visibleRange = placement == .selectionCentered
            ? initialVisibleRange(centeredOn: centeredIndex)
            : initialVisibleRangeFromStart()
        let size = preferredSize(visibleItemCount: visibleRange.count)
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visibleFrame = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let selectedRowCenter = rowCenterFromTop(for: centeredIndex, firstVisibleIndex: visibleRange.lowerBound)
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
            titles: titles,
            selectedIndex: selectedIndex,
            keyboardIndex: keyboardIndex,
            theme: theme,
            layoutDirection: layoutDirection,
            reduceMotion: reduceMotion,
            initialVisibleRange: visibleRange,
            onMove: { [weak self] index in
                self?.keyboardIndex = index
                self?.onMove(index)
            },
            onCommit: { [weak self] index in
                self?.onCommit(index)
                self?.dismiss(animated: true)
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
        popup.makeKeyAndOrderFront(nil)
        popup.makeFirstResponder(root)
        installOutsideClickMonitors()
    }

    func updateSelectedIndex(_ index: Int?) {
        selectedIndex = titles.indices.contains(index ?? -1) ? index : nil
        if keyboardIndex == nil { keyboardIndex = selectedIndex }
        popupView?.update(
            selectedIndex: selectedIndex,
            keyboardIndex: keyboardIndex
        )
    }

    func dismiss(animated _: Bool) {
        guard let panel else {
            onDismiss()
            return
        }
        popupView?.resetPointerState()
        removeOutsideClickMonitors()
        let finish = { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.anchor?.window?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
            self.popupView = nil
            self.transitionHost = nil
            self.unregisterAppearanceUpdates()
            self.onDismiss()
        }
        // ComboBox popup unload is intentionally immediate. Selection commits, Escape, trigger
        // toggles and outside clicks all remove the complete popup without a close storyboard.
        finish()
    }

    private func preferredSize(visibleItemCount: Int) -> NSSize {
        let font = theme.typography.font(for: .body)
        let widest = titles.reduce(CGFloat(0)) { result, title in
            max(result, (title as NSString).size(withAttributes: [.font: font]).width)
        }
        return NSSize(
            width: max(
                FluentComboBoxPopupMetrics.popupMinimumWidth,
                anchor?.bounds.width ?? 0,
                ceil(widest + 58)
            ),
            height: FluentComboBoxPopupMetrics.popupVerticalPadding * 2
                + CGFloat(visibleItemCount) * FluentComboBoxPopupMetrics.rowHeight
        )
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
            + CGFloat(max(index - firstVisibleIndex, 0)) * FluentComboBoxPopupMetrics.rowHeight
            + FluentComboBoxPopupMetrics.rowHeight / 2
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

    private func apply(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        transitionHost?.update(theme: theme)
        popupView?.update(theme: theme)
        panel?.appearance = fluentAppKitAppearance(for: theme)
        panel?.contentView?.needsDisplay = true
    }

    deinit {
        removeOutsideClickMonitors()
        unregisterAppearanceUpdates()
        panel?.orderOut(nil)
    }
}

private final class FluentComboBoxPopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FluentComboBoxPopupView: NSView {
    private let titles: [String]
    private var theme: FluentTheme
    private let layoutDirection: NSUserInterfaceLayoutDirection
    private let reduceMotion: Bool
    private let onMove: (Int) -> Void
    private let onCommit: (Int) -> Void
    private let onDismiss: () -> Void
    private var selectedIndex: Int?
    private var keyboardIndex: Int?
    private var rows: [FluentComboBoxPopupRow] = []
    private let scrollView = NSScrollView()
    private let rowsHost = FluentComboBoxPopupRowsView()
    private var pendingScrollIndex: Int?
    private var showsKeyboardFocus = false
    private let hoverCoordinator = FluentHoverCoordinator<FluentComboBoxPopupRow> { row, hovering in
        row.setPointerOver(hovering)
    }
    private var geometryObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(
        titles: [String],
        selectedIndex: Int?,
        keyboardIndex: Int?,
        theme: FluentTheme,
        layoutDirection: NSUserInterfaceLayoutDirection,
        reduceMotion: Bool,
        initialVisibleRange: Range<Int>,
        onMove: @escaping (Int) -> Void,
        onCommit: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.keyboardIndex = keyboardIndex
        self.theme = theme
        self.layoutDirection = layoutDirection
        self.reduceMotion = reduceMotion
        self.onMove = onMove
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBoxPopup.ItemsPresenter")
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("ComboBox options")
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
        addSubview(scrollView)
        for (index, title) in titles.enumerated() {
            let row = FluentComboBoxPopupRow(
                index: index,
                title: title,
                theme: theme,
                layoutDirection: layoutDirection,
                reduceMotion: reduceMotion,
                onCommit: { [weak self] index in self?.onCommit(index) },
                onPointerInteraction: { [weak self] in self?.hideKeyboardFocus() },
                onHoverChange: { [weak self] row, hovering in
                    self?.setHoveredRow(row, hovering: hovering)
                }
            )
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
        scrollView.frame = bounds.insetBy(
            dx: FluentComboBoxPopupMetrics.popupHorizontalPadding,
            dy: FluentComboBoxPopupMetrics.popupVerticalPadding
        )
        rowsHost.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: CGFloat(titles.count) * FluentComboBoxPopupMetrics.rowHeight
        )
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: 0,
                y: CGFloat(index) * FluentComboBoxPopupMetrics.rowHeight,
                width: rowsHost.bounds.width,
                height: FluentComboBoxPopupMetrics.rowHeight
            )
        }
        if let pendingScrollIndex {
            scrollView.contentView.scroll(
                to: NSPoint(
                    x: 0,
                    y: CGFloat(pendingScrollIndex) * FluentComboBoxPopupMetrics.rowHeight
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            self.pendingScrollIndex = nil
        }
        refreshPointerState()
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

    override func keyDown(with event: NSEvent) {
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
        NSAccessibility.post(element: rows[index], notification: .focusedUIElementChanged)
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
    let index: Int
    private let title: String
    private var theme: FluentTheme
    private let layoutDirection: NSUserInterfaceLayoutDirection
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
        onPointerInteraction()
        onHoverChange(self, true)
        if pointerState.setPressed(true) {
            updateVisualState(animated: true)
            displayIfNeeded()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldCommit = bounds.contains(point)
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
