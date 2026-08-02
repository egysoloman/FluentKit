import AppKit

/// Stable data for one destination in a `FluentSelectorBar`.
public struct FluentSelectorBarItem<Value: Hashable>: Hashable {
    public let value: Value
    public let title: String
    public let systemImageName: String?
    public let isEnabled: Bool

    public init(
        value: Value,
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true
    ) {
        self.value = value
        self.title = title
        systemImageName = systemImage
        self.isEnabled = isEnabled
    }
}

/// A horizontal view selector with per-item selection pills.
///
/// Unlike `FluentSegmentedControl`, SelectorBar has a transparent surface and each item owns its
/// own selection visual. It is intended for switching pages or views, not compact form choices.
public struct FluentSelectorBar<Value: Hashable>: FluentUpdatablePrimitiveView {
    private let items: [FluentSelectorBarItem<Value>]
    private let selection: FluentBinding<Value?>
    private let allowsEmptySelection: Bool
    private let onSelectionChange: ((Value?) -> Void)?

    public init(
        _ items: [FluentSelectorBarItem<Value>],
        selection: FluentBinding<Value?>,
        onSelectionChange: ((Value?) -> Void)? = nil
    ) {
        self.items = items
        self.selection = selection
        allowsEmptySelection = true
        self.onSelectionChange = onSelectionChange
    }

    public init(
        _ items: [FluentSelectorBarItem<Value>],
        selection: FluentBinding<Value>,
        onSelectionChange: ((Value) -> Void)? = nil
    ) {
        self.items = items
        self.selection = FluentBinding<Value?>(
            get: { selection.get() },
            set: { value in
                if let value { selection.set(value) }
            },
            observe: selection.observe.map { observe in
                { observer in observe { observer(Optional($0)) } }
            },
            removeObserver: selection.removeObserver
        )
        allowsEmptySelection = false
        self.onSelectionChange = { value in
            if let value { onSelectionChange?(value) }
        }
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentSelectorBarHost(
            items: items,
            selection: selection,
            allowsEmptySelection: allowsEmptySelection,
            onSelectionChange: onSelectionChange,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSelectorBarHost<Value> else { return false }
        host.update(
            items: items,
            selection: selection,
            allowsEmptySelection: allowsEmptySelection,
            onSelectionChange: onSelectionChange,
            context: context
        )
        return true
    }
}

private enum FluentSelectorBarFocusMove {
    case previous
    case next
    case first
    case last
}

private enum FluentSelectorBarMetrics {
    static let barVerticalPadding: CGFloat = 4
    static let itemLeadingPadding: CGFloat = 12
    static let itemTopPadding: CGFloat = 10
    static let itemTrailingPadding: CGFloat = 12
    static let itemBottomPadding: CGFloat = 7
    static let itemSpacing: CGFloat = 8
    static let iconVisualMargin: CGFloat = -2
    static let iconSize: CGFloat = 16
    static let pillWidth: CGFloat = 4
    static let pillHeight: CGFloat = 3
    static let pillSelectedScale: CGFloat = 4
    static let focusVisualMargin: CGFloat = -2
}

private final class FluentSelectorBarHost<Value: Hashable>: NSView, FluentControlSizeConfigurable {
    private var items: [FluentSelectorBarItem<Value>]
    private var selection: FluentBinding<Value?>
    private var allowsEmptySelection: Bool
    private var onSelectionChange: ((Value?) -> Void)?
    private var itemViews: [FluentSelectorBarItemView] = []
    private var observedSelection: FluentBinding<Value?>?
    private var selectionObserverID: UUID?
    private var selectedValue: Value?
    private var pendingRepositionFrames: [ObjectIdentifier: NSRect]?
    private var isWritingSelection = false
    private var theme: FluentTheme
    private var reduceMotion: Bool
    private var layoutDirection: FluentLayoutDirection

    var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            refreshItemConfigurations(animatedSelection: false)
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    init(
        items: [FluentSelectorBarItem<Value>],
        selection: FluentBinding<Value?>,
        allowsEmptySelection: Bool,
        onSelectionChange: ((Value?) -> Void)?,
        context: FluentRenderContext
    ) {
        self.items = items
        self.selection = selection
        self.allowsEmptySelection = allowsEmptySelection
        self.onSelectionChange = onSelectionChange
        theme = context.theme
        reduceMotion = context.reduceMotion
        layoutDirection = context.layoutDirection
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.SelectorBar")
        wantsLayer = true
        layer?.masksToBounds = false
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("View selector")
        reconcileItemViews(animatedReposition: false)
        installSelectionObserver()
        syncSelectionFromBinding(animated: false, writeCorrection: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: itemViews.reduce(0) { $0 + $1.preferredSize.width },
            height: (itemViews.map(\.preferredSize.height).max() ?? 0)
                + 2 * scaled(FluentSelectorBarMetrics.barVerticalPadding)
        )
    }

