import AppKit
import FluentKit

@main struct ScopeGalleryAudit {
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
            func capture(_ state: String, title: String, itemID: String?) throws {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.65))
                root.layoutSubtreeIfNeeded()
                root.displayIfNeeded()
                CATransaction.flush()
                let views = all(root)
                let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
                let bodyMatches = labels.contains(title) && (itemID != "Expander" || views.contains {
                    $0.identifier?.rawValue == "FluentKit.Expander"
                })
                records.append(["variant": dark ? "dark" : "light", "state": state,
                    "expectedTitle": title, "expectedItem": itemID ?? "home", "bodyMatches": bodyMatches,
                    "historyItem": navigation.current?.selectedItemID ?? "home",
                    "labels": labels, "expanderCount": views.filter { $0.identifier?.rawValue == "FluentKit.Expander" }.count])
                let size = root.bounds.size
                let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: image)!.cgContext
                cg.scaleBy(x: 2, y: 2)
                if root.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                root.layer!.render(in: cg)
                try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(dark ? "dark" : "light")-\(state).png"))
            }
            try capture("home", title: "FluentKit Gallery", itemID: nil)
            for id in ["Button", "Expander", "CheckBox"] {
                navigation.push(GalleryRoute(destination: .all, selectedItemID: id))
                try capture(id, title: GalleryCatalog.item(id: id)!.title, itemID: id)
            }
            navigation.goBack()
            try capture("back", title: GalleryCatalog.item(id: "Expander")!.title, itemID: "Expander")
            navigation.goForward()
            try capture("forward", title: GalleryCatalog.item(id: "CheckBox")!.title, itemID: "CheckBox")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
