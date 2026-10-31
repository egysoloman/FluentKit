import AppKit

/// What happens to an open SwipeControl after one of its items is invoked
/// (`SwipeBehaviorOnInvoked`). `.automatic` closes in both modes.
public enum FluentSwipeBehaviorOnInvoked: Hashable, Sendable {
    case automatic
    case close
    case remainOpen
}

/// `SwipeMode`: Reveal shows a set of commands; Execute runs the first item once the swipe passes
/// its threshold.
public enum FluentSwipeMode: Hashable, Sendable {
    case reveal
    case execute
}

public struct FluentSwipeItem {
    public var text: String
    public var systemImage: String?
    public var background: NSColor?
    public var foreground: NSColor?
    public var behaviorOnInvoked: FluentSwipeBehaviorOnInvoked
    public var onInvoked: () -> Void

    public init(
        _ text: String,
        systemImage: String? = nil,
        background: NSColor? = nil,
        foreground: NSColor? = nil,
        behaviorOnInvoked: FluentSwipeBehaviorOnInvoked = .automatic,
        onInvoked: @escaping () -> Void
    ) {
        self.text = text
        self.systemImage = systemImage
        self.background = background
        self.foreground = foreground
        self.behaviorOnInvoked = behaviorOnInvoked
        self.onInvoked = onInvoked
    }
}

public struct FluentSwipeItems {
    public var mode: FluentSwipeMode
    public var items: [FluentSwipeItem]

    public init(mode: FluentSwipeMode = .reveal, _ items: [FluentSwipeItem]) {
        self.mode = mode
        self.items = items
    }
}

/// A WinUI-style SwipeControl. Swiping the content with a finger (macOS 27 touch screens) or a
/// two-finger trackpad swipe reveals command items behind it. As in WinUI, mouse drags do not
/// swipe; VoiceOver exposes every item as a custom action instead.
///
/// Horizontal (`leftItems`/`rightItems`, mirrored in RTL) and vertical (`topItems`/`bottomItems`)
/// items cannot be combined; horizontal items win, matching WinUI which rejects the mix.
public struct FluentSwipeControl<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let configuration: FluentSwipeConfiguration
    private let content: Content

    public init(
        leftItems: FluentSwipeItems? = nil,
        rightItems: FluentSwipeItems? = nil,
        topItems: FluentSwipeItems? = nil,
        bottomItems: FluentSwipeItems? = nil,
        @FluentViewBuilder content: () -> Content
    ) {
        let horizontal = !(leftItems?.items.isEmpty ?? true) || !(rightItems?.items.isEmpty ?? true)
            || ((topItems?.items.isEmpty ?? true) && (bottomItems?.items.isEmpty ?? true))
        configuration = FluentSwipeConfiguration(
            isHorizontal: horizontal,
            near: horizontal ? leftItems : topItems,
            far: horizontal ? rightItems : bottomItems
        )
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentSwipeControlView(content: FluentAnyView(content), configuration: configuration, context: context)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let view = view as? FluentSwipeControlView else { return false }
        view.update(content: FluentAnyView(content), configuration: configuration, context: context)
        return true
    }
}

struct FluentSwipeConfiguration {
    var isHorizontal: Bool
    /// Leading (left, mirrored in RTL) or top items, revealed by a positive offset.
    var near: FluentSwipeItems?
    /// Trailing (right) or bottom items, revealed by a negative offset.
    var far: FluentSwipeItems?

    func items(for side: FluentSwipeSide) -> FluentSwipeItems? {
        let items = side == .near ? near : far
        return items?.items.isEmpty == false ? items : nil
    }
}

enum FluentSwipeSide {
    case near
    case far
}

/// Source-derived SwipeControl metrics (`SwipeControl.cpp`, `SwipeControl_themeresources.xaml`).
enum FluentSwipeMetrics {
    /// `c_ThresholdValue`: opening needs min(items extent - 1, 100).
    static let threshold: CGFloat = 100
    static let itemMinWidth: CGFloat = 68
    static let itemMinHeight: CGFloat = 40
    static let itemContentInsets = NSEdgeInsets(top: 4, left: 4, bottom: 2, right: 4)
    static let iconSize: CGFloat = 16
    static let labelFontSize: CGFloat = 12
    static let projectionTime: CGFloat = 0.25
}

