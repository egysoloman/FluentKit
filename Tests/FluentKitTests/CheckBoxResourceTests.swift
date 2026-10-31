import XCTest
@testable import FluentKit

/// Expected roles come from CheckBox_themeresources.xaml in the pinned WinUI 2.3.1 source.
final class CheckBoxResourceTests: XCTestCase {
    private let states: [FluentControlState] = [.normal, .pointerOver, .pressed, .disabled]

    private func assertColor(_ actual: NSColor, _ expected: NSColor, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let a = actual.usingColorSpace(.deviceRGB)!, e = expected.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(a.redComponent, e.redComponent, accuracy: 0.001, message + " red", file: file, line: line)
        XCTAssertEqual(a.greenComponent, e.greenComponent, accuracy: 0.001, message + " green", file: file, line: line)
        XCTAssertEqual(a.blueComponent, e.blueComponent, accuracy: 0.001, message + " blue", file: file, line: line)
        XCTAssertEqual(a.alphaComponent, e.alphaComponent, accuracy: 0.001, message + " alpha", file: file, line: line)
    }

    @MainActor func testStandardCheckBoxUsesWinUIAltFillAndStrongStrokeResources() {
        _ = NSApplication.shared
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .standard, colorScheme: dark ? .dark : .light)
            for checked in [false, true] { for (index, state) in states.enumerated() {
                let a = FluentAutomaticCheckBoxStyle().appearance(for: .init(isChecked: checked,
                    isEnabled: state != .disabled, isPointerOver: state == .pointerOver,
                    isPressed: state == .pressed, controlSize: .regular, theme: theme))
                let name = "dark=\(dark) checked=\(checked) state=\(state)"
                // Literal alpha values from Common_themeresources_any.xaml, not Button tokens.
                let fills: [NSColor] = dark
                    ? [NSColor(calibratedWhite: 0, alpha: 25/255), NSColor(calibratedWhite: 1, alpha: 11/255), NSColor(calibratedWhite: 1, alpha: 18/255), .clear]
                    : [NSColor(calibratedWhite: 0, alpha: 6/255), NSColor(calibratedWhite: 0, alpha: 15/255), NSColor(calibratedWhite: 0, alpha: 24/255), .clear]
                let disabledAlpha: CGFloat = dark ? 40.0/255 : 55.0/255
                let normalAlpha: CGFloat = dark ? 139.0/255 : 114.0/255
                let strokeAlpha = state == .disabled || (!checked && state == .pressed) ? disabledAlpha : normalAlpha
                let stroke = checked && state != .disabled ? theme.accentFill(for: state)
                    : NSColor(calibratedWhite: dark ? 1 : 0, alpha: strokeAlpha)
                assertColor(a.fillColor, checked ? theme.accentFill(for: state) : fills[index], name + " fill")
                assertColor(a.borderColor, stroke, name + " stroke")
                assertColor(a.markColor, state == .disabled ? theme.textOnAccentDisabled
                    : (checked && state == .pressed ? theme.textOnAccentSecondary : theme.textOnAccent), name + " glyph")
                XCTAssertEqual(a.boxSize, 20, name)
                XCTAssertEqual(a.cornerRadius, 4, name)
                XCTAssertEqual(a.borderWidth, 1, name)
            } }
        }
    }

    @MainActor func testHighContrastHasItsOwnCheckedAndUncheckedResourceMatrix() {
        _ = NSApplication.shared
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            appearance.performAsCurrentDrawingAppearance {
                for checked in [false, true] { for (i, state) in states.enumerated() {
                    let a = FluentAutomaticCheckBoxStyle().appearance(for: .init(isChecked: checked,
                        isEnabled: state != .disabled, isPointerOver: state == .pointerOver,
                        isPressed: state == .pressed, controlSize: .regular, theme: theme))
                    let fills: [NSColor] = checked
                        ? [.selectedContentBackgroundColor, .controlTextColor, .controlBackgroundColor, .disabledControlTextColor]
                        : [.controlBackgroundColor, .selectedMenuItemTextColor, .selectedContentBackgroundColor, theme.windowBackground]
                    let strokes: [NSColor] = checked ? fills
                        : [.controlTextColor, .selectedContentBackgroundColor, .selectedContentBackgroundColor, .disabledControlTextColor]
                    let glyphs: [NSColor] = checked
                        ? [.selectedMenuItemTextColor, .controlBackgroundColor, .controlTextColor, theme.windowBackground]
                        : [.controlBackgroundColor, .selectedContentBackgroundColor, .selectedMenuItemTextColor, .disabledControlTextColor]
                    let name = "HC dark=\(dark) checked=\(checked) state=\(state)"
                    assertColor(a.fillColor, fills[i], name + " fill")
                    assertColor(a.borderColor, strokes[i], name + " stroke")
                    assertColor(a.markColor, glyphs[i], name + " glyph")
                    assertColor(a.labelColor, state == .disabled ? .disabledControlTextColor : .controlTextColor, name + " label")
                    XCTAssertEqual(a.borderWidth, 1, name)
                } }
            }
        }
    }

    @MainActor func testTreeIndeterminateHighContrastUsesIndeterminateRatherThanCheckedBrushes() throws {
        _ = NSApplication.shared
        let identity = NSObject()
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            let cell = FluentOutlineCellHost(frame: NSRect(x: 0, y: 0, width: 250, height: 32))
            cell.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            cell.effectiveAppearance.performAsCurrentDrawingAppearance {
                cell.update(representedItem: ObjectIdentifier(identity), content: FluentAnyView(FluentText("Parent")),
                    context: FluentRenderContext(theme: theme, reduceMotion: true),
                    layout: .init(depth: 0, isMultiple: true, isExpandable: true, isExpanded: false,
                        checkState: .mixed, rowHeight: 32, isRightToLeft: false), onToggleExpansion: {}, onToggleCheck: {})
                cell.layoutSubtreeIfNeeded()
                let background = cell.layer?.sublayers?.first { $0.name == "FluentKit.TreeView.CheckBoxBackground" }
                XCTAssertEqual(background?.frame.minY, 4, "HC margin and border remain outside the opaque checkbox presenter")
                XCTAssertEqual(background?.frame.maxY, 28)
                cell.updateCheckBoxPointer(at: NSPoint(x: cell.checkBoxFrame.midX, y: cell.checkBoxFrame.midY))
                assertColor(NSColor(cgColor: cell.checkBoxLayer.backgroundColor!)!, .selectedMenuItemTextColor, "mixed hover fill")
                assertColor(NSColor(cgColor: cell.checkBoxLayer.borderColor!)!, .selectedContentBackgroundColor, "mixed hover stroke")
                assertColor(NSColor(cgColor: cell.checkMarkLayer.strokeColor!)!, .selectedContentBackgroundColor, "mixed hover dash")
                cell.beginCheckBoxPress()
                assertColor(NSColor(cgColor: cell.checkBoxLayer.backgroundColor!)!, .selectedContentBackgroundColor, "mixed pressed fill")
                assertColor(NSColor(cgColor: cell.checkMarkLayer.strokeColor!)!, .selectedMenuItemTextColor, "mixed pressed dash")
                cell.cancelCheckBoxPress()
            }
        }
    }

    @MainActor func testCapturedCheckBoxRevertsAppearanceOutsideAndStillCommitsOnReentry() throws {
        _ = NSApplication.shared
        let style = RecordingCheckBoxStyle()
        let box = FluentCheckBox(title: "Keep capture")
        box.fluentStyle = style; box.reduceMotion = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView!.addSubview(box); box.frame = NSRect(x: 10, y: 20, width: 180, height: 32)
        defer { window.close() }
        var notifications = 0
        box.onValueChanged = { _ in notifications += 1 }
        func event(_ type: NSEvent.EventType, inside: Bool) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: box.convert(NSPoint(x: inside ? 12 : 200, y: 16), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        box.mouseDown(with: event(.leftMouseDown, inside: true))
        XCTAssertEqual(style.last?.isPressed, true)
        box.mouseDragged(with: event(.leftMouseDragged, inside: false))
        XCTAssertEqual(style.last?.isPressed, false, "A retained press must not retain the pressed visual outside")
        XCTAssertEqual(style.last?.isPointerOver, false)
        box.mouseUp(with: event(.leftMouseUp, inside: false))
        XCTAssertFalse(box.isChecked); XCTAssertEqual(notifications, 0)
        box.mouseDown(with: event(.leftMouseDown, inside: true))
        box.mouseDragged(with: event(.leftMouseDragged, inside: false))
        box.mouseDragged(with: event(.leftMouseDragged, inside: true))
        XCTAssertEqual(style.last?.isPressed, true)
        XCTAssertFalse(box.isChecked); XCTAssertEqual(notifications, 0)
        box.mouseUp(with: event(.leftMouseUp, inside: true))
        XCTAssertTrue(box.isChecked); XCTAssertEqual(notifications, 1)
    }

    @MainActor func testExplicitHighContrastThemeResolvesColorsOutsideDrawingCallbacks() {
        _ = NSApplication.shared
        // AppKit resolves dynamic NSColor.cgColor against the current drawing appearance,
        // which can differ from a control's explicit theme during binding/event updates.
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            var expected = NSColor.clear
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                expected = NSColor.controlTextColor.usingColorSpace(.deviceRGB)!
            }
            NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
                let appearance = FluentAutomaticCheckBoxStyle().appearance(for: .init(isChecked: true,
                    isEnabled: true, isPointerOver: true, controlSize: .regular, theme: theme))
                assertColor(NSColor(cgColor: appearance.fillColor.cgColor)!, expected, "Explicit theme must own resolved layer colors")
            }
        }
    }

    @MainActor func testStandaloneCheckBoxIsExposedAsAnAccessibleCheckBox() {
        _ = NSApplication.shared
        let box = FluentCheckBox(title: "Accessible option")
        XCTAssertTrue(box.isAccessibilityElement())
        XCTAssertEqual(box.accessibilityRole(), .checkBox)
        XCTAssertEqual(box.accessibilityValue() as? NSNumber, 0)
        XCTAssertTrue(box.accessibilityPerformPress())
        XCTAssertEqual(box.accessibilityValue() as? NSNumber, 1)
        box.isEnabled = false
        XCTAssertFalse(box.accessibilityPerformPress())
        XCTAssertEqual(box.accessibilityValue() as? NSNumber, 1)
    }
}

private final class RecordingCheckBoxStyle: FluentCheckBoxStyle {
    var last: FluentCheckBoxStyleConfiguration?
    func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        last = configuration
        return FluentAutomaticCheckBoxStyle().appearance(for: configuration)
    }
}
