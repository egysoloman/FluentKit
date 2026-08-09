import AppKit

/// Stable identity for one browser-style window containing a `FluentTabView` tab collection.
public struct FluentWindowTabGroupID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}

/// A document-like tab whose identity and declarative state survive moves between windows.
public struct FluentWindowTab {
    public let id: AnyHashable
    public var title: String
    public var systemImageName: String?
    public var isClosable: Bool
    public var isEnabled: Bool
    public let content: FluentAnyView
    /// Return `false` to veto a close initiated by either the tab button or its containing window.
    public var shouldClose: (() -> Bool)?

    public init<ID: Hashable, Content: FluentView>(
        id: ID,
        title: String,
        systemImage: String? = nil,
        isClosable: Bool = true,
        isEnabled: Bool = true,
        shouldClose: (() -> Bool)? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.id = AnyHashable(id)
        self.title = title
        systemImageName = systemImage
        self.isClosable = isClosable
        self.isEnabled = isEnabled
        self.shouldClose = shouldClose
        self.content = FluentAnyView(content())
    }
}

/// Appearance and native-window policy for `FluentWindowTabCoordinator`.
public struct FluentWindowTabConfiguration {
    public var size: NSSize
    public var minimumSize: NSSize
    public var styleMask: NSWindow.StyleMask
    public var material: FluentMaterial?
    public var tabWidthMode: FluentTabViewWidthMode
    public var closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode
    public var windowControlsStyle: FluentWindowControlsStyle
    public var leadingTitleBarInset: CGFloat
    public var windowsLeadingTitleBarInset: CGFloat
    public var showsAddTabButton: Bool
    public var closesWindowWhenEmpty: Bool
    public var context: FluentRenderContext

    public init(
        size: NSSize = NSSize(width: 900, height: 620),
        minimumSize: NSSize = NSSize(width: 560, height: 360),
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        material: FluentMaterial? = .mica,
        tabWidthMode: FluentTabViewWidthMode = .equal,
        closeButtonOverlayMode: FluentTabViewCloseButtonOverlayMode = .onPointerOver,
        windowControlsStyle: FluentWindowControlsStyle = .macOS,
        leadingTitleBarInset: CGFloat = 78,
        windowsLeadingTitleBarInset: CGFloat = 12,
        showsAddTabButton: Bool = true,
        closesWindowWhenEmpty: Bool = true,
        context: FluentRenderContext = .init()
    ) {
        self.size = size
        self.minimumSize = minimumSize
        self.styleMask = styleMask.union(.fullSizeContentView)
        self.material = material
        self.tabWidthMode = tabWidthMode
        self.closeButtonOverlayMode = closeButtonOverlayMode
        self.windowControlsStyle = windowControlsStyle
        self.leadingTitleBarInset = max(leadingTitleBarInset, 0)
        self.windowsLeadingTitleBarInset = max(windowsLeadingTitleBarInset, 0)
        self.showsAddTabButton = showsAddTabButton
        self.closesWindowWhenEmpty = closesWindowWhenEmpty
        self.context = context
    }
}

/// Owns a Windows/browser-style tab model while presenting each tab group in a native macOS
/// window. AppKit performs the drag session; this coordinator commits reorder, merge, and tear-out
/// as one stable-ID transaction.
public final class FluentWindowTabCoordinator: NSObject, NSWindowDelegate {
    public typealias AddTabHandler = (FluentWindowTabGroupID) -> FluentWindowTab?
    public typealias ContentWrapper = (FluentWindowTabGroupID, FluentAnyView) -> FluentAnyView
    public typealias WindowConfigurator = (NSWindow, FluentWindowTabGroupID) -> Void

    private final class GroupRecord {
        let id: FluentWindowTabGroupID
        var tabIDs: [AnyHashable]
        var selectedID: AnyHashable?
        var controller: NSWindowController?
        var appearanceCoordinator: FluentAppearanceCoordinator?
        var closesWithoutConsultingTabs = false

        init(id: FluentWindowTabGroupID, tabIDs: [AnyHashable], selectedID: AnyHashable?) {
            self.id = id
            self.tabIDs = tabIDs
            self.selectedID = selectedID
        }
    }

