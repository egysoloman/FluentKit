import AppKit

/// Controls the preferred edge used by a Fluent popover. AppKit may flip the edge when the
/// preferred side cannot fit on the current screen.
public enum FluentPopoverPlacement: Hashable, Sendable {
    case automatic
    case top
    case bottom
    case leading
    case trailing
}

/// Mirrors NSPopover's native dismissal policies without exposing AppKit enum details in the
/// declarative API.
public enum FluentPopoverBehavior: Hashable, Sendable {
    case transient
    case semitransient
    case applicationDefined

    fileprivate var appKitBehavior: NSPopover.Behavior {
        switch self {
        case .transient: return .transient
        case .semitransient: return .semitransient
        case .applicationDefined: return .applicationDefined
        }
    }
}

private final class FluentPopoverSurfaceContainer: NSView {
    let material: FluentMaterialView
    var requestedSize: NSSize = .zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    init(material: FluentMaterialView, size: NSSize) {
        self.material = material
        requestedSize = size
        super.init(frame: .zero)
        addSubview(material)
        material.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { requestedSize }
}

private final class FluentPopoverContentController<Content: FluentView>: NSViewController {
    private let host: FluentViewHost<Content>
    private let surface: FluentPopoverSurfaceContainer
    private let material: FluentMaterialView
    private var content: Content

    init(content: Content, size: NSSize, context: FluentRenderContext) {
        self.content = content
        host = FluentViewHost(content, context: context)
        material = FluentMaterialView(material: context.theme.material(for: .transient) ?? .liquidGlass)
        surface = FluentPopoverSurfaceContainer(material: material, size: size)
        super.init(nibName: nil, bundle: nil)

        material.fluentTheme = context.theme
        material.isMaterialEnabled = context.theme.materialEffectsEnabled
        material.fallbackColor = context.theme.flyoutSurfaceFill
        material.identifier = NSUserInterfaceItemIdentifier("FluentKit.Popover.Content")
        material.setAccessibilityRole(.group)
        material.setAccessibilityLabel("Popover")
        surface.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            host.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            host.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
            host.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -16)
        ])
        surface.setFrameSize(size)
        view = surface
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = [.width, .height]
        preferredContentSize = size
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLayout() {
        super.viewDidLayout()
        if view.frame.size != preferredContentSize {
            view.setFrameSize(preferredContentSize)
        }
    }

    func update(content: Content, size: NSSize, context: FluentRenderContext) {
        self.content = content
        host.context = context
        host.update(content)
        material.fluentTheme = context.theme
        material.materialStyle = context.theme.material(for: .transient) ?? .liquidGlass
        material.isMaterialEnabled = context.theme.materialEffectsEnabled
        material.fallbackColor = context.theme.flyoutSurfaceFill
        surface.requestedSize = size
        surface.setFrameSize(size)
        preferredContentSize = size
    }
}

