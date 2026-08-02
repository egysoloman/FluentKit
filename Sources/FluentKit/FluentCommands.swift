import AppKit

/// A keyboard command that can be installed on a declarative view subtree.
/// Commands are handled by the native responder chain, so they remain scoped to the
/// window containing the view and do not require a global event monitor.
public struct FluentCommand {
    public let title: String
    public let keyEquivalent: String
    public let modifiers: NSEvent.ModifierFlags
    public let isEnabled: () -> Bool
    public let action: () -> Void

    public init(
        _ title: String,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        isEnabled: @escaping () -> Bool = { true },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// A named group of commands that can be composed before being attached to a view.
public struct FluentCommandGroup {
    public let title: String
    public let commands: [FluentCommand]

    public init(_ title: String, @FluentCommandBuilder commands: () -> [FluentCommand]) {
        self.title = title
        self.commands = commands()
    }
}

/// Optional application-level command provider. Apps can expose command groups without changing
/// their scene declarations; FluentKit installs them into the native macOS main menu.
public protocol FluentApplicationCommands {
    var applicationCommandGroups: [FluentCommandGroup] { get }
}

public extension FluentApplicationCommands {
    var applicationCommandGroups: [FluentCommandGroup] { [] }
}

@resultBuilder
public enum FluentCommandGroupBuilder {
    public static func buildBlock(_ groups: FluentCommandGroup...) -> [FluentCommandGroup] { groups }
    public static func buildOptional(_ component: [FluentCommandGroup]?) -> [FluentCommandGroup] { component ?? [] }
    public static func buildEither(first component: [FluentCommandGroup]) -> [FluentCommandGroup] { component }
    public static func buildEither(second component: [FluentCommandGroup]) -> [FluentCommandGroup] { component }
    public static func buildArray(_ components: [[FluentCommandGroup]]) -> [FluentCommandGroup] { components.flatMap { $0 } }
}

@resultBuilder
public enum FluentCommandBuilder {
    public static func buildBlock(_ commands: FluentCommand...) -> [FluentCommand] { commands }
    public static func buildOptional(_ component: [FluentCommand]?) -> [FluentCommand] { component ?? [] }
    public static func buildEither(first component: [FluentCommand]) -> [FluentCommand] { component }
    public static func buildEither(second component: [FluentCommand]) -> [FluentCommand] { component }
    public static func buildArray(_ components: [[FluentCommand]]) -> [FluentCommand] { components.flatMap { $0 } }
}

public struct FluentCommandsView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let commands: [FluentCommand]

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentCommandHost(content: content._mount(in: context), commands: commands)
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentCommandHost else { return false }
        host.commands = commands
        return host.updateContent?(host.contentView, context) ?? false
    }
}

/// Owns the native application menu generated from declarative command groups. The coordinator
/// keeps menu targets alive, rebuilds structure when groups change, and validates enabled state
/// immediately before the menu opens or a key equivalent is dispatched.
public final class FluentMainMenuCoordinator: NSObject, NSMenuDelegate, NSMenuItemValidation {
    public private(set) var menu: NSMenu
    public private(set) var servicesMenu: NSMenu
    public let applicationName: String

    private var groups: [FluentCommandGroup]
    private let settingsAction: (() -> Void)?
    private weak var installedApplication: NSApplication?
    private var commandByID: [UUID: FluentCommand] = [:]
    private var itemIDs: [ObjectIdentifier: UUID] = [:]

    public init(
        applicationName: String = ProcessInfo.processInfo.processName,
        groups: [FluentCommandGroup] = [],
        settingsAction: (() -> Void)? = nil
    ) {
        self.applicationName = applicationName
        self.groups = groups
        self.settingsAction = settingsAction
        menu = NSMenu(title: applicationName)
        servicesMenu = NSMenu(title: "Services")
        super.init()
        rebuild()
    }

    /// Replaces the declarative command groups and rebuilds the native menu tree.
    public func update(groups: [FluentCommandGroup]) {
        self.groups = groups
        rebuild()
    }

    /// Installs the generated menu as an application's main menu.
    public func install(on application: NSApplication = .shared) {
        application.mainMenu = menu
        application.servicesMenu = servicesMenu
        installedApplication = application
        validateAllItems()
    }

    /// Invokes a menu item owned by this coordinator. This is useful for deterministic tests and
    /// for integrations that need to trigger a command without synthesizing an NSEvent.
    @discardableResult
    public func perform(_ item: NSMenuItem) -> Bool {
        guard item.target === self,
              let id = itemIDs[ObjectIdentifier(item)],
              let command = commandByID[id],
              command.isEnabled(),
              let action = item.action,
              responds(to: action) else { return false }
        invoke(item)
        return true
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        validateAllItems(in: menu)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = itemIDs[ObjectIdentifier(menuItem)],
              let command = commandByID[id] else { return true }
        return command.isEnabled()
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard let id = itemIDs[ObjectIdentifier(sender)],
              let command = commandByID[id],
              command.isEnabled() else { return }
        command.action()
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsAction?()
    }

