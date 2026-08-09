import AppKit

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
