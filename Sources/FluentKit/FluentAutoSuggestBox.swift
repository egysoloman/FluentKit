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

/// A WinUI AutoSuggestBox backed by a Fluent text field, a query/clear adornment column, and an
/// application-owned suggestion popup.
///
/// The implementation follows the WinUI source contract:
/// - TextChanged is debounced for 150 ms before the provider is consulted and the event raised.
/// - The popup opens below the field when focused with non-empty text and matching suggestions,
///   flips above when the screen edge requires it, and closes on Escape, submit, or focus loss.
/// - Down/Up move through suggestions and update the text on select; Enter submits the selected
///   suggestion (or the raw query), and the query button always submits the raw query.
public struct FluentAutoSuggestBox: FluentUpdatablePrimitiveView {
    private let text: FluentBinding<String>
    private let placeholder: String
    private let header: String?
    private let querySystemImageName: String?
    private let suggestionsProvider: (String) -> [FluentAutoSuggestBoxSuggestion]
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
        onTextChanged: ((String) -> Void)? = nil,
        onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)? = nil,
        onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)? = nil
    ) {
        self.text = text
        self.placeholder = placeholder
        self.header = header
        self.querySystemImageName = querySystemImageName
        suggestionsProvider = suggestions
        self.onTextChanged = onTextChanged
        self.onSuggestionChosen = onSuggestionChosen
        self.onSubmit = onSubmit
        self.updateTextOnSelect = updateTextOnSelect
        self.maxSuggestionListHeight = max(0, maxSuggestionListHeight)
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentAutoSuggestBoxHost(
            text: text,
            placeholder: placeholder,
            header: header,
            querySystemImageName: querySystemImageName,
            suggestionsProvider: suggestionsProvider,
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
    fileprivate static let rowHeight: CGFloat = 40
    fileprivate static let popupVerticalPadding: CGFloat = 2

    private let field: FluentAutoSuggestBoxField
    private var headerLabel: NSTextField?
    private let clearButton = NSButton()
    private let queryButton = NSButton()
    private var bindingCoordinator: FluentStringBindingCoordinator!
    private var suggestionsProvider: (String) -> [FluentAutoSuggestBoxSuggestion]
    private var onTextChanged: ((String) -> Void)?
    private var onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)?
    private var onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)?
    private var updateTextOnSelect: Bool
    private var maxSuggestionListHeight: CGFloat
    private var theme: FluentTheme
    private var suggestions: [FluentAutoSuggestBoxSuggestion] = []
    private var selectedIndex = -1
    private var userTypedText = ""
    private var isApplyingProgrammaticText = false
    private var debounceWorkItem: DispatchWorkItem?
    private var popup: FluentAutoSuggestBoxPopup?
    private var pendingDismissWorkItem: DispatchWorkItem?

    init(
        text: FluentBinding<String>,
        placeholder: String,
        header: String?,
        querySystemImageName: String?,
        suggestionsProvider: @escaping (String) -> [FluentAutoSuggestBoxSuggestion],
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
        self.onTextChanged = onTextChanged
        self.onSuggestionChosen = onSuggestionChosen
        self.onSubmit = onSubmit
        self.updateTextOnSelect = updateTextOnSelect
        self.maxSuggestionListHeight = maxSuggestionListHeight
        theme = context.theme
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
            headerLabel.font = .systemFont(ofSize: 13)
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
        updateClearButton()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let fieldHeight = theme.controlHeight(for: .regular)
        let headerHeight: CGFloat = headerLabel == nil ? 0 : 21
        return NSSize(width: 260, height: headerHeight + (headerLabel == nil ? 0 : 8) + fieldHeight)
    }

    override func layout() {
        super.layout()
        let fieldHeight = theme.controlHeight(for: .regular)
        let headerHeight: CGFloat = headerLabel == nil ? 0 : 21
        let headerGap: CGFloat = headerLabel == nil ? 0 : 8
        let fieldY = max(0, bounds.height - fieldHeight)
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
        (field.cell as? FluentAutoSuggestBoxFieldCell)?.trailingInset = max(10, trailing)
        if let editor = field.currentEditor() {
            editor.frame = field.cell?.drawingRect(forBounds: field.bounds) ?? field.bounds
        }
    }

    func update(
        text: FluentBinding<String>,
        placeholder: String,
        header: String?,
        querySystemImageName: String?,
        suggestionsProvider: @escaping (String) -> [FluentAutoSuggestBoxSuggestion],
        onTextChanged: ((String) -> Void)?,
        onSuggestionChosen: ((FluentAutoSuggestBoxSuggestion) -> Void)?,
        onSubmit: ((String, FluentAutoSuggestBoxSuggestion?) -> Void)?,
        updateTextOnSelect: Bool,
        maxSuggestionListHeight: CGFloat,
        context: FluentRenderContext
    ) {
        bindingCoordinator.update(binding: text)
        if (field.placeholderAttributedString?.string ?? field.placeholderString) != placeholder { field.placeholderString = placeholder }
        updateClearButton()
        if theme != context.theme {
            theme = context.theme
            field.theme = theme
            headerLabel?.textColor = theme.textSecondary
            popup?.updateTheme(theme)
        }
        self.suggestionsProvider = suggestionsProvider
        self.onTextChanged = onTextChanged
        self.onSuggestionChosen = onSuggestionChosen
        self.onSubmit = onSubmit
        self.updateTextOnSelect = updateTextOnSelect
        self.maxSuggestionListHeight = max(0, maxSuggestionListHeight)
        if let header, !header.isEmpty {
            if let headerLabel {
                if headerLabel.stringValue != header { headerLabel.stringValue = header }
            } else {
                let label = NSTextField(labelWithString: header)
                label.identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Header")
                label.font = .systemFont(ofSize: 13)
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
    }

    deinit {
        debounceWorkItem?.cancel()
        pendingDismissWorkItem?.cancel()
        popup?.dismiss(animated: false)
    }

    // MARK: - Field editing

    func controlTextDidBeginEditing(_ obj: Notification) {
        if !field.stringValue.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.refreshSuggestionsAndPresentPopup()
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        let value = field.stringValue
        if !isApplyingProgrammaticText {
            bindingCoordinator.scheduleCurrentValuePublication()
            userTypedText = value
            selectedIndex = -1
            updateClearButton()
            if bindingCoordinator.currentBinding.textInputConfiguration.commitPolicy != .committedText
                || (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
                scheduleSuggestionRefresh()
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        bindingCoordinator.publishCurrentValue()
        if popup?.isPresented == true && NSEvent.pressedMouseButtons != 0 {
            pendingDismissWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.popup?.isPresented == true else { return }
                self.popup?.dismiss(animated: true)
            }
            pendingDismissWorkItem = work
            DispatchQueue.main.async(execute: work)
        } else {
            popup?.dismiss(animated: true)
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(forward: true)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(forward: false)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            submitCurrentSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelSuggestionNavigation()
            return true
        default:
            return false
        }
    }

    // MARK: - Suggestions

    private func scheduleSuggestionRefresh() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshSuggestionsAndPresentPopup()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.textChangedDebounce,
            execute: work
        )
    }

    private func refreshSuggestionsAndPresentPopup() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        let values = suggestionsProvider(field.stringValue)
        suggestions = values
        selectedIndex = -1
        onTextChanged?(field.stringValue)
        if field.currentEditor() != nil, !field.stringValue.isEmpty, !values.isEmpty {
            if let popup {
                popup.update(suggestions: values, selectedIndex: selectedIndex, theme: theme)
            } else {
                presentPopup()
            }
        } else {
            popup?.dismiss(animated: true)
        }
    }

    private func presentPopup() {
        guard !suggestions.isEmpty, let window = field.window else { return }
        popup?.dismiss(animated: false)
        let popup = FluentAutoSuggestBoxPopup(
            theme: theme,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            maxSuggestionListHeight: maxSuggestionListHeight,
            onSelect: { [weak self] index in
                self?.chooseSuggestion(at: index)
            },
            onDismiss: { [weak self] in
                self?.popup = nil
            }
        )
        self.popup = popup
        popup.present(
            relativeTo: field,
            suggestions: suggestions,
            selectedIndex: selectedIndex,
            in: window
        )
    }

    private func moveSelection(forward: Bool) {
        guard !suggestions.isEmpty else {
            popup?.dismiss(animated: true)
            return
        }
        if popup == nil { presentPopup() }
        let nextIndex: Int
        if selectedIndex == -1 {
            nextIndex = forward ? 0 : suggestions.count - 1
        } else {
            let candidate = selectedIndex + (forward ? 1 : -1)
            if candidate < 0 || candidate >= suggestions.count {
                nextIndex = -1
            } else {
                nextIndex = candidate
            }
        }
        applySelectionChange(to: nextIndex)
    }

    private func applySelectionChange(to index: Int) {
        if index == -1 {
            selectedIndex = -1
            isApplyingProgrammaticText = true
            field.stringValue = userTypedText
            isApplyingProgrammaticText = false
            updateClearButton()
        } else if suggestions.indices.contains(index) {
            selectedIndex = index
            let suggestion = suggestions[index]
            if updateTextOnSelect {
                isApplyingProgrammaticText = true
                field.stringValue = suggestion.title
                isApplyingProgrammaticText = false
                updateClearButton()
                bindingCoordinator.publishCurrentValue()
            }
            onSuggestionChosen?(suggestion)
        }
        popup?.update(suggestions: suggestions, selectedIndex: selectedIndex, theme: theme)
    }

    private func chooseSuggestion(at index: Int) {
        guard suggestions.indices.contains(index) else { return }
        applySelectionChange(to: index)
        submitCurrentSelection()
    }

    private func submitCurrentSelection() {
        let suggestion = selectedIndex >= 0 && selectedIndex < suggestions.count
            ? suggestions[selectedIndex]
            : nil
        bindingCoordinator.publishCurrentValue()
        onSubmit?(field.stringValue, suggestion)
        popup?.dismiss(animated: true)
    }

    private func cancelSuggestionNavigation() {
        guard popup?.isPresented == true else {
            popup?.dismiss(animated: true)
            return
        }
        applySelectionChange(to: -1)
        popup?.dismiss(animated: true)
    }

    // MARK: - Adornments and actions

    @objc private func commitText() {
        bindingCoordinator.publishCurrentValue()
    }

    @objc private func submitQuery() {
        bindingCoordinator.publishCurrentValue()
        onSubmit?(field.stringValue, nil)
        popup?.dismiss(animated: true)
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
        scheduleSuggestionRefresh()
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

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.drawingRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: 10,
            trailingInset: trailingInset
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
    private let reduceMotion: Bool
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
        registerAppearanceUpdates(from: anchorWindow)
        let size = preferredSize(suggestionCount: suggestions.count)
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
        installOutsideClickMonitors()
    }

    func update(
        suggestions: [FluentAutoSuggestBoxSuggestion],
        selectedIndex: Int,
        theme: FluentTheme
    ) {
        guard isPresented, let panel else { return }
        self.theme = theme
        let size = preferredSize(suggestionCount: suggestions.count)
        suggestionsView?.update(
            suggestions: suggestions,
            selectedIndex: selectedIndex,
            theme: theme
        )
        transitionHost?.update(theme: theme)
        panel.appearance = fluentAppKitAppearance(for: theme)
        if !size.equalTo(panel.frame.size) {
            panel.setContentSize(size)
            transitionHost?.frame = NSRect(origin: .zero, size: size)
            suggestionsView?.frame = NSRect(origin: .zero, size: size)
        }
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func updateTheme(_ theme: FluentTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        suggestionsView?.updateTheme(theme)
        transitionHost?.update(theme: theme)
        panel?.appearance = fluentAppKitAppearance(for: theme)
        panel?.contentView?.needsDisplay = true
    }

    func dismiss(animated: Bool) {
        dismiss(animated: animated, notify: true)
    }

    private func dismiss(animated: Bool, notify: Bool) {
        guard let popupPanel = panel else {
            if notify { onDismiss() }
            return
        }
        removeOutsideClickMonitors()
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
        let width = max(anchor?.bounds.width ?? 0, 160)
        let contentHeight = CGFloat(suggestionCount) * FluentAutoSuggestBoxHost.rowHeight
            + FluentAutoSuggestBoxHost.popupVerticalPadding * 2
        let availableHeight: CGFloat
        if let anchor, let window = anchor.window {
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            availableHeight = visibleFrame.height - 24
        } else {
            availableHeight = maxSuggestionListHeight
        }
        return NSSize(
            width: width,
            height: min(maxSuggestionListHeight > 0 ? maxSuggestionListHeight : availableHeight, max(contentHeight, 0))
        )
    }

    private func origin(anchorRect: NSRect, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let gap: CGFloat = 2
        let below = anchorRect.minY - size.height - gap
        let above = anchorRect.maxY + gap
        let maximumY = visibleFrame.maxY - size.height
        let y: CGFloat
        if below >= visibleFrame.minY {
            y = below
        } else if above <= maximumY {
            y = above
        } else {
            y = min(max(below, visibleFrame.minY), maximumY)
        }
        let x = min(max(anchorRect.minX, visibleFrame.minX + 4), max(visibleFrame.maxX - size.width - 4, visibleFrame.minX + 4))
        return NSPoint(x: x, y: y)
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

private final class FluentAutoSuggestBoxSuggestionsView: NSView {
    private let onSelect: (Int) -> Void
    private var rows: [FluentAutoSuggestBoxSuggestionRow] = []
    private var theme: FluentTheme

    init(
        suggestions: [FluentAutoSuggestBoxSuggestion],
        selectedIndex: Int,
        theme: FluentTheme,
        onSelect: @escaping (Int) -> Void
    ) {
        self.onSelect = onSelect
        self.theme = theme
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Suggestions")
        setAccessibilityRole(.list)
        update(suggestions: suggestions, selectedIndex: selectedIndex, theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func update(
        suggestions: [FluentAutoSuggestBoxSuggestion],
        selectedIndex: Int,
        theme: FluentTheme
    ) {
        self.theme = theme
        while rows.count > suggestions.count {
            let row = rows.removeLast()
            row.removeFromSuperview()
        }
        while rows.count < suggestions.count {
            let row = FluentAutoSuggestBoxSuggestionRow { [weak self] index in
                self?.onSelect(index)
            }
            row.identifier = NSUserInterfaceItemIdentifier("FluentKit.AutoSuggestBox.Suggestion")
            addSubview(row)
            rows.append(row)
        }
        for (index, row) in rows.enumerated() {
            row.update(
                suggestion: suggestions[index],
                index: index,
                selected: index == selectedIndex,
                theme: theme
            )
            row.frame = NSRect(
                x: 4,
                y: bounds.height - resolvedVerticalPadding
                    - CGFloat(index + 1) * FluentAutoSuggestBoxHost.rowHeight,
                width: max(bounds.width - 8, 0),
                height: FluentAutoSuggestBoxHost.rowHeight
            )
        }
        needsDisplay = true
    }

    func updateTheme(_ theme: FluentTheme) {
        self.theme = theme
        for row in rows { row.updateTheme(theme) }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: 4,
                y: bounds.height - resolvedVerticalPadding
                    - CGFloat(index + 1) * FluentAutoSuggestBoxHost.rowHeight,
                width: max(bounds.width - 8, 0),
                height: FluentAutoSuggestBoxHost.rowHeight
            )
        }
    }

    /// Do not let decorative popup padding consume part of the final suggestion row when the
    /// caller's maximum height is an exact multiple of the WinUI row height. WinUI's presenter
    /// clips the list viewport, not an individual ListViewItem.
    private var resolvedVerticalPadding: CGFloat {
        let required = CGFloat(rows.count) * FluentAutoSuggestBoxHost.rowHeight
            + FluentAutoSuggestBoxHost.popupVerticalPadding * 2
        return bounds.height + 0.5 >= required ? FluentAutoSuggestBoxHost.popupVerticalPadding : 0
    }
}

private final class FluentAutoSuggestBoxSuggestionRow: NSView {
    private let onSelect: (Int) -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var index = 0
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
        isPressed = true
        refreshBackground()
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
        refreshBackground()
    }

    override func mouseUp(with event: NSEvent) {
        let activates = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
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
        titleLabel.textColor = theme.textPrimary
        subtitleLabel.textColor = theme.textSecondary
        iconView.contentTintColor = theme.textSecondary
        refreshBackground()
        needsDisplay = true
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
        subtitleLabel.alignment = .right
    }
}
