import XCTest
@testable import FluentKit

// AppKit's outline-row proxies still implement the public informal accessibility interface.
// These signatures let the test send its documented selectors without assuming formal protocol
// conformance or using an unsafe function-pointer cast.
@objc private protocol TreeRowAXProbe {
    @objc(accessibilityIsAttributeSettable:) func treeCanSet(_ attribute: String) -> Bool
    @objc(accessibilityAttributeValue:) func treeValue(_ attribute: String) -> Any?
}

final class TreeViewExpansionEventTests: XCTestCase {
    @MainActor func testAccessibilityEligibilityReadsDoNotExpandOrLoadNodes() throws {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: Set<String>())
        var loads: [String] = []
        let tree = FluentTreeView(nodes: [FluentTreeViewNode(id: "remote", hasUnrealizedChildren: true) { FluentText("Remote") }])
            .expandedIDs(expanded.projectedValue).onExpanding { loads.append($0) }
        let view = try XCTUnwrap(tree._makeView(in: FluentRenderContext()) as? FluentOutlineView<String>)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = view; window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
        // macOS 27's SDK types these rows as NSAccessibilityRow, but its returned proxy does
        // not advertise that conformance. Use the same public Objective-C getters without
        // triggering Swift's NSArray element-conformance trap.
        let rows = try XCTUnwrap(view.outlineView.perform(NSSelectorFromString("accessibilityRows"))?.takeUnretainedValue() as? NSArray)
        let remote: AnyObject = try XCTUnwrap(rows.firstObject as AnyObject?)
        for _ in 0..<3 {
            XCTAssertTrue(remote.treeCanSet(NSAccessibility.Attribute.disclosing.rawValue))
            XCTAssertEqual(remote.treeValue(NSAccessibility.Attribute.disclosing.rawValue) as? Bool, false)
        }
        XCTAssertEqual(loads, [], "Reading AX affordances is not an expansion request")
        XCTAssertEqual(expanded.wrappedValue, [])
        // The audit separately invokes the real external AX Expand/Collapse actions through
        // CUA. Here exercise the native expansion transition after the eligibility reads.
        view.outlineView.expandItem(view.outlineView.item(atRow: 0))
        XCTAssertEqual(loads, ["remote"], "A real expansion transition loads exactly once")
        XCTAssertTrue(view.isExpanded("remote"))
        XCTAssertEqual(expanded.wrappedValue, ["remote"])
        view.outlineView.expandItem(view.outlineView.item(atRow: 0))
        XCTAssertEqual(loads, ["remote"], "An already-expanded node does not load twice")
    }

    @MainActor func testCollapsePublishesStateBeforeCallbackAndPreservesAReopenRequest() throws {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: Set(["root"]))
        var seen: [Set<String>] = [], opens = 0
        let tree = FluentTreeView(nodes: [FluentTreeViewNode(id: "root", children: [FluentTreeViewNode(id: "child") { FluentText("Child") }]) { FluentText("Root") }])
            .expandedIDs(expanded.projectedValue).onExpanding { _ in opens += 1 }.onCollapsed { _ in
                seen.append(expanded.wrappedValue)
                expanded.wrappedValue = ["root"]
            }
        let view = try XCTUnwrap(tree._makeView(in: FluentRenderContext()) as? FluentOutlineView<String>)
        view.toggleExpansion("root")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(seen, [[]])
        XCTAssertEqual(expanded.wrappedValue, ["root"])
        XCTAssertTrue(view.isExpanded("root"))
        XCTAssertEqual(opens, 1)
    }

    @MainActor func testBindingTransitionsRaiseEventsButInitialAndRestoredStateDoNot() throws {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: Set(["initial"]))
        var opening: [String] = [], closing: [String] = []
        func tree(loaded: Bool = false) -> FluentTreeView<String> {
            FluentTreeView(nodes: [
                FluentTreeViewNode(id: "initial", children: [FluentTreeViewNode(id: "a") { FluentText("A") }]) { FluentText("Initial") },
                FluentTreeViewNode(id: "remote", children: loaded ? [FluentTreeViewNode(id: "b") { FluentText("B") }] : [],
                    hasUnrealizedChildren: !loaded) { FluentText("Remote") }
            ]).expandedIDs(expanded.projectedValue).onExpanding { opening.append($0) }.onCollapsed { closing.append($0) }
        }
        let context = FluentRenderContext()
        let view = try XCTUnwrap(tree()._makeView(in: context) as? FluentOutlineView<String>)
        XCTAssertEqual(opening, [], "An initial snapshot is not a transition")
        expanded.wrappedValue = ["remote"]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(opening, ["remote"], "WinUI raises Expanding when the node's IsExpanded property changes")
        XCTAssertEqual(closing, ["initial"])
        XCTAssertTrue(view.isExpanded("remote"))
        XCTAssertTrue(tree(loaded: true)._updateView(view, in: context))
        XCTAssertEqual(opening, ["remote"], "Reloading loaded children preserves, rather than repeats, the transition")
        XCTAssertEqual(closing, ["initial"])
        expanded.wrappedValue = ["remote"]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(opening, ["remote"])
        expanded.wrappedValue = []
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(closing, ["initial", "remote"])
    }
}
