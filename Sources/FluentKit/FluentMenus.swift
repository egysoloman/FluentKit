import AppKit

public enum FluentMenuItemState {
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

public struct FluentMenuItem {
    public let title: String
    public let isEnabled: Bool
    public let state: FluentMenuItemState
    public let keyEquivalent: String
    public let keyModifiers: NSEvent.ModifierFlags
    public let submenu: [FluentMenuItem]
    public let action: () -> Void
    let isSeparator: Bool

    public var hasSubmenu: Bool { !submenu.isEmpty }

    public init(
        _ title: String,
        isEnabled: Bool = true,
        state: FluentMenuItemState = .off,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        submenu: [FluentMenuItem] = [],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.state = state
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.submenu = submenu
        self.action = action
        self.isSeparator = false
    }

    private init(separator: Void) {
        title = ""
        isEnabled = false
        state = .off
        keyEquivalent = ""
        keyModifiers = []
        submenu = []
        action = {}
        isSeparator = true
    }

    public static var separator: FluentMenuItem { FluentMenuItem(separator: ()) }

    public static func submenu(
        _ title: String,
        isEnabled: Bool = true,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) -> FluentMenuItem {
        FluentMenuItem(title, isEnabled: isEnabled, submenu: items(), action: {})
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

/// A custom in-application menu presenter. The macOS main menu intentionally remains native.
public final class FluentMenuFlyout {
    private let items: [FluentMenuItem]
    private let theme: FluentTheme
    private let minimumWidth: CGFloat
    private weak var owner: FluentMenuFlyout?
    private var panel: FluentMenuPanel?
    private var presenter: FluentMenuPresenterView?
    private var childFlyout: FluentMenuFlyout?
    private var childIndex: Int?
    private var pendingSubmenuWorkItem: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var parentWindow: NSWindow?
    private var layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight

    public init(items: [FluentMenuItem], theme: FluentTheme = .current, minimumWidth: CGFloat = 180) {
        self.items = items
        self.theme = theme
        self.minimumWidth = max(0, minimumWidth)
        owner = nil
    }

    private init(items: [FluentMenuItem], theme: FluentTheme, owner: FluentMenuFlyout) {
        self.items = items
        self.theme = theme
        minimumWidth = 180
        self.owner = owner
    }

    /// Whether the application-owned flyout panel is currently presented.
    public var isPresented: Bool { panel != nil }

    public func present(relativeTo anchor: NSView, at point: NSPoint? = nil) {
        guard owner == nil else {
            owner?.present(relativeTo: anchor, at: point)
            return
        }
        dismissBranch(animated: false)
        guard !items.isEmpty, let anchorWindow = anchor.window else { return }
        layoutDirection = anchor.userInterfaceLayoutDirection
        let size = FluentMenuPresenterView.preferredSize(for: items, theme: theme, minimumWidth: minimumWidth)
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screenPoint = point.map { anchorWindow.convertPoint(toScreen: anchor.convert($0, to: nil)) }
        let visibleFrame = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let rightToLeft = layoutDirection == .rightToLeft
        var origin: NSPoint
        if let screenPoint {
            origin = NSPoint(x: screenPoint.x - (rightToLeft ? size.width : 0), y: screenPoint.y - size.height)
            if origin.y < visibleFrame.minY { origin.y = anchorRect.maxY }
        } else {
            origin = NSPoint(
                x: rightToLeft ? anchorRect.maxX - size.width : anchorRect.minX,
                y: anchorRect.minY - size.height
            )
            if origin.y < visibleFrame.minY { origin.y = anchorRect.maxY }
        }
        presentPanel(
            in: anchorWindow,
            origin: clamped(origin, size: size, visibleFrame: visibleFrame),
            direction: layoutDirection
        )
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
        layoutDirection = anchor.userInterfaceLayoutDirection
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
        presentPanel(
            in: anchorWindow,
            origin: clamped(origin, size: size, visibleFrame: visibleFrame),
            direction: layoutDirection
        )
    }

    private func presentPanel(
        in anchorWindow: NSWindow,
        origin: NSPoint,
        direction: NSUserInterfaceLayoutDirection
    ) {
        let presenter = FluentMenuPresenterView(
            items: items,
            theme: theme,
            layoutDirection: direction,
            minimumWidth: minimumWidth
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
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true

        let material = FluentMaterialView(material: .acrylic)
        material.frame = NSRect(origin: .zero, size: size)
        material.tintColor = theme.micaTint.withAlphaComponent(theme.isDark ? 0.88 : 0.78)
        material.wantsLayer = true
        material.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        material.layer?.borderWidth = theme.controlStrokeWidth
        material.layer?.borderColor = theme.controlStroke.cgColor
        material.layer?.masksToBounds = true
        presenter.frame = material.bounds
        presenter.autoresizingMask = [.width, .height]
        material.addSubview(presenter)
        panel.contentView = material

        presenter.onDismiss = { [weak self] in self?.root.dismiss() }
        presenter.onSelection = { [weak self] index, row in self?.scheduleSubmenu(index: index, row: row) }
        presenter.onSubmenu = { [weak self] index, row in self?.openSubmenu(index: index, row: row) }
        presenter.onCloseSubmenu = { [weak self] in self?.closeFromKeyboard() }
        parentWindow = anchorWindow
        anchorWindow.addChildWindow(panel, ordered: .above)
        self.panel = panel
        self.presenter = presenter
        panel.setFrameOrigin(origin)
        if owner == nil { installOutsideClickMonitors() }

        let motion = FluentMotion.teachingTipOpen
        panel.alphaValue = 0
        material.layer?.setAffineTransform(
            CGAffineTransform(translationX: 0, y: motion.distance)
                .scaledBy(x: motion.scale, y: motion.scale)
        )
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(presenter)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.duration
            context.timingFunction = motion.curve.timingFunction
            panel.animator().alphaValue = 1
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(motion.duration)
        CATransaction.setAnimationTimingFunction(motion.curve.timingFunction)
        material.layer?.setAffineTransform(.identity)
        CATransaction.commit()
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

    private func dismissBranch(animated: Bool) {
        pendingSubmenuWorkItem?.cancel()
        pendingSubmenuWorkItem = nil
        childFlyout?.dismissBranch(animated: false)
        childFlyout = nil
        childIndex = nil
        if owner == nil { removeOutsideClickMonitors() }
        guard let panel else { return }
        let finish = { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
            self.presenter = nil
        }
        guard animated, panel.isVisible else {
            finish()
            return
        }
        let motion = FluentMotion.teachingTipClose
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.duration
            context.timingFunction = motion.curve.timingFunction
            panel.animator().alphaValue = 0
        } completionHandler: {
            finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + motion.duration + 0.02, execute: finish)
        if let material = panel.contentView?.layer {
            CATransaction.begin()
            CATransaction.setAnimationDuration(motion.duration)
            CATransaction.setAnimationTimingFunction(motion.curve.timingFunction)
            material.setAffineTransform(
                CGAffineTransform(translationX: 0, y: motion.distance)
                    .scaledBy(x: motion.scale, y: motion.scale)
            )
            CATransaction.commit()
        }
    }

    private func installOutsideClickMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, !self.contains(window: event.window) { self.dismiss() }
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

    private func removeOutsideClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit {
        removeOutsideClickMonitors()
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
    private let theme: FluentTheme
    private let layoutDirection: NSUserInterfaceLayoutDirection
    private var itemRows: [Int: FluentMenuItemRow] = [:]
    private var typeahead = ""
    private var typeaheadResetWorkItem: DispatchWorkItem?
    private(set) var selectedIndex: Int?

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
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)

        var y: CGFloat = 2
        for (index, item) in items.enumerated() {
            if item.isSeparator {
                let separator = FluentMenuSeparatorView(theme: theme)
                separator.frame = NSRect(x: 8, y: y, width: preferredSize.width - 16, height: 9)
                addSubview(separator)
                y += 9
                continue
            }
            let row = FluentMenuItemRow(item: item, theme: theme, accelerator: Self.accelerator(for: item), layoutDirection: layoutDirection)
            row.frame = NSRect(x: 4, y: y + 2, width: preferredSize.width - 8, height: 32)
            row.onHighlight = { [weak self] in self?.select(index, announce: true) }
            row.onInvoke = { [weak self] in self?.invoke(index) }
            addSubview(row)
            itemRows[index] = row
            y += 36
        }
        selectedIndex = enabledIndices.first
        updateSelection()
        setAccessibilityChildren(itemRows.keys.sorted().compactMap { itemRows[$0] })
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
            if let first = enabledIndices.first { select(first, announce: true) }
        case 119:
            if let last = enabledIndices.last { select(last, announce: true) }
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
        let current = selectedIndex.flatMap { enabled.firstIndex(of: $0) } ?? 0
        selectedIndex = enabled[(current + offset + enabled.count) % enabled.count]
        updateSelection()
        if let selectedIndex, let row = itemRows[selectedIndex] {
            onSelection?(selectedIndex, row)
            NSAccessibility.post(element: row, notification: .focusedUIElementChanged)
        }
    }

    private func select(_ index: Int, announce: Bool) {
        guard items.indices.contains(index) else { return }
        guard items[index].isEnabled else { return }
        selectedIndex = index
        updateSelection()
        if let row = itemRows[index] {
            onSelection?(index, row)
            if announce { NSAccessibility.post(element: row, notification: .focusedUIElementChanged) }
        }
    }

    private func updateSelection() {
        for (index, row) in itemRows {
            row.isKeyboardSelected = index == selectedIndex
            row.setAccessibilitySelected(index == selectedIndex)
        }
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
        if let first = enabledIndices.first { select(first, announce: false) }
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
        if let matching { select(matching, announce: true) }
    }

    static func preferredSize(for items: [FluentMenuItem], theme: FluentTheme, minimumWidth: CGFloat) -> NSSize {
        let font = theme.typography.font(for: .body)
        let widest = items.filter { !$0.isSeparator }.reduce(CGFloat(0)) { result, item in
            let titleWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
            let keyWidth = (Self.accelerator(for: item) as NSString).size(withAttributes: [.font: font]).width
            return max(result, titleWidth + keyWidth + (item.hasSubmenu ? 20 : 0))
        }
        let height = 4 + items.reduce(CGFloat(0)) { $0 + ($1.isSeparator ? 9 : 36) }
        return NSSize(width: max(minimumWidth, ceil(widest + 86)), height: max(8, height))
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

    deinit { typeaheadResetWorkItem?.cancel() }
}

private final class FluentMenuItemRow: NSControl {
    var isKeyboardSelected = false { didSet { needsDisplay = true } }
    var onHighlight: (() -> Void)?
    var onInvoke: (() -> Void)?

    private let item: FluentMenuItem
    private let theme: FluentTheme
    private let accelerator: String
    private let layoutDirection: NSUserInterfaceLayoutDirection
    private var isPointerOver = false
    private var isPressed = false

    init(item: FluentMenuItem, theme: FluentTheme, accelerator: String, layoutDirection: NSUserInterfaceLayoutDirection) {
        self.item = item
        self.theme = theme
        self.accelerator = accelerator
        self.layoutDirection = layoutDirection
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Menu.Item")
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(item.title)
        setAccessibilityEnabled(item.isEnabled)
        setAccessibilityValue(item.hasSubmenu ? "Submenu" : accessibilityState)
        setAccessibilityHelp(item.hasSubmenu ? "Opens a submenu" : nil)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        onHighlight?()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard item.isEnabled else { return }
        isPressed = true
        needsDisplay = true
        displayIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPressed = false
            self.onInvoke?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard item.isEnabled else { return false }
        onInvoke?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if item.isEnabled, isPressed || isPointerOver || isKeyboardSelected {
            let fill = isPressed ? theme.controlFillTertiary : theme.controlFillSecondary
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let alpha: CGFloat = item.isEnabled ? 1 : 0.42
        let foreground = theme.textPrimary.withAlphaComponent(alpha)
        let font = theme.typography.font(for: .body)
        let titleSize = (item.title as NSString).size(withAttributes: [.font: font])

        let rightToLeft = layoutDirection == .rightToLeft
        switch item.state {
        case .off: break
        case .on:
            let mark = NSBezierPath()
            let x = rightToLeft ? bounds.maxX - 23 : 12
            mark.move(to: NSPoint(x: x, y: bounds.midY))
            mark.line(to: NSPoint(x: x + (rightToLeft ? -4 : 4), y: bounds.midY - 4))
            mark.line(to: NSPoint(x: x + (rightToLeft ? -11 : 11), y: bounds.midY + 4))
            mark.lineWidth = 1.7
            mark.lineCapStyle = .round
            foreground.setStroke()
            mark.stroke()
        case .mixed:
            foreground.setFill()
            NSBezierPath(roundedRect: NSRect(x: rightToLeft ? bounds.maxX - 23 : 12, y: bounds.midY - 1, width: 11, height: 2), xRadius: 1, yRadius: 1).fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        (item.title as NSString).draw(
            in: NSRect(x: 34, y: bounds.midY - titleSize.height / 2, width: max(0, bounds.width - 78), height: titleSize.height),
            withAttributes: [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
        )
        if !accelerator.isEmpty {
            let acceleratorSize = (accelerator as NSString).size(withAttributes: [.font: font])
            let acceleratorX = rightToLeft ? 11 : bounds.maxX - acceleratorSize.width - 11
            (accelerator as NSString).draw(
                in: NSRect(x: acceleratorX, y: bounds.midY - acceleratorSize.height / 2, width: acceleratorSize.width, height: acceleratorSize.height),
                withAttributes: [.font: font, .foregroundColor: theme.textSecondary.withAlphaComponent(alpha)]
            )
        }
        if item.hasSubmenu {
            let x = rightToLeft ? 16 : bounds.maxX - 16
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
            theme.textSecondary.withAlphaComponent(alpha).setStroke()
            chevron.stroke()
        }
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
    private let theme: FluentTheme

    init(theme: FluentTheme) {
        self.theme = theme
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let host = FluentContextMenuHost(content: content._mount(in: context), items: items, theme: context.theme)
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentContextMenuHost else { return false }
        host.items = items
        host.theme = context.theme
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentContextMenuHost: NSView {
    var items: [FluentMenuItem]
    var theme: FluentTheme
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var flyout: FluentMenuFlyout?

    init(content: NSView, items: [FluentMenuItem], theme: FluentTheme) {
        self.items = items
        self.theme = theme
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

    override func rightMouseDown(with event: NSEvent) {
        guard !items.isEmpty else { return }
        let flyout = FluentMenuFlyout(items: items, theme: theme)
        self.flyout = flyout
        flyout.present(relativeTo: self, at: convert(event.locationInWindow, from: nil))
    }
}

public extension FluentView {
    func contextMenu(@FluentMenuBuilder items: () -> [FluentMenuItem]) -> FluentContextMenuView<Self> {
        FluentContextMenuView(content: self, items: items())
    }
}
