import AppKit

/// A toolbar item whose content is rendered by FluentKit and hosted by NSToolbar.
public struct FluentToolbarItem {
    fileprivate let identifier: String
    fileprivate let label: String
    fileprivate let paletteLabel: String
    fileprivate let toolTip: String?
    fileprivate let systemIdentifier: NSToolbarItem.Identifier?
    fileprivate let content: FluentAnyView?

    public init<V: FluentView>(
        _ identifier: String,
        label: String,
        paletteLabel: String? = nil,
        toolTip: String? = nil,
        @FluentViewBuilder content: () -> V
    ) {
        self.identifier = identifier
        self.label = label
        self.paletteLabel = paletteLabel ?? label
        self.toolTip = toolTip
        systemIdentifier = nil
        self.content = FluentAnyView(content())
    }

    private init(systemIdentifier: NSToolbarItem.Identifier) {
        identifier = systemIdentifier.rawValue
        label = ""
        paletteLabel = ""
        toolTip = nil
        self.systemIdentifier = systemIdentifier
        content = nil
    }

    public static var separator: FluentToolbarItem {
        FluentToolbarItem(systemIdentifier: NSToolbarItem.Identifier(rawValue: "NSToolbarSeparatorItemIdentifier"))
    }

    public static var space: FluentToolbarItem {
        FluentToolbarItem(systemIdentifier: NSToolbarItem.Identifier(rawValue: "NSToolbarSpaceItemIdentifier"))
    }

    public static var flexibleSpace: FluentToolbarItem {
        FluentToolbarItem(systemIdentifier: NSToolbarItem.Identifier(rawValue: "NSToolbarFlexibleSpaceItemIdentifier"))
    }
}

@resultBuilder
public enum FluentToolbarBuilder {
    public static func buildBlock(_ items: FluentToolbarItem...) -> [FluentToolbarItem] { items }
    public static func buildOptional(_ component: [FluentToolbarItem]?) -> [FluentToolbarItem] { component ?? [] }
    public static func buildEither(first component: [FluentToolbarItem]) -> [FluentToolbarItem] { component }
    public static func buildEither(second component: [FluentToolbarItem]) -> [FluentToolbarItem] { component }
    public static func buildArray(_ components: [[FluentToolbarItem]]) -> [FluentToolbarItem] { components.flatMap { $0 } }
}

public struct FluentToolbarView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let items: [FluentToolbarItem]

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentToolbarHost(content: content._mount(in: context), items: items, context: context)
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentToolbarHost else { return false }
        host.update(items: items, context: context)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentToolbarHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    private var coordinator: FluentToolbarCoordinator

    init(content: NSView, items: [FluentToolbarItem], context: FluentRenderContext) {
        coordinator = FluentToolbarCoordinator(items: items, context: context)
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
        coordinator.attach(to: window)
    }

    func update(items: [FluentToolbarItem], context: FluentRenderContext) {
        coordinator.update(items: items, context: context)
    }

    deinit { coordinator.detach() }
}

private final class FluentToolbarCoordinator: NSObject, NSToolbarDelegate {
    private var items: [FluentToolbarItem]
    private var context: FluentRenderContext
    private var toolbar: NSToolbar?
    private weak var window: NSWindow?
    private var previousToolbar: NSToolbar?
    private var previousToolbarStyle: NSWindow.ToolbarStyle?
    private var itemHosts: [NSToolbarItem.Identifier: FluentViewHost<FluentAnyView>] = [:]
    private var renderedIdentifiers: [NSToolbarItem.Identifier] = []

    init(items: [FluentToolbarItem], context: FluentRenderContext) {
        self.items = items
        self.context = context
        super.init()
    }

