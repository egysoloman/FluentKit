import AppKit
import FluentKit

@main struct AnimatedIconVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        for variant in ["light", "dark"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            for state in ["Normal", "PointerOver", "Pressed"] {
                let host = FluentViewHost(FluentAnyView(FluentHStack(spacing: 16) {
                    FluentAnimatedIcon(source: FluentBuiltInAnimatedIconSource(.back), state: state, size: 48)
                    FluentAnimatedIcon(source: FluentBuiltInAnimatedIconSource(.chevronDownSmall), state: state, size: 48)
                    FluentAnimatedIcon(source: FluentBuiltInAnimatedIconSource(.settings), state: state, size: 48)
                    FluentAnimatedIcon(source: FluentBuiltInAnimatedIconSource(.globalNavigationButton), state: state, size: 48)
                    FluentAnimatedIcon(source: FluentBuiltInAnimatedIconSource(.find), state: state, size: 48)
                    FluentAnimatedIcon(source: nil, fallbackSymbol: "star", state: state, size: 48)
                }.padding(16)), context: FluentRenderContext(theme: theme, reduceMotion: true))
                host.wantsLayer = true
                host.layer?.backgroundColor = theme.windowBackground.cgColor
                let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 420, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                // State changes apply on the next turn, as in WinUI.
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
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
                records.append(["variant": variant, "state": state, "glyphs": "approximations of the WinUI Lottie sources",
                                "windowsComparison": "pending"])
                window.close()
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
