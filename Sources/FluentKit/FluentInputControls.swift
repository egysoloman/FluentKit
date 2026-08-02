import AppKit

private final class FluentSecureTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.drawingRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: 10,
            trailingInset: 6
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        drawingRect(forBounds: rect)
    }

    override func edit(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

private final class FluentSearchFieldCell: NSSearchFieldCell {
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.searchTextRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: 4,
            trailingInset: 4
        )
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        fluentCenteredAdornmentRect(super.searchButtonRect(forBounds: rect), in: rect)
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        fluentCenteredAdornmentRect(super.cancelButtonRect(forBounds: rect), in: rect)
    }

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func edit(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: editorRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: editorRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func editorRect(forBounds rect: NSRect) -> NSRect {
        var result = searchTextRect(forBounds: rect)
        // NSSearchField inserts its editor through a flipped keyboard-focus clip view. In that
        // coordinate space a one-point negative adjustment brings the screen-space caret back to
        // the same baseline as the cell's drawing rect.
        result.origin.y -= 1
        return result
    }
}

private protocol FluentInputChrome: FluentControlSizeConfigurable where Self: NSControl {
    var theme: FluentTheme { get set }
    var fluentStyle: any FluentTextFieldStyle { get set }
}

private extension FluentInputChrome {
    func resolvedFluentAppearance(focused: Bool, pointerOver: Bool) -> FluentTextFieldAppearance {
        fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: isEnabled,
                isFocused: focused,
                isPointerOver: pointerOver,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

}

/// A Fluent-styled native secure text field. Prefer `FluentSecureField` when binding state.
public final class FluentSecureTextField: NSSecureTextField, FluentInputChrome {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            textEditingSession.theme = theme
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    private var isPointerOver = false
    private var pointerTrackingArea: NSTrackingArea?
    private lazy var textEditingSession = FluentTextEditingSession(control: self, theme: theme, isSecure: true)

    public init(placeholder: String = "") {
        super.init(frame: .zero)
        cell = FluentSecureTextFieldCell(textCell: "")
        configureFluentSingleLineTextControl(self)
        isEditable = true
        isSelectable = true
        placeholderString = placeholder
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 14)
        wantsLayer = true
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Secure text field")
        _ = textEditingSession
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 220 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    public override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        needsDisplay = true
    }

    public override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        textEditingSession.didBeginEditing()
        needsDisplay = true
    }

    public override func selectText(_ sender: Any?) {
        super.selectText(sender)
        textEditingSession.didBeginEditing()
    }

    public override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        textEditingSession.didEndEditing()
        needsDisplay = true
    }

    public override func rightMouseDown(with event: NSEvent) {
        if !textEditingSession.presentContextCommands(for: event) {
            super.rightMouseDown(with: event)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedFluentAppearance(
            focused: fluentTextControlHasFocus(self),
            pointerOver: isPointerOver
        )
        if let resolvedFont = appearance.font, font != resolvedFont { font = resolvedFont }
        applyFluentTextControlContentAppearance(self, appearance: appearance, theme: theme)
        drawFluentTextFieldChrome(in: bounds, appearance: appearance, isFlipped: isFlipped, phase: .background)
        super.draw(dirtyRect)
        drawFluentTextFieldChrome(in: bounds, appearance: appearance, isFlipped: isFlipped, phase: .borderAndFocus)
    }

    @discardableResult
    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentSecureTextField {
        fluentStyle = style
        return self
    }
}

/// A Fluent-styled native search field with AppKit's standard search and cancel affordances.
public final class FluentSearchTextField: NSSearchField, FluentInputChrome {
    /// Called when the field editor routes Escape through `cancelOperation(_:)`.
    public var onCancel: (() -> Void)?
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            textEditingSession.theme = theme
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    private var isPointerOver = false
    private var pointerTrackingArea: NSTrackingArea?
    private lazy var textEditingSession = FluentTextEditingSession(control: self, theme: theme, isSecure: false)