/// A button that presents FluentKit content in an NSPopover.
/// The popover is configured with macOS presentation semantics while its content is rendered by
/// FluentViewHost, so applications can use the same declarative view values in overlays.
public final class FluentPopoverButton<Content: FluentView>: NSButton, NSPopoverDelegate {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            needsDisplay = true
            updatePopoverContent()
        }
    }
    public var content: Content { didSet { updatePopoverContent() } }
    public var placement: FluentPopoverPlacement = .top { didSet { repositionPopover() } }
    public var behavior: FluentPopoverBehavior = .transient { didSet { popover?.behavior = behavior.appKitBehavior } }
    public var layoutDirection: FluentLayoutDirection = .system { didSet { repositionPopover() } }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet { popover?.animates = !reduceMotion }
    }

    private var popover: NSPopover?
    private let contentSize: NSSize

    public init(
        title: String = "More",
        contentSize: NSSize = NSSize(width: 280, height: 180),
        placement: FluentPopoverPlacement = .top,
        behavior: FluentPopoverBehavior = .transient,
        @FluentViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.contentSize = contentSize
        self.placement = placement
        self.behavior = behavior
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(ofSize: 13)
        focusRingType = .none
        target = self
        action = #selector(togglePopover)
        setAccessibilityRole(.button)
        setAccessibilityTitle(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        let padding = theme.controlPadding
        return NSSize(width: text.width + padding.left + padding.right, height: theme.controlHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: theme.buttonCornerRadius, yRadius: theme.buttonCornerRadius)
        theme.controlFill.setFill(); path.fill()
        theme.controlStroke.setStroke(); path.lineWidth = 1; path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: font as Any, .foregroundColor: theme.textPrimary]
        let text = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(in: NSRect(x: bounds.midX - text.width / 2, y: bounds.midY - text.height / 2 + 1, width: text.width, height: text.height), withAttributes: attrs)
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = behavior.appKitBehavior
        popover.animates = !reduceMotion
        popover.delegate = self
        popover.contentSize = contentSize
        popover.contentViewController = makeViewController()
        popover.show(relativeTo: bounds, of: self, preferredEdge: preferredEdge())
        self.popover = popover
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            popover?.performClose(nil)
        } else if event.keyCode == 36 || event.keyCode == 49 {
            togglePopover()
        } else {
            super.keyDown(with: event)
        }
    }

    func applyDeclarativeConfiguration(from source: FluentPopoverButton<Content>) {
        title = source.title
        font = source.font
        placement = source.placement
        behavior = source.behavior
        layoutDirection = source.layoutDirection
        reduceMotion = source.reduceMotion
        content = source.content
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    private func makeViewController() -> NSViewController {
        FluentPopoverContentController(
            content: content,
            size: contentSize,
            context: FluentRenderContext(theme: theme, layoutDirection: layoutDirection)
        )
    }

    private func updatePopoverContent() {
        guard let popover else { return }
        if let controller = popover.contentViewController as? FluentPopoverContentController<Content> {
            controller.update(
                content: content,
                size: contentSize,
                context: FluentRenderContext(theme: theme, layoutDirection: layoutDirection)
            )
        } else {
            popover.contentViewController = makeViewController()
        }
    }

    private func preferredEdge() -> NSRectEdge {
        switch placement {
        case .top: return .maxY
        case .bottom: return .minY
        case .leading: return layoutDirection.appKitValue == .rightToLeft ? .maxX : .minX
        case .trailing: return layoutDirection.appKitValue == .rightToLeft ? .minX : .maxX
        case .automatic: return .maxY
        }
    }

    private func repositionPopover() {
        guard let popover, popover.isShown, window != nil else { return }
        popover.show(relativeTo: bounds, of: self, preferredEdge: preferredEdge())
    }

    public func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        popover = nil
    }
}

/// A declarative popover attached to the wrapped content. The anchor remains mounted while the
/// native NSPopover is shown, and the binding is updated when AppKit dismisses the popover.
public struct FluentPopover<Content: FluentView, PopoverContent: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let popoverContent: PopoverContent
    private let isPresented: FluentBinding<Bool>
    private let placement: FluentPopoverPlacement
    private let size: NSSize
    private let behavior: FluentPopoverBehavior
    private let onDismiss: () -> Void

    public init(
        isPresented: FluentBinding<Bool>,
        placement: FluentPopoverPlacement = .automatic,
        size: NSSize = NSSize(width: 280, height: 180),
        behavior: FluentPopoverBehavior = .transient,
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder popover: () -> PopoverContent
    ) {
        self.content = content()
        self.popoverContent = popover()
        self.isPresented = isPresented
        self.placement = placement
        self.size = NSSize(width: max(size.width, 120), height: max(size.height, 80))
        self.behavior = behavior
        self.onDismiss = onDismiss
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentPopoverHost<Content, PopoverContent>(
            content: content._mount(in: context),
            popoverContent: popoverContent,
            binding: isPresented,
            placement: placement,
            size: size,
            behavior: behavior,
            onDismiss: onDismiss,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentPopoverHost<Content, PopoverContent> else { return false }
        host.update(
            binding: isPresented,
            popoverContent: popoverContent,
            placement: placement,
            size: size,
            behavior: behavior,
            onDismiss: onDismiss,
            context: context
        )
        host.updateContent(
            using: { nativeView, updateContext in content._update(nativeView, in: updateContext) },
            make: { content._mount(in: context) }
        )
        return true
    }
}

