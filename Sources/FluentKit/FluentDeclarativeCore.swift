import AppKit
import ObjectiveC

/// A value that describes a native AppKit view tree. Views are lightweight values; their body is
/// resolved whenever the host refreshes the tree.
public protocol FluentView {
    associatedtype Body: FluentView
    @FluentViewBuilder var body: Body { get }
    func _update(_ nativeView: NSView, in context: FluentRenderContext) -> Bool
}

public extension FluentView where Body == NeverFluentView {
    var body: NeverFluentView { NeverFluentView() }
}

/// A leaf marker used by primitive views that render themselves directly.
public struct NeverFluentView: FluentPrimitiveView {
    public init() {}
    public var body: NeverFluentView { self }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        NSView()
    }
}

/// Type erasure for building heterogeneous declarative view trees.
public struct FluentAnyView: FluentUpdatablePrimitiveView {
    let mount: (FluentRenderContext) -> NSView
    let update: (NSView, FluentRenderContext) -> Bool
    let children: [FluentAnyView]?

    public init<V: FluentView>(_ view: V) {
        if let erased = view as? FluentAnyView {
            mount = erased.mount
            update = erased.update
            children = erased.children
        } else {
            mount = { context in view._mount(in: context) }
            update = { nativeView, context in view._update(nativeView, in: context) }
            children = (view as? FluentTupleView)?.children
        }
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        mount(context)
    }

    public func _updateView(_ nativeView: NSView, in context: FluentRenderContext) -> Bool {
        update(nativeView, context)
    }
}

@resultBuilder
public enum FluentViewBuilder {
    public static func buildPartialBlock<First: FluentView>(first: First) -> First { first }

    public static func buildPartialBlock<Accumulated: FluentView, Next: FluentView>(
        accumulated: Accumulated,
        next: Next
    ) -> FluentAnyView {
        let accumulatedView = FluentAnyView(accumulated)
        let nextView = FluentAnyView(next)
        let children = (accumulatedView.children ?? [accumulatedView]) + (nextView.children ?? [nextView])
        return FluentAnyView(FluentTupleView(children))
    }

    public static func buildBlock() -> FluentAnyView { FluentAnyView(FluentEmptyView()) }

    public static func buildBlock<V: FluentView>(_ component: V) -> V {
        component
    }

    public static func buildBlock<V0: FluentView, V1: FluentView>(_ v0: V0, _ v1: V1) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView, V6: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5), FluentAnyView(v6)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView, V6: FluentView, V7: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5), FluentAnyView(v6), FluentAnyView(v7)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView, V6: FluentView, V7: FluentView, V8: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7, _ v8: V8) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5), FluentAnyView(v6), FluentAnyView(v7), FluentAnyView(v8)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView, V6: FluentView, V7: FluentView, V8: FluentView, V9: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7, _ v8: V8, _ v9: V9) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5), FluentAnyView(v6), FluentAnyView(v7), FluentAnyView(v8), FluentAnyView(v9)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView, V6: FluentView, V7: FluentView, V8: FluentView, V9: FluentView, V10: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7, _ v8: V8, _ v9: V9, _ v10: V10) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5), FluentAnyView(v6), FluentAnyView(v7), FluentAnyView(v8), FluentAnyView(v9), FluentAnyView(v10)]))
    }

    public static func buildBlock<V0: FluentView, V1: FluentView, V2: FluentView, V3: FluentView, V4: FluentView, V5: FluentView, V6: FluentView, V7: FluentView, V8: FluentView, V9: FluentView, V10: FluentView, V11: FluentView>(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5, _ v6: V6, _ v7: V7, _ v8: V8, _ v9: V9, _ v10: V10, _ v11: V11) -> FluentAnyView {
        FluentAnyView(FluentTupleView([FluentAnyView(v0), FluentAnyView(v1), FluentAnyView(v2), FluentAnyView(v3), FluentAnyView(v4), FluentAnyView(v5), FluentAnyView(v6), FluentAnyView(v7), FluentAnyView(v8), FluentAnyView(v9), FluentAnyView(v10), FluentAnyView(v11)]))
    }

    public static func buildOptional<V: FluentView>(_ component: V?) -> FluentAnyView {
        component.map(FluentAnyView.init) ?? FluentAnyView(FluentEmptyView())
    }

    public static func buildEither<TrueContent: FluentView>(first component: TrueContent) -> FluentAnyView {
        FluentAnyView(component)
    }

    public static func buildEither<FalseContent: FluentView>(second component: FalseContent) -> FluentAnyView {
        FluentAnyView(component)
    }

    public static func buildArray<V: FluentView>(_ components: [V]) -> FluentAnyView {
        FluentAnyView(FluentTupleView(components.map(FluentAnyView.init)))
    }
}

