import AppKit

private var fluentApplicationRunner: AnyObject?

/// Declarative placement policy for a native scene window.
public enum FluentWindowPlacement: Equatable, Sendable {
    /// Centers the first window and cascades subsequent windows.
    case automatic
    /// Centers every window in the visible screen frame.
    case centered
    /// Places windows in a predictable diagonal cascade.
    case cascade
    /// Uses a fixed AppKit screen-coordinate origin.
    case origin(x: CGFloat, y: CGFloat)
    /// Pins a window to a visible-screen corner with a 24 point inset.
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// Controls whether a scene window restores its last native frame between launches.
public enum FluentWindowRestoration: Equatable, Sendable {
    case automatic
    case disabled
}

/// Identifies the semantic role of a native Fluent window.
public enum FluentWindowRole: Equatable, Sendable {
    case standard
    case settings
}

/// Controls whether a Fluent window participates in native macOS window tabs.
public enum FluentWindowTabbing: Equatable, Sendable {
    case automatic
    case preferred(identifier: String? = nil)
    case disallowed
}

/// A window description produced by a declarative scene.
public struct FluentWindowDescription {
    /// Stable application-defined identity used by future restoration and window commands.
    public let id: String
    public let title: String
    public let content: FluentAnyView
    public let size: NSSize
    public let minimumSize: NSSize
    public let styleMask: NSWindow.StyleMask
    public let material: FluentMaterial?
    public let placement: FluentWindowPlacement
    public let restoration: FluentWindowRestoration
    public let role: FluentWindowRole
    public let tabbing: FluentWindowTabbing
    public let windowControlsStyle: FluentWindowControlsStyle
    public let initiallyVisible: Bool
    public let context: FluentRenderContext

    public init(
        id: String = "main",
        title: String = "FluentKit",
        size: NSSize = NSSize(width: 900, height: 620),
        minimumSize: NSSize = NSSize(width: 640, height: 420),
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable],
        material: FluentMaterial? = .mica,
        placement: FluentWindowPlacement = .automatic,
        restoration: FluentWindowRestoration = .automatic,
        role: FluentWindowRole = .standard,
        tabbing: FluentWindowTabbing = .automatic,
        windowControlsStyle: FluentWindowControlsStyle = .macOS,
        initiallyVisible: Bool = true,
        context: FluentRenderContext = .init(),
        content: FluentAnyView
    ) {
        precondition(!id.isEmpty, "Fluent window IDs must not be empty")
        self.id = id
        self.title = title
        self.content = content
        self.size = size
        self.minimumSize = minimumSize
        self.styleMask = styleMask
        self.material = material
        self.placement = placement
        self.restoration = restoration
        self.role = role
        self.tabbing = tabbing
        self.windowControlsStyle = windowControlsStyle
        self.initiallyVisible = initiallyVisible
        self.context = context
    }
}

/// A scene that creates one native AppKit window for its declarative content.
public protocol FluentScene {
    func _makeWindowDescriptions() -> [FluentWindowDescription]
}

public extension FluentScene {
    func _makeWindowDescription() -> FluentWindowDescription {
        _makeWindowDescriptions().first ?? FluentWindowDescription(content: FluentAnyView(FluentEmptyView()))
    }
}

/// Type erasure for composing heterogeneous scenes in a scene group.
public struct FluentAnyScene: FluentScene {
    private let makeDescriptions: () -> [FluentWindowDescription]

    public init<Scene: FluentScene>(_ scene: Scene) {
        makeDescriptions = scene._makeWindowDescriptions
    }

    public func _makeWindowDescriptions() -> [FluentWindowDescription] {
        makeDescriptions()
    }
}

/// A result-builder-backed collection of native windows.
public struct FluentSceneGroup: FluentScene {
    private let scenes: [FluentAnyScene]

    public init(_ scenes: [FluentAnyScene]) {
        self.scenes = scenes
    }

    public init(@FluentSceneBuilder content: () -> FluentSceneGroup) {
        self.scenes = content().scenes
    }

