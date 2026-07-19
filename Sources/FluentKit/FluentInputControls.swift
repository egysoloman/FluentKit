import AppKit

private protocol FluentInputChrome: FluentControlSizeConfigurable where Self: NSControl {
    var theme: FluentTheme { get set }
    var fluentStyle: any FluentTextFieldStyle { get set }
}

private extension FluentInputChrome {
    func resolvedFluentAppearance(focused: Bool) -> FluentTextFieldAppearance {
        fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: isEnabled,
                isFocused: focused,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    func drawFluentChrome(in bounds: NSRect, appearance: FluentTextFieldAppearance) {
        appearance.backgroundColor.setFill()
        bounds.fill()
        appearance.borderColor.setStroke()
        switch appearance.borderShape {
        case .rounded:
            let rect = bounds.insetBy(dx: appearance.borderWidth / 2, dy: appearance.borderWidth / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: appearance.cornerRadius, yRadius: appearance.cornerRadius)
            appearance.backgroundColor.setFill()
            path.fill()
            if appearance.borderWidth > 0 {
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        case .underline:
            guard appearance.borderWidth > 0 else { return }
            let path = NSBezierPath()
            let visualBottom = isFlipped
                ? bounds.maxY - appearance.borderWidth / 2
                : bounds.minY + appearance.borderWidth / 2
            path.move(to: NSPoint(x: bounds.minX, y: visualBottom))
            path.line(to: NSPoint(x: bounds.maxX, y: visualBottom))
            path.lineWidth = appearance.borderWidth
            path.stroke()
        }
    }
}

/// A Fluent-styled native secure text field. Prefer `FluentSecureField` when binding state.
public final class FluentSecureTextField: NSSecureTextField, FluentInputChrome {
    public var theme: FluentTheme = .current { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    public init(placeholder: String = "") {
        super.init(frame: .zero)
        placeholderString = placeholder
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 14)
        wantsLayer = true
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Secure text field")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 220 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedFluentAppearance(focused: window?.firstResponder === self || window?.firstResponder === currentEditor())
        textColor = appearance.textColor
        if let resolvedFont = appearance.font, font != resolvedFont { font = resolvedFont }
        drawFluentChrome(in: bounds, appearance: appearance)
        super.draw(dirtyRect)
    }

    @discardableResult
    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentSecureTextField {
        fluentStyle = style
        return self
    }
}

/// A Fluent-styled native search field with AppKit's standard search and cancel affordances.
public final class FluentSearchTextField: NSSearchField, FluentInputChrome {
    public var theme: FluentTheme = .current { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    public init(placeholder: String = "Search") {
        super.init(frame: .zero)
        placeholderString = placeholder
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 14)
        wantsLayer = true
        setAccessibilityRole(.textField)
        setAccessibilityLabel(placeholder.isEmpty ? "Search" : placeholder)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 240 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedFluentAppearance(focused: window?.firstResponder === self || window?.firstResponder === currentEditor())
        textColor = appearance.textColor
        if let resolvedFont = appearance.font, font != resolvedFont { font = resolvedFont }
        drawFluentChrome(in: bounds, appearance: appearance)
        super.draw(dirtyRect)
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
    private var binding: FluentBinding<String>
    private var observerID: UUID?

    init(binding: FluentBinding<String>, placeholder: String, theme: FluentTheme, style: any FluentTextFieldStyle) {
        self.binding = binding
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
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { field.intrinsicContentSize }

    func update(binding: FluentBinding<String>, placeholder: String, theme: FluentTheme, style: any FluentTextFieldStyle) {
        removeObserver()
        self.binding = binding
        field.placeholderString = placeholder
        field.theme = theme
        field.fluentStyle = style
        let isEditing = field.window.map { $0.firstResponder === field.currentEditor() } ?? false
        if !isEditing, field.stringValue != binding.get() {
            field.stringValue = binding.get()
        }
        installObserver()
    }

    func controlTextDidChange(_ obj: Notification) { binding.set(field.stringValue) }

    @objc private func commit() { binding.set(field.stringValue) }

    private func installObserver() {
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !(self.field.window.map { $0.firstResponder === self.field.currentEditor() } ?? false),
                      self.field.stringValue != value else { return }
                self.field.stringValue = value
            }
        }
    }

    private func removeObserver() {
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    private func pin(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    deinit { removeObserver() }
}

private final class FluentBoundSearchField: NSView, NSSearchFieldDelegate {
    let field: FluentSearchTextField
    private var binding: FluentBinding<String>
    private var observerID: UUID?
    private var onSubmit: (() -> Void)?

    init(
        binding: FluentBinding<String>,
        placeholder: String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        onSubmit: (() -> Void)?
    ) {
        self.binding = binding
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
        installObserver()
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
        removeObserver()
        self.binding = binding
        self.onSubmit = onSubmit
        field.placeholderString = placeholder
        field.theme = theme
        field.fluentStyle = style
        let isEditing = field.window.map { $0.firstResponder === field.currentEditor() } ?? false
        if !isEditing, field.stringValue != binding.get() {
            field.stringValue = binding.get()
        }
        installObserver()
    }

    func controlTextDidChange(_ obj: Notification) { binding.set(field.stringValue) }

    @objc private func submit() {
        binding.set(field.stringValue)
        onSubmit?()
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !(self.field.window.map { $0.firstResponder === self.field.currentEditor() } ?? false),
                      self.field.stringValue != value else { return }
                self.field.stringValue = value
            }
        }
    }

    private func removeObserver() {
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    deinit { removeObserver() }
}

/// A native combo box whose bound selection retains the option's stable value rather than its
/// display text.
public struct FluentComboBox<Option: Hashable>: FluentUpdatablePrimitiveView {
    private let options: [Option]
    private let selection: FluentBinding<Option?>
    private let title: (Option) -> String
    private let style: any FluentTextFieldStyle

    public init(
        options: [Option],
        selection: FluentBinding<Option?>,
        style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle(),
        title: @escaping (Option) -> String = { String(describing: $0) }
    ) {
        precondition(Set(options).count == options.count, "Fluent combo-box options must be unique")
        self.options = options
        self.selection = selection
        self.style = style
        self.title = title
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentComboBoxHost(
            options: options,
            selection: selection,
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
            title: title,
            theme: context.theme,
            style: style,
            reduceMotion: context.reduceMotion
        )
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentComboBox<Option> {
        FluentComboBox(options: options, selection: selection, style: style, title: title)
    }
}

private final class FluentComboBoxNative: NSComboBox {
    var onRequestFlyout: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

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
        window?.makeFirstResponder(self)
        onFocusChange?(true)
        onRequestFlyout?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 125, 126: onRequestFlyout?()
        default: super.keyDown(with: event)
        }
    }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
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
}

private final class FluentComboBoxHost<Option: Hashable>: NSView, NSComboBoxDelegate, FluentControlSizeConfigurable {
    let comboBox = FluentComboBoxNative(frame: .zero)
    var theme: FluentTheme = .current { didSet { applyTheme() } }
    var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { applyTheme() } }
    var fluentControlSize: FluentControlSize = .regular {
        didSet { applyControlSize() }
    }
    private var options: [Option]
    private var selection: FluentBinding<Option?>
    private var title: (Option) -> String
    private var observerID: UUID?
    private var isApplyingSelection = false
    private var menuFlyout: FluentMenuFlyout?
    private var reduceMotion: Bool
    private let focusHighlightLayer = CALayer()
    private let focusPillLayer = CALayer()

    init(
        options: [Option],
        selection: FluentBinding<Option?>,
        title: @escaping (Option) -> String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        reduceMotion: Bool
    ) {
        self.options = options
        self.selection = selection
        self.title = title
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        self.theme = theme
        fluentStyle = style
        wantsLayer = true
        focusHighlightLayer.name = "FluentKit.ComboBox.FocusHighlight"
        focusHighlightLayer.borderWidth = FluentComboBoxMetrics.focusHighlightBorderWidth
        focusHighlightLayer.cornerRadius = FluentComboBoxMetrics.focusHighlightCornerRadius
        layer?.addSublayer(focusHighlightLayer)
        focusPillLayer.name = "FluentKit.ComboBox.FocusPill"
        focusPillLayer.cornerRadius = FluentComboBoxMetrics.pillCornerRadius
        layer?.addSublayer(focusPillLayer)
        comboBox.isEditable = false
        comboBox.completes = true
        comboBox.focusRingType = .none
        comboBox.isBordered = false
        comboBox.drawsBackground = false
        comboBox.alphaValue = 0
        comboBox.delegate = self
        comboBox.setAccessibilityRole(.comboBox)
        comboBox.setAccessibilityHelp("Shows the available options")
        comboBox.onFocusChange = { [weak self] focused in
            self?.updateFocusPill(focused: focused, animated: false)
        }
        comboBox.onRequestFlyout = { [weak self] in self?.showOptions() }
        comboBox.target = self
        comboBox.action = #selector(showOptions)
        addSubview(comboBox)
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            comboBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            comboBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            comboBox.topAnchor.constraint(equalTo: topAnchor),
            comboBox.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        reloadOptions()
        installObserver()
        applyControlSize()
        applySelection()
        updateFocusPill(focused: false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    override func layout() {
        super.layout()
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let height = min(FluentComboBoxMetrics.pillHeight, max(0, bounds.height - 4))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusHighlightLayer.frame = bounds.insetBy(dx: -FluentComboBoxMetrics.focusHighlightMargin, dy: -FluentComboBoxMetrics.focusHighlightMargin)
        focusPillLayer.frame = NSRect(
            x: rightToLeft ? bounds.maxX - FluentComboBoxMetrics.pillWidth : bounds.minX,
            y: bounds.midY - height / 2,
            width: FluentComboBoxMetrics.pillWidth,
            height: height
        )
        CATransaction.commit()
    }

    func update(
        options: [Option],
        selection: FluentBinding<Option?>,
        title: @escaping (Option) -> String,
        theme: FluentTheme,
        style: any FluentTextFieldStyle,
        reduceMotion: Bool
    ) {
        removeObserver()
        let optionsChanged = self.options != options
        if optionsChanged {
            menuFlyout?.dismiss(animated: false)
            menuFlyout = nil
        }
        self.options = options
        self.selection = selection
        self.title = title
        self.reduceMotion = reduceMotion
        self.theme = theme
        self.fluentStyle = style
        if optionsChanged { reloadOptions() } else { refreshTitles() }
        applyControlSize()
        applySelection()
        updateFocusPill(focused: window?.firstResponder === comboBox, animated: false)
        installObserver()
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: comboBox.isEnabled,
                isFocused: window?.firstResponder === comboBox || window?.firstResponder === comboBox.currentEditor(),
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        appearance.backgroundColor.setFill()
        bounds.fill()
        appearance.borderColor.setStroke()
        switch appearance.borderShape {
        case .rounded:
            let rect = bounds.insetBy(dx: appearance.borderWidth / 2, dy: appearance.borderWidth / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: appearance.cornerRadius, yRadius: appearance.cornerRadius)
            appearance.backgroundColor.setFill()
            path.fill()
            if appearance.borderWidth > 0 {
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        case .underline:
            if appearance.borderWidth > 0 {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.minX, y: appearance.borderWidth / 2))
                path.line(to: NSPoint(x: bounds.maxX, y: appearance.borderWidth / 2))
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        }
        super.draw(dirtyRect)
        drawSelectedTitle()
        drawChevron()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let index = comboBox.indexOfSelectedItem
        selection.set(options.indices.contains(index) ? options[index] : nil)
    }

    @objc private func showOptions() {
        guard comboBox.isEnabled, !options.isEmpty else { return }
        updateFocusPill(focused: true, animated: false)
        menuFlyout?.dismiss(animated: false)
        let selected = selection.get()
        let items = options.map { option in
            FluentMenuItem(
                title(option),
                state: option == selected ? .on : .off,
                selectionIndicator: .pill
            ) { [weak self] in
                guard let self else { return }
                self.selection.set(option)
                self.applySelection()
            }
        }
        let flyout = FluentMenuFlyout(
            items: items,
            theme: theme,
            minimumWidth: bounds.width,
            reduceMotion: reduceMotion
        )
        menuFlyout = flyout
        flyout.present(relativeTo: self)
    }

    private func reloadOptions() {
        let previousApplyingSelection = isApplyingSelection
        isApplyingSelection = true
        defer { isApplyingSelection = previousApplyingSelection }
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: options.map(title))
    }

    private func refreshTitles() {
        let selected = selection.get()
        reloadOptions()
        selection.set(selected)
    }

    private func applySelection() {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        if let selected = selection.get(), let index = options.firstIndex(of: selected) {
            comboBox.selectItem(withObjectValue: title(selected))
            comboBox.stringValue = title(selected)
            comboBox.selectItem(at: index)
        } else {
            comboBox.deselectItem(at: comboBox.indexOfSelectedItem)
            comboBox.stringValue = ""
            if selection.get() != nil { selection.set(nil) }
        }
        needsDisplay = true
    }

    private func installObserver() {
        observerID = selection.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applySelection() }
        }
    }