    public var onAddTabRequested: AddTabHandler?
    public var onGroupsChanged: (([FluentWindowTabGroupID]) -> Void)?

    private var configuration: FluentWindowTabConfiguration
    private let contentWrapper: ContentWrapper?
    private let configureWindow: WindowConfigurator?
    private let dragScopeIdentifier = "FluentKit.WindowTabs.\(UUID().uuidString)"
    private let revision = FluentObservable(0)
    private var tabsByID: [AnyHashable: FluentWindowTab] = [:]
    private var groupsByID: [FluentWindowTabGroupID: GroupRecord] = [:]
    private var orderedGroupIDs: [FluentWindowTabGroupID] = []

    public init(
        configuration: FluentWindowTabConfiguration = .init(),
        onAddTabRequested: AddTabHandler? = nil,
        contentWrapper: ContentWrapper? = nil,
        configureWindow: WindowConfigurator? = nil
    ) {
        self.configuration = configuration
        self.onAddTabRequested = onAddTabRequested
        self.contentWrapper = contentWrapper
        self.configureWindow = configureWindow
        super.init()
    }

    public var groupIDs: [FluentWindowTabGroupID] { orderedGroupIDs }

    /// Updates existing detached-tab windows and the seed theme used by subsequently created
    /// groups without rebuilding their tab models or native windows.
    public func updateTheme(_ theme: FluentTheme) {
        configuration.context.theme = theme
        orderedGroupIDs.forEach { groupID in
            groupsByID[groupID]?.appearanceCoordinator?.updateTheme(theme)
        }
    }

    public func window(for groupID: FluentWindowTabGroupID) -> NSWindow? {
        groupsByID[groupID]?.controller?.window
    }

    public func tabs(in groupID: FluentWindowTabGroupID) -> [FluentWindowTab] {
        guard let record = groupsByID[groupID] else { return [] }
        return record.tabIDs.compactMap { tabsByID[$0] }
    }

    public func group(containing tabID: AnyHashable) -> FluentWindowTabGroupID? {
        orderedGroupIDs.first { groupsByID[$0]?.tabIDs.contains(tabID) == true }
    }

    /// Opens a tab in an existing group or creates a new window when no group is supplied.
    @discardableResult
    public func open(
        _ tab: FluentWindowTab,
        in requestedGroupID: FluentWindowTabGroupID? = nil,
        at requestedIndex: Int? = nil,
        select: Bool = true
    ) -> FluentWindowTabGroupID {
        if let existingGroupID = group(containing: tab.id) {
            tabsByID[tab.id] = tab
            if select { self.select(tabID: tab.id) } else { publishChanges(focusing: nil) }
            return existingGroupID
        }
        tabsByID[tab.id] = tab

        if let requestedGroupID, let record = groupsByID[requestedGroupID] {
            let index = min(max(requestedIndex ?? record.tabIDs.count, 0), record.tabIDs.count)
            record.tabIDs.insert(tab.id, at: index)
            if select || record.selectedID == nil { record.selectedID = tab.id }
            publishChanges(focusing: select ? requestedGroupID : nil)
            return requestedGroupID
        }

        let groupID = FluentWindowTabGroupID()
        let record = GroupRecord(id: groupID, tabIDs: [tab.id], selectedID: tab.id)
        groupsByID[groupID] = record
        orderedGroupIDs.append(groupID)
        installWindow(for: record, matching: nil, detachedAt: nil, pointerOffset: .zero)
        publishChanges(focusing: groupID)
        return groupID
    }

    /// Updates a tab's metadata and content without changing its window membership.
    public func update(_ tab: FluentWindowTab) {
        guard tabsByID[tab.id] != nil else { return }
        tabsByID[tab.id] = tab
        publishChanges(focusing: nil)
    }

    public func select(tabID: AnyHashable) {
        guard let groupID = group(containing: tabID), let record = groupsByID[groupID] else { return }
        record.selectedID = tabID
        publishChanges(focusing: groupID)
    }

