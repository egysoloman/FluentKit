import AppKit

@MainActor
protocol FluentSingleLineTextControl: AnyObject {
    func didConfigureFluentFieldEditor()
}

@MainActor
protocol FluentTextMutationObserving: AnyObject {
    func willApplyFluentTextChange(in editor: NSTextView, range: NSRange, replacement: String)
}

@inline(__always)
func configureFluentSingleLineTextControl(_ control: NSTextField) {
    // NSCell's single-line mode also imposes a fixed baseline that ignores custom font
    // metrics. These controls enforce single-line input through their editing session;
    // other native controls retain AppKit's own policy.
    control.usesSingleLineMode = !(control is any FluentSingleLineTextControl)
    control.maximumNumberOfLines = 1
    guard let cell = control.cell else { return }
    cell.wraps = false
    cell.isScrollable = true
    cell.lineBreakMode = .byClipping
}

/// Preserves AppKit's field editor and its control delegate while separating input policy
/// from NSCell's fixed-baseline rendering. Other validation and editing callbacks still
/// reach the native delegate, including formatters and the control's application delegate.
final class FluentSingleLineEditorDelegate: NSObject, NSTextViewDelegate {
    private weak var editor: NSTextView?
    private weak var originalDelegate: (any NSTextViewDelegate)?
    private(set) weak var owner: NSTextField?
    private var pendingMarkedReplacement: (range: NSRange, value: String)?
    private var isNormalizingComposition = false

    func install(on editor: NSTextView, owner: NSTextField) {
        guard editor.delegate !== self else { return }
        // AppKit restores the control during setup. Respect a later client delegate;
        // wrapping a client that already forwards to us would create a delegate cycle.
        guard editor.delegate === owner else { return }
        detach()
        self.editor = editor
        self.owner = owner
        originalDelegate = editor.delegate
        editor.delegate = self
    }

    func detach() {
        if let editor, editor.delegate === self { editor.delegate = originalDelegate }
        editor = nil
        originalDelegate = nil
        owner = nil
        pendingMarkedReplacement = nil
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        originalDelegate
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                  replacementString value: String?) -> Bool {
        if textView.hasMarkedText() {
            let accepted = originalDelegate?.textView?(textView, shouldChangeTextIn: range,
                                                       replacementString: value) ?? true
            if accepted, let value {
                pendingMarkedReplacement = value.rangeOfCharacter(from: .newlines) == nil ? nil
                    : (NSRange(location: range.location, length: value.utf16.count), value)
                (owner as? any FluentTextMutationObserving)?.willApplyFluentTextChange(in: textView, range: range, replacement: value)
            }
            return accepted
        }
        if let value, value.rangeOfCharacter(from: .newlines) != nil,
           textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true {
            // AppKit replaces each separator, including both scalars of CRLF, with a
            // space. Reenter native insertion so validation, selection and undo apply
            // to the normalized replacement rather than repairing the storage later.
            textView.insertText(value.components(separatedBy: .newlines).joined(separator: " "),
                                replacementRange: range)
            return false
        }
        let accepted = originalDelegate?.textView?(textView, shouldChangeTextIn: range, replacementString: value) ?? true
        if accepted, let value {
            (owner as? any FluentTextMutationObserving)?.willApplyFluentTextChange(in: textView, range: range, replacement: value)
        }
        return accepted
    }

    func textDidChange(_ notification: Notification) {
        guard !isNormalizingComposition else { return }
        if let textView = notification.object as? NSTextView { normalizeCommittedComposition(in: textView) }
        originalDelegate?.textDidChange?(notification)
    }

    private func normalizeCommittedComposition(in textView: NSTextView) {
        guard !textView.hasMarkedText(), let pending = pendingMarkedReplacement else { return }
        pendingMarkedReplacement = nil
        // AppKit keeps separators inside provisional marked text and filters them only
        // when it commits. Some commits finish in place, without another shouldChange
        // callback after unmarking. Finish that same native edit transaction here.
        guard editor === textView, owner?.currentEditor() === textView,
              textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true,
              NSMaxRange(pending.range) <= (textView.string as NSString).length,
              (textView.string as NSString).substring(with: pending.range) == pending.value else { return }
        let selection = textView.selectedRange()
        isNormalizingComposition = true
        defer { isNormalizingComposition = false }
        textView.insertText(pending.value.components(separatedBy: .newlines).joined(separator: " "),
                            replacementRange: pending.range)
        if editor === textView, owner?.currentEditor() === textView,
           NSMaxRange(selection) <= (textView.string as NSString).length {
            textView.setSelectedRange(selection)
        }
    }