final class FluentSwipeControlView: NSView {
    override var isFlipped: Bool { true }

    private static weak var lastOpened: FluentSwipeControlView?

    private(set) var configuration: FluentSwipeConfiguration
    private var context: FluentRenderContext
    let contentHost: FluentViewHost<FluentAnyView>
    private let itemsContainer = FluentSwipeFlippedView()
    private(set) var itemButtons: [FluentSwipeItemButton] = []
    private var itemsSide: FluentSwipeSide?
    private(set) var panDriver: FluentPanGestureDriver!
    private let animationCoordinator = FluentAnimationCoordinator()
    private var dismissMonitor: Any?

    /// Logical offset of the content along the swipe axis. Positive reveals near items.
    private(set) var offset: CGFloat = 0
    private(set) var isOpen = false
    private(set) var isInteracting = false
    private(set) var isThresholdReached = false
    private var wasOpenAtGestureStart = false
    private static let settleKey = "fluent.swipe.settle"

    init(content: FluentAnyView, configuration: FluentSwipeConfiguration, context: FluentRenderContext) {
        self.configuration = configuration
        self.context = context
        contentHost = FluentViewHost(content, context: context)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.SwipeControl")
        wantsLayer = true
        layer?.masksToBounds = true
        itemsContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.SwipeControl.Items")
        itemsContainer.wantsLayer = true
        addSubview(itemsContainer)
        contentHost.identifier = NSUserInterfaceItemIdentifier("FluentKit.SwipeControl.Content")
        addSubview(contentHost)
        setAccessibilityElement(false)
        animationCoordinator.reduceMotion = context.reduceMotion
        installPanDriver()
        updateAccessibilityActions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeDismissMonitor() }

