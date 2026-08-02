import AppKit

@inline(__always)
func configureFluentSingleLineTextControl(_ control: NSTextField) {
    control.usesSingleLineMode = true
    control.maximumNumberOfLines = 1
    guard let cell = control.cell else { return }
    cell.wraps = false
    cell.isScrollable = true
    cell.lineBreakMode = .byClipping
}

/// Bridges AppKit's native field editor to WinUI TextControl visuals and command availability.
/// The field editor continues to own IME, undo, selection, accessibility, and clipboard execution.
final class FluentTextEditingSession {
    weak var control: NSTextField?
    var theme: FluentTheme {
        didSet {
            guard oldValue != theme else { return }
            configureEditor()
        }
    }
    let isSecure: Bool

    private weak var editor: NSTextView?
    private var flyout: FluentTextCommandFlyout?
    private var rightClickMonitor: Any?
    private var editorConfigurationScheduled = false

    init(control: NSTextField, theme: FluentTheme, isSecure: Bool) {
        self.control = control
        self.theme = theme
        self.isSecure = isSecure
        installRightClickMonitor()
    }

    func didBeginEditing() {
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
        guard flyout?.isPresented != true else { return }
        editor = nil
    }

    @discardableResult
    func presentContextCommands(for event: NSEvent) -> Bool {
        guard let control, control.isEnabled, control.isEditable, let window = control.window else {
            return false
        }
        if control.currentEditor() == nil {
            _ = window.makeFirstResponder(control)
        }
        editor = control.currentEditor() as? NSTextView
        guard editor != nil else { return false }
        configureEditor()

        if flyout?.isPresented == true {
            flyout?.dismiss(animated: false)
            flyout = nil
            return true
        }

        // WinUI routes mouse context commands through the secondary row presenter. The compact
        // icon-first command bar is reserved for input devices that prefer primary commands.
        let commands = textCommands(prefersPrimaryCommands: event.type != .rightMouseDown)
        guard !commands.isEmpty else { return true }
        let presented = FluentTextCommandFlyout(
            commands: commands,
            theme: theme,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        flyout = presented
        presented.onDismiss = { [weak self, weak presented] in
            guard let self, self.flyout === presented else { return }
            self.flyout = nil
            guard let control = self.control, let window = control.window else { return }
            window.makeKeyAndOrderFront(nil)
            _ = window.makeFirstResponder(control)
            self.didBeginEditing()
        }
        let point = control.convert(event.locationInWindow, from: nil)
        presented.present(relativeTo: control, at: point)
        return true
    }

    private func configureEditor() {
        guard let editor = editor ?? control?.currentEditor() as? NSTextView else { return }
        self.editor = editor
        let preservedSelection = editor.selectedRange()
        if editor.isVerticallyResizable { editor.isVerticallyResizable = false }
        if !editor.isHorizontallyResizable { editor.isHorizontallyResizable = true }
        configureFluentSingleLineFieldEditor(editor)
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
        let targetFont = control?.font
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
    }

    private func textCommands(prefersPrimaryCommands: Bool) -> [FluentTextCommand] {
        guard let control, let editor else { return [] }
        let hasSelection = editor.selectedRange().length > 0
        let hasText = !control.stringValue.isEmpty
        let editable = control.isEnabled && control.isEditable && editor.isEditable
        let canPaste = editable && NSPasteboard.general.availableType(from: [.string, .rtf, .rtfd]) != nil
        var commands: [FluentTextCommand] = []

        if !isSecure, editable, hasSelection {
            commands.append(FluentTextCommand(
                kind: .cut,
                title: "Cut",
                accelerator: "\u{2318}X",
                systemImageName: "scissors",
                action: { [weak editor] in editor?.cut(nil) },
                isPrimary: prefersPrimaryCommands
            ))
        }
        if !isSecure, hasSelection {
            commands.append(FluentTextCommand(
                kind: .copy,
                title: "Copy",
                accelerator: "\u{2318}C",
                systemImageName: "doc.on.doc",
                action: { [weak editor] in editor?.copy(nil) },
                isPrimary: prefersPrimaryCommands
            ))
        }
        if canPaste {
            commands.append(FluentTextCommand(
                kind: .paste,
                title: "Paste",
                accelerator: "\u{2318}V",
                systemImageName: "doc.on.clipboard",
                action: { [weak editor] in editor?.paste(nil) },
                isPrimary: prefersPrimaryCommands
            ))
        }
        if !isSecure, editable, editor.undoManager?.canUndo == true {
            commands.append(FluentTextCommand(
                kind: .undo,
                title: "Undo",
                accelerator: "\u{2318}Z",
                systemImageName: "arrow.uturn.backward",
                action: { [weak editor] in editor?.undoManager?.undo() },
                isPrimary: false
            ))
        }
        if !isSecure, editable, editor.undoManager?.canRedo == true {
            commands.append(FluentTextCommand(
                kind: .redo,
                title: "Redo",
                accelerator: "\u{21E7}\u{2318}Z",
                systemImageName: "arrow.uturn.forward",
                action: { [weak editor] in editor?.undoManager?.redo() },
                isPrimary: false
            ))
        }
        if hasText {
            commands.append(FluentTextCommand(
                kind: .selectAll,
                title: "Select All",
                accelerator: "\u{2318}A",
                systemImageName: nil,
                action: { [weak editor] in editor?.selectAll(nil) },
                isPrimary: false
            ))
        }
        return commands
    }

    private func installRightClickMonitor() {
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

    deinit {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        flyout?.dismiss(animated: false)
    }
}
