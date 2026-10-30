import AppKit

/// A type-erased breadcrumb value suitable for both AppKit and FluentKit's declarative layer.
/// `id` preserves item identity when a path is updated without requiring the displayed title to
/// be unique.
public struct FluentBreadcrumbBarItem: Hashable {
    public let id: AnyHashable
    public var title: String
    public var systemImageName: String?

    public init(
        _ title: String,
        id: AnyHashable? = nil,
        systemImageName: String? = nil
    ) {
        self.id = id ?? AnyHashable(title)
        self.title = title
        self.systemImageName = systemImageName
    }
}

/// Native AppKit implementation of WinUI's BreadcrumbBar suffix-overflow, invocation, focus,
/// keyboard, right-to-left, and accessibility contracts.
public final class FluentBreadcrumbBar: NSControl, FluentControlSizeConfigurable {
    enum Metrics {
        static let itemHeight: CGFloat = 26
        static let fontSize: CGFloat = 14
        static let iconSize: CGFloat = 16
        static let iconSpacing: CGFloat = 8
        static let contentHorizontalPadding: CGFloat = 1
        static let chevronWidth: CGFloat = 16
        static let ellipsisContentWidth: CGFloat = 18
        static let focusInset: CGFloat = 1
        static let cornerRadius: CGFloat = 4
    }

