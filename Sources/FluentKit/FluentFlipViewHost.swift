import AppKit

final class FluentFlipViewHost: NSControl {
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
    private var source: FluentFlipViewSource
    private var pages: [AnyHashable: FluentViewHost<FluentAnyView>] = [:]
    private var orientation: NSUserInterfaceLayoutOrientation
    private var updateGeneration: UInt64 = 0
    private var lastLayoutSize = NSSize.zero
    private var panDriver: FluentPanGestureDriver?
    private(set) var isPanning = false
    private(set) var panOffset: CGFloat = 0
    private static let settleKey = "fluent.flipView.settle"
    private var selectionBinding: FluentBinding<Int>?
    private var selectionObserverID: UUID?
    private var selectionObservationGeneration: UInt64 = 0
    private var onSelectionChanged: ((Int) -> Void)?
    private var context: FluentRenderContext
    private var selectedIndex = 0
    private var isWritingBinding = false
    private var animationGeneration = 0
    private var isTransitioning = false
    private var transitionOutgoingID: AnyHashable?
    private let animationCoordinator = FluentAnimationCoordinator()

    init(
        source: FluentFlipViewSource,
        selection: FluentBinding<Int>?,
        orientation: NSUserInterfaceLayoutOrientation,
        onSelectionChanged: ((Int) -> Void)?,
        context: FluentRenderContext
    ) {
        self.source = source
        self.orientation = orientation
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
        selectedIndex = clamped(readBinding() ?? 0)
        selectedIndex = acceptedSelection(selectedIndex)
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        showCurrent()
        installPanDriver()
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
                cancelInteraction()
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
        if window == nil { cancelInteraction(); hideNavigationButtons() }
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

    /// `FlipView::OnPointerMoved`: only mouse and pen pointers reveal the navigation buttons.
    override func mouseEntered(with event: NSEvent) { revealForPointer(isTouch: false) }
    override func mouseMoved(with event: NSEvent) { revealForPointer(isTouch: FluentInputDeviceTracker.isTouch(event)) }

    /// Enter/exit events carry no subtype, so they rely on the window's last device alone.
    private func revealForPointer(isTouch: Bool) {
        guard !isTouch, FluentInputDeviceTracker.shared.lastDeviceType(in: window) != .touch else { return }
        revealNavigationButtons()
    }

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
            if isPanning { cancelInteraction() }
            super.scrollWheel(with: event)
            return
        }
        if !event.phase.isEmpty || !event.momentumPhase.isEmpty {
            if panDriver?.handleScrollWheel(event) != true { super.scrollWheel(with: event) }
            return
        }
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        var delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        if horizontal, orientation == .horizontal, userInterfaceLayoutDirection == .rightToLeft { delta = -delta }
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

