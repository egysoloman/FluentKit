import AppKit

/// One top-level entry in a WinUI-style in-window MenuBar. This is intentionally separate from
/// the native macOS application menu managed by `NSApplication.mainMenu`.
public struct FluentMenuBarItem {
    public let id: AnyHashable
    public let title: String
    public let items: [FluentMenuItem]
    public let isEnabled: Bool
    public let accessKey: Character?

    public init(
        id: AnyHashable? = nil,
        _ title: String,
        isEnabled: Bool = true,
        accessKey: Character? = nil,
        items: [FluentMenuItem]
    ) {
        self.id = id ?? AnyHashable(title)
        self.title = title
        self.items = items
        self.isEnabled = isEnabled
        self.accessKey = accessKey
    }

    public init(
        id: AnyHashable? = nil,
        _ title: String,
        isEnabled: Bool = true,
        accessKey: Character? = nil,
        @FluentMenuBuilder items: () -> [FluentMenuItem]
    ) {
        self.init(id: id, title, isEnabled: isEnabled, accessKey: accessKey, items: items())
    }
}

@resultBuilder
public enum FluentMenuBarBuilder {
    public static func buildExpression(_ item: FluentMenuBarItem) -> [FluentMenuBarItem] { [item] }
    public static func buildExpression(_ items: [FluentMenuBarItem]) -> [FluentMenuBarItem] { items }
    public static func buildBlock(_ components: [FluentMenuBarItem]...) -> [FluentMenuBarItem] { components.flatMap { $0 } }
    @_disfavoredOverload
    public static func buildBlock(_ components: FluentMenuBarItem...) -> [FluentMenuBarItem] { components }
    public static func buildOptional(_ component: [FluentMenuBarItem]?) -> [FluentMenuBarItem] { component ?? [] }
    public static func buildEither(first component: [FluentMenuBarItem]) -> [FluentMenuBarItem] { component }
    public static func buildEither(second component: [FluentMenuBarItem]) -> [FluentMenuBarItem] { component }
    public static func buildArray(_ components: [[FluentMenuBarItem]]) -> [FluentMenuBarItem] { components.flatMap { $0 } }
}

/// WinUI MenuBar rendered inside the application window. Items use the source 40-point minimum
/// height, 4-point outer margin and 10×4 content padding, and share FluentMenuFlyout presenters.
public final class FluentMenuBar: NSView, FluentControlSizeConfigurable {
    public static let minimumHeight: CGFloat = 40
    public static let itemMargin: CGFloat = 4
    public static let horizontalPadding: CGFloat = 10
    public static let verticalPadding: CGFloat = 4

    public var items: [FluentMenuBarItem] {
        didSet { synchronizeItems(previous: oldValue) }
    }
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            itemViews.forEach { $0.theme = theme }
            updateOpenMenu()
            invalidateIntrinsicContentSize()
            needsLayout = true
            needsDisplay = true
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet { if oldValue != reduceMotion { updateOpenMenu() } }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            itemViews.forEach { $0.fluentControlSize = fluentControlSize }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public private(set) var openItemIndex: Int?
    public var itemControlViews: [NSView] { itemViews }
    public var isFlyoutOpen: Bool { openItemIndex != nil }

    private var itemViews: [FluentMenuBarItemControl] = []
    private var flyout: FluentMenuFlyout?
    private var suppressDismissCallback = false
    private var accessKeyMonitor: Any?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private lazy var hoverCoordinator = FluentHoverCoordinator<FluentMenuBarItemControl> { item, hovering in
        item.setPointerOver(hovering)
    }

    public init(items: [FluentMenuBarItem]) {
        self.items = items
        super.init(frame: .zero)
        configure()
    }