public struct FluentEmptyView: FluentUpdatablePrimitiveView {
    public init() {}
    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        type(of: view) == NSView.self
    }
}

public struct FluentTupleView: FluentView {
    fileprivate let children: [FluentAnyView]

    fileprivate init(_ children: [FluentAnyView]) { self.children = children }

    public var body: NeverFluentView { NeverFluentView() }

    func _mount(in context: FluentRenderContext) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = context.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        children.map { $0.mount(context) }.forEach(stack.addArrangedSubview)
        return stack
    }

    public func _update(_ nativeView: NSView, in context: FluentRenderContext) -> Bool {
        guard let stack = nativeView as? NSStackView,
              stack.arrangedSubviews.count == children.count else { return false }
        for index in children.indices {
            let child = children[index]
            let nativeChild = stack.arrangedSubviews[index]
            if !child._update(nativeChild, in: context) {
                let replacement = child.mount(context)
                stack.removeArrangedSubview(nativeChild)
                nativeChild.removeFromSuperview()
                stack.insertArrangedSubview(replacement, at: index)
            }
        }
        stack.spacing = context.spacing
        return true
    }
}

public struct FluentVStackView: FluentPrimitiveView {
    fileprivate let spacing: CGFloat
    fileprivate let alignment: NSLayoutConstraint.Attribute
    fileprivate let content: FluentAnyView

    fileprivate init(spacing: CGFloat, alignment: NSLayoutConstraint.Attribute, content: FluentAnyView) {
        self.spacing = spacing
        self.alignment = alignment
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let views = content.children?.map { $0.mount(context) } ?? [content.mount(context)]
        views.forEach(stack.addArrangedSubview)
        return stack
    }

    public func _update(_ nativeView: NSView, in context: FluentRenderContext) -> Bool {
        guard let stack = nativeView as? NSStackView,
              let children = Optional(content.children ?? [content]),
              stack.arrangedSubviews.count == children.count else { return false }
        stack.spacing = spacing
        stack.alignment = alignment
        for index in children.indices {
            let child = children[index]
            let nativeChild = stack.arrangedSubviews[index]
            if !child._update(nativeChild, in: context) {
                let replacement = child.mount(context)
                stack.removeArrangedSubview(nativeChild)
                nativeChild.removeFromSuperview()
                stack.insertArrangedSubview(replacement, at: index)
            }
        }
        return true
    }
}

public func FluentVStack(spacing: CGFloat = 12, alignment: NSLayoutConstraint.Attribute = .leading, @FluentViewBuilder content: () -> FluentAnyView) -> FluentVStackView {
    FluentVStackView(spacing: spacing, alignment: alignment, content: content())
}

public struct FluentHStackView: FluentPrimitiveView {
    fileprivate let spacing: CGFloat
    fileprivate let alignment: NSLayoutConstraint.Attribute
    fileprivate let content: FluentAnyView

    fileprivate init(spacing: CGFloat, alignment: NSLayoutConstraint.Attribute, content: FluentAnyView) {
        self.spacing = spacing
        self.alignment = alignment
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = alignment
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let views = content.children?.map { $0.mount(context) } ?? [content.mount(context)]
        views.forEach(stack.addArrangedSubview)
        return stack
    }

    public func _update(_ nativeView: NSView, in context: FluentRenderContext) -> Bool {
        guard let stack = nativeView as? NSStackView,
              let children = Optional(content.children ?? [content]),
              stack.arrangedSubviews.count == children.count else { return false }
        stack.spacing = spacing
        stack.alignment = alignment
        for index in children.indices {
            let child = children[index]
            let nativeChild = stack.arrangedSubviews[index]
            if !child._update(nativeChild, in: context) {
                let replacement = child.mount(context)
                stack.removeArrangedSubview(nativeChild)
                nativeChild.removeFromSuperview()
                stack.insertArrangedSubview(replacement, at: index)
            }
        }
        return true
    }
}

public func FluentHStack(spacing: CGFloat = 12, alignment: NSLayoutConstraint.Attribute = .centerY, @FluentViewBuilder content: () -> FluentAnyView) -> FluentHStackView {
    FluentHStackView(spacing: spacing, alignment: alignment, content: content())
}

public struct FluentNativeView: FluentPrimitiveView {
    private let make: () -> NSView

