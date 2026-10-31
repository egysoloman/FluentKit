import XCTest
@testable import FluentKit

private final class WrappingExpanderContent: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(900 / max(bounds.width, 300)) * 24)
    }
    override func setFrameSize(_ size: NSSize) {
        let changed = abs(frame.width - size.width) > 0.5
        super.setFrameSize(size)
        if changed { invalidateIntrinsicContentSize() }
    }
}

final class ExpanderLayoutTests: XCTestCase {
    @MainActor private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @MainActor private func find(_ id: String, in root: NSView) throws -> NSView {
        try XCTUnwrap(all(root).first { $0.identifier?.rawValue == id })
    }
    @MainActor private func mount(_ view: some FluentView, context: FluentRenderContext = .init(reduceMotion: true)) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 560),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = FluentViewHost(view, context: context)
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }
    @MainActor private func settle(_ window: NSWindow, delay: UInt64 = 20_000_000) async throws {
        try await Task.sleep(nanoseconds: delay)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @MainActor func testNestedExpansionMovesOuterSurfaceAndFollowingSibling() async throws {
        for direction in [FluentExpandDirection.down, .up] {
            for rtl in [false, true] {
                let inner = FluentState(wrappedValue: false)
                let marker = NSTextField(labelWithString: "Following row")
                let window = mount(FluentScrollView(.vertical) {
                    FluentVStack(spacing: 18) {
                        FluentSettingsExpander("Outer", isExpanded: FluentBinding(get: { true }, set: { _ in })) {
                            FluentExpander("Inner", isExpanded: inner.projectedValue, expandDirection: direction) {
                                FluentText("Content").frame(height: 80)
                            }
                        }
                        FluentNativeView(marker)
                    }.padding(20)
                }, context: .init(reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                defer { window.close() }
                try await settle(window)
                let root = window.contentView!
                let viewport = try find("FluentKit.Settings.Expander.Viewport", in: root)
                let child = try find("FluentKit.Expander", in: root)
                let document = try XCTUnwrap(all(root).compactMap { $0 as? NSScrollView }.first?.documentView)
                let beforeHeight = viewport.bounds.height
                let beforeChild = child.bounds.height
                let beforeY = marker.convert(marker.bounds, to: document).minY
                inner.wrappedValue = true
                try await settle(window)
                let change = child.bounds.height - beforeChild
                XCTAssertGreaterThan(change, 0)
                XCTAssertEqual(viewport.bounds.height - beforeHeight, change, accuracy: 0.5)
                let movement = marker.convert(marker.bounds, to: document).minY - beforeY
                XCTAssertEqual(document.isFlipped ? movement : -movement, change, accuracy: 0.5)
                inner.wrappedValue = false
                try await settle(window)
                XCTAssertEqual(viewport.bounds.height, beforeHeight, accuracy: 0.5)
                XCTAssertEqual(marker.convert(marker.bounds, to: document).minY, beforeY, accuracy: 0.5)
            }
        }
    }

    @MainActor func testExpandedContentReplacementUpdatesHeightWithoutReopening() async throws {
        func content(_ height: CGFloat) -> FluentVStackView {
            FluentVStack {
                FluentSettingsExpander("Outer", isExpanded: FluentBinding(get: { true }, set: { _ in })) {
                    FluentText("Resizable body").frame(height: height)
                }
            }
        }
        let window = mount(content(40))
        defer { window.close() }
        try await settle(window)
        let root = try XCTUnwrap(window.contentView as? FluentViewHost<FluentVStackView>)
        let viewport = try find("FluentKit.Settings.Expander.Viewport", in: root)
        XCTAssertEqual(viewport.bounds.height, 60, accuracy: 0.5)
        root.update(content(180))
        try await settle(window)
        XCTAssertEqual(viewport.bounds.height, 200, accuracy: 0.5)
    }

    @MainActor func testExpandedContentRespondsToWidthDependentHeight() async throws {
        let body = WrappingExpanderContent()
        let window = mount(FluentVStack {
            FluentSettingsExpander("Wrapping", isExpanded: FluentBinding(get: { true }, set: { _ in })) { FluentNativeView(body) }
        }.padding(20))
        defer { window.close() }
        for width: CGFloat in [1000, 400, 1000] {
            window.setContentSize(NSSize(width: width, height: 560))
            try await settle(window)
            let viewport = try find("FluentKit.Settings.Expander.Viewport", in: window.contentView!)
            XCTAssertEqual(viewport.bounds.height, body.intrinsicContentSize.height + 20, accuracy: 0.5)
        }
    }

    @MainActor func testInnerChangeAndInterruptedOuterAnimationSettleToCurrentContent() async throws {
        let outer = FluentState(wrappedValue: false)
        let inner = FluentState(wrappedValue: false)
        let window = mount(FluentVStack {
            FluentSettingsExpander("Outer", isExpanded: outer.projectedValue) {
                FluentExpander("Inner", isExpanded: inner.projectedValue) {
                    FluentText("Content").frame(height: 80)
                }
            }
        }, context: .init(animationDuration: 0.12, reduceMotion: false))
        defer { window.close() }
        try await settle(window)
        outer.wrappedValue = true
        try await settle(window, delay: 30_000_000)
        inner.wrappedValue = true
        window.setContentSize(NSSize(width: 600, height: 560))
        outer.wrappedValue = false
        try await settle(window, delay: 30_000_000)
        outer.wrappedValue = true
        try await settle(window, delay: 450_000_000)
        let viewport = try find("FluentKit.Settings.Expander.Viewport", in: window.contentView!)
        let child = try find("FluentKit.Expander", in: window.contentView!)
        XCTAssertFalse(viewport.isHidden)
        XCTAssertEqual(viewport.bounds.height, child.bounds.height + 20, accuracy: 0.5)
        XCTAssertEqual(viewport.layer?.opacity ?? -1, 1, accuracy: 0.01)
        inner.wrappedValue = false
        try await settle(window, delay: 300_000_000)
        XCTAssertEqual(viewport.bounds.height, 68, accuracy: 0.5)
    }

    @MainActor func testLongContentRespectsExplicitExpanderWidth() async throws {
        let window = mount(FluentVStack {
            FluentExpander("Long content", isExpanded: FluentBinding(get: { true }, set: { _ in })) {
                FluentText(String(repeating: "Long text ", count: 20))
            }.frame(width: 520)
        })
        defer { window.close() }
        try await settle(window)
        let child = try find("FluentKit.Expander", in: window.contentView!)
        XCTAssertEqual(child.superview?.bounds.width ?? 0, 520, accuracy: 0.5)
        XCTAssertEqual(child.bounds.width, 520, accuracy: 0.5)
    }

    @MainActor func testFillWidthExpanderUsesAvailableRowWidthForLongContent() async throws {
        func content(_ width: CGFloat) -> some FluentView {
            FluentVStack(alignment: .width) {
                FluentExpander("Long content", isExpanded: FluentBinding(get: { true }, set: { _ in })) {
                    FluentText(String(repeating: "Long text ", count: 20))
                }
            }.padding(20).frame(width: width)
        }
        let window = mount(FluentAnyView(content(760)))
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? FluentViewHost<FluentAnyView>)
        let original = try find("FluentKit.Expander", in: root)
        for width: CGFloat in [760, 400, 1000] {
            root.update(FluentAnyView(content(width)))
            try await settle(window)
            let child = try find("FluentKit.Expander", in: root)
            XCTAssertTrue(child === original)
            XCTAssertEqual(child.bounds.width, width - 40, accuracy: 0.5)
        }
    }
}
