import AppKit

/// A single-line calendar date input backed by NSDatePicker with a Fluent surface and two-way binding.
/// Its visual contract follows WinUI's CalendarDatePicker rather than the three-column DatePicker.
public struct FluentDatePickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<Date>?
    fileprivate let date: Date
    fileprivate let minDate: Date?
    fileprivate let maxDate: Date?
    fileprivate let style: any FluentTextFieldStyle

    public init(
        selection: FluentBinding<Date>? = nil,
        date: Date = Date(),
        range: ClosedRange<Date>? = nil,
        style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()
    ) {
        self.binding = selection
        self.date = date
        minDate = range?.lowerBound
        maxDate = range?.upperBound
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let picker = FluentDatePickerNative(
            date: binding?.get() ?? date,
            binding: binding,
            minDate: minDate,
            maxDate: maxDate,
            style: style
        )
        picker.theme = context.theme
        picker.reduceMotion = context.reduceMotion
        picker.fluentStyle = style
        return picker
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let picker = view as? FluentDatePickerNative else { return false }
        picker.theme = context.theme
        picker.reduceMotion = context.reduceMotion
        picker.fluentStyle = style
        picker.update(binding: binding, date: date, minDate: minDate, maxDate: maxDate, style: style)
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentDatePickerView {
        FluentDatePickerView(selection: binding, date: date, range: minDate.map { $0 ... (maxDate ?? $0) }, style: style)
    }
}

