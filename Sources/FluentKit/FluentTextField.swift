import AppKit

@inline(__always)
func fluentTextControlHasFocus(_ control: NSTextField) -> Bool {
    guard let firstResponder = control.window?.firstResponder else { return false }
    return firstResponder === control || firstResponder === control.currentEditor()
}

struct FluentTextControlGeometry {
    let controlBounds: NSRect
    let contentRect: NSRect
    let placeholderRect: NSRect
    let editorRect: NSRect

    init(
        nativeTextRect: NSRect,
        in bounds: NSRect,
        font: NSFont?,
        topInset: CGFloat = 5,
        bottomInset: CGFloat = 6,
        leadingInset: CGFloat = 0,
        trailingInset: CGFloat = 0
    ) {
        controlBounds = bounds
        let resolvedFont = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        let horizontalMin = max(nativeTextRect.minX + leadingInset, bounds.minX)
        let horizontalMax = min(nativeTextRect.maxX - trailingInset, bounds.maxX)
        let contentMinY = min(max(bounds.minY + topInset, bounds.minY), bounds.maxY)
        let contentMaxY = max(min(bounds.maxY - bottomInset, bounds.maxY), contentMinY)
        let resolvedHeight = min(max(lineHeight, 0), contentMaxY - contentMinY)
        let resolvedY = floor(contentMinY + max(0, contentMaxY - contentMinY - resolvedHeight) / 2)
        let rect = NSRect(
            x: horizontalMin,
            y: resolvedY,
            width: max(horizontalMax - horizontalMin, 0),
            height: resolvedHeight
        )
        contentRect = rect
        placeholderRect = rect
        editorRect = rect
    }
}

@inline(__always)
func fluentSingleLineTextRect(
    _ textRect: NSRect,
    in bounds: NSRect,
    font: NSFont?,
    topInset: CGFloat = 5,
    bottomInset: CGFloat = 6,
    leadingInset: CGFloat = 0,
    trailingInset: CGFloat = 0
) -> NSRect {
    FluentTextControlGeometry(
        nativeTextRect: textRect,
        in: bounds,
        font: font,
        topInset: topInset,
        bottomInset: bottomInset,
        leadingInset: leadingInset,
        trailingInset: trailingInset
    ).contentRect
}

@inline(__always)
func fluentTextControlRect(
    _ textRect: NSRect,
    in bounds: NSRect,
    font: NSFont?,
    leadingInset: CGFloat = 10,
    trailingInset: CGFloat = 6
) -> NSRect {
    // TextControlThemePadding is 10,5,6,6. AppKit text controls use flipped coordinates, so the
    // first vertical value is the visual top inset. SearchBox adornments are centered separately.
    fluentSingleLineTextRect(
        textRect,
        in: bounds,
        font: font,
        topInset: 5,
        bottomInset: 6,
        leadingInset: leadingInset,
        trailingInset: trailingInset
    )
}

@inline(__always)
func fluentCenteredAdornmentRect(_ rect: NSRect, in bounds: NSRect) -> NSRect {
    var result = rect
    result.origin.y = floor(bounds.midY - result.height / 2)
    return result
}

@discardableResult
func configureFluentSingleLineFieldEditor(_ text: NSText) -> NSText {
    guard let editor = text as? NSTextView else { return text }
    editor.textContainerInset = .zero
    if let textContainer = editor.textContainer {
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byClipping
    }
    return editor
}

@inline(__always)
func applyFluentTextControlContentAppearance(
    _ control: NSTextField,
    appearance: FluentTextFieldAppearance,
    theme: FluentTheme
) {
    if control.textColor?.isEqual(appearance.textColor) != true {
        control.textColor = appearance.textColor
    }
    guard let placeholder = control.placeholderAttributedString?.string ?? control.placeholderString,
          !placeholder.isEmpty else { return }
    var attributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: control.isEnabled ? theme.textSecondary : theme.textDisabled
    ]
    if let font = appearance.font ?? control.font { attributes[.font] = font }
    let resolved = NSAttributedString(string: placeholder, attributes: attributes)
    if control.placeholderAttributedString?.isEqual(to: resolved) != true {
        control.placeholderAttributedString = resolved
    }
}

