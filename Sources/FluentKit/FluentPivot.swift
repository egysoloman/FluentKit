import AppKit

/// A WinUI-style Pivot: a row of large text headers above one visible content item.
///
/// Geometry, colors and motion follow `Pivot_themeresources.xaml` and `Pivot_Partial.cpp`:
/// 48pt headers in 24pt SemiLight with 12pt side padding, a 3pt accent selection pipe, a
/// 14pt bold title, and 12pt item margins. Headers are laid out in order when they fit (static);
/// otherwise, while `isHeaderItemsCarouselEnabled` is true, the selected header moves to the
/// leading edge and the rest follow cyclically (dynamic). Navigation wraps only in dynamic mode.
/// A locked Pivot hides unselected headers and ignores navigation. Selection changes fly the
/// old item out (83ms) and the new one in (767ms, `.direct` curve).
public struct FluentPivot<Data: RandomAccessCollection, Content: FluentView>: FluentUpdatablePrimitiveView {
    private let data: Data
    private let selection: FluentBinding<Int>?
    private let title: String?
    private let isLocked: Bool
    private let isHeaderItemsCarouselEnabled: Bool
    private let leftHeader: FluentAnyView?
    private let rightHeader: FluentAnyView?
    private let onSelectionChanged: ((Int) -> Void)?
    private let header: (Data.Element) -> String
    private let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        selection: FluentBinding<Int>? = nil,
        title: String? = nil,
        isLocked: Bool = false,
        isHeaderItemsCarouselEnabled: Bool = true,
        leftHeader: FluentAnyView? = nil,
        rightHeader: FluentAnyView? = nil,
        onSelectionChanged: ((Int) -> Void)? = nil,
        header: @escaping (Data.Element) -> String,
        @FluentViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.selection = selection
        self.title = title
        self.isLocked = isLocked
        self.isHeaderItemsCarouselEnabled = isHeaderItemsCarouselEnabled
        self.leftHeader = leftHeader
        self.rightHeader = rightHeader
        self.onSelectionChanged = onSelectionChanged
        self.header = header
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentPivotControl(context: context)
        host.update(configuration: configuration(in: context), context: context)
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentPivotControl else { return false }
        host.update(configuration: configuration(in: context), context: context)
        return true
    }

    private func configuration(in context: FluentRenderContext) -> FluentPivotConfiguration {
        FluentPivotConfiguration(
            items: data.map { element in
                FluentPivotRecord(header: header(element), view: FluentAnyView(content(element)))
            },
            selection: selection,
            title: title,
            isLocked: isLocked,
            isHeaderItemsCarouselEnabled: isHeaderItemsCarouselEnabled,
            leftHeader: leftHeader,
            rightHeader: rightHeader,
            onSelectionChanged: onSelectionChanged
        )
    }
}

struct FluentPivotRecord {
    let header: String
    let view: FluentAnyView
}

struct FluentPivotConfiguration {
    var items: [FluentPivotRecord]
    var selection: FluentBinding<Int>?
    var title: String?
    var isLocked: Bool
    var isHeaderItemsCarouselEnabled: Bool
    var leftHeader: FluentAnyView?
    var rightHeader: FluentAnyView?
    var onSelectionChanged: ((Int) -> Void)?
}

/// Source-derived Pivot metrics.
enum FluentPivotMetrics {
    static let headerHeight: CGFloat = 48
    static let headerFontSize: CGFloat = 24
    static let headerPadding: CGFloat = 12
    /// `PivotHeaderItemCharacterSpacing` = -25 thousandths of an em.
    static let headerKern: CGFloat = -0.025 * headerFontSize
    static let pipeHeight: CGFloat = 3
    static let pipeBottomMargin: CGFloat = 2
    static let pipeCornerRadius: CGFloat = 1.5
    static let lockedTranslation: CGFloat = 40
    static let lockedTransition: TimeInterval = 0.33
    static let titleFontSize: CGFloat = 14
    /// `PivotPortraitThemePadding` = 12,14,0,13.
    static let titleInsets = NSEdgeInsets(top: 14, left: 12, bottom: 13, right: 0)
    static let itemMargin: CGFloat = 12
    static let navigationButtonSize = NSSize(width: 20, height: 36)
    static let navigationButtonTopMargin: CGFloat = 6
    static let flyOutDistance: CGFloat = 7
    static let flyOutTranslation = FluentMotionToken(duration: 0.083, curve: .linear)
    static let flyOutOpacity = FluentMotionToken(duration: 0.067, curve: .linear)
    static let flyInDistance: CGFloat = 20
    static let flyInTranslation = FluentMotionToken(duration: 0.767, curve: .direct)
    static let flyInOpacity = FluentMotionToken(duration: 0.333, curve: .direct)
    /// Dynamic header carousel shift spans fly-out plus fly-in.
    static let headerShift = FluentMotionToken(duration: 0.850, curve: .direct)

    /// `PivotCurveGenerator::GetHeaderShiftOffset`: keeps the proportions of the space visible
    /// before and after the selected static header when the header strip is clipped.
    static func headerShiftOffset(before a: CGFloat, selected b: CGFloat, after c: CGFloat, viewport v: CGFloat) -> CGFloat {
        a + c == 0 ? 0 : max(a - a * (v - min(b, v)) / (a + c), 0)
    }
}

enum FluentPivotNavigationDirection {
    case previous
    case next
}

final class FluentPivotControl: NSControl {
    override var isFlipped: Bool { true }

    private(set) var context: FluentRenderContext
    fileprivate var configuration = FluentPivotConfiguration(
        items: [], selection: nil, title: nil, isLocked: false,
        isHeaderItemsCarouselEnabled: true, leftHeader: nil, rightHeader: nil, onSelectionChanged: nil
    )
    private(set) var selectedIndex = -1
    private(set) var usesStaticHeaders = true
    private(set) var isPointerOverHeaders = false

