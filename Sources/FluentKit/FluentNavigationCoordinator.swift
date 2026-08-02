import AppKit

/// The direction of the last route-history operation. Consumers use this to choose the
/// forward/backward page transition without inferring intent from route depth.
public enum FluentNavigationHistoryDirection: Hashable, Sendable {
    case initial
    case forward
    case backward
    case replacement
}

/// A snapshot of browser-style page history. This is deliberately separate from UndoManager:
/// editing commands change document state, while this type only changes the current route.
public struct FluentNavigationHistorySnapshot<Route: Hashable>: Sendable where Route: Sendable {
    public let entries: [Route]
    public let cursor: Int
    public let direction: FluentNavigationHistoryDirection

    public var current: Route? {
        guard entries.indices.contains(cursor) else { return nil }
        return entries[cursor]
    }

    public var canGoBack: Bool { cursor > 0 && entries.indices.contains(cursor) }
    public var canGoForward: Bool { cursor >= 0 && cursor + 1 < entries.count }

    init(
        entries: [Route],
        cursor: Int,
        direction: FluentNavigationHistoryDirection
    ) {
        self.entries = entries
        self.cursor = cursor
        self.direction = direction
    }
}

/// Owns a route history with WinUI/macOS browser-style Back and Forward semantics.
public final class FluentNavigationCoordinator<Route: Hashable & Sendable> {
    public private(set) var entries: [Route]
    public private(set) var cursor: Int
    public private(set) var direction: FluentNavigationHistoryDirection

    private let observable: FluentObservable<FluentNavigationHistorySnapshot<Route>>

    public init(initial route: Route? = nil) {
        entries = route.map { [$0] } ?? []
        cursor = route == nil ? -1 : 0
        direction = route == nil ? .initial : .initial
        observable = FluentObservable(
            FluentNavigationHistorySnapshot(
                entries: entries,
                cursor: cursor,
                direction: .initial
            )
        )
    }

    public var current: Route? {
        guard entries.indices.contains(cursor) else { return nil }
        return entries[cursor]
    }

    public var canGoBack: Bool { cursor > 0 && entries.indices.contains(cursor) }
    public var canGoForward: Bool { cursor >= 0 && cursor + 1 < entries.count }

    public var snapshot: FluentNavigationHistorySnapshot<Route> {
        observable.value
    }

    /// Observable history state for declarative hosts and application-menu integrations.
    public var state: FluentObservable<FluentNavigationHistorySnapshot<Route>> { observable }

    @discardableResult
    public func push(_ route: Route) -> Bool {
        if current == route { return false }
        if cursor + 1 < entries.count {
            entries.removeSubrange((cursor + 1)..<entries.count)
        }
        entries.append(route)
        cursor = entries.count - 1
        direction = .forward
        publish()
        return true
    }

    @discardableResult
    public func replace(_ route: Route) -> Bool {
        guard !entries.isEmpty, entries.indices.contains(cursor) else {
            entries = [route]
            cursor = 0
            direction = .replacement
            publish()
            return true
        }
        guard entries[cursor] != route else { return false }
        entries[cursor] = route
        direction = .replacement
        publish()
        return true
    }

    @discardableResult
    public func goBack() -> Route? {
        guard canGoBack else { return current }
        cursor -= 1
        direction = .backward
        publish()
        return current
    }

    @discardableResult
    public func goForward() -> Route? {
        guard canGoForward else { return current }
        cursor += 1
        direction = .forward
        publish()
        return current
    }

    public func reset(to route: Route? = nil) {
        entries = route.map { [$0] } ?? []
        cursor = route == nil ? -1 : 0
        direction = .replacement
        publish()
    }

    @discardableResult
    public func observe(_ observer: @escaping (FluentNavigationHistorySnapshot<Route>) -> Void) -> UUID {
        observable.observe(observer, notifyImmediately: true)
    }

    public func removeObserver(_ id: UUID) {
        observable.removeObserver(id)
    }

    /// A binding for hosts that already model the current route as an optional value.
    public var currentBinding: FluentBinding<Route?> {
        FluentBinding(
            get: { [weak self] in self?.current },
            set: { [weak self] route in
                guard let self else { return }
                if let route { _ = self.push(route) }
            },
            observe: { [weak self] observer in
                guard let self else { return UUID() }
                return self.observe { observer($0.current) }
            },
            removeObserver: { [weak self] id in self?.removeObserver(id) },
            observationIdentity: ObjectIdentifier(observable)
        )
    }

    private func publish() {
        observable.value = FluentNavigationHistorySnapshot(
            entries: entries,
            cursor: cursor,
            direction: direction
        )
    }
}

/// Installs browser-style navigation key equivalents on a declarative subtree without mixing
/// route history with the subtree's UndoManager.
public struct FluentNavigationHistoryScopeView<Content: FluentView, Route: Hashable & Sendable>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let coordinator: FluentNavigationCoordinator<Route>
    fileprivate let onNavigate: (Route) -> Void

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentNavigationHistoryScopeHost(
            content: content._mount(in: context),
            coordinator: coordinator,
            onNavigate: onNavigate
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNavigationHistoryScopeHost<Route>,
              host.coordinator === coordinator else { return false }
        host.onNavigate = onNavigate
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentNavigationHistoryScopeHost<Route: Hashable & Sendable>: NSView {
    let coordinator: FluentNavigationCoordinator<Route>
    var onNavigate: (Route) -> Void
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    init(
        content: NSView,
        coordinator: FluentNavigationCoordinator<Route>,
        onNavigate: @escaping (Route) -> Void
    ) {
        self.coordinator = coordinator
        self.onNavigate = onNavigate
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
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let characters = event.charactersIgnoringModifiers
        if modifiers == [.command], characters == "[" {
            navigateBack()
            return true
        }
        if modifiers == [.command], characters == "]" {
            navigateForward()
            return true
        }
        if modifiers == [.option], event.keyCode == 123 {
            navigateBack()
            return true
        }
        if modifiers == [.option], event.keyCode == 124 {
            navigateForward()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func navigateBack() {
        guard coordinator.canGoBack, let route = coordinator.goBack() else { return }
        onNavigate(route)
    }

    private func navigateForward() {
        guard coordinator.canGoForward, let route = coordinator.goForward() else { return }
        onNavigate(route)
    }
}

public extension FluentView {
    func fluentNavigationHistory<Route: Hashable & Sendable>(
        _ coordinator: FluentNavigationCoordinator<Route>,
        onNavigate: @escaping (Route) -> Void
    ) -> FluentNavigationHistoryScopeView<Self, Route> {
        FluentNavigationHistoryScopeView(
            content: self,
            coordinator: coordinator,
            onNavigate: onNavigate
        )
    }
}
