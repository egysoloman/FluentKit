import AppKit
import ObjectiveC

/// Controls how a semantic accessibility element exposes its declarative children.
public enum FluentAccessibilityChildBehavior: Hashable, Sendable {
    /// Hide the visual descendants from the accessibility tree and expose only the wrapper.
    case ignore
    /// Merge descendant labels into one semantic element.
    case combine
    /// Expose the wrapper and preserve the descendant tree below it.
    case contain
}

/// A VoiceOver-visible action that can be attached to any semantic Fluent element.
public struct FluentAccessibilityAction {
    public let name: String
    public let action: () -> Bool

    public init(_ name: String, action: @escaping () -> Bool) {
        self.name = name
        self.action = action
    }

    public init(_ name: String, action: @escaping () -> Void) {
        self.name = name
        self.action = {
            action()
            return true
        }
    }
}

/// A stable rotor entry resolved against an accessibility identifier in the mounted tree.
public struct FluentAccessibilityRotorEntry: Hashable, Sendable {
    public let identifier: String
    public let label: String

    public init(identifier: String, label: String) {
        precondition(!identifier.isEmpty, "A Fluent rotor entry needs a non-empty identifier")
        self.identifier = identifier
        self.label = label
    }
}

/// A custom VoiceOver rotor. Entries remain stable while the underlying declarative tree updates.
public struct FluentAccessibilityRotor: Hashable, Sendable {
    public let name: String
    public let entries: [FluentAccessibilityRotorEntry]

    public init(_ name: String, entries: [FluentAccessibilityRotorEntry]) {
        precondition(!name.isEmpty, "A Fluent accessibility rotor needs a name")
        self.name = name
        self.entries = entries
    }
}

public enum FluentAccessibilityAnnouncementPriority: Sendable {
    case low
    case medium
    case high

    fileprivate var appKitValue: Int {
        switch self {
        case .low: return 10
        case .medium: return 50
        case .high: return 90
        }
    }
}

/// Small, native helpers for posting VoiceOver announcements and focus changes.
public enum FluentAccessibility {
    public static func announce(
        _ message: String,
        priority: FluentAccessibilityAnnouncementPriority = .medium,
        from element: Any? = nil
    ) {
        guard !message.isEmpty else { return }
        let target = element ?? NSApplication.shared
        NSAccessibility.post(
            element: target,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSNumber(value: priority.appKitValue)
            ]
        )
    }

    public static func focus(_ element: NSAccessibilityElement) {
        NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
    }
}