    public init(_ view: @autoclosure @escaping () -> NSView) {
        make = view
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = make()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

public struct FluentEnvironmentView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let theme: FluentTheme?
    fileprivate let spacing: CGFloat?
    fileprivate let animationDuration: TimeInterval?
    fileprivate let animationTimingFunction: CAMediaTimingFunction?
    fileprivate let reduceMotion: Bool?
    fileprivate let layoutDirection: FluentLayoutDirection?
    fileprivate let locale: Locale?
    fileprivate let localizationBundle: Bundle?

    fileprivate init(
        content: Content,
        theme: FluentTheme?,
        spacing: CGFloat?,
        animationDuration: TimeInterval?,
        animationTimingFunction: CAMediaTimingFunction?,
        reduceMotion: Bool?,
        layoutDirection: FluentLayoutDirection? = nil,
        locale: Locale? = nil,
        localizationBundle: Bundle? = nil
    ) {
        self.content = content
        self.theme = theme
        self.spacing = spacing
        self.animationDuration = animationDuration
        self.animationTimingFunction = animationTimingFunction
        self.reduceMotion = reduceMotion
        self.layoutDirection = layoutDirection
        self.locale = locale
        self.localizationBundle = localizationBundle
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        var nested = context
        if let theme { nested.theme = theme }
        if let spacing { nested.spacing = spacing }
        if let animationDuration { nested.animationDuration = animationDuration }
        if let animationTimingFunction { nested.animationTimingFunction = animationTimingFunction }
        if let reduceMotion { nested.reduceMotion = reduceMotion }
        if let layoutDirection { nested.layoutDirection = layoutDirection }
        if let locale { nested.locale = locale }
        if let localizationBundle { nested.localizationBundle = localizationBundle }
        let view = content._mount(in: nested)
        if layoutDirection != nil { view.fluentApplyLayoutDirection(nested.layoutDirection, establishesOverride: true) }
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        var nested = context
        if let theme { nested.theme = theme }
        if let spacing { nested.spacing = spacing }
        if let animationDuration { nested.animationDuration = animationDuration }
        if let animationTimingFunction { nested.animationTimingFunction = animationTimingFunction }
        if let reduceMotion { nested.reduceMotion = reduceMotion }
        if let layoutDirection { nested.layoutDirection = layoutDirection }
        if let locale { nested.locale = locale }
        if let localizationBundle { nested.localizationBundle = localizationBundle }
        let updated = content._update(view, in: nested)
        if updated, layoutDirection != nil {
            view.fluentApplyLayoutDirection(nested.layoutDirection, establishesOverride: true)
        }
        return updated
    }
}

/// Applies semantic theme metrics to a subtree while preserving its existing accent, material,
/// and unrelated environment values.
public struct FluentThemeVariantView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let density: FluentThemeDensity?
    fileprivate let contrast: FluentThemeContrast?
    fileprivate let colorScheme: FluentThemeColorScheme?

    public var body: NeverFluentView { NeverFluentView() }

    private func nestedContext(_ context: FluentRenderContext) -> FluentRenderContext {
        var nested = context
        if let density { nested.theme = nested.theme.with(density: density) }
        if let contrast { nested.theme = nested.theme.with(contrast: contrast) }
        if let colorScheme { nested.theme = nested.theme.with(colorScheme: colorScheme) }
        return nested
    }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        content._mount(in: nestedContext(context))
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        content._update(view, in: nestedContext(context))
    }
}

/// Reads an observable application theme during each render pass.
public struct FluentThemeStoreView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let store: FluentThemeStore

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        var nested = context
        nested.theme = store.theme
        return content._mount(in: nested)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        var nested = context
        nested.theme = store.theme
        return content._update(view, in: nested)
    }
}