    public convenience init(@FluentMenuBarBuilder items: () -> [FluentMenuBarItem]) {
        self.init(items: items())
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        flyout?.dismiss(animated: false)
        if let accessKeyMonitor { NSEvent.removeMonitor(accessKeyMonitor) }
        removeLifecycleObservers()
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize {
        let margin = Self.itemMargin * fluentControlSize.metricScale
        return NSSize(
            width: itemViews.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width + 2 * margin },
            height: Self.minimumHeight * fluentControlSize.metricScale
        )
    }

    public override func layout() {
        super.layout()
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let margin = Self.itemMargin * fluentControlSize.metricScale
        var x = rtl ? bounds.maxX : bounds.minX
        for item in itemViews {
            item.userInterfaceLayoutDirection = userInterfaceLayoutDirection
            let width = item.intrinsicContentSize.width
            if rtl {
                x -= width + 2 * margin
                item.frame = NSRect(
                    x: x + margin,
                    y: margin,
                    width: width,
                    height: max(0, bounds.height - 2 * margin)
                )
            } else {
                item.frame = NSRect(
                    x: x + margin,
                    y: margin,
                    width: width,
                    height: max(0, bounds.height - 2 * margin)
                )
                x += width + 2 * margin
            }
        }
        flyout?.reposition()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        closeMenu()
        installAccessKeyMonitor()
        installLifecycleObservers()
    }

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { closeMenu() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { closeMenu(); removeLifecycleObservers() }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidHide() {
        super.viewDidHide()
        closeMenu()
    }

    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        flyout?.reposition()
    }

    public func openItem(at index: Int) {
        guard items.indices.contains(index), items[index].isEnabled, !items[index].items.isEmpty else { return }
        if openItemIndex == index, flyout?.isPresented == true { return }
        presentItem(at: index)
    }

    public func closeMenu() {
        cancelPointerState()
        guard flyout != nil || openItemIndex != nil else { return }
        suppressDismissCallback = true
        flyout?.dismiss(animated: false)
        suppressDismissCallback = false
        flyout = nil
        if let old = openItemIndex, itemViews.indices.contains(old) { itemViews[old].isSelected = false }
        openItemIndex = nil
    }

    public func toggleItem(at index: Int) {
        guard items.indices.contains(index), items[index].isEnabled else { return }
        if openItemIndex == index { closeMenu() }
        else { openItem(at: index) }
    }

    @discardableResult
    public func performAccessKey(_ character: Character) -> Bool {
        guard let index = items.firstIndex(where: {
            $0.isEnabled && $0.accessKey.map { String($0).caseInsensitiveCompare(String(character)) == .orderedSame } == true
        }) else { return false }
        let target = itemViews[index]
        FluentInputDeviceTracker.shared.record(.keyboard, in: window)
        guard let current = itemViews.firstIndex(where: { $0 === target }), target.acceptsFirstResponder else { return false }
        openItem(at: current)
        return true
    }

    private func configure() {
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.MenuBar")
        setAccessibilityElement(true)
        setAccessibilityRole(.menuBar)
        fluentSetDefaultAccessibilityTitle("Menu bar")
        rebuildItems()
    }

    private func cancelPointerState() {
        hoverCoordinator.reset(items: itemViews)
        itemViews.forEach { $0.cancelInteraction() }
    }

