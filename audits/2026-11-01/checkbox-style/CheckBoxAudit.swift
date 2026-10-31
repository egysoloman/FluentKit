import AppKit
import FluentKit

func rgba(_ color: CGColor?) -> [CGFloat] {
    guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return [0, 0, 0, 0] }
    return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
}

// Independent expected CheckBox resource aliases, transcribed from the pinned XAML.
// Accent palette generation is shared with Theme; unchecked colors are literal source ARGB.
@MainActor func expectedColors(dark: Bool, high: Bool, phase: String, control: Int, theme: FluentTheme) -> [String: Any] {
    let index = ["normal": 0, "hover": 1, "pressed": 2, "disabled": 3][phase] ?? 0
    let selected = control == 1 || control == 3 || control == 4, mixed = control == 4
    let state: FluentControlState = [.normal, .pointerOver, .pressed, .disabled][index]
    var fill: NSColor, stroke: NSColor, glyph: NSColor
    if high {
        let fills: [NSColor] = mixed
            ? [.selectedContentBackgroundColor, .selectedMenuItemTextColor, .selectedContentBackgroundColor, .disabledControlTextColor]
            : (selected ? [.selectedContentBackgroundColor, .controlTextColor, .controlBackgroundColor, .disabledControlTextColor]
                : [.controlBackgroundColor, .selectedMenuItemTextColor, .selectedContentBackgroundColor, theme.windowBackground])
        let strokes: [NSColor] = mixed
            ? [.selectedContentBackgroundColor, .selectedContentBackgroundColor, .selectedContentBackgroundColor, .disabledControlTextColor]
            : (selected ? fills : [.controlTextColor, .selectedContentBackgroundColor, .selectedContentBackgroundColor, .disabledControlTextColor])
        let glyphs: [NSColor] = mixed
            ? [.selectedMenuItemTextColor, .selectedContentBackgroundColor, .selectedMenuItemTextColor, theme.windowBackground]
            : (selected ? [.selectedMenuItemTextColor, .controlBackgroundColor, .controlTextColor, theme.windowBackground]
                : [.controlBackgroundColor, .selectedContentBackgroundColor, .selectedMenuItemTextColor, .disabledControlTextColor])
        fill = fills[index]; stroke = strokes[index]; glyph = glyphs[index]
    } else {
        let fills: [NSColor] = dark
            ? [NSColor(calibratedWhite: 0, alpha: 25/255), NSColor(calibratedWhite: 1, alpha: 11/255), NSColor(calibratedWhite: 1, alpha: 18/255), .clear]
            : [NSColor(calibratedWhite: 0, alpha: 6/255), NSColor(calibratedWhite: 0, alpha: 15/255), NSColor(calibratedWhite: 0, alpha: 24/255), .clear]
        let strong = NSColor(calibratedWhite: dark ? 1 : 0, alpha: dark ? 139/255 : 114/255)
        let disabled = NSColor(calibratedWhite: dark ? 1 : 0, alpha: dark ? 40/255 : 55/255)
        fill = selected ? theme.accentFill(for: state) : fills[index]
        stroke = index == 3 ? disabled : (selected ? theme.accentFill(for: state) : (index == 2 ? disabled : strong))
        glyph = index == 3 ? theme.textOnAccentDisabled : (selected && index == 2 ? theme.textOnAccentSecondary : theme.textOnAccent)
    }
    var result: [String: Any] = ["radius": 4, "strokeWidth": 1, "boxWidth": 20]
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        result["fill"] = rgba(fill.cgColor); result["stroke"] = rgba(stroke.cgColor); result["glyph"] = rgba(glyph.cgColor)
        result["rootBackground"] = rgba((high ? theme.windowBackground : NSColor.clear).cgColor)
    }
    return result
}

