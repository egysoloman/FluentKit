import AppKit
import FluentKit

@main struct RefreshVisualAudit {
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
            let context = FluentRenderContext(theme: theme, reduceMotion: true)
            let refreshing = FluentState(wrappedValue: false)
            var requests: [FluentRefreshDeferral] = []
            let host = FluentViewHost(FluentAnyView(FluentRefreshContainer(isRefreshing: refreshing.projectedValue,
                onRefreshRequested: { requests.append($0) }) {
                FluentText("Quarterly report\nDesign review\nLunch on Friday", style: .body).padding(12).frame(width: 320, height: 600)
            }.frame(width: 320, height: 240)), context: context)
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let container = descendants(host).first { $0.identifier?.rawValue == "FluentKit.RefreshContainer" }!
            let scrollView = descendants(container).compactMap { $0 as? NSScrollView }.first!
            func capture(_ state: String, extra: [String: Any] = [:]) throws {
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
                var record: [String: Any] = ["variant": variant, "state": state, "refreshing": refreshing.wrappedValue,
                                             "touchScreen": "pending device", "windowsComparison": "pending"]
                record.merge(extra) { $1 }
                records.append(record)
            }
            try capture("idle")
            // Phased scroll events sent straight to NSScrollView enter AppKit's elastic tracking
            // loop, which waits for real input; the pull state machine is covered by unit tests.
            refreshing.wrappedValue = true
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            precondition(requests.count == 1, "Setting isRefreshing requests a refresh")
            try capture("refreshing", extra: ["held": -scrollView.contentView.bounds.origin.y])
            requests[0].complete()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            precondition(refreshing.wrappedValue == false, "Completing the deferral ends the refresh")
            try capture("completed")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
