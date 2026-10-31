import XCTest
@testable import FluentKit

final class LayoutAPIRegressionTests: XCTestCase {
    @MainActor
    private func mount(_ view: FluentAnyView, size: NSSize = NSSize(width: 600, height: 400)) -> FluentViewHost<FluentAnyView> {
        _ = NSApplication.shared
        let host = FluentViewHost(view, context: FluentRenderContext(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    func testFrameSizeIsHonouredOverContentHugging() {
        let host = mount(FluentAnyView(FluentVStack(spacing: 0) {
            FluentText("Row", style: .body).padding(6).frame(width: 300, height: 32)
            FluentText("Row", style: .body).padding(6).frame(width: 300, height: 32)
        }))
        let frames = descendants(host).filter { view in
            view.constraints.contains { $0.identifier == "FluentKit.IdealHeight" }
        }
        XCTAssertEqual(frames.count, 2)
        for view in frames {
            XCTAssertEqual(view.frame.height, 32, accuracy: 0.5, "An explicit frame height wins over the text's own height")
            XCTAssertEqual(view.frame.width, 300, accuracy: 0.5)
        }
    }

    @MainActor
    func testForEachFollowsAHorizontalStack() {
        let host = mount(FluentAnyView(FluentHStack(spacing: 8) {
            FluentForEach(["A", "B", "C"], id: { $0 }) { FluentText($0) }
        }))
        let labels = descendants(host).compactMap { $0 as? NSTextField }.filter { ["A", "B", "C"].contains($0.stringValue) }
        XCTAssertEqual(labels.count, 3)
        let frames = labels.map { $0.convert($0.bounds, to: host) }
        XCTAssertEqual(frames[0].midY, frames[1].midY, accuracy: 1, "Items lie on one row inside an HStack")
        XCTAssertLessThan(frames[0].maxX, frames[1].minX)
        XCTAssertLessThan(frames[1].maxX, frames[2].minX)
    }

    @MainActor
    func testForEachStaysVerticalInAVerticalStack() {
        let host = mount(FluentAnyView(FluentVStack(spacing: 4) {
            FluentForEach(["A", "B"], id: { $0 }) { FluentText($0) }
        }))
        let labels = descendants(host).compactMap { $0 as? NSTextField }.filter { ["A", "B"].contains($0.stringValue) }
        let frames = labels.map { $0.convert($0.bounds, to: host) }
        XCTAssertEqual(frames[0].minX, frames[1].minX, accuracy: 1)
        XCTAssertNotEqual(frames[0].midY, frames[1].midY)
    }
}

final class ForEachRowHeightTests: XCTestCase {
    @MainActor
    func testForEachRowsKeepTheirFrameHeight() {
        _ = NSApplication.shared
        let host = FluentViewHost(FluentAnyView(FluentForEach(Array(0..<5), id: { $0 }, spacing: 0) { row in
            FluentText("Row \(row + 1)", style: .body).padding(6).frame(width: 300, height: 32)
        }), context: FluentRenderContext(reduceMotion: true))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let rows = descendants(host).filter { $0.constraints.contains { $0.identifier == "FluentKit.IdealHeight" } }
        XCTAssertEqual(rows.map { $0.frame.height }, Array(repeating: 32, count: 5))
        XCTAssertEqual(host.fittingSize.height, 160, accuracy: 0.5)
    }
}
