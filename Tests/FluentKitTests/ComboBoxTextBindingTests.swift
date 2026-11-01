import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxTextBindingTests: XCTestCase {
    @MainActor private final class Fixture {
        let selection = FluentState<Int?>(wrappedValue: 2)
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<Int>>
        let field: NSTextField
        let bridge: NSComboBox
        var binding: FluentBinding<String>?
        init(_ binding: FluentBinding<String>) throws {
            _ = NSApplication.shared
            self.binding = binding
            host = FluentViewHost(FluentComboBox(options: Array(0..<5), selection: selection.projectedValue,
                mode: .editable, text: binding, title: { "Option \($0)" }), context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 180, y: 200, width: 600, height: 350),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host)
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 80, y: 180, width: 280, height: 32)
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            field = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            bridge = try XCTUnwrap(all(host).compactMap { $0 as? NSComboBox }.first)
        }
        func edit() throws -> NSTextView {
            field.selectText(nil)
            return try XCTUnwrap(field.currentEditor() as? NSTextView)
        }
        func update(_ binding: FluentBinding<String>?, mode: FluentComboBoxMode = .editable) {
            self.binding = binding
            host.update(FluentComboBox(options: Array(0..<5), selection: selection.projectedValue,
                mode: mode, text: binding, title: { "Option \($0)" }),
                context: .init(theme: .custom(colorScheme: .dark), reduceMotion: true))
            host.layoutSubtreeIfNeeded()
        }
    }
    private func drain() async {
        for _ in 0..<5 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
        }
    }
    private func type(_ text: String, into editor: NSTextView) {
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }
    private func mark(_ text: String, in editor: NSTextView) {
        editor.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.didChangeText()
    }
    func testFocusedResetPreservesNativeIdentityAndClampsSelection() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); let delegate = editor.delegate
        editor.setSelectedRange(NSRange(location: 5, length: 3))
        state.wrappedValue = "短"
        XCTAssertTrue(f.field.currentEditor() === editor); XCTAssertTrue(editor.delegate === delegate)
        XCTAssertEqual(editor.string, "短"); XCTAssertEqual(f.field.stringValue, "短")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
        f.window.makeFirstResponder(nil); await drain()
        XCTAssertEqual(state.wrappedValue, "短")
    }
    func testExternalResetAndExplicitSameValueSendCancelQueuedTyping() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit()
        type("unsent", into: editor); state.wrappedValue = "reset"
        await drain(); XCTAssertEqual(editor.string, "reset"); XCTAssertEqual(state.wrappedValue, "reset")
        type("another unsent edit", into: editor); state.observableValue.send()
        await drain(); XCTAssertEqual(editor.string, "reset"); XCTAssertEqual(state.wrappedValue, "reset")
        f.window.makeFirstResponder(nil); await drain(); XCTAssertEqual(state.wrappedValue, "reset")
    }
    func testResetReconcilesMatchingSelectionWithoutReplacingPopup() throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); f.bridge.performClick(nil)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        state.wrappedValue = "free"
        XCTAssertNil(f.selection.wrappedValue); XCTAssertEqual(editor.string, "free")
        state.wrappedValue = "Option 4"
        XCTAssertEqual(f.selection.wrappedValue, 4); XCTAssertEqual(editor.string, "Option 4")
        XCTAssertTrue(f.window.childWindows?.first === panel); XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(f.bridge.indexOfSelectedItem, 4)
    }
    func testCommittedCompositionDefersPublicationAndLatestResetWins() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        var changes: [FluentTextEditingChange] = []
        let f = try Fixture(state.projectedValue.textInput(.init(commitPolicy: .committedText,
            onEditingChange: { changes.append($0) }))); defer { f.window.close() }
        let editor = try f.edit()
        mark("pin", in: editor); await drain()
        XCTAssertEqual(state.wrappedValue, "Option 2"); XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertEqual(changes.last, .init(text: "pin", isComposing: true))
        state.wrappedValue = "first reset"; state.wrappedValue = "Option 4"
        mark("ping", in: editor); await drain()
        XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.string, "ping")
        XCTAssertEqual(state.wrappedValue, "Option 4")
        editor.unmarkText(); editor.didChangeText(); await drain()
        XCTAssertTrue(f.field.currentEditor() === editor); XCTAssertEqual(editor.string, "Option 4")
        XCTAssertEqual(f.selection.wrappedValue, 4)
        f.window.makeFirstResponder(nil); await drain(); XCTAssertEqual(state.wrappedValue, "Option 4")
    }
    func testContinuousCompositionPublishesButCannotOverwritePendingReset() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit()
        mark("pin", in: editor); await drain(); XCTAssertEqual(state.wrappedValue, "pin")
        state.wrappedValue = "reset"
        mark("ping", in: editor); await drain()
        XCTAssertEqual(state.wrappedValue, "reset"); XCTAssertTrue(editor.hasMarkedText())
        editor.unmarkText(); editor.didChangeText(); await drain()
        XCTAssertEqual(editor.string, "reset"); XCTAssertEqual(state.wrappedValue, "reset")
    }
    func testUnobservedClosureResetIsReadBeforeBlurPublication() async throws {
        var value = "Option 2"
        let binding = FluentBinding(get: { value }, set: { value = $0 })
        let f = try Fixture(binding); defer { f.window.close() }
        let editor = try f.edit(); type("unsent", into: editor)
        value = "external"
        f.window.makeFirstResponder(nil); await drain()
        XCTAssertEqual(value, "external"); XCTAssertEqual(f.field.stringValue, "external")
        _ = try f.edit(); value = "rerender reset"; f.update(binding)
        XCTAssertEqual(f.field.stringValue, "rerender reset")
    }
    func testBindingReplacementCancelsOldPublicationAndOldNotifications() async throws {
        let first = FluentState(wrappedValue: "Option 2")
        let second = FluentState(wrappedValue: "new binding")
        let f = try Fixture(first.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); type("unsent old text", into: editor)
        f.update(second.projectedValue); first.wrappedValue = "stale notification"
        await drain()
        XCTAssertEqual(editor.string, "new binding"); XCTAssertEqual(second.wrappedValue, "new binding")
        type("new edit", into: editor); await drain()
        XCTAssertEqual(second.wrappedValue, "new edit"); XCTAssertEqual(first.wrappedValue, "stale notification")
    }
    func testBindingReplacementDuringCompositionKeepsMarkedTextUntilCommit() async throws {
        let first = FluentState(wrappedValue: "Option 2")
        let second = FluentState(wrappedValue: "replacement")
        let f = try Fixture(first.projectedValue.textInput(.init(commitPolicy: .committedText))); defer { f.window.close() }
        let editor = try f.edit(); mark("pin", in: editor)
        f.update(second.projectedValue.textInput(.init(commitPolicy: .committedText)))
        first.wrappedValue = "old reset"
        await drain(); XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.string, "pin")
        editor.unmarkText(); editor.didChangeText(); await drain()
        XCTAssertEqual(editor.string, "replacement"); XCTAssertEqual(second.wrappedValue, "replacement")
        XCTAssertEqual(first.wrappedValue, "old reset")
    }
    func testValidatingSetterAppliesItsNormalizedResultToLiveEditor() async throws {
        var value = "Option 2"
        let f = try Fixture(.init(get: { value }, set: { value = $0.uppercased() })); defer { f.window.close() }
        let editor = try f.edit(); type("lowercase", into: editor); await drain()
        XCTAssertEqual(value, "LOWERCASE"); XCTAssertEqual(editor.string, "LOWERCASE")
        XCTAssertNil(f.selection.wrappedValue); XCTAssertTrue(f.field.currentEditor() === editor)
    }
    func testReentrantSetterRebindsWithoutPublishingIntoReplacementModel() async throws {
        var value = "Option 2"
        let replacement = FluentState(wrappedValue: "replacement")
        var fixture: Fixture?
        let binding = FluentBinding(get: { value }, set: {
            value = $0
            if $0 == "typed" { fixture?.update(replacement.projectedValue) }
        })
        let f = try Fixture(binding); fixture = f; defer { fixture = nil; f.window.close() }
        let editor = try f.edit(); type("typed", into: editor); await drain()
        XCTAssertEqual(value, "typed"); XCTAssertEqual(replacement.wrappedValue, "replacement")
        XCTAssertEqual(editor.string, "replacement")
        replacement.wrappedValue = "subsequent reset"; XCTAssertEqual(editor.string, "subsequent reset")
    }
    func testRetiredCoordinatorCannotOverwriteModeChangedDuringSetter() async throws {
        var value = "Option 2"
        let replacement = FluentState(wrappedValue: "replacement")
        var fixture: Fixture?
        let f = try Fixture(.init(get: { value }, set: {
            value = $0.uppercased()
            if $0 == "typed", let fixture {
                fixture.selection.wrappedValue = 3
                fixture.update(replacement.projectedValue, mode: .selection)
            }
        })); fixture = f; defer { fixture = nil; f.window.close() }
        let editor = try f.edit(); type("typed", into: editor); await drain()
        XCTAssertEqual(f.bridge.stringValue, "Option 3")
        f.update(replacement.projectedValue)
        XCTAssertEqual(f.field.stringValue, "replacement"); XCTAssertEqual(replacement.wrappedValue, "replacement")
    }
    func testNativeUndoAndRedoSynchronizeTextAndSelection() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); type("Option 3", into: editor); await drain()
        XCTAssertEqual(state.wrappedValue, "Option 3"); XCTAssertEqual(f.selection.wrappedValue, 3)
        let undo = try XCTUnwrap(editor.undoManager); XCTAssertTrue(undo.canUndo)
        undo.undo(); await drain()
        XCTAssertEqual(state.wrappedValue, editor.string); XCTAssertEqual(f.selection.wrappedValue, 2)
        undo.redo(); await drain()
        XCTAssertEqual(state.wrappedValue, "Option 3"); XCTAssertEqual(f.selection.wrappedValue, 3)
    }
    func testEditingChangeCallbackCanReplaceBindingBeforePublication() async throws {
        let first = FluentState(wrappedValue: "Option 2")
        let second = FluentState(wrappedValue: "new value")
        var fixture: Fixture?
        let binding = first.projectedValue.textInput(.init(onEditingChange: {
            if $0.text == "typed" { fixture?.update(second.projectedValue) }
        }))
        let f = try Fixture(binding); fixture = f; defer { fixture = nil; f.window.close() }
        let editor = try f.edit(); type("typed", into: editor); await drain()
        XCTAssertEqual(first.wrappedValue, "Option 2"); XCTAssertEqual(second.wrappedValue, "new value")
        XCTAssertEqual(editor.string, "new value")
    }
    func testInactiveComboResetCannotMutateSharedEditorNowOwnedByOtherField() throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        _ = try f.edit()
        let other = FluentTextField(); other.stringValue = "Other text"
        other.frame = NSRect(x: 80, y: 100, width: 280, height: 32); f.window.contentView?.addSubview(other)
        other.selectText(nil)
        let editor = try XCTUnwrap(other.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        state.wrappedValue = "reset"
        XCTAssertEqual(f.field.stringValue, "reset"); XCTAssertEqual(editor.string, "Other text")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 2))
    }
    func testUnchangedBindingRefreshPreservesUnpublishedNativeEdit() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); type("pending", into: editor)
        f.update(state.projectedValue)
        XCTAssertEqual(editor.string, "pending"); XCTAssertTrue(f.field.currentEditor() === editor)
        await drain(); XCTAssertEqual(state.wrappedValue, "pending")
    }

    func testReplacingObservedBindingWithSameValueDiscardsOldQueuedEdit() async throws {
        let first = FluentState(wrappedValue: "Option 2")
        let second = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(first.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); type("unsent old text", into: editor)
        f.update(second.projectedValue); await drain()
        XCTAssertEqual(editor.string, "Option 2")
        f.window.makeFirstResponder(nil); await drain()
        XCTAssertEqual(first.wrappedValue, "Option 2"); XCTAssertEqual(second.wrappedValue, "Option 2")
    }

    func testUnchangedClosureBindingRefreshKeepsQueuedPublication() async throws {
        var value = "Option 2"
        let binding = FluentBinding(get: { value }, set: { value = $0 })
        let f = try Fixture(binding); defer { f.window.close() }
        let editor = try f.edit(); type("pending", into: editor)
        f.update(binding); await drain()
        XCTAssertEqual(editor.string, "pending"); XCTAssertEqual(value, "pending")
    }

    func testLatestClosureResetWinsOverEarlierPendingCompositionReset() async throws {
        var value = "Option 2"
        let binding = FluentBinding(get: { value }, set: { value = $0 })
            .textInput(.init(commitPolicy: .committedText))
        let f = try Fixture(binding); defer { f.window.close() }
        let editor = try f.edit(); mark("pin", in: editor); await drain()
        value = "earlier reset"; f.update(binding)
        value = "latest reset"
        editor.unmarkText(); editor.didChangeText(); await drain()
        XCTAssertEqual(editor.string, "latest reset"); XCTAssertEqual(value, "latest reset")
        f.window.makeFirstResponder(nil); await drain(); XCTAssertEqual(value, "latest reset")
    }

    func testRemovingTextBindingDetachesOldObserverAndQueuedPublication() async throws {
        let state = FluentState(wrappedValue: "Option 2")
        let f = try Fixture(state.projectedValue); defer { f.window.close() }
        let editor = try f.edit(); type("unsent old text", into: editor)
        f.update(nil); state.wrappedValue = "detached reset"; await drain()
        type("Option 4", into: editor); await drain()
        XCTAssertEqual(state.wrappedValue, "detached reset"); XCTAssertEqual(f.selection.wrappedValue, 4)
    }
}
