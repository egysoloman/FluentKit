import AppKit
import ObjectiveC

/// Coordinates the effective appearance and theme-dependent presenters owned by one window.
///
/// Declarative controls still receive their theme through `FluentRenderContext`. This object owns
/// the window boundary: AppKit appearance, the root material, and temporary presenters that must
/// update in the same transaction without being destroyed and recreated.
public final class FluentAppearanceCoordinator {
    /// The actual theme currently applied to this window. This value is always explicit Light or
    /// Dark; `.system` lives only in `preference` and the bound theme store.
    public private(set) var resolvedTheme: FluentTheme
    public var theme: FluentTheme { resolvedTheme }
    public private(set) var preference: FluentThemePreference
    public private(set) var themeGeneration: UInt64 = 0

    var resolvedAppearance: NSAppearance { currentAppearance }

    private weak var window: NSWindow?
    private weak var rootMaterialView: FluentMaterialView?
    private var ownedThemeStore: FluentThemeStore?
    private weak var themeStore: FluentThemeStore?
    private var themeStoreObserver: UUID?
    private var contentViewObservation: NSKeyValueObservation?
    private var appearanceObserverView: FluentAppearanceObserverView?
    private var currentAppearance: NSAppearance
    private var registrations: [UUID: Registration] = [:]
    private var registrationSequence: UInt64 = 0
    private var windowAppearanceObservation: NSKeyValueObservation?
    private var systemRefreshScheduled = false
    private var isApplyingAppearance = false
    private var applyAgainAfterCurrentTransaction = false

    private struct Registration {
        weak var owner: AnyObject?
        let sequence: UInt64
        let prepare: (() -> Void)?
        let update: (FluentTheme) -> Void
    }

    public init(theme: FluentTheme = FluentTheme()) {
        let store = FluentThemeStore(theme)
        ownedThemeStore = store
        themeStore = store
        preference = store.preference
        resolvedTheme = store.resolvedTheme
        currentAppearance = fluentDefaultAppearance()
        observeThemeStore(store)
    }

    public convenience init(
        preference: FluentThemePreference,
        theme: FluentTheme = FluentTheme()
    ) {
        self.init(theme: theme.with(colorScheme: preference.colorScheme))
        setPreference(preference)
    }

