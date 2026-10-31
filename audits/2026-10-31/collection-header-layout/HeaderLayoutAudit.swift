import AppKit
import FluentKit

@main struct HeaderLayoutAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func rect(_ r: NSRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
        var results: [[String: Any]] = []
        for kind in ["list", "grid"] {
            for dark in [false, true] {
                for rtl in [false, true] {
                    let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                    let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
                    var snapshot = FluentCollectionSnapshot<Int, Int>()
                    snapshot.appendSections([0, 1])
                    snapshot.appendItems(Array(0..<30), toSection: 0)
                    snapshot.appendItems(Array(30..<60), toSection: 1)
                    let request = FluentState<Int?>(wrappedValue: nil)
                    let collection = FluentCollection(snapshot: snapshot,
                        layout: kind == "list" ? .list(rowHeight: 32) : .adaptiveGrid(minimumItemWidth: 120, itemHeight: 60),
                        content: { FluentText("Item \($0)") },
                        header: { FluentText("Group \($0): a long heading that must fit the available width") })
                        .scrollIntoView(request.projectedValue, alignment: .leading)
                    let host = FluentViewHost(collection, context: context)
                    host.wantsLayer = true
                    host.layer?.backgroundColor = theme.windowBackground.cgColor
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = host
                    window.makeKeyAndOrderFront(nil)
                    host.layoutSubtreeIfNeeded()
                    let native = descendants(host).compactMap { $0 as? NSCollectionView }.first!
                    let scroll = native.enclosingScrollView!
                    scroll.scrollerStyle = .legacy
                    func pump() {
                        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                        host.layoutSubtreeIfNeeded()
                    }
                    let name = "\(kind)-\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")"
                    for width: CGFloat in [600, 180, 40, 1200, 320] {
                        window.setContentSize(NSSize(width: width, height: 300))
                        pump()
                        if width == 320 { request.wrappedValue = 45; pump(); precondition(request.wrappedValue == nil) }
                        let headers = native.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader)
                        precondition(!headers.isEmpty)
                        let measurements = headers.map { header -> [String: Any] in
                            let label = descendants(header).compactMap { $0 as? NSTextField }.first!
                            let aligned = label.alignmentRect(forFrame: label.frame)
                            let divider = header.layer!.sublayers!.first { $0.name == "FluentKit.Collection.HeaderDivider" }!
                            return ["header": rect(header.frame), "label": rect(aligned), "divider": rect(divider.frame),
                                "text": label.stringValue, "clipped": header.layer?.masksToBounds == true]
                        }
                        results.append(["variant": name, "requestedWidth": width, "hostWidth": host.bounds.width,
                            "viewportWidth": scroll.contentView.bounds.width, "scrollY": scroll.contentView.bounds.minY,
                            "headers": measurements, "windowsComparison": "pending"])
                        if width == 320 || width == 40 {
                            host.displayIfNeeded()
                            CATransaction.flush()
                            let size = host.bounds.size
                            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                            cg.scaleBy(x: 2, y: 2)
                            if host.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                            host.layer!.render(in: cg)
                            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(Int(width)).png"))
                        }
                    }
                    window.close()
                }
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
