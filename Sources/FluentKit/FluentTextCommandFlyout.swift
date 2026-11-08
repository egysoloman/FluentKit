import AppKit

public enum FluentCommandBarItemKind: Hashable, Sendable {
    case button
    case toggle(isOn: Bool)
    case separator
}

public struct FluentCommandBarItem {
    /// Stable identity for in-place CommandBar updates and moves between command groups.
    /// Use unique IDs when inserting/reordering; omitted IDs retain identity by group and position.
    public let id: AnyHashable?
    let toggleAction: ((Bool) -> Void)?
    public let title: String
    public let systemImageName: String?
    public let icon: FluentIconSource?
    public let isEnabled: Bool
    public let kind: FluentCommandBarItemKind
    public let keyEquivalent: String
    public let keyModifiers: NSEvent.ModifierFlags
    /// Values greater than zero move to overflow as ascending, equal-valued groups. Zero retains
    /// WinUI's default right-most-first fallback after all ordered groups have moved.
    public let dynamicOverflowOrder: Int
    public let labelPosition: FluentCommandBarLabelPosition
    public let action: () -> Void

    public init(
        id: AnyHashable? = nil,
        _ title: String,
        systemImageName: String? = nil,
        icon: FluentIconSource? = nil,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        dynamicOverflowOrder: Int = 0,
        labelPosition: FluentCommandBarLabelPosition = .default,
        action: @escaping () -> Void
    ) {
        self.id = id
        toggleAction = nil
        self.title = title
        self.systemImageName = systemImageName
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.isEnabled = isEnabled
        kind = .button
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.dynamicOverflowOrder = max(0, dynamicOverflowOrder)
        self.labelPosition = labelPosition
        self.action = action
    }

    private init(
        id: AnyHashable? = nil,
        toggleAction: ((Bool) -> Void)? = nil,
        title: String,
        systemImageName: String?,
        icon: FluentIconSource? = nil,
        isEnabled: Bool,
        kind: FluentCommandBarItemKind,
        keyEquivalent: String,
        keyModifiers: NSEvent.ModifierFlags,
        dynamicOverflowOrder: Int,
        labelPosition: FluentCommandBarLabelPosition,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.toggleAction = toggleAction
        self.title = title
        self.systemImageName = systemImageName
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.isEnabled = isEnabled
        self.kind = kind
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.dynamicOverflowOrder = max(0, dynamicOverflowOrder)
        self.labelPosition = labelPosition
        self.action = action
    }

    public static func toggle(
        id: AnyHashable? = nil,
        _ title: String,
        systemImageName: String? = nil,
        icon: FluentIconSource? = nil,
        isOn: Bool,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        keyModifiers: NSEvent.ModifierFlags = [.command],
        dynamicOverflowOrder: Int = 0,
        labelPosition: FluentCommandBarLabelPosition = .default,
        action: @escaping (Bool) -> Void
    ) -> FluentCommandBarItem {
        FluentCommandBarItem(
            id: id,
            toggleAction: action,
            title: title,
            systemImageName: systemImageName,
            icon: icon,
            isEnabled: isEnabled,
            kind: .toggle(isOn: isOn),
            keyEquivalent: keyEquivalent,
            keyModifiers: keyModifiers,
            dynamicOverflowOrder: dynamicOverflowOrder,
            labelPosition: labelPosition,
            action: { action(!isOn) }
        )
    }

    public static var separator: FluentCommandBarItem {
        separator()
    }