/// Keep AppKit's single-line editor and placeholder on the same baseline as other Fluent fields.
private final class FluentTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        configureFluentSingleLineFieldEditor(super.setUpFieldEditorAttributes(textObj))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        fluentTextControlRect(
            super.drawingRect(forBounds: rect),
            in: rect,
            font: font,
            leadingInset: 10,
            trailingInset: 6
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        drawingRect(forBounds: rect)
    }

    override func edit(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame frame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: titleRect(forBounds: frame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

enum FluentTextFieldChromePhase {
    case background
    case borderAndFocus
    case all
}

struct FluentInputChromeGeometry {
    let bounds: NSRect
    let backgroundRect: NSRect
    let borderOuterRect: NSRect
    let borderInnerRect: NSRect
    let borderOuterRadius: CGFloat
    let borderInnerRadius: CGFloat
    let endpointInset: CGFloat

    init(bounds: NSRect, appearance: FluentTextFieldAppearance, backingScale: CGFloat? = nil) {
        let pixels = FluentPixelGeometry(backingScale: backingScale)
        let maximumInset = max(min(bounds.width, bounds.height) / 2, 0)
        let antialiasInset = min(pixels.halfPixel, maximumInset)
        self.bounds = bounds
        backgroundRect = bounds
        borderOuterRect = bounds.insetBy(dx: antialiasInset, dy: antialiasInset)
        borderInnerRect = borderOuterRect.insetBy(
            dx: appearance.borderWidth,
            dy: appearance.borderWidth
        )
        borderOuterRadius = max(appearance.cornerRadius - antialiasInset, 0)
        borderInnerRadius = max(borderOuterRadius - appearance.borderWidth, 0)
        endpointInset = max(appearance.borderWidth / 2, pixels.halfPixel)
    }

    func focusIndicatorRect(width: CGFloat, isFlipped: Bool) -> NSRect {
        let resolvedWidth = min(max(width, 0), borderOuterRect.height)
        return NSRect(
            x: borderOuterRect.minX,
            y: isFlipped ? borderOuterRect.maxY - resolvedWidth : borderOuterRect.minY,
            width: borderOuterRect.width,
            height: resolvedWidth
        )
    }
}

@inline(__always)
func drawFluentTextFieldChrome(
    in bounds: NSRect,
    appearance: FluentTextFieldAppearance,
    isFlipped: Bool,
    phase: FluentTextFieldChromePhase = .all
) {
    let geometry = FluentInputChromeGeometry(bounds: bounds, appearance: appearance)
    if phase == .background || phase == .all {
        switch appearance.borderShape {
        case .rounded:
            let path = NSBezierPath(
                roundedRect: geometry.backgroundRect,
                xRadius: appearance.cornerRadius,
                yRadius: appearance.cornerRadius
            )
            appearance.backgroundColor.setFill()
            path.fill()
        case .underline:
            appearance.backgroundColor.setFill()
            geometry.backgroundRect.fill()
        }
    }

    guard phase == .borderAndFocus || phase == .all else { return }
    switch appearance.borderShape {
    case .rounded:
        guard appearance.borderWidth > 0 else { break }
        // Fill an even-odd rounded ring instead of clipping a centered stroke. Every antialiased
        // pixel remains inside the host, including the leading/trailing arcs at Retina scale.
        let outerRect = geometry.borderOuterRect
        let innerRect = geometry.borderInnerRect
        let borderPath = CGMutablePath()
        borderPath.addRoundedRect(
            in: outerRect,
            cornerWidth: geometry.borderOuterRadius,
            cornerHeight: geometry.borderOuterRadius
        )
        if innerRect.width > 0, innerRect.height > 0 {
            borderPath.addRoundedRect(
                in: innerRect,
                cornerWidth: geometry.borderInnerRadius,
                cornerHeight: geometry.borderInnerRadius
            )
        }
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.addPath(borderPath)
            context.clip(using: .evenOdd)
            if let colors = appearance.borderGradientColors, colors.count >= 2 {
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let resolvedColors = colors.compactMap {
                    $0.usingColorSpace(.deviceRGB)?.cgColor
                }
                let locations = appearance.borderGradientLocations.count == resolvedColors.count
                    ? appearance.borderGradientLocations
                    : (0..<resolvedColors.count).map {
                        CGFloat($0) / CGFloat(max(resolvedColors.count - 1, 1))
                    }
                if resolvedColors.count >= 2,
                   let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: resolvedColors as CFArray,
                    locations: locations
                   ) {
                    let extent = min(appearance.borderGradientExtent, outerRect.height)
                    let visualBottom = isFlipped ? outerRect.maxY : outerRect.minY
                    let visualTop = isFlipped ? outerRect.minY : outerRect.maxY
                    let startY = appearance.borderGradientEdge == .bottom ? visualBottom : visualTop
                    let endY: CGFloat
                    if appearance.borderGradientEdge == .bottom {
                        endY = startY + (isFlipped ? -extent : extent)
                    } else {
                        endY = startY + (isFlipped ? extent : -extent)
                    }
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: outerRect.midX, y: startY),
                        end: CGPoint(x: outerRect.midX, y: endY),
                        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                    )
                } else {
                    context.setFillColor(appearance.borderColor.cgColor)
                    context.fill(outerRect)
                }
            } else {
                context.setFillColor(appearance.borderColor.cgColor)
                context.fill(outerRect)
            }
            context.restoreGState()
        } else {
            appearance.borderColor.setStroke()
            let strokeRect = geometry.borderOuterRect.insetBy(
                dx: appearance.borderWidth / 2,
                dy: appearance.borderWidth / 2
            )
            let fallback = NSBezierPath(
                roundedRect: strokeRect,
                xRadius: max(geometry.borderOuterRadius - appearance.borderWidth / 2, 0),
                yRadius: max(geometry.borderOuterRadius - appearance.borderWidth / 2, 0)
            )
            fallback.lineWidth = appearance.borderWidth
            fallback.stroke()
        }
    case .underline:
        guard appearance.borderWidth > 0 else { break }
        let path = NSBezierPath()
        let visualBottom = isFlipped
            ? geometry.borderOuterRect.maxY - appearance.borderWidth / 2
            : geometry.borderOuterRect.minY + appearance.borderWidth / 2
        path.move(to: NSPoint(x: bounds.minX + geometry.endpointInset, y: visualBottom))
        path.line(to: NSPoint(x: bounds.maxX - geometry.endpointInset, y: visualBottom))
        path.lineWidth = appearance.borderWidth
        appearance.borderColor.setStroke()
        path.stroke()
    }

    guard let indicatorColor = appearance.focusIndicatorColor,
          appearance.focusIndicatorWidth > 0,
          appearance.borderShape == .rounded else { return }
    let clip = NSBezierPath(
        roundedRect: geometry.borderOuterRect,
        xRadius: geometry.borderOuterRadius,
        yRadius: geometry.borderOuterRadius
    )
    let indicatorRect = geometry.focusIndicatorRect(
        width: appearance.focusIndicatorWidth,
        isFlipped: isFlipped
    )
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    // This replaces the visual bottom of the one-point ring, yielding one 1,1,1,2 border model.
    indicatorColor.setFill()
    indicatorRect.fill()
    NSGraphicsContext.restoreGraphicsState()
}

