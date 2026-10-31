import AppKit
import FluentKit

@main struct WrapperContentAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 120, width: 640, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var records: [[String: Any]] = []
        for (name, wrap) in wrapperCases() {
            var invoked = ""
            func content(_ phase: String) -> some FluentView {
                FluentVStack(alignment: .leading) {
                    FluentText(name)
                    wrap(FluentAnyView(FluentButtonView(phase == "before" ? "Before" : "After \(phase)",
                        role: phase == "before" ? .standard : .primary, action: { invoked = phase })))
                        .frame(width: 280)
                }.padding(20)
            }
            let host = FluentViewHost(content("before"), context: .init(theme: .custom(colorScheme: .light), reduceMotion: true))
            host.wantsLayer = true; window.contentView = host; window.makeKeyAndOrderFront(nil)
            let button = all(host).compactMap { $0 as? FluentButton }.first!
            for phase in ["before", "dark", "light"] {
                let theme = FluentTheme.custom(colorScheme: phase == "dark" ? .dark : .light)
                window.appearance = NSAppearance(named: phase == "dark" ? .darkAqua : .aqua)
                window.backgroundColor = theme.windowBackground
                if phase != "before" { host.update(content(phase), context: .init(theme: theme, reduceMotion: true)) }
                host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                button.performClick(nil)
                records.append(["wrapper": name, "phase": phase, "title": button.title,
                    "expectedTitle": phase == "before" ? "Before" : "After \(phase)", "role": String(describing: button.role),
                    "expectedRole": phase == "before" ? "standard" : "primary", "action": invoked,
                    "sameButton": all(host).contains { $0 === button }, "dark": button.theme.isDark,
                    "buttonBounds": NSStringFromRect(button.bounds)])
                host.displayIfNeeded(); CATransaction.flush()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.setFillColor(theme.windowBackground.cgColor); cg.fill(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
                cg.scaleBy(x: 2, y: 2)
                if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
                host.layer?.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(records.count)-\(name.replacingOccurrences(of: " ", with: "-"))-\(phase).png"))
            }
            host.removeFromSuperview()
        }
        window.close()
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