    private let titleField = NSTextField(labelWithString: "")
    private let headerClipper = FluentPivotFlippedView()
    fileprivate let headerStrip = FluentPivotFlippedView()
    fileprivate let contentContainer = FluentPivotFlippedView()
    let previousButton = FluentPivotNavigationButton(direction: .previous)
    let nextButton = FluentPivotNavigationButton(direction: .next)
    private let focusLayer = CAShapeLayer()
    private(set) var headerItems: [FluentPivotHeaderItemView] = []
    private(set) var contentHosts: [FluentViewHost<FluentAnyView>] = []
    private var leftHeaderHost: FluentViewHost<FluentAnyView>?
    private var rightHeaderHost: FluentViewHost<FluentAnyView>?
    private var headerTrackingArea: NSTrackingArea?
    private var windowObservation: NSKeyValueObservation?
    private var selectionObserverID: UUID?
    private var observedSelection: FluentBinding<Int>?
    private var selectionObservationGeneration: UInt64 = 0
    private var isWritingBinding = false
    private var animationGeneration: UInt64 = 0
    private(set) var isTransitioning = false
    private var staticHeaderOffset: CGFloat = 0
    fileprivate let animationCoordinator = FluentAnimationCoordinator()
    /// Interactive pan state shared by trackpad scrolling, direct touch and wheel input.
    /// `panOffset` is logical: negative reveals the next item, positive the previous one.
    private(set) var isPanning = false
    private(set) var panOffset: CGFloat = 0
    /// Shared touch, trackpad and wheel input (see `FluentPanGestureDriver`).
    private(set) var panDriver: FluentPanGestureDriver!
    var touchPanRecognizer: NSPanGestureRecognizer? { panDriver.touchRecognizer }
    /// Logical header displacement while panning. Applied to header frames, not to the strip's
    /// backing-layer transform, which AppKit owns and may reset.
    private(set) var panHeaderShift: CGFloat = 0

    init(context: FluentRenderContext) {
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot")
        wantsLayer = true
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        fluentSetDefaultAccessibilityLabel("Pivot")

        titleField.identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot.Title")
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isHidden = true
        addSubview(titleField)

        headerClipper.identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot.Headers")
        headerClipper.wantsLayer = true
        headerClipper.layer?.masksToBounds = true
        headerStrip.wantsLayer = true
        headerClipper.addSubview(headerStrip)
        addSubview(headerClipper)

        contentContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot.Content")
        contentContainer.wantsLayer = true
        contentContainer.layer?.masksToBounds = true
        addSubview(contentContainer)

        for button in [previousButton, nextButton] {
            button.isHidden = true
            addSubview(button)
        }
        previousButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot.Previous")
        nextButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot.Next")
        previousButton.onClick = { [weak self] in self?.move(.previous, wrap: self?.shouldWrap ?? false) }
        nextButton.onClick = { [weak self] in self?.move(.next, wrap: self?.shouldWrap ?? false) }

        focusLayer.name = "FluentKit.Pivot.Focus"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.zPosition = 10
        layer?.addSublayer(focusLayer)
        animationCoordinator.reduceMotion = context.reduceMotion
        installPanDriver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeSelectionObserver() }

    // MARK: - Configuration

    func update(configuration next: FluentPivotConfiguration, context: FluentRenderContext) {
        removeSelectionObserver()
        if isPanning, configuration.items.count != next.items.count || next.isLocked {
            cancelInteractivePan(animated: false)
        }
        let headersChanged = configuration.items.map(\.header) != next.items.map(\.header)
        let lockChanged = configuration.isLocked != next.isLocked
        configuration = next
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion

        updateTitle()
        updateContentHosts()
        leftHeaderHost = updateSlot(leftHeaderHost, with: next.leftHeader, identifier: "FluentKit.Pivot.LeftHeader")
        rightHeaderHost = updateSlot(rightHeaderHost, with: next.rightHeader, identifier: "FluentKit.Pivot.RightHeader")
        if headersChanged || headerItems.count != next.items.count { rebuildHeaderItems() }

        let requested = clamped(next.selection?.get() ?? (selectedIndex < 0 ? 0 : selectedIndex))
        if requested != selectedIndex {
            commit(to: requested, direction: nil, animated: false)
        } else {
            synchronizeSelectionBinding()
            if !isTransitioning || context.reduceMotion { showCurrent() }
        }
        for button in [previousButton, nextButton] { button.theme = context.theme }
        updateHeaderStates(animatedLock: lockChanged)
        installSelectionObserver()
        updateAccessibility()
        needsLayout = true
    }

    private func updateTitle() {
        let title = configuration.title ?? ""
        titleField.isHidden = title.isEmpty
        titleField.stringValue = title
        titleField.font = NSFont.systemFont(ofSize: FluentPivotMetrics.titleFontSize * context.theme.typography.scale, weight: .bold)
        titleField.textColor = context.theme.textPrimary
    }

    private func updateSlot(_ host: FluentViewHost<FluentAnyView>?, with view: FluentAnyView?, identifier: String) -> FluentViewHost<FluentAnyView>? {
        guard let view else {
            host?.removeFromSuperview()
            return nil
        }
        if let host {
            host.update(view, context: context)
            return host
        }
        let created = FluentViewHost(view, context: context)
        created.translatesAutoresizingMaskIntoConstraints = true
        created.identifier = NSUserInterfaceItemIdentifier(identifier)
        addSubview(created, positioned: .below, relativeTo: previousButton)
        return created
    }

    private func updateContentHosts() {
        if contentHosts.count == configuration.items.count {
            for (host, item) in zip(contentHosts, configuration.items) { host.update(item.view, context: context) }
            return
        }
        animationGeneration &+= 1
        animationCoordinator.cancelAll(on: contentHosts.compactMap(\.layer))
        contentHosts.forEach { $0.removeFromSuperview() }
        contentHosts = configuration.items.map { item in
            let host = FluentViewHost(item.view, context: context)
            // Laid out by frame; FluentViewHost otherwise opts out of autoresizing constraints.
            host.translatesAutoresizingMaskIntoConstraints = true
            host.wantsLayer = true
            host.isHidden = true
            contentContainer.addSubview(host)
            return host
        }
        isTransitioning = false
    }

