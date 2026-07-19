import AppKit

/// A value type that describes the current insertion point or selected range in a rich editor.
public struct FluentTextSelection: Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int = 0, length: Int = 0) {
        self.location = max(location, 0)
        self.length = max(length, 0)
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var nsRange: NSRange { NSRange(location: location, length: length) }
}

public struct FluentTextAttachment: Hashable, Sendable {
    public let id: String
    public var data: Data
    public var typeIdentifier: String
    public var filename: String?
    public var accessibilityLabel: String?

    public init(
        id: String = UUID().uuidString,
        data: Data,
        typeIdentifier: String,
        filename: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        precondition(!id.isEmpty, "Fluent text attachment IDs must not be empty")
        precondition(!typeIdentifier.isEmpty, "Fluent text attachment type identifiers must not be empty")
        self.id = id
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.filename = filename
        self.accessibilityLabel = accessibilityLabel
    }

    public init(
        id: String = UUID().uuidString,
        image: NSImage,
        filename: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            id: id,
            data: image.tiffRepresentation ?? Data(),
            typeIdentifier: "public.tiff",
            filename: filename,
            accessibilityLabel: accessibilityLabel
        )
    }
}

public struct FluentTextAttachmentOccurrence: Hashable, Sendable {
    public let attachment: FluentTextAttachment
    public let range: FluentTextSelection

    public init(attachment: FluentTextAttachment, range: FluentTextSelection) {
        self.attachment = attachment
        self.range = range
    }
}

public enum FluentTextFormatStatus: Hashable, Sendable {
    case off
    case on
    case mixed
}

public struct FluentTextFormattingState: Equatable {
    public let bold: FluentTextFormatStatus
    public let italic: FluentTextFormatStatus
    public let underline: FluentTextFormatStatus
    public let fontSize: CGFloat?
    public let textColor: NSColor?
    public let alignment: NSTextAlignment?

    public init(
        bold: FluentTextFormatStatus,
        italic: FluentTextFormatStatus,
        underline: FluentTextFormatStatus,
        fontSize: CGFloat?,
        textColor: NSColor?,
        alignment: NSTextAlignment?
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.fontSize = fontSize
        self.textColor = textColor
        self.alignment = alignment
    }
}

public enum FluentTextFormattingCommand {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case fontSize(CGFloat)
    case textColor(NSColor)
    case alignment(NSTextAlignment)
    case clearFormatting
}

public extension NSAttributedString.Key {
    static let fluentAttachmentID = NSAttributedString.Key("dev.fluentkit.text-attachment.id")
    static let fluentAttachmentLabel = NSAttributedString.Key("dev.fluentkit.text-attachment.accessibility-label")
}

private final class FluentRichTextPlaceholderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A native NSTextView-backed rich editor with attributed-text and selection bindings.
/// Formatting methods operate on the current selection and preserve AppKit text-system behavior.
public final class FluentRichTextEditor: NSView, FluentUpdatablePrimitiveView, NSTextViewDelegate {
    public var theme: FluentTheme = .current { didSet { applyTheme() } }

    public let textView: NSTextView
    public var binding: FluentBinding<NSAttributedString>
    public var selection: FluentBinding<FluentTextSelection>?
    public let placeholder: String
    public let minimumHeight: CGFloat
    public let maximumHeight: CGFloat?

    private let scrollView: NSScrollView
    private let placeholderLabel: FluentRichTextPlaceholderLabel
    private var bindingObserverID: UUID?
    private var selectionObserverID: UUID?
    private var isApplyingBinding = false
    private var isApplyingSelection = false

    public init(
        _ binding: FluentBinding<NSAttributedString>,
        selection: FluentBinding<FluentTextSelection>? = nil,
        placeholder: String = "",
        minimumHeight: CGFloat = 140,
        maximumHeight: CGFloat? = nil
    ) {
        self.binding = binding
        self.selection = selection
        self.placeholder = placeholder
        let resolvedMinimumHeight = max(minimumHeight, 32)
        self.minimumHeight = resolvedMinimumHeight
        self.maximumHeight = maximumHeight.map { max($0, resolvedMinimumHeight) }
        textView = NSTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        placeholderLabel = FluentRichTextPlaceholderLabel(labelWithString: placeholder)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityElement(false)
        configureTextView()
        configureScrollView()
        configurePlaceholder()
        installObservers()
        applyAttributedValue(binding.get())
        applySelectionValue(selection?.get())
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
        guard let editor = view as? FluentRichTextEditor else { return false }
        editor.theme = context.theme
        editor.applyDeclarativeConfiguration(from: self)
        return true
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: minimumHeight)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    /// Replaces the selected text with an attributed value and keeps the selection after it.
    public func replaceSelection(with value: NSAttributedString) {
        let range = clampedRange(textView.selectedRange())
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.setSelectedRange(NSRange(location: range.location + value.length, length: 0))
        commitTextAndSelection()
    }

