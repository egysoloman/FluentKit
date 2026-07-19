import AppKit

public enum FluentAccessibilityRole {
    case button
    case checkbox
    case menu
    case menuItem
    case image
    case list
    case listItem
    case progressIndicator
    case radioButton
    case slider
    case staticText
    case tab
    case textField
    case toolbar
    case group
    case disclosureTriangle
    case colorWell
    case dateField

    fileprivate var nsRole: NSAccessibility.Role {
        switch self {
        case .button: return .button
        case .checkbox: return .checkBox
        case .menu: return .menu
        case .menuItem: return .menuItem
        case .image: return .image
        case .list: return .list
        case .listItem: return .group
        case .progressIndicator: return .progressIndicator
        case .radioButton: return .radioButton
        case .slider: return .slider
        case .staticText: return .staticText
        case .tab: return .radioButton
        case .textField: return .textField
        case .toolbar: return .toolbar
        case .group: return .group
        case .disclosureTriangle: return .disclosureTriangle
        case .colorWell: return .colorWell
        case .dateField: return .textField
    }
}
}

/// Explicitly marks a composed view as an accessibility container. AppKit keeps the wrapped
/// native view as the sole child, which makes the semantic hierarchy stable for VoiceOver and UI
/// automation even when the declarative branch is reconciled in place.
public struct FluentAccessibilityGroupView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let label: String?
    fileprivate let hint: String?
    fileprivate let identifier: String?

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentAccessibilityGroupHost(content: content._mount(in: context), label: label, hint: hint, identifier: identifier)
        host.updateContent = { [content] nativeView, updateContext in content._update(nativeView, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentAccessibilityGroupHost else { return false }
        host.update(label: label, hint: hint, identifier: identifier)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentAccessibilityGroupHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    init(content: NSView, label: String?, hint: String?, identifier: String?) {
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

    func update(label: String?, hint: String?, identifier: String?) {
        configure(label: label, hint: hint, identifier: identifier)
    }

    private func configure(label: String?, hint: String?, identifier: String?) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(label)
        setAccessibilityHelp(hint)
        setAccessibilityIdentifier(identifier)
        setAccessibilityChildren([contentView])
    }
}
public struct FluentAccessibilityView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let label: String?
    fileprivate let hint: String?
    fileprivate let identifier: String?
    fileprivate let role: FluentAccessibilityRole?
    fileprivate let value: Any?
    fileprivate let hidden: Bool?
    fileprivate let enabled: Bool?
    fileprivate let selected: Bool?

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
        if let label { view.setAccessibilityLabel(label) }
        if let hint { view.setAccessibilityHelp(hint) }
        if let identifier { view.setAccessibilityIdentifier(identifier) }
        if let role { view.setAccessibilityRole(role.nsRole) }
        if let value { view.setAccessibilityValue(value) }
        if let hidden { view.setAccessibilityElement(!hidden) }
        if let enabled { view.setAccessibilityEnabled(enabled) }
        if let selected { view.setAccessibilitySelected(selected) }
    }
}

public extension FluentView {
    func accessibilityGroup(
        label: String? = nil,
        hint: String? = nil,
        identifier: String? = nil
    ) -> FluentAccessibilityGroupView<Self> {
        FluentAccessibilityGroupView(content: self, label: label, hint: hint, identifier: identifier)
    }

    func accessibilityLabel(_ label: String) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: label, hint: nil, identifier: nil, role: nil, value: nil, hidden: nil, enabled: nil, selected: nil)
    }

    func accessibilityHint(_ hint: String) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: hint, identifier: nil, role: nil, value: nil, hidden: nil, enabled: nil, selected: nil)
    }

    func accessibilityIdentifier(_ identifier: String) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: nil, identifier: identifier, role: nil, value: nil, hidden: nil, enabled: nil, selected: nil)
    }

    func accessibilityRole(_ role: FluentAccessibilityRole) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: nil, identifier: nil, role: role, value: nil, hidden: nil, enabled: nil, selected: nil)
    }

    func accessibilityValue(_ value: Any) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: nil, identifier: nil, role: nil, value: value, hidden: nil, enabled: nil, selected: nil)
    }

    func accessibilityHidden(_ hidden: Bool = true) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: nil, identifier: nil, role: nil, value: nil, hidden: hidden, enabled: nil, selected: nil)
    }

    func accessibilityEnabled(_ enabled: Bool) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: nil, identifier: nil, role: nil, value: nil, hidden: nil, enabled: enabled, selected: nil)
    }

    func accessibilitySelected(_ selected: Bool) -> FluentAccessibilityView<Self> {
        FluentAccessibilityView(content: self, label: nil, hint: nil, identifier: nil, role: nil, value: nil, hidden: nil, enabled: nil, selected: selected)
    }
}
