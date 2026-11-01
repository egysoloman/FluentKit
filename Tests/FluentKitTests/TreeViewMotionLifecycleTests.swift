import XCTest
@testable import FluentKit

@MainActor
final class TreeViewMotionLifecycleTests: XCTestCase {
    private let rotationKey = "fluent.chevron.press"

    private func tree(_ title: String = "Root", multiple: Bool = false) -> FluentTreeView<String> {
        FluentTreeView(nodes: [
            FluentTreeViewNode(id: "root", children: [
                FluentTreeViewNode(id: "a") { FluentText("A") },
                FluentTreeViewNode(id: "b") { FluentText("B") }
            ]) { FluentText(title) },
            FluentTreeViewNode(id: "tail") { FluentText("Tail") }
        ], selection: multiple ? .multiple(FluentState(wrappedValue: Set<String>()).projectedValue) : .single(nil))
    }

    private func mount(multiple: Bool = false) throws -> (NSWindow, FluentOutlineView<String>, FluentOutlineCellHost) {
        _ = NSApplication.shared
        let view = try XCTUnwrap(tree(multiple: multiple)._makeView(in: .init(reduceMotion: false)) as? FluentOutlineView<String>)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible, "Disclosure motion is exercised in a displayed outline")
        view.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FluentOutlineCellHost)
        cell.layoutSubtreeIfNeeded()
        return (window, view, cell)
    }

    func testExpansionMotionSurvivesNativeLayoutAndStableContentUpdates() throws {
        let (window, view, cell) = try mount()
        defer { window.close() }
        let content = try XCTUnwrap(cell.contentView)
        view.toggleExpansion("root")
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey),
                        "visible=\(window.isVisible), systemReduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
        cell.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey), "Layout must not finish an in-flight rotation")
        XCTAssertTrue(tree("Updated root")._updateView(view, in: .init(reduceMotion: false)))
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey), "A content refresh must not cancel disclosure motion")
        XCTAssertTrue(cell.contentView === content)
        XCTAssertTrue(view.outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) === cell)
        XCTAssertEqual(view.outlineView.numberOfRows, 4)
        XCTAssertEqual(view.outlineView.rect(ofRow: 3).minY, 96, accuracy: 0.01)
        XCTAssertTrue(view.isExpanded("root"))
    }

    func testReusedCellStartsAtTheNewNodesDirectionWithoutAnOldTransition() {
        _ = NSApplication.shared
        let cell = FluentOutlineCellHost(frame: NSRect(x: 0, y: 0, width: 340, height: 32))
        let first = NSObject(), second = NSObject()
        func update(_ item: NSObject, expanded: Bool) {
            cell.update(representedItem: ObjectIdentifier(item), content: FluentAnyView(FluentText("Node")),
                context: .init(reduceMotion: false), layout: .init(depth: 0, isMultiple: false,
                    isExpandable: true, isExpanded: expanded, checkState: nil, rowHeight: 32, isRightToLeft: false),
                onToggleExpansion: {}, onToggleCheck: {})
        }
        update(first, expanded: true)
        update(second, expanded: false)
        XCTAssertNil(cell.chevronLayer.animation(forKey: rotationKey), "Reusing a row is not collapsing the previous node")
        XCTAssertEqual(cell.chevronLayer.transform.m12, -1, accuracy: 0.001)
    }

    func testReducedMotionAndDetachmentFinishOnlyTheCurrentDisclosureMotion() throws {
        let (window, view, cell) = try mount()
        defer { window.close() }
        view.toggleExpansion("root")
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey))
        XCTAssertTrue(tree()._updateView(view, in: .init(reduceMotion: true)))
        XCTAssertNil(cell.chevronLayer.animation(forKey: rotationKey))
        XCTAssertEqual(cell.chevronLayer.transform.m11, 1, accuracy: 0.001)
        XCTAssertTrue(tree()._updateView(view, in: .init(reduceMotion: false)))
        view.toggleExpansion("root")
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey))
        view.removeFromSuperview()
        XCTAssertNil(cell.chevronLayer.animation(forKey: rotationKey), "Detached cells must not retain disclosure animations")
        XCTAssertEqual(cell.chevronLayer.transform.m12, -1, accuracy: 0.001)
    }

    func testAccessoryPointerAndBackingChangesDoNotCancelRotation() throws {
        let (window, view, cell) = try mount(multiple: true)
        defer { window.close() }
        view.toggleExpansion("root")
        cell.beginCheckBoxPress()
        cell.cancelCheckBoxPress()
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey), "Independent accessory state must not finish disclosure motion")
        cell.viewDidChangeBackingProperties()
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey))
        XCTAssertEqual(cell.chevronLayer.contentsScale, window.backingScaleFactor)
    }

    func testThemeRefreshKeepsMotionAndRTLSwitchUsesTheNewDirection() throws {
        let (window, view, cell) = try mount()
        defer { window.close() }
        view.toggleExpansion("root")
        XCTAssertTrue(tree()._updateView(view, in: .init(theme: .custom(colorScheme: .dark), reduceMotion: false)))
        cell.layoutSubtreeIfNeeded()
        XCTAssertNotNil(cell.chevronLayer.animation(forKey: rotationKey))
        let rtl = FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
        XCTAssertTrue(tree()._updateView(view, in: rtl))
        XCTAssertNil(cell.chevronLayer.animation(forKey: rotationKey), "Direction changes settle the previous coordinate system")
        view.layoutSubtreeIfNeeded()
        // AppKit can replace row views when the outline's layout direction changes.
        let rtlCell = try XCTUnwrap(view.outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FluentOutlineCellHost)
        XCTAssertEqual(rtlCell.layoutState?.isRightToLeft, true)
        XCTAssertNil(rtlCell.chevronLayer.animation(forKey: rotationKey))
        view.toggleExpansion("root")
        rtlCell.layoutSubtreeIfNeeded()
        XCTAssertNotNil(rtlCell.chevronLayer.animation(forKey: rotationKey))
        XCTAssertEqual(rtlCell.chevronLayer.transform.m12, 1, accuracy: 0.001)
        XCTAssertFalse(view.isExpanded("root"))
        XCTAssertEqual(view.outlineView.numberOfRows, 2)
    }
}
