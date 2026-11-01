import AppKit

/// The preferred side of a ToolTip. `.automatic` uses WinUI's default top placement; pointer
/// activation docks to the pointer while keyboard activation docks to the target.
public enum FluentToolTipPlacement: Hashable, Sendable {
    case automatic
    /// WinUI's `PlacementMode.Mouse`: show below the pointer bounding rectangle rather than on a
    /// directional side of the target.
    case mouse
    case top
    case bottom
    case left
    case right
}

/// Optional presentation behavior. Continuous motion is a FluentKit extension, not a WinUI default.
public enum FluentToolTipMotion: Hashable, Sendable {
    case standard
    /// Move one visible surface between pointer targets in the same window. Placement is captured
    /// on activation; movement inside a target does not chase the pointer. Honors reduced motion.
    case continuous
}

/// WinUI default/fallback timing and geometry. Windows reads the actual fade timing, pointer
/// hover interval, and display duration from system theme parameters; AppKit does not expose
/// direct equivalents, so FluentKit uses the same documented fallback values.
enum FluentToolTipMetrics {
    static let normalPointerDelay: TimeInterval = 0.8
    static let reshowPointerDelay: TimeInterval = 0.6
    static let keyboardDelay: TimeInterval = 0.8
    static let betweenShowDelay: TimeInterval = 0.2
    static let showDuration: TimeInterval = 5
    static let fadeDuration: TimeInterval = 0.083
    static let mouseOffset: CGFloat = 20
    static let keyboardOffset: CGFloat = 12
    static let screenTolerance: CGFloat = 2
    static let maximumWidth: CGFloat = 320
    static let padding = NSEdgeInsets(top: 6, left: 9, bottom: 8, right: 9)
    static let continuousMoveDuration: TimeInterval = 0.22
    static let continuousFadeDuration: TimeInterval = 0.18
    static let continuousExitDelay: TimeInterval = 0.12
}

/// The WinUI default ToolTip text presenter: 12pt, wrapping, and constrained to 320pt including
/// the template padding.
public struct FluentToolTipText: FluentUpdatablePrimitiveView {
    public let value: String

    public init(_ value: String) { self.value = value }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let label = NSTextField(wrappingLabelWithString: value)
        configure(label, context: context)
        return label
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let label = view as? NSTextField else { return false }
        label.stringValue = value
        configure(label, context: context)
        return true
    }

    private func configure(_ label: NSTextField, context: FluentRenderContext) {
        label.font = .systemFont(ofSize: 12)
        label.textColor = context.theme.textPrimary
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setAccessibilityRole(.staticText)
    }
}

/// Attaches an automatic WinUI-style ToolTip to declarative content without replacing the
/// mounted anchor. Pointer and keyboard focus share one application-wide presenter.
public struct FluentToolTip<Content: FluentView, ToolTipContent: FluentView>: FluentUpdatablePrimitiveView {
    let content: Content
    let toolTipContent: ToolTipContent
    let placement: FluentToolTipPlacement
    let isEnabled: Bool
    let accessibilityText: String?
    let motion: FluentToolTipMotion

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentToolTipHost(
            contentView: content._mount(in: context),
            toolTipView: toolTipContent._mount(in: context),
            placement: placement,
            isEnabled: isEnabled,
            accessibilityText: accessibilityText,
            context: context,
            motion: motion
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentToolTipHost else { return false }
        guard content._update(host.contentView, in: context) else { return false }

        var resolvedToolTipView = host.toolTipView
        if !toolTipContent._update(resolvedToolTipView, in: context) {
            resolvedToolTipView = toolTipContent._mount(in: context)
        }
        host.update(
            toolTipView: resolvedToolTipView,
            placement: placement,
            isEnabled: isEnabled,
            accessibilityText: accessibilityText,
            context: context,
            motion: motion
        )
        return true
    }
}

public extension FluentView {
    /// Adds a text ToolTip with WinUI's default delay, duration, wrapping, and placement behavior.
    func toolTip(
        _ text: String,
        placement: FluentToolTipPlacement = .automatic,
        isEnabled: Bool = true,
        motion: FluentToolTipMotion = .standard
    ) -> FluentToolTip<Self, FluentToolTipText> {
        FluentToolTip(
            content: self,
            toolTipContent: FluentToolTipText(text),
            placement: placement,
            isEnabled: isEnabled,
            accessibilityText: text,
            motion: motion
        )
    }