    public var items: [FluentBreadcrumbBarItem] {
        didSet {
            guard oldValue != items else { return }
            rebuildItems()
        }
    }

    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            applyAppearance(animated: false)
        }
    }

    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            needsLayout = true
            applyAppearance(animated: false)
        }
    }

    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            itemControls.forEach { $0.fluentControlSize = fluentControlSize }
            ellipsisControl.fluentControlSize = fluentControlSize
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            ellipsisControl.isEnabled = isEnabled
            itemControls.forEach { $0.isEnabled = isEnabled }
            needsDisplay = true
        }
    }

    /// Receives the original item and its zero-based ItemsSource index.
    public var onItemClicked: ((FluentBreadcrumbBarItem, Int) -> Void)?

    let ellipsisControl = FluentBreadcrumbItemControl(kind: .ellipsis)
    private(set) var itemControls: [FluentBreadcrumbItemControl] = []
    private(set) var firstVisibleItemIndex = 0
    private(set) var hiddenItemIndices: [Int] = []
    private var overflowFlyout: FluentMenuFlyout?

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { false }

    public init(items: [FluentBreadcrumbBarItem] = []) {
        self.items = items
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        items = []
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        guard !itemControls.isEmpty else { return .zero }
        return NSSize(
            width: ceil(itemControls.reduce(0) { $0 + $1.preferredWidth }),
            height: ceil(Metrics.itemHeight * fluentControlSize.metricScale)
        )
    }

    public override func layout() {
        super.layout()
        layoutItems(in: bounds.width)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance(animated: false)
    }

    public override func accessibilityRole() -> NSAccessibility.Role? { .group }

    public override func accessibilityLabel() -> String? { "Breadcrumb bar" }

    public override func accessibilityChildren() -> [Any]? {
        var children: [Any] = []
        if !ellipsisControl.isHidden { children.append(ellipsisControl) }
        children.append(contentsOf: itemControls.filter { !$0.isHidden })
        return children
    }

    func activateItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        sendAction(action, to: target)
        onItemClicked?(items[index], index)
    }

    func showOverflow() {
        guard !hiddenItemIndices.isEmpty else { return }
        let menuItems = hiddenItemIndices.reversed().map { index in
            let item = items[index]
            return FluentMenuItem(
                item.title,
                systemImageName: item.systemImageName
            ) { [weak self] in
                self?.activateItem(at: index)
            }
        }
        let flyout = FluentMenuFlyout(
            items: menuItems,
            theme: theme,
            minimumWidth: 120,
            matchesAnchorWidth: false,
            reduceMotion: reduceMotion
        )
        flyout.onDismiss = { [weak self, weak flyout] in
            guard let self, self.overflowFlyout === flyout else { return }
            self.overflowFlyout = nil
            self.ellipsisControl.setOpen(false)
        }
        overflowFlyout = flyout
        ellipsisControl.setOpen(true)
        flyout.present(relativeTo: ellipsisControl, placement: .below)
    }

    func moveFocus(from control: FluentBreadcrumbItemControl, keyCode: UInt16) -> Bool {
        let isForwardKey = isRTL ? keyCode == 123 : keyCode == 124
        let isBackwardKey = isRTL ? keyCode == 124 : keyCode == 123
        guard isForwardKey || isBackwardKey else { return false }
        let visible = visibleControls
        guard let index = visible.firstIndex(where: { $0 === control }) else { return false }
        let targetIndex = index + (isForwardKey ? 1 : -1)
        guard visible.indices.contains(targetIndex) else { return true }
        window?.makeFirstResponder(visible[targetIndex])
        return true
    }

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    private var visibleControls: [FluentBreadcrumbItemControl] {
        var result: [FluentBreadcrumbItemControl] = []
        if !ellipsisControl.isHidden { result.append(ellipsisControl) }
        result.append(contentsOf: itemControls.filter { !$0.isHidden })
        return result
    }

    private func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Breadcrumb bar")

        ellipsisControl.owner = self
        ellipsisControl.fluentControlSize = fluentControlSize
        ellipsisControl.isEnabled = isEnabled
        ellipsisControl.isHidden = true
        addSubview(ellipsisControl)
        rebuildItems()
    }

    private func rebuildItems() {
        overflowFlyout?.dismiss(animated: false)
        overflowFlyout = nil
        itemControls.forEach { $0.removeFromSuperview() }
        itemControls = items.enumerated().map { index, item in
            let control = FluentBreadcrumbItemControl(kind: .item(index))
            control.owner = self
            control.item = item
            control.isCurrent = index == items.count - 1
            control.fluentControlSize = fluentControlSize
            control.isEnabled = isEnabled
            addSubview(control)
            return control
        }
        firstVisibleItemIndex = 0
        hiddenItemIndices = []
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
        applyAppearance(animated: false)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func layoutItems(in availableWidth: CGFloat) {
        guard !itemControls.isEmpty else {
            ellipsisControl.isHidden = true
            firstVisibleItemIndex = 0
            hiddenItemIndices = []
            return
        }

        let totalWidth = itemControls.reduce(0) { $0 + $1.preferredWidth }
        let shouldOverflow = totalWidth > max(0, availableWidth) + 0.001
        var first = 0
        if shouldOverflow {
            var occupied = ellipsisControl.preferredWidth + itemControls[itemControls.count - 1].preferredWidth
            first = itemControls.count - 1
            if itemControls.count > 1 {
                for index in stride(from: itemControls.count - 2, through: 0, by: -1) {
                    let proposed = occupied + itemControls[index].preferredWidth
                    if proposed > max(0, availableWidth) + 0.001 {
                        first = index + 1
                        break
                    }
                    occupied = proposed
                    first = index
                }
            }
        }

        let oldHidden = hiddenItemIndices
        firstVisibleItemIndex = first
        hiddenItemIndices = shouldOverflow ? Array(0..<first) : []
        ellipsisControl.isHidden = !shouldOverflow
        ellipsisControl.setAccessibilityElement(shouldOverflow)
        for (index, control) in itemControls.enumerated() {
            control.isHidden = shouldOverflow && index < first
            control.setAccessibilityElement(!control.isHidden)
            control.isCurrent = index == itemControls.count - 1
        }

        let visible = visibleControls
        let height = min(bounds.height, Metrics.itemHeight * fluentControlSize.metricScale)
        var x: CGFloat = isRTL ? bounds.maxX : bounds.minX
        for control in visible {
            let width = control.preferredWidth
            if isRTL {
                x -= width
                control.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            } else {
                control.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
                x += width
            }
            control.needsDisplay = true
        }
        if oldHidden != hiddenItemIndices {
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }

    private func applyAppearance(animated: Bool) {
        ellipsisControl.theme = theme
        ellipsisControl.reduceMotion = reduceMotion
        itemControls.forEach {
            $0.theme = theme
            $0.reduceMotion = reduceMotion
        }
        needsDisplay = true
    }
}

final class FluentBreadcrumbItemControl: NSControl, FluentControlSizeConfigurable {
    enum Kind {
        case ellipsis
        case item(Int)
    }

    let kind: Kind
    weak var owner: FluentBreadcrumbBar?
    var item: FluentBreadcrumbBarItem? {
        didSet {
            setAccessibilityLabel(item?.title)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var isCurrent = false {
        didSet {
            guard oldValue != isCurrent else { return }
            updateAccessibility()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private var trackingArea: NSTrackingArea?
    private var pointerOver = false
    private var pointerDown = false
    private var open = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled && !isHidden }

    var preferredWidth: CGFloat {
        let scale = fluentControlSize.metricScale
        switch kind {
        case .ellipsis:
            return ceil((FluentBreadcrumbBar.Metrics.ellipsisContentWidth + FluentBreadcrumbBar.Metrics.chevronWidth) * scale)
        case .item:
            guard let item else { return 0 }
            let font = NSFont.systemFont(ofSize: FluentBreadcrumbBar.Metrics.fontSize * scale)
            var width = ceil((item.title as NSString).size(withAttributes: [.font: font]).width)
            if item.systemImageName != nil {
                width += (FluentBreadcrumbBar.Metrics.iconSize + FluentBreadcrumbBar.Metrics.iconSpacing) * scale
            }
            width += FluentBreadcrumbBar.Metrics.contentHorizontalPadding * 2 * scale
            if !isCurrent { width += FluentBreadcrumbBar.Metrics.chevronWidth * scale }
            return ceil(width)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: preferredWidth,
            height: FluentBreadcrumbBar.Metrics.itemHeight * fluentControlSize.metricScale
        )
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isCurrent else { return }
        pointerOver = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        pointerDown = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !isCurrent else {
            if isEnabled { window?.makeFirstResponder(self) }
            return
        }
        window?.makeFirstResponder(self)
        pointerDown = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, !isCurrent else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pointerDown = false
        needsDisplay = true
        if inside { activate() }
    }

    override func keyDown(with event: NSEvent) {
        if owner?.moveFocus(from: self, keyCode: event.keyCode) == true { return }
        if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
            activate()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        activate()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = fluentControlSize.metricScale
        let state: FluentControlState = if !isEnabled {
            .disabled
        } else if !isCurrent && (pointerDown || open) {
            .pressed
        } else if !isCurrent && pointerOver {
            .pointerOver
        } else {
            .normal
        }
        let color = theme.breadcrumbForeground(current: isCurrent, state: state)
        let rtl = owner?.userInterfaceLayoutDirection == .rightToLeft

        context.saveGState()
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            let focusRect = bounds.insetBy(
                dx: FluentBreadcrumbBar.Metrics.focusInset,
                dy: FluentBreadcrumbBar.Metrics.focusInset
            )
            let path = CGPath(
                roundedRect: focusRect,
                cornerWidth: FluentBreadcrumbBar.Metrics.cornerRadius,
                cornerHeight: FluentBreadcrumbBar.Metrics.cornerRadius,
                transform: nil
            )
            context.setStrokeColor(theme.accentFillDefault.cgColor)
            context.setLineWidth(2 / max(window?.backingScaleFactor ?? 2, 1))
            context.addPath(path)
            context.strokePath()
        }

        let chevronWidth = FluentBreadcrumbBar.Metrics.chevronWidth * scale
        let hasChevron: Bool = switch kind {
        case .ellipsis: true
        case .item: !isCurrent
        }
        let contentRect: CGRect
        if hasChevron {
            contentRect = rtl
                ? CGRect(x: bounds.minX + chevronWidth, y: bounds.minY, width: bounds.width - chevronWidth, height: bounds.height)
                : CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width - chevronWidth, height: bounds.height)
            let chevronRect = rtl
                ? CGRect(x: bounds.minX, y: bounds.minY, width: chevronWidth, height: bounds.height)
                : CGRect(x: bounds.maxX - chevronWidth, y: bounds.minY, width: chevronWidth, height: bounds.height)
            drawChevron(in: chevronRect, color: color, pointsRight: !rtl, context: context)
        } else {
            contentRect = bounds
        }

        switch kind {
        case .ellipsis:
            drawEllipsis(in: contentRect, color: color, context: context)
        case .item:
            if let item { draw(item: item, in: contentRect, color: color, rtl: rtl, scale: scale) }
        }
        context.restoreGState()
    }

    func setOpen(_ value: Bool) {
        guard open != value else { return }
        open = value
        needsDisplay = true
    }

    private func activate() {
        switch kind {
        case .ellipsis:
            owner?.showOverflow()
        case let .item(index):
            owner?.activateItem(at: index)
        }
    }

    private func draw(item: FluentBreadcrumbBarItem, in rect: CGRect, color: NSColor, rtl: Bool, scale: CGFloat) {
        let font = NSFont.systemFont(ofSize: FluentBreadcrumbBar.Metrics.fontSize * scale)
        let iconSize = FluentBreadcrumbBar.Metrics.iconSize * scale
        let spacing = FluentBreadcrumbBar.Metrics.iconSpacing * scale
        let padding = FluentBreadcrumbBar.Metrics.contentHorizontalPadding * scale
        let titleWidth = ceil((item.title as NSString).size(withAttributes: [.font: font]).width)
        var x = rtl ? rect.maxX - padding : rect.minX + padding

        if let name = item.systemImageName,
           let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let configured = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            ) ?? image
            configured.isTemplate = true
            let imageRect = CGRect(
                x: rtl ? x - iconSize : x,
                y: rect.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            color.set()
            configured.draw(in: imageRect)
            x += rtl ? -(iconSize + spacing) : iconSize + spacing
        }

        let titleRect = CGRect(
            x: rtl ? x - titleWidth : x,
            y: rect.midY - ceil(font.ascender - font.descender) / 2,
            width: titleWidth,
            height: ceil(font.ascender - font.descender) + 2
        )
        (item.title as NSString).draw(in: titleRect, withAttributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    private func drawEllipsis(in rect: CGRect, color: NSColor, context: CGContext) {
        let diameter: CGFloat = 2
        let spacing: CGFloat = 3
        let total = diameter * 3 + spacing * 2
        var x = rect.midX - total / 2
        context.setFillColor(color.cgColor)
        for _ in 0..<3 {
            context.fillEllipse(in: CGRect(x: x, y: rect.midY - diameter / 2, width: diameter, height: diameter))
            x += diameter + spacing
        }
    }

    private func drawChevron(in rect: CGRect, color: NSColor, pointsRight: Bool, context: CGContext) {
        let width: CGFloat = 4.5
        let height: CGFloat = 7
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        if pointsRight {
            context.move(to: CGPoint(x: center.x - width / 2, y: center.y - height / 2))
            context.addLine(to: CGPoint(x: center.x + width / 2, y: center.y))
            context.addLine(to: CGPoint(x: center.x - width / 2, y: center.y + height / 2))
        } else {
            context.move(to: CGPoint(x: center.x + width / 2, y: center.y - height / 2))
            context.addLine(to: CGPoint(x: center.x - width / 2, y: center.y))
            context.addLine(to: CGPoint(x: center.x + width / 2, y: center.y + height / 2))
        }
        context.strokePath()
    }

    private func updateAccessibility() {
        switch kind {
        case .ellipsis:
            setAccessibilityLabel("More links")
            setAccessibilityHelp("Shows hidden breadcrumb items")
        case .item:
            setAccessibilityLabel(item?.title)
            setAccessibilityHelp(isCurrent ? "Current location" : "Breadcrumb item")
        }
    }
}

/// Declarative BreadcrumbBar wrapper. The path itself is application state; ItemClicked mirrors
/// WinUI and lets the application truncate or otherwise update that path.
public struct FluentBreadcrumbBarView: FluentUpdatablePrimitiveView {
    private let items: [FluentBreadcrumbBarItem]
    private let onItemClicked: ((FluentBreadcrumbBarItem, Int) -> Void)?

    public init(
        items: [FluentBreadcrumbBarItem],
        onItemClicked: ((FluentBreadcrumbBarItem, Int) -> Void)? = nil
    ) {
        self.items = items
        self.onItemClicked = onItemClicked
    }

    /// ItemsSource-style convenience for application models. The mapping closures are the
    /// declarative equivalent of WinUI's ItemTemplate while ItemClicked still returns the
    /// original model value.
    public init<Item>(
        items sourceItems: [Item],
        id: (Item) -> AnyHashable,
        title: (Item) -> String,
        systemImageName: (Item) -> String? = { _ in nil },
        onItemClicked: ((Item, Int) -> Void)? = nil
    ) {
        items = sourceItems.map { item in
            FluentBreadcrumbBarItem(
                title(item),
                id: id(item),
                systemImageName: systemImageName(item)
            )
        }
        self.onItemClicked = { _, index in
            guard sourceItems.indices.contains(index) else { return }
            onItemClicked?(sourceItems[index], index)
        }
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let control = FluentBreadcrumbBar(items: items)
        apply(to: control, context: context)
        return control
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentBreadcrumbBar else { return false }
        control.items = items
        apply(to: control, context: context)
        return true
    }

    private func apply(to control: FluentBreadcrumbBar, context: FluentRenderContext) {
        control.theme = context.theme
        control.reduceMotion = context.reduceMotion
        control.fluentLayoutDirection = context.layoutDirection
        control.onItemClicked = onItemClicked
    }
}
