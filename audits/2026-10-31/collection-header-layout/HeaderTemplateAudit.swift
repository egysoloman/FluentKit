import AppKit
import FluentKit

@main struct HeaderTemplateAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
        let cases: [FluentAnyView] = [
            FluentAnyView(FluentButtonView("Action") {}),
            FluentAnyView(FluentHStack(spacing: 12) { FluentButtonView("First") {}; FluentButtonView("Second") {} }),
            FluentAnyView(FluentVStack(alignment: .width) { FluentButtonView("Stretch") {} })
        ]
        var results: [[String: Any]] = []
        for rtl in [false, true] {
            for (index, template) in cases.enumerated() {
                let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
                let content = FluentCollection(snapshot: FluentCollectionSnapshot(section: 0, items: [0]),
                    layout: .list(headerHeight: 60), content: { FluentText("Item \($0)") }, header: { _ in template })
                let host = FluentViewHost(content, context: .init(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                host.wantsLayer = true
                host.layer?.backgroundColor = theme.windowBackground.cgColor
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                host.layoutSubtreeIfNeeded()
                let native = descendants(host).compactMap { $0 as? NSCollectionView }.first!
                let header = native.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).first!
                header.layoutSubtreeIfNeeded()
                let child = header.subviews.first!
                let buttons = descendants(child).compactMap { $0 as? FluentButton }
                let expected = index == 2 ? header.bounds.width - 24
                    : buttons.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width } + (index == 1 ? 12 : 0)
                let frame = child.alignmentRect(forFrame: child.frame)
                results.append(["rtl": rtl, "template": index, "width": frame.width, "expectedWidth": expected,
                    "x": frame.minX, "expectedX": rtl ? header.bounds.width - 12 - expected : 12])
                host.displayIfNeeded()
                CATransaction.flush()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 240, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: 2, y: 2)
                if host.isFlipped { cg.translateBy(x: 0, y: 120); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("template-\(index)-\(rtl ? "rtl" : "ltr").png"))
                window.close()
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