    private func installLifecycleObservers() {
        removeLifecycleObservers()
        guard let window else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                // A flyout legitimately takes key status from the host; release the captured
                // button interaction without dismissing that newly opened menu.
                if note.name == NSWindow.didResignKeyNotification { self?.cancelPointerState() }
                else { self?.closeMenu() }
            })
        }
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification,
            object: NSApp, queue: .main) { [weak self] _ in self?.closeMenu() })
    }

    private func removeLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    private func installAccessKeyMonitor() {
        if let accessKeyMonitor { NSEvent.removeMonitor(accessKeyMonitor) }
        accessKeyMonitor = nil
        guard window != nil else {
            itemViews.forEach { $0.showsAccessKey = false }
            return
        }
        accessKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.owns(eventWindow: event.window) else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let accessMode = modifiers.contains(.option)
                && !modifiers.contains(.command)
                && !modifiers.contains(.control)
            self.itemViews.forEach { $0.showsAccessKey = accessMode }
            guard event.type == .keyDown, accessMode,
                  let characters = event.charactersIgnoringModifiers,
                  characters.count == 1,
                  let character = characters.first,
                  self.performAccessKey(character) else { return event }
            return nil
        }
    }

    private func synchronizeItems(previous: [FluentMenuBarItem]) {
        let oldControls = itemViews
        let openControl = openItemIndex.flatMap { oldControls.indices.contains($0) ? oldControls[$0] : nil }
        let focused = oldControls.first { $0 === window?.firstResponder }
        var candidates: [AnyHashable: [FluentMenuBarItemControl]] = [:]
        for (item, control) in zip(previous, oldControls) { candidates[item.id, default: []].append(control) }
        itemViews = items.map { item in
            let control: FluentMenuBarItemControl
            if var matching = candidates[item.id], !matching.isEmpty {
                control = matching.removeFirst()
                candidates[item.id] = matching
            } else { control = FluentMenuBarItemControl(item: item, theme: theme) }
            control.update(item: item)
            configure(control)
            if control.superview !== self { addSubview(control) }
            return control
        }
        for control in candidates.values.flatMap({ $0 }) {
            hoverCoordinator.remove(control)
            control.cancelInteraction()
            control.onInvoke = nil
            control.onHoverChange = nil
            control.onHorizontalNavigation = nil
            control.removeFromSuperview()
        }
        if let openControl, let index = itemViews.firstIndex(where: { $0 === openControl }),
           items[index].isEnabled, !items[index].items.isEmpty {
            openItemIndex = index
            needsLayout = true
            layoutSubtreeIfNeeded()
            updateOpenMenu()
        } else {
            openControl?.isSelected = false
            openItemIndex = nil
            if flyout != nil { closeMenu() }
        }
        if let focused {
            let target = itemViews.contains(where: { $0 === focused }) && focused.acceptsFirstResponder
                ? focused : itemViews.first { $0.acceptsFirstResponder }
            window?.makeFirstResponder(target)
        }
        updateAccessibilityChildren()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func configure(_ control: FluentMenuBarItemControl) {
        control.theme = theme
        control.fluentControlSize = fluentControlSize
        control.onInvoke = { [weak self, weak control] invocation in
            guard let self, let control, self.itemViews.contains(where: { $0 === control }) else { return }
            if case .pointer(let device) = invocation {
                if device == .touch { self.hoverCoordinator.reset(items: self.itemViews) }
                else { self.hoverCoordinator.update(control, hovering: true) }
            }
            FluentInputDeviceTracker.shared.record(invocation.inputDeviceType, in: self.window)
            // Device-change notifications can synchronously reorder or replace the items.
            guard let index = self.itemViews.firstIndex(where: { $0 === control }), control.acceptsFirstResponder else { return }
            if case .keyboard = invocation { self.openItem(at: index) }
            else { self.toggleItem(at: index) }
        }
        control.onHoverChange = { [weak self, weak control] hovering in
            guard let self, let control, self.itemViews.contains(where: { $0 === control }) else { return }
            self.hoverCoordinator.update(control, hovering: hovering)
            if hovering {
                FluentInputDeviceTracker.shared.record(.mouse, in: self.window)
                guard let index = self.itemViews.firstIndex(where: { $0 === control }) else { return }
                self.hoverItem(at: index)
            }
        }
        control.onHorizontalNavigation = { [weak self, weak control] offset in
            guard let self, let control else { return }
            FluentInputDeviceTracker.shared.record(.keyboard, in: self.window)
            guard let index = self.itemViews.firstIndex(where: { $0 === control }), control.acceptsFirstResponder else { return }
            self.moveFromItem(at: index, physicalOffset: offset, open: false)
        }
    }

    private func updateOpenMenu() {
        guard let index = openItemIndex, items.indices.contains(index) else { return }
        flyout?.update(items: items[index].items, theme: theme, reduceMotion: reduceMotion)
    }

    private func rebuildItems() { synchronizeItems(previous: []) }

    private func updateAccessibilityChildren() {
        let visible = itemViews.filter { !$0.isHidden }
        setAccessibilityChildren(visible)
    }

    private func hoverItem(at index: Int) {
        guard openItemIndex != nil,
              openItemIndex != index,
              items.indices.contains(index),
              items[index].isEnabled,
              !items[index].items.isEmpty else { return }
        presentItem(at: index)
    }

    private func presentItem(at index: Int) {
        guard let window, !isHiddenOrHasHiddenAncestor, items.indices.contains(index),
              items[index].isEnabled, !items[index].items.isEmpty,
              !itemViews[index].isHiddenOrHasHiddenAncestor else { return }
        itemViews.forEach { $0.cancelPress() }
        let old = openItemIndex
        suppressDismissCallback = true
        flyout?.dismiss(animated: false)
        suppressDismissCallback = false
        if let old, itemViews.indices.contains(old) { itemViews[old].isSelected = false }

        let next = FluentMenuFlyout(
            items: items[index].items,
            theme: theme,
            minimumWidth: 180,
            matchesAnchorWidth: false,
            reduceMotion: reduceMotion
        )
        next.onRootHorizontalNavigation = { [weak self, weak next] physicalOffset in
            guard let self, let next, self.flyout === next else { return }
            // The key event belongs to the popup window. Carry its origin back to the bar's
            // host so the next root cannot inherit the host's stale mouse/touch record.
            FluentInputDeviceTracker.shared.record(.keyboard, in: self.window)
            guard self.flyout === next, let current = self.openItemIndex else { return }
            self.moveFromItem(at: current, physicalOffset: physicalOffset, open: true)
        }
        next.onDismiss = { [weak self, weak next] in
            guard let self, !self.suppressDismissCallback, self.flyout === next else { return }
            self.flyout = nil
            if let open = self.openItemIndex, self.itemViews.indices.contains(open) {
                self.itemViews[open].isSelected = false
            }
            self.openItemIndex = nil
            self.cancelPointerState()
        }
        flyout = next
        openItemIndex = index
        itemViews[index].isSelected = true
        window.makeFirstResponder(itemViews[index])
        next.present(relativeTo: itemViews[index], placement: .below)
    }

    private func moveFromItem(at index: Int, physicalOffset: Int, open: Bool) {
        if open {
            guard let destination = nextEnabledIndex(from: index, physicalOffset: physicalOffset) else {
                closeMenu()
                return
            }
            if items[destination].items.isEmpty { closeMenu(); window?.makeFirstResponder(itemViews[destination]) }
            else { presentItem(at: destination) }
        } else {
            let logicalOffset = userInterfaceLayoutDirection == .rightToLeft ? -physicalOffset : physicalOffset
            let adjacent = (index + logicalOffset + items.count) % items.count
            if items[adjacent].isEnabled { window?.makeFirstResponder(itemViews[adjacent]) }
        }
    }

    private func nextEnabledIndex(from index: Int, physicalOffset: Int) -> Int? {
        guard items.count > 1 else { return nil }
        let logicalOffset = userInterfaceLayoutDirection == .rightToLeft ? -physicalOffset : physicalOffset
        var candidate = index
        for _ in 1..<items.count {
            candidate = (candidate + logicalOffset + items.count) % items.count
            if items[candidate].isEnabled { return candidate }
        }
        return nil
    }

    private func owns(eventWindow: NSWindow?) -> Bool {
        guard let ownerWindow = window, let eventWindow else { return false }
        if eventWindow === ownerWindow { return true }
        var candidate = eventWindow.parent
        while let current = candidate {
            if current === ownerWindow { return true }
            candidate = current.parent
        }
        return false
    }
}

