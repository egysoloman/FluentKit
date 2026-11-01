import XCTest
@testable import FluentKit

@MainActor
final class WindowCaptionGeometryTests: XCTestCase {
    func testCaptionButtonsFillTheirToolTipHostsForEveryGlyphAndHeaderHeight() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 200),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let header = NSView(frame: NSRect(x: 0, y: 168, width: 600, height: 32))
        root.addSubview(header)
        window.contentView = root
        window.applyFluentWindowControlsStyle(.windows, titleBarHeight: 32, hostedIn: header)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        root.layoutSubtreeIfNeeded()
        let controls = try XCTUnwrap(header.subviews.first { $0.identifier?.rawValue == "FluentKit.WindowControls.Windows" })
        let hosts = controls.subviews.compactMap { $0 as? FluentToolTipHost }
        XCTAssertEqual(hosts.count, 3)
        for height: CGFloat in [32, 40, 48] {
            header.frame = NSRect(x: 0, y: 200-height, width: 600, height: height)
            root.layoutSubtreeIfNeeded()
            for host in hosts {
                let button = try XCTUnwrap(host.contentView as? NSButton)
                XCTAssertEqual(host.bounds, NSRect(x: 0, y: 0, width: 46, height: height))
                XCTAssertEqual(button.frame, host.bounds, "caption background and hit target must fill exactly one slot")
                XCTAssertEqual(button.alignmentRect(forFrame: button.frame), button.frame)
            }
            // Restore uses a different symbol. It must not change the button geometry either.
            let maximize = try XCTUnwrap(hosts[1].contentView as? NSButton)
            let original = maximize.image
            maximize.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(maximize.frame, hosts[1].bounds)
            maximize.image = original
        }
    }
}
