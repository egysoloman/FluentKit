import AppKit

/// A date-independent time-of-day value used by ``FluentTimePicker``.
///
/// WinUI models `SelectedTime` as a nullable duration within a day. Keeping the value separate
/// from `Date` prevents a caller's calendar, date, or daylight-saving transition from leaking
/// into a time-only binding.
public struct FluentTime: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        precondition((0..<24).contains(hour), "FluentTime hour must be in 0..<24")
        precondition((0..<60).contains(minute), "FluentTime minute must be in 0..<60")
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: FluentTime, rhs: FluentTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public var description: String { String(format: "%02d:%02d", hour, minute) }

    /// Coerces minutes down to the nearest item represented by WinUI's MinuteIncrement.
    /// An increment of zero has WinUI's special meaning of a single `00` minute item.
    public func adjusted(toMinuteIncrement minuteIncrement: Int) -> FluentTime {
        let increment = minuteIncrement == 0 ? 60 : min(max(minuteIncrement, 1), 59)
        return FluentTime(hour: hour, minute: minute - minute % increment)
    }
}

/// The clock presentation used by ``FluentTimePicker``.
public enum FluentClockIdentifier: Hashable, Sendable {
    case system
    case twelveHour
    case twentyFourHour
}

/// A WinUI-style time picker with nullable selection, minute increments, and explicit 12/24-hour
/// presentation. The closed surface follows WinUI's equal-column template; the flyout uses the
/// native macOS time editor while retaining WinUI's confirm/dismiss transaction.
public final class FluentTimePicker: NSControl, FluentControlSizeConfigurable, NSPopoverDelegate, NSDatePickerCellDelegate {
    public var selectedTime: FluentTime? {
        didSet {
            let adjusted = selectedTime?.adjusted(toMinuteIncrement: minuteIncrement)
            if adjusted != selectedTime {
                selectedTime = adjusted
            }
            guard oldValue != selectedTime else { return }
            updateAccessibilityMetadata()
            needsDisplay = true
            if !isApplyingBinding { binding?.set(selectedTime) }
            onSelectedTimeChanged?(selectedTime)
        }
    }

    public var minuteIncrement: Int {
        get { storedMinuteIncrement }
        set {
            guard (0...59).contains(newValue) else { return }
            guard storedMinuteIncrement != newValue else { return }
            storedMinuteIncrement = newValue
            selectedTime = selectedTime?.adjusted(toMinuteIncrement: newValue)
            syncEditor()
        }
    }

    public var clockIdentifier: FluentClockIdentifier = .system {
        didSet {
            guard oldValue != clockIdentifier else { return }
            syncEditor()
            secondDividerLayer.isHidden = !usesTwelveHourClock
            updateAccessibilityMetadata()
            needsDisplay = true
        }
    }

    public var header: String? {
        didSet {
            guard oldValue != header else { return }
            invalidateIntrinsicContentSize()
            updateAccessibilityMetadata()
            needsLayout = true
            needsDisplay = true
        }
    }

