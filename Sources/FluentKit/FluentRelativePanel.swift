import AppKit

/// The complete set of `RelativePanel` attached properties carried by a declarative child.
///
/// Sibling references use names, matching the `ElementName`-based syntax of WinUI. The host
/// resolves each name against `relativePanelName(_:)` before layout so the value can flow
/// through `FluentAnyView` without a second type-erased wrapper.
public struct FluentRelativePanelConstraints: Equatable, Sendable {
    public var leftOf: String?
    public var above: String?
    public var rightOf: String?
    public var below: String?
    public var alignLeftWith: String?
    public var alignTopWith: String?
    public var alignRightWith: String?
    public var alignBottomWith: String?
    public var alignHorizontalCenterWith: String?
    public var alignVerticalCenterWith: String?
    public var alignLeftWithPanel: Bool
    public var alignTopWithPanel: Bool
    public var alignRightWithPanel: Bool
    public var alignBottomWithPanel: Bool
    public var alignHorizontalCenterWithPanel: Bool
    public var alignVerticalCenterWithPanel: Bool

    public init(
        leftOf: String? = nil,
        above: String? = nil,
        rightOf: String? = nil,
        below: String? = nil,
        alignLeftWith: String? = nil,
        alignTopWith: String? = nil,
        alignRightWith: String? = nil,
        alignBottomWith: String? = nil,
        alignHorizontalCenterWith: String? = nil,
        alignVerticalCenterWith: String? = nil,
        alignLeftWithPanel: Bool = false,
        alignTopWithPanel: Bool = false,
        alignRightWithPanel: Bool = false,
        alignBottomWithPanel: Bool = false,
        alignHorizontalCenterWithPanel: Bool = false,
        alignVerticalCenterWithPanel: Bool = false
    ) {
        self.leftOf = leftOf
        self.above = above
        self.rightOf = rightOf
        self.below = below
        self.alignLeftWith = alignLeftWith
        self.alignTopWith = alignTopWith
        self.alignRightWith = alignRightWith
        self.alignBottomWith = alignBottomWith
        self.alignHorizontalCenterWith = alignHorizontalCenterWith
        self.alignVerticalCenterWith = alignVerticalCenterWith
        self.alignLeftWithPanel = alignLeftWithPanel
        self.alignTopWithPanel = alignTopWithPanel
        self.alignRightWithPanel = alignRightWithPanel
        self.alignBottomWithPanel = alignBottomWithPanel
        self.alignHorizontalCenterWithPanel = alignHorizontalCenterWithPanel
        self.alignVerticalCenterWithPanel = alignVerticalCenterWithPanel
    }
}

private var fluentRelativePanelConstraintsKey: UInt8 = 0
private var fluentRelativePanelNameKey: UInt8 = 0

private final class FluentRelativePanelConstraintsStorage {
    var constraints: FluentRelativePanelConstraints

    init(_ constraints: FluentRelativePanelConstraints) {
        self.constraints = constraints
    }
}

