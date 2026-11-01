import XCTest
@testable import FluentKit

final class TextCommandThemeTests: XCTestCase {
    @MainActor
    func testOpenTextMenusFollowTheirControlThemeInPlainWindows() throws {
        _ = NSApplication.shared
        let text = FluentTextField()
        let search = FluentSearchTextField()
        let password = FluentSecureTextField()
        let fields: [(NSTextField, (FluentTheme) -> Void)] = [
            (text, { text.theme = $0 }),
            (search, { search.theme = $0 }),
            (password, { password.theme = $0 })
        ]
        for (field, setTheme) in fields {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 400, height: 180),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            XCTAssertNil(window.fluentAppearanceCoordinator)
            let initial = FluentTheme.custom(colorScheme: .dark)
                .with(materialConfiguration: .init(material: .nativeAcrylic, isEnabled: false), for: .transient)
            setTheme(initial)
            field.frame = NSRect(x: 30, y: 100, width: 300, height: 32)
            field.stringValue = "Search text"
            window.contentView?.addSubview(field)
            window.makeKeyAndOrderFront(nil)
            field.selectText(nil)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.setSelectedRange(NSRange(location: 1, length: 3))
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown,
                location: field.convert(NSPoint(x: 50, y: 16), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            field.rightMouseDown(with: event)
            let panel = try XCTUnwrap(window.childWindows?.first)
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let surface = try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView))
                .compactMap { $0 as? FluentMaterialView }.first)
            XCTAssertEqual(surface.resolvedBackend, .opaque)
            let enabled = FluentTheme.custom(colorScheme: .light)
                .with(materialConfiguration: .init(material: .nativeAcrylic, isEnabled: true), for: .transient)
            setTheme(enabled)
            XCTAssertEqual(surface.fluentTheme, enabled)
            XCTAssertEqual(surface.resolvedBackend,
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .opaque : .visualEffect)
            XCTAssertEqual(panel.appearance?.name, .aqua)
            XCTAssertTrue(window.childWindows?.first === panel)
            XCTAssertTrue(field.currentEditor() === editor)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 3))
            XCTAssertEqual(editor.string, "Search text")
            setTheme(initial)
            XCTAssertEqual(surface.resolvedBackend, .opaque)
            XCTAssertEqual(panel.appearance?.name, .darkAqua)
            XCTAssertTrue(panel.isVisible)
            field.rightMouseDown(with: event)
            waitForUI(window.childWindows?.isEmpty != false)
        }
    }
}
