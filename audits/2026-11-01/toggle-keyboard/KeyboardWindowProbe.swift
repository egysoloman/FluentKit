import AppKit
import FluentKit

private final class AuditRoot: NSView {
    var onUnhandled: ((NSEvent) -> Void)?
    override func keyDown(with event: NSEvent) { onUnhandled?(event) }
    override func keyUp(with event: NSEvent) { onUnhandled?(event) }
}
private final class AuditDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct KeyboardWindowProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AuditDelegate()
        app.delegate = delegate
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        app.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 240, y: 220, width: 460, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "FluentKit Toggle Keyboard Audit"
        window.isReleasedWhenClosed = false
        let root = AuditRoot(frame: window.contentView!.bounds)
        window.contentView = root
        let toggle = FluentToggle(title: "Keyboard switch", isOn: false)
        toggle.frame = NSRect(x: 28, y: 94, width: 350, height: 40)
        let status = NSTextField(labelWithString: "Off · 0 changes")
        status.frame = NSRect(x: 28, y: 48, width: 380, height: 28)
        root.addSubview(toggle)
        root.addSubview(status)
        var commits = 0
        func record(_ kind: String, event: NSEvent? = nil) {
            var row: [String: Any] = ["kind": kind, "time": ProcessInfo.processInfo.systemUptime,
                "isOn": toggle.isOn, "commits": commits]
            if let event { row["keyCode"] = Int(event.keyCode); row["repeat"] = event.isARepeat }
            let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            FileHandle.standardOutput.write(data + Data([10]))
        }
        root.onUnhandled = { record($0.type == .keyDown ? "parent-keyDown" : "parent-keyUp", event: $0) }
        toggle.onValueChanged = { value in
            commits += 1
            status.stringValue = "\(value ? "On" : "Off") · \(commits) changes"
            record("valueChanged")
        }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            record(event.type == .keyDown ? "keyDown" : "keyUp", event: event)
            return event
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(toggle)
        record("ready")
        withExtendedLifetime(delegate) { app.run() }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
