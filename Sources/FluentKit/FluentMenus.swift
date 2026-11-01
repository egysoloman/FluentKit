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
    /// Stable identity within a menu level. Omitted IDs retain rows by position during updates.
    public let id: AnyHashable?
    public let title: String
    public let systemImageName: String?
    public let icon: FluentIconSource?
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
        id: AnyHashable? = nil,
        _ title: String,
        systemImageName: String? = nil,
        icon: FluentIconSource? = nil,
        isEnabled: Bool = true,
        state: FluentMenuItemState = .off,
        selectionIndicator: FluentMenuSelectionIndicator = .checkmark,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        submenu: [FluentMenuItem] = [],
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImageName = systemImageName
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.isEnabled = isEnabled
        self.state = state
        self.selectionIndicator = selectionIndicator
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.submenu = submenu
        self.action = action
        self.isSeparator = false
    }

    private init(separator: Void, id: AnyHashable? = nil) {
        self.id = id
        title = ""
        systemImageName = nil
        icon = nil
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

    public static func separator(id: AnyHashable) -> FluentMenuItem { FluentMenuItem(separator: (), id: id) }

    public static func submenu(
        id: AnyHashable? = nil,
        _ title: String,
        systemImageName: String? = nil,
        icon: FluentIconSource? = nil,
        isEnabled: Bool = true,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) -> FluentMenuItem {
        FluentMenuItem(
            id: id, title,
            systemImageName: systemImageName,
            icon: icon,
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
    public static func buildExpression(_ item: FluentMenuItem) -> [FluentMenuItem] { [item] }
    public static func buildExpression(_ items: [FluentMenuItem]) -> [FluentMenuItem] { items }
    public static func buildBlock(_ components: [FluentMenuItem]...) -> [FluentMenuItem] { components.flatMap { $0 } }
    @_disfavoredOverload
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
        menuItem.image = item.icon?.image(pointSize: 13)
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
    private var items: [FluentMenuItem]
    private var theme: FluentTheme
    private let minimumWidth: CGFloat
    private let matchesAnchorWidth: Bool
    private var reduceMotion: Bool
    private weak var owner: FluentMenuFlyout?
    private var panel: FluentMenuPanel?
    private var presenter: FluentMenuPresenterView?
    private weak var viewport: FluentMenuViewport?
    private var childFlyout: FluentMenuFlyout?
    private var childIndex: Int?
    private var pendingSubmenuWorkItem: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var anchorObserver: FluentPopupAnchorObserver?
    private weak var parentWindow: NSWindow?
    private weak var anchorView: NSView?
    private var anchorPoint: NSPoint?
    private var placement: FluentMenuPlacement = .automatic
    private weak var transitionHost: FluentPopupTransitionHost?
    private weak var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    private var layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
    private var presentationRevision: UInt = 0
    /// `FlyoutBase::m_inputDeviceTypeUsedToOpen`, captured when the root menu opens.
    private(set) var inputDeviceTypeUsedToOpen: FluentInputDeviceType = .none

    /// Called after the root presenter has been removed from its panel.
    /// Button-like controls use this to clear their open visual state.
    public var onDismiss: (() -> Void)?
    /// MenuBar installs this on a root flyout so physical Left/Right can move between top-level
    /// items. Ordinary MenuFlyout instances leave it nil and retain submenu close/open behavior.
    var onRootHorizontalNavigation: ((Int) -> Void)?

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

    /// `MenuFlyoutItemBase`: NarrowPadding (11,4,11,5) when opened with mouse, pen or keyboard; the
    /// default padding (11,8,11,9) otherwise, including touch. A desktop open with no recorded
    /// device keeps the narrow rows. Submenus inherit the root's choice.
    var usesNarrowPadding: Bool {
        if let owner { return owner.usesNarrowPadding }
        return inputDeviceTypeUsedToOpen != .touch
    }

    var itemHeight: CGFloat { usesNarrowPadding ? FluentMenuPresenterView.narrowItemHeight : FluentMenuPresenterView.touchItemHeight }

    public func present(
        relativeTo anchor: NSView,
        at point: NSPoint? = nil,
        placement: FluentMenuPlacement = .automatic
    ) {
        guard owner == nil else {
            owner?.present(relativeTo: anchor, at: point, placement: placement)
            return
        }
        presentationRevision &+= 1
        let revision = presentationRevision
        dismissBranch(animated: false)
        // onDismiss may have opened a replacement or explicitly cancelled this request.
        guard presentationRevision == revision else { return }
        guard !items.isEmpty, let anchorWindow = anchor.window else { return }
        inputDeviceTypeUsedToOpen = FluentInputDeviceTracker.shared.deviceTypeForCurrentInteraction(in: anchorWindow)
        anchorView = anchor
        anchorPoint = point
        self.placement = placement
        registerAppearanceUpdates(from: anchorWindow)
        layoutDirection = anchor.userInterfaceLayoutDirection
        presentAnchoredPanel(focusFirstItem: inputDeviceTypeUsedToOpen == .keyboard)
    }

    /// Update a live menu without reopening its panel or replacing retained rows/submenus.
    /// Supply unique item IDs within each level when inserting or reordering menu items.
    public func update(items: [FluentMenuItem], theme: FluentTheme? = nil, reduceMotion: Bool? = nil) {
        let childRow = childIndex.flatMap { presenter?.row(at: $0) }
        self.items = items
        if let theme { self.theme = theme }
        if let reduceMotion { self.reduceMotion = reduceMotion }
        guard let panel, let presenter else { return }
        guard !items.isEmpty, let anchor = anchorView, anchor.window === parentWindow else {
            dismissBranch(animated: false)
            return
        }
        layoutDirection = owner?.layoutDirection ?? anchor.userInterfaceLayoutDirection
        presenter.update(items: items, theme: self.theme, layoutDirection: layoutDirection,
                         minimumWidth: resolvedMinimumWidth(for: anchor))
        panel.appearance = fluentAppKitAppearance(for: self.theme)
        transitionHost?.update(theme: self.theme)
        positionPanel()
        if let childRow, let index = presenter.index(of: childRow), items[index].isEnabled, items[index].hasSubmenu {
            childIndex = index
            childFlyout?.update(items: items[index].submenu, theme: self.theme, reduceMotion: self.reduceMotion)
        } else if childFlyout != nil {
            let wasKey = childFlyout?.containsKeyWindow == true
            closeChild()
            panel.makeFirstResponder(presenter)
            if wasKey { panel.makeKey() }
        }
    }

    /// Follow the anchor when MenuBar items move or their FlowDirection changes.
    func reposition(placement: FluentMenuPlacement? = nil) {
        if let placement { self.placement = placement }
        guard panel != nil, let anchor = anchorView, anchor.window === parentWindow else {
            if panel != nil { dismissBranch(animated: false) }
            return
        }
        let direction = owner?.layoutDirection ?? anchor.userInterfaceLayoutDirection
        layoutDirection = direction
        presenter?.updateLayout(layoutDirection: direction, minimumWidth: resolvedMinimumWidth(for: anchor))
        positionPanel()
        childFlyout?.reposition()
    }

    private var containsKeyWindow: Bool { panel?.isKeyWindow == true || childFlyout?.containsKeyWindow == true }

    private func resolvedMinimumWidth(for anchor: NSView) -> CGFloat {
        matchesAnchorWidth ? max(minimumWidth, anchor.bounds.width) : minimumWidth
    }

    private func presentationLayout(anchor: NSView, preferredSize: NSSize) -> (point: NSPoint, size: NSSize, edge: FluentPopupRevealEdge)? {
        guard let anchorWindow = anchor.window else { return nil }
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let rtl = layoutDirection == .rightToLeft
        let targetPoint: NSPoint
        if owner != nil {
            targetPoint = NSPoint(x: rtl ? anchorRect.minX - 2 : anchorRect.maxX + 2, y: anchorRect.maxY)
        } else if placement == .automatic, let point = anchorPoint {
            targetPoint = anchorWindow.convertPoint(toScreen: anchor.convert(point, to: nil))
        } else {
            targetPoint = FluentScreenPlacement.topLeading(of: anchorRect, rightToLeft: rtl)
        }
        let visibleFrame = FluentScreenPlacement.visibleFrame(at: targetPoint, fallback: anchorWindow)
        // FlyoutBase caps the presenter at the available monitor bounds. As in
        // FrameworkElement::GetMinMax, an explicit minimum still wins over the maximum.
        let size = NSSize(width: max(resolvedMinimumWidth(for: anchor), min(preferredSize.width, max(1, visibleFrame.width - 8))),
                          height: min(preferredSize.height, max(1, visibleFrame.height - 8)))
        var origin: NSPoint
        if owner != nil {
            origin = NSPoint(x: rtl ? anchorRect.minX - size.width - 2 : anchorRect.maxX + 2,
                             y: anchorRect.maxY - size.height + 2)
            if origin.x < visibleFrame.minX + 4 || origin.x > visibleFrame.maxX - size.width - 4 {
                origin.x = rtl ? anchorRect.maxX + 2 : anchorRect.minX - size.width - 2
            }
        } else if placement == .comboBoxSelection {
            origin = NSPoint(x: rtl ? anchorRect.maxX - size.width : anchorRect.minX,
                             y: anchorRect.midY - size.height + min(size.height, max(0, selectedRowCenterFromTop() ?? size.height / 2)))
        } else if placement == .automatic, let point = anchorPoint {
            let screenPoint = anchorWindow.convertPoint(toScreen: anchor.convert(point, to: nil))
            origin = NSPoint(x: screenPoint.x - (rtl ? size.width : 0), y: screenPoint.y - size.height)
            if origin.y < visibleFrame.minY { origin.y = anchorRect.maxY }
        } else {
            origin = belowOrigin(anchorRect: anchorRect, size: size, visibleFrame: visibleFrame, rightToLeft: rtl)
        }
        let final = clamped(origin, size: size, visibleFrame: visibleFrame)
        return (final, size, final.y + size.height / 2 <= anchorRect.midY ? .top : .bottom)
    }

    private func presentAnchoredPanel(focusFirstItem: Bool = false) {
        guard let anchor = anchorView, let window = anchor.window else { return }
        let minimum = resolvedMinimumWidth(for: anchor)
        let size = FluentMenuPresenterView.preferredSize(for: items, theme: theme, minimumWidth: minimum, itemHeight: itemHeight)
        guard let origin = presentationLayout(anchor: anchor, preferredSize: size) else { return }
        presentPanel(in: window, origin: origin.point, size: origin.size, direction: layoutDirection,
                     presenterMinimumWidth: minimum, revealEdge: origin.edge, focusFirstItem: focusFirstItem)
    }

    private func positionPanel() {
        guard let panel, let presenter, let viewport, let host = transitionHost, let anchor = anchorView,
              let geometry = presentationLayout(anchor: anchor, preferredSize: presenter.preferredSize) else { return }
        let size = geometry.size
        viewport.setFrameSize(size)
        viewport.needsLayout = true
        viewport.layoutSubtreeIfNeeded()
        presenter.revealKeyboardSelection()
        // Selection-centered placement uses the selected row's viewport coordinate.
        guard let origin = presentationLayout(anchor: anchor, preferredSize: presenter.preferredSize) else { return }
        let resized = host.bounds.size != size
        let frame = NSRect(origin: origin.point, size: size)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        host.layoutSubtreeIfNeeded()
        if resized { host.settlePresentation() }
        presenter.layoutSubtreeIfNeeded()
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
                return top + itemHeight / 2 - (viewport?.scrollOffset ?? 0)
            }
            top += item.isSeparator ? 9 : itemHeight
        }
        return nil
    }

    public func dismiss(animated: Bool = true) {
        if let owner {
            owner.root.dismiss(animated: animated)
        } else {
            presentationRevision &+= 1
            dismissBranch(animated: animated)
        }
    }

    private var root: FluentMenuFlyout { owner?.root ?? self }

    private func presentSubmenu(relativeTo anchor: NSView, keyboard: Bool) {
        guard anchor.window != nil else { return }
        dismissBranch(animated: false)
        anchorView = anchor
        layoutDirection = owner?.layoutDirection ?? anchor.userInterfaceLayoutDirection
        presentAnchoredPanel(focusFirstItem: keyboard)
    }

    private func presentPanel(
        in anchorWindow: NSWindow,
        origin: NSPoint,
        size: NSSize,
        direction: NSUserInterfaceLayoutDirection,
        presenterMinimumWidth: CGFloat,
        revealEdge: FluentPopupRevealEdge,
        focusFirstItem: Bool
    ) {
        let presenter = FluentMenuPresenterView(
            items: items,
            theme: theme,
            layoutDirection: direction,
            minimumWidth: presenterMinimumWidth,
            itemHeight: itemHeight
        )
        let viewport = FluentMenuViewport(presenter: presenter)
        viewport.frame = NSRect(origin: .zero, size: size)
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

        // One shared popup surface owns the fill and edge; the theme-level material switch
        // replaces it with an opaque fallback without changing popup geometry.
        let transitionHost = FluentPopupTransitionHost(
            content: viewport,
            theme: theme,
            cornerRadius: theme.designTokens.cardCornerRadius,
            name: "FluentKit.MenuFlyout"
        )
        transitionHost.frame = NSRect(origin: .zero, size: size)
        transitionHost.autoresizingMask = [.width, .height]
        panel.contentView = transitionHost

        presenter.onDismiss = { [weak self, weak presenter] in
            guard let self, let presenter, self.presenter === presenter else { return }
            self.root.dismiss()
        }
        presenter.onEscape = { [weak self] in self?.closeFromKeyboard(dismissRoot: true) }
        presenter.onSelection = { [weak self] index, row, keyboard in
            guard let self else { return }
            if keyboard {
                self.pendingSubmenuWorkItem?.cancel()
                self.pendingSubmenuWorkItem = nil
                if self.childIndex != index { self.closeChild() }
            } else { self.scheduleSubmenu(index: index, row: row) }
        }
        presenter.onSubmenu = { [weak self] index, row, keyboard in self?.openSubmenu(index: index, row: row, keyboard: keyboard) }
        presenter.onCloseSubmenu = { [weak self] in self?.closeFromKeyboard() }
        presenter.onRootHorizontalNavigation = owner == nil ? onRootHorizontalNavigation : nil
        parentWindow = anchorWindow
        anchorWindow.addChildWindow(panel, ordered: .above)
        self.panel = panel
        self.presenter = presenter
        self.viewport = viewport
        self.transitionHost = transitionHost
        viewport.onScroll = { [weak self, weak viewport] in
            guard let self, self.viewport === viewport else { return }
            self.viewportDidScroll()
        }
        panel.setFrameOrigin(origin)
        transitionHost.layoutSubtreeIfNeeded()
        viewport.layoutSubtreeIfNeeded()
        if placement == .comboBoxSelection { presenter.revealCheckedSelection() }
        positionPanel()
        if owner == nil {
            installOutsideClickMonitors()
            installLifecycleObservers(in: anchorWindow)
        }

        panel.alphaValue = 1
        prepareSurfaceEntrance(
            host: transitionHost,
            edge: revealEdge,
            motion: owner == nil ? FluentMotion.menuOpen : FluentMotion.submenuOpen
        )
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(presenter)
        if focusFirstItem { presenter.focusFirstItem() }
        if let anchor = anchorView {
            anchorObserver = FluentPopupAnchorObserver(anchor: anchor, onChange: { [weak self] in self?.reposition() },
                onUnavailable: { [weak self] in self?.closeFromKeyboard(dismissRoot: true) })
        }
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
            guard let self, let row, let presenter = self.presenter,
                  let current = presenter.index(of: row), presenter.selectedIndex == current else { return }
            self.openSubmenu(index: current, row: row, keyboard: false)
        }
        pendingSubmenuWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func openSubmenu(index: Int, row: FluentMenuItemRow, keyboard: Bool) {
        pendingSubmenuWorkItem?.cancel()
        pendingSubmenuWorkItem = nil
        guard row.window === panel, row.visibleRect.intersects(row.bounds),
              let item = presenter?.item(at: index), item.isEnabled, item.hasSubmenu else {
            closeChild()
            return
        }
        if childIndex == index, let child = childFlyout, child.isPresented {
            if keyboard {
                child.panel?.makeKeyAndOrderFront(nil)
                if let presenter = child.presenter {
                    child.panel?.makeFirstResponder(presenter)
                    presenter.focusFirstItem()
                }
            }
            return
        }
        closeChild()
        let child = FluentMenuFlyout(items: item.submenu, theme: theme, owner: self)
        childIndex = index
        childFlyout = child
        child.presentSubmenu(relativeTo: row, keyboard: keyboard)
    }

    private func closeChild(cancelPending: Bool = true) {
        if cancelPending {
            pendingSubmenuWorkItem?.cancel()
            pendingSubmenuWorkItem = nil
        }
        childFlyout?.dismissBranch(animated: false)
        childFlyout = nil
        childIndex = nil
    }

    private func viewportDidScroll() {
        presenter?.refreshPointerAfterScrolling()
        guard let child = childFlyout, let anchor = child.anchorView else { return }
        if anchor.window !== panel || !anchor.visibleRect.intersects(anchor.bounds) {
            let wasKey = child.containsKeyWindow
            closeChild(cancelPending: false)
            if let presenter { panel?.makeFirstResponder(presenter) }
            if wasKey { panel?.makeKey() }
        } else {
            child.reposition()
        }
    }

    private func closeFromKeyboard(dismissRoot: Bool = false) {
        if let owner {
            guard owner.childFlyout === self else { return }
            let index = owner.childIndex
            owner.closeChild()
            owner.presenter?.window?.makeKeyAndOrderFront(nil)
            if let presenter = owner.presenter { owner.presenter?.window?.makeFirstResponder(presenter) }
            if let index { owner.presenter?.focusItem(at: index) }
        } else if dismissRoot {
            dismissBranch(animated: false)
        }
    }

    private func dismissBranch(animated _: Bool) {
        anchorObserver?.invalidate()
        anchorObserver = nil
        pendingSubmenuWorkItem?.cancel()
        pendingSubmenuWorkItem = nil
        childFlyout?.dismissBranch(animated: false)
        childFlyout = nil
        childIndex = nil
        presenter?.deactivate()
        viewport?.onScroll = nil
        viewport = nil
        if owner == nil {
            removeOutsideClickMonitors()
            removeLifecycleObservers()
        }
        guard let popupPanel = panel else { return }
        panel = nil
        presenter = nil
        transitionHost = nil
        anchorView = nil
        if owner == nil { unregisterAppearanceUpdates() }
        popupPanel.parent?.removeChildWindow(popupPanel)
        popupPanel.orderOut(nil)
        // MenuFlyout unload is intentionally immediate in FluentKit. Only entrance motion is
        // retained; removing this branch unloads its complete presenter in one transaction.
        // Escape in a nested presenter closes that branch and returns to its parent.
        onDismiss?()
    }

    private func installLifecycleObservers(in window: NSWindow) {
        removeLifecycleObservers()
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            lifecycleObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.reposition()
            })
        }
        lifecycleObservers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() })
        lifecycleObservers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.dismiss(animated: false)
        })
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.dismiss(animated: false)
        })
    }

    private func removeLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
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
        update(items: items, theme: theme)
    }

    private func prepareForAppearanceChange() {
        transitionHost?.settleForAppearanceChange()
        childFlyout?.prepareForAppearanceChange()
    }

    deinit {
        anchorObserver?.invalidate()
        removeLifecycleObservers()
        removeOutsideClickMonitors()
        unregisterAppearanceUpdates()
        childFlyout?.dismissBranch(animated: false)
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
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

/// WinUI MenuFlyoutPresenter's vertical ScrollViewer keeps the complete menu document.
private final class FluentMenuViewport: NSView {
    let scrollView = FluentViewportScrollView()
    private let presenter: FluentMenuPresenterView
    var onScroll: (() -> Void)?
    var scrollOffset: CGFloat { scrollView.contentView.bounds.minY }
    private var boundsObserver: NSObjectProtocol?
    private var scrollNotificationPending = false

    override var isFlipped: Bool { true }

    init(presenter: FluentMenuPresenterView) {
        self.presenter = presenter
        super.init(frame: .zero)
        setAccessibilityElement(false)
        scrollView.setAccessibilityElement(false)
        scrollView.contentView.setAccessibilityElement(false)
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = presenter
        addSubview(scrollView)
        scrollView.onViewportSizeChange = { [weak self] in self?.needsLayout = true }
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in self?.scheduleScrollNotification() }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        scrollView.userInterfaceLayoutDirection = presenter.userInterfaceLayoutDirection
        scrollView.hasVerticalScroller = presenter.preferredSize.height > bounds.height
        scrollView.tile()
        presenter.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width,
                                 height: max(scrollView.contentSize.height, presenter.preferredSize.height))
        presenter.layoutSubtreeIfNeeded()
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scheduleScrollNotification() {
        guard !scrollNotificationPending else { return }
        scrollNotificationPending = true
        // Bounds can change in the middle of a retained-row update; inspect anchors only
        // after the new row frames and viewport have settled.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollNotificationPending = false
            self.layoutSubtreeIfNeeded()
            self.onScroll?()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }
}

