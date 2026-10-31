import AppKit
import FluentKit

@main struct ImplementedSamplesVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let screen = GalleryScreen(themeStore: FluentThemeStore(),
            navigationCoordinator: FluentNavigationCoordinator(initial: GalleryRoute(destination: .home)),
            undoCoordinator: FluentUndoCoordinator())
        let names = ["ToggleButton", "RepeatButton", "StackPanel", "Grid", "SplitView", "NavigationView", "TabView",
                     "TeachingTip", "TitleBar", "CommandBarFlyout", "RichEditBox", "Clipboard", "StoragePickers"]
        for item in GalleryCatalog.allItems where names.contains(item.id) {
            let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
            let host = FluentViewHost(screen.sample(for: item, theme: theme), context: .init(theme: theme, reduceMotion: true))
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1040, pixelsHigh: 600, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            if host.isFlipped { cg.translateBy(x: 0, y: 300); cg.scaleBy(x: 1, y: -1) }
            host.layer!.render(in: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(item.id).png"))
            window.close()
        }
    }
}