    private func removeObserver() {
        if let observerID { selection.removeObserver(observerID) }
        observerID = nil
    }

    private func applyControlSize() {
        comboBox.controlSize = fluentControlSize.appKitSize
        let appearance = fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: comboBox.isEnabled,
                isFocused: window?.firstResponder === comboBox || window?.firstResponder === comboBox.currentEditor(),
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        let bodyFont = theme.typography.font(for: .body)
        comboBox.font = appearance.font ?? bodyFont.withSize(bodyFont.pointSize * fluentControlSize.metricScale)
        comboBox.textColor = appearance.textColor
        comboBox.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func applyTheme() {
        applyControlSize()
        focusPillLayer.backgroundColor = theme.accent.cgColor
        needsDisplay = true
    }

    private func updateFocusPill(focused: Bool, animated: Bool) {
        focusPillLayer.backgroundColor = theme.accent.cgColor
        focusHighlightLayer.borderColor = theme.accent.cgColor
        focusHighlightLayer.backgroundColor = NSColor.clear.cgColor
        let targetOpacity: Float = focused && comboBox.isEnabled ? 1 : 0
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

    private func drawChevron() {
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let centerX = rightToLeft
            ? bounds.minX + FluentComboBoxMetrics.glyphColumnWidth / 2
            : bounds.maxX - FluentComboBoxMetrics.glyphColumnWidth / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX - 3, y: bounds.midY + 2))
        path.line(to: NSPoint(x: centerX, y: bounds.midY - 1.5))
        path.line(to: NSPoint(x: centerX + 3, y: bounds.midY + 2))
        path.lineWidth = 1.4
        theme.textSecondary.setStroke()
        path.stroke()
    }

