import AppKit
import FluentKit
@main struct MaterialUpdateAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var rows: [[String: Any]] = []
        for style in [FluentMaterial.mica, .nativeAcrylic, .nativeMica, .liquidGlass] {
            func content(_ revision: Int) -> some FluentView {
                FluentMaterialSurface(material: style) {
                    FluentVStack { FluentText("Revision \(revision)"); FluentText("Stable content") }
                }
            }
            let host = FluentViewHost(content(0), context: FluentRenderContext(theme: .custom(colorScheme: .dark), reduceMotion: true))
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 360, height: 120),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            var milliseconds: [Double] = []
            for iteration in 0..<220 {
                let start = DispatchTime.now().uptimeNanoseconds
                host.update(content(iteration))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                CATransaction.flush()
                if iteration >= 20 { milliseconds.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000) }
            }
            window.orderOut(nil)
            milliseconds.sort()
            rows.append(["material": String(describing: style), "count": milliseconds.count,
                "averageMS": milliseconds.reduce(0,+)/Double(milliseconds.count),
                "medianMS": milliseconds[milliseconds.count/2], "p95MS": milliseconds[Int(Double(milliseconds.count)*0.95)]])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]))
    }
}
