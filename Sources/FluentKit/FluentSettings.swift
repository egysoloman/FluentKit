import AppKit

/// A WinUI-style settings row. The optional trailing action is mounted as a real Fluent view, so
/// toggles, ComboBoxes, buttons, and custom controls keep their own responder and accessibility
/// behavior instead of being flattened into a label.
public struct FluentSettingsCardView<Action: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let title: String
    fileprivate let description: String?
    fileprivate let systemImageName: String?
    fileprivate let isEnabled: Bool
    fileprivate let showsChevron: Bool
    fileprivate let onActivate: (() -> Void)?
    fileprivate let action: Action
    fileprivate let hasAction: Bool

    public init(
        _ title: String,
        description: String? = nil,
        systemImageName: String? = nil,
        isEnabled: Bool = true,
        showsChevron: Bool? = nil,
        onActivate: (() -> Void)? = nil,
        @FluentViewBuilder action: () -> Action
    ) {
        self.title = title
        self.description = description
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.action = action()
        hasAction = !(Action.self == FluentEmptyView.self)
        self.showsChevron = showsChevron ?? (onActivate != nil && !hasAction)
        self.onActivate = onActivate
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let actionView = action._mount(in: context)
        let host = FluentSettingsCardHost(
            title: title,
            description: description,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            showsChevron: showsChevron,
            onActivate: onActivate,
            action: actionView,
            hasAction: hasAction,
            context: context
        )
        host.updateAction = { [action] nativeView, updateContext in
            action._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSettingsCardHost else { return false }
        guard host.updateAction?(host.actionView, context) ?? false else { return false }
        host.update(
            title: title,
            description: description,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            showsChevron: showsChevron,
            onActivate: onActivate,
            hasAction: hasAction,
            context: context
        )
        return true
    }
}

/// A settings card without a trailing action. Use `onActivate` for a navigable settings row.
public func FluentSettingsCard(
    _ title: String,
    description: String? = nil,
    systemImageName: String? = nil,
    isEnabled: Bool = true,
    showsChevron: Bool? = nil,
    onActivate: (() -> Void)? = nil
) -> FluentSettingsCardView<FluentEmptyView> {
    FluentSettingsCardView(
        title,
        description: description,
        systemImageName: systemImageName,
        isEnabled: isEnabled,
        showsChevron: showsChevron,
        onActivate: onActivate
    ) { FluentEmptyView() }
}

/// A settings card with an arbitrary trailing Fluent control.
public func FluentSettingsCard<Action: FluentView>(
    _ title: String,
    description: String? = nil,
    systemImageName: String? = nil,
    isEnabled: Bool = true,
    showsChevron: Bool? = nil,
    onActivate: (() -> Void)? = nil,
    @FluentViewBuilder action: () -> Action
) -> FluentSettingsCardView<Action> {
    FluentSettingsCardView(
        title,
        description: description,
        systemImageName: systemImageName,
        isEnabled: isEnabled,
        showsChevron: showsChevron,
        onActivate: onActivate,
        action: action
    )
}

/// A vertical group of settings rows. The group owns the shared surface and the one-pixel gaps,
/// which keeps adjacent rows visually connected without asking each row to guess its corner role.
public struct FluentSettingsSectionView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let title: String?
    fileprivate let description: String?
    fileprivate let content: FluentAnyView

    public init(
        _ title: String? = nil,
        description: String? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = FluentAnyView(content())
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentSettingsSectionHost(title: title, description: description, content: content, context: context)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSettingsSectionHost else { return false }
        return host.update(title: title, description: description, content: content, context: context)
    }
}

public func FluentSettingsSection<Content: FluentView>(
    _ title: String? = nil,
    description: String? = nil,
    @FluentViewBuilder content: () -> Content
) -> FluentSettingsSectionView<Content> {
    FluentSettingsSectionView(title, description: description, content: content)
}