    /// Adds a ToolTip whose content is rendered by FluentKit. Supply `accessibilityText` when the
    /// visual content is not self-describing so the hidden anchor still exposes help to VoiceOver.
    func toolTip<ToolTipContent: FluentView>(
        placement: FluentToolTipPlacement = .automatic,
        isEnabled: Bool = true,
        accessibilityText: String? = nil,
        motion: FluentToolTipMotion = .standard,
        @FluentViewBuilder content: () -> ToolTipContent
    ) -> FluentToolTip<Self, ToolTipContent> {
        FluentToolTip(
            content: self,
            toolTipContent: content(),
            placement: placement,
            isEnabled: isEnabled,
            accessibilityText: accessibilityText,
            motion: motion
        )
    }
}

private enum FluentToolTipInputMode {
    case pointer
    case keyboard
}

private final class FluentToolTipCoordinator {
    static let shared = FluentToolTipCoordinator()
    weak var current: FluentToolTipHost?
    weak var pending: FluentToolTipHost?
    var lastClosedAt = Date.distantPast

    func claim(_ host: FluentToolTipHost) -> FluentToolTipPresentation? {
        guard current !== host else { return nil }
        let reused = host.canContinuePresentation(from: current) ? current?.releasePresentation() : nil
        // WinUI force-finishes a closing ToolTip before opening the next automatic one so two
        // transient surfaces never overlap during the hand-off.
        if reused == nil { current?.dismiss(animated: false) }
        current = host
        if pending === host { pending = nil }
        return reused
    }

    func prepare(_ host: FluentToolTipHost) {
        guard pending !== host else { return }
        pending?.cancelScheduledOpen()
        if current !== host, !host.canContinuePresentation(from: current) { current?.dismiss(animated: false) }
        pending = host
    }

    func cancelPending(_ host: FluentToolTipHost) {
        if pending === host { pending = nil }
    }

    func noteClosing(_ host: FluentToolTipHost) {
        guard current === host else { return }
        lastClosedAt = Date()
    }

    func relinquish(_ host: FluentToolTipHost, recordClose: Bool = true) {
        if pending === host { pending = nil }
        guard current === host else { return }
        current = nil
        if recordClose { lastClosedAt = Date() }
    }
}

final class FluentToolTipHost: NSView {
    let contentView: NSView
    private(set) var toolTipView: NSView
    private var placement: FluentToolTipPlacement
    private var isEnabled: Bool
    private var accessibilityText: String?
    private var context: FluentRenderContext
    private var trackingAreaReference: NSTrackingArea?
    private var firstResponderObservation: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var localKeyMonitor: Any?
    private var openWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private var pointerExitWorkItem: DispatchWorkItem?
    private var presentation: FluentToolTipPresentation?
    private var panel: FluentToolTipPanel? { presentation?.panel }
    private var surface: FluentToolTipSurface? { presentation?.surface }
    private var motion: FluentToolTipMotion
    private var openGeneration: UInt64 = 0
    private var presentationGeneration: UInt64 = 0
    private var attachmentGeneration: UInt64 = 0
    private var isClosing = false
    private var inputMode: FluentToolTipInputMode = .pointer
    private var pointerScreenPoint: NSPoint?
    private var presentationPointerPoint: NSPoint?
    private var pointerInside = false
    private var focusedInside = false
    private var anchorFrameAtPresentation: NSRect?
    private var inheritedAccessibilityHelp: String?
    private var lastAppliedAccessibilityHelp: String?

