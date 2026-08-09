import AppKit

public enum FluentMenuItemState: Hashable, Sendable {
    case off
    case on
    case mixed

    var nsState: NSControl.StateValue {
        switch self {
        case .off: return .off
        case .on: return .on
        case .mixed: return .mixed
        }
    }
}

public enum FluentMenuSelectionIndicator: Hashable, Sendable {
    case checkmark
    case pill
}

public struct FluentMenuItem {
    public let title: String
    public let systemImageName: String?
    public let isEnabled: Bool
    public let state: FluentMenuItemState
    public let selectionIndicator: FluentMenuSelectionIndicator
    public let keyEquivalent: String
    public let keyModifiers: NSEvent.ModifierFlags
    public let submenu: [FluentMenuItem]
    public let action: () -> Void
    let isSeparator: Bool

    public var hasSubmenu: Bool { !submenu.isEmpty }

    public init(
        _ title: String,
        systemImageName: String? = nil,
        isEnabled: Bool = true,
        state: FluentMenuItemState = .off,
        selectionIndicator: FluentMenuSelectionIndicator = .checkmark,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        submenu: [FluentMenuItem] = [],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.state = state
        self.selectionIndicator = selectionIndicator
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.submenu = submenu
        self.action = action
        self.isSeparator = false
    }

    private init(separator: Void) {
        title = ""
        systemImageName = nil
        isEnabled = false
        state = .off
        selectionIndicator = .checkmark
        keyEquivalent = ""
        keyModifiers = []
        submenu = []
        action = {}
        isSeparator = true
    }

    public static var separator: FluentMenuItem { FluentMenuItem(separator: ()) }

    public static func submenu(
        _ title: String,
        systemImageName: String? = nil,
        isEnabled: Bool = true,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) -> FluentMenuItem {
        FluentMenuItem(
            title,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            submenu: items(),
            action: {}
        )
    }

    var reservesCheckSlot: Bool {
        switch state {
        case .off: false
        case .on, .mixed: true
        }
    }
}

@resultBuilder
public enum FluentMenuBuilder {
    public static func buildBlock(_ components: FluentMenuItem...) -> [FluentMenuItem] { components }
    public static func buildOptional(_ component: [FluentMenuItem]?) -> [FluentMenuItem] { component ?? [] }
    public static func buildEither(first component: [FluentMenuItem]) -> [FluentMenuItem] { component }
    public static func buildEither(second component: [FluentMenuItem]) -> [FluentMenuItem] { component }
    public static func buildArray(_ components: [[FluentMenuItem]]) -> [FluentMenuItem] { components.flatMap { $0 } }
}

func makeFluentMenu(items: [FluentMenuItem]) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for item in items {
        if item.isSeparator {
            menu.addItem(.separator())
            continue
        }

        let action = FluentMenuAction(action: item.action)
        let menuItem = NSMenuItem(
            title: item.title,
            action: item.hasSubmenu ? nil : #selector(FluentMenuAction.invoke(_:)),
            keyEquivalent: item.keyEquivalent
        )
        if !item.hasSubmenu {
            menuItem.target = action
            menuItem.representedObject = action
        }
        menuItem.isEnabled = item.isEnabled
        menuItem.state = item.state.nsState
        menuItem.keyEquivalentModifierMask = item.keyModifiers
        if let systemImageName = item.systemImageName,
           let symbol = NSImage(systemSymbolName: systemImageName, accessibilityDescription: item.title) {
            let image = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            ) ?? symbol
            image.isTemplate = true
            menuItem.image = image
        }
        if item.hasSubmenu { menuItem.submenu = makeFluentMenu(items: item.submenu) }
        menu.addItem(menuItem)
    }
    return menu
}

private final class FluentMenuAction: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke(_ sender: Any?) {
        action()
    }
}

/// Placement policy for application-owned flyouts.
public enum FluentMenuPlacement: Hashable, Sendable {
    /// Use the supplied point (context menus) or the standard below/above fallback.
    case automatic
    /// Attach the presenter to the anchor's lower edge, flipping above when needed.
    case below
    /// Center the checked item over the anchor, matching the non-editable ComboBox popup.
    case comboBoxSelection
}

/// A custom in-application menu presenter. The macOS main menu intentionally remains native.
public final class FluentMenuFlyout {
    private let items: [FluentMenuItem]
    private var theme: FluentTheme
    private let minimumWidth: CGFloat
    private let matchesAnchorWidth: Bool
    private let reduceMotion: Bool
    private weak var owner: FluentMenuFlyout?
    private var panel: FluentMenuPanel?
    private var presenter: FluentMenuPresenterView?
    private var childFlyout: FluentMenuFlyout?
    private var childIndex: Int?
    private var pendingSubmenuWorkItem: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private weak var transitionHost: FluentPopupTransitionHost?
    private weak var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    private var layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight

    /// Called after the root presenter has been removed from its panel.
    /// Button-like controls use this to clear their open visual state.
    public var onDismiss: (() -> Void)?

    public init(
        items: [FluentMenuItem],
        theme: FluentTheme = .current,
        minimumWidth: CGFloat = 180,
        matchesAnchorWidth: Bool = true,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        self.items = items
        self.theme = theme
        self.minimumWidth = max(0, minimumWidth)
        self.matchesAnchorWidth = matchesAnchorWidth
        self.reduceMotion = reduceMotion
        owner = nil
    }

    private init(items: [FluentMenuItem], theme: FluentTheme, owner: FluentMenuFlyout) {
        self.items = items
        self.theme = theme
        minimumWidth = 180
        matchesAnchorWidth = false
        reduceMotion = owner.reduceMotion
        self.owner = owner
    }

    /// Whether the application-owned flyout panel is currently presented.
    public var isPresented: Bool { panel != nil }

    public func present(
        relativeTo anchor: NSView,
        at point: NSPoint? = nil,
        placement: FluentMenuPlacement = .automatic
    ) {
        guard owner == nil else {
            owner?.present(relativeTo: anchor, at: point, placement: placement)
            return
        }
        dismissBranch(animated: false)
        guard !items.isEmpty, let anchorWindow = anchor.window else { return }
        anchorView = anchor
        registerAppearanceUpdates(from: anchorWindow)
        layoutDirection = anchor.userInterfaceLayoutDirection
        let resolvedMinimumWidth = matchesAnchorWidth
            ? max(minimumWidth, anchor.bounds.width)
            : minimumWidth
        let size = FluentMenuPresenterView.preferredSize(
            for: items,
            theme: theme,
            minimumWidth: resolvedMinimumWidth
        )
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screenPoint = point.map { anchorWindow.convertPoint(toScreen: anchor.convert($0, to: nil)) }
        let visibleFrame = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let rightToLeft = layoutDirection == .rightToLeft
        var origin: NSPoint
        if placement == .comboBoxSelection {
            let selectedCenterFromTop = selectedRowCenterFromTop() ?? size.height / 2
            origin = NSPoint(
                x: rightToLeft ? anchorRect.maxX - size.width : anchorRect.minX,
                y: anchorRect.midY - size.height + selectedCenterFromTop
            )
        } else if placement == .below {
            origin = belowOrigin(anchorRect: anchorRect, size: size, visibleFrame: visibleFrame, rightToLeft: rightToLeft)
        } else if let screenPoint {
            origin = NSPoint(x: screenPoint.x - (rightToLeft ? size.width : 0), y: screenPoint.y - size.height)
            if origin.y < visibleFrame.minY { origin.y = anchorRect.maxY }
        } else {
            origin = belowOrigin(anchorRect: anchorRect, size: size, visibleFrame: visibleFrame, rightToLeft: rightToLeft)
        }
        let finalOrigin = clamped(origin, size: size, visibleFrame: visibleFrame)
        presentPanel(
            in: anchorWindow,
            origin: finalOrigin,
            direction: layoutDirection,
            presenterMinimumWidth: resolvedMinimumWidth,
            revealEdge: finalOrigin.y + size.height / 2 < anchorRect.midY ? .top : .bottom
        )
    }

    private func belowOrigin(
        anchorRect: NSRect,
        size: NSSize,
        visibleFrame: NSRect,
        rightToLeft: Bool
    ) -> NSPoint {
        let gap: CGFloat = 2
        let belowY = anchorRect.minY - size.height - gap
        let aboveY = anchorRect.maxY + gap
        let minimumY = visibleFrame.minY + 4
        let maximumY = visibleFrame.maxY - size.height - 4
        let y: CGFloat
        if belowY >= minimumY {
            y = belowY
        } else if aboveY <= maximumY {
            y = aboveY
        } else {
            y = belowY
        }
        return NSPoint(
            x: rightToLeft ? anchorRect.maxX - size.width : anchorRect.minX,
            y: y
        )
    }

    private func selectedRowCenterFromTop() -> CGFloat? {
        guard let selectedIndex = items.firstIndex(where: {
            !$0.isSeparator && $0.isEnabled && $0.state == .on
        }) ?? items.firstIndex(where: { !$0.isSeparator && $0.isEnabled }) else {
            return nil
        }
        var top: CGFloat = 2
        for (index, item) in items.enumerated() {
            if index == selectedIndex {
                return top + 2 + 16
            }
            top += item.isSeparator ? 9 : 36
        }
        return nil
    }

    public func dismiss(animated: Bool = true) {
        if let owner {
            owner.root.dismiss(animated: animated)
        } else {
            dismissBranch(animated: animated)
        }
    }

    private var root: FluentMenuFlyout { owner?.root ?? self }

