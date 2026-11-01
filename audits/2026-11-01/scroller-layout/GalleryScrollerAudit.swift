import AppKit
import FluentKit

@main struct GalleryScrollerAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.16)) }
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var results: [[String: Any]] = []
        for dark in [false, true] {
            for rtl in [false, true] {
                for width: CGFloat in [720, 1280] {
                    let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                    let navigation = FluentNavigationCoordinator(initial: GalleryRoute(destination: .home))
                    let screen = GalleryScreen(themeStore: FluentThemeStore(theme),
                        navigationCoordinator: navigation,
                        undoCoordinator: FluentUndoCoordinator())
                    let host = FluentViewHost(screen.frame(width: width, height: 560),
                        context: .init(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                    let window = NSWindow(contentRect: NSRect(x: 60, y: 320, width: width, height: 560),
                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.contentView = host
                    window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded(); settle()
                    _ = navigation.push(GalleryRoute(destination: .all, selectedItemID: "Expander"))
                    settle()
                    precondition(all(host).contains { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Header" })
                    for (step, style) in [NSScroller.Style.overlay, .legacy, .overlay].enumerated() {
                        all(host).compactMap { $0 as? NSScrollView }.forEach { $0.scrollerStyle = style }
                        settle()
                        for change in ["settled", "toggle-inner", "toggle-settings", "reopen-settings"] {
                            if change != "settled" {
                                let id = change == "toggle-inner" ? "FluentKit.Expander.Header" : "FluentKit.Settings.Expander.Header"
                                let control = all(host).first { $0.identifier?.rawValue == id }!
                                let hostID = change == "toggle-inner" ? "FluentKit.Expander" : "FluentKit.Settings.Expander"
                                let expander = all(host).first { $0.identifier?.rawValue == hostID }!
                                let oldHeight = expander.frame.height
                                if let button = control as? NSButton { button.performClick(nil) }
                                else { precondition(control.accessibilityPerformPress(), "Settings header must accept activation") }
                                // The real Gallery window installs its own appearance/motion context.
                                // Wait past its expansion animation before measuring final geometry.
                                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
                                precondition(abs(expander.frame.height - oldHeight) > 1, "Activation must change expander height")
                            }
                            let views = all(host)
                            for (index, scroll) in views.compactMap({ $0 as? NSScrollView }).enumerated() {
                                guard let document = scroll.documentView, scroll.frame.width > 0 else { continue }
                                results.append(["dark": dark, "rtl": rtl, "width": width, "step": step,
                                    "style": style.rawValue, "change": change, "scrollIndex": index,
                                    "class": String(describing: type(of: scroll)),
                                    "documentClass": String(describing: type(of: document)),
                                    "viewport": rect(scroll.contentView.bounds), "document": rect(document.frame),
                                    "expanders": all(document).filter { ["FluentKit.Expander", "FluentKit.Settings.Expander"].contains($0.identifier?.rawValue ?? "") }
                                        .map { ["id": $0.identifier!.rawValue, "frame": rect($0.convert($0.bounds, to: document))] }])
                            }
                        }
                    }
                    window.close()
                }
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
