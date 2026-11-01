import AppKit
import ScreenCaptureKit
import FluentKit

final class ColorBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: .systemBlue, ending: .systemOrange)?.draw(in: bounds, angle: 0)
        NSColor.white.withAlphaComponent(0.3).setFill()
        for x in stride(from: CGFloat(0), to: bounds.width, by: 70) {
            NSRect(x: x, y: 0, width: 16, height: bounds.height).fill()
        }
    }
}

@MainActor final class MaterialCompositorAudit: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await audit() } catch { print("FAILED: \(error)") }
            windows.forEach { $0.orderOut(nil) }
            NSApp.terminate(nil)
        }
    }

    func audit() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backdrop = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 440),
            styleMask: [.titled], backing: .buffered, defer: false)
        backdrop.title = "Own-process color backdrop"
        backdrop.contentView = ColorBackdrop(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
        backdrop.orderFront(nil)
        let window = NSWindow(contentRect: NSRect(x: 250, y: 260, width: 540, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "FluentKit Material Compositor Audit"
        windows = [backdrop, window]
        windows.forEach { $0.isReleasedWhenClosed = false }
        let material = FluentMaterialView()
        material.frame = NSRect(x: 0, y: 0, width: 540, height: 300)
        material.layer?.cornerRadius = 20
        material.layer?.masksToBounds = true
        window.contentView = material
        let label = NSTextField(labelWithString: "Material")
        label.frame = NSRect(x: 20, y: 235, width: 450, height: 28)
        label.font = .systemFont(ofSize: 16)
        material.addSubview(label)
        let field = NSTextField(string: "Retained editor")
        field.frame = NSRect(x: 20, y: 170, width: 330, height: 28)
        material.addSubview(field)
        let foreground = NSView(frame: NSRect(x: 450, y: 170, width: 30, height: 30))
        foreground.wantsLayer = true
        foreground.layer?.backgroundColor = NSColor.red.cgColor
        material.addSubview(foreground)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 250_000_000)
        let available = try await SCShareableContent.currentProcess
        let target = available.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
        let display = available.displays.first { $0.frame.intersects(target.frame) }!
        let filter = SCContentFilter(display: display, including: [target.owningApplication!], exceptingWindows: [])
        let capture = SCStreamConfiguration()
        capture.sourceRect = CGRect(x: target.frame.minX - display.frame.minX,
            y: target.frame.minY - display.frame.minY, width: target.frame.width, height: target.frame.height)
        capture.width = Int(target.frame.width * CGFloat(filter.pointPixelScale))
        capture.height = Int(target.frame.height * CGFloat(filter.pointPixelScale))
        capture.showsCursor = false
        capture.includeChildWindows = true
        var rows: [[String: Any]] = []
        let cases: [(FluentMaterial, FluentMaterialRole, Bool, FluentThemeContrast)] = [
            (.mica, .window, true, .standard), (.acrylic, .transient, true, .standard),
            (.nativeAcrylic, .container, true, .standard), (.nativeAcrylic, .transient, true, .standard),
            (.nativeMica, .window, true, .standard), (.liquidGlass, .transient, true, .standard),
            (.liquidGlass, .transient, false, .standard), (.nativeAcrylic, .container, true, .high)
        ]
        for scheme in [FluentThemeColorScheme.light, .dark] {
            for (style, role, enabled, contrast) in cases {
                let name = "\(scheme)-\(style)-\(role)-\(enabled)-\(contrast)"
                let theme = FluentTheme.custom(contrast: contrast, colorScheme: scheme, materialEffectsEnabled: enabled)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                material.configure(theme: theme, role: role,
                    configuration: .init(material: style, tintColor: NSColor.systemTeal.withAlphaComponent(0.12)))
                label.stringValue = name
                label.textColor = theme.textPrimary
                material.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 200_000_000)
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: capture)
                let bitmap = NSBitmapImageRep(cgImage: image)
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                rows.append(["name": name, "backend": material.resolvedBackend.rawValue,
                    "blend": material.preferredBlendingMode.rawValue, "radius": material.layer!.cornerRadius,
                    "fieldRetained": field.superview === material, "fieldText": field.stringValue,
                    "windowActive": window.isKeyWindow, "scale": filter.pointPixelScale,
                    "imageSize": [image.width, image.height]])
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("states.json"))
        print("Captured \(rows.count) compositor states")
    }
}

@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = MaterialCompositorAudit()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
