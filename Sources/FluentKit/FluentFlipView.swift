import AppKit

/// A WinUI-style horizontal paging control. Items occupy one viewport at a time and can be
/// navigated with overlaid previous/next buttons, arrow keys, or mouse/trackpad wheel events.
/// Buttons appear on pointer or keyboard interaction and hide after three idle seconds, except
/// while the pointer is over a button. A wheel burst advances once until a 200 ms pause or reversal.
/// Selection is zero-based and clamped to the available range, or `-1` for an empty collection.
/// Data changes synchronize that normalized index back to the optional binding.
public struct FluentFlipView<Data: RandomAccessCollection, Content: FluentView>:
    FluentUpdatablePrimitiveView {
    private let data: Data
    private let selection: FluentBinding<Int>?
    private let onSelectionChanged: ((Int) -> Void)?
    private let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        selection: FluentBinding<Int>? = nil,
        onSelectionChanged: ((Int) -> Void)? = nil,
        @FluentViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.selection = selection
        self.onSelectionChanged = onSelectionChanged
        self.content = content
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentFlipViewHost(
            records: makeRecords(in: context),
            selection: selection,
            onSelectionChanged: onSelectionChanged,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFlipViewHost else { return false }
        host.update(
            records: makeRecords(in: context),
            selection: selection,
            onSelectionChanged: onSelectionChanged,
            context: context
        )
        return true
    }

    private func makeRecords(in context: FluentRenderContext) -> [FluentFlipViewRecord] {
        data.map { element in
            let contentView = content(element)
            return FluentFlipViewRecord(
                make: {
                    FluentViewHost(FluentAnyView(contentView), context: context)
                },
                update: { nativeView, updateContext in
                    guard let host = nativeView as? FluentViewHost<FluentAnyView> else {
                        return false
                    }
                    host.update(FluentAnyView(contentView), context: updateContext)
                    return true
                }
            )
        }
    }
}

private struct FluentFlipViewRecord {
    let make: () -> NSView
    let update: (NSView, FluentRenderContext) -> Bool
}

private final class FluentFlipViewHost: NSControl {
    private static let buttonWidth: CGFloat = 16
    private static let buttonHeight: CGFloat = 38
    private static let transition = FluentMotionToken(
        duration: 0.250,
        curve: .controlFastOutSlowIn
    )

    private let focusLayer = CAShapeLayer()
    private var windowObservation: NSKeyValueObservation?
    private var navigationTimer: Timer?
    private var showsNavigationButtons = false
    private weak var hoveredNavigationButton: FluentFlipViewButton?
    private var lastWheelTime: TimeInterval?
    private var lastWheelDirection = 0
    private let contentContainer = NSView()
    private let previousButton = FluentFlipViewButton(
        symbolName: "chevron.left",
        accessibilityLabel: "Previous"
    )
    private let nextButton = FluentFlipViewButton(
        symbolName: "chevron.right",
        accessibilityLabel: "Next"
    )
    private var records: [FluentFlipViewRecord] = []
    private var contentHosts: [NSView] = []
    private var selectionBinding: FluentBinding<Int>?
    private var selectionObserverID: UUID?
    private var selectionObservationGeneration: UInt64 = 0
    private var onSelectionChanged: ((Int) -> Void)?
    private var context: FluentRenderContext
    private var selectedIndex = 0
    private var isWritingBinding = false
    private var animationGeneration = 0
    private var isTransitioning = false
    private let animationCoordinator = FluentAnimationCoordinator()

