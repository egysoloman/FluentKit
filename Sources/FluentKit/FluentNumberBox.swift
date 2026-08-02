import AppKit

public enum FluentNumberBoxSpinButtonPlacementMode: Hashable, Sendable {
    case hidden
    case compact
    case inline
}

public enum FluentNumberBoxValidationMode: Hashable, Sendable {
    case invalidInputOverwritten
    case disabled
}

private struct FluentNumberBoxSpinButtonStyle: FluentRepeatButtonStyle {
    func appearance(for configuration: FluentRepeatButtonStyleConfiguration) -> FluentButtonAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let background: NSColor = switch state {
        case .pointerOver: theme.subtleFillSecondary
        case .pressed: theme.subtleFillTertiary
        default: .clear
        }
        let foreground: NSColor = switch state {
        case .pressed: theme.textTertiary
        case .disabled: theme.textDisabled
        default: theme.textSecondary
        }
        return FluentButtonAppearance(
            backgroundColor: background,
            foregroundColor: foreground,
            borderColor: .clear,
            borderWidth: 0,
            cornerRadius: max(theme.buttonCornerRadius - 1, 0),
            contentInsets: NSEdgeInsetsZero,
            focusRingColor: nil,
            focusRingWidth: 0
        )
    }
}

private final class FluentNumberTextField: FluentTextField {
    var onScrollStep: ((Bool) -> Void)?
    var onEnabledChange: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard fluentTextControlHasFocus(self), event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        onScrollStep?(event.scrollingDeltaY > 0)
    }

    override var isEnabled: Bool {
        didSet { onEnabledChange?() }
    }
}

private final class FluentNumberBoxPopupIndicator: NSButton {
    var theme: FluentTheme = .current {
        didSet {
            updateImage()
            needsDisplay = true
        }
    }
    private let upChevron = FluentChevronPrimitiveLayer()
    private let downChevron = FluentChevronPrimitiveLayer()
    private var pointerOver = false
    private var pointerTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        wantsLayer = true
        layer?.masksToBounds = false
        upChevron.name = "FluentKit.NumberBox.CompactUpChevron"
        downChevron.name = "FluentKit.NumberBox.CompactDownChevron"
        layer?.addSublayer(upChevron)
        layer?.addSublayer(downChevron)
        setAccessibilityElement(false)
        updateImage()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            theme.subtleFillTertiary.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 4, dy: 4),
                xRadius: max(theme.buttonCornerRadius - 1, 0),
                yRadius: max(theme.buttonCornerRadius - 1, 0)
            ).fill()
        }
        updateImage(animated: false)
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        updateImage(animated: false)
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        pointerOver = true
        updateImage(animated: true)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        updateImage(animated: true)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        updateImage(state: .pressed, animated: true)
        super.mouseDown(with: event)
        updateImage(animated: true)
    }

    private func updateImage(state explicitState: FluentControlState? = nil, animated: Bool = false) {
        image = nil
        let state = explicitState ?? (!isEnabled ? .disabled : (pointerOver ? .pointerOver : .normal))
        let color: NSColor = switch state {
        case .pressed: theme.textTertiary
        case .disabled: theme.textDisabled
        default: theme.textSecondary
        }
        let glyphWidth: CGFloat = 10
        let glyphHeight: CGFloat = 8
        upChevron.update(
            frame: NSRect(
                x: bounds.midX - glyphWidth / 2,
                y: bounds.midY - 1,
                width: glyphWidth,
                height: glyphHeight
            ),
            color: color,
            state: state,
            direction: .up,
            backingScale: window?.backingScaleFactor,
            animated: animated
        )
        downChevron.update(
            frame: NSRect(
                x: bounds.midX - glyphWidth / 2,
                y: bounds.midY - glyphHeight + 1,
                width: glyphWidth,
                height: glyphHeight
            ),
            color: color,
            state: state,
            direction: .down,
            backingScale: window?.backingScaleFactor,
            animated: animated
        )
    }
}

private final class FluentNumberBoxCompactPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FluentNumberBoxCompactPopupView: NSView {
    let incrementButton = FluentRepeatButton(
        title: "Increase",
        systemImageName: "chevron.up",
        systemImagePointSize: 16
    )
    let decrementButton = FluentRepeatButton(
        title: "Decrease",
        systemImageName: "chevron.down",
        systemImagePointSize: 16
    )
    var theme: FluentTheme = .current { didSet { applyTheme() } }
    var reduceMotion = false {
        didSet {
            incrementButton.reduceMotion = reduceMotion
            decrementButton.reduceMotion = reduceMotion
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NumberBox.CompactPopup")
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        incrementButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NumberBox.PopupIncrement")
        decrementButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.NumberBox.PopupDecrement")
        incrementButton.allowsKeyboardFocus = false
        decrementButton.allowsKeyboardFocus = false
        incrementButton.fluentStyle = FluentNumberBoxSpinButtonStyle()
        decrementButton.fluentStyle = FluentNumberBoxSpinButtonStyle()
        incrementButton.setAccessibilityElement(false)
        decrementButton.setAccessibilityElement(false)
        addSubview(incrementButton)
        addSubview(decrementButton)
        incrementButton.frame = NSRect(x: 6, y: 6, width: 36, height: 36)
        decrementButton.frame = NSRect(x: 6, y: 46, width: 36, height: 36)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        incrementButton.frame = NSRect(x: 6, y: 6, width: 36, height: 36)
        decrementButton.frame = NSRect(x: 6, y: 46, width: 36, height: 36)
    }

    private func applyTheme() {
        layer?.backgroundColor = theme.flyoutSurfaceFill.cgColor
        layer?.borderColor = theme.surfaceStrokeFlyout.cgColor
        layer?.borderWidth = theme.isHighContrast ? 2 : 1
        incrementButton.theme = theme
        decrementButton.theme = theme
    }
}

private final class FluentNumberBoxCompactPopup: NSObject {
    private weak var anchor: NSView?
    private var anchorRect: NSRect = .zero
    private let panel: FluentNumberBoxCompactPanel
    let contentView: FluentNumberBoxCompactPopupView
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    var isPresented: Bool { panel.parent != nil || panel.isVisible }

    init(
        theme: FluentTheme,
        reduceMotion: Bool,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void
    ) {
        contentView = FluentNumberBoxCompactPopupView(frame: NSRect(x: 0, y: 0, width: 48, height: 88))
        contentView.theme = theme
        contentView.reduceMotion = reduceMotion
        contentView.incrementButton.onClick = onIncrement
        contentView.decrementButton.onClick = onDecrement
        panel = FluentNumberBoxCompactPanel(
            contentRect: contentView.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.identifier = NSUserInterfaceItemIdentifier("FluentKit.NumberBox.CompactPopupPanel")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = contentView
    }

    func present(relativeTo anchor: NSView, controlRect: NSRect) {
        guard let parentWindow = anchor.window else { return }
        self.anchor = anchor
        anchorRect = controlRect
        reposition(relativeTo: anchor, controlRect: controlRect)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        installLifecycle(for: parentWindow)
    }

    func reposition(relativeTo anchor: NSView, controlRect: NSRect) {
        guard let parentWindow = anchor.window else { return }
        self.anchor = anchor
        anchorRect = controlRect
        let anchorWindowRect = anchor.convert(controlRect, to: nil)
        let anchorScreenRect = parentWindow.convertToScreen(anchorWindowRect)
        let size = panel.frame.size
        var origin = NSPoint(
            x: anchorScreenRect.maxX - size.width - 1,
            y: anchorScreenRect.midY - size.height / 2
        )
        if let visibleFrame = parentWindow.screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    func update(
        theme: FluentTheme,
        reduceMotion: Bool,
        incrementEnabled: Bool,
        decrementEnabled: Bool
    ) {
        contentView.theme = theme
        panel.appearance = fluentAppKitAppearance(for: theme)
        contentView.reduceMotion = reduceMotion
        contentView.incrementButton.isEnabled = incrementEnabled
        contentView.decrementButton.isEnabled = decrementEnabled
    }

    func dismiss() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        anchor = nil
    }

    private func installLifecycle(for parentWindow: NSWindow) {
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self else { return event }
                if event.window === self.panel { return event }
                if let anchor = self.anchor,
                   event.window === anchor.window,
                   self.anchorRect.contains(anchor.convert(event.locationInWindow, from: nil)) {
                    return event
                }
                self.dismiss()
                return event
            }
        }
        guard windowObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(center.addObserver(
                forName: name,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                guard let self, let anchor = self.anchor else { return }
                self.reposition(relativeTo: anchor, controlRect: self.anchorRect)
            })
        }
        windowObservers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in self?.dismiss() })
    }

    deinit { dismiss() }
}

