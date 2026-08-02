import AppKit

/// A compact, keyboard-accessible segmented selector backed by NSSegmentedControl.
public struct FluentSegmentedControlView: FluentUpdatablePrimitiveView {
    fileprivate let labels: [String]
    fileprivate let selection: FluentBinding<Int>?
    fileprivate let selectedIndex: Int
    fileprivate let style: (any FluentSegmentedStyle)?

    public init(labels: [String], selection: FluentBinding<Int>? = nil, selectedIndex: Int = 0, style: (any FluentSegmentedStyle)? = nil) {
        self.labels = labels
        self.selection = selection
        self.selectedIndex = selectedIndex
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let control = FluentSegmentedControlNative(labels: labels, selectedIndex: selection?.get() ?? selectedIndex)
        control.theme = context.theme
        control.reduceMotion = context.reduceMotion
        control.fluentLayoutDirection = context.layoutDirection
        control.fluentStyle = style ?? FluentAutomaticSegmentedStyle()
        control.binding = selection
        control.syncSelection()
        return control
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentSegmentedControlNative else { return false }
        control.theme = context.theme
        control.reduceMotion = context.reduceMotion
        control.fluentLayoutDirection = context.layoutDirection
        control.fluentStyle = style ?? FluentAutomaticSegmentedStyle()
        control.update(labels: labels, binding: selection, selectedIndex: selectedIndex)
        return true
    }

    public func segmentedStyle(_ style: any FluentSegmentedStyle) -> FluentSegmentedControlView {
        FluentSegmentedControlView(labels: labels, selection: selection, selectedIndex: selectedIndex, style: style)
    }
}

