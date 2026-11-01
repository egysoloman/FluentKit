import AppKit
import FluentKit

@main struct SearchMenuAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var records: [[String: Any]] = []
        for style in ["default", "nativeAcrylic", "liquidGlass", "disabled"] {
            let field = FluentSearchTextField(placeholder: "查找设置")
            var theme = FluentTheme.custom(colorScheme: .dark,
                typography: FluentTypography(fontProvider: FluentFontProvider { _, size, weight in
                    NSFont(name: "MicrosoftYaHei", size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
                }))
            if style == "nativeAcrylic" { theme = theme.with(materialConfiguration: .init(material: .nativeAcrylic), for: .transient) }
            if style == "liquidGlass" { theme = theme.with(materialConfiguration: .init(material: .liquidGlass), for: .transient) }
            if style == "disabled" { theme = theme.with(materialEffectsEnabled: false) }
            field.theme = theme
            field.stringValue = "事实上"
            field.frame = NSRect(x: 30, y: 70, width: 310, height: 32)
            let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 380, height: 150),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView!.wantsLayer = true
            window.contentView!.addSubview(field)
            window.makeKeyAndOrderFront(nil)
            field.selectText(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            let editor = field.currentEditor()
            let click = NSEvent.mouseEvent(with: .rightMouseDown,
                location: field.convert(NSPoint(x: 55, y: 16), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0)!
            field.rightMouseDown(with: click)
            let panel = window.childWindows!.first!, layer = panel.contentView!.layer!
            let surface = all(panel.contentView!).compactMap { $0 as? FluentMaterialView }.first!
            let start = CACurrentMediaTime()
            var frames: [[String: Any]] = []
            for _ in 0..<32 {
                CATransaction.flush()
                let animation = layer.animation(forKey: "fluent.popup.textCommandBar.open.opacity")
                frames.append(["time": CACurrentMediaTime() - start,
                    "modelOpacity": layer.opacity, "presentationOpacity": layer.presentation()?.opacity ?? -1,
                    "animationDuration": animation?.duration ?? 0,
                    "visible": panel.isVisible])
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            records.append(["style": style, "backend": String(describing: surface.resolvedBackend),
                "materialEnabled": surface.isMaterialEnabled, "panelShadow": panel.hasShadow,
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "sameEditor": field.currentEditor() === editor, "frames": frames])
            // Toggle the same context flyout closed without executing a clipboard command.
            field.rightMouseDown(with: click)
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
