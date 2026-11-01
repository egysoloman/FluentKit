import AppKit
import FluentKit

@main struct InitialLayoutAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "Preset")
        let expanded = FluentState(wrappedValue: true)
        let definition = FluentExpander("Sample", isExpanded: expanded.projectedValue) {
            FluentVStack(alignment: .leading) {
                FluentComboBox(options: ["Preset", "中文"], selection: selection.projectedValue).frame(width: 220)
                FluentText("Following content")
            }
        }
        fputs("PHASE: mounting before allocation\n", stderr)
        let native = definition._mount(in: .init(reduceMotion: true))
        fputs("PHASE: allocating window\n", stderr)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = window.contentView!
        root.addSubview(native)
        native.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            native.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            native.topAnchor.constraint(equalTo: root.topAnchor),
            native.widthAnchor.constraint(equalToConstant: 380)
        ])
        window.orderFront(nil)
        root.layoutSubtreeIfNeeded()
        fputs("PHASE: laid out\n", stderr)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let records = all(native).map { view in
            ["type": String(describing: type(of: view)), "id": view.identifier?.rawValue ?? "",
             "frame": NSStringFromRect(view.frame), "intrinsic": NSStringFromSize(view.intrinsicContentSize)]
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]))
    }
}