private extension NSView {
    var fluentRelativePanelConstraints: FluentRelativePanelConstraints {
        get {
            (objc_getAssociatedObject(self, &fluentRelativePanelConstraintsKey)
                as? FluentRelativePanelConstraintsStorage)?.constraints
                ?? FluentRelativePanelConstraints()
        }
        set {
            objc_setAssociatedObject(
                self,
                &fluentRelativePanelConstraintsKey,
                FluentRelativePanelConstraintsStorage(newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var fluentRelativePanelName: String? {
        get { objc_getAssociatedObject(self, &fluentRelativePanelNameKey) as? String }
        set {
            objc_setAssociatedObject(
                self,
                &fluentRelativePanelNameKey,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
        }
    }
}

/// Wraps a declarative child with the `RelativePanel` attached properties applied by an
/// enclosing `FluentRelativePanel`.
public struct FluentRelativePanelPositionedView<Content: FluentView>:
    FluentUpdatablePrimitiveView
{
    fileprivate let content: Content
    fileprivate let constraints: FluentRelativePanelConstraints

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        view.fluentRelativePanelConstraints = constraints
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        view.fluentRelativePanelConstraints = constraints
        view.superview?.needsLayout = true
        return content._update(view, in: context)
    }
}

/// Names a declarative child for sibling references used by `RelativePanel`.
public struct FluentRelativePanelNamedView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let name: String

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        view.fluentRelativePanelName = name
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        view.fluentRelativePanelName = name
        return content._update(view, in: context)
    }
}

public extension FluentView {
    /// Sets the WinUI `RelativePanel` attached properties consumed by an enclosing
    /// `FluentRelativePanel`. Sibling references target `relativePanelName(_:)` values.
    func relativePanelPosition(
        leftOf: String? = nil,
        above: String? = nil,
        rightOf: String? = nil,
        below: String? = nil,
        alignLeftWith: String? = nil,
        alignTopWith: String? = nil,
        alignRightWith: String? = nil,
        alignBottomWith: String? = nil,
        alignHorizontalCenterWith: String? = nil,
        alignVerticalCenterWith: String? = nil,
        alignLeftWithPanel: Bool = false,
        alignTopWithPanel: Bool = false,
        alignRightWithPanel: Bool = false,
        alignBottomWithPanel: Bool = false,
        alignHorizontalCenterWithPanel: Bool = false,
        alignVerticalCenterWithPanel: Bool = false
    ) -> FluentRelativePanelPositionedView<Self> {
        FluentRelativePanelPositionedView(
            content: self,
            constraints: FluentRelativePanelConstraints(
                leftOf: leftOf,
                above: above,
                rightOf: rightOf,
                below: below,
                alignLeftWith: alignLeftWith,
                alignTopWith: alignTopWith,
                alignRightWith: alignRightWith,
                alignBottomWith: alignBottomWith,
                alignHorizontalCenterWith: alignHorizontalCenterWith,
                alignVerticalCenterWith: alignVerticalCenterWith,
                alignLeftWithPanel: alignLeftWithPanel,
                alignTopWithPanel: alignTopWithPanel,
                alignRightWithPanel: alignRightWithPanel,
                alignBottomWithPanel: alignBottomWithPanel,
                alignHorizontalCenterWithPanel: alignHorizontalCenterWithPanel,
                alignVerticalCenterWithPanel: alignVerticalCenterWithPanel
            )
        )
    }

    /// Gives a child the name used by sibling `RelativePanel` references.
    func relativePanelName(_ name: String) -> FluentRelativePanelNamedView<Self> {
        FluentRelativePanelNamedView(content: self, name: name)
    }
}

/// A WinUI `RelativePanel`: children are positioned relative to one another or to the panel's
/// edges through attached properties.
///
/// The layout engine is a faithful port of `RPGraph`: measure rectangles are derived from the
/// arranged rectangles of resolved dependencies, desired size comes from traversing each
/// horizontal/vertical leaf chain, and AppKit receives the final arrange rectangles directly.
public struct FluentRelativePanelView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: FluentAnyView

    fileprivate init(content: FluentAnyView) { self.content = content }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentRelativePanelHost()
        let children = content.children?.map { $0.mount(context) } ?? [content.mount(context)]
        host.setChildren(children)
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentRelativePanelHost else { return false }
        let children = content.children ?? [content]
        guard host.subviews.count == children.count else { return false }

        for index in children.indices {
            let nativeChild = host.subviews[index]
            let child = children[index]
            if !child._update(nativeChild, in: context) {
                host.replaceChild(at: index, with: child.mount(context))
            }
        }
        return true
    }
}

public func FluentRelativePanel<Content: FluentView>(
    @FluentViewBuilder content: () -> Content
) -> FluentRelativePanelView<Content> {
    FluentRelativePanelView(content: FluentAnyView(content()))
}

private struct FluentRelativePanelLayoutResult {
    var naturalSize: NSSize
    var frames: [NSRect]
}

private enum FluentRelativePanelLayoutEngine {
    static func resolve(
        children: [NSView],
        availableSize: NSSize,
        finalSize: NSSize
    ) -> FluentRelativePanelLayoutResult {
        guard !children.isEmpty else {
            return FluentRelativePanelLayoutResult(naturalSize: .zero, frames: [])
        }

        let graph = FluentRelativePanelGraph(children: children)
        graph.measure(availableSize: availableSize)
        graph.arrange(availableSize: availableSize, finalSize: finalSize)

        let frames = graph.nodes.map { node in
            NSRect(
                origin: NSPoint(
                    x: max(node.arrangeRect.minX, 0),
                    y: max(node.arrangeRect.minY, 0)
                ),
                size: NSSize(
                    width: max(node.arrangeRect.width, 0),
                    height: max(node.arrangeRect.height, 0)
                )
            )
        }

        return FluentRelativePanelLayoutResult(
            naturalSize: graph.desiredSize(),
            frames: frames
        )
    }
}

