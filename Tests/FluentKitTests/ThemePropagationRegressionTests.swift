import XCTest
@testable import FluentKit

final class ThemePropagationRegressionTests: XCTestCase {
    @MainActor func testOpenComboBoxFollowsItsHostThemeWithoutAWindowCoordinator() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "中文")
        let definition = FluentComboBox(options: ["中文", "英文"], selection: selection.projectedValue)
        let native = definition._makeView(in: .init(theme: .custom(colorScheme: .light), reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 240, height: 40),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = native; window.makeKeyAndOrderFront(nil); native.layoutSubtreeIfNeeded()
        XCTAssertNil(window.fluentAppearanceCoordinator)
        let bridge = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.ComboBox.NativeBridge" } as? NSComboBox)
        bridge.performClick(nil)
        let popup = try XCTUnwrap(window.childWindows?.first)
        for scheme in [FluentThemeColorScheme.dark, .light] {
            XCTAssertTrue(definition._updateView(native, in: .init(theme: .custom(colorScheme: scheme), reduceMotion: true)))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertTrue(window.childWindows?.first === popup)
            XCTAssertTrue(popup.isVisible)
            XCTAssertEqual(popup.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), scheme == .dark ? .darkAqua : .aqua)
            XCTAssertEqual(selection.wrappedValue, "中文")
        }
    }
}
