import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxRTLTextTests: XCTestCase {
    @MainActor private final class Fixture {
        let selection = FluentState<String?>(wrappedValue: nil)
        let text: FluentState<String>
        let window: NSWindow
        let host: FluentViewHost<FluentComboBox<String>>
        let field: NSTextField
        let glyph: CALayer
        init(rtl: Bool = false, width: CGFloat = 240, value: String = "Option 2 中文") throws {
            _ = NSApplication.shared
            text = FluentState(wrappedValue: value)
            let definition = FluentComboBox(options: ["Option 2 中文", "עברית"], selection: selection.projectedValue,
                mode: .editable, text: text.projectedValue)
            host = FluentViewHost(definition, context: .init(reduceMotion: true,
                layoutDirection: rtl ? .rightToLeft : .leftToRight))
            window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(host)
            host.translatesAutoresizingMaskIntoConstraints = true
            host.frame = NSRect(x: 60, y: 140, width: width, height: 44)
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            field = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
            let control = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.ComboBox.Host" })
            glyph = try XCTUnwrap(control.layer?.sublayers?.first { $0.name == "FluentKit.ComboBox.Chevron" })
            window.makeFirstResponder(nil)
        }
        func update(rtl: Bool, scale: CGFloat = 1) {
            let definition = FluentComboBox(options: ["Option 2 中文", "עברית"], selection: selection.projectedValue,
                mode: .editable, text: text.projectedValue)
            host.update(definition, context: .init(theme: .custom(typography: .init(scale: scale)),
                reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
            host.layoutSubtreeIfNeeded()
        }
        func edit() throws -> NSTextView {
            field.selectText(nil)
            return try XCTUnwrap(field.currentEditor() as? NSTextView)
        }
        var textRect: NSRect { field.cell!.titleRect(forBounds: field.bounds) }
    }

    private func clipRect(_ editor: NSTextView, field: NSTextField) throws -> NSRect {
        let clip = try XCTUnwrap(editor.superview as? NSClipView)
        return clip.convert(clip.bounds, to: field)
    }

    func testClosedTextReservationMirrorsWithoutChangingBaselineOrWidth() throws {
        for width: CGFloat in [80, 240, 380] {
            let f = try Fixture(width: width)
            defer { f.window.close() }
            let ltr = f.textRect
            XCTAssertLessThanOrEqual(ltr.maxX, f.glyph.frame.minX)
            f.update(rtl: true)
            let rtl = f.textRect
            XCTAssertGreaterThanOrEqual(rtl.minX, f.glyph.frame.maxX)
            XCTAssertEqual(rtl.minX, f.field.bounds.width - ltr.maxX, accuracy: 0.01)
            XCTAssertEqual(rtl.width, ltr.width, accuracy: 0.01)
            XCTAssertEqual(rtl.minY, ltr.minY, accuracy: 0.01)
            XCTAssertEqual(rtl.height, ltr.height, accuracy: 0.01)
            f.update(rtl: false)
            XCTAssertEqual(f.textRect, ltr)
        }
    }

    func testFreshEditorUsesTheSameReservedTextAreaInBothDirections() throws {
        for rtl in [false, true] {
            let f = try Fixture(rtl: rtl)
            defer { f.window.close() }
            let editor = try f.edit()
            let actual = editor.convert(editor.bounds, to: f.field)
            XCTAssertEqual(actual.minX, f.textRect.minX, accuracy: 0.01)
            XCTAssertEqual(actual.minY, f.textRect.minY, accuracy: 0.01)
            let clip = try clipRect(editor, field: f.field)
            if rtl { XCTAssertGreaterThanOrEqual(clip.minX, f.glyph.frame.maxX) }
            else { XCTAssertLessThanOrEqual(clip.maxX, f.glyph.frame.minX) }
        }
    }

    func testLiveDirectionChangeKeepsEditorSelectionDelegateAndBaseline() throws {
        let f = try Fixture()
        defer { f.window.close() }
        let editor = try f.edit()
        let delegate = editor.delegate
        let selection = NSRange(location: 2, length: 3)
        editor.setSelectedRange(selection)
        let baseline = editor.convert(editor.bounds, to: f.field).minY
        let initialTextRect = f.textRect
        let initialAnchor = editor.firstRect(forCharacterRange: selection, actualRange: nil)
        for rtl in [true, false, true] {
            f.update(rtl: rtl)
            XCTAssertTrue(f.field.currentEditor() === editor)
            XCTAssertTrue(editor.delegate === delegate)
            XCTAssertEqual(editor.selectedRange(), selection)
            XCTAssertEqual(editor.string, "Option 2 中文")
            let actual = editor.convert(editor.bounds, to: f.field)
            XCTAssertEqual(actual.minX, f.textRect.minX, accuracy: 0.01)
            XCTAssertEqual(actual.minY, baseline, accuracy: 0.01)
            let clip = try clipRect(editor, field: f.field)
            if rtl { XCTAssertGreaterThanOrEqual(clip.minX, f.glyph.frame.maxX) }
            else { XCTAssertLessThanOrEqual(clip.maxX, f.glyph.frame.minX) }
            let anchor = editor.firstRect(forCharacterRange: selection, actualRange: nil)
            XCTAssertEqual(anchor.minX - initialAnchor.minX, f.textRect.minX - initialTextRect.minX, accuracy: 0.5)
            // Reapplying an identical context must not translate the viewport again.
            f.update(rtl: rtl)
            XCTAssertEqual(try clipRect(editor, field: f.field), clip)
        }
    }

    func testLongTextKeepsHorizontalScrollAndSelectionWhenDirectionChanges() throws {
        let value = String(repeating: "Long option 中文 ", count: 30)
        let f = try Fixture(value: value)
        defer { f.window.close() }
        let editor = try f.edit()
        let selection = NSRange(location: editor.string.utf16.count, length: 0)
        editor.setSelectedRange(selection)
        editor.scrollRangeToVisible(selection)
        let clip = try XCTUnwrap(editor.superview as? NSClipView)
        let offset = clip.bounds.minX - editor.frame.minX
        XCTAssertGreaterThan(offset, 0)
        for rtl in [true, false] {
            f.update(rtl: rtl)
            XCTAssertTrue(f.field.currentEditor() === editor)
            XCTAssertEqual(editor.selectedRange(), selection)
            XCTAssertEqual(clip.bounds.minX - editor.frame.minX, offset, accuracy: 0.5)
            let visible = try clipRect(editor, field: f.field)
            if rtl { XCTAssertGreaterThanOrEqual(visible.minX, f.glyph.frame.maxX) }
            else { XCTAssertLessThanOrEqual(visible.maxX, f.glyph.frame.minX) }
        }
    }

    func testDirectionAndFontUpdatesPreserveMarkedText() throws {
        let f = try Fixture(value: "")
        defer { f.window.close() }
        let editor = try f.edit()
        editor.setMarkedText("pin", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.markedRange()
        let selection = editor.selectedRange()
        for rtl in [true, false, true] {
            f.update(rtl: rtl, scale: 1.25)
            XCTAssertTrue(f.field.currentEditor() === editor)
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(editor.markedRange(), marked)
            XCTAssertEqual(editor.selectedRange(), selection)
            XCTAssertEqual(editor.string, "pin")
            let actual = editor.convert(editor.bounds, to: f.field)
            XCTAssertEqual(actual.minX, f.textRect.minX, accuracy: 0.01)
            XCTAssertEqual(actual.minY, f.textRect.minY, accuracy: 0.01)
            let clip = try clipRect(editor, field: f.field)
            if rtl { XCTAssertGreaterThanOrEqual(clip.minX, f.glyph.frame.maxX) }
            else { XCTAssertLessThanOrEqual(clip.maxX, f.glyph.frame.minX) }
        }
        // Native marked-text preservation; this does not validate a physical IME candidate window.
    }

    func testInactiveComboBoxCannotMoveAnotherFieldsSharedEditor() throws {
        let f = try Fixture()
        defer { f.window.close() }
        _ = try f.edit()
        f.update(rtl: true)
        let other = FluentTextField(placeholder: "Other")
        other.frame = NSRect(x: 60, y: 70, width: 240, height: 32)
        other.stringValue = "Unrelated editor"
        f.window.contentView?.addSubview(other)
        other.selectText(nil)
        let editor = try XCTUnwrap(other.currentEditor() as? NSTextView)
        let selection = NSRange(location: 1, length: 4)
        editor.setSelectedRange(selection)
        let frame = try clipRect(editor, field: other)
        f.update(rtl: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(other.currentEditor() === editor)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(try clipRect(editor, field: other), frame)
        XCTAssertEqual(editor.string, "Unrelated editor")
    }
}