    private func rebuildHeaderItems() {
        headerItems.forEach { $0.removeFromSuperview() }
        headerItems = configuration.items.enumerated().map { index, item in
            let view = FluentPivotHeaderItemView(title: item.header, index: index)
            view.onPress = { [weak self] index in self?.headerTapped(index) }
            view.onPointerChanged = { [weak self] in self?.updateHeaderStates(animatedLock: false) }
            headerStrip.addSubview(view)
            return view
        }
    }

    // MARK: - Selection

    var shouldWrap: Bool { !usesStaticHeaders }

    private func clamped(_ index: Int) -> Int {
        guard !configuration.items.isEmpty else { return -1 }
        return min(max(index, 0), configuration.items.count - 1)
    }

    /// `Pivot::MoveToPreviousItem` / `MoveToNextItem`. Returns whether the selection moved.
    @discardableResult
    func move(_ direction: FluentPivotNavigationDirection, wrap: Bool) -> Bool {
        let count = configuration.items.count
        guard isEnabled, !configuration.isLocked, count > 0, selectedIndex >= 0 else { return false }
        let target: Int
        switch direction {
        case .previous:
            guard selectedIndex > 0 || wrap else { return false }
            target = selectedIndex == 0 ? count - 1 : selectedIndex - 1
        case .next:
            guard selectedIndex < count - 1 || wrap else { return false }
            target = selectedIndex == count - 1 ? 0 : selectedIndex + 1
        }
        guard target != selectedIndex else { return false }
        commit(to: target, direction: direction, animated: true)
        return true
    }

    @discardableResult
    func moveToEdge(first: Bool) -> Bool {
        guard isEnabled, !configuration.isLocked, !configuration.items.isEmpty else { return false }
        let target = first ? 0 : configuration.items.count - 1
        guard target != selectedIndex else { return false }
        commit(to: target, direction: first ? .previous : .next, animated: true)
        return true
    }

    func select(_ index: Int, animated: Bool) {
        let target = clamped(index)
        guard isEnabled, !configuration.isLocked, target >= 0, target != selectedIndex else { return }
        commit(to: target, direction: nil, animated: animated)
    }

