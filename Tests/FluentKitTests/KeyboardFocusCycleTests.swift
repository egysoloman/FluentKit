import AppKit
import XCTest
@testable import FluentKit

private final class RefuseFocusChange: NSObject, NSTextFieldDelegate {
    var attempts = 0
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        attempts += 1
        return false
    }
}

private final class TabCommandDelegate: NSObject, NSTextFieldDelegate {
    var consumesTab = false
    var commands: [Selector] = []
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        commands.append(commandSelector)
        return consumesTab
    }
}

final class KeyboardFocusCycleTests: XCTestCase {
    @MainActor private func window(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = true
        window.contentView = view; window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
        return window
    }
    @MainActor private func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
    @MainActor private func focusState(_ w: NSWindow, _ root: NSView) -> String {
        let controls = all(root).compactMap { $0 as? NSButton }.map {
            "\($0.title): frame=\($0.frame) visible=\($0.visibleRect) accepts=\($0.acceptsFirstResponder) key=\($0.canBecomeKeyView) enabled=\($0.isEnabled) hidden=\($0.isHiddenOrHasHiddenAncestor)"
        }
        return "fullKeyboard=\(NSApp.isFullKeyboardAccessEnabled) active=\(NSApp.isActive) responder=\(String(describing: w.firstResponder)); \(controls.joined(separator: "; "))"
    }
    @MainActor private func tab(_ window: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\t",
            charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
    }

    @MainActor func testScopeKeepsLogicalOrderAfterInsertionAndWindowRecalculation() throws {
        func page(_ names: [String]) -> some FluentView {
            FluentVStack {
                FluentVStack { FluentForEach(names, id: \.self) { FluentButtonView($0) } }.fluentFocusScope()
                FluentButtonView("Outside")
            }
        }
        let root = FluentViewHost(page(["A", "B"])); let w = window(root); defer { w.close() }
        root.update(page(["A", "C", "B"])); root.layoutSubtreeIfNeeded(); w.recalculateKeyViewLoop()
        let buttons = all(root).compactMap { $0 as? FluentButton }
        func button(_ title: String) -> FluentButton { buttons.first { $0.title == title }! }
        w.makeFirstResponder(button("B"))
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(w.firstResponder === button("A"), focusState(w, root))
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(w.firstResponder === button("C"), focusState(w, root))
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w, flags: .shift)))
        XCTAssertTrue(w.firstResponder === button("A"), focusState(w, root))
        w.makeFirstResponder(button("Outside"))
        XCTAssertNotNil(FluentFocusVisibility.handleKeyDown(tab(w)))
    }

    @MainActor func testNestedScopeAndUnavailableControlsDoNotLeakFocus() throws {
        let root = FluentViewHost(FluentVStack {
            FluentButtonView("Outer")
            FluentHStack {
                FluentButtonView("A"); FluentButtonView("Disabled"); FluentButtonView("Hidden"); FluentButtonView("B")
            }.fluentFocusScope()
        }.fluentFocusScope())
        let w = window(root); defer { w.close() }
        let buttons = all(root).compactMap { $0 as? FluentButton }
        func b(_ title: String) -> FluentButton { buttons.first { $0.title == title }! }
        b("Disabled").isEnabled = false; b("Hidden").isHidden = true
        w.makeFirstResponder(b("A")); w.recalculateKeyViewLoop()
        FluentInputDeviceTracker.shared.record(.touch, in: w)
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(w.firstResponder === b("B"), focusState(w, root))
        XCTAssertEqual(FluentInputDeviceTracker.shared.lastDeviceType(in: w), .keyboard)
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(w.firstResponder === b("A"), focusState(w, root))
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w, flags: .shift)))
        XCTAssertTrue(w.firstResponder === b("B"), focusState(w, root))
        for flag: NSEvent.ModifierFlags in [.command, .control, .option] {
            XCTAssertNotNil(FluentFocusVisibility.handleKeyDown(tab(w, flags: flag)))
            XCTAssertTrue(w.firstResponder === b("B"), focusState(w, root))
        }
    }

    @MainActor func testFieldEditorRoutesThroughItsControlAndKeepsMarkedText() throws {
        let first = NSTextField(string: "First"), second = NSTextField(string: "Second")
        let root = FluentViewHost(FluentVStack { FluentNativeView(first); FluentNativeView(second) }.fluentFocusScope())
        let w = window(root); defer { w.close() }
        w.makeFirstResponder(first)
        let commands = TabCommandDelegate(); first.delegate = commands
        commands.consumesTab = true
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(first.currentEditor() === w.firstResponder)
        commands.consumesTab = false
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(second.currentEditor() === w.firstResponder)
        XCTAssertEqual(commands.commands, [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertTab(_:))])
        let editor = try XCTUnwrap(w.firstResponder as? NSTextView)
        editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertNotNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(w.firstResponder === editor); XCTAssertTrue(editor.hasMarkedText())
        editor.unmarkText()
        let veto = RefuseFocusChange(); second.delegate = veto
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(second.currentEditor() === w.firstResponder)
        XCTAssertGreaterThan(veto.attempts, 0)
        second.delegate = nil
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(first.currentEditor() === w.firstResponder)
    }

    @MainActor func testContentDialogTrapsTabAfterAutomaticLoopRecalculation() throws {
        let shown = FluentState(wrappedValue: false)
        let root = FluentViewHost(FluentButtonView("Outside").contentDialog("Dialog", isPresented: shown.projectedValue,
            primaryButtonText: "OK", closeButtonText: "Cancel") { FluentButtonView("Inside") },
            context: .init(reduceMotion: true))
        let w = window(root); defer { w.close() }
        shown.wrappedValue = true
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)); root.layoutSubtreeIfNeeded()
        let buttons = all(root).compactMap { $0 as? FluentButton }
        let cancel = try XCTUnwrap(buttons.first { $0.title == "Cancel" })
        let inside = try XCTUnwrap(buttons.first { $0.title == "Inside" })
        w.makeFirstResponder(cancel); w.recalculateKeyViewLoop()
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertTrue(w.firstResponder === inside, focusState(w, root))
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w, flags: .shift)))
        XCTAssertTrue(w.firstResponder === cancel, focusState(w, root))
    }

    @MainActor func testScopeLetsAutoSuggestRestoreQueryBeforeTabMovesFocus() throws {
        let query = FluentState(wrappedValue: "")
        func page(_ note: String) -> some FluentView {
            FluentVStack {
                FluentText(note)
                FluentAutoSuggestBox(query.projectedValue, suggestions: { _ in
                    [FluentAutoSuggestBoxSuggestion(id: "apple", title: "Apple"),
                     FluentAutoSuggestBoxSuggestion(id: "apricot", title: "Apricot")]
                })
                FluentButtonView("After")
            }.fluentFocusScope()
        }
        let root = FluentViewHost(page("Before"), context: .init(reduceMotion: true))
        let w = window(root); defer { w.close() }
        let field = try XCTUnwrap(all(root).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as? NSTextField)
        w.makeFirstResponder(field); field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
        waitForUI(w.childWindows?.first?.isVisible == true)
        let popup = try XCTUnwrap(w.childWindows?.first)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(query.wrappedValue, "Apple")
        root.update(page("Refreshed"))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(query.wrappedValue, "Apple")
        XCTAssertNil(FluentFocusVisibility.handleKeyDown(tab(w)))
        XCTAssertEqual(query.wrappedValue, "Ap")
        XCTAssertEqual(field.stringValue, "Ap")
        XCTAssertFalse(popup.isVisible)
        XCTAssertFalse(w.firstResponder === editor)
    }
}
