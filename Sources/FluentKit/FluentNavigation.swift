import AppKit

public struct FluentTabItem {
    public let title: String
    public let content: FluentAnyView

    public init<V: FluentView>(_ title: String, @FluentViewBuilder content: () -> V) {
        self.title = title
        self.content = FluentAnyView(content())
    }
}

public struct FluentTabView: FluentUpdatablePrimitiveView {
    public let items: [FluentTabItem]
    public let selectedIndex: FluentBinding<Int>?

    public init(items: [FluentTabItem], selectedIndex: FluentBinding<Int>? = nil) {
        self.items = items
        self.selectedIndex = selectedIndex
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentTabContainer(items: items, binding: selectedIndex, theme: context.theme, context: context)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let tabs = view as? FluentTabContainer else { return false }
        tabs.update(items: items, binding: selectedIndex, theme: context.theme, context: context)
        return true
    }
}

private final class FluentTabContainer: NSView {
    private var items: [FluentTabItem]
    private var binding: FluentBinding<Int>?
    private var theme: FluentTheme
    private var context: FluentRenderContext
    private let tabBar = NSTabView()
    private var tabs: [NSTabViewItem] = []
    private var observerID: UUID?

    init(items: [FluentTabItem], binding: FluentBinding<Int>?, theme: FluentTheme, context: FluentRenderContext) {
        self.items = items
        self.binding = binding
        self.theme = theme
        self.context = context
        super.init(frame: .zero)
        tabBar.tabViewType = .topTabsBezelBorder
        tabBar.drawsBackground = false
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        tabs = items.map { item in
            let tab = NSTabViewItem(identifier: item.title)
            tab.label = item.title
            let host = FluentViewHost(item.content, context: context)
            tab.view = host
            return tab
        }
        tabs.forEach(tabBar.addTabViewItem)
        let initial = min(max(binding?.get() ?? 0, 0), max(items.count - 1, 0))
        if !tabs.isEmpty { tabBar.selectTabViewItem(at: initial) }
        installBindingObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(items: [FluentTabItem], binding: FluentBinding<Int>?, theme: FluentTheme, context: FluentRenderContext) {
        if let observerID { self.binding?.removeObserver?(observerID) }
        self.binding = binding
        self.theme = theme
        self.context = context
        installBindingObserver()
        guard items.count == tabs.count else {
            self.items = items
            tabs.forEach { tabBar.removeTabViewItem($0) }
            tabs = items.map { item in
                let tab = NSTabViewItem(identifier: item.title)
                tab.label = item.title
                tab.view = FluentViewHost(item.content, context: context)
                return tab
            }
            tabs.forEach(tabBar.addTabViewItem)
            if !tabs.isEmpty { tabBar.selectTabViewItem(at: min(max(binding?.get() ?? 0, 0), tabs.count - 1)) }
            return
        }

        self.items = items
        for index in items.indices {
            tabs[index].label = items[index].title
            guard let host = tabs[index].view as? FluentViewHost<FluentAnyView> else { continue }
            host.context = context
            host.update(items[index].content)
        }
        if let selected = binding?.get(), selected >= 0, selected < tabs.count, tabBar.selectedTabViewItem != tabs[selected] {
            tabBar.selectTabViewItem(at: selected)
        }
    }

    private func installBindingObserver() {
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async {
                guard let self, value >= 0, value < self.tabs.count else { return }
                if self.tabBar.selectedTabViewItem != self.tabs[value] {
                    self.tabBar.selectTabViewItem(at: value)
                }
            }
        }
    }

    deinit {
        if let observerID { binding?.removeObserver?(observerID) }
    }
}

extension FluentTabContainer: NSTabViewDelegate {
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabViewItem, let index = tabs.firstIndex(of: tabViewItem) else { return }
        binding?.set(index)
    }
}

public struct FluentSplitView<Sidebar: FluentView, Detail: FluentView>: FluentPrimitiveView {
    private let sidebar: Sidebar
    private let detail: Detail
    private let sidebarWidth: CGFloat

    public init(sidebarWidth: CGFloat = 240, @FluentViewBuilder sidebar: () -> Sidebar, @FluentViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.detail = detail()
        self.sidebarWidth = sidebarWidth
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        let sidebarHost = FluentViewHost(sidebar, context: context)
        let detailHost = FluentViewHost(detail, context: context)
        split.addArrangedSubview(sidebarHost)
        split.addArrangedSubview(detailHost)
        sidebarHost.widthAnchor.constraint(equalToConstant: sidebarWidth).isActive = true
        return split
    }
}