private final class FluentDatePickerNative: NSDatePicker, FluentControlSizeConfigurable, NSPopoverDelegate {
    var theme: FluentTheme = .current {
        didSet {
            applyTheme()
            refreshAppearance(animated: false)
        }
    }
    var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() {
        didSet {
            applyTheme()
            refreshAppearance(animated: false)
        }
    }
    var fluentControlSize: FluentControlSize = .regular { didSet { applyTheme() } }
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet {
            guard oldValue != reduceMotion else { return }
            visualStateCoordinator.reduceMotion = reduceMotion
            if reduceMotion {
                layer?.removeAllAnimations()
                elevationBorderLayer.removeAllAnimations()
            }
            refreshAppearance(animated: false)
        }
    }
    private var binding: FluentBinding<Date>?
    private var observedBinding: FluentBinding<Date>?
    private var observerID: UUID?
    private var isApplyingBinding = false
    private var isPointerOver = false
    private var isPressed = false
    private var pointerTrackingArea: NSTrackingArea?
    private var calendarPopover: NSPopover?
    private weak var calendarMonthView: FluentCalendarPickerEditorView?
    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let visualStateCoordinator = FluentVisualStateCoordinator()
    private let contentLeadingPadding: CGFloat = 12
    private let glyphColumnWidth: CGFloat = 32

    init(date: Date, binding: FluentBinding<Date>?, minDate: Date?, maxDate: Date?, style: any FluentTextFieldStyle) {
        self.binding = binding
        super.init(frame: .zero)
        // CalendarDatePicker is a button-like date surface with a calendar flyout. Keep
        // NSDatePicker for parsing, keyboard and accessibility, but own every visible pixel.
        datePickerStyle = .textField
        datePickerMode = .single
        datePickerElements = [.yearMonthDay]
        if #available(macOS 10.15.4, *) { presentsCalendarOverlay = false }
        drawsBackground = false
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 0
        dateValue = date
        self.minDate = minDate
        self.maxDate = maxDate
        fluentStyle = style
        target = self
        action = #selector(valueChanged)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker")
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Date")
        visualStateCoordinator.reduceMotion = reduceMotion
        configureElevationBorder()
        installObserver()
        applyTheme()
        refreshAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    override func layout() {
        super.layout()
        synchronizeVisualGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeVisualGeometry()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        synchronizeVisualGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeVisualGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeVisualGeometry()
    }

    private func synchronizeVisualGeometry() {
        updateElevationBorderGeometry(for: resolvedButtonAppearance())
    }

    deinit {
        calendarPopover?.close()
        if let observerID { observedBinding?.removeObserver?(observerID) }
    }

    func update(binding: FluentBinding<Date>?, date: Date, minDate: Date?, maxDate: Date?, style: any FluentTextFieldStyle) {
        self.binding = binding
        self.minDate = minDate
        self.maxDate = maxDate
        self.fluentStyle = style
        let requested = binding?.get() ?? date
        if dateValue != requested {
            isApplyingBinding = true
            dateValue = requested
            isApplyingBinding = false
        }
        syncCalendarOverlay()
        installObserver()
        applyTheme()
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observedBinding = binding
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isApplyingBinding, self.dateValue != value else { return }
                self.isApplyingBinding = true
                self.dateValue = value
                self.isApplyingBinding = false
                self.syncCalendarOverlay()
                self.needsDisplay = true
            }
        }
    }

    @objc private func valueChanged() {
        guard !isApplyingBinding, let binding else { return }
        binding.set(dateValue)
        setAccessibilityValue(dateValue as NSDate)
        syncCalendarOverlay()
        needsDisplay = true
    }

    private func applyTheme() {
        let appearance = resolvedTextAppearance()
        controlSize = fluentControlSize.appKitSize
        font = appearance.font ?? theme.typography.font(for: .body).withSize(theme.typography.font(for: .body).pointSize * fluentControlSize.metricScale)
        textColor = resolvedButtonAppearance().foregroundColor
        invalidateIntrinsicContentSize()
        setAccessibilityValue(dateValue as NSDate)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = resolvedButtonAppearance()
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self),
           let focusRingColor = appearance.focusRingColor {
            focusRingColor.setStroke()
            let focusPath = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                xRadius: max(appearance.cornerRadius - 2, 0),
                yRadius: max(appearance.cornerRadius - 2, 0)
            )
            focusPath.lineWidth = appearance.focusRingWidth
            focusPath.stroke()
        }
        drawDateContent(appearance: appearance)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        refreshAppearance(animated: false)
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = false
        if !isPressed { refreshAppearance(animated: false) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        isPressed = true
        refreshAppearance(animated: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPressed = false
            self.refreshAppearance(animated: false)
            self.toggleCalendarPopover()
        }
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        refreshAppearance(animated: false)
        switch event.keyCode {
        case 36, 49:
            toggleCalendarPopover()
        case 53 where calendarPopover?.isShown == true:
            dismissCalendarPopover()
        default:
            super.keyDown(with: event)
        }
    }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        toggleCalendarPopover()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { refreshAppearance(animated: false) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { refreshAppearance(animated: false) }
        return result
    }

    override var isEnabled: Bool {
        didSet {
            isPressed = false
            if !isEnabled { dismissCalendarPopover() }
            applyTheme()
            refreshAppearance(animated: false)
        }
    }

    private func drawDateContent(appearance: FluentButtonAppearance) {
        let resolvedFont = resolvedTextAppearance().font
            ?? theme.typography.font(for: .body).withSize(
                theme.typography.font(for: .body).pointSize * fluentControlSize.metricScale
            )
        let value = DateFormatter.localizedString(from: dateValue, dateStyle: .short, timeStyle: .none)
        let valueSize = (value as NSString).size(withAttributes: [.font: resolvedFont])
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rightToLeft ? .right : .left
        let textRect = fluentSingleLineTextRect(
            NSRect(
                x: rightToLeft ? glyphColumnWidth : contentLeadingPadding,
                y: 0,
                width: max(bounds.width - glyphColumnWidth - contentLeadingPadding, 0),
                height: valueSize.height
            ),
            in: bounds,
            font: resolvedFont,
            topInset: 0,
            bottomInset: 2
        )
        (value as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: resolvedFont,
                .foregroundColor: appearance.foregroundColor,
                .paragraphStyle: paragraph
            ]
        )

        let glyphCenterX = rightToLeft ? bounds.minX + glyphColumnWidth / 2 : bounds.maxX - glyphColumnWidth / 2
        guard let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Choose date") else { return }
        // A non-optional Date is always in CalendarDatePicker's Selected state, which promotes
        // both date text and calendar glyph to the selected foreground resource.
        let color = appearance.foregroundColor
        let point = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let tint = NSImage.SymbolConfiguration(hierarchicalColor: color)
        image.withSymbolConfiguration(point.applying(tint))?.draw(
            in: NSRect(x: glyphCenterX - 6, y: bounds.midY - 6, width: 12, height: 12)
        )
    }

    private func toggleCalendarPopover() {
        if calendarPopover?.isShown == true {
            dismissCalendarPopover()
        } else {
            presentCalendarPopover()
        }
    }

    private func presentCalendarPopover() {
        guard isEnabled, window != nil else { return }
        let calendarMonthView = FluentCalendarPickerEditorView(
            selectedDate: dateValue,
            calendar: calendar ?? .current,
            locale: locale ?? .current,
            timeZone: timeZone ?? .current,
            minDate: minDate,
            maxDate: maxDate,
            theme: theme,
            onSelect: { [weak self] date in
                self?.calendarOverlayValueChanged(date)
            }
        )

        let padding: CGFloat = 8
        let contentSize = NSSize(width: 296, height: 280)
        let contentView = FluentMaterialView(
            frame: NSRect(origin: .zero, size: contentSize)
        )
        contentView.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        contentView.fluentTheme = theme
        contentView.isMaterialEnabled = theme.materialEffectsEnabled
        contentView.fallbackColor = theme.flyoutSurfaceFill
        contentView.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Popover")
        contentView.addSubview(calendarMonthView)
        calendarMonthView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            calendarMonthView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            calendarMonthView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            calendarMonthView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
            calendarMonthView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding)
        ])

        let controller = NSViewController()
        controller.view = contentView
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !reduceMotion
        popover.contentSize = contentSize
        popover.contentViewController = controller
        popover.delegate = self
        calendarPopover = popover
        self.calendarMonthView = calendarMonthView
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        setAccessibilityValue(dateValue as NSDate)
    }

    private func dismissCalendarPopover() {
        calendarPopover?.performClose(nil)
    }

    private func calendarOverlayValueChanged(_ date: Date) {
        isApplyingBinding = true
        dateValue = date
        isApplyingBinding = false
        binding?.set(date)
        setAccessibilityValue(date as NSDate)
        needsDisplay = true
        dismissCalendarPopover()
    }

    private func syncCalendarOverlay() {
        calendarMonthView?.setSelectedDate(dateValue)
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === calendarPopover else { return }
        calendarPopover = nil
        calendarMonthView = nil
        isPressed = false
        refreshAppearance(animated: false)
    }

    private var controlState: FluentControlState {
        if !isEnabled { return .disabled }
        if isPressed { return .pressed }
        if isPointerOver { return .pointerOver }
        if window?.firstResponder === self, FluentFocusVisibility.isKeyboardFocusVisible(for: self) {
            return .focused
        }
        return .normal
    }

    private func resolvedTextAppearance() -> FluentTextFieldAppearance {
        fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: isEnabled,
                isFocused: window?.firstResponder === self,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
    }

    private func resolvedButtonAppearance() -> FluentButtonAppearance {
        resolvedButtonAppearance(for: visualStateCoordinator.state.primaryControlState)
    }

    private func resolvedButtonAppearance(for state: FluentControlState) -> FluentButtonAppearance {
        FluentAutomaticButtonStyle().appearance(
            for: FluentButtonStyleConfiguration(
                title: "Date",
                controlState: state,
                isEnabled: isEnabled,
                theme: theme
            )
        )
    }

    private func refreshAppearance(animated: Bool) {
        visualStateCoordinator.reduceMotion = reduceMotion
        visualStateCoordinator.transition(
            to: .forControlState(controlState),
            animated: animated,
            motion: FluentMotion.controlFaster
        ) { [weak self] transition in
            self?.applyVisualState(transition)
        }
    }

    private func applyVisualState(_ transition: FluentVisualStateTransition) {
        guard let layer else { needsDisplay = true; return }
        let appearance = resolvedButtonAppearance(for: transition.to.primaryControlState)
        CATransaction.begin()
        // CalendarDatePicker uses discrete VisualState setters rather than BrushTransition.
        CATransaction.setDisableActions(true)
        layer.backgroundColor = appearance.backgroundColor.cgColor
        layer.borderWidth = 0
        layer.cornerRadius = appearance.cornerRadius
        layer.cornerCurve = .continuous
        elevationBorderLayer.colors = (appearance.borderGradientColors
            ?? [appearance.borderColor, appearance.borderColor]).map(\.cgColor)
        CATransaction.commit()
        updateElevationBorderGeometry(for: appearance)
        textColor = appearance.foregroundColor
        needsDisplay = true
    }

    private func configureElevationBorder() {
        elevationBorderLayer.name = "FluentKit.CalendarDatePicker.ElevationBorder"
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        layer?.addSublayer(elevationBorderLayer)
    }

    private func updateElevationBorderGeometry(for appearance: FluentButtonAppearance) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: bounds,
            appearance: appearance,
            visualYAxis: .resolved(for: self.layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        )
        CATransaction.commit()
    }
}