/// A settings expander keeps its header and child content in one connected surface. Its child is
/// an arbitrary Fluent view, allowing nested SettingsSection/Card rows and custom content.
public struct FluentSettingsExpanderView<Action: FluentView, Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let title: String
    fileprivate let description: String?
    fileprivate let systemImageName: String?
    fileprivate let isExpanded: FluentBinding<Bool>?
    fileprivate let isEnabled: Bool
    fileprivate let action: Action
    fileprivate let content: Content
    fileprivate let hasAction: Bool

    public init(
        _ title: String,
        description: String? = nil,
        systemImageName: String? = nil,
        isExpanded: FluentBinding<Bool>? = nil,
        isEnabled: Bool = true,
        @FluentViewBuilder action: () -> Action,
        @FluentViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.systemImageName = systemImageName
        self.isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.action = action()
        self.content = content()
        hasAction = !(Action.self == FluentEmptyView.self)
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentSettingsExpanderHost(
            title: title,
            description: description,
            systemImageName: systemImageName,
            binding: isExpanded,
            isEnabled: isEnabled,
            action: action._mount(in: context),
            hasAction: hasAction,
            content: content._mount(in: context),
            context: context
        )
        host.updateAction = { [action] nativeView, updateContext in
            action._update(nativeView, in: updateContext)
        }
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSettingsExpanderHost else { return false }
        // Update with the new value's closures, not the callbacks captured when the host was
        // first mounted. Type-erased Gallery samples have the same outer Content type while the
        // underlying control changes; replaying the old callback kept Button mounted on the
        // CheckBox page and RadioButton mounted on the Slider page.
        guard action._update(host.actionView, in: context),
              content._update(host.contentView, in: context) else { return false }
        host.updateAction = { [action] nativeView, updateContext in
            action._update(nativeView, in: updateContext)
        }
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        host.update(
            title: title,
            description: description,
            systemImageName: systemImageName,
            binding: isExpanded,
            isEnabled: isEnabled,
            hasAction: hasAction,
            context: context
        )
        return true
    }
}

public func FluentSettingsExpander<Content: FluentView>(
    _ title: String,
    description: String? = nil,
    systemImageName: String? = nil,
    isExpanded: FluentBinding<Bool>? = nil,
    isEnabled: Bool = true,
    @FluentViewBuilder content: () -> Content
) -> FluentSettingsExpanderView<FluentEmptyView, Content> {
    FluentSettingsExpanderView(
        title,
        description: description,
        systemImageName: systemImageName,
        isExpanded: isExpanded,
        isEnabled: isEnabled,
        action: { FluentEmptyView() },
        content: content
    )
}

public func FluentSettingsExpander<Action: FluentView, Content: FluentView>(
    _ title: String,
    description: String? = nil,
    systemImageName: String? = nil,
    isExpanded: FluentBinding<Bool>? = nil,
    isEnabled: Bool = true,
    @FluentViewBuilder action: () -> Action,
    @FluentViewBuilder content: () -> Content
) -> FluentSettingsExpanderView<Action, Content> {
    FluentSettingsExpanderView(
        title,
        description: description,
        systemImageName: systemImageName,
        isExpanded: isExpanded,
        isEnabled: isEnabled,
        action: action,
        content: content
    )
}

private final class FluentSettingsCardHost: NSView, FluentAppearanceParticipant, FluentFillWidthProviding {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let labels = NSStackView()
    private let row = NSStackView()
    private var rowTrailingConstraint: NSLayoutConstraint!
    private let actionContainer = FluentSettingsActionContainer()
    private let chevronLayer = FluentChevronPrimitiveLayer()
    private let animationCoordinator = FluentAnimationCoordinator()
    private var trackingArea: NSTrackingArea?
    private var context: FluentRenderContext
    private var onActivate: (() -> Void)?
    private var isInteractive = false
    private var isEnabled = true
    private var isPointerOver = false
    private var isPressed = false
    private var hasAction = false
    private var showsChevron = false
    private var systemImageName: String?
    private var chevronIsExpander = false
    private var chevronExpanded = false
    private var isFramed = true
    var updateAction: ((NSView, FluentRenderContext) -> Bool)?
    var actionView: NSView { actionContainer.subviews[0] }