/// Gives a composed branch explicit semantic child behavior and a stable group identity.
public struct FluentAccessibilityElementView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let behavior: FluentAccessibilityChildBehavior
    fileprivate let label: String?
    fileprivate let hint: String?
    fileprivate let identifier: String?

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentSemanticAccessibilityHost(
            content: content._mount(in: context),
            behavior: behavior,
            label: label,
            hint: hint,
            identifier: identifier
        )
        host.updateContent = { [content] native, updateContext in
            content._update(native, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSemanticAccessibilityHost else { return false }
        host.update(behavior: behavior, label: label, hint: hint, identifier: identifier)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

/// Attaches custom actions and rotors without replacing the wrapped native identity.
public struct FluentAccessibilityActionsView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let actions: [FluentAccessibilityAction]
    fileprivate let rotors: [FluentAccessibilityRotor]

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        apply(to: view)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard content._update(view, in: context) else { return false }
        apply(to: view)
        return true
    }

    private func apply(to view: NSView) {
        view.setAccessibilityCustomActions(actions.map { action in
            NSAccessibilityCustomAction(name: action.name) { action.action() }
        })

        let delegates = rotors.map { FluentAccessibilityRotorDelegate(root: view, rotor: $0) }
        view.setAccessibilityCustomRotors(delegates.map {
            NSAccessibilityCustomRotor(label: $0.rotor.name, itemSearchDelegate: $0)
        })
        objc_setAssociatedObject(
            view,
            &fluentAccessibilityRotorDelegatesKey,
            delegates,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

/// Binds a live label or value to the mounted semantic element without waiting for a tree rebuild.
public struct FluentDynamicAccessibilityView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let label: FluentBinding<String>?
    fileprivate let value: FluentBinding<String>?

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentDynamicAccessibilityHost(
            content: content._mount(in: context),
            label: label,
            value: value
        )
        host.updateContent = { [content] native, updateContext in
            content._update(native, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentDynamicAccessibilityHost else { return false }
        host.update(label: label, value: value)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

/// Announces a semantic message once a wrapped control becomes the focused element.
public struct FluentFocusAnnouncementView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let message: String
    fileprivate let priority: FluentAccessibilityAnnouncementPriority

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFocusAnnouncementHost(content: content._mount(in: context), message: message, priority: priority)
        host.updateContent = { [content] native, updateContext in
            content._update(native, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFocusAnnouncementHost else { return false }
        host.message = message
        host.priority = priority
        return host.updateContent?(host.contentView, context) ?? false
    }
}

public extension FluentView {
    func accessibilityElement(
        children behavior: FluentAccessibilityChildBehavior,
        label: String? = nil,
        hint: String? = nil,
        identifier: String? = nil
    ) -> FluentAccessibilityElementView<Self> {
        FluentAccessibilityElementView(
            content: self,
            behavior: behavior,
            label: label,
            hint: hint,
            identifier: identifier
        )
    }

    func accessibilityAction(_ action: FluentAccessibilityAction) -> FluentAccessibilityActionsView<Self> {
        FluentAccessibilityActionsView(content: self, actions: [action], rotors: [])
    }

    func accessibilityActions(_ actions: [FluentAccessibilityAction]) -> FluentAccessibilityActionsView<Self> {
        FluentAccessibilityActionsView(content: self, actions: actions, rotors: [])
    }

    func accessibilityRotor(_ rotor: FluentAccessibilityRotor) -> FluentAccessibilityActionsView<Self> {
        FluentAccessibilityActionsView(content: self, actions: [], rotors: [rotor])
    }

    func accessibilityLabel(_ binding: FluentBinding<String>) -> FluentDynamicAccessibilityView<Self> {
        FluentDynamicAccessibilityView(content: self, label: binding, value: nil)
    }

    func accessibilityValue(_ binding: FluentBinding<String>) -> FluentDynamicAccessibilityView<Self> {
        FluentDynamicAccessibilityView(content: self, label: nil, value: binding)
    }

    func accessibilityAnnounceOnFocus(
        _ message: String,
        priority: FluentAccessibilityAnnouncementPriority = .medium
    ) -> FluentFocusAnnouncementView<Self> {
        FluentFocusAnnouncementView(content: self, message: message, priority: priority)
    }
}

private final class FluentSemanticAccessibilityHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    private var behavior: FluentAccessibilityChildBehavior
    private var semanticLabel: String?

    init(
        content: NSView,
        behavior: FluentAccessibilityChildBehavior,
        label: String?,
        hint: String?,
        identifier: String?
    ) {
        self.behavior = behavior
        semanticLabel = label
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        configure(label: label, hint: hint, identifier: identifier)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        behavior: FluentAccessibilityChildBehavior,
        label: String?,
        hint: String?,
        identifier: String?
    ) {
        self.behavior = behavior
        semanticLabel = label
        configure(label: label, hint: hint, identifier: identifier)
    }

    private func configure(label: String?, hint: String?, identifier: String?) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(label ?? (behavior == .combine ? combinedLabel(in: contentView) : nil))
        setAccessibilityHelp(hint)
        setAccessibilityIdentifier(identifier)
        switch behavior {
        case .ignore, .combine:
            setAccessibilityChildren([])
        case .contain:
            setAccessibilityChildren([contentView])
        }
    }

    private func combinedLabel(in view: NSView) -> String? {
        var labels: [String] = []
        func visit(_ candidate: NSView) {
            if candidate.isAccessibilityElement(),
               let label = candidate.accessibilityLabel(),
               !label.isEmpty {
                labels.append(label)
            } else {
                candidate.subviews.forEach(visit)
            }
        }
        visit(view)
        let value = labels.joined(separator: ", ")
        return value.isEmpty ? nil : value
    }
}

private final class FluentDynamicAccessibilityHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    private var labelBinding: FluentBinding<String>?
    private var valueBinding: FluentBinding<String>?
    private var labelObserver: UUID?
    private var valueObserver: UUID?

    init(content: NSView, label: FluentBinding<String>?, value: FluentBinding<String>?) {
        labelBinding = label
        valueBinding = value
        super.init(frame: .zero)
        setAccessibilityElement(false)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installObservers()
        applyBindings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(label: FluentBinding<String>?, value: FluentBinding<String>?) {
        removeObservers()
        labelBinding = label
        valueBinding = value
        installObservers()
        applyBindings()
    }

    private func installObservers() {
        labelObserver = labelBinding?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applyBindings() }
        }
        valueObserver = valueBinding?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applyBindings() }
        }
    }

    private func applyBindings() {
        if let label = labelBinding { contentView.setAccessibilityLabel(label.get()) }
        if let value = valueBinding { contentView.setAccessibilityValue(value.get()) }
    }

    private func removeObservers() {
        if let labelObserver { labelBinding?.removeObserver(labelObserver) }
        if let valueObserver { valueBinding?.removeObserver(valueObserver) }
        labelObserver = nil
        valueObserver = nil
    }

    deinit { removeObservers() }
}

private final class FluentFocusAnnouncementHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    var message: String
    var priority: FluentAccessibilityAnnouncementPriority

    private var windowObservers: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?
    private weak var announcedWindow: NSWindow?

    init(content: NSView, message: String, priority: FluentAccessibilityAnnouncementPriority) {
        self.message = message
        self.priority = priority
        super.init(frame: .zero)
        setAccessibilityElement(false)
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
        removeWindowObservers()
        guard let window else { return }
        observedWindow = window
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
                self?.announceIfFocused()
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.announceIfFocused()
            }
        ]
        DispatchQueue.main.async { [weak self] in self?.announceIfFocused() }
    }

    private func announceIfFocused() {
        guard let window = observedWindow, window.isKeyWindow, containsFirstResponder(in: contentView, window: window), announcedWindow !== window else { return }
        announcedWindow = window
        FluentAccessibility.announce(message, priority: priority, from: contentView)
    }

    private func containsFirstResponder(in view: NSView, window: NSWindow) -> Bool {
        if window.firstResponder === view { return true }
        return view.subviews.contains { containsFirstResponder(in: $0, window: window) }
    }

    private func removeWindowObservers() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        observedWindow = nil
        announcedWindow = nil
    }

    deinit { removeWindowObservers() }
}

private final class FluentAccessibilityRotorDelegate: NSObject, NSAccessibilityCustomRotorItemSearchDelegate {
    weak var root: NSView?
    let rotor: FluentAccessibilityRotor

    init(root: NSView, rotor: FluentAccessibilityRotor) {
        self.root = root
        self.rotor = rotor
    }

    func rotor(
        _ rotor: NSAccessibilityCustomRotor,
        resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters
    ) -> NSAccessibilityCustomRotor.ItemResult? {
        guard let root else { return nil }
        let targets = self.rotor.entries.compactMap { entry -> (FluentAccessibilityRotorEntry, NSView)? in
            find(identifier: entry.identifier, in: root).map { (entry, $0) }
        }
        let filtered = searchParameters.filterString.isEmpty
            ? targets
            : targets.filter { $0.0.label.localizedCaseInsensitiveContains(searchParameters.filterString) }
        guard !filtered.isEmpty else { return nil }
        let currentIndex = searchParameters.currentItem?.targetElement.flatMap { current in
            filtered.firstIndex { ($0.1 as AnyObject) === (current as AnyObject) }
        }
        let nextIndex: Int
        switch searchParameters.searchDirection {
        case .next:
            nextIndex = currentIndex.map { ($0 + 1) % filtered.count } ?? 0
        case .previous:
            nextIndex = currentIndex.map { ($0 - 1 + filtered.count) % filtered.count } ?? filtered.count - 1
        @unknown default:
            nextIndex = 0
        }
        let result = NSAccessibilityCustomRotor.ItemResult(targetElement: filtered[nextIndex].1)
        result.customLabel = filtered[nextIndex].0.label
        return result
    }

    private func find(identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        return view.subviews.lazy.compactMap { self.find(identifier: identifier, in: $0) }.first
    }
}

private var fluentAccessibilityRotorDelegatesKey: UInt8 = 0

/// A warning/error produced by `FluentAccessibilityAudit`.
public struct FluentAccessibilityAuditIssue: Equatable, Sendable {
    public enum Severity: String, Sendable {
        case warning
        case error
    }

    public let severity: Severity
    public let path: String
    public let message: String

    public init(severity: Severity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }
}

/// Performs deterministic semantic checks on a mounted native tree.
public enum FluentAccessibilityAudit {
    public static func run(on root: NSView) -> [FluentAccessibilityAuditIssue] {
        var issues: [FluentAccessibilityAuditIssue] = []
        var identifiers: [String: String] = [:]
        let interactiveRoles: Set<NSAccessibility.Role> = [
            .button, .checkBox, .radioButton, .slider, .textField, .comboBox,
            .popUpButton, .menuItem, .disclosureTriangle, .colorWell, .incrementor
        ]

        func visit(_ view: NSView, path: String) {
            let identifier = view.accessibilityIdentifier()
            if !identifier.isEmpty {
                if let previous = identifiers[identifier] {
                    issues.append(.init(severity: .error, path: path, message: "Accessibility identifier '\(identifier)' duplicates \(previous)"))
                } else {
                    identifiers[identifier] = path
                }
            }
            if view.isAccessibilityElement() {
                let role = view.accessibilityRole()
                let label = (view.accessibilityLabel() ?? view.accessibilityTitle() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let role, interactiveRoles.contains(role), label.isEmpty {
                    issues.append(.init(severity: .error, path: path, message: "Interactive accessibility role \(role.rawValue) has no label"))
                }
                if role == .group, label.isEmpty, (view.accessibilityChildren() ?? []).isEmpty {
                    issues.append(.init(severity: .warning, path: path, message: "Empty accessibility group has no label"))
                }
            }
            view.subviews.enumerated().forEach { index, child in
                visit(child, path: "\(path).\(index)")
            }
        }

        visit(root, path: String(describing: type(of: root)))
        return issues
    }

    public static func hasErrors(on root: NSView) -> Bool {
        run(on: root).contains { $0.severity == .error }
    }
}