    public func perform(_ command: FluentTextFormattingCommand) {
        switch command {
        case .toggleBold: toggleFontTrait(.boldFontMask)
        case .toggleItalic: toggleFontTrait(.italicFontMask)
        case .toggleUnderline: toggleUnderlineImplementation()
        case let .fontSize(size): setFontSizeImplementation(size)
        case let .textColor(color): setTextColorImplementation(color)
        case let .alignment(alignment): setAlignmentImplementation(alignment)
        case .clearFormatting: clearFormattingImplementation()
        }
    }

    public func toggleBold() { perform(.toggleBold) }
    public func toggleItalic() { perform(.toggleItalic) }
    public func toggleUnderline() {
        perform(.toggleUnderline)
    }

    public func setFontSize(_ size: CGFloat) { perform(.fontSize(size)) }
    public func setTextColor(_ color: NSColor) { perform(.textColor(color)) }
    public func setAlignment(_ alignment: NSTextAlignment) { perform(.alignment(alignment)) }
    public func clearFormatting() { perform(.clearFormatting) }

    public func insertAttachment(_ attachment: FluentTextAttachment) {
        let nativeAttachment = NSTextAttachment(data: attachment.data, ofType: attachment.typeIdentifier)
        nativeAttachment.fileWrapper?.preferredFilename = attachment.filename
        if let image = NSImage(data: attachment.data) {
            nativeAttachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        }
        let attributedAttachment = NSMutableAttributedString(attachment: nativeAttachment)
        let fullRange = NSRange(location: 0, length: attributedAttachment.length)
        attributedAttachment.addAttribute(.fluentAttachmentID, value: attachment.id, range: fullRange)
        if let accessibilityLabel = attachment.accessibilityLabel {
            attributedAttachment.addAttribute(.fluentAttachmentLabel, value: accessibilityLabel, range: fullRange)
        }
        replaceSelection(with: attributedAttachment)
    }

    public func attachments() -> [FluentTextAttachmentOccurrence] {
        let value = textView.attributedString()
        let fullRange = NSRange(location: 0, length: value.length)
        var result: [FluentTextAttachmentOccurrence] = []
        value.enumerateAttribute(.attachment, in: fullRange) { nativeValue, range, _ in
            guard let nativeAttachment = nativeValue as? NSTextAttachment else { return }
            let id = (value.attribute(.fluentAttachmentID, at: range.location, effectiveRange: nil) as? String)
                ?? "attachment-\(range.location)"
            let label = value.attribute(.fluentAttachmentLabel, at: range.location, effectiveRange: nil) as? String
            let data = nativeAttachment.contents ?? nativeAttachment.fileWrapper?.regularFileContents ?? Data()
            let typeIdentifier = nativeAttachment.fileType ?? "public.data"
            let attachment = FluentTextAttachment(
                id: id,
                data: data,
                typeIdentifier: typeIdentifier,
                filename: nativeAttachment.fileWrapper?.preferredFilename,
                accessibilityLabel: label
            )
            result.append(FluentTextAttachmentOccurrence(attachment: attachment, range: FluentTextSelection(range)))
        }
        return result
    }

    @discardableResult
    public func removeAttachment(id: String) -> Bool {
        let matches = attachments().filter { $0.attachment.id == id }
        guard !matches.isEmpty else { return false }
        for match in matches.reversed() {
            textView.textStorage?.deleteCharacters(in: match.range.nsRange)
        }
        let selection = clampedRange(textView.selectedRange())
        textView.setSelectedRange(selection)
        commitTextAndSelection()
        updatePlaceholderVisibility()
        return true
    }

    public var formattingState: FluentTextFormattingState {
        let range = clampedRange(textView.selectedRange())
        let attributes = attributesInSelection(range)
        return FluentTextFormattingState(
            bold: traitStatus(.boldFontMask, attributes: attributes),
            italic: traitStatus(.italicFontMask, attributes: attributes),
            underline: underlineStatus(attributes: attributes),
            fontSize: uniformValue(attributes.compactMap { ($0[.font] as? NSFont)?.pointSize }),
            textColor: uniformColor(attributes.compactMap { $0[.foregroundColor] as? NSColor }),
            alignment: uniformValue(attributes.map { paragraphAlignment(from: $0) })
        )
    }