/// Faithful port of WinUI's `RPGraph` dependency graph.
private final class FluentRelativePanelGraph {
    struct Node {
        let view: NSView
        let constraints: FluentRelativePanelConstraints
        var measureRect = NSRect.zero
        var arrangeRect = NSRect.zero
        var desiredSize = NSSize.zero
        var pending = false
        var measured = false
        var arrangedHorizontally = false
        var arrangedVertically = false
        var isHorizontalLeaf = true
        var isVerticalLeaf = true
        var leftOf: Int?
        var above: Int?
        var rightOf: Int?
        var below: Int?
        var alignLeftWith: Int?
        var alignTopWith: Int?
        var alignRightWith: Int?
        var alignBottomWith: Int?
        var alignHorizontalCenterWith: Int?
        var alignVerticalCenterWith: Int?
    }

    var nodes: [Node]

    private var minX: CGFloat = 0
    private var maxX: CGFloat = 0
    private var minY: CGFloat = 0
    private var maxY: CGFloat = 0
    private var isMinXCapped = false
    private var isMaxXCapped = false
    private var isMinYCapped = false
    private var isMaxYCapped = false
    private var accumulating: Set<Int> = []
    private var arrangingHorizontal: Set<Int> = []
    private var arrangingVertical: Set<Int> = []

    init(children: [NSView]) {
        nodes = children.map {
            Node(view: $0, constraints: $0.fluentRelativePanelConstraints)
        }
        resolveNameReferences()
    }

    func measure(availableSize: NSSize) {
        for index in nodes.indices {
            measureNode(index, availableSize: availableSize)
        }
    }

    func arrange(availableSize: NSSize, finalSize: NSSize) {
        if finalSize.width != availableSize.width {
            for index in nodes.indices {
                nodes[index].arrangedHorizontally = false
            }
            arrangingHorizontal.removeAll()
            for index in nodes.indices {
                arrangeNodeHorizontally(index, finalSize: finalSize)
            }
        }

        if finalSize.height != availableSize.height {
            for index in nodes.indices {
                nodes[index].arrangedVertically = false
            }
            arrangingVertical.removeAll()
            for index in nodes.indices {
                arrangeNodeVertically(index, finalSize: finalSize)
            }
        }
    }

    func desiredSize() -> NSSize {
        markLeaves()

        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0

        for index in nodes.indices {
            if nodes[index].isHorizontalLeaf {
                resetHorizontalAccumulator()
                accumulating.removeAll()
                accumulatePositiveDesiredWidth(index, x: 0)
                maxWidth = max(maxWidth, maxX - minX)
            }

            if nodes[index].isVerticalLeaf {
                resetVerticalAccumulator()
                accumulating.removeAll()
                accumulatePositiveDesiredHeight(index, y: 0)
                maxHeight = max(maxHeight, maxY - minY)
            }
        }

        return NSSize(width: max(0, maxWidth), height: max(0, maxHeight))
    }

    // MARK: - Name resolution

    private func resolveNameReferences() {
        var names: [String: Int] = [:]
        for (index, node) in nodes.enumerated() {
            if let name = node.view.fluentRelativePanelName, !name.isEmpty {
                names[name] = index
            }
        }

        func resolve(_ name: String?) -> Int? {
            guard let name, !name.isEmpty else { return nil }
            return names[name]
        }

        for index in nodes.indices {
            let constraints = nodes[index].constraints
            nodes[index].leftOf = resolve(constraints.leftOf)
            nodes[index].above = resolve(constraints.above)
            nodes[index].rightOf = resolve(constraints.rightOf)
            nodes[index].below = resolve(constraints.below)
            nodes[index].alignLeftWith = resolve(constraints.alignLeftWith)
            nodes[index].alignTopWith = resolve(constraints.alignTopWith)
            nodes[index].alignRightWith = resolve(constraints.alignRightWith)
            nodes[index].alignBottomWith = resolve(constraints.alignBottomWith)
            nodes[index].alignHorizontalCenterWith = resolve(constraints.alignHorizontalCenterWith)
            nodes[index].alignVerticalCenterWith = resolve(constraints.alignVerticalCenterWith)
        }
    }

    // MARK: - Anchoring predicates