public func FluentDatePicker(
    selection: FluentBinding<Date>? = nil,
    date: Date = Date(),
    range: ClosedRange<Date>? = nil,
    style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()
) -> FluentDatePickerView {
    FluentDatePickerView(selection: selection, date: date, range: range, style: style)
}

/// Controls whether a ColorPicker is always expanded or presented from a compact flyout button.
public enum FluentColorPickerPresentationMode: String, CaseIterable, Hashable, Sendable {
    case inline
    case flyout
}

/// A WinUI-style color editor with a Fluent binding and accessibility metadata.
public struct FluentColorPickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<NSColor>?
    fileprivate let color: NSColor
    fileprivate let label: String
    fileprivate let presentation: FluentColorPickerPresentationMode

    public init(
        selection: FluentBinding<NSColor>? = nil,
        color: NSColor = .systemBlue,
        label: String = "Color",
        presentation: FluentColorPickerPresentationMode = .inline
    ) {
        self.binding = selection
        self.color = color
        self.label = label
        self.presentation = presentation
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        switch presentation {
        case .inline:
            let editor = FluentWinUIColorPickerEditorView(
                color: binding?.get() ?? color,
                theme: context.theme,
                onChange: { value in binding?.set(value) }
            )
            editor.setAccessibilityRole(.group)
            editor.setAccessibilityLabel(label)
            return editor
        case .flyout:
            return FluentColorPickerFlyoutHost(
                color: binding?.get() ?? color,
                binding: binding,
                label: label,
                theme: context.theme,
                reduceMotion: context.reduceMotion
            )
        }
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        switch presentation {
        case .inline:
            guard let editor = view as? FluentWinUIColorPickerEditorView else { return false }
            editor.setAccessibilityLabel(label)
            editor.update(
                color: binding?.get() ?? color,
                theme: context.theme,
                onChange: { value in binding?.set(value) }
            )
            return true
        case .flyout:
            guard let host = view as? FluentColorPickerFlyoutHost else { return false }
            host.update(
                color: binding?.get() ?? color,
                binding: binding,
                label: label,
                theme: context.theme,
                reduceMotion: context.reduceMotion
            )
            return true
        }
    }
}