    init(
        title: String,
        description: String?,
        systemImageName: String?,
        isEnabled: Bool,
        showsChevron: Bool,
        onActivate: (() -> Void)?,
        action: NSView,
        hasAction: Bool,
        context: FluentRenderContext
    ) {
        self.context = context
        self.isEnabled = isEnabled
        self.onActivate = onActivate
        self.hasAction = hasAction
        self.showsChevron = showsChevron
        self.systemImageName = systemImageName
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.Card")
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        chevronLayer.name = "FluentKit.Settings.Chevron"
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = context.theme.accent
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 2
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(descriptionLabel)

        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.ActionContainer")
        actionContainer.setContentHuggingPriority(.required, for: .horizontal)
        actionContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        actionContainer.addSubview(action)
        action.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            action.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor),
            action.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            action.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            action.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor)
        ])

        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        row.addArrangedSubview(iconView)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(actionContainer)
        rowTrailingConstraint = row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowTrailingConstraint,
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
        apply(
            title: title,
            description: description,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            showsChevron: showsChevron,
            onActivate: onActivate,
            hasAction: hasAction,
            context: context
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { isInteractive }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        isFramed = !hasSettingsSurfaceAncestor
        applySurface(animated: false)
    }

    override func layout() {
        super.layout()
        updateChevron(animated: false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(localPoint), isEnabled else { return nil }
        let target = super.hitTest(point)
        if hasAction,
           let target,
           target === actionView || target.isDescendant(of: actionView) {
            return target
        }
        return isInteractive ? self : target
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        isPointerOver = true
        applySurface(animated: true)
        updateChevron(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        isPressed = false
        applySurface(animated: true)
        updateChevron(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return super.mouseDown(with: event) }
        _ = window?.makeFirstResponder(self)
        isPressed = true
        applySurface(animated: true)
        updateChevron(animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractive else { return super.mouseDragged(with: event) }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard isPressed != inside else { return }
        isPressed = inside
        applySurface(animated: true)
        updateChevron(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive else { return super.mouseUp(with: event) }
        let activates = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        applySurface(animated: true)
        updateChevron(animated: true)
        if activates { onActivate?() }
    }

    override func keyDown(with event: NSEvent) {
        guard isInteractive, event.keyCode == 36 || event.keyCode == 49 else {
            return super.keyDown(with: event)
        }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractive, isEnabled else { return false }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        onActivate?()
        return true
    }

    func update(
        title: String,
        description: String?,
        systemImageName: String?,
        isEnabled: Bool,
        showsChevron: Bool,
        onActivate: (() -> Void)?,
        hasAction: Bool,
        context: FluentRenderContext
    ) {
        apply(
            title: title,
            description: description,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            showsChevron: showsChevron,
            onActivate: onActivate,
            hasAction: hasAction,
            context: context
        )
        actionContainer.invalidateIntrinsicContentSize()
    }

    func applyFluentAppearance(_ theme: FluentTheme) {
        context.theme = theme
        var childContext = context
        childContext.theme = theme
        _ = updateAction?(actionView, childContext)
        titleLabel.textColor = isEnabled ? theme.textPrimary : theme.textDisabled
        descriptionLabel.textColor = isEnabled ? theme.textSecondary : theme.textDisabled
        iconView.contentTintColor = isEnabled ? theme.accent : theme.textDisabled
        applySurface(animated: false)
        updateChevron(animated: false)
    }

    func configureAsExpander() {
        chevronIsExpander = true
        setAccessibilityRole(.disclosureTriangle)
        needsLayout = true
    }

    func setChevronExpanded(_ expanded: Bool, animated: Bool) {
        setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
        guard chevronExpanded != expanded else { return }
        chevronExpanded = expanded
        updateChevron(animated: animated)
    }

    private func apply(
        title: String,
        description: String?,
        systemImageName: String?,
        isEnabled: Bool,
        showsChevron: Bool,
        onActivate: (() -> Void)?,
        hasAction: Bool,
        context: FluentRenderContext
    ) {
        self.context = context
        self.isEnabled = isEnabled
        self.onActivate = onActivate
        self.hasAction = hasAction
        self.showsChevron = showsChevron
        self.systemImageName = systemImageName
        isInteractive = onActivate != nil && isEnabled
        titleLabel.stringValue = title
        titleLabel.font = context.theme.typography.font(for: .body)
        titleLabel.textColor = isEnabled ? context.theme.textPrimary : context.theme.textDisabled
        descriptionLabel.stringValue = description ?? ""
        descriptionLabel.font = context.theme.typography.font(for: .caption)
        descriptionLabel.textColor = isEnabled ? context.theme.textSecondary : context.theme.textDisabled
        descriptionLabel.isHidden = description?.isEmpty != false
        iconView.image = systemImageName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
        iconView.isHidden = systemImageName == nil
        iconView.contentTintColor = isEnabled ? context.theme.accent : context.theme.textDisabled
        actionContainer.isHidden = !hasAction
        actionContainer.alphaValue = isEnabled ? 1 : 0.6
        rowTrailingConstraint.constant = showsChevron ? -42 : -16
        if showsChevron {
            if chevronLayer.superlayer == nil { layer?.addSublayer(chevronLayer) }
            chevronLayer.isHidden = false
        } else {
            chevronLayer.isHidden = true
        }
        applySurface(animated: false)
        needsLayout = true
        updateChevron(animated: false)
        setAccessibilityElement(true)
        setAccessibilityRole(isInteractive ? .button : .group)
        setAccessibilityLabel(title)
        setAccessibilityEnabled(isEnabled)
        setAccessibilityChildren(hasAction ? [actionView] : [])
    }

    private var hasSettingsSurfaceAncestor: Bool {
        var current = superview
        while let ancestor = current {
            if ancestor.identifier?.rawValue == "FluentKit.Settings.Section"
                || ancestor.identifier?.rawValue == "FluentKit.Settings.Expander" {
                return true
            }
            current = ancestor.superview
        }
        return false
    }

    private func applySurface(animated: Bool) {
        guard let layer else { return }
        let fill: NSColor
        if !isEnabled {
            fill = context.theme.controlFillDisabled
        } else if isPressed {
            fill = context.theme.subtleFillTertiary
        } else if isPointerOver {
            fill = context.theme.subtleFillSecondary
        } else {
            fill = isFramed ? context.theme.cardFill : context.theme.cardFill
        }
        let stroke = isFramed ? context.theme.cardStroke : .clear
        let radius = isFramed ? context.theme.cardCornerRadius : 0
        let change = FluentLayerAnimationChange(
            layer: layer,
            key: "fluent.settings.card.fill",
            keyPath: "backgroundColor",
            toValue: fill.cgColor
        ) { [weak self] in self?.layer?.setValue(fill.cgColor, forKeyPath: "backgroundColor") }
        if animated && window != nil {
            animationCoordinator.animateState([change], motion: FluentMotion.controlFast, animated: true)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = fill.cgColor
            CATransaction.commit()
        }
        layer.cornerRadius = radius
        layer.borderWidth = isFramed ? context.theme.controlStrokeWidth : 0
        layer.borderColor = stroke.cgColor
        layer.masksToBounds = true
    }

    private func updateChevron(animated: Bool) {
        guard showsChevron, bounds.width > 0, bounds.height > 0 else { return }
        let state: FluentControlState = !isEnabled
            ? .disabled
            : (isPressed ? .pressed : (isPointerOver ? .pointerOver : .normal))
        let color: NSColor = switch state {
        case .pressed: context.theme.textSecondary.withAlphaComponent(0.72)
        case .pointerOver: context.theme.textSecondary.withAlphaComponent(0.86)
        case .disabled: context.theme.textDisabled
        default: context.theme.textSecondary
        }
        let isRTL = context.layoutDirection == .rightToLeft
        let direction: FluentChevronDirection = if chevronIsExpander {
            chevronExpanded ? .down : (isRTL ? .left : .right)
        } else {
            isRTL ? .left : .right
        }
        chevronLayer.update(
            frame: NSRect(
                x: isRTL ? bounds.minX + 14 : bounds.maxX - 26,
                y: bounds.midY - 6,
                width: 12,
                height: 12
            ),
            color: color,
            state: state,
            visual: chevronIsExpander ? .upDownSmall : .directional,
            direction: direction,
            backingScale: window?.backingScaleFactor,
            animated: animated && !context.reduceMotion
        )
    }
}

private final class FluentSettingsSectionHost: NSView, FluentAppearanceParticipant, FluentFillWidthProviding {
    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let headerStack = NSStackView()
    private let itemsSurface = NSView()
    private let itemsStack = NSStackView()
    private var headerGapConstraint: NSLayoutConstraint!
    private var itemViews: [NSView] = []
    private var itemWidthConstraints: [NSLayoutConstraint] = []
    private var headerWidthConstraints: [NSLayoutConstraint] = []
    private var context: FluentRenderContext

    init(title: String?, description: String?, content: FluentAnyView, context: FluentRenderContext) {
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.Section")
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        headerStack.orientation = .vertical
        headerStack.alignment = .width
        headerStack.spacing = 3
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(descriptionLabel)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.alignment = .left
        descriptionLabel.alignment = .left
        headerWidthConstraints = [
            titleLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor),
            descriptionLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor)
        ]
        NSLayoutConstraint.activate(headerWidthConstraints)

        itemsSurface.wantsLayer = true
        itemsSurface.layer?.masksToBounds = true
        itemsSurface.layer?.cornerCurve = .continuous
        itemsSurface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(itemsSurface)
        itemsStack.orientation = .vertical
        itemsStack.alignment = .width
        itemsStack.spacing = 1
        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        itemsSurface.addSubview(itemsStack)
        let hasHeader = title?.isEmpty == false || description?.isEmpty == false
        headerGapConstraint = itemsSurface.topAnchor.constraint(
            equalTo: headerStack.bottomAnchor,
            constant: hasHeader ? 12 : 0
        )
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            itemsSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemsSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerGapConstraint,
            itemsSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            itemsStack.leadingAnchor.constraint(equalTo: itemsSurface.leadingAnchor),
            itemsStack.trailingAnchor.constraint(equalTo: itemsSurface.trailingAnchor),
            itemsStack.topAnchor.constraint(equalTo: itemsSurface.topAnchor),
            itemsStack.bottomAnchor.constraint(equalTo: itemsSurface.bottomAnchor)
        ])
        replaceItems(content.children ?? [content], context: context)
        apply(title: title, description: description, context: context)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String?, description: String?, content: FluentAnyView, context: FluentRenderContext) -> Bool {
        self.context = context
        let children = content.children ?? [content]
        guard children.count == itemViews.count else {
            replaceItems(children, context: context)
            apply(title: title, description: description, context: context)
            return true
        }
        for index in children.indices {
            if !children[index]._update(itemViews[index], in: context) {
                return false
            }
        }
        apply(title: title, description: description, context: context)
        return true
    }

    func applyFluentAppearance(_ theme: FluentTheme) {
        context.theme = theme
        apply(title: titleLabel.stringValue, description: descriptionLabel.stringValue, context: context)
    }

    private func replaceItems(_ children: [FluentAnyView], context: FluentRenderContext) {
        NSLayoutConstraint.deactivate(itemWidthConstraints)
        itemWidthConstraints.removeAll(keepingCapacity: true)
        itemViews.forEach {
            itemsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        itemViews = children.map { $0._mount(in: context) }
        itemViews.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            itemsStack.addArrangedSubview($0)
        }
        itemWidthConstraints = itemViews.map {
            $0.widthAnchor.constraint(equalTo: itemsStack.widthAnchor)
        }
        NSLayoutConstraint.activate(itemWidthConstraints)
    }

    private func apply(title: String?, description: String?, context: FluentRenderContext) {
        titleLabel.stringValue = title ?? ""
        titleLabel.font = context.theme.typography.font(for: .headline)
        titleLabel.textColor = context.theme.textPrimary
        titleLabel.isHidden = title?.isEmpty != false
        descriptionLabel.stringValue = description ?? ""
        descriptionLabel.font = context.theme.typography.font(for: .caption)
        descriptionLabel.textColor = context.theme.textSecondary
        descriptionLabel.isHidden = description?.isEmpty != false
        headerGapConstraint.constant = (title?.isEmpty == false || description?.isEmpty == false) ? 12 : 0
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        itemsSurface.layer?.backgroundColor = context.theme.divider.cgColor
        itemsSurface.layer?.borderColor = context.theme.cardStroke.cgColor
        itemsSurface.layer?.borderWidth = context.theme.controlStrokeWidth
        itemsSurface.layer?.cornerRadius = context.theme.cardCornerRadius
    }
}

