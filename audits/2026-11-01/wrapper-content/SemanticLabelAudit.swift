import AppKit
import FluentKit

@main struct SemanticLabelAudit {
    static func main() throws {
        _ = NSApplication.shared
        func content(_ value: String) -> some FluentView {
            FluentButtonView(value).accessibilityLabel(value).accessibilityHidden(false)
                .accessibilityElement(children: .combine)
        }
        let host = FluentViewHost(content("Before"))
        let semantic = host.subviews[0]
        let before = semantic.accessibilityLabel() ?? "nil"
        host.update(content("After"))
        let after = semantic.accessibilityLabel() ?? "nil"
        let data = try JSONSerialization.data(withJSONObject: ["before": before, "after": after], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