    public func _makeWindowDescriptions() -> [FluentWindowDescription] {
        scenes.flatMap { $0._makeWindowDescriptions() }
    }
}

@resultBuilder
public enum FluentSceneBuilder {
    public static func buildExpression<Scene: FluentScene>(_ scene: Scene) -> FluentAnyScene {
        FluentAnyScene(scene)
    }

    public static func buildBlock(_ scenes: FluentAnyScene...) -> FluentSceneGroup {
        FluentSceneGroup(scenes)
    }

    public static func buildOptional(_ scene: FluentSceneGroup?) -> FluentSceneGroup {
        scene ?? FluentSceneGroup([])
    }

    public static func buildEither(first scene: FluentSceneGroup) -> FluentSceneGroup { scene }
    public static func buildEither(second scene: FluentSceneGroup) -> FluentSceneGroup { scene }
    public static func buildArray(_ scenes: [FluentSceneGroup]) -> FluentSceneGroup {
        FluentSceneGroup(scenes.flatMap { $0._makeWindowDescriptions() }.map { FluentAnyScene(FluentWindowDescriptionScene(description: $0)) })
    }
}

private struct FluentWindowDescriptionScene: FluentScene {
    let description: FluentWindowDescription

    func _makeWindowDescriptions() -> [FluentWindowDescription] { [description] }
}

public struct FluentWindowScene<Content: FluentView>: FluentScene {
    private let description: FluentWindowDescription

    public init(
        id: String = "main",
        title: String = "FluentKit",
        size: NSSize = NSSize(width: 900, height: 620),
        minimumSize: NSSize = NSSize(width: 640, height: 420),
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable],
        material: FluentMaterial? = .mica,
        placement: FluentWindowPlacement = .automatic,
        restoration: FluentWindowRestoration = .automatic,
        role: FluentWindowRole = .standard,
        tabbing: FluentWindowTabbing = .automatic,
        windowControlsStyle: FluentWindowControlsStyle = .macOS,
        initiallyVisible: Bool = true,
        theme: FluentTheme = FluentTheme(),
        spacing: CGFloat = 12,
        animationDuration: TimeInterval = FluentAnimation.content,
        animationTimingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        @FluentViewBuilder content: () -> Content
    ) {
        description = FluentWindowDescription(
            id: id,
            title: title,
            size: size,
            minimumSize: minimumSize,
            styleMask: styleMask,
            material: material,
            placement: placement,
            restoration: restoration,
            role: role,
            tabbing: tabbing,
            windowControlsStyle: windowControlsStyle,
            initiallyVisible: initiallyVisible,
            context: FluentRenderContext(theme: theme, spacing: spacing, animationDuration: animationDuration, animationTimingFunction: animationTimingFunction),
            content: FluentAnyView(content())
        )
    }

    public func _makeWindowDescriptions() -> [FluentWindowDescription] { [description] }
}

/// A singleton settings scene backed by a normal Fluent window.
///
/// Settings windows are hidden initially, do not restore stale frames, and are excluded from
/// document-style tabs. The application runner exposes the scene through the standard Settings...
/// item in the application menu.
public struct FluentSettingsScene<Content: FluentView>: FluentScene {
    private let description: FluentWindowDescription

    public init(
        id: String = "settings",
        title: String = "Settings",
        size: NSSize = NSSize(width: 620, height: 480),
        minimumSize: NSSize = NSSize(width: 480, height: 360),
        material: FluentMaterial? = .mica,
        initiallyVisible: Bool = false,
        theme: FluentTheme = FluentTheme(),
        spacing: CGFloat = 12,
        @FluentViewBuilder content: () -> Content
    ) {
        description = FluentWindowDescription(
            id: id,
            title: title,
            size: size,
            minimumSize: minimumSize,
            material: material,
            placement: .centered,
            restoration: .disabled,
            role: .settings,
            tabbing: .disallowed,
            initiallyVisible: initiallyVisible,
            context: FluentRenderContext(theme: theme, spacing: spacing),
            content: FluentAnyView(content())
        )
    }

