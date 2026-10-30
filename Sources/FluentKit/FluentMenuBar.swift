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
            needsDisplay = true
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installAccessKeyMonitor()
    }

    public func openItem(at index: Int) {
        guard items.indices.contains(index), items[index].isEnabled, !items[index].items.isEmpty else { return }
        presentItem(at: index)
    }

    public func closeMenu() {
        guard flyout != nil || openItemIndex != nil else { return }
        suppressDismissCallback = true
        flyout?.dismiss(animated: false)
        suppressDismissCallback = false
        flyout = nil
        if let old = openItemIndex { itemViews[old].isSelected = false }
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
        openItem(at: index)
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
        closeMenu()
        if previous.map(\.id) == items.map(\.id), itemViews.count == items.count {
            for index in items.indices { itemViews[index].update(item: items[index]) }
        } else {
            rebuildItems()
        }
        updateAccessibilityChildren()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func rebuildItems() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.enumerated().map { index, item in
            let control = FluentMenuBarItemControl(item: item, theme: theme)
            control.fluentControlSize = fluentControlSize
            control.onInvoke = { [weak self] in self?.toggleItem(at: index) }
            control.onHover = { [weak self] in self?.hoverItem(at: index) }
            control.onHorizontalNavigation = { [weak self] offset in
                self?.moveFromItem(at: index, physicalOffset: offset, open: false)
            }
            addSubview(control)
            return control
        }
        updateAccessibilityChildren()
    }

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
        guard let window, items.indices.contains(index), !items[index].items.isEmpty else { return }
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
        next.onRootHorizontalNavigation = { [weak self] physicalOffset in
            self?.moveFromItem(at: index, physicalOffset: physicalOffset, open: true)
        }
        next.onDismiss = { [weak self, weak next] in
            guard let self, !self.suppressDismissCallback, self.flyout === next else { return }
            self.flyout = nil
            if let open = self.openItemIndex, self.itemViews.indices.contains(open) {
                self.itemViews[open].isSelected = false
            }
            self.openItemIndex = nil
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

private final class FluentMenuBarItemControl: NSControl, FluentControlSizeConfigurable {
    var item: FluentMenuBarItem
    var theme: FluentTheme { didSet { needsDisplay = true } }
    var fluentControlSize: FluentControlSize = .regular {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var isSelected = false {
        didSet { setAccessibilityExpanded(isSelected); needsDisplay = true }
    }
    var showsAccessKey = false { didSet { guard oldValue != showsAccessKey else { return }; needsDisplay = true } }
    var onInvoke: (() -> Void)?
    var onHover: (() -> Void)?
    var onHorizontalNavigation: ((Int) -> Void)?

    private var pointerOver = false
    private var pressed = false
    private var trackingPress = false

    init(item: FluentMenuBarItem, theme: FluentTheme) {
        self.item = item
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.MenuBar.Item.\(item.id)")
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityTitle(item.title)
        setAccessibilityEnabled(item.isEnabled)
        setAccessibilityExpanded(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { item.isEnabled }
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
        self.item = item
        identifier = NSUserInterfaceItemIdentifier("FluentKit.MenuBar.Item.\(item.id)")
        setAccessibilityTitle(item.title)
        setAccessibilityEnabled(item.isEnabled)
        if !item.isEnabled { pointerOver = false; pressed = false; trackingPress = false }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: surfaceRect,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard item.isEnabled else { return }
        pointerOver = true
        needsDisplay = true
        onHover?()
    }
    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        if !trackingPress { pressed = false }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        guard item.isEnabled, surfaceRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        trackingPress = true
        pressed = true
        needsDisplay = true
        onInvoke?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard trackingPress else { return }
        pressed = surfaceRect.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        trackingPress = false
        pressed = false
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.option) else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 125, 36, 49: onInvoke?()
        case 124: onHorizontalNavigation?(1)
        case 123: onHorizontalNavigation?(-1)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        guard item.isEnabled else { return false }
        onInvoke?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let state: FluentControlState = !item.isEnabled
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
        menuBar.items = items
        menuBar.theme = context.theme
        menuBar.reduceMotion = context.reduceMotion
        return true
    }
}
