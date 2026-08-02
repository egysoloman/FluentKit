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
    private weak var calendarOverlayPicker: NSDatePicker?
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
        let overlayPicker = NSDatePicker(frame: .zero)
        overlayPicker.datePickerStyle = .clockAndCalendar
        overlayPicker.datePickerMode = .single
        overlayPicker.datePickerElements = [.yearMonthDay]
        overlayPicker.dateValue = dateValue
        overlayPicker.minDate = minDate
        overlayPicker.maxDate = maxDate
        overlayPicker.calendar = calendar
        overlayPicker.locale = locale
        overlayPicker.timeZone = timeZone
        overlayPicker.drawsBackground = false
        overlayPicker.isBordered = false
        overlayPicker.focusRingType = .none
        overlayPicker.target = self
        overlayPicker.action = #selector(calendarOverlayValueChanged(_:))
        overlayPicker.setAccessibilityLabel("Calendar")
        overlayPicker.sizeToFit()

        let padding: CGFloat = 8
        let pickerSize = overlayPicker.intrinsicContentSize
        let contentSize = NSSize(
            width: ceil(max(pickerSize.width, overlayPicker.frame.width) + padding * 2),
            height: ceil(max(pickerSize.height, overlayPicker.frame.height) + padding * 2)
        )
        let contentView = FluentMaterialView(
            frame: NSRect(origin: .zero, size: contentSize)
        )
        contentView.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        contentView.fluentTheme = theme
        contentView.isMaterialEnabled = theme.materialEffectsEnabled
        contentView.fallbackColor = theme.flyoutSurfaceFill
        contentView.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Popover")
        contentView.addSubview(overlayPicker)
        overlayPicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayPicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            overlayPicker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            overlayPicker.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
            overlayPicker.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding)
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
        calendarOverlayPicker = overlayPicker
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        setAccessibilityValue(dateValue as NSDate)
    }

    private func dismissCalendarPopover() {
        calendarPopover?.performClose(nil)
    }

    @objc private func calendarOverlayValueChanged(_ sender: NSDatePicker) {
        isApplyingBinding = true
        dateValue = sender.dateValue
        isApplyingBinding = false
        binding?.set(sender.dateValue)
        setAccessibilityValue(sender.dateValue as NSDate)
        needsDisplay = true
        dismissCalendarPopover()
    }

    private func syncCalendarOverlay() {
        guard let calendarOverlayPicker else { return }
        calendarOverlayPicker.dateValue = dateValue
        calendarOverlayPicker.minDate = minDate
        calendarOverlayPicker.maxDate = maxDate
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === calendarPopover else { return }
        calendarPopover = nil
        calendarOverlayPicker = nil
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

/// A native color well with a Fluent binding and accessibility metadata.
public struct FluentColorPickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<NSColor>?
    fileprivate let color: NSColor
    fileprivate let label: String

    public init(
        selection: FluentBinding<NSColor>? = nil,
        color: NSColor = .systemBlue,
        label: String = "Color"
    ) {
        self.binding = selection
        self.color = color
        self.label = label
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let well = FluentColorWellNative(color: binding?.get() ?? color, binding: binding, label: label)
        well.theme = context.theme
        return well
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let well = view as? FluentColorWellNative else { return false }
        well.theme = context.theme
        well.update(binding: binding, color: color, label: label)
        return true
    }
}

private final class FluentColorWellNative: NSColorWell {
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    private var binding: FluentBinding<NSColor>?
    private var observedBinding: FluentBinding<NSColor>?
    private var observerID: UUID?
    private var isApplyingBinding = false

    init(color: NSColor, binding: FluentBinding<NSColor>?, label: String) {
        self.binding = binding
        super.init(frame: .zero)
        self.color = color
        isBordered = false
        setAccessibilityRole(.colorWell)
        setAccessibilityLabel(label)
        target = self
        action = #selector(valueChanged)
        installObserver()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observerID { observedBinding?.removeObserver?(observerID) }
    }

    func update(binding: FluentBinding<NSColor>?, color: NSColor, label: String) {
        self.binding = binding
        setAccessibilityLabel(label)
        let requested = binding?.get() ?? color
        if self.color != requested {
            isApplyingBinding = true
            self.color = requested
            isApplyingBinding = false
        }
        installObserver()
        applyTheme()
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observedBinding = binding
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isApplyingBinding, self.color != value else { return }
                self.isApplyingBinding = true
                self.color = value
                self.isApplyingBinding = false
            }
        }
    }

    @objc private func valueChanged() {
        guard !isApplyingBinding, let binding else { return }
        binding.set(color)
        setAccessibilityValue(color)
    }

    private func applyTheme() {
        setAccessibilityValue(color)
        needsDisplay = true
    }
}

public func FluentColorPicker(
    selection: FluentBinding<NSColor>? = nil,
    color: NSColor = .systemBlue,
    label: String = "Color"
) -> FluentColorPickerView {
    FluentColorPickerView(selection: selection, color: color, label: label)
}