    public func close(tabID: AnyHashable) {
        guard let groupID = group(containing: tabID),
              let record = groupsByID[groupID],
              let index = record.tabIDs.firstIndex(of: tabID),
              let tab = tabsByID[tabID],
              tab.isClosable,
              tab.shouldClose?() != false else { return }

        record.tabIDs.remove(at: index)
        tabsByID.removeValue(forKey: tabID)
        if record.selectedID == tabID {
            record.selectedID = record.tabIDs.isEmpty
                ? nil
                : record.tabIDs[min(index, record.tabIDs.count - 1)]
        }
        if record.tabIDs.isEmpty, configuration.closesWindowWhenEmpty {
            closeEmptyGroup(record)
        }
        publishChanges(focusing: nil)
    }

    /// Moves a tab into another window. Returns false when either side disappeared mid-drag.
    @discardableResult
    public func move(
        tabID: AnyHashable,
        to destinationGroupID: FluentWindowTabGroupID,
        at requestedIndex: Int
    ) -> Bool {
        guard let sourceGroupID = group(containing: tabID),
              let source = groupsByID[sourceGroupID],
              let destination = groupsByID[destinationGroupID],
              let sourceIndex = source.tabIDs.firstIndex(of: tabID) else { return false }

        if sourceGroupID == destinationGroupID {
            let destinationIndex = min(max(requestedIndex, 0), max(source.tabIDs.count - 1, 0))
            guard sourceIndex != destinationIndex else { return true }
            source.tabIDs.remove(at: sourceIndex)
            source.tabIDs.insert(tabID, at: destinationIndex)
            source.selectedID = tabID
            publishChanges(focusing: destinationGroupID)
            return true
        }

        source.tabIDs.remove(at: sourceIndex)
        if source.selectedID == tabID {
            source.selectedID = source.tabIDs.isEmpty
                ? nil
                : source.tabIDs[min(sourceIndex, source.tabIDs.count - 1)]
        }
        let destinationIndex = min(max(requestedIndex, 0), destination.tabIDs.count)
        destination.tabIDs.insert(tabID, at: destinationIndex)
        destination.selectedID = tabID
        if source.tabIDs.isEmpty, configuration.closesWindowWhenEmpty {
            closeEmptyGroup(source)
        }
        publishChanges(focusing: destinationGroupID)
        return true
    }

    /// Tears a tab into a new native window, or repositions the existing window when it is already
    /// the group's last tab.
    @discardableResult
    public func detach(
        tabID: AnyHashable,
        at screenLocation: NSPoint,
        pointerOffset: NSPoint = .zero
    ) -> FluentWindowTabGroupID? {
        guard let sourceGroupID = group(containing: tabID),
              let source = groupsByID[sourceGroupID],
              let sourceIndex = source.tabIDs.firstIndex(of: tabID) else { return nil }

        if source.tabIDs.count == 1 {
            position(source.controller?.window, at: screenLocation, pointerOffset: pointerOffset)
            source.controller?.window?.makeKeyAndOrderFront(nil)
            return sourceGroupID
        }

        source.tabIDs.remove(at: sourceIndex)
        if source.selectedID == tabID {
            source.selectedID = source.tabIDs[min(sourceIndex, source.tabIDs.count - 1)]
        }

        let newGroupID = FluentWindowTabGroupID()
        let newRecord = GroupRecord(id: newGroupID, tabIDs: [tabID], selectedID: tabID)
        groupsByID[newGroupID] = newRecord
        orderedGroupIDs.append(newGroupID)
        installWindow(
            for: newRecord,
            matching: source.controller?.window,
            detachedAt: screenLocation,
            pointerOffset: pointerOffset
        )
        publishChanges(focusing: newGroupID)
        return newGroupID
    }

    public func close(groupID: FluentWindowTabGroupID) {
        groupsByID[groupID]?.controller?.window?.performClose(nil)
    }

