import XCTest
@testable import FluentKit

final class CollectionHeaderLayoutTests: XCTestCase {
    @MainActor
    func testHeaderButtonsKeepNaturalWidthUnlessContentExplicitlyStretches() throws {
        _ = NSApplication.shared
        let cases: [FluentAnyView] = [
            FluentAnyView(FluentButtonView("Action") {}),
            FluentAnyView(FluentHStack(spacing: 12) {
                FluentButtonView("First") {}
                FluentButtonView("Second") {}
            }),
            FluentAnyView(FluentVStack(alignment: .width) { FluentButtonView("Stretch") {} })
        ]
        for (index, headerContent) in cases.enumerated() {
            let collection = FluentCollection(snapshot: FluentCollectionSnapshot(section: 0, items: [0]),
                content: { FluentText("Item \($0)") }, header: { _ in headerContent })
            let view = try XCTUnwrap(collection._makeView(in: .init()) as? FluentSectionedCollectionView<Int, Int>)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let header = try XCTUnwrap(view.nativeCollectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).first)
            header.layoutSubtreeIfNeeded()
            let content = try XCTUnwrap(header.subviews.first)
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let buttons = descendants(content).compactMap { $0 as? FluentButton }
            let expected = index == 2 ? header.bounds.width - 24
                : buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width } + (index == 1 ? 12 : 0)
            XCTAssertEqual(content.alignmentRect(forFrame: content.frame).width, expected, accuracy: 0.5)
            if index == 2 { XCTAssertEqual(buttons[0].frame.width, expected, accuracy: 0.5) }
        }
    }

    @MainActor
    func testVisibleHeaderUpdatesContentAndDirectionWithoutRemounting() throws {
        _ = NSApplication.shared
        func collection(_ title: String) -> FluentCollection<Int, Int> {
            FluentCollection(snapshot: .init(section: 0, items: [0, 1]), layout: .list(),
                content: { FluentText("Item \($0)") }, header: { _ in FluentText(title) })
        }
        let view = try XCTUnwrap(collection("Before")._makeView(in: .init()) as? FluentSectionedCollectionView<Int, Int>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let header = try XCTUnwrap(view.nativeCollectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).first)
        let label = try XCTUnwrap(header.subviews.first as? NSTextField)
        for direction in [FluentLayoutDirection.rightToLeft, .leftToRight] {
            XCTAssertTrue(collection("After")._updateView(view, in: .init(layoutDirection: direction)))
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(header.subviews.first === label)
            XCTAssertEqual(label.stringValue, "After")
            XCTAssertEqual(header.userInterfaceLayoutDirection, direction.appKitValue)
            XCTAssertEqual(label.userInterfaceLayoutDirection, direction.appKitValue)
            let aligned = label.alignmentRect(forFrame: label.frame)
            XCTAssertEqual(aligned.width, label.intrinsicContentSize.width, accuracy: 0.5)
            if direction == .leftToRight { XCTAssertEqual(aligned.minX, 12, accuracy: 0.5) }
            else { XCTAssertEqual(aligned.maxX, header.bounds.width - 12, accuracy: 0.5) }
        }
    }

    @MainActor
    func testReusedHeaderClampsItsContentSlotAndRestoresNormalPadding() throws {
        _ = NSApplication.shared
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            let snapshot = FluentCollectionSnapshot(section: 0, items: [0, 1, 2])
            let content = FluentCollection(snapshot: snapshot, layout: .adaptiveGrid(),
                content: { FluentText("Item \($0)") },
                header: { _ in FluentText("A long section heading that must fit the current viewport") })
            let view = try XCTUnwrap(content._makeView(in: .init(reduceMotion: true, layoutDirection: direction)) as? FluentSectionedCollectionView<Int, Int>)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let header = try XCTUnwrap(view.nativeCollectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).first)
            // Supplementary views also receive zero/narrow frames while being reused, independently
            // of the window's minimum size. Exercise the real dequeued header in those slots.
            header.removeFromSuperview()
            let stage = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
            window.contentView = stage
            stage.addSubview(header)
            header.translatesAutoresizingMaskIntoConstraints = true
            header.autoresizingMask = []
            let label = try XCTUnwrap(header.subviews.first as? NSTextField)
            for width: CGFloat in [600, 180, 24, 12, 1, 0, 360] {
                header.frame = NSRect(x: 0, y: 0, width: width, height: 48)
                header.layoutSubtreeIfNeeded()
                let aligned = label.alignmentRect(forFrame: label.frame)
                XCTAssertEqual(aligned.width, min(label.intrinsicContentSize.width, max(0, width - 24)), accuracy: 0.5)
                XCTAssertEqual(aligned.minY, 8, accuracy: 0.5)
                if direction == .leftToRight {
                    XCTAssertEqual(aligned.minX, 12, accuracy: 0.5)
                } else {
                    XCTAssertEqual(aligned.maxX, width - 12, accuracy: 0.5)
                }
                XCTAssertTrue(label.frame.width.isFinite && label.frame.height.isFinite)
                XCTAssertGreaterThanOrEqual(label.frame.width, 0)
                let divider = try XCTUnwrap(header.layer?.sublayers?.first { $0.name == "FluentKit.Collection.HeaderDivider" })
                XCTAssertEqual(divider.frame.width, max(0, width - 24), accuracy: 0.5)
                XCTAssertEqual(divider.frame.minY, label.frame.maxY + 8, accuracy: 0.5)
                XCTAssertEqual(divider.frame.height, 1)
            }
        }
    }
}
