import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

@MainActor private final class IntegrationActions: NSObject {
    let controller: SettingsWindowController
    let output: URL
    var rows: [[String: Any]] = []
    var monitor: Any?
    init(controller: SettingsWindowController, output: URL) { self.controller = controller; self.output = output }
    func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    func layer(_ name: String, _ root: CALayer?) -> CALayer? {
        guard let root else { return nil }
        if root.name == name { return root }
        return root.sublayers?.compactMap { layer(name, $0) }.first
    }
    func capture(_ reason: String, screenshot: Bool = false) {
        guard let window = controller.window, let root = window.contentView else { return }
        let search = all(root).compactMap { $0 as? FluentSearchTextField }.first!
        let editor = search.currentEditor() as? NSTextView
        var row: [String: Any] = ["reason": reason, "uptime": ProcessInfo.processInfo.systemUptime,
            "window": NSStringFromRect(window.frame), "appearance": window.effectiveAppearance.name.rawValue,
            "preference": Preferences.shared.appearance, "page": String(describing: Mirror(reflecting: controller).descendant("page")!),
            "searchIdentity": String(describing: ObjectIdentifier(search)), "search": search.stringValue,
            "marked": editor?.hasMarkedText() ?? false, "editorIdentity": editor.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
            "inputSource": editor?.inputContext?.selectedKeyboardInputSource ?? "nil",
            "searchScreenFrame": NSStringFromRect(window.convertToScreen(search.convert(search.bounds, to: nil))),
            "menus": (window.childWindows ?? []).filter(\.isVisible).map { ["frame": NSStringFromRect($0.frame), "appearance": $0.effectiveAppearance.name.rawValue] },
            "toggles": all(root).compactMap { $0 as? FluentToggle }.map { toggle -> [String: Any] in
                let knob = layer("FluentKit.Toggle.Knob", toggle.layer), track = layer("FluentKit.Toggle.Track", toggle.layer)
                return ["label": toggle.accessibilityLabel() ?? "", "on": toggle.isOn,
                    "knob": knob.map { NSStringFromRect($0.bounds) } ?? "nil",
                    "presentationKnob": knob?.presentation().map { NSStringFromRect($0.bounds) } ?? "nil",
                    "track": track.map { NSStringFromRect($0.bounds) } ?? "nil"]
            }]
        if let editor { row["caret"] = NSStringFromRect(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)) }
        rows.append(row)
        do {
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("states.json"), options: .atomic)
            if screenshot {
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width * 2), pixelsHigh: Int(root.bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                if root.isFlipped { cg.translateBy(x: 0, y: root.bounds.height); cg.scaleBy(x: 1, y: -1) }
                root.layer?.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("capture-\(rows.count).png"))
            }
        } catch { print(error) }
    }
    @objc func record(_ sender: Any?) { capture("manual", screenshot: true) }
    @objc func light(_ sender: Any?) { NSApp.appearance = NSAppearance(named: .aqua); capture("app-light") }
    @objc func dark(_ sender: Any?) { NSApp.appearance = NSAppearance(named: .darkAqua); capture("app-dark") }
    @objc func quit(_ sender: Any?) { if let monitor { NSEvent.removeMonitor(monitor) }; NSApp.stop(nil) }
    func install() {
        let bar = NSMenu(), item = NSMenuItem(), menu = NSMenu(title: "Integration audit")
        item.submenu = menu; bar.addItem(item)
        for (title, key, selector) in [("Record own window", "s", #selector(IntegrationActions.record(_:))), ("Application light signal", "l", #selector(IntegrationActions.light(_:))), ("Application dark signal", "d", #selector(IntegrationActions.dark(_:)))] {
            let action = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            action.target = self; action.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(action)
        }
        let quit = NSMenuItem(title: "Quit integration audit", action: #selector(IntegrationActions.quit(_:)), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); NSApp.mainMenu = bar
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.controller.window else { return event }
            for delay in [0.03, 0.14, 0.25] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.capture("\(event.type)-\(delay)") }
            }
            return event
        }
    }
}

@main struct SettingsIntegrationAudit {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "org.fluentkit.audit.settings.integration")
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = try RimeEngine(sharedDirectory: URL(fileURLWithPath: CommandLine.arguments[2]),
            userDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-IntegrationAudit-" + UUID().uuidString))
        defer { FIMFinalize() }
        let controller = try SettingsWindowController(engine: engine)
        controller.showWindow(nil); controller.window!.title = "Fluent Settings Integration Audit"
        let actions = IntegrationActions(controller: controller, output: output)
        actions.install(); actions.capture("opened")
        NSApp.activate(ignoringOtherApps: true)
        withExtendedLifetime(actions) { NSApp.run() }
        controller.window?.close()
    }
}
