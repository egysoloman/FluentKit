import AppKit

/// Explicit keyboard cycles remain authoritative when AppKit rebuilds the window's
/// geometric key-view loop. This does not restrict programmatic focus requests.
protocol FluentKeyboardFocusCycle: AnyObject {
    func moveKeyboardFocus(from view: NSView, backwards: Bool)
}

/// The default CheckBox/RadioButton HighVisibility focus borders. WinUI inflates the
/// control by (7, 3), then draws a 2pt outer Border and a 1pt inner Border. Its Border
/// CornerRadius describes the stroke centerline (geometry.cpp), not the painted edge.
enum FluentChoiceFocusVisual {
    static func update(
        outer: CAShapeLayer,
        inner: CAShapeLayer,
        bounds: CGRect,
        cornerRadius: CGFloat,
        theme: FluentTheme
    ) {
        let borderBounds = bounds.insetBy(dx: -7, dy: -3)
        // FocusRectManager.AdjustCornerRadius uses the average of adjacent margins;
        // a zero radius deliberately stays square.
        let radius = cornerRadius > 0 ? cornerRadius + 5 : 0
        outer.frame = bounds
        outer.path = CGPath(roundedRect: borderBounds.insetBy(dx: 1, dy: 1),
            cornerWidth: radius, cornerHeight: radius, transform: nil)
        outer.lineWidth = 2
        outer.strokeColor = (theme.isHighContrast
            ? theme.resolvedHighContrastColor(.controlTextColor) : theme.focusStrokeOuter).cgColor
        inner.frame = bounds
        inner.path = CGPath(roundedRect: borderBounds.insetBy(dx: 2.5, dy: 2.5),
            cornerWidth: max(0, radius - 2), cornerHeight: max(0, radius - 2), transform: nil)
        inner.lineWidth = 1
        inner.strokeColor = (theme.isHighContrast
            ? theme.resolvedHighContrastColor(.controlBackgroundColor) : theme.focusStrokeInner).cgColor
    }
}

/// Tracks whether the active focus was reached from the keyboard. AppKit exposes the first
/// responder but not the input modality that produced it, while Fluent focus visuals are shown
/// for keyboard navigation and remain hidden for ordinary pointer interaction.
enum FluentFocusVisibility {
    private static var isInstalled = false
    private static var monitors: [Any] = []
    private static let keyboardVisibilityByWindow = NSMapTable<NSWindow, NSNumber>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    static func isKeyboardFocusVisible(for view: NSView) -> Bool {
        installIfNeeded()
        guard let window = view.window,
              window.firstResponder === view,
              keyboardVisibilityByWindow.object(forKey: window)?.boolValue == true else {
            return false
        }
        return true
    }

    /// Returns the input modality that most recently moved focus in this window. Compound
    /// controls such as ToolTip use this to avoid treating a pointer click or an ordinary
    /// programmatic `makeFirstResponder` call as keyboard navigation.
    static func isKeyboardInteraction(in window: NSWindow?) -> Bool {
        installIfNeeded()
        guard let window else { return false }
        return keyboardVisibilityByWindow.object(forKey: window)?.boolValue == true
    }

    static func markKeyboardInteraction(in window: NSWindow?) {
        installIfNeeded()
        guard let window else { return }
        keyboardVisibilityByWindow.setObject(NSNumber(value: true), forKey: window)
    }

    static func markPointerInteraction(in window: NSWindow?) {
        installIfNeeded()
        guard let window else { return }
        keyboardVisibilityByWindow.setObject(NSNumber(value: false), forKey: window)
    }

