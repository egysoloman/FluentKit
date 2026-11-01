import AppKit

/// A suggestion displayed by `FluentAutoSuggestBox`.
public struct FluentAutoSuggestBoxSuggestion: Hashable {
    public let id: AnyHashable
    public let title: String
    public let subtitle: String?
    public let systemImageName: String?

    public init(
        id: AnyHashable = UUID(),
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
    }
}

/// The origin of a debounced AutoSuggestBox text change, matching WinUI's three reasons.
public enum FluentAutoSuggestBoxTextChangeReason: Sendable, Equatable {
    case userInput, programmaticChange, suggestionChosen
}

public struct FluentAutoSuggestBoxTextChangedEvent: Sendable, Equatable {
    public let text: String
    public let reason: FluentAutoSuggestBoxTextChangeReason
}

/// A WinUI AutoSuggestBox backed by a Fluent text field, a query/clear adornment column, and an
/// application-owned suggestion popup.
///
/// The implementation follows the WinUI source contract:
/// - TextChanged is debounced for 150 ms before the provider is consulted and the event raised.
/// - The popup opens below the field when focused with non-empty text and matching suggestions,
///   flips above when the screen edge requires it, and closes on Escape, submit, or focus loss.
/// - Supply stable, unique suggestion IDs to retain rows and selection when the provider updates.
/// - `onTextChangedEvent` distinguishes input, programmatic changes and suggestion previews;
///   the existing string-only `onTextChanged` callback remains supported.
/// - A zero maximum height hides suggestions; negative heights use available screen space.
/// - Down/Up move through suggestions and update the text on select; Enter submits the selected
///   suggestion (or the raw query), and the query button always submits the raw query.
public struct FluentAutoSuggestBox: FluentUpdatablePrimitiveView {
    private let text: FluentBinding<String>
    private let placeholder: String
    private let header: String?
    private let querySystemImageName: String?
    private let suggestionsProvider: (String) -> [FluentAutoSuggestBoxSuggestion]
    private let onTextChangedEvent: ((FluentAutoSuggestBoxTextChangedEvent) -> Void)?
    private let onTextChanged: ((String) -> Void)?
    private let onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)?
    private let onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)?
    private let updateTextOnSelect: Bool
    private let maxSuggestionListHeight: CGFloat

    public init(
        _ text: FluentBinding<String>,
        placeholder: String = "",
        header: String? = nil,
        querySystemImageName: String? = nil,
        suggestions: @escaping (String) -> [FluentAutoSuggestBoxSuggestion] = { _ in [] },
        updateTextOnSelect: Bool = true,
        maxSuggestionListHeight: CGFloat = 374,
        onTextChangedEvent: ((FluentAutoSuggestBoxTextChangedEvent) -> Void)? = nil,
        onTextChanged: ((String) -> Void)? = nil,
        onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)? = nil,
        onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)? = nil
    ) {
        self.text = text
        self.placeholder = placeholder
        self.header = header
        self.querySystemImageName = querySystemImageName
        suggestionsProvider = suggestions
        self.onTextChangedEvent = onTextChangedEvent
        self.onTextChanged = onTextChanged
        self.onSuggestionChosen = onSuggestionChosen
        self.onSubmit = onSubmit
        self.updateTextOnSelect = updateTextOnSelect
        self.maxSuggestionListHeight = maxSuggestionListHeight
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentAutoSuggestBoxHost(
            text: text,
            placeholder: placeholder,
            header: header,
            querySystemImageName: querySystemImageName,
            suggestionsProvider: suggestionsProvider,
            onTextChangedEvent: onTextChangedEvent,
            onTextChanged: onTextChanged,
            onSuggestionChosen: onSuggestionChosen,
            onSubmit: onSubmit,
            updateTextOnSelect: updateTextOnSelect,
            maxSuggestionListHeight: maxSuggestionListHeight,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentAutoSuggestBoxHost else { return false }
        host.update(
            text: text,
            placeholder: placeholder,
            header: header,
            querySystemImageName: querySystemImageName,
            suggestionsProvider: suggestionsProvider,
            onTextChangedEvent: onTextChangedEvent,
            onTextChanged: onTextChanged,
            onSuggestionChosen: onSuggestionChosen,
            onSubmit: onSubmit,
            updateTextOnSelect: updateTextOnSelect,
            maxSuggestionListHeight: maxSuggestionListHeight,
            context: context
        )
        return true
    }
}

private final class FluentAutoSuggestBoxHost: NSView, NSTextFieldDelegate {
    fileprivate static let textChangedDebounce: TimeInterval = 0.150
    fileprivate static let deleteButtonWidth: CGFloat = 32
    fileprivate static let queryButtonWidth: CGFloat = 32
    fileprivate static let queryButtonMargin: CGFloat = 2
    fileprivate static let rightMargin: CGFloat = 4
    fileprivate static func textHeight(for theme: FluentTheme) -> CGFloat {
        let font = theme.typography.font(for: .body)
        return ceil(font.ascender - font.descender + font.leading)
    }
    fileprivate static func rowHeight(for theme: FluentTheme) -> CGFloat { max(40, textHeight(for: theme) + 16) }
    fileprivate static let popupVerticalPadding: CGFloat = 2