    init(
        contentView: NSView,
        toolTipView: NSView,
        placement: FluentToolTipPlacement,
        isEnabled: Bool,
        accessibilityText: String?,
        context: FluentRenderContext,
        motion: FluentToolTipMotion = .standard
    ) {
        self.contentView = contentView
        self.toolTipView = toolTipView
        self.placement = placement
        self.isEnabled = isEnabled
        self.accessibilityText = accessibilityText
        self.context = context
        self.motion = motion
        super.init(frame: .zero)
        _ = FluentFocusVisibility.isKeyboardInteraction(in: nil)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ToolTip.Anchor")
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        inheritedAccessibilityHelp = contentView.accessibilityHelp()
        applyAccessibilityHelp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
        attachmentGeneration &+= 1
        if window == nil, presentation != nil, motion == .continuous {
            // AppKit briefly detaches titlebar accessories while changing appearance. Give a
            // same-window reattachment this main-loop turn; real removal still closes promptly.
            cancelScheduledOpen()
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attachmentGeneration == generation else { return }
                if self.window == nil { self.dismiss(animated: false) }
            }
            return
        }
        if window == nil || panel?.parent !== window { dismiss(animated: false) }
    }

    override func viewDidHide() {
        super.viewDidHide()
        dismiss(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        cancelPointerExit()
        pointerScreenPoint = screenPoint(for: event)
        scheduleOpen(mode: .pointer)
    }

    override func mouseMoved(with event: NSEvent) {
        pointerScreenPoint = screenPoint(for: event)
        if panel != nil { evaluateSafeZone(at: pointerScreenPoint) }
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        cancelScheduledOpen()
        guard panel != nil else { return }
        evaluateSafeZone(at: screenPoint(for: event))
    }

    override func layout() {
        super.layout()
        guard panel != nil,
              let initial = anchorFrameAtPresentation,
              let current = anchorScreenFrame,
              !initial.nearlyEquals(current) else { return }
        dismiss(animated: true)
    }

    func update(
        toolTipView newToolTipView: NSView,
        placement: FluentToolTipPlacement,
        isEnabled: Bool,
        accessibilityText: String?,
        context: FluentRenderContext,
        motion: FluentToolTipMotion = .standard
    ) {
        let replaced = toolTipView !== newToolTipView
        if replaced {
            // The surface captures outgoing content before detaching it.
            if presentation == nil { toolTipView.removeFromSuperview() }
            toolTipView = newToolTipView
        }
        self.placement = placement
        self.isEnabled = isEnabled
        self.accessibilityText = accessibilityText
        self.context = context
        self.motion = motion
        applyAccessibilityHelp()
        guard isEnabled else {
            dismiss(animated: false)
            return
        }
        if presentation != nil, !isClosing { refreshOpenPanel(replacingContent: replaced) }
    }

    func dismiss(animated: Bool) {
        cancelScheduledOpen()
        cancelPointerExit()
        closeWorkItem?.cancel()
        closeWorkItem = nil
        removeTransientMonitors()
        guard let presentation else {
            FluentToolTipCoordinator.shared.relinquish(self)
            return
        }
        isClosing = true
        presentationGeneration &+= 1
        let generation = presentationGeneration
        FluentToolTipCoordinator.shared.noteClosing(self)
        presentation.fade(to: 0, motion: motion, reduceMotion: context.reduceMotion, animated: animated) { [weak self, weak presentation] in
            guard let self, let presentation, self.presentation === presentation,
                  self.presentationGeneration == generation else { return }
            presentation.close()
            self.presentation = nil
            self.isClosing = false
            FluentToolTipCoordinator.shared.relinquish(self, recordClose: false)
        }
    }

    fileprivate func canContinuePresentation(from other: FluentToolTipHost?) -> Bool {
        guard let other, motion == .continuous, other.motion == .continuous,
              inputMode == .pointer, other.inputMode == .pointer,
              let window, other.window === window,
              other.panel?.isVisible == true else { return false }
        return true
    }

    fileprivate func releasePresentation() -> FluentToolTipPresentation? {
        cancelScheduledOpen()
        cancelPointerExit()
        closeWorkItem?.cancel()
        closeWorkItem = nil
        removeTransientMonitors()
        presentationGeneration &+= 1
        let result = presentation
        presentation = nil
        isClosing = false
        return result
    }

    func cancelScheduledOpen() {
        openGeneration &+= 1
        openWorkItem?.cancel()
        openWorkItem = nil
        FluentToolTipCoordinator.shared.cancelPending(self)
    }

    private func scheduleOpen(mode: FluentToolTipInputMode) {
        guard isEnabled, window?.isVisible == true, !isHiddenOrHasHiddenAncestor else { return }
        inputMode = mode
        if presentation != nil {
            if isClosing, motion == .continuous, mode == .pointer { present(mode: mode) }
            return
        }
        cancelScheduledOpen()
        let coordinator = FluentToolTipCoordinator.shared
        if canContinuePresentation(from: coordinator.current) {
            present(mode: mode)
            return
        }
        coordinator.prepare(self)
        let delay: TimeInterval
        switch mode {
        case .keyboard:
            delay = FluentToolTipMetrics.keyboardDelay
        case .pointer:
            let elapsed = Date().timeIntervalSince(coordinator.lastClosedAt)
            delay = elapsed < FluentToolTipMetrics.betweenShowDelay
                ? FluentToolTipMetrics.reshowPointerDelay
                : FluentToolTipMetrics.normalPointerDelay
        }
        let generation = openGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.openGeneration == generation,
                  self.isEnabled, !self.isHiddenOrHasHiddenAncestor,
                  (mode == .pointer ? self.pointerInside : self.focusedInside) else { return }
            self.present(mode: mode)
        }
        openWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func present(mode: FluentToolTipInputMode) {
        guard let ownerWindow = window, ownerWindow.isVisible, !ownerWindow.isMiniaturized else { return }
        cancelScheduledOpen()
        cancelPointerExit()
        closeWorkItem?.cancel()
        inputMode = mode
        let reused = FluentToolTipCoordinator.shared.claim(self) ?? presentation
        let presentation = reused ?? FluentToolTipPresentation(content: toolTipView, context: context)
        self.presentation = presentation
        presentationGeneration &+= 1
        isClosing = false
        presentationPointerPoint = pointerScreenPoint
        let animate = motion == .continuous && mode == .pointer && !context.reduceMotion
        presentation.surface.replaceContent(with: toolTipView, animated: animate)
        presentation.surface.update(context: context)
        let size = presentation.surface.measure(maximumHeight: maximumContentHeight(for: mode))
        let frame = NSRect(origin: resolvedOrigin(for: size, mode: mode), size: size)
        presentation.show(in: ownerWindow, frame: frame, motion: motion,
                          animateGeometry: animate, reduceMotion: context.reduceMotion)
        anchorFrameAtPresentation = anchorScreenFrame
        installTransientMonitors()

        let generation = presentationGeneration
        let close = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.dismiss(animated: true)
        }
        closeWorkItem = close
        DispatchQueue.main.asyncAfter(deadline: .now() + FluentToolTipMetrics.showDuration, execute: close)
    }

    private func refreshOpenPanel(replacingContent: Bool) {
        guard let presentation else { return }
        let animate = motion == .continuous && inputMode == .pointer && !context.reduceMotion
        if replacingContent { presentation.surface.replaceContent(with: toolTipView, animated: animate) }
        presentation.surface.update(context: context)
        let size = presentation.surface.measure(maximumHeight: maximumContentHeight(for: inputMode))
        presentation.move(to: NSRect(origin: resolvedOrigin(for: size, mode: inputMode), size: size),
                          animated: animate, contentChanged: replacingContent)
        if context.reduceMotion {
            presentation.fade(to: 1, motion: motion, reduceMotion: true, animated: false)
        }
    }

    private func cancelPointerExit() {
        pointerExitWorkItem?.cancel()
        pointerExitWorkItem = nil
    }

    private func schedulePointerExit() {
        guard motion == .continuous, !context.reduceMotion else {
            dismiss(animated: true)
            return
        }
        guard pointerExitWorkItem == nil, !isClosing else { return }
        let generation = presentationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.dismiss(animated: true)
        }
        pointerExitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FluentToolTipMetrics.continuousExitDelay, execute: work)
    }

    private func resolvedOrigin(for size: NSSize, mode: FluentToolTipInputMode) -> NSPoint {
        let target = placementTarget(for: mode)
        let screenFrame = screenContaining(targetCenter: NSPoint(x: target.midX, y: target.midY))?.visibleFrame
            ?? window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? target.insetBy(dx: -500, dy: -500)
        if placement == .mouse, mode == .pointer {
            let raw = NSRect(
                x: context.layoutDirection.appKitValue == .rightToLeft ? target.midX - size.width : target.midX,
                y: target.midY - 11 - size.height,
                width: size.width,
                height: size.height
            )
            return constrained(raw, to: screenFrame).origin
        }
        let preferred = resolvedPlacement(mode: mode)
        let candidates = placementCandidates(preferred)
        let offset = mode == .pointer ? FluentToolTipMetrics.mouseOffset : FluentToolTipMetrics.keyboardOffset
        let frames = candidates.map { candidateFrame(side: $0, target: target, size: size, offset: offset) }
        if let fitting = frames.first(where: { screenFrame.contains($0) }) { return fitting.origin }
        // WinUI preserves the requested side when none of the four candidates can fit, then
        // constrains the result into the visible region instead of picking a maximum-overlap side.
        let best = frames[0]
        return NSPoint(
            x: min(max(best.minX, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - size.width)),
            y: min(max(best.minY, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - size.height))
        )
    }

    private func resolvedPlacement(mode: FluentToolTipInputMode) -> FluentToolTipPlacement {
        let requested = (placement == .automatic || (placement == .mouse && mode == .keyboard))
            ? FluentToolTipPlacement.top
            : placement
        guard context.layoutDirection.appKitValue == .rightToLeft else { return requested }
        if requested == .left { return .right }
        if requested == .right { return .left }
        return requested
    }

    private func placementCandidates(_ preferred: FluentToolTipPlacement) -> [FluentToolTipPlacement] {
        switch preferred {
        case .top, .automatic, .mouse: return [.top, .bottom, .right, .left]
        case .bottom: return [.bottom, .top, .right, .left]
        case .left: return [.left, .right, .top, .bottom]
        case .right: return [.right, .left, .top, .bottom]
        }
    }

    private func candidateFrame(
        side: FluentToolTipPlacement,
        target: NSRect,
        size: NSSize,
        offset: CGFloat
    ) -> NSRect {
        switch side {
        case .top, .automatic, .mouse:
            return NSRect(x: target.midX - size.width / 2, y: target.maxY + offset, width: size.width, height: size.height)
        case .bottom:
            return NSRect(x: target.midX - size.width / 2, y: target.minY - offset - size.height, width: size.width, height: size.height)
        case .left:
            return NSRect(x: target.minX - offset - size.width, y: target.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: target.maxX + offset, y: target.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    private func installWindowObservers() {
        firstResponderObservation?.invalidate()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        guard let window else { return }
        firstResponderObservation = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] _, change in
            guard let self else { return }
            let focused = self.ownsFirstResponder(change.newValue ?? nil)
            guard focused != self.focusedInside else { return }
            self.focusedInside = focused
            if focused {
                if FluentFocusVisibility.isKeyboardInteraction(in: self.window) {
                    self.scheduleOpen(mode: .keyboard)
                }
            } else {
                self.openWorkItem?.cancel()
                if self.inputMode == .keyboard { self.dismiss(animated: true) }
            }
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willMoveNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.willMiniaturizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in self?.dismiss(animated: false) })
        }
    }

    private func ownsFirstResponder(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSView,
           view === contentView || view.isDescendant(of: contentView) { return true }
        if let editor = responder as? NSTextView,
           let delegate = fluentFieldEditorOwner(editor),
           delegate === contentView || delegate.isDescendant(of: contentView) { return true }
        return false
    }

    private func applyAccessibilityHelp() {
        let current = contentView.accessibilityHelp()
        if current != lastAppliedAccessibilityHelp { inheritedAccessibilityHelp = current }
        let resolved = isEnabled ? (accessibilityText ?? inheritedAccessibilityHelp) : inheritedAccessibilityHelp
        contentView.setAccessibilityHelp(resolved)
        lastAppliedAccessibilityHelp = resolved
    }

    private var anchorScreenFrame: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    private func screenContaining(targetCenter: NSPoint) -> NSScreen? {
        FluentScreenPlacement.screen(nearest: targetCenter)
    }

    private func installTransientMonitors() {
        removeTransientMonitors()
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async { self?.evaluateSafeZone(at: NSEvent.mouseLocation) }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(event.type) {
                self?.dismiss(animated: false)
            } else {
                self?.evaluateSafeZone(at: NSEvent.mouseLocation)
            }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            if self.shouldDismiss(for: event) { self.dismiss(animated: true) }
            return event
        }
    }

    private func removeTransientMonitors() {
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        globalPointerMonitor = nil
        localPointerMonitor = nil
        localKeyMonitor = nil
    }

    private func evaluateSafeZone(at point: NSPoint?) {
        guard let point, let panel else { return }
        let anchorFrame = anchorScreenFrame ?? anchorFrameAtPresentation ?? .zero
        if anchorFrameAtPresentation.map({ !$0.nearlyEquals(anchorFrame) }) == true {
            dismiss(animated: true)
            return
        }
        if Self.point(point, isInsideConvexHullOf: anchorFrame, and: panel.frame) {
            cancelPointerExit()
        } else {
            schedulePointerExit()
        }
    }

    private func shouldDismiss(for event: NSEvent) -> Bool {
        if event.keyCode == 58 || event.keyCode == 61 { return false }
        // WinUI leaves navigation/editing keys alone so their target keeps normal behavior.
        return ![49, 51, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(event.keyCode)
    }

    private func placementTarget(for mode: FluentToolTipInputMode) -> NSRect {
        let point = motion == .continuous && panel != nil ? presentationPointerPoint : pointerScreenPoint
        if mode == .pointer, let point { return NSRect(origin: point, size: .zero) }
        return anchorScreenFrame ?? .zero
    }

    private func maximumContentHeight(for mode: FluentToolTipInputMode) -> CGFloat {
        let target = placementTarget(for: mode)
        let visibleHeight = screenContaining(targetCenter: NSPoint(x: target.midX, y: target.midY))?.visibleFrame.height
            ?? window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900
        return max(1, visibleHeight - FluentToolTipMetrics.screenTolerance * 2)
    }

    private func constrained(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        NSRect(
            x: min(max(rect.minX, bounds.minX + FluentToolTipMetrics.screenTolerance), max(bounds.minX, bounds.maxX - rect.width - FluentToolTipMetrics.screenTolerance)),
            y: min(max(rect.minY, bounds.minY + FluentToolTipMetrics.screenTolerance), max(bounds.minY, bounds.maxY - rect.height - FluentToolTipMetrics.screenTolerance)),
            width: min(rect.width, max(1, bounds.width - FluentToolTipMetrics.screenTolerance * 2)),
            height: min(rect.height, max(1, bounds.height - FluentToolTipMetrics.screenTolerance * 2))
        )
    }

    static func point(_ point: NSPoint, isInsideConvexHullOf first: NSRect, and second: NSRect) -> Bool {
        if first.contains(point) || second.contains(point) { return true }
        let points = [
            NSPoint(x: first.minX, y: first.minY), NSPoint(x: first.minX, y: first.maxY),
            NSPoint(x: first.maxX, y: first.maxY), NSPoint(x: first.maxX, y: first.minY),
            NSPoint(x: second.minX, y: second.minY), NSPoint(x: second.minX, y: second.maxY),
            NSPoint(x: second.maxX, y: second.maxY), NSPoint(x: second.maxX, y: second.minY)
        ]
        let hull = convexHull(points)
        guard hull.count >= 3 else { return false }
        var sign: CGFloat = 0
        for index in hull.indices {
            let a = hull[index]
            let b = hull[(index + 1) % hull.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) < 0.0001 { continue }
            if sign == 0 { sign = cross }
            else if sign * cross < 0 { return false }
        }
        return true
    }

    private static func convexHull(_ points: [NSPoint]) -> [NSPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return sorted }
        func cross(_ o: NSPoint, _ a: NSPoint, _ b: NSPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [NSPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        var upper: [NSPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    private func screenPoint(for event: NSEvent) -> NSPoint? {
        guard let window = event.window else { return nil }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    deinit {
        firstResponderObservation?.invalidate()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        openWorkItem?.cancel()
        closeWorkItem?.cancel()
        pointerExitWorkItem?.cancel()
        removeTransientMonitors()
    }
}

final class FluentToolTipSurface: NSView {
    private(set) var content: NSView
    private let material: FluentMaterialView
    private let contentContainer = NSView()
    private var outgoingContent: CALayer?
    var hasContentTransition: Bool { outgoingContent != nil }
    private var measuredContentSize: NSSize = .zero
    private var context: FluentRenderContext

    init(content: NSView, context: FluentRenderContext) {
        self.content = content
        self.context = context
        material = FluentMaterialView(material: .acrylic)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ToolTip.Surface")
        wantsLayer = true
        addSubview(material)
        contentContainer.wantsLayer = true
        addSubview(contentContainer)
        contentContainer.addSubview(content)
        setAccessibilityRole(.helpTag)
        update(context: context)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        material.frame = bounds
        contentContainer.frame = bounds
        let padding = FluentToolTipMetrics.padding
        let size = outgoingContent == nil
            ? NSSize(width: max(0, bounds.width - padding.left - padding.right),
                     height: max(0, bounds.height - padding.top - padding.bottom))
            : measuredContentSize
        content.frame = NSRect(x: padding.left, y: padding.bottom, width: size.width, height: size.height)
    }

    func replaceContent(with content: NSView, animated: Bool = false) {
        guard self.content !== content else { return }
        let image = animated ? captureContent() : nil
        finishContentTransition()
        self.content.removeFromSuperview()
        self.content = content
        contentContainer.addSubview(content)
        if let image {
            let snapshot = CALayer()
            snapshot.contents = image
            snapshot.frame = contentContainer.bounds
            contentContainer.layer?.addSublayer(snapshot)
            outgoingContent = snapshot
            content.alphaValue = 0
        }
        needsLayout = true
    }

    func setContentTransitionProgress(_ progress: CGFloat) {
        guard let outgoingContent else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoingContent.opacity = Float(1 - progress)
        content.alphaValue = progress
        CATransaction.commit()
    }

    func finishContentTransition() {
        outgoingContent?.removeFromSuperlayer()
        outgoingContent = nil
        content.alphaValue = 1
        needsLayout = true
    }

    private func captureContent() -> CGImage? {
        layoutSubtreeIfNeeded()
        contentContainer.displayIfNeeded()
        CATransaction.flush()
        let scale = window?.backingScaleFactor ?? 1
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(bounds.width * scale)), pixelsHigh: Int(ceil(bounds.height * scale)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let cg = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return nil }
        cg.scaleBy(x: scale, y: scale)
        // Capture text/custom content only. The live material is never flattened or duplicated.
        contentContainer.layer?.render(in: cg)
        return bitmap.cgImage
    }

    func update(context: FluentRenderContext) {
        if self.context.theme != context.theme || context.reduceMotion { finishContentTransition() }
        self.context = context
        let theme = context.theme
        material.configure(theme: theme, role: .toolTip)
        material.wantsLayer = true
        material.layer?.cornerRadius = 4
        material.layer?.borderWidth = 1
        material.layer?.borderColor = theme.surfaceStrokeFlyout.cgColor
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        needsLayout = true
    }

    func measure(maximumHeight: CGFloat) -> NSSize {
        content.layoutSubtreeIfNeeded()
        var contentSize = content.fittingSize
        if contentSize.width <= 0 || contentSize.width == NSView.noIntrinsicMetric {
            contentSize.width = max(1, content.intrinsicContentSize.width)
        }
        let horizontalPadding = FluentToolTipMetrics.padding.left + FluentToolTipMetrics.padding.right
        let verticalPadding = FluentToolTipMetrics.padding.top + FluentToolTipMetrics.padding.bottom
        let maximumContentWidth = FluentToolTipMetrics.maximumWidth - horizontalPadding
        contentSize.width = min(maximumContentWidth, max(1, contentSize.width))
        // AppKit's wrapping label keeps reporting its one-line fitting height after only changing
        // the frame. WinUI measures the TextBlock against the ContentPresenter's constrained width,
        // so establish the same proposal before asking for the final height.
        if let label = content as? NSTextField,
           label.maximumNumberOfLines != 1 {
            label.preferredMaxLayoutWidth = contentSize.width
            label.invalidateIntrinsicContentSize()
        }
        content.setFrameSize(NSSize(width: contentSize.width, height: max(1, contentSize.height)))
        content.layoutSubtreeIfNeeded()
        contentSize.height = max(contentSize.height, content.fittingSize.height)
        measuredContentSize = NSSize(width: contentSize.width,
            height: max(0, min(contentSize.height, maximumHeight - verticalPadding)))
        return NSSize(
            width: contentSize.width + horizontalPadding,
            height: min(contentSize.height + verticalPadding, maximumHeight)
        )
    }
}

final class FluentToolTipPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ToolTip.Panel")
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .popUpMenu
        hidesOnDeactivate = true
        collectionBehavior = [.transient, .ignoresCycle]
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension NSRect {
    func nearlyEquals(_ other: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
