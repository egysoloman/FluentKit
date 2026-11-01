import XCTest
@testable import FluentKit

@MainActor
final class RefreshLayoutTests: XCTestCase {
    private struct Items: FluentView {
        let count: FluentState<Int>
        let vertical: Bool
        var body: some FluentView {
            if vertical {
                FluentVStack(spacing: 12) {
                    FluentForEach(Array(0..<count.wrappedValue), id: \.self) { FluentText("Item \($0)").frame(height: 32) }
                }
            } else {
                FluentHStack(spacing: 12) {
                    FluentForEach(Array(0..<count.wrappedValue), id: \.self) { FluentText("Item \($0)").frame(width: 80) }
                }
            }
        }
    }

    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    private func settle() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        try? await Task.sleep(nanoseconds: 40_000_000)
    }

    func testContentChangesUpdateScrollExtentWithoutResizingOrReplacingHost() async throws {
        _ = NSApplication.shared
        for direction in [FluentRefreshPullDirection.topToBottom, .bottomToTop, .leftToRight, .rightToLeft] {
            for rtl in [false, true] {
                let vertical = direction == .topToBottom || direction == .bottomToTop
                let count = FluentState(wrappedValue: 20)
                let root = FluentViewHost(FluentRefreshContainer(pullDirection: direction, onRefreshRequested: { $0.complete() }) {
                    Items(count: count, vertical: vertical)
                }, context: .init(reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 300),
                                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.contentView = root
                window.orderFront(nil)
                let container = try XCTUnwrap(all(root).compactMap { $0 as? FluentRefreshContainerView }.first)
                let host = container.contentHost
                let scroll = container.scrollView
                for value in [20, 2, 40, 0, 20] {
                    count.wrappedValue = value
                    await settle()
                    let viewport = scroll.contentSize
                    let document = try XCTUnwrap(scroll.documentView)
                    let natural = CGFloat(value) * (vertical ? 32 : 80) + CGFloat(max(0, value - 1)) * 12
                    XCTAssertEqual(vertical ? document.frame.height : document.frame.width,
                        max(natural, vertical ? viewport.height : viewport.width), accuracy: 0.01,
                        "\(direction), RTL=\(rtl), count=\(value)")
                    XCTAssertEqual(vertical ? host.frame.width : host.frame.height,
                                   vertical ? viewport.width : viewport.height, accuracy: 0.01)
                    XCTAssertTrue(host === container.contentHost)
                    let labels = all(host).compactMap { $0 as? NSTextField }.filter { $0.stringValue.hasPrefix("Item ") }
                    XCTAssertEqual(labels.count, value)
                    for label in labels {
                        let frame = try XCTUnwrap(label.superview).frame
                        XCTAssertEqual(vertical ? frame.height : frame.width, vertical ? 32 : 80, accuracy: 0.01)
                    }
                }
            }
        }
    }

    func testDirectionResizeAndScrollerChangesPreserveRefreshContent() async throws {
        _ = NSApplication.shared
        let count = FluentState(wrappedValue: 20)
        let refreshing = FluentState(wrappedValue: false)
        var requests: [FluentRefreshDeferral] = []
        func definition(_ direction: FluentRefreshPullDirection) -> some FluentView {
            FluentRefreshContainer(pullDirection: direction, isRefreshing: refreshing.projectedValue,
                onRefreshRequested: { requests.append($0) }) {
                Items(count: count, vertical: direction == .topToBottom || direction == .bottomToTop)
            }
        }
        let root = FluentViewHost(definition(.topToBottom), context: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 300),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = root
        window.orderFront(nil)
        let container = try XCTUnwrap(all(root).compactMap { $0 as? FluentRefreshContainerView }.first)
        let scroll = container.scrollView
        let document = try XCTUnwrap(scroll.documentView)
        for direction in [FluentRefreshPullDirection.leftToRight, .bottomToTop, .rightToLeft, .topToBottom] {
            let vertical = direction == .topToBottom || direction == .bottomToTop
            root.update(definition(direction))
            await settle()
            XCTAssertTrue(container === all(root).compactMap { $0 as? FluentRefreshContainerView }.first)
            XCTAssertEqual(scroll.hasVerticalScroller, vertical)
            XCTAssertEqual(scroll.hasHorizontalScroller, !vertical)
            let previousRequests = requests.count
            refreshing.wrappedValue = true
            count.wrappedValue = 40
            await settle()
            XCTAssertEqual(container.state, .refreshing)
            XCTAssertEqual(requests.count, previousRequests + 1)
            XCTAssertEqual(vertical ? document.frame.height : document.frame.width,
                           vertical ? 1748 : 3668, accuracy: 0.01)
            try XCTUnwrap(requests.last).complete()
            await settle()
            XCTAssertFalse(refreshing.wrappedValue)
            XCTAssertEqual(container.state, .idle)
            let insets = scroll.contentInsets
            XCTAssertEqual([insets.top, insets.left, insets.bottom, insets.right], [0, 0, 0, 0])
            for size in [NSSize(width: 260, height: 180), NSSize(width: 420, height: 300)] {
                window.setContentSize(size)
                for style in [NSScroller.Style.legacy, .overlay] {
                    scroll.scrollerStyle = style
                    await settle()
                    XCTAssertEqual(vertical ? document.frame.width : document.frame.height,
                                   vertical ? scroll.contentSize.width : scroll.contentSize.height, accuracy: 0.01)
                    XCTAssertEqual(vertical ? document.frame.height : document.frame.width,
                                   vertical ? 1748 : 3668, accuracy: 0.01)
                }
            }
        }
    }
}