    private func headerTapped(_ index: Int) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        guard !configuration.isLocked, index != selectedIndex else { return }
        // Dynamic headers only lie after the selected one, so a tap always moves forward.
        commit(to: index, direction: usesStaticHeaders ? nil : .next, animated: true)
    }

    fileprivate func commit(to index: Int, direction: FluentPivotNavigationDirection?, animated: Bool) {
        if isPanning { cancelInteractivePan(animated: false) }
        let oldIndex = selectedIndex
        let contentHadFocus = contentHosts.indices.contains(oldIndex) && ownsFirstResponder(in: contentHosts[oldIndex])
        selectedIndex = index
        synchronizeSelectionBinding()
        let resolvedDirection = direction ?? (index >= oldIndex ? .next : .previous)
        let headerShift = previousHeaderPosition(of: index)
        updateHeaderStates(animatedLock: false)
        layoutHeaders(animatedFrom: animated ? headerShift : nil)
        animateContent(from: oldIndex, to: index, direction: resolvedDirection, animated: animated && oldIndex >= 0)
        if contentHadFocus, isEnabled { window?.makeFirstResponder(self) }
        updateNavigationButtons()
        updateAccessibility()
        if oldIndex >= 0 { configuration.onSelectionChanged?(index) }
    }

    private func synchronizeSelectionBinding() {
        guard let binding = configuration.selection, !isWritingBinding, binding.get() != selectedIndex else { return }
        isWritingBinding = true
        defer { isWritingBinding = false }
        binding.set(selectedIndex)
    }

    private func installSelectionObserver() {
        guard let binding = configuration.selection else { return }
        let generation = selectionObservationGeneration
        observedSelection = binding
        selectionObserverID = binding.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectionObservationGeneration == generation,
                      !self.isWritingBinding, let binding = self.configuration.selection else { return }
                let target = self.clamped(binding.get())
                if target != self.selectedIndex, target >= 0 {
                    self.commit(to: target, direction: nil, animated: true)
                } else {
                    self.synchronizeSelectionBinding()
                }
            }
        }
    }

    private func removeSelectionObserver() {
        selectionObservationGeneration &+= 1
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
        selectionObserverID = nil
        observedSelection = nil
    }

    // MARK: - Content motion

    private func animateContent(from oldIndex: Int, to newIndex: Int, direction: FluentPivotNavigationDirection, animated: Bool) {
        showCurrent(exceptOutgoing: animated ? oldIndex : nil)
        guard animated, !context.reduceMotion,
              contentHosts.indices.contains(oldIndex), contentHosts.indices.contains(newIndex),
              let oldLayer = contentHosts[oldIndex].layer, let newLayer = contentHosts[newIndex].layer else {
            showCurrent()
            return
        }
        animationGeneration &+= 1
        let generation = animationGeneration
        isTransitioning = true
        // Pivot_Partial.cpp: moving forward flies the old item out toward the leading edge and
        // the new one in from the trailing edge; RTL mirrors the physical direction.
        let logical: CGFloat = direction == .next ? 1 : -1
        let physical = userInterfaceLayoutDirection == .rightToLeft ? -logical : logical
        let outEnd = CATransform3DMakeTranslation(-physical * FluentPivotMetrics.flyOutDistance, 0, 0)
        let inStart = CATransform3DMakeTranslation(physical * FluentPivotMetrics.flyInDistance, 0, 0)
        let newHost = contentHosts[newIndex]
        let oldHost = contentHosts[oldIndex]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        newHost.isHidden = true
        oldHost.isHidden = false
        CATransaction.commit()

        animationCoordinator.animateTransition([
            FluentLayerAnimationChange(layer: oldLayer, key: "fluent.pivot.out.opacity", keyPath: "opacity",
                fromValue: 1, toValue: 0) { oldLayer.opacity = 0 }
        ], motion: FluentPivotMetrics.flyOutOpacity, animated: true)
        animationCoordinator.animateTransition([
            FluentLayerAnimationChange(layer: oldLayer, key: "fluent.pivot.out.transform", keyPath: "transform",
                fromValue: NSValue(caTransform3D: CATransform3DIdentity), toValue: NSValue(caTransform3D: outEnd)) {
                oldLayer.transform = outEnd
            }
        ], motion: FluentPivotMetrics.flyOutTranslation, animated: true) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            oldHost.isHidden = true
            oldLayer.opacity = 1
            oldLayer.transform = CATransform3DIdentity
            newHost.isHidden = false
            newHost.frame = self.contentFrame()
            CATransaction.commit()
            self.animationCoordinator.animateTransition([
                FluentLayerAnimationChange(layer: newLayer, key: "fluent.pivot.in.opacity", keyPath: "opacity",
                    fromValue: 0, toValue: 1) { newLayer.opacity = 1 }
            ], motion: FluentPivotMetrics.flyInOpacity, animated: true)
            self.animationCoordinator.animateTransition([
                FluentLayerAnimationChange(layer: newLayer, key: "fluent.pivot.in.transform", keyPath: "transform",
                    fromValue: NSValue(caTransform3D: inStart), toValue: NSValue(caTransform3D: CATransform3DIdentity)) {
                    newLayer.transform = CATransform3DIdentity
                }
            ], motion: FluentPivotMetrics.flyInTranslation, animated: true) { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.showCurrent()
            }
        }
    }

    /// Settles every content host. An interrupted transition must not leave an old page visible.
    fileprivate func showCurrent(exceptOutgoing outgoing: Int? = nil) {
        if outgoing == nil {
            isTransitioning = false
            animationGeneration &+= 1
        }
        animationCoordinator.cancelAll(on: contentHosts.compactMap(\.layer))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, host) in contentHosts.enumerated() {
            host.layer?.removeAllAnimations()
            host.layer?.transform = CATransform3DIdentity
            host.layer?.opacity = 1
            host.isHidden = index != selectedIndex && index != outgoing
            host.frame = contentFrame()
        }
        CATransaction.commit()
        updateAccessibility()
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: headerRowTop + FluentPivotMetrics.headerHeight + 120)
    }

    private var headerRowTop: CGFloat {
        guard !titleField.isHidden else { return 0 }
        let insets = FluentPivotMetrics.titleInsets
        return insets.top + ceil(titleField.intrinsicContentSize.height) + insets.bottom
    }

    fileprivate func contentFrame() -> NSRect {
        let width = max(0, contentContainer.bounds.width - 2 * FluentPivotMetrics.itemMargin)
        return NSRect(x: min(FluentPivotMetrics.itemMargin, contentContainer.bounds.width / 2), y: 0,
                      width: width, height: contentContainer.bounds.height)
    }

    override func layout() {
        super.layout()
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        func mirrored(_ rect: NSRect) -> NSRect {
            guard isRTL else { return rect }
            return NSRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        }
        let insets = FluentPivotMetrics.titleInsets
        if !titleField.isHidden {
            let height = ceil(titleField.intrinsicContentSize.height)
            titleField.alignment = isRTL ? .right : .left
            titleField.frame = mirrored(NSRect(x: insets.left, y: insets.top,
                width: max(0, bounds.width - insets.left - insets.right), height: height))
        }
        let top = headerRowTop
        let rowHeight = min(FluentPivotMetrics.headerHeight, max(0, bounds.height - top))
        let leftWidth = min(leftHeaderHost.map { ceil($0.fittingSize.width) } ?? 0, bounds.width)
        let rightWidth = min(rightHeaderHost.map { ceil($0.fittingSize.width) } ?? 0, max(0, bounds.width - leftWidth))
        leftHeaderHost?.frame = mirrored(NSRect(x: 0, y: top, width: leftWidth, height: rowHeight))
        rightHeaderHost?.frame = mirrored(NSRect(x: bounds.width - rightWidth, y: top, width: rightWidth, height: rowHeight))
        let column = NSRect(x: leftWidth, y: top, width: max(0, bounds.width - leftWidth - rightWidth), height: rowHeight)
        headerClipper.frame = mirrored(column)

        let size = FluentPivotMetrics.navigationButtonSize
        let buttonWidth = min(size.width, column.width / 2)
        let buttonHeight = min(size.height, max(0, rowHeight - FluentPivotMetrics.navigationButtonTopMargin))
        let buttonY = top + FluentPivotMetrics.navigationButtonTopMargin
        previousButton.frame = mirrored(NSRect(x: column.minX, y: buttonY, width: buttonWidth, height: buttonHeight))
        nextButton.frame = mirrored(NSRect(x: column.maxX - buttonWidth, y: buttonY, width: buttonWidth, height: buttonHeight))
        previousButton.isRightToLeft = isRTL
        nextButton.isRightToLeft = isRTL

        contentContainer.frame = NSRect(x: 0, y: top + rowHeight, width: bounds.width,
                                        height: max(0, bounds.height - top - rowHeight))
        if !isTransitioning, !isPanning {
            for host in contentHosts { host.frame = contentFrame() }
        }
        layoutHeaders(animatedFrom: nil)
        if isPanning { applyPanVisuals() }
        updateHeaderTracking()
        updateFocusVisual()
    }

    private func headerWidths() -> [CGFloat] {
        headerItems.map { $0.preferredWidth(theme: context.theme) }
    }

    /// The strip-relative leading position the given header occupied before the selection moved.
    private func previousHeaderPosition(of index: Int) -> CGFloat? {
        guard headerItems.indices.contains(index), !usesStaticHeaders else { return nil }
        return logicalPositions[index]
    }

    private var logicalPositions: [CGFloat] = []

    fileprivate func layoutHeaders(animatedFrom previousSelectedPosition: CGFloat?) {
        let widths = headerWidths()
        let total = widths.reduce(0, +)
        let viewport = headerClipper.bounds.width
        let clipped = total > viewport + 0.5
        // Pivot::ShouldUseStaticHeaders: carousel disabled → always static; otherwise static
        // only while every header fits.
        usesStaticHeaders = !configuration.isHeaderItemsCarouselEnabled || !clipped
        var positions = Array(repeating: CGFloat(0), count: widths.count)
        if usesStaticHeaders {
            var x: CGFloat = 0
            for index in widths.indices { positions[index] = x; x += widths[index] }
            func shift(for index: Int) -> CGFloat {
                guard clipped, widths.indices.contains(index) else { return 0 }
                let before = positions[index]
                let after = total - before - widths[index]
                return FluentPivotMetrics.headerShiftOffset(
                    before: before, selected: widths[index], after: after, viewport: viewport)
            }
            staticHeaderOffset = shift(for: selectedIndex)
            // PivotCurveGenerator::GetStaticCurveSegments: during a pan the static strip follows
            // the curve between the current and the neighbouring item's shift offsets.
            if isPanning, let neighbor = panNeighbor, let width = panSectionWidth, width > 0 {
                let fraction = min(abs(panOffset) / width, 1)
                staticHeaderOffset += (shift(for: neighbor) - staticHeaderOffset) * fraction
            }
        } else {
            staticHeaderOffset = 0
            var x: CGFloat = 0
            let start = max(selectedIndex, 0)
            for step in 0..<widths.count {
                let index = (start + step) % widths.count
                positions[index] = x
                x += widths[index]
            }
            // While panning toward the previous item, its header enters from the leading edge.
            if isPanning, panOffset > 0, widths.count > 1 {
                let previous = (start + widths.count - 1) % widths.count
                positions[previous] = -widths[previous]
            }
        }
        logicalPositions = positions
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headerStrip.frame = NSRect(x: 0, y: 0, width: max(viewport, total), height: headerClipper.bounds.height)
        for (index, item) in headerItems.enumerated() {
            let x = positions[index] - staticHeaderOffset + panHeaderShift
            let width = widths[index]
            item.frame = NSRect(x: isRTL ? viewport - x - width : x, y: 0, width: width,
                                height: FluentPivotMetrics.headerHeight)
        }
        CATransaction.commit()
        if let previousSelectedPosition, previousSelectedPosition > 0, !usesStaticHeaders,
           !context.reduceMotion, let layer = headerStrip.layer {
            let shift = isRTL ? -previousSelectedPosition : previousSelectedPosition
            animationCoordinator.animateTransition([
                FluentLayerAnimationChange(layer: layer, key: "fluent.pivot.headerShift", keyPath: "transform",
                    fromValue: NSValue(caTransform3D: CATransform3DMakeTranslation(shift, 0, 0)),
                    toValue: NSValue(caTransform3D: CATransform3DIdentity)) { layer.transform = CATransform3DIdentity }
            ], motion: FluentPivotMetrics.headerShift, animated: true)
        }
        updateNavigationButtons()
    }

    // MARK: - Header states

    private func updateHeaderStates(animatedLock: Bool) {
        for (index, item) in headerItems.enumerated() {
            item.apply(
                theme: context.theme,
                isSelected: index == selectedIndex,
                isEnabled: isEnabled,
                isLocked: configuration.isLocked,
                isRightToLeft: userInterfaceLayoutDirection == .rightToLeft,
                animated: animatedLock && !context.reduceMotion
            )
        }
        updateNavigationButtons()
    }

    /// `Pivot::UpdateVisualStates` navigation-button group.
    func updateNavigationButtons() {
        var showPrevious = false
        var showNext = false
        if isPointerOverHeaders, isEnabled, !configuration.isLocked {
            if usesStaticHeaders {
                let total = headerWidths().reduce(0, +)
                if total > headerClipper.bounds.width + 0.5, configuration.items.count > 1, selectedIndex >= 0 {
                    showPrevious = selectedIndex > 0
                    showNext = selectedIndex < configuration.items.count - 1
                }
            } else {
                showPrevious = true
                showNext = true
            }
        }
        previousButton.isHidden = !showPrevious
        nextButton.isHidden = !showNext
        updateAccessibility()
    }

    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled, ownsFirstResponder(in: self) { window?.makeFirstResponder(nil) }
            if !isEnabled { cancelInteractivePan(animated: false) }
            updateHeaderStates(animatedLock: false)
            updateFocusVisual()
        }
    }

    // MARK: - Pointer

    private func updateHeaderTracking() {
        if let headerTrackingArea { removeTrackingArea(headerTrackingArea) }
        let area = NSTrackingArea(rect: NSRect(x: 0, y: headerRowTop, width: bounds.width,
                                               height: min(FluentPivotMetrics.headerHeight, bounds.height)),
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        headerTrackingArea = area
    }

    func setPointerOverHeaders(_ inside: Bool) {
        guard isPointerOverHeaders != inside else { return }
        isPointerOverHeaders = inside
        updateNavigationButtons()
    }

    /// `m_isMouseOrPenPointerOverHeaders`: touch never reveals the navigation buttons.
    override func mouseEntered(with event: NSEvent) {
        // Enter/exit events carry no subtype; the window's last device decides.
        guard FluentInputDeviceTracker.shared.lastDeviceType(in: window) != .touch else { return }
        setPointerOverHeaders(true)
    }
    override func mouseExited(with event: NSEvent) { setPointerOverHeaders(false) }

    // MARK: - Keyboard and focus

    override var acceptsFirstResponder: Bool { isEnabled && !configuration.items.isEmpty }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        updateFocusVisual()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.updateFocusVisual() }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            self?.updateFocusVisual()
        }
        if window == nil { setPointerOverHeaders(false) }
    }

    /// Pivot::OnHeaderKeyDown: Left/Right (mirrored in RTL), Home and End act on the header.
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        updateFocusVisual()
        if handleSwitchShortcut(event) { return }
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: if !move(isRTL ? .next : .previous, wrap: shouldWrap) { super.keyDown(with: event) }
        case 124: if !move(isRTL ? .previous : .next, wrap: shouldWrap) { super.keyDown(with: event) }
        case 115: if !moveToEdge(first: true) { super.keyDown(with: event) }
        case 119: if !moveToEdge(first: false) { super.keyDown(with: event) }
        default: super.keyDown(with: event)
        }
    }

    /// Pivot::OnKeyDownImpl: Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+PageUp and Ctrl+PageDown switch items
    /// from anywhere inside the Pivot, including focused item content.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEnabled, event.type == .keyDown, ownsFirstResponder(in: self) else {
            return super.performKeyEquivalent(with: event)
        }
        return handleSwitchShortcut(event) || super.performKeyEquivalent(with: event)
    }

    @discardableResult
    func handleSwitchShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.contains(.control), !modifiers.contains(.command), !modifiers.contains(.option) else { return false }
        let shift = modifiers.contains(.shift)
        switch event.keyCode {
        case 48:
            move(shift ? .previous : .next, wrap: shouldWrap)
            return true
        case 121 where !shift:
            move(.next, wrap: shouldWrap)
            return true
        case 116 where !shift:
            move(.previous, wrap: shouldWrap)
            return true
        default:
            return false
        }
    }

    fileprivate func ownsFirstResponder(in root: NSView) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if let editor = responder as? NSTextView, let delegate = editor.delegate as? NSView,
           delegate === root || delegate.isDescendant(of: root) { return true }
        guard let view = responder as? NSView else { return false }
        return view === root || view.isDescendant(of: root)
    }

    /// Default `HeaderFocusVisualPlacement.ItemHeaders`: one focus rectangle around the header strip.
    private func updateFocusVisual() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.strokeColor = context.theme.focusStrokeOuter.cgColor
        focusLayer.lineWidth = context.theme.focusStrokeWidth
        let rect = headerClipper.frame.insetBy(dx: 1, dy: 1)
        focusLayer.frame = bounds
        focusLayer.path = rect.width > 0 && rect.height > 0
            ? CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil) : nil
        focusLayer.opacity = isEnabled && window?.firstResponder === self
            && FluentFocusVisibility.isKeyboardInteraction(in: window) ? 1 : 0
        CATransaction.commit()
    }

    // MARK: - Accessibility

    private func updateAccessibility() {
        if configuration.items.indices.contains(selectedIndex) {
            setAccessibilityValue(configuration.items[selectedIndex].header)
        } else {
            fluentSetDefaultAccessibilityValue("0 items")
        }
        let visibleHeaders: [NSView] = headerItems.filter { !$0.isAccessibilityHiddenForLock }
        let current: [NSView] = contentHosts.indices.contains(selectedIndex) ? [contentHosts[selectedIndex]] : []
        let buttons: [NSView] = [previousButton, nextButton].filter { !$0.isHidden }
        setAccessibilityChildren(visibleHeaders + buttons + current)
        setAccessibilityTabs(visibleHeaders)
    }
}