private final class FluentSettingsActionContainer: NSView {
    override var intrinsicContentSize: NSSize {
        guard !isHidden, let action = subviews.first else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        let intrinsic = action.intrinsicContentSize
        let fitting = action.fittingSize
        return NSSize(
            width: resolvedMetric(intrinsic.width, fitting: fitting.width),
            height: resolvedMetric(intrinsic.height, fitting: fitting.height)
        )
    }

    override func layout() {
        super.layout()
        guard !isHidden, let action = subviews.first, bounds.width > 0, bounds.height > 0 else { return }
        assert(
            bounds.insetBy(dx: -0.5, dy: -0.5).contains(action.frame),
            "FluentSettingsCard action must remain inside its action slot"
        )
    }

    private func resolvedMetric(_ intrinsic: CGFloat, fitting: CGFloat) -> CGFloat {
        if intrinsic != NSView.noIntrinsicMetric { return max(0, intrinsic) }
        return fitting > 0 ? fitting : NSView.noIntrinsicMetric
    }
}

private final class FluentSettingsExpanderHost: NSView, FluentAppearanceParticipant, FluentFillWidthProviding {
    let actionView: NSView
    let contentView: NSView
    var updateAction: ((NSView, FluentRenderContext) -> Bool)?
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?

    private var header: FluentSettingsCardHost!
    private let stack = NSStackView()
    private let contentContainer = NSView()
    private let contentSeparator = NSView()
    private var contentHeight: NSLayoutConstraint!
    private var binding: FluentBinding<Bool>?
    private var observerID: UUID?
    private var context: FluentRenderContext
    private var isExpanded = false
    private var hasAppliedExpandedState = false
    private var isEnabled = true
    private var hasAction = false
    private let animationCoordinator = FluentAnimationCoordinator()
    private var expansionGeneration: UInt64 = 0

