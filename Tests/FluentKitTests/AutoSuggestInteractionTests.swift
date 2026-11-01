import XCTest
@testable import FluentKit

final class AutoSuggestInteractionTests: XCTestCase {
    @MainActor private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @MainActor private func field(_ root: NSView) throws -> NSTextField {
        try XCTUnwrap(all(root).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as? NSTextField)
    }
    @MainActor private func mount(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 400, width: 460, height: 160),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 160))
        window.contentView = stage; stage.addSubview(view)
        view.frame = NSRect(x: 20, y: 40, width: 300, height: view.intrinsicContentSize.height)
        window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
        return window
    }
    @MainActor private func type(_ text: String, in root: NSView, wait: Bool = true) throws -> NSTextView {
        let field = try field(root)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        if wait { waitForUI(root.window?.childWindows?.first?.isVisible == true) }
        return editor
    }
    private var values: [FluentAutoSuggestBoxSuggestion] {
        (0..<20).map { FluentAutoSuggestBoxSuggestion(id: $0, title: "Apple \($0)", subtitle: "Fruit", systemImageName: "leaf") }
    }

    @MainActor func testEscapeRestoresOriginalQueryAndBindingImmediately() throws {
        let state = FluentState(wrappedValue: "")
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in self.values })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(state.wrappedValue, "Apple 0")
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(try field(view).stringValue, "Ap")
        XCTAssertEqual(state.wrappedValue, "Ap")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(try field(view).stringValue, "Ap", "Closed suggestions must not be navigated")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testCancellationRestoresQueryAfterSelectedSuggestionReplacement() throws {
        for removesSelectedItem in [false, true] {
            for command in [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)), #selector(NSResponder.cancelOperation(_:))] {
                let state = FluentState(wrappedValue: "")
                var values = [FluentAutoSuggestBoxSuggestion(id: 1, title: "Apple"), .init(id: 2, title: "Apricot")]
                var events: [FluentAutoSuggestBoxTextChangedEvent] = []
                func content() -> FluentAutoSuggestBox {
                    FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in values }, onTextChangedEvent: { events.append($0) })
                }
                let view = content()._makeView(in: .init(reduceMotion: true))
                let window = mount(view); defer { window.close() }
                let editor = try type("Ap", in: view)
                editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
                XCTAssertEqual(state.wrappedValue, "Apple")
                values = removesSelectedItem ? [.init(id: 2, title: "Apricot")] : [.init(id: 3, title: "Apple"), .init(id: 4, title: "Apricot")]
                XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true)))
                let popup = try XCTUnwrap(window.childWindows?.first)
                XCTAssertTrue(popup.isVisible)
                XCTAssertFalse(all(popup.contentView!).contains { $0.isAccessibilitySelected() })
                editor.doCommand(by: command)
                XCTAssertEqual(state.wrappedValue, "Ap", "\(command), remove=\(removesSelectedItem)")
                XCTAssertEqual(try field(view).stringValue, "Ap")
                XCTAssertFalse(popup.isVisible)
                waitForUI(events.last?.reason == .programmaticChange)
                XCTAssertEqual(events.last?.reason, .programmaticChange)
                XCTAssertEqual(events.last?.text, "Ap")
            }
        }
    }

    @MainActor func testClosedSuggestionsOnlyEscapeRestoresOriginalQuery() throws {
        for escape in [false, true] {
            let state = FluentState(wrappedValue: "")
            var values = [FluentAutoSuggestBoxSuggestion(id: 1, title: "Apple")]
            func content() -> FluentAutoSuggestBox { FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in values }) }
            let view = content()._makeView(in: .init(reduceMotion: true))
            let window = mount(view); defer { window.close() }
            let editor = try type("Ap", in: view)
            editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
            values = []
            XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true)))
            XCTAssertTrue(window.childWindows?.isEmpty ?? true)
            editor.doCommand(by: escape ? #selector(NSResponder.cancelOperation(_:)) : #selector(NSResponder.insertTab(_:)))
            XCTAssertEqual(state.wrappedValue, escape ? "Ap" : "Apple")
            XCTAssertEqual(try field(view).stringValue, escape ? "Ap" : "Apple")
        }
    }

    @MainActor func testHelperButtonsSkipTabButRetainActionsAndEditingFocus() throws {
        let state = FluentState(wrappedValue: "")
        var submitted: String?
        let root = FluentViewHost(FluentVStack {
            FluentAutoSuggestBox(state.projectedValue, querySystemImageName: "magnifyingglass", onSubmit: { text, _ in submitted = text })
            FluentButtonView("After")
        })
        let window = mount(root); defer { window.close() }
        // A composite FluentViewHost has no intrinsic height; give the whole stack a
        // visible frame instead of the single-control helper's intrinsic-size frame.
        root.frame = NSRect(x: 20, y: 5, width: 400, height: 150)
        root.layoutSubtreeIfNeeded()
        window.autorecalculatesKeyViewLoop = true
        let editor = try type("Ap", in: root, wait: false)
        let after = try XCTUnwrap(all(root).compactMap { $0 as? FluentButton }.first { $0.title == "After" })
        let clear = try XCTUnwrap(all(root).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.ClearButton" } as? NSButton)
        let query = try XCTUnwrap(all(root).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.QueryButton" } as? NSButton)
        for button in [clear, query] {
            XCTAssertFalse(button.canBecomeKeyView)
        }
        XCTAssertTrue(after.canBecomeKeyView, "frame=\(after.frame) visible=\(after.visibleRect) accepts=\(after.acceptsFirstResponder) fullKeyboard=\(NSApp.isFullKeyboardAccessEnabled)")
        let currentField = try field(root)
        window.recalculateKeyViewLoop()
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertTrue(window.firstResponder === after, "actual=\(String(describing: window.firstResponder)); next=\(String(describing: currentField.nextValidKeyView)); after=\(after)")
        window.selectPreviousKeyView(nil)
        XCTAssertTrue(try field(root).currentEditor() === window.firstResponder)
        query.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(submitted, "Ap")
        clear.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(state.wrappedValue, "")
        XCTAssertTrue(try field(root).currentEditor() === editor)
    }

    @MainActor func testSuggestionViewportScrollsToKeyboardSelection() throws {
        let state = FluentState(wrappedValue: "")
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in self.values }, maxSuggestionListHeight: 84)._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        let popup = try XCTUnwrap(window.childWindows?.first)
        for _ in 0..<20 { editor.doCommand(by: #selector(NSResponder.moveDown(_:))) }
        let root = try XCTUnwrap(popup.contentView)
        let row = try XCTUnwrap(all(root).first { $0.accessibilityLabel() == "Apple 19" })
        XCTAssertTrue(row.isAccessibilitySelected())
        XCTAssertGreaterThan(row.visibleRect.height, 39)
        let scroll = try XCTUnwrap(all(root).first { $0 is NSScrollView } as? NSScrollView)
        XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 600)
        XCTAssertTrue(window.firstResponder === editor)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(state.wrappedValue, "Ap")
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.5)
    }

    @MainActor func testHeaderAndRTLAdornmentsFitInsideTheirBounds() throws {
        let state = FluentState(wrappedValue: "")
        let view = FluentAutoSuggestBox(state.projectedValue, header: "Search fruit", querySystemImageName: "magnifyingglass")._makeView(in: .init(reduceMotion: true, layoutDirection: .rightToLeft))
        view.fluentApplyLayoutDirection(.rightToLeft)
        let window = mount(view); defer { window.close() }
        _ = try type("Ap", in: view, wait: false)
        view.layoutSubtreeIfNeeded()
        let header = try XCTUnwrap(all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Header" })
        let query = try XCTUnwrap(all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.QueryButton" })
        let clear = try XCTUnwrap(all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.ClearButton" })
        XCTAssertTrue(view.bounds.contains(header.frame))
        XCTAssertEqual(query.frame.minX, 4, accuracy: 0.01)
        XCTAssertEqual(clear.frame.minX, query.frame.maxX + 2, accuracy: 0.01)
        let textField = try field(view)
        let editor = try XCTUnwrap(textField.currentEditor())
        let editRect = editor.convert(editor.visibleRect, to: textField)
        XCTAssertGreaterThanOrEqual(editRect.minX, clear.frame.maxX)
    }

    @MainActor func testExternalResetInvalidatesSelectionAndClosesOldSuggestions() throws {
        let state = FluentState(wrappedValue: "")
        var chosen: String?
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { query in query.isEmpty ? [] : self.values },
            onSubmit: { _, item in chosen = item?.title })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        state.wrappedValue = ""
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(try field(view).stringValue, "")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertNil(chosen)
        XCTAssertEqual(state.wrappedValue, "")
        state.wrappedValue = "Pear"
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(state.wrappedValue, "Pear", "Cancellation must preserve a subsequent external reset")
        XCTAssertEqual(try field(view).stringValue, "Pear")
    }

    @MainActor func testLiveProviderUpdatePreservesSelectedIDAndResizesFromAnchor() throws {
        let state = FluentState(wrappedValue: "")
        var values = Array(self.values.prefix(2))
        var maxHeight: CGFloat = 84
        func content() -> FluentAutoSuggestBox { FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in values }, maxSuggestionListHeight: maxHeight) }
        let view = content()._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        let panel = try XCTUnwrap(window.childWindows?.first)
        let first = try XCTUnwrap(all(panel.contentView!).first { $0.accessibilityLabel() == "Apple 0" })
        values = Array(self.values.reversed()); maxHeight = 164
        XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true)))
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual(panel.frame.height, 164, accuracy: 0.5)
        XCTAssertTrue(all(panel.contentView!).contains { $0 === first })
        XCTAssertTrue(first.isAccessibilitySelected())
        let anchor = window.convertToScreen(try field(view).convert(try field(view).bounds, to: nil))
        XCTAssertEqual(panel.frame.maxY, anchor.minY - 2, accuracy: 0.5)
    }

    @MainActor func testZeroMaximumHidesSuggestionsAndNegativeUsesAvailableSpace() throws {
        let state = FluentState(wrappedValue: "")
        var requested = false
        func content(_ height: CGFloat) -> FluentAutoSuggestBox {
            FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in requested = true; return self.values }, maxSuggestionListHeight: height)
        }
        let view = content(0)._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        _ = try type("Ap", in: view, wait: false)
        waitForUI(requested)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        XCTAssertTrue(content(-1)._updateView(view, in: .init(reduceMotion: true)))
        let popup = try XCTUnwrap(window.childWindows?.first)
        XCTAssertLessThanOrEqual(popup.frame.height, window.screen!.visibleFrame.height)
        XCTAssertTrue(window.screen!.visibleFrame.contains(popup.frame))
    }

    @MainActor func testEscapeDuringDebounceDoesNotReopenAndDetachClosesPanel() throws {
        let state = FluentState(wrappedValue: "")
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in self.values })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view, wait: false)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        _ = try type("App", in: view)
        XCTAssertFalse(window.childWindows?.isEmpty ?? true)
        view.removeFromSuperview()
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testTextChangeReasonsAreDebouncedAndCallbacksSupplyCurrentResults() throws {
        let state = FluentState(wrappedValue: "")
        var events: [FluentAutoSuggestBoxTextChangedEvent] = []
        var values: [FluentAutoSuggestBoxSuggestion] = []
        var queries: [String] = []
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { query in queries.append(query); return values },
            onTextChangedEvent: { event in
                events.append(event)
                if event.reason == .userInput { values = [FluentAutoSuggestBoxSuggestion(id: 1, title: "Apple")] }
            })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        XCTAssertEqual(events.map(\.reason), [.userInput])
        XCTAssertEqual(queries, ["Ap"])
        XCTAssertFalse(window.childWindows?.isEmpty ?? true)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        waitForUI(events.last?.reason == .suggestionChosen)
        XCTAssertEqual(events.map(\.reason), [.userInput, .suggestionChosen])
        XCTAssertEqual(events.last?.text, "Apple")
        XCTAssertEqual(queries, ["Ap"], "Previewing must not re-filter by the candidate title")
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        waitForUI(events.last?.reason == .programmaticChange)
        XCTAssertEqual(events.last?.reason, .programmaticChange)
        XCTAssertEqual(events.last?.text, "Ap")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        window.makeFirstResponder(nil)
        try field(view).selectText(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
        XCTAssertEqual(events.count, 3, "Focus alone is not a text change")
    }

    @MainActor func testSingleResultDoesNotCycleAndUpdateTextOnSelectCanBeDisabled() throws {
        let state = FluentState(wrappedValue: "")
        var chosen: [String] = []
        var submissions: [(String, String?)] = []
        let view = FluentAutoSuggestBox(state.projectedValue,
            suggestions: { _ in [FluentAutoSuggestBoxSuggestion(id: 1, title: "Apple")] }, updateTextOnSelect: false,
            onSuggestionChosen: { chosen.append($0.title) }, onSubmit: { submissions.append(($0, $1?.title)) })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        for _ in 0..<3 { editor.doCommand(by: #selector(NSResponder.moveDown(_:))) }
        editor.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(chosen, ["Apple"])
        XCTAssertEqual(state.wrappedValue, "Ap")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(submissions.last?.0, "Ap")
        XCTAssertEqual(submissions.last?.1, "Apple")
    }

    @MainActor func testBlurAndRefocusDoNotAdoptSuggestionPreviewAsTypedQuery() throws {
        let state = FluentState(wrappedValue: "")
        var queries: [String] = []
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { query in
            queries.append(query)
            return [.init(id: 1, title: "Apple"), .init(id: 2, title: "Apricot")]
        })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(state.wrappedValue, "Apple")
        XCTAssertTrue(window.makeFirstResponder(nil))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        try field(view).selectText(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
        let resumedEditor = try XCTUnwrap(try field(view).currentEditor() as? NSTextView)
        XCTAssertEqual(queries.last, "Ap", "Focus must not filter the list by a previewed suggestion")
        resumedEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(state.wrappedValue, "Ap")
        XCTAssertEqual(resumedEditor.string, "Ap")
    }

    @MainActor func testExternalResetRemainsCancellationBaselineAcrossFocusChanges() throws {
        for resetWhileFocused in [false, true] {
            let state = FluentState(wrappedValue: "")
            let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in self.values })
                ._makeView(in: .init(reduceMotion: true))
            let window = mount(view); defer { window.close() }
            let editor = try type("Ap", in: view)
            editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
            if resetWhileFocused { state.wrappedValue = "Pear" }
            XCTAssertTrue(window.makeFirstResponder(nil))
            if !resetWhileFocused { state.wrappedValue = "Pear" }
            try field(view).selectText(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
            let resumedEditor = try XCTUnwrap(try field(view).currentEditor() as? NSTextView)
            resumedEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            XCTAssertEqual(state.wrappedValue, "Pear")
            XCTAssertEqual(resumedEditor.string, "Pear")
        }
    }

    @MainActor func testSubmitSynchronizesUnobservedModelBeforeResolvingChosenSuggestion() throws {
        var model = ""
        var submitted: String?, chosen: FluentAutoSuggestBoxSuggestion?
        let binding = FluentBinding(get: { model }, set: { model = $0 })
        let view = FluentAutoSuggestBox(binding, suggestions: { _ in self.values },
            onSubmit: { submitted = $0; chosen = $1 })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(model, "Apple 0")
        // A closure binding can change before a declarative update observes it.
        model = "Pear"
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(submitted, "Pear")
        XCTAssertNil(chosen, "The external reset invalidates the previous selection")
        XCTAssertEqual(editor.string, "Pear")
    }

    @MainActor func testProviderCannotPublishResultsForQueryReplacedDuringItsCallback() throws {
        let state = FluentState(wrappedValue: "")
        var popupAfterOldProvider: Bool?
        var window: NSWindow!
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { query in
            if query == "Ap" {
                state.wrappedValue = "Pear"
                DispatchQueue.main.async {
                    popupAfterOldProvider = window.childWindows?.contains { $0.isVisible } ?? false
                }
                return [.init(id: 1, title: "Apple")]
            }
            return []
        })._makeView(in: .init(reduceMotion: true))
        window = mount(view); defer { window.close() }
        _ = try type("Ap", in: view, wait: false)
        waitForUI(popupAfterOldProvider != nil)
        XCTAssertEqual(state.wrappedValue, "Pear")
        XCTAssertEqual(popupAfterOldProvider, false, "Old results must not reopen over the new query")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor func testCompositionCancelsOldDebounceAndExternalResetWinsOnCommit() throws {
        let state = FluentState(wrappedValue: "")
        var events: [FluentAutoSuggestBoxTextChangedEvent] = []
        let view = FluentAutoSuggestBox(state.projectedValue.textInput(.init(commitPolicy: .committedText)),
            suggestions: { _ in self.values }, onTextChangedEvent: { events.append($0) })._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view, wait: false)
        editor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.didChangeText()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        state.wrappedValue = "reset"
        XCTAssertTrue(editor.hasMarkedText())
        editor.unmarkText(); editor.didChangeText()
        waitForUI(events.last?.text == "reset")
        XCTAssertEqual(editor.string, "reset")
        XCTAssertEqual(state.wrappedValue, "reset")
        XCTAssertEqual(events.last?.text, "reset")
        XCTAssertEqual(events.last?.reason, .programmaticChange)
    }

    @MainActor func testPopupTracksScrollingAncestor() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: "")
        let view = FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in Array(self.values.prefix(2)) }, maxSuggestionListHeight: 84)
            ._makeView(in: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 460, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
        document.addSubview(view); scroll.documentView = document
        view.frame = NSRect(x: 20, y: 120, width: 300, height: view.intrinsicContentSize.height)
        window.contentView!.addSubview(scroll); window.makeKeyAndOrderFront(nil)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        view.layoutSubtreeIfNeeded()
        _ = try type("Ap", in: view)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let field = try field(view)
        let previousAnchor = window.convertToScreen(field.convert(field.bounds, to: nil))
        let previousPopup = panel.frame
        let origin = scroll.contentView.bounds.origin
        scroll.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + 35))
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        let movedAnchor = window.convertToScreen(field.convert(field.bounds, to: nil))
        XCTAssertEqual(abs(movedAnchor.minY - previousAnchor.minY), 35, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY - previousPopup.minY, movedAnchor.minY - previousAnchor.minY, accuracy: 0.5)
        let beforeParentMove = panel.frame
        scroll.setFrameOrigin(NSPoint(x: scroll.frame.minX + 15, y: scroll.frame.minY + 7))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(panel.frame.minX - beforeParentMove.minX, 15, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY - beforeParentMove.minY, 7, accuracy: 0.5)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(window.childWindows?.count ?? 0, 0, "A fully clipped input must not leave detached suggestions")
        scroll.contentView.scroll(to: .zero)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(window.childWindows?.count ?? 0, 0, "Scrolling back must not reopen stale suggestions")
        _ = try type("App", in: view)
        let reopened = try XCTUnwrap(window.childWindows?.first)
        let currentAnchor = window.convertToScreen(field.convert(field.bounds, to: nil))
        XCTAssertEqual(currentAnchor.minY - reopened.frame.maxY, 2, accuracy: 0.5)
        XCTAssertEqual(reopened.frame.minX, currentAnchor.minX, accuracy: 0.5)
    }

    @MainActor func testPopupMovesWithAnchorResizesItsClipAndFlipsInsideScreen() throws {
        let state = FluentState(wrappedValue: "")
        var count = 2
        func content() -> FluentAutoSuggestBox {
            FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in Array(self.values.prefix(count)) }, maxSuggestionListHeight: 164)
        }
        let view = content()._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        _ = try type("Ap", in: view)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let old = panel.frame.origin
        view.setFrameOrigin(NSPoint(x: view.frame.minX + 35, y: view.frame.minY + 10))
        XCTAssertEqual(panel.frame.origin.x, old.x + 35, accuracy: 0.5)
        XCTAssertEqual(panel.frame.origin.y, old.y + 10, accuracy: 0.5)
        count = 20
        XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true)))
        let root = try XCTUnwrap(panel.contentView)
        root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
        func mask(_ layer: CALayer) -> CALayer? {
            if let mask = layer.mask, mask.name?.hasSuffix("RevealClip") == true { return mask }
            return layer.sublayers?.compactMap(mask).first
        }
        XCTAssertTrue(try XCTUnwrap(mask(try XCTUnwrap(root.layer))).frame.contains(root.bounds))
        let visible = try XCTUnwrap(window.screen).visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.minX + 30, y: visible.minY + 2))
        view.layoutSubtreeIfNeeded()
        let anchor = window.convertToScreen(try field(view).convert(try field(view).bounds, to: nil))
        XCTAssertEqual(panel.frame.minY, anchor.maxY + 2, accuracy: 0.5)
        XCTAssertTrue(visible.contains(panel.frame))
    }

    @MainActor func testRemovedAndClosedSuggestionRowsCannotInvokeLater() throws {
        let state = FluentState(wrappedValue: "")
        var values = self.values
        var submissions = 0
        func content() -> FluentAutoSuggestBox {
            FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in values }, onSubmit: { _, _ in submissions += 1 })
        }
        let view = content()._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        _ = try type("Ap", in: view)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let row = try XCTUnwrap(all(panel.contentView!).first { $0.accessibilityLabel() == "Apple 0" })
        values.removeFirst()
        XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true)))
        XCTAssertFalse(row.accessibilityPerformPress())
        let current = try XCTUnwrap(all(panel.contentView!).first { $0.accessibilityLabel() == "Apple 1" })
        window.close()
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        XCTAssertFalse(current.accessibilityPerformPress())
        XCTAssertEqual(submissions, 0)
    }


    @MainActor func testDirectionChangeWhileEditingKeepsEditorSelectionAndPopup() throws {
        let state = FluentState(wrappedValue: "")
        let auto = FluentAutoSuggestBox(state.projectedValue, querySystemImageName: "magnifyingglass", suggestions: { _ in self.values })
        let view = auto._makeView(in: .init(reduceMotion: true, layoutDirection: .leftToRight))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        let popup = try XCTUnwrap(window.childWindows?.first)
        XCTAssertTrue(auto._updateView(view, in: .init(reduceMotion: true, layoutDirection: .rightToLeft)))
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(try field(view).currentEditor() === editor)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertTrue(window.childWindows?.first === popup)
        XCTAssertEqual(editor.alignment, .right)
        XCTAssertTrue(all(popup.contentView!).contains { $0.accessibilityLabel() == "Apple 0" && $0.isAccessibilitySelected() })
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(state.wrappedValue, "Ap")
    }


    @MainActor func testUnchangedRefreshPreservesManualScrollButResizeRevealsSelection() throws {
        let state = FluentState(wrappedValue: "")
        var height: CGFloat = 164
        func content() -> FluentAutoSuggestBox {
            FluentAutoSuggestBox(state.projectedValue, suggestions: { _ in self.values }, maxSuggestionListHeight: height)
        }
        let view = content()._makeView(in: .init(reduceMotion: true))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        for _ in 0..<10 { editor.doCommand(by: #selector(NSResponder.moveDown(_:))) }
        let popup = try XCTUnwrap(window.childWindows?.first)
        let root = try XCTUnwrap(popup.contentView)
        let row = try XCTUnwrap(all(root).first { $0.accessibilityLabel() == "Apple 9" })
        let scroll = try XCTUnwrap(all(root).first { $0 is NSScrollView } as? NSScrollView)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        for _ in 0..<5 { XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true))) }
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.5)
        height = 84
        XCTAssertTrue(content()._updateView(view, in: .init(reduceMotion: true)))
        XCTAssertTrue(row.isAccessibilitySelected())
        XCTAssertGreaterThan(row.visibleRect.height, 39)
    }


    @MainActor func testObservedBodyRefreshKeepsOriginalQueryAndCandidateSelection() throws {
        let text = FluentState(wrappedValue: "")
        let status = FluentState(wrappedValue: "")
        let view = FluentViewHost(AutoSuggestObservedSample(text: text, status: status))
        let window = mount(view); defer { window.close() }
        let editor = try type("Ap", in: view)
        let field = try field(view)
        let popup = try XCTUnwrap(window.childWindows?.first)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        waitForUI(all(view).compactMap { $0 as? NSTextField }.contains { !$0.isEditable && $0.stringValue == "Apple" })
        XCTAssertEqual(text.wrappedValue, "Apple")
        XCTAssertEqual(status.wrappedValue, "Apple")
        XCTAssertTrue(try self.field(view) === field)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertTrue(window.childWindows?.first === popup)
        XCTAssertTrue(all(popup.contentView!).contains { $0.accessibilityLabel() == "Apple" && $0.isAccessibilitySelected() })
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
        XCTAssertEqual(text.wrappedValue, "Ap")
        XCTAssertEqual(editor.string, "Ap")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }


    @MainActor func testEditorShowsWholeGlyphsAndKeepsAlignmentDuringPreviewAndReset() throws {
        for rtl in [false, true] {
            let state = FluentState(wrappedValue: "")
            let suggestionsReady = expectation(description: "Initial suggestions are available (RTL=\(rtl))")
            var didRequestSuggestions = false
            let view = FluentAutoSuggestBox(state.projectedValue, querySystemImageName: "magnifyingglass", suggestions: { query in
                if query == "Ap", !didRequestSuggestions {
                    didRequestSuggestions = true; suggestionsReady.fulfill()
                }
                return self.values
            })
                ._makeView(in: .init(reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
            let window = mount(view)
            defer { window.close() }
            let editor = try type("Ap", in: view)
            // A fixed 190ms wait does not guarantee that the 150ms debounce ran under load.
            // Preview assertions require its result, rather than a particular scheduler speed.
            wait(for: [suggestionsReady], timeout: 2)
            XCTAssertNotNil(window.childWindows?.first, "Suggestions must be open before keyboard preview")
            func assertVisible(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
                view.layoutSubtreeIfNeeded()
                let manager = try XCTUnwrap(editor.layoutManager)
                let container = try XCTUnwrap(editor.textContainer)
                manager.ensureLayout(for: container)
                let range = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: text.utf16.count), actualCharacterRange: nil)
                let glyph = manager.boundingRect(forGlyphRange: range, in: container)
                    .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                XCTAssertTrue(editor.visibleRect.insetBy(dx: -0.5, dy: -0.5).contains(glyph), "glyph=\(glyph) viewport=\(editor.visibleRect)", file: file, line: line)
                XCTAssertEqual(editor.alignment, rtl ? .right : .left, file: file, line: line)
                XCTAssertEqual(editor.string, text, file: file, line: line)
            }
            try assertVisible("Ap")
            editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
            try assertVisible("Apple 0")
            state.wrappedValue = "Pear"
            try assertVisible("Pear")
            let clear = try XCTUnwrap(all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.ClearButton" } as? NSButton)
            clear.performClick(nil); view.layoutSubtreeIfNeeded()
            let longQuery = String(repeating: "Apple ", count: 80) + "Z"
            editor.insertText(longQuery, replacementRange: NSRange(location: 0, length: 0))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.19))
            let manager = try XCTUnwrap(editor.layoutManager)
            manager.ensureLayout(for: try XCTUnwrap(editor.textContainer))
            let last = manager.glyphRange(forCharacterRange: NSRange(location: longQuery.utf16.count - 1, length: 1), actualCharacterRange: nil)
            let lastGlyph = manager.boundingRect(forGlyphRange: last, in: editor.textContainer!)
                .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            XCTAssertTrue(editor.visibleRect.insetBy(dx: -0.5, dy: -0.5).contains(lastGlyph), "long input end: \(lastGlyph); viewport: \(editor.visibleRect)")
            XCTAssertEqual(state.wrappedValue, longQuery)
            state.wrappedValue = "Pear"
            try assertVisible("Pear")
        }
    }

}


private struct AutoSuggestObservedSample: FluentView {
    let text: FluentState<String>
    let status: FluentState<String>
    var body: some FluentView {
        FluentVStack {
            FluentAutoSuggestBox(text.projectedValue,
                suggestions: { query in ["Apple", "Apricot"].filter { $0.hasPrefix(query) }.map { .init(id: $0, title: $0) } },
                onSuggestionChosen: { status.wrappedValue = $0.title })
            FluentText(status.wrappedValue)
        }
    }
}