    private let field: FluentAutoSuggestBoxField
    private var headerLabel: NSTextField?
    private let clearButton = NSButton()
    private let queryButton = NSButton()
    private var bindingCoordinator: FluentStringBindingCoordinator!
    private var suggestionsProvider: (String) -> [FluentAutoSuggestBoxSuggestion]
    private var onTextChangedEvent: ((FluentAutoSuggestBoxTextChangedEvent) -> Void)?
    private var onTextChanged: ((String) -> Void)?
    private var onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)?
    private var onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)?
    private var updateTextOnSelect: Bool
    private var maxSuggestionListHeight: CGFloat
    private var theme: FluentTheme
    private var reduceMotion: Bool
    private var refreshGeneration: UInt = 0
    private var hasPendingResultRefresh = false
    private var suppressPresentation = false
    private var suggestions: [FluentAutoSuggestBoxSuggestion] = []
    private var selectedIndex = -1
    private var userTypedText = ""
    private var isApplyingProgrammaticText = false
    private var debounceWorkItem: DispatchWorkItem?
    private var popup: FluentAutoSuggestBoxPopup?
    private var pendingDismissWorkItem: DispatchWorkItem?
    private weak var geometryEditor: NSTextView?
    private var geometryText: String?

    init(
        text: FluentBinding<String>,
        placeholder: String,
        header: String?,
        querySystemImageName: String?,
        suggestionsProvider: @escaping (String) -> [FluentAutoSuggestBoxSuggestion],
        onTextChangedEvent: ((FluentAutoSuggestBoxTextChangedEvent) -> Void)?,
        onTextChanged: ((String) -> Void)?,
        onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)?,
        onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)?,
        updateTextOnSelect: Bool,
        maxSuggestionListHeight: CGFloat,
        context: FluentRenderContext
    ) {
        field = FluentAutoSuggestBoxField(placeholder: placeholder)
        if let header, !header.isEmpty {
            headerLabel = NSTextField(labelWithString: header)
        } else {
            headerLabel = nil
        }
        self.suggestionsProvider = suggestionsProvider
        self.onTextChangedEvent = onTextChangedEvent
        self.onTextChanged = onTextChanged
        self.onSuggestionChosen = onSuggestionChosen
        self.onSubmit = onSubmit
        self.updateTextOnSelect = updateTextOnSelect
        self.maxSuggestionListHeight = maxSuggestionListHeight
        theme = context.theme
        reduceMotion = context.reduceMotion
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox")
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        field.identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Field")
        field.theme = theme
        field.fluentStyle = FluentAutomaticTextFieldStyle()
        field.stringValue = text.get()
        field.delegate = self
        field.target = self
        field.action = #selector(commitText)
        addSubview(field)

        if let headerLabel {
            headerLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Header")
            headerLabel.font = theme.typography.font(for: .body)
            headerLabel.textColor = theme.textSecondary
            addSubview(headerLabel)
        }

        configureButton(
            clearButton,
            identifier: "FluentKit.AutoSuggestBox.ClearButton",
            symbolName: "xmark",
            label: "Clear",
            action: #selector(clearText)
        )
        clearButton.isHidden = true
        addSubview(clearButton)

        configureButton(
            queryButton,
            identifier: "FluentKit.AutoSuggestBox.QueryButton",
            symbolName: querySystemImageName ?? "magnifyingglass",
            label: "Search",
            action: #selector(submitQuery)
        )
        queryButton.isHidden = querySystemImageName == nil
        addSubview(queryButton)

        bindingCoordinator = FluentStringBindingCoordinator(field: field, binding: text)
        userTypedText = field.stringValue
        bindingCoordinator.onExternalValueApplied = { [weak self] value in
            self?.externalTextDidChange(value)
        }
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        updateClearButton()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let fieldHeight = max(theme.controlHeight(for: .regular), Self.textHeight(for: theme) + 14)
        let headerHeight: CGFloat = headerLabel == nil ? 0 : max(21, Self.textHeight(for: theme))
        return NSSize(width: 260, height: headerHeight + (headerLabel == nil ? 0 : 8) + fieldHeight)
    }

    override func layout() {
        super.layout()
        let fieldHeight = max(theme.controlHeight(for: .regular), Self.textHeight(for: theme) + 14)
        let headerHeight: CGFloat = headerLabel == nil ? 0 : max(21, Self.textHeight(for: theme))
        let headerGap: CGFloat = headerLabel == nil ? 0 : 8
        let fieldY = max(0, bounds.height - fieldHeight - headerHeight - headerGap)
        headerLabel?.frame = NSRect(x: 0, y: fieldY + fieldHeight + headerGap, width: bounds.width, height: headerHeight)
        field.frame = NSRect(x: 0, y: fieldY, width: bounds.width, height: fieldHeight)

        // WinUI's delete and query columns are Auto-sized. A collapsed adornment must not leave
        // its 32-point column behind, otherwise the clear glyph floats in the middle of the field
        // and the editable text is shortened even when no button is visible.
        var trailing = Self.rightMargin
        if queryButton.isHidden {
            queryButton.frame = .zero
        } else {
            queryButton.frame = NSRect(
                x: bounds.width - trailing - Self.queryButtonWidth,
                y: fieldY,
                width: Self.queryButtonWidth,
                height: fieldHeight
            )
            trailing += Self.queryButtonWidth
        }
        if clearButton.isHidden {
            clearButton.frame = .zero
        } else {
            if !queryButton.isHidden { trailing += Self.queryButtonMargin }
            clearButton.frame = NSRect(
                x: bounds.width - trailing - Self.deleteButtonWidth,
                y: fieldY,
                width: Self.deleteButtonWidth,
                height: fieldHeight
            )
            trailing += Self.deleteButtonWidth
        }
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        for button in [clearButton, queryButton] where !button.isHidden {
            if rtl { button.frame.origin.x = bounds.width - button.frame.maxX }
        }
        field.userInterfaceLayoutDirection = userInterfaceLayoutDirection
        let alignment: NSTextAlignment = rtl ? .right : .left
        // Both control and cell alignment setters end editing. Defer the cell until blur.
        if field.currentEditor() == nil, field.cell?.alignment != alignment { field.cell?.alignment = alignment }
        headerLabel?.alignment = rtl ? .right : .left
        if let cell = field.cell as? FluentAutoSuggestBoxFieldCell {
            cell.trailingInset = max(10, trailing)
            cell.isRightToLeft = rtl
        }
        synchronizeEditorGeometry()
        popup?.reposition()
    }

    private func synchronizeEditorGeometry() {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let alignment: NSTextAlignment = userInterfaceLayoutDirection == .rightToLeft ? .right : .left
        if !isComposing, editor.alignment != alignment {
            let wasApplying = isApplyingProgrammaticText
            isApplyingProgrammaticText = true
            editor.alignment = alignment
            isApplyingProgrammaticText = wasApplying
        }
        let contentRect = field.cell?.drawingRect(forBounds: field.bounds) ?? field.bounds
        if let clip = editor.superview as? NSClipView {
            // The native field editor retains its original viewport, minimum size and scroll
            // origin. Replacing just its frame leaves clipped ascenders/descenders, especially
            // when the clear button appears or right alignment changes the native baseline.
            let viewport = field.convert(contentRect, to: clip.superview)
            let resized = clip.frame != viewport || editor.minSize != contentRect.size
            let textChanged = geometryEditor !== editor || geometryText != editor.string
            clip.automaticallyAdjustsContentInsets = false
            clip.contentInsets = .init()
            if clip.frame != viewport { clip.frame = viewport }
            editor.minSize = contentRect.size
            editor.maxSize = NSSize(width: max(editor.maxSize.width, contentRect.width), height: contentRect.height)
            if resized || textChanged {
                var width = contentRect.width
                if let manager = editor.layoutManager, let container = editor.textContainer {
                    manager.ensureLayout(for: container)
                    let range = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: editor.string.utf16.count), actualCharacterRange: nil)
                    let textWidth = manager.boundingRect(forGlyphRange: range, in: container).width
                    if textWidth > width { width = ceil(textWidth) + 2 } // Keep room for the insertion caret.
                }
                editor.frame = NSRect(x: 0, y: 0, width: width, height: contentRect.height)
                editor.scrollRangeToVisible(editor.selectedRange())
                geometryEditor = editor
                geometryText = editor.string
            }
            let x = editor.frame.width <= clip.bounds.width ? 0 : clip.bounds.minX
            clip.scroll(to: NSPoint(x: x, y: 0))
        } else {
            let frame = field.convert(contentRect, to: editor.superview)
            if editor.frame != frame { editor.frame = frame }
        }
    }

    func update(
        text: FluentBinding<String>,
        placeholder: String,
        header: String?,
        querySystemImageName: String?,
        suggestionsProvider: @escaping (String) -> [FluentAutoSuggestBoxSuggestion],
        onTextChangedEvent: ((FluentAutoSuggestBoxTextChangedEvent) -> Void)?,
        onTextChanged: ((String) -> Void)?,
        onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)?,
        onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)?,
        updateTextOnSelect: Bool,
        maxSuggestionListHeight: CGFloat,
        context: FluentRenderContext
    ) {
        reduceMotion = context.reduceMotion
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        bindingCoordinator.update(binding: text)
        if (field.placeholderAttributedString?.string ?? field.placeholderString) != placeholder { field.placeholderString = placeholder }
        updateClearButton()
        if theme != context.theme {
            theme = context.theme
            field.theme = theme
            headerLabel?.textColor = theme.textSecondary
            headerLabel?.font = theme.typography.font(for: .body)
            clearButton.contentTintColor = theme.textSecondary
            popup?.updateTheme(theme)
        }
        self.suggestionsProvider = suggestionsProvider
        self.onTextChangedEvent = onTextChangedEvent
        self.onTextChanged = onTextChanged
        self.onSuggestionChosen = onSuggestionChosen
        self.onSubmit = onSubmit
        self.updateTextOnSelect = updateTextOnSelect
        if self.maxSuggestionListHeight != maxSuggestionListHeight, maxSuggestionListHeight != 0 { suppressPresentation = false }
        self.maxSuggestionListHeight = maxSuggestionListHeight
        if let header, !header.isEmpty {
            if let headerLabel {
                if headerLabel.stringValue != header { headerLabel.stringValue = header }
            } else {
                let label = NSTextField(labelWithString: header)
                label.identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Header")
                label.font = theme.typography.font(for: .body)
                label.textColor = theme.textSecondary
                addSubview(label)
                headerLabel = label
            }
        } else if let headerLabel {
            headerLabel.removeFromSuperview()
            self.headerLabel = nil
        }
        queryButton.isHidden = querySystemImageName == nil
        updateAdornmentImage(queryButton, symbolName: querySystemImageName ?? "magnifyingglass")
        invalidateIntrinsicContentSize()
        needsLayout = true
        if !hasPendingResultRefresh && !isComposing {
            refreshSuggestions(preservingSelection: true)
        }
        updatePopup()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow {
            popup?.dismiss(animated: false)
            pendingDismissWorkItem?.cancel()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        popup?.reposition()
    }

    deinit {
        debounceWorkItem?.cancel()
        pendingDismissWorkItem?.cancel()
        popup?.dismiss(animated: false)
    }

    // MARK: - Field editing

    private var isComposing: Bool { (field.currentEditor() as? NSTextView)?.hasMarkedText() == true }

    func controlTextDidBeginEditing(_ obj: Notification) {
        pendingDismissWorkItem?.cancel()
        suppressPresentation = false
        if selectedIndex == -1 { userTypedText = field.stringValue }
        if !field.stringValue.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasPendingResultRefresh, !self.isComposing else { return }
                self.refreshSuggestions(preservingSelection: true)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isApplyingProgrammaticText else { return }
        bindingCoordinator.scheduleCurrentValuePublication()
        userTypedText = field.stringValue
        selectedIndex = -1
        if field.currentEditor()?.alignment != (userInterfaceLayoutDirection == .rightToLeft ? NSTextAlignment.right : .left) { needsLayout = true }
        updateClearButton()
        cancelPendingTextChange()
        if isComposing && bindingCoordinator.currentBinding.textInputConfiguration.commitPolicy == .committedText {
            // A pending pre-composition debounce must not open our popup over the IME candidates.
            popup?.dismiss(animated: false)
            return
        }
        suppressPresentation = false
        scheduleTextChange(reason: .userInput, refreshResults: true)
        updatePopup()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        bindingCoordinator.publishCurrentValue()
        needsLayout = true
        if popup?.isPresented == true && NSEvent.pressedMouseButtons != 0 {
            pendingDismissWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.popup?.dismiss(animated: true) }
            pendingDismissWorkItem = work
            DispatchQueue.main.async(execute: work)
        } else {
            popup?.dismiss(animated: true)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard popup?.isPresented == true else { return false }
            moveSelection(forward: commandSelector == #selector(NSResponder.moveDown(_:)))
            return true
        case #selector(NSResponder.insertNewline(_:)):
            submitCurrentSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelSuggestionNavigation()
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            if popup?.isPresented == true { cancelSuggestionNavigation() }
            return false // Continue normal key-view traversal after restoring the query.
        default:
            return false
        }
    }

    // MARK: - Suggestions

    private func cancelPendingTextChange() {
        refreshGeneration &+= 1
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        hasPendingResultRefresh = false
    }

    private func scheduleTextChange(reason: FluentAutoSuggestBoxTextChangeReason, refreshResults: Bool) {
        cancelPendingTextChange()
        hasPendingResultRefresh = refreshResults
        let generation = refreshGeneration
        let event = FluentAutoSuggestBoxTextChangedEvent(text: field.stringValue, reason: reason)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.refreshGeneration == generation else { return }
            self.debounceWorkItem = nil
            self.hasPendingResultRefresh = false
            if self.isComposing && self.bindingCoordinator.currentBinding.textInputConfiguration.commitPolicy == .committedText { return }
            // WinUI raises TextChanged first, so an application can supply the new results there.
            self.onTextChanged?(event.text)
            self.onTextChangedEvent?(event)
            guard self.refreshGeneration == generation else { return }
            if refreshResults { self.refreshSuggestions(preservingSelection: false) }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.textChangedDebounce, execute: work)
    }

    private func externalTextDidChange(_ value: String) {
        userTypedText = value
        needsLayout = true
        selectedIndex = -1
        suggestions = []
        popup?.dismiss(animated: false)
        suppressPresentation = false
        updateClearButton()
        scheduleTextChange(reason: .programmaticChange, refreshResults: true)
    }

    private func refreshSuggestions(preservingSelection: Bool) {
        let selectedID = preservingSelection && suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex].id : nil
        // Keyboard preview must not turn the previewed title into a new filter query.
        let values = suggestionsProvider(userTypedText)
        suggestions = values
        selectedIndex = selectedID.flatMap { id in values.firstIndex { $0.id == id } } ?? -1
        updatePopup()
    }

    private func updatePopup() {
        guard field.currentEditor() != nil, !isComposing, !suppressPresentation,
              !field.stringValue.isEmpty, !suggestions.isEmpty, maxSuggestionListHeight != 0 else {
            popup?.dismiss(animated: false)
            return
        }
        if let popup {
            popup.update(suggestions: suggestions, selectedIndex: selectedIndex, theme: theme,
                maxSuggestionListHeight: maxSuggestionListHeight, reduceMotion: reduceMotion)
        } else {
            presentPopup()
        }
    }

    private func presentPopup() {
        guard !suggestions.isEmpty, let window = field.window else { return }
        let popup = FluentAutoSuggestBoxPopup(
            theme: theme, reduceMotion: reduceMotion, maxSuggestionListHeight: maxSuggestionListHeight,
            onSelect: { [weak self] index in self?.chooseSuggestion(at: index) },
            onDismiss: { [weak self] in
                self?.popup = nil
                self?.selectedIndex = -1
                self?.suppressPresentation = true
            }
        )
        self.popup = popup
        popup.present(relativeTo: field, suggestions: suggestions, selectedIndex: selectedIndex, in: window)
    }

    private func moveSelection(forward: Bool) {
        guard popup?.isPresented == true, !suggestions.isEmpty else { return }
        // WinUI keeps the sole suggestion selected instead of cycling back to the query.
        if suggestions.count == 1 && selectedIndex == 0 { return }
        let candidate = selectedIndex == -1 ? (forward ? 0 : suggestions.count - 1) : selectedIndex + (forward ? 1 : -1)
        applySelectionChange(to: suggestions.indices.contains(candidate) ? candidate : -1)
    }

    private func setPreviewText(_ value: String, reason: FluentAutoSuggestBoxTextChangeReason) {
        let changed = field.stringValue != value
        isApplyingProgrammaticText = true
        field.stringValue = value
        if let editor = field.currentEditor() as? NSTextView {
            editor.string = value
            editor.setSelectedRange(NSRange(location: value.utf16.count, length: 0))
        }
        synchronizeEditorGeometry()
        isApplyingProgrammaticText = false
        updateClearButton()
        bindingCoordinator.publishCurrentValue()
        if changed && field.stringValue == value { scheduleTextChange(reason: reason, refreshResults: false) }
    }

    private func applySelectionChange(to index: Int) {
        if index >= 0 && index == selectedIndex { return }
        selectedIndex = index
        if index == -1 {
            setPreviewText(userTypedText, reason: .programmaticChange)
        } else if suggestions.indices.contains(index) {
            let suggestion = suggestions[index]
            if updateTextOnSelect { setPreviewText(suggestion.title, reason: .suggestionChosen) }
            onSuggestionChosen?(suggestion)
        }
        updatePopup()
    }

    private func chooseSuggestion(at index: Int) {
        guard popup?.isPresented == true, suggestions.indices.contains(index) else { return }
        applySelectionChange(to: index)
        submitCurrentSelection()
    }

    private func submitCurrentSelection() {
        let suggestion = popup?.isPresented == true && suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex] : nil
        bindingCoordinator.publishCurrentValue()
        suppressPresentation = true
        popup?.dismiss(animated: true)
        onSubmit?(field.stringValue, suggestion)
    }

    private func cancelSuggestionNavigation() {
        suppressPresentation = true
        // WinUI restores the user's query even when a result refresh removed the selected
        // item. Selection identity must not decide whether preview text can be cancelled.
        applySelectionChange(to: -1)
        popup?.dismiss(animated: true)
    }

    // MARK: - Adornments and actions

    @objc private func commitText() {
        bindingCoordinator.publishCurrentValue()
    }

    @objc private func submitQuery() {
        bindingCoordinator.publishCurrentValue()
        suppressPresentation = true
        popup?.dismiss(animated: true)
        onSubmit?(field.stringValue, nil)
    }

    @objc private func clearText() {
        isApplyingProgrammaticText = true
        field.stringValue = ""
        isApplyingProgrammaticText = false
        userTypedText = ""
        selectedIndex = -1
        updateClearButton()
        bindingCoordinator.publishCurrentValue()
        popup?.dismiss(animated: true)
        suppressPresentation = false
        suggestions = []
        scheduleTextChange(reason: .userInput, refreshResults: true)
    }

    private func updateClearButton() {
        let visible = !field.stringValue.isEmpty
        if clearButton.isHidden != !visible {
            clearButton.isHidden = !visible
            needsLayout = true
        }
    }

    private func configureButton(
        _ button: NSButton,
        identifier: String,
        symbolName: String,
        label: String,
        action: Selector
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.isBordered = false
        button.focusRingType = .none
        // WinUI's DeleteButton/QueryButton are not Tab stops. Keep their native actions
        // available, while pointer activation leaves editing focus in the text field.
        button.refusesFirstResponder = true
        button.target = self
        button.action = action
        button.setAccessibilityLabel(label)
        updateAdornmentImage(button, symbolName: symbolName)
    }

    private func updateAdornmentImage(_ button: NSButton, symbolName: String) {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: button.accessibilityLabel()) else {
            button.image = nil
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.image = symbol.withSymbolConfiguration(configuration) ?? symbol
        button.image?.isTemplate = true
        button.contentTintColor = theme.textSecondary
    }
}

