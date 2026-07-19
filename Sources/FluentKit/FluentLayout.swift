import AppKit

public struct FluentZStackView: FluentUpdatablePrimitiveView {
    fileprivate let content: FluentAnyView

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentZStackContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        let children = content.children?.map { $0.mount(context) } ?? [content.mount(context)]
        for child in children {
            container.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                child.topAnchor.constraint(equalTo: container.topAnchor),
                child.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentZStackContainer,
              let children = content.children,
              container.subviews.count == children.count else { return false }
        for index in children.indices {
            if !children[index]._update(container.subviews[index], in: context) {
                return false
            }
        }
        return true
    }
}

private final class FluentZStackContainer: NSView {}

public func FluentZStack(@FluentViewBuilder content: () -> FluentAnyView) -> FluentZStackView {
    FluentZStackView(content: content())
}

public struct FluentPaddingView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let insets: NSEdgeInsets

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentLayoutContainer()
        let child = content._mount(in: context)
        container.setChild(child, insets: insets)
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentLayoutContainer,
              let child = container.subviews.first else { return false }
        container.updateInsets(insets)
        return content._update(child, in: context)
    }
}

public struct FluentFrameView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let width: CGFloat?
    fileprivate let height: CGFloat?

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentLayoutContainer()
        let child = content._mount(in: context)
        container.setChild(child, insets: NSEdgeInsetsZero)
        container.updateSize(width: width, height: height)
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentLayoutContainer,
              let child = container.subviews.first else { return false }
        container.updateSize(width: width, height: height)
        return content._update(child, in: context)
    }
}

public struct FluentBackgroundView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let color: NSColor
    fileprivate let cornerRadius: CGFloat

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentLayoutContainer()
        let child = content._mount(in: context)
        container.setChild(child, insets: NSEdgeInsetsZero)
        container.wantsLayer = true
        container.layer?.backgroundColor = color.cgColor
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentLayoutContainer,
              let child = container.subviews.first else { return false }
        container.updateBackground(color: color, cornerRadius: cornerRadius)
        return content._update(child, in: context)
    }
}

public struct FluentOpacityView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let opacity: CGFloat

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentLayoutContainer()
        container.setChild(content._mount(in: context), insets: NSEdgeInsetsZero)
        container.updateOpacity(opacity)
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentLayoutContainer,
              let child = container.subviews.first else { return false }
        container.updateOpacity(opacity)
        return content._update(child, in: context)
    }
}

/// Applies a visual affine transform without changing the view's layout footprint.
public struct FluentTransformView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let transform: CGAffineTransform

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentTransformContainer()
        container.setChild(content._mount(in: context), insets: NSEdgeInsetsZero)
        container.updateTransform(transform)
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentTransformContainer,
              let child = container.subviews.first else { return false }
        container.updateTransform(transform)
        return content._update(child, in: context)
    }
}

public struct FluentDisabledView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let disabled: Bool

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let container = FluentDisabledContainer()
        container.setChild(content._mount(in: context), insets: NSEdgeInsetsZero)
        container.applyDisabled(disabled)
        return container
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let container = view as? FluentDisabledContainer,
              let child = container.subviews.first else { return false }
        let updated = content._update(child, in: context)
        container.applyDisabled(disabled)
        return updated
    }
}

private class FluentLayoutContainer: NSView {
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?
    private var top: NSLayoutConstraint?
    private var bottom: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    func setChild(_ child: NSView, insets: NSEdgeInsets) {
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        updateInsets(insets)
    }

