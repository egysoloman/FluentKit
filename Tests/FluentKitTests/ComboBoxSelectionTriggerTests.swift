import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxSelectionTriggerTests: XCTestCase {
    @MainActor private final class Fixture {
        let selection = FluentState<Int?>(wrappedValue: 1)
        let text = FluentState(wrappedValue: "Option 1")
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<Int>>
        let field: NSTextField
        let bridge: NSComboBox
        let mode: FluentComboBoxMode
        var options = [0, 1, 2, 3]
        var trigger: FluentComboBoxSelectionChangedTrigger
        let bindsText: Bool
        init(_ mode: FluentComboBoxMode = .selection, trigger: FluentComboBoxSelectionChangedTrigger = .committed,
             bindsText: Bool = true) throws {
            _ = NSApplication.shared
            self.mode = mode
            self.trigger = trigger
            self.bindsText = bindsText
            host = FluentViewHost(FluentComboBox(options: options, selection: selection.projectedValue,
                mode: mode, text: mode == .editable && bindsText ? text.projectedValue : nil, title: { "Option \($0)" })
                .selectionChangedTrigger(trigger).textFieldStyle(FluentAutomaticTextFieldStyle()),
                context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 600, height: 350),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 80, y: 180, width: 280, height: 32)
            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
            func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
            field = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            bridge = try XCTUnwrap(all(host).compactMap { $0 as? NSComboBox }.first)
        }
        var popup: NSWindow? { window.childWindows?.first { $0.isVisible } }
        func open() throws -> NSWindow {
            bridge.performClick(nil)
            return try XCTUnwrap(popup)
        }
        func update(_ options: [Int]? = nil) {
            if let options { self.options = options }
            host.update(FluentComboBox(options: self.options, selection: selection.projectedValue,
                mode: mode, text: mode == .editable && bindsText ? text.projectedValue : nil, title: { "Option \($0)" })
                .selectionChangedTrigger(trigger),
                context: .init(theme: .custom(colorScheme: .dark), reduceMotion: true))
        }
    }
    private func key(_ code: UInt16, _ f: Fixture) {
        let target = f.mode == .editable ? f.window : f.popup ?? f.window
        let characters = code == 125 ? "\u{F701}" : code == 36 ? "\r" : code == 48 ? "\t" : code == 53 ? "\u{1b}" : ""
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: target.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        NSApp.sendEvent(event)
    }
    private func rows(_ f: Fixture) -> [NSView] {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return f.popup?.contentView.map { all($0).filter { $0.accessibilityRole() == .menuItem } } ?? []
    }
    private func drain() async {
        for _ in 0..<5 { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } } }
    }
    func testDefaultPopupNavigationPreviewsUntilReturnInBothModes() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try Fixture(mode); defer { f.window.close() }
            _ = try f.open(); key(125, f)
            XCTAssertEqual(f.selection.wrappedValue, 1)
            XCTAssertEqual(rows(f).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() }, ["Option 1"])
            if mode == .editable { XCTAssertEqual(f.field.stringValue, "Option 2") }
            key(36, f)
            XCTAssertEqual(f.selection.wrappedValue, 2); XCTAssertNil(f.popup)
        }
    }
    func testSelectionDismissalDiscardsPreviewButEditableDismissalCommits() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            for code: UInt16 in [118, 48] {
                let f = try Fixture(mode); defer { f.window.close() }
                _ = try f.open(); key(125, f); key(code, f)
                XCTAssertNil(f.popup)
                XCTAssertEqual(f.selection.wrappedValue, mode == .editable ? 2 : 1)
            }
        }
    }
    func testEscapeCancelsPreviewWithoutPublishingIt() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try Fixture(mode); defer { f.window.close() }
            var writes: [Int?] = []
            let observer = f.selection.projectedValue.observe { writes.append($0) }
            defer { if let observer { f.selection.projectedValue.removeObserver(observer) } }
            _ = try f.open(); key(125, f); key(53, f)
            XCTAssertTrue(writes.isEmpty); XCTAssertEqual(f.selection.wrappedValue, 1)
            if mode == .editable { XCTAssertEqual(f.field.stringValue, "Option 1") }
        }
    }
    func testPreviewSurvivesThemeAndReorderThenCommitsStableOption() throws {
        let f = try Fixture(); defer { f.window.close() }
        let popup = try f.open(); key(125, f)
        f.update([3, 2, 0, 1])
        XCTAssertTrue(f.popup === popup); XCTAssertEqual(f.selection.wrappedValue, 1)
        XCTAssertEqual(rows(f).filter { $0.isAccessibilityFocused() }.compactMap { $0.accessibilityTitle() }, ["Option 2"])
        key(36, f); XCTAssertEqual(f.selection.wrappedValue, 2)
    }
    func testExternalSelectionReplacesCancellationBaseline() throws {
        let f = try Fixture(); defer { f.window.close() }
        _ = try f.open(); key(125, f)
        f.selection.wrappedValue = 3
        key(53, f); XCTAssertEqual(f.selection.wrappedValue, 3)
    }
    func testExternalTextResetReplacesEditableCancellationBaseline() throws {
        let f = try Fixture(.editable); defer { f.window.close() }
        _ = try f.open(); key(125, f)
        f.text.wrappedValue = "external reset"
        key(53, f)
        XCTAssertEqual(f.text.wrappedValue, "external reset"); XCTAssertEqual(f.field.stringValue, "external reset")
        XCTAssertNil(f.selection.wrappedValue)
    }
    func testTypedExactValueDefersSelectionUntilReturnOrBlur() async throws {
        for blur in [false, true] {
            let f = try Fixture(.editable); defer { f.window.close() }
            f.field.selectText(nil)
            let editor = try XCTUnwrap(f.field.currentEditor() as? NSTextView)
            editor.insertText("Option 3", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            await drain()
            XCTAssertEqual(f.text.wrappedValue, "Option 3"); XCTAssertEqual(f.selection.wrappedValue, 1)
            if blur { f.window.makeFirstResponder(nil) } else { key(36, f) }
            await drain(); XCTAssertEqual(f.selection.wrappedValue, 3)
        }
    }
    func testHidingControlDoesNotCommitNavigationPreview() throws {
        let f = try Fixture(); defer { f.window.close() }
        _ = try f.open(); key(125, f)
        f.host.subviews.first?.isHidden = true
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 1)
    }

    func testAlwaysPublishesNavigationAndEscapeRestoresBaselineInBothModes() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try Fixture(mode, trigger: .always); defer { f.window.close() }
            _ = try f.open(); key(125, f)
            XCTAssertEqual(f.selection.wrappedValue, 2)
            key(53, f); XCTAssertEqual(f.selection.wrappedValue, 1)
        }
    }

    func testEmptySelectionOpeningUsesTriggerPolicy() throws {
        for trigger in [FluentComboBoxSelectionChangedTrigger.committed, .always] {
            let f = try Fixture(trigger: trigger); defer { f.window.close() }
            f.selection.wrappedValue = nil
            _ = try f.open()
            XCTAssertEqual(f.selection.wrappedValue, trigger == .always ? 0 : nil)
            key(36, f); XCTAssertEqual(f.selection.wrappedValue, 0)
        }
    }

    func testEditableWithoutTextBindingPreviewsAndCommitsWithoutReplacingEditor() throws {
        let f = try Fixture(.editable, bindsText: false); defer { f.window.close() }
        _ = try f.open()
        let editor = try XCTUnwrap(f.field.currentEditor() as? NSTextView)
        key(125, f)
        XCTAssertEqual(editor.string, "Option 2"); XCTAssertEqual(f.selection.wrappedValue, 1)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 8))
        key(36, f)
        XCTAssertEqual(f.selection.wrappedValue, 2); XCTAssertTrue(f.field.currentEditor() === editor)
    }

    func testOutsideClickClosesWithModeSpecificCommit() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = try Fixture(mode); defer { f.window.close() }
            _ = try f.open(); key(125, f)
            NSApp.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 470, y: 40),
                modifierFlags: [], timestamp: 0, windowNumber: f.window.windowNumber, context: nil,
                eventNumber: 22, clickCount: 1, pressure: 1)!)
            XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, mode == .editable ? 2 : 1)
        }
    }

    func testExternalSelectionReplacesEditablePreviewAndCancellationBaseline() throws {
        let f = try Fixture(.editable); defer { f.window.close() }
        _ = try f.open(); key(125, f)
        f.selection.wrappedValue = 3
        XCTAssertEqual(f.field.stringValue, "Option 3"); XCTAssertEqual(f.text.wrappedValue, "Option 3")
        key(53, f); XCTAssertEqual(f.selection.wrappedValue, 3); XCTAssertEqual(f.field.stringValue, "Option 3")
    }

    func testLiveTriggerChangePreservesPopupAndOnlyChangesSubsequentNavigation() throws {
        let f = try Fixture(); defer { f.window.close() }
        let panel = try f.open(); key(125, f)
        f.trigger = .always; f.update()
        XCTAssertTrue(f.popup === panel); XCTAssertEqual(f.selection.wrappedValue, 1)
        key(125, f); XCTAssertEqual(f.selection.wrappedValue, 3)
        f.trigger = .committed; f.update(); key(125, f)
        XCTAssertEqual(f.selection.wrappedValue, 3)
        key(53, f); XCTAssertEqual(f.selection.wrappedValue, 1)
    }

    func testExplicitRowCommitSurvivesReentrantReorderAndReopening() throws {
        let f = try Fixture(); defer { f.window.close() }
        var changed = false
        let id = f.selection.projectedValue.observe { value in
            guard value == 2, !changed else { return }
            changed = true
            f.update([3, 2, 0, 1])
            f.bridge.performClick(nil)
            f.bridge.performClick(nil)
        }
        defer { if let id { f.selection.projectedValue.removeObserver(id) } }
        let original = try f.open()
        XCTAssertTrue(try XCTUnwrap(rows(f).first { $0.accessibilityTitle() == "Option 2" }).accessibilityPerformPress())
        XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertNotNil(f.popup); XCTAssertFalse(f.popup === original)
    }

    func testMarkedTextNeverCommitsASelectionBeforeNativeCompositionEnds() async throws {
        let f = try Fixture(.editable); defer { f.window.close() }
        _ = try f.open()
        let editor = try XCTUnwrap(f.field.currentEditor() as? NSTextView)
        editor.setMarkedText("Option 3", selectedRange: NSRange(location: 8, length: 0),
            replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.didChangeText(); await drain()
        XCTAssertEqual(f.selection.wrappedValue, 1)
        XCTAssertFalse(f.field.delegate?.control?(f.field, textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))) ?? true)
        XCTAssertTrue(editor.hasMarkedText())
        editor.unmarkText(); editor.didChangeText(); await drain()
        XCTAssertEqual(f.selection.wrappedValue, 1)
        key(36, f); XCTAssertEqual(f.selection.wrappedValue, 3)
    }

    func testRenamedEditablePreviewCommitsStableValueOnToggleWithOrWithoutTextBinding() throws {
        for bindsText in [false, true] {
            let f = try Fixture(.editable, bindsText: bindsText); defer { f.window.close() }
            _ = try f.open(); key(125, f)
            f.host.update(FluentComboBox(options: [3, 2, 0, 1], selection: f.selection.projectedValue,
                mode: .editable, text: bindsText ? f.text.projectedValue : nil, title: { "Renamed \($0)" }),
                context: .init(reduceMotion: true))
            key(118, f)
            XCTAssertEqual(f.selection.wrappedValue, 2); XCTAssertEqual(f.field.stringValue, "Renamed 2")
        }
    }

    func testReplacingSelectionBindingWhileOpenCancelsOldPreviewBaseline() throws {
        let f = try Fixture(); defer { f.window.close() }
        let other = FluentState<Int?>(wrappedValue: 3)
        let panel = try f.open(); key(125, f)
        f.host.update(FluentComboBox(options: f.options, selection: other.projectedValue,
            title: { "Option \($0)" }), context: .init(reduceMotion: true))
        XCTAssertTrue(f.popup === panel)
        key(53, f)
        XCTAssertEqual(other.wrappedValue, 3); XCTAssertEqual(f.selection.wrappedValue, 1)
    }

    func testAlwaysCallbackCanReplaceBindingWithoutKeepingOldCancelBaseline() throws {
        for replacement in [2, 3] {
            let f = try Fixture(trigger: .always); defer { f.window.close() }
            let other = FluentState<Int?>(wrappedValue: replacement)
            let id = f.selection.projectedValue.observe { value in
                guard value == 2 else { return }
                f.host.update(FluentComboBox(options: f.options, selection: other.projectedValue,
                    title: { "Option \($0)" }).selectionChangedTrigger(.always), context: .init(reduceMotion: true))
            }
            defer { if let id { f.selection.projectedValue.removeObserver(id) } }
            _ = try f.open(); key(125, f)
            XCTAssertEqual(rows(f).filter { $0.isAccessibilityFocused() }.compactMap { $0.accessibilityTitle() }, ["Option \(replacement)"])
            key(53, f)
            XCTAssertEqual(other.wrappedValue, replacement)
        }
    }

    func testExternalSelectionDuringCompositionWaitsAndWinsAfterCommit() async throws {
        for (bindsText, opensPopup) in [(false, false), (false, true), (true, false), (true, true)] {
            let f = try Fixture(.editable, bindsText: bindsText); defer { f.window.close() }
            if opensPopup { _ = try f.open() } else { f.field.selectText(nil) }
            let editor = try XCTUnwrap(f.field.currentEditor() as? NSTextView)
            editor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0),
                replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            editor.didChangeText(); await drain()
            f.selection.wrappedValue = 3
            XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.string, "pin")
            editor.unmarkText(); editor.didChangeText(); await drain()
            XCTAssertEqual(editor.string, "Option 3"); XCTAssertEqual(f.selection.wrappedValue, 3)
            if opensPopup { key(53, f) }
            XCTAssertEqual(editor.string, "Option 3"); XCTAssertEqual(f.selection.wrappedValue, 3)
        }
    }
}
