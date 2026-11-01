import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxKeyboardContractTests: XCTestCase {
    @MainActor private final class Fixture {
        let selection: FluentState<Int?>
        let text = FluentState(wrappedValue: "Option 2")
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<Int>>
        let bridge: NSComboBox
        let field: NSTextField
        let before = FluentTextField(placeholder: "Before")
        let after = FluentTextField(placeholder: "After")
        let mode: FluentComboBoxMode
        var options: [Int]
        init(mode: FluentComboBoxMode = .selection, selected: Int? = 2, count: Int = 5) throws {
            _ = NSApplication.shared
            self.mode = mode
            options = Array(0..<count)
            selection = FluentState(wrappedValue: selected)
            host = FluentViewHost(FluentComboBox(options: options, selection: selection.projectedValue,
                mode: mode, text: mode == .editable ? text.projectedValue : nil, title: { "Option \($0)" }).selectionChangedTrigger(.always),
                context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 600, height: 350),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            for view in [before, host, after] { window.contentView?.addSubview(view) }
            before.frame = NSRect(x: 50, y: 260, width: 240, height: 32)
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 50, y: 180, width: 240, height: 32)
            after.frame = NSRect(x: 50, y: 100, width: 240, height: 32)
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            bridge = try XCTUnwrap(all(host).compactMap { $0 as? NSComboBox }.first)
            field = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            let control: NSView = mode == .editable ? field : bridge
            before.nextKeyView = control; control.nextKeyView = after; after.nextKeyView = before
            window.makeFirstResponder(control)
        }
        var popup: NSWindow? { window.childWindows?.first { $0.isVisible } }
        func open() throws -> NSWindow {
            bridge.performClick(nil)
            return try XCTUnwrap(popup)
        }
        func edit() throws -> NSTextView {
            field.selectText(nil)
            return try XCTUnwrap(field.currentEditor() as? NSTextView)
        }
        func update(_ options: [Int]) {
            self.options = options
            host.update(FluentComboBox(options: options, selection: selection.projectedValue,
                mode: mode, text: mode == .editable ? text.projectedValue : nil, title: { "Option \($0)" }).selectionChangedTrigger(.always),
                context: .init(reduceMotion: true))
            host.layoutSubtreeIfNeeded()
        }
    }
    private func event(_ code: UInt16, window: NSWindow, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
        let characters = code == 125 ? "\u{F701}" : code == 126 ? "\u{F700}" : ""
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: repeatKey, keyCode: code)!
    }
    private func key(_ code: UInt16, _ f: Fixture, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) {
        let window = f.popup ?? f.window
        let target = f.popup?.firstResponder ?? f.bridge
        target.keyDown(with: event(code, window: window, flags: flags, repeatKey: repeatKey))
    }
    func testClosedSelectionNavigationIsBoundedAndDoesNotOpen() throws {
        let f = try Fixture(); defer { f.window.close() }
        for (code, expected): (UInt16, Int) in [(125, 3), (126, 2), (115, 0), (126, 0), (119, 4), (125, 4)] {
            key(code, f)
            XCTAssertEqual(f.selection.wrappedValue, expected)
            XCTAssertNil(f.popup)
        }
    }
    func testSelectionModeUsesControlAsKeyboardResponder() throws {
        let f = try Fixture(); defer { f.window.close() }
        XCTAssertTrue(f.window.firstResponder === f.bridge,
            "responder=\(String(describing: f.window.firstResponder)) editor=\(String(describing: f.bridge.currentEditor())) key=\(f.bridge.canBecomeKeyView)")
    }
    func testNoSelectionUpStaysEmptyAndDownSelectsFirst() throws {
        let f = try Fixture(selected: nil); defer { f.window.close() }
        key(126, f); XCTAssertNil(f.selection.wrappedValue); XCTAssertNil(f.popup)
        key(125, f); XCTAssertEqual(f.selection.wrappedValue, 0); XCTAssertNil(f.popup)
    }
    func testF4AndOptionArrowsToggleWithoutSelectingAndIgnoreToggleRepeat() throws {
        let f = try Fixture(); defer { f.window.close() }
        key(118, f)
        let panel = try XCTUnwrap(f.popup)
        key(118, f, repeatKey: true); XCTAssertTrue(f.popup === panel)
        key(118, f); XCTAssertNil(f.popup)
        key(125, f, flags: .option); XCTAssertNotNil(f.popup)
        key(126, f, flags: .option); XCTAssertNil(f.popup)
        XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertTrue(f.window.firstResponder === f.bridge)
    }
    func testCommandModifiedArrowDoesNotOpenOrChangeSelection() throws {
        let f = try Fixture(); defer { f.window.close() }
        key(125, f, flags: .command)
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 2)
    }
    func testPopupEdgesDoNotWrapAndPageNavigationMovesByViewport() throws {
        let f = try Fixture(count: 40); defer { f.window.close() }
        _ = try f.open()
        key(119, f); key(125, f); XCTAssertEqual(f.selection.wrappedValue, 39)
        key(115, f); key(126, f); XCTAssertEqual(f.selection.wrappedValue, 0)
        key(121, f)
        let page = try XCTUnwrap(f.selection.wrappedValue)
        XCTAssertGreaterThan(page, 1); XCTAssertLessThan(page, 39)
        key(116, f); XCTAssertEqual(f.selection.wrappedValue, 0)
    }
    func testPopupTabTraversesParentKeyLoopInBothDirections() throws {
        for backwards in [false, true] {
            let f = try Fixture(); defer { f.window.close() }
            _ = try f.open()
            key(48, f, flags: backwards ? .shift : [])
            XCTAssertNil(f.popup)
            let target = backwards ? f.before : f.after
            XCTAssertTrue(f.window.firstResponder === target.currentEditor() || f.window.firstResponder === target,
                "backwards=\(backwards) responder=\(String(describing: f.window.firstResponder)) bridgeEditor=\(String(describing: f.bridge.currentEditor())) next=\(String(describing: f.bridge.nextValidKeyView)) previous=\(String(describing: f.bridge.previousValidKeyView))")
        }
    }
    func testEscapeRestoresOpeningSelectionByIdentityAfterReorder() throws {
        let f = try Fixture(); defer { f.window.close() }
        _ = try f.open(); key(125, f); XCTAssertEqual(f.selection.wrappedValue, 3)
        f.update([4, 3, 1, 0, 2])
        key(53, f)
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertTrue(f.window.firstResponder === f.bridge)
    }
    func testEscapeNeverRestoresAnOptionRemovedWhileOpen() throws {
        let f = try Fixture(); defer { f.window.close() }
        _ = try f.open(); key(125, f)
        f.update([0, 1, 3, 4]); key(53, f)
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 3)
    }
    func testEditableCommandsKeepNativeEditorAndNavigateOpenPopup() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        editor.setSelectedRange(NSRange(location: 2, length: 3))
        let delegate = editor.delegate
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        let popup = try XCTUnwrap(f.popup)
        XCTAssertFalse(popup.canBecomeKey)
        XCTAssertTrue(f.window.firstResponder === editor)
        XCTAssertTrue(f.field.currentEditor() === editor)
        XCTAssertTrue(editor.delegate === delegate)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 3))
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(f.selection.wrappedValue, 3)
        XCTAssertEqual(editor.string, "Option 3")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(f.popup); XCTAssertTrue(f.field.currentEditor() === editor)
    }
    func testEditableTypingAndSpaceKeepPopupAndEditor() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        let popup = try XCTUnwrap(f.popup)
        editor.insertText("Free text", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        waitForUI(f.text.wrappedValue == "Free text ")
        // Always publishes found matches immediately; unmatched drafts retain the old choice.
        XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertTrue(f.popup === popup); XCTAssertTrue(f.field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "Free text ")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(f.selection.wrappedValue)
        XCTAssertEqual(editor.string, "Free text ")
    }
    func testEditableEscapeRestoresOpeningValueWithoutEndingEditing() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        _ = try XCTUnwrap(f.popup)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertEqual(f.text.wrappedValue, "Option 2"); XCTAssertEqual(editor.string, "Option 2")
        XCTAssertTrue(f.field.currentEditor() === editor)
    }
    func testEditableF4EquivalentIsScopedToFocusedEditor() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        XCTAssertTrue(f.field.performKeyEquivalent(with: event(118, window: f.window)))
        XCTAssertNotNil(f.popup); XCTAssertTrue(f.field.currentEditor() === editor)
        XCTAssertTrue(f.field.performKeyEquivalent(with: event(118, window: f.window)))
        XCTAssertNil(f.popup)
        f.after.selectText(nil)
        XCTAssertFalse(f.field.performKeyEquivalent(with: event(118, window: f.window)))
        XCTAssertNil(f.popup)
    }
    func testApplicationDispatchF4TogglesForTheNativeEditor() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        NSApp.sendEvent(event(118, window: f.window))
        XCTAssertNotNil(f.popup); XCTAssertTrue(f.field.currentEditor() === editor)
        NSApp.sendEvent(event(118, window: f.window))
        XCTAssertNil(f.popup); XCTAssertTrue(f.field.currentEditor() === editor)
        f.after.selectText(nil)
        NSApp.sendEvent(event(118, window: f.window))
        XCTAssertNil(f.popup)
    }
    func testEditableParagraphCommandsRemainNative() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        editor.doCommand(by: #selector(NSResponder.moveToEndOfParagraph(_:)))
        XCTAssertNil(f.popup); XCTAssertEqual(editor.selectedRange().location, editor.string.utf16.count)
        editor.doCommand(by: #selector(NSResponder.moveToBeginningOfParagraph(_:)))
        XCTAssertNil(f.popup); XCTAssertEqual(editor.selectedRange().location, 0)
    }
    func testEditableOptionArrowDispatchDoesNotRetoggleOnRepeat() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        NSApp.sendEvent(event(125, window: f.window, flags: .option))
        let panel = try XCTUnwrap(f.popup)
        NSApp.sendEvent(event(125, window: f.window, flags: .option, repeatKey: true))
        XCTAssertTrue(f.popup === panel); XCTAssertTrue(f.field.currentEditor() === editor)
        NSApp.sendEvent(event(126, window: f.window, flags: .option))
        XCTAssertNil(f.popup)
    }

    func testPopupTabHonorsAnEnclosingExplicitFocusCycle() throws {
        final class Cycle: NSView, @preconcurrency FluentKeyboardFocusCycle {
            var source: NSView?
            var backwards: Bool?
            func moveKeyboardFocus(from view: NSView, backwards: Bool) {
                source = view; self.backwards = backwards
            }
        }
        let f = try Fixture(); defer { f.window.close() }
        let cycle = Cycle(frame: f.window.contentView!.bounds)
        f.window.contentView?.addSubview(cycle)
        cycle.addSubview(f.host)
        _ = try f.open(); key(48, f, flags: .shift)
        XCTAssertNil(f.popup); XCTAssertTrue(cycle.source === f.bridge); XCTAssertEqual(cycle.backwards, true)
    }

    func testEditableEscapeRestoresCustomTextAndNavigationUsesCurrentOptions() throws {
        let f = try Fixture(mode: .editable, selected: nil); defer { f.window.close() }
        f.text.wrappedValue = "Custom"
        f.field.stringValue = "Custom"
        let editor = try f.edit()
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        _ = try XCTUnwrap(f.popup)
        f.update([4, 3, 2, 1, 0])
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(f.selection.wrappedValue, 4)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertNil(f.popup); XCTAssertNil(f.selection.wrappedValue)
        XCTAssertEqual(f.text.wrappedValue, "Custom"); XCTAssertEqual(editor.string, "Custom")
    }
    func testEditableUpWithNoMatchingOptionStartsAtFirstItem() throws {
        let f = try Fixture(mode: .editable, selected: nil); defer { f.window.close() }
        f.field.stringValue = "Custom"
        let editor = try f.edit()
        editor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        _ = try XCTUnwrap(f.popup)
        editor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(f.selection.wrappedValue, 0)
    }
    func testMarkedTextRetainsNativeCommandOwnership() throws {
        let f = try Fixture(mode: .editable); defer { f.window.close() }
        let editor = try f.edit()
        editor.setMarkedText("pin", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        let delegate = try XCTUnwrap(f.field.delegate)
        for selector in [#selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)),
                         #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            XCTAssertFalse(delegate.control?(f.field, textView: editor, doCommandBy: selector) ?? false)
        }
        XCTAssertFalse(f.field.performKeyEquivalent(with: event(118, window: f.window)))
        XCTAssertNil(f.popup); XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.string, "pin")
    }
    func testEditableTabClosesPopupAndKeepsNativeTraversal() throws {
        for backwards in [false, true] {
            let f = try Fixture(mode: .editable); defer { f.window.close() }
            let editor = try f.edit()
            editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
            _ = try XCTUnwrap(f.popup)
            editor.doCommand(by: backwards ? #selector(NSResponder.insertBacktab(_:)) : #selector(NSResponder.insertTab(_:)))
            XCTAssertNil(f.popup)
            let target = backwards ? f.before : f.after
            XCTAssertTrue(f.window.firstResponder === target.currentEditor() || f.window.firstResponder === target)
        }
    }
}
