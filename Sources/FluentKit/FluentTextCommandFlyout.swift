import AppKit

public enum FluentCommandBarItemKind: Hashable, Sendable {
    case button
    case toggle(isOn: Bool)
    case separator
}

public struct FluentCommandBarItem {
    public let title: String
    public let systemImageName: String?
    public let isEnabled: Bool
    public let kind: FluentCommandBarItemKind
    public let keyEquivalent: String
    public let keyModifiers: NSEvent.ModifierFlags
    public let action: () -> Void

    public init(
        _ title: String,
        systemImageName: String? = nil,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        kind = .button
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.action = action
    }

    private init(
        title: String,
        systemImageName: String?,
        isEnabled: Bool,
        kind: FluentCommandBarItemKind,
        keyEquivalent: String,
        keyModifiers: NSEvent.ModifierFlags,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.kind = kind
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.action = action
    }

    public static func toggle(
        _ title: String,
        systemImageName: String? = nil,
        isOn: Bool,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        action: @escaping (Bool) -> Void
    ) -> FluentCommandBarItem {
        FluentCommandBarItem(
            title: title,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            kind: .toggle(isOn: isOn),
            keyEquivalent: keyEquivalent,
            keyModifiers: keyModifiers,
            action: { action(!isOn) }
        )
    }

    public static var separator: FluentCommandBarItem {
        FluentCommandBarItem(
            title: "",
            systemImageName: nil,
            isEnabled: false,
            kind: .separator,
            keyEquivalent: "",
            keyModifiers: [],
            action: {}
        )
    }

    public var accelerator: String {
        guard !keyEquivalent.isEmpty else { return "" }
        var value = ""
        if keyModifiers.contains(.control) { value += "⌃" }
        if keyModifiers.contains(.option) { value += "⌥" }
        if keyModifiers.contains(.shift) { value += "⇧" }
        if keyModifiers.contains(.command) { value += "⌘" }
        return value + keyEquivalent.uppercased()
    }

    var isSeparator: Bool { kind == .separator }
    var isChecked: Bool {
        if case .toggle(let isOn) = kind { return isOn }
        return false
    }
}

@resultBuilder
public enum FluentCommandBarBuilder {
    public static func buildBlock(_ components: FluentCommandBarItem...) -> [FluentCommandBarItem] { components }
    public static func buildOptional(_ component: [FluentCommandBarItem]?) -> [FluentCommandBarItem] { component ?? [] }
    public static func buildEither(first component: [FluentCommandBarItem]) -> [FluentCommandBarItem] { component }
    public static func buildEither(second component: [FluentCommandBarItem]) -> [FluentCommandBarItem] { component }
    public static func buildArray(_ components: [[FluentCommandBarItem]]) -> [FluentCommandBarItem] { components.flatMap { $0 } }
}

public struct FluentCommandBarFlyoutConfiguration {
    public let primaryCommands: [FluentCommandBarItem]
    public let secondaryCommands: [FluentCommandBarItem]
    public let alwaysExpanded: Bool

    public init(
        primaryCommands: [FluentCommandBarItem],
        secondaryCommands: [FluentCommandBarItem] = [],
        alwaysExpanded: Bool = false
    ) {
        self.primaryCommands = primaryCommands
        self.secondaryCommands = secondaryCommands
        self.alwaysExpanded = alwaysExpanded
    }
}

/// A WinUI-style CommandBarFlyout with compact primary commands and an optional secondary overflow.
public final class FluentCommandBarFlyout {
    public let primaryCommands: [FluentCommandBarItem]
    public let secondaryCommands: [FluentCommandBarItem]
    public let alwaysExpanded: Bool

    private let presenter: FluentTextCommandFlyout

    public var onDismiss: (() -> Void)? {
        didSet { presenter.onDismiss = { [weak self] in self?.onDismiss?() } }
    }

    public var isPresented: Bool { presenter.isPresented }

