import AppKit
import XCTest
@testable import FluentKit

private struct SquareCheckStyle: FluentCheckBoxStyle {
    func appearance(for c: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        let a = FluentAutomaticCheckBoxStyle().appearance(for: c)
        return FluentCheckBoxAppearance(boxSize: a.boxSize, cornerRadius: 0, fillColor: a.fillColor,
            borderColor: a.borderColor, borderWidth: a.borderWidth, markColor: a.markColor,
            labelColor: a.labelColor, labelFont: a.labelFont, labelSpacing: a.labelSpacing)
    }
}

final class ChoiceFocusTests: XCTestCase {
    @MainActor private func makeControl(radio: Bool, theme: FluentTheme) -> NSControl {
        if radio {
            let control = FluentRadioButton(title: "Focus 焦点")
            control.theme = theme; control.reduceMotion = true
            return control
        }
        let control = FluentCheckBox(title: "Focus 焦点")
        control.theme = theme; control.reduceMotion = true
        return control
    }

    private func assertColor(_ actual: CGColor?, _ expected: NSColor,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let actual, let a = NSColor(cgColor: actual)?.usingColorSpace(.deviceRGB),
              let e = expected.usingColorSpace(.deviceRGB) else {
            return XCTFail("Missing focus brush", file: file, line: line)
        }
        for (x, y) in zip([a.redComponent, a.greenComponent, a.blueComponent, a.alphaComponent],
                          [e.redComponent, e.greenComponent, e.blueComponent, e.alphaComponent]) {
            XCTAssertEqual(x, y, accuracy: 0.001, file: file, line: line)
        }
    }

    @MainActor func testChoiceFocusUsesWinUIMarginsBorderWidthsAndCornerAdjustment() {
        _ = NSApplication.shared
        for radio in [false, true] { for rtl in [false, true] {
            let control = makeControl(radio: radio, theme: .custom(colorScheme: .light))
            control.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            for width: CGFloat in [120, 240] {
                control.frame = NSRect(x: 0, y: 0, width: width, height: 32)
                control.layoutSubtreeIfNeeded()
                let prefix = radio ? "FluentKit.RadioButton" : "FluentKit.CheckBox"
                let outer = control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing" } as? CAShapeLayer
                let inner = control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing.Inner" } as? CAShapeLayer
                XCTAssertNotNil(outer, "Primary focus is a 2pt shape border")
                XCTAssertNotNil(inner, "Secondary focus is a separate 1pt border")
                // WinUI margin (-7,-3), outer border 2, inner border 1. Border's CornerRadius
                // describes its centerline; AdjustCornerRadius adds (7+3)/2 then subtracts 2.
                XCTAssertEqual(outer?.path, CGPath(roundedRect: CGRect(x: -6, y: -2, width: width + 12, height: 36),
                    cornerWidth: 9, cornerHeight: 9, transform: nil))
                XCTAssertEqual(inner?.path, CGPath(roundedRect: CGRect(x: -4.5, y: -0.5, width: width + 9, height: 33),
                    cornerWidth: 7, cornerHeight: 7, transform: nil))
                XCTAssertEqual(outer?.lineWidth, 2); XCTAssertEqual(inner?.lineWidth, 1)
                XCTAssertFalse(control.layer?.masksToBounds ?? true)
            }
        } }
    }

    @MainActor func testChoiceFocusBrushesFollowExplicitThemeAndHighContrastRoles() {
        _ = NSApplication.shared
        for radio in [false, true] { for dark in [false, true] { for high in [false, true] {
            let theme = FluentTheme.custom(contrast: high ? .high : .standard, colorScheme: dark ? .dark : .light)
            let control = makeControl(radio: radio, theme: theme)
            var expected: [NSColor] = []
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                expected = high ? [.controlTextColor, .controlBackgroundColor] : [
                    dark ? .white : NSColor(calibratedWhite: 0, alpha: 228.0 / 255),
                    NSColor(calibratedWhite: dark ? 0 : 1, alpha: 179.0 / 255)]
                expected = expected.map { $0.usingColorSpace(.deviceRGB)! }
            }
            NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
                control.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
                control.layoutSubtreeIfNeeded()
                let prefix = radio ? "FluentKit.RadioButton" : "FluentKit.CheckBox"
                let outer = control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing" }
                let inner = control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing.Inner" }
                assertColor((outer as? CAShapeLayer)?.strokeColor ?? outer?.borderColor, expected[0])
                assertColor((inner as? CAShapeLayer)?.strokeColor, expected[1])
            }
        } } }
    }

    @MainActor func testChoiceFocusVisibilityAndStandardModeDoNotInventRevealPressAnimation() throws {
        _ = NSApplication.shared
        for radio in [false, true] {
            let control = makeControl(radio: radio, theme: .custom(colorScheme: .dark))
            if let box = control as? FluentCheckBox { box.reduceMotion = false }
            if let button = control as? FluentRadioButton { button.reduceMotion = false }
            control.frame = NSRect(x: 20, y: 20, width: 180, height: 32)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView!.addSubview(control)
            defer { window.close() }
            window.makeFirstResponder(control)
            let prefix = radio ? "FluentKit.RadioButton" : "FluentKit.CheckBox"
            let outer = try XCTUnwrap(control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing" })
            XCTAssertEqual(outer.opacity, 0, "Programmatic focus alone is not keyboard modality")
            func key(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: " ",
                    charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
            }
            control.keyDown(with: key(.keyDown)); XCTAssertEqual(outer.opacity, 1)
            let path = (outer as? CAShapeLayer)?.path
            control.keyUp(with: key(.keyUp)); XCTAssertEqual(outer.opacity, 1)
            XCTAssertEqual((outer as? CAShapeLayer)?.path, path)
            XCTAssertTrue((outer.animationKeys() ?? []).isEmpty)
            control.isEnabled = false
            XCTAssertEqual(outer.opacity, 0, "A disabled choice must not retain its focus highlight")
            window.makeFirstResponder(nil)
            XCTAssertEqual(outer.opacity, 0)
        }
    }

    @MainActor func testSquareCheckBoxDoesNotGainRoundedFocusCorners() {
        _ = NSApplication.shared
        let box = FluentCheckBox(); box.fluentStyle = SquareCheckStyle()
        box.frame = NSRect(x: 0, y: 0, width: 180, height: 32); box.layoutSubtreeIfNeeded()
        let outer = box.layer?.sublayers?.first { $0.name == "FluentKit.CheckBox.FocusRing" } as? CAShapeLayer
        let inner = box.layer?.sublayers?.first { $0.name == "FluentKit.CheckBox.FocusRing.Inner" } as? CAShapeLayer
        XCTAssertEqual(outer?.path, CGPath(roundedRect: CGRect(x: -6, y: -2, width: 192, height: 36),
            cornerWidth: 0, cornerHeight: 0, transform: nil))
        XCTAssertEqual(inner?.path, CGPath(roundedRect: CGRect(x: -4.5, y: -0.5, width: 189, height: 33),
            cornerWidth: 0, cornerHeight: 0, transform: nil))
    }
}