    override var isHidden: Bool {
        didSet { if isHidden { cancelInteraction(); hideNavigationButtons() } }
    }
    override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        didSet { if oldValue != userInterfaceLayoutDirection { cancelInteraction(); needsLayout = true } }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, let hit = super.hitTest(point) else { return nil }
        if (isPanning || isTransitioning) && hit !== previousButton && hit !== nextButton { return self }
        return hit
    }
    override func layout() {
        super.layout()
        if bounds.size != lastLayoutSize { cancelInteraction(); lastLayoutSize = bounds.size }
        contentContainer.frame = bounds
        if !isPanning { for host in pages.values { host.frame = contentContainer.bounds } }
        let vertical = orientation == .vertical
        let buttonSize = NSSize(width: min(vertical ? Self.buttonHeight : Self.buttonWidth, max(0, bounds.width - 2)),
            height: min(vertical ? Self.buttonWidth : Self.buttonHeight, max(0, bounds.height - 2)))
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        if vertical {
            previousButton.frame = NSRect(x: bounds.midX - buttonSize.width / 2, y: bounds.maxY - min(1, bounds.height / 2) - buttonSize.height, width: buttonSize.width, height: buttonSize.height)
            nextButton.frame = NSRect(x: bounds.midX - buttonSize.width / 2, y: bounds.minY + min(1, bounds.height / 2), width: buttonSize.width, height: buttonSize.height)
        } else {
            let margin = min(1, max(0, bounds.width / 2))
            let leading = bounds.minX + margin, trailing = bounds.maxX - margin - buttonSize.width
            previousButton.frame = NSRect(x: isRTL ? trailing : leading, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
            nextButton.frame = NSRect(x: isRTL ? leading : trailing, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
        }
        let inset = min(2, max(0, min(bounds.width, bounds.height) / 2))
        focusLayer.frame = bounds
        focusLayer.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: 2, cornerHeight: 2, transform: nil)
        updateFocusVisual()
        previousButton.updateSymbol(vertical ? "chevron.up" : isRTL ? "chevron.right" : "chevron.left")
        nextButton.updateSymbol(vertical ? "chevron.down" : isRTL ? "chevron.left" : "chevron.right")
        if isPanning { applyPanVisuals() }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        updateFocusVisual()
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        let leftKey: UInt16 = orientation == .vertical ? 126 : isRTL ? 124 : 123
        let rightKey: UInt16 = orientation == .vertical ? 125 : isRTL ? 123 : 124
        if [leftKey, rightKey, 115, 119].contains(event.keyCode) { revealNavigationButtons() }
        switch event.keyCode {
        case leftKey:
            select(mapSelectionOffset(-1), animated: true)
        case rightKey:
            select(mapSelectionOffset(1), animated: true)
        case 115:
            select(0, animated: true)
        case 119:
            select(source.count - 1, animated: true)
        default:
            super.keyDown(with: event)
        }
    }

    func update(source: FluentFlipViewSource, selection: FluentBinding<Int>?, orientation: NSUserInterfaceLayoutOrientation,
                onSelectionChanged: ((Int) -> Void)?, context: FluentRenderContext) {
        updateGeneration &+= 1
        let generation = updateGeneration
        let oldIndex = selectedIndex, oldID = selectedID
        let reused = selectionBinding?.observationIdentity != nil && selectionBinding?.observationIdentity == selection?.observationIdentity
        let bindingChanged = selectionBinding?.observationIdentity != selection?.observationIdentity
        if !reused { removeSelectionObserver() }
        let requested = FluentDependencyTracking.withoutTracking { selection?.get() }
        let target = (bindingChanged || requested.map { $0 != oldIndex } == true) ? requested ?? oldIndex
            : oldID.flatMap(source.index) ?? oldIndex
        let sameIdentityOrder = self.source.count == source.count && pages.keys.allSatisfy { self.source.index($0) == source.index($0) }
        let axisChanged = self.orientation != orientation
        if !sameIdentityOrder || axisChanged || (context.reduceMotion && !self.context.reduceMotion) { cancelInteraction() }
        self.source = source; self.orientation = orientation; selectionBinding = selection
        self.onSelectionChanged = onSelectionChanged; self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        previousButton.theme = context.theme; nextButton.theme = context.theme
        userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        if axisChanged { installPanDriver() }
        let accepted = acceptedSelection(clamped(target))
        guard generation == updateGeneration else { return }
        selectedIndex = accepted
        if selectedIndex != oldIndex || selectedID != oldID { cancelInteraction() }
        reconcilePages(refresh: true)
        guard generation == updateGeneration else { return }
        if !isTransitioning && !isPanning { showCurrent() }
        if isPanning { applyPanVisuals() }
        if !reused { installSelectionObserver() }
        updateAccessibilityValue(); updateButtonState(); needsLayout = true
        if selectedIndex != oldIndex || selectedID != oldID { self.onSelectionChanged?(selectedIndex) }
    }

    deinit {
        navigationTimer?.invalidate(); panDriver?.detach()
        removeSelectionObserver()
    }

    // MARK: - Selection

    private func mapSelectionOffset(_ offset: Int) -> Int {
        if source.count <= 1 { return selectedIndex }
        if selectedIndex + offset < 0 { return 0 }
        if selectedIndex + offset >= source.count { return source.count - 1 }
        return selectedIndex + offset
    }

    private func clamped(_ index: Int) -> Int {
        guard source.count > 0 else { return -1 }
        return min(max(index, 0), source.count - 1)
    }

    private func select(_ index: Int, animated: Bool) {
        guard isEnabled else { return }
        let target = clamped(index)
        guard target >= 0, target != selectedIndex else { return }
        commit(to: target, animated: animated)
    }

    private func readBinding() -> Int? { FluentDependencyTracking.withoutTracking { selectionBinding?.get() } }
    private func acceptedSelection(_ requested: Int) -> Int {
        let target = clamped(requested)
        guard let selectionBinding, !isWritingBinding else { return target }
        if readBinding() != target {
            let generation = updateGeneration
            isWritingBinding = true; selectionBinding.set(target); isWritingBinding = false
            // A setter may synchronously replace the data/binding. Its nested update could not
            // write while this transaction was active; make one bounded normalization attempt.
            if generation != updateGeneration, let current = self.selectionBinding, let raw = readBinding(), raw != clamped(raw) {
                isWritingBinding = true; current.set(clamped(raw)); isWritingBinding = false
            }
        }
        return clamped(readBinding() ?? target)
    }
    private func synchronizeSelectionBinding() { selectedIndex = acceptedSelection(selectedIndex) }
    private var selectedID: AnyHashable? { (0..<source.count).contains(selectedIndex) ? source.id(selectedIndex) : nil }
    private func page(at index: Int) -> NSView? { (0..<source.count).contains(index) ? pages[source.id(index)] : nil }

    private func commit(to index: Int, animated: Bool, interactiveOffset: CGFloat? = nil) {
        let oldIndex = selectedIndex
        let generation = updateGeneration
        let accepted = acceptedSelection(index)
        guard generation == updateGeneration else { return }
        guard accepted != oldIndex else { if isPanning { settlePanBack() }; return }
        let restoreFocus = page(at: oldIndex).map(ownsFirstResponder) ?? false
        cancelInteraction(resetDriver: interactiveOffset == nil)
        guard generation == updateGeneration else { return }
        selectedIndex = accepted
        updateAccessibilityValue(); updateButtonState()
        animateSelection(from: oldIndex, to: selectedIndex, animated: animated, initialOffset: interactiveOffset ?? 0)
        if restoreFocus, isEnabled { window?.makeFirstResponder(self) }
        guard generation == updateGeneration else { return }
        onSelectionChanged?(selectedIndex)
    }

    private func animateSelection(from oldIndex: Int, to newIndex: Int, animated: Bool, initialOffset: CGFloat = 0) {
        // Settle any interrupted transition before starting another. An older outgoing page
        // must not remain visible when its completion is superseded by a later selection.
        stopAnimations()
        reconcilePages(keeping: [oldIndex])
        guard let oldHost = page(at: oldIndex), let newHost = page(at: newIndex) else { showCurrent(); return }
        oldHost.wantsLayer = true
        newHost.wantsLayer = true
        guard let oldLayer = oldHost.layer, let newLayer = newHost.layer else { return }
        animationGeneration &+= 1
        let generation = animationGeneration
        let distance = max(pageExtent, 1)
        let logicalDirection: CGFloat = newIndex > oldIndex ? 1 : -1
        let newStart = translation(logicalDirection * distance + initialOffset)
        let oldStart = translation(initialOffset)
        let oldEnd = translation(-logicalDirection * distance)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        oldLayer.transform = oldStart
        newLayer.transform = newStart
        oldHost.isHidden = false
        newHost.isHidden = false
        oldHost.frame = contentContainer.bounds
        newHost.frame = contentContainer.bounds
        CATransaction.commit()

        guard animated, !context.reduceMotion, distance > 0 else {
            showCurrent()
            return
        }

        isTransitioning = true
        transitionOutgoingID = source.id(oldIndex)
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: oldLayer,
                    key: "fluent.flipView.old",
                    keyPath: "transform",
                    fromValue: NSValue(caTransform3D: oldStart),
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

    private func stopAnimations() {
        isTransitioning = false; transitionOutgoingID = nil; animationGeneration &+= 1
        animationCoordinator.cancelAll(on: pages.values.compactMap(\.layer))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for host in pages.values { host.layer?.removeAllAnimations(); host.layer?.transform = CATransform3DIdentity }
        CATransaction.commit()
    }
    private func showCurrent() {
        stopAnimations()
        let generation = updateGeneration
        reconcilePages()
        guard generation == updateGeneration else { return }
        for (id, host) in pages { host.isHidden = id != selectedID; host.frame = contentContainer.bounds }
        updateButtonState()
    }
    private func reconcilePages(keeping extra: Set<Int> = [], refresh: Bool = false) {
        let generation = updateGeneration
        var wanted = extra.filter { (0..<source.count).contains($0) }
        if isTransitioning, let transitionOutgoingID, let index = source.index(transitionOutgoingID) { wanted.insert(index) }
        if selectedIndex >= 0 && source.count > 0 {
            wanted.formUnion(max(0, selectedIndex - 1)...min(source.count - 1, selectedIndex + 1))
        }
        let ids = Set(wanted.map(source.id))
        for id in Array(pages.keys) where !ids.contains(id) {
            guard let host = pages.removeValue(forKey: id) else { continue }
            if ownsFirstResponder(in: host) { window?.makeFirstResponder(isEnabled ? self : nil) }
            host.removeFromSuperview()
            guard generation == updateGeneration else { return }
        }
        for index in wanted.sorted() {
            let id = source.id(index)
            if let host = pages[id] {
                if refresh { host.update(source.view(index), context: context) }
                guard generation == updateGeneration else { return }
            } else {
                let host = FluentViewHost(source.view(index), context: context)
                host.wantsLayer = true
                host.frame = contentContainer.bounds; host.autoresizingMask = [.width, .height]
                host.isHidden = id != selectedID
                pages[id] = host; contentContainer.addSubview(host)
            }
            if let host = pages[id] {
                host.identifier = NSUserInterfaceItemIdentifier("FluentKit.FlipView.Page.\(index)")
                fluentApplyInheritedDisabledState(to: host)
            }
        }
    }

    private func updateButtonState() {
        previousButton.isEnabled = isEnabled && selectedIndex > 0
        nextButton.isEnabled = isEnabled && selectedIndex >= 0 && selectedIndex < source.count - 1
        previousButton.isHidden = !showsNavigationButtons || !previousButton.isEnabled
        nextButton.isHidden = !showsNavigationButtons || !nextButton.isEnabled
        if hoveredNavigationButton?.isHidden == true { hoveredNavigationButton = nil }
        updateAccessibilityChildren()
    }

    private func updateAccessibilityValue() {
        guard selectedIndex >= 0, selectedIndex < source.count else {
            fluentSetDefaultAccessibilityValue("0 items")
            return
        }
        setAccessibilityValue("\(selectedIndex + 1) of \(source.count)")
    }

    private func updateAccessibilityChildren() {
        let current: [NSView] = page(at: selectedIndex).map { [$0] } ?? []
        setAccessibilityChildren(current + [previousButton, nextButton].filter { !$0.isHidden })
    }

    // MARK: - Single-page direct manipulation

    private var pageExtent: CGFloat { orientation == .vertical ? contentContainer.bounds.height : contentContainer.bounds.width }
    private func translation(_ value: CGFloat) -> CATransform3D {
        if orientation == .vertical { return CATransform3DMakeTranslation(0, -value, 0) }
        return CATransform3DMakeTranslation(userInterfaceLayoutDirection == .rightToLeft ? -value : value, 0, 0)
    }
    private func logicalOffset(_ transform: CATransform3D) -> CGFloat {
        orientation == .vertical ? -transform.m42 : userInterfaceLayoutDirection == .rightToLeft ? -transform.m41 : transform.m41
    }
    private func installPanDriver() {
        panDriver?.detach()
        let driver = FluentPanGestureDriver(view: self, axis: orientation == .vertical ? .vertical : .horizontal)
        driver.onBeginAllowed = { [weak self] in self?.canBeginInteractivePan ?? false }
        driver.onBegin = { [weak self] in self?.beginInteractivePan() }
        driver.onChange = { [weak self] in self?.updateInteractivePan(translation: $0) }
        driver.onEnd = { [weak self] in self?.endInteractivePan(velocity: $0) }
        driver.onCancel = { [weak self] in self?.settlePanBack() }
        panDriver = driver
    }
    var canBeginInteractivePan: Bool { isEnabled && !isHiddenOrHasHiddenAncestor && source.count > 1 && pageExtent > 0 }
    @discardableResult func beginInteractivePan() -> CGFloat? {
        guard canBeginInteractivePan else { return nil }
        animationCoordinator.cancelValueAnimation(key: Self.settleKey)
        if !isPanning {
            var offset: CGFloat = 0
            if isTransitioning, let layer = page(at: selectedIndex)?.layer,
               let outgoing = transitionOutgoingID.flatMap(source.index), abs(outgoing - selectedIndex) == 1 {
                if let transform = layer.presentation()?.transform { offset = logicalOffset(transform) }
                else if let key = layer.animationKeys()?.first(where: { $0.hasPrefix("fluent.flipView.new") }),
                        let from = (layer.animation(forKey: key) as? CABasicAnimation)?.fromValue as? NSValue {
                    offset = logicalOffset(from.caTransform3DValue)
                }
            }
            stopAnimations(); isPanning = true; panOffset = offset
            reconcilePages(); applyPanVisuals()
        }
        hideNavigationButtons()
        if panNeighbor == nil, abs(panOffset) < pageExtent {
            return panOffset / (0.55 * (1 - abs(panOffset) / pageExtent))
        }
        return panOffset
    }
    private var panNeighbor: Int? {
        guard panOffset != 0 else { return nil }
        let index = selectedIndex + (panOffset < 0 ? 1 : -1)
        return (0..<source.count).contains(index) ? index : nil
    }
    func updateInteractivePan(translation value: CGFloat) {
        guard isPanning, pageExtent > 0 else { return }
        panOffset = max(-pageExtent, min(pageExtent, value))
        if panNeighbor == nil && value != 0 {
            let magnitude = abs(value) * 0.55
            panOffset = (value < 0 ? -1 : 1) * pageExtent * magnitude / (pageExtent + magnitude)
        }
        applyPanVisuals()
    }
    func endInteractivePan(velocity: CGFloat) {
        guard isPanning else { return }
        // The platform Direct Manipulation engine owns WinUI inertia. Here a bounded local
        // projection chooses one adjacent page; it is not a claim of identical physics.
        let projected = panOffset + velocity * 0.2
        let sameSide = panOffset == 0 || (projected < 0) == (panOffset < 0)
        if sameSide && abs(projected) > pageExtent / 2,
           (0..<source.count).contains(selectedIndex + (projected < 0 ? 1 : -1)) {
            let target = selectedIndex + (projected < 0 ? 1 : -1)
            commit(to: target, animated: true, interactiveOffset: panOffset)
        } else { settlePanBack() }
    }
    private func applyPanVisuals() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (id, host) in pages {
            let index = source.index(id)
            host.isHidden = index != selectedIndex && index != panNeighbor
            // Frame displacement belongs to this pager. The declarative host owns its layer
            // transform and may reset that transform while refreshing or laying out content.
            let offset = index == selectedIndex ? panOffset : panOffset + (panOffset < 0 ? pageExtent : -pageExtent)
            if index == selectedIndex || index == panNeighbor {
                let position = translation(offset)
                host.layer?.transform = CATransform3DIdentity
                host.frame = contentContainer.bounds.offsetBy(dx: position.m41, dy: position.m42)
            }
        }
        CATransaction.commit()
    }
    private func settlePanBack() {
        let value: CGFloat = 0
        guard isPanning else { return }
        guard !context.reduceMotion && abs(panOffset - value) > 0.5 else {
            isPanning = false; panOffset = 0; showCurrent(); return
        }
        animationCoordinator.animateValue(key: Self.settleKey, from: panOffset, to: value,
            motion: Self.transition, animated: true, update: { [weak self] value in
                guard let self, self.isPanning else { return }; self.panOffset = value; self.applyPanVisuals()
            }, completion: { [weak self] in
                guard let self else { return }; self.isPanning = false; self.panOffset = 0; self.showCurrent()
            })
    }
    private func cancelInteraction(resetDriver: Bool = true) {
        if resetDriver { panDriver?.reset(notify: false) }
        animationCoordinator.cancelValueAnimation(key: Self.settleKey)
        isPanning = false; panOffset = 0
        showCurrent()
    }

    // MARK: - Binding

    private func installSelectionObserver() {
        removeSelectionObserver()
        guard let selectionBinding else { return }
        let generation = selectionObservationGeneration
        selectionObserverID = selectionBinding.observe { [weak self] _ in
            guard self?.isWritingBinding == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectionObservationGeneration == generation,
                      !self.isWritingBinding, let binding = self.selectionBinding else { return }
                // Multiple writes in one turn resolve to the current model value.
                let target = self.clamped(FluentDependencyTracking.withoutTracking { binding.get() })
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

