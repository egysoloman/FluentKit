import AppKit

extension FluentButton: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentButton else { return false }
        button.theme = context.theme
        button.applyDeclarativeConfiguration(from: self)
        return true
    }
}

extension FluentTextField: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let field = view as? FluentTextField else { return false }
        field.theme = context.theme
        field.fluentStyle = fluentStyle
        field.fluentControlSize = fluentControlSize
        field.placeholderString = placeholderString
        return true
    }
}

extension FluentToggle: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let toggle = view as? FluentToggle else { return false }
        toggle.theme = context.theme
        toggle.applyDeclarativeConfiguration(from: self)
        return true
    }
}

extension FluentProgressBar: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let progress = view as? FluentProgressBar else { return false }
        progress.theme = context.theme
        progress.applyDeclarativeConfiguration(from: self)
        return true
    }
}

extension FluentSlider: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let slider = view as? FluentSlider else { return false }
        slider.theme = context.theme
        slider.applyDeclarativeConfiguration(from: self)
        return true
    }
}

extension FluentMaterialView: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let material = view as? FluentMaterialView else { return false }
        material.needsDisplay = true
        return true
    }
}

extension FluentCheckBox: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView { theme = context.theme; return self }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let checkbox = view as? FluentCheckBox else { return false }
        checkbox.theme = context.theme
        checkbox.title = title
        if checkbox.isChecked != isChecked { checkbox.isChecked = isChecked }
        checkbox.fluentStyle = fluentStyle
        checkbox.fluentControlSize = fluentControlSize
        return true
    }
}

extension FluentRadioButton: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView { theme = context.theme; return self }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let radio = view as? FluentRadioButton else { return false }
        radio.theme = context.theme
        radio.title = title
        if radio.isSelected != isSelected { radio.isSelected = isSelected }
        radio.fluentStyle = fluentStyle
        radio.fluentControlSize = fluentControlSize
        return true
    }
}

extension FluentProgressRing: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView { theme = context.theme; return self }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let ring = view as? FluentProgressRing else { return false }
        ring.theme = context.theme
        return true
    }
}

extension FluentPopoverButton: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentPopoverButton<Content> else { return false }
        button.theme = context.theme
        button.applyDeclarativeConfiguration(from: self)
        return true
    }
}

extension FluentMenuButton: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentMenuButton else { return false }
        button.theme = context.theme
        button.applyDeclarativeConfiguration(from: self)
        return true
    }
}

extension FluentBoundTextField: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView { theme = context.theme; return self }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let field = view as? FluentBoundTextField else { return false }
        field.update(binding: binding, theme: context.theme)
        field.field.placeholderString = self.field.placeholderString
        field.field.fluentStyle = self.field.fluentStyle
        field.field.fluentControlSize = self.field.fluentControlSize
        return true
    }
}

extension FluentBoundToggle: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        toggle.theme = context.theme
        toggle.reduceMotion = context.reduceMotion
        toggle.fluentLayoutDirection = context.layoutDirection
        return self
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let toggle = view as? FluentBoundToggle else { return false }
        toggle.update(
            binding: binding,
            theme: context.theme,
            reduceMotion: context.reduceMotion,
            layoutDirection: context.layoutDirection
        )
        toggle.toggle.applyDeclarativeConfiguration(from: self.toggle)
        return true
    }
}

extension FluentBoundSlider: FluentUpdatablePrimitiveView {
    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView { slider.theme = context.theme; return self }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let slider = view as? FluentBoundSlider else { return false }
        slider.update(binding: binding, theme: context.theme)
        slider.slider.applyDeclarativeConfiguration(from: self.slider)
        return true
    }
}
