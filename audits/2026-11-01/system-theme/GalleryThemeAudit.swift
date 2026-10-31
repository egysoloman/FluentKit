import AppKit
import FluentKit

private final class ThemeBackground: NSView {
    var theme: FluentTheme { didSet { needsDisplay = true } }
    init(_ theme: FluentTheme) { self.theme = theme; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { theme.windowBackground.setFill(); dirtyRect.fill() }
}

@main struct GalleryThemeAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        NSApp.appearance = NSAppearance(named: .aqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 1120, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.backgroundColor = .clear; window.isOpaque = false
        let coordinator = FluentAppearanceCoordinator(theme: FluentTheme())
        coordinator.attach(to: window)
        let store = FluentThemeStore(preference: .system, resolvedTheme: coordinator.resolvedTheme)
        coordinator.bind(to: store)
        let navigation = FluentNavigationCoordinator(initial: GalleryRoute(destination: .home))
        let root = FluentViewHost(GalleryScreen(themeStore: store, navigationCoordinator: navigation,
            undoCoordinator: FluentUndoCoordinator()), context: .init(theme: coordinator.resolvedTheme, appearanceCoordinator: coordinator))
        root.wantsLayer = true
        let background = ThemeBackground(coordinator.resolvedTheme)
        background.frame.size = NSSize(width: 1120, height: 760); background.autoresizingMask = [.width, .height]
        background.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: background.leadingAnchor), root.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            root.topAnchor.constraint(equalTo: background.topAnchor), root.bottomAnchor.constraint(equalTo: background.bottomAnchor)])
        window.contentView = background
        coordinator.register(owner: background, updateImmediately: false) { [weak background] in background?.theme = $0 }
        window.makeKeyAndOrderFront(nil)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func color(_ c: NSColor?) -> [CGFloat] {
            guard let c = c?.usingColorSpace(.sRGB) else { return [] }
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        var records: [[String: Any]] = []
        for page in ["TextBox", "Expander", "ToggleSwitch", "AutoSuggestBox", "CommandBar", "MenuBar", "SplitButton"] {
            _ = navigation.push(GalleryRoute(destination: .all, selectedItemID: page))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.55))
            for dark in [false, true, false] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                let views = all(root)
                var controls: [[String: Any]] = []
                for v in views {
                    var theme: FluentTheme?
                    if let v = v as? FluentButton { theme = v.theme }
                    if let v = v as? FluentTextField { theme = v.theme }
                    if let v = v as? FluentSearchTextField { theme = v.theme }
                    if let v = v as? FluentSecureTextField { theme = v.theme }
                    if let v = v as? FluentToggle { theme = v.theme }
                    if let v = v as? FluentMenuBar { theme = v.theme }
                    if let v = v as? FluentCommandBar { theme = v.theme }
                    if let v = v as? FluentSplitButton { theme = v.theme }
                    if let theme { controls.append(["type": String(describing: type(of: v)), "dark": theme.isDark]) }
                }
                let labels = views.compactMap { $0 as? NSTextField }.filter { $0.stringValue == page }
                records.append(["page": page, "dark": dark, "coordinatorDark": coordinator.resolvedTheme.isDark,
                    "storeDark": store.resolvedTheme.isDark, "backgroundDark": background.theme.isDark,
                    "windowAppearance": window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])!.rawValue,
                    "titleInks": labels.map { color($0.textColor) }, "expectedInk": color(coordinator.resolvedTheme.textPrimary), "controls": controls])
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2240, pixelsHigh: 1520,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                if root.isFlipped { cg.translateBy(x: 0, y: root.bounds.height); cg.scaleBy(x: 1, y: -1) }
                root.layer?.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(records.count)-\(page)-\(dark).png"))
            }
        }
        window.close()
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
