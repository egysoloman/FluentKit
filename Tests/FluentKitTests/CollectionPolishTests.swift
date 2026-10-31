import XCTest
@testable import FluentKit

final class CollectionPolishTests: XCTestCase {
    @MainActor
    private func makeSectioned(sticky: Bool? = nil, request: FluentBinding<Int?>? = nil,
                               alignment: FluentScrollIntoViewAlignment = .default, items: Int = 40) throws -> FluentSectionedCollectionView<String, Int> {
        _ = NSApplication.shared
        var snapshot = FluentCollectionSnapshot<String, Int>()
        snapshot.appendSections(["A", "B"])
        snapshot.appendItems(Array(0..<items), toSection: "A")
        snapshot.appendItems(Array(items..<(items * 2)), toSection: "B")
        var collection = FluentCollection(snapshot: snapshot, layout: .list(rowHeight: 40), content: { FluentText("Item \($0)") },
                                          header: { FluentText("Group \($0)") })
        if let sticky { collection = collection.areStickyGroupHeadersEnabled(sticky) }
        if let request { collection = collection.scrollIntoView(request, alignment: alignment) }
        let view = try XCTUnwrap(collection._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentSectionedCollectionView<String, Int>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        return view
    }

    @MainActor
    func testStickyGroupHeadersAreOnByDefaultAndCanBeTurnedOff() throws {
        XCTAssertTrue(try makeSectioned().areStickyGroupHeadersEnabled, "AreStickyGroupHeadersEnabled defaults to true")
        XCTAssertFalse(try makeSectioned(sticky: false).areStickyGroupHeadersEnabled)
        XCTAssertEqual(FluentCollectionLayout.list().headerHeight, 48, "44pt MinHeight plus the 4pt bottom margin")
        XCTAssertEqual(FluentCollectionLayout.adaptiveGrid().headerHeight, 48)
    }

    @MainActor
    func testHeaderUsesTheListViewHeaderItemTemplate() throws {
        let view = try makeSectioned()
        let header = try XCTUnwrap(view.nativeCollectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).first)
        let content = try XCTUnwrap(header.subviews.first)
        let aligned = content.alignmentRect(forFrame: content.frame)
        XCTAssertEqual(aligned.minX, 12, accuracy: 0.5, "Padding 12,8,12,0")
        XCTAssertEqual(aligned.minY, 8, accuracy: 0.5)
        let divider = try XCTUnwrap(header.layer?.sublayers?.first { $0.name == "FluentKit.Collection.HeaderDivider" })
        XCTAssertEqual(divider.frame.height, 1)
        XCTAssertEqual(divider.frame.minY, content.frame.maxY + 8, accuracy: 0.5)
        XCTAssertEqual(divider.frame.minX, 12)
        XCTAssertEqual(divider.frame.maxX, header.bounds.width - 12, accuracy: 0.5)
    }

    @MainActor
    func testScrollIntoViewScrollsThenClearsTheRequest() throws {
        let request = FluentState<Int?>(wrappedValue: nil)
        let view = try makeSectioned(request: request.projectedValue, alignment: .leading)
        XCTAssertEqual(view.nativeCollectionView.visibleRect.minY, 0, accuracy: 0.5)
        request.wrappedValue = 60
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNil(request.wrappedValue, "The request resets once handled")
        XCTAssertEqual(view.lastScrolledItem, AnyHashable(60))
        let attributes = try XCTUnwrap(view.nativeCollectionView.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 20, section: 1)))
        XCTAssertEqual(view.nativeCollectionView.visibleRect.minY + 48, attributes.frame.minY, accuracy: 1,
                       "Leading alignment puts the item at the top, just below the pinned group header")
    }

    @MainActor
    func testDefaultAlignmentScrollsMinimallyAndUnknownItemsWait() throws {
        let request = FluentState<Int?>(wrappedValue: nil)
        let view = try makeSectioned(request: request.projectedValue)
        request.wrappedValue = 15
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let attributes = try XCTUnwrap(view.nativeCollectionView.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 15, section: 0)))
        XCTAssertEqual(view.nativeCollectionView.visibleRect.maxY, attributes.frame.maxY, accuracy: 1, "Default reveals the item at the nearest edge")
        request.wrappedValue = 999
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(request.wrappedValue, 999, "An item not in the data stays pending")
    }
}
