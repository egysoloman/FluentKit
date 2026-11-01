import AppKit

// Only explicitly transparent wrappers forward metadata. A semantic group/card
// must keep its own name even when it happens to contain one control.
protocol FluentAccessibilityTargetProviding: AnyObject {
    var fluentAccessibilityTarget: NSView? { get }
}

protocol FluentAccessibilitySubtreeVisibilityProviding: AnyObject {
    var fluentAccessibilityHidesContent: Bool { get }
}

private func fluentAccessibilityTarget(in view: NSView) -> NSView {
    guard let target = (view as? FluentAccessibilityTargetProviding)?.fluentAccessibilityTarget,
          target !== view else { return view }
    return fluentAccessibilityTarget(in: target)
}

private final class FluentAccessibilityVisibilityHost: NSView, FluentAccessibilityTargetProviding, FluentAccessibilitySubtreeVisibilityProviding, FluentFillWidthProviding {
    let contentView: NSView
    var fluentAccessibilityTarget: NSView? { contentView }
    var fluentFillsAvailableWidth: Bool { fluentViewFillsAvailableWidth(contentView) }
    var fluentAccessibilityHidesContent: Bool { hidesContent }
    private var hidesContent: Bool

    init(content: NSView, hidden: Bool) {
        contentView = content
        hidesContent = hidden
        super.init(frame: .zero)
        setAccessibilityElement(false)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(content.contentHuggingPriority(for: axis), for: axis)
            setContentCompressionResistancePriority(content.contentCompressionResistancePriority(for: axis), for: axis)
        }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let intrinsic = contentView.intrinsicContentSize
        let fitting = contentView.fittingSize
        return NSSize(width: intrinsic.width == NSView.noIntrinsicMetric ? fitting.width : intrinsic.width,
                      height: intrinsic.height == NSView.noIntrinsicMetric ? fitting.height : intrinsic.height)
    }

    override func accessibilityChildren() -> [Any]? {
        hidesContent ? [] : NSAccessibility.unignoredChildren(from: [contentView])
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        hidesContent ? nil : super.accessibilityHitTest(point)
    }

    func update(hidden: Bool) {
        let changed = hidesContent != hidden
        hidesContent = hidden
        invalidateIntrinsicContentSize()
        if changed, let window { NSAccessibility.post(element: window, notification: .layoutChanged) }
    }
}

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

/// Explicitly marks a composed view as an accessibility container. Its children omit ignored
/// layout/binding wrappers while preserving nested semantic groups and live content updates.
public struct FluentAccessibilityGroupView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let label: String?
    fileprivate let hint: String?
    fileprivate let identifier: String?

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentAccessibilityGroupHost(content: content._mount(in: context), label: label, hint: hint, identifier: identifier)
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentAccessibilityGroupHost else { return false }
        host.update(label: label, hint: hint, identifier: identifier)
        return content._update(host.contentView, in: context)
    }
}

private final class FluentAccessibilityGroupHost: NSView {
    var contentView: NSView { subviews[0] }

    override func accessibilityChildren() -> [Any]? {
        NSAccessibility.unignoredChildren(from: [contentView])
    }

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
        if let hidden { return FluentAccessibilityVisibilityHost(content: view, hidden: hidden) }
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        if let hidden {
            guard let host = view as? FluentAccessibilityVisibilityHost,
                  content._update(host.contentView, in: context) else { return false }
            apply(to: host.contentView)
            host.update(hidden: hidden)
            return true
        }
        guard content._update(view, in: context) else { return false }
        apply(to: view)
        return true
    }

    private func apply(to view: NSView) {
        let view = fluentAccessibilityTarget(in: view)
        if let label { view.setAccessibilityLabel(label) }
        if let hint { view.setAccessibilityHelp(hint) }
        if let identifier { view.setAccessibilityIdentifier(identifier) }
        if let role { view.setAccessibilityRole(role.nsRole) }
        if let value { view.setAccessibilityValue(value) }
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