    func textView(_ textView: NSTextView, doCommandBy command: Selector) -> Bool {
        switch NSStringFromSelector(command) {
        case "insertNewlineIgnoringFieldEditor:", "insertLineBreak:",
             "insertParagraphSeparator:", "insertContainerBreak:":
            return true
        default:
            // Return, Tab, Escape, navigation and editing commands retain native dispatch.
            return originalDelegate?.textView?(textView, doCommandBy: command) ?? false
        }
    }
}

/// The shared editor can have a forwarding delegate rather than the control itself.
func fluentFieldEditorOwner(_ editor: NSTextView) -> NSView? {
    (editor.delegate as? FluentSingleLineEditorDelegate)?.owner ?? editor.delegate as? NSView
}

/// AppKit updates an active editor's font but can keep its old vertical text metrics.
/// Reposition the existing viewport instead of ending/restarting composition.
func synchronizeFluentSingleLineEditorGeometry(_ control: NSTextField, recheckAfterLayout: Bool = true) {
    guard control is any FluentSingleLineTextControl,
          let editor = control.currentEditor() as? NSTextView,
          fluentFieldEditorOwner(editor) === control,
          let clip = editor.superview as? NSClipView,
          clip.documentView === editor, clip.isDescendant(of: control),
          let parent = clip.superview, let cell = control.cell else { return }
    let textRect = (cell as? NSSearchFieldCell)?.searchTextRect(forBounds: control.bounds)
        ?? cell.titleRect(forBounds: control.bounds)
    let heightChanged = editor.frame.height != textRect.height
    if heightChanged { editor.setFrameSize(NSSize(width: editor.frame.width, height: textRect.height)) }
    let target = control.convert(textRect, to: parent)
    let actual = editor.convert(editor.bounds, to: parent)
    let offset = target.minY - actual.minY
    guard heightChanged || abs(offset) > 0.001 else { return }
    // Keep the native clip's padding and horizontal scrolling. Moving the document's
    // origin makes NSClipView scroll along with it, so translate only the viewport.
    if abs(offset) > 0.001 { clip.setFrameOrigin(NSPoint(x: clip.frame.minX, y: clip.frame.minY + offset)) }
    editor.needsDisplay = true
    if recheckAfterLayout {
        DispatchQueue.main.async { [weak control, weak editor] in
            guard let control, let editor, control.currentEditor() === editor else { return }
            synchronizeFluentSingleLineEditorGeometry(control, recheckAfterLayout: false)
        }
    }
}

/// Bridges AppKit's native field editor to WinUI TextControl visuals and command availability.
/// The field editor continues to own IME, undo, selection, accessibility, and clipboard execution.
final class FluentTextEditingSession {
    weak var control: NSTextField?
    var theme: FluentTheme {
        didSet {
            guard oldValue != theme else { return }
            configureEditor()
            // Plain AppKit windows may update controls directly without an appearance
            // coordinator. Keep the already-open editor menu on the same theme too.
            flyout?.apply(theme: theme)
        }
    }
    let isSecure: Bool

    private weak var editor: NSTextView?
    private var singleLineDelegate: FluentSingleLineEditorDelegate?
    private var flyout: FluentTextCommandFlyout?
    private var rightClickMonitor: Any?
    static private(set) var activeRightClickMonitorCount = 0
    private var editorConfigurationScheduled = false

    init(control: NSTextField, theme: FluentTheme, isSecure: Bool) {
        self.control = control
        self.theme = theme
        self.isSecure = isSecure
    }

