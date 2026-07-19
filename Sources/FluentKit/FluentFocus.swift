import AppKit

/// Binds a Boolean to whether the wrapped native view should receive keyboard focus.
public struct FluentFocusedView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let binding: FluentBinding<Bool>

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFocusHost(content: content._mount(in: context), binding: binding)
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFocusHost else { return false }
        host.update(binding: binding)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentFocusHost: NSView {
    var binding: FluentBinding<Bool>
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
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
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentInitialFocusHost else { return false }
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentInitialFocusHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
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
        host.updateContent = { [content] nativeView, updateContext in
            let updated = content._update(nativeView, in: updateContext)
            host.configureKeyViewLoop()
            return updated
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFocusScopeHost else { return false }
        let updated = host.updateContent?(host.contentView, context) ?? false
        host.configureKeyViewLoop()
        return updated
    }
}

private final class FluentFocusScopeHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
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
        let focusable = focusableViews(in: contentView)
        guard !focusable.isEmpty else { return }
        for index in focusable.indices {
            focusable[index].nextKeyView = focusable[(index + 1) % focusable.count]
        }
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
        return view.subviews.flatMap(focusableViews(in:))
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