    private func presentSubmenu(relativeTo anchor: NSView) {
        guard let anchorWindow = anchor.window else { return }
        dismissBranch(animated: false)
        // Rows draw with the parent's resolved FlowDirection. Inherit that value explicitly;
        // reading the row's AppKit default here would send RTL submenus to the trailing side.
        layoutDirection = owner?.layoutDirection ?? anchor.userInterfaceLayoutDirection
        let size = FluentMenuPresenterView.preferredSize(for: items, theme: theme, minimumWidth: minimumWidth)
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visibleFrame = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let rightToLeft = layoutDirection == .rightToLeft
        var origin = NSPoint(
            x: rightToLeft ? anchorRect.minX - size.width - 2 : anchorRect.maxX + 2,
            y: anchorRect.maxY - size.height + 2
        )
        let minimumX = visibleFrame.minX + 4
        let maximumX = visibleFrame.maxX - size.width - 4
        if origin.x < minimumX || origin.x > maximumX {
            origin.x = rightToLeft ? anchorRect.maxX + 2 : anchorRect.minX - size.width - 2
        }
        let finalOrigin = clamped(origin, size: size, visibleFrame: visibleFrame)
        presentPanel(
            in: anchorWindow,
            origin: finalOrigin,
            direction: layoutDirection,
            presenterMinimumWidth: minimumWidth,
            revealEdge: finalOrigin.y + size.height / 2 <= anchorRect.midY ? .top : .bottom
        )
    }

    private func presentPanel(
        in anchorWindow: NSWindow,
        origin: NSPoint,
        direction: NSUserInterfaceLayoutDirection,
        presenterMinimumWidth: CGFloat,
        revealEdge: FluentPopupRevealEdge
    ) {
        let presenter = FluentMenuPresenterView(
            items: items,
            theme: theme,
            layoutDirection: direction,
            minimumWidth: presenterMinimumWidth
        )
        let size = presenter.preferredSize
        let panel = FluentMenuPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // NSPanel's stock shadow produces a hard black perimeter around a borderless pop-up.
        // The temporary opaque popup surface owns the complete edge treatment.
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.appearance = anchorWindow.effectiveAppearance

        // One shared Liquid Glass surface owns the fill and edge; the theme-level material switch
        // replaces it with an opaque fallback without changing popup geometry.
        let transitionHost = FluentPopupTransitionHost(
            content: presenter,
            theme: theme,
            cornerRadius: theme.designTokens.cardCornerRadius,
            name: "FluentKit.MenuFlyout"
        )
        transitionHost.frame = NSRect(origin: .zero, size: size)
        transitionHost.autoresizingMask = [.width, .height]
        panel.contentView = transitionHost

        presenter.onDismiss = { [weak self] in self?.root.dismiss() }
        presenter.onSelection = { [weak self] index, row in self?.scheduleSubmenu(index: index, row: row) }
        presenter.onSubmenu = { [weak self] index, row in self?.openSubmenu(index: index, row: row) }
        presenter.onCloseSubmenu = { [weak self] in self?.closeFromKeyboard() }
        parentWindow = anchorWindow
        anchorWindow.addChildWindow(panel, ordered: .above)
        self.panel = panel
        self.presenter = presenter
        self.transitionHost = transitionHost
        panel.setFrameOrigin(origin)
        if owner == nil { installOutsideClickMonitors() }

        panel.alphaValue = 1
        prepareSurfaceEntrance(
            host: transitionHost,
            edge: revealEdge,
            motion: owner == nil ? FluentMotion.menuOpen : FluentMotion.submenuOpen
        )
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(presenter)
    }

    private func prepareSurfaceEntrance(
        host: FluentPopupTransitionHost,
        edge: FluentPopupRevealEdge,
        motion: FluentMotionToken
    ) {
        // MenuFlyout uses ClosedRatio=0.5 for the root and 0.67 for nested presenters.
        fluentPrepareMenuPopupEntrance(
            host: host,
            edge: edge,
            motion: motion,
            closedRatio: owner == nil ? 0.5 : 0.67,
            reduceMotion: reduceMotion
        )
    }