    public func _makeWindowDescriptions() -> [FluentWindowDescription] { [description] }
}

public extension FluentScene {
    static func group(@FluentSceneBuilder content: () -> FluentSceneGroup) -> FluentSceneGroup {
        content()
    }
}

/// Commands accepted by a running application's window coordinator.
public enum FluentWindowCommand: Sendable, Equatable {
    case open(String)
    case close(String)
    case focus(String)
    case toggle(String)
}

/// Coordinates native windows produced by a scene group.
public final class FluentWindowCoordinator: NSObject, NSWindowDelegate {
    private let descriptions: [String: FluentWindowDescription]
    private let orderedIDs: [String]
    private let makeWindow: (FluentWindowDescription) -> NSWindow
    private let positionWindow: (NSWindow, Int, FluentWindowPlacement) -> Void
    private var windowsByID: [String: NSWindow] = [:]
    private let defaults: UserDefaults
    private let openWindowsDefaultsKey = "FluentKit.windows.openIDs"
    private let activeWindowDefaultsKey = "FluentKit.windows.activeID"

    public var onWindowOpened: ((String, NSWindow) -> Void)?
    public var onWindowClosed: ((String) -> Void)?

    public init(
        descriptions: [FluentWindowDescription],
        makeWindow: @escaping (FluentWindowDescription) -> NSWindow,
        positionWindow: @escaping (NSWindow, Int, FluentWindowPlacement) -> Void,
        defaults: UserDefaults = .standard
    ) {
        var indexed: [String: FluentWindowDescription] = [:]
        var orderedIDs: [String] = []
        for description in descriptions {
            precondition(indexed[description.id] == nil, "Duplicate Fluent window ID: \(description.id)")
            indexed[description.id] = description
            orderedIDs.append(description.id)
        }
        self.descriptions = indexed
        self.orderedIDs = orderedIDs
        self.makeWindow = makeWindow
        self.positionWindow = positionWindow
        self.defaults = defaults
        super.init()
    }

    public var availableWindowIDs: [String] { descriptions.keys.sorted() }
    public var openWindowIDs: [String] { windowsByID.keys.sorted() }

    /// The first standard scene in declaration order, falling back to the first declared scene.
    public var primaryWindowID: String? {
        orderedIDs.first { descriptions[$0]?.role == .standard } ?? orderedIDs.first
    }

    /// The first scene declared with the settings role, if the app provides one.
    public var settingsWindowID: String? {
        orderedIDs.first { descriptions[$0]?.role == .settings }
    }

    public func window(for id: String) -> NSWindow? { windowsByID[id] }

    @discardableResult
    public func open(id: String) -> NSWindow? {
        guard let description = descriptions[id] else { return nil }
        if let window = windowsByID[id] {
            focus(id: id)
            return window
        }
        let window = makeWindow(description)
        let index = windowsByID.count
        positionWindow(window, index, description.placement)
        let didRestoreFrame = restoreFrameIfAvailable(for: window, description: description)
        window.delegate = self
        windowsByID[id] = window
        persistOpenWindowState()
        window.makeKeyAndOrderFront(nil)
        if didRestoreFrame {
            // AppKit may cascade a newly ordered titled window after the initial frame restore.
            // Reapply the persisted frame after ordering so independent scene IDs keep their own
            // origins as well as their sizes.
            _ = restoreFrameIfAvailable(for: window, description: description)
        }
        activeWindowID = id
        onWindowOpened?(id, window)
        return window
    }

    public func close(id: String) { windowsByID[id]?.close() }