private enum FluentMenuBarInvocation {
    case pointer(FluentInputDeviceType)
    case keyboard
    case accessibility

    var inputDeviceType: FluentInputDeviceType {
        if case .pointer(let device) = self { return device }
        return .keyboard
    }
}

private final class FluentMenuBarItemControl: NSControl, FluentControlSizeConfigurable {
    var item: FluentMenuBarItem
    var theme: FluentTheme {
        didSet { if oldValue != theme { invalidateIntrinsicContentSize(); needsDisplay = true } }
    }
    var fluentControlSize: FluentControlSize = .regular {
        didSet { if oldValue != fluentControlSize { invalidateIntrinsicContentSize(); needsDisplay = true } }
    }
    var isSelected = false {
        didSet { setAccessibilityExpanded(isSelected); needsDisplay = true }
    }
    var showsAccessKey = false { didSet { guard oldValue != showsAccessKey else { return }; needsDisplay = true } }
    var onInvoke: ((FluentMenuBarInvocation) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onHorizontalNavigation: ((Int) -> Void)?

    private var pointerOver = false
    private var pressed = false
    private var trackingPress = false
    private lazy var pointerTrackingAreaHost = FluentTrackingAreaHost(
        view: self, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    )
    private var canReceiveInput: Bool { isEnabled && item.isEnabled && window != nil && !isHiddenOrHasHiddenAncestor }

    init(item: FluentMenuBarItem, theme: FluentTheme) {
        self.item = item
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.MenuBar.Item.\(item.id)")
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(item.title)
        isEnabled = item.isEnabled
        setAccessibilityEnabled(item.isEnabled)
        setAccessibilityExpanded(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { canReceiveInput }
    override var isEnabled: Bool {
        didSet { if oldValue != isEnabled, !isEnabled { cancelInteraction() } }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { cancelInteraction() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelInteraction() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidHide() { super.viewDidHide(); cancelInteraction() }

    func setPointerOver(_ hovering: Bool) {
        let next = hovering && canReceiveInput
        guard pointerOver != next else { return }
        pointerOver = next
        needsDisplay = true
    }

    func cancelPress() {
        trackingPress = false
        if pressed { pressed = false; needsDisplay = true }
    }

    func cancelInteraction() {
        cancelPress()
        setPointerOver(false)
        onHoverChange?(false)
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }
    override var intrinsicContentSize: NSSize {
        let scale = fluentControlSize.metricScale
        let font = theme.typography.font(for: .body)
        let titleWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
        return NSSize(
            width: ceil(titleWidth + 2 * FluentMenuBar.horizontalPadding * scale),
            height: max(0, (FluentMenuBar.minimumHeight - 2 * FluentMenuBar.itemMargin) * scale)
        )
    }

    func update(item: FluentMenuBarItem) {
        let titleChanged = self.item.title != item.title
        self.item = item
        identifier = NSUserInterfaceItemIdentifier("FluentKit.MenuBar.Item.\(item.id)")
        setAccessibilityTitle(item.title)
        isEnabled = item.isEnabled
        setAccessibilityEnabled(item.isEnabled)
        if !item.isEnabled { cancelInteraction() }
        if titleChanged { invalidateIntrinsicContentSize() }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        pointerTrackingAreaHost.update()
    }

    override func mouseEntered(with event: NSEvent) {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        // Disabled entries still end the previous item's hover ownership.
        onHoverChange?(true)
    }
    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
        pressed = false
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        guard canReceiveInput, surfaceRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        trackingPress = true
        pressed = true
        needsDisplay = true
        onInvoke?(.pointer(FluentInputDeviceTracker.deviceType(for: event) ?? .mouse))
    }
    override func mouseDragged(with event: NSEvent) {
        guard trackingPress, canReceiveInput else { return }
        pressed = surfaceRect.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        trackingPress = false
        pressed = false
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard canReceiveInput else { return }
        guard !event.modifierFlags.contains(.option) else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 125, 36, 49:
            if !event.isARepeat { onInvoke?(.keyboard) }
        case 124: onHorizontalNavigation?(1)
        case 123: onHorizontalNavigation?(-1)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        guard canReceiveInput else { return false }
        onInvoke?(.accessibility)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let state: FluentControlState = !isEnabled || !item.isEnabled
            ? .disabled
            : (pressed ? .pressed : (pointerOver ? .pointerOver : .normal))
        let background: NSColor
        if pressed { background = theme.subtleFillTertiary }
        else if pointerOver { background = theme.subtleFillSecondary }
        else if isSelected { background = theme.subtleFillTertiary }
        else { background = .clear }
        if background.alphaComponent > 0 {
            background.setFill()
            NSBezierPath(
                roundedRect: surfaceRect,
                xRadius: theme.designTokens.controlCornerRadius,
                yRadius: theme.designTokens.controlCornerRadius
            ).fill()
        }
        if theme.isHighContrast {
            let stroke = (pointerOver || pressed || isSelected) ? theme.focusStrokeOuter : theme.controlStrokeStrong
            stroke.setStroke()
            let path = NSBezierPath(
                roundedRect: surfaceRect.insetBy(dx: 1, dy: 1),
                xRadius: max(0, theme.designTokens.controlCornerRadius - 1),
                yRadius: max(0, theme.designTokens.controlCornerRadius - 1)
            )
            path.lineWidth = 2
            path.stroke()
        }
        let foreground = state == .disabled ? theme.textDisabled : theme.textPrimary
        let font = theme.typography.font(for: .body)
        let titleSize = (item.title as NSString).size(withAttributes: [.font: font])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let attributedTitle = NSMutableAttributedString(string: item.title, attributes: titleAttributes)
        if showsAccessKey, let accessKey = item.accessKey,
           let range = item.title.range(
               of: String(accessKey),
               options: [.caseInsensitive, .diacriticInsensitive]
           ) {
            attributedTitle.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(range, in: item.title))
        }
        attributedTitle.draw(
            in: NSRect(
                x: surfaceRect.minX + FluentMenuBar.horizontalPadding * fluentControlSize.metricScale,
                y: surfaceRect.midY - titleSize.height / 2,
                width: max(0, surfaceRect.width - 2 * FluentMenuBar.horizontalPadding * fluentControlSize.metricScale),
                height: titleSize.height
            )
        )
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            drawFocusVisual()
        }
    }

    private var surfaceRect: NSRect {
        bounds
    }

    private func drawFocusVisual() {
        let outer = NSBezierPath(
            roundedRect: surfaceRect.insetBy(dx: -3, dy: -3),
            xRadius: theme.designTokens.controlCornerRadius + 3,
            yRadius: theme.designTokens.controlCornerRadius + 3
        )
        outer.lineWidth = 2
        theme.focusStrokeOuter.setStroke()
        outer.stroke()
        let inner = NSBezierPath(
            roundedRect: surfaceRect.insetBy(dx: -0.5, dy: -0.5),
            xRadius: theme.designTokens.controlCornerRadius + 0.5,
            yRadius: theme.designTokens.controlCornerRadius + 0.5
        )
        inner.lineWidth = 1
        theme.focusStrokeInner.setStroke()
        inner.stroke()
    }
}

public struct FluentMenuBarView: FluentUpdatablePrimitiveView {
    public let items: [FluentMenuBarItem]

    public init(items: [FluentMenuBarItem]) { self.items = items }
    public init(@FluentMenuBarBuilder items: () -> [FluentMenuBarItem]) { self.items = items() }

    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        let menuBar = FluentMenuBar(items: items)
        menuBar.theme = context.theme
        menuBar.reduceMotion = context.reduceMotion
        return menuBar
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let menuBar = view as? FluentMenuBar else { return false }
        menuBar.theme = context.theme
        menuBar.reduceMotion = context.reduceMotion
        menuBar.items = items
        return true
    }
}