    private func rebuild() {
        commandByID.removeAll(keepingCapacity: true)
        itemIDs.removeAll(keepingCapacity: true)
        servicesMenu = NSMenu(title: "Services")
        let nextMenu = NSMenu(title: applicationName)
        nextMenu.autoenablesItems = true
        nextMenu.delegate = self

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: applicationName)
        appMenu.autoenablesItems = false
        appMenu.addItem(withTitle: "About \(applicationName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        if settingsAction != nil {
            let settingsItem = NSMenuItem(
                title: "Settings...",
                action: #selector(openSettings(_:)),
                keyEquivalent: ","
            )
            settingsItem.target = self
            appMenu.addItem(settingsItem)
        }
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(applicationName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(applicationName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        nextMenu.addItem(appItem)

        addStandardMenu(
            title: "File",
            items: [
                standardItem("New", action: #selector(NSDocumentController.newDocument(_:)), key: "n"),
                standardItem("Open...", action: #selector(NSDocumentController.openDocument(_:)), key: "o"),
                .separator(),
                standardItem("Close Window", action: #selector(NSWindow.performClose(_:)), key: "w")
            ],
            to: nextMenu
        )
        addStandardMenu(
            title: "Edit",
            items: [
                standardItem("Undo", action: Selector(("undo:")), key: "z"),
                standardItem("Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
                .separator(),
                standardItem("Cut", action: #selector(NSText.cut(_:)), key: "x"),
                standardItem("Copy", action: #selector(NSText.copy(_:)), key: "c"),
                standardItem("Paste", action: #selector(NSText.paste(_:)), key: "v"),
                standardItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a")
            ],
            to: nextMenu
        )
        addStandardMenu(
            title: "View",
            items: [
                standardItem("Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control])
            ],
            to: nextMenu
        )
        addStandardMenu(
            title: "Window",
            items: [
                standardItem("Close Window", action: #selector(NSWindow.performClose(_:)), key: "w"),
                .separator(),
                standardItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"),
                standardItem("Zoom", action: #selector(NSWindow.performZoom(_:)), key: ""),
                .separator(),
                standardItem("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), key: "")
            ],
            to: nextMenu
        )
        addStandardMenu(
            title: "Help",
            items: [
                standardItem("\(applicationName) Help", action: #selector(NSApplication.showHelp(_:)), key: "?")
            ],
            to: nextMenu
        )

        for group in groups {
            let groupMenu: NSMenu
            if let standardMenu = nextMenu.items.first(where: { $0.submenu?.title == group.title })?.submenu {
                groupMenu = standardMenu
                if !groupMenu.items.isEmpty, !group.commands.isEmpty { groupMenu.addItem(.separator()) }
            } else {
                let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                groupMenu = NSMenu(title: group.title)
                groupItem.submenu = groupMenu
                nextMenu.addItem(groupItem)
            }
            groupMenu.delegate = self
            for command in group.commands {
                let id = UUID()
                commandByID[id] = command
                let item = NSMenuItem(title: command.title, action: #selector(invoke(_:)), keyEquivalent: command.keyEquivalent)
                item.target = self
                item.keyEquivalentModifierMask = command.modifiers.nsMenuModifierMask
                itemIDs[ObjectIdentifier(item)] = id
                item.isEnabled = command.isEnabled()
                groupMenu.addItem(item)
            }
        }

        menu = nextMenu
        if let installedApplication {
            installedApplication.mainMenu = nextMenu
            installedApplication.servicesMenu = servicesMenu
        }
    }

    private func addStandardMenu(title: String, items: [NSMenuItem], to menu: NSMenu) {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = true
        items.forEach(submenu.addItem)
        menuItem.submenu = submenu
        menu.addItem(menuItem)
    }

    private func standardItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers.nsMenuModifierMask
        item.target = nil
        return item
    }

    private func validateAllItems(in menu: NSMenu? = nil) {
        let targetMenu = menu ?? self.menu
        for item in targetMenu.items {
            if let id = itemIDs[ObjectIdentifier(item)], let command = commandByID[id] {
                item.isEnabled = command.isEnabled()
            }
            if let submenu = item.submenu { validateAllItems(in: submenu) }
        }
    }
}

private extension NSEvent.ModifierFlags {
    var nsMenuModifierMask: NSEvent.ModifierFlags {
        intersection([.command, .option, .control, .shift])
    }
}

private final class FluentCommandHost: NSView {
    var commands: [FluentCommand]
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    init(content: NSView, commands: [FluentCommand]) {
        self.commands = commands
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return super.performKeyEquivalent(with: event)
        }

        let eventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        for command in commands where command.isEnabled() {
            let commandModifiers = command.modifiers.intersection([.command, .option, .control, .shift])
            guard eventModifiers == commandModifiers else { continue }
            guard characters.caseInsensitiveCompare(command.keyEquivalent) == .orderedSame else { continue }
            command.action()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

public extension FluentView {
    /// Installs keyboard commands for this view subtree. The commands are evaluated on each
    /// render, which keeps enabled state and captured application state current.
    func fluentCommands(@FluentCommandBuilder _ commands: () -> [FluentCommand]) -> FluentCommandsView<Self> {
        FluentCommandsView(content: self, commands: commands())
    }

    func fluentCommands(_ groups: [FluentCommandGroup]) -> FluentCommandsView<Self> {
        FluentCommandsView(content: self, commands: groups.flatMap(\.commands))
    }

    func fluentCommandGroups(@FluentCommandGroupBuilder _ groups: () -> [FluentCommandGroup]) -> FluentCommandsView<Self> {
        FluentCommandsView(content: self, commands: groups().flatMap(\.commands))
    }
}