final class FluentPivotFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// `DefaultPivotHeaderItemStyle`: text plus a bottom selection pipe, with Selected, Unselected,
/// UnselectedLocked, PointerOver, Pressed and Disabled states.
final class FluentPivotHeaderItemView: NSView {
    override var isFlipped: Bool { true }
    let index: Int
    let title: String
    var onPress: ((Int) -> Void)?
    var onPointerChanged: (() -> Void)?
    private(set) var isSelected = false
    private(set) var isPointerOver = false
    private(set) var isPressed = false
    private(set) var isLocked = false
    private(set) var isItemEnabled = true
    private var theme: FluentTheme = .current
    private var isRightToLeft = false
    private let pipeLayer = CALayer()
    private var trackingArea: NSTrackingArea?

    init(title: String, index: Int) {
        self.title = title
        self.index = index
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.Pivot.Header.\(index)")
        wantsLayer = true
        pipeLayer.name = "FluentKit.Pivot.SelectedPipe"
        pipeLayer.cornerRadius = FluentPivotMetrics.pipeCornerRadius
        layer?.addSublayer(pipeLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isAccessibilityHiddenForLock: Bool { isLocked && !isSelected }

    func font(theme: FluentTheme) -> NSFont {
        // PivotHeaderItemThemeFontWeight = SemiLight (350); AppKit resolves the nearest system weight.
        NSFont.systemFont(ofSize: FluentPivotMetrics.headerFontSize * theme.typography.scale,
                          weight: NSFont.Weight(rawValue: -0.2))
    }

    private func attributes(theme: FluentTheme, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font(theme: theme), .foregroundColor: color,
         .kern: FluentPivotMetrics.headerKern * theme.typography.scale]
    }

    func textWidth(theme: FluentTheme) -> CGFloat {
        ceil((title as NSString).size(withAttributes: attributes(theme: theme, color: .black)).width)
    }

    func preferredWidth(theme: FluentTheme) -> CGFloat {
        textWidth(theme: theme) + 2 * FluentPivotMetrics.headerPadding
    }

    /// Theme foregrounds follow the legacy SystemControl Base ramp: Medium (60%), MediumHigh
    /// (80%), High (100%) and MediumLow (40%) for Disabled.
    var foregroundColor: NSColor {
        let base: NSColor = theme.isDark ? .white : .black
        if theme.isHighContrast {
            return isItemEnabled ? (isSelected ? theme.textPrimary : theme.textSecondary) : theme.textDisabled
        }
        if !isItemEnabled { return base.withAlphaComponent(0.4) }
        if isSelected { return base.withAlphaComponent(isPressed || isPointerOver ? 0.8 : 1) }
        return base.withAlphaComponent(isPressed || isPointerOver ? 0.8 : 0.6)
    }

    var showsPipe: Bool { isSelected && isItemEnabled }

    func apply(theme: FluentTheme, isSelected: Bool, isEnabled: Bool, isLocked: Bool, isRightToLeft: Bool, animated: Bool) {
        self.theme = theme
        self.isSelected = isSelected
        self.isItemEnabled = isEnabled
        self.isRightToLeft = isRightToLeft
        let wasHidden = self.isLocked && !wasSelectedForLock
        self.isLocked = isLocked
        wasSelectedForLock = isSelected
        if !isEnabled { isPointerOver = false; isPressed = false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pipeLayer.backgroundColor = (theme.isHighContrast ? theme.accent : theme.accentFillDefault).cgColor
        pipeLayer.isHidden = !showsPipe
        CATransaction.commit()
        applyLockState(hidden: isAccessibilityHiddenForLock, wasHidden: wasHidden, animated: animated)
        setAccessibilityValue(isSelected)
        setAccessibilityEnabled(isEnabled && (!isLocked || isSelected))
        needsLayout = true
        needsDisplay = true
    }

    private var wasSelectedForLock = false

    /// UnselectedLocked translates the header by `PivotHeaderItemLockedTranslation` and hides it,
    /// with a 0.33s generated transition to and from Unselected.
    private func applyLockState(hidden: Bool, wasHidden: Bool, animated: Bool) {
        guard let layer else { return }
        let offset = (isRightToLeft ? -1 : 1) * FluentPivotMetrics.lockedTranslation
        let targetTransform = hidden ? CATransform3DMakeTranslation(offset, 0, 0) : CATransform3DIdentity
        let targetOpacity: Float = hidden ? 0 : 1
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || hidden == wasHidden)
        CATransaction.setAnimationDuration(FluentPivotMetrics.lockedTransition)
        layer.transform = targetTransform
        layer.opacity = targetOpacity
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let textWidth = min(self.textWidth(theme: theme), max(0, bounds.width - 2 * FluentPivotMetrics.headerPadding))
        let x = isRightToLeft ? bounds.width - FluentPivotMetrics.headerPadding - textWidth : FluentPivotMetrics.headerPadding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pipeLayer.frame = NSRect(
            x: x,
            y: max(0, bounds.height - FluentPivotMetrics.pipeBottomMargin - FluentPivotMetrics.pipeHeight),
            width: max(0, textWidth),
            height: min(FluentPivotMetrics.pipeHeight, bounds.height)
        )
        CATransaction.commit()
        updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        let string = NSAttributedString(string: title, attributes: attributes(theme: theme, color: foregroundColor))
        let size = string.size()
        let x = isRightToLeft ? bounds.width - FluentPivotMetrics.headerPadding - ceil(size.width) : FluentPivotMetrics.headerPadding
        string.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isAccessibilityHiddenForLock ? nil : super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isItemEnabled else { return }
        isPointerOver = true
        needsDisplay = true
        onPointerChanged?()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        isPressed = false
        needsDisplay = true
        onPointerChanged?()
    }

    override func mouseDown(with event: NSEvent) {
        guard isItemEnabled else { return }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?(index) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isItemEnabled, !isAccessibilityHiddenForLock else { return false }
        onPress?(index)
        return true
    }
}

/// `PreviousTemplate` / `NextTemplate`: 20×36 Base-ramp backgrounds with a 12pt chevron.
final class FluentPivotNavigationButton: NSView {
    override var isFlipped: Bool { true }
    let direction: FluentPivotNavigationDirection
    var onClick: (() -> Void)?
    var theme: FluentTheme = .current { didSet { if oldValue != theme { updateAppearance() } } }
    var isRightToLeft = false { didSet { if oldValue != isRightToLeft { updateSymbol() } } }
    private let imageView = NSImageView()
    private(set) var isPointerOver = false
    private(set) var isPressed = false
    private var trackingArea: NSTrackingArea?