/// Fluent text field whose content column reserves WinUI's delete/query/right-margin columns.
private final class FluentAutoSuggestBoxField: FluentTextField {
    override init(placeholder: String = "") {
        super.init(placeholder: placeholder)
        cell = FluentAutoSuggestBoxFieldCell(textCell: "")
        cell?.isEditable = true
        cell?.isSelectable = true
        configureFluentSingleLineTextControl(self)
        isEditable = true
        isSelectable = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
}

private final class FluentAutoSuggestBoxFieldCell: NSTextFieldCell {
    var trailingInset: CGFloat = 10
    var isRightToLeft = false

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.drawingRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: isRightToLeft ? trailingInset : 10,
            trailingInset: isRightToLeft ? 10 : trailingInset
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

/// The suggestion popup: an application-owned borderless panel attached to the field.
private final class FluentAutoSuggestBoxPopup: NSObject {
    private var reduceMotion: Bool
    private var theme: FluentTheme
    private var maxSuggestionListHeight: CGFloat
    private let onSelect: (Int) -> Void
    private let onDismiss: () -> Void
    private var panel: NSPanel?
    private weak var transitionHost: FluentPopupTransitionHost?
    private weak var suggestionsView: FluentAutoSuggestBoxSuggestionsView?
    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var anchorGeometryObservers: [NSObjectProtocol] = []
    private var observedAncestorIDs: [ObjectIdentifier] = []
    private weak var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?

