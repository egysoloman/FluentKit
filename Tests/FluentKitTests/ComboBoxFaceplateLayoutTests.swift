import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxFaceplateLayoutTests: XCTestCase {
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    private func mount(_ definition: FluentAnyView, theme: FluentTheme = .custom(colorScheme: .light)) -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = window.contentView!
        let native = definition._mount(in: .init(theme: theme, reduceMotion: true))
        root.addSubview(native)
        native.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([native.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            native.topAnchor.constraint(equalTo: root.topAnchor), native.widthAnchor.constraint(equalToConstant: 380)])
        window.makeKeyAndOrderFront(nil)
        root.layoutSubtreeIfNeeded()
        return (window, native)
    }

    private func faceplate(_ view: NSView) throws -> NSView {
        try XCTUnwrap(all(view).first { $0.identifier?.rawValue == "FluentKit.ComboBox.Host" })
    }

    func testUnconstrainedHeightInBothModesAcrossDeclarativeContainers() throws {
        let selection = FluentState<String?>(wrappedValue: "Preset")
        let expanded = FluentState(wrappedValue: true)
        for mode in [FluentComboBoxMode.selection, .editable] {
            let combo = FluentComboBox(options: ["Preset", "中文"], selection: selection.projectedValue, mode: mode)
            let variants = [FluentAnyView(combo), FluentAnyView(combo.frame(width: 220)),
                FluentAnyView(FluentVStack(alignment: .leading) { combo.frame(width: 220); FluentText("Following content") }),
                FluentAnyView(FluentExpander("Sample", isExpanded: expanded.projectedValue) {
                    FluentVStack(alignment: .leading) { combo.frame(width: 220); FluentText("Following content") }
                })]
            for definition in variants {
                let (window, native) = mount(definition)
                defer { window.close() }
                let host = try faceplate(native)
                XCTAssertEqual(host.bounds.height, 32, accuracy: 0.01)
                let bridge = try XCTUnwrap(host.subviews.first { $0 is NSComboBox })
                let editor = try XCTUnwrap(host.subviews.first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" })
                XCTAssertEqual(bridge.frame, host.bounds)
                XCTAssertEqual(editor.frame, host.bounds)
            }
        }
    }

    func testDensityAndLargerTypographyKeepFullTextLineAfterLiveUpdate() throws {
        let selection = FluentState<String?>(wrappedValue: "中文 English")
        for mode in [FluentComboBoxMode.selection, .editable] {
            let combo = FluentComboBox(options: ["中文 English"], selection: selection.projectedValue, mode: mode).frame(width: 220)
            let (window, native) = mount(FluentAnyView(combo))
            defer { window.close() }
            let original = try faceplate(native)
            for density in [FluentThemeDensity.compact, .regular, .spacious] {
                for scale: CGFloat in [1, 1.5, 2] {
                    let theme = FluentTheme.custom(density: density, colorScheme: .light, typography: .init(scale: scale))
                    XCTAssertTrue(combo._update(native, in: .init(theme: theme, reduceMotion: true)))
                    window.contentView!.layoutSubtreeIfNeeded()
                    let host = try faceplate(native)
                    XCTAssertTrue(host === original)
                    let bridge = try XCTUnwrap(host.subviews.compactMap { $0 as? NSComboBox }.first)
                    let font = try XCTUnwrap(bridge.font)
                    XCTAssertEqual(font.pointSize, 14 * scale, accuracy: 0.01)
                    let lineHeight = ceil(font.ascender - font.descender + font.leading)
                    XCTAssertGreaterThanOrEqual(host.bounds.height + 0.01, theme.controlHeight(for: .regular))
                    XCTAssertGreaterThanOrEqual(host.bounds.height - 12 + 0.01, lineHeight)
                    if mode == .editable {
                        let editor = try XCTUnwrap(host.subviews.first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
                        XCTAssertGreaterThanOrEqual(editor.cell!.titleRect(forBounds: editor.bounds).height, lineHeight)
                    }
                }
            }
        }
    }

    func testControlSizesAndExplicitHeightRemainSupported() throws {
        let selection = FluentState<String?>(wrappedValue: "English")
        for size in [FluentControlSize.small, .regular, .large] {
            let definition = FluentComboBox(options: ["English"], selection: selection.projectedValue).controlSize(size).frame(width: 220)
            let (window, native) = mount(FluentAnyView(definition))
            defer { window.close() }
            let host = try faceplate(native)
            let font = try XCTUnwrap(host.subviews.compactMap { ($0 as? NSComboBox)?.font }.first)
            XCTAssertGreaterThanOrEqual(host.bounds.height, size.height)
            XCTAssertGreaterThanOrEqual(host.bounds.height - 12, ceil(font.ascender - font.descender + font.leading))
        }
        let definition = FluentComboBox(options: ["English"], selection: selection.projectedValue).frame(width: 220, height: 44)
        let (window, native) = mount(FluentAnyView(definition))
        defer { window.close() }
        XCTAssertEqual(try faceplate(native).bounds.height, 44, accuracy: 0.01)
    }

    func testResizingEditableFaceplatePreservesItsActiveMarkedText() throws {
        let selection = FluentState<String?>(wrappedValue: nil)
        let text = FluentState(wrappedValue: "")
        let definition = FluentComboBox(options: ["中文"], selection: selection.projectedValue,
                                       mode: .editable, text: text.projectedValue).frame(width: 220)
        let (window, native) = mount(FluentAnyView(definition))
        defer { window.close() }
        let host = try faceplate(native)
        let field = try XCTUnwrap(host.subviews.first { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" } as? NSTextField)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let theme = FluentTheme.custom(colorScheme: .dark, typography: .init(scale: 1.5))
        XCTAssertTrue(definition._update(native, in: .init(theme: theme, reduceMotion: true)))
        window.contentView!.layoutSubtreeIfNeeded()
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "pin")
        XCTAssertGreaterThan(host.bounds.height, 32)
        // This checks AppKit editor preservation, not real input-method candidate placement.
    }
}