    public init(
        primaryCommands: [FluentCommandBarItem],
        secondaryCommands: [FluentCommandBarItem] = [],
        alwaysExpanded: Bool = false,
        theme: FluentTheme = .current,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        self.primaryCommands = primaryCommands
        self.secondaryCommands = secondaryCommands
        self.alwaysExpanded = alwaysExpanded
        presenter = FluentTextCommandFlyout(
            commands: Self.resolve(primaryCommands, isPrimary: true)
                + Self.resolve(secondaryCommands, isPrimary: false),
            theme: theme,
            reduceMotion: reduceMotion,
            alwaysExpanded: alwaysExpanded,
            presenterIdentifier: "FluentKit.CommandBarFlyout",
            presenterTitle: "Command bar"
        )
    }

    public convenience init(
        alwaysExpanded: Bool = false,
        theme: FluentTheme = .current,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        @FluentCommandBarBuilder primaryCommands: () -> [FluentCommandBarItem],
        @FluentCommandBarBuilder secondaryCommands: () -> [FluentCommandBarItem] = { [] }
    ) {
        self.init(
            primaryCommands: primaryCommands(),
            secondaryCommands: secondaryCommands(),
            alwaysExpanded: alwaysExpanded,
            theme: theme,
            reduceMotion: reduceMotion
        )
    }

    public func present(relativeTo anchor: NSView, at point: NSPoint? = nil) {
        presenter.present(
            relativeTo: anchor,
            at: point ?? NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
        )
    }

    public func dismiss() { presenter.dismiss(animated: false) }

    private static func resolve(
        _ items: [FluentCommandBarItem],
        isPrimary: Bool
    ) -> [FluentTextCommand] {
        items.map { item in
            FluentTextCommand(
                kind: .custom(UUID()),
                title: item.title,
                accelerator: item.accelerator,
                systemImageName: item.systemImageName,
                action: item.action,
                isPrimary: isPrimary,
                isEnabled: item.isEnabled,
                isChecked: item.isChecked,
                isSeparator: item.isSeparator,
                showsSecondaryIcon: !isPrimary && item.systemImageName != nil
            )
        }
    }
}

enum FluentTextCommandKind: Hashable {
    case cut
    case copy
    case paste
    case undo
    case redo
    case selectAll
    case custom(UUID)
}

struct FluentTextCommand {
    let kind: FluentTextCommandKind
    let title: String
    let accelerator: String
    let systemImageName: String?
    let action: () -> Void
    let isPrimary: Bool
    let isEnabled: Bool
    let isChecked: Bool
    let isSeparator: Bool
    let showsSecondaryIcon: Bool

    init(
        kind: FluentTextCommandKind,
        title: String,
        accelerator: String,
        systemImageName: String?,
        action: @escaping () -> Void,
        isPrimary: Bool,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        isSeparator: Bool = false,
        showsSecondaryIcon: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.accelerator = accelerator
        self.systemImageName = systemImageName
        self.action = action
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.isSeparator = isSeparator
        self.showsSecondaryIcon = showsSecondaryIcon
    }
}

/// The TextCommandBarFlyout surface used by TextBox-family controls. WinUI puts the direct
/// editing commands in a compact icon bar and keeps history/select-all commands in its overflow.
final class FluentTextCommandFlyout {
    private let commands: [FluentTextCommand]
    private var theme: FluentTheme
    private let reduceMotion: Bool
    private let alwaysExpanded: Bool
    private let presenterIdentifier: String
    private let presenterTitle: String
    private let animationCoordinator: FluentAnimationCoordinator
    private var panel: FluentTextCommandPanel?
    private var view: FluentTextCommandBarView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var applicationObserver: NSObjectProtocol?
    private var materialView: FluentMaterialView?
    private var animationRoot: NSView?
    private weak var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    private var expansionGeneration = 0
    private var anchorScreenPoint: NSPoint = .zero
    private var opensAbove = true

    var onDismiss: (() -> Void)?
    var isPresented: Bool { panel != nil }

    init(
        commands: [FluentTextCommand],
        theme: FluentTheme,
        reduceMotion: Bool,
        alwaysExpanded: Bool = false,
        presenterIdentifier: String = "FluentKit.TextCommandBarFlyout",
        presenterTitle: String = "Text commands"
    ) {
        self.commands = commands
        self.theme = theme
        self.reduceMotion = reduceMotion
        self.alwaysExpanded = alwaysExpanded
        self.presenterIdentifier = presenterIdentifier
        self.presenterTitle = presenterTitle
        animationCoordinator = FluentAnimationCoordinator(reduceMotion: reduceMotion)
    }