public class FluentTextField: NSTextField {
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            textEditingSession.theme = theme
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentStyle: (any FluentTextFieldStyle)? { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    /// Composite controls such as NumberBox can own one outer chrome while reusing this editor.
    public var drawsFluentChrome = true { didSet { needsDisplay = true } }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            controlSize = fluentControlSize.appKitSize
            font = .systemFont(ofSize: fluentControlSize.fontSize + 1)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var onFluentPointerChange: ((Bool) -> Void)?
    private(set) var isFluentPointerOver = false
    private var fluentPointerTrackingArea: NSTrackingArea?
    private lazy var textEditingSession = FluentTextEditingSession(control: self, theme: theme, isSecure: false)

    public init(placeholder: String = "") {
        super.init(frame: .zero)
        cell = FluentTextFieldCell(textCell: "")
        configureFluentSingleLineTextControl(self)
        isEditable = true
        isSelectable = true
        stringValue = ""
        placeholderString = placeholder
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = .systemFont(ofSize: 14)
        focusRingType = .none
        wantsLayer = true
        setAccessibilityRole(.textField)
        _ = textEditingSession
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override var intrinsicContentSize: NSSize {
        NSSize(
            width: 220 * theme.density.metricScale,
            height: theme.controlHeight(for: fluentControlSize)
        )
    }

    public override func updateTrackingAreas() {
        if let fluentPointerTrackingArea { removeTrackingArea(fluentPointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        fluentPointerTrackingArea = area
        addTrackingArea(area)
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isFluentPointerOver = true
        onFluentPointerChange?(true)
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        isFluentPointerOver = false
        onFluentPointerChange?(false)
        needsDisplay = true
    }

    public override func textDidBeginEditing(_ notification: Notification) {
        // AppKit may refresh cell flags as it installs the shared field editor. Reassert that
        // Fluent owns every visible part of the input chrome before configuring the editor.
        focusRingType = .none
        isBordered = false
        isBezeled = false
        drawsBackground = false
        super.textDidBeginEditing(notification)
        textEditingSession.didBeginEditing()
        needsDisplay = true
    }

    public override func selectText(_ sender: Any?) {
        super.selectText(sender)
        textEditingSession.didBeginEditing()
    }

    public override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        textEditingSession.didEndEditing()
        needsDisplay = true
    }

    public override func rightMouseDown(with event: NSEvent) {
        if !textEditingSession.presentContextCommands(for: event) {
            super.rightMouseDown(with: event)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedAppearance()
        if let font = appearance.font, self.font != font { self.font = font }
        applyFluentTextControlContentAppearance(self, appearance: appearance, theme: theme)
        if drawsFluentChrome {
            drawFluentTextFieldChrome(in: bounds, appearance: appearance, isFlipped: isFlipped, phase: .background)
        }
        super.draw(dirtyRect)
        if drawsFluentChrome {
            drawFluentTextFieldChrome(in: bounds, appearance: appearance, isFlipped: isFlipped, phase: .borderAndFocus)
        }
    }

    public override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    private func resolvedAppearance() -> FluentTextFieldAppearance {
        let configuration = FluentTextFieldStyleConfiguration(
            isEnabled: isEnabled,
            isFocused: fluentTextControlHasFocus(self),
            isPointerOver: isFluentPointerOver,
            controlSize: fluentControlSize,
            theme: theme
        )
        return fluentStyle?.appearance(for: configuration)
            ?? FluentAutomaticTextFieldStyle().appearance(for: configuration)
    }
}

extension FluentTextField: FluentControlSizeConfigurable {}
