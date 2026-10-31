import AppKit

final class FluentFlipViewButton: NSButton {
    var onClick: (() -> Void)?
    var onPointerPresenceChanged: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKeyView: Bool { false }
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
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
        image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image?.isTemplate = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        onPointerPresenceChanged?(true)
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        onPointerPresenceChanged?(false)
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        onPointerPresenceChanged?(true)
        isPressed = true
        updateAppearance()
        // NSButton consumes mouse-up inside its tracking loop, so clean up after it returns.
        defer { isPressed = false; updateAppearance() }
        super.mouseDown(with: event)
    }

    @objc private func invoke() {
        guard isEnabled else { return }
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