    init(
        theme: FluentTheme,
        reduceMotion: Bool,
        maxSuggestionListHeight: CGFloat,
        onSelect: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.theme = theme
        self.reduceMotion = reduceMotion
        self.maxSuggestionListHeight = maxSuggestionListHeight
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        super.init()
    }

    var isPresented: Bool { panel?.isVisible == true }

    func present(
        relativeTo anchor: NSView,
        suggestions: [FluentAutoSuggestBoxSuggestion],
        selectedIndex: Int,
        in anchorWindow: NSWindow
    ) {
        dismiss(animated: false, notify: false)
        guard !suggestions.isEmpty else { return }
        self.anchor = anchor
        let size = preferredSize(suggestionCount: suggestions.count)
        guard size.height > 0 else { dismiss(animated: false); return }
        registerAppearanceUpdates(from: anchorWindow)
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visibleFrame = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = origin(
            anchorRect: anchorRect,
            size: size,
            visibleFrame: visibleFrame
        )

        let suggestionsView = FluentAutoSuggestBoxSuggestionsView(
            suggestions: suggestions,
            selectedIndex: selectedIndex,
            theme: theme,
            onSelect: onSelect
        )
        suggestionsView.userInterfaceLayoutDirection = anchor.userInterfaceLayoutDirection
        suggestionsView.frame = NSRect(origin: .zero, size: size)

        let popup = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = false
        // A transient child panel does not become the key window. Its row tracking areas are
        // activeAlways, and mouse-move delivery must remain enabled for WinUI PointerOver states.
        popup.acceptsMouseMovedEvents = true
        popup.level = .popUpMenu
        popup.collectionBehavior = [.transient, .fullScreenAuxiliary]
        popup.hidesOnDeactivate = true
        popup.appearance = fluentAppKitAppearance(for: theme) ?? anchorWindow.effectiveAppearance

        let transitionHost = FluentPopupTransitionHost(
            content: suggestionsView,
            theme: theme,
            cornerRadius: theme.designTokens.cardCornerRadius,
            name: "FluentKit.AutoSuggestBox.Popup"
        )
        transitionHost.frame = NSRect(origin: .zero, size: size)
        transitionHost.autoresizingMask = [.width, .height]
        popup.contentView = transitionHost
        popup.setFrameOrigin(origin)
        anchorWindow.addChildWindow(popup, ordered: .above)

        let revealEdge: FluentPopupRevealEdge = origin.y + size.height <= anchorRect.minY ? .top : .bottom
        fluentPrepareMenuPopupEntrance(
            host: transitionHost,
            edge: revealEdge,
            motion: FluentMotion.menuOpen,
            closedRatio: 0.5,
            reduceMotion: reduceMotion
        )

        self.panel = popup
        self.transitionHost = transitionHost
        self.suggestionsView = suggestionsView
        popup.orderFront(nil)
        observeAnchorGeometry()
        installOutsideClickMonitors()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: anchorWindow, queue: .main) { [weak self] _ in self?.reposition() })
        }
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: anchorWindow, queue: .main) { [weak self] _ in self?.dismiss(animated: false) })
        }
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in self?.dismiss(animated: false) })
        suggestionsView.layoutSubtreeIfNeeded()
        suggestionsView.revealSelection()
    }

    func update(
        suggestions: [FluentAutoSuggestBoxSuggestion], selectedIndex: Int, theme: FluentTheme,
        maxSuggestionListHeight: CGFloat, reduceMotion: Bool
    ) {
        guard isPresented, let panel else { return }
        self.theme = theme
        self.maxSuggestionListHeight = maxSuggestionListHeight
        self.reduceMotion = reduceMotion
        suggestionsView?.update(suggestions: suggestions, selectedIndex: selectedIndex, theme: theme)
        transitionHost?.update(theme: theme)
        panel.appearance = fluentAppKitAppearance(for: theme)
        reposition()
        suggestionsView?.revealSelection()
    }

    func reposition() {
        guard let panel else { return }
        guard let anchor, let window = anchor.window, panel.parent === window else {
            dismiss(animated: false)
            return
        }
        guard !anchor.isHiddenOrHasHiddenAncestor,
              !anchor.bounds.intersection(anchor.visibleRect).isEmpty else {
            dismiss(animated: false)
            return
        }
        observeAnchorGeometry()
        let size = preferredSize(suggestionCount: suggestionsView?.count ?? 0)
        guard size.height > 0 else { dismiss(animated: false); return }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(origin: origin(anchorRect: rect, size: size, visibleFrame: visible), size: size)
        let resized = frame.size != panel.frame.size
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        suggestionsView?.userInterfaceLayoutDirection = anchor.userInterfaceLayoutDirection
        transitionHost?.frame = NSRect(origin: .zero, size: size)
        suggestionsView?.frame = NSRect(origin: .zero, size: size)
        suggestionsView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
        suggestionsView?.revealSelection()
        if resized || reduceMotion { transitionHost?.settlePresentation() }
    }

    func updateTheme(_ theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        suggestionsView?.updateTheme(theme)
        transitionHost?.update(theme: theme)
        panel?.appearance = fluentAppKitAppearance(for: theme)
        panel?.contentView?.needsDisplay = true
        reposition()
        suggestionsView?.revealSelection()
    }

    func dismiss(animated: Bool) {
        dismiss(animated: animated, notify: true)
    }

    private func dismiss(animated: Bool, notify: Bool) {
        removeAnchorGeometryObservers()
        guard let popupPanel = panel else {
            if notify { onDismiss() }
            return
        }
        removeOutsideClickMonitors()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        suggestionsView?.deactivate()
        unregisterAppearanceUpdates()
        panel = nil
        transitionHost = nil
        suggestionsView = nil
        popupPanel.parent?.removeChildWindow(popupPanel)
        popupPanel.orderOut(nil)
        if notify { onDismiss() }
    }

    deinit {
        dismiss(animated: false, notify: false)
    }

    private func preferredSize(suggestionCount: Int) -> NSSize {
        guard let anchor, let window = anchor.window else { return .zero }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let available = max(0, max(rect.minY - visible.minY - 2, visible.maxY - rect.maxY - 2))
        let contentHeight = CGFloat(suggestionCount) * FluentAutoSuggestBoxHost.rowHeight(for: theme)
            + FluentAutoSuggestBoxHost.popupVerticalPadding * 2
        // WinUI: zero hides the list; a negative maximum means use the available screen space.
        let maximum = maxSuggestionListHeight < 0 ? available : maxSuggestionListHeight
        return NSSize(width: min(anchor.bounds.width, max(0, visible.width - 8)),
            height: max(0, min(maximum, available, contentHeight)))
    }

    private func origin(anchorRect: NSRect, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let below = anchorRect.minY - size.height - 2
        let y = below >= visibleFrame.minY ? below : min(anchorRect.maxY + 2, visibleFrame.maxY - size.height)
        let rtl = anchor?.userInterfaceLayoutDirection == .rightToLeft
        let leading = rtl ? anchorRect.maxX - size.width : anchorRect.minX
        let x = min(max(leading, visibleFrame.minX + 4), max(visibleFrame.maxX - size.width - 4, visibleFrame.minX + 4))
        return NSPoint(x: x, y: max(visibleFrame.minY, y))
    }

    private func observeAnchorGeometry() {
        // A child NSPanel follows its window, but not the input's scrolling/layout ancestors.
        // AppKit posts these view notifications by default; leave client notification flags alone.
        var ancestors: [NSView] = []
        var current = anchor
        while let view = current {
            ancestors.append(view)
            current = view.superview
        }
        let identifiers = ancestors.map(ObjectIdentifier.init)
        guard identifiers != observedAncestorIDs else { return }
        removeAnchorGeometryObservers()
        observedAncestorIDs = identifiers
        for view in ancestors {
            for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                anchorGeometryObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: view, queue: .main
                ) { [weak self] _ in self?.reposition() })
            }
        }
    }

    private func removeAnchorGeometryObservers() {
        anchorGeometryObservers.forEach(NotificationCenter.default.removeObserver)
        anchorGeometryObservers.removeAll()
        observedAncestorIDs.removeAll()
    }

    private func installOutsideClickMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  event.window !== self.panel,
                  !self.eventTargetsAnchor(event) else { return event }
            self.dismiss(animated: true)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss(animated: true)
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func eventTargetsAnchor(_ event: NSEvent) -> Bool {
        guard let anchor,
              event.window === anchor.window else { return false }
        return anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
    }

    private func registerAppearanceUpdates(from window: NSWindow) {
        guard let coordinator = window.fluentAppearanceCoordinator else { return }
        if appearanceCoordinator === coordinator, appearanceRegistration != nil { return }
        unregisterAppearanceUpdates()
        appearanceCoordinator = coordinator
        appearanceRegistration = coordinator.register(
            owner: self,
            prepareForAppearanceChange: { [weak self] in
                self?.transitionHost?.settleForAppearanceChange()
            }
        ) { [weak self] theme in
            self?.updateTheme(theme)
        }
    }

    private func unregisterAppearanceUpdates() {
        if let appearanceRegistration {
            appearanceCoordinator?.unregister(appearanceRegistration)
        }
        appearanceRegistration = nil
        appearanceCoordinator = nil
    }
}

