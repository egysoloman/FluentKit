import AppKit

/// Trailing preserves WinUI CommandBar's default. Leading supports document toolbars such
/// as Explorer without changing the standard command/content arrangement for existing apps.
public enum FluentCommandBarPrimaryAlignment: Hashable, Sendable {
    case leading
    case trailing
}

public enum FluentAppBarClosedDisplayMode: Hashable, Sendable {
    case compact
    case minimal
    case hidden
}

public enum FluentCommandBarOverflowButtonVisibility: Hashable, Sendable {
    case automatic
    case visible
    case collapsed
}

public enum FluentCommandBarDynamicOverflowAction: Hashable, Sendable {
    case addingToOverflow
    case removingFromOverflow
}

/// WinUI-style CommandBar. Primary command objects remain stable while the bar reparents them
/// between the primary strip and the overflow presenter. Ordered overflow groups move first;
/// un-ordered commands then fall back to the source right-most-first policy.
public final class FluentCommandBar: NSView, FluentControlSizeConfigurable {
    public static let compactHeight: CGFloat = 48
    public static let openHeight: CGFloat = 64
    public static let minimalHeight: CGFloat = 24
    public static let moreButtonWidth: CGFloat = 48
    public static let contentLeadingPadding: CGFloat = 4

    public var primaryCommands: [FluentCommandBarItem] {
        didSet { rebuildControls() }
    }
    public var secondaryCommands: [FluentCommandBarItem] {
        didSet { rebuildControls() }
    }
    public var contentView: NSView? {
        didSet {
            if oldValue !== contentView { oldValue?.removeFromSuperview() }
            if let contentView, contentView.superview !== self { addSubview(contentView) }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    public var primaryCommandAlignment: FluentCommandBarPrimaryAlignment = .trailing {
        didSet { guard oldValue != primaryCommandAlignment else { return }; needsLayout = true }
    }
    public var defaultLabelPosition: FluentCommandBarDefaultLabelPosition = .bottom {
        didSet {
            guard oldValue != defaultLabelPosition else { return }
            primaryButtons.forEach { $0.defaultLabelPosition = defaultLabelPosition }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    public var overflowButtonVisibility: FluentCommandBarOverflowButtonVisibility = .automatic {
        didSet { guard oldValue != overflowButtonVisibility else { return }; needsLayout = true }
    }
    public var isDynamicOverflowEnabled = true {
        didSet { guard oldValue != isDynamicOverflowEnabled else { return }; needsLayout = true }
    }
    public var closedDisplayMode: FluentAppBarClosedDisplayMode = .compact {
        didSet {
            guard oldValue != closedDisplayMode else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            applyTheme()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            primaryButtons.forEach { $0.reduceMotion = reduceMotion }
            secondaryButtons.forEach { $0.reduceMotion = reduceMotion }
            moreButton.reduceMotion = reduceMotion
            overflowHost?.animationCoordinator.reduceMotion = reduceMotion
        }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            primaryControls.forEach { ($0 as? FluentControlSizeConfigurable)?.fluentControlSize = fluentControlSize }
            secondaryControls.forEach { ($0 as? FluentControlSizeConfigurable)?.fluentControlSize = fluentControlSize }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    public var onIsOpenChanged: ((Bool) -> Void)?
    public var onDynamicOverflowItemsChanging: ((FluentCommandBarDynamicOverflowAction) -> Void)?

    public private(set) var isOpen = false
    public private(set) var overflowedPrimaryIndexes: [Int] = []
    public var primaryCommandViews: [NSView] { primaryControls }
    public var secondaryCommandViews: [NSView] { secondaryControls }
    public var visiblePrimaryIndexes: [Int] {
        primaryCommands.indices.filter { !overflowedPrimaryIndexes.contains($0) }
    }
    public var isOverflowButtonVisible: Bool { resolvedOverflowButtonVisible }

    private var primaryControls: [NSView] = []
    private var secondaryControls: [NSView] = []
    private var primaryButtons: [FluentAppBarButton] { primaryControls.compactMap { $0 as? FluentAppBarButton } }
    private var secondaryButtons: [FluentAppBarButton] { secondaryControls.compactMap { $0 as? FluentAppBarButton } }
    private let moreButton = FluentCommandBarMoreButton()
    private weak var overflowPanel: FluentCommandBarPanel?
    private weak var overflowHost: FluentPopupTransitionHost?
    private weak var overflowPresenter: FluentCommandBarOverflowPresenter?
    private weak var restoreFirstResponder: NSResponder?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    public init(
        primaryCommands: [FluentCommandBarItem],
        secondaryCommands: [FluentCommandBarItem] = [],
        contentView: NSView? = nil
    ) {
        self.primaryCommands = primaryCommands
        self.secondaryCommands = secondaryCommands
        self.contentView = contentView
        super.init(frame: .zero)
        configure()
    }

    public convenience init(
        contentView: NSView? = nil,
        @FluentCommandBarBuilder primaryCommands: () -> [FluentCommandBarItem],
        @FluentCommandBarBuilder secondaryCommands: () -> [FluentCommandBarItem] = { [] }
    ) {
        self.init(
            primaryCommands: primaryCommands(),
            secondaryCommands: secondaryCommands(),
            contentView: contentView
        )
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { dismissOverflow(animated: false, notify: false) }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize {
        let scale = fluentControlSize.metricScale
        let height = isOpen ? Self.openHeight : closedHeight
        let primaryWidth = primaryControls.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width }
        let contentWidth = max(0, contentView?.intrinsicContentSize.width ?? 0)
        let moreWidth = resolvedOverflowButtonVisible ? Self.moreButtonWidth * scale : 0
        return NSSize(
            width: Self.contentLeadingPadding * scale + contentWidth + primaryWidth + moreWidth,
            height: height * scale
        )
    }

    public override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        recomputeDynamicOverflow(for: bounds.width)
        arrangePrimaryStrip()
    }

    public func setOpen(_ open: Bool, animated: Bool = true) {
        guard open != isOpen else { return }
        if open { presentOverflow(animated: animated) }
        else { dismissOverflow(animated: animated, notify: true) }
    }

    public func toggleOverflow() { setOpen(!isOpen, animated: true) }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissOverflow(animated: false, notify: true) }
    }

    private var closedHeight: CGFloat {
        switch closedDisplayMode {
        case .compact: Self.compactHeight
        case .minimal: Self.minimalHeight
        case .hidden: 0
        }
    }

    private var hasBottomLabel: Bool {
        guard defaultLabelPosition == .bottom else { return false }
        return primaryCommands.contains { !$0.isSeparator && $0.labelPosition != .collapsed }
    }

    private var resolvedOverflowButtonVisible: Bool {
        switch overflowButtonVisibility {
        case .visible: true
        case .collapsed: false
        case .automatic:
            !secondaryCommands.isEmpty
                || !overflowedPrimaryIndexes.isEmpty
                || closedDisplayMode != .compact
                || hasBottomLabel
                || bounds.height > Self.compactHeight * fluentControlSize.metricScale + 0.5
        }
    }

    private func configure() {
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CommandBar")
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        fluentSetDefaultAccessibilityTitle("Command bar")
        setAccessibilityExpanded(false)
        moreButton.onInvoke = { [weak self] in self?.toggleOverflow() }
        addSubview(moreButton)
        if let contentView { addSubview(contentView) }
        rebuildControls()
        applyTheme()
    }

    private func rebuildControls() {
        dismissOverflow(animated: false, notify: true)
        primaryControls.forEach { $0.removeFromSuperview() }
        secondaryControls.forEach { $0.removeFromSuperview() }
        primaryControls = primaryCommands.enumerated().map { makeControl(for: $0.element, primaryIndex: $0.offset) }
        secondaryControls = secondaryCommands.map { makeControl(for: $0, primaryIndex: nil) }
        primaryControls.forEach(addSubview)
        overflowedPrimaryIndexes = []
        applyTheme()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func makeControl(for item: FluentCommandBarItem, primaryIndex: Int?) -> NSView {
        let view: NSView
        switch item.kind {
        case .separator:
            let separator = FluentAppBarSeparator()
            separator.dynamicOverflowOrder = item.dynamicOverflowOrder
            view = separator
        case .button:
            let button = FluentAppBarButton(item.title, systemImageName: item.systemImageName) { [weak self] in
                item.action()
                if self?.isOpen == true { self?.dismissOverflow(animated: true, notify: true) }
            }
            configure(button: button, item: item)
            view = button
        case .toggle(let isOn):
            let button = FluentAppBarToggleButton(
                item.title,
                systemImageName: item.systemImageName,
                isChecked: isOn
            ) { [weak self] _ in
                item.action()
                if self?.isOpen == true { self?.dismissOverflow(animated: true, notify: true) }
            }
            configure(button: button, item: item)
            view = button
        }
        view.identifier = NSUserInterfaceItemIdentifier(
            primaryIndex.map { "FluentKit.CommandBar.Primary.\($0)" } ?? "FluentKit.CommandBar.Secondary"
        )
        (view as? FluentControlSizeConfigurable)?.fluentControlSize = fluentControlSize
        return view
    }

    private func configure(button: FluentAppBarButton, item: FluentCommandBarItem) {
        button.labelPosition = item.labelPosition
        button.defaultLabelPosition = defaultLabelPosition
        button.icon = item.icon
        button.dynamicOverflowOrder = item.dynamicOverflowOrder
        button.keyboardAcceleratorTextOverride = item.accelerator
        button.isEnabled = item.isEnabled
        button.reduceMotion = reduceMotion
        button.theme = theme
    }

    private func applyTheme() {
        layer?.backgroundColor = NSColor.clear.cgColor
        primaryButtons.forEach { $0.theme = theme }
        secondaryButtons.forEach { $0.theme = theme }
        primaryControls.compactMap { $0 as? FluentAppBarSeparator }.forEach { $0.theme = theme }
        secondaryControls.compactMap { $0 as? FluentAppBarSeparator }.forEach { $0.theme = theme }
        moreButton.theme = theme
        overflowHost?.update(theme: theme)
        overflowPresenter?.theme = theme
        needsDisplay = true
    }

    private func recomputeDynamicOverflow(for totalWidth: CGFloat) {
        let scale = fluentControlSize.metricScale
        let contentMinimum = max(0, contentView?.intrinsicContentSize.width ?? 0)
        // Auto can become visible because overflow was needed. Reserve More while measuring if
        // secondary commands or a source condition already requires it; otherwise retry once when
        // the first primary command is moved.
        let sourceNeedsMore = overflowButtonVisibility == .visible
            || (overflowButtonVisibility == .automatic
                && (!secondaryCommands.isEmpty || closedDisplayMode != .compact || hasBottomLabel))
        let reservedMore = sourceNeedsMore ? Self.moreButtonWidth * scale : 0
        var available = max(0, totalWidth - Self.contentLeadingPadding * scale - contentMinimum - reservedMore)
        var result: [Int] = []
        guard isDynamicOverflowEnabled else {
            updateOverflowIndexes(result)
            return
        }

        let widths = primaryControls.map { max(0, $0.intrinsicContentSize.width) }
        var remaining = widths.reduce(0, +)
        guard remaining > available else {
            updateOverflowIndexes(result)
            return
        }
        if !sourceNeedsMore, overflowButtonVisibility != .collapsed {
            available = max(0, available - Self.moreButtonWidth * scale)
        }

        let positiveOrders = Array(Set(primaryCommands.map(\.dynamicOverflowOrder).filter { $0 > 0 })).sorted()
        for order in positiveOrders where remaining > available {
            let group = primaryCommands.indices.filter { primaryCommands[$0].dynamicOverflowOrder == order }
            appendWithAdjacentSeparators(group, to: &result)
            remaining = widthExcluding(result, widths: widths)
        }

        if remaining > available {
            if positiveOrders.isEmpty {
                // Source default starts at the command nearest More and can ultimately move the
                // first/only command too when no primary width remains.
                for index in primaryCommands.indices.reversed() where remaining > available {
                    appendWithAdjacentSeparators([index], to: &result)
                    remaining = widthExcluding(result, widths: widths)
                }
            } else {
                for index in primaryCommands.indices.reversed()
                    where primaryCommands[index].dynamicOverflowOrder == 0 && remaining > available {
                    appendWithAdjacentSeparators([index], to: &result)
                    remaining = widthExcluding(result, widths: widths)
                }
            }
        }
        trimOuterSeparators(in: &result)
        updateOverflowIndexes(result.sorted())
    }

    private func appendWithAdjacentSeparators(_ indexes: [Int], to result: inout [Int]) {
        for index in indexes where !result.contains(index) { result.append(index) }
        for index in indexes {
            if index > 0, primaryCommands[index - 1].isSeparator, !result.contains(index - 1) {
                result.append(index - 1)
            }
            if index + 1 < primaryCommands.count,
               primaryCommands[index + 1].isSeparator,
               !result.contains(index + 1) {
                result.append(index + 1)
            }
        }
    }

    private func trimOuterSeparators(in indexes: inout [Int]) {
        while let first = primaryCommands.indices.first(where: { !Set(indexes).contains($0) }),
              primaryCommands[first].isSeparator {
            indexes.append(first)
        }
        while let last = primaryCommands.indices.last(where: { !Set(indexes).contains($0) }),
              primaryCommands[last].isSeparator {
            indexes.append(last)
        }
    }

    private func widthExcluding(_ indexes: [Int], widths: [CGFloat]) -> CGFloat {
        let excluded = Set(indexes)
        return widths.indices.filter { !excluded.contains($0) }.reduce(CGFloat(0)) { $0 + widths[$1] }
    }

    private func updateOverflowIndexes(_ next: [Int]) {
        guard next != overflowedPrimaryIndexes else { return }
        let action: FluentCommandBarDynamicOverflowAction = next.count > overflowedPrimaryIndexes.count
            ? .addingToOverflow
            : .removingFromOverflow
        overflowedPrimaryIndexes = next
        onDynamicOverflowItemsChanging?(action)
        if isOpen {
            dismissOverflow(animated: false, notify: false)
            presentOverflow(animated: false)
        }
        invalidateIntrinsicContentSize()
    }

    private func arrangePrimaryStrip() {
        let scale = fluentControlSize.metricScale
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let barHeight = isOpen ? Self.openHeight * scale : closedHeight * scale
        let hidesContent = !isOpen && closedDisplayMode != .compact
        let showMore = resolvedOverflowButtonVisible
        moreButton.isHidden = !showMore || (!isOpen && closedDisplayMode == .hidden)
        moreButton.isEnabled = !moreButton.isHidden
        moreButton.isExpanded = isOpen
        moreButton.userInterfaceLayoutDirection = userInterfaceLayoutDirection

        let overflowed = Set(overflowedPrimaryIndexes)
        let leadingAligned = primaryCommandAlignment == .leading
        let visualIndexes = leadingAligned ? Array(primaryControls.indices) : Array(primaryControls.indices.reversed())
        var commandLeading: CGFloat
        var commandTrailing: CGFloat
        if rtl {
            let moreWidth = showMore ? Self.moreButtonWidth * scale : 0
            if showMore {
                moreButton.frame = CGRect(x: 0, y: 0, width: moreWidth, height: barHeight)
            }
            commandLeading = moreWidth
            commandTrailing = bounds.maxX
        } else {
            let moreWidth = showMore ? Self.moreButtonWidth * scale : 0
            if showMore {
                moreButton.frame = CGRect(x: bounds.maxX - moreWidth, y: 0, width: moreWidth, height: barHeight)
            }
            commandLeading = 0
            commandTrailing = bounds.maxX - moreWidth
        }
        if leadingAligned {
            commandLeading = Self.contentLeadingPadding * scale
            commandTrailing = bounds.maxX - Self.contentLeadingPadding * scale
        }
        for index in visualIndexes {
            let control = primaryControls[index]
            control.userInterfaceLayoutDirection = userInterfaceLayoutDirection
            let isMoved = overflowed.contains(index)
            control.isHidden = hidesContent || isMoved
            guard !control.isHidden else { continue }
            if control.superview !== self {
                control.removeFromSuperview()
                addSubview(control, positioned: .below, relativeTo: moreButton)
            }
            // Resolve the visual state before measuring. Otherwise the first open/close layout
            // pass measures the previous 48/64-point branch and then mutates it after framing.
            if let button = control as? FluentAppBarButton {
                button.useOverflowStyle = false
                button.isCompact = !isOpen
            } else if let separator = control as? FluentAppBarSeparator {
                separator.useOverflowStyle = false
                separator.isCompact = !isOpen
            }
            let size = control.intrinsicContentSize
            if rtl != leadingAligned {
                control.frame = CGRect(x: commandLeading, y: 0, width: size.width, height: barHeight)
                commandLeading += size.width
            } else {
                commandTrailing -= size.width
                control.frame = CGRect(x: commandTrailing, y: 0, width: size.width, height: barHeight)
            }
        }
        if leadingAligned, showMore {
            let width = Self.moreButtonWidth * scale
            moreButton.frame = CGRect(x: rtl ? commandTrailing - width : commandLeading, y: 0, width: width, height: barHeight)
            if rtl { commandTrailing -= width } else { commandLeading += width }
        }
        contentView?.isHidden = hidesContent
        if let contentView, !hidesContent {
            let padding = Self.contentLeadingPadding * scale
            contentView.frame = (rtl != leadingAligned)
                ? CGRect(x: commandLeading, y: 0, width: max(0, bounds.maxX - padding - commandLeading), height: barHeight)
                : CGRect(x: padding, y: 0, width: max(0, commandTrailing - padding), height: barHeight)
        }
        layer?.cornerRadius = isOpen ? theme.designTokens.controlCornerRadius : 0
        setAccessibilityChildren(
            (contentView.map { [$0] } ?? [])
                + visiblePrimaryIndexes.compactMap { primaryControls[$0].isHidden ? nil : primaryControls[$0] }
                + (moreButton.isHidden ? [] : [moreButton])
        )
    }

    private var overflowControlsInOrder: [NSView] {
        var result = overflowedPrimaryIndexes.sorted().map { primaryControls[$0] }
        if !result.isEmpty, !secondaryControls.isEmpty {
            result.append(FluentAppBarSeparator(useOverflowStyle: true))
        }
        result.append(contentsOf: secondaryControls)
        return result
    }

    private func presentOverflow(animated: Bool) {
        guard !isOpen, let anchorWindow = window else { return }
        let controls = overflowControlsInOrder
        restoreFirstResponder = anchorWindow.firstResponder
        isOpen = true
        primaryButtons.forEach { $0.isCompact = false }
        arrangePrimaryStrip()
        notifyIntrinsicHeightChanged()

        // A compact bar with bottom labels still opens to the full 64-point primary template even
        // when it has no secondary rows. This is why Auto shows More for bottom-labeled commands.
        guard !controls.isEmpty else {
            moreButton.isExpanded = true
            setAccessibilityExpanded(true)
            onIsOpenChanged?(true)
            return
        }

        let presenter = FluentCommandBarOverflowPresenter(controls: controls, theme: theme)
        presenter.onDismiss = { [weak self] in self?.dismissOverflow(animated: true, notify: true) }
        presenter.userInterfaceLayoutDirection = userInterfaceLayoutDirection
        controls.forEach { $0.userInterfaceLayoutDirection = userInterfaceLayoutDirection }
        let size = presenter.preferredSize
        let panel = FluentCommandBarPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.appearance = anchorWindow.effectiveAppearance

        let host = FluentPopupTransitionHost(
            content: presenter,
            theme: theme,
            cornerRadius: theme.designTokens.cardCornerRadius,
            name: "FluentKit.CommandBar.Overflow"
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        let anchor = anchorWindow.convertToScreen(convert(bounds, to: nil))
        let visible = anchorWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let spaceBelow = anchor.minY - visible.minY
        let opensBelow = spaceBelow >= size.height + 4 || anchor.maxY + size.height > visible.maxY
        let preferredX = userInterfaceLayoutDirection == .rightToLeft ? anchor.minX : anchor.maxX - size.width
        var origin = NSPoint(
            x: min(max(preferredX, visible.minX + 4), max(visible.maxX - size.width - 4, visible.minX + 4)),
            y: opensBelow ? anchor.minY - size.height : anchor.maxY
        )
        origin.y = min(max(origin.y, visible.minY + 4), max(visible.maxY - size.height - 4, visible.minY + 4))

        anchorWindow.addChildWindow(panel, ordered: .above)
        panel.setFrameOrigin(origin)
        overflowPanel = panel
        overflowHost = host
        overflowPresenter = presenter
        installDismissMonitors()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(presenter.firstFocusableControl)
        fluentPrepareMenuPopupEntrance(
            host: host,
            edge: opensBelow ? .top : .bottom,
            motion: FluentMotion.controlNormal,
            closedRatio: 0.5,
            reduceMotion: reduceMotion || !animated
        )
        moreButton.isExpanded = true
        setAccessibilityExpanded(true)
        onIsOpenChanged?(true)
    }

    private func dismissOverflow(animated: Bool, notify: Bool) {
        guard isOpen || overflowPanel != nil else { return }
        removeDismissMonitors()
        let panel = overflowPanel
        let host = overflowHost
        overflowPanel = nil
        overflowHost = nil
        overflowPresenter = nil
        isOpen = false

        let finish = { [weak self, weak panel] in
            guard let self else { return }
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            // Reparent every primary object, including commands that remain logically overflowed.
            // Those commands stay hidden in the strip but must not remain owned by a dismissed
            // presenter or lose identity when a later wider measure restores them.
            for control in self.primaryControls {
                control.removeFromSuperview()
                self.addSubview(control, positioned: .below, relativeTo: self.moreButton)
            }
            self.secondaryControls.forEach { $0.removeFromSuperview() }
            self.primaryButtons.forEach {
                $0.useOverflowStyle = false
                $0.isCompact = true
            }
            self.arrangePrimaryStrip()
            if let responder = self.restoreFirstResponder,
               let anchorWindow = self.window,
               (responder as? NSView)?.window === anchorWindow {
                anchorWindow.makeFirstResponder(responder)
            } else if self.window?.firstResponder == nil {
                self.window?.makeFirstResponder(self.moreButton)
            }
            self.restoreFirstResponder = nil
        }
        if animated, !reduceMotion, panel != nil, let host {
            host.animationCoordinator.animateTransition([
                FluentLayerAnimationChange(
                    layer: host.animationRoot.layer!,
                    key: "fluent.commandbar.close.opacity",
                    keyPath: "opacity",
                    toValue: Float(0)
                ) { host.animationRoot.layer?.opacity = 0 }
            ], motion: FluentMotion.controlFast, animated: true, completion: finish)
        } else {
            finish()
        }
        moreButton.isExpanded = false
        setAccessibilityExpanded(false)
        notifyIntrinsicHeightChanged()
        if notify { onIsOpenChanged?(false) }
    }

    private func notifyIntrinsicHeightChanged() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        // Declarative frame/layout wrappers derive their own intrinsic size from this view.
        // AppKit does not invalidate that derived metric automatically when a descendant changes.
        var ancestor = superview
        while let current = ancestor {
            current.invalidateIntrinsicContentSize()
            current.needsLayout = true
            ancestor = current.superview
        }
    }

    private func installDismissMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.overflowPanel else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismissOverflow(animated: true, notify: true)
                return nil
            }
            if event.window === panel {
                if event.type == .keyDown, self.overflowPresenter?.handleNavigation(event) == true { return nil }
                return event
            }
            if event.window === self.window {
                if event.type != .keyDown,
                   !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.dismissOverflow(animated: true, notify: true)
                }
                return event
            }
            if event.type != .keyDown { self.dismissOverflow(animated: true, notify: true) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissOverflow(animated: false, notify: true)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in self?.dismissOverflow(animated: false, notify: true) }
    }