public final class FluentNumberBoxControl: NSControl, NSTextFieldDelegate, FluentControlSizeConfigurable {
    public let textField: FluentTextField = FluentNumberTextField()
    public let incrementButton = FluentRepeatButton(title: "Increase", systemImageName: "chevron.up")
    public let decrementButton = FluentRepeatButton(title: "Decrease", systemImageName: "chevron.down")

    public var theme: FluentTheme = .current {
        didSet {
            applyTheme()
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            incrementButton.reduceMotion = reduceMotion
            decrementButton.reduceMotion = reduceMotion
            updateCompactPopup()
        }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            applyControlSize()
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }
    public var fluentLayoutDirection: FluentLayoutDirection = .system {
        didSet {
            guard oldValue != fluentLayoutDirection else { return }
            userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            textField.userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            incrementButton.userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            decrementButton.userInterfaceLayoutDirection = fluentLayoutDirection.appKitValue
            needsLayout = true
        }
    }
    public var title: String {
        didSet {
            guard oldValue != title else { return }
            titleLabel.stringValue = title
            titleLabel.isHidden = title.isEmpty
            setAccessibilityTitle(title)
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }
    public var placeholder: String {
        didSet { textField.placeholderString = placeholder }
    }
    public var minimum: Double {
        didSet {
            if minimum > maximum { minimum = maximum; return }
            synchronizeValue(notify: true)
        }
    }
    public var maximum: Double {
        didSet {
            if maximum < minimum { maximum = minimum; return }
            synchronizeValue(notify: true)
        }
    }
    public var smallChange: Double {
        didSet { precondition(smallChange > 0, "FluentNumberBox smallChange must be positive") }
    }
    public var largeChange: Double {
        didSet { precondition(largeChange > 0, "FluentNumberBox largeChange must be positive") }
    }
    public var spinButtonPlacement: FluentNumberBoxSpinButtonPlacementMode {
        didSet {
            guard oldValue != spinButtonPlacement else { return }
            updateSpinButtonVisibility()
            needsLayout = true
            if spinButtonPlacement != .compact { dismissCompactPopup() }
        }
    }
    public var validationMode: FluentNumberBoxValidationMode {
        didSet { synchronizeValue(notify: true) }
    }
    public var isWrapEnabled: Bool {
        didSet { updateSpinButtonEnabledState() }
    }
    public var textFieldStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() {
        didSet {
            activeTextField.fluentStyle = textFieldStyle
            needsDisplay = true
        }
    }
    public var format: (Double) -> String {
        didSet { updateTextFromValue() }
    }
    public var parse: (String) -> Double? = { Double($0) }
    public var onValueChanged: ((Double) -> Void)?

    public var value: Double {
        get { storedValue }
        set { setValue(newValue, notify: true) }
    }

    public override var isFlipped: Bool { true }

    public override var isEnabled: Bool {
        didSet {
            textField.isEnabled = isEnabled
            popupIndicator.isEnabled = isEnabled
            setAccessibilityEnabled(isEnabled)
            updateSpinButtonEnabledState()
            if !isEnabled { dismissCompactPopup() }
            needsDisplay = true
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let popupIndicator = FluentNumberBoxPopupIndicator(frame: .zero)
    private var storedValue: Double
    private var suppressesValueNotification = false
    private var compactPopup: FluentNumberBoxCompactPopup?

    public init(
        title: String = "",
        value: Double,
        range: ClosedRange<Double>,
        smallChange: Double = 1,
        largeChange: Double = 10,
        spinButtonPlacement: FluentNumberBoxSpinButtonPlacementMode = .hidden,
        validationMode: FluentNumberBoxValidationMode = .invalidInputOverwritten,
        isWrapEnabled: Bool = false,
        placeholder: String = "",
        format: @escaping (Double) -> String = { String(format: "%g", $0) }
    ) {
        precondition(smallChange > 0, "FluentNumberBox smallChange must be positive")
        precondition(largeChange > 0, "FluentNumberBox largeChange must be positive")
        self.title = title
        storedValue = value
        minimum = range.lowerBound
        maximum = range.upperBound
        self.smallChange = smallChange
        self.largeChange = largeChange
        self.spinButtonPlacement = spinButtonPlacement
        self.validationMode = validationMode
        self.isWrapEnabled = isWrapEnabled
        self.placeholder = placeholder
        self.format = format
        super.init(frame: .zero)
        configureView()
        synchronizeValue(notify: false)
    }

    required init?(coder: NSCoder) {
        title = ""
        storedValue = 0
        minimum = -Double.greatestFiniteMagnitude
        maximum = Double.greatestFiniteMagnitude
        smallChange = 1
        largeChange = 10
        spinButtonPlacement = .hidden
        validationMode = .invalidInputOverwritten
        isWrapEnabled = false
        placeholder = ""
        format = { String(format: "%g", $0) }
        super.init(coder: coder)
        configureView()
        synchronizeValue(notify: false)
    }

    public override var intrinsicContentSize: NSSize {
        let controlHeight = theme.controlHeight(for: fluentControlSize)
        let headerHeight = title.isEmpty ? 0 : resolvedHeaderHeight + 8 * theme.density.metricScale
        return NSSize(width: 120 * fluentControlSize.metricScale, height: ceil(headerHeight + controlHeight))
    }

    public override func layout() {
        super.layout()
        let scale = fluentControlSize.metricScale
        let controlRect = numberControlRect
        let headerHeight = title.isEmpty ? 0 : resolvedHeaderHeight
        if !title.isEmpty {
            titleLabel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        }
        let showsButtons = spinButtonPlacement == .inline
        let showsPopupIndicator = spinButtonPlacement == .compact
        let spinWidth = showsButtons ? min(72 * scale, controlRect.width) : 0
        let indicatorWidth = showsPopupIndicator ? min(32 * scale, controlRect.width) : 0
        let trailingWidth = max(spinWidth, indicatorWidth)
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        textField.frame = NSRect(
            x: isRTL ? trailingWidth : 0,
            y: controlRect.minY,
            width: max(controlRect.width - trailingWidth, 0),
            height: controlRect.height
        )
        popupIndicator.frame = NSRect(
            x: isRTL ? controlRect.minX : controlRect.maxX - indicatorWidth,
            y: controlRect.minY,
            width: indicatorWidth,
            height: controlRect.height
        )
        guard showsButtons else {
            incrementButton.frame = .zero
            decrementButton.frame = .zero
            compactPopup?.reposition(relativeTo: self, controlRect: controlRect)
            return
        }
        let spinMinX = isRTL ? controlRect.minX : controlRect.maxX - spinWidth
        let margin = 4 * scale
        let buttonWidth = max((spinWidth - margin * 2) / 2, 0)
        let buttonHeight = max(controlRect.height - margin * 2, 0)
        let leadingFrame = NSRect(
            x: spinMinX + margin,
            y: controlRect.minY + margin,
            width: buttonWidth,
            height: buttonHeight
        )
        let trailingFrame = NSRect(
            x: leadingFrame.maxX,
            y: leadingFrame.minY,
            width: buttonWidth,
            height: buttonHeight
        )
        decrementButton.frame = isRTL ? trailingFrame : leadingFrame
        incrementButton.frame = isRTL ? leadingFrame : trailingFrame
        compactPopup?.reposition(relativeTo: self, controlRect: controlRect)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedTextFieldAppearance()
        let controlRect = numberControlRect
        guard controlRect.width > 0, controlRect.height > 0 else { return }
        drawFluentTextFieldChrome(
            in: controlRect,
            appearance: appearance,
            isFlipped: isFlipped
        )
    }

    public override func accessibilityValue() -> Any? { storedValue }

    public override func accessibilityPerformIncrement() -> Bool {
        guard incrementButton.isEnabled else { return false }
        stepValue(by: smallChange)
        return true
    }

    public override func accessibilityPerformDecrement() -> Bool {
        guard decrementButton.isEnabled else { return false }
        stepValue(by: -smallChange)
        return true
    }

    public func setValueFromBinding(_ value: Double) {
        suppressesValueNotification = true
        setValue(value, notify: false)
        suppressesValueNotification = false
    }

    public func commitEditing() { commitText() }

    public func controlTextDidBeginEditing(_ obj: Notification) {
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            guard let editor = self?.textField.currentEditor() else { return }
            editor.selectedRange = NSRange(location: 0, length: editor.string.utf16.count)
            self?.presentCompactPopupIfNeeded()
        }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
        dismissCompactPopup()
        needsDisplay = true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissCompactPopup() }
    }

    public func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            stepValue(by: smallChange)
        case #selector(NSResponder.moveDown(_:)):
            stepValue(by: -smallChange)
        case #selector(NSResponder.scrollPageUp(_:)):
            stepValue(by: largeChange)
        case #selector(NSResponder.scrollPageDown(_:)):
            stepValue(by: -largeChange)
        case #selector(NSResponder.insertNewline(_:)):
            commitText()
        case #selector(NSResponder.cancelOperation(_:)):
            updateTextFromValue()
        default:
            return false
        }
        return true
    }

    private var resolvedHeaderHeight: CGFloat {
        let font = titleLabel.font ?? theme.typography.font(for: .body)
        return ceil(font.ascender - font.descender + font.leading)
    }

    private var numberControlRect: NSRect {
        let controlHeight = min(theme.controlHeight(for: fluentControlSize), bounds.height)
        let headerHeight = title.isEmpty ? 0 : resolvedHeaderHeight
        let headerGap = title.isEmpty ? 0 : 8 * theme.density.metricScale
        let y = headerHeight + headerGap
        return NSRect(
            x: 0,
            y: y,
            width: bounds.width,
            height: max(min(controlHeight, bounds.height - y), 0)
        )
    }

    private func configureView() {
        wantsLayer = true
        focusRingType = .none
        setAccessibilityRole(.incrementor)
        setAccessibilityTitle(title)
        setAccessibilityEnabled(isEnabled)

        titleLabel.stringValue = title
        titleLabel.isHidden = title.isEmpty
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        popupIndicator.target = self
        popupIndicator.action = #selector(focusInputBox)
        popupIndicator.identifier = NSUserInterfaceItemIdentifier("FluentKit.NumberBox.PopupIndicator")
        popupIndicator.toolTip = "Show spin buttons"
        addSubview(popupIndicator)

        let numberTextField = activeTextField
        numberTextField.placeholderString = placeholder
        numberTextField.delegate = self
        numberTextField.drawsFluentChrome = false
        numberTextField.alignment = .natural
        numberTextField.onFluentPointerChange = { [weak self] _ in self?.needsDisplay = true }
        numberTextField.onScrollStep = { [weak self] increment in
            guard let self else { return }
            self.stepValue(by: increment ? self.smallChange : -self.smallChange)
        }
        numberTextField.onEnabledChange = { [weak self] in
            self?.updateSpinButtonEnabledState()
            self?.needsDisplay = true
        }
        numberTextField.target = self
        numberTextField.action = #selector(commitText)
        addSubview(numberTextField)

        incrementButton.allowsKeyboardFocus = false
        decrementButton.allowsKeyboardFocus = false
        incrementButton.systemImagePointSize = 12
        decrementButton.systemImagePointSize = 12
        incrementButton.fluentStyle = FluentNumberBoxSpinButtonStyle()
        decrementButton.fluentStyle = FluentNumberBoxSpinButtonStyle()
        incrementButton.onClick = { [weak self] in self?.stepValue(by: self?.smallChange ?? 0) }
        decrementButton.onClick = { [weak self] in self?.stepValue(by: -(self?.smallChange ?? 0)) }
        addSubview(incrementButton)
        addSubview(decrementButton)
        updateSpinButtonVisibility()
        applyTheme()
        applyControlSize()
        updateTextFromValue()
        updateSpinButtonEnabledState()
    }

    private var activeTextField: FluentNumberTextField {
        guard let field = textField as? FluentNumberTextField else {
            fatalError("NumberBox text field was not configured")
        }
        return field
    }

    private func applyTheme() {
        titleLabel.font = theme.typography.font(for: .body)
        titleLabel.textColor = isEnabled ? theme.textPrimary : theme.textDisabled
        activeTextField.theme = theme
        activeTextField.fluentStyle = textFieldStyle
        incrementButton.theme = theme
        decrementButton.theme = theme
        popupIndicator.theme = theme
        incrementButton.reduceMotion = reduceMotion
        decrementButton.reduceMotion = reduceMotion
        updateCompactPopup()
        needsDisplay = true
    }

    private func applyControlSize() {
        activeTextField.fluentControlSize = fluentControlSize
        incrementButton.fluentControlSize = fluentControlSize
        decrementButton.fluentControlSize = fluentControlSize
        needsLayout = true
    }

    private func updateSpinButtonVisibility() {
        let inlineVisible = spinButtonPlacement == .inline
        incrementButton.isHidden = !inlineVisible
        decrementButton.isHidden = !inlineVisible
        popupIndicator.isHidden = spinButtonPlacement != .compact
        updateSpinButtonEnabledState()
    }

    private func resolvedTextFieldAppearance() -> FluentTextFieldAppearance {
        textFieldStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: isEnabled,
                isFocused: fluentTextControlHasFocus(activeTextField),
                isPointerOver: activeTextField.isFluentPointerOver,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    @objc private func commitText() {
        let trimmed = activeTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            setValue(.nan, notify: true)
            return
        }
        guard let parsed = parse(trimmed) else {
            if validationMode == .invalidInputOverwritten { updateTextFromValue() }
            return
        }
        setValue(parsed, notify: true)
    }

    private func stepValue(by change: Double) {
        guard isEnabled, change != 0 else { return }
        commitText()
        guard !storedValue.isNaN else { return }
        var next = storedValue + change
        if isWrapEnabled {
            if next > maximum { next = minimum }
            if next < minimum { next = maximum }
        }
        setValue(next, notify: true)
        if let editor = activeTextField.currentEditor() {
            editor.selectedRange = NSRange(location: editor.string.count, length: 0)
        }
    }

    private func synchronizeValue(notify: Bool) {
        setValue(storedValue, notify: notify)
    }

    private func setValue(_ rawValue: Double, notify: Bool) {
        let next: Double
        if rawValue.isNaN || validationMode == .disabled {
            next = rawValue
        } else {
            next = min(max(rawValue, minimum), maximum)
        }
        let changed = !sameValue(storedValue, next)
        storedValue = next
        updateTextFromValue()
        updateSpinButtonEnabledState()
        setAccessibilityValue(next)
        guard changed, notify, !suppressesValueNotification else { return }
        sendAction(action, to: target)
        onValueChanged?(next)
    }

    private func updateTextFromValue() {
        activeTextField.stringValue = storedValue.isNaN ? "" : format(storedValue)
    }

    private func updateSpinButtonEnabledState() {
        let controlEnabled = isEnabled && activeTextField.isEnabled && !storedValue.isNaN
        let ignoresBounds = isWrapEnabled || validationMode == .disabled
        incrementButton.isEnabled = controlEnabled && (ignoresBounds || storedValue < maximum)
        decrementButton.isEnabled = controlEnabled && (ignoresBounds || storedValue > minimum)
        updateCompactPopup()
    }

    @objc private func focusInputBox() {
        guard isEnabled else { return }
        _ = window?.makeFirstResponder(activeTextField)
        activeTextField.selectText(nil)
        presentCompactPopupIfNeeded()
    }

    private func presentCompactPopupIfNeeded() {
        guard spinButtonPlacement == .compact,
              isEnabled,
              fluentTextControlHasFocus(activeTextField),
              window != nil else { return }
        if compactPopup == nil {
            compactPopup = FluentNumberBoxCompactPopup(
                theme: theme,
                reduceMotion: reduceMotion,
                onIncrement: { [weak self] in self?.stepValue(by: self?.smallChange ?? 0) },
                onDecrement: { [weak self] in self?.stepValue(by: -(self?.smallChange ?? 0)) }
            )
        }
        updateCompactPopup()
        guard let compactPopup, !compactPopup.isPresented else { return }
        compactPopup.present(relativeTo: self, controlRect: numberControlRect)
    }

    private func updateCompactPopup() {
        compactPopup?.update(
            theme: theme,
            reduceMotion: reduceMotion,
            incrementEnabled: incrementButton.isEnabled,
            decrementEnabled: decrementButton.isEnabled
        )
    }

    private func dismissCompactPopup() {
        compactPopup?.dismiss()
        compactPopup = nil
    }

    private func sameValue(_ lhs: Double, _ rhs: Double) -> Bool {
        (lhs.isNaN && rhs.isNaN) || lhs == rhs
    }

    deinit { dismissCompactPopup() }
}

