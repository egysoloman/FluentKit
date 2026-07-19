import AppKit

/// A resolved navigation destination. The descriptor keeps route-specific title and content
/// together so a stack can resolve one destination value once per transition.
public struct FluentNavigationDestination {
    public let title: String
    public let content: FluentAnyView

    public init<V: FluentView>(
        title: String,
        @FluentViewBuilder content: () -> V
    ) {
        self.title = title
        self.content = FluentAnyView(content())
    }

    public init(title: String, content: FluentAnyView) {
        self.title = title
        self.content = content
    }
}

/// A type-safe registry that resolves hashable route values into navigation destinations.
///
/// Registration is keyed by the concrete route type. Registering a type again replaces its
/// previous resolver, which makes it possible to update a workspace destination set while
/// keeping the native navigation host mounted.
public final class FluentNavigationDestinationRegistry {
    private var handlers: [ObjectIdentifier: (AnyHashable) -> FluentNavigationDestination] = [:]

    public init() {}

    public var count: Int { handlers.count }

    /// Registers a resolver for a concrete route type. A later registration for the same type
    /// replaces the earlier resolver and returns this registry for fluent composition.
    @discardableResult
    public func register<Route: Hashable>(
        _ routeType: Route.Type = Route.self,
        destination: @escaping (Route) -> FluentNavigationDestination
    ) -> FluentNavigationDestinationRegistry {
        handlers[ObjectIdentifier(routeType)] = { route in
            guard let typedRoute = route.base as? Route else { return Self.unavailableDestination(for: route) }
            return destination(typedRoute)
        }
        return self
    }


    /// Removes the resolver for a concrete route type.
    @discardableResult
    public func unregister<Route: Hashable>(_ routeType: Route.Type = Route.self) -> Bool {
        handlers.removeValue(forKey: ObjectIdentifier(routeType)) != nil
    }

    /// Resolves a route, returning nil when no resolver is registered for its concrete type.
    public func resolve(_ route: AnyHashable) -> FluentNavigationDestination? {
        handlers[ObjectIdentifier(type(of: route.base))]?(route)
    }

    /// Resolves a typed route without requiring callers to erase it manually.
    public func resolve<Route: Hashable>(_ route: Route) -> FluentNavigationDestination? {
        resolve(AnyHashable(route))
    }

    /// Removes every registered resolver.
    public func removeAll() {
        handlers.removeAll()
    }

    /// Returns whether a concrete route type currently has a resolver.
    public func contains<Route: Hashable>(_ routeType: Route.Type = Route.self) -> Bool {
        handlers[ObjectIdentifier(routeType)] != nil
    }

    /// A safe fallback used by registry-backed stacks when a persisted route is no longer known.
    public static func unavailableDestination(for route: AnyHashable) -> FluentNavigationDestination {
        FluentNavigationDestination(title: "Unavailable") {
            FluentText("No destination registered for \(route)")
        }
    }
}

/// A homogeneous, Codable navigation path. Its route type keeps destination registration and
/// restoration type-safe while still allowing the native stack host to use erased identities.
public struct FluentNavigationPath<Route: Hashable & Codable>: Codable, Hashable {
    public private(set) var elements: [Route]

    public init(_ elements: [Route] = []) {
        self.elements = elements
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }
    public var last: Route? { elements.last }

    public mutating func append(_ route: Route) {
        elements.append(route)
    }

    public mutating func append(contentsOf routes: [Route]) {
        elements.append(contentsOf: routes)
    }

    @discardableResult
    public mutating func popLast() -> Route? {
        elements.popLast()
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        elements.removeAll(keepingCapacity: keepingCapacity)
    }
}