    func updateInsets(_ insets: NSEdgeInsets) {
        if let leading { leading.isActive = false }
        if let trailing { trailing.isActive = false }
        if let top { top.isActive = false }
        if let bottom { bottom.isActive = false }
        guard let child = subviews.first else { return }
        leading = child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left)
        trailing = child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right)
        top = child.topAnchor.constraint(equalTo: topAnchor, constant: insets.top)
        bottom = child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        NSLayoutConstraint.activate([leading!, trailing!, top!, bottom!])
    }

    func updateBackground(color: NSColor, cornerRadius: CGFloat) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }

    func updateOpacity(_ opacity: CGFloat) {
        alphaValue = min(max(opacity, 0), 1)
    }

    func updateSize(width: CGFloat?, height: CGFloat?) {
        widthConstraint?.isActive = false
        heightConstraint?.isActive = false
        widthConstraint = width.map { widthAnchor.constraint(equalToConstant: $0) }
        heightConstraint = height.map { heightAnchor.constraint(equalToConstant: $0) }
        if let widthConstraint { widthConstraint.isActive = true }
        if let heightConstraint { heightConstraint.isActive = true }
    }
}

private final class FluentTransformContainer: FluentLayoutContainer {
    func updateTransform(_ transform: CGAffineTransform) {
        wantsLayer = true
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.setAffineTransform(transform)
    }
}

private final class FluentDisabledContainer: FluentLayoutContainer {
    private var previousEnabled: [ObjectIdentifier: Bool] = [:]
    private var isDisabled = false

    func applyDisabled(_ disabled: Bool) {
        guard disabled != isDisabled else {
            if disabled { subviews.forEach { enforceDisabled($0) } }
            return
        }
        if disabled {
            previousEnabled.removeAll(keepingCapacity: true)
            subviews.forEach { snapshotAndDisable($0) }
        } else {
            subviews.forEach { restoreEnabled($0) }
            previousEnabled.removeAll(keepingCapacity: true)
        }
        isDisabled = disabled
    }

    private func snapshotAndDisable(_ view: NSView) {
        if let control = view as? NSControl {
            previousEnabled[ObjectIdentifier(control)] = control.isEnabled
            control.isEnabled = false
        }
        view.subviews.forEach { snapshotAndDisable($0) }
    }

    private func restoreEnabled(_ view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = previousEnabled[ObjectIdentifier(control)] ?? control.isEnabled
        }
        view.subviews.forEach { restoreEnabled($0) }
    }

    private func enforceDisabled(_ view: NSView) {
        if let control = view as? NSControl { control.isEnabled = false }
        view.subviews.forEach { enforceDisabled($0) }
    }
}

public extension FluentView {
    func padding(_ value: CGFloat = 8) -> FluentPaddingView<Self> {
        FluentPaddingView(content: self, insets: NSEdgeInsets(top: value, left: value, bottom: value, right: value))
    }

    func padding(_ insets: NSEdgeInsets) -> FluentPaddingView<Self> {
        FluentPaddingView(content: self, insets: insets)
    }

    func frame(width: CGFloat? = nil, height: CGFloat? = nil) -> FluentFrameView<Self> {
        FluentFrameView(content: self, width: width, height: height)
    }

    func background(_ color: NSColor, cornerRadius: CGFloat = 0) -> FluentBackgroundView<Self> {
        FluentBackgroundView(content: self, color: color, cornerRadius: cornerRadius)
    }

    func opacity(_ value: CGFloat) -> FluentOpacityView<Self> {
        FluentOpacityView(content: self, opacity: min(max(value, 0), 1))
    }

    func transformEffect(_ transform: CGAffineTransform) -> FluentTransformView<Self> {
        FluentTransformView(content: self, transform: transform)
    }

    /// Translates the rendered content without changing the space it occupies during layout.
    func offset(x: CGFloat = 0, y: CGFloat = 0) -> FluentTransformView<Self> {
        transformEffect(CGAffineTransform(translationX: x, y: y))
    }

    /// Scales the rendered content around its center without changing its layout footprint.
    func scaleEffect(_ scale: CGFloat) -> FluentTransformView<Self> {
        transformEffect(CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Rotates the rendered content around its center by an angle expressed in radians.
    func rotationEffect(_ radians: CGFloat) -> FluentTransformView<Self> {
        transformEffect(CGAffineTransform(rotationAngle: radians))
    }

    func disabled(_ value: Bool = true) -> FluentDisabledView<Self> {
        FluentDisabledView(content: self, disabled: value)
    }
}
