import AppKit
import FluentKit

@main
struct FluentKitGalleryApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = GalleryAppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class GalleryAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    private var mainMenuCoordinator: FluentMainMenuCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 1120, height: 760)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FluentKit Gallery"
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()

        let navigationCoordinator = FluentNavigationCoordinator(
            initial: GalleryRoute(destination: .home)
        )
        let undoCoordinator = FluentUndoCoordinator()
        let menuCoordinator = FluentMainMenuCoordinator(
            applicationName: "FluentKit Gallery",
            groups: [
                FluentCommandGroup("View") {
                    FluentCommand(
                        "Back",
                        keyEquivalent: "[",
                        isEnabled: { navigationCoordinator.canGoBack },
                        action: { _ = navigationCoordinator.goBack() }
                    )
                    FluentCommand(
                        "Forward",
                        keyEquivalent: "]",
                        isEnabled: { navigationCoordinator.canGoForward },
                        action: { _ = navigationCoordinator.goForward() }
                    )
                    FluentCommand("Search", keyEquivalent: "f") {
                        FluentNavigationSearch.requestFocus(in: window)
                    }
                }
            ],
            settingsAction: { [weak window] in
                _ = navigationCoordinator.push(GalleryRoute(destination: .settings))
                window?.makeKeyAndOrderFront(nil)
            }
        )
        menuCoordinator.install(on: NSApplication.shared)
        mainMenuCoordinator = menuCoordinator

        let coordinator = FluentAppearanceCoordinator(theme: FluentTheme())
        coordinator.attach(to: window)
        appearanceCoordinator = coordinator
        let themeStore = FluentThemeStore(
            preference: .system,
            resolvedTheme: coordinator.resolvedTheme
        )
        coordinator.bind(to: themeStore)
        let background = GalleryBackgroundView(
            frame: NSRect(origin: .zero, size: size),
            theme: coordinator.resolvedTheme
        )
        background.autoresizingMask = [.width, .height]
        let context = FluentRenderContext(
            theme: coordinator.resolvedTheme,
            spacing: coordinator.resolvedTheme.designTokens.spacingMedium,
            appearanceCoordinator: coordinator
        )
        let host = FluentViewHost(
            FluentAnyView(
                GalleryScreen(
                    themeStore: themeStore,
                    navigationCoordinator: navigationCoordinator,
                    undoCoordinator: undoCoordinator
                )
            ),
            context: context
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        window.contentView = background
        appearanceRegistration = coordinator.register(owner: background, updateImmediately: false) {
            [weak background] theme in
            background?.theme = theme
        }

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private final class GalleryBackgroundView: NSView {
    var theme: FluentTheme {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, theme: FluentTheme) {
        self.theme = theme
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        theme.windowBackground.setFill()
        dirtyRect.fill()
    }
}
