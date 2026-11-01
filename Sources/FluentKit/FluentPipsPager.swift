import AppKit

public enum FluentPipsPagerButtonVisibility: Hashable, Sendable {
    case visible
    case visibleOnPointerOver
    case collapsed
}

public enum FluentPipsPagerWrapMode: Hashable, Sendable {
    case none
    case wrap
}

public enum FluentPipsPagerOrientation: Hashable, Sendable {
    case horizontal
    case vertical
}

/// Native AppKit implementation of WinUI's PipsPager paging, viewport, navigation-button,
/// keyboard, right-to-left, and Selection automation contracts.
public final class FluentPipsPager: NSControl, FluentControlSizeConfigurable {
    fileprivate enum Metrics {
        static let normalGlyph: CGFloat = 4
        static let selectedGlyph: CGFloat = 6
        static let horizontalPipSize = NSSize(width: 12, height: 24)
        static let verticalPipSize = NSSize(width: 24, height: 12)
        static let navigationButtonSize = NSSize(width: 24, height: 24)
        static let navigationPressedScale: CGFloat = 0.875
        static let virtualizationBuffer = 2
    }

    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            applyAppearance(animated: false)
            invalidateIntrinsicContentSize()
        }
    }

    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            if reduceMotion { removeVisualAnimations() }
            realizedPipButtons.values.forEach {
                $0.reduceMotion = reduceMotion
                $0.refreshAppearance(animated: false)
            }
            for button in [previousButton, nextButton] {
                button.reduceMotion = reduceMotion
                button.refreshAppearance(animated: false)
            }
        }
    }

    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            rebuildRealizedPips()
            needsLayout = true
        }
    }

    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            rebuildRealizedPips()
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    /// A negative count selects WinUI's unbounded-pages mode. Zero displays no pips.
    public var numberOfPages: Int {
        didSet {
            guard oldValue != numberOfPages else { return }
            if numberOfPages >= 0 {
                infiniteItemCount = 0
                if numberOfPages == 0, storedSelectedPageIndex != 0 {
                    setSelectedPageIndex(0, notify: true)
                } else if numberOfPages > 0, storedSelectedPageIndex >= numberOfPages {
                    setSelectedPageIndex(numberOfPages - 1, notify: true)
                }
            } else {
                updateInfiniteItemCount()
            }
            rebuildRealizedPips()
            updateNavigationButtons()
            invalidateIntrinsicContentSize()
            needsLayout = true
            updateAccessibilityState()
        }
    }

    public var selectedPageIndex: Int {
        get { storedSelectedPageIndex }
        set { setSelectedPageIndex(newValue, notify: true) }
    }

    public var maxVisiblePips: Int {
        didSet {
            guard oldValue != maxVisiblePips else { return }
            updateInfiniteItemCount()
            rebuildRealizedPips()
            updateNavigationButtons()
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public var orientation: FluentPipsPagerOrientation {
        didSet {
            guard oldValue != orientation else { return }
            rebuildRealizedPips()
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public var previousButtonVisibility: FluentPipsPagerButtonVisibility {
        didSet {
            guard oldValue != previousButtonVisibility else { return }
            updateNavigationButtons()
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public var nextButtonVisibility: FluentPipsPagerButtonVisibility {
        didSet {
            guard oldValue != nextButtonVisibility else { return }
            updateNavigationButtons()
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    public var wrapMode: FluentPipsPagerWrapMode {
        didSet {
            guard oldValue != wrapMode else { return }
            updateNavigationButtons()
        }
    }

    /// Receives the old and new zero-based indices after source-compatible coercion.
    public var onSelectedIndexChanged: ((Int, Int) -> Void)?

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            realizedPipButtons.values.forEach { $0.isEnabled = isEnabled }
            updateNavigationButtons()
            updateAccessibilityState()
        }
    }

    private(set) var realizedPipButtons: [Int: FluentPipsPagerPipButton] = [:]
    let previousButton = FluentPipsPagerNavigationButton()
    let nextButton = FluentPipsPagerNavigationButton()
    let viewport = NSClipView()
    let itemsHost = NSView()

    private var storedSelectedPageIndex: Int
    private var infiniteItemCount = 0
    private var trackingArea: NSTrackingArea?
    private var pointerOverControl = false
    private var keyboardFocusWithin = false
    private var suppressesSelectionNotification = false

    private var metricScale: CGFloat { fluentControlSize.metricScale }
    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }
    private var visiblePipCount: Int {
        let maximum = max(0, maxVisiblePips)
        guard maximum > 0 else { return 0 }
        if numberOfPages < 0 { return min(maximum, infiniteItemCount) }
        return min(maximum, max(0, numberOfPages))
    }
    private var logicalItemCount: Int { numberOfPages < 0 ? infiniteItemCount : max(0, numberOfPages) }
    private var pipExtent: CGFloat {
        let size = orientation == .horizontal ? Metrics.horizontalPipSize : Metrics.verticalPipSize
        return (orientation == .horizontal ? size.width : size.height) * metricScale
    }
    private var pipCrossExtent: CGFloat {
        let size = orientation == .horizontal ? Metrics.horizontalPipSize : Metrics.verticalPipSize
        return (orientation == .horizontal ? size.height : size.width) * metricScale
    }

    public init(
        numberOfPages: Int = -1,
        selectedPageIndex: Int = 0,
        maxVisiblePips: Int = 5,
        orientation: FluentPipsPagerOrientation = .horizontal,
        previousButtonVisibility: FluentPipsPagerButtonVisibility = .collapsed,
        nextButtonVisibility: FluentPipsPagerButtonVisibility = .collapsed,
        wrapMode: FluentPipsPagerWrapMode = .none
    ) {
        self.numberOfPages = numberOfPages
        storedSelectedPageIndex = Self.coerceSelectedIndex(selectedPageIndex, pageCount: numberOfPages)
        self.maxVisiblePips = maxVisiblePips
        self.orientation = orientation
        self.previousButtonVisibility = previousButtonVisibility
        self.nextButtonVisibility = nextButtonVisibility
        self.wrapMode = wrapMode
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        numberOfPages = -1
        storedSelectedPageIndex = 0
        maxVisiblePips = 5
        orientation = .horizontal
        previousButtonVisibility = .collapsed
        nextButtonVisibility = .collapsed
        wrapMode = .none
        super.init(coder: coder)
        configureView()
    }

    public override var intrinsicContentSize: NSSize {
        let navigationExtent = Metrics.navigationButtonSize.width * metricScale
        let previousExtent = previousButtonVisibility == .collapsed ? 0 : navigationExtent
        let nextExtent = nextButtonVisibility == .collapsed ? 0 : navigationExtent
        let pageExtent = CGFloat(visiblePipCount) * pipExtent
        if orientation == .horizontal {
            return NSSize(
                width: ceil(previousExtent + pageExtent + nextExtent),
                height: ceil(max(pipCrossExtent, Metrics.navigationButtonSize.height * metricScale))
            )
        }
        return NSSize(
            width: ceil(max(pipCrossExtent, Metrics.navigationButtonSize.width * metricScale)),
            height: ceil(previousExtent + pageExtent + nextExtent)
        )
    }

    public override func layout() {
        super.layout()
        let scale = metricScale
        let navigationSize = NSSize(
            width: Metrics.navigationButtonSize.width * scale,
            height: Metrics.navigationButtonSize.height * scale
        )
        let viewportExtent = CGFloat(visiblePipCount) * pipExtent
        let previousCollapsed = previousButtonVisibility == .collapsed
        let nextCollapsed = nextButtonVisibility == .collapsed

        if orientation == .horizontal {
            let previousWidth = previousCollapsed ? 0 : navigationSize.width
            let nextWidth = nextCollapsed ? 0 : navigationSize.width
            let contentWidth = min(viewportExtent, max(0, bounds.width - previousWidth - nextWidth))
            let y = bounds.midY - navigationSize.height / 2
            if isRTL {
                nextButton.frame = NSRect(x: bounds.minX, y: y, width: nextWidth, height: navigationSize.height)
                viewport.frame = NSRect(x: nextButton.frame.maxX, y: bounds.midY - pipCrossExtent / 2, width: contentWidth, height: pipCrossExtent)
                previousButton.frame = NSRect(x: viewport.frame.maxX, y: y, width: previousWidth, height: navigationSize.height)
            } else {
                previousButton.frame = NSRect(x: bounds.minX, y: y, width: previousWidth, height: navigationSize.height)
                viewport.frame = NSRect(x: previousButton.frame.maxX, y: bounds.midY - pipCrossExtent / 2, width: contentWidth, height: pipCrossExtent)
                nextButton.frame = NSRect(x: viewport.frame.maxX, y: y, width: nextWidth, height: navigationSize.height)
            }
        } else {
            let previousHeight = previousCollapsed ? 0 : navigationSize.height
            let nextHeight = nextCollapsed ? 0 : navigationSize.height
            let contentHeight = min(viewportExtent, max(0, bounds.height - previousHeight - nextHeight))
            nextButton.frame = NSRect(
                x: bounds.midX - navigationSize.width / 2,
                y: bounds.minY,
                width: navigationSize.width,
                height: nextHeight
            )
            viewport.frame = NSRect(
                x: bounds.midX - pipCrossExtent / 2,
                y: nextButton.frame.maxY,
                width: pipCrossExtent,
                height: contentHeight
            )
            previousButton.frame = NSRect(
                x: bounds.midX - navigationSize.width / 2,
                y: viewport.frame.maxY,
                width: navigationSize.width,
                height: previousHeight
            )
        }
        previousButton.isHidden = previousCollapsed
        nextButton.isHidden = nextCollapsed
        layoutItemsHost()
        updateChevronDirections()
        scrollSelectionIntoCenter(animated: false)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        pointerOverControl = true
        updateNavigationButtons()
    }

    public override func mouseExited(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard !bounds.insetBy(dx: 1, dy: 1).contains(local) else { return }
        pointerOverControl = false
        updateNavigationButtons()
    }

    public override func accessibilityRole() -> NSAccessibility.Role? { .menu }
    public override func accessibilityLabel() -> String? { "Pips pager" }
    public override func accessibilityChildren() -> [Any]? {
        let pips = realizedPipButtons.keys.sorted().compactMap { realizedPipButtons[$0] }
        return [previousButton] + pips + [nextButton]
    }
    public override func accessibilitySelectedChildren() -> [Any]? {
        realizedPipButtons[storedSelectedPageIndex].map { [$0] } ?? []
    }

    @discardableResult
    public func selectPreviousPage() -> Bool {
        guard logicalItemCount != 0, logicalItemCount != 1 else { return false }
        if wrapMode == .wrap, numberOfPages > 1, storedSelectedPageIndex == 0 {
            selectedPageIndex = numberOfPages - 1
            return true
        }
        let target = max(0, storedSelectedPageIndex - 1)
        guard target != storedSelectedPageIndex else { return false }
        selectedPageIndex = target
        return true
    }

    @discardableResult
    public func selectNextPage() -> Bool {
        guard logicalItemCount != 0, logicalItemCount != 1 else { return false }
        if wrapMode == .wrap, numberOfPages > 0, storedSelectedPageIndex == numberOfPages - 1 {
            selectedPageIndex = 0
            return true
        }
        let target = numberOfPages < 0
            ? storedSelectedPageIndex + 1
            : min(storedSelectedPageIndex + 1, numberOfPages - 1)
        guard target != storedSelectedPageIndex else { return false }
        selectedPageIndex = target
        return true
    }

    func setSelectedPageIndexFromBinding(_ value: Int) {
        suppressesSelectionNotification = true
        setSelectedPageIndex(value, notify: false)
        suppressesSelectionNotification = false
    }

    private func configureView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        fluentSetDefaultAccessibilityLabel("Pips pager")

        viewport.drawsBackground = false
        viewport.documentView = itemsHost
        itemsHost.wantsLayer = true
        itemsHost.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(viewport)
        addSubview(previousButton)
        addSubview(nextButton)

        previousButton.onInvoke = { [weak self] in _ = self?.selectPreviousPage() }
        nextButton.onInvoke = { [weak self] in _ = self?.selectNextPage() }
        [previousButton, nextButton].forEach { button in
            button.onFocusChanged = { [weak self] in self?.scheduleFocusUpdate() }
            button.onNavigationKey = { [weak self] keyCode in
                self?.handleNavigationKey(keyCode, from: self?.storedSelectedPageIndex ?? 0) ?? false
            }
        }
        previousButton.fluentSetDefaultAccessibilityLabel("Previous page")
        nextButton.fluentSetDefaultAccessibilityLabel("Next page")

        updateInfiniteItemCount()
        rebuildRealizedPips()
        updateNavigationButtons()
        applyAppearance(animated: false)
        updateAccessibilityState()
    }

    private static func coerceSelectedIndex(_ value: Int, pageCount: Int) -> Int {
        let nonnegative = max(0, value)
        guard pageCount > 0 else { return nonnegative }
        return min(nonnegative, pageCount - 1)
    }

    private func setSelectedPageIndex(_ proposed: Int, notify: Bool) {
        let coerced = Self.coerceSelectedIndex(proposed, pageCount: numberOfPages)
        guard coerced != storedSelectedPageIndex else { return }
        let oldValue = storedSelectedPageIndex
        storedSelectedPageIndex = coerced
        updateInfiniteItemCount()
        rebuildRealizedPips()
        updateNavigationButtons()
        needsLayout = true
        layoutSubtreeIfNeeded()
        scrollSelectionIntoCenter(animated: true)
        updateAccessibilityState()
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        guard notify, !suppressesSelectionNotification else { return }
        sendAction(action, to: target)
        onSelectedIndexChanged?(oldValue, coerced)
    }

    private func updateInfiniteItemCount() {
        guard numberOfPages < 0 else { return }
        let minimum = max(storedSelectedPageIndex + 1, max(0, maxVisiblePips))
        infiniteItemCount = max(infiniteItemCount, minimum)
        if storedSelectedPageIndex == infiniteItemCount - 1 { infiniteItemCount += 1 }
    }

    private func realizedRange() -> Range<Int> {
        let count = logicalItemCount
        let visible = visiblePipCount
        guard count > 0, visible > 0 else { return 0..<0 }
        let desired = min(count, visible + Metrics.virtualizationBuffer * 2)
        var lower = max(0, storedSelectedPageIndex - visible / 2 - Metrics.virtualizationBuffer)
        lower = min(lower, max(0, count - desired))
        return lower..<(lower + desired)
    }

    private func rebuildRealizedPips() {
        let range = realizedRange()
        let obsoleteIndices = realizedPipButtons.keys.filter { !range.contains($0) }
        for index in obsoleteIndices {
            realizedPipButtons.removeValue(forKey: index)?.removeFromSuperview()
        }
        for index in range where realizedPipButtons[index] == nil {
            let button = FluentPipsPagerPipButton(index: index)
            button.onInvoke = { [weak self] index in self?.selectedPageIndex = index }
            button.onFocusChanged = { [weak self] in self?.scheduleFocusUpdate() }
            button.onNavigationKey = { [weak self] keyCode, index in
                self?.handleNavigationKey(keyCode, from: index) ?? false
            }
            itemsHost.addSubview(button)
            realizedPipButtons[index] = button
        }
        for (index, button) in realizedPipButtons {
            button.index = index
            button.isSelectedPip = index == storedSelectedPageIndex
            button.theme = theme
            button.reduceMotion = reduceMotion
            button.fluentControlSize = fluentControlSize
            button.isEnabled = isEnabled
            button.setAccessibilityLabel("Page \(index + 1)")
            button.setAccessibilityHelp(numberOfPages < 0
                ? "Page \(index + 1)"
                : "Page \(index + 1) of \(max(0, numberOfPages))")
        }
        needsLayout = true
    }

    private func layoutItemsHost() {
        let count = logicalItemCount
        let extent = CGFloat(count) * pipExtent
        if orientation == .horizontal {
            itemsHost.frame = NSRect(x: 0, y: 0, width: extent, height: pipCrossExtent)
        } else {
            itemsHost.frame = NSRect(x: 0, y: 0, width: pipCrossExtent, height: extent)
        }
        for (index, button) in realizedPipButtons {
            let position = visualPosition(for: index, count: count)
            if orientation == .horizontal {
                button.frame = NSRect(x: CGFloat(position) * pipExtent, y: 0, width: pipExtent, height: pipCrossExtent)
            } else {
                button.frame = NSRect(x: 0, y: CGFloat(count - position - 1) * pipExtent, width: pipCrossExtent, height: pipExtent)
            }
            button.orientation = orientation
        }
    }

    private func visualPosition(for logicalIndex: Int, count: Int) -> Int {
        orientation == .horizontal && isRTL ? count - logicalIndex - 1 : logicalIndex
    }

    private func scrollSelectionIntoCenter(animated: Bool) {
        guard visiblePipCount > 0, logicalItemCount > 0 else {
            viewport.scroll(to: .zero)
            return
        }
        let position = CGFloat(visualPosition(for: storedSelectedPageIndex, count: logicalItemCount))
        let viewportExtent = orientation == .horizontal ? viewport.bounds.width : viewport.bounds.height
        let contentExtent = CGFloat(logicalItemCount) * pipExtent
        let selectedCenter = orientation == .horizontal
            ? (position + 0.5) * pipExtent
            : contentExtent - (position + 0.5) * pipExtent
        let offset = min(max(0, selectedCenter - viewportExtent / 2), max(0, contentExtent - viewportExtent))
        let target = orientation == .horizontal
            ? NSPoint(x: offset, y: 0)
            : NSPoint(x: 0, y: offset)
        guard animated, !reduceMotion, window != nil else {
            viewport.scroll(to: target)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FluentAnimation.content
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            viewport.animator().setBoundsOrigin(target)
        }
    }

    private func updateNavigationButtons() {
        let hasPages = logicalItemCount > 0 && maxVisiblePips > 0
        let wraps = wrapMode == .wrap && numberOfPages > 1
        let previousAvailable = hasPages && (storedSelectedPageIndex > 0 || wraps)
        let nextAvailable = hasPages && (
            numberOfPages < 0 || storedSelectedPageIndex < numberOfPages - 1 || wraps
        )
        configureNavigationButton(
            previousButton,
            visibility: previousButtonVisibility,
            available: previousAvailable
        )
        configureNavigationButton(
            nextButton,
            visibility: nextButtonVisibility,
            available: nextAvailable
        )
        updateChevronDirections()
    }

    private func configureNavigationButton(
        _ button: FluentPipsPagerNavigationButton,
        visibility: FluentPipsPagerButtonVisibility,
        available: Bool
    ) {
        button.theme = theme
        button.reduceMotion = reduceMotion
        button.fluentControlSize = fluentControlSize
        button.isHidden = visibility == .collapsed
        let shownByMode = visibility == .visible || pointerOverControl || keyboardFocusWithin
        button.alphaValue = shownByMode && available ? 1 : 0
        button.isEnabled = available && isEnabled
        button.setAccessibilityHidden(button.isHidden)
    }

    private func updateChevronDirections() {
        if orientation == .vertical {
            previousButton.direction = .up
            nextButton.direction = .down
        } else if isRTL {
            previousButton.direction = .right
            nextButton.direction = .left
        } else {
            previousButton.direction = .left
            nextButton.direction = .right
        }
    }

    private func handleNavigationKey(_ keyCode: UInt16, from index: Int) -> Bool {
        let delta: Int
        switch keyCode {
        case 123: // Left
            delta = orientation == .horizontal && isRTL ? 1 : -1
        case 124: // Right
            delta = orientation == .horizontal && isRTL ? -1 : 1
        case 126: delta = -1 // Up
        case 125: delta = 1  // Down
        default: return false
        }
        let target = index + delta
        guard target >= 0, target < logicalItemCount else { return true }
        ensureRealizedForFocus(target)
        window?.makeFirstResponder(realizedPipButtons[target])
        return true
    }

    private func ensureRealizedForFocus(_ index: Int) {
        guard realizedPipButtons[index] == nil else { return }
        let button = FluentPipsPagerPipButton(index: index)
        button.onInvoke = { [weak self] index in self?.selectedPageIndex = index }
        button.onFocusChanged = { [weak self] in self?.scheduleFocusUpdate() }
        button.onNavigationKey = { [weak self] keyCode, index in
            self?.handleNavigationKey(keyCode, from: index) ?? false
        }
        button.isSelectedPip = index == storedSelectedPageIndex
        button.theme = theme
        button.reduceMotion = reduceMotion
        button.fluentControlSize = fluentControlSize
        button.isEnabled = isEnabled
        button.setAccessibilityLabel("Page \(index + 1)")
        button.setAccessibilityHelp(numberOfPages < 0
            ? "Page \(index + 1)"
            : "Page \(index + 1) of \(max(0, numberOfPages))")
        itemsHost.addSubview(button)
        realizedPipButtons[index] = button
        layoutItemsHost()
    }

    private func scheduleFocusUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var responder = self.window?.firstResponder as? NSView
            if !self.keyboardFocusWithin,
               let pip = responder as? FluentPipsPagerPipButton,
               pip.index != self.storedSelectedPageIndex {
                self.ensureRealizedForFocus(self.storedSelectedPageIndex)
                if let selected = self.realizedPipButtons[self.storedSelectedPageIndex] {
                    _ = self.window?.makeFirstResponder(selected)
                    responder = selected
                }
            }
            self.keyboardFocusWithin = responder.map { $0 === self || $0.isDescendant(of: self) } ?? false
            self.updateNavigationButtons()
        }
    }

    private func applyAppearance(animated: Bool) {
        realizedPipButtons.values.forEach {
            $0.theme = theme
            $0.refreshAppearance(animated: animated)
        }
        previousButton.theme = theme
        nextButton.theme = theme
        previousButton.refreshAppearance(animated: animated)
        nextButton.refreshAppearance(animated: animated)
        updateNavigationButtons()
    }

    private func updateAccessibilityState() {
        setAccessibilityEnabled(isEnabled)
        setAccessibilityValue(numberOfPages == 0 ? "No pages" : "Page \(storedSelectedPageIndex + 1)")
    }

    private func removeVisualAnimations() {
        realizedPipButtons.values.forEach { $0.removeVisualAnimations() }
        previousButton.removeVisualAnimations()
        nextButton.removeVisualAnimations()
        viewport.layer?.removeAllAnimations()
    }
}

final class FluentPipsPagerPipButton: NSButton, FluentControlSizeConfigurable {
    var index: Int
    var isSelectedPip = false { didSet { refreshAppearance(animated: true) } }
    var orientation: FluentPipsPagerOrientation = .horizontal
    var theme: FluentTheme = .current { didSet { refreshAppearance(animated: false) } }
    var reduceMotion = false
    var fluentControlSize: FluentControlSize = .regular { didSet { refreshAppearance(animated: false) } }
    var onInvoke: ((Int) -> Void)?
    var onFocusChanged: (() -> Void)?
    var onNavigationKey: ((UInt16, Int) -> Bool)?

    private let chromeLayer = CALayer()
    private let glyphLayer = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var pointerOver = false
    private var pressed = false

    override var acceptsFirstResponder: Bool { isEnabled }

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        title = ""
        target = self
        action = #selector(invoke)
        focusRingType = .none
        wantsLayer = true
        layer?.addSublayer(chromeLayer)
        layer?.addSublayer(glyphLayer)
        layer?.addSublayer(focusLayer)
        glyphLayer.fillColor = NSColor.clear.cgColor
        focusLayer.fillColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        refreshAppearance(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerOver = true
        refreshAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        pressed = false
        refreshAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refreshAppearance(animated: true)
        super.mouseDown(with: event)
        pressed = false
        refreshAppearance(animated: true)
    }

    override func keyDown(with event: NSEvent) {
        if onNavigationKey?(event.keyCode, index) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { refreshAppearance(animated: true); onFocusChanged?() }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { refreshAppearance(animated: true); onFocusChanged?() }
        return result
    }

    override func accessibilityValue() -> Any? { isSelectedPip ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onInvoke?(index)
        return true
    }

    @objc private func invoke() { onInvoke?(index) }

    func refreshAppearance(animated: Bool) {
        guard layer != nil else { return }
        let state: FluentControlState = !isEnabled ? .disabled : pressed ? .pressed : pointerOver ? .pointerOver : isSelectedPip ? .selected : .normal
        let scale = fluentControlSize.metricScale
        let glyphSize = (pressed ? Metrics.normalGlyph : (isSelectedPip || pointerOver) ? Metrics.selectedGlyph : Metrics.normalGlyph) * scale
        let glyphFrame = CGRect(x: bounds.midX - glyphSize / 2, y: bounds.midY - glyphSize / 2, width: glyphSize, height: glyphSize)
        let chromeColor = theme.pipsPagerIndicatorBackground(selected: isSelectedPip, state: state)
        let glyphColor = theme.pipsPagerIndicatorForeground(selected: isSelectedPip, state: state)
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? FluentAnimation.stateChange : 0)
        chromeLayer.frame = bounds
        chromeLayer.cornerRadius = theme.designTokens.controlCornerRadius * scale
        chromeLayer.backgroundColor = chromeColor.cgColor
        chromeLayer.borderWidth = theme.isHighContrast ? theme.controlStrokeWidth : 0
        chromeLayer.borderColor = chromeColor.cgColor
        glyphLayer.path = CGPath(ellipseIn: glyphFrame, transform: nil)
        glyphLayer.fillColor = glyphColor.cgColor
        focusLayer.frame = bounds.insetBy(dx: 1, dy: 1)
        focusLayer.path = CGPath(roundedRect: focusLayer.bounds, cornerWidth: theme.designTokens.controlCornerRadius * scale, cornerHeight: theme.designTokens.controlCornerRadius * scale, transform: nil)
        focusLayer.strokeColor = theme.focusStrokeOuter.cgColor
        focusLayer.lineWidth = theme.focusStrokeWidth
        focusLayer.opacity = FluentFocusVisibility.isKeyboardFocusVisible(for: self) ? 1 : 0
        CATransaction.commit()
        setAccessibilityEnabled(isEnabled)
    }

    func removeVisualAnimations() {
        [layer, chromeLayer, glyphLayer, focusLayer].forEach { $0?.removeAllAnimations() }
    }

    private enum Metrics {
        static let normalGlyph: CGFloat = 4
        static let selectedGlyph: CGFloat = 6
    }
}

