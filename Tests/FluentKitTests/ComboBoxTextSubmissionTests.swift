import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxTextSubmissionTests: XCTestCase {
    private struct InsertingForm: FluentView {
        @FluentState var options = ["Alpha", "Bravo"]
        @FluentState var selection: String? = "Alpha"
        @FluentState var text = "Alpha"
        @FluentState var submissions = 0
        var body: some FluentView {
            FluentComboBox(options: options, selection: $selection, mode: .editable,
                text: $text, title: { $0 }).onTextSubmitted { event in
                    submissions += 1
                    options.append(event.text)
                }
        }
    }

    private struct RebindingForm: FluentView {
        @FluentState var replacement = false
        @FluentState var selection: String? = "Alpha"
        @FluentState var text = "Alpha"
        @FluentState var newSelection: String? = "Bravo"
        @FluentState var newText = "Custom"
        let handled: Bool
        var body: some FluentView {
            FluentComboBox(options: ["Alpha", "Bravo"], selection: replacement ? $newSelection : $selection,
                mode: .editable, text: replacement ? $newText : $text, title: { $0 }).onTextSubmitted { event in
                    replacement = true
                    event.handled = handled
                }
        }
    }

    @MainActor private final class Fixture {
        let selected = FluentState<Int?>(wrappedValue: 0)
        let text = FluentState(wrappedValue: "Alpha")
        var selectionBinding: FluentBinding<Int?>
        var textBinding: FluentBinding<String>?
        var names = [0: "Alpha", 1: "Bravo", 2: "Charlie"]
        var options = [0, 1, 2]
        var mode: FluentComboBoxMode = .editable
        var trigger: FluentComboBoxSelectionChangedTrigger
        var search = true
        var appliesStyle = false
        var submitted: [String] = []
        var handler: ((inout FluentComboBoxTextSubmittedEvent) -> Void)?
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<Int>>
        let field: NSTextField
        let bridge: NSComboBox
        let after = FluentTextField(placeholder: "After")
        init(bound: Bool = true, open: Bool = true, always: Bool = false) throws {
            _ = NSApplication.shared
            selectionBinding = selected.projectedValue
            textBinding = bound ? text.projectedValue : nil
            trigger = always ? .always : .committed
            let titles = names
            host = FluentViewHost(FluentComboBox(options: options, selection: selectionBinding,
                mode: .editable, text: textBinding, title: { titles[$0] ?? "" }).selectionChangedTrigger(trigger),
                context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 560, height: 320),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host); window.contentView?.addSubview(after)
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 50, y: 190, width: 280, height: 32)
            after.frame = NSRect(x: 50, y: 100, width: 280, height: 32)
            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
            field = try XCTUnwrap(Self.all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            bridge = try XCTUnwrap(Self.all(host).compactMap { $0 as? NSComboBox }.first)
            field.nextKeyView = after; after.nextKeyView = field
            update(); field.selectText(nil)
            if open { bridge.performClick(nil) }
        }
        static func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        var editor: NSTextView { field.currentEditor() as! NSTextView }
        var popup: NSWindow? { window.childWindows?.first { $0.isVisible } }
        func update() {
            let titles = names
            var value = FluentComboBox(options: options, selection: selectionBinding, mode: mode,
                text: textBinding, title: { titles[$0] ?? "" }).selectionChangedTrigger(trigger)
                .isTextSearchEnabled(search).onTextSubmitted { [weak self] event in
                    guard let self else { return }
                    self.submitted.append(event.text)
                    self.handler?(&event)
                }
            if appliesStyle { value = value.textFieldStyle(FluentAutomaticTextFieldStyle()) }
            host.update(value, context: .init(reduceMotion: true))
            host.layoutSubtreeIfNeeded()
        }
        func replace(_ value: String) {
            editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        }
        func key(_ code: UInt16) {
            let characters = code == 36 ? "\r" : code == 53 ? "\u{1b}" : code == 48 ? "\t" : ""
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
        }
    }
    private func drain() async {
        for _ in 0..<5 { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } } }
    }

    func testCustomReturnPublishesOnceAndKeepsNativeEditorAcrossModes() async throws {
        for bound in [false, true] { for open in [false, true] { for always in [false, true] {
            let f = try Fixture(bound: bound, open: open, always: always); defer { f.window.close() }
            let editor = f.editor, delegate = editor.delegate
            f.replace("Custom"); await drain()
            XCTAssertTrue(f.submitted.isEmpty); XCTAssertEqual(f.selected.wrappedValue, 0)
            f.key(36); await drain()
            XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertNil(f.selected.wrappedValue)
            XCTAssertEqual(f.field.stringValue, "Custom"); XCTAssertNil(f.popup)
            XCTAssertTrue(f.field.currentEditor() === editor); XCTAssertTrue(editor.delegate === delegate)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 6))
            if bound { XCTAssertEqual(f.text.wrappedValue, "Custom") }
        } } }
    }

    func testReturnTabBlurToggleAndOutsideSubmitButEscapeDoesNot() async throws {
        for command in ["return", "tab", "blur", "toggle", "outside", "escape"] {
            let f = try Fixture(); defer { f.window.close() }
            f.replace("Custom"); await drain()
            switch command {
            case "return": f.key(36); await drain()
            case "tab": f.key(48)
            case "blur": f.window.makeFirstResponder(f.after)
            case "toggle": f.key(118)
            case "escape": f.key(53); f.window.makeFirstResponder(f.after)
            default:
                NSApp.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 500, y: 40),
                    modifierFlags: [], timestamp: 0, windowNumber: f.window.windowNumber, context: nil,
                    eventNumber: 37, clickCount: 1, pressure: 1)!)
            }
            await drain()
            XCTAssertEqual(f.submitted, command == "escape" ? [] : ["Custom"], command)
            XCTAssertEqual(f.field.stringValue, command == "escape" ? "Alpha" : "Custom", command)
        }
    }

    func testMatchesAndProgrammaticChangesDoNotRaiseCustomSubmission() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.text.wrappedValue = "External"; await drain(); XCTAssertTrue(f.submitted.isEmpty)
        for query in ["Ch", "charlie", "Alpha"] {
            f.replace(query); await drain(); f.key(36); await drain()
            XCTAssertTrue(f.submitted.isEmpty, query)
        }
    }

    func testRepeatedCustomValueIsSuppressedUntilAConcreteOptionIsCommitted() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.replace("Custom"); await drain(); f.key(36); await drain(); f.key(36); await drain()
        f.replace("CUSTOM"); await drain(); f.key(36); await drain()
        f.window.makeFirstResponder(f.after); await drain()
        XCTAssertEqual(f.submitted, ["Custom"])
        f.field.selectText(nil); f.replace("Bravo"); await drain(); f.key(36); await drain()
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom", "Custom"])
    }

    func testEmptyAndSpaceOnlyValuesRestoreTheCurrentChoiceWithoutSubmitting() async throws {
        let f = try Fixture(); defer { f.window.close() }
        for value in ["", "   "] {
            f.replace(value); await drain(); f.key(36); await drain()
            XCTAssertTrue(f.submitted.isEmpty); XCTAssertEqual(f.selected.wrappedValue, 0)
            XCTAssertEqual(f.field.stringValue, "Alpha"); XCTAssertEqual(f.text.wrappedValue, "Alpha")
        }
    }

    func testHandledRejectionRestoresTheCurrentChoiceOrAcceptedCustomValue() async throws {
        for bound in [false, true] { for open in [false, true] {
            let f = try Fixture(bound: bound, open: open); defer { f.window.close() }
            f.handler = { $0.handled = true }
            f.replace("Rejected"); await drain(); f.key(36); await drain()
            XCTAssertEqual(f.selected.wrappedValue, 0); XCTAssertEqual(f.field.stringValue, "Alpha")
            f.handler = nil
            f.replace("Accepted"); await drain(); f.key(36); await drain()
            f.handler = { $0.handled = true }
            f.replace("Rejected again"); await drain(); f.key(36); await drain()
            XCTAssertNil(f.selected.wrappedValue); XCTAssertEqual(f.field.stringValue, "Accepted")
            f.window.makeFirstResponder(f.after); await drain()
            XCTAssertEqual(f.submitted, ["Rejected", "Accepted", "Rejected again"])
        } }
    }

    func testHandledCallbackCanChooseAnOptionWithoutHavingToRewriteItsTitle() async throws {
        for bound in [false, true] { for open in [false, true] {
            let f = try Fixture(bound: bound, open: open); defer { f.window.close() }
            f.handler = { [weak f] event in f?.selected.wrappedValue = 1; event.handled = true }
            f.replace("Custom"); await drain(); f.key(36); await drain()
            XCTAssertEqual(f.selected.wrappedValue, 1); XCTAssertEqual(f.field.stringValue, "Bravo")
            if bound { XCTAssertEqual(f.text.wrappedValue, "Bravo") }
        } }
    }

    func testUnhandledCallbackRechecksExactOptionsAfterInsertionOrReplacement() async throws {
        for replace in [false, true] { for bound in [false, true] {
            let f = try Fixture(bound: bound); defer { f.window.close() }
            f.handler = { [weak f] event in
                guard let f else { return }
                f.names[3] = event.text; f.options = replace ? [3] : f.options + [3]; f.update()
            }
            f.replace("Custom"); await drain(); f.key(36); await drain()
            XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertEqual(f.selected.wrappedValue, 3)
            XCTAssertEqual(f.field.stringValue, "Custom")
        } }
    }

    func testPostCallbackMatchIsExactAndSearchOptOutDoesNotDisableSubmission() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.search = false; f.update()
        f.handler = { [weak f] _ in f?.names[3] = "Custom suffix"; f?.options.append(3); f?.update() }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertNil(f.selected.wrappedValue)
        XCTAssertEqual(f.field.stringValue, "Custom")
    }

    func testCallbackTextResetWinsOverDefaultCommit() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.handler = { [weak f] _ in f?.text.wrappedValue = "External reset" }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertEqual(f.text.wrappedValue, "External reset")
        XCTAssertEqual(f.field.stringValue, "External reset")
    }

    func testCallbackRebindingWithSameTextDoesNotClearTheNewSelection() async throws {
        let f = try Fixture(); defer { f.window.close() }
        let newSelection = FluentState<Int?>(wrappedValue: 1), newText = FluentState(wrappedValue: "Custom")
        f.handler = { [weak f] _ in
            f?.selectionBinding = newSelection.projectedValue; f?.textBinding = newText.projectedValue; f?.update()
        }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.selected.wrappedValue, 0); XCTAssertEqual(newSelection.wrappedValue, 1)
        XCTAssertEqual(newText.wrappedValue, "Custom")
    }

    func testCallbackCanReopenAPopupWithoutTheOldReturnClosingIt() async throws {
        let f = try Fixture(); defer { f.window.close() }
        let old = try XCTUnwrap(f.popup)
        f.handler = { [weak f] _ in f?.bridge.performClick(nil); f?.bridge.performClick(nil) }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom"])
        XCTAssertNotNil(f.popup); XCTAssertFalse(f.popup === old)
        XCTAssertEqual(f.selected.wrappedValue, 0); XCTAssertEqual(f.field.stringValue, "Custom")
    }

    func testDismissalCallbackCanOpenANewPopup() async throws {
        let f = try Fixture(); defer { f.window.close() }
        let old = try XCTUnwrap(f.popup)
        f.handler = { [weak f] _ in f?.bridge.performClick(nil) }
        f.replace("Custom"); await drain(); f.key(118)
        XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertNotNil(f.popup)
        XCTAssertFalse(f.popup === old); XCTAssertEqual(f.selected.wrappedValue, 0)
    }

    func testReentrantCommitDoesNotSubmitTwice() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.handler = { [weak f] _ in f?.key(36) }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertNil(f.selected.wrappedValue)
        XCTAssertEqual(f.field.stringValue, "Custom")
    }

    func testCallbackStartingCompositionKeepsNativeMarkedText() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.handler = { [weak f] _ in
            guard let editor = f?.field.currentEditor() as? NSTextView else { return }
            editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            editor.didChangeText()
        }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom"]); XCTAssertTrue(f.editor.hasMarkedText())
        XCTAssertEqual(f.editor.string, "拼"); XCTAssertEqual(f.selected.wrappedValue, 0)
    }

    func testMarkedTextDoesNotSubmitUntilNativeCommit() async throws {
        let f = try Fixture(); defer { f.window.close() }
        let editor = f.editor
        editor.setMarkedText("Custom", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: 0, length: 5))
        editor.didChangeText(); await drain()
        let handled = f.field.delegate?.control?(f.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(handled, false); XCTAssertTrue(f.submitted.isEmpty)
        editor.unmarkText(); editor.didChangeText(); await drain(); f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom"])
    }

    func testStyleModifierAndLiveCallbackReplacementRetainSubmission() async throws {
        let f = try Fixture(); defer { f.window.close() }
        var old = 0, current = 0
        f.appliesStyle = true; f.handler = { _ in old += 1 }; f.update()
        f.handler = { _ in current += 1 }; f.update()
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(old, 0); XCTAssertEqual(current, 1); XCTAssertEqual(f.submitted, ["Custom"])
    }

    func testDeclarativeStateInsertionIsRematchedAfterItsScheduledRender() async throws {
        _ = NSApplication.shared
        let form = InsertingForm()
        let host = FluentViewHost(form, context: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 500, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(x: 50, y: 170, width: 280, height: 32)
        window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(Fixture.all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Custom", replacementRange: NSRange(location: 0, length: 5)); await drain()
        var choices: [String?] = []
        let observation = form.$selection.observe { choices.append($0) }
        defer { if let observation { form.$selection.removeObserver(observation) } }
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:))); await drain()
        XCTAssertEqual(form.submissions, 1); XCTAssertEqual(form.options, ["Alpha", "Bravo", "Custom"])
        XCTAssertEqual(form.selection, "Custom"); XCTAssertEqual(form.text, "Custom")
        XCTAssertEqual(choices, ["Custom"], "Insertion must not publish an intermediate nil choice.")
        XCTAssertTrue(field.currentEditor() === editor)
    }

    func testClosureBindingReplacementWithSameTextKeepsTheNewOwner() async throws {
        let f = try Fixture(); defer { f.window.close() }
        var oldChoice: Int? = 0, oldText = "Alpha", newChoice: Int? = 1, newText = "Custom"
        f.selectionBinding = FluentBinding(get: { oldChoice }, set: { oldChoice = $0 })
        f.textBinding = FluentBinding(get: { oldText }, set: { oldText = $0 }); f.update()
        f.handler = { [weak f] _ in
            f?.selectionBinding = FluentBinding(get: { newChoice }, set: { newChoice = $0 })
            f?.textBinding = FluentBinding(get: { newText }, set: { newText = $0 }); f?.update()
        }
        f.replace("Custom"); await drain(); f.key(36); await drain()
        XCTAssertEqual(oldChoice, 0); XCTAssertEqual(oldText, "Custom")
        XCTAssertEqual(newChoice, 1); XCTAssertEqual(newText, "Custom")
    }

    func testStoredClosureAndMappedBindingsAllowCallbackOptionInsertion() async throws {
        for mapped in [false, true] {
            let f = try Fixture(); defer { f.window.close() }
            let text = f.text, choice = f.selected
            f.textBinding = mapped ? text.projectedValue.map({ $0 }, { $0 })
                : FluentBinding(get: { text.wrappedValue }, set: { text.wrappedValue = $0 })
            f.selectionBinding = mapped ? choice.projectedValue.map({ $0 }, { $0 })
                : FluentBinding(get: { choice.wrappedValue }, set: { choice.wrappedValue = $0 })
            f.update()
            f.handler = { [weak f] event in f?.names[3] = event.text; f?.options.append(3); f?.update() }
            f.replace("Custom"); await drain(); f.key(36); await drain()
            XCTAssertEqual(choice.wrappedValue, 3, "mapped=\(mapped)")
            XCTAssertEqual(text.wrappedValue, "Custom")
        }
    }

    func testNewNativeEditCancelsThePendingDefaultCommit() async throws {
        let f = try Fixture(); defer { f.window.close() }
        f.replace("Custom"); await drain(); f.key(36)
        f.replace("New custom"); await drain()
        XCTAssertEqual(f.selected.wrappedValue, 0); XCTAssertEqual(f.field.stringValue, "New custom")
        f.key(36); await drain()
        XCTAssertEqual(f.submitted, ["Custom", "New custom"]); XCTAssertNil(f.selected.wrappedValue)
    }

    func testDetachmentCancelsPendingSubmissionAndCallbackFocusMoveDoesNot() async throws {
        for detach in [false, true] {
            let f = try Fixture(); defer { f.window.close() }
            f.handler = { [weak f] _ in
                guard let f else { return }
                if detach { f.host.removeFromSuperview() } else { f.window.makeFirstResponder(f.after) }
            }
            f.replace("Custom"); await drain(); f.key(36); await drain()
            XCTAssertEqual(f.submitted, ["Custom"])
            XCTAssertEqual(f.selected.wrappedValue, detach ? 0 : nil)
        }
    }

    func testDeclarativeRebindingWinsForHandledAndUnhandledCallbacks() async throws {
        for handled in [false, true] {
            _ = NSApplication.shared
            let form = RebindingForm(handled: handled)
            let host = FluentViewHost(form, context: .init(reduceMotion: true))
            let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 500, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; defer { window.close() }
            window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 50, y: 170, width: 280, height: 32)
            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
            let field = try XCTUnwrap(Fixture.all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            field.selectText(nil)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("Custom", replacementRange: NSRange(location: 0, length: 5)); await drain()
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:))); await drain()
            XCTAssertEqual(form.selection, "Alpha"); XCTAssertEqual(form.text, "Custom", "handled=\(handled)")
            XCTAssertEqual(form.newSelection, "Bravo"); XCTAssertEqual(form.newText, "Custom")
            XCTAssertEqual(field.stringValue, "Custom")
        }
    }
}
