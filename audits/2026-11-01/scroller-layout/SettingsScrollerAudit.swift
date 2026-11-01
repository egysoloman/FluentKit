import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

@main struct SettingsScrollerAudit {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "org.fluentkit.audit.scroller-layout")
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "AuditOutput") as! String)
        let shared = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "RimeSharedDirectory") as! String)
        let engine = try RimeEngine(sharedDirectory: shared,
            userDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-ScrollerAudit-" + UUID().uuidString))
        defer { FIMFinalize() }
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.14)) }
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var results: [[String: Any]] = []
        for page in ["home", "general", "keys", "appearance", "dictionary", "advanced", "preview"] {
            setenv("FLUENTIME_RENDER_PAGE", page, 1)
            let controller = try SettingsWindowController(engine: engine)
            let window = controller.window!
            controller.showWindow(nil)
            settle()
            let root = window.contentView!
            let scroll = all(root).compactMap { $0 as? NSScrollView }.first!
            let document = scroll.documentView!
            for width: CGFloat in [600, 640, 1100] {
                window.setContentSize(NSSize(width: width, height: 760))
                root.layoutSubtreeIfNeeded(); settle()
                let targetY = min(100, max(0, document.frame.height - scroll.contentView.bounds.height))
                scroll.contentView.scroll(to: NSPoint(x: 0, y: targetY)); scroll.reflectScrolledClipView(scroll.contentView); settle()
                for (step, style) in [nil, NSScroller.Style.overlay, .legacy, .overlay, .legacy].enumerated() {
                    if let style { scroll.scrollerStyle = style }
                    settle()
                    results.append(["page": page, "width": width, "step": step,
                        "requestedStyle": style?.rawValue ?? -1, "actualStyle": scroll.scrollerStyle.rawValue,
                        "scrollerClass": String(describing: type(of: scroll.verticalScroller!)),
                        "overlayCompatible": type(of: scroll.verticalScroller!).isCompatibleWithOverlayScrollers,
                        "viewport": rect(scroll.contentView.bounds), "document": rect(document.frame),
                        "scroll": rect(scroll.frame), "targetY": targetY,
                        "rightGap": scroll.contentView.bounds.width - document.frame.width,
                        "childMaxX": document.subviews.map(\.frame.maxX).max() ?? 0])
                }
            }
            window.close()
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("results.json"))
    }
}
