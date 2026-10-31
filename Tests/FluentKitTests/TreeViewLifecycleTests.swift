import XCTest
@testable import FluentKit

final class TreeViewLifecycleTests: XCTestCase {
    private final class Probe: NSView {
        static var moves = 0
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); Self.moves += 1 }
        override var intrinsicContentSize: NSSize { NSSize(width: 80, height: 20) }
    }
    private func nodes(_ ids: [String]) -> [FluentTreeViewNode<String>] {
        ids.map { id in FluentTreeViewNode(id: id) { FluentNativeView(make: { Probe() }, update: { _, _ in }) } }
    }
    @MainActor
    func testUnboundSelectionSurvivesAStableIDReorder() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let view = try XCTUnwrap(FluentTreeView(nodes: nodes(["a", "b", "c"]))._makeView(in: context) as? FluentOutlineView<String>)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        view.layoutSubtreeIfNeeded()
        view.outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertTrue(FluentTreeView(nodes: nodes(["c", "a", "b"]))._updateView(view, in: context))
        XCTAssertEqual(view.outlineView.selectedRow, 2, "Selection follows node b rather than the previous row index")
    }

    @MainActor
    func testRemovingTheUnboundSelectedNodeDoesNotSelectItsReplacement() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext()
        let view = try XCTUnwrap(FluentTreeView(nodes: nodes(["a", "b", "c"]))._makeView(in: context) as? FluentOutlineView<String>)
        view.outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertTrue(FluentTreeView(nodes: nodes(["a", "c"]))._updateView(view, in: context))
        XCTAssertEqual(view.outlineView.selectedRow, -1)
    }

    @MainActor
    func testContentOnlyUpdateChangesTheRetainedVisibleLabel() throws {
        _ = NSApplication.shared
        func tree(_ title: String) -> FluentTreeView<String> {
            FluentTreeView(nodes: [FluentTreeViewNode(id: "a") { FluentText(title) }])
        }
        let context = FluentRenderContext()
        let view = try XCTUnwrap(tree("Before")._makeView(in: context) as? FluentOutlineView<String>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FluentOutlineCellHost)
        let label = try XCTUnwrap(cell.contentView as? NSTextField)
        XCTAssertTrue(tree("After")._updateView(view, in: context))
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(cell.contentView === label)
        XCTAssertEqual(label.stringValue, "After")
    }
    @MainActor
    func testUnchangedTreeKeepsNativeItemAndContentIdentity() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let tree = FluentTreeView(nodes: nodes(["a", "b", "c"]))
        let view = try XCTUnwrap(tree._makeView(in: context) as? FluentOutlineView<String>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(view.outlineView.item(atRow: 1) as AnyObject?)
        let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 1, makeIfNecessary: true))
        Probe.moves = 0
        for _ in 0..<5 {
            XCTAssertTrue(FluentTreeView(nodes: nodes(["a", "b", "c"]))._updateView(view, in: context))
            view.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(view.outlineView.item(atRow: 1) as AnyObject? === item)
        XCTAssertTrue(view.outlineView.view(atColumn: 0, row: 1, makeIfNecessary: true) === cell)
        XCTAssertEqual(Probe.moves, 0, "Unchanged rows must not remove and reattach native content")
    }
    @MainActor
    func testDetachedMultipleBindingCannotReceiveQueuedNormalization() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext()
        let first = FluentState(wrappedValue: Set(["parent"]))
        let second = FluentState(wrappedValue: Set<String>())
        let tree = [FluentTreeViewNode(id: "parent", children: nodes(["child"])) { FluentText("Parent") }]
        let view = FluentTreeView(nodes: tree, selection: .multiple(first.projectedValue))._makeView(in: context)
        XCTAssertTrue(FluentTreeView(nodes: tree, selection: .multiple(second.projectedValue))._updateView(view, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(first.wrappedValue, ["parent"], "A detached binding must not be modified by an old queued task")
        XCTAssertTrue(second.wrappedValue.isEmpty)
    }

    @MainActor
    func testBoundSelectionSurvivesReorderingAndClearsOnlyWhenRemoved() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "b")
        let context = FluentRenderContext()
        func tree(_ ids: [String]) -> FluentTreeView<String> { FluentTreeView(nodes: nodes(ids), selectionID: selection.projectedValue) }
        let view = try XCTUnwrap(tree(["a", "b", "c"])._makeView(in: context) as? FluentOutlineView<String>)
        XCTAssertTrue(tree(["c", "a", "b"])._updateView(view, in: context))
        XCTAssertEqual(selection.wrappedValue, "b")
        XCTAssertEqual(view.outlineView.selectedRow, 2)
        XCTAssertTrue(tree(["c", "a"])._updateView(view, in: context))
        XCTAssertNil(selection.wrappedValue)
    }
    @MainActor
    func testLazyChildrenKeepExpansionAndInheritASelectedParent() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext()
        let checked = FluentState(wrappedValue: Set(["remote"]))
        let expanded = FluentState(wrappedValue: Set<String>())
        var calls: [String] = []
        func tree(loaded: Bool) -> FluentTreeView<String> {
            FluentTreeView(nodes: [FluentTreeViewNode(id: "remote", children: loaded ? nodes(["a", "b"]) : [],
                hasUnrealizedChildren: !loaded) { FluentText(loaded ? "Loaded" : "Remote") }], selection: .multiple(checked.projectedValue))
                .expandedIDs(expanded.projectedValue).onExpanding { calls.append($0) }
        }
        let view = try XCTUnwrap(tree(loaded: false)._makeView(in: context) as? FluentOutlineView<String>)
        let item = view.outlineView.item(atRow: 0) as AnyObject?
        view.toggleExpansion("remote")
        XCTAssertEqual(calls, ["remote"])
        XCTAssertTrue(expanded.wrappedValue.contains("remote"))
        XCTAssertTrue(tree(loaded: true)._updateView(view, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertTrue(view.outlineView.item(atRow: 0) as AnyObject? === item)
        XCTAssertTrue(view.isExpanded("remote"))
        XCTAssertEqual(view.outlineView.numberOfRows, 3)
        XCTAssertEqual(checked.wrappedValue, ["remote", "a", "b"])
        XCTAssertEqual(calls, ["remote"], "Restoring expansion must not trigger a second load")
    }

    @MainActor
    func testRTLContentFollowsTheMirroredChevronAndCanSwitchBack() throws {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: Set(["root"]))
        let tree = FluentTreeView(nodes: [FluentTreeViewNode(id: "root", children: [
            FluentTreeViewNode(id: "child") { FluentText("Child") }
        ]) { FluentText("Root") }]).expandedIDs(expanded.projectedValue)
        let context = FluentRenderContext(layoutDirection: .rightToLeft)
        let view = try XCTUnwrap(tree._makeView(in: context) as? FluentOutlineView<String>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? FluentOutlineCellHost)
        cell.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(cell.contentView)
        XCTAssertEqual(content.alignmentRect(forFrame: content.frame).maxX, cell.bounds.maxX - 60, accuracy: 0.5)
        XCTAssertTrue(tree._updateView(view, in: FluentRenderContext(layoutDirection: .leftToRight)))
        view.layoutSubtreeIfNeeded()
        let ltrCell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? FluentOutlineCellHost)
        ltrCell.layoutSubtreeIfNeeded()
        let ltrContent = try XCTUnwrap(ltrCell.contentView)
        XCTAssertEqual(ltrContent.alignmentRect(forFrame: ltrContent.frame).minX, 60, accuracy: 0.5)
    }
}
