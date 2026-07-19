import AppKit

public enum FluentValidationState: Equatable, Sendable {
    case none
    case success(String?)
    case warning(String)
    case error(String)

    public static var valid: FluentValidationState { .success(nil) }

    public var message: String? {
        switch self {
        case .none: return nil
        case let .success(message): return message
        case let .warning(message), let .error(message): return message
        }
    }

    public var isValid: Bool {
        switch self {
        case .none, .success: return true
        case .warning, .error: return false
        }
    }
}

/// A labeled form field with optional help and validation feedback. Its content is an ordinary
/// Fluent view, so text fields, pickers, toggles, and custom controls share one validation model.
public struct FluentFormField<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let title: String
    private let help: String?
    private let validation: FluentValidationState
    private let required: Bool
    private let content: Content

    public init(
        _ title: String,
        help: String? = nil,
        validation: FluentValidationState = .none,
        required: Bool = false,
        @FluentViewBuilder content: () -> Content
    ) {
        self.title = title
        self.help = help
        self.validation = validation
        self.required = required
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFormFieldHost(
            title: title,
            help: help,
            validation: validation,
            required: required,
            content: content._mount(in: context),
            theme: context.theme
        )
        host.updateContent = { [content] native, updateContext in content._update(native, in: updateContext) }
        host.makeContent = { [content] updateContext in content._mount(in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFormFieldHost else { return false }
        if !(host.updateContent?(host.contentView, context) ?? false),
           let makeContent = host.makeContent {
            host.replaceContent(makeContent(context))
        }
        host.update(
            title: title,
            help: help,
            validation: validation,
            required: required,
            theme: context.theme
        )
        return true
    }
}

private final class FluentFormFieldHost: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let helpLabel = NSTextField(labelWithString: "")
    let validationLabel = NSTextField(labelWithString: "")
    let contentContainer = NSView()
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var makeContent: ((FluentRenderContext) -> NSView)?
    var contentView: NSView { contentContainer.subviews[0] }

    init(
        title: String,
        help: String?,
        validation: FluentValidationState,
        required: Bool,
        content: NSView,
        theme: FluentTheme
    ) {
        super.init(frame: .zero)
        [titleLabel, helpLabel, validationLabel].forEach {
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
        }
        contentContainer.wantsLayer = true
        contentContainer.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        let stack = NSStackView(views: [titleLabel, contentContainer, helpLabel, validationLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        update(title: title, help: help, validation: validation, required: required, theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func replaceContent(_ content: NSView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    func update(
        title: String,
        help: String?,
        validation: FluentValidationState,
        required: Bool,
        theme: FluentTheme
    ) {
        titleLabel.stringValue = title + (required ? " *" : "")
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = theme.textPrimary
        helpLabel.stringValue = help ?? ""
        helpLabel.isHidden = help?.isEmpty != false
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = theme.textSecondary
        validationLabel.stringValue = validation.message ?? ""
        validationLabel.isHidden = validation.message == nil
        validationLabel.font = .systemFont(ofSize: 11, weight: .medium)

        let validationColor: NSColor?
        switch validation {
        case .none: validationColor = nil
        case .success: validationColor = .systemGreen
        case .warning: validationColor = .systemOrange
        case .error: validationColor = .systemRed
        }
        validationLabel.textColor = validationColor ?? theme.textSecondary
        contentContainer.layer?.cornerRadius = 8
        let showsValidationBorder: Bool = switch validation {
        case .warning, .error: true
        case .none, .success: false
        }
        contentContainer.layer?.borderWidth = showsValidationBorder ? 1.5 : 0
        contentContainer.layer?.borderColor = validationColor?.withAlphaComponent(0.8).cgColor

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        setAccessibilityHelp(validation.message ?? help)
        setAccessibilityValue(validation.isValid ? "Valid" : "Invalid")
        setAccessibilityChildren([contentView])
    }
}

/// An unframed group of related fields with a semantic heading and optional footer.
public struct FluentFormSection<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let title: String
    private let footer: String?
    private let content: Content

    public init(
        _ title: String,
        footer: String? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFormSectionHost(
            title: title,
            footer: footer,
            content: content._mount(in: context),
            theme: context.theme
        )
        host.updateContent = { [content] native, updateContext in content._update(native, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFormSectionHost else { return false }
        guard host.updateContent?(host.contentView, context) ?? false else { return false }
        host.update(title: title, footer: footer, theme: context.theme)
        return true
    }
}

private final class FluentFormSectionHost: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let divider = NSBox()
    let contentContainer = NSView()
    let footerLabel = NSTextField(labelWithString: "")
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { contentContainer.subviews[0] }

    init(title: String, footer: String?, content: NSView, theme: FluentTheme) {
        super.init(frame: .zero)
        divider.boxType = .separator
        contentContainer.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        footerLabel.lineBreakMode = .byWordWrapping
        footerLabel.maximumNumberOfLines = 0
        let stack = NSStackView(views: [titleLabel, divider, contentContainer, footerLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            contentContainer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        update(title: title, footer: footer, theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, footer: String?, theme: FluentTheme) {
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = theme.textPrimary
        footerLabel.stringValue = footer ?? ""
        footerLabel.isHidden = footer?.isEmpty != false
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = theme.textSecondary
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        setAccessibilityChildren([contentView])
    }
}

/// A compact label/value pair useful outside full form sections.
public struct FluentLabeledContent<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let title: String
    private let labelWidth: CGFloat
    private let content: Content

    public init(
        _ title: String,
        labelWidth: CGFloat = 140,
        @FluentViewBuilder content: () -> Content
    ) {
        self.title = title
        self.labelWidth = max(labelWidth, 40)
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentLabeledContentHost(
            title: title,
            labelWidth: labelWidth,
            content: content._mount(in: context),
            theme: context.theme
        )
        host.updateContent = { [content] native, updateContext in content._update(native, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentLabeledContentHost else { return false }
        guard host.updateContent?(host.contentView, context) ?? false else { return false }
        host.update(title: title, labelWidth: labelWidth, theme: context.theme)
        return true
    }
}

private final class FluentLabeledContentHost: NSView {
    let label = NSTextField(labelWithString: "")
    let contentContainer = NSView()
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { contentContainer.subviews[0] }
    private var widthConstraint: NSLayoutConstraint!

    init(title: String, labelWidth: CGFloat, content: NSView, theme: FluentTheme) {
        super.init(frame: .zero)
        contentContainer.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        let stack = NSStackView(views: [label, contentContainer])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        widthConstraint = label.widthAnchor.constraint(equalToConstant: labelWidth)
        widthConstraint.isActive = true
        update(title: title, labelWidth: labelWidth, theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, labelWidth: CGFloat, theme: FluentTheme) {
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = theme.textPrimary
        widthConstraint.constant = labelWidth
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        setAccessibilityChildren([contentView])
    }
}