    private func scheduleSubmenu(index: Int, row: FluentMenuItemRow) {
        pendingSubmenuWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak row] in
            guard let self, let row, self.presenter?.selectedIndex == index else { return }
            self.openSubmenu(index: index, row: row)
        }
        pendingSubmenuWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func openSubmenu(index: Int, row: FluentMenuItemRow) {
        pendingSubmenuWorkItem?.cancel()
        pendingSubmenuWorkItem = nil
        guard let item = presenter?.item(at: index), item.isEnabled, item.hasSubmenu else {
            closeChild()
            return
        }
        if childIndex == index, childFlyout?.isPresented == true { return }
        closeChild()
        let child = FluentMenuFlyout(items: item.submenu, theme: theme, owner: self)
        childIndex = index
        childFlyout = child
        child.presentSubmenu(relativeTo: row)
    }

    private func closeChild() {
        pendingSubmenuWorkItem?.cancel()
        pendingSubmenuWorkItem = nil
        childFlyout?.dismissBranch(animated: false)
        childFlyout = nil
        childIndex = nil
    }

    private func closeFromKeyboard() {
        if let owner {
            owner.closeChild()
            owner.presenter?.window?.makeKeyAndOrderFront(nil)
            if let presenter = owner.presenter { owner.presenter?.window?.makeFirstResponder(presenter) }
        } else {
            dismissBranch(animated: false)
        }
    }

    private func dismissBranch(animated _: Bool) {
        pendingSubmenuWorkItem?.cancel()
        pendingSubmenuWorkItem = nil
        childFlyout?.dismissBranch(animated: false)
        childFlyout = nil
        childIndex = nil
        presenter?.resetPointerState()
        if owner == nil { removeOutsideClickMonitors() }
        guard let popupPanel = panel else { return }
        panel = nil
        presenter = nil
        transitionHost = nil
        if owner == nil { anchorView = nil }
        if owner == nil { unregisterAppearanceUpdates() }
        popupPanel.parent?.removeChildWindow(popupPanel)
        popupPanel.orderOut(nil)
        // MenuFlyout unload is intentionally immediate in FluentKit. Only entrance motion is
        // retained; dismissing from an item, Escape, the trigger, or an outside click removes the
        // complete presenter in one transaction.
        onDismiss?()
    }

    private func installOutsideClickMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self,
               !self.contains(window: event.window),
               !self.eventTargetsAnchor(event) {
                self.dismiss()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func contains(window: NSWindow?) -> Bool {
        guard let window else { return false }
        if panel === window { return true }
        return childFlyout?.contains(window: window) ?? false
    }

    private func eventTargetsAnchor(_ event: NSEvent) -> Bool {
        guard owner == nil,
              let anchorView,
              event.window === anchorView.window else { return false }
        return anchorView.bounds.contains(anchorView.convert(event.locationInWindow, from: nil))
    }

    private func removeOutsideClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func registerAppearanceUpdates(from window: NSWindow) {
        guard owner == nil, let coordinator = window.fluentAppearanceCoordinator else { return }
        if appearanceCoordinator === coordinator, appearanceRegistration != nil { return }
        unregisterAppearanceUpdates()
        appearanceCoordinator = coordinator
        appearanceRegistration = coordinator.register(
            owner: self,
            prepareForAppearanceChange: { [weak self] in
                self?.prepareForAppearanceChange()
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
        panel?.appearance = fluentAppKitAppearance(for: theme)
        transitionHost?.update(theme: theme)
        presenter?.update(theme: theme)
        childFlyout?.apply(theme: theme)
    }

    private func prepareForAppearanceChange() {
        transitionHost?.settleForAppearanceChange()
        childFlyout?.prepareForAppearanceChange()
    }

    deinit {
        removeOutsideClickMonitors()
        unregisterAppearanceUpdates()
        childFlyout?.dismissBranch(animated: false)
        panel?.orderOut(nil)
    }

    private func clamped(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX + 4), max(visibleFrame.maxX - size.width - 4, visibleFrame.minX + 4)),
            y: min(max(origin.y, visibleFrame.minY + 4), max(visibleFrame.maxY - size.height - 4, visibleFrame.minY + 4))
        )
    }
}

private final class FluentMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FluentMenuPresenterView: NSView {
    let preferredSize: NSSize
    var onDismiss: (() -> Void)?
    var onSelection: ((Int, FluentMenuItemRow) -> Void)?
    var onSubmenu: ((Int, FluentMenuItemRow) -> Void)?
    var onCloseSubmenu: (() -> Void)?

