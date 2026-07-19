import AppKit

/// Places a teaching tip relative to the view carrying the presentation modifier.
public enum FluentTeachingTipPlacement: Hashable, Sendable {
    case automatic
    case top
    case bottom
    case leading
    case trailing
}

/// A binding-driven, application-owned teaching-tip presentation.
public struct FluentTeachingTip<Content: FluentView, TipContent: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let tipContent: TipContent
    private let isPresented: FluentBinding<Bool>
    private let placement: FluentTeachingTipPlacement
    private let size: NSSize
    private let onDismiss: () -> Void

    public init(
        isPresented: FluentBinding<Bool>,
        placement: FluentTeachingTipPlacement = .automatic,
        size: NSSize = NSSize(width: 320, height: 150),
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder tip: () -> TipContent
    ) {
        self.content = content()
        tipContent = tip()
        self.isPresented = isPresented
        self.placement = placement
        self.size = NSSize(width: max(size.width, 240), height: max(size.height, 96))
        self.onDismiss = onDismiss
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentTeachingTipHost(
            content: content._mount(in: context),
            tipContent: tipContent,
            binding: isPresented,
            placement: placement,
            size: size,
            onDismiss: onDismiss,
            context: context
        )
        host.updateContent = { [content] nativeView, updateContext in
            content._update(nativeView, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentTeachingTipHost<TipContent> else { return false }
        host.update(
            tipContent: tipContent,
            binding: isPresented,
            placement: placement,
            size: size,
            onDismiss: onDismiss,
            context: context
        )
        return host.updateContent?(host.anchorContent, context) ?? false
    }
}

public extension FluentView {
    /// Presents a Fluent teaching tip next to this view while keeping the anchor mounted.
    func teachingTip<TipContent: FluentView>(
        isPresented: FluentBinding<Bool>,
        placement: FluentTeachingTipPlacement = .automatic,
        size: NSSize = NSSize(width: 320, height: 150),
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: @escaping () -> TipContent
    ) -> FluentTeachingTip<Self, TipContent> {
        FluentTeachingTip(
            isPresented: isPresented,
            placement: placement,
            size: size,
            onDismiss: onDismiss,
            content: { self },
            tip: content
        )
    }
}

private final class FluentTeachingTipHost<TipContent: FluentView>: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var anchorContent: NSView { subviews[0] }

    private var tipContent: TipContent
    private var binding: FluentBinding<Bool>
    private var placement: FluentTeachingTipPlacement
    private var size: NSSize
    private var onDismiss: () -> Void
    private var context: FluentRenderContext
    private var observerID: UUID?
    private var panel: FluentTeachingTipPanel?
    private var chrome: FluentTeachingTipChrome?
    private var tipHost: FluentViewHost<TipContent>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isDismissing = false

    init(
        content: NSView,
        tipContent: TipContent,
        binding: FluentBinding<Bool>,
        placement: FluentTeachingTipPlacement,
        size: NSSize,
        onDismiss: @escaping () -> Void,
        context: FluentRenderContext
    ) {
        self.tipContent = tipContent
        self.binding = binding
        self.placement = placement
        self.size = size
        self.onDismiss = onDismiss
        self.context = context
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installObserver()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    override func layout() {
        super.layout()
        if panel != nil { positionPanel() }
    }

    func update(
        tipContent: TipContent,
        binding: FluentBinding<Bool>,
        placement: FluentTeachingTipPlacement,
        size: NSSize,
        onDismiss: @escaping () -> Void,
        context: FluentRenderContext
    ) {
        if let observerID { self.binding.removeObserver(observerID) }
        self.tipContent = tipContent
        self.binding = binding
        self.placement = placement
        self.size = size
        self.onDismiss = onDismiss
        self.context = context
        tipHost?.context = context
        tipHost?.update(tipContent)
        chrome?.theme = context.theme
        chrome?.surfaceSize = size
        installObserver()
        synchronizePresentation()
        positionPanel()
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func synchronizePresentation() {
        guard window != nil else { return }
        if binding.get() {
            guard panel == nil, !isDismissing else { return }
            present()
        } else if panel != nil, !isDismissing {
            dismiss(animated: !context.reduceMotion)
        }
    }

    private func present() {
        guard let parentWindow = window else { return }
        let resolvedPlacement = resolvePlacement()
        let host = FluentViewHost(tipContent, context: context)
        let chrome = FluentTeachingTipChrome(
            content: host,
            surfaceSize: size,
            placement: resolvedPlacement,
            theme: context.theme
        )
        chrome.onDismiss = { [weak self] in self?.requestDismissal() }
        let panel = FluentTeachingTipPanel(
            contentRect: NSRect(origin: .zero, size: chrome.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = chrome
        parentWindow.addChildWindow(panel, ordered: .above)
        self.panel = panel
        self.chrome = chrome
        tipHost = host
        positionPanel(resolvedPlacement: resolvedPlacement)
        installOutsideClickMonitors(panel: panel)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(chrome)
        animate(opening: true, panel: panel, chrome: chrome, placement: resolvedPlacement)
    }

    private func requestDismissal() {
        if binding.get() {
            binding.set(false)
        } else {
            synchronizePresentation()
        }
    }

    private func dismiss(animated: Bool) {
        guard let panel, let chrome else { return }
        isDismissing = true
        removeOutsideClickMonitors()
        let finish = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.window?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
            self.chrome = nil
            self.tipHost = nil
            self.isDismissing = false
            self.onDismiss()
            self.synchronizePresentation()
        }
        guard animated else {
            finish()
            return
        }
        animate(opening: false, panel: panel, chrome: chrome, placement: chrome.placement, completion: finish)
    }

    private func resolvePlacement() -> FluentTeachingTipPlacement {
        guard placement == .automatic, let parentWindow = window else { return placement }
        let anchor = parentWindow.convertToScreen(convert(bounds, to: nil))
        let visible = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let verticalSpaceAbove = visible.maxY - anchor.maxY
        let verticalSpaceBelow = anchor.minY - visible.minY
        return verticalSpaceAbove >= size.height + 48 || verticalSpaceAbove >= verticalSpaceBelow
            ? .top
            : .bottom
    }

    private func positionPanel(resolvedPlacement: FluentTeachingTipPlacement? = nil) {
        guard let parentWindow = window, let panel, let chrome else { return }
        let resolved = resolvedPlacement ?? (chrome.placement == .automatic ? resolvePlacement() : chrome.placement)
        chrome.placement = resolved
        let anchor = parentWindow.convertToScreen(convert(bounds, to: nil))
        let panelSize = chrome.panelSize
        let gap: CGFloat = 4
        var origin: NSPoint
        switch resolved {
        case .automatic, .top:
            origin = NSPoint(
                x: anchor.midX - chrome.surfaceFrame.midX,
                y: anchor.maxY + gap - FluentTeachingTipChrome.shadowMargin
            )
        case .bottom:
            origin = NSPoint(
                x: anchor.midX - chrome.surfaceFrame.midX,
                y: anchor.minY - gap - panelSize.height + FluentTeachingTipChrome.shadowMargin
            )
        case .leading:
            origin = NSPoint(
                x: anchor.minX - gap - panelSize.width + FluentTeachingTipChrome.shadowMargin,
                y: anchor.midY - chrome.surfaceFrame.midY
            )
        case .trailing:
            origin = NSPoint(
                x: anchor.maxX + gap - FluentTeachingTipChrome.shadowMargin,
                y: anchor.midY - chrome.surfaceFrame.midY
            )
        }

        let visible = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        origin.x = min(max(origin.x, visible.minX), max(visible.maxX - panelSize.width, visible.minX))
        origin.y = min(max(origin.y, visible.minY), max(visible.maxY - panelSize.height, visible.minY))
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)

        switch resolved {
        case .automatic, .top, .bottom:
            chrome.tailOffset = anchor.midX - origin.x
        case .leading, .trailing:
            chrome.tailOffset = anchor.midY - origin.y
        }
    }

    private func animate(
        opening: Bool,
        panel: NSPanel,
        chrome: FluentTeachingTipChrome,
        placement: FluentTeachingTipPlacement,
        completion: (() -> Void)? = nil
    ) {
        guard !context.reduceMotion else {
            panel.alphaValue = opening ? 1 : 0
            chrome.layer?.setAffineTransform(.identity)
            chrome.layer?.shadowOpacity = opening ? 0.24 : 0
            completion?()
            return
        }
        let motion = opening ? FluentMotion.teachingTipOpen : FluentMotion.teachingTipClose
        let offset = Self.offset(for: placement, distance: motion.distance)
        let compact = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: motion.scale, y: motion.scale)
        if opening {
            panel.alphaValue = 0
            chrome.layer?.setAffineTransform(compact)
            chrome.layer?.shadowOpacity = 0
        }
        NSAnimationContext.runAnimationGroup { animationContext in
            animationContext.duration = motion.duration
            animationContext.timingFunction = motion.curve.timingFunction
            panel.animator().alphaValue = opening ? 1 : 0
        } completionHandler: {
            completion?()
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(motion.duration)
        CATransaction.setAnimationTimingFunction(motion.curve.timingFunction)
        chrome.layer?.setAffineTransform(opening ? .identity : compact)
        chrome.layer?.shadowOpacity = opening ? 0.24 : 0
        CATransaction.commit()
    }

    private static func offset(for placement: FluentTeachingTipPlacement, distance: CGFloat) -> NSPoint {
        switch placement {
        case .automatic, .top: return NSPoint(x: 0, y: -distance)
        case .bottom: return NSPoint(x: 0, y: distance)
        case .leading: return NSPoint(x: distance, y: 0)
        case .trailing: return NSPoint(x: -distance, y: 0)
        }
    }

    private func installOutsideClickMonitors(panel: NSPanel) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            if event.window !== panel { self?.requestDismissal() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.requestDismissal()
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit {
        if let observerID { binding.removeObserver(observerID) }
        removeOutsideClickMonitors()
        if let panel {
            window?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}

private final class FluentTeachingTipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FluentTeachingTipChrome: NSView {
    static let shadowMargin: CGFloat = 16
    private static let tailLength: CGFloat = 8

    var theme: FluentTheme { didSet { applyTheme() } }
    var placement: FluentTeachingTipPlacement { didSet { needsLayout = true; needsDisplay = true } }
    var tailOffset: CGFloat = 0 { didSet { needsDisplay = true; updateShadowPath() } }
    var onDismiss: (() -> Void)?
    var surfaceSize: NSSize {
        didSet {
            frame.size = panelSize
            needsLayout = true
            needsDisplay = true
        }
    }

    private let material = FluentMaterialView(material: .acrylic)
    private let closeButton = NSButton()

    var panelSize: NSSize {
        switch placement {
        case .leading, .trailing:
            return NSSize(
                width: surfaceSize.width + Self.shadowMargin * 2 + Self.tailLength,
                height: surfaceSize.height + Self.shadowMargin * 2
            )
        case .automatic, .top, .bottom:
            return NSSize(
                width: surfaceSize.width + Self.shadowMargin * 2,
                height: surfaceSize.height + Self.shadowMargin * 2 + Self.tailLength
            )
        }
    }

    var surfaceFrame: NSRect {
        switch placement {
        case .top, .automatic:
            return NSRect(
                x: Self.shadowMargin,
                y: Self.shadowMargin + Self.tailLength,
                width: surfaceSize.width,
                height: surfaceSize.height
            )
        case .bottom:
            return NSRect(
                x: Self.shadowMargin,
                y: Self.shadowMargin,
                width: surfaceSize.width,
                height: surfaceSize.height
            )
        case .leading:
            return NSRect(
                x: Self.shadowMargin,
                y: Self.shadowMargin,
                width: surfaceSize.width,
                height: surfaceSize.height
            )
        case .trailing:
            return NSRect(
                x: Self.shadowMargin + Self.tailLength,
                y: Self.shadowMargin,
                width: surfaceSize.width,
                height: surfaceSize.height
            )
        }
    }

    init(
        content: NSView,
        surfaceSize: NSSize,
        placement: FluentTeachingTipPlacement,
        theme: FluentTheme
    ) {
        self.surfaceSize = surfaceSize
        self.placement = placement
        self.theme = theme
        super.init(frame: NSRect(origin: .zero, size: .zero))
        frame.size = panelSize
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowOpacity = 0.24
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Teaching tip")

        material.wantsLayer = true
        addSubview(material)
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.focusRingType = .none
        closeButton.toolTip = "Close"
        closeButton.setAccessibilityLabel("Close")
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(closeButton)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -44),
            content.topAnchor.constraint(equalTo: material.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -16),
            closeButton.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: material.topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        material.frame = surfaceFrame
        updateShadowPath()
    }

    override func draw(_ dirtyRect: NSRect) {
        let tail = tailPath()
        theme.micaTint.withAlphaComponent(theme.isDark ? 0.96 : 0.94).setFill()
        tail.fill()
        theme.controlStroke.setStroke()
        tail.lineWidth = 1
        tail.stroke()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc private func close() { onDismiss?() }

    private func applyTheme() {
        material.tintColor = theme.micaTint.withAlphaComponent(theme.isDark ? 0.88 : 0.78)
        material.layer?.cornerRadius = theme.designTokens.cardCornerRadius
        material.layer?.borderWidth = theme.controlStrokeWidth
        material.layer?.borderColor = theme.controlStroke.cgColor
        material.layer?.masksToBounds = true
        closeButton.contentTintColor = theme.textSecondary
        needsDisplay = true
    }

    private func tailPath() -> NSBezierPath {
        let surface = surfaceFrame
        let path = NSBezierPath()
        switch placement {
        case .automatic, .top:
            let center = min(max(tailOffset, surface.minX + 16), surface.maxX - 16)
            path.move(to: NSPoint(x: center - 8, y: surface.minY))
            path.line(to: NSPoint(x: center, y: Self.shadowMargin))
            path.line(to: NSPoint(x: center + 8, y: surface.minY))
        case .bottom:
            let center = min(max(tailOffset, surface.minX + 16), surface.maxX - 16)
            path.move(to: NSPoint(x: center - 8, y: surface.maxY))
            path.line(to: NSPoint(x: center, y: bounds.maxY - Self.shadowMargin))
            path.line(to: NSPoint(x: center + 8, y: surface.maxY))
        case .leading:
            let center = min(max(tailOffset, surface.minY + 16), surface.maxY - 16)
            path.move(to: NSPoint(x: surface.maxX, y: center - 8))
            path.line(to: NSPoint(x: bounds.maxX - Self.shadowMargin, y: center))
            path.line(to: NSPoint(x: surface.maxX, y: center + 8))
        case .trailing:
            let center = min(max(tailOffset, surface.minY + 16), surface.maxY - 16)
            path.move(to: NSPoint(x: surface.minX, y: center - 8))
            path.line(to: NSPoint(x: Self.shadowMargin, y: center))
            path.line(to: NSPoint(x: surface.minX, y: center + 8))
        }
        path.close()
        return path
    }

    private func updateShadowPath() {
        let path = NSBezierPath(
            roundedRect: surfaceFrame,
            xRadius: theme.designTokens.cardCornerRadius,
            yRadius: theme.designTokens.cardCornerRadius
        )
        path.append(tailPath())
        layer?.shadowPath = path.fluentCGPath
    }
}

private extension NSBezierPath {
    var fluentCGPath: CGPath {
        let result = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                result.move(to: points[0])
            case .lineTo:
                result.addLine(to: points[0])
            case .curveTo:
                result.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:
                result.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                result.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                result.closeSubpath()
            @unknown default:
                break
            }
        }
        return result
    }
}