    /// Attaches the coordinator to its native window. A coordinator is intentionally not shared
    /// between windows because AppKit appearances and transient presenters are window scoped.
    public func attach(to window: NSWindow, rootMaterialView: FluentMaterialView? = nil) {
        windowAppearanceObservation?.invalidate()
        contentViewObservation?.invalidate()
        self.window = window
        self.rootMaterialView = rootMaterialView
        window.fluentAppearanceCoordinator = self
        windowAppearanceObservation = window.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            self?.scheduleSystemAppearanceRefresh()
        }
        contentViewObservation = window.observe(\.contentView, options: [.new]) {
            [weak self, weak window] _, _ in
            guard let window else { return }
            self?.installAppearanceObserver()
            self?.synchronizeAppearanceHosts(in: window.contentView)
        }
        installAppearanceObserver()
        refreshResolvedTheme(forceApply: true, synchronizeParticipants: true)
        synchronizeAppearanceHosts(in: window.contentView)
    }

    /// Uses an observable store as this window's authoritative theme source.
    public func bind(to store: FluentThemeStore) {
        if themeStore === store { return }
        unbindThemeStore()
        ownedThemeStore = nil
        themeStore = store
        observeThemeStore(store)
        preference = store.preference
        refreshResolvedTheme(forceApply: true, synchronizeParticipants: true)
    }

    /// Registers an already-presented surface such as ContentDialog. Registrations hold their
    /// owner weakly, so a dismissed presenter never stays alive because of the coordinator.
    @discardableResult
    public func register(
        owner: AnyObject,
        updateImmediately: Bool = true,
        prepareForAppearanceChange: (() -> Void)? = nil,
        _ update: @escaping (FluentTheme) -> Void
    ) -> UUID {
        removeReleasedRegistrations()
        let id = UUID()
        registrationSequence &+= 1
        registrations[id] = Registration(
            owner: owner,
            sequence: registrationSequence,
            prepare: prepareForAppearanceChange,
            update: update
        )
        if updateImmediately { update(theme) }
        return id
    }

    public func unregister(_ id: UUID) {
        registrations.removeValue(forKey: id)
    }

    /// Applies a fixed theme when no store owns the window, or synchronizes an external update.
    public func updateTheme(_ theme: FluentTheme) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateTheme(theme) }
            return
        }
        themeStore?.theme = theme
    }

    public func setPreference(_ preference: FluentThemePreference) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setPreference(preference) }
            return
        }
        themeStore?.preference = preference
    }

    /// AppKit appearance callbacks only signal this method. Theme resolution and all native view
    /// updates remain owned by one coalesced coordinator transaction on the next main-loop turn.
    public func scheduleSystemAppearanceRefresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleSystemAppearanceRefresh() }
            return
        }
        guard !systemRefreshScheduled else { return }
        systemRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.systemRefreshScheduled = false
            guard self.preference == .system else { return }
            self.refreshResolvedTheme()
        }
    }

    func requestSystemAppearanceRefresh() { scheduleSystemAppearanceRefresh() }

    private func refreshResolvedTheme(
        forceApply: Bool = false,
        synchronizeParticipants: Bool = false
    ) {
        guard let store = themeStore else { return }
        let appearance = finalAppearance()
        currentAppearance = appearance
        let resolved = store.resolve(using: appearance)
        let didChange = resolvedTheme != resolved || preference != store.preference
        preference = store.preference
        resolvedTheme = resolved
        apply(
            theme: resolved,
            didChange: didChange,
            forceApply: forceApply,
            synchronizeParticipants: synchronizeParticipants
        )
    }

    private func finalAppearance() -> NSAppearance {
        if preference == .system {
            // A previous explicit preference may still be installed on the window until the
            // transaction below clears it. Use the application/root appearance for System so the
            // old override cannot leak into the new resolved theme.
            if window?.appearance == nil {
                return appearanceObserverView?.effectiveAppearance
                    ?? window?.effectiveAppearance
                    ?? fluentDefaultAppearance()
            }
            return NSApp?.effectiveAppearance ?? fluentDefaultAppearance()
        }
        return window?.effectiveAppearance ?? fluentDefaultAppearance()
    }

    private func installAppearanceObserver() {
        guard let contentView = window?.contentView else { return }
        if appearanceObserverView?.superview === contentView { return }
        appearanceObserverView?.removeFromSuperview()
        let observer = FluentAppearanceObserverView(coordinator: self)
        observer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(observer)
        NSLayoutConstraint.activate([
            observer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            observer.topAnchor.constraint(equalTo: contentView.topAnchor),
            observer.widthAnchor.constraint(equalToConstant: 0),
            observer.heightAnchor.constraint(equalToConstant: 0)
        ])
        appearanceObserverView = observer
    }

    private func apply(
        theme: FluentTheme,
        didChange: Bool,
        forceApply: Bool,
        synchronizeParticipants: Bool
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(
                    theme: theme,
                    didChange: didChange,
                    forceApply: forceApply,
                    synchronizeParticipants: synchronizeParticipants
                )
            }
            return
        }

        guard didChange || forceApply || synchronizeParticipants else { return }
        guard !isApplyingAppearance else {
            applyAgainAfterCurrentTransaction = true
            return
        }

        removeReleasedRegistrations()
        let registrations = self.registrations.values.sorted { $0.sequence < $1.sequence }
        let participants = appearanceParticipants(in: window?.contentView)
        isApplyingAppearance = true
        applyAgainAfterCurrentTransaction = false
        if didChange { themeGeneration &+= 1 }
        defer {
            isApplyingAppearance = false
            if applyAgainAfterCurrentTransaction {
                applyAgainAfterCurrentTransaction = false
                DispatchQueue.main.async { [weak self] in
                    self?.refreshResolvedTheme(forceApply: true)
                }
            }
        }

        if didChange {
            registrations.compactMap(\.prepare).forEach { $0() }
            participants.forEach { $0.prepareForFluentAppearanceChange() }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window?.appearance = fluentAppKitAppearance(for: preference, theme: theme)
        rootMaterialView?.fluentTheme = theme
        rootMaterialView?.isMaterialEnabled = theme.materialEffectsEnabled
        rootMaterialView?.fallbackColor = theme.windowBackground

        if didChange || synchronizeParticipants {
            participants.forEach { $0.applyFluentAppearance(theme) }
            registrations.forEach { $0.update(theme) }
        }
        markForDisplay(window?.contentView)
        window?.contentView?.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    private func appearanceParticipants(in view: NSView?) -> [any FluentAppearanceParticipant] {
        guard let view else { return [] }
        // A declarative host is already one registration and owns all descendants. Traversing
        // below it would write the same controls twice and could re-enter a render pass.
        if view is any FluentAppearanceHost { return [] }
        var result: [any FluentAppearanceParticipant] = []
        if view !== rootMaterialView,
           let participant = view as? any FluentAppearanceParticipant {
            result.append(participant)
        }
        view.subviews.forEach { result.append(contentsOf: appearanceParticipants(in: $0)) }
        return result
    }

    private func markForDisplay(_ view: NSView?) {
        guard let view else { return }
        view.needsDisplay = true
        view.layer?.setNeedsDisplay()
        view.subviews.forEach(markForDisplay)
    }

    private func synchronizeAppearanceHosts(in view: NSView?) {
        guard let view else { return }
        if let host = view as? any FluentAppearanceHost {
            host.synchronizeAppearanceRegistration()
            return
        }
        view.subviews.forEach { synchronizeAppearanceHosts(in: $0) }
    }

    private func removeReleasedRegistrations() {
        registrations = registrations.filter { $0.value.owner != nil }
    }

    private func observeThemeStore(_ store: FluentThemeStore) {
        themeStoreObserver = store.requestChanges.observe({ [weak self, weak store] _ in
            guard let self, store != nil else { return }
            self.refreshResolvedTheme(forceApply: true, synchronizeParticipants: true)
        }, notifyImmediately: false)
    }

    private func unbindThemeStore() {
        if let themeStoreObserver { themeStore?.requestChanges.removeObserver(themeStoreObserver) }
        themeStoreObserver = nil
        themeStore = nil
    }

    deinit {
        unbindThemeStore()
        windowAppearanceObservation?.invalidate()
        contentViewObservation?.invalidate()
    }
}

