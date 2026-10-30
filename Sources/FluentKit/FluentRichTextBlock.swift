import AppKit

/// A read-only WinUI RichTextBlock backed by the AppKit text system.
///
/// Unlike FluentTextView, this presenter keeps paragraph formatting and embedded links intact.
/// The native text view never enters the responder chain, so its content remains inert except for
/// the optional selection and automatic URL activation callbacks.
public struct FluentRichTextBlock: FluentUpdatablePrimitiveView {
    private let attributedText: NSAttributedString
    private let wrapsText: Bool
    private let maximumLines: Int
    private let isTextSelectionEnabled: Bool
    private let automaticallyDetectsLinks: Bool
    private let onLinkActivated: ((URL) -> Void)?

    public init(
        _ attributedText: NSAttributedString,
        wrapsText: Bool = true,
        maximumLines: Int = 0,
        isTextSelectionEnabled: Bool = false,
        automaticallyDetectsLinks: Bool = true,
        onLinkActivated: ((URL) -> Void)? = nil
    ) {
        self.attributedText = attributedText
        self.wrapsText = wrapsText
        self.maximumLines = max(maximumLines, 0)
        self.isTextSelectionEnabled = isTextSelectionEnabled
        self.automaticallyDetectsLinks = automaticallyDetectsLinks
        self.onLinkActivated = onLinkActivated
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentRichTextBlockView(
            attributedText: attributedText,
            wrapsText: wrapsText,
            maximumLines: maximumLines,
            isTextSelectionEnabled: isTextSelectionEnabled,
            automaticallyDetectsLinks: automaticallyDetectsLinks,
            onLinkActivated: onLinkActivated,
            theme: context.theme
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentRichTextBlockView else { return false }
        host.update(
            attributedText: attributedText,
            wrapsText: wrapsText,
            maximumLines: maximumLines,
            isTextSelectionEnabled: isTextSelectionEnabled,
            automaticallyDetectsLinks: automaticallyDetectsLinks,
            onLinkActivated: onLinkActivated,
            theme: context.theme
        )
        return true
    }
}

private final class FluentRichTextBlockDelegate: NSObject, NSTextViewDelegate {
    var onLinkActivated: ((URL) -> Void)?

    init(onLinkActivated: ((URL) -> Void)?) {
        self.onLinkActivated = onLinkActivated
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            onLinkActivated?(url)
            return true
        }
        if let string = link as? String, let url = URL(string: string) {
            onLinkActivated?(url)
            return true
        }
        return false
    }
}

/// Native RichTextBlock presenter. It keeps AppKit's layout, wrapping, and link handling while
/// remaining read-only and chrome-free.
public final class FluentRichTextBlockView: NSTextView, FluentUpdatablePrimitiveView {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            applyTheme()
        }
    }

    private var richDelegate: FluentRichTextBlockDelegate
    private var currentAttributedText: NSAttributedString
    private var wrapsText = true
    private var maximumLines = 0
    private var isTextSelectionEnabled = false
    private var automaticallyDetectsLinks = true
    private var onLinkActivated: ((URL) -> Void)?

    public init(
        attributedText: NSAttributedString,
        wrapsText: Bool = true,
        maximumLines: Int = 0,
        isTextSelectionEnabled: Bool = false,
        automaticallyDetectsLinks: Bool = true,
        onLinkActivated: ((URL) -> Void)? = nil,
        theme: FluentTheme = .current
    ) {
        currentAttributedText = attributedText
        richDelegate = FluentRichTextBlockDelegate(onLinkActivated: onLinkActivated)
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: .zero)
        layoutManager.addTextContainer(textContainer)
        super.init(frame: .zero, textContainer: textContainer)
        self.theme = theme
        identifier = NSUserInterfaceItemIdentifier("FluentKit.RichTextBlock")
        configureTextSystem(
            wrapsText: wrapsText,
            maximumLines: maximumLines,
            isTextSelectionEnabled: isTextSelectionEnabled,
            automaticallyDetectsLinks: automaticallyDetectsLinks,
            onLinkActivated: onLinkActivated
        )
        applyAttributedText(attributedText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        theme = context.theme
        return self
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentRichTextBlockView else { return false }
        host.theme = context.theme
        return true
    }

    public override var intrinsicContentSize: NSSize {
        let bounds = currentAttributedText.boundingRect(
            with: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(
            width: 320,
            height: max(ceil(bounds.height) + 2, 20)
        )
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    func update(
        attributedText: NSAttributedString,
        wrapsText: Bool,
        maximumLines: Int,
        isTextSelectionEnabled: Bool,
        automaticallyDetectsLinks: Bool,
        onLinkActivated: ((URL) -> Void)?,
        theme: FluentTheme
    ) {
        self.theme = theme
        if !currentAttributedText.isEqual(to: attributedText) {
            currentAttributedText = attributedText
            applyAttributedText(attributedText)
        }
        configureTextSystem(
            wrapsText: wrapsText,
            maximumLines: maximumLines,
            isTextSelectionEnabled: isTextSelectionEnabled,
            automaticallyDetectsLinks: automaticallyDetectsLinks,
            onLinkActivated: onLinkActivated
        )
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func configureTextSystem(
        wrapsText: Bool,
        maximumLines: Int,
        isTextSelectionEnabled: Bool,
        automaticallyDetectsLinks: Bool,
        onLinkActivated: ((URL) -> Void)?
    ) {
        self.wrapsText = wrapsText
        self.maximumLines = max(maximumLines, 0)
        self.isTextSelectionEnabled = isTextSelectionEnabled
        self.automaticallyDetectsLinks = automaticallyDetectsLinks
        self.onLinkActivated = onLinkActivated
        isEditable = false
        isSelectable = isTextSelectionEnabled
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        usesFindPanel = false
        allowsUndo = false
        drawsBackground = false
        focusRingType = .none
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = automaticallyDetectsLinks
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = wrapsText
        textContainer?.heightTracksTextView = true
        textContainer?.maximumNumberOfLines = self.maximumLines
        isHorizontallyResizable = !wrapsText
        isVerticallyResizable = false
        setSelectedRange(NSRange(location: 0, length: 0))
        richDelegate.onLinkActivated = onLinkActivated
        delegate = richDelegate
        applyTheme()
    }

    private func applyAttributedText(_ value: NSAttributedString) {
        let resolved = NSMutableAttributedString(attributedString: value)
        let fullRange = NSRange(location: 0, length: resolved.length)
        resolved.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            if attributes[.font] == nil {
                resolved.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: range)
            }
        }
        textStorage?.setAttributedString(resolved)
        textContainer?.maximumNumberOfLines = maximumLines
        needsDisplay = true
    }

    private func applyTheme() {
        textColor = theme.textPrimary
        linkTextAttributes = [
            .foregroundColor: theme.accentTextPrimary,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        insertionPointColor = theme.textCaret
        needsDisplay = true
    }

}
