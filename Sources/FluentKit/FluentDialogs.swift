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
    private weak var presentationCoordinator: FluentPresentationCoordinator?
    private var presentationToken: FluentPresentationCoordinator.Token?
    private var alertToken: FluentPresentationCoordinator.Token?
    private var programmaticDismissalToken: FluentPresentationCoordinator.Token?

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
        if window == nil {
            cancelPresentation()
            return
        }
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    func update(
        title: String,
        message: String,
        isPresented: FluentBinding<Bool>,
        actions: [FluentDialogAction]
    ) {
        let reusesObservation = self.isPresented.observationIdentity != nil
            && self.isPresented.observationIdentity == isPresented.observationIdentity
        if !reusesObservation, let observerID { self.isPresented.removeObserver?(observerID) }
        self.title = title
        self.message = message
        self.isPresented = isPresented
        self.actions = actions
        if !reusesObservation { installObserver() }
        updatePresentedAlert()
        synchronizePresentation()
    }

    private func installObserver() {
        observerID = isPresented.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func synchronizePresentation() {
        guard let window else {
            cancelPresentation()
            return
        }
        if isPresented.get() {
            guard presentationToken == nil else { return }
            let coordinator = FluentPresentationCoordinator.coordinator(for: window)
            presentationCoordinator = coordinator
            presentationToken = coordinator.enqueue(
                owner: self,
                present: { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.beginPresentation(on: window)
                },
                cancel: { [weak self] in self?.endPresentationForCancellation() }
            )
        } else {
            cancelPresentation()
        }
    }

    private func beginPresentation(on window: NSWindow) {
        guard let token = presentationToken else { return }
        guard isPresented.get() else {
            presentationCoordinator?.finish(token)
            presentationToken = nil
            return
        }

        let alert = makeAlert()
        self.alert = alert
        alertToken = token
        let coordinator = presentationCoordinator
        alert.beginSheetModal(for: window) { [weak self, weak alert, coordinator] response in
            coordinator?.finish(token)
            guard let self else { return }
            let wasProgrammatic = self.programmaticDismissalToken === token
            if wasProgrammatic { self.programmaticDismissalToken = nil }
            if self.alertToken === token {
                self.alertToken = nil
                self.alert = nil
            }
            guard self.presentationToken === token else { return }
            self.presentationToken = nil
            if !wasProgrammatic, self.isPresented.get() { self.isPresented.set(false) }
            guard !wasProgrammatic, alert != nil else { return }
            let offset = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let actions = self.effectiveActions
            guard offset >= 0, offset < actions.count else { return }
            actions[offset].action()
        }
    }

    private func cancelPresentation() {
        guard let token = presentationToken else { return }
        programmaticDismissalToken = token
        presentationCoordinator?.cancel(token)
        if presentationToken === token { presentationToken = nil }
    }

    private func endPresentationForCancellation() {
        guard let token = presentationToken else { return }
        if let alert, alertToken === token, let parent = window ?? alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .cancel)
        } else {
            presentationCoordinator?.finish(token)
        }
    }

    private var effectiveActions: [FluentDialogAction] {
        actions.isEmpty ? [FluentDialogAction("OK")] : actions
    }

    private func updatePresentedAlert() {
        guard let alert else { return }
        let actions = effectiveActions
        guard alert.buttons.count == actions.count else {
            cancelPresentation()
            synchronizePresentation()
            return
        }
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = actions.contains { $0.role == .destructive } ? .warning : .informational
        for (index, action) in actions.enumerated() {
            configure(alert.buttons[index], for: action, at: index)
        }
    }

    private func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = actions.contains { $0.role == .destructive } ? .warning : .informational
        for (index, action) in effectiveActions.enumerated() {
            let button = alert.addButton(withTitle: action.title)
            configure(button, for: action, at: index)
        }
        return alert
    }

    private func configure(_ button: NSButton, for action: FluentDialogAction, at index: Int) {
        button.title = action.title
        button.keyEquivalent = action.role == .cancel ? "\u{1b}" : (index == 0 ? "\r" : "")
        button.contentTintColor = action.role == .destructive ? .systemRed : nil
    }

    deinit {
        if let observerID { isPresented.removeObserver?(observerID) }
        if let token = presentationToken { presentationCoordinator?.cancel(token) }
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
