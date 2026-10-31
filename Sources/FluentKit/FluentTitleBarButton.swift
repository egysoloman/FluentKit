import AppKit

final class FluentTitleBarButton: NSButton {
    enum Kind {
        case back
        case forward
        case pane
    }

    let kind: Kind
    var onInvoke: (() -> Void)?
    private var theme: FluentTheme = .current
    private var layoutDirection: FluentLayoutDirection = .leftToRight
    private var isWindowActive = true
    private(set) var pointerOver = false
    private(set) var pressed = false
    private var trackingPress = false
    private var spaceHeld = false
    private let motion = FluentAnimationCoordinator()
    private(set) var glyphHeadOffset: CGFloat = 0
    private(set) var glyphTailOffset: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }
    override var isEnabled: Bool { didSet { if !isEnabled { resetInteraction() } } }
    override var isHidden: Bool { didSet { if isHidden { resetInteraction() } } }

    override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        target = self
        action = #selector(invoke)
        setAccessibilityRole(.button)
        let label = switch kind {
        case .back: "Back"
        case .forward: "Forward"
        case .pane: "Navigation"
        }
        setAccessibilityTitle(label)
        toolTip = label
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        theme: FluentTheme,
        layoutDirection: FluentLayoutDirection,
        isActive: Bool,
        reduceMotion: Bool,
        isEnabled: Bool,
        accessibilityValue: String?
    ) {
        self.theme = theme
        self.layoutDirection = layoutDirection
        let label: String = switch kind { case .back: "Back"; case .forward: "Forward"; case .pane: "Navigation" }
        setAccessibilityTitle(fluentControlString(label))
        toolTip = fluentControlString(label)
        isWindowActive = isActive
        motion.reduceMotion = reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !isActive { resetInteraction() }
        if motion.reduceMotion { updateGlyph(animated: false) }
        self.isEnabled = isEnabled
        setAccessibilityEnabled(isEnabled)
        setAccessibilityValue(accessibilityValue)
        needsDisplay = true
    }

    private var canInvoke: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    override func viewDidHide() { super.viewDidHide(); resetInteraction() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { resetInteraction() }
    }
    override func resignFirstResponder() -> Bool {
        spaceHeld = false
        setPressed(false)
        return super.resignFirstResponder()
    }
    override func mouseEntered(with event: NSEvent) {
        guard canInvoke else { return }
        pointerOver = true
        if trackingPress { setPressed(true) }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        if trackingPress { setPressed(false) }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        guard canInvoke, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        FluentInputDeviceTracker.shared.record(FluentInputDeviceTracker.deviceType(for: event) ?? .mouse, in: window)
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        spaceHeld = false; trackingPress = true; pointerOver = true
        setPressed(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard trackingPress, canInvoke else { return }
        pointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(pointerOver)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard trackingPress else { return }
        let inside = canInvoke && bounds.contains(convert(event.locationInWindow, from: nil))
        trackingPress = false; pointerOver = inside
        setPressed(false)
        if inside { invoke() }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard canInvoke else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 49:
            guard !event.isARepeat, !spaceHeld, !trackingPress else { return }
            spaceHeld = true; setPressed(true)
        case 36, 76:
            if !event.isARepeat { performClick(nil) }
        case 53: resetInteraction()
        default: super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            guard spaceHeld else { return }
            let activate = spaceHeld && canInvoke
            spaceHeld = false; setPressed(false)
            if activate { invoke() }
        } else if event.keyCode != 36 && event.keyCode != 76 {
            super.keyUp(with: event)
        }
    }
    override func performClick(_ sender: Any?) {
        guard canInvoke else { return }
        // Programmatic/AX invocation has no captured pointer or pending key-up.
        invoke()
    }
    override func accessibilityPerformPress() -> Bool {
        guard canInvoke else { return false }
        performClick(nil)
        return true
    }
    private func resetInteraction() {
        trackingPress = false; spaceHeld = false; pointerOver = false; pressed = false
        motion.cancelAllValueAnimations()
        glyphHeadOffset = 0; glyphTailOffset = 0
        needsDisplay = true
    }
    private func setPressed(_ value: Bool) {
        guard pressed != value else { return }
        pressed = value
        updateGlyph(animated: true)
        needsDisplay = true
    }
    private func updateGlyph(animated: Bool) {
        guard kind != .pane else { return }
        let startHead = glyphHeadOffset, startTail = glyphTailOffset
        let compress = pressed
        // AnimatedBackVisualSource: 48-unit art shown at 16pt; press frames 10–19,
        // release frames 40–59. Arrowhead moves inward; the surface never scales.
        let duration = compress ? 9.0 / 60 : 19.0 / 60
        let shouldAnimate = animated && window != nil && !motion.reduceMotion
        if !shouldAnimate {
            motion.cancelAllValueAnimations()
            glyphHeadOffset = compress ? 3 : 0
            glyphTailOffset = compress ? 0.938 / 3 : 0
            needsDisplay = true
            return
        }
        motion.animateValue(key: "backGlyph", from: 0, to: 1,
            motion: .init(duration: duration, curve: .linear), animated: true) { [weak self] fraction in
            guard let self else { return }
            func eased(_ t: CGFloat, _ curve: FluentCubicBezier) -> CGFloat {
                FluentAnimationCurve.cubicBezier(curve).progress(at: t)
            }
            if compress {
                let p = eased(fraction, .init(0.167, 0.167, 0, 1))
                self.glyphHeadOffset = startHead + (3 - startHead) * p
                self.glyphTailOffset = startTail + (0.938 / 3 - startTail) * p
            } else {
                let strength = min(max(startHead / 3, 0), 1)
                let headOvershoot = -4.016 / 3 * strength, tailOvershoot = -1.25 * strength
                let split: CGFloat = 10.0 / 19
                if fraction <= split {
                    let t = fraction / split
                    self.glyphHeadOffset = startHead + (headOvershoot - startHead) * eased(t, .init(0.85, 0, 0.75, 1))
                    self.glyphTailOffset = startTail + (tailOvershoot - startTail) * eased(t, .init(0.55, 0, 0.75, 1))
                } else {
                    let p = eased((fraction - split) / (1 - split), .init(0.35, 0, 0, 1))
                    self.glyphHeadOffset = headOvershoot * (1 - p)
                    self.glyphTailOffset = tailOvershoot * (1 - p)
                }
            }
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // The view's frame is already the 40-point WinUI button after its external Margin=2 has
        // been removed by layout. Its root surface therefore fills these bounds.
        let surface = bounds
        let background: NSColor
        if !isEnabled {
            background = theme.buttonBackground(for: .disabled)
        } else if pressed {
            background = theme.subtleFillTertiary
        } else if pointerOver {
            background = theme.subtleFillSecondary
        } else {
            background = .clear
        }
        background.setFill()
        NSBezierPath(roundedRect: surface, xRadius: 4, yRadius: 4).fill()

        let color: NSColor
        if !isEnabled {
            color = theme.textDisabled
        } else if pressed {
            color = theme.textSecondary
        } else {
            color = isWindowActive ? theme.textPrimary : theme.textTertiary
        }
        color.setStroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = kind == .pane ? 1.5 : 0.75
        glyph.lineCapStyle = .round
        glyph.lineJoinStyle = .round
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .pane:
            // Segoe Fluent E700 / AnimatedGlobalNavigationButtonVisualSource fallback geometry.
            for offset in [-5.0, 0, 5.0] {
                glyph.move(to: NSPoint(x: center.x - 7, y: center.y + offset))
                glyph.line(to: NSPoint(x: center.x + 7, y: center.y + offset))
            }
        case .back, .forward:
            // WinUI E72B is a complete arrow with a horizontal stem. SF's chevron/arrow metrics
            // are noticeably different at 16 points, so keep the Fluent fallback geometry here.
            let pointsRight = (kind == .forward) != (layoutDirection == .rightToLeft)
            let sign: CGFloat = pointsRight ? 1 : -1
            let tipX = center.x + sign * (5.625 - glyphHeadOffset)
            let tailX = center.x - sign * (5.625 + glyphTailOffset)
            glyph.move(to: NSPoint(x: tailX, y: center.y))
            glyph.line(to: NSPoint(x: tipX, y: center.y))
            glyph.move(to: NSPoint(x: tipX, y: center.y))
            glyph.line(to: NSPoint(x: tipX - sign * 5.375, y: center.y - 4.875))
            glyph.move(to: NSPoint(x: tipX, y: center.y))
            glyph.line(to: NSPoint(x: tipX - sign * 5.375, y: center.y + 4.875))
        }
        glyph.stroke()
        // AppKit may nominate the first title-bar key view while a window is becoming key. That
        // must not look like a keyboard selection until the user actually navigates with keys.
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            theme.accent.setStroke()
            let focus = NSBezierPath(roundedRect: surface.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            focus.lineWidth = theme.focusStrokeWidth
            focus.stroke()
        }
    }

    @objc private func invoke() { if canInvoke { onInvoke?() } }
}