    private func isLeftAnchored(_ index: Int) -> Bool {
        let node = nodes[index]
        return node.constraints.alignLeftWithPanel
            || node.alignLeftWith != nil
            || (node.rightOf != nil && node.alignHorizontalCenterWith == nil)
    }

    private func isTopAnchored(_ index: Int) -> Bool {
        let node = nodes[index]
        return node.constraints.alignTopWithPanel
            || node.alignTopWith != nil
            || (node.below != nil && node.alignVerticalCenterWith == nil)
    }

    private func isRightAnchored(_ index: Int) -> Bool {
        let node = nodes[index]
        return node.constraints.alignRightWithPanel
            || node.alignRightWith != nil
            || (node.leftOf != nil && node.alignHorizontalCenterWith == nil)
    }

    private func isBottomAnchored(_ index: Int) -> Bool {
        let node = nodes[index]
        return node.constraints.alignBottomWithPanel
            || node.alignBottomWith != nil
            || (node.above != nil && node.alignVerticalCenterWith == nil)
    }

    private func isHorizontalCenterAnchored(_ index: Int) -> Bool {
        let node = nodes[index]
        return (node.constraints.alignHorizontalCenterWithPanel
            && !node.constraints.alignLeftWithPanel
            && !node.constraints.alignRightWithPanel
            && node.alignLeftWith == nil
            && node.alignRightWith == nil
            && node.leftOf == nil
            && node.rightOf == nil)
            || (node.alignHorizontalCenterWith != nil
            && !node.constraints.alignLeftWithPanel
            && !node.constraints.alignRightWithPanel
            && node.alignLeftWith == nil
            && node.alignRightWith == nil)
    }

    private func isVerticalCenterAnchored(_ index: Int) -> Bool {
        let node = nodes[index]
        return (node.constraints.alignVerticalCenterWithPanel
            && !node.constraints.alignTopWithPanel
            && !node.constraints.alignBottomWithPanel
            && node.alignTopWith == nil
            && node.alignBottomWith == nil
            && node.above == nil
            && node.below == nil)
            || (node.alignVerticalCenterWith != nil
            && !node.constraints.alignTopWithPanel
            && !node.constraints.alignBottomWithPanel
            && node.alignTopWith == nil
            && node.alignBottomWith == nil)
    }

    // MARK: - Measure pass

    private func dependencies(of index: Int) -> [Int?] {
        let node = nodes[index]
        return [
            node.leftOf,
            node.above,
            node.rightOf,
            node.below,
            node.alignLeftWith,
            node.alignTopWith,
            node.alignRightWith,
            node.alignBottomWith,
            node.alignHorizontalCenterWith,
            node.alignVerticalCenterWith
        ]
    }

    private func measureNode(_ index: Int?, availableSize: NSSize) {
        guard let index else { return }
        guard !nodes[index].measured else { return }
        guard !nodes[index].pending else { return }

        nodes[index].pending = true
        for dependency in dependencies(of: index) {
            measureNode(dependency, availableSize: availableSize)
        }
        nodes[index].pending = false

        calculateMeasureRectHorizontally(index, availableSize: availableSize)
        calculateMeasureRectVertically(index, availableSize: availableSize)
        nodes[index].desiredSize = measuredSize(of: index, availableSize: nodes[index].measureRect.size)
        nodes[index].measured = true

        if availableSize.width.isFinite {
            calculateArrangeRectHorizontally(index)
            nodes[index].arrangedHorizontally = true
        }
        if availableSize.height.isFinite {
            calculateArrangeRectVertically(index)
            nodes[index].arrangedVertically = true
        }
    }

    private func measuredSize(of index: Int, availableSize: NSSize) -> NSSize {
        // AppKit has no measure-with-constraint API. The natural size is the closest analogue;
        // capping it to the measure rectangle matches the behavior of a child that reports its
        // full desired size when measured with a smaller slot.
        var size = fluentNaturalSize(of: nodes[index].view, forceLayout: false)
        if availableSize.width.isFinite {
            size.width = min(size.width, max(0, availableSize.width))
        }
        if availableSize.height.isFinite {
            size.height = min(size.height, max(0, availableSize.height))
        }
        return NSSize(width: max(0, size.width), height: max(0, size.height))
    }