    init(
        title: String,
        description: String?,
        systemImageName: String?,
        binding: FluentBinding<Bool>?,
        isEnabled: Bool,
        action: NSView,
        hasAction: Bool,
        content: NSView,
        context: FluentRenderContext
    ) {
        self.actionView = action
        self.contentView = content
        self.binding = binding
        self.context = context
        self.isExpanded = binding?.get() ?? false
        self.isEnabled = isEnabled
        self.hasAction = hasAction
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.Expander")
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        animationCoordinator.reduceMotion = context.reduceMotion

        header = FluentSettingsCardHost(
            title: title,
            description: description,
            systemImageName: systemImageName,
            isEnabled: isEnabled,
            showsChevron: true,
            onActivate: { [weak self] in self?.toggle() },
            action: action,
            hasAction: hasAction,
            context: context
        )
        header.identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.Expander.Header")
        header.configureAsExpander()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.addArrangedSubview(header)

        contentContainer.wantsLayer = true
        contentContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.Expander.Viewport")
        contentContainer.layer?.masksToBounds = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentSeparator.wantsLayer = true
        contentSeparator.identifier = NSUserInterfaceItemIdentifier("FluentKit.Settings.Expander.Separator")
        contentSeparator.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentSeparator)
        contentContainer.addSubview(content)
        if let contentStack = content as? NSStackView { contentStack.spacing = 1 }
        content.translatesAutoresizingMaskIntoConstraints = false
        let contentBottomConstraint = content.bottomAnchor.constraint(
            lessThanOrEqualTo: contentContainer.bottomAnchor,
            constant: -12
        )
        contentBottomConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 8),
            contentBottomConstraint,
            contentSeparator.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSeparator.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSeparator.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentSeparator.heightAnchor.constraint(equalToConstant: 1),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        stack.addArrangedSubview(contentContainer)
        contentContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        contentHeight = contentContainer.heightAnchor.constraint(equalToConstant: 0)
        contentHeight.isActive = true
        installObserver()
        applySurface()
        applyExpanded(animated: false, force: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isExpanded else { return }
            self.applyExpanded(animated: false, force: true)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let headerHeight = max(header?.fittingSize.height ?? 0, 64)
        return NSSize(width: NSView.noIntrinsicMetric, height: headerHeight + (contentHeight?.constant ?? 0))
    }

    func update(
        title: String,
        description: String?,
        systemImageName: String?,
        binding: FluentBinding<Bool>?,
        isEnabled: Bool,
        hasAction: Bool,
        context: FluentRenderContext
    ) {
        let bindingChanged = binding?.observationIdentity != self.binding?.observationIdentity
            || (binding?.observationIdentity == nil) != (self.binding?.observationIdentity == nil)
        if bindingChanged, let observerID {
            self.binding?.removeObserver?(observerID)
            self.observerID = nil
        }
        self.binding = binding
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        self.isEnabled = isEnabled
        self.hasAction = hasAction
        if let contentStack = contentView as? NSStackView { contentStack.spacing = 1 }
        installObserver()
        if let header {
            header.update(
                title: title,
                description: description,
                systemImageName: systemImageName,
                isEnabled: isEnabled,
                showsChevron: true,
                onActivate: { [weak self] in self?.toggle() },
                hasAction: hasAction,
                context: context
            )
            header.configureAsExpander()
        }
        applySurface()
        let requestedExpanded = binding?.get() ?? isExpanded
        if requestedExpanded != isExpanded {
            receiveExpandedValue(requestedExpanded, animated: window != nil)
        } else if !hasAppliedExpandedState {
            applyExpanded(animated: false, force: true)
        }
    }

    func prepareForFluentAppearanceChange() {
        expansionGeneration &+= 1
        animationCoordinator.cancelAllValueAnimations()
        animationCoordinator.cancelAll(on: [layer, contentContainer.layer].compactMap { $0 })
        contentHeight.constant = isExpanded ? measuredContentHeight() : 0
        invalidateIntrinsicContentSize()
        contentContainer.layer?.opacity = isExpanded ? 1 : 0
        contentContainer.isHidden = !isExpanded
        header.setChevronExpanded(isExpanded, animated: false)
        needsLayout = true
    }

    func applyFluentAppearance(_ theme: FluentTheme) {
        context.theme = theme
        applySurface()
    }

    private func installObserver() {
        guard observerID == nil, let binding else { return }
        observerID = binding.observe { [weak self] value in
            let apply: () -> Void = { [weak self] in
                self?.receiveExpandedValue(value, animated: true)
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func toggle() {
        guard isEnabled else { return }
        if let binding {
            binding.set(!binding.get())
            if observerID == nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let binding = self.binding else { return }
                    self.receiveExpandedValue(binding.get(), animated: true)
                }
            }
        } else {
            receiveExpandedValue(!isExpanded, animated: true)
        }
    }

    private func receiveExpandedValue(_ value: Bool, animated: Bool) {
        guard value != isExpanded || !hasAppliedExpandedState else { return }
        isExpanded = value
        applyExpanded(animated: animated, force: true)
    }

    private func measuredContentHeight() -> CGFloat {
        layoutSubtreeIfNeeded()
        let intrinsic = contentView.intrinsicContentSize.height
        let fitting = contentView.fittingSize.height
        let desired = intrinsic == NSView.noIntrinsicMetric ? fitting : intrinsic
        return max(desired + 20, 20)
    }

    private func applyExpanded(animated: Bool, force: Bool = false) {
        guard force || !hasAppliedExpandedState else { return }
        hasAppliedExpandedState = true
        expansionGeneration &+= 1
        let generation = expansionGeneration
        let expanded = isExpanded
        if expanded { contentContainer.isHidden = false }
        let target = expanded ? measuredContentHeight() : 0
        let current = contentHeight.constant
        // Detached views are commonly measured before they enter a window. Resolve those state
        // changes synchronously so fittingSize reflects the binding immediately; mounted views
        // continue through the shared animation coordinator.
        let effectiveAnimated = animated
            && window != nil
            && !context.reduceMotion
            && context.animationDuration > 0
        contentContainer.isHidden = false
        let motion = FluentMotionToken(
            duration: context.animationDuration,
            curve: .controlFastOutSlowIn
        )
        animationCoordinator.animateValue(
            key: "fluent.settings.expander.height",
            from: current,
            to: target,
            motion: motion,
            animated: effectiveAnimated,
            update: { [weak self] value in
                guard let self else { return }
                self.contentHeight.constant = value
                self.invalidateExpandedLayout()
            },
            completion: { [weak self] in
                guard let self, self.expansionGeneration == generation else { return }
                self.contentContainer.isHidden = !expanded
                self.contentHeight.constant = target
                self.invalidateExpandedLayout()
            }
        )
        header.setChevronExpanded(expanded, animated: effectiveAnimated)
        if let contentLayer = contentContainer.layer {
            let targetOpacity: Float = expanded ? 1 : 0
            let opacity = FluentLayerAnimationChange(
                layer: contentLayer,
                key: "fluent.settings.expander.opacity",
                keyPath: "opacity",
                fromValue: nil,
                toValue: targetOpacity
            ) { [weak contentLayer] in contentLayer?.opacity = targetOpacity }
            animationCoordinator.animateState(
                [opacity],
                motion: motion,
                animated: effectiveAnimated
            )
        }
    }

    private func invalidateExpandedLayout() {
        // NSStackView updates this control's frame as the height constraint animates, but custom
        // wrapper and scroll-document views do not automatically invalidate their own forwarded
        // fitting sizes. Propagate the new DesiredSize to the window root before hit-testing or
        // scroll tiling, matching WinUI's upward Measure invalidation.
        var view: NSView? = self
        while let current = view {
            current.invalidateIntrinsicContentSize()
            current.needsLayout = true
            view = current.superview
        }
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func applySurface() {
        layer?.backgroundColor = context.theme.cardFill.cgColor
        layer?.borderColor = context.theme.cardStroke.cgColor
        layer?.borderWidth = context.theme.controlStrokeWidth
        layer?.cornerRadius = context.theme.cardCornerRadius
        contentSeparator.layer?.backgroundColor = context.theme.divider.cgColor
    }

    deinit {
        if let observerID { binding?.removeObserver?(observerID) }
        animationCoordinator.cancelAllValueAnimations()
    }
}
