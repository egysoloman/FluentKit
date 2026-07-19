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
        control.fluentStyle = style ?? FluentAutomaticSegmentedStyle()
        control.binding = selection
        control.syncSelection()
        return control
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentSegmentedControlNative else { return false }
        control.theme = context.theme
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

private final class FluentSegmentedControlNative: NSSegmentedControl, FluentControlSizeConfigurable {
    public var theme: FluentTheme = .current { didSet { applyTheme() } }
    public var fluentStyle: any FluentSegmentedStyle = FluentAutomaticSegmentedStyle() { didSet { applyTheme() } }
    public var fluentControlSize: FluentControlSize = .regular { didSet { applyTheme() } }
    public override var isEnabled: Bool { didSet { applyTheme() } }
    var binding: FluentBinding<Int>? {
        didSet { installObserver() }
    }
    private var observedBinding: FluentBinding<Int>?
    private var observerID: UUID?
    private var isApplyingBinding = false
    private var segmentTitles: [String]
    private var segmentLabels: [FluentSegmentedLabel] = []
    private let selectionIndicatorView = NSView()
    private var lastRenderedSelection = -1
    private var hoveredSegment = -1

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
        selectionIndicatorView.layer?.opacity = 0
        addSubview(selectionIndicatorView)
        rebuildLabels()
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
        guard !segmentLabels.isEmpty else { return }
        let width = bounds.width / CGFloat(segmentLabels.count)
        for (index, label) in segmentLabels.enumerated() {
            label.frame = NSRect(
                x: CGFloat(index) * width,
                y: 0,
                width: width,
                height: bounds.height
            )
        }
        updateSelectionIndicator(animated: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        let rect = bounds.insetBy(dx: appearance.borderWidth / 2, dy: appearance.borderWidth / 2)
        appearance.backgroundColor.setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: appearance.cornerRadius,
            yRadius: appearance.cornerRadius
        ).fill()

        if hoveredSegment >= 0, hoveredSegment != selectedSegment,
           let hoverRect = rectForSegment(hoveredSegment, inset: 2) {
            appearance.hoverColor.setFill()
            NSBezierPath(
                roundedRect: hoverRect,
                xRadius: max(appearance.cornerRadius - 2, 0),
                yRadius: max(appearance.cornerRadius - 2, 0)
            ).fill()
        }

        appearance.borderColor.setStroke()
        let border = NSBezierPath(
            roundedRect: rect,
            xRadius: appearance.cornerRadius,
            yRadius: appearance.cornerRadius
        )
        border.lineWidth = appearance.borderWidth
        border.stroke()

