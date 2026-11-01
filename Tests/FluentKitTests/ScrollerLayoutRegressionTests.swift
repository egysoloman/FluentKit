import XCTest
@testable import FluentKit

final class ScrollerLayoutRegressionTests: XCTestCase {
    @MainActor private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @MainActor private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12)) }
    private func rows() -> some FluentView {
        FluentVStack(spacing: 0) {
            FluentForEach(Array(0..<60), id: \.self) { FluentText("Row \($0)").frame(height: 32) }
        }
    }

    @MainActor private func check(
        _ content: FluentAnyView, direction: FluentLayoutDirection, horizontal: Bool = false,
        open: ((NSView) throws -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        _ = NSApplication.shared
        let root = FluentViewHost(content.frame(width: 420, height: 300),
            context: .init(reduceMotion: true, layoutDirection: direction))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 360, width: 420, height: 300),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        root.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        root.layoutSubtreeIfNeeded()
        settle()
        try open?(root)
        settle()
        let surfaces = [window.contentView!] + (window.childWindows ?? []).compactMap(\.contentView)
        let scroll = try XCTUnwrap(surfaces.flatMap(all).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(scroll.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(scroll.frame.height, 0, file: file, line: line)
        scroll.scrollerStyle = .overlay
        scroll.superview?.needsLayout = true
        surfaces.forEach { $0.layoutSubtreeIfNeeded() }
        settle()
        let outerSize = scroll.frame.size
        let overlaySize = scroll.contentView.bounds.size
        scroll.contentView.scroll(to: horizontal ? NSPoint(x: 100, y: 0) : NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle()
        for style in [NSScroller.Style.overlay, .legacy, .overlay, .legacy] {
            scroll.scrollerStyle = style
            // No resize, forced parent layout, or synthetic scrollWheel event.
            settle()
            let viewport = scroll.contentView.bounds
            XCTAssertEqual(scroll.frame.size, outerSize, file: file, line: line)
            XCTAssertEqual(horizontal ? document.frame.height : document.frame.width,
                horizontal ? viewport.height : viewport.width, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(horizontal ? viewport.minX : viewport.minY, 100, accuracy: 1, file: file, line: line)
            if style == .legacy {
                XCTAssertLessThan(horizontal ? viewport.height : viewport.width,
                    horizontal ? overlaySize.height : overlaySize.width, file: file, line: line)
            }
            for child in document.subviews {
                XCTAssertLessThanOrEqual(horizontal ? child.frame.maxY : child.frame.maxX,
                    horizontal ? viewport.height : viewport.width, file: file, line: line)
            }
            if let collection = document as? NSCollectionView {
                XCTAssertFalse(collection.visibleItems().isEmpty, file: file, line: line)
            }
        }
    }

    @MainActor func testAutoSuggestRowsFollowLiveScrollerStyleWithoutRevealingSelection() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            let text = FluentState(wrappedValue: "")
            try check(FluentAnyView(FluentAutoSuggestBox(text.projectedValue,
                suggestions: { _ in (0..<30).map { .init(id: $0, title: "Result \($0)") } }, maxSuggestionListHeight: 180)),
                direction: direction, open: { root in
                    let field = try XCTUnwrap(self.all(root).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as? NSTextField)
                    field.selectText(nil)
                    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                    editor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
                })
        }
    }

    @MainActor func testComboBoxRowsFollowLiveScrollerStyleWithoutRevealingSelection() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            let selection = FluentState<Int?>(wrappedValue: 0)
            try check(FluentAnyView(FluentComboBox(options: Array(0..<30), selection: selection.projectedValue)),
                direction: direction, open: { root in
                    try XCTUnwrap(self.all(root).compactMap { $0 as? NSComboBox }.first).performClick(nil)
                })
            XCTAssertEqual(selection.wrappedValue, 0)
        }
    }

    @MainActor func testVerticalRefreshContentFollowsLiveScrollerStyle() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            try check(FluentAnyView(FluentRefreshContainer(onRefreshRequested: { $0.complete() }) { rows() }), direction: direction)
        }
    }

    @MainActor func testHorizontalRefreshContentFollowsLiveScrollerStyle() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            try check(FluentAnyView(FluentRefreshContainer(pullDirection: .leftToRight, onRefreshRequested: { $0.complete() }) {
                FluentHStack { FluentForEach(Array(0..<20), id: \.self) { FluentText("Column \($0)").frame(width: 80) } }
            }), direction: direction, horizontal: true)
        }
    }

    @MainActor func testContentDialogReservesScrollerWidthAndPreservesScrollPosition() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            let presented = FluentState(wrappedValue: true)
            try check(FluentAnyView(FluentText("Dialog host").contentDialog("Scroll styles", isPresented: presented.projectedValue,
                primaryButtonText: "OK", closeButtonText: "Cancel") { rows() }), direction: direction)
        }
    }

    @MainActor func testLegacyListPreservesScrollPositionWhenScrollerStyleChanges() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            try check(FluentAnyView(FluentList(rows: (0..<60).map { FluentText("Row \($0)") })), direction: direction)
        }
    }

    @MainActor func testNavigationRowsFitLiveScrollerViewportInExpandedAndCompactModes() throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            for expanded in [false, true] {
                let selection = FluentState<Int?>(wrappedValue: 0)
                let open = FluentState(wrappedValue: expanded)
                try check(FluentAnyView(FluentNavigationView(
                    (0..<60).map { FluentNavigationItem(id: $0, title: "Item \($0)", systemImageName: "star") },
                    footerItems: [.init(id: 99, title: "Settings", systemImageName: "gearshape")],
                    selection: selection.projectedValue, isPaneOpen: open.projectedValue,
                    paneDisplayMode: expanded ? .left : .leftCompact
                ) { FluentText("Page") }), direction: direction)
            }
        }
    }
}
