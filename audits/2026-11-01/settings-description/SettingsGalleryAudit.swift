import AppKit
import FluentKit

@main struct ExpanderGalleryAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var records: [[String: Any]] = []
        for dark in [false, true] {
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            let navigation = FluentNavigationCoordinator(initial: GalleryRoute(destination: .home))
            let undo = FluentUndoCoordinator()
            let root = FluentViewHost(FluentAnyView(GalleryScreen(themeStore: FluentThemeStore(theme),
                navigationCoordinator: navigation, undoCoordinator: undo)), context: .init(theme: theme))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 1120, height: 760),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
            func rect(_ r: CGRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
            func capture(_ state: String, delay: TimeInterval = 0.45) throws {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: delay))
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                let views = all(root)
                let outer = views.first { $0.identifier?.rawValue == "FluentKit.Settings.Expander" }!
                let viewport = views.first { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Viewport" }!
                let content = viewport.subviews.first { $0.identifier?.rawValue != "FluentKit.Settings.Expander.Separator" }!
                let intrinsic = content.intrinsicContentSize.height
                let desired = intrinsic == NSView.noIntrinsicMetric ? content.fittingSize.height : intrinsic
                let children = views.filter { $0.identifier?.rawValue == "FluentKit.Expander" }.map {
                    ["label": $0.accessibilityLabel() ?? "", "bounds": rect($0.bounds),
                     "parentBounds": rect($0.superview!.bounds), "windowFrame": rect($0.convert($0.bounds, to: nil)),
                     "value": $0.accessibilityValue() as? String ?? ""] as [String: Any]
                }
                let header = views.first { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Header" }!
                let description = all(header).compactMap { $0 as? NSTextField }.first { $0.stringValue.contains("acceptance matrix") }!
                let descriptionCellSize = description.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: description.bounds.width, height: 1000))
                records.append(["rootBounds": rect(root.bounds), "headerFrame": rect(header.frame),
                    "descriptionFrame": rect(description.frame), "descriptionIntrinsicHeight": description.intrinsicContentSize.height,
                    "descriptionMeasuredHeight": descriptionCellSize.height, "descriptionWidth": descriptionCellSize.width,
                    "descriptionMaxWidth": description.preferredMaxLayoutWidth,
"variant": dark ? "dark" : "light", "state": state,
                    "outerFrame": rect(outer.convert(outer.bounds, to: nil)),
                    "viewportHeight": viewport.bounds.height, "viewportHidden": viewport.isHidden,
                    "expectedContentHeight": desired + 20, "contentFrame": rect(content.frame),
                    "children": children])
                let size = root.bounds.size
                let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: image)!.cgContext
                cg.scaleBy(x: 2, y: 2)
                if root.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                (root.layer!.presentation() ?? root.layer!).render(in: cg)
                try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(dark ? "dark" : "light")-\(state).png"))
            }
            navigation.push(GalleryRoute(destination: .all, selectedItemID: "Expander"))
            try capture("expanded")
            func inner(_ index: Int) {
                let headers = all(root).filter { $0.identifier?.rawValue == "FluentKit.Expander" }
                precondition(headers.count == 2)
                precondition(headers[index].accessibilityPerformPress())
            }
            inner(0); try capture("collapse-down-early", delay: 0.03); try capture("collapse-down")
            inner(1); try capture("both-collapsed")
            inner(0); try capture("expand-down")
            let outerHeader = all(root).first { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Header" }!
            precondition(outerHeader.accessibilityPerformPress()); try capture("outer-closed")
            precondition(outerHeader.accessibilityPerformPress()); try capture("outer-reopened")
            inner(1); try capture("expand-up")
            window.setContentSize(NSSize(width: 820, height: 760)); try capture("narrow")
            window.setContentSize(NSSize(width: 1400, height: 760)); try capture("wide")
            window.setContentSize(NSSize(width: 1120, height: 760)); try capture("restored")
            inner(0); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.04)); inner(0)
            try capture("interrupted")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