    public func focus(id: String) {
        guard let window = windowsByID[id] else { return }
        window.makeKeyAndOrderFront(nil)
        activeWindowID = id
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toggle(id: String) {
        if windowsByID[id] == nil { _ = open(id: id) } else { close(id: id) }
    }

    @discardableResult
    public func perform(_ command: FluentWindowCommand) -> NSWindow? {
        switch command {
        case let .open(id): return open(id: id)
        case let .close(id): close(id: id)
        case let .focus(id): focus(id: id)
        case let .toggle(id): toggle(id: id)
        }
        return window(for: command.id)
    }

    /// Opens the declaration's initial windows or the persisted multi-window presentation state.
    /// The application runner calls this automatically after constructing the coordinator.
    public func openInitiallyVisibleWindows() {
        let restoredIDs = restoredOpenWindowIDs
        // Opening a window updates the persisted active ID. Capture the launch-time value before
        // opening the restored set so the last declaration does not accidentally win focus.
        let restoredActiveID = restoredActiveWindowID
        let descriptionsToOpen = orderedIDs.compactMap { descriptions[$0] }.filter { description in
            guard description.restoration == .automatic else { return description.initiallyVisible }
            guard let restoredIDs else { return description.initiallyVisible }
            return restoredIDs.contains(description.id)
        }
        descriptionsToOpen.forEach { _ = open(id: $0.id) }
        if let restoredActiveID, windowsByID[restoredActiveID] != nil {
            focus(id: restoredActiveID)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let entry = windowsByID.first(where: { $0.value === closingWindow }) else { return }
        saveFrame(for: entry.key, window: closingWindow)
        windowsByID.removeValue(forKey: entry.key)
        if activeWindowID == entry.key {
            activeWindowID = orderedIDs.first { windowsByID[$0] != nil }
        }
        persistOpenWindowState()
        onWindowClosed?(entry.key)
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard let focusedWindow = notification.object as? NSWindow,
              let entry = windowsByID.first(where: { $0.value === focusedWindow }) else { return }
        activeWindowID = entry.key
    }

    /// Persists the current open-window set, active window, and automatic-restoration frames.
    /// Applications embedding a coordinator without `FluentApp` can call this during their own
    /// termination hook.
    public func saveRestorationState() {
        for (id, window) in windowsByID { saveFrame(for: id, window: window) }
        persistOpenWindowState()
    }

    func saveOpenWindowFrames() { saveRestorationState() }

    public private(set) var activeWindowID: String? {
        get { defaults.string(forKey: activeWindowDefaultsKey) }
        set {
            if let newValue { defaults.set(newValue, forKey: activeWindowDefaultsKey) }
            else { defaults.removeObject(forKey: activeWindowDefaultsKey) }
        }
    }

    private var restoredOpenWindowIDs: Set<String>? {
        guard let values = defaults.array(forKey: openWindowsDefaultsKey) as? [String] else { return nil }
        return Set(values)
    }

    private var restoredActiveWindowID: String? {
        defaults.string(forKey: activeWindowDefaultsKey)
    }

    private func persistOpenWindowState() {
        let ids = orderedIDs.filter { windowsByID[$0] != nil }
        defaults.set(ids, forKey: openWindowsDefaultsKey)
        if let activeWindowID, windowsByID[activeWindowID] == nil {
            self.activeWindowID = ids.first
        }
    }

    private func frameKey(for id: String) -> String { "FluentKit.window.\(id).frame" }

    @discardableResult
    private func restoreFrameIfAvailable(for window: NSWindow, description: FluentWindowDescription) -> Bool {
        guard description.restoration == .automatic,
              let values = defaults.array(forKey: frameKey(for: description.id)) as? [Double],
              values.count == 4,
              values.allSatisfy(\.isFinite) else { return false }
        let frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard frame.width >= description.minimumSize.width, frame.height >= description.minimumSize.height,
              let screen = NSScreen.screens.max(by: { lhs, rhs in
                  let lhsIntersection = lhs.visibleFrame.intersection(frame)
                  let rhsIntersection = rhs.visibleFrame.intersection(frame)
                  return lhsIntersection.width * lhsIntersection.height
                      < rhsIntersection.width * rhsIntersection.height
              }),
              screen.visibleFrame.intersects(frame) else { return false }
        // AppKit owns the final visible-frame policy. This keeps a restored window reachable when
        // a monitor, dock, menu bar, or saved coordinate system changed since the last launch.
        let visibleFrame = screen.visibleFrame
        var constrainedFrame = window.constrainFrameRect(frame, to: screen)
        constrainedFrame.size.width = min(constrainedFrame.width, visibleFrame.width)
        constrainedFrame.size.height = min(constrainedFrame.height, visibleFrame.height)
        constrainedFrame.origin.x = min(
            max(constrainedFrame.minX, visibleFrame.minX),
            visibleFrame.maxX - constrainedFrame.width
        )
        constrainedFrame.origin.y = min(
            max(constrainedFrame.minY, visibleFrame.minY),
            visibleFrame.maxY - constrainedFrame.height
        )
        window.setFrame(constrainedFrame, display: false)
        return true
    }

    private func saveFrame(for id: String, window: NSWindow) {
        guard descriptions[id]?.restoration == .automatic else { return }
        let frame = window.frame
        defaults.set([frame.origin.x, frame.origin.y, frame.width, frame.height], forKey: frameKey(for: id))
    }
}

private extension FluentWindowCommand {
    var id: String {
        switch self {
        case let .open(id), let .close(id), let .focus(id), let .toggle(id): return id
        }
    }
}

/// Optional lifecycle callbacks that receive the live window coordinator.
public protocol FluentWindowLifecycle {
    func applicationDidLaunch(with coordinator: FluentWindowCoordinator)
    func applicationWillTerminate(with coordinator: FluentWindowCoordinator)
}

public extension FluentWindowLifecycle {
    func applicationDidLaunch(with coordinator: FluentWindowCoordinator) {}
    func applicationWillTerminate(with coordinator: FluentWindowCoordinator) {}
}

/// A native application entry point. Conforming types can be used with the main attribute.
public protocol FluentApp {
    associatedtype Body: FluentScene
    init()
    var body: Body { get }

    func applicationDidLaunch()
    func applicationWillTerminate()
}

public extension FluentApp {
    func applicationDidLaunch() {}
    func applicationWillTerminate() {}

    static func main() {
        let runner = FluentApplicationRunner(app: Self())
        fluentApplicationRunner = runner
        runner.run()
    }
}

private final class FluentApplicationRunner<App: FluentApp>: NSObject, NSApplicationDelegate {
    private let app: App
    private var windows: [NSWindow] = []
    private var coordinator: FluentWindowCoordinator?
    private var mainMenuCoordinator: FluentMainMenuCoordinator?
    private var servicesCoordinator: FluentApplicationServicesCoordinator?
    private var keepsApplicationAliveWithoutWindows = false

    init(app: App) { self.app = app }

    func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = self
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let descriptions = app.body._makeWindowDescriptions()
        keepsApplicationAliveWithoutWindows = descriptions.contains { !$0.initiallyVisible }
        let coordinator = FluentWindowCoordinator(
            descriptions: descriptions,
            makeWindow: Self.makeWindow,
            positionWindow: Self.position
        )
        self.coordinator = coordinator
        let commandProvider = app as? any FluentApplicationCommands
        let applicationServicesProvider = app as? any FluentApplicationServices
        let servicesCoordinator = FluentApplicationServicesCoordinator(
            provider: applicationServicesProvider,
            windows: coordinator
        )
        self.servicesCoordinator = servicesCoordinator
        let menuCoordinator = FluentMainMenuCoordinator(
            applicationName: ProcessInfo.processInfo.processName,
            groups: commandProvider?.applicationCommandGroups ?? [],
            settingsAction: coordinator.settingsWindowID.map { settingsID in
                { [weak coordinator] in _ = coordinator?.open(id: settingsID) }
            }
        )
        menuCoordinator.install(on: NSApp)
        mainMenuCoordinator = menuCoordinator
        servicesCoordinator.installServices(on: NSApp)
        coordinator.openInitiallyVisibleWindows()
        windows = descriptions.compactMap { coordinator.window(for: $0.id) }
        NSApp.activate(ignoringOtherApps: true)
        app.applicationDidLaunch()
        (app as? any FluentWindowLifecycle)?.applicationDidLaunch(with: coordinator)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let servicesCoordinator else { return }
        application.activate(ignoringOtherApps: true)
        servicesCoordinator.openURLs(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let servicesCoordinator else { return }
        sender.activate(ignoringOtherApps: true)
        servicesCoordinator.openFiles(filenames.map { URL(fileURLWithPath: $0) })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard let servicesCoordinator else { return false }
        sender.activate(ignoringOtherApps: true)
        return servicesCoordinator.handleReopen(hasVisibleWindows: hasVisibleWindows)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        servicesCoordinator?.makeDockMenu()
    }

    private static func position(_ window: NSWindow, index: Int, placement: FluentWindowPlacement) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let inset: CGFloat = 24
        let cascadeOffset: CGFloat = CGFloat(index) * 28
        let centeredOrigin = NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        )
        let origin: NSPoint
        switch placement {
        case .automatic:
            if index == 0 {
                origin = centeredOrigin
            } else {
                origin = NSPoint(
                    x: visible.minX + 72 + cascadeOffset,
                    y: visible.maxY - window.frame.height - 72 - cascadeOffset
                )
            }
        case .centered:
            origin = centeredOrigin
        case .cascade:
            origin = NSPoint(
                x: visible.minX + 72 + cascadeOffset,
                y: visible.maxY - window.frame.height - 72 - cascadeOffset
            )
        case let .origin(x, y):
            origin = NSPoint(x: x, y: y)
        case .topLeading:
            origin = NSPoint(x: visible.minX + inset, y: visible.maxY - window.frame.height - inset)
        case .topTrailing:
            origin = NSPoint(x: visible.maxX - window.frame.width - inset, y: visible.maxY - window.frame.height - inset)
        case .bottomLeading:
            origin = NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .bottomTrailing:
            origin = NSPoint(x: visible.maxX - window.frame.width - inset, y: visible.minY + inset)
        }
        let clampedX = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
        let clampedY = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private static func makeWindow(_ description: FluentWindowDescription) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: description.size),
            styleMask: description.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = description.title
        window.contentMinSize = description.minimumSize
        window.minSize = description.minimumSize
        window.isReleasedWhenClosed = false
        window.applyFluentWindowControlsStyle(description.windowControlsStyle)
        switch description.tabbing {
        case .automatic:
            window.tabbingMode = .automatic
        case let .preferred(identifier):
            window.tabbingMode = .preferred
            if let identifier { window.tabbingIdentifier = identifier }
        case .disallowed:
            window.tabbingMode = .disallowed
        }

        let appearanceCoordinator = FluentAppearanceCoordinator(theme: description.context.theme)
        var context = description.context
        context.appearanceCoordinator = appearanceCoordinator
        let host = FluentViewHost(description.content, context: context)
        if let material = description.material {
            let materialView = FluentMaterialView(material: material)
            materialView.fluentTheme = context.theme
            materialView.isMaterialEnabled = context.theme.materialEffectsEnabled
            materialView.fallbackColor = context.theme.windowBackground
            materialView.translatesAutoresizingMaskIntoConstraints = false
            materialView.addSubview(host)
            host.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
                host.topAnchor.constraint(equalTo: materialView.topAnchor),
                host.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
            ])
            window.contentView = materialView
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            appearanceCoordinator.attach(to: window, rootMaterialView: materialView)
        } else {
            window.contentView = host
            appearanceCoordinator.attach(to: window)
        }
        return window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !keepsApplicationAliveWithoutWindows
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.applicationWillTerminate()
        if let coordinator {
            coordinator.saveRestorationState()
            (app as? any FluentWindowLifecycle)?.applicationWillTerminate(with: coordinator)
        }
    }
}
