import AppKit

/// A WinUI-style horizontal paging control. Items occupy one viewport at a time and can be
/// navigated with the overlaid previous/next buttons or the Left/Right arrow keys.
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
                    host.context = updateContext
                    host.update(FluentAnyView(contentView))
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

private final class FluentFlipViewHost: NSView {
    private static let buttonWidth: CGFloat = 20
    private static let buttonHeight: CGFloat = 36
    private static let transition = FluentMotionToken(
        duration: 0.250,
        curve: .controlFastOutSlowIn
    )

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
    private var onSelectionChanged: ((Int) -> Void)?
    private var context: FluentRenderContext
    private var selectedIndex = 0
    private var isWritingBinding = false
    private var animationGeneration = 0
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
        setAccessibilityLabel("Flip view")

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
        }
        nextButton.onClick = { [weak self] in
            guard let self else { return }
            self.select(self.mapSelectionOffset(1), animated: true)
        }
        addSubview(previousButton)
        addSubview(nextButton)

        animationCoordinator.reduceMotion = context.reduceMotion
        rebuildContentHosts(animated: false)
        selectedIndex = clamped(selection?.get() ?? 0)
        showCurrent(animated: false)
        updateAccessibilityValue()
        updateButtonState()
        installSelectionObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: 180)
    }

    override func layout() {
        super.layout()
        contentContainer.frame = bounds
        for host in contentHosts {
            host.frame = contentContainer.bounds
        }
        let buttonY = max((bounds.height - Self.buttonHeight) / 2, 0)
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        previousButton.frame = NSRect(
            x: isRTL ? bounds.maxX - Self.buttonWidth : 0,
            y: buttonY,
            width: Self.buttonWidth,
            height: Self.buttonHeight
        )
        nextButton.frame = NSRect(
            x: isRTL ? 0 : bounds.maxX - Self.buttonWidth,
            y: buttonY,
            width: Self.buttonWidth,
            height: Self.buttonHeight
        )
        previousButton.updateSymbol(isRTL ? "chevron.right" : "chevron.left")
        nextButton.updateSymbol(isRTL ? "chevron.left" : "chevron.right")
    }

    override func keyDown(with event: NSEvent) {
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let leftKey: UInt16 = isRTL ? 124 : 123
        let rightKey: UInt16 = isRTL ? 123 : 124
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
        selectionBinding = selection
        self.onSelectionChanged = onSelectionChanged
        self.context = context
        animationCoordinator.reduceMotion = context.reduceMotion
        previousButton.theme = context.theme
        nextButton.theme = context.theme
        installSelectionObserver()

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
            rebuildContentHosts(animated: false)
        }
        let target = clamped(selection?.get() ?? selectedIndex)
        if target != selectedIndex {
            commit(to: target, animated: false)
        } else {
            showCurrent(animated: false)
        }
        updateAccessibilityValue()
        updateButtonState()
        needsLayout = true
    }

    deinit {
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
        let target = clamped(index)
        guard target >= 0, target != selectedIndex else { return }
        if let selectionBinding, !isWritingBinding {
            isWritingBinding = true
            selectionBinding.set(target)
            isWritingBinding = false
        }
        commit(to: target, animated: animated)
    }

    private func commit(to index: Int, animated: Bool) {
        let oldIndex = selectedIndex
        selectedIndex = index
        onSelectionChanged?(index)
        updateAccessibilityValue()
        updateButtonState()
        animateSelection(from: oldIndex, to: index, animated: animated)
    }

    private func animateSelection(from oldIndex: Int, to newIndex: Int, animated: Bool) {
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
        let direction: CGFloat = newIndex > oldIndex ? 1 : -1
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

        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: oldLayer,
                    key: "fluent.flipView.old.\(generation)",
                    keyPath: "transform",
                    toValue: NSValue(caTransform3D: oldEnd)
                ) {
                    oldLayer.transform = oldEnd
                },
                FluentLayerAnimationChange(
                    layer: newLayer,
                    key: "fluent.flipView.new.\(generation)",
                    keyPath: "transform",
                    toValue: NSValue(caTransform3D: CATransform3DIdentity)
                ) {
                    newLayer.transform = CATransform3DIdentity
                }
            ],
            motion: Self.transition,
            animated: true,
            completion: { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                oldHost.isHidden = true
                oldLayer.transform = CATransform3DIdentity
                newLayer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
        )
    }

    private func showCurrent(animated: Bool) {
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

    private func rebuildContentHosts(animated: Bool) {
        animationCoordinator.cancelAllValueAnimations()
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
        selectedIndex = clamped(selectedIndex)
        showCurrent(animated: animated)
        updateAccessibilityChildren()
    }

    private func updateButtonState() {
        previousButton.isEnabled = selectedIndex > 0
        nextButton.isEnabled = selectedIndex >= 0 && selectedIndex < records.count - 1
    }

    private func updateAccessibilityValue() {
        guard selectedIndex >= 0, selectedIndex < records.count else {
            setAccessibilityValue("0 items")
            return
        }
        setAccessibilityValue("\(selectedIndex + 1) of \(records.count)")
    }

    private func updateAccessibilityChildren() {
        setAccessibilityChildren(contentHosts + [previousButton, nextButton])
    }

    // MARK: - Binding

    private func installSelectionObserver() {
        removeSelectionObserver()
        guard let selectionBinding else { return }
        selectionObserverID = selectionBinding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isWritingBinding else { return }
                let target = self.clamped(value)
                guard target >= 0, target != self.selectedIndex else { return }
                self.commit(to: target, animated: true)
            }
        }
    }

    private func removeSelectionObserver() {
        if let selectionObserverID {
            selectionBinding?.removeObserver(selectionObserverID)
        }
        selectionObserverID = nil
    }
}

private final class FluentFlipViewButton: NSButton {
    var onClick: (() -> Void)?
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
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image?.isTemplate = true
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        updateAppearance()
        super.mouseUp(with: event)
    }

    @objc private func invoke() {
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
