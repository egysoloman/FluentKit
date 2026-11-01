import AppKit
import FluentKit

@main struct FocusChainAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        let navigation = FluentNavigationCoordinator(initial: GalleryRoute(destination: .home))
        let root = FluentViewHost(FluentAnyView(GalleryScreen(themeStore: FluentThemeStore(theme),
            navigationCoordinator: navigation, undoCoordinator: FluentUndoCoordinator())), context: .init(theme: theme))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1120, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root
        window.autorecalculatesKeyViewLoop = CommandLine.arguments.contains("--automatic")
        let controller = NSWindowController(window: window)
        controller.showWindow(nil); window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func name(_ view: NSView?) -> String {
            guard let view else { return "nil" }
            return "\(type(of: view)):\(view.accessibilityTitle() ?? view.accessibilityLabel() ?? ""):\(view.identifier?.rawValue ?? "")"
        }
        func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.45)); root.layoutSubtreeIfNeeded() }
        var records: [[String: Any]] = []
        func record(_ state: String) {
            let views = all(root).filter { $0.acceptsFirstResponder }
            records.append(["state": state, "automatic": window.autorecalculatesKeyViewLoop,
                "firstResponder": name(window.firstResponder as? NSView),
                "views": views.map { v in ["view": name(v), "canBecome": v.canBecomeKeyView,
                    "hidden": v.isHiddenOrHasHiddenAncestor, "frame": NSStringFromRect(v.convert(v.bounds, to: nil)),
                    "next": name(v.nextKeyView), "nextValid": name(v.nextValidKeyView)] as [String: Any] }])
        }
        settle(); record("home")
        navigation.push(GalleryRoute(destination: .category("BasicInput")))
        settle(); record("category")
        navigation.push(GalleryRoute(destination: .category("BasicInput"), selectedItemID: "CheckBox"))
        settle(); record("checkbox")
        let settings = all(root).first { $0.accessibilityTitle() == "Settings" && $0.acceptsFirstResponder }!
        window.makeFirstResponder(settings)
        let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48)!
        window.sendEvent(tab); record("tab-key-from-settings")
        window.makeFirstResponder(settings); window.selectNextKeyView(nil); record("tab-from-settings")
        window.recalculateKeyViewLoop(); record("recalculated")
        window.makeFirstResponder(settings); window.selectNextKeyView(nil); record("tab-after-recalculation")
        let check = all(root).compactMap { $0 as? FluentCheckBox }.first!
        window.makeFirstResponder(check); record("direct-check-focus")
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
