import AppKit
import FluentKit

@main struct Probe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        var rows: [[String: Any]] = []
        func exercise(_ name: String, _ body: (FluentToggle, (String) -> Void) -> Void) {
            let toggle = FluentToggle(title: "Test", isOn: false)
            toggle.frame = NSRect(x: 20, y: 20, width: 160, height: 32)
            toggle.reduceMotion = true
            root.addSubview(toggle)
            root.layoutSubtreeIfNeeded()
            var callbacks = 0
            toggle.onValueChanged = { _ in callbacks += 1 }
            body(toggle) { step in
                rows.append(["case": name, "step": step, "isOn": toggle.isOn, "callbacks": callbacks])
            }
            toggle.removeFromSuperview()
        }
        func key(_ type: NSEvent.EventType, _ code: UInt16 = 49, repeating: Bool = false) -> NSEvent {
            let characters = code == 49 ? " " : "\r"
            return NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: repeating, keyCode: code)!
        }
        exercise("space") { toggle, record in
            toggle.keyDown(with: key(.keyDown)); record("down")
            toggle.keyDown(with: key(.keyDown, repeating: true)); record("repeat")
            toggle.keyUp(with: key(.keyUp)); record("up")
        }
        exercise("unpaired-release") { toggle, record in
            toggle.keyUp(with: key(.keyUp)); record("up")
        }
        exercise("return") { toggle, record in
            toggle.keyDown(with: key(.keyDown, 36)); record("down")
            toggle.keyUp(with: key(.keyUp, 36)); record("up")
        }
        exercise("cancel") { toggle, record in
            toggle.keyDown(with: key(.keyDown)); record("down")
            toggle.cancelOperation(nil); record("cancel")
            toggle.keyUp(with: key(.keyUp)); record("up")
        }
        exercise("disable") { toggle, record in
            toggle.keyDown(with: key(.keyDown)); record("down")
            toggle.isEnabled = false; record("disabled")
            toggle.keyUp(with: key(.keyUp)); record("up")
        }
        exercise("accessibility") { toggle, record in
            _ = toggle.accessibilityPerformPress(); record("press")
        }
        print(String(data: try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        window.close()
    }
}