    fileprivate func makeTabView(for groupID: FluentWindowTabGroupID) -> FluentAnyView {
        _ = revision.value
        guard let record = groupsByID[groupID] else { return FluentAnyView(FluentEmptyView()) }
        let tabs = record.tabIDs.compactMap { tabsByID[$0] }
        let items = tabs.map { tab in
            FluentTabItem(
                id: tab.id,
                title: tab.title,
                systemImage: tab.systemImageName,
                isClosable: tab.isClosable,
                isEnabled: tab.isEnabled
            ) { tab.content }
        }
        let selection = FluentBinding<Int>(
            get: { [weak self] in
                guard let self,
                      let current = self.groupsByID[groupID],
                      let selectedID = current.selectedID else { return -1 }
                return current.tabIDs.firstIndex(of: selectedID) ?? -1
            },
            set: { [weak self] index in self?.select(groupID: groupID, index: index) }
        )

        let tabView = FluentTabView(
            items: items,
            selectedIndex: selection,
            tabWidthMode: configuration.tabWidthMode,
            closeButtonOverlayMode: configuration.closeButtonOverlayMode,
            isAddTabButtonVisible: configuration.showsAddTabButton,
            canDragTabs: true,
            canReorderTabs: true,
            allowsDropTabs: true,
            dragScopeIdentifier: dragScopeIdentifier,
            dragContainerIdentifier: groupID.description,
            onAddTabButtonClick: { [weak self] in self?.requestAddTab(in: groupID) },
            onTabCloseRequested: { [weak self] index in self?.close(groupID: groupID, index: index) },
            onTabMoveRequested: { [weak self] from, to in self?.moveWithin(groupID: groupID, from: from, to: to) },
            onTabDropRequested: { [weak self] request in
                self?.move(tabID: request.tabID, to: groupID, at: request.destinationIndex) == true
            },
            onTabTearOutRequested: { [weak self] request in
                _ = self?.detach(
                    tabID: request.tabID,
                    at: request.screenLocation,
                    pointerOffset: request.pointerOffset
                )
            }
        )
        .tabStripHeader {
            FluentSpacer().frame(
                width: configuration.windowControlsStyle == .macOS
                    ? configuration.leadingTitleBarInset
                    : configuration.windowsLeadingTitleBarInset,
                height: 1
            )
        }
        .tabStripFooter {
            FluentSpacer().frame(
                width: configuration.windowControlsStyle.trailingTitleBarInset,
                height: 1
            )
        }
        return FluentAnyView(tabView)
    }

    private func requestAddTab(in groupID: FluentWindowTabGroupID) {
        guard let tab = onAddTabRequested?(groupID) else { return }
        _ = open(tab, in: groupID)
    }

    private func select(groupID: FluentWindowTabGroupID, index: Int) {
        guard let record = groupsByID[groupID], record.tabIDs.indices.contains(index) else { return }
        record.selectedID = record.tabIDs[index]
        publishChanges(focusing: nil)
    }

    private func close(groupID: FluentWindowTabGroupID, index: Int) {
        guard let record = groupsByID[groupID], record.tabIDs.indices.contains(index) else { return }
        close(tabID: record.tabIDs[index])
    }

    private func moveWithin(groupID: FluentWindowTabGroupID, from: Int, to: Int) {
        guard let record = groupsByID[groupID], record.tabIDs.indices.contains(from) else { return }
        _ = move(tabID: record.tabIDs[from], to: groupID, at: to)
    }

    private func installWindow(
        for record: GroupRecord,
        matching sourceWindow: NSWindow?,
        detachedAt screenLocation: NSPoint?,
        pointerOffset: NSPoint
    ) {
        var size = sourceWindow?.frame.size ?? configuration.size
        size.width = max(size.width, configuration.minimumSize.width)
        size.height = max(size.height, configuration.minimumSize.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = configuration.minimumSize
        window.minSize = configuration.minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.applyFluentWindowControlsStyle(configuration.windowControlsStyle)

        let groupView = FluentAnyView(FluentWindowTabGroupView(coordinator: self, groupID: record.id))
        let wrappedContent = contentWrapper?(record.id, groupView) ?? groupView
        let appearanceCoordinator = FluentAppearanceCoordinator(theme: configuration.context.theme)
        var context = configuration.context
        context.appearanceCoordinator = appearanceCoordinator
        let host = FluentViewHost(wrappedContent, context: context)
        host.autoresizingMask = [.width, .height]

        if let material = configuration.material {
            let materialView = FluentMaterialView(material: material)
            materialView.fluentTheme = context.theme
            materialView.isMaterialEnabled = context.theme.materialEffectsEnabled
            materialView.fallbackColor = context.theme.windowBackground
            materialView.frame = NSRect(origin: .zero, size: size)
            materialView.autoresizingMask = [.width, .height]
            materialView.addSubview(host)
            host.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
                host.topAnchor.constraint(equalTo: materialView.topAnchor),
                host.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
            ])
            window.contentView = materialView
            window.isOpaque = false
            window.backgroundColor = .clear
            appearanceCoordinator.attach(to: window, rootMaterialView: materialView)
        } else {
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            appearanceCoordinator.attach(to: window)
        }

