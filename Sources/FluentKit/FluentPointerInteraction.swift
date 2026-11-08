import AppKit

/// Tracks the window lifetime of an active hover, press or focused control. AppKit need not
/// deliver an exit when a window deactivates or orders out; idle controls can release observation.
final class FluentPointerLifetime {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var visibility: NSKeyValueObservation?
    private let reset: () -> Void

    init(reset: @escaping () -> Void) { self.reset = reset }

    func observe(_ window: NSWindow?) {
        guard self.window !== window else { return }
        invalidate()
        guard let window else { return }
        self.window = window
        // Ordering out a non-key/already-occluded window can omit both resign-key and
        // occlusion notifications. Its public visibility property still changes synchronously.
        visibility = window.observe(\.isVisible) { [weak self] window, _ in
            if !window.isVisible { self?.reset() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willMiniaturizeNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                guard let self else { return }
                if note.name != NSWindow.didChangeOcclusionStateNotification || self.window?.isVisible != true {
                    self.reset()
                }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.willResignActiveNotification,
            object: NSApp, queue: .main) { [weak self] _ in self?.reset() })
    }

    func invalidate() {
        visibility?.invalidate()
        visibility = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        window = nil
    }

    deinit { invalidate() }
}

struct FluentPointerInteractionState: Equatable {
    private(set) var isPointerOver = false
    private(set) var isPressed = false

    @discardableResult
    mutating func setPointerOver(_ value: Bool) -> Bool {
        guard isPointerOver != value else { return false }
        isPointerOver = value
        return true
    }

    @discardableResult
    mutating func setPressed(_ value: Bool) -> Bool {
        guard isPressed != value else { return false }
        isPressed = value
        return true
    }

    @discardableResult
    mutating func reset() -> Bool {
        let changed = isPointerOver || isPressed
        isPointerOver = false
        isPressed = false
        return changed
    }
}

/// Owns one AppKit tracking area for a view and replaces it atomically when geometry changes.
final class FluentTrackingAreaHost {
    private weak var view: NSView?
    private let options: NSTrackingArea.Options
    private var trackingArea: NSTrackingArea?

    init(view: NSView, options: NSTrackingArea.Options) {
        self.view = view
        self.options = options
    }

    func update() {
        guard let view else { return }
        if let trackingArea, view.trackingAreas.contains(where: { $0 === trackingArea }) {
            view.removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: options.contains(.inVisibleRect) ? .zero : view.bounds,
            options: options,
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    func invalidate() {
        guard let view, let trackingArea else { return }
        if view.trackingAreas.contains(where: { $0 === trackingArea }) {
            view.removeTrackingArea(trackingArea)
        }
        self.trackingArea = nil
    }
}

/// Keeps transient pointer-over ownership exclusive within a composite control presenter.
final class FluentHoverCoordinator<Item: AnyObject> {
    private weak var hoveredItem: Item?
    private let apply: (Item, Bool) -> Void

    init(apply: @escaping (Item, Bool) -> Void) {
        self.apply = apply
    }

    var currentItem: Item? { hoveredItem }

    func update(_ item: Item, hovering: Bool) {
        if hovering {
            if hoveredItem !== item { clearCurrent() }
            hoveredItem = item
            apply(item, true)
        } else if hoveredItem === item {
            clearCurrent()
        } else {
            apply(item, false)
        }
    }

    func remove(_ item: Item) {
        if hoveredItem === item {
            clearCurrent()
        } else {
            apply(item, false)
        }
    }

    func reset<S: Sequence>(items: S) where S.Element == Item {
        let previous = hoveredItem
        clearCurrent()
        for item in items where item !== previous {
            apply(item, false)
        }
    }

    func reset() {
        clearCurrent()
    }

    private func clearCurrent() {
        guard let hoveredItem else { return }
        self.hoveredItem = nil
        apply(hoveredItem, false)
    }
}