private final class FluentNumberBoxBindingHost: NSView, FluentControlSizeConfigurable {
    let numberBox: FluentNumberBoxControl
    var fluentControlSize: FluentControlSize = .regular {
        didSet {
            numberBox.fluentControlSize = fluentControlSize
            invalidateIntrinsicContentSize()
        }
    }
    private var binding: FluentBinding<Double>
    private var observerID: UUID?
    private var isApplyingBinding = false

    init(numberBox: FluentNumberBoxControl, binding: FluentBinding<Double>) {
        self.numberBox = numberBox
        self.binding = binding
        super.init(frame: .zero)
        addSubview(numberBox)
        numberBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            numberBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            numberBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            numberBox.topAnchor.constraint(equalTo: topAnchor),
            numberBox.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        numberBox.onValueChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.binding.set(value)
        }
        if !sameValue(numberBox.value, binding.get()) { binding.set(numberBox.value) }
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { numberBox.intrinsicContentSize }

    func update(binding: FluentBinding<Double>, configure: (FluentNumberBoxControl) -> Void) {
        removeObserver()
        self.binding = binding
        configure(numberBox)
        let value = binding.get()
        if !sameValue(numberBox.value, value) { numberBox.setValueFromBinding(value) }
        installObserver()
        invalidateIntrinsicContentSize()
    }

