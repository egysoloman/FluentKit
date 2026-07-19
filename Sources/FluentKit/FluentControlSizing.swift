import AppKit

public struct FluentControlSizeView<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let size: FluentControlSize

    fileprivate init(content: Content, size: FluentControlSize) {
        self.content = content
        self.size = size
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentControlSizeHost(content: content._mount(in: context), size: size)
        host.updateContent = { [content] native, updateContext in content._update(native, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentControlSizeHost else { return false }
        guard host.updateContent?(host.contentView, context) ?? false else { return false }
        host.update(size: size)
        return true
    }
}

private final class FluentControlSizeHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    init(content: NSView, size: FluentControlSize) {
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        apply(size, to: content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(size: FluentControlSize) {
        apply(size, to: contentView)
        invalidateIntrinsicContentSize()
    }

    private func apply(_ size: FluentControlSize, to view: NSView) {
        if let configurable = view as? FluentControlSizeConfigurable {
            configurable.fluentControlSize = size
        } else if let control = view as? NSControl {
            control.controlSize = size.appKitSize
            if let text = control as? NSTextField { text.font = .systemFont(ofSize: size.fontSize) }
            if let button = control as? NSButton { button.font = .systemFont(ofSize: size.fontSize) }
            control.invalidateIntrinsicContentSize()
        }
        view.subviews.forEach { apply(size, to: $0) }
    }
}

public extension FluentView {
    /// Applies one semantic control size to every native control in this subtree.
    func controlSize(_ size: FluentControlSize) -> FluentControlSizeView<Self> {
        FluentControlSizeView(content: self, size: size)
    }
}
