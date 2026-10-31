import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

@main struct SettingsMotionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = try RimeEngine(sharedDirectory: URL(fileURLWithPath: CommandLine.arguments[2]),
            userDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-MotionAudit-" + UUID().uuidString))
        defer { FIMFinalize() }
        let controller = try SettingsWindowController(engine: engine)
        controller.showWindow(nil)
        let window = controller.window!, root = window.contentView!
        if ProcessInfo.processInfo.environment["MOTION_AUDIT_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular); window.title = "Fluent Settings Motion Audit"
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); NSApp.run(); return
        }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func layers(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers) }
        let scroll = Mirror(reflecting: controller).descendant("scroll") as! NSScrollView
        let motion = Mirror(reflecting: controller).descendant("pageMotion") as! IMEPageMotion
        var records: [[String: Any]] = []
        func capture(_ name: String, wait: TimeInterval = 0.025) throws {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: wait))
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
            let tree = layers(root.layer!)
            let oldPages = tree.filter { $0.animation(forKey: "FluentIME.Page.Exit") != nil }
            let incoming = tree.filter { $0.animation(forKey: "FluentIME.Page.Entrance") != nil }
            let title = tree.filter { $0.animation(forKey: "FluentIME.TitleBar.Visibility") != nil }
            records.append(["state": name, "viewport": NSStringFromRect(scroll.contentView.bounds),
                "outgoingPages": oldPages.count, "incomingPages": incoming.count, "titleAnimations": title.count,
                "oldFrames": oldPages.map { NSStringFromRect($0.frame) },
                "backHidden": all(root).first { $0.identifier?.rawValue == "FluentKit.TitleBar.Back" }!.isHidden])
            if let snapshot = motion.capture(scroll.contentView) {
                try NSBitmapImageRep(cgImage: snapshot.image).representation(using: .png, properties: [:])!
                    .write(to: output.appendingPathComponent(name + ".png"))
            }
        }
        func open(_ name: String) {
            let button = all(root).compactMap { $0 as? NSButton }.first {
                $0.title == name && String(describing: type(of: $0)) == "SettingsNavigationButton"
            }!
            NSApp.sendAction(button.action!, to: button.target, from: button)
        }
        func back() {
            let button = all(root).first { $0.identifier?.rawValue == "FluentKit.TitleBar.Back" } as! NSButton
            button.performClick(nil)
        }
        try capture("home", wait: 0.1)
        for (index, name) in ["常规", "按键", "外观", "词库和自学习"].enumerated() {
            open(name); try capture("detail-\(index)")
            back(); try capture("return-\(index)")
        }
        open("常规"); try capture("before-resize")
        window.setContentSize(NSSize(width: 1000, height: 850)); try capture("resized", wait: 0.01)
        try capture("settled", wait: 0.6)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120)); try capture("scrolled", wait: 0.02)
        back(); try capture("back-from-scrolled")
        try capture("final", wait: 0.6)
        window.close()
        records.append(["state": "closed", "remainingPageAnimations": layers(root.layer!).filter {
            ($0.animationKeys() ?? []).contains { $0.hasPrefix("FluentIME.Page.") }
        }.count])
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
