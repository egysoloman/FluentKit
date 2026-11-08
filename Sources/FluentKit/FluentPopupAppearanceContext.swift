import AppKit

/// Keeps a caller's requested theme separate from the resolved colors of a presentation.
/// Like FlyoutBase::ForwardThemeToPresenter, defaults follow the placement target while an
/// explicit override survives window-wide theme transactions. System resolves at the anchor.
final class FluentPopupAppearanceContext {
    var requestedTheme: FluentTheme?
    var themeProvider: (() -> FluentTheme?)?
    private weak var anchor: NSView?
    private weak var ownerWindow: NSWindow?
    private weak var coordinator: FluentAppearanceCoordinator?
    private var registration: UUID?
    private let observer = FluentPopupAppearanceObserver()
    private var update: ((FluentTheme) -> Void)?
    private var generation: UInt = 0
    private var refreshPending = false

    init(theme: FluentTheme?) { requestedTheme = theme }

    var resolvedTheme: FluentTheme {
        let requested = themeProvider?() ?? requestedTheme
        // Window tokens still supply accent, density and materials for inherited surfaces.
        // The native anchor can have a more local appearance than its window coordinator.
        let inherited = (coordinator?.theme ?? FluentTheme()).with(colorScheme: .system)
        return fluentResolvedTheme(requested ?? inherited, using: anchor?.effectiveAppearance)
    }

    func observe(anchor: NSView, prepare: @escaping () -> Void,
                 update: @escaping (FluentTheme) -> Void) {
        invalidate()
        self.anchor = anchor
        ownerWindow = anchor.window
        self.update = update
        coordinator = anchor.window?.fluentAppearanceCoordinator
        registration = coordinator?.register(owner: self, updateImmediately: false,
            prepareForAppearanceChange: prepare) { [weak self] _ in
                guard let self else { return }
                self.update?(self.resolvedTheme)
            }
        anchor.addSubview(observer)
        observer.onChange = { [weak self] in self?.scheduleRefresh() }
    }

    private func scheduleRefresh() {
        guard !refreshPending, update != nil else { return }
        refreshPending = true
        let generation = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == generation else { return }
            self.refreshPending = false
            guard let anchor = self.anchor, anchor.window === self.ownerWindow else { return }
            // Reconciliation can replace the anchor's children. Restore only our own probe.
            if self.observer.superview !== anchor { anchor.addSubview(self.observer) }
            self.update?(self.resolvedTheme)
        }
    }

    func invalidate() {
        generation &+= 1
        refreshPending = false
        update = nil
        observer.onChange = nil
        observer.removeFromSuperview()
        if let registration { coordinator?.unregister(registration) }
        registration = nil
        coordinator = nil
        anchor = nil
        ownerWindow = nil
    }

    deinit { invalidate() }
}

/// A noninteractive attachment receives AppKit's native window and ancestor appearance changes
/// even when the host is an ordinary NSView without a FluentAppearanceCoordinator.
private final class FluentPopupAppearanceObserver: NSView {
    var onChange: (() -> Void)?
    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Popup.AppearanceObserver")
        alphaValue = 0
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onChange?() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onChange?() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); onChange?() }
}