private final class FluentMenuPresenterView: NSView {
    private(set) var preferredSize = NSSize.zero
    var onDismiss: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSelection: ((Int, FluentMenuItemRow, Bool) -> Void)?
    var onSubmenu: ((Int, FluentMenuItemRow, Bool) -> Void)?
    var onCloseSubmenu: (() -> Void)?
    var onRootHorizontalNavigation: ((Int) -> Void)?

    private enum Identity: Hashable {
        case explicit(AnyHashable, occurrence: Int)
        case position(Int)
    }
    private var items: [FluentMenuItem] = []
    private var identities: [Identity] = []
    private var orderedViews: [NSView] = []
    private var theme: FluentTheme
    private var layoutDirection: NSUserInterfaceLayoutDirection
    private var minimumWidth: CGFloat
    static let narrowItemHeight: CGFloat = 36
    static let touchItemHeight: CGFloat = 44
    let itemHeight: CGFloat
    private var itemRows: [Int: FluentMenuItemRow] = [:]
    private var typeahead = ""
    private var typeaheadResetWorkItem: DispatchWorkItem?
    private(set) var selectedIndex: Int?
    private var showsKeyboardSelection = false
    private var acceptsCommands = true
    private let hoverCoordinator = FluentHoverCoordinator<FluentMenuItemRow> { row, hovering in
        row.setPointerOver(hovering)
    }
    private var windowObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(items: [FluentMenuItem], theme: FluentTheme, layoutDirection: NSUserInterfaceLayoutDirection,
         minimumWidth: CGFloat, itemHeight: CGFloat = FluentMenuPresenterView.narrowItemHeight) {
        self.theme = theme
        self.layoutDirection = layoutDirection
        self.minimumWidth = minimumWidth
        self.itemHeight = itemHeight
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        update(items: items, theme: theme, layoutDirection: layoutDirection, minimumWidth: minimumWidth)
        setFrameSize(preferredSize)
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard notification.object as? NSWindow === self?.window else { return }
            self?.resetPointerState()
        }
    }

    func update(items nextItems: [FluentMenuItem], theme: FluentTheme,
                layoutDirection: NSUserInterfaceLayoutDirection, minimumWidth: CGFloat) {
        let previousIndex = selectedIndex
        let selectedRow = previousIndex.flatMap { itemRows[$0] }
        var candidates = Dictionary(uniqueKeysWithValues: zip(identities, orderedViews))
        let previousRows = itemRows
        var occurrences: [AnyHashable: Int] = [:]
        identities = nextItems.enumerated().map { index, item in
            guard let id = item.id else { return .position(index) }
            let count = occurrences[id, default: 0]
            occurrences[id] = count + 1
            return .explicit(id, occurrence: count)
        }
        items = nextItems
        self.theme = theme
        self.layoutDirection = layoutDirection
        self.minimumWidth = minimumWidth
        userInterfaceLayoutDirection = layoutDirection
        preferredSize = Self.preferredSize(for: items, theme: theme, minimumWidth: minimumWidth, itemHeight: itemHeight)
        let checkSlot = items.contains { !$0.isSeparator && $0.reservesCheckSlot }
        let iconSlot = items.contains { !$0.isSeparator && $0.icon != nil }
        itemRows = [:]
        orderedViews = items.enumerated().map { index, item in
            let candidate = candidates.removeValue(forKey: identities[index])
            let view: NSView
            if item.isSeparator {
                let separator = (candidate as? FluentMenuSeparatorView) ?? FluentMenuSeparatorView(theme: theme)
                separator.update(theme: theme)
                view = separator
            } else {
                let row = (candidate as? FluentMenuItemRow) ?? FluentMenuItemRow(
                    item: item, theme: theme, accelerator: Self.accelerator(for: item), layoutDirection: layoutDirection,
                    showsCheckPlaceholder: checkSlot, showsIconPlaceholder: iconSlot)
                row.update(item: item, theme: theme, accelerator: Self.accelerator(for: item), layoutDirection: layoutDirection,
                    showsCheckPlaceholder: checkSlot, showsIconPlaceholder: iconSlot)
                row.onHoverChange = { [weak self] row, hovering in self?.setHoveredRow(row, index: index, hovering: hovering) }
                row.onInvoke = { [weak self] keyboard in self?.invoke(index, keyboard: keyboard) }
                itemRows[index] = row
                view = row
            }
            if candidate !== view { candidate?.removeFromSuperview() }
            if view.superview !== self { addSubview(view) }
            return view
        }
        for view in candidates.values {
            (view as? FluentMenuItemRow)?.onInvoke = nil
            (view as? FluentMenuItemRow)?.onHoverChange = nil
            view.removeFromSuperview()
        }
        if let selectedRow, let index = index(of: selectedRow), items[index].isEnabled {
            selectedIndex = index
        } else {
            if selectedRow != nil { hoverCoordinator.reset(items: previousRows.values) }
            selectedIndex = showsKeyboardSelection && previousIndex != nil
                ? (enabledIndices.first { $0 >= previousIndex! } ?? enabledIndices.last) : nil
        }
        updateSelection()
        setAccessibilityChildren(orderedViews.filter { $0 is FluentMenuItemRow })
        needsLayout = true
        needsDisplay = true
    }

    func row(at index: Int) -> FluentMenuItemRow? { itemRows[index] }
    func index(of row: FluentMenuItemRow) -> Int? { itemRows.first { $0.value === row }?.key }

    func updateLayout(layoutDirection: NSUserInterfaceLayoutDirection, minimumWidth: CGFloat) {
        guard self.layoutDirection != layoutDirection || self.minimumWidth != minimumWidth else { return }
        update(items: items, theme: theme, layoutDirection: layoutDirection, minimumWidth: minimumWidth)
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 2
        for view in orderedViews {
            if view is FluentMenuSeparatorView {
                view.frame = NSRect(x: 8, y: y, width: max(0, bounds.width - 16), height: 9)
                y += 9
            } else {
                view.frame = NSRect(x: 4, y: y + 2, width: max(0, bounds.width - 8), height: itemHeight - 4)
                y += itemHeight
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func deactivate() {
        acceptsCommands = false
        typeaheadResetWorkItem?.cancel()
        resetPointerState()
        onDismiss = nil
        onEscape = nil
        onSelection = nil
        onSubmenu = nil
        onCloseSubmenu = nil
        onRootHorizontalNavigation = nil
        for row in itemRows.values {
            row.onInvoke = nil
            row.onHoverChange = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard acceptsCommands else { return }
        switch event.keyCode {
        case 53: onEscape?()
        case 125: moveSelection(by: 1)
        case 126: moveSelection(by: -1)
        case 36, 49:
            if let selectedIndex { invoke(selectedIndex, keyboard: true) }
        case 48: break // Menu navigation retains focus on Tab, as MenuFlyoutPresenter does.
        case 124: handleHorizontalNavigation(physicalOffset: 1)
        case 123: handleHorizontalNavigation(physicalOffset: -1)
        case 115:
            if let first = enabledIndices.first { select(first, announce: true, keyboard: true) }
        case 119:
            if let last = enabledIndices.last { select(last, announce: true, keyboard: true) }
        default: super.keyDown(with: event)
        }
        if ![53, 125, 126, 36, 49, 48, 124, 123, 115, 119].contains(event.keyCode) {
            handleTypeahead(event)
        }
    }

    private var enabledIndices: [Int] {
        items.indices.filter { !items[$0].isSeparator && items[$0].isEnabled }
    }

    private func handleHorizontalNavigation(physicalOffset: Int) {
        let opensSubmenu = layoutDirection == .rightToLeft
            ? physicalOffset < 0
            : physicalOffset > 0
        if opensSubmenu,
           let selectedIndex,
           let row = itemRows[selectedIndex],
           items[selectedIndex].hasSubmenu {
            onSubmenu?(selectedIndex, row, true)
            return
        }
        if let onRootHorizontalNavigation {
            onRootHorizontalNavigation(physicalOffset)
        } else if !opensSubmenu {
            onCloseSubmenu?()
        }
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
        hoverCoordinator.reset(items: itemRows.values)
        updateSelection()
        revealKeyboardSelection()
        if let selectedIndex, let row = itemRows[selectedIndex] {
            onSelection?(selectedIndex, row, true)
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
        revealKeyboardSelection()
        if let row = itemRows[index] {
            onSelection?(index, row, keyboard)
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

    func revealKeyboardSelection() {
        guard showsKeyboardSelection, let index = selectedIndex, let row = itemRows[index] else { return }
        scrollToVisible(row.frame)
    }

    func revealCheckedSelection() {
        guard let index = items.firstIndex(where: { !$0.isSeparator && $0.isEnabled && $0.state == .on }) ?? enabledIndices.first,
              let row = itemRows[index] else { return }
        scrollToVisible(row.frame)
    }

    func refreshPointerAfterScrolling() {
        resetPointerState()
        // Programmatic scrolling must not replace keyboard focus with a stationary cursor.
        guard !showsKeyboardSelection, let window, window.isVisible, window.isKeyWindow else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point), let (index, row) = itemRows.first(where: { $0.value.frame.contains(point) }) else { return }
        setHoveredRow(row, index: index, hovering: true)
    }

    func update(theme: FluentTheme) {
        update(items: items, theme: theme, layoutDirection: layoutDirection, minimumWidth: minimumWidth)
    }

    private func invoke(_ index: Int, keyboard: Bool) {
        guard acceptsCommands, items.indices.contains(index), items[index].isEnabled else { return }
        if items[index].hasSubmenu, let row = itemRows[index] {
            onSubmenu?(index, row, keyboard)
            return
        }
        items[index].action()
        // Invoking an item can replace the root. Its retired presenter has no authority
        // to close the application's newly opened menu after the callback returns.
        guard acceptsCommands else { return }
        onDismiss?()
    }

    func item(at index: Int) -> FluentMenuItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    func focusFirstItem() {
        if let first = enabledIndices.first { select(first, announce: false, keyboard: true) }
    }

    func focusItem(at index: Int) { select(index, announce: true, keyboard: true) }

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

    static func preferredSize(for items: [FluentMenuItem], theme: FluentTheme, minimumWidth: CGFloat,
                              itemHeight: CGFloat = narrowItemHeight) -> NSSize {
        let font = theme.typography.font(for: .body)
        let placeholderCount = (items.contains { !$0.isSeparator && $0.reservesCheckSlot } ? 1 : 0)
            + (items.contains { !$0.isSeparator && $0.icon != nil } ? 1 : 0)
        let widest = items.filter { !$0.isSeparator }.reduce(CGFloat(0)) { result, item in
            let titleWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
            let keyWidth = (Self.accelerator(for: item) as NSString).size(withAttributes: [.font: font]).width
            let trailingWidth = (!item.keyEquivalent.isEmpty ? keyWidth + 24 : 0)
                + (item.hasSubmenu ? 36 : 0)
            return max(result, titleWidth + CGFloat(placeholderCount * 28) + trailingWidth)
        }
        let height = 4 + items.reduce(CGFloat(0)) { $0 + ($1.isSeparator ? 9 : itemHeight) }
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
    var onInvoke: ((Bool) -> Void)?

    private var item: FluentMenuItem
    private var theme: FluentTheme
    private var accelerator: String
    private var layoutDirection: NSUserInterfaceLayoutDirection
    private var showsCheckPlaceholder: Bool
    private var showsIconPlaceholder: Bool
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
        iconView.identifier = NSUserInterfaceItemIdentifier("FluentKit.Menu.Item.Icon")
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        selectionPillLayer.name = "FluentKit.ComboBoxItem.SelectionPill"
        selectionPillLayer.cornerRadius = 1.5
        update(item: item, theme: theme, accelerator: accelerator, layoutDirection: layoutDirection,
               showsCheckPlaceholder: showsCheckPlaceholder, showsIconPlaceholder: showsIconPlaceholder)
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
            if self.window != nil, self.item.isEnabled { self.onInvoke?(false) }
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

    func update(item: FluentMenuItem, theme: FluentTheme, accelerator: String,
                layoutDirection: NSUserInterfaceLayoutDirection,
                showsCheckPlaceholder: Bool, showsIconPlaceholder: Bool) {
        self.item = item
        self.theme = theme
        self.accelerator = accelerator
        self.layoutDirection = layoutDirection
        self.showsCheckPlaceholder = showsCheckPlaceholder
        self.showsIconPlaceholder = showsIconPlaceholder
        userInterfaceLayoutDirection = layoutDirection
        isEnabled = item.isEnabled
        setAccessibilityTitle(item.title)
        setAccessibilityEnabled(item.isEnabled)
        setAccessibilityValue(item.hasSubmenu ? "Submenu" : accessibilityState)
        setAccessibilityHelp(item.hasSubmenu ? "Opens a submenu" : (accelerator.isEmpty ? nil : "Keyboard shortcut \(accelerator)"))
        if !item.isEnabled { resetPointerState() }
        if showsIconPlaceholder, let icon = item.icon {
            iconView.image = icon.image(pointSize: 13, color: item.isEnabled ? theme.textPrimary : theme.textDisabled,
                                        layoutDirection: layoutDirection)
            if iconView.superview == nil { addSubview(iconView) }
        } else { iconView.removeFromSuperview() }
        if item.state == .on, item.selectionIndicator == .pill {
            if selectionPillLayer.superlayer == nil { layer?.addSublayer(selectionPillLayer) }
            selectionPillLayer.backgroundColor = theme.accentFillDefault.cgColor
        } else { selectionPillLayer.removeFromSuperlayer() }
        needsLayout = true
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard item.isEnabled else { return false }
        onInvoke?(true)
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
        iconView.contentTintColor = item.icon?.tint == .original ? nil : foreground
        iconView.image = item.icon?.image(pointSize: 13, color: foreground, layoutDirection: userInterfaceLayoutDirection)
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
        paragraph.lineBreakMode = .byClipping
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
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        host.updateMenu()
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
        flyout?.dismiss(animated: false)
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

    func updateMenu() {
        flyout?.update(items: items, theme: theme, reduceMotion: reduceMotion)
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

/// Test access to the presenter's source-derived size for a given row pitch.
enum FluentMenuPresenterViewProbe {
    static func size(items: [FluentMenuItem], theme: FluentTheme = .current, minimumWidth: CGFloat = 180, itemHeight: CGFloat) -> NSSize {
        FluentMenuPresenterView.preferredSize(for: items, theme: theme, minimumWidth: minimumWidth, itemHeight: itemHeight)
    }
}
