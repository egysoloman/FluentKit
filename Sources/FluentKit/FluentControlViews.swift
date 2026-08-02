import AppKit

public struct FluentButtonView: FluentUpdatablePrimitiveView {
    public let title: String
    public let role: FluentButtonRole
    public let action: (() -> Void)?
    public let style: (any FluentButtonStyle)?
    public let flyoutItems: [FluentMenuItem]?
    public let flyoutPlacement: FluentMenuPlacement
    public let commandBarFlyoutConfiguration: FluentCommandBarFlyoutConfiguration?

    public init(
        _ title: String,
        role: FluentButtonRole = .standard,
        action: (() -> Void)? = nil,
        style: (any FluentButtonStyle)? = nil,
        flyoutItems: [FluentMenuItem]? = nil,
        flyoutPlacement: FluentMenuPlacement = .below,
        commandBarFlyoutConfiguration: FluentCommandBarFlyoutConfiguration? = nil
    ) {
        self.title = title
        self.role = role
        self.action = action
        self.style = style
        self.flyoutItems = flyoutItems
        self.flyoutPlacement = flyoutPlacement
        self.commandBarFlyoutConfiguration = commandBarFlyoutConfiguration
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let button = FluentButton(title: title, role: role)
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.onClick = action
        button.fluentStyle = style
        button.flyoutItems = flyoutItems
        button.flyoutPlacement = flyoutPlacement
        button.commandBarFlyoutConfiguration = commandBarFlyoutConfiguration
        return button
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentButton else { return false }
        button.title = title
        button.role = role
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        button.onClick = action
        button.fluentStyle = style
        button.flyoutItems = flyoutItems
        button.flyoutPlacement = flyoutPlacement
        button.commandBarFlyoutConfiguration = commandBarFlyoutConfiguration
        button.setAccessibilityTitle(title)
        button.invalidateIntrinsicContentSize()
        return true
    }

    public func buttonStyle(_ style: any FluentButtonStyle) -> FluentButtonView {
        FluentButtonView(
            title,
            role: role,
            action: action,
            style: style,
            flyoutItems: flyoutItems,
            flyoutPlacement: flyoutPlacement,
            commandBarFlyoutConfiguration: commandBarFlyoutConfiguration
        )
    }

    /// Attaches an application-owned MenuFlyout to this button, matching WinUI's
    /// `Button.Flyout` relationship.
    public func flyout(
        placement: FluentMenuPlacement = .below,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) -> FluentButtonView {
        FluentButtonView(
            title,
            role: role,
            action: action,
            style: style,
            flyoutItems: items(),
            flyoutPlacement: placement,
            commandBarFlyoutConfiguration: nil
        )
    }

    /// Attaches a CommandBarFlyout while preserving the Button as the invocation target.
    public func commandBarFlyout(
        alwaysExpanded: Bool = false,
        @FluentCommandBarBuilder primaryCommands: () -> [FluentCommandBarItem],
        @FluentCommandBarBuilder secondaryCommands: () -> [FluentCommandBarItem] = { [] }
    ) -> FluentButtonView {
        FluentButtonView(
            title,
            role: role,
            action: action,
            style: style,
            flyoutItems: nil,
            flyoutPlacement: flyoutPlacement,
            commandBarFlyoutConfiguration: FluentCommandBarFlyoutConfiguration(
                primaryCommands: primaryCommands(),
                secondaryCommands: secondaryCommands(),
                alwaysExpanded: alwaysExpanded
            )
        )
    }
}

public struct FluentToggleView: FluentUpdatablePrimitiveView {
    private let title: String
    private let binding: FluentBinding<Bool>
    private let style: (any FluentToggleStyle)?

    public init(_ title: String, isOn: FluentBinding<Bool>, style: (any FluentToggleStyle)? = nil) {
        self.title = title
        self.binding = isOn
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let toggle = FluentBoundToggle(binding, title: title)
        toggle.toggle.theme = context.theme
        toggle.toggle.reduceMotion = context.reduceMotion
        toggle.toggle.fluentLayoutDirection = context.layoutDirection
        toggle.toggle.fluentStyle = style
        return toggle
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let toggle = view as? FluentBoundToggle else { return false }
        toggle.update(
            binding: binding,
            theme: context.theme,
            reduceMotion: context.reduceMotion,
            layoutDirection: context.layoutDirection
        )
        toggle.toggle.title = title
        if toggle.toggle.fluentStyle != nil || style != nil { toggle.toggle.fluentStyle = style }
        return true
    }

    public func toggleStyle(_ style: any FluentToggleStyle) -> FluentToggleView {
        FluentToggleView(title, isOn: binding, style: style)
    }
}

public struct FluentSliderView: FluentUpdatablePrimitiveView {
    private let binding: FluentBinding<Double>
    private let range: ClosedRange<Double>
    private let style: (any FluentSliderStyle)?

    public init(value: FluentBinding<Double>, range: ClosedRange<Double> = 0...1, style: (any FluentSliderStyle)? = nil) {
        self.binding = value
        self.range = range
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let slider = FluentBoundSlider(binding, range: range)
        slider.slider.theme = context.theme
        slider.slider.reduceMotion = context.reduceMotion
        slider.slider.fluentLayoutDirection = context.layoutDirection
        slider.slider.fluentStyle = style
        return slider
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let slider = view as? FluentBoundSlider else { return false }
        slider.update(
            binding: binding,
            theme: context.theme,
            reduceMotion: context.reduceMotion,
            layoutDirection: context.layoutDirection
        )
        if slider.slider.minimumValue != range.lowerBound {
            slider.slider.minimumValue = range.lowerBound
        }
        if slider.slider.maximumValue != range.upperBound {
            slider.slider.maximumValue = range.upperBound
        }
        slider.slider.applyDeclarativeStyle(style)
        return true
    }

    public func sliderStyle(_ style: any FluentSliderStyle) -> FluentSliderView {
        FluentSliderView(value: binding, range: range, style: style)
    }
}

public struct FluentTextFieldView: FluentUpdatablePrimitiveView {
    private let binding: FluentBinding<String>
    private let placeholder: String
    private let style: (any FluentTextFieldStyle)?

    public init(text: FluentBinding<String>, placeholder: String = "", style: (any FluentTextFieldStyle)? = nil) {
        self.binding = text
        self.placeholder = placeholder
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let field = FluentBoundTextField(binding, placeholder: placeholder)
        field.theme = context.theme
        field.field.fluentStyle = style
        return field
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let field = view as? FluentBoundTextField else { return false }
        field.update(binding: binding, theme: context.theme)
        field.field.placeholderString = placeholder
        field.field.fluentStyle = style
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentTextFieldView {
        FluentTextFieldView(text: binding, placeholder: placeholder, style: style)
    }
}