    init(direction: FluentPivotNavigationDirection) {
        self.direction = direction
        super.init(frame: .zero)
        wantsLayer = true
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        fluentSetDefaultAccessibilityLabel(direction == .previous ? "Previous" : "Next")
        updateSymbol()
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { false }

    private func updateSymbol() {
        // MirroredWhenRightToLeft: the glyph points toward its logical direction.
        let pointsLeft = (direction == .previous) != isRightToLeft
        let name = pointsLeft ? "chevron.left" : "chevron.right"
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        imageView.image?.isTemplate = true
    }

    var backgroundColor: NSColor {
        let base: NSColor = theme.isDark ? .white : .black
        return base.withAlphaComponent(isPressed ? 0.8 : isPointerOver ? 0.6 : 0.4)
    }

    private func updateAppearance() {
        let alt: NSColor = theme.isDark ? .black : .white
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = backgroundColor.cgColor
        CATransaction.commit()
        imageView.contentTintColor = alt.withAlphaComponent(0.8)
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isPointerOver = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; isPressed = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) { isPressed = true; updateAppearance() }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isHidden else { return false }
        onClick?()
        return true
    }
}

// MARK: - Interactive pan (trackpad, direct touch, wheel)

extension FluentPivotControl {
    /// Projection window used to emulate ScrollViewer inertia for MandatorySingle snapping.
    static let panProjectionTime: CGFloat = 0.25
    private static let panSettleKey = "fluent.pivot.pan"

