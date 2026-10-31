import XCTest
@testable import FluentKit

/// FluentViewHost opts out of autoresizing constraints; controls that place hosts by frame must
/// opt back in, or Auto Layout shrinks the host to its content's intrinsic size.
final class ManualHostLayoutTests: XCTestCase {
    @MainActor
    private func mountInWindow(_ view: NSView, size: NSSize) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @MainActor
    func testHostsKeepTheFramesTheirControlsAssign() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let size = NSSize(width: 360, height: 240)

        let pivot = try XCTUnwrap(FluentPivot(["A", "B"], header: { $0 }) { FluentText($0) }._makeView(in: context) as? FluentPivotControl)
        mountInWindow(pivot, size: size)
        XCTAssertEqual(pivot.contentHosts[0].frame.width, 360 - 24, "PivotItemMargin on both sides")

        let swipe = try XCTUnwrap(FluentSwipeControl(rightItems: FluentSwipeItems([FluentSwipeItem("Flag") {}])) { FluentText("x") }
            ._makeView(in: context) as? FluentSwipeControlView)
        mountInWindow(swipe, size: size)
        XCTAssertEqual(swipe.contentHost.frame.size, size)

        let zoom = try XCTUnwrap(FluentSemanticZoom(zoomedInView: { FluentText("in") }, zoomedOutView: { _ in FluentText("out") })
            ._makeView(in: context) as? FluentSemanticZoomControl)
        mountInWindow(zoom, size: size)
        XCTAssertEqual(zoom.zoomedInHost?.frame.size, size)

        let parallax = try XCTUnwrap(FluentParallaxView(vertical: FluentParallaxAxis(shift: 100), background: { FluentText("bg") }) { FluentText("x") }
            ._makeView(in: context) as? FluentParallaxControl)
        mountInWindow(parallax, size: size)
        XCTAssertEqual(parallax.backgroundHost.frame.size, NSSize(width: 360, height: 340))

        let refresh = try XCTUnwrap(FluentRefreshContainer(onRefreshRequested: { _ in }) { FluentText("x") }
            ._makeView(in: context) as? FluentRefreshContainerView)
        mountInWindow(refresh, size: size)
        XCTAssertEqual(refresh.contentHost.frame.width, refresh.scrollView.contentSize.width)

        let annotated = try XCTUnwrap(FluentAnnotatedScrollView(labels: []) { FluentText("x") }
            ._makeView(in: context) as? FluentAnnotatedScrollViewControl)
        mountInWindow(annotated, size: size)
        XCTAssertEqual(annotated.contentHost.frame.width, annotated.scrollView.contentSize.width)
    }
}

final class SingleChildStackTests: XCTestCase {
    @MainActor
    func testStacksAcceptASingleChildOfAnyType() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let vertical = FluentVStack(spacing: 4) { FluentText("Only child") }
        let horizontal = FluentHStack(spacing: 4) { FluentButtonView("Only button") {} }
        let list = FluentVStack(spacing: 4) { FluentForEach(["a", "b"], id: { $0 }) { FluentText($0) } }
        for view in [FluentAnyView(vertical), FluentAnyView(horizontal), FluentAnyView(list)] {
            let host = FluentViewHost(view, context: context)
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(host.subviews.isEmpty)
        }
    }
}

final class GridStarSizingTests: XCTestCase {
    @MainActor
    func testGridColumnsAndRowsShareSpaceEqually() throws {
        _ = NSApplication.shared
        let grid = try XCTUnwrap(FluentGrid(columns: 3, spacing: 8) {
            FluentText("Wide first cell content")
            FluentText("B")
            FluentText("C")
            FluentText("D")
            FluentText("E")
            FluentText("F")
        }._makeView(in: FluentRenderContext(reduceMotion: true)) as? NSGridView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = grid
        window.contentView?.layoutSubtreeIfNeeded()
        let widths = (0..<3).map { grid.column(at: $0).width > 0 ? grid.column(at: $0).width : (grid.cell(atColumnIndex: $0, rowIndex: 0).contentView?.frame.width ?? 0) }
        XCTAssertEqual(widths[0], widths[1], accuracy: 1)
        XCTAssertEqual(widths[1], widths[2], accuracy: 1)
        let heights = (0..<2).map { grid.cell(atColumnIndex: 0, rowIndex: $0).contentView?.frame.height ?? 0 }
        XCTAssertEqual(heights[0], heights[1], accuracy: 1)
    }
}
