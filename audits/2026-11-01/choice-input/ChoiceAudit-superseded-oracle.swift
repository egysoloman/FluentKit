import AppKit
import FluentKit

final class PressRecord { var value = false }
struct CheckStyle: FluentCheckBoxStyle {
    let record: PressRecord
    func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        record.value = configuration.isPressed
        return FluentAutomaticCheckBoxStyle().appearance(for: configuration)
    }
}
struct RadioStyle: FluentRadioButtonStyle {
    let record: PressRecord
    func appearance(for configuration: FluentRadioButtonStyleConfiguration) -> FluentRadioButtonAppearance {
        record.value = configuration.isPressed
        return FluentAutomaticRadioButtonStyle().appearance(for: configuration)
    }
}

@main struct ChoiceAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        for dark in [false, true] { for radio in [false, true] {
            for scenario in ["space", "return", "keypad", "focus", "detach", "window", "external", "rebind", "refresh", "disable", "focus-key", "detach-key", "window-key", "disable-key"] {
                if radio && scenario == "keypad" { continue }
                var context = FluentRenderContext()
                context.theme = .custom(colorScheme: dark ? .dark : .light); context.reduceMotion = true
                let state = FluentState<Bool>(wrappedValue: false), replacement = FluentState<Bool>(wrappedValue: false)
                let press = PressRecord()
                let checkView = FluentCheckBoxView("Keyboard choice", isChecked: state.projectedValue, style: CheckStyle(record: press))
                let radioView = FluentRadioButtonView("Keyboard choice", isSelected: state.projectedValue, style: RadioStyle(record: press))
                let bound = radio ? radioView._makeView(in: context) : checkView._makeView(in: context)
                let control: NSControl = radio ? (bound as! FluentBoundRadioButton).radioButton : (bound as! FluentBoundCheckBox).checkBox
                let window = NSWindow(contentRect: NSRect(x: 20, y: 80, width: 280, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let root = window.contentView!; root.wantsLayer = true; root.layer?.backgroundColor = context.theme.windowBackground.cgColor
                bound.frame = NSRect(x: 15, y: 25, width: 240, height: 32); root.addSubview(bound)
                window.makeKeyAndOrderFront(nil); window.makeFirstResponder(control); root.layoutSubtreeIfNeeded()
                let id = "\(dark ? "dark" : "light")-\(radio ? "radio" : "check")-\(scenario)"
                func key(_ type: NSEvent.EventType, _ code: UInt16 = 49, repeatKey: Bool = false) -> NSEvent {
                    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                        context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeatKey, keyCode: code)!
                }
                func pointer(_ type: NSEvent.EventType) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: control.convert(NSPoint(x: 10, y: 16), to: nil), modifierFlags: [],
                        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                }
                func capture(_ phase: String, selected: Bool, pressed: Bool, image: Bool = false) throws {
                    root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                    rows.append(["id": id + "-" + phase, "selected": (control.accessibilityValue() as? NSNumber)?.boolValue ?? false,
                        "pressed": press.value, "model": state.wrappedValue, "replacement": replacement.wrappedValue,
                        "expected": ["selected": selected, "pressed": pressed]])
                    if image {
                        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 560, pixelsHigh: 180, bitsPerSample: 8,
                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                        let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2); root.layer!.render(in: cg)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(id + "-" + phase + ".png"))
                    }
                }
                switch scenario {
                case "space":
                    try capture("initial", selected: false, pressed: false, image: true)
                    control.keyDown(with: key(.keyDown)); try capture("down", selected: false, pressed: true, image: true)
                    control.keyDown(with: key(.keyDown, repeatKey: true)); try capture("repeat", selected: false, pressed: true)
                    control.keyUp(with: key(.keyUp)); try capture("up", selected: true, pressed: false, image: true)
                case "return":
                    control.keyDown(with: key(.keyDown, 36)); try capture("down", selected: false, pressed: false)
                    state.wrappedValue = false; RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                    control.keyDown(with: key(.keyDown)); control.keyDown(with: key(.keyDown, 36)); control.keyUp(with: key(.keyUp))
                    try capture("cancel-space", selected: false, pressed: false)
                case "keypad":
                    control.keyDown(with: key(.keyDown, 69)); try capture("add", selected: true, pressed: false)
                    control.keyDown(with: key(.keyDown, 78)); try capture("subtract", selected: false, pressed: false)
                case "external":
                    control.keyDown(with: key(.keyDown))
                    state.wrappedValue = true; RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                    try capture("updated-while-held", selected: true, pressed: true, image: true)
                    control.keyUp(with: key(.keyUp)); try capture("up", selected: radio, pressed: false)
                case "rebind", "refresh":
                    control.mouseDown(with: pointer(.leftMouseDown))
                    let binding = scenario == "rebind" ? replacement.projectedValue : state.projectedValue
                    if radio { _ = FluentRadioButtonView("Keyboard choice", isSelected: binding, style: RadioStyle(record: press))._updateView(bound, in: context) }
                    else { _ = FluentCheckBoxView("Keyboard choice", isChecked: binding, style: CheckStyle(record: press))._updateView(bound, in: context) }
                    control.mouseUp(with: pointer(.leftMouseUp))
                    try capture("up", selected: scenario == "refresh", pressed: false)
                default:
                    if scenario.hasSuffix("-key") { control.keyDown(with: key(.keyDown)) }
                    else { control.mouseDown(with: pointer(.leftMouseDown)) }
                    let reason = scenario.replacingOccurrences(of: "-key", with: "")
                    if reason == "focus" { window.makeFirstResponder(nil) }
                    if reason == "detach" { bound.removeFromSuperview() }
                    if reason == "window" { NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window) }
                    if reason == "disable" { control.isEnabled = false; control.isEnabled = true }
                    if scenario.hasSuffix("-key") { control.keyUp(with: key(.keyUp)) }
                    else { control.mouseUp(with: pointer(.leftMouseUp)) }
                    try capture("up", selected: false, pressed: false)
                }
                window.close()
            }
        } }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
        let failures = rows.filter { row in
            let expected = row["expected"] as! [String: Bool]
            return expected.contains { row[$0.key] as? Bool != $0.value }
        }
        print("\(rows.count) native states, \(failures.count) states disagree with WinUI-derived expectations")
    }
}
