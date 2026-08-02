import AppKit

private final class FluentTextEditorPlaceholderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A native multiline editor backed by NSTextView and synchronized with a Fluent binding.
/// The editor keeps AppKit's text system intact while providing Fluent theme, placeholder,
/// sizing, and accessibility behavior.
public final class FluentTextEditor: NSView, FluentUpdatablePrimitiveView, NSTextViewDelegate {
    public var theme: FluentTheme = .current {
        didSet { applyTheme() }
    }

    public let textView: NSTextView
    public var binding: FluentBinding<String>
    public let placeholder: String
    public let minimumHeight: CGFloat
    public let maximumHeight: CGFloat?

    private let scrollView: NSScrollView
    private let placeholderLabel: FluentTextEditorPlaceholderLabel
    private var observerID: UUID?
    private var isApplyingBinding = false

    public init(
        _ binding: FluentBinding<String>,
        placeholder: String = "",
        minimumHeight: CGFloat = 120,
        maximumHeight: CGFloat? = nil
    ) {
        self.binding = binding
        self.placeholder = placeholder
        let resolvedMinimumHeight = max(minimumHeight, 32)
        self.minimumHeight = resolvedMinimumHeight
        self.maximumHeight = maximumHeight.map { max($0, resolvedMinimumHeight) }
        textView = NSTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        placeholderLabel = FluentTextEditorPlaceholderLabel(labelWithString: placeholder)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityElement(false)

        configureTextView()
        configureScrollView()
        configurePlaceholder()
        installBindingObserver()
        textView.string = binding.get()
        updatePlaceholderVisibility()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let editor = view as? FluentTextEditor else { return false }
        editor.theme = context.theme
        editor.applyDeclarativeConfiguration(from: self)
        return true
    }

    /// Explicitly commits the current native text to the binding. Text changes already commit
    /// through textDidChange, but this is useful for integrations that edit textView directly.
    public func commitText() {
        binding.set(textView.string)
    }

    public func textDidChange(_ notification: Notification) {
        guard !isApplyingBinding else { return }
        binding.set(textView.string)
        updatePlaceholderVisibility()
    }

    public func textDidBeginEditing(_ notification: Notification) { applyTheme() }
    public func textDidEndEditing(_ notification: Notification) { applyTheme() }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: minimumHeight)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    private func configureTextView() {
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = theme.textPrimary
        textView.insertionPointColor = theme.accent
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.setAccessibilityElement(true)
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityLabel(placeholder.isEmpty ? "Text editor" : placeholder)
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight)
        ])
        if let maximumHeight {
            heightAnchor.constraint(lessThanOrEqualToConstant: maximumHeight).isActive = true
        }
    }

    private func configurePlaceholder() {
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.backgroundColor = .clear
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
    }

    private func installBindingObserver() {
        observerID = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.textView.string != value else { return }
                guard self.textView.window?.firstResponder !== self.textView else { return }
                self.isApplyingBinding = true
                self.textView.string = value
                self.isApplyingBinding = false
                self.updatePlaceholderVisibility()
            }
        }
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty
        setAccessibilityValue(textView.string)
    }

    private func applyTheme() {
        textView.textColor = theme.textPrimary
        textView.insertionPointColor = theme.accent
        placeholderLabel.textColor = theme.textSecondary
        layer?.backgroundColor = theme.controlFill.cgColor
        layer?.cornerRadius = theme.buttonCornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = (textView.window?.firstResponder === textView ? theme.controlStrokeStrong : theme.controlStroke).cgColor
        layer?.masksToBounds = true
        needsDisplay = true
    }

    private func applyDeclarativeConfiguration(from source: FluentTextEditor) {
        if let observerID { binding.removeObserver?(observerID) }
        binding = source.binding
        installBindingObserver()
        if textView.window?.firstResponder !== textView, textView.string != binding.get() {
            isApplyingBinding = true
            textView.string = binding.get()
            isApplyingBinding = false
        }
        updatePlaceholderVisibility()
        applyTheme()
    }

    deinit {
        if let observerID { binding.removeObserver?(observerID) }
    }
}
