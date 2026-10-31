import XCTest
@testable import FluentKit

final class TreeViewPolishTests: XCTestCase {
    private static func nodes(lazy: Bool = false) -> [FluentTreeViewNode<String>] {
        [
            FluentTreeViewNode(id: "work", children: [
                FluentTreeViewNode(id: "plan") { FluentText("Plan") },
                FluentTreeViewNode(id: "specs", children: [
                    FluentTreeViewNode(id: "spec-a") { FluentText("Spec A") }
                ]) { FluentText("Specs") }
            ]) { FluentText("Work") },
            FluentTreeViewNode(id: "remote", hasUnrealizedChildren: lazy) { FluentText("Remote") },
            FluentTreeViewNode(id: "notes") { FluentText("Notes") }
        ]
    }

    @MainActor
    private func mount(_ tree: FluentTreeView<String>) throws -> FluentOutlineView<String> {
        _ = NSApplication.shared
        let view = try XCTUnwrap(tree._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentOutlineView<String>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 300)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        return view
    }

    @MainActor
    private func row(_ view: FluentOutlineView<String>, _ index: Int) throws -> (FluentTreeRowView, FluentOutlineCellHost) {
        view.layoutSubtreeIfNeeded()
        let rowView = try XCTUnwrap(view.outlineView.rowView(atRow: index, makeIfNecessary: true) as? FluentTreeRowView)
        let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: index, makeIfNecessary: true) as? FluentOutlineCellHost)
        rowView.layoutSubtreeIfNeeded()
        cell.layoutSubtreeIfNeeded()
        return (rowView, cell)
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    @MainActor
    func testRowsFollowTheTreeViewItemTemplate() throws {
        let expanded = FluentState(wrappedValue: Set(["work"]))
        let selection = FluentState<String?>(wrappedValue: "plan")
        let view = try mount(FluentTreeView(nodes: Self.nodes(), selectionID: selection.projectedValue).expandedIDs(expanded.projectedValue))
        XCTAssertEqual(view.outlineView.rowHeight, 32, "MinHeight 28 plus the 4,2 presenter margin")

        let (rootRow, rootCell) = try row(view, 0)
        XCTAssertEqual(rootCell.chevronFrame.minX, 18, accuracy: 0.5, "4pt margin + 14pt chevron padding")
        XCTAssertEqual(rootCell.chevronFrame.width, 12)
        XCTAssertFalse(rootCell.chevronLayer.isHidden)
        XCTAssertEqual(rootRow.fillLayer.frame, rootRow.bounds.insetBy(dx: 4, dy: 2))
        XCTAssertEqual(rootRow.indicatorLayer.opacity, 0)

        let (childRow, childCell) = try row(view, 1)
        XCTAssertEqual(childCell.chevronFrame.minX, 34, accuracy: 0.5, "16pt indentation per level")
        XCTAssertTrue(childCell.chevronLayer.isHidden, "Leaf nodes keep the chevron space with zero opacity")
        let content = try XCTUnwrap(childCell.contentView)
        XCTAssertEqual(content.alignmentRect(forFrame: content.frame).minX, 60, accuracy: 0.5, "Content follows the 14,0 chevron padding")
        XCTAssertTrue(childRow.showsSelected)
        XCTAssertEqual(childRow.indicatorLayer.opacity, 1)
        XCTAssertEqual(childRow.indicatorLayer.frame.size, NSSize(width: 3, height: 16))
        XCTAssertEqual(childRow.indicatorLayer.frame.minX, 4)
    }

    @MainActor
    func testMultipleSelectionUsesTriStateCheckBoxes() throws {
        let checked = FluentState(wrappedValue: Set<String>())
        let view = try mount(FluentTreeView(nodes: Self.nodes(), selection: .multiple(checked.projectedValue))
            .expandedIDs(FluentState(wrappedValue: Set(["work", "specs"])).projectedValue))
        let (_, cell) = try row(view, 0)
        XCTAssertEqual(cell.checkBoxFrame.width, 20)
        XCTAssertEqual(cell.chevronFrame.minX, 46, accuracy: 0.5, "Check box column (10 + 32) then chevron padding 0,0,14,0")

        view.toggleCheck("work")
        XCTAssertEqual(checked.wrappedValue, ["work", "plan", "specs", "spec-a"], "Checking a parent checks its subtree")
        view.toggleCheck("spec-a")
        XCTAssertEqual(checked.wrappedValue, ["plan"])
        XCTAssertEqual(view.checkState(of: "work"), .mixed)
        XCTAssertEqual(view.checkState(of: "specs"), .unchecked)
        view.toggleCheck("work")
        XCTAssertEqual(view.checkState(of: "work"), .checked, "A mixed parent becomes checked")

        let (row0, _) = try row(view, 0)
        XCTAssertTrue(row0.showsSelected)
        XCTAssertEqual(row0.indicatorLayer.opacity, 0, "Multiple selection shows check boxes instead of the pill")

        checked.wrappedValue = ["specs"]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(checked.wrappedValue, ["specs", "spec-a"], "SelectedNodes.Append selects the subtree")
        XCTAssertEqual(view.checkState(of: "work"), .mixed)
    }

    @MainActor
    func testExpansionBindingAndEvents() throws {
        let expanded = FluentState(wrappedValue: Set<String>())
        var expanding: [String] = []
        var collapsed: [String] = []
        let view = try mount(FluentTreeView(nodes: Self.nodes(lazy: true), selectionID: nil)
            .expandedIDs(expanded.projectedValue)
            .onExpanding { expanding.append($0) }
            .onCollapsed { collapsed.append($0) })
        let (_, remoteCell) = try row(view, 1)
        XCTAssertFalse(remoteCell.chevronLayer.isHidden, "HasUnrealizedChildren shows the chevron")

        view.toggleExpansion("work")
        XCTAssertEqual(expanded.wrappedValue, ["work"])
        XCTAssertEqual(expanding, ["work"])
        view.toggleExpansion("work")
        XCTAssertEqual(expanded.wrappedValue, [])
        XCTAssertEqual(collapsed, ["work"])

        expanded.wrappedValue = ["work", "specs"]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(view.isExpanded("work"))
        XCTAssertTrue(view.isExpanded("specs"))
        XCTAssertEqual(view.outlineView.numberOfRows, 6)
        XCTAssertEqual(expanding, ["work"], "Programmatic expansion does not raise Expanding")
    }

    @MainActor
    func testKeyboardFollowsHandleExpandCollapse() throws {
        let selection = FluentState<String?>(wrappedValue: "work")
        var invoked: [String] = []
        let view = try mount(FluentTreeView(nodes: Self.nodes(), selectionID: selection.projectedValue)
            .onItemInvoked { invoked.append($0) })
        XCTAssertTrue(view.handleKey(key(124)))
        XCTAssertTrue(view.isExpanded("work"), "Right expands a collapsed node")
        XCTAssertTrue(view.handleKey(key(124)))
        XCTAssertEqual(selection.wrappedValue, "plan", "Right on an expanded node moves to its first child")
        XCTAssertTrue(view.handleKey(key(123)))
        XCTAssertEqual(selection.wrappedValue, "work", "Left on a collapsed child moves to its parent")
        XCTAssertTrue(view.handleKey(key(123)))
        XCTAssertFalse(view.isExpanded("work"), "Left collapses an expanded node")
        XCTAssertTrue(view.handleKey(key(36)))
        XCTAssertEqual(invoked, ["work"], "Return raises ItemInvoked")
    }

    @MainActor
    func testReorderReportsTheIndexAfterRemoval() throws {
        let view = try mount(FluentTreeView(nodes: Self.nodes(), selectionID: nil).onMove { _ in })
        let down = try XCTUnwrap(view.simulateMove("work", toParent: nil, proposedIndex: 3))
        XCTAssertNil(down.parentID)
        XCTAssertEqual(down.index, 2, "Dropping after Notes lands at the end once Work is removed")
        let onto = try XCTUnwrap(view.simulateMove("notes", toParent: "work", proposedIndex: NSOutlineViewDropOnItemIndex))
        XCTAssertEqual(onto.parentID, "work")
        XCTAssertEqual(onto.index, 2, "Dropping onto a node appends it as the last child")
        XCTAssertNil(view.simulateMove("remote", toParent: nil, proposedIndex: 1), "Dropping in place is not a move")
    }
}
