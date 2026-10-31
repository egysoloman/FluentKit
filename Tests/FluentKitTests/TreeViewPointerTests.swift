import XCTest
@testable import FluentKit

final class TreeViewPointerTests: XCTestCase {
    @MainActor func testDrawnCheckBoxAndChevronReceiveNativeOutlineClicksInBothDirections() throws {
        _ = NSApplication.shared
        for direction: FluentLayoutDirection in [.leftToRight, .rightToLeft] {
            let checked = FluentState(wrappedValue: Set<String>())
            let expanded = FluentState(wrappedValue: Set<String>())
            var invoked = 0
            let tree = FluentTreeView(nodes: [
                FluentTreeViewNode(id: "root", children: [FluentTreeViewNode(id: "child") { FluentText("Child") }]) { FluentText("Root") }
            ], selection: .multiple(checked.projectedValue)).expandedIDs(expanded.projectedValue).onItemInvoked { _ in invoked += 1 }
            let view = try XCTUnwrap(tree._makeView(in: FluentRenderContext(layoutDirection: direction)) as? FluentOutlineView<String>)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view
            view.layoutSubtreeIfNeeded()
            let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FluentOutlineCellHost)
            cell.layoutSubtreeIfNeeded()
            func event(at point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: .leftMouseDown, location: cell.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            XCTAssertTrue(view.outlineView.handleAccessoryMouseDown(event(at: NSPoint(x: cell.checkBoxFrame.midX, y: cell.checkBoxFrame.midY))))
            XCTAssertEqual(checked.wrappedValue, [], "A checkbox commits on release, unlike the chevron")
            view.outlineView.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp,
                location: cell.convert(NSPoint(x: cell.checkBoxFrame.midX, y: cell.checkBoxFrame.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 0)!)
            XCTAssertEqual(checked.wrappedValue, ["root", "child"])
            XCTAssertEqual(view.outlineView.selectedRow, 0)
            XCTAssertTrue(view.outlineView.handleAccessoryMouseDown(event(at: NSPoint(x: cell.chevronFrame.midX, y: cell.chevronFrame.midY))))
            XCTAssertEqual(expanded.wrappedValue, ["root"])
            XCTAssertEqual(invoked, 0, "Accessory clicks are handled, not row invocation")
            XCTAssertFalse(view.outlineView.handleAccessoryMouseDown(event(at: NSPoint(x: cell.bounds.midX, y: cell.bounds.midY))), "Ordinary content remains available to native drag tracking")
            window.close()
        }
    }
}
