import XCTest
@testable import FluentKit

final class FlipViewVirtualizationTests: XCTestCase {
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    @MainActor func testOnlyViewportNeighborhoodBuildsAndUpdatesContent() throws {
        _ = NSApplication.shared
        var builds = 0, makes = 0, updates = 0
        func page(_ value: Int) -> FluentNativeView {
            builds += 1
            return FluentNativeView(make: { makes += 1; return NSTextField(labelWithString: "") },
                update: { (field: NSTextField, _) in updates += 1; field.stringValue = String(value) })
        }
        let context = FluentRenderContext(reduceMotion: true)
        let native = FluentFlipView(Array(0..<1000), content: page)._makeView(in: context)
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180); native.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(builds, 3); XCTAssertLessThanOrEqual(makes, 3)
        builds = 0; updates = 0
        for _ in 0..<5 { XCTAssertTrue(FluentFlipView(Array(0..<1000), content: page)._updateView(native, in: context)) }
        XCTAssertLessThanOrEqual(builds, 15); XCTAssertLessThanOrEqual(updates, 15)
    }
    @MainActor func testAppendingPagesRetainsTheCurrentNativeContent() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        func content(_ count: Int) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(Array(0..<count)) { value in
                FluentNativeView(make: { NSTextField(labelWithString: "") }, update: { (field: NSTextField, _) in field.stringValue = String(value) })
            }
        }
        let native = content(3)._makeView(in: context)
        let first = try XCTUnwrap(all(native).compactMap { $0 as? NSTextField }.first { $0.stringValue == "0" })
        XCTAssertTrue(content(4)._updateView(native, in: context))
        XCTAssertTrue(all(native).contains { $0 === first }, "Appending should not rebuild the currently visible page")
    }
    @MainActor func testRejectedSelectionDoesNotDivergeFromTheBinding() throws {
        _ = NSApplication.shared
        var changes: [Int] = []
        let binding = FluentBinding<Int>(get: { 0 }, set: { _ in })
        let native = FluentFlipView([0,1,2], selection: binding, onSelectionChanged: { changes.append($0) }) { FluentText(String($0)) }
            ._makeView(in: .init(reduceMotion: true))
        native.keyDown(with: key(124))
        XCTAssertEqual(native.accessibilityValue() as? String, "1 of 3")
        XCTAssertTrue(changes.isEmpty)
    }
}