public extension FluentView {
    func fluentTheme(_ theme: FluentTheme) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: theme, spacing: nil, animationDuration: nil, animationTimingFunction: nil, reduceMotion: nil)
    }

    /// Inherits an observable application theme and refreshes this subtree when it changes.
    func fluentTheme(_ store: FluentThemeStore) -> FluentThemeStoreView<Self> {
        FluentThemeStoreView(content: self, store: store)
    }

    func fluentSpacing(_ spacing: CGFloat) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: spacing, animationDuration: nil, animationTimingFunction: nil, reduceMotion: nil)
    }

    func fluentAnimationDuration(_ duration: TimeInterval) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: nil, animationDuration: duration, animationTimingFunction: nil, reduceMotion: nil)
    }

    func fluentAnimationTimingFunction(_ timingFunction: CAMediaTimingFunction) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: nil, animationDuration: nil, animationTimingFunction: timingFunction, reduceMotion: nil)
    }

    /// Overrides the inherited motion preference for a view subtree. When enabled, transitions
    /// and implicit animations resolve to an immediate update while preserving their final state.
    func fluentReduceMotion(_ enabled: Bool) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: nil, animationDuration: nil, animationTimingFunction: nil, reduceMotion: enabled)
    }

    /// Applies a left-to-right, right-to-left, or system-derived direction to a subtree.
    func fluentLayoutDirection(_ direction: FluentLayoutDirection) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: nil, animationDuration: nil, animationTimingFunction: nil, reduceMotion: nil, layoutDirection: direction)
    }

    /// Overrides the locale used by localized Fluent content in this subtree.
    func fluentLocale(_ locale: Locale) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: nil, animationDuration: nil, animationTimingFunction: nil, reduceMotion: nil, locale: locale)
    }

    /// Selects the bundle used to resolve localized Fluent resources in this subtree.
    func fluentLocalizationBundle(_ bundle: Bundle) -> FluentEnvironmentView<Self> {
        FluentEnvironmentView(content: self, theme: nil, spacing: nil, animationDuration: nil, animationTimingFunction: nil, reduceMotion: nil, localizationBundle: bundle)
    }

    /// Applies a density variant to the current theme for a view subtree.
    func fluentDensity(_ density: FluentThemeDensity) -> FluentThemeVariantView<Self> {
        FluentThemeVariantView(content: self, density: density, contrast: nil, colorScheme: nil)
    }

    /// Applies a contrast variant to the current theme for a view subtree.
    func fluentContrast(_ contrast: FluentThemeContrast) -> FluentThemeVariantView<Self> {
        FluentThemeVariantView(content: self, density: nil, contrast: contrast, colorScheme: nil)
    }

    /// Applies a light, dark, or system-derived color scheme to a view subtree.
    func fluentColorScheme(_ colorScheme: FluentThemeColorScheme) -> FluentThemeVariantView<Self> {
        FluentThemeVariantView(content: self, density: nil, contrast: nil, colorScheme: colorScheme)
    }

    /// Gives a branch an explicit identity. When the identity changes, the renderer replaces only
    /// that branch, preserving unrelated native controls around it.
    func fluentID<ID: Hashable>(_ id: ID) -> FluentIDView<Self> {
        FluentIDView(content: self, id: AnyHashable(id))
    }
}

public struct FluentIDView<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let id: AnyHashable

    fileprivate init(content: Content, id: AnyHashable) {
        self.content = content
        self.id = id
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        view.fluentIdentity = id
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let previous = view.fluentIdentity else { return content._update(view, in: context) }
        guard previous == id else { return false }
        return content._update(view, in: context)
    }
}

private var fluentIdentityKey: UInt8 = 0

