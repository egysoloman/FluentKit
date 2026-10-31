import XCTest
@testable import FluentKit

final class TreeViewDropValidationTests: XCTestCase {
    @MainActor
    func testSingleMoveRejectsCyclesUnknownParentsAndInvalidIndexes() throws {
        _ = NSApplication.shared
        let tree = FluentTreeView(nodes: [
            FluentTreeViewNode(id: "a", children: [FluentTreeViewNode(id: "child") { FluentText("Child") }]) { FluentText("A") },
            FluentTreeViewNode(id: "b") { FluentText("B") }
        ]).onMove { _ in }
        let view = try XCTUnwrap(tree._makeView(in: FluentRenderContext()) as? FluentOutlineView<String>)
        XCTAssertNil(view.simulateMove("a", toParent: "child", proposedIndex: -1), "A node cannot move into its descendant")
        XCTAssertNil(view.simulateMove("a", toParent: "a", proposedIndex: -1), "A node cannot contain itself")
        XCTAssertNil(view.simulateMove("a", toParent: "missing", proposedIndex: -1), "Unknown parents are not the root")
        XCTAssertNil(view.simulateMove("a", toParent: nil, proposedIndex: 99), "Do not deliver an invalid insertion index")
        XCTAssertNil(view.simulateMove("a", toParent: nil, proposedIndex: -2), "Only -1 has drop-on-item meaning")
    }
}