    func present(relativeTo anchor: NSView, at point: NSPoint) {
        dismiss(animated: false, notify: false)
        guard let parentWindow = anchor.window, !commands.isEmpty else { return }
        registerAppearanceUpdates(from: parentWindow)
        anchorScreenPoint = parentWindow.convertPoint(toScreen: anchor.convert(point, to: nil))

        let primary = commands.filter(\.isPrimary)
        let secondary = commands.filter { !$0.isPrimary }
        let hasPrimaryCommands = primary.contains { !$0.isSeparator }
        let hasSecondaryCommands = secondary.contains { !$0.isSeparator }
        let startsExpanded = alwaysExpanded || (!hasPrimaryCommands && hasSecondaryCommands)
        let contentSize = FluentTextCommandBarView.preferredSize(
            primary: primary,
            secondary: secondary,
            theme: theme,
            expanded: startsExpanded,
            alwaysExpanded: alwaysExpanded
        )
        let visibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        opensAbove = anchorScreenPoint.y - contentSize.height - 8 >= visibleFrame.minY
        let origin = origin(for: contentSize, visibleFrame: visibleFrame)

        let commandView = FluentTextCommandBarView(
            commands: commands,
            theme: theme,
            primaryAtBottom: !opensAbove,
            alwaysExpanded: alwaysExpanded,
            presenterIdentifier: presenterIdentifier,
            presenterTitle: presenterTitle
        )
        commandView.frame = NSRect(origin: .zero, size: contentSize)
        commandView.onCommand = { [weak self] command in
            command.action()
            self?.dismiss(animated: false)
        }
        commandView.onExpandedChange = { [weak self] expanded in
            self?.resize(expanded: expanded)
        }
        commandView.onDismiss = { [weak self] in self?.dismiss(animated: false) }
        view = commandView

        let popup = FluentTextCommandPanel(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = false
        popup.level = .popUpMenu
        popup.collectionBehavior = [.transient, .fullScreenAuxiliary]
        popup.hidesOnDeactivate = true
        popup.appearance = fluentAppKitAppearance(for: theme) ?? parentWindow.effectiveAppearance
        let surface = FluentMaterialView(material: theme.material(for: .transient) ?? .liquidGlass)
        surface.fluentTheme = theme
        surface.isMaterialEnabled = theme.materialEffectsEnabled
        surface.fallbackColor = theme.flyoutSurfaceFill
        surface.frame = NSRect(origin: .zero, size: contentSize)
        surface.autoresizingMask = [.width, .height]
        surface.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        let animationRoot = NSView(frame: NSRect(origin: .zero, size: contentSize))
        animationRoot.wantsLayer = true
        animationRoot.layer?.name = "FluentKit.TextCommandBarFlyout.AnimationRoot"
        animationRoot.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        animationRoot.layer?.cornerCurve = .continuous
        animationRoot.layer?.masksToBounds = true
        animationRoot.addSubview(surface)
        commandView.frame = animationRoot.bounds
        commandView.autoresizingMask = [.width, .height]
        animationRoot.addSubview(commandView)
        self.animationRoot = animationRoot
        materialView = surface
        popup.contentView = animationRoot
        commandView.needsLayout = true
        commandView.layoutSubtreeIfNeeded()
        panel = popup
        if let animationLayer = animationRoot.layer {
            animationCoordinator.animateTransition(
                [
                    FluentLayerAnimationChange(
                        layer: animationLayer,
                        key: "fluent.popup.textCommandBar.open.opacity",
                        keyPath: "opacity",
                        fromValue: 0,
                        toValue: Float(1),
                        applyModelValue: { animationLayer.opacity = 1 }
                    )
                ],
                motion: FluentMotion.commandBarFlyoutOpen,
                animated: true
            )
        }
        // Attach the source OpeningOpacityStoryboard before AppKit can display the first panel
        // frame. Ordering first can expose the fully opaque model layer for one refresh cycle.
        parentWindow.addChildWindow(popup, ordered: .above)
        popup.orderFront(nil)
        installOutsideClickMonitor()
    }

    func dismiss(animated: Bool, notify: Bool = true) {
        expansionGeneration += 1
        removeOutsideClickMonitor()
        if let rootLayer = animationRoot?.layer {
            var animatedLayers = [rootLayer]
            if let mask = rootLayer.mask { animatedLayers.append(mask) }
            animationCoordinator.cancelAll(on: animatedLayers)
        }
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        view = nil
        materialView = nil
        animationRoot = nil
        unregisterAppearanceUpdates()
        if notify { onDismiss?() }
    }

    private func resize(expanded: Bool, animated: Bool = true) {
        guard let panel, let view else { return }
        let previousSize = panel.frame.size
        let primary = commands.filter(\.isPrimary)
        let secondary = commands.filter { !$0.isPrimary }
        let size = FluentTextCommandBarView.preferredSize(
            primary: primary,
            secondary: secondary,
            theme: theme,
            expanded: expanded,
            alwaysExpanded: alwaysExpanded
        )
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = origin(for: size, visibleFrame: visibleFrame)
        let frame = NSRect(origin: origin, size: size)
        // The source state machine commits Expanded geometry before running its clip storyboard.
        // Keeping window geometry out of the visual animation also makes the model frame reliable.
        panel.setFrame(frame, display: true)
        let contentBounds = NSRect(origin: .zero, size: size)
        animationRoot?.frame = contentBounds
        materialView?.frame = contentBounds
        view.frame = contentBounds
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        if animated, expanded, size.height > previousSize.height {
            animateExpansion(from: previousSize, to: size, primaryAtBottom: view.primaryAtBottom)
        }
    }

    private func registerAppearanceUpdates(from window: NSWindow) {
        guard let coordinator = window.fluentAppearanceCoordinator else { return }
        if appearanceCoordinator === coordinator, appearanceRegistration != nil { return }
        unregisterAppearanceUpdates()
        appearanceCoordinator = coordinator
        appearanceRegistration = coordinator.register(
            owner: self,
            prepareForAppearanceChange: { [weak self] in
                self?.settleForAppearanceChange()
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
        materialView?.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        materialView?.fluentTheme = theme
        materialView?.isMaterialEnabled = theme.materialEffectsEnabled
        materialView?.fallbackColor = theme.flyoutSurfaceFill
        materialView?.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        animationRoot?.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        view?.update(theme: theme)
        if let view { resize(expanded: view.isExpanded, animated: false) }
        panel?.contentView?.needsDisplay = true
    }

    private func settleForAppearanceChange() {
        expansionGeneration += 1
        guard let rootLayer = animationRoot?.layer else { return }
        var layers = [rootLayer]
        if let mask = rootLayer.mask { layers.append(mask) }
        animationCoordinator.cancelAll(on: layers)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.opacity = 1
        rootLayer.mask = nil
        CATransaction.commit()
    }

    private func animateExpansion(from previousSize: NSSize, to size: NSSize, primaryAtBottom: Bool) {
        guard let animationRoot, let layer = animationRoot.layer else { return }
        expansionGeneration += 1
        let generation = expansionGeneration
        animationRoot.layoutSubtreeIfNeeded()

        let fullRect = CGRect(origin: .zero, size: size)
        let collapsedWidth = min(previousSize.width, size.width)
        let collapsedHeight = min(previousSize.height, size.height)
        let collapsedRect = CGRect(
            x: (size.width - collapsedWidth) / 2,
            y: primaryAtBottom ? 0 : size.height - collapsedHeight,
            width: collapsedWidth,
            height: collapsedHeight
        )
        let mask = CAShapeLayer()
        mask.name = "FluentKit.TextCommandBarFlyout.ExpansionClip"
        mask.frame = fullRect
        mask.path = CGPath(rect: fullRect, transform: nil)
        layer.mask = mask

        let fullPath = CGPath(rect: fullRect, transform: nil)
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: mask,
                    key: "fluent.popup.textCommandBar.expand.clip",
                    keyPath: "path",
                    fromValue: CGPath(rect: collapsedRect, transform: nil),
                    toValue: fullPath,
                    applyModelValue: { mask.path = fullPath }
                )
            ],
            motion: FluentMotion.controlNormal,
            animated: true
        ) { [weak self, weak layer, weak mask] in
            guard let self, self.expansionGeneration == generation, layer?.mask === mask else { return }
            layer?.mask = nil
        }
    }

