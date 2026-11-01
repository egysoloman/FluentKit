import AppKit
import FluentKit

@main struct InitialLayoutAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = FluentViewHost(FluentRefreshContainer(pullDirection: .leftToRight,
            onRefreshRequested: { $0.complete() }) {
            FluentHStack {
                FluentForEach(Array(0..<20), id: \.self) { FluentText("Column \($0)").frame(width: 80) }
            }
        }.frame(width: 420, height: 300), context: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 360, width: 420, height: 300),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        root.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        fputs("PHASE: first layout\n", stderr)
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let records = all(root).map { view in
            ["type": String(describing: type(of: view)), "id": view.identifier?.rawValue ?? "",
             "frame": NSStringFromRect(view.frame)]
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]))
    }
}