    public init(placeholder: String = "Search") {
        super.init(frame: .zero)
        cell = FluentSearchFieldCell(textCell: "")
        configureFluentSingleLineTextControl(self)
        isEditable = true
        isSelectable = true
        placeholderString = placeholder
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 14)
        wantsLayer = true
        setAccessibilityRole(.textField)
        setAccessibilityLabel(placeholder.isEmpty ? "Search" : placeholder)
        _ = textEditingSession
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 240 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    public override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        needsDisplay = true
    }

    public override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        textEditingSession.didBeginEditing()
        needsDisplay = true
    }

    public override func selectText(_ sender: Any?) {
        super.selectText(sender)
        textEditingSession.didBeginEditing()
    }

    public override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        textEditingSession.didEndEditing()
        needsDisplay = true
    }

    public override func rightMouseDown(with event: NSEvent) {
        if !textEditingSession.presentContextCommands(for: event) {
            super.rightMouseDown(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedFluentAppearance(
            focused: fluentTextControlHasFocus(self),
            pointerOver: isPointerOver
        )
        if let resolvedFont = appearance.font, font != resolvedFont { font = resolvedFont }
        applyFluentTextControlContentAppearance(self, appearance: appearance, theme: theme)
        drawFluentTextFieldChrome(in: bounds, appearance: appearance, isFlipped: isFlipped, phase: .background)
        super.draw(dirtyRect)
        drawFluentTextFieldChrome(in: bounds, appearance: appearance, isFlipped: isFlipped, phase: .borderAndFocus)
    }

    @discardableResult
    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentSearchTextField {
        fluentStyle = style
        return self
    }
}

public struct FluentSecureField: FluentUpdatablePrimitiveView {
    private let binding: FluentBinding<String>
    private let placeholder: String
    private let style: any FluentTextFieldStyle

    public init(_ text: FluentBinding<String>, placeholder: String = "Password", style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()) {
        binding = text
        self.placeholder = placeholder
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentBoundSecureField(binding: binding, placeholder: placeholder, theme: context.theme, style: style)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentBoundSecureField else { return false }
        host.update(binding: binding, placeholder: placeholder, theme: context.theme, style: style)
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentSecureField {
        FluentSecureField(binding, placeholder: placeholder, style: style)
    }
}

public struct FluentSearchField: FluentUpdatablePrimitiveView {
    private let binding: FluentBinding<String>
    private let placeholder: String
    private let style: any FluentTextFieldStyle
    private let onSubmit: (() -> Void)?

    public init(
        _ text: FluentBinding<String>,
        placeholder: String = "Search",
        style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle(),
        onSubmit: (() -> Void)? = nil
    ) {
        binding = text
        self.placeholder = placeholder
        self.style = style
        self.onSubmit = onSubmit
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentBoundSearchField(
            binding: binding,
            placeholder: placeholder,
            theme: context.theme,
            style: style,
            onSubmit: onSubmit
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentBoundSearchField else { return false }
        host.update(
            binding: binding,
            placeholder: placeholder,
            theme: context.theme,
            style: style,
            onSubmit: onSubmit
        )
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentSearchField {
        FluentSearchField(binding, placeholder: placeholder, style: style, onSubmit: onSubmit)
    }
}

private final class FluentBoundSecureField: NSView, NSTextFieldDelegate {
    let field: FluentSecureTextField
    private var bindingCoordinator: FluentStringBindingCoordinator!

    init(binding: FluentBinding<String>, placeholder: String, theme: FluentTheme, style: any FluentTextFieldStyle) {
        field = FluentSecureTextField(placeholder: placeholder)
        super.init(frame: .zero)
        field.theme = theme
        field.fluentStyle = style
        field.stringValue = binding.get()
        field.delegate = self
        field.target = self
        field.action = #selector(commit)
        addSubview(field)
        pin(field)
        bindingCoordinator = FluentStringBindingCoordinator(field: field, binding: binding)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { field.intrinsicContentSize }

    func update(binding: FluentBinding<String>, placeholder: String, theme: FluentTheme, style: any FluentTextFieldStyle) {
        bindingCoordinator.update(binding: binding)
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        if field.theme != theme { field.theme = theme }
        field.fluentStyle = style
    }

    func controlTextDidChange(_ obj: Notification) {
        bindingCoordinator.scheduleCurrentValuePublication()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        bindingCoordinator.publishCurrentValue()
    }

    @objc private func commit() { bindingCoordinator.publishCurrentValue() }

    private func pin(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

}

private final class FluentBoundSearchField: NSView, NSSearchFieldDelegate {
    let field: FluentSearchTextField
    private var bindingCoordinator: FluentStringBindingCoordinator!
    private var onSubmit: (() -> Void)?

    init(
        binding: FluentBinding<String>,
        placeholder: String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        onSubmit: (() -> Void)?
    ) {
        self.onSubmit = onSubmit
        field = FluentSearchTextField(placeholder: placeholder)
        super.init(frame: .zero)
        field.theme = theme
        field.fluentStyle = style
        field.stringValue = binding.get()
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        bindingCoordinator = FluentStringBindingCoordinator(field: field, binding: binding)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { field.intrinsicContentSize }

    func update(
        binding: FluentBinding<String>,
        placeholder: String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        onSubmit: (() -> Void)?
    ) {
        bindingCoordinator.update(binding: binding)
        self.onSubmit = onSubmit
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        if field.theme != theme { field.theme = theme }
        field.fluentStyle = style
    }

    func controlTextDidChange(_ obj: Notification) {
        bindingCoordinator.scheduleCurrentValuePublication()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        bindingCoordinator.publishCurrentValue()
    }

    @objc private func submit() {
        bindingCoordinator.publishCurrentValue()
        onSubmit?()
    }

}

/// A native combo box whose bound selection retains the option's stable value rather than its
/// display text.
public enum FluentComboBoxMode: Hashable, Sendable {
    /// The closed control displays one selected item and centers that item when opened.
    case selection
    /// The closed control exposes an editable text box and opens its popup below the field.
    case editable
}

public struct FluentComboBox<Option: Hashable>: FluentUpdatablePrimitiveView {
    private let options: [Option]
    private let selection: FluentBinding<Option?>
    private let text: FluentBinding<String>?
    private let mode: FluentComboBoxMode
    private let title: (Option) -> String
    private let style: any FluentTextFieldStyle

    public init(
        options: [Option],
        selection: FluentBinding<Option?>,
        mode: FluentComboBoxMode = .selection,
        text: FluentBinding<String>? = nil,
        style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle(),
        title: @escaping (Option) -> String = { String(describing: $0) }
    ) {
        precondition(Set(options).count == options.count, "Fluent combo-box options must be unique")
        self.options = options
        self.selection = selection
        self.text = text
        self.mode = mode
        self.style = style
        self.title = title
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentComboBoxHost(
            options: options,
            selection: selection,
            text: text,
            mode: mode,
            title: title,
            theme: context.theme,
            style: style,
            reduceMotion: context.reduceMotion
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentComboBoxHost<Option> else { return false }
        host.update(
            options: options,
            selection: selection,
            text: text,
            mode: mode,
            title: title,
            theme: context.theme,
            style: style,
            reduceMotion: context.reduceMotion
        )
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentComboBox<Option> {
        FluentComboBox(options: options, selection: selection, mode: mode, text: text, style: style, title: title)
    }
}

private final class FluentComboBoxCell: NSComboBoxCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.drawingRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: 11,
            trailingInset: 38
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect { drawingRect(forBounds: rect) }

    override func edit(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

private final class FluentComboBoxEditableTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.drawingRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: 11,
            trailingInset: 38
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect { drawingRect(forBounds: rect) }

    override func edit(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(withFrame: titleRect(forBounds: frame), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

private final class FluentComboBoxEditableTextField: NSTextField {
    var fluentTheme: FluentTheme = .current {
        didSet {
            guard oldValue != fluentTheme else { return }
            textEditingSession.theme = fluentTheme
        }
    }
    var onRequestFlyout: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onPressChange: ((Bool) -> Void)?
    var onPointerChange: ((Bool) -> Void)?
    var onGlyphPointerChange: ((Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?
    private var isTrackingGlyphPress = false
    private lazy var textEditingSession = FluentTextEditingSession(control: self, theme: fluentTheme, isSecure: false)

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerChange?(true)
        onGlyphPointerChange?(isInGlyphColumn(event))
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerChange?(true)
        onGlyphPointerChange?(isInGlyphColumn(event))
    }

    override func mouseExited(with event: NSEvent) {
        onPointerChange?(false)
        onGlyphPointerChange?(false)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        textEditingSession.didBeginEditing()
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        textEditingSession.didBeginEditing()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        textEditingSession.didEndEditing()
    }

    override func rightMouseDown(with event: NSEvent) {
        if !textEditingSession.presentContextCommands(for: event) {
            super.rightMouseDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isInGlyphColumn(event) else {
            super.mouseDown(with: event)
            return
        }
        FluentFocusVisibility.markPointerInteraction(in: window)
        isTrackingGlyphPress = true
        onGlyphPointerChange?(true)
        onPressChange?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingGlyphPress else { return }
        let inside = isInGlyphColumn(event)
        onGlyphPointerChange?(inside)
        onPressChange?(inside)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingGlyphPress else { return }
        let opensPopup = isInGlyphColumn(event)
        isTrackingGlyphPress = false
        onPressChange?(false)
        onGlyphPointerChange?(opensPopup)
        if opensPopup { DispatchQueue.main.async { [weak self] in self?.onRequestFlyout?() } }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), event.keyCode == 125 || event.keyCode == 126 {
            onRequestFlyout?()
            return
        }
        super.keyDown(with: event)
    }

    private func isInGlyphColumn(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let glyphColumn: CGFloat = 38
        return userInterfaceLayoutDirection == .rightToLeft
            ? point.x <= glyphColumn
            : point.x >= bounds.maxX - glyphColumn
    }
}

private final class FluentComboBoxNative: NSComboBox {
    var onRequestFlyout: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onPressChange: ((Bool) -> Void)?
    var onPointerChange: ((Bool) -> Void)?
    var usesCustomPopup = true
    var tracksPointerInteractions = true {
        didSet {
            guard oldValue != tracksPointerInteractions else { return }
            updateTrackingAreas()
            if !tracksPointerInteractions { onPointerChange?(false) }
        }
    }
    private var pointerTrackingArea: NSTrackingArea?
    private var isTrackingPress = false

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        guard tracksPointerInteractions else {
            pointerTrackingArea = nil
            return
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) { onPointerChange?(true) }
    override func mouseExited(with event: NSEvent) { onPointerChange?(false) }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)

        // WinUI editable ComboBox keeps the text portion as a real TextBox. Only the
        // glyph column opens the ComboBox popup; forwarding the other hit to AppKit
        // preserves insertion, selection and IME behavior.
        if isEditable, usesCustomPopup {
            let point = convert(event.locationInWindow, from: nil)
            let glyphColumn: CGFloat = 38
            let inGlyphColumn = userInterfaceLayoutDirection == .rightToLeft
                ? point.x <= glyphColumn
                : point.x >= bounds.maxX - glyphColumn
            if !inGlyphColumn {
                super.mouseDown(with: event)
                return
            }
        }
        window?.makeFirstResponder(self)
        // PointerFocused keeps native focus semantics without showing the keyboard focus Pill.
        onFocusChange?(false)
        isTrackingPress = true
        onPressChange?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        onPressChange?(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        let opensPopup = bounds.contains(convert(event.locationInWindow, from: nil))
        isTrackingPress = false
        onPressChange?(false)
        if opensPopup { DispatchQueue.main.async { [weak self] in self?.onRequestFlyout?() } }
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        onFocusChange?(true)
        switch event.keyCode {
        case 36, 49, 125, 126: onRequestFlyout?()
        default: super.keyDown(with: event)
        }
    }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        window?.makeFirstResponder(self)
        onFocusChange?(true)
        onRequestFlyout?()
    }
}

private enum FluentComboBoxMetrics {
    // Derived from ComboBox_themeresources_perf2026.xaml.
    static let pillWidth: CGFloat = 3
    static let pillHeight: CGFloat = 16
    static let pillCornerRadius: CGFloat = 1.5
    static let focusHighlightMargin: CGFloat = 4
    static let focusHighlightBorderWidth: CGFloat = 2
    static let focusHighlightCornerRadius: CGFloat = 7
    static let contentLeadingPadding: CGFloat = 12
    static let glyphColumnWidth: CGFloat = 38
    static let glyphWidth: CGFloat = 12
    static let glyphTrailingPadding: CGFloat = 14
}

private final class FluentComboBoxHost<Option: Hashable>: NSView, NSComboBoxDelegate, FluentControlSizeConfigurable {
    let comboBox = FluentComboBoxNative(frame: .zero)
    let editableField = FluentComboBoxEditableTextField(frame: .zero)
    var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            applyTheme()
        }
    }
    var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { applyTheme() } }
    var fluentControlSize: FluentControlSize = .regular {
        didSet { applyControlSize() }
    }
    private var options: [Option]
    private var selection: FluentBinding<Option?>
    private var text: FluentBinding<String>?
    private var mode: FluentComboBoxMode
    private var title: (Option) -> String
    private var observerID: UUID?
    private var textObserverID: UUID?
    private var selectionSubscriptionGeneration: UInt = 0
    private var textSubscriptionGeneration: UInt = 0
    private var editPublicationGeneration: UInt = 0
    private var editPublicationScheduled = false
    private var pendingEditableValue: String?
    private var isApplyingSelection = false
    private var comboPopup: FluentComboBoxPopup?
    private var reduceMotion: Bool
    private let focusHighlightLayer = CALayer()
    private let focusPillLayer = CALayer()
    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let dropDownOverlayLayer = CALayer()
    private let chevronLayer = FluentAnimatedChevronLayer()
    private let visualStateCoordinator = FluentVisualStateCoordinator()
    private let animationCoordinator = FluentAnimationCoordinator()
    private var pointerTrackingArea: NSTrackingArea?
    private var isPointerOver = false
    private var isPointerOverGlyph = false
    private var isPressed = false
    private var isEditingText = false

    override var isFlipped: Bool { true }

    init(
        options: [Option],
        selection: FluentBinding<Option?>,
        text: FluentBinding<String>?,
        mode: FluentComboBoxMode,
        title: @escaping (Option) -> String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        reduceMotion: Bool
    ) {
        self.options = options
        self.selection = selection
        self.text = text
        self.mode = mode
        self.title = title
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBox.Host")
        self.theme = theme
        fluentStyle = style
        visualStateCoordinator.reduceMotion = reduceMotion
        animationCoordinator.reduceMotion = reduceMotion
        wantsLayer = true
        layer?.masksToBounds = false
        elevationBorderLayer.name = "FluentKit.ComboBox.ElevationBorder"
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        layer?.addSublayer(elevationBorderLayer)
        focusHighlightLayer.name = "FluentKit.ComboBox.FocusHighlight"
        focusHighlightLayer.borderWidth = FluentComboBoxMetrics.focusHighlightBorderWidth
        focusHighlightLayer.cornerRadius = FluentComboBoxMetrics.focusHighlightCornerRadius
        layer?.addSublayer(focusHighlightLayer)
        focusPillLayer.name = "FluentKit.ComboBox.FocusPill"
        focusPillLayer.cornerRadius = FluentComboBoxMetrics.pillCornerRadius
        layer?.addSublayer(focusPillLayer)
        dropDownOverlayLayer.name = "FluentKit.ComboBox.DropDownOverlay"
        dropDownOverlayLayer.cornerRadius = 4
        layer?.addSublayer(dropDownOverlayLayer)
        chevronLayer.name = "FluentKit.ComboBox.Chevron"
        layer?.addSublayer(chevronLayer)
        comboBox.cell = FluentComboBoxCell(textCell: "")
        comboBox.identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBox.NativeBridge")
        configureFluentSingleLineTextControl(comboBox)
        if let cell = comboBox.cell as? NSComboBoxCell {
            cell.isButtonBordered = false
            cell.isBordered = false
            cell.isBezeled = false
            cell.drawsBackground = false
        }
        comboBox.isEditable = mode == .editable
        comboBox.isSelectable = true
        comboBox.completes = true
        comboBox.focusRingType = .none
        comboBox.isBordered = false
        comboBox.isBezeled = false
        comboBox.drawsBackground = false
        // The native combo remains a data/accessibility bridge only. Both public modes render
        // their own faceplate, so the AppKit arrow must never flash during mount or mode changes.
        comboBox.alphaValue = 0
        comboBox.isHidden = mode == .editable
        comboBox.tracksPointerInteractions = false
        comboBox.delegate = self
        comboBox.setAccessibilityRole(.comboBox)
        comboBox.setAccessibilityHelp("Shows the available options")
        comboBox.onFocusChange = { [weak self] focused in
            self?.updateFocusPill(focused: focused, animated: false)
            self?.applyButtonChrome(animated: true)
        }
        comboBox.onPressChange = { [weak self] pressed in
            self?.isPressed = pressed
            self?.applyButtonChrome(animated: true)
        }
        comboBox.onPointerChange = { [weak self] over in
            self?.isPointerOver = over
            self?.applyButtonChrome(animated: true)
        }
        comboBox.onRequestFlyout = { [weak self] in self?.requestOpen() }
        comboBox.target = self
        comboBox.action = #selector(requestOpen)
        addSubview(comboBox)
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            comboBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            comboBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            comboBox.topAnchor.constraint(equalTo: topAnchor),
            comboBox.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        editableField.cell = FluentComboBoxEditableTextFieldCell(textCell: "")
        configureFluentSingleLineTextControl(editableField)
        editableField.fluentTheme = theme
        editableField.isEditable = true
        editableField.isSelectable = true
        editableField.isBordered = false
        editableField.isBezeled = false
        editableField.drawsBackground = false
        editableField.focusRingType = .none
        editableField.delegate = self
        editableField.isHidden = mode != .editable
        editableField.identifier = NSUserInterfaceItemIdentifier("FluentKit.ComboBox.EditableText")
        editableField.setAccessibilityRole(.comboBox)
        editableField.setAccessibilityHelp("Edits a value or shows the available options")
        editableField.onFocusChange = { [weak self] focused in
            self?.updateFocusPill(focused: focused, animated: false)
            self?.applyButtonChrome(animated: true)
        }
        editableField.onPressChange = { [weak self] pressed in
            self?.isPressed = pressed
            self?.applyButtonChrome(animated: true)
        }
        editableField.onPointerChange = { [weak self] over in
            self?.isPointerOver = over
            self?.applyButtonChrome(animated: true)
        }
        editableField.onGlyphPointerChange = { [weak self] over in
            self?.isPointerOverGlyph = over
            self?.applyButtonChrome(animated: true)
        }
        editableField.onRequestFlyout = { [weak self] in self?.requestOpen() }
        addSubview(editableField)
        editableField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editableField.leadingAnchor.constraint(equalTo: leadingAnchor),
            editableField.trailingAnchor.constraint(equalTo: trailingAnchor),
            editableField.topAnchor.constraint(equalTo: topAnchor),
            editableField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        reloadOptions()
        installObserver()
        installTextObserver()
        applyControlSize()
        applySelection()
        updateFocusPill(focused: false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 240 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if mode == .selection { return comboBox.isEnabled ? self : nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        guard mode == .selection else {
            pointerTrackingArea = nil
            return
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard mode == .selection, comboBox.isEnabled else { return }
        isPointerOver = true
        applyButtonChrome(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard mode == .selection else { return }
        isPointerOver = false
        applyButtonChrome(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard mode == .selection, comboBox.isEnabled else { return super.mouseDown(with: event) }
        FluentFocusVisibility.markPointerInteraction(in: window)
        _ = window?.makeFirstResponder(comboBox)
        updateFocusPill(focused: false, animated: false)
        isPressed = true
        applyButtonChrome(animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .selection else { return super.mouseDragged(with: event) }
        let pressed = bounds.contains(convert(event.locationInWindow, from: nil))
        guard pressed != isPressed else { return }
        isPressed = pressed
        applyButtonChrome(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .selection else { return super.mouseUp(with: event) }
        let opens = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        applyButtonChrome(animated: true)
        if opens { requestOpen() }
    }

    override func layout() {
        super.layout()
        synchronizeVisualGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeVisualGeometry()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        synchronizeVisualGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeVisualGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeVisualGeometry()
    }

    private func synchronizeVisualGeometry() {
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let height = min(FluentComboBoxMetrics.pillHeight, max(0, bounds.height - 4))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusHighlightLayer.frame = bounds.insetBy(dx: -FluentComboBoxMetrics.focusHighlightMargin, dy: -FluentComboBoxMetrics.focusHighlightMargin)
        focusPillLayer.frame = NSRect(
            x: rightToLeft
                ? bounds.maxX - FluentComboBoxMetrics.pillWidth - 1
                : bounds.minX + 1,
            y: bounds.midY - height / 2,
            width: FluentComboBoxMetrics.pillWidth,
            height: height
        )
        dropDownOverlayLayer.frame = NSRect(
            x: rightToLeft ? bounds.minX + 4 : bounds.maxX - 34,
            y: bounds.minY + 4,
            width: 30,
            height: max(0, bounds.height - 8)
        )
        updateElevationBorderGeometry()
        updateChevron(animated: false)
        CATransaction.commit()
    }

    func update(
        options: [Option],
        selection: FluentBinding<Option?>,
        text: FluentBinding<String>?,
        mode: FluentComboBoxMode,
        title: @escaping (Option) -> String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        reduceMotion: Bool
    ) {
        let modeChanged = self.mode != mode
        let reusesSelectionObservation = self.selection.observationIdentity != nil
            && self.selection.observationIdentity == selection.observationIdentity
        let reusesTextObservation: Bool
        switch (self.text?.observationIdentity, text?.observationIdentity) {
        case let (oldID?, newID?):
            reusesTextObservation = oldID == newID
        case (nil, nil):
            reusesTextObservation = self.text == nil && text == nil
        default:
            reusesTextObservation = false
        }
        if !reusesSelectionObservation { removeSelectionObserver() }
        if !reusesTextObservation {
            cancelScheduledEditablePublication()
            removeTextObserver()
        }
        let optionsChanged = self.options != options
        if optionsChanged {
            comboPopup?.dismiss(animated: false)
            comboPopup = nil
        }
        self.options = options
        self.selection = selection
        self.text = text
        self.mode = mode
        self.title = title
        self.reduceMotion = reduceMotion
        if self.theme != theme { self.theme = theme }
        self.fluentStyle = style
        editableField.fluentTheme = theme
        comboBox.isEditable = mode == .editable
        comboBox.alphaValue = 0
        comboBox.isHidden = mode == .editable
        comboBox.tracksPointerInteractions = false
        editableField.isHidden = mode != .editable
        if modeChanged {
            isPointerOver = false
            isPointerOverGlyph = false
            isPressed = false
            updateTrackingAreas()
            invalidateIntrinsicContentSize()
        }
        if let cell = comboBox.cell as? NSComboBoxCell {
            cell.isButtonBordered = false
            cell.isBordered = false
            cell.isBezeled = false
            cell.drawsBackground = false
        }
        visualStateCoordinator.reduceMotion = reduceMotion
        animationCoordinator.reduceMotion = reduceMotion
        if reduceMotion {
            layer?.removeAllAnimations()
            elevationBorderLayer.removeAllAnimations()
            chevronLayer.removeAllAnimations()
        }
        if optionsChanged { reloadOptions() } else { refreshTitles() }
        applyControlSize()
        applySelection()
        updateFocusPill(focused: isTextFocusActive, animated: false)
        if !reusesSelectionObservation { installObserver() }
        if !reusesTextObservation { installTextObserver() }
    }

    override func draw(_ dirtyRect: NSRect) {
        if usesEditableTextChrome {
            let appearance = fluentStyle.appearance(
                for: FluentTextFieldStyleConfiguration(
                    isEnabled: comboBox.isEnabled,
                    isFocused: true,
                    controlSize: fluentControlSize,
                    theme: theme
                )
            )
            drawFluentTextFieldChrome(
                in: bounds,
                appearance: appearance,
                isFlipped: isFlipped
            )
        } else {
            applyButtonChrome(animated: false)
        }
        super.draw(dirtyRect)
        if mode == .selection { drawSelectedTitle() }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let index = comboBox.indexOfSelectedItem
        selection.set(options.indices.contains(index) ? options[index] : nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard mode == .editable, !isApplyingSelection else { return }
        let value = (notification.object as? NSTextField)?.stringValue ?? editableField.stringValue
        editableField.stringValue = value
        comboBox.stringValue = value
        scheduleEditablePublication(value)
        needsDisplay = true
    }

    private func scheduleEditablePublication(_ value: String) {
        pendingEditableValue = value
        guard !editPublicationScheduled else { return }
        editPublicationScheduled = true
        let publication = editPublicationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.editPublicationScheduled,
                  publication == self.editPublicationGeneration,
                  let value = self.pendingEditableValue else { return }
            self.editPublicationScheduled = false
            self.pendingEditableValue = nil
            self.publishEditableValue(value)
        }
    }

    private func flushEditablePublication() {
        let value = pendingEditableValue ?? editableField.stringValue
        cancelScheduledEditablePublication()
        publishEditableValue(value)
    }

    private func cancelScheduledEditablePublication() {
        editPublicationGeneration &+= 1
        editPublicationScheduled = false
        pendingEditableValue = nil
    }

    private func publishEditableValue(_ value: String) {
        guard mode == .editable else { return }
        if text?.get() != value { text?.set(value) }
        let exactIndex = options.firstIndex { title($0) == value }
        if let exactIndex {
            if selection.get() != options[exactIndex] { selection.set(options[exactIndex]) }
        } else if selection.get() != nil {
            selection.set(nil)
        }
        comboPopup?.updateSelectedIndex(exactIndex)
        needsDisplay = true
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard mode == .editable, (notification.object as? NSTextField) === editableField else { return }
        isEditingText = true
        applyButtonChrome(animated: true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard mode == .editable, (notification.object as? NSTextField) === editableField else { return }
        flushEditablePublication()
        isEditingText = false
        applyButtonChrome(animated: true)
    }

    @objc private func requestOpen() {
        guard comboBox.isEnabled, !options.isEmpty else { return }
        if comboPopup?.isPresented == true {
            comboPopup?.dismiss(animated: false)
            comboPopup = nil
            applyButtonChrome(animated: true)
            return
        }
        updateFocusPill(
            focused: FluentFocusVisibility.isKeyboardFocusVisible(for: mode == .editable ? editableField : comboBox),
            animated: false
        )
        let selectedIndex = selection.get().flatMap { options.firstIndex(of: $0) }
        let popup = FluentComboBoxPopup(
            titles: options.map(title),
            selectedIndex: selectedIndex,
            placement: mode == .editable ? .editable : .selectionCentered,
            theme: theme,
            layoutDirection: userInterfaceLayoutDirection,
            reduceMotion: reduceMotion,
            onMove: { [weak self] index in self?.selectOption(at: index, dismiss: false) },
            onCommit: { [weak self] index in self?.selectOption(at: index, dismiss: false) },
            onDismiss: { [weak self] in
                self?.comboPopup = nil
                self?.applyButtonChrome(animated: true)
            }
        )
        comboPopup = popup
        popup.present(relativeTo: self)
        // Opening changes the editable faceplate from Button-like chrome to the TextControl
        // state. Apply that state only after `present` has established `isPresented`.
        applyButtonChrome(animated: true)
    }

    private func selectOption(at index: Int, dismiss: Bool) {
        guard options.indices.contains(index) else { return }
        cancelScheduledEditablePublication()
        let option = options[index]
        if mode == .editable {
            let value = title(option)
            if text?.get() != value { text?.set(value) }
            comboBox.stringValue = value
            editableField.stringValue = value
        }
        if selection.get() != option {
            selection.set(option)
        }
        applySelection()
        comboPopup?.updateSelectedIndex(index)
        if dismiss {
            comboPopup?.dismiss(animated: true)
            comboPopup = nil
        }
    }

    private func reloadOptions() {
        let previousApplyingSelection = isApplyingSelection
        isApplyingSelection = true
        defer { isApplyingSelection = previousApplyingSelection }
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: options.map(title))
    }

    private func refreshTitles() {
        reloadOptions()
        applySelection()
    }

    private func applySelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        let selectedIndex: Int?
        if mode == .editable, let text {
            let isLocallyEditing = editableField.currentEditor() != nil
                || window?.firstResponder === editableField
            let value = isLocallyEditing ? editableField.stringValue : text.get()
            comboBox.stringValue = value
            if !isLocallyEditing, editableField.stringValue != value {
                editableField.stringValue = value
            }
            if let exactIndex = options.firstIndex(where: { title($0) == value }) {
                comboBox.selectItem(at: exactIndex)
                selectedIndex = exactIndex
            } else {
                comboBox.deselectItem(at: comboBox.indexOfSelectedItem)
                selectedIndex = nil
            }
            needsDisplay = true
            comboPopup?.updateSelectedIndex(selectedIndex)
            return
        }
        if let selected = selection.get(), let index = options.firstIndex(of: selected) {
            comboBox.selectItem(withObjectValue: title(selected))
            comboBox.stringValue = title(selected)
            editableField.stringValue = title(selected)
            comboBox.selectItem(at: index)
            selectedIndex = index
            if mode == .editable { text?.set(title(selected)) }
        } else {
            comboBox.deselectItem(at: comboBox.indexOfSelectedItem)
            selectedIndex = nil
            // An editable ComboBox may intentionally contain text that is not one of the
            // options. Clearing it here would make every non-matching keystroke disappear.
            if mode == .selection { comboBox.stringValue = "" }
            if selection.get() != nil { selection.set(nil) }
        }
        comboPopup?.updateSelectedIndex(selectedIndex)
        needsDisplay = true
    }

    private func installObserver() {
        selectionSubscriptionGeneration &+= 1
        let subscription = selectionSubscriptionGeneration
        observerID = selection.observe { [weak self] _ in
            let apply = { [weak self] in
                guard let self, subscription == self.selectionSubscriptionGeneration else { return }
                self.applySelection()
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func installTextObserver() {
        guard let text else { return }
        textSubscriptionGeneration &+= 1
        let subscription = textSubscriptionGeneration
        textObserverID = text.observe { [weak self] value in
            let apply = { [weak self] in
                guard let self,
                      subscription == self.textSubscriptionGeneration,
                      self.text?.get() == value,
                      self.mode == .editable,
                      self.window?.firstResponder !== self.comboBox,
                      self.window?.firstResponder !== self.editableField,
                      self.comboBox.currentEditor() == nil,
                      self.editableField.currentEditor() == nil,
                      self.comboBox.stringValue != value else { return }
                self.isApplyingSelection = true
                self.comboBox.stringValue = value
                self.editableField.stringValue = value
                self.isApplyingSelection = false
                self.needsDisplay = true
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func removeSelectionObserver() {
        selectionSubscriptionGeneration &+= 1
        if let observerID { selection.removeObserver(observerID) }
        observerID = nil
    }

    private func removeTextObserver() {
        textSubscriptionGeneration &+= 1
        if let textObserverID { text?.removeObserver(textObserverID) }
        textObserverID = nil
    }

    private func applyControlSize() {
        comboBox.controlSize = fluentControlSize.appKitSize
        let contentAppearance = fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: comboBox.isEnabled,
                isFocused: isTextFocusActive,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        let bodyFont = theme.typography.font(for: .body)
        comboBox.font = contentAppearance.font
            ?? bodyFont.withSize(bodyFont.pointSize * fluentControlSize.metricScale)
        comboBox.textColor = theme.textPrimary
        editableField.controlSize = fluentControlSize.appKitSize
        editableField.font = comboBox.font
        editableField.textColor = theme.textPrimary
        comboBox.invalidateIntrinsicContentSize()
        applyButtonChrome(animated: false)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func applyTheme() {
        applyControlSize()
        focusPillLayer.backgroundColor = theme.accentFillDefault.cgColor
        needsDisplay = true
    }

    private func applyButtonChrome(animated: Bool) {
        visualStateCoordinator.reduceMotion = reduceMotion
        visualStateCoordinator.transition(
            to: .forControlState(resolvedButtonControlState()),
            animated: animated,
            motion: FluentMotion.controlFaster
        ) { [weak self] transition in
            self?.applyButtonVisualState(transition)
        }
    }

    private func applyButtonVisualState(_ transition: FluentVisualStateTransition) {
        if usesEditableTextChrome {
            guard let layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 0
            elevationBorderLayer.isHidden = true
            CATransaction.commit()
            updateDropDownOverlay()
            updateChevron(animated: transition.isAnimated)
            needsDisplay = true
            return
        }
        let appearance = resolvedButtonAppearance(for: transition.to.primaryControlState)
        guard let layer else { return }
        applyFluentButtonChrome(
            to: layer,
            elevationLayer: elevationBorderLayer,
            elevationMask: elevationBorderMask,
            bounds: bounds,
            appearance: appearance,
            visualYAxis: .resolved(for: layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1,
            animationCoordinator: animationCoordinator,
            motion: transition.motion,
            animated: transition.isAnimated
        )
        updateDropDownOverlay()
        updateChevron(animated: transition.isAnimated)
        needsDisplay = true
    }

    private func updateElevationBorderGeometry(for appearance: FluentButtonAppearance? = nil) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let resolvedAppearance = appearance ?? resolvedButtonAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: bounds,
            appearance: resolvedAppearance,
            visualYAxis: .resolved(for: self.layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        )
        CATransaction.commit()
    }

    private func updateFocusPill(focused: Bool, animated: Bool) {
        focusPillLayer.backgroundColor = theme.accentFillDefault.cgColor
        focusHighlightLayer.borderColor = theme.accent.cgColor
        focusHighlightLayer.backgroundColor = NSColor.clear.cgColor
        let targetOpacity: Float = mode == .selection && focused && comboBox.isEnabled ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusHighlightLayer.opacity = targetOpacity
        focusPillLayer.opacity = targetOpacity
        CATransaction.commit()
        if animated {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = focusPillLayer.presentation()?.opacity ?? focusPillLayer.opacity
            opacity.toValue = targetOpacity
            opacity.duration = 0
            focusPillLayer.add(opacity, forKey: "fluent.combobox.focusPill.opacity")
        }
    }

    private func updateChevron(animated: Bool) {
        let pointerOver = mode == .editable && usesEditableTextChrome
            ? isPointerOverGlyph
            : isPointerOver
        let state: FluentControlState = !comboBox.isEnabled
            ? .disabled
            : (isPressed
                ? .pressed
                : (pointerOver
                    ? .pointerOver
                    : (FluentFocusVisibility.isKeyboardFocusVisible(for: comboBox) ? .focused : .normal)))
        let color: NSColor = switch state {
        case .pressed: theme.textSecondary.withAlphaComponent(0.72)
        case .pointerOver: theme.textSecondary.withAlphaComponent(0.86)
        case .disabled: theme.textDisabled
        default: theme.textSecondary
        }
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let x = rightToLeft
            ? bounds.minX + FluentComboBoxMetrics.glyphTrailingPadding
            : bounds.maxX - FluentComboBoxMetrics.glyphTrailingPadding - FluentComboBoxMetrics.glyphWidth
        chevronLayer.update(
            frame: NSRect(x: x, y: bounds.midY - 6, width: FluentComboBoxMetrics.glyphWidth, height: FluentComboBoxMetrics.glyphWidth),
            color: color,
            state: state,
            visual: .downSmall,
            animated: animated
        )
    }

    private func updateDropDownOverlay() {
        let color: NSColor
        if mode == .editable, usesEditableTextChrome, isPressed {
            color = theme.subtleFillTertiary
        } else if mode == .editable, usesEditableTextChrome, isPointerOverGlyph {
            color = theme.subtleFillSecondary
        } else {
            color = .clear
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropDownOverlayLayer.backgroundColor = color.cgColor
        dropDownOverlayLayer.isHidden = mode != .editable
        CATransaction.commit()
    }

    private func drawSelectedTitle() {
        guard !comboBox.stringValue.isEmpty else { return }
        let appearance = resolvedButtonAppearance()
        let bodyFont = theme.typography.font(for: .body)
        let font = comboBox.font
            ?? bodyFont.withSize(bodyFont.pointSize * fluentControlSize.metricScale)
        let size = (comboBox.stringValue as NSString).size(withAttributes: [.font: font])
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        let textRect = fluentSingleLineTextRect(
            NSRect(
                x: rightToLeft ? FluentComboBoxMetrics.glyphColumnWidth : FluentComboBoxMetrics.contentLeadingPadding,
                y: 0,
                width: max(0, bounds.width - FluentComboBoxMetrics.glyphColumnWidth - FluentComboBoxMetrics.contentLeadingPadding),
                height: size.height
            ),
            in: bounds,
            font: font,
            topInset: 5,
            bottomInset: 7
        )
        (comboBox.stringValue as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: font,
                .foregroundColor: appearance.foregroundColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func resolvedButtonAppearance() -> FluentButtonAppearance {
        resolvedButtonAppearance(for: visualStateCoordinator.state.primaryControlState)
    }

    private func resolvedButtonAppearance(for state: FluentControlState) -> FluentButtonAppearance {
        return FluentAutomaticButtonStyle().appearance(
            for: FluentButtonStyleConfiguration(
                title: comboBox.stringValue,
                controlState: state,
                isEnabled: comboBox.isEnabled,
                theme: theme
            )
        )
    }

    private func resolvedButtonControlState() -> FluentControlState {
        let focused = isTextFocusActive
        return isPressed
            ? .pressed
            : (isPointerOver ? .pointerOver : (focused ? .focused : .normal))
    }

    private var usesEditableTextChrome: Bool {
        mode == .editable && (isEditingText || isTextFocusActive || comboPopup?.isPresented == true)
    }

    private var isTextFocusActive: Bool {
        guard let firstResponder = window?.firstResponder else { return false }
        return firstResponder === comboBox
            || firstResponder === comboBox.currentEditor()
            || firstResponder === editableField
            || firstResponder === editableField.currentEditor()
    }

    deinit {
        cancelScheduledEditablePublication()
        removeSelectionObserver()
        removeTextObserver()
        comboPopup?.dismiss(animated: false)
    }
}

/// A numeric stepper composed from native AppKit editing and stepping controls.
public struct FluentStepper: FluentUpdatablePrimitiveView {
    private let title: String
    private let binding: FluentBinding<Double>
    private let range: ClosedRange<Double>
    private let step: Double
    private let format: (Double) -> String
    private let style: any FluentStepperStyle

    public init(
        _ title: String,
        value: FluentBinding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        style: any FluentStepperStyle = FluentAutomaticStepperStyle(),
        format: @escaping (Double) -> String = { String(format: "%g", $0) }
    ) {
        precondition(step > 0, "Fluent stepper increments must be positive")
        self.title = title
        binding = value
        self.range = range
        self.step = step
        self.style = style
        self.format = format
    }

    public init(
        _ title: String,
        value: FluentBinding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        style: any FluentStepperStyle = FluentAutomaticStepperStyle()
    ) {
        self.init(
            title,
            value: value.map(Double.init, { Int($0.rounded()) }),
            in: Double(range.lowerBound)...Double(range.upperBound),
            step: Double(step),
            style: style,
            format: { String(Int($0.rounded())) }
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentStepperHost(
            title: title,
            binding: binding,
            range: range,
            step: step,
            format: format,
            theme: context.theme,
            style: style
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentStepperHost else { return false }
        host.update(
            title: title,
            binding: binding,
            range: range,
            step: step,
            format: format,
            theme: context.theme,
            style: style
        )
        return true
    }

    public func stepperStyle(_ style: any FluentStepperStyle) -> FluentStepper {
        FluentStepper(title, value: binding, in: range, step: step, style: style, format: format)
    }
}

private final class FluentStepperNative: NSStepper {
    var onStep: ((Bool) -> Void)?
    var onPointerSideChange: ((Bool?) -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var pointerSideIsIncrement: Bool?
    private(set) var pressedSideIsIncrement: Bool?

    // NSStepper reserves bezel alignment insets even when its native drawing is suppressed.
    // Zero them so the visible/hit-test column matches NumberBox's 72pt template column.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointerSide(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointerSide(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerSideIsIncrement = nil
        onPointerSideChange?(nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let isLeadingHalf = localPoint.x < bounds.midX
        let increment = userInterfaceLayoutDirection == .rightToLeft ? !isLeadingHalf : isLeadingHalf
        pressedSideIsIncrement = increment
        pointerSideIsIncrement = increment
        onPointerSideChange?(increment)
        needsDisplay = true
        onStep?(increment)
    }

    override func mouseUp(with event: NSEvent) {
        pressedSideIsIncrement = nil
        updatePointerSide(with: event)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Keep AppKit stepping and accessibility while FluentStepperHost owns the pixels.
    }

    private func updatePointerSide(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let isLeadingHalf = localPoint.x < bounds.midX
        let side = bounds.contains(localPoint)
            ? (userInterfaceLayoutDirection == .rightToLeft ? !isLeadingHalf : isLeadingHalf)
            : nil
        pointerSideIsIncrement = side
        onPointerSideChange?(side)
        needsDisplay = true
    }
}

private final class FluentStepperHost: NSView, NSTextFieldDelegate, FluentControlSizeConfigurable {
    let titleLabel = NSTextField(labelWithString: "")
    let valueField = FluentTextField()
    let stepper = FluentStepperNative(frame: .zero)
    var fluentControlSize: FluentControlSize = .regular { didSet { applyControlSize() } }
    private var theme: FluentTheme = .current
    private var style: any FluentStepperStyle = FluentAutomaticStepperStyle()
    private var stack: NSStackView!
    private var valueWidthConstraint: NSLayoutConstraint!
    private var stepperWidthConstraint: NSLayoutConstraint!
    private var binding: FluentBinding<Double>
    private var range: ClosedRange<Double>
    private var step: Double
    private var format: (Double) -> String
    private var observerID: UUID?
    private var isApplyingValue = false

    init(
        title: String,
        binding: FluentBinding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        theme: FluentTheme,
        style: any FluentStepperStyle
    ) {
        self.binding = binding
        self.range = range
        self.step = step
        self.format = format
        super.init(frame: .zero)
        self.theme = theme
        self.style = style
        titleLabel.stringValue = title
        titleLabel.isHidden = title.isEmpty
        titleLabel.textColor = theme.textPrimary
        valueField.theme = theme
        valueField.alignment = .right
        valueField.delegate = self
        valueField.target = self
        valueField.action = #selector(commitText)
        valueField.onFluentPointerChange = { [weak self] _ in self?.needsDisplay = true }
        stepper.target = self
        stepper.action = #selector(stepValue)
        stepper.onStep = { [weak self] increment in self?.stepValueByDirection(increment: increment) }
        stepper.onPointerSideChange = { [weak self] _ in self?.needsDisplay = true }
        stack = NSStackView(views: [titleLabel, valueField, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        valueWidthConstraint = valueField.widthAnchor.constraint(equalToConstant: 88)
        stepperWidthConstraint = stepper.widthAnchor.constraint(equalToConstant: 28)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueWidthConstraint,
            stepperWidthConstraint
        ])
        configureNativeControls()
        applyValue(binding.get(), writeBinding: true)
        installObserver()
        applyControlSize()
        applyControlSize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let appearance = style.appearance(
            for: FluentStepperStyleConfiguration(
                isEnabled: valueField.isEnabled && stepper.isEnabled,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        guard appearance.drawsContainerChrome else { return }
        let expectedWidth = max(0, bounds.width - appearance.arrowColumnWidth)
        if abs(valueWidthConstraint.constant - expectedWidth) > 0.1 {
            valueWidthConstraint.constant = expectedWidth
            needsLayout = true
        }
    }

    func update(
        title: String,
        binding: FluentBinding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        theme: FluentTheme,
        style: any FluentStepperStyle
    ) {
        removeObserver()
        self.binding = binding
        self.range = range
        self.step = step
        self.format = format
        self.theme = theme
        self.style = style
        titleLabel.stringValue = title
        titleLabel.isHidden = title.isEmpty
        titleLabel.textColor = theme.textPrimary
        valueField.theme = theme
        configureNativeControls()
        applyValue(binding.get(), writeBinding: true)
        installObserver()
        applyControlSize()
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    @objc private func stepValue() { applyValue(stepper.doubleValue, writeBinding: true) }

    private func stepValueByDirection(increment: Bool) {
        let nextValue = binding.get() + (increment ? step : -step)
        applyValue(nextValue, writeBinding: true)
    }

    @objc private func commitText() {
        guard let value = Double(valueField.stringValue) else {
            applyValue(binding.get(), writeBinding: false)
            NSSound.beep()
            return
        }
        applyValue(value, writeBinding: true)
    }

    private func configureNativeControls() {
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = step
        stepper.valueWraps = false
        stepper.setAccessibilityRole(.incrementor)
        stepper.setAccessibilityLabel(titleLabel.stringValue)
    }

    private func applyValue(_ rawValue: Double, writeBinding: Bool) {
        let value = min(max(rawValue, range.lowerBound), range.upperBound)
        isApplyingValue = true
        stepper.doubleValue = value
        valueField.stringValue = format(value)
        isApplyingValue = false
        if writeBinding, binding.get() != value { binding.set(value) }
        setAccessibilityValue(value)
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let clamped = min(max(value, self.range.lowerBound), self.range.upperBound)
                self.applyValue(value, writeBinding: clamped != value)
            }
        }
    }

    private func removeObserver() {
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    private func applyControlSize() {
        let appearance = style.appearance(
            for: FluentStepperStyleConfiguration(
                isEnabled: valueField.isEnabled && stepper.isEnabled,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        titleLabel.font = appearance.labelFont
        titleLabel.textColor = appearance.labelColor
        stack?.spacing = appearance.spacing
        valueWidthConstraint?.constant = appearance.valueFieldWidth
        valueField.fluentStyle = appearance.textFieldStyle
        valueField.fluentControlSize = fluentControlSize
        // NumberBox uses the TextBox's natural reading alignment; the compact inline
        // stepper keeps its numeric value right-aligned beside the arrows.
        valueField.alignment = appearance.drawsContainerChrome ? .natural : .right
        valueField.drawsFluentChrome = !appearance.drawsContainerChrome
        stepper.controlSize = fluentControlSize.appKitSize
        stepperWidthConstraint?.constant = appearance.arrowColumnWidth
        if appearance.drawsContainerChrome {
            valueWidthConstraint?.constant = bounds.width > 0
                ? max(0, bounds.width - appearance.arrowColumnWidth)
                : appearance.valueFieldWidth
        }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let appearance = style.appearance(
            for: FluentStepperStyleConfiguration(
                isEnabled: valueField.isEnabled && stepper.isEnabled,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        if appearance.drawsContainerChrome {
            let focused = fluentTextControlHasFocus(valueField)
            let fieldAppearance = appearance.textFieldStyle.appearance(
                for: FluentTextFieldStyleConfiguration(
                    isEnabled: valueField.isEnabled,
                    isFocused: focused,
                    isPointerOver: valueField.isFluentPointerOver,
                    controlSize: fluentControlSize,
                    theme: theme
                )
            )
            drawFluentTextFieldChrome(in: bounds, appearance: fieldAppearance, isFlipped: isFlipped)
        }
        drawStepperArrows(
            in: stepper.convert(stepper.bounds, to: self),
            enabled: valueField.isEnabled && stepper.isEnabled,
            pointerSide: stepper.pointerSideIsIncrement,
            pressedSide: stepper.pressedSideIsIncrement
        )
    }

    private func drawStepperArrows(
        in frame: NSRect,
        enabled: Bool,
        pointerSide: Bool?,
        pressedSide: Bool?
    ) {
        guard frame.width > 0, frame.height > 0 else { return }
        let color = (enabled ? theme.textSecondary : theme.textDisabled).withAlphaComponent(enabled ? 1 : 0.55)
        let buttonWidth = frame.width / 2
        let arrowHeight: CGFloat = 4
        let arrowWidth: CGFloat = 5
        let incrementIndex = userInterfaceLayoutDirection == .rightToLeft ? 1 : 0
        let visualUpSign: CGFloat = isFlipped ? -1 : 1
        for index in 0...1 {
            let sideIsIncrement = index == incrementIndex
            let pointsUp = sideIsIncrement
            let buttonFrame = NSRect(
                x: frame.minX + CGFloat(index) * buttonWidth,
                y: frame.minY,
                width: buttonWidth,
                height: frame.height
            )
            let fill: NSColor
            if pressedSide == sideIsIncrement {
                fill = theme.controlFillTertiary
            } else if pointerSide == sideIsIncrement {
                fill = theme.controlFillSecondary
            } else {
                fill = .clear
            }
            fill.setFill()
            NSBezierPath(roundedRect: buttonFrame, xRadius: 3, yRadius: 3).fill()

            let centerX = buttonFrame.midX
            let centerY = buttonFrame.midY
            let path = NSBezierPath()
            if pointsUp {
                path.move(to: NSPoint(x: centerX - arrowWidth / 2, y: centerY - visualUpSign * arrowHeight / 2))
                path.line(to: NSPoint(x: centerX, y: centerY + visualUpSign * arrowHeight / 2))
                path.line(to: NSPoint(x: centerX + arrowWidth / 2, y: centerY - visualUpSign * arrowHeight / 2))
            } else {
                path.move(to: NSPoint(x: centerX - arrowWidth / 2, y: centerY + visualUpSign * arrowHeight / 2))
                path.line(to: NSPoint(x: centerX, y: centerY - visualUpSign * arrowHeight / 2))
                path.line(to: NSPoint(x: centerX + arrowWidth / 2, y: centerY + visualUpSign * arrowHeight / 2))
            }
            path.lineWidth = 1.2
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }
    }

    deinit { removeObserver() }
}
