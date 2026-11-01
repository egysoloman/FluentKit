import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxCollectionMutationTests: XCTestCase {
    private final class Model {
        var selected: Int? = 2
        var text = "Option 2"
        var writes: [Int?] = []
        var onSelection: ((Int?) -> Void)?
        var onText: ((String) -> Void)?
        var selection: FluentBinding<Int?> {
            FluentBinding(get: { self.selected }, set: {
                self.selected = $0
                self.writes.append($0)
                self.onSelection?($0)
            })
        }
        var textBinding: FluentBinding<String> {
            FluentBinding(get: { self.text }, set: { self.text = $0; self.onText?($0) })
        }
    }
    @MainActor private final class Fixture {
        let model = Model()
        let window: NSWindow
        let hosting: FluentViewHost<FluentComboBox<Int>>
        var options: [Int]
        var mode: FluentComboBoxMode
        var bindsText: Bool
        var direction: FluentLayoutDirection = .leftToRight
        init(mode: FluentComboBoxMode = .selection, options: [Int] = Array(0..<5), bindsText: Bool = false) {
            _ = NSApplication.shared
            self.mode = mode
            self.options = options
            self.bindsText = bindsText
            hosting = FluentViewHost(FluentComboBox(options: options, selection: model.selection,
                mode: mode, text: bindsText ? model.textBinding : nil, title: { "Option \($0)" }).selectionChangedTrigger(.always),
                context: .init(reduceMotion: true))
            window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 700, height: 500),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(hosting)
            hosting.translatesAutoresizingMaskIntoConstraints = true
            hosting.frame = NSRect(x: 160, y: 260, width: 180, height: 32)
            window.makeKeyAndOrderFront(nil)
            hosting.layoutSubtreeIfNeeded()
        }
        func update(_ options: [Int], longTitle: Bool = false) {
            self.options = options
            hosting.update(FluentComboBox(options: options, selection: model.selection, mode: mode,
                text: bindsText ? model.textBinding : nil,
                title: { longTitle ? "Long updated option \($0) with additional detail" : "Option \($0)" }).selectionChangedTrigger(.always),
                context: .init(reduceMotion: true, layoutDirection: direction))
            hosting.layoutSubtreeIfNeeded()
            window.childWindows?.first?.contentView?.layoutSubtreeIfNeeded()
        }
    }
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    private func open(_ f: Fixture) throws -> (NSWindow, NSScrollView, [NSView]) {
        try XCTUnwrap(all(f.hosting).compactMap { $0 as? NSComboBox }.first).performClick(nil)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let scroll = try XCTUnwrap(panel.contentView.flatMap { all($0).compactMap { $0 as? NSScrollView }.first })
        return (panel, scroll, try XCTUnwrap(scroll.documentView).subviews)
    }
    private func key(_ code: UInt16, _ panel: NSWindow) {
        panel.firstResponder?.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
    }
    private func mouse(_ type: NSEvent.EventType, _ row: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: row.window?.windowNumber ?? 0, context: nil,
            eventNumber: 934, clickCount: 1, pressure: 1)!
    }

    func testAppendRetainsPanelResponderRowsAndSelectionInBothModes() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = Fixture(mode: mode)
            defer { f.window.close() }
            let (panel, scroll, rows) = try open(f)
            let responder = panel.firstResponder
            f.update(Array(0..<7))
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(f.window.childWindows?.first === panel)
            XCTAssertTrue(panel.firstResponder === responder)
            let updated = try XCTUnwrap(scroll.documentView).subviews
            XCTAssertEqual(updated.count, 7)
            XCTAssertTrue(zip(rows, updated).allSatisfy { $0 === $1 })
            XCTAssertEqual(f.model.selected, 2)
            XCTAssertTrue(f.model.writes.isEmpty)
            XCTAssertEqual(updated.last?.accessibilityTitle(), "Option 6")
        }
    }

    func testReorderKeepsStableSelectionFocusAndRowIdentity() throws {
        for mode in [FluentComboBoxMode.selection, .editable] {
            let f = Fixture(mode: mode)
            defer { f.window.close() }
            let (panel, scroll, rows) = try open(f)
            f.update([4, 3, 1, 0, 2])
            let updated = try XCTUnwrap(scroll.documentView).subviews
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(updated.count, 5)
            guard updated.count == 5 else { continue }
            XCTAssertTrue(updated[4] === rows[2])
            XCTAssertTrue(updated[0] === rows[4])
            XCTAssertTrue(updated[4].isAccessibilitySelected())
            XCTAssertTrue(updated[4].isAccessibilityFocused())
            XCTAssertTrue(f.model.writes.isEmpty)
            key(126, panel)
            XCTAssertEqual(f.model.selected, 0)
            key(36, panel)
            XCTAssertEqual(f.model.selected, 0)
            XCTAssertFalse(panel.isVisible)
        }
    }

    func testRemovingFocusedItemKeepsPopupAndUsesNeighborWithoutSelectingIt() throws {
        let f = Fixture()
        defer { f.window.close() }
        let (panel, scroll, _) = try open(f)
        key(125, panel)
        XCTAssertEqual(f.model.selected, 3)
        f.update([0, 1, 2, 4])
        XCTAssertTrue(panel.isVisible)
        XCTAssertNil(f.model.selected)
        let focused = scroll.documentView?.subviews.first { $0.isAccessibilityFocused() }
        XCTAssertEqual(focused?.accessibilityTitle(), "Option 4")
        key(36, panel)
        XCTAssertEqual(f.model.selected, 4)
        XCTAssertFalse(panel.isVisible)
    }

    func testReorderCancelsCapturedPressAndFreshPressUsesRetainedIdentity() throws {
        let f = Fixture()
        defer { f.window.close() }
        let (panel, _, rows) = try open(f)
        let retained = rows[4]
        retained.mouseDown(with: mouse(.leftMouseDown, retained))
        f.update([4, 3, 1, 0, 2])
        retained.mouseUp(with: mouse(.leftMouseUp, retained))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(f.model.selected, 2)
        retained.mouseDown(with: mouse(.leftMouseDown, retained))
        retained.mouseUp(with: mouse(.leftMouseUp, retained))
        XCTAssertEqual(f.model.selected, 4)
        XCTAssertEqual(f.model.writes.compactMap { $0 }, [4])
        XCTAssertFalse(panel.isVisible)
    }

    func testRemovedRowCannotCommitByReleaseOrAccessibility() throws {
        let f = Fixture()
        defer { f.window.close() }
        let (panel, _, rows) = try open(f)
        let removed = rows[3]
        removed.mouseDown(with: mouse(.leftMouseDown, removed))
        f.update([0, 1, 2, 4])
        removed.mouseUp(with: mouse(.leftMouseUp, removed))
        XCTAssertNil(removed.superview)
        XCTAssertFalse(removed.accessibilityPerformPress())
        XCTAssertEqual(f.model.selected, 2)
        XCTAssertTrue(f.model.writes.isEmpty)
        XCTAssertTrue(panel.isVisible)
    }

    func testInsertionPreservesVisibleStableRowAndShrinkConstrainsScroll() throws {
        let f = Fixture(options: Array(0..<40))
        defer { f.window.close() }
        f.model.selected = 20
        f.update(f.options)
        let (panel, scroll, rows) = try open(f)
        let visible = scroll.documentVisibleRect
        let first = try XCTUnwrap(rows.first { visible.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) })
        let offset = first.frame.minY - visible.minY
        f.update([-2, -1] + Array(0..<40))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(first.frame.minY - scroll.documentVisibleRect.minY, offset, accuracy: 0.5)
        XCTAssertTrue(scroll.documentVisibleRect.intersects(first.frame))
        f.update([18, 19, 20])
        XCTAssertEqual(scroll.documentView?.subviews.count, 3)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.5)
        XCTAssertTrue(scroll.documentVisibleRect.contains(try XCTUnwrap(scroll.documentView).bounds))
        XCTAssertFalse(scroll.hasVerticalScroller)
    }

    func testEmptyAndModeChangeStillDismissPopup() throws {
        for changesMode in [false, true] {
            let f = Fixture()
            defer { f.window.close() }
            let (panel, _, rows) = try open(f)
            if changesMode { f.mode = .editable }
            f.update(changesMode ? f.options : [])
            XCTAssertFalse(panel.isVisible)
            XCTAssertTrue(f.window.childWindows?.isEmpty ?? true)
            XCTAssertFalse(rows[2].accessibilityPerformPress())
            if !changesMode { XCTAssertNil(f.model.selected) }
        }
    }

    func testExternalSelectionResetAfterMutationKeepsPopupAndClearsPill() throws {
        let f = Fixture()
        defer { f.window.close() }
        let (panel, scroll, _) = try open(f)
        f.update([4, 3, 1, 0, 2])
        f.model.selected = nil
        f.update(f.options)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(try XCTUnwrap(scroll.documentView).subviews.contains { $0.isAccessibilitySelected() })
        XCTAssertTrue(f.model.writes.isEmpty)
    }

    func testReentrantSelectionCallbackCanRemoveFocusedItem() throws {
        let f = Fixture()
        defer { f.window.close() }
        let (panel, scroll, _) = try open(f)
        f.model.onSelection = { [weak f] value in
            guard let f, value == 4 else { return }
            f.update([0, 1])
        }
        key(119, panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertNil(f.model.selected)
        XCTAssertEqual(scroll.documentView?.subviews.count, 2)
        XCTAssertEqual(scroll.documentView?.subviews.first { $0.isAccessibilityFocused() }?.accessibilityTitle(), "Option 1")
        key(36, panel)
        XCTAssertEqual(f.model.selected, 1)
    }

    func testEditableBoundTextSurvivesRemovalAndSelectionIsNormalized() throws {
        let f = Fixture(mode: .editable, bindsText: true)
        defer { f.window.close() }
        let (panel, _, _) = try open(f)
        f.update([0, 1, 3, 4])
        XCTAssertTrue(panel.isVisible)
        XCTAssertNil(f.model.selected)
        XCTAssertEqual(f.model.text, "Option 2")
    }

    func testEditableTextCallbackCannotRestoreAnOptionItJustRemoved() throws {
        let f = Fixture(mode: .editable, bindsText: true)
        defer { f.window.close() }
        let (panel, _, _) = try open(f)
        f.model.onText = { [weak f] value in
            guard let f, value == "Option 3" else { return }
            f.update([0, 1])
        }
        key(125, panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertNil(f.model.selected)
        XCTAssertEqual(f.model.text, "Option 3")
        XCTAssertFalse(f.model.writes.compactMap { $0 }.contains(3))
    }

    func testEditableTextCallbackCanReorderAndRetainTheIntendedOption() throws {
        let f = Fixture(mode: .editable, bindsText: true)
        defer { f.window.close() }
        let (panel, scroll, rows) = try open(f)
        f.model.onText = { [weak f] value in
            guard let f, value == "Option 3" else { return }
            f.update([3, 0, 1, 2, 4])
        }
        key(125, panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(f.model.selected, 3)
        XCTAssertEqual(f.model.text, "Option 3")
        XCTAssertTrue(scroll.documentView?.subviews.first === rows[3])
        XCTAssertTrue(rows[3].isAccessibilitySelected())
    }

    func testEditablePublicationUsesCurrentSelectionAfterReentrantReorder() throws {
        let f = Fixture(mode: .editable, bindsText: true)
        defer { f.window.close() }
        let (panel, _, rows) = try open(f)
        let field = try XCTUnwrap(all(f.hosting).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" })
        f.model.onSelection = { [weak f] value in
            guard let f, value == 3 else { return }
            f.update([3, 0, 1, 2, 4])
        }
        field.stringValue = "Option 3"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        waitForUI(f.model.selected == 3)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(f.model.selected, 3)
        XCTAssertTrue(rows[3].isAccessibilitySelected())
        XCTAssertFalse(rows[2].isAccessibilitySelected())
    }

    func testMutationRefreshesRTLGeometryAndAccessibleTitles() throws {
        let f = Fixture()
        defer { f.window.close() }
        let (panel, scroll, rows) = try open(f)
        let oldWidth = panel.frame.width
        f.direction = .rightToLeft
        f.update([4, 3, 1, 0, 2, 5], longTitle: true)
        XCTAssertTrue(panel.isVisible)
        XCTAssertGreaterThan(panel.frame.width, oldWidth)
        XCTAssertEqual(rows[2].accessibilityTitle(), "Long updated option 2 with additional detail")
        XCTAssertTrue(scroll.documentView?.subviews.last?.accessibilityTitle()?.contains("option 5") == true)
        let pill = try XCTUnwrap(rows[2].layer?.sublayers?.first { $0.name == "FluentKit.ComboBoxItem.SelectionPill" })
        XCTAssertGreaterThan(pill.frame.midX, rows[2].bounds.midX)
    }

    func testReentrantNormalizationKeepsReplacementBindingObserved() throws {
        _ = NSApplication.shared
        let original = FluentState<Int?>(wrappedValue: 2)
        let replacement = FluentState<Int?>(wrappedValue: 99)
        let context = FluentRenderContext(reduceMotion: true)
        let initial = FluentComboBox(options: Array(0..<5), selection: original.projectedValue)
        let updated = FluentComboBox(options: Array(0..<5), selection: replacement.projectedValue)
        let control = initial._makeView(in: context)
        let bridge = try XCTUnwrap(all(control).compactMap { $0 as? NSComboBox }.first)
        let token = replacement.projectedValue.observe { value in
            if value == nil { XCTAssertTrue(updated._updateView(control, in: context)) }
        }
        defer { if let token { replacement.projectedValue.removeObserver(token) } }
        XCTAssertTrue(updated._updateView(control, in: context))
        XCTAssertNil(replacement.wrappedValue)
        replacement.wrappedValue = 4
        XCTAssertEqual(bridge.indexOfSelectedItem, 4)
        original.wrappedValue = 1
        XCTAssertEqual(bridge.indexOfSelectedItem, 4)
    }

    func testReentrantNormalizationKeepsReplacementTextObserved() throws {
        _ = NSApplication.shared
        let original = FluentState<Int?>(wrappedValue: 2)
        let replacement = FluentState<Int?>(wrappedValue: 99)
        let originalText = FluentState<String>(wrappedValue: "old text")
        let replacementText = FluentState<String>(wrappedValue: "free text")
        let context = FluentRenderContext(reduceMotion: true)
        let initial = FluentComboBox(options: Array(0..<5), selection: original.projectedValue,
            mode: .editable, text: originalText.projectedValue)
        let updated = FluentComboBox(options: Array(0..<5), selection: replacement.projectedValue,
            mode: .editable, text: replacementText.projectedValue)
        let control = initial._makeView(in: context)
        let field = try XCTUnwrap(all(control).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" })
        let token = replacement.projectedValue.observe { value in
            if value == nil { XCTAssertTrue(updated._updateView(control, in: context)) }
        }
        defer { if let token { replacement.projectedValue.removeObserver(token) } }
        XCTAssertTrue(updated._updateView(control, in: context))
        XCTAssertNil(replacement.wrappedValue)
        replacementText.wrappedValue = "new text"
        XCTAssertEqual(field.stringValue, "new text")
        originalText.wrappedValue = "stale text"
        XCTAssertEqual(field.stringValue, "new text")
    }
}