    private func installObserver() {
        observerID = binding.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.sameValue(self.numberBox.value, value) else { return }
                self.isApplyingBinding = true
                self.numberBox.setValueFromBinding(value)
                let normalized = self.numberBox.value
                if !self.sameValue(value, normalized) { self.binding.set(normalized) }
                self.isApplyingBinding = false
            }
        }
    }

    private func removeObserver() {
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    private func sameValue(_ lhs: Double, _ rhs: Double) -> Bool {
        (lhs.isNaN && rhs.isNaN) || lhs == rhs
    }

    deinit { removeObserver() }
}

public struct FluentNumberBox: FluentUpdatablePrimitiveView {
    private let title: String
    private let binding: FluentBinding<Double>
    private let range: ClosedRange<Double>
    private let smallChange: Double
    private let largeChange: Double
    private let spinButtonPlacement: FluentNumberBoxSpinButtonPlacementMode
    private let validationMode: FluentNumberBoxValidationMode
    private let isWrapEnabled: Bool
    private let placeholder: String
    private let textFieldStyle: any FluentTextFieldStyle
    private let format: (Double) -> String
    private let parse: (String) -> Double?

    public init(
        _ title: String = "",
        value: FluentBinding<Double>,
        in range: ClosedRange<Double>,
        smallChange: Double = 1,
        largeChange: Double = 10,
        spinButtonPlacement: FluentNumberBoxSpinButtonPlacementMode = .hidden,
        validationMode: FluentNumberBoxValidationMode = .invalidInputOverwritten,
        isWrapEnabled: Bool = false,
        placeholder: String = "",
        textFieldStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle(),
        format: @escaping (Double) -> String = { String(format: "%g", $0) },
        parse: @escaping (String) -> Double? = { Double($0) }
    ) {
        precondition(smallChange > 0, "FluentNumberBox smallChange must be positive")
        precondition(largeChange > 0, "FluentNumberBox largeChange must be positive")
        self.title = title
        binding = value
        self.range = range
        self.smallChange = smallChange
        self.largeChange = largeChange
        self.spinButtonPlacement = spinButtonPlacement
        self.validationMode = validationMode
        self.isWrapEnabled = isWrapEnabled
        self.placeholder = placeholder
        self.textFieldStyle = textFieldStyle
        self.format = format
        self.parse = parse
    }

