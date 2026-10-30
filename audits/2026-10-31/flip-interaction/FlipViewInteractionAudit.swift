import AppKit
import FluentKit

// Compile with the four Gallery sample source files, like tools/quality/GallerySampleAudit.swift.
@main struct FlipViewInteractionAudit {
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
            var disabled = false
            let host = FluentViewHost(FluentAnyView(screen.sample(for: item, theme: theme).disabled(disabled)), context: context)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            func refresh() {
                host.update(FluentAnyView(screen.sample(for: item, theme: theme).disabled(disabled)), context: context)
                host.layoutSubtreeIfNeeded()
            }
            func click(_ title: String) {
                let button = descendants(host).compactMap { $0 as? NSButton }.first { $0.title == title }!
                precondition(button.isEnabled)
                button.performClick(nil)
                refresh()
            }
            func capture(_ state: String, expected: String, previousVisible: Bool, nextVisible: Bool) throws {
                refresh()
                let views = descendants(host)
                let flip = views.first { $0.identifier?.rawValue == "FluentKit.FlipView" }!
                precondition(flip.accessibilityValue() as? String == expected)
                let previous = views.first { $0.identifier?.rawValue == "FluentKit.FlipView.Previous" }!
                let next = views.first { $0.identifier?.rawValue == "FluentKit.FlipView.Next" }!
                precondition(previous.isHidden != previousVisible && next.isHidden != nextVisible)
                for view in views {
                    precondition([view.frame.minX, view.frame.minY, view.frame.width, view.frame.height].allSatisfy(\.isFinite))
                    precondition(view.frame.width >= 0 && view.frame.height >= 0)
                }
                host.displayIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(
                    to: output.appendingPathComponent("flip-\(variant)-\(state).png"))
                results.append(["variant": variant, "state": state, "accessibilityValue": expected,
                    "previousVisible": previousVisible, "nextVisible": nextVisible, "enabled": !disabled,
                    "buttonWidth": next.frame.width, "buttonHeight": next.frame.height])
            }
            let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            let flip = descendants(host).first { $0.identifier?.rawValue == "FluentKit.FlipView" }!
            try capture("idle", expected: "1 of 3", previousVisible: false, nextVisible: false)
            flip.mouseEntered(with: event)
            try capture("pointer", expected: "1 of 3", previousVisible: false, nextVisible: true)
            click("Last page")
            flip.mouseEntered(with: event)
            try capture("last", expected: "3 of 3", previousVisible: true, nextVisible: false)
            window.makeFirstResponder(flip)
            flip.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 115)!)
            try capture("keyboard", expected: "1 of 3", previousVisible: false, nextVisible: true)
            disabled = true
            try capture("disabled", expected: "1 of 3", previousVisible: false, nextVisible: false)
            disabled = false
            refresh()
            for _ in 0..<3 { click("Remove last") }
            try capture("empty", expected: "0 items", previousVisible: false, nextVisible: false)
            click("Reset")
            precondition(flip.accessibilityValue() as? String == "1 of 3")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