        if window?.firstResponder === self {
            theme.accent.setStroke()
            let focus = NSBezierPath(
                roundedRect: rect.insetBy(dx: 2, dy: 2),
                xRadius: max(appearance.cornerRadius - 2, 0),
                yRadius: max(appearance.cornerRadius - 2, 0)
            )
            focus.lineWidth = theme.focusStrokeWidth
            focus.stroke()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let next = segmentIndex(at: convert(event.locationInWindow, from: nil))
        if next != hoveredSegment {
            hoveredSegment = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredSegment = -1
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let index = segmentIndex(at: convert(event.locationInWindow, from: nil))
        guard segmentTitles.indices.contains(index) else { return }
        setSelection(index, animated: true, writeBinding: true)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, !segmentTitles.isEmpty else { return }
        let current = selectedSegment >= 0 ? selectedSegment : 0
        let next: Int?
        switch event.keyCode {
        case 123: next = max(current - 1, 0)
        case 124: next = min(current + 1, segmentTitles.count - 1)
        case 115: next = 0
        case 119: next = segmentTitles.count - 1
        case 36, 49: next = current
        default: next = nil
        }
        guard let next else {
            super.keyDown(with: event)
            return
        }
        setSelection(next, animated: true, writeBinding: true)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { needsDisplay = true }
        return resigned
    }

    func update(labels: [String], binding: FluentBinding<Int>?, selectedIndex: Int) {
        let oldSelection = selectedSegment
        segmentTitles = labels
        if segmentCount != labels.count {
            segmentCount = labels.count
        }
        for (index, label) in labels.enumerated() { setLabel(label, forSegment: index) }
        rebuildLabels()
        self.binding = binding
        let requested = binding?.get() ?? selectedIndex
        selectedSegment = labels.isEmpty ? -1 : min(max(requested, 0), labels.count - 1)
        syncSelection(animated: oldSelection != selectedSegment)
    }

    func syncSelection(animated: Bool = false) {
        if selectedSegment >= 0 { setAccessibilityValue(selectedSegment) }
        updateLabels()
        updateSelectionIndicator(animated: animated)
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

    private func rebuildLabels() {
        segmentLabels.forEach { $0.removeFromSuperview() }
        segmentLabels = segmentTitles.map { title in
            let label = FluentSegmentedLabel(labelWithString: title)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.drawsBackground = false
            label.isBordered = false
            addSubview(label)
            return label
        }
        updateLabels()
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    private func updateLabels() {
        let appearance = resolvedAppearance()
        for (index, label) in segmentLabels.enumerated() {
            label.font = appearance.font
            label.textColor = index == selectedSegment
                ? appearance.selectedForegroundColor
                : appearance.foregroundColor
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
        return NSRect(
            x: CGFloat(index) * segmentWidth + inset,
            y: inset,
            width: max(segmentWidth - inset * 2, 0),
            height: max(bounds.height - inset * 2, 0)
        )
    }

    private func segmentIndex(at point: NSPoint) -> Int {
        guard bounds.contains(point), !segmentTitles.isEmpty, bounds.width > 0 else { return -1 }
        let index = Int(point.x / (bounds.width / CGFloat(segmentTitles.count)))
        return min(max(index, 0), segmentTitles.count - 1)
    }

    private func updateSelectionIndicator(animated: Bool) {
        let appearance = resolvedAppearance()
        selectionIndicatorView.layer?.backgroundColor = appearance.selectedSegmentColor.cgColor
        selectionIndicatorView.layer?.cornerRadius = max(appearance.cornerRadius - 2, 0)

        guard let target = rectForSegment(selectedSegment, inset: 2) else {
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

        let previous = selectionIndicatorView.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionIndicatorView.frame = target
        selectionIndicatorView.layer?.opacity = 1
        selectionIndicatorView.layer?.setAffineTransform(.identity)
        CATransaction.commit()

        if animated, lastRenderedSelection >= 0, previous.width > 0, previous != target,
           let indicatorLayer = selectionIndicatorView.layer {
            let motion = FluentMotion.controlNormal
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: NSPoint(x: previous.midX, y: previous.midY))
            position.toValue = NSValue(point: NSPoint(x: target.midX, y: target.midY))
            position.timingFunction = motion.curve.timingFunction

            let bounds = CABasicAnimation(keyPath: "bounds.size")
            bounds.fromValue = NSValue(size: previous.size)
            bounds.toValue = NSValue(size: target.size)
            bounds.timingFunction = motion.curve.timingFunction

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 0.94, 1]
            scale.keyTimes = [NSNumber(value: 0), NSNumber(value: 0.45), NSNumber(value: 1)]
            scale.timingFunctions = [motion.curve.timingFunction, motion.curve.timingFunction]

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [1, 0.78, 1]
            opacity.keyTimes = scale.keyTimes
            opacity.timingFunctions = scale.timingFunctions

            let group = CAAnimationGroup()
            group.animations = [position, bounds, scale, opacity]
            group.duration = motion.duration
            group.isRemovedOnCompletion = true
            indicatorLayer.add(group, forKey: "fluent.segmented.selection")
        }

        lastRenderedSelection = selectedSegment
        updateLabels()
    }

    private func applyTheme() {
        let appearance = resolvedAppearance()
        layer?.backgroundColor = NSColor.clear.cgColor
        controlSize = fluentControlSize.appKitSize
        font = appearance.font
        segmentStyle = appearance.segmentStyle
        setAccessibilityLabel("Segmented control")
        updateLabels()
        updateSelectionIndicator(animated: false)
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