    private func calculateMeasureRectHorizontally(_ index: Int, availableSize: NSSize) {
        var x: CGFloat = 0
        var width = availableSize.width

        if availableSize.width.isFinite {
            var centeredFromLeft = false
            var centeredFromRight = false
            let node = nodes[index]

            if !node.constraints.alignLeftWithPanel {
                if let dependency = node.alignLeftWith {
                    let restricted = nodes[dependency].arrangeRect.minX
                    x = restricted
                    width -= restricted
                } else if node.alignHorizontalCenterWith != nil {
                    centeredFromLeft = true
                } else if let dependency = node.rightOf {
                    let restricted = nodes[dependency].arrangeRect.maxX
                    x = restricted
                    width -= restricted
                }
            }

            if !node.constraints.alignRightWithPanel {
                if let dependency = node.alignRightWith {
                    width -= availableSize.width - nodes[dependency].arrangeRect.maxX
                } else if node.alignHorizontalCenterWith != nil {
                    centeredFromRight = true
                } else if let dependency = node.leftOf {
                    width -= availableSize.width - nodes[dependency].arrangeRect.minX
                }
            }

            if centeredFromLeft, centeredFromRight, let dependency = node.alignHorizontalCenterWith {
                let center = nodes[dependency].arrangeRect.midX
                width = min(center, availableSize.width - center) * 2
                x = center - width / 2
            }
        }

        nodes[index].measureRect.origin.x = x
        nodes[index].measureRect.size.width = max(0, width)
    }

    private func calculateMeasureRectVertically(_ index: Int, availableSize: NSSize) {
        var y: CGFloat = 0
        var height = availableSize.height

        if availableSize.height.isFinite {
            var centeredFromTop = false
            var centeredFromBottom = false
            let node = nodes[index]

            if !node.constraints.alignTopWithPanel {
                if let dependency = node.alignTopWith {
                    let restricted = nodes[dependency].arrangeRect.minY
                    y = restricted
                    height -= restricted
                } else if node.alignVerticalCenterWith != nil {
                    centeredFromTop = true
                } else if let dependency = node.below {
                    let restricted = nodes[dependency].arrangeRect.maxY
                    y = restricted
                    height -= restricted
                }
            }

            if !node.constraints.alignBottomWithPanel {
                if let dependency = node.alignBottomWith {
                    height -= availableSize.height - nodes[dependency].arrangeRect.maxY
                } else if node.alignVerticalCenterWith != nil {
                    centeredFromBottom = true
                } else if let dependency = node.above {
                    height -= availableSize.height - nodes[dependency].arrangeRect.minY
                }
            }

            if centeredFromTop, centeredFromBottom, let dependency = node.alignVerticalCenterWith {
                let center = nodes[dependency].arrangeRect.midY
                height = min(center, availableSize.height - center) * 2
                y = center - height / 2
            }
        }

        nodes[index].measureRect.origin.y = y
        nodes[index].measureRect.size.height = max(0, height)
    }

    private func calculateArrangeRectHorizontally(_ index: Int) {
        let measureRect = nodes[index].measureRect
        let desiredWidth = min(
            max(0, measureRect.width),
            max(0, nodes[index].desiredSize.width)
        )
        var x = measureRect.minX
        var width = desiredWidth

        if isLeftAnchored(index) {
            if isRightAnchored(index) {
                x = measureRect.minX
                width = max(0, measureRect.width)
            } else {
                x = measureRect.minX
                width = desiredWidth
            }
        } else if isRightAnchored(index) {
            x = measureRect.maxX - desiredWidth
            width = desiredWidth
        } else if isHorizontalCenterAnchored(index) {
            x = measureRect.midX - desiredWidth / 2
            width = desiredWidth
        }

        nodes[index].arrangeRect.origin.x = x
        nodes[index].arrangeRect.size.width = max(0, width)
    }

    private func calculateArrangeRectVertically(_ index: Int) {
        let measureRect = nodes[index].measureRect
        let desiredHeight = min(
            max(0, measureRect.height),
            max(0, nodes[index].desiredSize.height)
        )
        var y = measureRect.minY
        var height = desiredHeight

        if isTopAnchored(index) {
            if isBottomAnchored(index) {
                y = measureRect.minY
                height = max(0, measureRect.height)
            } else {
                y = measureRect.minY
                height = desiredHeight
            }
        } else if isBottomAnchored(index) {
            y = measureRect.maxY - desiredHeight
            height = desiredHeight
        } else if isVerticalCenterAnchored(index) {
            y = measureRect.midY - desiredHeight / 2
            height = desiredHeight
        }

        nodes[index].arrangeRect.origin.y = y
        nodes[index].arrangeRect.size.height = max(0, height)
    }