    func update(content: FluentAnyView, configuration next: FluentSwipeConfiguration, context: FluentRenderContext) {
        let axisChanged = next.isHorizontal != configuration.isHorizontal
        configuration = next
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        contentHost.update(content, context: context)
        if axisChanged {
            closeWithoutAnimation()
            if let recognizer = panDriver.touchRecognizer { removeGestureRecognizer(recognizer) }
            installPanDriver()
        } else if itemsSide.map({ configuration.items(for: $0) == nil }) ?? false {
            closeWithoutAnimation()
        } else if let itemsSide {
            buildItems(for: itemsSide)
        }
        updateAccessibilityActions()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize { contentHost.fittingSize }

    // MARK: Layout

    override func layout() {
        super.layout()
        itemsContainer.frame = bounds
        applyOffset()
    }

    private var isRTL: Bool { configuration.isHorizontal && userInterfaceLayoutDirection == .rightToLeft }

    /// Extent of the control along the swipe axis.
    private var axisLength: CGFloat { configuration.isHorizontal ? bounds.width : bounds.height }

    /// Extent of the revealed command panel (`SwipeContentStackPanel`).
    var itemsExtent: CGFloat {
        guard let side = itemsSide, let items = configuration.items(for: side) else { return 0 }
        let extents = itemButtons.map { configuration.isHorizontal ? $0.preferredWidth : $0.preferredHeight }
        return items.mode == .execute ? (extents.first ?? 0) : extents.reduce(0, +)
    }

    private func applyOffset() {
        let along = offset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if configuration.isHorizontal {
            contentHost.frame = NSRect(x: isRTL ? -along : along, y: 0, width: bounds.width, height: bounds.height)
        } else {
            contentHost.frame = NSRect(x: 0, y: along, width: bounds.width, height: bounds.height)
        }
        layoutItems()
        CATransaction.commit()
    }

    /// Places items from the revealed edge. Reveal stacks them along the axis; Execute stretches
    /// the first item's background over the whole revealed area.
    private func layoutItems() {
        guard let side = itemsSide, let items = configuration.items(for: side) else {
            itemsContainer.isHidden = true
            return
        }
        itemsContainer.isHidden = offset == 0 && !isOpen
        let revealed = abs(offset)
        let cross = configuration.isHorizontal ? bounds.height : bounds.width
        func frame(start: CGFloat, extent: CGFloat) -> NSRect {
            // `start` is measured from the revealed edge inward.
            let fromNear = side == .near ? start : axisLength - start - extent
            if configuration.isHorizontal {
                let x = isRTL ? bounds.width - fromNear - extent : fromNear
                return NSRect(x: x, y: 0, width: extent, height: cross)
            }
            return NSRect(x: 0, y: fromNear, width: cross, height: extent)
        }
        if items.mode == .execute, let button = itemButtons.first {
            button.frame = frame(start: 0, extent: max(revealed, 0))
            button.isExecuteItem = true
            button.isThresholdReached = isThresholdReached
            button.revealEdgeIsNear = side == .near
            button.isHorizontal = configuration.isHorizontal
            button.contentExtent = configuration.isHorizontal ? button.preferredWidth : button.preferredHeight
            return
        }
        var position: CGFloat = 0
        for button in itemButtons {
            let extent = configuration.isHorizontal ? button.preferredWidth : button.preferredHeight
            button.frame = frame(start: position, extent: extent)
            button.isExecuteItem = false
            button.isHorizontal = configuration.isHorizontal
            position += extent
        }
    }

    private func buildItems(for side: FluentSwipeSide) {
        let items = configuration.items(for: side)?.items ?? []
        let mode = configuration.items(for: side)?.mode ?? .reveal
        let visible = mode == .execute ? Array(items.prefix(1)) : items
        if itemsSide != side || itemButtons.count != visible.count {
            itemButtons.forEach { $0.removeFromSuperview() }
            itemButtons = visible.indices.map { index in
                let button = FluentSwipeItemButton(index: index)
                button.onPress = { [weak self] index in self?.invokeItem(at: index) }
                itemsContainer.addSubview(button)
                return button
            }
        }
        itemsSide = side
        for (button, item) in zip(itemButtons, visible) { button.configure(item: item, theme: context.theme) }
        needsLayout = true
    }

    // MARK: Pan

    private func installPanDriver() {
        let driver = FluentPanGestureDriver(view: self, axis: configuration.isHorizontal ? .horizontal : .vertical)
        driver.onBeginAllowed = { [weak self] in self?.canBeginSwipe ?? false }
        driver.onBegin = { [weak self] in self?.beginSwipe() }
        driver.onChange = { [weak self] translation in self?.updateSwipe(translation: translation) }
        driver.onEnd = { [weak self] velocity in self?.endSwipe(velocity: velocity) }
        driver.onCancel = { [weak self] in self?.endSwipe(velocity: 0) }
        panDriver = driver
    }

    var canBeginSwipe: Bool {
        isEnabledForInput && (configuration.near != nil || configuration.far != nil)
    }

    private var isEnabledForInput: Bool {
        var view: NSView? = self
        while let current = view {
            if let control = current as? NSControl, !control.isEnabled { return false }
            view = current.superview
        }
        return true
    }

    @discardableResult
    func beginSwipe() -> CGFloat? {
        guard canBeginSwipe else { return nil }
        animationCoordinator.cancelValueAnimation(key: Self.settleKey)
        if let other = Self.lastOpened, other !== self { other.close() }
        isInteracting = true
        wasOpenAtGestureStart = isOpen
        return offset
    }

    /// Applies a logical translation. A side without items stays closed; an open side cannot be
    /// dragged past zero onto the other side within the same gesture (`blockNear/FarContent`).
    func updateSwipe(translation: CGFloat) {
        guard isInteracting else { return }
        var value = translation
        if wasOpenAtGestureStart, let side = itemsSide {
            value = side == .near ? max(value, 0) : min(value, 0)
        }
        if value > 0, configuration.items(for: .near) == nil { value = 0 }
        if value < 0, configuration.items(for: .far) == nil { value = 0 }
        if value != 0 {
            let side: FluentSwipeSide = value > 0 ? .near : .far
            if itemsSide != side { buildItems(for: side); layoutSubtreeIfNeeded() }
        }
        offset = max(-axisLength, min(axisLength, value))
        updateThresholdReached()
        applyOffset()
    }

    /// `SwipeControl::UpdateThresholdReached`.
    private func updateThresholdReached() {
        let extent = itemsExtent - 1
        if !wasOpenAtGestureStart {
            isThresholdReached = abs(offset) > min(extent, FluentSwipeMetrics.threshold)
        } else {
            isThresholdReached = abs(offset) < extent
        }
    }

    /// Resting decision equivalent to the source's inertia modifiers: opening needs the projected
    /// position past the threshold; once open, any closing movement closes; a flick across zero
    /// closes without opening the other side.
    func endSwipe(velocity: CGFloat) {
        guard isInteracting else { return }
        isInteracting = false
        let projected = offset + velocity * FluentSwipeMetrics.projectionTime
        let extent = itemsExtent
        var open: Bool
        if offset == 0 || (projected < 0) != (offset < 0) {
            open = false
        } else if wasOpenAtGestureStart {
            open = abs(projected) >= extent - 1
        } else {
            open = abs(projected) > min(extent - 1, FluentSwipeMetrics.threshold)
        }
        if extent <= 0 { open = false }
        let target = open ? (offset < 0 ? -extent : extent) : 0
        settle(to: target, velocity: velocity)
    }

    private func settle(to target: CGFloat, velocity: CGFloat) {
        let distance = abs(target - offset)
        guard distance > 0.5, !context.reduceMotion else {
            offset = target
            applyOffset()
            didComeToRest()
            return
        }
        let duration = min(max(Double(distance / max(abs(velocity), 1)), 0.15), 0.3)
        animationCoordinator.animateValue(
            key: Self.settleKey, from: offset, to: target,
            motion: FluentMotionToken(duration: duration, curve: .controlFastOutSlowIn), animated: true,
            update: { [weak self] value in
                guard let self else { return }
                self.offset = value
                self.applyOffset()
            },
            completion: { [weak self] in self?.didComeToRest() }
        )
    }

    /// `SwipeControl::IdleStateEntered`: an open Execute side invokes its item; a closed control
    /// drops its revealed items.
    private func didComeToRest() {
        setOpen(offset != 0)
        if isOpen, let side = itemsSide, configuration.items(for: side)?.mode == .execute {
            invokeItem(at: 0)
        } else if !isOpen {
            itemButtons.forEach { $0.removeFromSuperview() }
            itemButtons = []
            itemsSide = nil
            isThresholdReached = false
            applyOffset()
        }
    }

    private func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        isOpen = open
        if open {
            if let other = Self.lastOpened, other !== self { other.close() }
            Self.lastOpened = self
            installDismissMonitor()
        } else {
            if Self.lastOpened === self { Self.lastOpened = nil }
            removeDismissMonitor()
        }
        updateAccessibilityActions()
    }