    private func toggleUnderlineImplementation() {
        let range = clampedRange(textView.selectedRange())
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let current = (attributes[.underlineStyle] as? Int) ?? 0
            attributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes = attributes
        } else {
            let storage = textView.textStorage
            var hasUnderline = false
            storage?.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
                if (value as? Int ?? 0) != 0 { hasUnderline = true }
            }
            storage?.addAttribute(.underlineStyle, value: hasUnderline ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        }
        commitTextAndSelection()
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        let range = clampedRange(textView.selectedRange())
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = (attributes[.font] as? NSFont) ?? .systemFont(ofSize: 14)
            let hasTrait = NSFontManager.shared.traits(of: font).contains(trait)
            attributes[.font] = hasTrait
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            textView.typingAttributes = attributes
        } else {
            let storage = textView.textStorage
            storage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? .systemFont(ofSize: 14)
                let hasTrait = NSFontManager.shared.traits(of: font).contains(trait)
                let converted = hasTrait
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                    : NSFontManager.shared.convert(font, toHaveTrait: trait)
                storage?.addAttribute(.font, value: converted, range: subrange)
            }
        }
        commitTextAndSelection()
    }

    /// Applies a point size to the selection, or to future typing when there is no selection.
    private func setFontSizeImplementation(_ size: CGFloat) {
        let resolvedSize = max(size, 1)
        let range = clampedRange(textView.selectedRange())
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let currentFont = (attributes[.font] as? NSFont) ?? .systemFont(ofSize: resolvedSize)
            attributes[.font] = currentFont.withSize(resolvedSize)
            textView.typingAttributes = attributes
        } else {
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let currentFont = (value as? NSFont) ?? .systemFont(ofSize: resolvedSize)
                self.textView.textStorage?.addAttribute(.font, value: currentFont.withSize(resolvedSize), range: subrange)
            }
        }
        commitTextAndSelection()
    }

    private func setTextColorImplementation(_ color: NSColor) {
        let range = clampedRange(textView.selectedRange())
        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[.foregroundColor] = color
            textView.typingAttributes = attributes
        } else {
            textView.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
        }
        commitTextAndSelection()
    }

    private func setAlignmentImplementation(_ alignment: NSTextAlignment) {
        let range = clampedRange(textView.selectedRange())
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let paragraphStyle = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            attributes[.paragraphStyle] = paragraphStyle
            textView.typingAttributes = attributes
        } else {
            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            textView.textStorage?.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, subrange, _ in
                let paragraphStyle = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                paragraphStyle.alignment = alignment
                self.textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: subrange)
            }
        }
        commitTextAndSelection()
    }

    private func clearFormattingImplementation() {
        let range = clampedRange(textView.selectedRange())
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: theme.textPrimary
        ]
        if range.length == 0 {
            textView.typingAttributes = defaultAttributes
        } else {
            let keys: [NSAttributedString.Key] = [
                .font, .foregroundColor, .backgroundColor, .underlineStyle,
                .strikethroughStyle, .kern, .baselineOffset, .paragraphStyle
            ]
            for key in keys { textView.textStorage?.removeAttribute(key, range: range) }
            textView.textStorage?.addAttributes(defaultAttributes, range: range)
        }
        commitTextAndSelection()
    }

    private func attributesInSelection(_ range: NSRange) -> [[NSAttributedString.Key: Any]] {
        if range.length == 0 {
            return [textView.typingAttributes]
        }
        var result: [[NSAttributedString.Key: Any]] = []
        textView.textStorage?.enumerateAttributes(in: range) { attributes, _, _ in result.append(attributes) }
        return result.isEmpty ? [textView.typingAttributes] : result
    }

    private func traitStatus(
        _ trait: NSFontTraitMask,
        attributes: [[NSAttributedString.Key: Any]]
    ) -> FluentTextFormatStatus {
        let values = attributes.map { attributes in
            let font = (attributes[.font] as? NSFont) ?? .systemFont(ofSize: 14)
            return NSFontManager.shared.traits(of: font).contains(trait)
        }
        if values.allSatisfy({ $0 }) { return .on }
        if values.allSatisfy({ !$0 }) { return .off }
        return .mixed
    }

    private func underlineStatus(
        attributes: [[NSAttributedString.Key: Any]]
    ) -> FluentTextFormatStatus {
        let values = attributes.map { (($0[.underlineStyle] as? Int) ?? 0) != 0 }
        if values.allSatisfy({ $0 }) { return .on }
        if values.allSatisfy({ !$0 }) { return .off }
        return .mixed
    }

    private func paragraphAlignment(from attributes: [NSAttributedString.Key: Any]) -> NSTextAlignment {
        (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
    }

    private func uniformValue<Value: Equatable>(_ values: [Value]) -> Value? {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func uniformColor(_ colors: [NSColor]) -> NSColor? {
        guard let first = colors.first, colors.dropFirst().allSatisfy({ $0.isEqual(first) }) else { return nil }
        return first
    }

    /// Returns all matching ranges in document order, without changing the current selection.
    public func find(_ query: String, options: NSString.CompareOptions = [.caseInsensitive]) -> [FluentTextSelection] {
        guard !query.isEmpty else { return [] }
        let source = textView.string as NSString
        var matches: [FluentTextSelection] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let match = source.range(of: query, options: options, range: searchRange)
            guard match.location != NSNotFound else { break }
            matches.append(FluentTextSelection(match))
            let nextLocation = match.location + max(match.length, 1)
            guard nextLocation < source.length else { break }
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        return matches
    }

    /// Replaces every match and returns the number of replacements performed.
    @discardableResult
    public func replaceAll(_ query: String, with replacement: String, options: NSString.CompareOptions = [.caseInsensitive]) -> Int {
        let matches = find(query, options: options)
        guard !matches.isEmpty else { return 0 }
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedString())
        for match in matches.reversed() {
            let replacementAttributes: [NSAttributedString.Key: Any]
            if match.location < mutableText.length {
                replacementAttributes = mutableText.attributes(at: match.location, effectiveRange: nil)
            } else {
                replacementAttributes = textView.typingAttributes
            }
            mutableText.replaceCharacters(in: match.nsRange, with: NSAttributedString(string: replacement, attributes: replacementAttributes))
        }
        let oldSelection = clampedRange(textView.selectedRange())
        textView.textStorage?.setAttributedString(mutableText)
        textView.setSelectedRange(NSRange(location: min(oldSelection.location, mutableText.length), length: 0))
        commitTextAndSelection()
        return matches.count
    }

    public func textDidChange(_ notification: Notification) {
        guard !isApplyingBinding else { return }
        commitTextAndSelection()
        updatePlaceholderVisibility()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        selection?.set(FluentTextSelection(textView.selectedRange()))
    }

    private func configureTextView() {
        textView.delegate = self
        textView.isRichText = true
        textView.importsGraphics = true
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
        textView.setAccessibilityLabel(placeholder.isEmpty ? "Rich text editor" : placeholder)
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

    private func installObservers() {
        bindingObserverID = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.textView.attributedString() != value else { return }
                guard self.textView.window?.firstResponder !== self.textView else { return }
                self.applyAttributedValue(value)
            }
        }
        selectionObserverID = selection?.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in self?.applySelectionValue(value) }
        }
    }

    private func applyAttributedValue(_ value: NSAttributedString) {
        isApplyingBinding = true
        textView.textStorage?.setAttributedString(value)
        isApplyingBinding = false
        updatePlaceholderVisibility()
    }

    private func applySelectionValue(_ value: FluentTextSelection?) {
        guard let value else { return }
        isApplyingSelection = true
        textView.setSelectedRange(clampedRange(value.nsRange))
        isApplyingSelection = false
    }

    private func commitTextAndSelection() {
        binding.set(textView.attributedString())
        selection?.set(FluentTextSelection(textView.selectedRange()))
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = textView.string.isEmpty == false
        setAccessibilityValue(textView.string)
    }

    private func clampedRange(_ range: NSRange) -> NSRange {
        let length = textView.string.utf16.count
        let location = min(max(range.location, 0), length)
        let maxLength = max(length - location, 0)
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
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

    private func applyDeclarativeConfiguration(from source: FluentRichTextEditor) {
        if let bindingObserverID { binding.removeObserver?(bindingObserverID) }
        if let selectionObserverID { selection?.removeObserver?(selectionObserverID) }
        binding = source.binding
        selection = source.selection
        installObservers()
        if textView.window?.firstResponder !== textView, textView.attributedString() != binding.get() {
            applyAttributedValue(binding.get())
        }
        applySelectionValue(selection?.get())
        updatePlaceholderVisibility()
        applyTheme()
    }

    deinit {
        if let bindingObserverID { binding.removeObserver?(bindingObserverID) }
        if let selectionObserverID { selection?.removeObserver?(selectionObserverID) }
    }
}