    private func removeDismissMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        localMonitor = nil
        globalMonitor = nil
        resignObserver = nil
    }
}

private final class FluentCommandBarMoreButton: NSControl {
    var onInvoke: (() -> Void)?
    var theme: FluentTheme = .current { didSet { updateAppearance() } }
    var reduceMotion = false
    var isExpanded = false {
        didSet {
            setAccessibilityExpanded(isExpanded)
            updateAppearance()
        }
    }
    private var pointerOver = false
    private var pressed = false
    private var trackingPress = false
    private let surface = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CommandBar.MoreButton")
        layer?.addSublayer(surface)
        surface.cornerCurve = .continuous
        setAccessibilityRole(.button)
        fluentSetDefaultAccessibilityTitle("More")
        setAccessibilityExpanded(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixel = 1 / max(scale, 1)
        surface.frame = CGRect(x: 2, y: min(6, bounds.height), width: max(0, bounds.width - 8), height: max(0, bounds.height - 12))
        surface.cornerRadius = theme.designTokens.controlCornerRadius
        surface.borderWidth = theme.isHighContrast ? max(2, pixel) : 0
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { pointerOver = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { pointerOver = false; if !trackingPress { pressed = false }; updateAppearance() }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        trackingPress = true
        pressed = true
        updateAppearance()
    }
    override func mouseDragged(with event: NSEvent) {
        guard trackingPress else { return }
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
        updateAppearance()
    }
    override func mouseUp(with event: NSEvent) {
        guard trackingPress else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        trackingPress = false
        pressed = false
        updateAppearance()
        if inside { onInvoke?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { pressed = true; updateAppearance() }
        else { super.keyDown(with: event) }
    }
    override func keyUp(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 49), pressed {
            pressed = false
            updateAppearance()
            onInvoke?()
        } else { super.keyUp(with: event) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onInvoke?()
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More") else { return }
        let color = isEnabled ? (pressed ? theme.textSecondary : theme.textPrimary) : theme.textDisabled
        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 20, weight: .regular).applying(.init(hierarchicalColor: color))
        ) ?? image
        configured.draw(
            in: FluentIconSource.systemSymbol("ellipsis").fittedRect(imageSize: configured.size,
                in: CGRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20)),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        let fill: NSColor = pressed
            ? theme.subtleFillTertiary
            : ((pointerOver || isExpanded) ? theme.subtleFillSecondary : .clear)
        surface.backgroundColor = fill.cgColor
        surface.borderColor = theme.focusStrokeOuter.cgColor
        CATransaction.commit()
        needsDisplay = true
    }
}