@main struct CheckBoxAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let interactive = CommandLine.arguments.count == 1
        NSApp.setActivationPolicy(interactive ? .regular : .accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: interactive ? Bundle.main.object(forInfoDictionaryKey: "AuditOutputPath") as! String : CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if interactive { try showInteractive(output); NSApp.run(); return }
        var records: [[String: Any]] = []
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        for dark in [false, true] { for hc in [false, true] {
            let theme = FluentTheme.custom(contrast: hc ? .high : .standard, colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = window.contentView!; root.wantsLayer = true; root.layer?.backgroundColor = theme.windowBackground.cgColor
            var boxes: [FluentCheckBox] = [], outlines: [NSOutlineView] = [], cells: [NSView] = []
            for checked in [false, true] {
                let box = FluentCheckBox(title: checked ? "Checked" : "Unchecked", isChecked: checked)
                box.theme = theme; box.reduceMotion = true
                box.frame = NSRect(x: checked ? 220 : 10, y: 75, width: 190, height: 32)
                root.addSubview(box); boxes.append(box)
            }
            for (i, selection) in [Set<String>(), Set(["root", "a", "b"]), Set(["a"])].enumerated() {
                let binding = FluentState(wrappedValue: selection)
                let tree = FluentTreeView(nodes: [FluentTreeViewNode(id: "root", children: [
                    FluentTreeViewNode(id: "a") { FluentText("A") }, FluentTreeViewNode(id: "b") { FluentText("B") }
                ]) { FluentText(["Tree unchecked", "Tree checked", "Tree mixed"][i]) }], selection: .multiple(binding.projectedValue))
                let host = FluentViewHost(tree, context: FluentRenderContext(theme: theme, reduceMotion: true))
                host.translatesAutoresizingMaskIntoConstraints = true; host.wantsLayer = true
                host.frame = NSRect(x: 420 + i * 205, y: 20, width: 205, height: 90); root.addSubview(host)
                host.layoutSubtreeIfNeeded()
                let outline = all(host).compactMap { $0 as? NSOutlineView }.first!
                outlines.append(outline); cells.append(outline.view(atColumn: 0, row: 0, makeIfNecessary: true)!)
            }
            window.makeKeyAndOrderFront(nil); root.layoutSubtreeIfNeeded()
            func event(_ view: NSView, _ type: NSEvent.EventType, _ inside: Bool) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: inside ? 30 : view.bounds.width + 12, y: 16), to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            }
            for phase in ["normal", "hover", "pressed", "outside", "disabled"] {
                for box in boxes {
                    switch phase {
                    case "hover": box.mouseEntered(with: event(box, .mouseMoved, true))
                    case "pressed": box.mouseDown(with: event(box, .leftMouseDown, true))
                    case "outside": box.mouseDragged(with: event(box, .leftMouseDragged, false))
                    case "disabled": box.mouseUp(with: event(box, .leftMouseUp, false)); box.isEnabled = false
                    default: break
                    }
                }
                for (i, cell) in cells.enumerated() {
                    switch phase {
                    case "hover": cell.mouseMoved(with: event(cell, .mouseMoved, true))
                    case "pressed": outlines[i].mouseDown(with: event(cell, .leftMouseDown, true))
                    case "outside": outlines[i].mouseDragged(with: event(cell, .leftMouseDragged, false))
                    case "disabled": outlines[i].mouseUp(with: event(cell, .leftMouseUp, false)) // Tree has no disabled API: capture normal again.
                    default: break
                    }
                }
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                let variant = "\(dark ? "dark" : "light")-\(hc ? "high" : "standard")-\(phase)"
                for (i, view) in (boxes.map { $0 as NSView } + cells).enumerated() {
                    let layers = view.layer!.sublayers!
                    let boxLayer = layers.first { abs($0.bounds.width - 20) < 0.1 && $0.borderWidth > 0 }!
                    let glyph = i < 2 ? layers.compactMap { $0 as? CAShapeLayer }.last! : boxLayer.sublayers!.compactMap { $0 as? CAShapeLayer }.first!
                    let actualPhase = i >= 2 && phase == "disabled" ? "normal-after-cancel" : phase
                    let background = i < 2 ? view.layer?.backgroundColor
                        : layers.first { $0.name == "FluentKit.TreeView.CheckBoxBackground" }?.backgroundColor
                    records.append(["variant": variant, "control": i, "phase": actualPhase,
                        "fill": rgba(boxLayer.backgroundColor), "stroke": rgba(boxLayer.borderColor), "glyph": rgba(glyph.strokeColor),
                        "radius": boxLayer.cornerRadius, "strokeWidth": boxLayer.borderWidth, "boxWidth": boxLayer.bounds.width,
                        "rootBackground": rgba(background), "frameInRoot": NSStringFromRect(view.convert(view.bounds, to: root)),
                        "expected": expectedColors(dark: dark, high: hc, phase: actualPhase, control: i, theme: theme)])
                }
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2080, pixelsHigh: 260, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                root.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(variant + ".png"))
            }
            window.close()
        } }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
        print("Captured \(records.count) native control states; disabled TreeView is explicitly excluded.")
    }

    @MainActor static func showInteractive(_ output: URL) throws {
        let window = CheckBoxReviewWindow(contentRect: NSRect(x: 160, y: 180, width: 520, height: 230),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "CheckBox pointer review"; window.output = output
        window.appearance = NSAppearance(named: .darkAqua)
        let root = window.contentView!; root.wantsLayer = true
        root.layer?.backgroundColor = FluentTheme.custom(contrast: .standard, colorScheme: .dark).windowBackground.cgColor
        let box = FluentCheckBox(title: "Drag out, release; then reenter and release")
        box.theme = FluentTheme.custom(contrast: .standard, colorScheme: .dark); box.reduceMotion = true
        box.fluentStyle = window.recorder; box.frame = NSRect(x: 32, y: 140, width: 440, height: 32)
        root.addSubview(box); window.box = box
        let target = NSTextField(labelWithString: "Outside release area")
        target.textColor = .white; target.frame = NSRect(x: 32, y: 40, width: 220, height: 25); root.addSubview(target)
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

private final class AuditCheckBoxStyle: FluentCheckBoxStyle {
    var last: FluentCheckBoxStyleConfiguration?
    func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        last = configuration; return FluentAutomaticCheckBoxStyle().appearance(for: configuration)
    }
}

private final class CheckBoxReviewWindow: NSWindow {
    var output: URL!; var box: FluentCheckBox!
    let recorder = AuditCheckBoxStyle()
    var records: [[String: Any]] = []
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        guard [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type), let state = recorder.last else { return }
        records.append(["event": event.type.rawValue, "over": state.isPointerOver, "pressed": state.isPressed, "checked": box.isChecked,
            "pointInBox": NSStringFromPoint(box.convert(event.locationInWindow, from: nil))])
        do { try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("pointer-events.json")) }
        catch { print("Failed to persist interactive events: \(error)") }
    }
}
