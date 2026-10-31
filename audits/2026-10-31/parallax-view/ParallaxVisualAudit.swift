import AppKit
import FluentKit

@main struct ParallaxVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for variant in ["light", "dark"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let host = FluentViewHost(FluentAnyView(FluentParallaxView(vertical: FluentParallaxAxis(shift: 160), background: {
                FluentText("Parallax background", style: .titleLarge, color: theme.accent).padding(24).frame(width: 320, height: 400)
                    .background(theme.cardFillSecondary, cornerRadius: 0)
            }) {
                FluentText((1...40).map { "Item \($0)" }.joined(separator: "\n"), style: .body).padding(16).frame(width: 320, height: 1_000)
            }.frame(width: 320, height: 240)), context: FluentRenderContext(theme: theme, reduceMotion: true))
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let parallax = descendants(host).first { $0.identifier?.rawValue == "FluentKit.ParallaxView" }!
            let background = descendants(parallax).first { $0.identifier?.rawValue == "FluentKit.ParallaxView.Background" }!.subviews[0]
            let scrollView = descendants(parallax).compactMap { $0 as? NSScrollView }.first!
            func capture(_ state: String, offset: CGFloat) throws {
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: offset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                let scale: CGFloat = 2
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                    pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: scale, y: scale)
                if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(state).png"))
                records.append(["variant": variant, "state": state, "scrollOffset": offset, "backgroundY": background.frame.minY,
                                "backgroundHeight": background.frame.height, "windowsComparison": "pending"])
            }
            try capture("top", offset: 0)
            try capture("middle", offset: 380)
            try capture("end", offset: 760)
            let ys = records.suffix(3).map { $0["backgroundY"] as! CGFloat }
            precondition(ys[0] > ys[1] && ys[1] > ys[2], "The background moves up as content scrolls")
            precondition(ys[2] > -760, "The background moves slower than the content")
            precondition((records.last!["backgroundHeight"] as! CGFloat) == 400, "Arranged taller by the shift")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