    var panSectionWidth: CGFloat? {
        let width = contentContainer.bounds.width
        return width > 0 ? width : nil
    }

    /// The item revealed by the current pan, honoring carousel-only wrapping.
    var panNeighbor: Int? {
        neighbor(towardNext: panOffset < 0, active: panOffset != 0)
    }

    private func neighbor(towardNext: Bool, active: Bool) -> Int? {
        let count = configuration.items.count
        guard active, count > 1, selectedIndex >= 0 else { return nil }
        if towardNext {
            return selectedIndex < count - 1 ? selectedIndex + 1 : (shouldWrap ? 0 : nil)
        }
        return selectedIndex > 0 ? selectedIndex - 1 : (shouldWrap ? count - 1 : nil)
    }

    var canBeginInteractivePan: Bool {
        isEnabled && !configuration.isLocked && configuration.items.count > 1 && selectedIndex >= 0
            && panSectionWidth != nil
    }

    /// Starts (or takes over a settling) pan. Returns the logical offset the new gesture starts from.
    @discardableResult
    func beginInteractivePan() -> CGFloat? {
        guard canBeginInteractivePan else { return nil }
        animationCoordinator.cancelValueAnimation(key: Self.panSettleKey)
        if isPanning { return panOffsetBeforeDamping }
        if isTransitioning { showCurrent() }
        if let layer = headerStrip.layer { animationCoordinator.cancel(layer: layer, key: "fluent.pivot.headerShift") }
        isPanning = true
        panOffset = 0
        return 0
    }