    private func drawSelectedTitle() {
        guard !comboBox.stringValue.isEmpty else { return }
        let appearance = fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: comboBox.isEnabled,
                isFocused: focusPillLayer.opacity > 0,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        let font = appearance.font
            ?? theme.typography.font(for: .body).withSize(
                theme.typography.font(for: .body).pointSize * fluentControlSize.metricScale
            )
        let size = (comboBox.stringValue as NSString).size(withAttributes: [.font: font])
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        (comboBox.stringValue as NSString).draw(
            in: NSRect(
                x: rightToLeft ? FluentComboBoxMetrics.glyphColumnWidth : FluentComboBoxMetrics.contentLeadingPadding,
                y: bounds.midY - size.height / 2,
                width: max(0, bounds.width - FluentComboBoxMetrics.glyphColumnWidth - FluentComboBoxMetrics.contentLeadingPadding),
                height: size.height
            ),
            withAttributes: [
                .font: font,
                .foregroundColor: appearance.textColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    deinit {
        removeObserver()
        menuFlyout?.dismiss(animated: false)
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

private final class FluentStepperHost: NSView, NSTextFieldDelegate, FluentControlSizeConfigurable {
    let titleLabel = NSTextField(labelWithString: "")
    let valueField = FluentTextField()
    let stepper = NSStepper(frame: .zero)
    var fluentControlSize: FluentControlSize = .regular { didSet { applyControlSize() } }
    private var theme: FluentTheme = .current
    private var style: any FluentStepperStyle = FluentAutomaticStepperStyle()
    private var stack: NSStackView!
    private var valueWidthConstraint: NSLayoutConstraint!
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
        stepper.target = self
        stepper.action = #selector(stepValue)
        stack = NSStackView(views: [titleLabel, valueField, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        valueWidthConstraint = valueField.widthAnchor.constraint(equalToConstant: 88)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueWidthConstraint
        ])
        configureNativeControls()
        applyValue(binding.get(), writeBinding: true)
        installObserver()
        applyControlSize()
        applyControlSize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        stepper.controlSize = fluentControlSize.appKitSize
        invalidateIntrinsicContentSize()
    }

    deinit { removeObserver() }
}