public func FluentColorPicker(
    selection: FluentBinding<NSColor>? = nil,
    color: NSColor = .systemBlue,
    label: String = "Color",
    presentation: FluentColorPickerPresentationMode = .inline
) -> FluentColorPickerView {
    FluentColorPickerView(
        selection: selection,
        color: color,
        label: label,
        presentation: presentation
    )
}

private final class FluentColorPickerFlyoutHost: NSControl, NSPopoverDelegate {
    private var color: NSColor
    private var binding: FluentBinding<NSColor>?
    private var label: String
    private var theme: FluentTheme
    private var reduceMotion: Bool
    private var observedBinding: FluentBinding<NSColor>?
    private var observerID: UUID?
    private var popover: NSPopover?
    private weak var editor: FluentWinUIColorPickerEditorView?
    private var trackingAreaReference: NSTrackingArea?
    private var isPointerOver = false
    private var isPressed = false
    private let surfaceLayer = CALayer()
    private let strokeLayer = CAShapeLayer()
    private let swatchLayer = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()

    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 32) }

    init(
        color: NSColor,
        binding: FluentBinding<NSColor>?,
        label: String,
        theme: FluentTheme,
        reduceMotion: Bool
    ) {
        self.color = color
        self.binding = binding
        self.label = label
        self.theme = theme
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.FlyoutButton")
        setAccessibilityRole(.popUpButton)
        wantsLayer = true
        layer?.masksToBounds = false
        surfaceLayer.cornerCurve = .continuous
        swatchLayer.cornerCurve = .continuous
        layer?.addSublayer(surfaceLayer)
        layer?.addSublayer(strokeLayer)
        layer?.addSublayer(swatchLayer)
        titleLabel.alignment = .natural
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.setAccessibilityElement(false)
        addSubview(chevronView)
        installObserver()
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        popover?.close()
        if let observerID { observedBinding?.removeObserver?(observerID) }
    }

    override func layout() {
        super.layout()
        let radius = theme.designTokens.controlCornerRadius
        let swatchSize = min(20, max(0, bounds.height - 10))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = bounds
        surfaceLayer.cornerRadius = radius
        strokeLayer.frame = bounds
        strokeLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: max(radius - 0.5, 0),
            cornerHeight: max(radius - 0.5, 0),
            transform: nil
        )
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.lineWidth = 1
        swatchLayer.frame = CGRect(
            x: userInterfaceLayoutDirection == .rightToLeft ? bounds.maxX - 10 - swatchSize : 10,
            y: floor(bounds.midY - swatchSize / 2),
            width: swatchSize,
            height: swatchSize
        )
        swatchLayer.cornerRadius = 4
        CATransaction.commit()
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let textLeading: CGFloat = isRTL ? 30 : 40
        let textTrailing: CGFloat = isRTL ? 40 : 30
        let labelHeight = min(titleLabel.intrinsicContentSize.height, bounds.height)
        titleLabel.frame = CGRect(
            x: textLeading,
            y: floor(bounds.midY - labelHeight / 2),
            width: max(0, bounds.width - textLeading - textTrailing),
            height: labelHeight
        )
        chevronView.frame = CGRect(
            x: isRTL ? 12 : bounds.maxX - 22,
            y: floor(bounds.midY - 5),
            width: 10,
            height: 10
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        refreshAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        refreshAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        isPressed = true
        refreshAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        refreshAppearance()
        if inside { togglePopover() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        switch event.keyCode {
        case 36, 49: togglePopover()
        case 53: popover?.performClose(nil)
        default: super.keyDown(with: event)
        }
    }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        togglePopover()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        togglePopover()
        return true
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { popover?.performClose(nil) }
            refreshAppearance()
        }
    }

    func update(
        color: NSColor,
        binding: FluentBinding<NSColor>?,
        label: String,
        theme: FluentTheme,
        reduceMotion: Bool
    ) {
        self.color = color
        self.binding = binding
        self.label = label
        self.theme = theme
        self.reduceMotion = reduceMotion
        editor?.update(color: color, theme: theme, onChange: { [weak self] in self?.commit($0) })
        installObserver()
        refreshAppearance()
        needsLayout = true
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observedBinding = binding
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.color = value
                self.editor?.updateColor(value)
                self.refreshAppearance()
            }
        }
    }

    private func commit(_ value: NSColor) {
        color = value
        binding?.set(value)
        refreshAppearance()
    }

    private func togglePopover() {
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        guard isEnabled, window != nil else { return }
        let editor = FluentWinUIColorPickerEditorView(
            color: color,
            theme: theme,
            onChange: { [weak self] in self?.commit($0) }
        )
        let padding: CGFloat = 12
        let contentSize = NSSize(width: 344, height: 374)
        let content = FluentMaterialView(frame: CGRect(origin: .zero, size: contentSize))
        content.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        content.fluentTheme = theme
        content.isMaterialEnabled = theme.materialEffectsEnabled
        content.fallbackColor = theme.flyoutSurfaceFill
        content.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Popover")
        content.addSubview(editor)
        editor.frame = content.bounds.insetBy(dx: padding, dy: padding)
        editor.autoresizingMask = [.width, .height]
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !reduceMotion
        popover.contentSize = contentSize
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        self.editor = editor
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        refreshAppearance()
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        popover = nil
        editor = nil
        refreshAppearance()
    }

    private func refreshAppearance() {
        let state: FluentControlState = !isEnabled ? .disabled : (isPressed ? .pressed : (isPointerOver ? .pointerOver : .normal))
        let fill: NSColor
        switch state {
        case .disabled: fill = theme.controlFillDisabled
        case .pressed: fill = theme.controlFillTertiary
        case .pointerOver: fill = theme.controlFillSecondary
        default: fill = theme.controlFill
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.backgroundColor = fill.cgColor
        strokeLayer.strokeColor = theme.controlStrokeDefault.cgColor
        swatchLayer.backgroundColor = color.cgColor
        swatchLayer.borderColor = theme.controlStroke.cgColor
        swatchLayer.borderWidth = 1
        CATransaction.commit()
        titleLabel.stringValue = label
        titleLabel.font = theme.typography.font(for: .body)
        titleLabel.textColor = isEnabled ? theme.textPrimary : theme.textDisabled
        titleLabel.userInterfaceLayoutDirection = userInterfaceLayoutDirection
        let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Choose color")
        let point = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let tint = NSImage.SymbolConfiguration(
            hierarchicalColor: isEnabled ? theme.textSecondary : theme.textDisabled
        )
        chevronView.image = image?.withSymbolConfiguration(point.applying(tint))
        setAccessibilityLabel(label)
        setAccessibilityValue(String(describing: color))
        setAccessibilityExpanded(popover?.isShown == true)
        needsDisplay = true
        needsLayout = true
    }
}