    /// Applies a logical translation. ScrollViewer `MandatorySingle` limits travel to one item;
    /// past a non-wrapping end the offset is damped like an elastic overpan.
    func updateInteractivePan(translation: CGFloat) {
        guard isPanning, let width = panSectionWidth else { return }
        panOffset = max(-width, min(width, translation))
        if panNeighbor == nil, panOffset != 0 {
            let magnitude = abs(translation)
            let damped = (1 - 1 / (magnitude * 0.55 / width + 1)) * width
            panOffset = translation < 0 ? -damped : damped
        }
        applyPanVisuals()
    }

    /// Ends a pan with a logical velocity in points per second. The projected position decides
    /// between finishing on the neighbouring item and snapping back (`PivotStateMachine`
    /// `InFinishTransition` / `InSnapBackInertial`).
    func endInteractivePan(velocity: CGFloat) {
        guard isPanning, let width = panSectionWidth else { return }
        let projected = panOffset + velocity * Self.panProjectionTime
        let sameSide = panOffset == 0 || (projected < 0) == (panOffset < 0)
        let target = sameSide && abs(projected) > width / 2
            ? neighbor(towardNext: projected < 0, active: true) : nil
        let final: CGFloat = target == nil ? 0 : (projected < 0 ? -width : width)
        settlePan(to: final, velocity: velocity, target: target)
    }

    func cancelInteractivePan(animated: Bool) {
        guard isPanning else { return }
        if animated {
            settlePan(to: 0, velocity: 0, target: nil)
        } else {
            animationCoordinator.cancelValueAnimation(key: Self.panSettleKey)
            finishPan(target: nil, direction: nil)
        }
    }

    private func settlePan(to final: CGFloat, velocity: CGFloat, target: Int?) {
        let direction: FluentPivotNavigationDirection? = target == nil ? nil : (final < 0 ? .next : .previous)
        let distance = abs(final - panOffset)
        guard distance > 0.5, !context.reduceMotion else {
            finishPan(target: target, direction: direction)
            return
        }
        // Velocity-matched deceleration, bounded by the 0.4s flick duration of PivotStateMachine.
        let duration = min(max(Double(distance / max(abs(velocity), 1)), 0.15), 0.4)
        animationCoordinator.animateValue(
            key: Self.panSettleKey,
            from: panOffset,
            to: final,
            motion: FluentMotionToken(duration: duration, curve: .controlFastOutSlowIn),
            animated: true,
            update: { [weak self] value in
                guard let self, self.isPanning else { return }
                self.panOffset = value
                self.applyPanVisuals()
            },
            completion: { [weak self] in self?.finishPan(target: target, direction: direction) }
        )
    }

    private func finishPan(target: Int?, direction: FluentPivotNavigationDirection?) {
        guard isPanning else { return }
        isPanning = false
        panOffset = 0
        panHeaderShift = 0
        if let target, target != selectedIndex {
            // Content already rests on the target, so the commit itself does not fly.
            commit(to: target, direction: direction, animated: false)
        } else {
            showCurrent()
            layoutHeaders(animatedFrom: nil)
        }
    }

    /// Places the selected and neighbouring items and moves the headers with the pan. Dynamic
    /// headers travel by the outgoing (next) or incoming (previous) header's width per section,
    /// as in `PivotCurveGenerator::GetDynamicCurveSegments`.
    func applyPanVisuals() {
        guard isPanning, let width = panSectionWidth else { return }
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let base = contentFrame()
        let neighbor = panNeighbor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, host) in contentHosts.enumerated() {
            host.layer?.removeAllAnimations()
            host.layer?.transform = CATransform3DIdentity
            host.layer?.opacity = 1
            let logicalX: CGFloat?
            if index == selectedIndex {
                logicalX = panOffset
            } else if index == neighbor {
                logicalX = panOffset + (panOffset < 0 ? width : -width)
            } else {
                logicalX = nil
            }
            host.isHidden = logicalX == nil
            if let logicalX { host.frame = base.offsetBy(dx: isRTL ? -logicalX : logicalX, dy: 0) }
        }
        CATransaction.commit()
        layoutHeaders(animatedFrom: nil)
        var headerShift: CGFloat = 0
        if !usesStaticHeaders, let neighbor, headerItems.indices.contains(selectedIndex) {
            let fraction = max(-1, min(1, panOffset / width))
            let travel = headerItems[fraction < 0 ? selectedIndex : neighbor].preferredWidth(theme: context.theme)
            headerShift = fraction * travel
        }
        if panHeaderShift != headerShift {
            panHeaderShift = headerShift
            layoutHeaders(animatedFrom: nil)
        }
    }

    // MARK: Input

    fileprivate func installPanDriver() {
        let driver = FluentPanGestureDriver(view: self, axis: .horizontal)
        driver.onBeginAllowed = { [weak self] in self?.canBeginInteractivePan ?? false }
        driver.onBegin = { [weak self] in self?.beginInteractivePan() }
        driver.onChange = { [weak self] translation in self?.updateInteractivePan(translation: translation) }
        driver.onEnd = { [weak self] velocity in self?.endInteractivePan(velocity: velocity) }
        driver.onCancel = { [weak self] in self?.cancelInteractivePan(animated: true) }
        // A horizontal mouse wheel without gesture phases moves one item per burst.
        driver.onDiscreteStep = { [weak self] direction, _ in
            guard let self, !self.configuration.isLocked else { return false }
            return self.move(direction < 0 ? .next : .previous, wrap: self.shouldWrap)
        }
        panDriver = driver
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, panDriver.handleScrollWheel(event, replayUnclaimed: forwardScrollWheel) else {
            super.scrollWheel(with: event)
            return
        }
    }

    private func forwardScrollWheel(_ event: NSEvent) { super.scrollWheel(with: event) }

    /// Undamped logical translation equivalent to the current offset, so a resumed gesture
    /// continues naturally while an elastic overpan is shown.
    fileprivate var panOffsetBeforeDamping: CGFloat {
        guard let width = panSectionWidth, panNeighbor == nil, panOffset != 0 else { return panOffset }
        let fraction = min(abs(panOffset) / width, 0.999)
        let raw = (1 / (1 - fraction) - 1) * width / 0.55
        return panOffset < 0 ? -raw : raw
    }
}
