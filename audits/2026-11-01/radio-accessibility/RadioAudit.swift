import AppKit
import FluentKit

func rgba(_ color: CGColor?) -> [CGFloat] {
    guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return [0, 0, 0, 0] }
    return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
}

@main struct RadioAudit {
    @MainActor static var review: RadioReview?
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let interactive = CommandLine.arguments.count == 1
        NSApp.setActivationPolicy(interactive ? .regular : .accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: interactive ? Bundle.main.object(forInfoDictionaryKey: "AuditOutputPath") as! String : CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if interactive { review = try RadioReview(output: output); NSApp.run(); return }
        var records: [[String: Any]] = []
        for dark in [false, true] { for high in [false, true] { for rtl in [false, true] { for selected in [false, true] {
            let theme = FluentTheme.custom(contrast: high ? .high : .standard, colorScheme: dark ? .dark : .light)
            let desired = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let opposite = NSAppearance(named: dark ? .aqua : .darkAqua)!
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 250, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = desired
            let root = window.contentView!; root.wantsLayer = true; root.layer?.backgroundColor = theme.windowBackground.cgColor
                let radio = FluentRadioButton(title: selected ? "Selected choice" : "Unselected choice", isSelected: selected)
                radio.theme = theme; radio.reduceMotion = true; radio.fluentLayoutDirection = rtl ? .rightToLeft : .leftToRight
                radio.frame = NSRect(x: 10, y: 40, width: 230, height: 32)
                root.addSubview(radio)
            window.makeKeyAndOrderFront(nil)
            for phase in ["normal", "hover", "pressed", "outside", "reentered", "cancelled", "disabled"] {
                do {
                    func event(_ type: NSEvent.EventType, inside: Bool = true) -> NSEvent {
                        NSEvent.mouseEvent(with: type, location: radio.convert(NSPoint(x: inside ? 20 : 260, y: 16), to: nil),
                            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                            eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
                    }
                    opposite.performAsCurrentDrawingAppearance {
                        switch phase {
                        case "normal": radio.theme = theme; radio.layoutSubtreeIfNeeded()
                        case "hover": radio.mouseEntered(with: event(.mouseMoved))
                        case "pressed": radio.mouseDown(with: event(.leftMouseDown))
                        case "outside": radio.mouseDragged(with: event(.leftMouseDragged, inside: false))
                        case "reentered": radio.mouseDragged(with: event(.leftMouseDragged))
                        case "cancelled": radio.mouseUp(with: event(.leftMouseUp, inside: false))
                        case "disabled": radio.isEnabled = false
                        default: break
                        }
                    }
                }
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                let variant = "\(dark ? "dark" : "light")-\(high ? "high" : "standard")-\(rtl ? "rtl" : "ltr")-\(phase)"
                do {
                    func layer(_ suffix: String) -> CALayer { radio.layer!.sublayers!.first { $0.name == "FluentKit.RadioButton." + suffix }! }
                    let outer = layer("Outer"), dot = layer("Dot"), feedback = layer("PressedDot")
                    records.append(["variant": variant, "selected": radio.isSelected, "phase": phase,
                        "fill": rgba(outer.backgroundColor), "stroke": rgba(outer.borderColor), "dot": rgba(dot.backgroundColor),
                        "feedback": rgba(feedback.backgroundColor), "diameter": outer.bounds.width, "dotDiameter": dot.bounds.width,
                        "dotOpacity": dot.opacity, "feedbackOpacity": feedback.opacity, "strokeWidth": outer.borderWidth,
                        "expected": expected(theme: theme, dark: dark, high: high, selected: radio.isSelected, phase: phase)])
                }
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 500, pixelsHigh: 200, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                root.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(variant + "-\(selected ? "selected" : "unselected").png"))
            }
            window.close()
        } } } }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
        print("Captured \(records.count) native radio states with an intentionally opposite drawing appearance during updates.")
    }