    func didBeginEditing() {
        installRightClickMonitor()
        editor = control?.currentEditor() as? NSTextView
        configureEditor()
        // AppKit reapplies its field-editor defaults after the control begins editing. Reassert
        // the TextControl attributes once that setup transaction has completed.
        guard !editorConfigurationScheduled else { return }
        editorConfigurationScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.editorConfigurationScheduled = false
            self?.configureEditor()
        }
    }

    func didEndEditing() {
        removeRightClickMonitor()
        guard flyout?.isPresented != true else { return }
        singleLineDelegate?.detach()
        editor = nil
    }

    @discardableResult
    func presentContextCommands(for event: NSEvent) -> Bool {
        guard let control, control.isEnabled, control.isEditable, let window = control.window else {
            return false
        }
        if control.currentEditor() == nil {
            // `makeFirstResponder(_:)` can leave an NSTextField itself as first responder without
            // installing the window-owned field editor. That is especially common for an empty,
            // previously untouched field, and used to make its context flyout silently fail.
            // `selectText(_:)` follows AppKit's real text-entry path and creates the editor while
            // preserving the WinUI behavior that a context invocation also focuses TextBox.
            control.selectText(nil)
            if control.currentEditor() == nil {
                _ = window.makeFirstResponder(control)
                control.selectText(nil)
            }
        }
        editor = control.currentEditor() as? NSTextView
        guard editor != nil else { return false }
        configureEditor()

        if flyout?.isPresented == true {
            flyout?.dismiss(animated: false)
            flyout = nil
            return true
        }

        // `FlyoutBase::OnOpening`: touch and pen set InputDevicePrefersPrimaryCommands and get the
        // compact icon-first command bar; mouse and keyboard use the secondary row presenter.
        let prefersPrimary = Self.prefersPrimaryCommands(for: event, in: window)
        let commands = textCommands(prefersPrimaryCommands: prefersPrimary)
        guard !commands.isEmpty else { return true }
        let presented = FluentTextCommandFlyout(
            commands: commands,
            theme: theme,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            refreshCommands: { [weak self] in
                self?.textCommands(prefersPrimaryCommands: prefersPrimary) ?? []
            }
        )
        flyout = presented
        presented.onDismiss = { [weak self, weak presented] in
            guard let self, self.flyout === presented else { return }
            self.flyout = nil
            guard let control = self.control, let window = control.window else { return }
            // Dismissing a transient editor menu must not resurrect a parent window that was
            // closed or hidden while the 83ms fade-out was running.
            guard window.isVisible, window.isKeyWindow else { return }
            _ = window.makeFirstResponder(control)
            self.didBeginEditing()
        }
        let point = control.convert(event.locationInWindow, from: nil)
        presented.present(relativeTo: control, at: point)
        return true
    }

    private func configureEditor() {
        // Deferred setup must not reclaim a shared editor that has moved to another control.
        guard let control, let editor = control.currentEditor() as? NSTextView else { return }
        self.editor = editor
        if singleLineDelegate == nil { singleLineDelegate = FluentSingleLineEditorDelegate() }
        singleLineDelegate?.install(on: editor, owner: control)
        let preservedSelection = editor.selectedRange()
        // The window-owned field editor becomes first responder in place of FluentTextField.
        // Its default focus ring can otherwise leak through after content is remounted into a
        // detached tab window, drawing AppKit's blue rectangle over Fluent's bottom accent.
        if editor.focusRingType != .none { editor.focusRingType = .none }
        if editor.isVerticallyResizable { editor.isVerticallyResizable = false }
        if !editor.isHorizontallyResizable { editor.isHorizontallyResizable = true }
        // NSSearchFieldCell paints glyphs two points inside searchTextRect. Its shared field
        // editor can retain a different inset from the previous control, and AppKit may reset
        // it after cell setup. Reassert the matching inset here, including the deferred setup
        // pass, so focus/IME caret geometry stays aligned with the inactive cell's actual ink.
        configureFluentSingleLineFieldEditor(
            editor, lineFragmentPadding: control is FluentSearchTextField ? 2 : 0
        )
        if let textContainer = editor.textContainer {
            if textContainer.maximumNumberOfLines != 1 { textContainer.maximumNumberOfLines = 1 }
            if textContainer.lineBreakMode != .byClipping { textContainer.lineBreakMode = .byClipping }
            if textContainer.widthTracksTextView { textContainer.widthTracksTextView = false }
            if !textContainer.heightTracksTextView { textContainer.heightTracksTextView = true }
        }
        if editor.drawsBackground { editor.drawsBackground = false }
        if !editor.backgroundColor.isEqual(NSColor.clear) { editor.backgroundColor = .clear }
        if editor.textColor?.isEqual(theme.textPrimary) != true { editor.textColor = theme.textPrimary }
        if !editor.insertionPointColor.isEqual(theme.textCaret) {
            editor.insertionPointColor = theme.textCaret
        }
        let selectedAttributes = editor.selectedTextAttributes
        let selectedBackground = selectedAttributes[.backgroundColor] as? NSColor
        let selectedForeground = selectedAttributes[.foregroundColor] as? NSColor
        if selectedBackground?.isEqual(theme.textSelectionBackground) != true
            || selectedForeground?.isEqual(theme.textSelectionForeground) != true {
            editor.selectedTextAttributes = [
                .backgroundColor: theme.textSelectionBackground,
                .foregroundColor: theme.textSelectionForeground
            ]
        }
        var typingAttributes = editor.typingAttributes
        let currentTypingColor = typingAttributes[.foregroundColor] as? NSColor
        let currentTypingFont = typingAttributes[.font] as? NSFont
        let targetFont = control.font
        if currentTypingColor?.isEqual(theme.textPrimary) != true
            || targetFont.map({ currentTypingFont != $0 }) == true {
            typingAttributes[.foregroundColor] = theme.textPrimary
            if let targetFont { typingAttributes[.font] = targetFont }
            editor.typingAttributes = typingAttributes
        }
        let textLength = editor.string.utf16.count
        if NSMaxRange(preservedSelection) <= textLength,
           editor.selectedRange() != preservedSelection {
            editor.setSelectedRange(preservedSelection)
        }
        synchronizeFluentSingleLineEditorGeometry(control)
    }

    /// Classifies the opening event and records it, falling back to the window's last device.
    static func prefersPrimaryCommands(for event: NSEvent, in window: NSWindow?) -> Bool {
        let device = FluentInputDeviceTracker.deviceType(for: event)
            ?? FluentInputDeviceTracker.shared.lastDeviceType(in: window)
        FluentInputDeviceTracker.shared.record(device, in: window)
        return device.prefersPrimaryCommands
    }

    private func textCommands(prefersPrimaryCommands: Bool) -> [FluentTextCommand] {
        guard let control, let editor, control.currentEditor() === editor else { return [] }
        let hasSelection = editor.selectedRange().length > 0
        let hasText = !editor.string.isEmpty
        let editable = control.isEnabled && control.isEditable && editor.isEditable
        let canPaste = editable && NSPasteboard.general.availableType(from: [.string, .rtf, .rtfd]) != nil
        var commands: [FluentTextCommand] = []

        if !isSecure, editable, hasSelection {
            commands.append(FluentTextCommand(
                kind: .cut,
                title: control.fluentControlString("Cut"),
                accelerator: "\u{2318}X",
                systemImageName: "scissors",
                action: { [weak editor] in editor?.cut(nil) },
                isPrimary: prefersPrimaryCommands
            ))
        }
        if !isSecure, hasSelection {
            commands.append(FluentTextCommand(
                kind: .copy,
                title: control.fluentControlString("Copy"),
                accelerator: "\u{2318}C",
                systemImageName: "doc.on.doc",
                action: { [weak editor] in editor?.copy(nil) },
                isPrimary: prefersPrimaryCommands
            ))
        }
        if canPaste {
            commands.append(FluentTextCommand(
                kind: .paste,
                title: control.fluentControlString("Paste"),
                accelerator: "\u{2318}V",
                systemImageName: "doc.on.clipboard",
                action: { [weak editor] in editor?.paste(nil) },
                isPrimary: prefersPrimaryCommands
            ))
        }
        if !isSecure, editable, editor.undoManager?.canUndo == true {
            commands.append(FluentTextCommand(
                kind: .undo,
                title: control.fluentControlString("Undo"),
                accelerator: "\u{2318}Z",
                systemImageName: "arrow.uturn.backward",
                action: { [weak editor] in editor?.undoManager?.undo() },
                isPrimary: false
            ))
        }
        if !isSecure, editable, editor.undoManager?.canRedo == true {
            commands.append(FluentTextCommand(
                kind: .redo,
                title: control.fluentControlString("Redo"),
                accelerator: "\u{21E7}\u{2318}Z",
                systemImageName: "arrow.uturn.forward",
                action: { [weak editor] in editor?.undoManager?.redo() },
                isPrimary: false
            ))
        }
        // Keep a secondary command row even when the field and pasteboard are empty. This gives
        // an empty TextBox the same right-click target as a populated one; the unavailable action
        // remains visible but disabled instead of making the entire flyout disappear.
        commands.append(FluentTextCommand(
            kind: .selectAll,
            title: control.fluentControlString("Select All"),
            accelerator: "\u{2318}A",
            systemImageName: nil,
            action: { [weak editor] in editor?.selectAll(nil) },
            isPrimary: false,
            isEnabled: hasText
        ))
        return commands
    }

    private func installRightClickMonitor() {
        guard rightClickMonitor == nil, control?.window != nil else { return }
        Self.activeRightClickMonitorCount += 1
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  let control = self.control,
                  event.window === control.window,
                  control.bounds.contains(control.convert(event.locationInWindow, from: nil)) else {
                return event
            }
            return self.presentContextCommands(for: event) ? nil : event
        }
    }

    private func removeRightClickMonitor() {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
            Self.activeRightClickMonitorCount -= 1
        }
    }

    deinit {
        removeRightClickMonitor()
        singleLineDelegate?.detach()
        flyout?.dismiss(animated: false)
    }
}