final class FluentPipsPagerNavigationButton: NSButton, FluentControlSizeConfigurable {
    var theme: FluentTheme = .current { didSet { refreshAppearance(animated: false) } }
    var reduceMotion = false
    var fluentControlSize: FluentControlSize = .regular { didSet { refreshAppearance(animated: false) } }
    var direction: FluentChevronDirection = .left { didSet { refreshAppearance(animated: false) } }
    var onInvoke: (() -> Void)?
    var onFocusChanged: (() -> Void)?
    var onNavigationKey: ((UInt16) -> Bool)?

    private let chromeLayer = CALayer()
    private let chevronLayer = FluentChevronPrimitiveLayer()
    private var trackingArea: NSTrackingArea?
    private var pointerOver = false
    private var pressed = false

    override var acceptsFirstResponder: Bool { isEnabled }

    init() {
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        title = ""
        target = self
        action = #selector(invoke)
        focusRingType = .default
        wantsLayer = true
        layer?.addSublayer(chromeLayer)
        layer?.addSublayer(chevronLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        refreshAppearance(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerOver = true; refreshAppearance(animated: true) }
    override func mouseExited(with event: NSEvent) { pointerOver = false; pressed = false; refreshAppearance(animated: true) }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refreshAppearance(animated: true)
        super.mouseDown(with: event)
        pressed = false
        refreshAppearance(animated: true)
    }

    override func keyDown(with event: NSEvent) {
        if onNavigationKey?(event.keyCode) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChanged?() }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChanged?() }
        return result
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onInvoke?()
        return true
    }

    @objc private func invoke() { onInvoke?() }

    func refreshAppearance(animated: Bool) {
        guard layer != nil else { return }
        let state: FluentControlState = !isEnabled ? .disabled : pressed ? .pressed : pointerOver ? .pointerOver : .normal
        let scale = fluentControlSize.metricScale
        let background = theme.pipsPagerNavigationBackground(for: state)
        let foreground = theme.pipsPagerNavigationForeground(for: state)
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? FluentAnimation.stateChange : 0)
        chromeLayer.frame = bounds
        chromeLayer.cornerRadius = theme.designTokens.controlCornerRadius * scale
        chromeLayer.backgroundColor = background.cgColor
        chromeLayer.borderWidth = theme.isHighContrast ? theme.controlStrokeWidth : 0
        chromeLayer.borderColor = theme.isHighContrast ? theme.controlStrokeStrong.cgColor : NSColor.clear.cgColor
        let transform = pressed
            ? CATransform3DMakeScale(FluentPipsPager.Metrics.navigationPressedScale, FluentPipsPager.Metrics.navigationPressedScale, 1)
            : CATransform3DIdentity
        layer?.transform = transform
        CATransaction.commit()
        chevronLayer.update(
            frame: CGRect(x: bounds.midX - 5, y: bounds.midY - 5, width: 10, height: 10),
            color: foreground,
            state: state,
            direction: direction,
            inverted: !isFlipped,
            backingScale: window?.backingScaleFactor,
            preservingUnchangedAnimations: window != nil && !isHiddenOrHasHiddenAncestor && isEnabled && !reduceMotion,
            reduceMotion: reduceMotion,
            animated: animated && !reduceMotion
        )
        setAccessibilityEnabled(isEnabled)
    }

    func removeVisualAnimations() {
        [layer, chromeLayer, chevronLayer].forEach { $0?.removeAllAnimations() }
    }
}