private final class FluentCommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FluentCommandBarOverflowPresenter: NSView {
    let controls: [NSView]
    let preferredSize: NSSize
    var onDismiss: (() -> Void)?
    var theme: FluentTheme {
        didSet {
            controls.compactMap { $0 as? FluentAppBarButton }.forEach { $0.theme = theme }
            controls.compactMap { $0 as? FluentAppBarSeparator }.forEach { $0.theme = theme }
        }
    }
    var firstFocusableControl: NSView? { controls.first { $0.acceptsFirstResponder } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(controls: [NSView], theme: FluentTheme) {
        self.controls = controls
        self.theme = theme
        let width = min(max(controls.map { $0.intrinsicContentSize.width }.max() ?? 160, 160), 480)
        let height = controls.reduce(CGFloat(8)) { total, view in
            total + (view is FluentAppBarSeparator ? 9 : 40)
        }
        preferredSize = NSSize(width: width, height: min(height, 640))
        super.init(frame: NSRect(origin: .zero, size: preferredSize))
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CommandBar.OverflowPresenter")
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        fluentSetDefaultAccessibilityTitle("Command bar overflow")
        for control in controls {
            control.removeFromSuperview()
            addSubview(control)
            control.userInterfaceLayoutDirection = userInterfaceLayoutDirection
            if let button = control as? FluentAppBarButton {
                button.useOverflowStyle = true
            } else if let separator = control as? FluentAppBarSeparator {
                separator.useOverflowStyle = true
            }
        }
        setAccessibilityChildren(controls.filter { !($0 is FluentAppBarSeparator) })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        var y: CGFloat = 4
        for control in controls {
            let height: CGFloat = control is FluentAppBarSeparator ? 9 : 40
            control.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?(); return }
        if handleNavigation(event) { return }
        super.keyDown(with: event)
    }

    func handleNavigation(_ event: NSEvent) -> Bool {
        let focusable = controls.filter { $0.acceptsFirstResponder && !($0 is FluentAppBarSeparator) }
        guard !focusable.isEmpty else { return false }
        let current = focusable.firstIndex { $0 === window?.firstResponder }
        let destination: Int
        switch event.keyCode {
        case 125: destination = min((current ?? -1) + 1, focusable.count - 1) // Down
        case 126: destination = max((current ?? 1) - 1, 0) // Up
        case 115: destination = 0 // Home
        case 119: destination = focusable.count - 1 // End
        default: return false
        }
        window?.makeFirstResponder(focusable[destination])
        return true
    }
}

public struct FluentCommandBarView: FluentUpdatablePrimitiveView {
    public let primaryCommands: [FluentCommandBarItem]
    public let secondaryCommands: [FluentCommandBarItem]
    public let defaultLabelPosition: FluentCommandBarDefaultLabelPosition
    public let overflowButtonVisibility: FluentCommandBarOverflowButtonVisibility
    public let isDynamicOverflowEnabled: Bool
    public let primaryCommandAlignment: FluentCommandBarPrimaryAlignment
    public let closedDisplayMode: FluentAppBarClosedDisplayMode