    // MARK: - Arrange pass

    private func arrangeNodeHorizontally(_ index: Int?, finalSize: NSSize) {
        guard let index, !nodes[index].arrangedHorizontally else { return }
        guard !arrangingHorizontal.contains(index) else { return }
        arrangingHorizontal.insert(index)
        defer { arrangingHorizontal.remove(index) }

        for dependency in dependencies(of: index) {
            arrangeNodeHorizontally(dependency, finalSize: finalSize)
        }

        calculateMeasureRectHorizontally(index, availableSize: finalSize)
        calculateArrangeRectHorizontally(index)
        nodes[index].arrangedHorizontally = true
    }

    private func arrangeNodeVertically(_ index: Int?, finalSize: NSSize) {
        guard let index, !nodes[index].arrangedVertically else { return }
        guard !arrangingVertical.contains(index) else { return }
        arrangingVertical.insert(index)
        defer { arrangingVertical.remove(index) }

        for dependency in dependencies(of: index) {
            arrangeNodeVertically(dependency, finalSize: finalSize)
        }

        calculateMeasureRectVertically(index, availableSize: finalSize)
        calculateArrangeRectVertically(index)
        nodes[index].arrangedVertically = true
    }

    // MARK: - Desired size accumulation

    private func markLeaves() {
        for index in nodes.indices {
            nodes[index].isHorizontalLeaf = true
            nodes[index].isVerticalLeaf = true
        }

        for index in nodes.indices {
            unmarkNeighbors(of: index)
        }
    }

    private func unmarkNeighbors(of index: Int) {
        let node = nodes[index]
        var centeredFromLeft = false
        var centeredFromRight = false
        var centeredFromTop = false
        var centeredFromBottom = false

        if !node.constraints.alignLeftWithPanel {
            if let dependency = node.alignLeftWith {
                nodes[dependency].isHorizontalLeaf = false
            } else if node.alignHorizontalCenterWith != nil {
                centeredFromLeft = true
            } else if let dependency = node.rightOf {
                nodes[dependency].isHorizontalLeaf = false
            }
        }

        if !node.constraints.alignTopWithPanel {
            if let dependency = node.alignTopWith {
                nodes[dependency].isVerticalLeaf = false
            } else if node.alignVerticalCenterWith != nil {
                centeredFromTop = true
            } else if let dependency = node.below {
                nodes[dependency].isVerticalLeaf = false
            }
        }

        if !node.constraints.alignRightWithPanel {
            if let dependency = node.alignRightWith {
                nodes[dependency].isHorizontalLeaf = false
            } else if node.alignHorizontalCenterWith != nil {
                centeredFromRight = true
            } else if let dependency = node.leftOf {
                nodes[dependency].isHorizontalLeaf = false
            }
        }

        if !node.constraints.alignBottomWithPanel {
            if let dependency = node.alignBottomWith {
                nodes[dependency].isVerticalLeaf = false
            } else if node.alignVerticalCenterWith != nil {
                centeredFromBottom = true
            } else if let dependency = node.above {
                nodes[dependency].isVerticalLeaf = false
            }
        }

        if centeredFromLeft, centeredFromRight, let dependency = node.alignHorizontalCenterWith {
            nodes[dependency].isHorizontalLeaf = false
        }
        if centeredFromTop, centeredFromBottom, let dependency = node.alignVerticalCenterWith {
            nodes[dependency].isVerticalLeaf = false
        }
    }

    private func resetHorizontalAccumulator() {
        minX = 0
        maxX = 0
        isMinXCapped = false
        isMaxXCapped = false
    }

    private func resetVerticalAccumulator() {
        minY = 0
        maxY = 0
        isMinYCapped = false
        isMaxYCapped = false
    }