public struct FluentPipsPagerView: FluentUpdatablePrimitiveView {
    private let selectedPageIndex: FluentBinding<Int>
    private let numberOfPages: Int
    private let maxVisiblePips: Int
    private let orientation: FluentPipsPagerOrientation
    private let previousButtonVisibility: FluentPipsPagerButtonVisibility
    private let nextButtonVisibility: FluentPipsPagerButtonVisibility
    private let wrapMode: FluentPipsPagerWrapMode
    private let onSelectedIndexChanged: ((Int, Int) -> Void)?

    public init(
        selectedPageIndex: FluentBinding<Int>,
        numberOfPages: Int = -1,
        maxVisiblePips: Int = 5,
        orientation: FluentPipsPagerOrientation = .horizontal,
        previousButtonVisibility: FluentPipsPagerButtonVisibility = .collapsed,
        nextButtonVisibility: FluentPipsPagerButtonVisibility = .collapsed,
        wrapMode: FluentPipsPagerWrapMode = .none,
        onSelectedIndexChanged: ((Int, Int) -> Void)? = nil
    ) {
        self.selectedPageIndex = selectedPageIndex
        self.numberOfPages = numberOfPages
        self.maxVisiblePips = maxVisiblePips
        self.orientation = orientation
        self.previousButtonVisibility = previousButtonVisibility
        self.nextButtonVisibility = nextButtonVisibility
        self.wrapMode = wrapMode
        self.onSelectedIndexChanged = onSelectedIndexChanged
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentBoundPipsPager(
            selectedPageIndex: selectedPageIndex,
            numberOfPages: numberOfPages,
            maxVisiblePips: maxVisiblePips,
            orientation: orientation,
            previousButtonVisibility: previousButtonVisibility,
            nextButtonVisibility: nextButtonVisibility,
            wrapMode: wrapMode,
            onSelectedIndexChanged: onSelectedIndexChanged,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentBoundPipsPager else { return false }
        host.update(
            selectedPageIndex: selectedPageIndex,
            numberOfPages: numberOfPages,
            maxVisiblePips: maxVisiblePips,
            orientation: orientation,
            previousButtonVisibility: previousButtonVisibility,
            nextButtonVisibility: nextButtonVisibility,
            wrapMode: wrapMode,
            onSelectedIndexChanged: onSelectedIndexChanged,
            context: context
        )
        return true
    }
}

private final class FluentBoundPipsPager: NSView {
    let pager: FluentPipsPager
    private var binding: FluentBinding<Int>
    private var observedBinding: FluentBinding<Int>?
    private var observerID: UUID?
    private var subscriptionGeneration: UInt = 0
    private var applyingBinding = false

