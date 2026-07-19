import AppKit

/// A snapshot of native undo/redo availability suitable for declarative labels, menus, and
/// disabled states.
public struct FluentUndoState: Equatable, Sendable {
    public let canUndo: Bool
    public let canRedo: Bool
    public let undoActionName: String
    public let redoActionName: String

    public init(canUndo: Bool, canRedo: Bool, undoActionName: String, redoActionName: String) {
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.undoActionName = undoActionName
        self.redoActionName = redoActionName
    }
}

private final class FluentUndoTarget: NSObject {
    weak var coordinator: FluentUndoCoordinator?

    init(coordinator: FluentUndoCoordinator) {
        self.coordinator = coordinator
    }
}

/// Coordinates application-state undo transactions with a native `UndoManager`.
///
/// Text views keep their own AppKit editing history. Use this coordinator for model and binding
/// changes that should participate in window-level Undo/Redo commands.
public final class FluentUndoCoordinator {
    public let undoManager: UndoManager
    public let state: FluentObservable<FluentUndoState>

    private lazy var target = FluentUndoTarget(coordinator: self)
    private var notificationObservers: [NSObjectProtocol] = []

    public init(undoManager: UndoManager = UndoManager()) {
        self.undoManager = undoManager
        state = FluentObservable(Self.snapshot(of: undoManager))
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSUndoManagerCheckpoint,
            .NSUndoManagerDidOpenUndoGroup,
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ]
        notificationObservers = names.map { name in
            center.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                self?.refreshState()
            }
        }
    }

    public var canUndo: Bool { undoManager.canUndo }
    public var canRedo: Bool { undoManager.canRedo }

    /// Registers and applies a binding mutation. The equality predicate prevents no-op entries.
    public func set<Value>(
        _ value: Value,
        on binding: FluentBinding<Value>,
        actionName: String = "Change",
        areEquivalent: @escaping (Value, Value) -> Bool
    ) {
        let previous = binding.get()
        guard !areEquivalent(previous, value) else { return }
        let needsStandaloneGroup = undoManager.groupingLevel == 0
            && !undoManager.isUndoing
            && !undoManager.isRedoing
        if needsStandaloneGroup { undoManager.beginUndoGrouping() }
        register(previous, on: binding, actionName: actionName, areEquivalent: areEquivalent)
        binding.set(value)
        if needsStandaloneGroup { undoManager.endUndoGrouping() }
        refreshState()
    }

    public func beginGroup(actionName: String? = nil) {
        undoManager.beginUndoGrouping()
        if let actionName, !actionName.isEmpty { undoManager.setActionName(actionName) }
        refreshState()
    }

    public func endGroup(actionName: String? = nil) {
        precondition(undoManager.groupingLevel > 0, "Cannot end a Fluent undo group that was not begun")
        if let actionName, !actionName.isEmpty { undoManager.setActionName(actionName) }
        undoManager.endUndoGrouping()
        refreshState()
    }

    @discardableResult
    public func withGroup<Result>(actionName: String, _ changes: () throws -> Result) rethrows -> Result {
        beginGroup(actionName: actionName)
        defer { endGroup(actionName: actionName) }
        return try changes()
    }

    public func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refreshState()
    }

    public func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refreshState()
    }

    public func removeAllActions() {
        undoManager.removeAllActions()
        refreshState()
    }

    private func register<Value>(
        _ value: Value,
        on binding: FluentBinding<Value>,
        actionName: String,
        areEquivalent: @escaping (Value, Value) -> Bool
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            guard let coordinator = target.coordinator else { return }
            let inverse = binding.get()
            guard !areEquivalent(inverse, value) else { return }
            coordinator.register(
                inverse,
                on: binding,
                actionName: actionName,
                areEquivalent: areEquivalent
            )
            binding.set(value)
            coordinator.refreshState()
        }
        if !actionName.isEmpty { undoManager.setActionName(actionName) }
    }

    private func refreshState() {
        state.value = Self.snapshot(of: undoManager)
    }

    private static func snapshot(of manager: UndoManager) -> FluentUndoState {
        FluentUndoState(
            canUndo: manager.canUndo,
            canRedo: manager.canRedo,
            undoActionName: manager.undoActionName,
            redoActionName: manager.redoActionName
        )
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

public extension FluentBinding {
    /// Returns a binding that records each distinct mutation in the supplied native undo manager.
    func undoable(
        using coordinator: FluentUndoCoordinator,
        actionName: String = "Change",
        areEquivalent: @escaping (Value, Value) -> Bool
    ) -> FluentBinding<Value> {
        FluentBinding(
            get: get,
            set: { coordinator.set($0, on: self, actionName: actionName, areEquivalent: areEquivalent) },
            observe: observe,
            removeObserver: removeObserver
        )
    }
}

public extension FluentBinding where Value: Equatable {
    func undoable(
        using coordinator: FluentUndoCoordinator,
        actionName: String = "Change"
    ) -> FluentBinding<Value> {
        undoable(using: coordinator, actionName: actionName, areEquivalent: ==)
    }
}

/// Installs a shared native undo manager on a declarative subtree and routes Command-Z /
/// Shift-Command-Z when the focused responder does not consume those keys itself.
public struct FluentUndoScopeView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let coordinator: FluentUndoCoordinator

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        var nested = context
        nested.undoCoordinator = coordinator
        let host = FluentUndoScopeHost(content: content._mount(in: nested), coordinator: coordinator)
        host.updateContent = { [content] nativeView, updateContext in
            var childContext = updateContext
            childContext.undoCoordinator = coordinator
            return content._update(nativeView, in: childContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentUndoScopeHost, host.coordinator === coordinator else { return false }
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentUndoScopeHost: NSView {
    let coordinator: FluentUndoCoordinator
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    init(content: NSView, coordinator: FluentUndoCoordinator) {
        self.coordinator = coordinator
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

    override var undoManager: UndoManager? { coordinator.undoManager }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return super.performKeyEquivalent(with: event)
        }
        if modifiers == [.command], coordinator.canUndo {
            coordinator.undo()
            return true
        }
        if modifiers == [.command, .shift], coordinator.canRedo {
            coordinator.redo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

public extension FluentView {
    func fluentUndoScope(_ coordinator: FluentUndoCoordinator) -> FluentUndoScopeView<Self> {
        FluentUndoScopeView(content: self, coordinator: coordinator)
    }
}