    private let items: [FluentMenuItem]
    private var theme: FluentTheme
    private let layoutDirection: NSUserInterfaceLayoutDirection
    private var itemRows: [Int: FluentMenuItemRow] = [:]
    private var typeahead = ""
    private var typeaheadResetWorkItem: DispatchWorkItem?
    private(set) var selectedIndex: Int?
    private var showsKeyboardSelection = false
    private let hoverCoordinator = FluentHoverCoordinator<FluentMenuItemRow> { row, hovering in
        row.setPointerOver(hovering)
    }
    private var windowObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(
        items: [FluentMenuItem],
        theme: FluentTheme,
        layoutDirection: NSUserInterfaceLayoutDirection,
        minimumWidth: CGFloat
    ) {
        self.items = items
        self.theme = theme
        self.layoutDirection = layoutDirection
        preferredSize = Self.preferredSize(for: items, theme: theme, minimumWidth: minimumWidth)
        super.init(frame: NSRect(origin: .zero, size: preferredSize))
        userInterfaceLayoutDirection = layoutDirection
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        let showsCheckPlaceholder = items.contains { !$0.isSeparator && $0.reservesCheckSlot }
        let showsIconPlaceholder = items.contains { !$0.isSeparator && $0.systemImageName != nil }

        var y: CGFloat = 2
        for (index, item) in items.enumerated() {
            if item.isSeparator {
                let separator = FluentMenuSeparatorView(theme: theme)
                separator.frame = NSRect(x: 8, y: y, width: preferredSize.width - 16, height: 9)
                addSubview(separator)
                y += 9
                continue
            }
            let row = FluentMenuItemRow(
                item: item,
                theme: theme,
                accelerator: Self.accelerator(for: item),
                layoutDirection: layoutDirection,
                showsCheckPlaceholder: showsCheckPlaceholder,
                showsIconPlaceholder: showsIconPlaceholder
            )
            row.frame = NSRect(x: 4, y: y + 2, width: preferredSize.width - 8, height: 32)
            row.onHoverChange = { [weak self] row, hovering in
                self?.setHoveredRow(row, index: index, hovering: hovering)
            }
            row.onInvoke = { [weak self] in self?.invoke(index) }
            addSubview(row)
            itemRows[index] = row
            y += 36
        }
        // MenuFlyout has no persistent selected-row background. Check state is represented only by
        // its checkmark; pointer-over and explicit keyboard navigation own transient row fills.
        selectedIndex = nil
        updateSelection()
        setAccessibilityChildren(itemRows.keys.sorted().compactMap { itemRows[$0] })
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object as? NSWindow === self?.window else { return }
            self?.resetPointerState()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onDismiss?()
        case 125: moveSelection(by: 1)
        case 126: moveSelection(by: -1)
        case 36, 49:
            if let selectedIndex { invoke(selectedIndex) }
        case 124:
            if let selectedIndex, let row = itemRows[selectedIndex], items[selectedIndex].hasSubmenu {
                onSubmenu?(selectedIndex, row)
            }
        case 123: onCloseSubmenu?()
        case 115:
            if let first = enabledIndices.first { select(first, announce: true, keyboard: true) }
        case 119:
            if let last = enabledIndices.last { select(last, announce: true, keyboard: true) }
        default: super.keyDown(with: event)
        }
        if ![53, 125, 126, 36, 49, 124, 123, 115, 119].contains(event.keyCode) {
            handleTypeahead(event)
        }
    }

    private var enabledIndices: [Int] {
        items.indices.filter { !items[$0].isSeparator && items[$0].isEnabled }
    }

    private func moveSelection(by offset: Int) {
        let enabled = enabledIndices
        guard !enabled.isEmpty else { return }
        if let current = selectedIndex.flatMap({ enabled.firstIndex(of: $0) }) {
            selectedIndex = enabled[(current + offset + enabled.count) % enabled.count]
        } else {
            selectedIndex = offset >= 0 ? enabled.first : enabled.last
        }
        showsKeyboardSelection = true
        updateSelection()
        if let selectedIndex, let row = itemRows[selectedIndex] {
            onSelection?(selectedIndex, row)
            NSAccessibility.post(element: row, notification: .focusedUIElementChanged)
        }
    }

    private func select(_ index: Int, announce: Bool, keyboard: Bool) {
        guard items.indices.contains(index) else { return }
        guard items[index].isEnabled else { return }
        if keyboard { hoverCoordinator.reset(items: itemRows.values) }
        selectedIndex = index
        showsKeyboardSelection = keyboard
        updateSelection()
        if let row = itemRows[index] {
            onSelection?(index, row)
            if announce { NSAccessibility.post(element: row, notification: .focusedUIElementChanged) }
        }
    }

    private func updateSelection() {
        for (index, row) in itemRows {
            let selected = showsKeyboardSelection && index == selectedIndex
            row.isKeyboardSelected = selected
            row.setAccessibilitySelected(selected)
        }
    }

    private func setHoveredRow(_ row: FluentMenuItemRow, index: Int, hovering: Bool) {
        hoverCoordinator.update(row, hovering: hovering)
        if hovering {
            select(index, announce: true, keyboard: false)
        } else if !showsKeyboardSelection, selectedIndex == index {
            selectedIndex = nil
            updateSelection()
        }
    }

    func resetPointerState() {
        hoverCoordinator.reset(items: itemRows.values)
        itemRows.values.forEach { $0.resetPointerState() }
        if !showsKeyboardSelection {
            selectedIndex = nil
            updateSelection()
        }
    }

    func update(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        for subview in subviews {
            if let row = subview as? FluentMenuItemRow {
                row.update(theme: theme)
            } else if let separator = subview as? FluentMenuSeparatorView {
                separator.update(theme: theme)
            }
        }
        needsDisplay = true
    }

    private func invoke(_ index: Int) {
        guard items.indices.contains(index), items[index].isEnabled else { return }
        if items[index].hasSubmenu, let row = itemRows[index] {
            onSubmenu?(index, row)
            return
        }
        items[index].action()
        onDismiss?()
    }

    func item(at index: Int) -> FluentMenuItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    func focusFirstItem() {
        if let first = enabledIndices.first { select(first, announce: false, keyboard: true) }
    }

    private func handleTypeahead(_ event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1,
              characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return }
        typeahead += characters
        typeaheadResetWorkItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in self?.typeahead = "" }
        typeaheadResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: reset)
        let matching = enabledIndices.first { items[$0].title.lowercased().hasPrefix(typeahead) }
            ?? (typeahead.count > 1 ? enabledIndices.first { items[$0].title.lowercased().hasPrefix(characters) } : nil)
        if let matching { select(matching, announce: true, keyboard: true) }
    }

    static func preferredSize(for items: [FluentMenuItem], theme: FluentTheme, minimumWidth: CGFloat) -> NSSize {
        let font = theme.typography.font(for: .body)
        let placeholderCount = (items.contains { !$0.isSeparator && $0.reservesCheckSlot } ? 1 : 0)
            + (items.contains { !$0.isSeparator && $0.systemImageName != nil } ? 1 : 0)
        let widest = items.filter { !$0.isSeparator }.reduce(CGFloat(0)) { result, item in
            let titleWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
            let keyWidth = (Self.accelerator(for: item) as NSString).size(withAttributes: [.font: font]).width
            let trailingWidth = (!item.keyEquivalent.isEmpty ? keyWidth + 24 : 0)
                + (item.hasSubmenu ? 36 : 0)
            return max(result, titleWidth + CGFloat(placeholderCount * 28) + trailingWidth)
        }
        let height = 4 + items.reduce(CGFloat(0)) { $0 + ($1.isSeparator ? 9 : 36) }
        // 11pt narrow padding lives inside each row, while the source template also applies a
        // separate 4pt MenuFlyoutItemMargin on both horizontal edges.
        return NSSize(width: max(minimumWidth, ceil(widest + 30)), height: max(8, height))
    }

    private static func accelerator(for item: FluentMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        var value = ""
        if item.keyModifiers.contains(.control) { value += "⌃" }
        if item.keyModifiers.contains(.option) { value += "⌥" }
        if item.keyModifiers.contains(.shift) { value += "⇧" }
        if item.keyModifiers.contains(.command) { value += "⌘" }
        return value + item.keyEquivalent.uppercased()
    }

    deinit {
        typeaheadResetWorkItem?.cancel()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
    }
}