    public var onSelectedTimeChanged: ((FluentTime?) -> Void)?
    public var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            updateFont()
            updateAppearance()
        }
    }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet { if reduceMotion { layer?.removeAllAnimations() } }
    }
    public var fluentControlSize: FluentControlSize = .regular {
        didSet {
            guard oldValue != fluentControlSize else { return }
            updateFont()
            invalidateIntrinsicContentSize()
            needsLayout = true
            needsDisplay = true
        }
    }

    private var storedMinuteIncrement: Int
    private var binding: FluentBinding<FluentTime?>?
    private var observedBinding: FluentBinding<FluentTime?>?
    private var observerID: UUID?
    private var isApplyingBinding = false
    private var isPointerOver = false
    private var isPressed = false
    private var isTrackingPress = false
    private var displayFont = FluentTheme.current.typography.font(for: .body)
    private var headerFont = FluentTheme.current.typography.font(for: .body)
    private let surfaceLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let firstDividerLayer = CALayer()
    private let secondDividerLayer = CALayer()
    private let focusOuterLayer = CAShapeLayer()
    private let focusInnerLayer = CAShapeLayer()
    private var pickerPopover: NSPopover?
    private weak var editorView: FluentTimePickerEditorView?
    private var pendingTime: FluentTime?

    public init(
        selectedTime: FluentTime? = nil,
        minuteIncrement: Int = 1,
        clockIdentifier: FluentClockIdentifier = .system,
        header: String? = nil,
        onSelectedTimeChanged: ((FluentTime?) -> Void)? = nil
    ) {
        storedMinuteIncrement = (0...59).contains(minuteIncrement) ? minuteIncrement : 1
        self.selectedTime = selectedTime?.adjusted(toMinuteIncrement: storedMinuteIncrement)
        self.clockIdentifier = clockIdentifier
        self.header = header
        self.onSelectedTimeChanged = onSelectedTimeChanged
        super.init(frame: .zero)
        commonInit()
    }

    fileprivate init(
        binding: FluentBinding<FluentTime?>?,
        time: FluentTime?,
        minuteIncrement: Int,
        clockIdentifier: FluentClockIdentifier,
        header: String?
    ) {
        storedMinuteIncrement = (0...59).contains(minuteIncrement) ? minuteIncrement : 1
        self.binding = binding
        selectedTime = (binding?.get() ?? time)?.adjusted(toMinuteIncrement: storedMinuteIncrement)
        self.clockIdentifier = clockIdentifier
        self.header = header
        super.init(frame: .zero)
        commonInit()
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        pickerPopover?.close()
        if let observerID { observedBinding?.removeObserver(observerID) }
    }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public override var intrinsicContentSize: NSSize {
        let scale = fluentControlSize.metricScale
        let buttonHeight = theme.controlHeight(for: fluentControlSize)
        let headerHeight = header.map { _ in ceil(headerFont.ascender - headerFont.descender) + 4 * scale } ?? 0
        return NSSize(width: 242 * scale, height: buttonHeight + headerHeight)
    }

    public override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            isPressed = false
            isTrackingPress = false
            if !isEnabled { pickerPopover?.performClose(nil) }
            updateAppearance()
        }
    }

    public override func layout() {
        super.layout()
        let button = buttonRect
        let radius = theme.designTokens.controlCornerRadius * fluentControlSize.metricScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = button
        surfaceLayer.cornerRadius = radius
        surfaceLayer.cornerCurve = .continuous
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: button.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
        borderLayer.lineWidth = 1

        let columnCount = usesTwelveHourClock ? 3 : 2
        let pixel = FluentPixelGeometry(backingScale: window?.backingScaleFactor).pixel
        let columnWidth = (button.width - CGFloat(columnCount - 1) * pixel) / CGFloat(columnCount)
        let firstX = button.minX + columnWidth
        firstDividerLayer.frame = CGRect(x: firstX, y: button.minY + pixel, width: pixel, height: max(0, button.height - pixel * 2))
        secondDividerLayer.isHidden = columnCount == 2
        secondDividerLayer.frame = CGRect(x: firstX + pixel + columnWidth, y: button.minY + pixel, width: pixel, height: max(0, button.height - pixel * 2))

        let outerRect = button.insetBy(dx: -2, dy: -2)
        focusOuterLayer.frame = bounds
        focusOuterLayer.path = CGPath(roundedRect: outerRect, cornerWidth: radius + 2, cornerHeight: radius + 2, transform: nil)
        focusOuterLayer.lineWidth = 2
        focusInnerLayer.frame = bounds
        focusInnerLayer.path = CGPath(roundedRect: button.insetBy(dx: 1, dy: 1), cornerWidth: max(radius - 1, 0), cornerHeight: max(radius - 1, 0), transform: nil)
        focusInnerLayer.lineWidth = 1
        CATransaction.commit()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: buttonRect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    public override func draw(_ dirtyRect: NSRect) {
        if let header, !header.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: isEnabled ? theme.textPrimary : theme.textDisabled
            ]
            let height = ceil(headerFont.ascender - headerFont.descender)
            let rect = CGRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
            (header as NSString).draw(in: rect, withAttributes: attributes)
        }

        let texts = displayColumns
        let button = buttonRect
        let count = texts.count
        let pixel = FluentPixelGeometry(backingScale: window?.backingScaleFactor).pixel
        let columnWidth = (button.width - CGFloat(count - 1) * pixel) / CGFloat(count)
        let foreground = displayForegroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        for (index, text) in texts.enumerated() {
            let x = button.minX + CGFloat(index) * (columnWidth + pixel)
            let rect = fluentSingleLineTextRect(
                CGRect(x: x, y: button.minY, width: columnWidth, height: button.height),
                in: button,
                font: displayFont,
                topInset: 3 * fluentControlSize.metricScale,
                bottomInset: 6 * fluentControlSize.metricScale
            )
            (text as NSString).draw(in: rect, withAttributes: [
                .font: displayFont,
                .foregroundColor: foreground,
                .paragraphStyle: paragraph
            ])
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = true
        updateAppearance()
    }

    public override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        isPointerOver = false
        if !isTrackingPress { isPressed = false }
        updateAppearance()
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled, buttonRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        isTrackingPress = true
        isPressed = true
        updateAppearance()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        let inside = buttonRect.contains(convert(event.locationInWindow, from: nil))
        isPointerOver = inside
        isPressed = inside
        updateAppearance()
    }

    public override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        let inside = buttonRect.contains(convert(event.locationInWindow, from: nil))
        isTrackingPress = false
        isPressed = false
        isPointerOver = inside
        updateAppearance()
        if inside { togglePopover() }
    }

    public override func keyDown(with event: NSEvent) {
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        let opensWithAltArrow = event.modifierFlags.contains(.option) && (event.keyCode == 125 || event.keyCode == 126)
        if opensWithAltArrow || event.keyCode == 36 || event.keyCode == 49 {
            togglePopover()
        } else if event.keyCode == 53, pickerPopover?.isShown == true {
            pickerPopover?.performClose(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    public override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        togglePopover()
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { updateAppearance() }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { updateAppearance() }
        return result
    }

    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        togglePopover()
        return true
    }

    fileprivate func update(
        binding: FluentBinding<FluentTime?>?,
        time: FluentTime?,
        minuteIncrement: Int,
        clockIdentifier: FluentClockIdentifier,
        header: String?
    ) {
        self.binding = binding
        self.minuteIncrement = minuteIncrement
        self.clockIdentifier = clockIdentifier
        self.header = header
        let value = (binding?.get() ?? time)?.adjusted(toMinuteIncrement: self.minuteIncrement)
        if selectedTime != value {
            isApplyingBinding = true
            selectedTime = value
            isApplyingBinding = false
        }
        installObserver()
    }

    private var buttonRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: theme.controlHeight(for: fluentControlSize))
    }

    private var usesTwelveHourClock: Bool {
        switch clockIdentifier {
        case .twelveHour: return true
        case .twentyFourHour: return false
        case .system:
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.dateFormat.contains("a")
        }
    }

    private var displayColumns: [String] {
        guard let selectedTime else {
            return usesTwelveHourClock ? ["hour", "minute", "period"] : ["hour", "minute"]
        }
        if usesTwelveHourClock {
            let hour = selectedTime.hour % 12 == 0 ? 12 : selectedTime.hour % 12
            return [String(hour), String(format: "%02d", selectedTime.minute), selectedTime.hour < 12 ? "AM" : "PM"]
        }
        return [String(format: "%02d", selectedTime.hour), String(format: "%02d", selectedTime.minute)]
    }

    var displayForegroundColor: NSColor {
        if !isEnabled { return theme.textDisabled }
        return selectedTime == nil ? theme.textSecondary : theme.textPrimary
    }

    private var controlState: FluentControlState {
        if !isEnabled { return .disabled }
        if isPressed { return .pressed }
        if isPointerOver { return .pointerOver }
        if FluentFocusVisibility.isKeyboardFocusVisible(for: self) { return .focused }
        return .normal
    }

    private var resolvedAppearance: FluentButtonAppearance {
        FluentAutomaticButtonStyle().appearance(for: FluentButtonStyleConfiguration(
            title: "Time",
            controlState: controlState,
            isEnabled: isEnabled,
            theme: theme
        ))
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
        for child in [surfaceLayer, borderLayer, firstDividerLayer, secondDividerLayer, focusOuterLayer, focusInnerLayer] {
            layer?.addSublayer(child)
        }
        surfaceLayer.name = "FluentKit.TimePicker.Surface"
        borderLayer.name = "FluentKit.TimePicker.Border"
        borderLayer.fillColor = NSColor.clear.cgColor
        firstDividerLayer.name = "FluentKit.TimePicker.FirstDivider"
        secondDividerLayer.name = "FluentKit.TimePicker.SecondDivider"
        for focus in [focusOuterLayer, focusInnerLayer] {
            focus.fillColor = NSColor.clear.cgColor
            focus.opacity = 0
        }
        focusOuterLayer.name = "FluentKit.TimePicker.FocusOuter"
        focusInnerLayer.name = "FluentKit.TimePicker.FocusInner"
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Time")
        updateFont()
        updateAccessibilityMetadata()
        updateAppearance()
    }

    private func updateFont() {
        let body = theme.typography.font(for: .body)
        displayFont = body.withSize(body.pointSize * fluentControlSize.metricScale)
        headerFont = displayFont
        invalidateIntrinsicContentSize()
    }

    private func updateAppearance() {
        let appearance = resolvedAppearance
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.backgroundColor = appearance.backgroundColor.cgColor
        borderLayer.strokeColor = appearance.borderColor.cgColor
        let dividerColor = (isEnabled ? theme.divider : theme.controlStrokeStrongDisabled).cgColor
        firstDividerLayer.backgroundColor = dividerColor
        secondDividerLayer.backgroundColor = dividerColor
        secondDividerLayer.isHidden = !usesTwelveHourClock
        let showFocus = FluentFocusVisibility.isKeyboardFocusVisible(for: self)
        focusOuterLayer.strokeColor = theme.focusStrokeOuter.cgColor
        focusInnerLayer.strokeColor = theme.focusStrokeInner.cgColor
        focusOuterLayer.opacity = showFocus ? 1 : 0
        focusInnerLayer.opacity = showFocus ? 1 : 0
        CATransaction.commit()
        needsLayout = true
        needsDisplay = true
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver(observerID) }
        observedBinding = binding
        observerID = binding?.observe { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let adjusted = value?.adjusted(toMinuteIncrement: self.minuteIncrement)
                guard self.selectedTime != adjusted else { return }
                self.isApplyingBinding = true
                self.selectedTime = adjusted
                self.isApplyingBinding = false
            }
        }
    }

    private func togglePopover() {
        if pickerPopover?.isShown == true {
            pickerPopover?.performClose(nil)
        } else {
            presentPopover()
        }
    }

    private func presentPopover() {
        guard isEnabled, window != nil else { return }
        pendingTime = selectedTime ?? currentTime().adjusted(toMinuteIncrement: minuteIncrement)
        let editorView = FluentTimePickerEditorView(
            time: pendingTime ?? FluentTime(hour: 0, minute: 0),
            minuteIncrement: minuteIncrement,
            clockIdentifier: clockIdentifier,
            locale: resolvedLocale,
            theme: theme
        ) { [weak self] time in
            self?.pendingTime = time
        }
        self.editorView = editorView

        let accept = FluentWinUIDatePickerFlyoutButton(iconName: "checkmark", label: "Accept")
        let dismiss = FluentWinUIDatePickerFlyoutButton(iconName: "xmark", label: "Dismiss")
        accept.theme = theme
        dismiss.theme = theme
        accept.target = self
        dismiss.target = self
        accept.action = #selector(acceptPendingTime)
        dismiss.action = #selector(dismissPendingTime)

        let content = FluentMaterialView(frame: CGRect(x: 0, y: 0, width: 242, height: 398))
        content.identifier = NSUserInterfaceItemIdentifier("FluentKit.TimePicker.Popover")
        content.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        content.fluentTheme = theme
        content.isMaterialEnabled = theme.materialEffectsEnabled
        content.fallbackColor = theme.flyoutSurfaceFill
        for view in [editorView, accept, dismiss] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = theme.divider.cgColor
        content.addSubview(separator)
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: content.topAnchor),
            editorView.heightAnchor.constraint(equalToConstant: 357),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: editorView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 2),
            accept.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            accept.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            accept.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.5),
            accept.topAnchor.constraint(equalTo: separator.bottomAnchor),
            dismiss.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            dismiss.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            dismiss.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.5),
            dismiss.topAnchor.constraint(equalTo: separator.bottomAnchor)
        ])

        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !reduceMotion
        popover.contentSize = content.frame.size
        popover.contentViewController = controller
        popover.delegate = self
        pickerPopover = popover
        popover.show(relativeTo: buttonRect, of: self, preferredEdge: .minY)
    }

    @objc private func acceptPendingTime() {
        selectedTime = pendingTime
        pickerPopover?.performClose(nil)
    }

    @objc private func dismissPendingTime() {
        pickerPopover?.performClose(nil)
    }

    public func datePickerCell(
        _ datePickerCell: NSDatePickerCell,
        validateProposedDateValue proposedDateValue: AutoreleasingUnsafeMutablePointer<NSDate>,
        timeInterval proposedTimeInterval: UnsafeMutablePointer<TimeInterval>?
    ) {
        let adjusted = time(from: proposedDateValue.pointee as Date).adjusted(toMinuteIncrement: minuteIncrement)
        proposedDateValue.pointee = date(from: adjusted) as NSDate
    }

    public func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === pickerPopover else { return }
        pickerPopover = nil
        editorView = nil
        pendingTime = nil
        isPressed = false
        updateAccessibilityMetadata()
        updateAppearance()
    }

    private func syncEditor() {
        editorView?.updateTheme(theme)
    }

    private var resolvedLocale: Locale {
        switch clockIdentifier {
        case .system: return .current
        case .twelveHour: return Locale(identifier: "\(Locale.current.identifier)@hours=h12")
        case .twentyFourHour: return Locale(identifier: "\(Locale.current.identifier)@hours=h23")
        }
    }

    private func date(from time: FluentTime) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2011, month: 7, day: 15, hour: time.hour, minute: time.minute)) ?? Date()
    }

    private func time(from date: Date) -> FluentTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return FluentTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    private func currentTime() -> FluentTime {
        time(from: Date())
    }

    private func updateAccessibilityMetadata() {
        setAccessibilityLabel(header?.isEmpty == false ? header : "Time")
        setAccessibilityValue(selectedTime?.description ?? "No time selected")
        setAccessibilityExpanded(pickerPopover?.isShown == true)
    }
}