extension FluentNavigationPath: RandomAccessCollection {
    public typealias Index = Int

    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }

    public subscript(position: Int) -> Route {
        elements[position]
    }

    public func index(after index: Int) -> Int {
        elements.index(after: index)
    }

    public func index(before index: Int) -> Int {
        elements.index(before: index)
    }

    public func index(_ i: Int, offsetBy distance: Int) -> Int {
        elements.index(i, offsetBy: distance)
    }

    public func distance(from start: Int, to end: Int) -> Int {
        elements.distance(from: start, to: end)
    }
}

/// The visual transition used when a navigation route changes.
public enum FluentNavigationTransition: Sendable {
    case none
    case crossFade
    case slide
}

/// A declarative link that appends a route to a navigation path when its label is activated.
public struct FluentNavigationLink<Label: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let route: AnyHashable
    fileprivate let path: FluentBinding<[AnyHashable]>
    fileprivate let label: Label

    public init(
        _ route: AnyHashable,
        path: FluentBinding<[AnyHashable]>,
        @FluentViewBuilder label: () -> Label
    ) {
        self.route = route
        self.path = path
        self.label = label()
    }

    public init<Route: Hashable>(
        _ route: Route,
        path: FluentBinding<[AnyHashable]>,
        @FluentViewBuilder label: () -> Label
    ) {
        self.init(AnyHashable(route), path: path, label: label)
    }

    /// Creates a link that appends a route to a homogeneous Codable navigation path.
    public init<Route: Hashable & Codable>(
        _ route: Route,
        path: FluentBinding<FluentNavigationPath<Route>>,
        @FluentViewBuilder label: () -> Label
    ) {
        self.init(
            AnyHashable(route),
            path: path.map(
                { $0.elements.map(AnyHashable.init) },
                { FluentNavigationPath($0.compactMap { $0.base as? Route }) }
            ),
            label: label
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentNavigationLinkHost(
            label: label._mount(in: context),
            route: route,
            path: path,
            theme: context.theme
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNavigationLinkHost else { return false }
        host.update(route: route, path: path, theme: context.theme, context: context, makeLabel: { label._mount(in: context) }) { native, updateContext in
            label._update(native, in: updateContext)
        }
        return true
    }
}

private final class FluentNavigationLinkHost: NSView {
    private var route: AnyHashable
    private var path: FluentBinding<[AnyHashable]>
    private var theme: FluentTheme

    init(label: NSView, route: AnyHashable, path: FluentBinding<[AnyHashable]>, theme: FluentTheme) {
        self.route = route
        self.path = path
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilityLabel("Navigate to \(route)")
        installLabel(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        alphaValue = 0.82
    }

    override func mouseExited(with event: NSEvent) {
        alphaValue = 1
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        var value = path.get()
        value.append(route)
        path.set(value)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 49 else {
            super.keyDown(with: event)
            return
        }
        var value = path.get()
        value.append(route)
        path.set(value)
    }

    override var acceptsFirstResponder: Bool { true }

    private func installLabel(_ label: NSView) {
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(route: AnyHashable, path: FluentBinding<[AnyHashable]>, theme: FluentTheme, context: FluentRenderContext, makeLabel: @escaping () -> NSView, updateLabel: @escaping (NSView, FluentRenderContext) -> Bool) {
        self.route = route
        self.path = path
        self.theme = theme
        setAccessibilityLabel("Navigate to \(route)")
        if let label = subviews.first {
            if !updateLabel(label, context) {
                label.removeFromSuperview()
                installLabel(makeLabel())
            }
        }
    }

    private var isEnabled: Bool { window != nil }
}

/// A value-driven navigation stack. The path stores route identities while destination content
/// stays entirely in native Fluent views. Pushing and popping routes updates only the content host.
public struct FluentNavigationStack<Root: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let root: Root
    fileprivate let path: FluentBinding<[AnyHashable]>
    fileprivate let destination: (AnyHashable) -> FluentAnyView
    fileprivate let title: (AnyHashable) -> String
    fileprivate let resolvedDestination: ((AnyHashable) -> FluentNavigationDestination)?
    fileprivate let transition: FluentNavigationTransition

    public init(
        path: FluentBinding<[AnyHashable]>,
        @FluentViewBuilder root: () -> Root,
        title: @escaping (AnyHashable) -> String = { String(describing: $0) },
        destination: @escaping (AnyHashable) -> FluentAnyView,
        transition: FluentNavigationTransition = .slide
    ) {
        self.path = path
        self.root = root()
        self.destination = destination
        self.title = title
        self.resolvedDestination = nil
        self.transition = transition
    }

    /// Creates a stack whose route resolver returns a title and view as one value.
    public init(
        path: FluentBinding<[AnyHashable]>,
        @FluentViewBuilder root: () -> Root,
        transition: FluentNavigationTransition = .slide,
        destination: @escaping (AnyHashable) -> FluentNavigationDestination
    ) {
        self.path = path
        self.root = root()
        self.destination = { route in destination(route).content }
        self.title = { route in destination(route).title }
        self.resolvedDestination = destination
        self.transition = transition
    }

    /// Creates a stack backed by a homogeneous Codable path and a type-safe destination registry.
    /// Unknown routes resolve to a safe unavailable destination instead of trapping.
    public init<Route: Hashable & Codable>(
        path: FluentBinding<FluentNavigationPath<Route>>,
        @FluentViewBuilder root: () -> Root,
        registry: FluentNavigationDestinationRegistry,
        transition: FluentNavigationTransition = .slide
    ) {
        let erasedPath = path.map(
            { typedPath in typedPath.elements.map(AnyHashable.init) },
            { erased in FluentNavigationPath(erased.compactMap { $0.base as? Route }) }
        )
        self.path = erasedPath
        self.root = root()
        self.destination = { route in
            (registry.resolve(route) ?? FluentNavigationDestinationRegistry.unavailableDestination(for: route)).content
        }
        self.title = { route in
            (registry.resolve(route) ?? FluentNavigationDestinationRegistry.unavailableDestination(for: route)).title
        }
        self.resolvedDestination = { route in
            registry.resolve(route) ?? FluentNavigationDestinationRegistry.unavailableDestination(for: route)
        }
        self.transition = transition
    }

    /// Creates a stack using the existing erased path API and a type-safe destination registry.
    public init(
        path: FluentBinding<[AnyHashable]>,
        @FluentViewBuilder root: () -> Root,
        registry: FluentNavigationDestinationRegistry,
        transition: FluentNavigationTransition = .slide
    ) {
        self.path = path
        self.root = root()
        self.destination = { route in
            (registry.resolve(route) ?? FluentNavigationDestinationRegistry.unavailableDestination(for: route)).content
        }
        self.title = { route in
            (registry.resolve(route) ?? FluentNavigationDestinationRegistry.unavailableDestination(for: route)).title
        }
        self.resolvedDestination = { route in
            registry.resolve(route) ?? FluentNavigationDestinationRegistry.unavailableDestination(for: route)
        }
        self.transition = transition
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentNavigationStackHost(
            root: FluentAnyView(root),
            path: path,
            title: title,
            destination: destination,
            resolvedDestination: resolvedDestination,
            transition: transition,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNavigationStackHost else { return false }
        host.update(root: FluentAnyView(root), path: path, title: title, destination: destination, resolvedDestination: resolvedDestination, transition: transition, context: context)
        return true
    }
}

private final class FluentNavigationStackHost: NSView {
    private var root: FluentAnyView
    private var path: FluentBinding<[AnyHashable]>
    private var title: (AnyHashable) -> String
    private var destination: (AnyHashable) -> FluentAnyView
    private var resolvedDestination: ((AnyHashable) -> FluentNavigationDestination)?
    private var transition: FluentNavigationTransition
    private var context: FluentRenderContext
    private var observerID: UUID?
    private var observedPath: FluentBinding<[AnyHashable]>?
    private var lastRenderedPath: [AnyHashable] = []

    private let stack = NSStackView()
    private let header = NSStackView()
    private let backButton = FluentButton(title: "Back")
    private let titleLabel = NSTextField(labelWithString: "")
    private let contentContainer = NSView()
    private var contentHost: FluentViewHost<FluentAnyView>

    init(
        root: FluentAnyView,
        path: FluentBinding<[AnyHashable]>,
        title: @escaping (AnyHashable) -> String,
        destination: @escaping (AnyHashable) -> FluentAnyView,
        resolvedDestination: ((AnyHashable) -> FluentNavigationDestination)?,
        transition: FluentNavigationTransition,
        context: FluentRenderContext
    ) {
        self.root = root
        self.path = path
        self.title = title
        self.destination = destination
        self.resolvedDestination = resolvedDestination
        self.transition = transition
        self.context = context
        contentHost = FluentViewHost(root, context: context)
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        backButton.theme = context.theme
        backButton.onClick = { [weak self] in self?.pop() }
        backButton.setAccessibilityLabel("Back")
        header.addArrangedSubview(backButton)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = context.theme.textPrimary
        titleLabel.setAccessibilityRole(.staticText)
        header.addArrangedSubview(titleLabel)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        stack.addArrangedSubview(contentContainer)
        contentContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        installObserver()
        render(path: path.get(), animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        root: FluentAnyView,
        path: FluentBinding<[AnyHashable]>,
        title: @escaping (AnyHashable) -> String,
        destination: @escaping (AnyHashable) -> FluentAnyView,
        resolvedDestination: ((AnyHashable) -> FluentNavigationDestination)?,
        transition: FluentNavigationTransition,
        context: FluentRenderContext
    ) {
        if let observerID { observedPath?.removeObserver?(observerID) }
        self.root = root
        self.path = path
        self.title = title
        self.destination = destination
        self.resolvedDestination = resolvedDestination
        self.transition = transition
        self.context = context
        backButton.theme = context.theme
        titleLabel.textColor = context.theme.textPrimary
        contentHost.context = context
        installObserver()
        render(path: path.get(), animated: false)
    }

    private func installObserver() {
        observedPath = path
        observerID = path.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in self?.render(path: value, animated: true) }
        }
    }

    private func render(path: [AnyHashable], animated: Bool) {
        guard path != lastRenderedPath || !animated else { return }
        lastRenderedPath = path
        let route = path.last
        backButton.isHidden = route == nil
        let resolved = route.flatMap { resolvedDestination?($0) }
        titleLabel.stringValue = resolved?.title ?? route.map(title) ?? ""
        let view = resolved?.content ?? route.map(destination) ?? root
        let update = { [weak self] in
            guard let self else { return }
            self.contentHost.update(view)
            self.contentHost.needsLayout = true
            self.needsLayout = true
        }
        guard animated, !context.reduceMotion, transition != .none else {
            update()
            return
        }
        contentHost.wantsLayer = true
        let duration = context.animationDuration
        switch transition {
        case .crossFade:
            contentHost.alphaValue = 0
            update()
            NSAnimationContext.runAnimationGroup { animationContext in
                animationContext.duration = duration
                animationContext.timingFunction = context.animationTimingFunction
                contentHost.animator().alphaValue = 1
            }
        case .slide:
            contentHost.layer?.setAffineTransform(CGAffineTransform(translationX: 24, y: 0))
            update()
            NSAnimationContext.runAnimationGroup { animationContext in
                animationContext.duration = duration
                animationContext.timingFunction = context.animationTimingFunction
                animationContext.allowsImplicitAnimation = true
                contentHost.animator().layer?.setAffineTransform(.identity)
            }
        case .none:
            update()
        }
    }

    private func pop() {
        var value = path.get()
        guard !value.isEmpty else { return }
        value.removeLast()
        path.set(value)
    }

    deinit {
        if let observerID { observedPath?.removeObserver?(observerID) }
    }
}