private final class FluentPopoverHost<Content: FluentView, PopoverContent: FluentView>: NSView, NSPopoverDelegate {
    private var binding: FluentBinding<Bool>
    private var popoverContent: PopoverContent
    private var placement: FluentPopoverPlacement
    private var size: NSSize
    private var behavior: FluentPopoverBehavior
    private var onDismiss: () -> Void
    private var context: FluentRenderContext
    private var observerID: UUID?
    private var popover: NSPopover?
    private var contentController: FluentPopoverContentController<PopoverContent>?
    private var closingPopover: NSPopover?
    private var programmaticClosingPopover: NSPopover?
    private var hostRemovalClosingPopover: NSPopover?
    private var replacingForGeometry = false
    private weak var focusedView: NSView?

    init(
        content: NSView,
        popoverContent: PopoverContent,
        binding: FluentBinding<Bool>,
        placement: FluentPopoverPlacement,
        size: NSSize,
        behavior: FluentPopoverBehavior,
        onDismiss: @escaping () -> Void,
        context: FluentRenderContext
    ) {
        self.binding = binding
        self.popoverContent = popoverContent
        self.placement = placement
        self.size = size
        self.behavior = behavior
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
        if window == nil {
            closePopover(programmatic: true, becauseHostWasRemoved: true)
            return
        }
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    override func layout() {
        super.layout()
        popover?.positioningRect = bounds
    }

    func update(
        binding: FluentBinding<Bool>,
        popoverContent: PopoverContent,
        placement: FluentPopoverPlacement,
        size: NSSize,
        behavior: FluentPopoverBehavior,
        onDismiss: @escaping () -> Void,
        context: FluentRenderContext
    ) {
        let previousSize = self.size
        let reusesObservation = self.binding.observationIdentity != nil
            && self.binding.observationIdentity == binding.observationIdentity
        if !reusesObservation, let observerID { self.binding.removeObserver?(observerID) }
        self.binding = binding
        self.popoverContent = popoverContent
        self.placement = placement
        self.size = NSSize(width: max(size.width, 120), height: max(size.height, 80))
        self.behavior = behavior
        self.onDismiss = onDismiss
        self.context = context
        if !reusesObservation { installObserver() }
        if previousSize != self.size, popover?.isShown == true {
            replacingForGeometry = true
            closePopover(programmatic: true, becauseHostWasRemoved: false)
            return
        }
        contentController?.update(content: popoverContent, size: self.size, context: context)
        if let popover {
            popover.behavior = behavior.appKitBehavior
            popover.animates = !context.reduceMotion
            popover.positioningRect = bounds
            if let window, popover.isShown {
                let animates = popover.animates
                popover.animates = false
                popover.show(relativeTo: bounds, of: self, preferredEdge: preferredEdge(for: window))
                popover.animates = animates
            }
            applyContentSize(to: popover)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak popover] in
                guard let self, let popover else { return }
                self.applyContentSize(to: popover)
            }
        }
        synchronizePresentation()
    }

    func updateContent(using update: @escaping (NSView, FluentRenderContext) -> Bool, make: @escaping () -> NSView) {
        guard let current = subviews.first else { return }
        if !update(current, context) {
            current.removeFromSuperview()
            let replacement = make()
            addSubview(replacement)
            replacement.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                replacement.leadingAnchor.constraint(equalTo: leadingAnchor),
                replacement.trailingAnchor.constraint(equalTo: trailingAnchor),
                replacement.topAnchor.constraint(equalTo: topAnchor),
                replacement.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func installObserver() {
        observerID = binding.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func synchronizePresentation() {
        guard window != nil else { return }
        if binding.get() {
            if let popover, popover.isShown {
                popover.positioningRect = bounds
                return
            }
            if popover != nil { return }
            presentPopover()
        } else {
            closePopover(programmatic: true, becauseHostWasRemoved: false)
        }
    }

    private func presentPopover() {
        guard let window else { return }
        let controller = FluentPopoverContentController(content: popoverContent, size: size, context: context)
        let popover = NSPopover()
        popover.behavior = behavior.appKitBehavior
        popover.animates = !context.reduceMotion
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = size
        self.contentController = controller
        self.popover = popover
        focusedView = window.firstResponder as? NSView
        popover.show(relativeTo: bounds, of: self, preferredEdge: preferredEdge(for: window))
        let animates = popover.animates
        popover.animates = false
        popover.show(relativeTo: bounds, of: self, preferredEdge: preferredEdge(for: window))
        popover.animates = animates
        applyContentSize(to: popover)
        DispatchQueue.main.async { [weak self, weak popover] in
            guard let self, let popover else { return }
            self.applyContentSize(to: popover)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak popover] in
            guard let self, let popover else { return }
            self.applyContentSize(to: popover)
        }
    }

    private func applyContentSize(to popover: NSPopover) {
        if let contentController { popover.contentViewController = contentController }
        popover.contentSize = size
        contentController?.view.setFrameSize(size)
        contentController?.view.translatesAutoresizingMaskIntoConstraints = true
        contentController?.view.autoresizingMask = [.width, .height]
        if let window = contentController?.view.window {
            window.contentMinSize = size
            window.setContentSize(size)
            window.contentView?.setFrameSize(size)
            contentController?.view.setFrameSize(window.contentView?.bounds.size ?? size)
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func closePopover(programmatic: Bool, becauseHostWasRemoved: Bool) {
        guard let popover else { return }
        if closingPopover === popover {
            if becauseHostWasRemoved { hostRemovalClosingPopover = popover }
            return
        }
        closingPopover = popover
        if programmatic { programmaticClosingPopover = popover }
        if becauseHostWasRemoved { hostRemovalClosingPopover = popover }
        popover.animates = !context.reduceMotion
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.close()
        }
        DispatchQueue.main.async { [weak self, weak popover] in
            guard let self, let popover, !popover.isShown else { return }
            self.finishPopoverClose(popover)
        }
    }

    private func preferredEdge(for window: NSWindow) -> NSRectEdge {
        switch placement {
        case .top: return .maxY
        case .bottom: return .minY
        case .leading:
            return context.layoutDirection.appKitValue == .rightToLeft ? .maxX : .minX
        case .trailing:
            return context.layoutDirection.appKitValue == .rightToLeft ? .minX : .maxX
        case .automatic:
            return automaticEdge(for: window)
        }
    }

    private func automaticEdge(for window: NSWindow) -> NSRectEdge {
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let requiredVertical = size.height + 12
        let requiredHorizontal = size.width + 12
        if anchor.minY - visible.minY >= requiredVertical { return .minY }
        if visible.maxY - anchor.maxY >= requiredVertical { return .maxY }
        if visible.maxX - anchor.maxX >= requiredHorizontal { return .maxX }
        if anchor.minX - visible.minX >= requiredHorizontal { return .minX }
        return (anchor.minY - visible.minY) >= (visible.maxY - anchor.maxY) ? .minY : .maxY
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover,
              closedPopover === popover || closedPopover === closingPopover else { return }
        finishPopoverClose(closedPopover)
    }

    private func finishPopoverClose(_ closedPopover: NSPopover) {
        guard closedPopover === popover || closedPopover === closingPopover else { return }
        let wasProgrammatic = programmaticClosingPopover === closedPopover
        let wasHostRemoval = hostRemovalClosingPopover === closedPopover
        let wasGeometryReplacement = replacingForGeometry && !wasHostRemoval
        if popover === closedPopover {
            popover = nil
            contentController = nil
        }
        closingPopover = nil
        programmaticClosingPopover = nil
        hostRemovalClosingPopover = nil
        restoreFocus()
        if wasGeometryReplacement {
            replacingForGeometry = false
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
            return
        }
        if wasHostRemoval {
            if binding.get() { binding.set(false) }
            onDismiss()
            return
        }
        if !wasProgrammatic, binding.get() { binding.set(false) }
        onDismiss()
        if binding.get() {
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func restoreFocus() {
        guard let window, let focusedView, focusedView.window === window else { return }
        window.makeFirstResponder(focusedView)
    }

    deinit {
        if let observerID { binding.removeObserver?(observerID) }
        popover?.close()
    }
}

public extension FluentView {
    /// Presents a native NSPopover while keeping both the anchor and popover content declarative.
    func popover<PopoverContent: FluentView>(
        isPresented: FluentBinding<Bool>,
        placement: FluentPopoverPlacement = .automatic,
        size: NSSize = NSSize(width: 280, height: 180),
        behavior: FluentPopoverBehavior = .transient,
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder popover: @escaping () -> PopoverContent
    ) -> FluentPopover<Self, PopoverContent> {
        FluentPopover(
            isPresented: isPresented,
            placement: placement,
            size: size,
            behavior: behavior,
            onDismiss: onDismiss,
            content: { self },
            popover: popover
        )
    }
}

/// A declarative sheet presenter. The wrapped content remains mounted while the sheet is shown,
/// and changing the binding presents or dismisses the native sheet window.
public struct FluentSheet<Content: FluentView, SheetContent: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let sheetContent: SheetContent
    private let isPresented: FluentBinding<Bool>
    private let title: String
    private let size: NSSize
    private let onDismiss: () -> Void

    public init(
        isPresented: FluentBinding<Bool>,
        title: String = "",
        size: NSSize = NSSize(width: 520, height: 360),
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder sheet: () -> SheetContent
    ) {
        self.content = content()
        self.sheetContent = sheet()
        self.isPresented = isPresented
        self.title = title
        self.size = NSSize(width: max(size.width, 240), height: max(size.height, 180))
        self.onDismiss = onDismiss
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentSheetHost(
            content: content._mount(in: context),
            sheetContent: sheetContent,
            binding: isPresented,
            title: title,
            size: size,
            onDismiss: onDismiss,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSheetHost<SheetContent> else { return false }
        host.update(binding: isPresented, sheetContent: sheetContent, title: title, size: size, onDismiss: onDismiss, context: context)
        host.updateContent(
            using: { nativeView, updateContext in content._update(nativeView, in: updateContext) },
            make: { content._mount(in: context) }
        )
        return true
    }
}

private final class FluentSheetHost<SheetContent: FluentView>: NSView {
    private var sheetContent: SheetContent
    private var updateContent: (NSView, FluentRenderContext) -> Bool
    private var binding: FluentBinding<Bool>
    private var title: String
    private var size: NSSize
    private var onDismiss: () -> Void
    private var context: FluentRenderContext
    private weak var sheetWindow: NSWindow?
    private var sheetController: FluentSheetWindowController<SheetContent>?
    private var observerID: UUID?
    private var updatePresentedContent: ((SheetContent, FluentRenderContext) -> Void)?
    private weak var presentationCoordinator: FluentPresentationCoordinator?
    private var presentationToken: FluentPresentationCoordinator.Token?
    private var programmaticDismissalToken: FluentPresentationCoordinator.Token?

    init(content: NSView, sheetContent: SheetContent, binding: FluentBinding<Bool>, title: String, size: NSSize, onDismiss: @escaping () -> Void, context: FluentRenderContext) {
        self.sheetContent = sheetContent
        self.updateContent = { _, _ in false }
        self.binding = binding
        self.title = title
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
        installBindingObserver()
        DispatchQueue.main.async { [weak self] in self?.syncPresentation() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelPresentation()
            return
        }
        DispatchQueue.main.async { [weak self] in self?.syncPresentation() }
    }

    func update(binding: FluentBinding<Bool>, sheetContent: SheetContent, title: String, size: NSSize, onDismiss: @escaping () -> Void, context: FluentRenderContext) {
        let reusesObservation = self.binding.observationIdentity != nil
            && self.binding.observationIdentity == binding.observationIdentity
        if !reusesObservation, let observerID { self.binding.removeObserver?(observerID) }
        self.binding = binding
        self.sheetContent = sheetContent
        self.title = title
        self.size = size
        self.onDismiss = onDismiss
        self.context = context
        if !reusesObservation { installBindingObserver() }
        updatePresentedContent?(sheetContent, context)
        syncPresentation()
    }

    func updateContent(using update: @escaping (NSView, FluentRenderContext) -> Bool, make: @escaping () -> NSView) {
        self.updateContent = update
        guard let current = subviews.first else { return }
        if !update(current, context) {
            current.removeFromSuperview()
            let replacement = make()
            addSubview(replacement)
            replacement.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                replacement.leadingAnchor.constraint(equalTo: leadingAnchor),
                replacement.trailingAnchor.constraint(equalTo: trailingAnchor),
                replacement.topAnchor.constraint(equalTo: topAnchor),
                replacement.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func installBindingObserver() {
        observerID = binding.observe? { [weak self] _ in
            DispatchQueue.main.async { self?.syncPresentation() }
        }
    }

    private func syncPresentation() {
        guard let parentWindow = window else {
            cancelPresentation()
            return
        }
        if binding.get() {
            if presentationToken != nil {
                updatePresentedContent?(sheetContent, context)
                sheetController?.update(title: title, size: size, context: context)
                return
            }

            let coordinator = FluentPresentationCoordinator.coordinator(for: parentWindow)
            presentationCoordinator = coordinator
            presentationToken = coordinator.enqueue(
                owner: self,
                present: { [weak self, weak parentWindow] in
                    guard let self, let parentWindow else { return }
                    self.beginPresentation(on: parentWindow)
                },
                cancel: { [weak self] in self?.endPresentationForCancellation() }
            )
        } else {
            cancelPresentation()
        }
    }

    private func beginPresentation(on parentWindow: NSWindow) {
        guard let token = presentationToken else { return }
        guard binding.get() else {
            presentationCoordinator?.finish(token)
            presentationToken = nil
            return
        }
        let controller = FluentSheetWindowController(content: sheetContent, title: title, size: size, context: context)
        sheetController = controller
        sheetWindow = controller.window
        updatePresentedContent = { [weak controller] content, context in
            controller?.update(content: content, context: context)
        }
        guard let sheetWindow else {
            presentationCoordinator?.finish(token)
            presentationToken = nil
            return
        }
        let coordinator = presentationCoordinator
        let dismissal = onDismiss
        parentWindow.beginSheet(sheetWindow) { [weak self, coordinator, dismissal] _ in
            coordinator?.finish(token)
            dismissal()
            guard let self else { return }
            let wasProgrammatic = self.programmaticDismissalToken === token
            if wasProgrammatic { self.programmaticDismissalToken = nil }
            guard self.presentationToken === token else { return }
            self.presentationToken = nil
            self.sheetWindow = nil
            self.sheetController = nil
            self.updatePresentedContent = nil
            if !wasProgrammatic, self.binding.get() { self.binding.set(false) }
        }
        controller.applyRequestedSize()
    }

    private func endPresentationForCancellation() {
        guard let token = presentationToken else { return }
        programmaticDismissalToken = token
        if let sheetWindow, let parentWindow = window ?? sheetWindow.sheetParent {
            parentWindow.endSheet(sheetWindow, returnCode: .cancel)
        } else {
            presentationCoordinator?.finish(token)
        }
        // Release this host's ownership immediately. The old native completion still owns the
        // coordinator slot and will only finish the matching token.
        presentationToken = nil
    }

    private func cancelPresentation() {
        guard let token = presentationToken else { return }
        presentationCoordinator?.cancel(token)
        if presentationToken === token { presentationToken = nil }
    }

    deinit {
        if let observerID { binding.removeObserver?(observerID) }
        if let token = presentationToken { presentationCoordinator?.cancel(token) }
    }
}

private final class FluentSheetWindowController<Content: FluentView>: NSWindowController {
    private let host: FluentViewHost<Content>
    private let material: FluentMaterialView
    private var requestedSize: NSSize
    private let widthConstraint: NSLayoutConstraint
    private let heightConstraint: NSLayoutConstraint

    init(content: Content, title: String, size: NSSize, context: FluentRenderContext) {
        requestedSize = size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.contentMinSize = size
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        let material = FluentMaterialView(material: context.theme.material(for: .transient) ?? .liquidGlass)
        material.fluentTheme = context.theme
        material.isMaterialEnabled = context.theme.materialEffectsEnabled
        material.fallbackColor = context.theme.windowBackground
        host = FluentViewHost(content, context: context)
        self.material = material
        widthConstraint = material.widthAnchor.constraint(equalToConstant: size.width)
        heightConstraint = material.heightAnchor.constraint(equalToConstant: size.height)
        material.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 28),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -28),
            host.topAnchor.constraint(equalTo: material.topAnchor, constant: 24),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -24),
            widthConstraint,
            heightConstraint
        ])
        window.contentView = material
        super.init(window: window)
    }

    func update(content: Content, context: FluentRenderContext) {
        host.context = context
        host.update(content)
        apply(context: context)
    }

    func update(title: String, size: NSSize, context: FluentRenderContext) {
        requestedSize = size
        window?.title = title
        applyRequestedSize()
        apply(context: context)
    }

    func applyRequestedSize() {
        guard let window else { return }
        widthConstraint.constant = requestedSize.width
        heightConstraint.constant = requestedSize.height
        window.contentMinSize = requestedSize
        window.setContentSize(requestedSize)
    }

    private func apply(context: FluentRenderContext) {
        window?.appearance = fluentAppKitAppearance(for: context.theme)
        material.fluentTheme = context.theme
        material.materialStyle = context.theme.material(for: .transient) ?? .liquidGlass
        material.isMaterialEnabled = context.theme.materialEffectsEnabled
        material.fallbackColor = context.theme.windowBackground
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

public extension FluentView {
    /// Presents custom Fluent content as a native document-modal sheet.
    func sheet<SheetContent: FluentView>(
        isPresented: FluentBinding<Bool>,
        title: String = "",
        size: NSSize = NSSize(width: 520, height: 360),
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder sheet: @escaping () -> SheetContent
    ) -> FluentSheet<Self, SheetContent> {
        FluentSheet(
            isPresented: isPresented,
            title: title,
            size: size,
            onDismiss: onDismiss,
            content: { self },
            sheet: sheet
        )
    }
}

/// Presents a Fluent-styled alert window and writes the selected response into the binding.
public struct FluentAlert: FluentPrimitiveView {
    private let title: String
    private let message: String
    private let buttons: [String]
    private let selection: FluentBinding<Int>?

    public init(title: String, message: String, buttons: [String] = ["OK"], selection: FluentBinding<Int>? = nil) {
        self.title = title
        self.message = message
        self.buttons = buttons.isEmpty ? ["OK"] : buttons
        self.selection = selection
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentAlertHost(title: title, message: message, buttons: buttons, selection: selection)
    }
}

private final class FluentAlertHost: NSView {
    private let alertTitle: String
    private let message: String
    private let buttons: [String]
    private let selection: FluentBinding<Int>?
    private weak var presentationCoordinator: FluentPresentationCoordinator?
    private var presentationToken: FluentPresentationCoordinator.Token?
    private var alertToken: FluentPresentationCoordinator.Token?
    private var alert: NSAlert?
    private var hasRequestedPresentation = false

    init(title: String, message: String, buttons: [String], selection: FluentBinding<Int>?) {
        alertTitle = title
        self.message = message
        self.buttons = buttons
        self.selection = selection
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelPresentation()
            return
        }
        DispatchQueue.main.async { [weak self] in self?.requestPresentation() }
    }

    private func requestPresentation() {
        guard !hasRequestedPresentation, let window else { return }
        hasRequestedPresentation = true
        let coordinator = FluentPresentationCoordinator.coordinator(for: window)
        presentationCoordinator = coordinator
        presentationToken = coordinator.enqueue(
            owner: self,
            present: { [weak self, weak window] in
                guard let self, let window else { return }
                self.beginPresentation(on: window)
            },
            cancel: { [weak self] in self?.endPresentationForCancellation() }
        )
    }

    private func beginPresentation(on window: NSWindow) {
        guard let token = presentationToken else { return }
        let alert = NSAlert()
        alert.messageText = alertTitle
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        self.alert = alert
        alertToken = token
        let coordinator = presentationCoordinator
        alert.beginSheetModal(for: window) { [weak self, coordinator] response in
            coordinator?.finish(token)
            guard let self else { return }
            if self.alertToken === token {
                self.alertToken = nil
                self.alert = nil
            }
            guard self.presentationToken === token else { return }
            self.presentationToken = nil
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if index >= 0, index < self.buttons.count { self.selection?.set(index) }
        }
    }

    private func cancelPresentation() {
        guard let token = presentationToken else { return }
        presentationCoordinator?.cancel(token)
        if presentationToken === token { presentationToken = nil }
    }

    private func endPresentationForCancellation() {
        guard let token = presentationToken else { return }
        if let alert, alertToken === token, let parent = window ?? alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .cancel)
        } else {
            presentationCoordinator?.finish(token)
        }
    }

    deinit {
        if let token = presentationToken { presentationCoordinator?.cancel(token) }
    }
}