    func attach(to window: NSWindow?) {
        guard let window else {
            detach()
            return
        }
        guard self.window !== window || toolbar == nil else { return }
        detach()
        self.window = window
        previousToolbar = window.toolbar
        previousToolbarStyle = window.toolbarStyle
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("FluentKit.toolbar.\(ObjectIdentifier(self).hashValue)"))
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        self.toolbar = toolbar
        window.toolbarStyle = .unified
        window.toolbar = toolbar
        rebuildToolbar()
    }

    func detach() {
        guard let window else { return }
        if window.toolbar === toolbar { window.toolbar = previousToolbar }
        if let previousToolbarStyle { window.toolbarStyle = previousToolbarStyle }
        toolbar?.delegate = nil
        toolbar = nil
        self.window = nil
        previousToolbar = nil
        previousToolbarStyle = nil
        itemHosts.removeAll()
        renderedIdentifiers.removeAll()
    }

    func update(items: [FluentToolbarItem], context: FluentRenderContext) {
        self.items = items
        self.context = context
        for item in items {
            guard item.systemIdentifier == nil, let content = item.content else { continue }
            let id = toolbarIdentifier(for: item)
            if let host = itemHosts[id] {
                host.context = context
                host.update(content)
            } else {
                itemHosts[id] = FluentViewHost(content, context: context)
            }
        }
        let identifiers = items.map(toolbarIdentifier(for:))
        if identifiers != renderedIdentifiers {
            rebuildToolbar()
        } else {
            updateVisibleItems()
        }
    }

    private func rebuildToolbar() {
        guard let toolbar else { return }
        while !toolbar.items.isEmpty {
            toolbar.removeItem(at: toolbar.items.count - 1)
        }
        let identifiers = items.map(toolbarIdentifier(for:))
        for (index, identifier) in identifiers.enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
        renderedIdentifiers = identifiers
        updateVisibleItems()
        toolbar.validateVisibleItems()
    }

    private func updateVisibleItems() {
        guard let toolbar else { return }
        for toolbarItem in toolbar.items {
            guard let item = items.first(where: { toolbarIdentifier(for: $0) == toolbarItem.itemIdentifier }),
                  item.systemIdentifier == nil else { continue }
            toolbarItem.label = item.label
            toolbarItem.paletteLabel = item.paletteLabel
            toolbarItem.toolTip = item.toolTip
            guard let host = itemHosts[toolbarItem.itemIdentifier] else { continue }
            let size = host.fittingSize
            host.frame = NSRect(
                origin: .zero,
                size: NSSize(width: max(size.width, 1), height: max(size.height, 1))
            )
            toolbarItem.view = host
        }
    }

    private func toolbarIdentifier(for item: FluentToolbarItem) -> NSToolbarItem.Identifier {
        item.systemIdentifier ?? NSToolbarItem.Identifier("FluentKit.item.\(item.identifier)")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items.map(toolbarIdentifier(for:)) + [
            NSToolbarItem.Identifier(rawValue: "NSToolbarSeparatorItemIdentifier"),
            NSToolbarItem.Identifier(rawValue: "NSToolbarSpaceItemIdentifier"),
            NSToolbarItem.Identifier(rawValue: "NSToolbarFlexibleSpaceItemIdentifier")
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items.map(toolbarIdentifier(for:)
        )
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let item = items.first(where: { toolbarIdentifier(for: $0) == itemIdentifier }) else { return nil }
        if let systemIdentifier = item.systemIdentifier {
            return NSToolbarItem(itemIdentifier: systemIdentifier)
        }
        guard let content = item.content else { return nil }
        let host: FluentViewHost<FluentAnyView>
        if let existing = itemHosts[itemIdentifier] {
            host = existing
        } else {
            host = FluentViewHost(content, context: context)
            itemHosts[itemIdentifier] = host
        }
        let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
        toolbarItem.label = item.label
        toolbarItem.paletteLabel = item.paletteLabel
        toolbarItem.toolTip = item.toolTip
        let size = host.fittingSize
        host.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(size.width, 1), height: max(size.height, 1))
        )
        toolbarItem.view = host
        return toolbarItem
    }
}

public extension FluentView {
    /// Installs a native NSToolbar on the containing window. Toolbar item content remains
    /// declarative and participates in the same state dependency tracking as the main view.
    func toolbar(@FluentToolbarBuilder _ items: () -> [FluentToolbarItem]) -> FluentToolbarView<Self> {
        FluentToolbarView(content: self, items: items())
    }
}