    private func origin(for size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let x = min(
            max(anchorScreenPoint.x - size.width / 2, visibleFrame.minX + 4),
            max(visibleFrame.maxX - size.width - 4, visibleFrame.minX + 4)
        )
        let y = opensAbove
            ? anchorScreenPoint.y - size.height - 8
            : anchorScreenPoint.y + 8
        return NSPoint(
            x: x,
            y: min(max(y, visibleFrame.minY + 4), max(visibleFrame.maxY - size.height - 4, visibleFrame.minY + 4))
        )
    }

    private func installOutsideClickMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismiss(animated: false)
                return nil
            }
            if event.window === panel { return event }
            if event.type == .keyDown { return event }
            self.dismiss(animated: false)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss(animated: false)
        }
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in self?.dismiss(animated: false) }
    }

    private func removeOutsideClickMonitor() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let applicationObserver { NotificationCenter.default.removeObserver(applicationObserver) }
        localMonitor = nil
        globalMonitor = nil
        applicationObserver = nil
    }

    deinit { dismiss(animated: false, notify: false) }
}

private final class FluentTextCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FluentTextCommandBarView: NSView {
    private let commands: [FluentTextCommand]
    private var theme: FluentTheme
    private let primaryViews: [NSView]
    private let primaryButtons: [FluentTextCommandButton]
    private let moreButton: FluentTextCommandButton?
    private var secondaryViews: [NSView] = []
    private var secondaryRows: [FluentTextCommandRow] = []
    private(set) var isExpanded: Bool
    let primaryAtBottom: Bool