private extension NSView {
    var fluentIdentity: AnyHashable? {
        get { objc_getAssociatedObject(self, &fluentIdentityKey) as? AnyHashable }
        set { objc_setAssociatedObject(self, &fluentIdentityKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

public struct FluentRenderContext {
    public var theme: FluentTheme
    public var spacing: CGFloat
    public var invalidate: (() -> Void)?
    public var animationDuration: TimeInterval
    public var animationTimingFunction: CAMediaTimingFunction
    public var reduceMotion: Bool
    public var undoCoordinator: FluentUndoCoordinator?
    public var layoutDirection: FluentLayoutDirection
    public var locale: Locale
    public var localizationBundle: Bundle

    public init(theme: FluentTheme = .current, spacing: CGFloat = 12, animationDuration: TimeInterval = FluentAnimation.content, animationTimingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut), reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, undoCoordinator: FluentUndoCoordinator? = nil, layoutDirection: FluentLayoutDirection = .system, locale: Locale = .current, localizationBundle: Bundle = .main, invalidate: (() -> Void)? = nil) {
        self.theme = theme
        self.spacing = spacing
        self.animationDuration = animationDuration
        self.animationTimingFunction = animationTimingFunction
        self.reduceMotion = reduceMotion
        self.undoCoordinator = undoCoordinator
        self.layoutDirection = layoutDirection
        self.locale = locale
        self.localizationBundle = localizationBundle
        self.invalidate = invalidate
    }
}

public extension FluentView {
    func _mount(in context: FluentRenderContext) -> NSView {
        if let primitive = self as? any FluentPrimitiveView {
            return primitive._makeView(in: context)
        }
        return body._mount(in: context)
    }

    /// Updates a previously mounted native view when the declarative shape is compatible.
    /// Returning false tells the host to rebuild that branch.
    func _update(_ nativeView: NSView, in context: FluentRenderContext) -> Bool {
        if let primitive = self as? any FluentUpdatablePrimitiveView {
            return primitive._updateView(nativeView, in: context)
        }
        if self is any FluentPrimitiveView {
            return false
        }
        return body._update(nativeView, in: context)
    }
}

public protocol FluentPrimitiveView: FluentView {
    func _makeView(in context: FluentRenderContext) -> NSView
}

public protocol FluentUpdatablePrimitiveView: FluentPrimitiveView {
    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool
}

/// Hosts a declarative Fluent view inside an AppKit view hierarchy. Calling `update` replaces the
/// rendered tree while retaining the native window and responder chain.
public final class FluentViewHost<Content: FluentView>: NSView {
    public private(set) var content: Content
    public var context: FluentRenderContext {
        didSet {
            userInterfaceLayoutDirection = context.layoutDirection.appKitValue
            update(content)
        }
    }

    private var mountedView: NSView?
    private var isRendering = false
    private var refreshScheduled = false
    private var dependencyCancellations: [ObjectIdentifier: () -> Void] = [:]

    /// Forward a mounted leaf's natural size when the host is used as an AppKit custom view,
    /// such as an NSToolbarItem. Container roots can still opt out by returning no intrinsic size.
    public override var intrinsicContentSize: NSSize {
        mountedView?.intrinsicContentSize ?? NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public init(_ content: Content, context: FluentRenderContext = .init()) {
        self.content = content
        self.context = context
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        mount(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(_ content: Content) {
        self.content = content
        refresh(content)
    }

    private func mount(_ content: Content) {
        guard !isRendering else {
            requestRefresh()
            return
        }
        isRendering = true
        defer { isRendering = false }
        mountedView?.removeFromSuperview()
        let (view, dependencies) = FluentDependencyTracking.collect { [self] in
            var renderContext = context
            renderContext.invalidate = { [weak self] in self?.requestRefresh() }
            return content._mount(in: renderContext)
        }
        updateDependencies(dependencies)
        view.fluentApplyLayoutDirection(context.layoutDirection)
        mountedView = view
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        invalidateIntrinsicContentSize()
    }

    private func refresh(_ content: Content) {
        guard !isRendering else {
            requestRefresh()
            return
        }
        isRendering = true
        let (didUpdate, dependencies) = FluentDependencyTracking.collect { [self] in
            var renderContext = context
            renderContext.invalidate = { [weak self] in self?.requestRefresh() }
            guard let mountedView else { return false }
            return content._update(mountedView, in: renderContext)
        }
        isRendering = false

        guard didUpdate else {
            mount(content)
            return
        }
        mountedView?.fluentApplyLayoutDirection(context.layoutDirection)
        updateDependencies(dependencies)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func requestRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh(self.content)
        }
    }

    private func updateDependencies(_ dependencies: [ObjectIdentifier: FluentTrackedDependency]) {
        for id in Array(dependencyCancellations.keys) where dependencies[id] == nil {
            dependencyCancellations.removeValue(forKey: id)?()
        }
        for (id, dependency) in dependencies where dependencyCancellations[id] == nil {
            dependencyCancellations[id] = dependency.subscribe { [weak self] in
                self?.requestRefresh()
            }
        }
    }

    deinit {
        dependencyCancellations.values.forEach { $0() }
    }
}

public struct FluentTextView: FluentUpdatablePrimitiveView {
    public let value: String
    public let size: CGFloat
    public let weight: NSFont.Weight
    public let color: NSColor?
    public let textStyle: FluentTextStyle?

    public init(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, color: NSColor? = nil) {
        self.value = value
        self.size = size
        self.weight = weight
        self.color = color
        textStyle = nil
    }

    public init(_ value: String, style: FluentTextStyle, color: NSColor? = nil) {
        self.value = value
        size = 0
        weight = .regular
        self.color = color
        textStyle = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let label = NSTextField(labelWithString: value)
        label.font = resolvedFont(in: context)
        label.textColor = color ?? context.theme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let label = view as? NSTextField else { return false }
        label.stringValue = value
        label.font = resolvedFont(in: context)
        label.textColor = color ?? context.theme.textPrimary
        return true
    }

    private func resolvedFont(in context: FluentRenderContext) -> NSFont {
        textStyle.map { context.theme.typography.font(for: $0) }
            ?? .systemFont(ofSize: size, weight: weight)
    }
}

public func FluentText(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, color: NSColor? = nil) -> FluentTextView {
    FluentTextView(value, size: size, weight: weight, color: color)
}

public func FluentText(_ value: String, style: FluentTextStyle, color: NSColor? = nil) -> FluentTextView {
    FluentTextView(value, style: style, color: color)
}
