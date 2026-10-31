import AppKit
import FluentKit

@main struct TreeMoveGalleryAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var results: [[String: Any]] = []
        for variant in ["light", "dark", "rtl"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let sample = TreeViewGallerySample()
            let host = FluentViewHost(sample, context: FluentRenderContext(theme: theme, reduceMotion: true,
                layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight))
            host.wantsLayer = true; host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            window.makeKeyAndOrderFront(nil)
            let outline = all(host).compactMap { $0 as? NSOutlineView }.first!
            func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06)); host.layoutSubtreeIfNeeded() }
            func labels() -> [String] {
                (0..<outline.numberOfRows).map { row in
                    all(outline.view(atColumn: 0, row: row, makeIfNecessary: true)!).compactMap { ($0 as? NSTextField)?.stringValue }.joined()
                }
            }
            func capture(_ phase: String, expected: [String]) throws {
                pump(); let actual = labels(); precondition(actual == expected, "\(phase): \(actual)")
                precondition(host.bounds.width == 600, "Caption must not enlarge the window")
                results.append(["variant": variant, "phase": phase, "labels": actual, "width": host.bounds.width])
                host.displayIfNeeded(); CATransaction.flush()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(phase).png"))
            }
            pump()
            sample.moveEntries(["plan", "notes"], to: "remote", at: 0)
            try capture("moved-into-unloaded", expected: ["Work", "Specs", "Remote"])
            outline.expandItem(outline.item(atRow: 2))
            try capture("loaded-preserves-moved", expected: ["Work", "Specs", "Remote", "Plan", "Notes", "Shared document", "Reference"])
            sample.moveEntries(["remote", "work"], to: nil, at: 0)
            try capture("group-order", expected: ["Remote", "Plan", "Notes", "Shared document", "Reference", "Work", "Specs"])
            sample.moveEntries(["plan", "missing"], to: nil, at: 0)
            sample.moveEntries(["remote"], to: "plan", at: 0)
            try capture("failed-transaction-preserves-tree", expected: ["Remote", "Plan", "Notes", "Shared document", "Reference", "Work", "Specs"])
            window.close()
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
        print("12 Gallery move/lazy-load/order/rollback states passed")
    }
}
