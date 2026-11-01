import AppKit
import FluentKit

func rgba(_ color: CGColor?) -> [Double] {
    guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return [] }
    return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Double(($0 * 10000).rounded() / 10000) }
}
func rect(_ r: CGRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
func border(_ layer: CALayer?) -> [String: Any] {
    guard let layer else { return [:] }
    if let shape = layer as? CAShapeLayer, let path = shape.path {
        var firstLine: CGPoint?
        path.applyWithBlock { e in if firstLine == nil && e.pointee.type == .addLineToPoint { firstLine = e.pointee.points[0] } }
        let b = path.boundingBoxOfPath
        return ["bounds": rect(b.insetBy(dx: -shape.lineWidth / 2, dy: -shape.lineWidth / 2)),
            "width": shape.lineWidth, "radius": b.maxY - (firstLine?.y ?? b.maxY), "color": rgba(shape.strokeColor)]
    }
    return ["bounds": rect(layer.frame), "width": layer.borderWidth,
        "radius": layer.cornerRadius - layer.borderWidth / 2, "color": rgba(layer.borderColor)]
}

@main struct FocusAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        for radio in [false, true] { for dark in [false, true] { for high in [false, true] { for wrapped in [false, true] {
            let theme = FluentTheme.custom(contrast: high ? .high : .standard, colorScheme: dark ? .dark : .light)
            var context = FluentRenderContext(); context.theme = theme; context.reduceMotion = false
            let state = FluentState(wrappedValue: false)
            let host: NSView, control: NSControl
            if wrapped {
                host = radio ? FluentRadioButtonView("Focus 焦点", isSelected: state.projectedValue)._makeView(in: context)
                    : FluentCheckBoxView("Focus 焦点", isChecked: state.projectedValue)._makeView(in: context)
                control = radio ? (host as! FluentBoundRadioButton).radioButton : (host as! FluentBoundCheckBox).checkBox
            } else if radio {
                let c = FluentRadioButton(title: "Focus 焦点"); c.theme = theme; c.reduceMotion = false; host = c; control = c
            } else {
                let c = FluentCheckBox(title: "Focus 焦点"); c.theme = theme; c.reduceMotion = false; host = c; control = c
            }
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 280, height: 90),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = window.contentView!; root.wantsLayer = true; root.layer!.backgroundColor = theme.windowBackground.cgColor
            host.frame = NSRect(x: 20, y: 25, width: 180, height: 32); root.addSubview(host)
            window.makeKeyAndOrderFront(nil); window.makeFirstResponder(control); root.layoutSubtreeIfNeeded()
            let name = "\(radio ? "radio" : "check")-\(dark ? "dark" : "light")-\(high ? "high" : "standard")-\(wrapped ? "bound" : "native")"
            let prefix = radio ? "FluentKit.RadioButton" : "FluentKit.CheckBox"
            var colors: [[Double]] = []
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                let cs: [NSColor] = high ? [.controlTextColor, .controlBackgroundColor] : [
                    dark ? .white : NSColor(calibratedWhite: 0, alpha: 228.0 / 255),
                    NSColor(calibratedWhite: dark ? 0 : 1, alpha: 179.0 / 255)]
                colors = cs.map { rgba($0.cgColor) }
            }
            func key(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
            }
            func capture(_ phase: String, visible: Bool, image: Bool = false) throws {
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                let outer = control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing" }
                let inner = control.layer?.sublayers?.first { $0.name == prefix + ".FocusRing.Inner" }
                let w = control.bounds.width, h = control.bounds.height
                let expected: [String: Any] = [
                    "outer": ["bounds": [-7, -3, w + 14, h + 6], "width": 2, "radius": 9, "color": colors[0]],
                    "inner": ["bounds": [-5, -1, w + 10, h + 2], "width": 1, "radius": 7, "color": colors[1]],
                    "outerVisible": visible, "innerVisible": visible, "focusAnimations": 0, "clips": false]
                records.append(["id": name + "-" + phase, "outer": border(outer), "inner": border(inner),
                    "outerVisible": (outer?.opacity ?? 0) > 0, "innerVisible": (inner?.opacity ?? 0) > 0,
                    "focusAnimations": (outer?.animationKeys()?.count ?? 0) + (inner?.animationKeys()?.count ?? 0),
                    "clips": control.layer?.masksToBounds ?? true, "expected": expected])
                if image {
                    for scale in [1, 2] {
                        let b = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 280 * scale, pixelsHigh: 90 * scale,
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                        let cg = NSGraphicsContext(bitmapImageRep: b)!.cgContext; cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale)); root.layer!.render(in: cg)
                        try b.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + "-\(scale)x.png"))
                    }
                }
            }
            try capture("initial", visible: false)
            NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance { control.keyDown(with: key(.keyDown)) }
            try capture("down", visible: true, image: true)
            control.keyUp(with: key(.keyUp)); try capture("up", visible: true)
            host.setFrameSize(NSSize(width: 224, height: 32)); try capture("resized", visible: true)
            control.isEnabled = false; try capture("disabled", visible: false)
            window.makeFirstResponder(nil); try capture("blur", visible: false)
            window.close()
        } } } }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("results.json"))
        print("\(records.count) focus states captured")
        // Record a suspected reentrancy issue without treating a new policy as a WinUI oracle.
        let model = FluentState<String?>(wrappedValue: "A")
        let token = model.observe { if $0 == "B" { model.wrappedValue = "C" } }
        var events: [String] = []
        let group = FluentRadioButtons(["A", "B", "C"], selection: model.projectedValue,
            onSelectionChanged: { events.append("\($0 ?? "nil")->\($1 ?? "nil")") })._makeView(in: FluentRenderContext())
        let radios = group.subviews.compactMap { $0 as? FluentRadioButton }
        _ = radios[1].accessibilityPerformPress()
        let immediate: [String: Any] = ["model": model.wrappedValue ?? "nil", "selected": radios.map(\.isSelected), "events": events]
        model.observableValue.send()
        let republished: [String: Any] = ["model": model.wrappedValue ?? "nil", "selected": radios.map(\.isSelected), "events": events]
        model.observableValue.removeObserver(token)
        try JSONSerialization.data(withJSONObject: ["immediate": immediate, "republished": republished], options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("reentrancy-observation.json"))
    }
}