    var onCommand: ((FluentTextCommand) -> Void)?
    var onExpandedChange: ((Bool) -> Void)?
    var onDismiss: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(
        commands: [FluentTextCommand],
        theme: FluentTheme,
        primaryAtBottom: Bool,
        alwaysExpanded: Bool,
        presenterIdentifier: String,
        presenterTitle: String
    ) {
        self.commands = commands
        self.theme = theme
        self.primaryAtBottom = primaryAtBottom
        let primary = commands.filter(\.isPrimary)
        let secondary = commands.filter { !$0.isPrimary }
        let hasPrimaryCommands = primary.contains { !$0.isSeparator }
        let hasSecondaryCommands = secondary.contains { !$0.isSeparator }
        isExpanded = alwaysExpanded || (!hasPrimaryCommands && hasSecondaryCommands)
        primaryViews = primary.map { command in
            command.isSeparator
                ? FluentCommandBarSeparatorView(theme: theme, orientation: .vertical)
                : FluentTextCommandButton(command: command, theme: theme, showsIcon: true)
        }
        primaryButtons = primaryViews.compactMap { $0 as? FluentTextCommandButton }
        if alwaysExpanded || !hasSecondaryCommands || !hasPrimaryCommands {
            moreButton = nil
        } else {
            moreButton = FluentTextCommandButton(
                title: "More",
                accelerator: "",
                systemImageName: "ellipsis",
                theme: theme
            )
        }
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier(presenterIdentifier)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityTitle(presenterTitle)
        primaryViews.forEach(addSubview)
        primaryButtons.forEach { button in
            button.onInvoke = { [weak self, weak button] in
                guard let self, let button else { return }
                self.onCommand?(button.command)
            }
        }
        if let moreButton {
            moreButton.onInvoke = { [weak self] in
                guard let self else { return }
                self.isExpanded.toggle()
                self.rebuildSecondaryRows()
                self.onExpandedChange?(self.isExpanded)
                self.needsLayout = true
                self.setAccessibilityChildren(self.accessibilityElements)
            }
            addSubview(moreButton)
        }
        rebuildSecondaryRows()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let secondary = commands.filter { !$0.isPrimary }
        let primaryY = isExpanded && primaryAtBottom ? max(bounds.height - 48, 0) : 0
        var x: CGFloat = 8
        for primaryView in primaryViews {
            let width: CGFloat = primaryView is FluentCommandBarSeparatorView ? 5 : 40
            primaryView.frame = NSRect(x: x, y: primaryY + 4, width: width, height: 40)
            x += width
        }
        if let moreButton {
            moreButton.frame = NSRect(x: x, y: primaryY + 4, width: 40, height: 40)
        }
        guard isExpanded, !secondary.isEmpty else { return }
        let hasPrimaryCommands = !primaryButtons.isEmpty
        var y: CGFloat = !hasPrimaryCommands || primaryAtBottom ? 4 : 52
        for secondaryView in secondaryViews {
            if secondaryView is FluentCommandBarSeparatorView {
                secondaryView.frame = NSRect(x: 8, y: y, width: max(bounds.width - 16, 0), height: 9)
                y += 9
            } else {
                secondaryView.frame = NSRect(x: 4, y: y, width: bounds.width - 8, height: 32)
                y += 36
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let strokeWidth: CGFloat = theme.isHighContrast ? 2 : 1
        let strokeInset = strokeWidth / 2
        let surface = NSBezierPath(
            roundedRect: bounds.insetBy(dx: strokeInset, dy: strokeInset),
            xRadius: max(theme.designTokens.cardCornerRadius - strokeInset, 0),
            yRadius: max(theme.designTokens.cardCornerRadius - strokeInset, 0)
        )
        // The popup host owns the fill. Keeping this view transparent lets the native Liquid
        // Glass surface remain visible; the opaque fallback is supplied by FluentMaterialView
        // when the global material switch is disabled.
        theme.surfaceStrokeFlyout.setStroke()
        surface.lineWidth = strokeWidth
        surface.stroke()
        if isExpanded, !primaryButtons.isEmpty {
            theme.divider.setFill()
            let dividerY = primaryAtBottom ? max(bounds.height - 49, 0) : 48
            NSRect(x: 8, y: dividerY, width: max(0, bounds.width - 16), height: 1).fill()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    private func rebuildSecondaryRows() {
        secondaryViews.forEach { $0.removeFromSuperview() }
        secondaryViews.removeAll()
        secondaryRows.removeAll()
        guard isExpanded else {
            updateAccessibilityChildren()
            return
        }
        let secondary = commands.filter { !$0.isPrimary }
        let reservesToggleSlot = secondary.contains { !$0.isSeparator && $0.isChecked }
        let reservesIconSlot = secondary.contains { !$0.isSeparator && $0.showsSecondaryIcon }
        for command in secondary {
            if command.isSeparator {
                let separator = FluentCommandBarSeparatorView(theme: theme, orientation: .horizontal)
                secondaryViews.append(separator)
                addSubview(separator)
                continue
            }
            let row = FluentTextCommandRow(
                command: command,
                theme: theme,
                reservesToggleSlot: reservesToggleSlot,
                reservesIconSlot: reservesIconSlot
            )
            row.onInvoke = { [weak self] in self?.onCommand?(command) }
            secondaryRows.append(row)
            secondaryViews.append(row)
            addSubview(row)
        }
        updateAccessibilityChildren()
    }

    private func updateAccessibilityChildren() {
        var children: [Any] = primaryButtons
        if let moreButton { children.append(moreButton) }
        if isExpanded { children.append(contentsOf: secondaryRows) }
        setAccessibilityChildren(children)
    }

    private var accessibilityElements: [Any] {
        var children: [Any] = primaryButtons
        if let moreButton { children.append(moreButton) }
        if isExpanded { children.append(contentsOf: secondaryRows) }
        return children
    }

    private func applyTheme() {
        layer?.backgroundColor = NSColor.clear.cgColor
        for view in primaryViews {
            if let button = view as? FluentTextCommandButton {
                button.theme = theme
            } else if let separator = view as? FluentCommandBarSeparatorView {
                separator.update(theme: theme)
            }
        }
        moreButton?.theme = theme
        for view in secondaryViews {
            if let row = view as? FluentTextCommandRow {
                row.theme = theme
            } else if let separator = view as? FluentCommandBarSeparatorView {
                separator.update(theme: theme)
            }
        }
        needsDisplay = true
    }

    func update(theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        applyTheme()
        needsLayout = true
    }

    static func preferredSize(
        primary: [FluentTextCommand],
        secondary: [FluentTextCommand],
        theme: FluentTheme,
        expanded: Bool,
        alwaysExpanded: Bool = false
    ) -> NSSize {
        let hasPrimaryCommands = primary.contains { !$0.isSeparator }
        let hasSecondaryCommands = secondary.contains { !$0.isSeparator }
        let primaryContentWidth = primary.reduce(CGFloat(0)) { width, command in
            width + (command.isSeparator ? 5 : 40)
        }
        let moreWidth: CGFloat = hasSecondaryCommands && hasPrimaryCommands && !alwaysExpanded ? 40 : 0
        let primaryWidth = primaryContentWidth + moreWidth > 0 ? primaryContentWidth + moreWidth + 16 : 0
        let reservesToggleSlot = secondary.contains { !$0.isSeparator && $0.isChecked }
        let reservesIconSlot = secondary.contains { !$0.isSeparator && $0.showsSecondaryIcon }
        let leadingSlots = CGFloat((reservesToggleSlot ? 1 : 0) + (reservesIconSlot ? 1 : 0)) * 28
        let secondaryWidth = secondary.filter { !$0.isSeparator }.reduce(CGFloat(0)) { width, command in
            let titleWidth = (command.title as NSString).size(
                withAttributes: [.font: theme.typography.font(for: .body)]
            ).width
            let keyWidth = (command.accelerator as NSString).size(
                withAttributes: [.font: theme.typography.font(for: .body)]
            ).width
            return max(width, ceil(titleWidth + keyWidth + leadingSlots + 60))
        }
        let width = max(56, primaryWidth, expanded ? max(136, secondaryWidth) : 0)
        let baseHeight: CGFloat = hasPrimaryCommands ? 48 : 4
        let secondaryHeight = secondary.reduce(CGFloat(0)) { $0 + ($1.isSeparator ? 9 : 36) }
        let height = baseHeight + (expanded && hasSecondaryCommands ? secondaryHeight + 4 : 0)
        return NSSize(width: width, height: height)
    }
}

private final class FluentTextCommandButton: NSButton {
    let command: FluentTextCommand
    var theme: FluentTheme { didSet { updateImage(); needsDisplay = true } }
    var onInvoke: (() -> Void)?
    private var isPointerOver = false

    init(command: FluentTextCommand, theme: FluentTheme, showsIcon: Bool) {
        self.command = command
        self.theme = theme
        super.init(frame: .zero)
        configure(title: command.title, accelerator: command.accelerator, systemImageName: showsIcon ? command.systemImageName : nil)
        isEnabled = command.isEnabled
        setAccessibilityValue(command.isChecked ? "On" : nil)
    }

    init(title: String, accelerator: String, systemImageName: String, theme: FluentTheme) {
        command = FluentTextCommand(kind: .selectAll, title: title, accelerator: accelerator, systemImageName: systemImageName, action: {}, isPrimary: false)
        self.theme = theme
        super.init(frame: .zero)
        configure(title: title, accelerator: accelerator, systemImageName: systemImageName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        needsDisplay = true
        super.mouseDown(with: event)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let state = resolvedVisualState
        let fill: NSColor
        let foreground: NSColor
        if command.isChecked {
            fill = theme.accentFill(for: state)
            foreground = switch state {
            case .pressed: theme.textOnAccentSecondary
            case .disabled: theme.textOnAccentDisabled
            default: theme.textOnAccent
            }
        } else {
            fill = switch state {
            case .pointerOver: theme.subtleFillSecondary
            case .pressed: theme.subtleFillTertiary
            default: .clear
            }
            foreground = theme.buttonForeground(for: state)
        }
        if fill.alphaComponent > 0 {
            fill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).fill()
        }
        contentTintColor = foreground
        super.draw(dirtyRect)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onInvoke?()
        return true
    }

    private func configure(title: String, accelerator: String, systemImageName: String?) {
        self.title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(title)
        setAccessibilityHelp(accelerator.isEmpty ? nil : "Keyboard shortcut \(accelerator)")
        target = self
        action = #selector(invoke)
        toolTip = title
        updateImage(systemImageName: systemImageName)
    }

    @objc private func invoke() { onInvoke?() }

    private func updateImage() { updateImage(systemImageName: command.systemImageName) }

    private func updateImage(systemImageName: String?) {
        guard let systemImageName,
              let symbol = NSImage(systemSymbolName: systemImageName, accessibilityDescription: accessibilityTitle()) else {
            image = nil
            return
        }
        image = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        ) ?? symbol
        image?.isTemplate = true
    }

    private var resolvedVisualState: FluentControlState {
        guard isEnabled else { return .disabled }
        if isHighlighted { return .pressed }
        if isPointerOver { return .pointerOver }
        return .normal
    }
}

private final class FluentTextCommandRow: NSButton {
    let command: FluentTextCommand
    var theme: FluentTheme { didSet { needsDisplay = true } }
    var onInvoke: (() -> Void)?
    private var isPointerOver = false
    private let reservesToggleSlot: Bool
    private let reservesIconSlot: Bool

    init(
        command: FluentTextCommand,
        theme: FluentTheme,
        reservesToggleSlot: Bool,
        reservesIconSlot: Bool
    ) {
        self.command = command
        self.theme = theme
        self.reservesToggleSlot = reservesToggleSlot
        self.reservesIconSlot = reservesIconSlot
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(command.title)
        setAccessibilityValue(command.isChecked ? "On" : nil)
        setAccessibilityHelp(command.accelerator.isEmpty ? nil : "Keyboard shortcut \(command.accelerator)")
        isEnabled = command.isEnabled
        target = self
        action = #selector(invoke)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isPointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let state = resolvedVisualState
        let fill = theme.menuItemBackground(for: state)
        if fill.alphaComponent > 0 {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let font = theme.typography.font(for: .body)
        let foreground = theme.menuItemForeground(for: state)
        let acceleratorForeground = theme.menuAcceleratorForeground(for: state)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground
        ]
        var titleX: CGFloat = 12
        if reservesToggleSlot {
            if command.isChecked {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 13, y: bounds.midY))
                check.line(to: NSPoint(x: 17, y: bounds.midY - 4))
                check.line(to: NSPoint(x: 24, y: bounds.midY + 4))
                check.lineWidth = 1.7
                check.lineCapStyle = .round
                foreground.setStroke()
                check.stroke()
            }
            titleX += 28
        }
        if reservesIconSlot {
            if command.showsSecondaryIcon,
               let name = command.systemImageName,
               let symbol = NSImage(systemSymbolName: name, accessibilityDescription: command.title) {
                let image = symbol.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                        .applying(.init(hierarchicalColor: foreground))
                ) ?? symbol
                image.draw(
                    in: NSRect(x: titleX, y: bounds.midY - 8, width: 16, height: 16),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
            titleX += 28
        }
        let titleSize = (command.title as NSString).size(withAttributes: attributes)
        (command.title as NSString).draw(
            in: NSRect(
                x: titleX,
                y: bounds.midY - titleSize.height / 2,
                width: max(0, bounds.width - titleX - 12),
                height: titleSize.height
            ),
            withAttributes: attributes
        )
        guard !command.accelerator.isEmpty else { return }
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: acceleratorForeground
        ]
        let keySize = (command.accelerator as NSString).size(withAttributes: keyAttributes)
        (command.accelerator as NSString).draw(
            in: NSRect(x: bounds.maxX - keySize.width - 12, y: bounds.midY - keySize.height / 2, width: keySize.width, height: keySize.height),
            withAttributes: keyAttributes
        )
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onInvoke?()
        return true
    }

    @objc private func invoke() { onInvoke?() }

    private var resolvedVisualState: FluentControlState {
        guard isEnabled else { return .disabled }
        if isHighlighted { return .pressed }
        if isPointerOver { return .pointerOver }
        return .normal
    }
}

private final class FluentCommandBarSeparatorView: NSView {
    enum Orientation { case horizontal, vertical }

    private var theme: FluentTheme
    private let orientation: Orientation

    init(theme: FluentTheme, orientation: Orientation) {
        self.theme = theme
        self.orientation = orientation
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CommandBarFlyout.Separator")
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
        switch orientation {
        case .horizontal:
            NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
        case .vertical:
            NSRect(x: bounds.midX - 0.5, y: 8, width: 1, height: max(bounds.height - 16, 0)).fill()
        }
    }
}