    @MainActor static func expected(theme: FluentTheme, dark: Bool, high: Bool, selected: Bool, phase: String) -> [String: Any] {
        let i = ["hover": 1, "pressed": 2, "reentered": 2, "disabled": 3][phase] ?? 0
        let state: FluentControlState = [.normal, .pointerOver, .pressed, .disabled][i]
        var fill: NSColor, stroke: NSColor, dot: NSColor, feedback: NSColor
        if high {
            let fills: [NSColor] = selected ? [.selectedMenuItemTextColor, .controlBackgroundColor, .controlBackgroundColor, theme.windowBackground]
                : [.controlBackgroundColor, .selectedMenuItemTextColor, .selectedMenuItemTextColor, theme.windowBackground]
            let strokes: [NSColor] = selected ? [.selectedContentBackgroundColor, .controlTextColor, .controlBackgroundColor, .disabledControlTextColor]
                : [.controlTextColor, .selectedContentBackgroundColor, .selectedMenuItemTextColor, .disabledControlTextColor]
            fill = fills[i]; stroke = strokes[i]
            dot = [NSColor.selectedContentBackgroundColor, .controlTextColor, .controlTextColor, .disabledControlTextColor][i]
            feedback = .selectedContentBackgroundColor
        } else {
            let fills: [NSColor] = dark
                ? [NSColor(calibratedWhite: 0, alpha: 25/255), NSColor(calibratedWhite: 1, alpha: 11/255), NSColor(calibratedWhite: 1, alpha: 18/255), .clear]
                : [NSColor(calibratedWhite: 0, alpha: 6/255), NSColor(calibratedWhite: 0, alpha: 15/255), NSColor(calibratedWhite: 0, alpha: 24/255), .clear]
            fill = selected ? theme.accentFill(for: state) : fills[i]
            let normalAlpha: CGFloat = dark ? 139.0/255 : 114.0/255, disabledAlpha: CGFloat = dark ? 40.0/255 : 55.0/255
            stroke = selected ? theme.accentFill(for: state) : NSColor(calibratedWhite: dark ? 1 : 0, alpha: i >= 2 ? disabledAlpha : normalAlpha)
            dot = theme.textOnAccent; feedback = theme.textOnAccent
        }
        var result: [String: Any] = ["diameter": 20, "dotDiameter": [12, 14, 10, 14][i], "dotOpacity": selected ? 1 : 0,
                                     "feedbackOpacity": i == 2 && !selected ? 1 : 0, "strokeWidth": 1]
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            result["fill"] = rgba(fill.cgColor); result["stroke"] = rgba(stroke.cgColor)
            result["dot"] = rgba(dot.cgColor); result["feedback"] = rgba(feedback.cgColor)
        }
        return result
    }
}

@MainActor final class RadioReview: NSObject {
    let window: NSWindow
    let output: URL
    let selection = FluentState<String?>(wrappedValue: "Auto")
    let a1 = FluentRadioButton(title: "Native A1", isSelected: true)
    let a2 = FluentRadioButton(title: "Native A2")
    let b1 = FluentRadioButton(title: "Separate B1", isSelected: true)
    let status = NSTextField(labelWithString: "")
    var records: [[String: Any]] = []
    init(output: URL) throws {
        self.output = output
        window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 600, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false; window.title = "RadioButton review"
        let root = window.contentView!
        for (x, controls) in [(CGFloat(20), [a1, a2]), (CGFloat(320), [b1])] {
            let parent = NSView(frame: NSRect(x: x, y: 285, width: 250, height: 110)); root.addSubview(parent)
            for (i, radio) in controls.enumerated() {
                radio.frame = NSRect(x: 10, y: 65 - i * 40, width: 225, height: 32); parent.addSubview(radio)
                radio.onValueChanged = { [weak self] _ in self?.capture("native selection") }
            }
        }
        let group = FluentRadioButtons(["Auto", "Manual", "Unavailable"], selection: selection.projectedValue,
            header: "Declarative mode", isEnabled: { $0 != "Unavailable" },
            onSelectionChanged: { [weak self] _, _ in self?.capture("group selection") })
        let native = group._makeView(in: FluentRenderContext())
        native.translatesAutoresizingMaskIntoConstraints = true
        native.frame = NSRect(x: 30, y: 110, width: 300, height: 160); root.addSubview(native)
        status.frame = NSRect(x: 30, y: 22, width: 550, height: 26); root.addSubview(status)
        for (x, title, action) in [(CGFloat(30), "Select native A2", #selector(selectA2)), (CGFloat(200), "Clear model", #selector(clearModel))] {
            let button = NSButton(title: title, target: self, action: action)
            button.frame = NSRect(x: x, y: 64, width: 160, height: 30); root.addSubview(button)
        }
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        menu.addItem(item); appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); root.layoutSubtreeIfNeeded(); NSApp.activate(ignoringOtherApps: true)
        capture("initial")
    }
    @objc func selectA2() { _ = a2.accessibilityPerformPress(); capture("select A2 command") }
    @objc func clearModel() { selection.wrappedValue = nil; capture("clear model command") }
    func capture(_ reason: String) {
        status.stringValue = "A1=\(a1.isSelected) A2=\(a2.isSelected) B1=\(b1.isSelected); mode=\(selection.wrappedValue ?? "nil")"
        records.append(["reason": reason, "a1": a1.isSelected, "a2": a2.isSelected, "b1": b1.isSelected, "mode": selection.wrappedValue ?? "nil"])
        do { try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("selection-events.json")) }
        catch { print("Could not write events: \(error)") }
    }
}
