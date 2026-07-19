import AppKit

public struct FluentCheckBoxView: FluentUpdatablePrimitiveView {
    private let title: String
    private let binding: FluentBinding<Bool>
    private let style: (any FluentCheckBoxStyle)?

    public init(_ title: String, isChecked: FluentBinding<Bool>, style: (any FluentCheckBoxStyle)? = nil) {
        self.title = title
        self.binding = isChecked
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let bound = FluentBoundCheckBox(binding, title: title)
        bound.checkBox.theme = context.theme
        bound.checkBox.fluentStyle = style ?? FluentAutomaticCheckBoxStyle()
        return bound
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let bound = view as? FluentBoundCheckBox else { return false }
        bound.update(binding: binding, theme: context.theme)
        bound.checkBox.title = title
        bound.checkBox.fluentStyle = style ?? FluentAutomaticCheckBoxStyle()
        bound.invalidateIntrinsicContentSize()
        return true
    }

    public func checkBoxStyle(_ style: any FluentCheckBoxStyle) -> FluentCheckBoxView {
        FluentCheckBoxView(title, isChecked: binding, style: style)
    }
}

public struct FluentRadioButtonView: FluentUpdatablePrimitiveView {
    private let title: String
    private let binding: FluentBinding<Bool>
    private let style: (any FluentRadioButtonStyle)?

    public init(_ title: String, isSelected: FluentBinding<Bool>, style: (any FluentRadioButtonStyle)? = nil) {
        self.title = title
        self.binding = isSelected
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let bound = FluentBoundRadioButton(binding, title: title)
        bound.radioButton.theme = context.theme
        bound.radioButton.fluentStyle = style ?? FluentAutomaticRadioButtonStyle()
        return bound
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let bound = view as? FluentBoundRadioButton else { return false }
        bound.update(binding: binding, theme: context.theme)
        bound.radioButton.title = title
        bound.radioButton.fluentStyle = style ?? FluentAutomaticRadioButtonStyle()
        bound.invalidateIntrinsicContentSize()
        return true
    }

    public func radioButtonStyle(_ style: any FluentRadioButtonStyle) -> FluentRadioButtonView {
        FluentRadioButtonView(title, isSelected: binding, style: style)
    }
}