private final class FluentMenuItemRow: NSControl {
    var isKeyboardSelected = false { didSet { needsDisplay = true } }
    var onHoverChange: ((FluentMenuItemRow, Bool) -> Void)?
    var onInvoke: (() -> Void)?

    private let item: FluentMenuItem
    private var theme: FluentTheme
    private let accelerator: String
    private let layoutDirection: NSUserInterfaceLayoutDirection
    private let showsCheckPlaceholder: Bool
    private let showsIconPlaceholder: Bool
    private let iconView = NSImageView()
    private let selectionPillLayer = CALayer()
    private var pointerState = FluentPointerInteractionState()
    private lazy var pointerTrackingAreaHost = FluentTrackingAreaHost(
        view: self,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    )

    init(
        item: FluentMenuItem,
        theme: FluentTheme,
        accelerator: String,
        layoutDirection: NSUserInterfaceLayoutDirection,
        showsCheckPlaceholder: Bool,
        showsIconPlaceholder: Bool
    ) {
        self.item = item
        self.theme = theme
        self.accelerator = accelerator
        self.layoutDirection = layoutDirection
        self.showsCheckPlaceholder = showsCheckPlaceholder
        self.showsIconPlaceholder = showsIconPlaceholder
        super.init(frame: .zero)
        userInterfaceLayoutDirection = layoutDirection
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Menu.Item")
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(item.title)
        setAccessibilityEnabled(item.isEnabled)
        setAccessibilityValue(item.hasSubmenu ? "Submenu" : accessibilityState)
        setAccessibilityHelp(
            item.hasSubmenu
                ? "Opens a submenu"
                : (accelerator.isEmpty ? nil : "Keyboard shortcut \(accelerator)")
        )
        if showsIconPlaceholder, let systemImageName = item.systemImageName {
            iconView.identifier = NSUserInterfaceItemIdentifier("FluentKit.Menu.Item.Icon")
            iconView.imageScaling = .scaleProportionallyDown
            iconView.setAccessibilityElement(false)
            if let symbol = NSImage(systemSymbolName: systemImageName, accessibilityDescription: item.title) {
                let image = symbol.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                ) ?? symbol
                image.isTemplate = true
                iconView.image = image
            }
            addSubview(iconView)
        }
        if item.state == .on, item.selectionIndicator == .pill {
            selectionPillLayer.name = "FluentKit.ComboBoxItem.SelectionPill"
            selectionPillLayer.backgroundColor = theme.accentFillDefault.cgColor
            selectionPillLayer.cornerRadius = 1.5
            layer?.addSublayer(selectionPillLayer)
        }
        pointerTrackingAreaHost.update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        pointerTrackingAreaHost.update()
    }

    override func layout() {
        super.layout()
        if iconView.superview != nil {
            let logicalX: CGFloat = 11 + (showsCheckPlaceholder ? 28 : 0)
            let slot = physicalRect(logicalX: logicalX, width: 16)
            iconView.frame = NSRect(
                x: slot.minX,
                y: bounds.midY - 8,
                width: 16,
                height: 16
            )
        }
        updateSelectionPill(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(self, true)
    }

    override func mouseExited(with event: NSEvent) { onHoverChange?(self, false) }

    override func mouseDown(with event: NSEvent) {
        guard item.isEnabled else { return }
        onHoverChange?(self, true)
        if pointerState.setPressed(true) {
            updateSelectionPill(animated: true)
            needsDisplay = true
            displayIfNeeded()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.pointerState.setPressed(false) {
                self.updateSelectionPill(animated: true)
                self.needsDisplay = true
            }
            self.onInvoke?()
        }
    }

    func setPointerOver(_ value: Bool) {
        guard pointerState.setPointerOver(value) else { return }
        needsDisplay = true
    }

    func resetPointerState() {
        guard pointerState.reset() else { return }
        updateSelectionPill(animated: false)
        needsDisplay = true
    }

    func update(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        selectionPillLayer.backgroundColor = theme.accentFillDefault.cgColor
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard item.isEnabled else { return false }
        onInvoke?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let state = resolvedVisualState
        let background = theme.menuItemBackground(for: state)
        if background.alphaComponent > 0 {
            let fill = background
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let foreground = theme.menuItemForeground(for: state)
        let acceleratorForeground = theme.menuAcceleratorForeground(for: state)
        iconView.contentTintColor = foreground
        let font = theme.typography.font(for: .body)
        let titleSize = (item.title as NSString).size(withAttributes: [.font: font])

        let rightToLeft = layoutDirection == .rightToLeft
        let checkSlot = physicalRect(logicalX: 11, width: 16)
        switch item.state {
        case .off: break
        case .on:
            if item.selectionIndicator == .checkmark {
                let mark = NSBezierPath()
                let x = checkSlot.minX + 1
                mark.move(to: NSPoint(x: x, y: bounds.midY))
                // The check slot follows FlowDirection, but the check glyph itself is not
                // mirrored. WinUI only mirrors directional submenu chevrons in RTL.
                mark.line(to: NSPoint(x: x + 4, y: bounds.midY - 4))
                mark.line(to: NSPoint(x: x + 11, y: bounds.midY + 4))
                mark.lineWidth = 1.7
                mark.lineCapStyle = .round
                foreground.setStroke()
                mark.stroke()
            }
        case .mixed:
            foreground.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: checkSlot.minX + 1, y: bounds.midY - 1, width: 11, height: 2),
                xRadius: 1,
                yRadius: 1
            ).fill()
        }

        var trailingLogicalX = bounds.width - 11
        var acceleratorRect: NSRect?
        var chevronRect: NSRect?
        if item.hasSubmenu {
            trailingLogicalX -= 12
            chevronRect = physicalRect(logicalX: trailingLogicalX, width: 12)
            trailingLogicalX -= 24
        }
        if !accelerator.isEmpty {
            let acceleratorSize = (accelerator as NSString).size(withAttributes: [.font: font])
            trailingLogicalX -= acceleratorSize.width
            acceleratorRect = physicalRect(logicalX: trailingLogicalX, width: acceleratorSize.width)
            trailingLogicalX -= 24
        }
        let placeholderCount = (showsCheckPlaceholder ? 1 : 0) + (showsIconPlaceholder ? 1 : 0)
        let titleLogicalX = 11 + CGFloat(placeholderCount * 28)
        let titleRect = physicalRect(
            logicalX: titleLogicalX,
            width: max(0, trailingLogicalX - titleLogicalX)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        (item.title as NSString).draw(
            in: NSRect(
                x: titleRect.minX,
                y: bounds.midY - titleSize.height / 2,
                width: titleRect.width,
                height: titleSize.height
            ),
            withAttributes: [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
        )
        if let acceleratorRect {
            let acceleratorSize = (accelerator as NSString).size(withAttributes: [.font: font])
            (accelerator as NSString).draw(
                in: NSRect(
                    x: acceleratorRect.minX,
                    y: bounds.midY - acceleratorSize.height / 2,
                    width: acceleratorRect.width,
                    height: acceleratorSize.height
                ),
                withAttributes: [.font: font, .foregroundColor: acceleratorForeground]
            )
        }
        if let chevronRect {
            let x = chevronRect.midX
            let chevron = NSBezierPath()
            if rightToLeft {
                chevron.move(to: NSPoint(x: x + 3, y: bounds.midY - 4))
                chevron.line(to: NSPoint(x: x - 1, y: bounds.midY))
                chevron.line(to: NSPoint(x: x + 3, y: bounds.midY + 4))
            } else {
                chevron.move(to: NSPoint(x: x - 3, y: bounds.midY - 4))
                chevron.line(to: NSPoint(x: x + 1, y: bounds.midY))
                chevron.line(to: NSPoint(x: x - 3, y: bounds.midY + 4))
            }
            chevron.lineWidth = 1.4
            foreground.setStroke()
            chevron.stroke()
        }
    }

    private var resolvedVisualState: FluentControlState {
        guard item.isEnabled else { return .disabled }
        if pointerState.isPressed { return .pressed }
        if pointerState.isPointerOver || isKeyboardSelected { return .pointerOver }
        return .normal
    }

    private func physicalRect(logicalX: CGFloat, width: CGFloat) -> NSRect {
        let x = layoutDirection == .rightToLeft
            ? bounds.width - logicalX - width
            : logicalX
        return NSRect(x: x, y: 0, width: max(width, 0), height: 0)
    }

    private func updateSelectionPill(animated: Bool) {
        guard item.state == .on, item.selectionIndicator == .pill else { return }
        let targetHeight: CGFloat = pointerState.isPressed ? 10 : 16
        let targetFrame = NSRect(
            x: layoutDirection == .rightToLeft ? bounds.maxX - 3 : bounds.minX,
            y: bounds.midY - targetHeight / 2,
            width: 3,
            height: targetHeight
        )
        let presentationFrame = selectionPillLayer.presentation()?.frame ?? selectionPillLayer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionPillLayer.frame = targetFrame
        CATransaction.commit()
        selectionPillLayer.removeAnimation(forKey: "fluent.combobox.pill.frame")
        guard animated, abs(presentationFrame.height - targetFrame.height) > 0.001 else { return }
        let motion = FluentMotion.controlFast
        let animation = CABasicAnimation(keyPath: "frame")
        animation.fromValue = presentationFrame
        animation.toValue = targetFrame
        animation.duration = motion.duration
        animation.timingFunction = motion.curve.timingFunction
        selectionPillLayer.add(animation, forKey: "fluent.combobox.pill.frame")
    }

    private var accessibilityState: String {
        switch item.state {
        case .off: return "Not selected"
        case .on: return "Selected"
        case .mixed: return "Mixed"
        }
    }
}

private final class FluentMenuSeparatorView: NSView {
    private var theme: FluentTheme

    init(theme: FluentTheme) {
        self.theme = theme
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.divider.setFill()
        NSRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: 1).fill()
    }
}

