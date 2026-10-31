import XCTest
@testable import FluentKit

final class RTLStackLayoutTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    func testNestedHorizontalStackKeepsButtonsInsideItsOwnBounds() throws {
        _ = NSApplication.shared
        func content(_ message: String) -> FluentVStackView { FluentVStack {
            FluentText("Toolbar").frame(width: 440, height: 100)
            FluentHStack(spacing: 12) {
                FluentButtonView("Collapse all") {}
                FluentButtonView("Reset tree") {}
            }
            FluentText(message, style: .caption)
            FluentText("Drag one item to move it. Use arrow keys to browse and Space to toggle a check box.", style: .caption)
        } }
        let host = FluentViewHost(content("Open Remote to load its children."), context: FluentRenderContext(reduceMotion: true, layoutDirection: .rightToLeft))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        host.wantsLayer = true
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        for (index, setting) in [(FluentLayoutDirection.rightToLeft, 600.0), (.rightToLeft, 450.0), (.leftToRight, 450.0), (.rightToLeft, 600.0)].enumerated() {
            let (direction, width) = setting
            window.setContentSize(NSSize(width: width, height: 240))
            if index > 0 { host.update(content("Collapsed work"), context: FluentRenderContext(reduceMotion: true, layoutDirection: direction)) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
            let buttons = descendants(host).compactMap { $0 as? FluentButton }
            XCTAssertEqual(buttons.count, 2)
            let stack = try XCTUnwrap(buttons.first?.superview as? NSStackView)
            let rects = buttons.map { $0.alignmentRect(forFrame: $0.frame) }
            for (index, rect) in rects.enumerated() {
                XCTAssertGreaterThanOrEqual(rect.minX, stack.bounds.minX - 0.5)
                XCTAssertLessThanOrEqual(rect.maxX, stack.bounds.maxX + 0.5)
                XCTAssertEqual(rect.width, buttons[index].intrinsicContentSize.width, accuracy: 0.5)
            }
            if direction == .rightToLeft {
                XCTAssertEqual(rects[0].minX - rects[1].maxX, 12, accuracy: 0.5)
                XCTAssertEqual(rects[0].maxX, stack.bounds.maxX, accuracy: 0.5)
                XCTAssertEqual(host.convert(stack.bounds, from: stack).maxX, host.bounds.width, accuracy: 0.5)
            } else {
                XCTAssertEqual(rects[1].minX - rects[0].maxX, 12, accuracy: 0.5)
                XCTAssertEqual(rects[0].minX, stack.bounds.minX, accuracy: 0.5)
            }
        }
    }
}
