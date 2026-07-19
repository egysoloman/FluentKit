import AppKit

public struct FluentKeyboardActionView<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let defaultAction: (() -> Void)?
    private let cancelAction: (() -> Void)?
    private let isDefaultEnabled: () -> Bool
    private let isCancelEnabled: () -> Bool

    fileprivate init(
        content: Content,
        defaultAction: (() -> Void)?,
        cancelAction: (() -> Void)?,
        isDefaultEnabled: @escaping () -> Bool,
        isCancelEnabled: @escaping () -> Bool
    ) {
        self.content = content
        self.defaultAction = defaultAction
        self.cancelAction = cancelAction
        self.isDefaultEnabled = isDefaultEnabled
        self.isCancelEnabled = isCancelEnabled
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentKeyboardActionHost(
            content: content._mount(in: context),
            defaultAction: defaultAction,
            cancelAction: cancelAction,
            isDefaultEnabled: isDefaultEnabled,
            isCancelEnabled: isCancelEnabled
        )
        host.updateContent = { [content] native, updateContext in content._update(native, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentKeyboardActionHost else { return false }
        host.update(
            defaultAction: defaultAction,
            cancelAction: cancelAction,
            isDefaultEnabled: isDefaultEnabled,
            isCancelEnabled: isCancelEnabled
        )
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentKeyboardActionHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var defaultAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var isDefaultEnabled: () -> Bool
    private var isCancelEnabled: () -> Bool

    init(
        content: NSView,
        defaultAction: (() -> Void)?,
        cancelAction: (() -> Void)?,
        isDefaultEnabled: @escaping () -> Bool,
        isCancelEnabled: @escaping () -> Bool
    ) {
        self.defaultAction = defaultAction
        self.cancelAction = cancelAction
        self.isDefaultEnabled = isDefaultEnabled
        self.isCancelEnabled = isCancelEnabled
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

    func update(
        defaultAction: (() -> Void)?,
        cancelAction: (() -> Void)?,
        isDefaultEnabled: @escaping () -> Bool,
        isCancelEnabled: @escaping () -> Bool
    ) {
        self.defaultAction = defaultAction
        self.cancelAction = cancelAction
        self.isDefaultEnabled = isDefaultEnabled
        self.isCancelEnabled = isCancelEnabled
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty else { return super.performKeyEquivalent(with: event) }
        if (event.keyCode == 36 || event.keyCode == 76), let defaultAction, isDefaultEnabled() {
            defaultAction()
            return true
        }
        if event.keyCode == 53, let cancelAction, isCancelEnabled() {
            cancelAction()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

public extension FluentView {
    func fluentDefaultAction(
        isEnabled: @escaping () -> Bool = { true },
        _ action: @escaping () -> Void
    ) -> FluentKeyboardActionView<Self> {
        FluentKeyboardActionView(
            content: self,
            defaultAction: action,
            cancelAction: nil,
            isDefaultEnabled: isEnabled,
            isCancelEnabled: { true }
        )
    }

    func fluentCancelAction(
        isEnabled: @escaping () -> Bool = { true },
        _ action: @escaping () -> Void
    ) -> FluentKeyboardActionView<Self> {
        FluentKeyboardActionView(
            content: self,
            defaultAction: nil,
            cancelAction: action,
            isDefaultEnabled: { true },
            isCancelEnabled: isEnabled
        )
    }
}
