import XCTest
@testable import FluentKit

final class TextFontMetricsTests: XCTestCase {
    @MainActor
    private func withEditor(_ field: NSTextField, _ body: (NSWindow, NSTextView) throws -> Void) throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 150),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        field.frame = NSRect(x: 20, y: 70, width: 310, height: 32)
        field.stringValue = "before"
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        field.selectText(nil)
        try body(window, XCTUnwrap(field.currentEditor() as? NSTextView))
    }

    @MainActor
    func testSingleLineInsertionAndCommandsKeepNativeBehavior() throws {
        for field: NSTextField in [FluentTextField(), FluentSearchTextField(), FluentSecureTextField()] {
            try withEditor(field) { _, editor in
                editor.insertText("A\nB\rC\r\nD\u{000B}E\u{000C}F\u{0085}G\u{2028}H\u{2029}I",
                                  replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                XCTAssertEqual(editor.string, "A B C  D E F G H I")
                XCTAssertEqual(field.stringValue, editor.string)
                for command in ["insertNewlineIgnoringFieldEditor:", "insertLineBreak:",
                                "insertParagraphSeparator:", "insertContainerBreak:"] {
                    editor.doCommand(by: NSSelectorFromString(command))
                    XCTAssertEqual(editor.string, "A B C  D E F G H I", command)
                }
                editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                XCTAssertTrue(editor.hasMarkedText())
                editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                XCTAssertTrue(editor.hasMarkedText())
                XCTAssertEqual(editor.string, "nihao")
                editor.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
                XCTAssertFalse(editor.hasMarkedText())
                XCTAssertEqual(editor.string, "你好")
            }
        }
    }

    @MainActor
    func testNormalizedInsertionIsOneNativeUndoAndRedo() throws {
        try withEditor(FluentSearchTextField()) { _, editor in
            editor.allowsUndo = true
            let undo = try XCTUnwrap(editor.undoManager)
            undo.removeAllActions()
            editor.breakUndoCoalescing()
            editor.insertText("One\nTwo", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            XCTAssertEqual(editor.string, "One Two")
            XCTAssertTrue(undo.canUndo)
            undo.undo()
            XCTAssertEqual(editor.string, "before")
            XCTAssertTrue(undo.canRedo)
            undo.redo()
            XCTAssertEqual(editor.string, "One Two")
        }
    }

    @MainActor
    func testMarkedSeparatorsRemainComposingUntilNativeCommit() throws {
        try withEditor(FluentSearchTextField()) { _, editor in
            editor.allowsUndo = true
            let undo = try XCTUnwrap(editor.undoManager)
            undo.removeAllActions()
            editor.setMarkedText("a\nb", selectedRange: NSRange(location: 2, length: 1),
                                 replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "a\nb")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 1))
            editor.insertText("c\nd", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertFalse(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "c d")
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            undo.undo()
            XCTAssertEqual(editor.string, "before")
            undo.redo()
            XCTAssertEqual(editor.string, "c d")
        }
    }

    @MainActor
    func testFirstEditAfterNativeFocusUsesSingleLinePolicy() throws {
        _ = NSApplication.shared
        for field: NSTextField in [FluentTextField(), FluentSearchTextField(), FluentSecureTextField()] {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 350, height: 120),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            field.frame = NSRect(x: 20, y: 40, width: 300, height: 32)
            window.contentView?.addSubview(field)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("first\nedit", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertEqual(editor.string, "first edit")
        }
    }

    @MainActor
    func testClientForwardingDelegateDoesNotCreateACycle() throws {
        let field = FluentSearchTextField()
        try withEditor(field) { _, editor in
            let client = ForwardingTextDelegate()
            client.next = editor.delegate
            editor.delegate = client
            field.theme = .custom(colorScheme: .light)
            XCTAssertTrue(editor.delegate === client)
            editor.insertText("A\nB", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            XCTAssertEqual(editor.string, "A B")
            XCTAssertTrue(editor.delegate === client)
            withExtendedLifetime(client) {}
        }
    }

    @MainActor
    func testFontUpdatePreservesMarkedTextSelectionAndInputPolicy() throws {
        let field = FluentSearchTextField()
        try withEditor(field) { _, editor in
            editor.setMarkedText("nihao", selectedRange: NSRange(location: 2, length: 1),
                                 replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            field.frame.size.height = 44
            field.theme = .custom(typography: FluentTypography(fontProvider: FluentFontProvider { _, _, _ in
                NSFont.systemFont(ofSize: 21)
            }))
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            XCTAssertTrue(field.currentEditor() === editor)
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "nihao")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 1))
            editor.insertText("你\n好", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(editor.string, "你 好")
        }
    }

    @MainActor
    func testLiveFontChangesKeepTheSharedEditorInTheCurrentTextRectangle() throws {
        for field: NSTextField in [FluentTextField(), FluentSearchTextField(), FluentSecureTextField()] {
            try withEditor(field) { _, editor in
                editor.setMarkedText("nihao", selectedRange: NSRange(location: 2, length: 1),
                                     replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                for size: CGFloat in [21, 12, 18] {
                    let theme = FluentTheme.custom(typography: FluentTypography(fontProvider: FluentFontProvider { _, _, _ in
                        NSFont.systemFont(ofSize: size)
                    }))
                    switch field {
                    case let search as FluentSearchTextField: search.theme = theme
                    case let secure as FluentSecureTextField: secure.theme = theme
                    case let text as FluentTextField: text.theme = theme
                    default: XCTFail("Unexpected fixture")
                    }
                    field.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                    let cell = try XCTUnwrap(field.cell)
                    let expected = (cell as? NSSearchFieldCell)?.searchTextRect(forBounds: field.bounds)
                        ?? cell.titleRect(forBounds: field.bounds)
                    let actual = editor.convert(editor.bounds, to: field)
                    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.01)
                    XCTAssertEqual(actual.height, expected.height, accuracy: 0.01)
                    XCTAssertTrue(field.currentEditor() === editor)
                    XCTAssertTrue(editor.hasMarkedText())
                    XCTAssertEqual(editor.string, "nihao")
                    XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 1))
                }
            }
        }
    }

    @MainActor
    func testDeferredFontLayoutDoesNotChangeTheNextFieldEditorOwner() throws {
        let search = FluentSearchTextField()
        try withEditor(search) { window, _ in
            search.theme = .custom(typography: FluentTypography(fontProvider: FluentFontProvider { _, _, _ in
                .systemFont(ofSize: 21)
            }))
            let next = FluentTextField()
            next.frame = NSRect(x: 20, y: 20, width: 310, height: 32)
            window.contentView?.addSubview(next)
            next.selectText(nil)
            let editor = try XCTUnwrap(next.currentEditor() as? NSTextView)
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: 0, length: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            XCTAssertNil(search.currentEditor())
            XCTAssertTrue(next.currentEditor() === editor)
            XCTAssertTrue(fluentFieldEditorOwner(editor) === next)
            XCTAssertEqual(editor.font, next.font)
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.string, "ni")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
        }
    }

    @MainActor
    func testReusedEditorRestoresNativeDelegateAndInputPolicy() throws {
        let field = FluentSearchTextField()
        try withEditor(field) { window, editor in
            let native = NSTextField(frame: NSRect(x: 20, y: 20, width: 310, height: 32))
            native.usesSingleLineMode = false
            window.contentView?.addSubview(native)
            native.selectText(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let reused = try XCTUnwrap(native.currentEditor() as? NSTextView)
            XCTAssertTrue(reused === editor)
            XCTAssertTrue(reused.delegate === native)
            reused.insertText("A\nB", replacementRange: NSRange(location: 0, length: reused.string.utf16.count))
            XCTAssertEqual(reused.string, "A\nB", "Fluent's input policy must not leak into the next control")
            field.selectText(nil)
            XCTAssertTrue(field.currentEditor() === editor)
            editor.insertText("C\nD", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            XCTAssertEqual(editor.string, "C D")
        }
    }

    @MainActor
    func testControlValidationAndCommandDelegateStillReceiveNormalizedInput() throws {
        let field = FluentTextField()
        let observer = TextInputObserver()
        let formatter = RejectingTextFormatter()
        field.delegate = observer
        field.formatter = formatter
        try withEditor(field) { _, editor in
            editor.insertText("A\nB", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            XCTAssertEqual(editor.string, "A B")
            XCTAssertEqual(formatter.proposals.last, "A B")
            XCTAssertEqual(observer.changes.last, "A B")
            editor.insertText("x\ny", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            XCTAssertEqual(formatter.proposals.last, "x y")
            XCTAssertEqual(editor.string, "A B", "The original formatter can still reject an edit")
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            XCTAssertEqual(observer.commands.last, "insertNewline:")
        }
    }

    @MainActor
    func testCustomFontsKeepTheirNaturalBaselineInAllSingleLineEditors() throws {
        _ = NSApplication.shared
        for fontName in ["Helvetica", "PingFangSC-Regular"] {
            _ = try XCTUnwrap(NSFont(name: fontName, size: 14))
            for size: CGFloat in [14, 21] {
                let theme = FluentTheme.custom(typography: FluentTypography(
                    fontProvider: FluentFontProvider { _, _, _ in NSFont(name: fontName, size: size)! }))
                let text = FluentTextField()
                let search = FluentSearchTextField()
                let password = FluentSecureTextField()
                text.theme = theme; search.theme = theme; password.theme = theme
                for field: NSTextField in [text, search, password] {
                    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 100),
                                          styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    defer { window.close() }
                    field.frame = NSRect(x: 20, y: 20, width: 310, height: 44)
                    field.stringValue = "Agpq"
                    window.contentView?.addSubview(field)
                    window.makeKeyAndOrderFront(nil)
                    field.selectText(nil)
                    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                    let manager = try XCTUnwrap(editor.layoutManager)
                    let container = try XCTUnwrap(editor.textContainer)
                    let font = try XCTUnwrap(field.font)
                    manager.ensureLayout(for: container)
                    XCTAssertEqual(manager.location(forGlyphAt: 0).y,
                                   manager.defaultBaselineOffset(for: font), accuracy: 0.01,
                                   "\(type(of: field)), \(fontName), \(size)")
                    XCTAssertEqual(manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height,
                                   manager.defaultLineHeight(for: font), accuracy: 0.01)
                }
            }
        }
    }
}

private final class ForwardingTextDelegate: NSObject, NSTextViewDelegate {
    weak var next: (any NSTextViewDelegate)?
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (next?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? { next }
}

@MainActor
private final class TextInputObserver: NSObject, NSTextFieldDelegate {
    var changes: [String] = []
    var commands: [String] = []
    func controlTextDidChange(_ notification: Notification) {
        changes.append((notification.object as? NSTextField)?.stringValue ?? "")
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        commands.append(NSStringFromSelector(command))
        return true
    }
}

private final class RejectingTextFormatter: Formatter {
    var proposals: [String] = []
    override func string(for obj: Any?) -> String? { obj as? String }
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as NSString
        return true
    }
    override func isPartialStringValid(_ partialString: String,
                                       newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        proposals.append(partialString)
        return !partialString.contains("x")
    }
}
