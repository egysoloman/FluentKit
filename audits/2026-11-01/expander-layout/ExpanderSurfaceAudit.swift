import AppKit
import FluentKit

// Same background drawing and host constraints as Gallery App.swift; all page content is the
// actual GalleryScreen, not a replacement mock. This executable has its own windows/process.
private final class AuditBackground: NSView {
    let theme: FluentTheme
    init(theme: FluentTheme) { self.theme = theme; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { theme.windowBackground.setFill(); dirtyRect.fill() }
}

@main struct ExpanderSurfaceAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func rect(_ r: CGRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var records: [[String: Any]] = []
        for dark in [false, true] { for material in [false, true] {
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: material)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1120, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 820, height: 560)
            window.isOpaque = false
            window.backgroundColor = .clear
            let coordinator = FluentAppearanceCoordinator(theme: theme)
            coordinator.attach(to: window)
            let store = FluentThemeStore(theme)
            coordinator.bind(to: store)
            let navigation = FluentNavigationCoordinator(initial: GalleryRoute(destination: .home))
            let root = FluentViewHost(GalleryScreen(themeStore: store, navigationCoordinator: navigation,
                                                   undoCoordinator: FluentUndoCoordinator()),
                                      context: .init(theme: coordinator.resolvedTheme, appearanceCoordinator: coordinator))
            let background = AuditBackground(theme: theme)
            background.frame = NSRect(origin: .zero, size: NSSize(width: 1120, height: 760))
            background.autoresizingMask = [.width, .height]
            root.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(root)
            NSLayoutConstraint.activate([
                root.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                root.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                root.topAnchor.constraint(equalTo: background.topAnchor),
                root.bottomAnchor.constraint(equalTo: background.bottomAnchor)
            ])
            window.contentView = background
            root.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
            let variant = "\(dark ? "dark" : "light")-\(material ? "material" : "opaque")"
            func capture(_ state: String, saveImage: Bool = false) throws {
                background.layoutSubtreeIfNeeded()
                background.displayIfNeeded()
                CATransaction.flush()
                var layers: [[String: Any]] = []
                func record(_ layer: CALayer, owner: NSView, name: String) {
                    layers.append(["name": name, "ownerBounds": rect(owner.bounds), "frame": rect(layer.frame),
                                   "presentation": rect(layer.presentation()?.frame ?? layer.frame),
                                   "animations": layer.animationKeys() ?? [], "hidden": layer.isHidden])
                }
                for view in all(root) {
                    for layer in view.layer?.sublayers ?? [] where layer.name == "FluentKit.WindowShell.SharedChromeTint" {
                        record(layer, owner: view, name: layer.name!)
                        if let mask = layer.mask { record(mask, owner: view, name: layer.name! + ".mask") }
                    }
                    if let mask = view.layer?.mask, let name = mask.name { record(mask, owner: view, name: name) }
                }
                let views = all(root)
                let expanders = views.filter { $0.identifier?.rawValue == "FluentKit.Expander" }
                let viewport = views.first { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Viewport" }
                let following = views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Source identity" }
                var document: NSView? = viewport
                while document != nil && !(document is NSScrollView) { document = document?.superview }
                let scroll = document as? NSScrollView
                records.append(["variant": variant, "state": state, "bounds": rect(root.bounds), "layers": layers,
                    "expanderCount": expanders.count,
                    "followingRowFrame": following.map { rect($0.convert($0.bounds, to: nil)) } ?? [],
                    "viewportHeight": viewport?.bounds.height ?? 0,
                    "viewportHidden": viewport?.isHidden ?? true,
                    "documentHeight": scroll?.documentView?.bounds.height ?? 0,
                    "visibleDocumentHeight": scroll?.contentView.bounds.height ?? 0])
                guard saveImage else { return }
                let size = root.bounds.size
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: 2, y: 2)
                if root.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                (root.layer!.presentation() ?? root.layer!).render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(variant + "-" + state + ".png"))
            }
            func frames(_ name: String) throws {
                try capture(name + "-00")
                for frame in 1...8 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0 / 30))
                    if [1, 4, 8].contains(frame) { try capture(String(format: "%@-%02d", name, frame), saveImage: name == "page" && frame == 8) }
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            try capture("initial", saveImage: true)
            window.performZoom(nil)
            try frames("zoom")
            window.setContentSize(NSSize(width: 820, height: 560))
            try frames("narrow")
            _ = navigation.push(GalleryRoute(destination: .all, selectedItemID: "Expander"))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            try frames("page")
            let inner = all(root).filter { $0.identifier?.rawValue == "FluentKit.Expander" }
            precondition(inner.count == 2, "Navigation must update the actual page body")
            precondition(inner[0].accessibilityPerformPress())
            precondition(inner[1].accessibilityPerformPress())
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
            try capture("both-collapsed", saveImage: true)
            let outer = all(root).first { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Header" }!
            precondition(outer.accessibilityPerformPress())
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
            try capture("outer-closed")
            precondition(outer.accessibilityPerformPress())
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
            precondition(inner[0].accessibilityPerformPress())
            precondition(inner[1].accessibilityPerformPress())
            window.setContentSize(NSSize(width: 1000, height: 640))
            try frames("opening-resize")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
            try capture("reopened-resized", saveImage: true)
            window.setContentSize(NSSize(width: 1120, height: 760))
            try frames("restore")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
            try capture("restored", saveImage: true)
            window.close()
        }}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
