import AppKit
import FluentKit

// Compile with the four Gallery sample source files, like tools/quality/GallerySampleAudit.swift.
@main struct FlipViewVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let item = GalleryCatalog.allItems.first { $0.id == "FlipView" }!
        precondition(item.coverage == .partial)
        var results: [[String: Any]] = []
        for variant in ["light", "dark", "rtl"] {
            let screen = GalleryScreen(themeStore: FluentThemeStore(),
                navigationCoordinator: FluentNavigationCoordinator(initial: GalleryRoute(destination: .home)),
                undoCoordinator: FluentUndoCoordinator())
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true,
                layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight, locale: Locale(identifier: "en_US"))
            let host = FluentViewHost(screen.sample(for: item, theme: theme), context: context)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            func refresh() {
                host.update(screen.sample(for: item, theme: theme), context: context)
                host.layoutSubtreeIfNeeded()
            }
            func click(_ title: String) {
                let button = descendants(host).compactMap { $0 as? NSButton }.first { $0.title == title }!
                precondition(button.isEnabled)
                button.performClick(nil)
                refresh()
            }
            func capture(_ state: String, expected: String) throws {
                refresh()
                let views = descendants(host)
                let flip = views.first { $0.identifier?.rawValue == "FluentKit.FlipView" }!
                precondition(flip.accessibilityValue() as? String == expected)
                for view in views {
                    precondition([view.frame.minX, view.frame.minY, view.frame.width, view.frame.height].allSatisfy(\.isFinite))
                    precondition(view.frame.width >= 0 && view.frame.height >= 0)
                }
                host.displayIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(
                    to: output.appendingPathComponent("flip-\(variant)-\(state).png"))
                results.append(["variant": variant, "state": state, "accessibilityValue": expected])
            }
            try capture("first", expected: "1 of 3")
            click("Last page")
            try capture("last", expected: "3 of 3")
            for _ in 0..<3 { click("Remove last") }
            try capture("empty", expected: "0 items")
            click("Reset")
            let flip = descendants(host).first { $0.identifier?.rawValue == "FluentKit.FlipView" }!
            precondition(flip.accessibilityValue() as? String == "1 of 3")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
