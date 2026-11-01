import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxEditableCompletionTests: XCTestCase {
    @MainActor private final class Fixture {
        let selected = FluentState<Int?>(wrappedValue: 0)
        let text = FluentState(wrappedValue: "Alpha")
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<Int>>
        let field: NSTextField
        let bridge: NSComboBox
        var names = ["Alpha", "Bravo", "Charlie", "Chase", "👩‍💻 Tools", "Éclair", "Ｆｌｕｅｎｔ", "カタカナ"]
        var options = Array(0..<8)
        let trigger: FluentComboBoxSelectionChangedTrigger
        let bound: Bool
        var searchEnabled = true
        var binding: FluentBinding<String>?
        init(bound: Bool = true, open: Bool = true, trigger: FluentComboBoxSelectionChangedTrigger = .committed,
             configure: ((FluentBinding<String>) -> FluentBinding<String>)? = nil) throws {
            _ = NSApplication.shared
            self.trigger = trigger; self.bound = bound
            let titles = names
            binding = bound ? (configure?(text.projectedValue) ?? text.projectedValue) : nil
            host = FluentViewHost(FluentComboBox(options: options, selection: selected.projectedValue,
                mode: .editable, text: binding, title: { titles[$0] }).selectionChangedTrigger(trigger),
                context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 520, height: 320),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 60, y: 170, width: 280, height: 32)
            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
            field = try XCTUnwrap(Self.all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            bridge = try XCTUnwrap(Self.all(host).compactMap { $0 as? NSComboBox }.first)
            field.selectText(nil)
            if open { bridge.performClick(nil) }
        }
        static func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        var editor: NSTextView { field.currentEditor() as! NSTextView }
        var popup: NSWindow? { window.childWindows?.first { $0.isVisible } }
        var rows: [NSView] { popup?.contentView.map { Self.all($0).filter { $0.accessibilityRole() == .menuItem } } ?? [] }
        func update() {
            let titles = names
            host.update(FluentComboBox(options: options, selection: selected.projectedValue,
                mode: .editable, text: binding, title: { titles[$0] }).selectionChangedTrigger(trigger)
                .isTextSearchEnabled(searchEnabled), context: .init(reduceMotion: true))
        }
        func replace(_ value: String) { editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count)) }
        func key(_ code: UInt16) {
            let characters = code == 36 ? "\r" : code == 53 ? "\u{1b}" : "\t"
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
        }
    }
    private func drain() async {
        for _ in 0..<5 { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } } }
    }

    func testCompletionSelectsSuffixWithoutReplacingEditorAndRespectsTrigger() async throws {
        for bound in [false, true] {
            for open in [false, true] {
                for trigger in [FluentComboBoxSelectionChangedTrigger.committed, .always] {
                    let f = try Fixture(bound: bound, open: open, trigger: trigger); defer { f.window.close() }
                    let editor = f.editor, delegate = editor.delegate, panel = f.popup
                    f.replace("Ch"); await drain()
                    XCTAssertEqual(editor.string, "Charlie"); XCTAssertEqual(f.field.stringValue, "Charlie")
                    XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 5))
                    XCTAssertTrue(f.field.currentEditor() === editor); XCTAssertTrue(editor.delegate === delegate)
                    XCTAssertTrue(f.window.firstResponder === editor); XCTAssertTrue(f.popup === panel)
                    XCTAssertEqual(f.selected.wrappedValue, trigger == .always ? 2 : 0)
                    if bound { XCTAssertEqual(f.text.wrappedValue, "Charlie") }
                    if open {
                        XCTAssertEqual(f.rows.filter { $0.isAccessibilityFocused() }.compactMap { $0.accessibilityTitle() }, ["Charlie"])
                    }
                    f.key(36); XCTAssertEqual(f.selected.wrappedValue, 2)
                }
            }
        }
    }

    func testTypingOverSuffixFindsTheNextMatchingOption() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.replace("Ch"); await drain()
        f.editor.insertText("a", replacementRange: f.editor.selectedRange()); await drain()
        XCTAssertEqual(f.editor.string, "Charlie"); XCTAssertEqual(f.editor.selectedRange(), NSRange(location: 3, length: 4))
        f.editor.insertText("s", replacementRange: f.editor.selectedRange()); await drain()
        XCTAssertEqual(f.editor.string, "Chase"); XCTAssertEqual(f.editor.selectedRange(), NSRange(location: 4, length: 1))
        f.key(36); XCTAssertEqual(f.selected.wrappedValue, 3)
    }

    func testDeletingCompletionDoesNotImmediatelyRestoreIt() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.replace("Ch"); await drain()
        f.editor.deleteBackward(nil); await drain()
        XCTAssertEqual(f.editor.string, "Ch"); XCTAssertEqual(f.text.wrappedValue, "Ch")
        f.editor.deleteBackward(nil); await drain(); XCTAssertEqual(f.editor.string, "C")
        f.key(36); XCTAssertNil(f.selected.wrappedValue); XCTAssertEqual(f.text.wrappedValue, "C")
    }

    func testUnicodeMatchingKeepsSuffixRangesOnValidBoundaries() async throws {
        for (query, id, range) in [("👩‍💻", 4, NSRange(location: 5, length: 6)),
                                  ("e", 5, NSRange(location: 1, length: 5)),
                                  ("e\u{301}", 5, NSRange(location: 1, length: 5)),
                                  ("fl", 6, NSRange(location: 2, length: 4)),
                                  ("かた", 7, NSRange(location: 2, length: 2))] {
            let f = try Fixture(); defer { f.window.close() }
            f.replace(query); await drain()
            XCTAssertEqual(f.editor.string, f.names[id]); XCTAssertEqual(f.editor.selectedRange(), range)
            f.key(36); XCTAssertEqual(f.selected.wrappedValue, id)
        }
    }

    func testCaseInsensitiveExactMatchKeepsTypedCasing() async throws {
        for bound in [false, true] {
            for open in [false, true] {
                let f = try Fixture(bound: bound, open: open); defer { f.window.close() }
                f.replace("charlie"); await drain()
                XCTAssertEqual(f.editor.string, "charlie")
                f.key(36); XCTAssertEqual(f.selected.wrappedValue, 2)
                XCTAssertEqual(f.editor.string, "charlie")
                if bound { XCTAssertEqual(f.text.wrappedValue, "charlie") }
            }
        }
    }

    func testUnboundCaseEquivalentCommitSurvivesBlurAndYieldsToExternalSelection() async throws {
        let f = try Fixture(bound: false, open: false); defer { f.window.close() }
        f.replace("charlie"); await drain(); f.window.makeFirstResponder(nil); await drain()
        XCTAssertEqual(f.field.stringValue, "charlie"); XCTAssertEqual(f.selected.wrappedValue, 2)
        f.selected.wrappedValue = 1
        XCTAssertEqual(f.field.stringValue, "Bravo")
    }

    func testSearchOptOutAndLiveOptInOnlyAffectNewEdits() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.searchEnabled = false; f.update(); f.replace("Ch"); await drain()
        XCTAssertEqual(f.editor.string, "Ch")
        f.searchEnabled = true; f.update(); await drain(); XCTAssertEqual(f.editor.string, "Ch")
        f.editor.insertText("a", replacementRange: NSRange(location: 2, length: 0)); await drain()
        XCTAssertEqual(f.editor.string, "Charlie")
    }

    func testCompositionCompletesOnlyAfterNativeCommit() async throws {
        for bound in [false, true] {
            let f = try Fixture(bound: bound, configure: { $0.textInput(.init(commitPolicy: .committedText)) })
            defer { f.window.close() }
            let editor = f.editor
            editor.setMarkedText("Ch", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 5))
            editor.didChangeText(); await drain()
            XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.string, "Ch"); XCTAssertEqual(f.selected.wrappedValue, 0)
            editor.unmarkText(); editor.didChangeText(); await drain()
            XCTAssertEqual(editor.string, "Charlie"); XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 5))
        }
    }

    func testQueuedCompletionCannotOverwriteExternalTextReset() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.replace("Ch"); f.text.wrappedValue = "Br"; await drain()
        XCTAssertEqual(f.editor.string, "Br"); XCTAssertEqual(f.text.wrappedValue, "Br")
        f.key(36); XCTAssertEqual(f.text.wrappedValue, "Br"); XCTAssertNil(f.selected.wrappedValue)
    }

    func testExternalSelectionDuringCompositionPrecedesCompletion() async throws {
        for bound in [false, true] {
            let f = try Fixture(bound: bound); defer { f.window.close() }
            let editor = f.editor
            editor.setMarkedText("Ch", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 5))
            editor.didChangeText(); await drain(); f.selected.wrappedValue = 1
            editor.unmarkText(); editor.didChangeText(); await drain()
            XCTAssertEqual(editor.string, "Bravo"); XCTAssertEqual(f.selected.wrappedValue, 1)
        }
    }

    func testNativeUndoAndRedoIncludeCompletion() async throws {
        let f = try Fixture(trigger: .always); defer { f.window.close() }
        f.replace("Ch"); await drain(); XCTAssertEqual(f.editor.string, "Charlie")
        let undo = try XCTUnwrap(f.editor.undoManager)
        undo.undo(); await drain(); XCTAssertEqual(f.editor.string, "Alpha"); XCTAssertEqual(f.selected.wrappedValue, 0)
        undo.redo(); await drain(); XCTAssertEqual(f.editor.string, "Charlie"); XCTAssertEqual(f.selected.wrappedValue, 2)
    }

    func testEscapeRestoresOpeningValueAfterCompletion() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.replace("Ch"); await drain(); XCTAssertEqual(f.editor.string, "Charlie")
        f.key(53); XCTAssertEqual(f.editor.string, "Alpha"); XCTAssertEqual(f.text.wrappedValue, "Alpha")
        XCTAssertEqual(f.selected.wrappedValue, 0)
    }

    func testCompletionCallbackCanResetTextWithoutStartingAnotherCompletion() async throws {
        var fixture: Fixture?
        let f = try Fixture(configure: { original in
            original.textInput(.init(onEditingChange: { change in
                if change.text == "Charlie" { fixture?.text.wrappedValue = "Br" }
            }))
        }); fixture = f; defer { fixture = nil; f.window.close() }
        f.replace("Ch"); await drain()
        XCTAssertEqual(f.editor.string, "Br"); XCTAssertEqual(f.text.wrappedValue, "Br")
        XCTAssertNil(f.selected.wrappedValue)
    }

    func testEnablingSearchDoesNotCompleteAnEarlierOptOutEditOnBlur() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.searchEnabled = false; f.update(); f.replace("Ch"); await drain()
        f.searchEnabled = true; f.update(); f.key(36)
        XCTAssertEqual(f.text.wrappedValue, "Ch"); XCTAssertNil(f.selected.wrappedValue)
    }

    func testCompletedStableOptionSurvivesRenameAndReorder() async throws {
        for bound in [false, true] {
            for open in [false, true] {
                let f = try Fixture(bound: bound, open: open); defer { f.window.close() }
                f.replace("Ch"); await drain()
                f.names[2] = "Renamed"; f.options = [3, 2, 1, 0]; f.update()
                f.key(36)
                XCTAssertEqual(f.selected.wrappedValue, 2); XCTAssertEqual(f.field.stringValue, "Renamed")
            }
        }
    }

    func testValidatingSetterCanReplaceCompletedValue() async throws {
        let f = try Fixture(); defer { f.window.close() }
        let model = f.text
        f.binding = FluentBinding(get: { model.wrappedValue }, set: { model.wrappedValue = $0 == "Charlie" ? "Br" : $0 })
        f.update(); f.replace("Ch"); await drain()
        XCTAssertEqual(f.editor.string, "Br"); XCTAssertEqual(f.text.wrappedValue, "Br")
        f.key(36); XCTAssertEqual(f.text.wrappedValue, "Br"); XCTAssertNil(f.selected.wrappedValue)
    }

    func testCompletionCallbackCanReplaceTheBindingWithTheSameValue() async throws {
        var fixture: Fixture?
        let replacement = FluentState(wrappedValue: "Charlie")
        let f = try Fixture(configure: { original in
            original.textInput(.init(onEditingChange: { change in
                guard change.text == "Charlie", let fixture else { return }
                fixture.binding = replacement.projectedValue; fixture.update()
            }))
        }); fixture = f; defer { fixture = nil; f.window.close() }
        f.replace("Ch"); await drain()
        XCTAssertEqual(f.text.wrappedValue, "Alpha"); XCTAssertEqual(replacement.wrappedValue, "Charlie")
        f.key(36); XCTAssertEqual(f.selected.wrappedValue, 2)
    }

    func testAlwaysReconcilesSelectionWhenCompletedTextAlreadyEqualsTheModel() async throws {
        let model = FluentState(wrappedValue: "Charlie")
        let f = try Fixture(open: false, trigger: .always, configure: { _ in model.projectedValue })
        defer { f.window.close() }
        f.replace("Ch"); await drain()
        XCTAssertEqual(f.editor.string, "Charlie"); XCTAssertEqual(f.selected.wrappedValue, 2)
    }

    func testAlwaysKeepsLastChoiceWhileTextHasNoMatchUntilCommitted() async throws {
        for bound in [false, true] {
            let f = try Fixture(bound: bound, trigger: .always); defer { f.window.close() }
            f.replace("Ch"); await drain(); XCTAssertEqual(f.selected.wrappedValue, 2)
            f.editor.deleteBackward(nil); await drain()
            XCTAssertEqual(f.editor.string, "Ch"); XCTAssertEqual(f.selected.wrappedValue, 2)
            f.key(36); XCTAssertNil(f.selected.wrappedValue)
        }
    }
}