private final class FluentAutoSuggestBoxSuggestionDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class FluentAutoSuggestBoxSuggestionsView: NSView {
    private let onSelect: (Int) -> Void
    private let scrollView = NSScrollView()
    private let document = FluentAutoSuggestBoxSuggestionDocument()
    private var rows: [FluentAutoSuggestBoxSuggestionRow] = []
    private var selectedIndex = -1
    private var needsSelectionReveal = true
    private var isActive = true
    private var rowHeight: CGFloat = 40
    var count: Int { rows.count }

    init(suggestions: [FluentAutoSuggestBoxSuggestion], selectedIndex: Int, theme: FluentTheme, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Suggestions")
        setAccessibilityRole(.list)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = document
        addSubview(scrollView)
        update(suggestions: suggestions, selectedIndex: selectedIndex, theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(suggestions: [FluentAutoSuggestBoxSuggestion], selectedIndex: Int, theme: FluentTheme) {
        let newHeight = FluentAutoSuggestBoxHost.rowHeight(for: theme)
        if rowHeight != newHeight { needsSelectionReveal = true }
        rowHeight = newHeight
        let oldSelected = rows.indices.contains(self.selectedIndex) ? rows[self.selectedIndex] : nil
        let oldIDs = rows.compactMap(\.suggestionID)
        var available = Dictionary(grouping: rows, by: { $0.suggestionID })
        let updated = suggestions.enumerated().map { index, suggestion -> FluentAutoSuggestBoxSuggestionRow in
            let row: FluentAutoSuggestBoxSuggestionRow
            if var matches = available[suggestion.id], !matches.isEmpty {
                row = matches.removeFirst()
                available[suggestion.id] = matches
            } else {
                row = FluentAutoSuggestBoxSuggestionRow { [weak self] index in
                    guard let self, self.isActive, self.rows.indices.contains(index) else { return }
                    self.onSelect(index)
                }
                row.identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Suggestion")
                document.addSubview(row)
            }
            row.update(suggestion: suggestion, index: index, selected: index == selectedIndex, theme: theme)
            return row
        }
        for row in available.values.flatMap({ $0 }) { row.deactivate(); row.removeFromSuperview() }
        rows = updated
        self.selectedIndex = selectedIndex
        let newSelected = rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
        needsSelectionReveal = needsSelectionReveal || oldIDs != suggestions.map(\.id) || oldSelected !== newSelected
        setAccessibilityChildren(rows)
        needsLayout = true
    }

    func updateTheme(_ theme: FluentTheme) {
        rowHeight = FluentAutoSuggestBoxHost.rowHeight(for: theme)
        for row in rows { row.updateTheme(theme) }
        needsLayout = true
        needsSelectionReveal = true
    }

    func deactivate() {
        isActive = false
        rows.forEach { $0.deactivate() }
    }

    override func layout() {
        super.layout()
        let padding = FluentAutoSuggestBoxHost.popupVerticalPadding
        let viewport = NSRect(x: 0, y: min(padding, bounds.height / 2), width: bounds.width, height: max(0, bounds.height - padding * 2))
        if scrollView.frame.size != viewport.size { needsSelectionReveal = true }
        scrollView.frame = viewport
        scrollView.tile()
        let width = scrollView.contentSize.width
        document.frame.size = NSSize(width: width, height: max(CGFloat(rows.count) * rowHeight, scrollView.contentSize.height))
        for (index, row) in rows.enumerated() {
            if row.userInterfaceLayoutDirection != userInterfaceLayoutDirection {
                row.userInterfaceLayoutDirection = userInterfaceLayoutDirection
                row.needsLayout = true
            }
            row.frame = NSRect(x: 4, y: CGFloat(index) * rowHeight,
                width: max(width - 8, 0), height: rowHeight)
        }
    }

    func revealSelection() {
        guard needsSelectionReveal else { return }
        needsSelectionReveal = false
        if rows.indices.contains(selectedIndex) { document.scrollToVisible(rows[selectedIndex].frame) }
        else { scrollView.contentView.scroll(to: .zero); scrollView.reflectScrolledClipView(scrollView.contentView) }
    }
}

private final class FluentAutoSuggestBoxSuggestionRow: NSView {
    private let onSelect: (Int) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var index = 0
    private var suggestion: FluentAutoSuggestBoxSuggestion?
    var suggestionID: AnyHashable? { suggestion?.id }
    private var isActive = true
    private var theme: FluentTheme = .current
    private var isSelected = false
    private var isPointerOver = false
    private var isPressed = false

    init(onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        wantsLayer = true
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(iconView)
        setAccessibilityRole(.row)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                // The suggestion NSPanel deliberately remains non-key so editing stays in the
                // AutoSuggestBox. activeInKeyWindow would therefore suppress every hover event.
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { false }

    override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        isPressed = false
        refreshBackground()
    }

    override func mouseDown(with event: NSEvent) {
        guard isActive, window != nil else { return }
        isPressed = true
        refreshBackground()
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
        refreshBackground()
    }

    override func mouseUp(with event: NSEvent) {
        let activates = isActive && window != nil && isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        refreshBackground()
        if activates { onSelect(index) }
    }

    func update(
        suggestion: FluentAutoSuggestBoxSuggestion,
        index: Int,
        selected: Bool,
        theme: FluentTheme
    ) {
        self.index = index
        self.theme = theme
        isSelected = selected
        setAccessibilitySelected(selected)
        if self.suggestion != suggestion {
            self.suggestion = suggestion
            titleLabel.stringValue = suggestion.title
            setAccessibilityLabel(suggestion.title)
            subtitleLabel.stringValue = suggestion.subtitle ?? ""
            subtitleLabel.isHidden = suggestion.subtitle == nil
            if let symbolName = suggestion.systemImageName,
               let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: suggestion.title) {
                let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                iconView.image = symbol.withSymbolConfiguration(configuration) ?? symbol
                iconView.image?.isTemplate = true
                iconView.isHidden = false
            } else {
                iconView.image = nil
                iconView.isHidden = true
            }
        }
        titleLabel.font = theme.typography.font(for: .body)
        subtitleLabel.font = theme.typography.font(for: .caption)
        titleLabel.textColor = theme.textPrimary
        subtitleLabel.textColor = theme.textSecondary
        iconView.contentTintColor = theme.textSecondary
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        refreshBackground()
        needsLayout = true
    }

    func updateTheme(_ theme: FluentTheme) {
        self.theme = theme
        titleLabel.font = theme.typography.font(for: .body)
        subtitleLabel.font = theme.typography.font(for: .caption)
        titleLabel.textColor = theme.textPrimary
        subtitleLabel.textColor = theme.textSecondary
        iconView.contentTintColor = theme.textSecondary
        refreshBackground()
        needsDisplay = true
        needsLayout = true
    }

    func deactivate() { isActive = false; isPressed = false }

    override func accessibilityPerformPress() -> Bool {
        guard isActive, window != nil else { return false }
        onSelect(index)
        return true
    }

    private func refreshBackground() {
        let color: NSColor
        if isPressed {
            color = theme.subtleFillTertiary
        } else if isPointerOver {
            color = theme.subtleFillSecondary
        } else if isSelected {
            color = theme.accentFillDefault.withAlphaComponent(0.12)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
    }

    override func layout() {
        super.layout()
        let leading: CGFloat = 12
        let iconSize: CGFloat = iconView.isHidden ? 0 : 18
        iconView.frame = NSRect(x: leading, y: max((bounds.height - iconSize) / 2, 0), width: iconSize, height: iconSize)
        let textX = leading + iconSize + (iconView.isHidden ? 0 : 10)
        let subtitleWidth: CGFloat = subtitleLabel.isHidden ? 0 : min(140, bounds.width * 0.38)
        let titleHeight = min(titleLabel.intrinsicContentSize.height, bounds.height)
        let subtitleHeight = min(subtitleLabel.intrinsicContentSize.height, bounds.height)
        titleLabel.frame = NSRect(
            x: textX,
            y: floor((bounds.height - titleHeight) / 2),
            width: max(bounds.width - textX - subtitleWidth - 16, 0),
            height: titleHeight
        )
        subtitleLabel.frame = NSRect(
            x: bounds.width - subtitleWidth - 12,
            y: floor((bounds.height - subtitleHeight) / 2),
            width: subtitleWidth,
            height: subtitleHeight
        )
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        if rtl {
            for view in [iconView, titleLabel, subtitleLabel] { view.frame.origin.x = bounds.width - view.frame.maxX }
        }
        titleLabel.alignment = rtl ? .right : .left
        subtitleLabel.alignment = rtl ? .left : .right
    }
}