    static func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        markKeyboardInteraction(in: event.window)
        guard event.keyCode == 48,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window = event.window else { return event }
        let focused: NSView?
        if let editor = window.firstResponder as? NSTextView {
            // Let the input method consume Tab while it owns a marked-text session.
            guard !editor.hasMarkedText() else { return event }
            focused = editor.isFieldEditor ? (editor.delegate as? NSView) : editor
        } else {
            focused = window.firstResponder as? NSView
        }
        guard let focused else { return event }
        var ancestor: NSView? = focused
        while let view = ancestor {
            if let cycle = view as? FluentKeyboardFocusCycle {
                // A consumed event may not reach the separate input-device monitor.
                FluentInputDeviceTracker.shared.record(.keyboard, in: window)
                // Text controls can consume Tab, or prepare navigation (for example,
                // AutoSuggestBox restores its query before leaving a suggestion preview).
                if let editor = window.firstResponder as? NSTextView {
                    let command = event.modifierFlags.contains(.shift)
                        ? #selector(NSResponder.insertBacktab(_:)) : #selector(NSResponder.insertTab(_:))
                    let consumed: Bool
                    if editor.isFieldEditor, let field = focused as? NSTextField {
                        consumed = field.delegate?.control?(field, textView: editor, doCommandBy: command) ?? false
                    } else {
                        consumed = editor.delegate?.textView?(editor, doCommandBy: command) ?? false
                    }
                    if consumed || window.firstResponder !== editor { return nil }
                }
                cycle.moveKeyboardFocus(from: focused, backwards: event.modifierFlags.contains(.shift))
                return nil
            }
            ancestor = view.superview
        }
        return event
    }

    static func cycleFocus(_ candidates: [NSView], from focused: NSView, backwards: Bool, in window: NSWindow) {
        let views = candidates.filter { $0.window === window && $0.canBecomeKeyView }
        guard !views.isEmpty else { return }
        let current = views.firstIndex { focused === $0 || focused.isDescendant(of: $0) }
        let next = current.map { ($0 + (backwards ? views.count - 1 : 1)) % views.count }
            ?? (backwards ? views.count - 1 : 0)
        // A validating text field may refuse to end editing. Preserve that veto.
        window.makeFirstResponder(views[next])
    }

    private static func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handleKeyDown(event)
        }) {
            monitors.append(monitor)
        }
        let pointerEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents, handler: { event in
            markPointerInteraction(in: event.window)
            return event
        }) {
            monitors.append(monitor)
        }
    }
}

/// Binds a Boolean to whether the wrapped native view should receive keyboard focus.
public struct FluentFocusedView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let binding: FluentBinding<Bool>

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFocusHost(content: content._mount(in: context), binding: binding)
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFocusHost else { return false }
        host.update(binding: binding)
        return content._update(host.contentView, in: context)
    }
}

private final class FluentFocusHost: NSView {
    var binding: FluentBinding<Bool>
    var contentView: NSView { subviews[0] }
    private var observerID: UUID?
    private var windowObservation: NSKeyValueObservation?
    private var isWritingBinding = false

    init(content: NSView, binding: FluentBinding<Bool>) {
        self.binding = binding
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservation()
        DispatchQueue.main.async { [weak self] in self?.syncFocusFromBinding() }
    }

    private func syncFocusFromBinding() {
        guard let window else { return }
        if binding.get() {
            guard !ownsFirstResponder(window.firstResponder),
                  let target = preferredFocusView(in: contentView) else { return }
            window.makeFirstResponder(target)
        } else if ownsFirstResponder(window.firstResponder) {
            window.makeFirstResponder(nil)
        }
    }

    func update(binding: FluentBinding<Bool>) {
        if let observerID { self.binding.removeObserver?(observerID) }
        self.binding = binding
        installObserver()
        syncFocusFromBinding()
    }

    private func installObserver() {
        observerID = binding.observe? { [weak self] _ in
            guard self?.isWritingBinding == false else { return }
            DispatchQueue.main.async { [weak self] in self?.syncFocusFromBinding() }
        }
    }

    private func installWindowObservation() {
        windowObservation?.invalidate()
        windowObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            let isFocused = self.ownsFirstResponder(change.newValue ?? nil)
            guard self.binding.get() != isFocused else { return }
            self.isWritingBinding = true
            self.binding.set(isFocused)
            self.isWritingBinding = false
        }
    }

    private func ownsFirstResponder(_ responder: NSResponder?) -> Bool {
        if let responderView = responder as? NSView,
           responderView === contentView || responderView.isDescendant(of: contentView) {
            return true
        }

        // Text fields use the window's shared field editor as first responder while editing.
        if let textView = responder as? NSTextView,
           let delegateView = textView.delegate as? NSView {
            return delegateView === contentView || delegateView.isDescendant(of: contentView)
        }
        return false
    }

    private func preferredFocusView(in view: NSView) -> NSView? {
        if view.acceptsFirstResponder, !view.isHidden, view.alphaValue > 0 {
            return view
        }
        for subview in view.subviews {
            if let target = preferredFocusView(in: subview) {
                return target
            }
        }
        return nil
    }

    deinit {
        windowObservation?.invalidate()
        if let observerID { binding.removeObserver?(observerID) }
    }
}