    init(
        records: [FluentFlipViewRecord],
        selection: FluentBinding<Int>?,
        onSelectionChanged: ((Int) -> Void)?,
        context: FluentRenderContext
    ) {
        self.records = records
        selectionBinding = selection
        self.onSelectionChanged = onSelectionChanged
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.FlipView")
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        fluentSetDefaultAccessibilityLabel("Flip view")

        contentContainer.identifier = NSUserInterfaceItemIdentifier("FluentKit.FlipView.Content")
        contentContainer.wantsLayer = true
        contentContainer.layer?.masksToBounds = true
        addSubview(contentContainer)

        previousButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.FlipView.Previous")
        nextButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.FlipView.Next")
        previousButton.theme = context.theme
        nextButton.theme = context.theme
        previousButton.onClick = { [weak self] in
            guard let self else { return }
            self.select(self.mapSelectionOffset(-1), animated: true)
            self.revealNavigationButtons()
        }
        nextButton.onClick = { [weak self] in
            guard let self else { return }
            self.select(self.mapSelectionOffset(1), animated: true)
            self.revealNavigationButtons()
        }
        addSubview(previousButton)
        addSubview(nextButton)
        previousButton.onPointerPresenceChanged = { [weak self] inside in
            guard let self else { return }
            self.navigationPointerChanged(inside, button: self.previousButton)
        }
        nextButton.onPointerPresenceChanged = { [weak self] inside in
            guard let self else { return }
            self.navigationPointerChanged(inside, button: self.nextButton)
        }
        focusRingType = .none
        focusLayer.name = "FluentKit.FlipView.Focus"
        focusLayer.fillColor = NSColor.clear.cgColor
        focusLayer.zPosition = 10
        layer?.addSublayer(focusLayer)
        updateFocusVisual()
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))

        animationCoordinator.reduceMotion = context.reduceMotion
        rebuildContentHosts()
        selectedIndex = clamped(selection?.get() ?? 0)
        synchronizeSelectionBinding()
        showCurrent()
        updateAccessibilityValue()
        updateButtonState()
        installSelectionObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { isEnabled }

    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                hideNavigationButtons()
                lastWheelTime = nil
                lastWheelDirection = 0
                if ownsFirstResponder(in: self) { window?.makeFirstResponder(nil) }
            }
            updateButtonState()
            updateFocusVisual()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            if self.ownsFirstResponder(in: self), FluentFocusVisibility.isKeyboardInteraction(in: self.window) {
                self.revealNavigationButtons()
            }
            self.updateFocusVisual()
        }
        if window == nil { hideNavigationButtons() }
        updateFocusVisual()
    }

    private func ownsFirstResponder(in root: NSView) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if let editor = responder as? NSTextView, let delegate = editor.delegate as? NSView,
           delegate === root || delegate.isDescendant(of: root) { return true }
        guard let view = responder as? NSView else { return false }
        return view === root || view.isDescendant(of: root)
    }

    override func becomeFirstResponder() -> Bool {
        guard isEnabled else { return false }
        let result = super.becomeFirstResponder()
        if result, FluentFocusVisibility.isKeyboardInteraction(in: window) { revealNavigationButtons() }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        updateFocusVisual()
    }

    override func mouseEntered(with event: NSEvent) { revealNavigationButtons() }
    override func mouseMoved(with event: NSEvent) { revealNavigationButtons() }

    private func navigationPointerChanged(_ inside: Bool, button: FluentFlipViewButton) {
        guard isEnabled else { return }
        if inside { hoveredNavigationButton = button }
        else if hoveredNavigationButton === button { hoveredNavigationButton = nil }
        revealNavigationButtons()
    }

    private func revealNavigationButtons() {
        guard isEnabled else { return }
        showsNavigationButtons = true
        navigationTimer?.invalidate()
        // FlipView_Partial.h: FLIP_VIEW_BUTTONS_SHOW_DURATION_MS = 3000. The source
        // collapses the buttons immediately at expiry; it does not specify an opacity clip.
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.navigationTimer = nil
            if self.hoveredNavigationButton?.isHidden == false { return }
            self.hideNavigationButtons()
        }
        navigationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateButtonState()
        updateFocusVisual()
    }

    private func hideNavigationButtons() {
        navigationTimer?.invalidate()
        navigationTimer = nil
        showsNavigationButtons = false
        hoveredNavigationButton = nil
        updateButtonState()
    }

    private func updateFocusVisual() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusLayer.strokeColor = context.theme.accent.cgColor
        focusLayer.lineWidth = context.theme.focusStrokeWidth
        focusLayer.opacity = isEnabled && ownsFirstResponder(in: self)
            && FluentFocusVisibility.isKeyboardInteraction(in: window) ? 1 : 0
        CATransaction.commit()
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, !event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        var delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        if horizontal, userInterfaceLayoutDirection == .rightToLeft { delta = -delta }
        guard delta != 0 else { super.scrollWheel(with: event); return }
        let direction = delta < 0 ? 1 : -1
        let canFlip = direction != lastWheelDirection || lastWheelTime.map { event.timestamp - $0 > 0.2 } != false
        // Record suppressed deltas too: a long momentum tail must not advance every 200 ms.
        lastWheelTime = event.timestamp
        guard canFlip else { return }
        let target = mapSelectionOffset(direction)
        guard target != selectedIndex else { super.scrollWheel(with: event); return }
        lastWheelDirection = direction
        select(target, animated: true)
    }

    override func accessibilityPerformIncrement() -> Bool { accessibilityMove(1) }
    override func accessibilityPerformDecrement() -> Bool { accessibilityMove(-1) }
    private func accessibilityMove(_ offset: Int) -> Bool {
        guard isEnabled, mapSelectionOffset(offset) != selectedIndex else { return false }
        select(mapSelectionOffset(offset), animated: true)
        return true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: 180)
    }

    override func layout() {
        super.layout()
        contentContainer.frame = bounds
        for host in contentHosts {
            host.frame = contentContainer.bounds
        }
        let margin = min(1, max(0, bounds.width / 2))
        let width = min(Self.buttonWidth, max(0, bounds.width - 2 * margin))
        let height = min(Self.buttonHeight, max(0, bounds.height - 2))
        let buttonY = bounds.minY + max((bounds.height - height) / 2, 0)
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let leading = bounds.minX + margin
        let trailing = bounds.maxX - margin - width
        previousButton.frame = NSRect(x: isRTL ? trailing : leading, y: buttonY, width: width, height: height)
        nextButton.frame = NSRect(x: isRTL ? leading : trailing, y: buttonY, width: width, height: height)
        let inset = min(2, max(0, min(bounds.width, bounds.height) / 2))
        focusLayer.frame = bounds
        focusLayer.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: 2, cornerHeight: 2, transform: nil)
        updateFocusVisual()
        previousButton.updateSymbol(isRTL ? "chevron.right" : "chevron.left")
        nextButton.updateSymbol(isRTL ? "chevron.left" : "chevron.right")
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        updateFocusVisual()
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let leftKey: UInt16 = isRTL ? 124 : 123
        let rightKey: UInt16 = isRTL ? 123 : 124
        if [leftKey, rightKey, 115, 119].contains(event.keyCode) { revealNavigationButtons() }
        switch event.keyCode {
        case leftKey:
            select(mapSelectionOffset(-1), animated: true)
        case rightKey:
            select(mapSelectionOffset(1), animated: true)
        case 115:
            select(0, animated: true)
        case 119:
            select(records.count - 1, animated: true)
        default:
            super.keyDown(with: event)
        }
    }

    func update(
        records: [FluentFlipViewRecord],
        selection: FluentBinding<Int>?,
        onSelectionChanged: ((Int) -> Void)?,
        context: FluentRenderContext
    ) {
        // Detach from the old source before replacing its binding, including queued deliveries.
        removeSelectionObserver()
        selectionBinding = selection
        self.onSelectionChanged = onSelectionChanged
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        previousButton.theme = context.theme
        nextButton.theme = context.theme

        let canReuse = self.records.count == records.count
        var reuseFailed = false
        if canReuse {
            for (index, record) in records.enumerated() {
                guard index < contentHosts.count,
                      record.update(contentHosts[index], context) else {
                    reuseFailed = true
                    break
                }
            }
        }
        self.records = records
        if !canReuse || reuseFailed {
            rebuildContentHosts()
        }
        let target = clamped(selection?.get() ?? selectedIndex)
        if target != selectedIndex {
            commit(to: target, animated: false)
        } else {
            synchronizeSelectionBinding()
            if !isTransitioning || context.reduceMotion { showCurrent() }
        }
        installSelectionObserver()
        updateAccessibilityValue()
        updateButtonState()
        needsLayout = true
    }

    deinit {
        navigationTimer?.invalidate()
        removeSelectionObserver()
    }

    // MARK: - Selection

    private func mapSelectionOffset(_ offset: Int) -> Int {
        if records.count <= 1 { return selectedIndex }
        if selectedIndex + offset < 0 { return 0 }
        if selectedIndex + offset >= records.count { return records.count - 1 }
        return selectedIndex + offset
    }

    private func clamped(_ index: Int) -> Int {
        guard !records.isEmpty else { return -1 }
        return min(max(index, 0), records.count - 1)
    }

    private func select(_ index: Int, animated: Bool) {
        guard isEnabled else { return }
        let target = clamped(index)
        guard target >= 0, target != selectedIndex else { return }
        commit(to: target, animated: animated)
    }

    private func synchronizeSelectionBinding() {
        guard let selectionBinding, !isWritingBinding, selectionBinding.get() != selectedIndex else { return }
        isWritingBinding = true
        defer { isWritingBinding = false }
        selectionBinding.set(selectedIndex)
    }

    private func commit(to index: Int, animated: Bool) {
        let oldIndex = selectedIndex
        let restoreFocus = contentHosts.indices.contains(oldIndex) && ownsFirstResponder(in: contentHosts[oldIndex])
        selectedIndex = index
        synchronizeSelectionBinding()
        updateAccessibilityValue()
        updateButtonState()
        animateSelection(from: oldIndex, to: index, animated: animated)
        if restoreFocus, isEnabled { window?.makeFirstResponder(self) }
        onSelectionChanged?(index)
    }

    private func animateSelection(from oldIndex: Int, to newIndex: Int, animated: Bool) {
        // Settle any interrupted transition before starting another. An older outgoing page
        // must not remain visible when its completion is superseded by a later selection.
        showCurrent()
        guard contentHosts.indices.contains(oldIndex),
              contentHosts.indices.contains(newIndex) else { return }
        let oldHost = contentHosts[oldIndex]
        let newHost = contentHosts[newIndex]
        oldHost.wantsLayer = true
        newHost.wantsLayer = true
        guard let oldLayer = oldHost.layer, let newLayer = newHost.layer else { return }
        animationGeneration &+= 1
        let generation = animationGeneration
        let distance = max(contentContainer.bounds.width, 1)
        let logicalDirection: CGFloat = newIndex > oldIndex ? 1 : -1
        let direction = userInterfaceLayoutDirection == .rightToLeft ? -logicalDirection : logicalDirection
        let newStart = CATransform3DMakeTranslation(direction * distance, 0, 0)
        let oldEnd = CATransform3DMakeTranslation(-direction * distance, 0, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        oldLayer.transform = CATransform3DIdentity
        newLayer.transform = newStart
        oldHost.isHidden = false
        newHost.isHidden = false
        oldHost.frame = contentContainer.bounds
        newHost.frame = contentContainer.bounds
        CATransaction.commit()

        guard animated, !context.reduceMotion, distance > 0 else {
            oldHost.isHidden = true
            newLayer.transform = CATransform3DIdentity
            return
        }

        isTransitioning = true
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: oldLayer,
                    key: "fluent.flipView.old",
                    keyPath: "transform",
                    fromValue: NSValue(caTransform3D: CATransform3DIdentity),
                    toValue: NSValue(caTransform3D: oldEnd)
                ) {
                    oldLayer.transform = oldEnd
                },
                FluentLayerAnimationChange(
                    layer: newLayer,
                    key: "fluent.flipView.new",
                    keyPath: "transform",
                    fromValue: NSValue(caTransform3D: newStart),
                    toValue: NSValue(caTransform3D: CATransform3DIdentity)
                ) {
                    newLayer.transform = CATransform3DIdentity
                }
            ],
            motion: Self.transition,
            animated: true,
            completion: { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                self.showCurrent()
            }
        )
    }

    private func showCurrent() {
        isTransitioning = false
        animationGeneration &+= 1
        animationCoordinator.cancelAll(on: contentHosts.compactMap(\.layer))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (index, host) in contentHosts.enumerated() {
            host.isHidden = index != selectedIndex
            host.layer?.removeAllAnimations()
            host.layer?.transform = CATransform3DIdentity
        }
        if selectedIndex >= 0, contentHosts.indices.contains(selectedIndex) {
            contentHosts[selectedIndex].frame = contentContainer.bounds
        }
        updateButtonState()
    }

    private func rebuildContentHosts() {
        animationGeneration &+= 1
        animationCoordinator.cancelAll(on: contentHosts.compactMap(\.layer))
        contentHosts.forEach {
            $0.layer?.removeAllAnimations()
            $0.removeFromSuperview()
        }
        contentHosts = records.map { record in
            let host = record.make()
            host.frame = contentContainer.bounds
            host.autoresizingMask = [.width, .height]
            contentContainer.addSubview(host)
            return host
        }
        showCurrent()
        updateAccessibilityChildren()
    }

    private func updateButtonState() {
        previousButton.isEnabled = isEnabled && selectedIndex > 0
        nextButton.isEnabled = isEnabled && selectedIndex >= 0 && selectedIndex < records.count - 1
        previousButton.isHidden = !showsNavigationButtons || !previousButton.isEnabled
        nextButton.isHidden = !showsNavigationButtons || !nextButton.isEnabled
        if hoveredNavigationButton?.isHidden == true { hoveredNavigationButton = nil }
        updateAccessibilityChildren()
    }

    private func updateAccessibilityValue() {
        guard selectedIndex >= 0, selectedIndex < records.count else {
            fluentSetDefaultAccessibilityValue("0 items")
            return
        }
        setAccessibilityValue("\(selectedIndex + 1) of \(records.count)")
    }

    private func updateAccessibilityChildren() {
        let current: [NSView] = contentHosts.indices.contains(selectedIndex) ? [contentHosts[selectedIndex]] : []
        setAccessibilityChildren(current + [previousButton, nextButton].filter { !$0.isHidden })
    }

    // MARK: - Binding

    private func installSelectionObserver() {
        removeSelectionObserver()
        guard let selectionBinding else { return }
        let generation = selectionObservationGeneration
        selectionObserverID = selectionBinding.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectionObservationGeneration == generation,
                      !self.isWritingBinding, let binding = self.selectionBinding else { return }
                // Multiple writes in one turn resolve to the current model value.
                let target = self.clamped(binding.get())
                if target != self.selectedIndex {
                    self.commit(to: target, animated: true)
                } else {
                    self.synchronizeSelectionBinding()
                }
            }
        }
    }

    private func removeSelectionObserver() {
        selectionObservationGeneration &+= 1
        if let selectionObserverID {
            selectionBinding?.removeObserver(selectionObserverID)
        }
        selectionObserverID = nil
    }
}

