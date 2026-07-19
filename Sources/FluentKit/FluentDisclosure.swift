import AppKit

/// A collapsible section with a Fluent-styled disclosure header.
public struct FluentDisclosureGroupView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let title: String
    fileprivate let binding: FluentBinding<Bool>?
    fileprivate let content: Content

    public init(
        _ title: String,
        isExpanded: FluentBinding<Bool>? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.title = title
        self.binding = isExpanded
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentDisclosureHost(
            title: title,
            binding: binding,
            content: content._mount(in: context),
            context: context
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentDisclosureHost else { return false }
        host.update(title: title, binding: binding, context: context)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentDisclosureHeader: NSButton {
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    var expanded = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: theme.controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: isEnabled ? theme.textPrimary : theme.textDisabled
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let titleRect = NSRect(
            x: 28,
            y: bounds.midY - titleSize.height / 2,
            width: max(bounds.width - 28, titleSize.width),
            height: titleSize.height
        )
        let chevron = NSBezierPath()
        let center = NSPoint(x: 10, y: bounds.midY)
        if expanded {
            chevron.move(to: NSPoint(x: center.x - 3.5, y: center.y + 2))
            chevron.line(to: NSPoint(x: center.x + 3.5, y: center.y + 2))
            chevron.line(to: NSPoint(x: center.x, y: center.y - 2.5))
        } else {
            chevron.move(to: NSPoint(x: center.x - 2.5, y: center.y + 3.5))
            chevron.line(to: NSPoint(x: center.x + 2.5, y: center.y))
            chevron.line(to: NSPoint(x: center.x - 2.5, y: center.y - 3.5))
        }
        theme.textSecondary.setStroke()
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()
        (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)
    }
}

private final class FluentDisclosureHost: NSView {
    private var title: String
    private var binding: FluentBinding<Bool>?
    private var context: FluentRenderContext
    private var observerID: UUID?
    private var isApplyingBinding = false
    private let stack = NSStackView()
    private let header = FluentDisclosureHeader(frame: .zero)
    private let contentContainer = NSView()
    private(set) var isExpanded: Bool
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { contentContainer.subviews[0] }

    init(title: String, binding: FluentBinding<Bool>?, content: NSView, context: FluentRenderContext) {
        self.title = title
        self.binding = binding
        self.context = context
        isExpanded = binding?.get() ?? false
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        header.title = title
        header.theme = context.theme
        header.target = self
        header.action = #selector(toggle)
        header.setButtonType(.momentaryPushIn)
        header.isBordered = false
        header.alignment = .left
        header.contentTintColor = context.theme.textPrimary
        header.setAccessibilityRole(.disclosureTriangle)
        header.setAccessibilityTitle(title)
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        stack.addArrangedSubview(contentContainer)
        contentContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        installObserver()
        applyExpanded(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, binding: FluentBinding<Bool>?, context: FluentRenderContext) {
        if let observerID { self.binding?.removeObserver?(observerID) }
        self.title = title
        self.binding = binding
        self.context = context
        header.title = title
        header.theme = context.theme
        header.setAccessibilityTitle(title)
        if let binding { isExpanded = binding.get() }
        installObserver()
        applyExpanded(animated: false)
    }

    private func installObserver() {
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isExpanded != value else { return }
                self.isExpanded = value
                self.applyExpanded(animated: true)
            }
        }
    }

    @objc private func toggle() {
        guard header.isEnabled else { return }
        let value = !isExpanded
        isExpanded = value
        if let binding, !isApplyingBinding {
            isApplyingBinding = true
            binding.set(value)
            isApplyingBinding = false
        }
        applyExpanded(animated: true)
    }

    private func applyExpanded(animated: Bool) {
        header.expanded = isExpanded
        header.setAccessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        contentContainer.isHidden = !isExpanded
        let effectiveAnimated = animated && !context.reduceMotion
        let duration = effectiveAnimated ? context.animationDuration : 0
        NSAnimationContext.runAnimationGroup { animationContext in
            animationContext.duration = duration
            animationContext.timingFunction = context.animationTimingFunction
            animationContext.allowsImplicitAnimation = effectiveAnimated
            contentContainer.animator().alphaValue = isExpanded ? 1 : 0
        }
        needsLayout = true
    }

    deinit {
        if let observerID { binding?.removeObserver?(observerID) }
    }
}

public func FluentDisclosureGroup<Content: FluentView>(
    _ title: String,
    isExpanded: FluentBinding<Bool>? = nil,
    @FluentViewBuilder content: () -> Content
) -> FluentDisclosureGroupView<Content> {
    FluentDisclosureGroupView(title, isExpanded: isExpanded, content: content)
}
