import AppKit

public enum FluentDialogActionRole {
    case normal
    case cancel
    case destructive
}

public struct FluentDialogAction {
    public let title: String
    public let role: FluentDialogActionRole
    public let action: () -> Void

    public init(_ title: String, role: FluentDialogActionRole = .normal, action: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.action = action
    }
}

@resultBuilder
public enum FluentDialogActionBuilder {
    public static func buildBlock(_ components: FluentDialogAction...) -> [FluentDialogAction] { components }
    public static func buildOptional(_ component: [FluentDialogAction]?) -> [FluentDialogAction] { component ?? [] }
    public static func buildEither(first component: [FluentDialogAction]) -> [FluentDialogAction] { component }
    public static func buildEither(second component: [FluentDialogAction]) -> [FluentDialogAction] { component }
    public static func buildArray(_ components: [[FluentDialogAction]]) -> [FluentDialogAction] { components.flatMap { $0 } }
}

/// Presents a native confirmation sheet while keeping presentation state in a FluentBinding.
public struct FluentConfirmationDialog<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let title: String
    fileprivate let message: String
    fileprivate let isPresented: FluentBinding<Bool>
    fileprivate let actions: [FluentDialogAction]

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentConfirmationDialogHost(
            content: content._mount(in: context),
            title: title,
            message: message,
            isPresented: isPresented,
            actions: actions
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentConfirmationDialogHost else { return false }
        host.update(title: title, message: message, isPresented: isPresented, actions: actions)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentConfirmationDialogHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var title: String
    private var message: String
    private var isPresented: FluentBinding<Bool>
    private var actions: [FluentDialogAction]
    private var observerID: UUID?
    private var alert: NSAlert?
    private var isProgrammaticDismissal = false

    init(
        content: NSView,
        title: String,
        message: String,
        isPresented: FluentBinding<Bool>,
        actions: [FluentDialogAction]
    ) {
        self.title = title
        self.message = message
        self.isPresented = isPresented
        self.actions = actions
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    func update(
        title: String,
        message: String,
        isPresented: FluentBinding<Bool>,
        actions: [FluentDialogAction]
    ) {
        if let observerID { self.isPresented.removeObserver?(observerID) }
        self.title = title
        self.message = message
        self.isPresented = isPresented
        self.actions = actions
        installObserver()
        synchronizePresentation()
    }

    private func installObserver() {
        observerID = isPresented.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func synchronizePresentation() {
        guard let window else { return }
        if isPresented.get() {
            guard alert == nil else { return }
            let alert = makeAlert()
            self.alert = alert
            alert.beginSheetModal(for: window) { [weak self, weak alert] response in
                guard let self else { return }
                let wasProgrammatic = self.isProgrammaticDismissal
                self.isProgrammaticDismissal = false
                self.alert = nil
                if self.isPresented.get() { self.isPresented.set(false) }
                guard !wasProgrammatic, let alert else { return }
                let offset = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                guard offset >= 0, offset < self.actions.count else { return }
                self.actions[offset].action()
                _ = alert
            }
        } else if let alert {
            isProgrammaticDismissal = true
            window.endSheet(alert.window, returnCode: .cancel)
        }
    }

    private func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = actions.contains { $0.role == .destructive } ? .warning : .informational
        let effectiveActions = actions.isEmpty ? [FluentDialogAction("OK")] : actions
        for (index, action) in effectiveActions.enumerated() {
            let button = alert.addButton(withTitle: action.title)
            if action.role == .cancel { button.keyEquivalent = "\u{1b}" }
            if action.role == .destructive {
                button.contentTintColor = .systemRed
            } else if index == 0 {
                button.keyEquivalent = "\r"
            }
        }
        if actions.isEmpty { self.actions = effectiveActions }
        return alert
    }

    deinit {
        if let observerID { isPresented.removeObserver?(observerID) }
    }
}

public extension FluentView {
    func confirmationDialog(
        _ title: String,
        isPresented: FluentBinding<Bool>,
        message: String = "",
        @FluentDialogActionBuilder actions: () -> [FluentDialogAction]
    ) -> FluentConfirmationDialog<Self> {
        FluentConfirmationDialog(
            content: self,
            title: title,
            message: message,
            isPresented: isPresented,
            actions: actions()
        )
    }
}