/// A zero-sized root participant keeps AppKit's effective-appearance callback at the window tree
/// boundary. Individual controls never use this callback as an independent theme update source.
private final class FluentAppearanceObserverView: NSView {
    private weak var coordinator: FluentAppearanceCoordinator?

    init(coordinator: FluentAppearanceCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Appearance.Observer")
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        coordinator?.scheduleSystemAppearanceRefresh()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Internal hook for native Fluent controls mounted outside a declarative host. The coordinator
/// remains the sole owner of when a resolved theme is applied.
protocol FluentAppearanceParticipant: AnyObject {
    func prepareForFluentAppearanceChange()
    func applyFluentAppearance(_ theme: FluentTheme)
}

extension FluentAppearanceParticipant {
    func prepareForFluentAppearanceChange() {}
}

/// Settles transition participants inside one declarative tree before its host receives the new
/// render context. Nested hosts prepare through their own registration.
func fluentPrepareAppearance(in view: NSView?) {
    guard let view else { return }
    if view is any FluentAppearanceHost { return }
    if let participant = view as? any FluentAppearanceParticipant {
        participant.prepareForFluentAppearanceChange()
    }
    view.subviews.forEach { fluentPrepareAppearance(in: $0) }
}

func fluentNotifyAppearanceCoordinator(from view: NSView) {
    view.window?.fluentAppearanceCoordinator?.requestSystemAppearanceRefresh()
}

/// Resolves an explicit Fluent theme to the matching AppKit appearance for transient windows.
/// System themes intentionally return nil so the native window remains the source of truth.
func fluentAppKitAppearance(
    for preference: FluentThemePreference,
    theme: FluentTheme
) -> NSAppearance? {
    guard preference != .system else { return nil }
    return fluentAppKitAppearance(for: theme)
}

func fluentAppKitAppearance(for theme: FluentTheme) -> NSAppearance? {
    guard theme.colorScheme != .system else { return nil }
    let name: NSAppearance.Name
    if theme.isHighContrast {
        name = theme.isDark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
    } else {
        name = theme.isDark ? .darkAqua : .aqua
    }
    return NSAppearance(named: name)
}

private var fluentAppearanceCoordinatorKey: UInt8 = 0

public extension NSWindow {
    /// The appearance coordinator installed by FluentKit for this window, when available.
    var fluentAppearanceCoordinator: FluentAppearanceCoordinator? {
        get {
            objc_getAssociatedObject(self, &fluentAppearanceCoordinatorKey)
                as? FluentAppearanceCoordinator
        }
        set {
            objc_setAssociatedObject(
                self,
                &fluentAppearanceCoordinatorKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