    override var intrinsicContentSize: NSSize { pager.intrinsicContentSize }

    init(
        selectedPageIndex: FluentBinding<Int>,
        numberOfPages: Int,
        maxVisiblePips: Int,
        orientation: FluentPipsPagerOrientation,
        previousButtonVisibility: FluentPipsPagerButtonVisibility,
        nextButtonVisibility: FluentPipsPagerButtonVisibility,
        wrapMode: FluentPipsPagerWrapMode,
        onSelectedIndexChanged: ((Int, Int) -> Void)?,
        context: FluentRenderContext
    ) {
        binding = selectedPageIndex
        pager = FluentPipsPager(
            numberOfPages: numberOfPages,
            selectedPageIndex: selectedPageIndex.get(),
            maxVisiblePips: maxVisiblePips,
            orientation: orientation,
            previousButtonVisibility: previousButtonVisibility,
            nextButtonVisibility: nextButtonVisibility,
            wrapMode: wrapMode
        )
        super.init(frame: .zero)
        addSubview(pager)
        pager.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pager.leadingAnchor.constraint(equalTo: leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: trailingAnchor),
            pager.topAnchor.constraint(equalTo: topAnchor),
            pager.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyContext(context)
        installValueHandler(onSelectedIndexChanged)
        normalizeBindingIfNeeded(requested: selectedPageIndex.get())
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { removeObserver() }

    func update(
        selectedPageIndex: FluentBinding<Int>,
        numberOfPages: Int,
        maxVisiblePips: Int,
        orientation: FluentPipsPagerOrientation,
        previousButtonVisibility: FluentPipsPagerButtonVisibility,
        nextButtonVisibility: FluentPipsPagerButtonVisibility,
        wrapMode: FluentPipsPagerWrapMode,
        onSelectedIndexChanged: ((Int, Int) -> Void)?,
        context: FluentRenderContext
    ) {
        let observationChanged = binding.observationIdentity != selectedPageIndex.observationIdentity
        if observationChanged { removeObserver() }
        binding = selectedPageIndex
        applyContext(context)
        installValueHandler(onSelectedIndexChanged)
        pager.numberOfPages = numberOfPages
        pager.maxVisiblePips = maxVisiblePips
        pager.orientation = orientation
        pager.previousButtonVisibility = previousButtonVisibility
        pager.nextButtonVisibility = nextButtonVisibility
        pager.wrapMode = wrapMode
        applyingBinding = true
        let requested = selectedPageIndex.get()
        pager.setSelectedPageIndexFromBinding(requested)
        applyingBinding = false
        normalizeBindingIfNeeded(requested: requested)
        if observationChanged { installObserver() }
        invalidateIntrinsicContentSize()
    }

    private func applyContext(_ context: FluentRenderContext) {
        pager.theme = context.theme
        pager.reduceMotion = context.reduceMotion
        pager.fluentLayoutDirection = context.layoutDirection
    }

    private func installValueHandler(_ callback: ((Int, Int) -> Void)?) {
        pager.onSelectedIndexChanged = { [weak self] old, new in
            guard let self, !applyingBinding else { return }
            binding.set(new)
            callback?(old, new)
        }
    }

    private func installObserver() {
        subscriptionGeneration &+= 1
        let generation = subscriptionGeneration
        observedBinding = binding
        observerID = binding.observe? { [weak self] value in
            let apply = { [weak self] in
                guard let self, generation == subscriptionGeneration else { return }
                applyingBinding = true
                pager.setSelectedPageIndexFromBinding(value)
                applyingBinding = false
                normalizeBindingIfNeeded(requested: value)
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func removeObserver() {
        subscriptionGeneration &+= 1
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observerID = nil
        observedBinding = nil
    }

    private func normalizeBindingIfNeeded(requested: Int) {
        let normalized = pager.selectedPageIndex
        if requested != normalized { binding.set(normalized) }
    }
}