        let controller = NSWindowController(window: window)
        record.controller = controller
        record.appearanceCoordinator = appearanceCoordinator
        configureWindow?(window, record.id)
        updateWindowTitle(record)

        if let screenLocation {
            position(window, at: screenLocation, pointerOffset: pointerOffset)
        } else {
            window.center()
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func position(_ window: NSWindow?, at screenLocation: NSPoint, pointerOffset: NSPoint) {
        guard let window else { return }
        let leadingInset = configuration.windowControlsStyle == .macOS
            ? configuration.leadingTitleBarInset
            : configuration.windowsLeadingTitleBarInset
        let proposedTopLeft = NSPoint(
            x: screenLocation.x - leadingInset - pointerOffset.x,
            y: screenLocation.y + 8 + pointerOffset.y
        )
        let screen = NSScreen.screens.first { $0.frame.contains(screenLocation) } ?? window.screen ?? NSScreen.main
        guard let screen else {
            window.setFrameTopLeftPoint(proposedTopLeft)
            return
        }
        var frame = window.frame
        frame.origin = NSPoint(x: proposedTopLeft.x, y: proposedTopLeft.y - frame.height)
        let visible = screen.visibleFrame
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    private func closeEmptyGroup(_ record: GroupRecord) {
        record.closesWithoutConsultingTabs = true
        record.controller?.window?.orderOut(nil)
        DispatchQueue.main.async { [weak self, weak record] in
            guard let self, let record, self.groupsByID[record.id] === record else { return }
            record.controller?.window?.close()
        }
    }

    private func publishChanges(focusing groupID: FluentWindowTabGroupID?) {
        orderedGroupIDs.forEach { id in
            if let record = groupsByID[id] { updateWindowTitle(record) }
        }
        revision.value += 1
        onGroupsChanged?(orderedGroupIDs)
        if let groupID {
            groupsByID[groupID]?.controller?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateWindowTitle(_ record: GroupRecord) {
        guard let window = record.controller?.window else { return }
        let selected = record.selectedID.flatMap { tabsByID[$0] }
        window.title = selected?.title ?? "FluentKit"
        window.representedURL = nil
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let record = record(for: sender) else { return true }
        if record.closesWithoutConsultingTabs { return true }
        return record.tabIDs.allSatisfy { tabsByID[$0]?.shouldClose?() != false }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let record = record(for: window) else { return }
        record.tabIDs.forEach { tabsByID.removeValue(forKey: $0) }
        groupsByID.removeValue(forKey: record.id)
        orderedGroupIDs.removeAll { $0 == record.id }
        window.contentView = nil
        revision.value += 1
        onGroupsChanged?(orderedGroupIDs)
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let record = record(for: window) else { return }
        updateWindowTitle(record)
    }

    private func record(for window: NSWindow) -> GroupRecord? {
        orderedGroupIDs.lazy.compactMap { self.groupsByID[$0] }.first { $0.controller?.window === window }
    }
}

/// The live declarative root installed in every coordinated window.
public struct FluentWindowTabGroupView: FluentView {
    public let coordinator: FluentWindowTabCoordinator
    public let groupID: FluentWindowTabGroupID

    public init(coordinator: FluentWindowTabCoordinator, groupID: FluentWindowTabGroupID) {
        self.coordinator = coordinator
        self.groupID = groupID
    }

    public var body: FluentAnyView {
        coordinator.makeTabView(for: groupID)
    }
}
