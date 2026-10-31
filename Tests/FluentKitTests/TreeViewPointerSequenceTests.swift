import XCTest
@testable import FluentKit

final class TreeViewPointerSequenceTests: XCTestCase {
    @MainActor private struct Fixture {
        let checked = FluentState(wrappedValue: Set<String>())
        let expanded = FluentState(wrappedValue: Set<String>())
        let context: FluentRenderContext
        let window: NSWindow
        let view: FluentOutlineView<String>

        init(multiple: Bool = true, rtl: Bool = false) throws {
            _ = NSApplication.shared
            context = FluentRenderContext(theme: .custom(colorScheme: .light, materialEffectsEnabled: false),
                reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            let tree = FluentTreeView(nodes: Self.nodes("root"), selection: multiple ? .multiple(checked.projectedValue) : .none)
                .expandedIDs(expanded.projectedValue)
            view = try XCTUnwrap(tree._makeView(in: context) as? FluentOutlineView<String>)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; view.layoutSubtreeIfNeeded()
        }
        static func nodes(_ id: String) -> [FluentTreeViewNode<String>] {
            [FluentTreeViewNode(id: id, children: [FluentTreeViewNode(id: "child") { FluentText("Child") }]) { FluentText(id) }]
        }
        func cell() throws -> FluentOutlineCellHost {
            let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FluentOutlineCellHost)
            cell.layoutSubtreeIfNeeded(); return cell
        }
        func event(_ type: NSEvent.EventType, _ cell: NSView, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: cell.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
    }

    @MainActor func testChevronUsesFullTemplatePaddingAndExcludesPresenterMargins() throws {
        for multiple in [false, true] { for rtl in [false, true] {
            let f = try Fixture(multiple: multiple, rtl: rtl); defer { f.window.close() }
            let cell = try f.cell(), glyph = cell.chevronFrame
            let trailing = NSPoint(x: rtl ? glyph.minX - 13 : glyph.maxX + 13, y: glyph.midY)
            XCTAssertTrue(f.view.outlineView.handleAccessoryMouseDown(f.event(.leftMouseDown, cell, trailing)))
            XCTAssertEqual(f.expanded.wrappedValue, ["root"], "The entire trailing 14pt padding expands on press")
            f.view.outlineView.mouseUp(with: f.event(.leftMouseUp, cell, trailing))
            XCTAssertEqual(f.expanded.wrappedValue, ["root"], "Release must not toggle a second time")
            if !multiple {
                let leading = NSPoint(x: rtl ? glyph.maxX + 13 : glyph.minX - 13, y: glyph.midY)
                XCTAssertTrue(f.view.outlineView.handleAccessoryMouseDown(f.event(.leftMouseDown, cell, leading)))
                XCTAssertEqual(f.expanded.wrappedValue, [])
                f.view.outlineView.mouseUp(with: f.event(.leftMouseUp, cell, leading))
            }
            XCTAssertFalse(f.view.outlineView.handleAccessoryMouseDown(f.event(.leftMouseDown, cell, NSPoint(x: glyph.midX, y: 1))))
            if multiple {
                XCTAssertFalse(f.view.outlineView.handleAccessoryMouseDown(f.event(.leftMouseDown, cell, NSPoint(x: cell.checkBoxFrame.midX, y: 1))))
            }
        } }
    }

    @MainActor func testCheckboxReleaseOutsideCancelsAndReentryCommitsOnce() throws {
        for rtl in [false, true] {
            let f = try Fixture(rtl: rtl); defer { f.window.close() }
            let cell = try f.cell(), inside = NSPoint(x: cell.checkBoxFrame.midX, y: cell.checkBoxFrame.midY)
            let outside = NSPoint(x: cell.bounds.midX, y: inside.y)
            let normal = cell.checkBoxLayer.backgroundColor
            f.view.outlineView.mouseDown(with: f.event(.leftMouseDown, cell, inside))
            XCTAssertEqual(f.checked.wrappedValue, [])
            XCTAssertNotEqual(cell.checkBoxLayer.backgroundColor, normal, "Press uses checkbox pressed chrome")
            f.view.outlineView.mouseDragged(with: f.event(.leftMouseDragged, cell, outside))
            XCTAssertEqual(cell.checkBoxLayer.backgroundColor, normal)
            f.view.outlineView.mouseUp(with: f.event(.leftMouseUp, cell, outside))
            XCTAssertEqual(f.checked.wrappedValue, [])
            f.view.outlineView.mouseDown(with: f.event(.leftMouseDown, cell, inside))
            f.view.outlineView.mouseDragged(with: f.event(.leftMouseDragged, cell, outside))
            f.view.outlineView.mouseDragged(with: f.event(.leftMouseDragged, cell, inside))
            XCTAssertEqual(f.checked.wrappedValue, [])
            f.view.outlineView.mouseUp(with: f.event(.leftMouseUp, cell, inside))
            XCTAssertEqual(f.checked.wrappedValue, ["root", "child"])
            f.view.outlineView.mouseUp(with: f.event(.leftMouseUp, cell, inside))
            XCTAssertEqual(f.checked.wrappedValue, ["root", "child"], "Duplicate release cannot repeat an action")
        }
    }

    @MainActor func testCaptureCancellationAndRemovedRowsCannotCommit() throws {
        for cancellation in ["escape", "resign-window", "detach", "replace", "mode"] {
            let f = try Fixture(); defer { f.window.close() }
            let cell = try f.cell(), point = NSPoint(x: cell.checkBoxFrame.midX, y: cell.checkBoxFrame.midY)
            let up = f.event(.leftMouseUp, cell, point)
            f.view.outlineView.mouseDown(with: f.event(.leftMouseDown, cell, point))
            switch cancellation {
            case "escape": f.view.outlineView.cancelOperation(nil)
            case "resign-window": NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
            case "detach": f.window.contentView = nil; f.window.contentView = f.view
            case "replace":
                XCTAssertTrue(FluentTreeView(nodes: Fixture.nodes("replacement"), selection: .multiple(f.checked.projectedValue))._updateView(f.view, in: f.context))
            default:
                XCTAssertTrue(FluentTreeView(nodes: Fixture.nodes("root"), selection: .none)._updateView(f.view, in: f.context))
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            f.view.outlineView.mouseUp(with: up)
            XCTAssertEqual(f.checked.wrappedValue, [], cancellation)
        }
    }
}
