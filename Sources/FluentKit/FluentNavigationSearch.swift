import AppKit

private extension Notification.Name {
    static let fluentNavigationSearchFocusRequested = Notification.Name(
        "FluentKit.NavigationSearch.FocusRequested"
    )
}

/// A type-erased suggestion displayed by `FluentNavigationSearch`.
public struct FluentNavigationSearchSuggestion: Hashable {
    public let id: AnyHashable
    public let title: String
    public let subtitle: String?
    public let systemImageName: String?

    public init(
        id: AnyHashable,
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

/// WinUI AutoSuggestBox behavior for a NavigationView pane. The pane owns the compact/expanded
/// placement; this view owns query editing, suggestions, submit, and Escape semantics.
public struct FluentNavigationSearch: FluentUpdatablePrimitiveView {
    private let query: FluentBinding<String>
    private let placeholder: String
    private let suggestions: (String) -> [FluentNavigationSearchSuggestion]
    private let onSubmit: (String, FluentNavigationSearchSuggestion?) -> Void
    private let isPaneOpen: FluentBinding<Bool>?

    public init(
        _ query: FluentBinding<String>,
        placeholder: String = "Search",
        isPaneOpen: FluentBinding<Bool>? = nil,
        suggestions: @escaping (String) -> [FluentNavigationSearchSuggestion] = { _ in [] },
        onSubmit: @escaping (String, FluentNavigationSearchSuggestion?) -> Void
    ) {
        self.query = query
        self.placeholder = placeholder
        self.isPaneOpen = isPaneOpen
        self.suggestions = suggestions
        self.onSubmit = onSubmit
    }

    public var body: NeverFluentView { NeverFluentView() }

    /// Requests the NavigationSearch belonging to a window to expand its pane and take focus.
    public static func requestFocus(in window: NSWindow? = NSApp.keyWindow) {
        NotificationCenter.default.post(
            name: .fluentNavigationSearchFocusRequested,
            object: window
        )
    }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentNavigationSearchHost(
            query: query,
            placeholder: placeholder,
            isPaneOpen: isPaneOpen,
            suggestions: suggestions,
            onSubmit: onSubmit,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNavigationSearchHost else { return false }
        host.update(
            query: query,
            placeholder: placeholder,
            isPaneOpen: isPaneOpen,
            suggestions: suggestions,
            onSubmit: onSubmit,
            context: context
        )
        return true
    }
}

private final class FluentNavigationSearchHost: NSView, NSSearchFieldDelegate {
    private let field: FluentSearchTextField
    private let compactButton = NSButton()
    private let suggestionsStack = NSStackView()
    private var query: FluentBinding<String>
    private var isPaneOpen: FluentBinding<Bool>?
    private var suggestionProvider: (String) -> [FluentNavigationSearchSuggestion]
    private var submit: (String, FluentNavigationSearchSuggestion?) -> Void
    private var context: FluentRenderContext
    private var observerID: UUID?
    private var isCompact = false
    private var suggestionByButton: [ObjectIdentifier: FluentNavigationSearchSuggestion] = [:]
    private var focusRequestObserver: NSObjectProtocol?

    init(
        query: FluentBinding<String>,
        placeholder: String,
        isPaneOpen: FluentBinding<Bool>?,
        suggestions: @escaping (String) -> [FluentNavigationSearchSuggestion],
        onSubmit: @escaping (String, FluentNavigationSearchSuggestion?) -> Void,
        context: FluentRenderContext
    ) {
        self.query = query
        self.isPaneOpen = isPaneOpen
        suggestionProvider = suggestions
        submit = onSubmit
        self.context = context
        field = FluentSearchTextField(placeholder: placeholder)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Search")
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        field.theme = context.theme
        field.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Search.Field")
        field.stringValue = query.get()
        field.delegate = self
        field.target = self
        field.action = #selector(submitQuery)
        field.onCancel = { [weak self] in self?.cancelSearch() }
        addSubview(field)

        compactButton.isBordered = false
        compactButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Search.CompactButton")
        compactButton.bezelStyle = .regularSquare
        compactButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        compactButton.imagePosition = .imageOnly
        compactButton.target = self
        compactButton.action = #selector(requestExpandedSearch)
        compactButton.setAccessibilityRole(.button)
        compactButton.setAccessibilityLabel("Search")
        addSubview(compactButton)

        suggestionsStack.orientation = .vertical
        suggestionsStack.alignment = .width
        suggestionsStack.spacing = 1
        suggestionsStack.wantsLayer = true
        addSubview(suggestionsStack)
        installObserver()
        updateSuggestions()
        focusRequestObserver = NotificationCenter.default.addObserver(
            forName: .fluentNavigationSearchFocusRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let requestedWindow = notification.object as? NSWindow
            guard requestedWindow == nil || requestedWindow === self.window else { return }
            self.requestExpandedSearch()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let suggestionHeight = CGFloat(suggestionsStack.arrangedSubviews.count) * 36
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: isCompact ? 40 : 32 + (suggestionHeight > 0 ? suggestionHeight + 2 : 0)
        )
    }

    override func layout() {
        super.layout()
        let compact = bounds.width > 0 && bounds.width < 120
        if compact != isCompact {
            isCompact = compact
            invalidateIntrinsicContentSize()
        }
        compactButton.isHidden = !isCompact
        field.isHidden = isCompact
        compactButton.frame = NSRect(x: 4, y: 0, width: 40, height: min(bounds.height, 40))
        field.frame = NSRect(x: 0, y: max(bounds.height - 32, 0), width: bounds.width, height: 32)
        suggestionsStack.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(field.frame.minY - 2, 0)
        )
        suggestionsStack.isHidden = isCompact || suggestionsStack.arrangedSubviews.isEmpty
    }

    func update(
        query: FluentBinding<String>,
        placeholder: String,
        isPaneOpen: FluentBinding<Bool>?,
        suggestions: @escaping (String) -> [FluentNavigationSearchSuggestion],
        onSubmit: @escaping (String, FluentNavigationSearchSuggestion?) -> Void,
        context: FluentRenderContext
    ) {
        let identityChanged = query.observationIdentity != self.query.observationIdentity
        if identityChanged { removeObserver() }
        self.query = query
        self.isPaneOpen = isPaneOpen
        suggestionProvider = suggestions
        submit = onSubmit
        self.context = context
        field.theme = context.theme
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        if field.stringValue != query.get() { field.stringValue = query.get() }
        installObserver()
        updateSuggestions()
        needsLayout = true
    }

    func controlTextDidChange(_ notification: Notification) {
        let value = field.stringValue
        if query.get() != value { query.set(value) }
        updateSuggestions()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if field.stringValue != query.get() { query.set(field.stringValue) }
    }

    private func installObserver() {
        guard observerID == nil else { return }
        observerID = query.observe { [weak self] value in
            guard let self, self.field.stringValue != value else { return }
            self.field.stringValue = value
            self.updateSuggestions()
        }
    }

    private func removeObserver() {
        if let observerID { query.removeObserver(observerID) }
        observerID = nil
    }

    private func updateSuggestions() {
        let values = suggestionProvider(field.stringValue).prefix(8)
        suggestionsStack.arrangedSubviews.forEach {
            suggestionByButton.removeValue(forKey: ObjectIdentifier($0))
            suggestionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for suggestion in values {
            let button = NSButton(title: suggestion.title, target: self, action: #selector(selectSuggestion(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Search.Suggestion")
            suggestionByButton[ObjectIdentifier(button)] = suggestion
            button.alignment = .left
            button.isBordered = false
            button.contentTintColor = context.theme.textPrimary
            button.toolTip = suggestion.subtitle
            button.setAccessibilityLabel(suggestion.subtitle.map { "\(suggestion.title), \($0)" } ?? suggestion.title)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            suggestionsStack.addArrangedSubview(button)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    @objc private func submitQuery() {
        query.set(field.stringValue)
        submit(field.stringValue, nil)
    }

    @objc private func selectSuggestion(_ sender: NSButton) {
        guard let suggestion = suggestionByButton[ObjectIdentifier(sender)] else { return }
        field.stringValue = suggestion.title
        query.set(suggestion.title)
        submit(suggestion.title, suggestion)
    }

    @objc private func requestExpandedSearch() {
        isPaneOpen?.set(true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.field)
            self.field.selectText(nil)
        }
    }

    private func cancelSearch() {
        query.set("")
        window?.makeFirstResponder(nil)
    }

    deinit {
        removeObserver()
        if let focusRequestObserver { NotificationCenter.default.removeObserver(focusRequestObserver) }
    }
}
