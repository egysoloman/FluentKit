import XCTest
@testable import FluentKit

final class TreeViewMultiDragTests: XCTestCase {
    private func leaf(_ id: String) -> FluentTreeViewNode<String> { FluentTreeViewNode(id: id) { FluentText(id) } }
    private var nodes: [FluentTreeViewNode<String>] {
        [FluentTreeViewNode(id: "folder", children: [leaf("a"), leaf("b"), leaf("c")]) { FluentText("Folder") },
         leaf("target"), leaf("last")]
    }
    @MainActor private func mount(_ tree: FluentTreeView<String>) throws -> FluentOutlineView<String> {
        _ = NSApplication.shared
        return try XCTUnwrap(tree._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentOutlineView<String>)
    }
    @MainActor private func item(_ id: String, in view: FluentOutlineView<String>) throws -> Any {
        // All root fixtures and their direct children are stable, and expanding is real AppKit.
        view.outlineView.expandItem(nil, expandChildren: true)
        let ids = ["folder", "a", "b", "c", "target", "last"]
        return try XCTUnwrap(view.outlineView.item(atRow: try XCTUnwrap(ids.firstIndex(of: id))))
    }

    @MainActor func testMovesSelectedSubtreesOnceInSelectionOrder() throws {
        let checks = FluentState(wrappedValue: Set<String>())
        var moves: [FluentTreeViewItemsMove<String>] = []
        let view = try mount(FluentTreeView(nodes: nodes, selection: .multiple(checks.projectedValue)).onMoveItems { moves.append($0) })
        view.toggleCheck("last")
        view.toggleCheck("folder")
        XCTAssertEqual(view.beginDragging("a"), ["last", "folder"], "Selected descendants travel with their selected ancestor")
        XCTAssertTrue(view.acceptMove(to: nil, proposedIndex: 2))
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].ids, ["last", "folder"])
        XCTAssertEqual(moves[0].index, 1)
        XCTAssertNil(moves[0].parentID)
        XCTAssertFalse(view.acceptMove(to: nil, proposedIndex: 2), "A consumed drag cannot call the application twice")
    }

    @MainActor func testPartialSelectionMovesChildrenAndRejectsCyclesAndNoOps() throws {
        let checks = FluentState(wrappedValue: Set(["a", "c"]))
        var moves: [FluentTreeViewItemsMove<String>] = []
        let view = try mount(FluentTreeView(nodes: nodes, selection: .multiple(checks.projectedValue)).onMoveItems { moves.append($0) })
        XCTAssertEqual(view.beginDragging("b"), ["a", "c"], "WinUI drags the checked set even from an unchecked row")
        XCTAssertFalse(view.acceptMove(to: try item("a", in: view), proposedIndex: -1))
        XCTAssertTrue(view.acceptMove(to: try item("folder", in: view), proposedIndex: 3))
        XCTAssertEqual(moves[0].ids, ["a", "c"])
        XCTAssertEqual(moves[0].parentID, "folder")
        XCTAssertEqual(moves[0].index, 1, "Remove both earlier siblings before inserting the group")

        checks.wrappedValue = ["a", "b"]
        view.beginDragging("a")
        XCTAssertFalse(view.acceptMove(to: try item("folder", in: view), proposedIndex: 2), "Contiguous selection already occupies the requested slot")
        XCTAssertEqual(moves.count, 1)
    }

    @MainActor func testCrossParentMoveAndEmptySelectionFallback() throws {
        let checks = FluentState(wrappedValue: Set(["b", "last"]))
        var moves: [FluentTreeViewItemsMove<String>] = []
        let view = try mount(FluentTreeView(nodes: nodes, selection: .multiple(checks.projectedValue)).onMoveItems { moves.append($0) })
        XCTAssertEqual(view.beginDragging("last"), ["b", "last"])
        XCTAssertTrue(view.acceptMove(to: try item("target", in: view), proposedIndex: -1))
        XCTAssertEqual(moves[0].parentID, "target")
        XCTAssertEqual(moves[0].index, 0)
        checks.wrappedValue = []
        XCTAssertEqual(view.beginDragging("c"), ["c"])
        XCTAssertTrue(view.acceptMove(to: nil, proposedIndex: 0))
        XCTAssertEqual(moves[1].ids, ["c"])
    }

    @MainActor func testLegacyHandlerRemainsSingleAndLastModifierWins() throws {
        let checks = FluentState(wrappedValue: Set(["folder", "last"]))
        var moved: [String] = []
        let tree = FluentTreeView(nodes: nodes, selection: .multiple(checks.projectedValue))
            .onMoveItems { _ in XCTFail("The last handler should win") }.onMove { moved.append($0.id) }
        let view = try mount(tree)
        XCTAssertEqual(view.beginDragging("b"), ["b"])
        XCTAssertTrue(view.acceptMove(to: nil, proposedIndex: 0))
        XCTAssertEqual(moved, ["b"])
    }

    @MainActor func testRemovedNodeInvalidatesDragButLazyLoadingDoesNot() throws {
        let checks = FluentState(wrappedValue: Set(["a"]))
        var calls = 0
        func tree(_ nodes: [FluentTreeViewNode<String>]) -> FluentTreeView<String> {
            FluentTreeView(nodes: nodes, selection: .multiple(checks.projectedValue)).onMoveItems { _ in calls += 1 }
        }
        let view = try mount(tree(nodes))
        view.beginDragging("a")
        XCTAssertTrue(tree(nodes + [leaf("loaded")])._updateView(view, in: FluentRenderContext()))
        XCTAssertTrue(view.acceptMove(to: nil, proposedIndex: 4), "An unrelated lazy load does not discard the selected subtree")
        view.beginDragging("a")
        XCTAssertTrue(tree([leaf("target")])._updateView(view, in: FluentRenderContext()))
        XCTAssertFalse(view.acceptMove(to: nil, proposedIndex: 0))
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testDragCapturesSelectionButUsesLatestHandler() throws {
        let checks = FluentState(wrappedValue: Set(["a", "b"]))
        let original = FluentTreeView(nodes: nodes, selection: .multiple(checks.projectedValue)).onMoveItems { _ in XCTFail("Stale handler") }
        let view = try mount(original)
        view.beginDragging("a")
        checks.wrappedValue = ["last"]
        var result: [String] = []
        let latest = original.onMoveItems { result = $0.ids }
        XCTAssertTrue(latest._updateView(view, in: FluentRenderContext()))
        XCTAssertTrue(view.acceptMove(to: nil, proposedIndex: 3))
        XCTAssertEqual(result, ["a", "b"])
    }

    @MainActor func testNativeDropRequiresSameSourceAndFreshValidationAfterTopologyChanges() throws {
        var calls = 0
        let tree = FluentTreeView(nodes: nodes).onMoveItems { _ in calls += 1 }
        let view = try mount(tree)
        let local = TreeDragInfo(source: view.outlineView)
        let foreign = TreeDragInfo(source: NSOutlineView())
        view.beginDragging("a")
        XCTAssertEqual(view.outlineView(view.outlineView, validateDrop: foreign, proposedItem: nil, proposedChildIndex: 3), [])
        XCTAssertFalse(view.outlineView(view.outlineView, acceptDrop: local, item: nil, childIndex: 3))
        XCTAssertEqual(view.outlineView(view.outlineView, validateDrop: local, proposedItem: nil, proposedChildIndex: 3), .move)
        let next = FluentTreeView(nodes: nodes + [leaf("loaded")]).onMoveItems { _ in calls += 1 }
        XCTAssertTrue(next._updateView(view, in: FluentRenderContext()))
        XCTAssertFalse(view.outlineView(view.outlineView, acceptDrop: local, item: nil, childIndex: 3))
        XCTAssertEqual(view.outlineView(view.outlineView, validateDrop: local, proposedItem: nil, proposedChildIndex: 4), .move)
        XCTAssertTrue(view.outlineView(view.outlineView, acceptDrop: local, item: nil, childIndex: 4))
        XCTAssertEqual(calls, 1)
    }
}

private final class TreeDragInfo: NSObject, NSDraggingInfo {
    let draggingSource: Any?
    init(source: NSOutlineView) { draggingSource = source }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { .init(name: .init("FluentKit.TreeDragTest")) }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
