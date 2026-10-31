import AppKit
import FluentKit

@main struct AnnotatedScrollBarVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for variant in ["light", "dark", "rtl"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight)
            var scrolls: [String] = []
            let host = FluentViewHost(FluentAnyView(FluentAnnotatedScrollView(
                labels: (0..<10).map { FluentAnnotatedScrollBarLabel(String(UnicodeScalar(65 + $0 * 2)!), scrollOffset: CGFloat($0) * 40 * 32) },
                detailLabel: { "Row \(Int($0 / 32) + 1)" },
                onScrolling: { _, kind in scrolls.append("\(kind)"); return false }
            ) {
                FluentAnyView(FluentForEach(Array(0..<400), id: { $0 }, spacing: 0) { row in
                    FluentText("Row \(row + 1)", style: .body).padding(6).frame(width: 300, height: 32)
                })
            }.frame(width: 380, height: 300)), context: context)
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 380, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let bar = descendants(host).first { $0.identifier?.rawValue == "FluentKit.AnnotatedScrollBar" }!
            func capture(_ state: String) throws {
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
                records.append(["variant": variant, "state": state, "scrolls": scrolls, "voiceOver": "pending", "windowsComparison": "pending"])
            }
            try capture("initial")
            let barMid = bar.convert(NSPoint(x: bar.bounds.midX, y: bar.bounds.height * 0.6), to: nil)
            let move = NSEvent.mouseEvent(with: .mouseMoved, location: barMid, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            bar.mouseMoved(with: move)
            let bubble = descendants(host).first { $0.identifier?.rawValue == "FluentKit.AnnotatedScrollBar.DetailLabel" }
            precondition(bubble?.isHidden == false, "Hovering the rail shows the detail label")
            try capture("hover")
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: barMid, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            bar.mouseDown(with: down)
            bar.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: barMid, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
            precondition(scrolls == ["click"], "Clicking the rail scrolls")
            try capture("clicked")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