    // MARK: Commands

    func invokeItem(at index: Int) {
        guard let side = itemsSide, let items = configuration.items(for: side), items.items.indices.contains(index) else { return }
        let item = items.items[index]
        item.onInvoked()
        if item.behaviorOnInvoked != .remainOpen { close() }
    }

    /// Closes with animation (`SwipeControl::Close`).
    public func close() {
        animationCoordinator.cancelValueAnimation(key: Self.settleKey)
        isInteracting = false
        guard offset != 0 || isOpen else { return }
        settle(to: 0, velocity: 0)
    }

    func closeWithoutAnimation() {
        animationCoordinator.cancelValueAnimation(key: Self.settleKey)
        isInteracting = false
        offset = 0
        applyOffset()
        didComeToRest()
    }

    /// Any press outside the revealed items closes the control; a press on its content is eaten
    /// (the template's `InputEater`), presses elsewhere in the window pass through.
    private func installDismissMonitor() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isOpen, event.window === self.window else { return event }
            return self.handleDismissingPress(at: self.convert(event.locationInWindow, from: nil)) ? nil : event
        }
    }

    /// Returns true when the press should be consumed.
    @discardableResult
    func handleDismissingPress(at point: NSPoint) -> Bool {
        guard isOpen else { return false }
        if itemButtons.contains(where: { !$0.isHidden && $0.frame.contains(itemsContainer.convert(point, from: self)) }) {
            return false
        }
        close()
        return contentHost.frame.contains(point)
    }

    private func removeDismissMonitor() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closeWithoutAnimation() }
    }

    override func scrollWheel(with event: NSEvent) {
        if !panDriver.handleScrollWheel(event) { super.scrollWheel(with: event) }
    }

    // MARK: Accessibility

    /// VoiceOver cannot swipe, so every item on both sides is exposed as a custom action.
    private func updateAccessibilityActions() {
        var actions: [NSAccessibilityCustomAction] = []
        for side in [FluentSwipeSide.near, .far] {
            guard let items = configuration.items(for: side) else { continue }
            for (index, item) in items.items.enumerated() where items.mode == .reveal || index == 0 {
                actions.append(NSAccessibilityCustomAction(name: item.text) { [weak self] in
                    guard let self else { return false }
                    item.onInvoked()
                    if item.behaviorOnInvoked != .remainOpen { self.close() }
                    return true
                })
            }
        }
        contentHost.setAccessibilityCustomActions(actions)
    }
}

