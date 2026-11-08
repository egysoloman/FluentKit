import XCTest
@testable import FluentKit

@MainActor
final class PipsPagerAppearanceTests: XCTestCase {
    private func resolved(_ color: NSColor, dark: Bool) -> CGColor {
        var result = color.cgColor
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            result = (color.usingColorSpace(.deviceRGB) ?? color).cgColor
        }
        return result
    }

    private func assertColor(_ actual: CGColor?, _ expected: CGColor,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let actualColor = try XCTUnwrap(actual.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB), file: file, line: line)
        let expectedColor = try XCTUnwrap(NSColor(cgColor: expected)?.usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(actualColor.alphaComponent, expectedColor.alphaComponent, accuracy: 0.002, file: file, line: line)
    }

    private func colorsMatch(_ actual: CGColor?, _ expected: CGColor) -> Bool {
        guard let actual = actual.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB),
              let expected = NSColor(cgColor: expected)?.usingColorSpace(.sRGB) else { return false }
        return abs(actual.redComponent - expected.redComponent) < 0.002
            && abs(actual.greenComponent - expected.greenComponent) < 0.002
            && abs(actual.blueComponent - expected.blueComponent) < 0.002
            && abs(actual.alphaComponent - expected.alphaComponent) < 0.002
    }

    private func layer(_ suffix: String, in button: NSView) throws -> CALayer {
        try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.PipsPager.\(suffix)" })
    }

    private func mount(_ pager: FluentPipsPager, dark: Bool) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView?.addSubview(pager)
        pager.frame = NSRect(x: 40, y: 80, width: 160, height: 24)
        pager.reduceMotion = true
        window.makeKeyAndOrderFront(nil)
        pager.layoutSubtreeIfNeeded()
        return window
    }

    func testHighContrastResourcesResolveBeforeLeavingTheRequestedAppearance() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            var foreground: CGColor?
            var background: CGColor?
            var disabled: CGColor?
            NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
                foreground = theme.pipsPagerIndicatorForeground(selected: false, state: .normal).cgColor
                background = theme.pipsPagerIndicatorBackground(selected: false, state: .normal).cgColor
                disabled = theme.pipsPagerNavigationForeground(for: .disabled).cgColor
            }
            try assertColor(foreground, resolved(.controlTextColor, dark: dark))
            try assertColor(background, resolved(.controlBackgroundColor, dark: dark))
            try assertColor(disabled, resolved(.disabledControlTextColor, dark: dark))
        }
    }

    func testNavigationBorderUsesItsStateResource() throws {
        for dark in [false, true] {
            let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2,
                                       previousButtonVisibility: .visible, nextButtonVisibility: .visible)
            pager.theme = .custom(contrast: .high, colorScheme: dark ? .dark : .light)
            let window = mount(pager, dark: dark)
            defer { window.close() }
            let button = pager.nextButton
            let chrome = try layer("NavigationChrome", in: button)
            try assertColor(chrome.borderColor, resolved(.controlBackgroundColor, dark: dark))
            button.setPointerHover(true)
            try assertColor(chrome.borderColor, resolved(.linkColor, dark: dark))
            let press = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
            button.keyDown(with: press)
            try assertColor(chrome.borderColor, resolved(.linkColor, dark: dark))
            button.isEnabled = false
            try assertColor(chrome.borderColor, resolved(.controlBackgroundColor, dark: dark))
            try assertColor(chrome.backgroundColor, resolved(.controlBackgroundColor, dark: dark))
        }
    }

    func testHighContrastNavigationHighlightHasReadableContrast() throws {
        func luminance(_ color: NSColor) throws -> CGFloat {
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            let linear = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        for dark in [false, true] {
            let theme = FluentTheme.custom(contrast: .high, colorScheme: dark ? .dark : .light)
            for state: FluentControlState in [.pointerOver, .pressed] {
                let foreground = try luminance(theme.pipsPagerNavigationForeground(for: state))
                let background = try luminance(theme.pipsPagerNavigationBackground(for: state))
                let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                XCTAssertGreaterThanOrEqual(contrast, 3, "The small navigation glyph must remain visible")
            }
        }
    }

    func testLiveExplicitThemesResolvePipColorsOutsideDrawingCallbacks() throws {
        let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2,
                                   previousButtonVisibility: .visible, nextButtonVisibility: .visible)
        let window = mount(pager, dark: false)
        defer { window.close() }
        let normal = try XCTUnwrap(pager.realizedPipButtons[0])
        let selected = try XCTUnwrap(pager.realizedPipButtons[2])
        let glyph = try XCTUnwrap(layer("PipGlyph", in: selected) as? CAShapeLayer)
        for dark in [true, false] {
            NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
                pager.theme = .custom(contrast: .high, colorScheme: dark ? .dark : .light)
            }
            try assertColor(try layer("PipChrome", in: normal).backgroundColor, resolved(.controlBackgroundColor, dark: dark))
            try assertColor(try layer("PipChrome", in: selected).backgroundColor, resolved(.selectedContentBackgroundColor, dark: dark))
            try assertColor(glyph.fillColor, resolved(.selectedMenuItemTextColor, dark: dark))
            XCTAssertEqual(glyph.path?.boundingBox.width, 6)
            XCTAssertEqual(selected.accessibilityValue() as? Int, 1)
            XCTAssertTrue(pager.realizedPipButtons[2] === selected)
            XCTAssertEqual(pager.selectedPageIndex, 2)
        }
    }

    func testSystemThemeTracksContainingWindowWithoutReplacingButtons() throws {
        _ = NSApplication.shared
        let originalAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = originalAppearance }
        for contrast: FluentThemeContrast in [.standard, .high] {
            let pager = FluentPipsPager(numberOfPages: 5, selectedPageIndex: 2)
            pager.theme = .custom(contrast: contrast, colorScheme: .system)
            let window = mount(pager, dark: false)
            defer { window.close() }
            let pip = try XCTUnwrap(pager.realizedPipButtons[0])
            let chrome = try layer("PipChrome", in: pip)
            let glyph = try XCTUnwrap(layer("PipGlyph", in: pip) as? CAShapeLayer)
            for dark in [true, false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let reference = FluentTheme.custom(contrast: contrast, colorScheme: dark ? .dark : .light)
                let expectedForeground = resolved(contrast == .high ? .controlTextColor : reference.controlStrokeStrong, dark: dark)
                let expectedBackground = resolved(contrast == .high ? .controlBackgroundColor : .clear, dark: dark)
                waitForUI(colorsMatch(glyph.fillColor, expectedForeground))
                try assertColor(chrome.backgroundColor, expectedBackground)
                try assertColor(glyph.fillColor, expectedForeground)
                XCTAssertTrue(pager.realizedPipButtons[0] === pip)
                XCTAssertEqual(pager.selectedPageIndex, 2)
            }
        }
    }
}
