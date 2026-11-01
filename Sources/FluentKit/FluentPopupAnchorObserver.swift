import AppKit

/// Keeps an open popup tied to its original target/window. The attachment view gives
/// arbitrary NSView targets lifecycle callbacks without swizzling or polling.
final class FluentPopupAnchorObserver {
    private weak var anchor: NSView?
    private weak var ownerWindow: NSWindow?
    private let attachment = FluentPopupAnchorAttachment()
    private var geometryTokens: [NSObjectProtocol] = []
    private var windowToken: NSObjectProtocol?
    private var ancestorIDs: [ObjectIdentifier] = []
    private var updatePending = false
    private var onChange: (() -> Void)?
    private var onUnavailable: (() -> Void)?

    init(anchor: NSView, onChange: @escaping () -> Void, onUnavailable: @escaping () -> Void) {
        self.anchor = anchor
        ownerWindow = anchor.window
        self.onChange = onChange
        self.onUnavailable = onUnavailable
        anchor.addSubview(attachment)
        observeAncestors()
        attachment.onChange = { [weak self] in self?.scheduleUpdate() }
        if let window = ownerWindow {
            windowToken = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { [weak self] _ in self?.onUnavailable?() }
        }
    }

    private func observeAncestors() {
        var ancestors: [NSView] = []
        var current = anchor
        while let view = current { ancestors.append(view); current = view.superview }
        let ids = ancestors.map(ObjectIdentifier.init)
        guard ids != ancestorIDs else { return }
        geometryTokens.forEach(NotificationCenter.default.removeObserver)
        geometryTokens.removeAll()
        ancestorIDs = ids
        for view in ancestors {
            // Leave client notification flags unchanged, as in AutoSuggestBox's observer.
            for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                geometryTokens.append(NotificationCenter.default.addObserver(forName: name,
                    object: view, queue: .main) { [weak self] _ in self?.scheduleUpdate() })
            }
        }
    }

    private func scheduleUpdate() {
        guard !updatePending, onChange != nil else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.updatePending = false }
            // Layout may be in flight when a frame notification is sent. Also allow
            // AppKit's same-turn reattachment (e.g. titlebar appearance updates) to settle.
            self.ownerWindow?.contentView?.layoutSubtreeIfNeeded()
            guard let anchor = self.anchor, let window = self.ownerWindow,
                  anchor.window === window, window.isVisible,
                  !anchor.isHiddenOrHasHiddenAncestor,
                  anchor.bounds.isEmpty || (anchor.visibleRect.intersects(anchor.bounds)
                    && !self.isOutsideViewport(anchor, window: window)) else {
                self.onUnavailable?()
                return
            }
            // A client may reconcile the target's subviews; restore only our zero-sized probe.
            if self.attachment.superview !== anchor { anchor.addSubview(self.attachment) }
            self.observeAncestors()
            self.onChange?()
        }
    }

    private func isOutsideViewport(_ anchor: NSView, window: NSWindow) -> Bool {
        // A layer-backed view can keep its previous visibleRect until display. Clip
        // bounds and coordinate conversion already reflect the current scroll offset.
        var current = anchor.superview
        while let view = current {
            if (view is NSClipView || view === window.contentView),
               !anchor.convert(anchor.bounds, to: view).intersects(view.bounds) { return true }
            current = view.superview
        }
        return false
    }

    func invalidate() {
        onChange = nil
        onUnavailable = nil
        attachment.onChange = nil
        attachment.removeFromSuperview()
        geometryTokens.forEach(NotificationCenter.default.removeObserver)
        geometryTokens.removeAll()
        if let windowToken { NotificationCenter.default.removeObserver(windowToken) }
        windowToken = nil
        anchor = nil
        ownerWindow = nil
    }

    deinit { invalidate() }
}

private final class FluentPopupAnchorAttachment: NSView {
    var onChange: (() -> Void)?
    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Popup.AnchorObserver")
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onChange?() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); onChange?() }
    override func viewDidHide() { super.viewDidHide(); onChange?() }
}
