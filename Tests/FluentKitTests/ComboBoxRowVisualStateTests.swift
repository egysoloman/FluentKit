import XCTest
@testable import FluentKit

@MainActor
final class ComboBoxRowVisualStateTests: XCTestCase {
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    func testImmediateSelectionUpdatesDoNotInheritAmbientLayerAnimations() throws {
        _ = NSApplication.shared
        for reduceMotion in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 500, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let anchor = NSView(frame: NSRect(x: 60, y: 170, width: 240, height: 32))
            window.contentView?.addSubview(anchor)
            window.makeKeyAndOrderFront(nil)
            let popup = FluentComboBoxPopup(titles: ["Alpha", "Charlie"], selectedIndex: 0,
                placement: .editable, theme: .custom(colorScheme: .dark), layoutDirection: .leftToRight,
                reduceMotion: reduceMotion, onMove: { _ in }, onCommit: { _ in }, onDismiss: {})
            popup.present(relativeTo: anchor)
            defer { popup.dismiss(animated: false) }
            let panel = try XCTUnwrap(window.childWindows?.first)
            panel.displayIfNeeded()
            CATransaction.flush()
            let rows = all(try XCTUnwrap(panel.contentView)).filter { $0.accessibilityRole() == .menuItem }
            XCTAssertEqual(rows.count, 2)
            let layers = rows.flatMap { $0.layer?.sublayers ?? [] }
            let pills = layers.filter { $0.name?.contains("ComboBoxItem.") == true && $0.name?.contains("Pill") == true }
            let surfaces = layers.filter { $0.name == "FluentKit.ComboBoxItem.Background" }
            XCTAssertEqual(pills.count, 2)
            layers.forEach { $0.removeAllAnimations() }

            // An ancestor's transaction must not turn a nonanimated row selection update
            // into a fade, which would leave both the old and new selection pills visible.
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(10)
            popup.updateSelectedIndex(1)
            CATransaction.commit()
            CATransaction.flush()

            XCTAssertEqual(pills.map(\.opacity), [0, 1])
            for layer in pills + surfaces {
                XCTAssertTrue((layer.animationKeys() ?? []).isEmpty,
                    "reduceMotion=\(reduceMotion) layer=\(layer.name ?? "") keys=\(layer.animationKeys() ?? [])")
            }
        }
    }
}
