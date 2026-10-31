import XCTest
@testable import FluentKit

final class RadioButtonAuditTests: XCTestCase {
    private func assertColor(_ actual: NSColor, _ expected: NSColor, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let a = actual.usingColorSpace(.deviceRGB)!, e = expected.usingColorSpace(.deviceRGB)!
        for (x, y) in zip([a.redComponent, a.greenComponent, a.blueComponent, a.alphaComponent],
                          [e.redComponent, e.greenComponent, e.blueComponent, e.alphaComponent]) {
            XCTAssertEqual(x, y, accuracy: 0.001, message, file: file, line: line)
        }
    }

    @MainActor func testHighContrastRadioResourcesResolveUnderTheExplicitTheme() {
        _ = NSApplication.shared
        for dark in [false, true] { for selected in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            for (i, state) in [FluentControlState.normal, .pointerOver, .pressed, .disabled].enumerated() {
                // WinUI RadioButton_themeresources.xaml: these differ from CheckBox's matrix.
                let fills: [NSColor] = selected
                    ? [.selectedMenuItemTextColor, .controlBackgroundColor, .controlBackgroundColor, theme.windowBackground]
                    : [.controlBackgroundColor, .selectedMenuItemTextColor, .selectedMenuItemTextColor, theme.windowBackground]
                let strokes: [NSColor] = selected
                    ? [.selectedContentBackgroundColor, .controlTextColor, .controlBackgroundColor, .disabledControlTextColor]
                    : [.controlTextColor, .selectedContentBackgroundColor, .selectedMenuItemTextColor, .disabledControlTextColor]
                let dots: [NSColor] = [.selectedContentBackgroundColor, .controlTextColor, .controlTextColor, .disabledControlTextColor]
                var expected: [NSColor] = []
                NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                    expected = [fills[i], strokes[i], dots[i], .selectedContentBackgroundColor,
                                state == .disabled ? .disabledControlTextColor : .controlTextColor]
                        .map { $0.usingColorSpace(.deviceRGB)! }
                }
                NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
                    let a = FluentAutomaticRadioButtonStyle().appearance(for: .init(isSelected: selected,
                        isEnabled: state != .disabled, isPointerOver: state == .pointerOver,
                        isPressed: state == .pressed, controlSize: .regular, theme: theme))
                    for (j, color) in [a.fillColor, a.borderColor, a.dotColor, a.pressedFeedbackColor, a.labelColor].enumerated() {
                        assertColor(NSColor(cgColor: color.cgColor)!, expected[j], "dark=\(dark) selected=\(selected) state=\(state) field=\(j)")
                    }
                }
            }
        } }
    }

    @MainActor func testStandaloneRadioIsAnAccessibleNumericSingleSelectionControl() {
        _ = NSApplication.shared
        let radio = FluentRadioButton(title: "Mode")
        var changes: [Bool] = []
        radio.onValueChanged = { changes.append($0) }
        XCTAssertTrue(radio.isAccessibilityElement())
        XCTAssertEqual(radio.accessibilityRole(), .radioButton)
        XCTAssertEqual(radio.accessibilityValue() as? NSNumber, 0)
        XCTAssertTrue(radio.accessibilityPerformPress())
        XCTAssertEqual(radio.accessibilityValue() as? NSNumber, 1)
        XCTAssertTrue(radio.accessibilityPerformPress())
        XCTAssertEqual(changes, [true], "Re-activating a selected option must not clear it or emit another selection")
        radio.isEnabled = false
        XCTAssertFalse(radio.accessibilityPerformPress())
        XCTAssertEqual(radio.accessibilityValue() as? NSNumber, 1)
    }

    @MainActor func testRadioButtonsExposesItsChildrenAndModelChanges() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "Auto")
        let group = FluentRadioButtons(["Auto", "Manual", "Disabled"], selection: selection.projectedValue,
            header: "Mode", isEnabled: { $0 != "Disabled" })
        let native = group._makeView(in: FluentRenderContext())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = native
        defer { window.close() }
        native.layoutSubtreeIfNeeded()
        let radios = native.subviews.compactMap { $0 as? FluentRadioButton }
        XCTAssertEqual(radios.count, 3)
        XCTAssertTrue(native.isAccessibilityElement())
        XCTAssertEqual(native.accessibilityRole(), .radioGroup)
        XCTAssertEqual(native.accessibilityLabel(), "Mode")
        XCTAssertEqual(native.accessibilityChildren()?.compactMap { $0 as? FluentRadioButton }.count, 3)
        XCTAssertTrue(radios.allSatisfy { $0.isAccessibilityElement() })
        XCTAssertTrue(radios[1].accessibilityPerformPress())
        XCTAssertEqual(selection.wrappedValue, "Manual")
        XCTAssertEqual(radios.map { $0.accessibilityValue() as? NSNumber }, [0, 1, 0])
        XCTAssertFalse(radios[2].accessibilityPerformPress())
        selection.wrappedValue = nil
        XCTAssertEqual(radios.map { $0.accessibilityValue() as? NSNumber }, [0, 0, 0])
        selection.wrappedValue = "Auto"
        XCTAssertEqual(radios.map { $0.accessibilityValue() as? NSNumber }, [1, 0, 0])
    }

    @MainActor func testNativeSiblingsShareTheirParentAndArrowNavigation() {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        let parent = NSView(frame: root.bounds); root.addSubview(parent)
        let first = FluentRadioButton(title: "First", isSelected: true)
        let second = FluentRadioButton(title: "Second")
        let disabled = FluentRadioButton(title: "Disabled"); disabled.isEnabled = false
        for (i, radio) in [first, second, disabled].enumerated() {
            radio.frame = NSRect(x: 10, y: 30 + i * 40, width: 200, height: 32); parent.addSubview(radio)
        }
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root
        defer { window.close() }
        XCTAssertTrue(second.accessibilityPerformPress())
        XCTAssertFalse(first.isSelected, "Unnamed native siblings in a plain NSView must be exclusive")
        XCTAssertTrue(second.isSelected)
        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        second.keyDown(with: right)
        XCTAssertTrue(first.isSelected, "Independent group navigation wraps and skips the disabled member")
        XCTAssertFalse(second.isSelected)
        XCTAssertEqual(first.accessibilityHelp(), "Option 1 of 3")
    }

    @MainActor func testSeparateNativeParentsAreNotAccidentallyOneGroupAndBoundAdaptersStayTransparent() {
        _ = NSApplication.shared
        let root = NSView()
        let aParent = NSView(), bParent = NSView()
        root.addSubview(aParent); root.addSubview(bParent)
        let a = FluentRadioButton(title: "A"), b = FluentRadioButton(title: "B")
        aParent.addSubview(a); bParent.addSubview(b)
        a.isSelected = true; b.isSelected = true
        XCTAssertTrue(a.isSelected, "WinUI unnamed groups use the immediate parent, even when it has only one child")
        XCTAssertTrue(b.isSelected)

        let firstValue = FluentState(wrappedValue: true), secondValue = FluentState(wrappedValue: false)
        let parent = NSView()
        let first = FluentBoundRadioButton(firstValue.projectedValue, title: "Bound 1")
        let second = FluentBoundRadioButton(secondValue.projectedValue, title: "Bound 2")
        parent.addSubview(first); parent.addSubview(second)
        XCTAssertTrue(second.radioButton.accessibilityPerformPress())
        XCTAssertFalse(firstValue.wrappedValue)
        XCTAssertTrue(secondValue.wrappedValue, "A binding adapter is not a semantic group boundary")
        // Explicit names deliberately bridge different parents in the same window/root.
        a.groupName = "shared"; b.groupName = "shared"
        a.isSelected = true
        XCTAssertFalse(b.isSelected)
        a.groupName = " scoped "; b.groupName = "scoped"
        a.isSelected = true; b.isSelected = true
        XCTAssertTrue(a.isSelected, "WinUI group names are exact identifiers, not trimmed labels")
    }
}