final class FluentSwipeFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// `SwipeItemStyle`: an AppBarButton-like command with a 16pt icon above a 12pt label, MinWidth
/// 68 and MinHeight 40, filled with the item background (pressed: ControlAltFillQuarternary).
final class FluentSwipeItemButton: NSView {
    override var isFlipped: Bool { true }
    let index: Int
    var onPress: ((Int) -> Void)?
    private(set) var item: FluentSwipeItem?
    private var theme: FluentTheme = .current
    private(set) var isPressed = false
    var isExecuteItem = false { didSet { if oldValue != isExecuteItem { needsDisplay = true } } }
    var isThresholdReached = false { didSet { if oldValue != isThresholdReached { needsDisplay = true } } }
    var revealEdgeIsNear = true
    var isHorizontal = true
    var contentExtent: CGFloat = 0

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.SwipeControl.Item.\(index)")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: FluentSwipeItem, theme: FluentTheme) {
        self.item = item
        self.theme = theme
        setAccessibilityLabel(item.text)
        needsDisplay = true
    }

    private var labelFont: NSFont { NSFont.systemFont(ofSize: FluentSwipeMetrics.labelFontSize * theme.typography.scale) }

    private var labelSize: NSSize {
        (item?.text as NSString?)?.size(withAttributes: [.font: labelFont]) ?? .zero
    }

    var preferredWidth: CGFloat {
        let insets = FluentSwipeMetrics.itemContentInsets
        return max(FluentSwipeMetrics.itemMinWidth, ceil(max(labelSize.width, FluentSwipeMetrics.iconSize)) + insets.left + insets.right)
    }

    var preferredHeight: CGFloat {
        let insets = FluentSwipeMetrics.itemContentInsets
        let icon = item?.systemImage == nil ? 0 : FluentSwipeMetrics.iconSize + 2
        return max(FluentSwipeMetrics.itemMinHeight, ceil(labelSize.height) + icon + insets.top + insets.bottom)
    }

    var backgroundColor: NSColor {
        if isExecuteItem {
            return isThresholdReached ? (item?.background ?? theme.accentFillDefault) : theme.controlFillTertiary
        }
        if isPressed { return theme.controlAltFillQuaternary }
        return item?.background ?? theme.controlFillTertiary
    }

    var foregroundColor: NSColor {
        if isExecuteItem {
            return isThresholdReached ? (item?.foreground ?? theme.textOnAccent) : theme.textSecondary
        }
        return item?.foreground ?? theme.textPrimary
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        guard let item else { return }
        // Execute items keep their command at the revealed edge while the background stretches.
        var content = bounds
        if isExecuteItem, contentExtent > 0 {
            if isHorizontal {
                let width = min(contentExtent, bounds.width)
                let atLeft = revealEdgeIsNear != (userInterfaceLayoutDirection == .rightToLeft)
                content = NSRect(x: atLeft ? 0 : bounds.width - width, y: 0, width: width, height: bounds.height)
            } else {
                let height = min(contentExtent, bounds.height)
                content = NSRect(x: 0, y: revealEdgeIsNear ? 0 : bounds.height - height, width: bounds.width, height: height)
            }
        }
        let color = foregroundColor
        let label = NSAttributedString(string: item.text, attributes: [
            .font: labelFont, .foregroundColor: color,
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()
        ])
        let textSize = label.size()
        let iconHeight: CGFloat = item.systemImage == nil ? 0 : FluentSwipeMetrics.iconSize + 2
        let total = iconHeight + textSize.height
        var y = content.midY - total / 2
        if let name = item.systemImage,
           let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: FluentSwipeMetrics.iconSize * 0.8, weight: .regular)) {
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let side = FluentSwipeMetrics.iconSize
            let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            tinted.draw(in: NSRect(x: content.midX - size.width / 2, y: y + (side - size.height) / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            y += iconHeight
        }
        label.draw(in: NSRect(x: content.minX, y: y, width: content.width, height: textSize.height))
    }

    override func mouseDown(with event: NSEvent) {
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
        onPress?(index)
        return true
    }
}