    private func accumulatePositiveDesiredWidth(_ index: Int, x: CGFloat) {
        guard !accumulating.contains(index) else { return }
        accumulating.insert(index)
        defer { accumulating.remove(index) }

        let initialX = x
        var centeredFromLeft = false
        var centeredFromRight = false
        let cursor = x + nodes[index].desiredSize.width
        maxX = max(maxX, cursor)

        let node = nodes[index]
        if node.constraints.alignLeftWithPanel {
            if !isMaxXCapped {
                maxX = cursor
                isMaxXCapped = true
            }
        } else if let dependency = node.alignLeftWith {
            if node.alignLeftWith != node.alignRightWith {
                accumulateNegativeDesiredWidth(dependency, x: cursor)
            }
        } else if node.alignHorizontalCenterWith != nil {
            centeredFromLeft = true
        } else if let dependency = node.rightOf {
            accumulatePositiveDesiredWidth(dependency, x: cursor)
        }

        if node.constraints.alignRightWithPanel {
            if isMinXCapped {
                minX = min(minX, initialX)
            } else {
                minX = initialX
                isMinXCapped = true
            }
        } else if let dependency = node.alignRightWith {
            accumulatePositiveDesiredWidth(dependency, x: initialX)
        } else if node.alignHorizontalCenterWith != nil {
            centeredFromRight = true
        } else if let dependency = node.leftOf {
            accumulateNegativeDesiredWidth(dependency, x: initialX)
        }

        if centeredFromLeft, centeredFromRight, let dependency = node.alignHorizontalCenterWith {
            let centerX = cursor - node.desiredSize.width / 2
            let edgeX = centerX - nodes[dependency].desiredSize.width / 2
            minX = min(minX, edgeX)
            accumulatePositiveDesiredWidth(dependency, x: edgeX)
        } else if isHorizontalCenterAnchored(index) {
            let centerX = cursor - node.desiredSize.width / 2
            let upper = maxX - centerX
            let lower = centerX - minX
            maxX = max(upper, lower) * 2
            minX = 0
        }
    }

    private func accumulateNegativeDesiredWidth(_ index: Int, x: CGFloat) {
        guard !accumulating.contains(index) else { return }
        accumulating.insert(index)
        defer { accumulating.remove(index) }

        let initialX = x
        var centeredFromLeft = false
        var centeredFromRight = false
        let cursor = x - nodes[index].desiredSize.width
        minX = min(minX, cursor)

        let node = nodes[index]
        if node.constraints.alignRightWithPanel {
            if !isMinXCapped {
                minX = cursor
                isMinXCapped = true
            }
        } else if let dependency = node.alignRightWith {
            if node.alignRightWith != node.alignLeftWith {
                accumulatePositiveDesiredWidth(dependency, x: cursor)
            }
        } else if node.alignHorizontalCenterWith != nil {
            centeredFromRight = true
        } else if let dependency = node.leftOf {
            accumulateNegativeDesiredWidth(dependency, x: cursor)
        }

        if node.constraints.alignLeftWithPanel {
            if isMaxXCapped {
                maxX = max(maxX, initialX)
            } else {
                maxX = initialX
                isMaxXCapped = true
            }
        } else if let dependency = node.alignLeftWith {
            accumulateNegativeDesiredWidth(dependency, x: initialX)
        } else if node.alignHorizontalCenterWith != nil {
            centeredFromLeft = true
        } else if let dependency = node.rightOf {
            accumulatePositiveDesiredWidth(dependency, x: initialX)
        }

        if centeredFromLeft, centeredFromRight, let dependency = node.alignHorizontalCenterWith {
            let centerX = cursor + node.desiredSize.width / 2
            let edgeX = centerX + nodes[dependency].desiredSize.width / 2
            maxX = max(maxX, edgeX)
            accumulateNegativeDesiredWidth(dependency, x: edgeX)
        } else if isHorizontalCenterAnchored(index) {
            let centerX = cursor + node.desiredSize.width / 2
            let upper = maxX - centerX
            let lower = centerX - minX
            maxX = max(upper, lower) * 2
            minX = 0
        }
    }

