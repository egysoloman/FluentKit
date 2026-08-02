import AppKit

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