private final class FluentSegmentedLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class FluentSegmentedBorderOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class FluentSegmentedControlNative: NSSegmentedControl, FluentControlSizeConfigurable {
    public var theme: FluentTheme = .current { didSet { applyTheme() } }
    public var fluentStyle: any FluentSegmentedStyle = FluentAutomaticSegmentedStyle() { didSet { applyTheme() } }
    public var fluentControlSize: FluentControlSize = .regular { didSet { applyTheme() } }
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            if reduceMotion { snapSelectionIndicatorToModelGeometry() }
        }
    }
    var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            cancelInteraction()
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            lastLayoutDirection = nil
            needsLayout = true
        }
    }
    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { cancelInteraction() }
            setAccessibilityEnabled(isEnabled)
            applyTheme()
        }
    }
    var binding: FluentBinding<Int>? {
        didSet { installObserver() }
    }
    private var observedBinding: FluentBinding<Int>?
    private var observerID: UUID?
    private var isApplyingBinding = false
    private var segmentTitles: [String]
    private var segmentLabels: [FluentSegmentedLabel] = []
    private let selectionIndicatorView = NSView()
    private let borderOverlayView = FluentSegmentedBorderOverlayView()
    private let outerBorderLayer = CAShapeLayer()
    private let focusBorderLayer = CAShapeLayer()
    private var lastRenderedSelection = -1
    private var hoveredSegment = -1
    private var pressedSegment = -1
    private var lastLayoutSize = NSSize(width: -1, height: -1)
    private var lastLayoutDirection: NSUserInterfaceLayoutDirection?

    private var isRTL: Bool { userInterfaceLayoutDirection == .rightToLeft }

    init(labels: [String], selectedIndex: Int) {
        segmentTitles = labels
        super.init(frame: .zero)
        segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            setLabel(label, forSegment: index)
            setWidth(0, forSegment: index)
        }
        selectedSegment = labels.isEmpty ? -1 : min(max(selectedIndex, 0), labels.count - 1)
        segmentStyle = .rounded
        trackingMode = .selectOne
        target = self
        action = #selector(selectionChanged)
        focusRingType = .none
        wantsLayer = true
        selectionIndicatorView.identifier = NSUserInterfaceItemIdentifier("FluentKit.Segmented.SelectionIndicator")
        selectionIndicatorView.wantsLayer = true
        selectionIndicatorView.layer?.name = "FluentKit.Segmented.SelectionIndicator"
        selectionIndicatorView.layer?.opacity = 0
        selectionIndicatorView.layer?.masksToBounds = true
        selectionIndicatorView.layer?.cornerCurve = .continuous
        addSubview(selectionIndicatorView)
        borderOverlayView.identifier = NSUserInterfaceItemIdentifier("FluentKit.Segmented.BorderOverlay")
        borderOverlayView.wantsLayer = true
        borderOverlayView.layer?.masksToBounds = false
        addSubview(borderOverlayView, positioned: .above, relativeTo: selectionIndicatorView)
        outerBorderLayer.name = "FluentKit.Segmented.OuterBorder"
        outerBorderLayer.fillRule = .evenOdd
        focusBorderLayer.name = "FluentKit.Segmented.FocusBorder"
        focusBorderLayer.fillRule = .evenOdd
        focusBorderLayer.zPosition = 1
        borderOverlayView.layer?.addSublayer(outerBorderLayer)
        borderOverlayView.layer?.addSublayer(focusBorderLayer)
        synchronizeLabelViews()
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        setAccessibilityRole(.radioGroup)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observerID { observedBinding?.removeObserver?(observerID) }
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        let appearance = resolvedAppearance()
        let widestTitle = segmentTitles.reduce(CGFloat(0)) { width, title in
            max(width, (title as NSString).size(withAttributes: [.font: appearance.font]).width)
        }
        let segmentWidth = max(ceil(widestTitle + 24 * theme.density.metricScale), 44)
        return NSSize(
            width: segmentWidth * CGFloat(max(segmentTitles.count, 1)),
            height: theme.controlHeight(for: fluentControlSize)
        )
    }

    override func layout() {
        super.layout()
        let direction = userInterfaceLayoutDirection
        guard bounds.size != lastLayoutSize || direction != lastLayoutDirection else { return }
        lastLayoutSize = bounds.size
        lastLayoutDirection = direction
        borderOverlayView.frame = bounds

        let width = segmentLabels.isEmpty ? 0 : bounds.width / CGFloat(segmentLabels.count)
        let font = resolvedAppearance().font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        for (index, label) in segmentLabels.enumerated() {
            let slot = visualSlot(for: index)
            label.frame = NSRect(
                x: CGFloat(slot) * width,
                y: floor(bounds.midY - lineHeight / 2),
                width: width,
                height: lineHeight
            )
        }
        snapSelectionIndicatorToModelGeometry()
        updateBorderOverlays()
    }

    override func draw(_ dirtyRect: NSRect) {
        // NSSegmentedControl remains the input and accessibility surface; FluentKit owns all pixels.
        let appearance = resolvedAppearance()
        let rect = bounds.insetBy(dx: appearance.borderWidth / 2, dy: appearance.borderWidth / 2)
        appearance.backgroundColor.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: appearance.cornerRadius,
            yRadius: appearance.cornerRadius
        ).fill()

        let interactiveSegment = activePressedSegment >= 0 ? activePressedSegment : hoveredSegment
        if interactiveSegment >= 0, interactiveSegment != selectedSegment,
           let hoverRect = rectForSegment(interactiveSegment, inset: 2) {
            (activePressedSegment >= 0 ? appearance.pressedColor : appearance.hoverColor).setFill()
            NSBezierPath(
                roundedRect: hoverRect,
                xRadius: max(appearance.cornerRadius - 2, 0),
                yRadius: max(appearance.cornerRadius - 2, 0)
            ).fill()
        }

    }

    override func mouseMoved(with event: NSEvent) {
        let next = segmentIndex(at: convert(event.locationInWindow, from: nil))
        if next != hoveredSegment {
            hoveredSegment = next
            refreshInteractionAppearance()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hoveredSegment = segmentIndex(at: convert(event.locationInWindow, from: nil))
        refreshInteractionAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hoveredSegment = -1
        refreshInteractionAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        let index = segmentIndex(at: convert(event.locationInWindow, from: nil))
        guard segmentTitles.indices.contains(index) else { return }
        window?.makeFirstResponder(self)
        hoveredSegment = index
        pressedSegment = index
        refreshInteractionAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedSegment >= 0 else { return }
        hoveredSegment = segmentIndex(at: convert(event.locationInWindow, from: nil))
        refreshInteractionAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedSegment >= 0 else { return }
        let releasedSegment = segmentIndex(at: convert(event.locationInWindow, from: nil))
        let committedSegment = releasedSegment == pressedSegment ? pressedSegment : -1
        pressedSegment = -1
        hoveredSegment = releasedSegment
        if committedSegment >= 0 {
            setSelection(committedSegment, animated: true, writeBinding: true)
        } else {
            refreshInteractionAppearance()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, !segmentTitles.isEmpty else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        needsDisplay = true
        let current = selectedSegment >= 0 ? selectedSegment : 0
        let next: Int?
        switch event.keyCode {
        case 123:
            next = isRTL
                ? min(current + 1, segmentTitles.count - 1)
                : max(current - 1, 0)
        case 124:
            next = isRTL
                ? max(current - 1, 0)
                : min(current + 1, segmentTitles.count - 1)
        case 115: next = 0
        case 119: next = segmentTitles.count - 1
        case 36, 49: next = current
        case 53:
            cancelInteraction()
            return
        default: next = nil
        }
        guard let next else {
            super.keyDown(with: event)
            return
        }
        setSelection(next, animated: true, writeBinding: true)
    }

    override func cancelOperation(_ sender: Any?) { cancelInteraction() }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        updateBorderOverlays()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { needsDisplay = true }
        updateBorderOverlays()
        return resigned
    }

    func update(labels: [String], binding: FluentBinding<Int>?, selectedIndex: Int) {
        let countChanged = segmentTitles.count != labels.count
        segmentTitles = labels
        if countChanged {
            segmentCount = labels.count
        }
        for (index, label) in labels.enumerated() { setLabel(label, forSegment: index) }
        synchronizeLabelViews()
        self.binding = binding
        let requested = binding?.get() ?? selectedIndex
        let nextSelection = labels.isEmpty ? -1 : min(max(requested, 0), labels.count - 1)
        if selectedSegment != nextSelection {
            cancelInteraction(refresh: false)
            selectedSegment = nextSelection
            syncSelection(animated: !countChanged)
        } else {
            refreshInteractionAppearance()
        }
    }

    func syncSelection(animated: Bool = false) {
        if selectedSegment >= 0 { setAccessibilityValue(selectedSegment) }
        updateLabels()
        if bounds.size == lastLayoutSize, lastLayoutDirection == userInterfaceLayoutDirection {
            updateSelectionIndicator(animated: animated)
        } else {
            needsLayout = true
        }
        needsDisplay = true
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observedBinding = binding
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isApplyingBinding else { return }
                let index = self.segmentCount == 0 ? -1 : min(max(value, 0), self.segmentCount - 1)
                guard self.selectedSegment != index else { return }
                self.cancelInteraction(refresh: false)
                self.selectedSegment = index
                self.syncSelection(animated: true)
            }
        }
    }

    @objc private func selectionChanged() {
        guard selectedSegment >= 0 else { return }
        syncSelection(animated: lastRenderedSelection != selectedSegment)
        guard let binding, !isApplyingBinding else { return }
        isApplyingBinding = true
        binding.set(selectedSegment)
        isApplyingBinding = false
    }

    private func setSelection(_ index: Int, animated: Bool, writeBinding: Bool) {
        guard segmentTitles.indices.contains(index) else { return }
        let changed = selectedSegment != index
        selectedSegment = index
        syncSelection(animated: animated && changed)
        guard writeBinding, let binding, !isApplyingBinding else { return }
        isApplyingBinding = true
        binding.set(index)
        isApplyingBinding = false
    }

    private func synchronizeLabelViews() {
        if segmentLabels.count != segmentTitles.count {
            segmentLabels.forEach { $0.removeFromSuperview() }
            segmentLabels = segmentTitles.enumerated().map { index, title in
                let label = FluentSegmentedLabel(labelWithString: title)
                label.identifier = NSUserInterfaceItemIdentifier("FluentKit.Segmented.Label.\(index)")
                label.alignment = .center
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
                label.drawsBackground = false
                label.isBordered = false
                label.setAccessibilityElement(false)
                addSubview(label, positioned: .below, relativeTo: borderOverlayView)
                return label
            }
            lastLayoutSize = NSSize(width: -1, height: -1)
            needsLayout = true
        } else {
            for (index, title) in segmentTitles.enumerated() {
                segmentLabels[index].stringValue = title
            }
        }
        updateLabels()
        invalidateIntrinsicContentSize()
    }

    private func updateLabels() {
        let appearance = resolvedAppearance()
        for (index, label) in segmentLabels.enumerated() {
            label.font = appearance.font
            if index == selectedSegment {
                label.textColor = activePressedSegment == index
                    ? appearance.selectedPressedForegroundColor
                    : (hoveredSegment == index
                        ? appearance.selectedHoverForegroundColor
                        : appearance.selectedForegroundColor)
            } else if activePressedSegment == index {
                label.textColor = appearance.pressedForegroundColor
            } else if hoveredSegment == index {
                label.textColor = appearance.hoverForegroundColor
            } else {
                label.textColor = appearance.foregroundColor
            }
        }
    }

    private func resolvedAppearance() -> FluentSegmentedAppearance {
        fluentStyle.appearance(
            for: FluentSegmentedStyleConfiguration(
                selectedIndex: selectedSegment,
                isEnabled: isEnabled,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    private func rectForSegment(_ index: Int, inset: CGFloat) -> NSRect? {
        guard segmentTitles.indices.contains(index), !segmentTitles.isEmpty else { return nil }
        let segmentWidth = bounds.width / CGFloat(segmentTitles.count)
        let slot = visualSlot(for: index)
        return NSRect(
            x: CGFloat(slot) * segmentWidth + inset,
            y: inset,
            width: max(segmentWidth - inset * 2, 0),
            height: max(bounds.height - inset * 2, 0)
        )
    }

    private func segmentIndex(at point: NSPoint) -> Int {
        guard bounds.contains(point), !segmentTitles.isEmpty, bounds.width > 0 else { return -1 }
        let slot = min(
            max(Int(point.x / (bounds.width / CGFloat(segmentTitles.count))), 0),
            segmentTitles.count - 1
        )
        return isRTL ? segmentTitles.count - 1 - slot : slot
    }

    private func updateSelectionIndicator(animated: Bool) {
        let appearance = resolvedAppearance()
        updateSelectionIndicatorAppearance(appearance)
        selectionIndicatorView.layer?.cornerRadius = max(appearance.cornerRadius - 2, 0)

        guard let target = rectForSegment(selectedSegment, inset: 2) else {
            selectionIndicatorView.layer?.removeAnimation(forKey: "fluent.segmented.selection")
            selectionIndicatorView.layer?.opacity = 0
            lastRenderedSelection = -1
            updateLabels()
            return
        }

        if !animated,
           lastRenderedSelection == selectedSegment,
           selectionIndicatorView.frame == target {
            updateLabels()
            return
        }

        let indicatorLayer = selectionIndicatorView.layer
        let presentationLayer = indicatorLayer?.presentation()
        let previousPosition = presentationLayer?.position ?? indicatorLayer?.position
        let previousBounds = presentationLayer?.bounds ?? indicatorLayer?.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionIndicatorView.frame = target
        selectionIndicatorView.layer?.opacity = 1
        CATransaction.commit()

        indicatorLayer?.removeAnimation(forKey: "fluent.segmented.selection")
        if animated, !reduceMotion, lastRenderedSelection >= 0,
           let indicatorLayer, let previousPosition, let previousBounds,
           previousBounds.width > 0,
           previousPosition != indicatorLayer.position || previousBounds != indicatorLayer.bounds {
            // CALayer.frame is derived from position, bounds, anchorPoint, and transform; it is
            // not itself an animatable property. Capture both presentation properties so rapid
            // selection and relayout cannot leave the highlight detached from its segment.
            let motion = FluentMotion.controlFast
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: previousPosition)
            position.toValue = NSValue(point: indicatorLayer.position)

            let bounds = CABasicAnimation(keyPath: "bounds")
            bounds.fromValue = NSValue(rect: previousBounds)
            bounds.toValue = NSValue(rect: indicatorLayer.bounds)

            let group = CAAnimationGroup()
            group.animations = [position, bounds]
            group.duration = motion.duration
            group.timingFunction = motion.curve.timingFunction
            group.isRemovedOnCompletion = true
            indicatorLayer.add(group, forKey: "fluent.segmented.selection")
        }

        lastRenderedSelection = selectedSegment
        updateLabels()
    }

    private var activePressedSegment: Int {
        hoveredSegment == pressedSegment ? pressedSegment : -1
    }

    private func visualSlot(for index: Int) -> Int {
        isRTL ? segmentTitles.count - 1 - index : index
    }

    private func updateSelectionIndicatorAppearance(_ appearance: FluentSegmentedAppearance? = nil) {
        let appearance = appearance ?? resolvedAppearance()
        let color: NSColor
        if activePressedSegment == selectedSegment {
            color = appearance.selectedPressedSegmentColor
        } else if hoveredSegment == selectedSegment {
            color = appearance.selectedHoverSegmentColor
        } else {
            color = appearance.selectedSegmentColor
        }
        selectionIndicatorView.layer?.backgroundColor = color.cgColor
    }

    private func refreshInteractionAppearance() {
        updateSelectionIndicatorAppearance()
        updateLabels()
        needsDisplay = true
    }

    private func updateBorderOverlays() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let appearance = resolvedAppearance()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        borderOverlayView.frame = bounds
        let overlayBounds = borderOverlayView.bounds
        let outer = overlayBounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outerBorderLayer.contentsScale = scale
        outerBorderLayer.frame = overlayBounds
        outerBorderLayer.path = insideRingPath(
            outer: outer,
            inner: outer.insetBy(dx: appearance.borderWidth, dy: appearance.borderWidth),
            outerRadius: appearance.cornerRadius,
            innerRadius: max(appearance.cornerRadius - appearance.borderWidth, 0)
        )
        outerBorderLayer.fillColor = appearance.borderColor.cgColor
        outerBorderLayer.strokeColor = nil
        outerBorderLayer.lineWidth = 0
        outerBorderLayer.isHidden = appearance.borderWidth <= 0

        let showsFocus = FluentFocusVisibility.isKeyboardFocusVisible(for: self)
        let focusOuter = outer.insetBy(dx: 2, dy: 2)
        let focusInner = focusOuter.insetBy(dx: theme.focusStrokeWidth, dy: theme.focusStrokeWidth)
        focusBorderLayer.contentsScale = scale
        focusBorderLayer.frame = overlayBounds
        focusBorderLayer.path = insideRingPath(
            outer: focusOuter,
            inner: focusInner,
            outerRadius: max(appearance.cornerRadius - 2, 0),
            innerRadius: max(appearance.cornerRadius - 2 - theme.focusStrokeWidth, 0)
        )
        focusBorderLayer.fillColor = theme.accent.cgColor
        focusBorderLayer.isHidden = !showsFocus
        CATransaction.commit()
    }

    private func insideRingPath(
        outer: CGRect,
        inner: CGRect,
        outerRadius: CGFloat,
        innerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: outer, cornerWidth: outerRadius, cornerHeight: outerRadius)
        if inner.width > 0, inner.height > 0 {
            path.addRoundedRect(in: inner, cornerWidth: innerRadius, cornerHeight: innerRadius)
        }
        return path
    }

    private func cancelInteraction(refresh: Bool = true) {
        guard pressedSegment >= 0 || hoveredSegment >= 0 else { return }
        pressedSegment = -1
        hoveredSegment = -1
        if refresh { refreshInteractionAppearance() }
    }

    private func snapSelectionIndicatorToModelGeometry() {
        selectionIndicatorView.layer?.removeAnimation(forKey: "fluent.segmented.selection")
        updateSelectionIndicator(animated: false)
    }

    private func applyTheme() {
        let appearance = resolvedAppearance()
        layer?.backgroundColor = NSColor.clear.cgColor
        controlSize = fluentControlSize.appKitSize
        font = appearance.font
        if segmentStyle != appearance.segmentStyle { segmentStyle = appearance.segmentStyle }
        setAccessibilityLabel("Segmented control")
        updateLabels()
        updateSelectionIndicatorAppearance(appearance)
        selectionIndicatorView.layer?.cornerRadius = max(appearance.cornerRadius - 2, 0)
        updateBorderOverlays()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
}

public func FluentSegmentedControl(
    _ labels: [String],
    selection: FluentBinding<Int>? = nil,
    selectedIndex: Int = 0,
    style: (any FluentSegmentedStyle)? = nil
) -> FluentSegmentedControlView {
    FluentSegmentedControlView(labels: labels, selection: selection, selectedIndex: selectedIndex, style: style)
}