/// Adds a custom Fluent contextual flyout without replacing the wrapped declarative content.
public struct FluentContextMenuView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let items: [FluentMenuItem]

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentContextMenuHost(
            content: content._mount(in: context),
            items: items,
            theme: context.theme,
            reduceMotion: context.reduceMotion
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentContextMenuHost else { return false }
        host.items = items
        host.theme = context.theme
        host.reduceMotion = context.reduceMotion
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentContextMenuHost: NSView {
    var items: [FluentMenuItem]
    var theme: FluentTheme
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var flyout: FluentMenuFlyout?
    private var rightClickMonitor: Any?
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    init(content: NSView, items: [FluentMenuItem], theme: FluentTheme, reduceMotion: Bool) {
        self.items = items
        self.theme = theme
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeRightClickMonitor()
        guard window != nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                return event
            }
            self.presentMenu(at: self.convert(event.locationInWindow, from: nil))
            return nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown?, .rightMouseUp?, .rightMouseDragged?:
            let localPoint = superview.map { convert(point, from: $0) } ?? point
            return bounds.contains(localPoint) ? self : nil
        default:
            return super.hitTest(point)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        presentMenu(at: convert(event.locationInWindow, from: nil))
    }

    private func presentMenu(at point: NSPoint) {
        guard !items.isEmpty else { return }
        let flyout = FluentMenuFlyout(
            items: items,
            theme: theme,
            matchesAnchorWidth: false,
            reduceMotion: reduceMotion
        )
        self.flyout = flyout
        flyout.present(relativeTo: self, at: point)
    }

    private func removeRightClickMonitor() {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        rightClickMonitor = nil
    }

    deinit { removeRightClickMonitor() }

}

public extension FluentView {
    func contextMenu(@FluentMenuBuilder items: () -> [FluentMenuItem]) -> FluentContextMenuView<Self> {
        FluentContextMenuView(content: self, items: items())
    }
}
