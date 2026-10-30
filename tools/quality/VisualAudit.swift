import AppKit
import FluentKit

private final class Canvas: NSView { override var isFlipped: Bool { true } }
@main struct VisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light)
            let canvas = Canvas(frame: NSRect(x: 0, y: 0, width: 1040, height: 650))
            canvas.wantsLayer = true
            canvas.layer?.backgroundColor = theme.windowBackground.cgColor
            canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: canvas.bounds, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 14) {
                let label = NSTextField(labelWithString: text)
                label.font = .systemFont(ofSize: size)
                label.textColor = theme.textPrimary
                label.frame = NSRect(x: x, y: y, width: 980, height: max(24, size * 1.5))
                canvas.addSubview(label)
            }
            func event(_ type: NSEvent.EventType, _ view: NSView) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: 8, y: 8), to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            label("FluentKit · Input and command states", x: 24, y: 18, size: 28)
            label("Controlled macOS render · not a Windows parity certificate", x: 24, y: 56, size: 12)
            let states = ["Normal", "Hover", "Pressed", "Focus*", "Disabled"]
            var focusedField: FluentTextField?
            for (index, state) in states.enumerated() {
                let x = 150 + CGFloat(index) * 174
                label(state, x: x, y: 90)
                let button = FluentButton(title: "Continue")
                button.theme = theme
                button.reduceMotion = true
                button.frame = NSRect(x: x, y: 125, width: 150, height: 32)
                canvas.addSubview(button)
                button.controlState = [.normal, .pointerOver, .pressed, .focused, .disabled][index]
                if index == 4 { button.isEnabled = false }
                let field = FluentTextField(placeholder: "Search")
                field.theme = theme
                field.frame = NSRect(x: x, y: 200, width: 150, height: 32)
                field.stringValue = "Fluent 文本"
                canvas.addSubview(field)
                if index == 1 { field.mouseEntered(with: event(.mouseMoved, field)) }
                if index == 3 { focusedField = field }
                if index == 4 { field.isEnabled = false }
                let appBar = FluentAppBarButton("查看", systemImageName: "list.bullet", flyoutItems: [FluentMenuItem("Details", action: {})])
                appBar.defaultLabelPosition = .right
                appBar.theme = theme
                appBar.reduceMotion = true
                appBar.frame = NSRect(origin: NSPoint(x: x, y: 275), size: appBar.intrinsicContentSize)
                canvas.addSubview(appBar)
                if index == 1 { appBar.mouseEntered(with: event(.mouseMoved, appBar)) }
                if index == 2 { appBar.mouseDown(with: event(.leftMouseDown, appBar)) }
                if index == 4 { appBar.isEnabled = false }
                let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [FluentCommandBarItem("Properties", isEnabled: false, action: {})])
                bar.overflowButtonVisibility = .visible
                bar.theme = theme
                bar.reduceMotion = true
                bar.frame = NSRect(x: x, y: 350, width: 150, height: 48)
                canvas.addSubview(bar)
                bar.layoutSubtreeIfNeeded()
                if let more = bar.subviews.compactMap({ $0 as? NSControl }).first {
                    if index == 1 { more.mouseEntered(with: event(.mouseMoved, more)) }
                    if index == 2 { more.mouseDown(with: event(.leftMouseDown, more)) }
                    if index == 4 { more.isEnabled = false }
                }
            }
            for (name, y) in [("Button", 130.0), ("TextBox", 205), ("AppBar", 290), ("More", 365)] { label(name, x: 24, y: y) }
            label("*Focus: active TextBox editor; AppBar/More show normal. TextBox has no separate Pressed chrome.", x: 24, y: 415, size: 12)
            for (index, material) in [FluentMaterial.mica, .acrylic].enumerated() {
                let surface = FluentMaterialView(material: material)
                surface.fluentTheme = theme
                surface.frame = NSRect(x: 24 + index * 240, y: 465, width: 210, height: 92)
                canvas.addSubview(surface)
                label(index == 0 ? "Mica fixed base" : "Acrylic fixed base", x: surface.frame.minX + 12, y: 495)
            }
            let wide = NSImage(size: NSSize(width: 36, height: 12), flipped: false) { rect in NSColor.systemOrange.setFill(); rect.fill(); return true }
            let sources: [FluentIconSource] = [.systemSymbol("ellipsis"), .glyph("★", font: .systemFont(ofSize: 24)),
                .image(wide), .path(CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 30, height: 10), transform: nil))]
            for (index, source) in sources.enumerated() {
                let view = NSImageView(frame: NSRect(x: 600 + index * 80, y: 475, width: 48, height: 48))
                view.imageScaling = .scaleProportionallyUpOrDown
                view.image = source.image(pointSize: 24, color: theme.textPrimary)
                canvas.addSubview(view)
            }
            label("Symbol · Glyph · Image · Path", x: 590, y: 535, size: 12)
            label("Title 28 / Subtitle 20 / Body 14 / Caption 12", x: 24, y: 590, size: 20)
            focusedField?.selectText(nil)
            (focusedField?.currentEditor() as? NSTextView)?.insertionPointColor = .clear
            canvas.layoutSubtreeIfNeeded()
            canvas.displayIfNeeded()
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try data.write(to: output.appendingPathComponent(dark ? "audit-states-dark.png" : "audit-states-light.png"))
            window.close()
        }
        let environment: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
            "scale": NSScreen.main?.backingScaleFactor ?? 1, "locale": "fixed fixture strings", "material": "fixed base colors",
            "systemFont": NSFont.systemFont(ofSize: 14).fontName, "purpose": "regression baseline, not Windows parity"]
        try JSONSerialization.data(withJSONObject: environment, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("visual-environment.json"))
    }
}
