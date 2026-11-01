import AppKit
import FluentKit
@main struct CaptionGeometryAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 200),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        window.contentView = root
        let header = NSView(frame: NSRect(x: 0, y: 168, width: 600, height: 32))
        root.addSubview(header)
        window.applyFluentWindowControlsStyle(.windows, titleBarHeight: 32, hostedIn: header)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        root.layoutSubtreeIfNeeded()
        let controls = header.subviews.first { $0.identifier?.rawValue == "FluentKit.WindowControls.Windows" }!
        var rows: [[String: Any]] = []
        for height: CGFloat in [32, 40, 48] {
            header.frame = NSRect(x: 0, y: 200-height, width: 600, height: height)
            root.layoutSubtreeIfNeeded()
            for host in controls.subviews {
                guard let button = host.subviews.first as? NSButton else { continue }
                let insets = button.alignmentRectInsets
                rows.append(["name": button.identifier!.rawValue, "height": height,
                    "hostFrame": NSStringFromRect(host.frame), "buttonFrame": NSStringFromRect(button.frame),
                    "buttonInHeader": NSStringFromRect(button.convert(button.bounds, to: header)),
                    "alignmentInsets": [insets.top, insets.left, insets.bottom, insets.right],
                    "contained": host.bounds.contains(button.frame), "fillsHost": host.bounds == button.frame])
            }
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]))
    }
}
