import AppKit

/// WinUI-style HyperlinkButton: a keyboard-focusable link with the same subtle pointer and
/// pressed surfaces as the Windows control. Set `navigateURL` for navigation, `onClick` for an
/// application action, or both.
public final class FluentHyperlinkButton: NSControl, FluentControlSizeConfigurable {
    public var title: String {
        didSet {
            guard oldValue != title else { return }
            setAccessibilityTitle(title)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var navigateURL: URL? {
        didSet { updateAccessibilityMetadata() }
    }
    public var onClick: (() -> Void)?
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            updateFont()
            invalidateIntrinsicContentSize()
            updateAppearance(animated: false)
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            animationCoordinator.reduceMotion = reduceMotion
            if reduceMotion { layer?.removeAllAnimations() }
            updateAppearance(animated: false)
        }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            updateFont()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private var displayFont = FluentTheme.current.typography.font(for: .body)
    private var isPointerOver = false
    private var isPressed = false
    private var isTrackingPress = false
    private var isKeyboardPressed = false
    private let focusOuterLayer = CAShapeLayer()
    private let focusInnerLayer = CAShapeLayer()
    private let animationCoordinator = FluentAnimationCoordinator()

    public init(
        _ title: String,
        navigateURL: URL? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.navigateURL = navigateURL
        onClick = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        animationCoordinator.reduceMotion = reduceMotion
        configureFocusLayers()
        updateFont()
        setAccessibilityRole(.link)
        setAccessibilityTitle(title)
        updateAccessibilityMetadata()
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: displayFont])
        let scale = fluentControlSize.metricScale
        let horizontalPadding = 11 * scale
        let vertical = (6 + 7) * scale
        return NSSize(
            width: ceil(text.width + horizontalPadding * 2),
            height: ceil(max(theme.controlHeight(for: fluentControlSize), text.height + vertical))
        )
    }

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            if !isEnabled {
                isPressed = false
                isKeyboardPressed = false
                isTrackingPress = false
            }
            updateAppearance(animated: true)
        }
    }

    public override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        updateAppearance(animated: true)
    }

    public override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = false
        if !isTrackingPress { isPressed = false }
        updateAppearance(animated: true)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        isTrackingPress = true
        isPressed = true
        updateAppearance(animated: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPointerOver = inside
        guard isPressed != inside else { return }
        isPressed = inside
        updateAppearance(animated: true)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isTrackingPress = false
        isPressed = false
        isPointerOver = inside
        updateAppearance(animated: true)
        if inside { invoke() }
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 36 where !event.isARepeat,
             49 where !event.isARepeat:
            isKeyboardPressed = true
            updateAppearance(animated: true)
        case 53:
            isKeyboardPressed = false
            updateAppearance(animated: true)
        default:
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard isEnabled else { return }
        if (event.keyCode == 36 || event.keyCode == 49), isKeyboardPressed {
            isKeyboardPressed = false
            updateAppearance(animated: true)
            invoke()
        } else {
            super.keyUp(with: event)
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { updateAppearance(animated: true) }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        isKeyboardPressed = false
        let result = super.resignFirstResponder()
        if result { updateAppearance(animated: true) }
        return result
    }

    public override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let textRect = fluentSingleLineTextRect(
            bounds.insetBy(dx: 11 * fluentControlSize.metricScale, dy: 0),
            in: bounds,
            font: displayFont,
            topInset: 6 * fluentControlSize.metricScale,
            bottomInset: 7 * fluentControlSize.metricScale
        )
        NSAttributedString(
            string: title,
            attributes: [
                .font: displayFont,
                .foregroundColor: foregroundColor,
                .paragraphStyle: paragraph
            ]
        ).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        invoke()
        return true
    }

    private var controlState: FluentControlState {
        if !isEnabled { return .disabled }
        if isPressed || isKeyboardPressed { return .pressed }
        if isPointerOver { return .pointerOver }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) { return .focused }
        return .normal
    }

    private var foregroundColor: NSColor {
        switch controlState {
        case .pointerOver: return theme.accentTextSecondary
        case .pressed: return theme.accentTextTertiary
        case .disabled: return theme.accentTextDisabled
        default: return theme.accentTextPrimary
        }
    }

    private var backgroundColor: NSColor {
        switch controlState {
        case .pointerOver: return theme.subtleFillSecondary
        case .pressed: return theme.subtleFillTertiary
        default: return .clear
        }
    }

    private func configureFocusLayers() {
        for focusLayer in [focusOuterLayer, focusInnerLayer] {
            focusLayer.fillColor = NSColor.clear.cgColor
            focusLayer.opacity = 0
            layer?.addSublayer(focusLayer)
        }
        focusOuterLayer.name = "FluentKit.HyperlinkButton.FocusOuter"
        focusInnerLayer.name = "FluentKit.HyperlinkButton.FocusInner"
    }

    private func updateFont() {
        let body = theme.typography.font(for: .body)
        displayFont = body.withSize(body.pointSize * fluentControlSize.metricScale)
    }

    private func updateLayerGeometry() {
        guard let layer else { return }
        let radius = theme.designTokens.controlCornerRadius * fluentControlSize.metricScale
        layer.cornerRadius = radius
        let outerRect = bounds.insetBy(dx: 1, dy: 1)
        focusOuterLayer.frame = bounds
        focusOuterLayer.path = CGPath(roundedRect: outerRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        focusOuterLayer.lineWidth = 2
        let innerRect = bounds.insetBy(dx: 3, dy: 3)
        focusInnerLayer.frame = bounds
        focusInnerLayer.path = CGPath(roundedRect: innerRect, cornerWidth: max(0, radius - 2), cornerHeight: max(0, radius - 2), transform: nil)
        focusInnerLayer.lineWidth = 1
    }

    private func updateAppearance(animated: Bool) {
        guard let layer else { return }
        updateLayerGeometry()
        let background = backgroundColor.cgColor
        animationCoordinator.animateState(
            [FluentLayerAnimationChange(
                layer: layer,
                key: "fluent.hyperlink.background",
                keyPath: "backgroundColor",
                toValue: background
            ) { [weak layer] in layer?.backgroundColor = background }],
            motion: FluentMotion.controlFaster,
            animated: animated
        )
        let showsFocus = FluentFocusVisibility.isKeyboardFocusVisible(for: self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusOuterLayer.strokeColor = theme.focusStrokeOuter.cgColor
        focusInnerLayer.strokeColor = theme.focusStrokeInner.cgColor
        focusOuterLayer.opacity = showsFocus ? 1 : 0
        focusInnerLayer.opacity = showsFocus ? 1 : 0
        CATransaction.commit()
        needsDisplay = true
    }

    private func updateAccessibilityMetadata() {
        setAccessibilityHelp(navigateURL?.absoluteString)
    }

    private func invoke() {
        onClick?()
        if let navigateURL { NSWorkspace.shared.open(navigateURL) }
    }
}

public struct FluentHyperlinkButtonView: FluentUpdatablePrimitiveView {
    public let title: String
    public let navigateURL: URL?
    public let action: (() -> Void)?

    public init(
        _ title: String,
        navigateURL: URL? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.navigateURL = navigateURL
        self.action = action
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let button = FluentHyperlinkButton(title, navigateURL: navigateURL, action: action)
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        return button
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let button = view as? FluentHyperlinkButton else { return false }
        button.title = title
        button.navigateURL = navigateURL
        button.onClick = action
        button.theme = context.theme
        button.reduceMotion = context.reduceMotion
        return true
    }
}
