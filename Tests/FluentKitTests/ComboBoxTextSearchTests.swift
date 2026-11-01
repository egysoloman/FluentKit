import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxTextSearchTests: XCTestCase {
    @MainActor private final class Fixture {
        let selection = FluentState<Int?>(wrappedValue: 0)
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<Int>>
        let bridge: NSComboBox
        var titles = ["Alpha", "Bravo", "Blue sky", "Blue sea", "Charlie"]
        var options = Array(0..<5)
        var searchEnabled = true
        let trigger: FluentComboBoxSelectionChangedTrigger
        init(open: Bool = false, trigger: FluentComboBoxSelectionChangedTrigger = .committed) throws {
            _ = NSApplication.shared
            self.trigger = trigger
            let names = titles
            host = FluentViewHost(FluentComboBox(options: options, selection: selection.projectedValue,
                title: { names[$0] }).selectionChangedTrigger(trigger), context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 520, height: 320),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 60, y: 170, width: 280, height: 32)
            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
            bridge = try XCTUnwrap(Self.all(host).compactMap { $0 as? NSComboBox }.first)
            window.makeFirstResponder(bridge)
            if open { bridge.performClick(nil) }
        }
        static func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var popup: NSWindow? { window.childWindows?.first { $0.isVisible } }
        var rows: [NSView] { popup?.contentView.map { Self.all($0).filter { $0.accessibilityRole() == .menuItem } } ?? [] }
        var focused: [String] { rows.filter { $0.isAccessibilityFocused() }.compactMap { $0.accessibilityTitle() } }
        func update() {
            let names = titles
            host.update(FluentComboBox(options: options, selection: selection.projectedValue,
                title: { names[$0] }).selectionChangedTrigger(trigger).isTextSearchEnabled(searchEnabled)
                .textFieldStyle(FluentAutomaticTextFieldStyle()), context: .init(reduceMotion: true))
        }
        func key(_ characters: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) {
            let owner = popup ?? window
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: owner.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
        }
        func type(_ text: String) {
            for character in text { key(String(character), code: character == " " ? 49 : 0) }
        }
    }

    func testPrefixSelectsImmediatelyInClosedAndOpenControlsWithEitherTrigger() throws {
        for open in [false, true] {
            for trigger in [FluentComboBoxSelectionChangedTrigger.committed, .always] {
                let f = try Fixture(open: open, trigger: trigger); defer { f.window.close() }
                let panel = f.popup
                f.key("c", code: 8)
                XCTAssertEqual(f.selection.wrappedValue, 4)
                if open {
                    XCTAssertTrue(f.popup === panel); XCTAssertEqual(f.focused, ["Charlie"])
                    XCTAssertEqual(f.rows.filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() }, ["Charlie"])
                } else { XCTAssertNil(f.popup) }
            }
        }
    }

    func testSpaceExtendsSearchWithoutOpeningOrClosingThePopup() throws {
        for open in [false, true] {
            let f = try Fixture(open: open); defer { f.window.close() }
            let panel = f.popup
            f.type("blue se")
            XCTAssertEqual(f.selection.wrappedValue, 3)
            if open { XCTAssertTrue(f.popup === panel); XCTAssertEqual(f.focused, ["Blue sea"]) }
            else { XCTAssertNil(f.popup) }
        }
    }

    func testPrefixUsesDisplayedTitlesAndUnicodeFolding() throws {
        for (title, query) in [("  Éclair", "E"), ("Ｆｌｕｅｎｔ", "fl"), ("カタカナ", "かた"),
                               ("🐈 Cat", "🐈"), ("👩‍💻 Developer", "👩‍💻")] {
            let f = try Fixture(open: true); defer { f.window.close() }
            f.titles[4] = title; f.update()
            f.type(query)
            XCTAssertEqual(f.selection.wrappedValue, 4, "\(query) → \(title)")
            XCTAssertEqual(f.focused, [title])
        }
    }

    func testFailedExtensionDoesNotFallbackToTheLastCharacter() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        f.type("b"); XCTAssertEqual(f.selection.wrappedValue, 1)
        f.type("l"); XCTAssertEqual(f.selection.wrappedValue, 2)
        f.type("z"); XCTAssertEqual(f.selection.wrappedValue, 2)
        f.type("c"); XCTAssertEqual(f.selection.wrappedValue, 2)
        XCTAssertEqual(f.focused, ["Blue sky"])
    }

    func testEscapeRestoresOpeningSelectionAfterImmediateSearch() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        f.type("c"); XCTAssertEqual(f.selection.wrappedValue, 4)
        f.key("\u{1b}", code: 53)
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 0)
    }

    func testSearchSupersedesArrowPreviewAndSubsequentArrowStillDefers() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        f.key("\u{F701}", code: 125)
        XCTAssertEqual(f.selection.wrappedValue, 0)
        f.type("b"); XCTAssertEqual(f.selection.wrappedValue, 1)
        f.key("\u{F701}", code: 125)
        XCTAssertEqual(f.selection.wrappedValue, 1); XCTAssertEqual(f.focused, ["Blue sky"])
        f.key("\r", code: 36); XCTAssertEqual(f.selection.wrappedValue, 2)
    }

    func testSelectionCallbackCanReorderBeforeSearchFocusIsApplied() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        let panel = f.popup
        let id = f.selection.projectedValue.observe { value in
            guard value == 4 else { return }
            f.options = [4, 3, 2, 1, 0]; f.update()
        }
        defer { if let id { f.selection.projectedValue.removeObserver(id) } }
        f.type("c")
        XCTAssertEqual(f.selection.wrappedValue, 4); XCTAssertTrue(f.popup === panel)
        XCTAssertEqual(f.focused, ["Charlie"])
        f.key("\u{F701}", code: 125); f.key("\r", code: 36)
        XCTAssertEqual(f.selection.wrappedValue, 3)
    }

    func testExternalSelectionEndsOldSearchAndSetsNewCancelBaseline() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        f.type("b"); XCTAssertEqual(f.selection.wrappedValue, 1)
        f.selection.wrappedValue = 2
        f.type("c"); XCTAssertEqual(f.selection.wrappedValue, 4)
        f.key("\u{1b}", code: 53); XCTAssertEqual(f.selection.wrappedValue, 2)
    }

    func testLiveTitleUpdateRetainsPrefixButSearchesCurrentOptions() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        f.type("b"); XCTAssertEqual(f.selection.wrappedValue, 1)
        f.titles[4] = "Black"; f.options = [4, 0, 1]; f.update()
        f.type("l"); XCTAssertEqual(f.selection.wrappedValue, 4)
        XCTAssertEqual(f.focused, ["Black"])
    }

    func testDisabledSearchRetainsNormalSpaceBehaviorAndCanBeReenabledLive() throws {
        let f = try Fixture(); defer { f.window.close() }
        f.searchEnabled = false; f.update()
        f.type("c"); XCTAssertEqual(f.selection.wrappedValue, 0)
        f.key(" ", code: 49); XCTAssertNotNil(f.popup)
        f.searchEnabled = true; f.update(); f.type("c")
        XCTAssertEqual(f.selection.wrappedValue, 4)
        f.searchEnabled = false; f.update(); f.key(" ", code: 49)
        XCTAssertNil(f.popup); XCTAssertEqual(f.selection.wrappedValue, 4)
    }

    func testFocusLossAndHidingDiscardPrefix() throws {
        for hide in [false, true] {
            let f = try Fixture(); defer { f.window.close() }
            f.type("b"); XCTAssertEqual(f.selection.wrappedValue, 1)
            if hide { f.host.subviews.first?.isHidden = true; f.host.subviews.first?.isHidden = false }
            else { f.window.makeFirstResponder(nil) }
            f.window.makeFirstResponder(f.bridge)
            f.type("c"); XCTAssertEqual(f.selection.wrappedValue, 4)
        }
    }

    func testSearchKeepsReopenedPopupUnderItsNewOwner() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        let oldPanel = f.popup
        let id = f.selection.projectedValue.observe { value in
            guard value == 4 else { return }
            f.bridge.performClick(nil); f.bridge.performClick(nil)
            f.key("\u{F700}", code: 126)
        }
        defer { if let id { f.selection.projectedValue.removeObserver(id) } }
        f.type("c")
        XCTAssertEqual(f.selection.wrappedValue, 4); XCTAssertNotNil(f.popup)
        XCTAssertFalse(f.popup === oldPanel); XCTAssertEqual(f.focused, ["Blue sea"])
    }

    func testNormalizingSelectionCallbackEndsOldPrefix() throws {
        for open in [false, true] {
            let f = try Fixture(open: open); defer { f.window.close() }
            let id = f.selection.projectedValue.observe { value in
                if value == 4 { f.selection.wrappedValue = 0 }
            }
            defer { if let id { f.selection.projectedValue.removeObserver(id) } }
            f.type("c"); XCTAssertEqual(f.selection.wrappedValue, 0)
            f.type("b"); XCTAssertEqual(f.selection.wrappedValue, 1)
        }
    }

    func testSearchRevealsMatchingRowInScrollablePopup() throws {
        let f = try Fixture(open: true); defer { f.window.close() }
        f.options = Array(0..<60); f.titles = f.options.map { "Item \($0)" }
        f.titles[59] = "Zebra"; f.update(); f.type("z")
        XCTAssertEqual(f.selection.wrappedValue, 59); XCTAssertEqual(f.focused, ["Zebra"])
        let row = try XCTUnwrap(f.rows.first { $0.accessibilityTitle() == "Zebra" })
        let scroll = try XCTUnwrap(row.enclosingScrollView)
        XCTAssertTrue(scroll.documentVisibleRect.contains(row.frame))
    }

    func testPrefixTimeoutStartsAfterCurrentSelectionAndWrapsWithoutSleeping() {
        var search = FluentComboBoxTextSearch()
        let titles = ["Alpha", "Bravo", "Blue", "Blunt"]
        XCTAssertEqual(search.append("b", titles: titles, selectedIndex: 0, at: 10), 1)
        XCTAssertEqual(search.append("l", titles: titles, selectedIndex: 1, at: 10.5), 2)
        XCTAssertTrue(search.isSearching(at: 11.5)); XCTAssertFalse(search.isSearching(at: 11.501))
        XCTAssertEqual(search.append("b", titles: titles, selectedIndex: 2, at: 12), 3)
        XCTAssertEqual(search.append("b", titles: titles, selectedIndex: 3, at: 14), 1)
        XCTAssertNil(search.append("b", titles: titles, selectedIndex: 1, at: 14.5))
        search.reset(); XCTAssertFalse(search.isSearching(at: 14.5))
    }

    func testPrefixLimitPreservesWholeGraphemesAndRecoversAfterTimeout() {
        var search = FluentComboBoxTextSearch()
        let title = String(repeating: "a", count: 255) + "🐈"
        // The emoji will not fit; retaining the complete 255-character prefix still matches.
        XCTAssertEqual(search.append(title, titles: [title], selectedIndex: nil, at: 1), 0)
        XCTAssertEqual(search.append("b", titles: [title, "Bravo"], selectedIndex: 0, at: 3), 1)
    }

    func testClosureModelRefreshEndsClosedSearchWithoutObservationIdentity() throws {
        let f = try Fixture(); defer { f.window.close() }
        var model: Int? = 0
        func refresh() {
            f.host.update(FluentComboBox(options: f.options,
                selection: FluentBinding(get: { model }, set: { model = $0 }), title: { f.titles[$0] }),
                context: .init(reduceMotion: true))
        }
        refresh(); f.type("b"); XCTAssertEqual(model, 1)
        model = 2; refresh()
        f.type("c"); XCTAssertEqual(model, 4)
    }

    func testShiftAndCharacterProducingOptionKeysSearchButCommandAndControlDoNot() throws {
        for flags in [NSEvent.ModifierFlags.shift, .option, .command, .control] {
            let f = try Fixture(); defer { f.window.close() }
            // Send to the focused control to test its routing without invoking application menu shortcuts.
            let characters = flags == .option ? "ç" : "C"
            f.bridge.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: f.window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!)
            XCTAssertEqual(f.selection.wrappedValue, flags == .command || flags == .control ? 0 : 4)
        }
    }
}