public extension FluentView {
    func focused(_ binding: FluentBinding<Bool>) -> FluentFocusedView<Self> {
        FluentFocusedView(content: self, binding: binding)
    }
}

/// Requests focus once when the wrapped view first enters a window. The request is conservative:
/// an existing responder is never displaced, which keeps this modifier safe for restored windows
/// and navigation updates.
public struct FluentInitialFocusView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentInitialFocusHost(content: content._mount(in: context))
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentInitialFocusHost else { return false }
        return content._update(host.contentView, in: context)
    }
}

private final class FluentInitialFocusHost: NSView {
    var contentView: NSView { subviews[0] }
    private var didRequestFocus = false

    init(content: NSView) {
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.requestInitialFocusIfNeeded() }
    }

    private func requestInitialFocusIfNeeded() {
        guard !didRequestFocus, let window else { return }
        // AppKit may temporarily report the content view as first responder while a
        // window is becoming key. Treat that state as unfocused, but never displace a
        // real control or field editor that the user already selected.
        guard window.firstResponder == nil || window.firstResponder === window.contentView else { return }
        guard let target = preferredFocusView(in: contentView), window.makeFirstResponder(target) else { return }
        didRequestFocus = true
    }

    private func preferredFocusView(in view: NSView) -> NSView? {
        if view.acceptsFirstResponder, !view.isHidden, view.alphaValue > 0, (view as? NSControl)?.isEnabled != false {
            return view
        }
        for subview in view.subviews {
            if let target = preferredFocusView(in: subview) { return target }
        }
        return nil
    }
}

/// A focus scope gives its focusable AppKit descendants a deterministic Tab loop. Nested scopes
/// are allowed; each scope owns only the controls mounted below its own content host.
public struct FluentFocusScopeView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFocusScopeHost(content: content._mount(in: context))
        // Configure immediately so programmatic mounts have a deterministic key-view chain
        // even before AppKit performs the first window/layout pass.
        host.configureKeyViewLoop()
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFocusScopeHost else { return false }
        let updated = content._update(host.contentView, in: context)
        host.configureKeyViewLoop()
        return updated
    }
}

private final class FluentFocusScopeHost: NSView, FluentKeyboardFocusCycle {
    var contentView: NSView { subviews[0] }
    private weak var observedWindow: NSWindow?

    init(content: NSView) {
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observedWindow = window
        configureKeyViewLoop()
    }

    override func layout() {
        super.layout()
        configureKeyViewLoop()
    }

    func configureKeyViewLoop() {
        _ = FluentFocusVisibility.isKeyboardInteraction(in: window)
        let focusable = focusableViews(in: contentView)
        guard !focusable.isEmpty else { return }
        for index in focusable.indices {
            focusable[index].nextKeyView = focusable[(index + 1) % focusable.count]
        }
    }

    func moveKeyboardFocus(from view: NSView, backwards: Bool) {
        guard let window else { return }
        FluentFocusVisibility.cycleFocus(focusableViews(in: contentView), from: view, backwards: backwards, in: window)
    }

    private func focusableViews(in view: NSView) -> [NSView] {
        if view.isHidden || view.alphaValue <= 0 { return [] }
        // A nested scope owns its own Tab loop. The parent must not splice its
        // controls into that loop or overwrite the nested scope's responder order.
        if view !== contentView, view is FluentFocusScopeHost { return [] }
        if let control = view as? NSControl, control.acceptsFirstResponder, control.isEnabled {
            return [control]
        }
        if let textView = view as? NSTextView, textView.acceptsFirstResponder, textView.isEditable {
            return [textView]
        }
        let children = (view as? NSStackView)?.arrangedSubviews ?? view.subviews
        return children.flatMap(focusableViews(in:))
    }

    deinit {
        for view in focusableViews(in: contentView) { view.nextKeyView = nil }
        observedWindow = nil
    }
}

public extension FluentView {
    /// Requests one-time initial focus for the first focusable native descendant.
    func fluentInitialFocus() -> FluentInitialFocusView<Self> {
        FluentInitialFocusView(content: self)
    }

    /// Makes the focusable descendants of this view cycle deterministically with Tab/Shift-Tab.
    func fluentFocusScope() -> FluentFocusScopeView<Self> {
        FluentFocusScopeView(content: self)
    }
}