    public init(
        _ title: String = "",
        value: FluentBinding<Int>,
        in range: ClosedRange<Int>,
        smallChange: Int = 1,
        largeChange: Int = 10,
        spinButtonPlacement: FluentNumberBoxSpinButtonPlacementMode = .hidden,
        validationMode: FluentNumberBoxValidationMode = .invalidInputOverwritten,
        isWrapEnabled: Bool = false,
        placeholder: String = "",
        textFieldStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()
    ) {
        self.init(
            title,
            value: value.map(Double.init, { candidate in
                candidate.isFinite ? Int(candidate.rounded()) : value.get()
            }),
            in: Double(range.lowerBound)...Double(range.upperBound),
            smallChange: Double(smallChange),
            largeChange: Double(largeChange),
            spinButtonPlacement: spinButtonPlacement,
            validationMode: validationMode,
            isWrapEnabled: isWrapEnabled,
            placeholder: placeholder,
            textFieldStyle: textFieldStyle,
            format: { String(Int($0.rounded())) },
            parse: { Double($0).map { Double(Int($0.rounded())) } }
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let control = makeControl(in: context)
        return FluentNumberBoxBindingHost(numberBox: control, binding: binding)
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNumberBoxBindingHost else { return false }
        host.update(binding: binding) { control in
            configure(control, in: context)
        }
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentNumberBox {
        FluentNumberBox(
            title,
            value: binding,
            in: range,
            smallChange: smallChange,
            largeChange: largeChange,
            spinButtonPlacement: spinButtonPlacement,
            validationMode: validationMode,
            isWrapEnabled: isWrapEnabled,
            placeholder: placeholder,
            textFieldStyle: style,
            format: format,
            parse: parse
        )
    }

    private func makeControl(in context: FluentRenderContext) -> FluentNumberBoxControl {
        let control = FluentNumberBoxControl(
            title: title,
            value: binding.get(),
            range: range,
            smallChange: smallChange,
            largeChange: largeChange,
            spinButtonPlacement: spinButtonPlacement,
            validationMode: validationMode,
            isWrapEnabled: isWrapEnabled,
            placeholder: placeholder,
            format: format
        )
        configure(control, in: context)
        return control
    }

    private func configure(_ control: FluentNumberBoxControl, in context: FluentRenderContext) {
        control.theme = context.theme
        control.reduceMotion = context.reduceMotion
        control.fluentLayoutDirection = context.layoutDirection
        control.title = title
        control.minimum = range.lowerBound
        control.maximum = range.upperBound
        control.smallChange = smallChange
        control.largeChange = largeChange
        control.spinButtonPlacement = spinButtonPlacement
        control.validationMode = validationMode
        control.isWrapEnabled = isWrapEnabled
        control.placeholder = placeholder
        control.textFieldStyle = textFieldStyle
        control.format = format
        control.parse = parse
    }
}