    public init(
        primaryCommands: [FluentCommandBarItem],
        secondaryCommands: [FluentCommandBarItem] = [],
        defaultLabelPosition: FluentCommandBarDefaultLabelPosition = .bottom,
        overflowButtonVisibility: FluentCommandBarOverflowButtonVisibility = .automatic,
        isDynamicOverflowEnabled: Bool = true,
        closedDisplayMode: FluentAppBarClosedDisplayMode = .compact,
        primaryCommandAlignment: FluentCommandBarPrimaryAlignment = .trailing
    ) {
        self.primaryCommands = primaryCommands
        self.secondaryCommands = secondaryCommands
        self.defaultLabelPosition = defaultLabelPosition
        self.overflowButtonVisibility = overflowButtonVisibility
        self.isDynamicOverflowEnabled = isDynamicOverflowEnabled
        self.primaryCommandAlignment = primaryCommandAlignment
        self.closedDisplayMode = closedDisplayMode
    }

    public init(
        defaultLabelPosition: FluentCommandBarDefaultLabelPosition = .bottom,
        overflowButtonVisibility: FluentCommandBarOverflowButtonVisibility = .automatic,
        isDynamicOverflowEnabled: Bool = true,
        closedDisplayMode: FluentAppBarClosedDisplayMode = .compact,
        primaryCommandAlignment: FluentCommandBarPrimaryAlignment = .trailing,
        @FluentCommandBarBuilder primaryCommands: () -> [FluentCommandBarItem],
        @FluentCommandBarBuilder secondaryCommands: () -> [FluentCommandBarItem] = { [] }
    ) {
        self.init(
            primaryCommands: primaryCommands(),
            secondaryCommands: secondaryCommands(),
            defaultLabelPosition: defaultLabelPosition,
            overflowButtonVisibility: overflowButtonVisibility,
            isDynamicOverflowEnabled: isDynamicOverflowEnabled,
            closedDisplayMode: closedDisplayMode,
            primaryCommandAlignment: primaryCommandAlignment
        )
    }

    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        let bar = FluentCommandBar(primaryCommands: primaryCommands, secondaryCommands: secondaryCommands)
        apply(to: bar, context: context, replaceCommands: false)
        return bar
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let bar = view as? FluentCommandBar else { return false }
        apply(to: bar, context: context, replaceCommands: true)
        return true
    }
    private func apply(to bar: FluentCommandBar, context: FluentRenderContext, replaceCommands: Bool) {
        if replaceCommands {
            bar.primaryCommands = primaryCommands
            bar.secondaryCommands = secondaryCommands
        }
        bar.primaryCommandAlignment = primaryCommandAlignment
        bar.defaultLabelPosition = defaultLabelPosition
        bar.overflowButtonVisibility = overflowButtonVisibility
        bar.isDynamicOverflowEnabled = isDynamicOverflowEnabled
        bar.closedDisplayMode = closedDisplayMode
        bar.theme = context.theme
        bar.reduceMotion = context.reduceMotion
    }
}