    override func layout() {
        super.layout()
        let verticalPadding = scaled(FluentSelectorBarMetrics.barVerticalPadding)
        var x = userInterfaceLayoutDirection == .rightToLeft
            ? bounds.maxX
            : bounds.minX
        let oldFrames = pendingRepositionFrames
        pendingRepositionFrames = nil

        for itemView in itemViews {
            let size = itemView.preferredSize
            if userInterfaceLayoutDirection == .rightToLeft { x -= size.width }
            let target = NSRect(x: x, y: verticalPadding, width: size.width, height: size.height)
            itemView.frame = target
            itemView.updateLayerGeometry()
            if let oldFrame = oldFrames?[ObjectIdentifier(itemView)],
               !reduceMotion,
               abs(oldFrame.minX - target.minX) > 0.01 {
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                animation.fromValue = oldFrame.minX - target.minX
                animation.toValue = CGFloat(0)
                animation.duration = FluentMotion.controlNormal.duration
                animation.timingFunction = FluentMotion.controlNormal.curve.timingFunction
                itemView.layer?.add(animation, forKey: "fluent.selectorbar.reposition")
            }
            if userInterfaceLayoutDirection != .rightToLeft { x += size.width }
        }
    }

    func update(
        items: [FluentSelectorBarItem<Value>],
        selection: FluentBinding<Value?>,
        allowsEmptySelection: Bool,
        onSelectionChange: ((Value?) -> Void)?,
        context: FluentRenderContext
    ) {
        let itemsChanged = self.items != items
        let directionChanged = layoutDirection != context.layoutDirection
        if itemsChanged {
            pendingRepositionFrames = Dictionary(
                uniqueKeysWithValues: itemViews.map { (ObjectIdentifier($0), $0.frame) }
            )
        }
        self.items = items
        self.selection = selection
        self.allowsEmptySelection = allowsEmptySelection
        self.onSelectionChange = onSelectionChange
        theme = context.theme
        reduceMotion = context.reduceMotion
        layoutDirection = context.layoutDirection
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        if reduceMotion { itemViews.forEach { $0.removeFluentAnimations() } }
        if itemsChanged { reconcileItemViews(animatedReposition: true) }
        installSelectionObserver()
        syncSelectionFromBinding(animated: !itemsChanged, writeCorrection: true)
        refreshItemConfigurations(animatedSelection: false)
        if directionChanged {
            pendingRepositionFrames = nil
            itemViews.forEach { $0.removeFluentAnimations() }
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func reconcileItemViews(animatedReposition: Bool) {
        var reusable: [AnyHashable: [FluentSelectorBarItemView]] = [:]
        for itemView in itemViews {
            reusable[itemView.itemID, default: []].append(itemView)
        }

        var nextViews: [FluentSelectorBarItemView] = []
        for item in items {
            let key = AnyHashable(item.value)
            let itemView: FluentSelectorBarItemView
            if var bucket = reusable[key], !bucket.isEmpty {
                itemView = bucket.removeFirst()
                reusable[key] = bucket
            } else {
                itemView = FluentSelectorBarItemView(itemID: key)
                addSubview(itemView)
            }
            itemView.onActivate = { [weak self] in self?.activate(value: item.value, from: itemView) }
            itemView.onMoveFocus = { [weak self] move in self?.moveSelection(from: item.value, move: move) }
            itemView.onReceiveFocus = { [weak self] in self?.selectFocusedItemIfNeeded(item.value) }
            nextViews.append(itemView)
        }
        reusable.values.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        itemViews = nextViews
        setAccessibilityChildren(itemViews)
        refreshItemConfigurations(animatedSelection: false)
        if !animatedReposition { pendingRepositionFrames = nil }
    }

    private func installSelectionObserver() {
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
        observedSelection = selection
        selectionObserverID = selection.observe { [weak self] value in
            guard let self else { return }
            let apply = { [weak self] in
                guard let self, !self.isWritingSelection else { return }
                self.applySelection(self.normalizedSelection(value), animated: true, writeBinding: false)
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func syncSelectionFromBinding(animated: Bool, writeCorrection: Bool) {
        let requested = selection.get()
        let normalized = normalizedSelection(requested)
        applySelection(normalized, animated: animated, writeBinding: writeCorrection && requested != normalized)
    }

    private func normalizedSelection(_ value: Value?) -> Value? {
        if let value, items.contains(where: { $0.value == value }) { return value }
        if allowsEmptySelection { return nil }
        return items.first(where: \.isEnabled)?.value ?? items.first?.value
    }

    private func activate(value: Value, from itemView: FluentSelectorBarItemView) {
        guard items.first(where: { $0.value == value })?.isEnabled == true else { return }
        window?.makeFirstResponder(itemView)
        applySelection(value, animated: true, writeBinding: true)
    }

    private func selectFocusedItemIfNeeded(_ value: Value) {
        guard selectedValue == nil,
              items.first(where: { $0.value == value })?.isEnabled == true else { return }
        applySelection(value, animated: true, writeBinding: true)
    }

    private func moveSelection(from value: Value, move: FluentSelectorBarFocusMove) {
        let enabledIndices = items.indices.filter { items[$0].isEnabled }
        guard !enabledIndices.isEmpty else { return }
        let current = items.firstIndex(where: { $0.value == value })
            ?? items.firstIndex(where: { $0.value == selectedValue })
            ?? enabledIndices[0]
        let targetIndex: Int
        switch move {
        case .first:
            targetIndex = enabledIndices[0]
        case .last:
            targetIndex = enabledIndices[enabledIndices.count - 1]
        case .previous, .next:
            let movingPrevious = move == .previous
            let candidates = movingPrevious
                ? enabledIndices.filter { $0 < current }
                : enabledIndices.filter { $0 > current }
            targetIndex = movingPrevious ? (candidates.last ?? current) : (candidates.first ?? current)
        }
        let target = items[targetIndex].value
        applySelection(target, animated: target != selectedValue, writeBinding: true)
        window?.makeFirstResponder(itemViews[targetIndex])
    }

    private func applySelection(_ value: Value?, animated: Bool, writeBinding: Bool) {
        let changed = selectedValue != value
        selectedValue = value
        refreshItemConfigurations(animatedSelection: animated && changed)
        setAccessibilityValue(value.map { String(describing: $0) })
        guard changed else { return }
        if writeBinding {
            isWritingSelection = true
            selection.set(value)
            isWritingSelection = false
        }
        onSelectionChange?(value)
    }

    private func refreshItemConfigurations(animatedSelection: Bool) {
        var selectedOccurrenceConsumed = false
        for (index, itemView) in itemViews.enumerated() where items.indices.contains(index) {
            let item = items[index]
            let isSelected = !selectedOccurrenceConsumed && item.value == selectedValue
            if isSelected { selectedOccurrenceConsumed = true }
            itemView.update(
                title: item.title,
                systemImageName: item.systemImageName,
                isEnabled: item.isEnabled,
                isSelected: isSelected,
                theme: theme,
                scale: metricScale,
                font: itemFont,
                reduceMotion: reduceMotion,
                animatedSelection: animatedSelection && isSelected
            )
        }
    }

    private var metricScale: CGFloat {
        theme.density.metricScale * fluentControlSize.metricScale
    }

    private var itemFont: NSFont {
        let body = theme.typography.font(for: .body)
        return body.withSize(body.pointSize * fluentControlSize.metricScale)
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * metricScale }

    deinit {
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
    }
}

private final class FluentSelectorBarItemView: NSButton {
    let itemID: AnyHashable
    var onActivate: (() -> Void)?
    var onMoveFocus: ((FluentSelectorBarFocusMove) -> Void)?
    var onReceiveFocus: (() -> Void)?

    private let pillLayer = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private var itemTitle = ""
    private var systemImageName: String?
    private var selected = false
    private var pointerOver = false
    private var pressed = false
    private var theme = FluentTheme.current
    private var metricScale: CGFloat = 1
    private var itemFont = NSFont.systemFont(ofSize: 14)
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    var preferredSize: NSSize {
        let titleWidth = itemTitle.isEmpty
            ? 0
            : ceil((itemTitle as NSString).size(withAttributes: [.font: itemFont]).width)
        let iconWidth = systemImageName == nil ? 0 : scaled(FluentSelectorBarMetrics.iconSize)
        let spacing = titleWidth > 0 && iconWidth > 0 ? scaled(FluentSelectorBarMetrics.itemSpacing) : 0
        let iconMargin = iconWidth > 0 ? 2 * scaled(FluentSelectorBarMetrics.iconVisualMargin) : 0
        let contentWidth = max(0, titleWidth + iconWidth + spacing + iconMargin)
        let lineHeight = ceil(itemFont.ascender - itemFont.descender + itemFont.leading)
        let contentHeight = max(titleWidth > 0 ? lineHeight : 0, iconWidth)
        return NSSize(
            width: max(
                contentWidth
                    + scaled(FluentSelectorBarMetrics.itemLeadingPadding)
                    + scaled(FluentSelectorBarMetrics.itemTrailingPadding),
                scaled(40)
            ),
            height: contentHeight
                + scaled(FluentSelectorBarMetrics.itemTopPadding)
                + scaled(FluentSelectorBarMetrics.itemBottomPadding)
                + scaled(FluentSelectorBarMetrics.pillHeight)
        )
    }

    init(itemID: AnyHashable) {
        self.itemID = itemID
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.SelectorBar.Item")
        title = ""
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(invoke)
        wantsLayer = true
        layer?.masksToBounds = false
        pillLayer.name = "FluentKit.SelectorBar.ItemPill"
        focusLayer.name = "FluentKit.SelectorBar.ItemFocus"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.opacity = 0
        layer?.addSublayer(pillLayer)
        layer?.addSublayer(focusLayer)
        setAccessibilityRole(.radioButton)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        title: String,
        systemImageName: String?,
        isEnabled: Bool,
        isSelected: Bool,
        theme: FluentTheme,
        scale: CGFloat,
        font: NSFont,
        reduceMotion: Bool,
        animatedSelection: Bool
    ) {
        let selectionChanged = selected != isSelected
        itemTitle = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        selected = isSelected
        self.theme = theme
        metricScale = scale
        itemFont = font
        self.reduceMotion = reduceMotion
        setAccessibilityTitle(title)
        setAccessibilityEnabled(isEnabled)
        setAccessibilitySelected(isSelected)
        setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        updateLayerGeometry()
        updatePill(
            animated: animatedSelection && selectionChanged,
            preserveActiveAnimation: !selectionChanged
        )
        updateFocusVisual()
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    func updateLayerGeometry() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let pillWidth = scaled(FluentSelectorBarMetrics.pillWidth)
        let pillHeight = scaled(FluentSelectorBarMetrics.pillHeight)
        pillLayer.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        pillLayer.position = CGPoint(x: bounds.midX, y: bounds.maxY - pillHeight / 2)
        pillLayer.path = CGPath(
            roundedRect: pillLayer.bounds,
            cornerWidth: scaled(0.5),
            cornerHeight: scaled(1),
            transform: nil
        )
        let focusMargin = scaled(FluentSelectorBarMetrics.focusVisualMargin)
        focusLayer.frame = bounds.insetBy(dx: focusMargin, dy: focusMargin)
        focusLayer.path = CGPath(
            roundedRect: focusLayer.bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: theme.designTokens.controlCornerRadius + 2,
            cornerHeight: theme.designTokens.controlCornerRadius + 2,
            transform: nil
        )
    }

    func removeFluentAnimations() {
        pillLayer.removeAllAnimations()
        focusLayer.removeAllAnimations()
        layer?.removeAnimation(forKey: "fluent.selectorbar.reposition")
        updatePill(animated: false, preserveActiveAnimation: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let foreground: NSColor
        if !isEnabled {
            foreground = theme.textDisabled
        } else if selected, pressed {
            foreground = theme.textSecondary
        } else if pressed {
            foreground = theme.textTertiary
        } else if pointerOver {
            foreground = theme.textSecondary
        } else {
            foreground = theme.textPrimary
        }

        let leading = scaled(FluentSelectorBarMetrics.itemLeadingPadding)
        let trailing = scaled(FluentSelectorBarMetrics.itemTrailingPadding)
        let top = scaled(FluentSelectorBarMetrics.itemTopPadding)
        let iconSize = systemImageName == nil ? 0 : scaled(FluentSelectorBarMetrics.iconSize)
        let titleWidth = itemTitle.isEmpty
            ? 0
            : ceil((itemTitle as NSString).size(withAttributes: [.font: itemFont]).width)
        let spacing = titleWidth > 0 && iconSize > 0 ? scaled(FluentSelectorBarMetrics.itemSpacing) : 0
        let iconMargin = iconSize > 0 ? scaled(FluentSelectorBarMetrics.iconVisualMargin) : 0
        let lineHeight = ceil(itemFont.ascender - itemFont.descender + itemFont.leading)
        let visualHeight = max(titleWidth > 0 ? lineHeight : 0, iconSize)
        let contentY = top
        let isRTL = userInterfaceLayoutDirection == .rightToLeft

        if let systemImageName,
           let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: itemTitle) {
            let iconX = isRTL
                ? bounds.maxX - trailing - iconMargin - iconSize
                : bounds.minX + leading + iconMargin
            let configuration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
                .applying(.init(hierarchicalColor: foreground))
            image.withSymbolConfiguration(configuration)?.draw(
                in: NSRect(
                    x: iconX,
                    y: contentY + (visualHeight - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
            )
        }

        if !itemTitle.isEmpty {
            let textX: CGFloat
            if isRTL {
                textX = bounds.maxX - trailing - titleWidth
                    - (iconSize > 0 ? iconSize + spacing + 2 * iconMargin : 0)
            } else {
                textX = bounds.minX + leading
                    + (iconSize > 0 ? iconSize + spacing + 2 * iconMargin : 0)
            }
            (itemTitle as NSString).draw(
                in: NSRect(
                    x: textX,
                    y: contentY + (visualHeight - lineHeight) / 2,
                    width: titleWidth,
                    height: lineHeight
                ),
                withAttributes: [.font: itemFont, .foregroundColor: foreground]
            )
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        pointerOver = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        pointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        updateFocusVisual()
        switch event.keyCode {
        case 123:
            onMoveFocus?(userInterfaceLayoutDirection == .rightToLeft ? .next : .previous)
        case 124:
            onMoveFocus?(userInterfaceLayoutDirection == .rightToLeft ? .previous : .next)
        case 115:
            onMoveFocus?(.first)
        case 119:
            onMoveFocus?(.last)
        case 36, 49:
            invoke()
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onReceiveFocus?()
            updateFocusVisual()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { updateFocusVisual() }
        return result
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        invoke()
        return true
    }

    @objc private func invoke() {
        guard isEnabled else { return }
        onActivate?()
    }

    private func updatePill(animated: Bool, preserveActiveAnimation: Bool) {
        let targetTransform = selected
            ? CATransform3DMakeScale(FluentSelectorBarMetrics.pillSelectedScale, 1, 1)
            : CATransform3DIdentity
        let targetOpacity: Float = selected ? 1 : 0
        let currentTransform = pillLayer.presentation()?.transform ?? pillLayer.transform
        let currentOpacity = pillLayer.presentation()?.opacity ?? pillLayer.opacity

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.transform = targetTransform
        pillLayer.opacity = targetOpacity
        pillLayer.fillColor = (isEnabled ? theme.accentFillDefault : theme.accentFillDisabled).cgColor
        CATransaction.commit()
        if !preserveActiveAnimation {
            pillLayer.removeAnimation(forKey: "fluent.selectorbar.pill.scale")
            pillLayer.removeAnimation(forKey: "fluent.selectorbar.pill.opacity")
        }

        guard selected, animated, !reduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = currentOpacity > 0 ? currentTransform : CATransform3DIdentity
        scale.toValue = targetTransform
        scale.duration = FluentMotion.controlFast.duration
        scale.timingFunction = FluentMotion.controlFast.curve.timingFunction
        pillLayer.add(scale, forKey: "fluent.selectorbar.pill.scale")

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = currentOpacity
        opacity.toValue = targetOpacity
        opacity.duration = FluentMotion.controlFast.duration
        opacity.timingFunction = FluentMotion.controlFast.curve.timingFunction
        pillLayer.add(opacity, forKey: "fluent.selectorbar.pill.opacity")
    }

    private func updateFocusVisual() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.strokeColor = theme.accent.cgColor
        focusLayer.lineWidth = theme.focusStrokeWidth
        focusLayer.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
        CATransaction.commit()
        needsDisplay = true
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * metricScale }
}
