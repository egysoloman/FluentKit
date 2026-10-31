import AppKit
import FluentKit

final class KeyboardWindow: NSWindow {
    var check: FluentCheckBox?
    var radio: FluentRadioButton?
    var output: URL!
    var records: [[String: Any]] = []
    override func sendEvent(_ event: NSEvent) {
        let relevant = event.type == .keyDown || event.type == .keyUp
        if relevant { record("before", event) }
        super.sendEvent(event)
        if relevant { record("after", event) }
    }
    func record(_ phase: String, _ event: NSEvent? = NSApp.currentEvent) {
        guard let check, let radio, let output else { return }
        records.append(["phase": phase, "type": event.map { String(describing: $0.type) } ?? "none",
            "eventTypeRaw": event.map { Int($0.type.rawValue) } ?? -1,
            "keyCode": event.flatMap { $0.type == .keyDown || $0.type == .keyUp ? $0.keyCode : nil } ?? 0,
            "checked": check.isChecked, "selected": radio.isSelected,
            "focus": firstResponder === check ? "check" : (firstResponder === radio ? "radio" : "other")])
        if let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output)
        }
    }
}

@MainActor final class Review: NSObject {
    let window: KeyboardWindow
    let check = FluentCheckBox(title: "CheckBox keyboard target")
    let radio = FluentRadioButton(title: "RadioButton keyboard target")
    override init() {
        window = KeyboardWindow(contentRect: NSRect(x: 150, y: 150, width: 450, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false; window.title = "Choice keyboard review"
        window.output = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "AuditOutputPath") as! String)
        window.check = check; window.radio = radio
        let root = window.contentView!
        check.frame = NSRect(x: 20, y: 170, width: 360, height: 32)
        radio.frame = NSRect(x: 20, y: 125, width: 360, height: 32)
        root.addSubview(check); root.addSubview(radio)
        check.onValueChanged = { [weak self] _ in self?.window.record("valueChanged") }
        radio.onValueChanged = { [weak self] _ in self?.window.record("valueChanged") }
        let focusCheck = NSButton(title: "Focus CheckBox", target: self, action: #selector(focusCheckBox))
        let focusRadio = NSButton(title: "Focus RadioButton", target: self, action: #selector(focusRadioButton))
        focusCheck.frame = NSRect(x: 20, y: 50, width: 190, height: 32)
        focusRadio.frame = NSRect(x: 220, y: 50, width: 190, height: 32)
        root.addSubview(focusCheck); root.addSubview(focusRadio)
        let menu = NSMenu(); let app = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = submenu; menu.addItem(app); NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window.record("initial", nil)
    }
    @objc func focusCheckBox() { window.makeFirstResponder(check); window.record("focus-check", nil) }
    @objc func focusRadioButton() { window.makeFirstResponder(radio); window.record("focus-radio", nil) }
}

@main struct KeyboardReview {
    @MainActor static var review: Review?
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
        review = Review(); NSApp.run()
    }
}