/// Declarative TimePicker surface. A `nil` binding value preserves WinUI's HasNoTime state.
public struct FluentTimePickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<FluentTime?>?
    fileprivate let time: FluentTime?
    fileprivate let minuteIncrement: Int
    fileprivate let clockIdentifier: FluentClockIdentifier
    fileprivate let header: String?

    public init(
        selection: FluentBinding<FluentTime?>? = nil,
        time: FluentTime? = nil,
        minuteIncrement: Int = 1,
        clockIdentifier: FluentClockIdentifier = .system,
        header: String? = nil
    ) {
        self.binding = selection
        self.time = time
        self.minuteIncrement = minuteIncrement
        self.clockIdentifier = clockIdentifier
        self.header = header
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let picker = FluentTimePicker(
            binding: binding,
            time: time,
            minuteIncrement: minuteIncrement,
            clockIdentifier: clockIdentifier,
            header: header
        )
        picker.theme = context.theme
        picker.reduceMotion = context.reduceMotion
        return picker
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let picker = view as? FluentTimePicker else { return false }
        picker.theme = context.theme
        picker.reduceMotion = context.reduceMotion
        picker.update(
            binding: binding,
            time: time,
            minuteIncrement: minuteIncrement,
            clockIdentifier: clockIdentifier,
            header: header
        )
        return true
    }
}