    private func accumulatePositiveDesiredHeight(_ index: Int, y: CGFloat) {
        guard !accumulating.contains(index) else { return }
        accumulating.insert(index)
        defer { accumulating.remove(index) }

        let initialY = y
        var centeredFromTop = false
        var centeredFromBottom = false
        let cursor = y + nodes[index].desiredSize.height
        maxY = max(maxY, cursor)

        let node = nodes[index]
        if node.constraints.alignTopWithPanel {
            if !isMaxYCapped {
                maxY = cursor
                isMaxYCapped = true
            }
        } else if let dependency = node.alignTopWith {
            if node.alignTopWith != node.alignBottomWith {
                accumulateNegativeDesiredHeight(dependency, y: cursor)
            }
        } else if node.alignVerticalCenterWith != nil {
            centeredFromTop = true
        } else if let dependency = node.below {
            accumulatePositiveDesiredHeight(dependency, y: cursor)
        }

        if node.constraints.alignBottomWithPanel {
            if isMinYCapped {
                minY = min(minY, initialY)
            } else {
                minY = initialY
                isMinYCapped = true
            }
        } else if let dependency = node.alignBottomWith {
            accumulatePositiveDesiredHeight(dependency, y: initialY)
        } else if node.alignVerticalCenterWith != nil {
            centeredFromBottom = true
        } else if let dependency = node.above {
            accumulateNegativeDesiredHeight(dependency, y: initialY)
        }

        if centeredFromTop, centeredFromBottom, let dependency = node.alignVerticalCenterWith {
            let centerY = cursor - node.desiredSize.height / 2
            let edgeY = centerY - nodes[dependency].desiredSize.height / 2
            minY = min(minY, edgeY)
            accumulatePositiveDesiredHeight(dependency, y: edgeY)
        } else if isVerticalCenterAnchored(index) {
            let centerY = cursor - node.desiredSize.height / 2
            let upper = maxY - centerY
            let lower = centerY - minY
            maxY = max(upper, lower) * 2
            minY = 0
        }
    }

    private func accumulateNegativeDesiredHeight(_ index: Int, y: CGFloat) {
        guard !accumulating.contains(index) else { return }
        accumulating.insert(index)
        defer { accumulating.remove(index) }

        let initialY = y
        var centeredFromTop = false
        var centeredFromBottom = false
        let cursor = y - nodes[index].desiredSize.height
        minY = min(minY, cursor)

        let node = nodes[index]
        if node.constraints.alignBottomWithPanel {
            if !isMinYCapped {
                minY = cursor
                isMinYCapped = true
            }
        } else if let dependency = node.alignBottomWith {
            if node.alignBottomWith != node.alignTopWith {
                accumulatePositiveDesiredHeight(dependency, y: cursor)
            }
        } else if node.alignVerticalCenterWith != nil {
            centeredFromBottom = true
        } else if let dependency = node.above {
            accumulateNegativeDesiredHeight(dependency, y: cursor)
        }

        if node.constraints.alignTopWithPanel {
            if isMaxYCapped {
                maxY = max(maxY, initialY)
            } else {
                maxY = initialY
                isMaxYCapped = true
            }
        } else if let dependency = node.alignTopWith {
            accumulateNegativeDesiredHeight(dependency, y: initialY)
        } else if node.alignVerticalCenterWith != nil {
            centeredFromTop = true
        } else if let dependency = node.below {
            accumulatePositiveDesiredHeight(dependency, y: initialY)
        }

        if centeredFromTop, centeredFromBottom, let dependency = node.alignVerticalCenterWith {
            let centerY = cursor + node.desiredSize.height / 2
            let edgeY = centerY + nodes[dependency].desiredSize.height / 2
            maxY = max(maxY, edgeY)
            accumulateNegativeDesiredHeight(dependency, y: edgeY)
        } else if isVerticalCenterAnchored(index) {
            let centerY = cursor + node.desiredSize.height / 2
            let upper = maxY - centerY
            let lower = centerY - minY
            maxY = max(upper, lower) * 2
            minY = 0
        }
    }
}

private final class FluentRelativePanelHost: NSView {
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        FluentRelativePanelLayoutEngine.resolve(
            children: subviews,
            availableSize: NSSize(width: CGFloat.infinity, height: CGFloat.infinity),
            finalSize: NSSize(width: CGFloat.infinity, height: CGFloat.infinity)
        ).naturalSize
    }

    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.RelativePanel")
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        fluentSetDefaultAccessibilityLabel("Relative panel")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setChildren(_ children: [NSView]) {
        children.forEach { child in
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        needsLayout = true
    }

    func replaceChild(at index: Int, with child: NSView) {
        guard subviews.indices.contains(index) else { return }
        subviews[index].removeFromSuperview()
        child.translatesAutoresizingMaskIntoConstraints = false
        if index < subviews.count {
            addSubview(child, positioned: .below, relativeTo: subviews[index])
        } else {
            addSubview(child)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let result = FluentRelativePanelLayoutEngine.resolve(
            children: subviews,
            availableSize: bounds.size,
            finalSize: bounds.size
        )
        for index in subviews.indices {
            subviews[index].frame = index < result.frames.count ? result.frames[index] : .zero
        }
    }
}