    public static func separator(
        id: AnyHashable? = nil,
        dynamicOverflowOrder: Int = 0
    ) -> FluentCommandBarItem {
        FluentCommandBarItem(
            id: id,
            title: "",
            systemImageName: nil,
            isEnabled: false,
            kind: .separator,
            keyEquivalent: "",
            keyModifiers: [],
            dynamicOverflowOrder: dynamicOverflowOrder,
            labelPosition: .default,
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
/// Primary commands stay open for repeated actions; secondary commands dismiss the flyout.
/// Call `dismiss()` from a primary action when it should close the presentation.
public final class FluentCommandBarFlyout {
    public private(set) var primaryCommands: [FluentCommandBarItem]
    public private(set) var secondaryCommands: [FluentCommandBarItem]
    public private(set) var alwaysExpanded: Bool

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
            commands: Self.resolve(primary: primaryCommands, secondary: secondaryCommands),
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

    /// Updates both command groups together, including an already-open presentation. Incoming
    /// toggle values are authoritative. An empty configuration closes the current presentation.
    public func update(configuration: FluentCommandBarFlyoutConfiguration) {
        primaryCommands = configuration.primaryCommands
        secondaryCommands = configuration.secondaryCommands
        alwaysExpanded = configuration.alwaysExpanded
        presenter.update(commands: Self.resolve(primary: primaryCommands, secondary: secondaryCommands),
                         alwaysExpanded: alwaysExpanded)
    }

    private static func resolve(
        primary: [FluentCommandBarItem], secondary: [FluentCommandBarItem]
    ) -> [FluentTextCommand] {
        let identities = FluentCommandBarItemIdentity.resolve(primary: primary, secondary: secondary)
        return resolve(primary, identities: identities.primary, isPrimary: true)
            + resolve(secondary, identities: identities.secondary, isPrimary: false)
    }

    private static func resolve(
        _ items: [FluentCommandBarItem],
        identities: [FluentCommandBarItemIdentity],
        isPrimary: Bool
    ) -> [FluentTextCommand] {
        zip(items, identities).map { item, identity in
            FluentTextCommand(
                kind: .commandBar(identity),
                title: item.title,
                accelerator: item.accelerator,
                systemImageName: item.systemImageName,
                icon: item.icon,
                action: item.action,
                isPrimary: isPrimary,
                isEnabled: item.isEnabled,
                isChecked: item.isChecked,
                toggleAction: item.toggleAction,
                isSeparator: item.isSeparator,
                showsSecondaryIcon: !isPrimary && item.icon != nil
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
    case commandBar(FluentCommandBarItemIdentity)
}

struct FluentTextCommand {
    let kind: FluentTextCommandKind
    let title: String
    let accelerator: String
    let systemImageName: String?
    let icon: FluentIconSource?
    let action: () -> Void
    let isPrimary: Bool
    let isEnabled: Bool
    var isChecked: Bool
    let toggleAction: ((Bool) -> Void)?
    let isSeparator: Bool
    let showsSecondaryIcon: Bool

    init(
        kind: FluentTextCommandKind,
        title: String,
        accelerator: String,
        systemImageName: String?,
        icon: FluentIconSource? = nil,
        action: @escaping () -> Void,
        isPrimary: Bool,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        toggleAction: ((Bool) -> Void)? = nil,
        isSeparator: Bool = false,
        showsSecondaryIcon: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.accelerator = accelerator
        self.systemImageName = systemImageName
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.action = action
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.toggleAction = toggleAction
        self.isSeparator = isSeparator
        self.showsSecondaryIcon = showsSecondaryIcon
    }
}

/// The TextCommandBarFlyout surface used by TextBox-family controls. WinUI puts the direct
/// editing commands in a compact icon bar and keeps history/select-all commands in its overflow.
final class FluentTextCommandFlyout {
    private var commands: [FluentTextCommand]
    private let refreshCommands: (() -> [FluentTextCommand])?
    private var theme: FluentTheme
    private let reduceMotion: Bool
    private var alwaysExpanded: Bool
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
    private var screenObserver: FluentPopupScreenObserver?
    private var opensAbove = true

    var onDismiss: (() -> Void)?
    var isPresented: Bool { panel != nil }

    init(
        commands: [FluentTextCommand],
        theme: FluentTheme,
        reduceMotion: Bool,
        alwaysExpanded: Bool = false,
        presenterIdentifier: String = "FluentKit.TextCommandBarFlyout",
        presenterTitle: String = "Text commands",
        refreshCommands: (() -> [FluentTextCommand])? = nil
    ) {
        self.commands = commands
        self.refreshCommands = refreshCommands
        self.theme = theme
        self.reduceMotion = reduceMotion
        self.alwaysExpanded = alwaysExpanded
        self.presenterIdentifier = presenterIdentifier
        self.presenterTitle = presenterTitle
        animationCoordinator = FluentAnimationCoordinator(reduceMotion: reduceMotion)
    }

    func present(relativeTo anchor: NSView, at point: NSPoint) {
        dismiss(animated: false, notify: false)
        guard let parentWindow = anchor.window, commands.contains(where: { !$0.isSeparator }) else { return }
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
        let visibleFrame = FluentScreenPlacement.visibleFrame(at: anchorScreenPoint, fallback: parentWindow)
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
        commandView.onCommand = { [weak self, weak commandView] command in
            guard let self, let commandView, self.view === commandView, let panel = self.panel else { return }
            // WinUI consumes secondary commands, while primary commands remain usable. The
            // view guards synchronous reentry for both paths before dispatching user code.
            if !command.isPrimary { commandView.deactivate() }
            if let index = self.commands.firstIndex(where: { $0.kind == command.kind }) {
                self.commands[index] = command
            }
            if let toggleAction = command.toggleAction { toggleAction(command.isChecked) }
            else { command.action() }
            // A command may replace this presentation. Only its original panel may be closed.
            guard self.panel === panel else { return }
            if !command.isPrimary {
                self.dismiss(animated: false)
            } else if let refreshCommands = self.refreshCommands {
                let refreshed = refreshCommands()
                guard self.panel === panel, self.view === commandView else { return }
                self.update(commands: refreshed, alwaysExpanded: self.alwaysExpanded)
            }
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
        surface.configure(theme: theme, role: .transient, fallback: { $0.flyoutSurfaceFill })
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
        let shouldAnimate = !reduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        animationRoot.layer?.opacity = shouldAnimate ? 0 : 1
        CATransaction.commit()
        parentWindow.addChildWindow(popup, ordered: .above)
        popup.orderFront(nil)
        // A CAAnimation attached before a borderless child window is ordered never enters a live
        // render tree. Commit the transparent first frame, then start WinUI's faster opacity
        // storyboard on the next run-loop turn.
        if shouldAnimate, let animationLayer = animationRoot.layer {
            DispatchQueue.main.async { [weak self, weak popup, weak animationLayer] in
                guard let self,
                      self.panel === popup,
                      let animationLayer, animationLayer.opacity == 0 else { return }
                self.animationCoordinator.animateTransition(
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
        }
        installOutsideClickMonitor()
        screenObserver = FluentPopupScreenObserver(window: parentWindow) { [weak self, weak anchor] in
            guard let self, let view = self.view else { return }
            guard let anchor, let window = anchor.window, self.panel?.parent === window else {
                self.dismiss(animated: false)
                return
            }
            self.anchorScreenPoint = window.convertPoint(toScreen: anchor.convert(point, to: nil))
            self.resize(expanded: view.isExpanded, animated: false)
        }
    }

    func update(commands: [FluentTextCommand], alwaysExpanded: Bool) {
        self.commands = commands
        self.alwaysExpanded = alwaysExpanded
        // A secondary command has already consumed its presentation before its callback runs.
        // Save a callback's new configuration for next time without reviving that old surface.
        guard let view, let panel, view.isActive else { return }
        guard commands.contains(where: { !$0.isSeparator }) else {
            dismiss(animated: false)
            return
        }
        settlePresentationAnimations()
        view.update(commands: commands, alwaysExpanded: alwaysExpanded)
        guard self.panel === panel, self.view === view else { return }
        resize(expanded: view.isExpanded, animated: false)
    }

    func dismiss(animated: Bool, notify: Bool = true) {
        screenObserver = nil
        expansionGeneration += 1
        removeOutsideClickMonitor()
        view?.deactivate()
        if let rootLayer = animationRoot?.layer {
            var animatedLayers = [rootLayer]
            if let mask = rootLayer.mask { animatedLayers.append(mask) }
            animationCoordinator.cancelAll(on: animatedLayers)
        }
        guard let panel else { return }

        if animated, !reduceMotion, let rootLayer = animationRoot?.layer {
            animationCoordinator.animateTransition(
                [
                    FluentLayerAnimationChange(
                        layer: rootLayer,
                        key: "fluent.popup.textCommandBar.close.opacity",
                        keyPath: "opacity",
                        fromValue: rootLayer.presentation()?.opacity ?? rootLayer.opacity,
                        toValue: Float(0),
                        applyModelValue: { rootLayer.opacity = 0 }
                    )
                ],
                motion: FluentMotion.commandBarFlyoutOpen,
                animated: true
            ) { [weak self, weak panel] in
                guard let self, let panel, self.panel === panel else { return }
                self.finishDismissal(panel: panel, notify: notify)
            }
            return
        }
        finishDismissal(panel: panel, notify: notify)
    }

    private func finishDismissal(panel: NSPanel, notify: Bool) {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
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
        let visibleFrame = FluentScreenPlacement.visibleFrame(at: anchorScreenPoint, fallback: panel.parent)
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
                self?.settlePresentationAnimations()
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
        self.theme = theme
        panel?.appearance = fluentAppKitAppearance(for: theme)
        materialView?.configure(theme: theme, role: .transient, fallback: { $0.flyoutSurfaceFill })
        materialView?.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        animationRoot?.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        view?.update(theme: theme)
        if let view { resize(expanded: view.isExpanded, animated: false) }
        panel?.contentView?.needsDisplay = true
    }

    private func settlePresentationAnimations() {
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
    private var commands: [FluentTextCommand]
    private var theme: FluentTheme
    private var primaryViews: [NSView] = []
    private var primaryButtons: [FluentTextCommandButton] = []
    private var primaryIdentities: [FluentTextCommandKind] = []
    private var secondaryIdentities: [FluentTextCommandKind] = []
    private var moreButton: FluentTextCommandButton?
    private var alwaysExpanded: Bool
    private(set) var isActive = true
    private var isInvokingCommand = false
    private var secondaryViews: [NSView] = []
    private var secondaryRows: [FluentTextCommandRow] = []
    private let hoverCoordinator = FluentHoverCoordinator<FluentTextCommandControl> { control, hovering in
        control.setPointerHover(hovering)
    }
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
        self.alwaysExpanded = alwaysExpanded
        let primary = commands.filter(\.isPrimary)
        let secondary = commands.filter { !$0.isPrimary }
        let hasPrimaryCommands = primary.contains { !$0.isSeparator }
        let hasSecondaryCommands = secondary.contains { !$0.isSeparator }
        isExpanded = alwaysExpanded || (!hasPrimaryCommands && hasSecondaryCommands)
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier(presenterIdentifier)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityTitle(presenterTitle)
        rebuildPrimaryViews()
        rebuildSecondaryRows()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rebuildPrimaryViews() {
        let oldViews = primaryViews
        let candidates = Dictionary(uniqueKeysWithValues: zip(primaryIdentities, oldViews))
        let primary = commands.filter(\.isPrimary)
        primaryIdentities = primary.map(\.kind)
        primaryViews = primary.map { command in
            let candidate = candidates[command.kind]
            if command.isSeparator {
                return (candidate as? FluentCommandBarSeparatorView)
                    ?? FluentCommandBarSeparatorView(theme: theme, orientation: .vertical)
            }
            let button = (candidate as? FluentTextCommandButton)
                ?? FluentTextCommandButton(command: command, theme: theme, showsIcon: true)
            button.hoverCoordinator = hoverCoordinator
            button.update(command: command)
            return button
        }
        primaryButtons = primaryViews.compactMap { $0 as? FluentTextCommandButton }
        for old in oldViews where !primaryViews.contains(where: { $0 === old }) {
            if let button = old as? FluentTextCommandButton {
                button.onInvoke = nil
                button.isEnabled = false
            }
            old.removeFromSuperview()
        }
        for view in primaryViews where view.superview !== self { addSubview(view) }
        primaryButtons.forEach { button in
            button.onInvoke = { [weak self, weak button] in
                guard let self, let button else { return false }
                return self.invoke(kind: button.command.kind)
            }
        }
        let needsMore = !alwaysExpanded && !primaryButtons.isEmpty
            && commands.contains { !$0.isPrimary && !$0.isSeparator }
        if needsMore {
            let moreButton = moreButton ?? FluentTextCommandButton(
                title: "More", accelerator: "", systemImageName: "ellipsis", theme: theme)
            self.moreButton = moreButton
            moreButton.hoverCoordinator = hoverCoordinator
            moreButton.onInvoke = { [weak self] in
                guard let self, self.isActive, !self.isInvokingCommand else { return false }
                self.isExpanded.toggle()
                self.rebuildSecondaryRows()
                self.onExpandedChange?(self.isExpanded)
                self.needsLayout = true
                self.setAccessibilityChildren(self.accessibilityElements)
                return true
            }
            if moreButton.superview !== self { addSubview(moreButton) }
        } else {
            moreButton?.onInvoke = nil
            moreButton?.isEnabled = false
            moreButton?.removeFromSuperview()
            moreButton = nil
        }
    }

    private func invoke(kind: FluentTextCommandKind) -> Bool {
        guard isActive, !isInvokingCommand, let onCommand,
              let index = commands.firstIndex(where: { $0.kind == kind }),
              commands[index].isEnabled, !commands[index].isSeparator else { return false }
        isInvokingCommand = true
        defer { isInvokingCommand = false }
        if commands[index].toggleAction != nil {
            commands[index].isChecked.toggle()
            let updated = commands[index]
            primaryButtons.filter { $0.command.kind == kind }.forEach { $0.update(command: updated) }
            secondaryRows.filter { $0.command.kind == kind }.forEach { $0.update(command: updated) }
        }
        onCommand(commands[index])
        return true
    }

    func update(commands: [FluentTextCommand], alwaysExpanded: Bool) {
        guard isActive else { return }
        let focusedControl = window?.firstResponder as? NSView
        let focusedKind = (focusedControl as? FluentTextCommandButton)?.command.kind
            ?? (focusedControl as? FluentTextCommandRow)?.command.kind
        let ownedFocus = focusedControl?.superview === self
        self.commands = commands
        self.alwaysExpanded = alwaysExpanded
        let hasPrimary = commands.contains { $0.isPrimary && !$0.isSeparator }
        let hasSecondary = commands.contains { !$0.isPrimary && !$0.isSeparator }
        if !hasPrimary { isExpanded = hasSecondary }
        else if !hasSecondary { isExpanded = false }
        else if alwaysExpanded { isExpanded = true }
        rebuildPrimaryViews()
        rebuildSecondaryRows()
        if ownedFocus, let focusedControl,
           focusedControl.superview !== self || (focusedControl as? NSControl)?.isEnabled == false {
            var candidates: [NSButton] = primaryButtons
            if let moreButton { candidates.append(moreButton) }
            candidates.append(contentsOf: secondaryRows)
            let matching = candidates.first { button in
                button.isEnabled && focusedKind != nil
                    && ((button as? FluentTextCommandButton)?.command.kind
                        ?? (button as? FluentTextCommandRow)?.command.kind) == focusedKind
            }
            let replacement = matching ?? candidates.first(where: \.isEnabled)
            _ = window?.makeFirstResponder(replacement ?? self)
        }
        needsLayout = true
        needsDisplay = true
    }

    func deactivate() {
        isActive = false
        hoverCoordinator.reset()
        onCommand = nil
        onExpandedChange = nil
        onDismiss = nil
        for button in primaryButtons {
            button.onInvoke = nil
            button.isEnabled = false
        }
        moreButton?.onInvoke = nil
        moreButton?.isEnabled = false
        retireSecondaryRows()
    }

    private func retireSecondaryRows() {
        for row in secondaryRows {
            row.onInvoke = nil
            row.isEnabled = false
        }
    }

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
        // The popup host owns the fill. Keeping this view transparent preserves the configured
        // transient material; the opaque fallback is supplied by FluentMaterialView
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
        let oldViews = secondaryViews
        let candidates = Dictionary(uniqueKeysWithValues: zip(secondaryIdentities, oldViews))
        secondaryViews.removeAll()
        secondaryRows.removeAll()
        let secondary = isExpanded ? commands.filter { !$0.isPrimary } : []
        secondaryIdentities = secondary.map(\.kind)
        let reservesToggleSlot = secondary.contains { !$0.isSeparator && ($0.toggleAction != nil || $0.isChecked) }
        let reservesIconSlot = secondary.contains { !$0.isSeparator && $0.showsSecondaryIcon }
        for command in secondary {
            let candidate = candidates[command.kind]
            if command.isSeparator {
                let separator = (candidate as? FluentCommandBarSeparatorView)
                    ?? FluentCommandBarSeparatorView(theme: theme, orientation: .horizontal)
                secondaryViews.append(separator)
                if separator.superview !== self { addSubview(separator) }
                continue
            }
            let row = (candidate as? FluentTextCommandRow) ?? FluentTextCommandRow(
                command: command,
                theme: theme,
                reservesToggleSlot: reservesToggleSlot,
                reservesIconSlot: reservesIconSlot
            )
            row.hoverCoordinator = hoverCoordinator
            row.update(command: command, reservesToggleSlot: reservesToggleSlot, reservesIconSlot: reservesIconSlot)
            row.onInvoke = { [weak self, weak row] in
                guard let self, let row else { return false }
                return self.invoke(kind: row.command.kind)
            }
            secondaryRows.append(row)
            secondaryViews.append(row)
            if row.superview !== self { addSubview(row) }
        }
        for old in oldViews where !secondaryViews.contains(where: { $0 === old }) {
            if let row = old as? FluentTextCommandRow {
                row.onInvoke = nil
                row.isEnabled = false
            }
            old.removeFromSuperview()
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
        let reservesToggleSlot = secondary.contains { !$0.isSeparator && ($0.toggleAction != nil || $0.isChecked) }
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

/// Primary buttons, More and overflow rows share hover ownership. Native tracking can omit
/// an exit when a row moves, disappears or its window deactivates.
private class FluentTextCommandControl: NSButton {
    weak var hoverCoordinator: FluentHoverCoordinator<FluentTextCommandControl>?
    private(set) var isPointerOver = false
    private lazy var pointerLifetime = FluentPointerLifetime { [weak self] in self?.updatePointerHover(false) }
    private lazy var trackingHost = FluentTrackingAreaHost(
        view: self, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect])

    override var isEnabled: Bool {
        didSet { if !isEnabled { updatePointerHover(false) } }
    }

    override var frame: NSRect {
        didSet { if oldValue != frame { updatePointerHover(false) } }
    }

    func setPointerHover(_ value: Bool) {
        let next = value && isEnabled && !isHiddenOrHasHiddenAncestor && window?.isVisible == true
        if isPointerOver != next { isPointerOver = next; needsDisplay = true }
        if next { pointerLifetime.observe(window) }
        else { pointerLifetime.invalidate() }
    }

    private func updatePointerHover(_ value: Bool) {
        // Disabled commands still take ownership to clear a sibling whose exit was missed.
        if let hoverCoordinator { hoverCoordinator.update(self, hovering: value) }
        else { setPointerHover(value) }
    }

    override func mouseEntered(with event: NSEvent) { updatePointerHover(true) }
    override func mouseExited(with event: NSEvent) { updatePointerHover(false) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingHost.update()
        if isPointerOver {
            let point = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
            if isHiddenOrHasHiddenAncestor || point.map({ !visibleRect.contains($0) }) != false {
                updatePointerHover(false)
            }
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        updatePointerHover(false)
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { updatePointerHover(false) }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { updatePointerHover(false) }
        super.viewWillMove(toWindow: newWindow)
    }
}

private final class FluentTextCommandButton: FluentTextCommandControl {
    private(set) var command: FluentTextCommand
    var theme: FluentTheme { didSet { updateImage(); needsDisplay = true } }
    var onInvoke: (() -> Bool)?

    init(command: FluentTextCommand, theme: FluentTheme, showsIcon: Bool) {
        self.command = command
        self.theme = theme
        super.init(frame: .zero)
        configure(title: command.title, accelerator: command.accelerator, systemImageName: showsIcon ? command.systemImageName : nil)
        update(command: command)
    }

    init(title: String, accelerator: String, systemImageName: String, theme: FluentTheme) {
        command = FluentTextCommand(kind: .selectAll, title: title, accelerator: accelerator, systemImageName: systemImageName, action: {}, isPrimary: false)
        self.theme = theme
        super.init(frame: .zero)
        configure(title: title, accelerator: accelerator, systemImageName: systemImageName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(command: FluentTextCommand) {
        self.command = command
        isEnabled = command.isEnabled
        setAccessibilityTitle(command.title)
        setAccessibilityValue(command.toggleAction != nil ? (command.isChecked ? "On" : "Off") : nil)
        setAccessibilityHelp(command.accelerator.isEmpty ? nil : "Keyboard shortcut \(command.accelerator)")
        toolTip = command.title
        updateImage()
        needsDisplay = true
    }

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
        return onInvoke?() ?? false
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

    @objc private func invoke() { _ = onInvoke?() }

    private func updateImage() { updateImage(systemImageName: command.systemImageName) }

    private func updateImage(systemImageName: String?) {
        image = command.icon?.image(pointSize: 17, color: theme.textPrimary, layoutDirection: userInterfaceLayoutDirection)
        image?.isTemplate = command.icon?.tint == .template
    }

    private var resolvedVisualState: FluentControlState {
        guard isEnabled else { return .disabled }
        if isHighlighted { return .pressed }
        if isPointerOver { return .pointerOver }
        return .normal
    }
}

private final class FluentTextCommandRow: FluentTextCommandControl {
    private(set) var command: FluentTextCommand
    var theme: FluentTheme { didSet { needsDisplay = true } }
    var onInvoke: (() -> Bool)?
    private var reservesToggleSlot: Bool
    private var reservesIconSlot: Bool

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
        update(command: command)
        target = self
        action = #selector(invoke)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(command: FluentTextCommand, reservesToggleSlot: Bool? = nil, reservesIconSlot: Bool? = nil) {
        self.command = command
        if let reservesToggleSlot { self.reservesToggleSlot = reservesToggleSlot }
        if let reservesIconSlot { self.reservesIconSlot = reservesIconSlot }
        isEnabled = command.isEnabled
        setAccessibilityTitle(command.title)
        setAccessibilityValue(command.toggleAction != nil ? (command.isChecked ? "On" : "Off") : nil)
        setAccessibilityHelp(command.accelerator.isEmpty ? nil : "Keyboard shortcut \(command.accelerator)")
        needsDisplay = true
    }

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
                let down: CGFloat = isFlipped ? 1 : -1
                check.move(to: NSPoint(x: 13, y: bounds.midY))
                check.line(to: NSPoint(x: 17, y: bounds.midY + 4 * down))
                check.line(to: NSPoint(x: 24, y: bounds.midY - 4 * down))
                check.lineWidth = 1.7
                check.lineCapStyle = .round
                foreground.setStroke()
                check.stroke()
            }
            titleX += 28
        }
        if reservesIconSlot {
            if command.showsSecondaryIcon {
                command.icon?.draw(in: NSRect(x: titleX, y: bounds.midY - 8, width: 16, height: 16),
                                   color: foreground, layoutDirection: userInterfaceLayoutDirection)
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
        return onInvoke?() ?? false
    }

    @objc private func invoke() { _ = onInvoke?() }

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