private final class FluentFlipViewButton: NSButton {
    var onClick: (() -> Void)?
    var onPointerPresenceChanged: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKeyView: Bool { false }
    var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            updateAppearance()
        }
    }

    private var isPointerOver = false
    private var isPressed = false
    init(symbolName: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        setAccessibilityLabel(accessibilityLabel)
        target = self
        action = #selector(invoke)
        updateSymbol(symbolName)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            updateAppearance()
        }
    }

    func updateSymbol(_ symbolName: String) {
        guard let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel()
        ) else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
        image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image?.isTemplate = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        onPointerPresenceChanged?(true)
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        onPointerPresenceChanged?(false)
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        onPointerPresenceChanged?(true)
        isPressed = true
        updateAppearance()
        // NSButton consumes mouse-up inside its tracking loop, so clean up after it returns.
        defer { isPressed = false; updateAppearance() }
        super.mouseDown(with: event)
    }

    @objc private func invoke() {
        guard isEnabled else { return }
        onClick?()
    }

    private func updateAppearance() {
        let background: NSColor
        if !isEnabled {
            background = theme.controlFillDisabled
        } else if isPressed {
            background = theme.controlFillTertiary
        } else if isPointerOver {
            background = theme.controlFillSecondary
        } else {
            background = theme.controlFill
        }
        layer?.backgroundColor = background.cgColor
        contentTintColor = isEnabled ? theme.textPrimary : theme.textDisabled
        needsDisplay = true
    }
}
