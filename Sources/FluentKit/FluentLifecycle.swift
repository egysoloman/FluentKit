import AppKit

/// Adds lifecycle callbacks to a declarative view without changing its native layout.
public struct FluentLifecycleView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let onAppearAction: (() -> Void)?
    fileprivate let onDisappearAction: (() -> Void)?

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentLifecycleHost(
            content: content._mount(in: context),
            onAppear: onAppearAction,
            onDisappear: onDisappearAction
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentLifecycleHost else { return false }
        host.onAppear = onAppearAction
        host.onDisappear = onDisappearAction
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentLifecycleHost: NSView {
    var onAppear: (() -> Void)?
    var onDisappear: (() -> Void)?
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var hasAppeared = false

    init(content: NSView, onAppear: (() -> Void)?, onDisappear: (() -> Void)?) {
        self.onAppear = onAppear
        self.onDisappear = onDisappear
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
        let visible = window != nil
        if visible && !hasAppeared {
            hasAppeared = true
            onAppear?()
        } else if !visible && hasAppeared {
            hasAppeared = false
            onDisappear?()
        }
    }
}

/// Reports pointer entry and exit while keeping the wrapped view's native identity.
public struct FluentHoverView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let action: (Bool) -> Void

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentHoverHost(content: content._mount(in: context), action: action)
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentHoverHost else { return false }
        host.action = action
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentHoverHost: NSView {
    var action: (Bool) -> Void
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var isInside = false

    init(content: NSView, action: @escaping (Bool) -> Void) {
        self.action = action
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isInside else { return }
        isInside = true
        action(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isInside else { return }
        isInside = false
        action(false)
    }
}

public extension FluentView {
    func onAppear(perform action: @escaping () -> Void) -> FluentLifecycleView<Self> {
        FluentLifecycleView(content: self, onAppearAction: action, onDisappearAction: nil)
    }

    func onDisappear(perform action: @escaping () -> Void) -> FluentLifecycleView<Self> {
        FluentLifecycleView(content: self, onAppearAction: nil, onDisappearAction: action)
    }

    func onHover(perform action: @escaping (Bool) -> Void) -> FluentHoverView<Self> {
        FluentHoverView(content: self, action: action)
    }
}
