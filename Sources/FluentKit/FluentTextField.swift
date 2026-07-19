import AppKit

public final class FluentTextField: NSTextField {
    public var theme: FluentTheme = .current { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    public var fluentStyle: (any FluentTextFieldStyle)? { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            font = .systemFont(ofSize: fluentControlSize.fontSize + 1)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    public init(placeholder: String = "") {
        super.init(frame: .zero)
        stringValue = ""
        placeholderString = placeholder
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = .systemFont(ofSize: 14)
        focusRingType = .none
        wantsLayer = true
        setAccessibilityRole(.textField)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var intrinsicContentSize: NSSize {
        NSSize(
            width: 220 * theme.density.metricScale,
            height: theme.controlHeight(for: fluentControlSize)
        )
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        textColor = appearance.textColor
        if let font = appearance.font { self.font = font }
        appearance.backgroundColor.setFill()
        bounds.fill()
        appearance.borderColor.setStroke()
        switch appearance.borderShape {
        case .rounded:
            let rect = bounds.insetBy(dx: appearance.borderWidth / 2, dy: appearance.borderWidth / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: appearance.cornerRadius, yRadius: appearance.cornerRadius)
            appearance.backgroundColor.setFill()
            path.fill()
            if appearance.borderWidth > 0 {
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        case .underline:
            if appearance.borderWidth > 0 {
                let path = NSBezierPath()
                let visualBottom = isFlipped
                    ? bounds.maxY - appearance.borderWidth / 2
                    : bounds.minY + appearance.borderWidth / 2
                path.move(to: NSPoint(x: bounds.minX, y: visualBottom))
                path.line(to: NSPoint(x: bounds.maxX, y: visualBottom))
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        }
        super.draw(dirtyRect)
    }

    public override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func resolvedAppearance() -> FluentTextFieldAppearance {
        let configuration = FluentTextFieldStyleConfiguration(
            isEnabled: isEnabled,
            isFocused: window?.firstResponder === self || window?.firstResponder === currentEditor(),
            controlSize: fluentControlSize,
            theme: theme
        )
        return fluentStyle?.appearance(for: configuration)
            ?? FluentAutomaticTextFieldStyle().appearance(for: configuration)
    }
}

extension FluentTextField: FluentControlSizeConfigurable {}
