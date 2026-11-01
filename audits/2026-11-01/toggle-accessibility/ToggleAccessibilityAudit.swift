import AppKit
import FluentKit

@main struct ToggleAccessibilityAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: false)
        let bound = FluentBoundToggle(state.projectedValue, title: "Bound switch")
        let direct = FluentToggle(title: "Direct switch")
        let native = NSSwitch(frame: .zero)
        native.setAccessibilityTitle("Native reference")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for (i, view) in [direct, bound, native].enumerated() {
            view.frame = NSRect(x: 20, y: 130 - i * 50, width: 300, height: 32)
            window.contentView!.addSubview(view)
        }
        window.orderFront(nil)
        window.contentView!.layoutSubtreeIfNeeded()
        var rows: [[String: Any]] = []
        func record(_ stage: String) {
            for control: NSControl in [direct, bound.toggle, native] {
                let value = control.accessibilityValue()
                rows.append(["stage": stage, "title": control.accessibilityTitle() ?? "", "exposed": control.isAccessibilityElement(),
                    "role": control.accessibilityRole()?.rawValue ?? "nil", "subrole": control.accessibilitySubrole()?.rawValue ?? "nil", "roleDescription": control.accessibilityRoleDescription() ?? "nil", "enabled": control.isAccessibilityEnabled(),
                    "valueType": value.map { String(describing: type(of: $0)) } ?? "nil",
                    "value": value as? NSNumber ?? String(describing: value ?? "nil") as Any,
                    "isNumericValue": value is NSNumber, "binding": state.wrappedValue])
            }
        }
        record("initial")
        _ = direct.accessibilityPerformPress()
        _ = bound.toggle.accessibilityPerformPress()
        native.state = .on
        record("pressed")
        direct.isEnabled = false; bound.toggle.isEnabled = false; native.isEnabled = false
        _ = direct.accessibilityPerformPress(); _ = bound.toggle.accessibilityPerformPress()
        record("disabled-press")
        state.wrappedValue = false
        direct.isOn = false; native.state = .off
        record("external-off")
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
