import XCTest
@testable import FluentKit

final class ViewBuilderConditionalTests: XCTestCase {
    @MainActor private func text(in view: NSView) -> [String] {
        (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { text(in: $0) }
    }

    @MainActor func testSingleIfWithoutElseCompilesAndMountsBothBranches() {
        _ = NSApplication.shared
        for visible in [false, true] {
            let view = FluentVStack {
                if visible { FluentText("Visible") }
            }._makeView(in: FluentRenderContext())
            XCTAssertEqual(text(in: view), visible ? ["Visible"] : [])
        }
    }

    @MainActor func testOptionalBindingAndNestedConditionalsComposeWithSiblings() {
        _ = NSApplication.shared
        for value: String? in [nil, "Value"] {
            let view = FluentVStack {
                FluentText("Always")
                if let value {
                    FluentText(value)
                    if value == "Value" { FluentText("Nested") }
                }
                FluentText("After")
            }._makeView(in: FluentRenderContext())
            XCTAssertEqual(text(in: view), value == nil ? ["Always", "After"] : ["Always", "Value", "Nested", "After"])
        }
    }
}
