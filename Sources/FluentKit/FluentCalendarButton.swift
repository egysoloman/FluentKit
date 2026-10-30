import AppKit

final class FluentCalendarButton: NSButton {
    enum Glyph { case up, down }
    var glyph: Glyph?
    var theme: FluentTheme = .current
    var roundDay = false
    var selected = false
    var today = false
    var blackout = false
    var outOfScope = false
    var isHeader = false
    var participatesInTabOrder = true
    var onInvoke: (() -> Void)?
    var onFocus: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    private var pointerOver = false

    init() {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        target = self
        action = #selector(invoke)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { participatesInTabOrder && super.canBecomeKeyView }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus?(); needsDisplay = true }
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }
    override func mouseEntered(with event: NSEvent) { pointerOver = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerOver = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        needsDisplay = true
        defer { needsDisplay = true }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !blackout else { return false }
        onInvoke?()
        return true
    }
    @objc private func invoke() { if isEnabled, !blackout { onInvoke?() } }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        NSBezierPath(rect: bounds).addClip()
        let pressed = cell?.isHighlighted == true
        let inset = min(1, min(bounds.width, bounds.height) / 2)
        var chrome = bounds.insetBy(dx: inset, dy: inset)
        if roundDay {
            let side = min(chrome.width, chrome.height)
            chrome = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        }
        let path = NSBezierPath(roundedRect: chrome, xRadius: roundDay ? chrome.width / 2 : 4, yRadius: roundDay ? chrome.height / 2 : 4)
        var foreground = !isEnabled || blackout ? theme.textDisabled : outOfScope ? theme.textSecondary : theme.textPrimary
        if today {
            (isEnabled ? theme.accent : theme.accent.withAlphaComponent(0.35)).setFill()
            path.fill()
            foreground = theme.textOnAccent
        } else if isEnabled, pressed || pointerOver {
            (pressed ? theme.subtleFillTertiary : theme.subtleFillSecondary).setFill()
            path.fill()
        }
        if selected {
            (today ? theme.textOnAccent : isEnabled ? theme.accent : theme.accent.withAlphaComponent(0.35)).setStroke()
            path.lineWidth = 2
            path.stroke()
            if !today { foreground = isEnabled ? theme.accentTextPrimary : theme.accentTextDisabled }
        }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            theme.focusStrokeOuter.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        if let glyph {
            let glyphPath = NSBezierPath()
            let halfWidth = min(4, bounds.width / 3), halfHeight = min(2, bounds.height / 3)
            let direction: CGFloat = (glyph == .up ? 1 : -1) * (isFlipped ? -1 : 1)
            glyphPath.move(to: NSPoint(x: bounds.midX - halfWidth, y: bounds.midY - direction * halfHeight))
            glyphPath.line(to: NSPoint(x: bounds.midX, y: bounds.midY + direction * halfHeight))
            glyphPath.line(to: NSPoint(x: bounds.midX + halfWidth, y: bounds.midY - direction * halfHeight))
            glyphPath.lineWidth = 1
            foreground.setStroke()
            glyphPath.stroke()
            return
        }
        let font = theme.typography.font(for: isHeader ? .bodyStrong : .body)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let size = (title as NSString).size(withAttributes: attributes)
        let x = isHeader ? (userInterfaceLayoutDirection == .rightToLeft ? bounds.maxX - size.width - 4 : 4)
            : bounds.midX - size.width / 2
        (title as NSString).draw(at: NSPoint(x: x, y: bounds.midY - size.height / 2), withAttributes: attributes)
        if blackout {
            let strike = NSBezierPath()
            strike.move(to: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY))
            strike.line(to: NSPoint(x: bounds.midX + size.width / 2, y: bounds.midY))
            foreground.setStroke()
            strike.lineWidth = 1
            strike.stroke()
        }
    }
}
