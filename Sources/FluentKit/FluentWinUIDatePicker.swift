import AppKit

/// WinUI `DatePicker` presents three independent looping selectors: day, month, and year.
/// This is intentionally distinct from the calendar-style ``FluentDatePickerView`` /
/// ``FluentDatePicker`` control, which models WinUI `CalendarDatePicker`.
public final class FluentWinUIDatePickerControl: NSControl, FluentControlSizeConfigurable, NSPopoverDelegate {
    public var selectedDate: Date? {
        didSet {
            if let selectedDate, let clamped = clampedSelection(selectedDate), clamped != selectedDate {
                self.selectedDate = clamped
            }
            guard oldValue != selectedDate else { return }
            if !isPropagatingDate {
                isPropagatingDate = true
                date = selectedDate
                isPropagatingDate = false
            }
            if !isApplyingBinding { binding?.set(selectedDate) }
            onSelectedDateChanged?(selectedDate)
            updateAccessibilityMetadata()
            needsLayout = true
            needsDisplay = true
        }
    }

    /// WinUI's `Date` property. It is kept in two-way lockstep with `SelectedDate`.
    public var date: Date? {
        didSet {
            guard oldValue != date else { return }
            if !isPropagatingDate {
                selectedDate = date
                if date != selectedDate { date = selectedDate }
            }
            needsDisplay = true
        }
    }

    public var minYear: Date? {
        didSet {
            guard oldValue != minYear else { return }
            if !isUpdatingConfiguration { coerceSelection() }
        }
    }

    public var maxYear: Date? {
        didSet {
            guard oldValue != maxYear else { return }
            if !isUpdatingConfiguration { coerceSelection() }
        }
    }

    public var dayFormat: String? {
        didSet {
            guard oldValue != dayFormat else { return }
            needsDisplay = true
        }
    }

    public var monthFormat: String? {
        didSet {
            guard oldValue != monthFormat else { return }
            needsDisplay = true
        }
    }

    public var yearFormat: String? {
        didSet {
            guard oldValue != yearFormat else { return }
            needsDisplay = true
        }
    }

    public var calendarIdentifier: String? {
        didSet {
            guard oldValue != calendarIdentifier else { return }
            if !isUpdatingConfiguration { coerceSelection() }
            needsDisplay = true
        }
    }

    public var yearVisible = true {
        didSet {
            guard oldValue != yearVisible else { return }
            updateAppearance()
            updateAccessibilityMetadata()
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

    public var onSelectedDateChanged: ((Date?) -> Void)?

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

    private var binding: FluentBinding<Date?>?
    private var observedBinding: FluentBinding<Date?>?
    private var observerID: UUID?
    private var observationGeneration: UInt64 = 0
    private var isUpdatingConfiguration = false
    private var isApplyingBinding = false
    private var isPropagatingDate = false
    private var isPointerOver = false
    private var isPressed = false
    private var isTrackingPress = false
    private var displayFont = FluentTheme.current.typography.font(for: .body)
    private var headerFont = FluentTheme.current.typography.font(for: .body)
    private let surfaceLayer = CALayer()
    private let elevationBorderLayer = CAGradientLayer()
    private let elevationBorderMask = CAShapeLayer()
    private let firstDividerLayer = CALayer()
    private let secondDividerLayer = CALayer()
    private let focusOuterLayer = CAShapeLayer()
    private let focusInnerLayer = CAShapeLayer()
    private var pickerPopover: NSPopover?
    private var pendingDate: Date?

    public init(
        selectedDate: Date? = nil,
        date: Date? = nil,
        minYear: Date? = nil,
        maxYear: Date? = nil,
        dayFormat: String? = nil,
        monthFormat: String? = nil,
        yearFormat: String? = nil,
        calendarIdentifier: String? = nil,
        yearVisible: Bool = true,
        header: String? = nil
    ) {
        self.selectedDate = selectedDate ?? date
        self.date = selectedDate ?? date
        self.minYear = minYear
        self.maxYear = maxYear
        self.dayFormat = dayFormat
        self.monthFormat = monthFormat
        self.yearFormat = yearFormat
        self.calendarIdentifier = calendarIdentifier
        self.yearVisible = yearVisible
        self.header = header
        super.init(frame: .zero)
        commonInit()
        coerceSelection()
    }

    fileprivate init(
        binding: FluentBinding<Date?>?,
        date: Date?,
        minYear: Date?,
        maxYear: Date?,
        dayFormat: String?,
        monthFormat: String?,
        yearFormat: String?,
        calendarIdentifier: String?,
        yearVisible: Bool,
        header: String?
    ) {
        self.binding = binding
        let value = binding.map { $0.get() } ?? date
        selectedDate = value
        self.date = value
        self.minYear = minYear
        self.maxYear = maxYear
        self.dayFormat = dayFormat
        self.monthFormat = monthFormat
        self.yearFormat = yearFormat
        self.calendarIdentifier = calendarIdentifier
        self.yearVisible = yearVisible
        self.header = header
        super.init(frame: .zero)
        commonInit()
        coerceSelection()
        synchronizeBinding()
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
        return NSSize(width: 296 * scale, height: buttonHeight + headerHeight)
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
        let appearance = resolvedAppearance
        let radius = appearance.cornerRadius

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = button
        surfaceLayer.cornerRadius = radius
        surfaceLayer.cornerCurve = .continuous

        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: button,
            appearance: appearance,
            visualYAxis: .resolved(for: layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        )

        let pixel = FluentPixelGeometry(backingScale: window?.backingScaleFactor).pixel
        let columns = fieldColumns(in: button)
        if columns.count >= 3 {
            firstDividerLayer.isHidden = false
            firstDividerLayer.frame = CGRect(
                x: columns[0].maxX,
                y: button.minY + pixel,
                width: pixel,
                height: max(0, button.height - pixel * 2)
            )
            secondDividerLayer.isHidden = !yearVisible
            secondDividerLayer.frame = CGRect(
                x: columns[1].maxX,
                y: button.minY + pixel,
                width: pixel,
                height: max(0, button.height - pixel * 2)
            )
        } else if columns.count == 2 {
            firstDividerLayer.isHidden = false
            firstDividerLayer.frame = CGRect(
                x: columns[0].maxX,
                y: button.minY + pixel,
                width: pixel,
                height: max(0, button.height - pixel * 2)
            )
            secondDividerLayer.isHidden = true
        }

        let outerRect = button.insetBy(dx: -3, dy: -3)
        focusOuterLayer.frame = bounds
        focusOuterLayer.path = CGPath(
            roundedRect: outerRect,
            cornerWidth: radius + 3,
            cornerHeight: radius + 3,
            transform: nil
        )
        focusOuterLayer.lineWidth = 2
        focusInnerLayer.frame = bounds
        focusInnerLayer.path = CGPath(
            roundedRect: button.insetBy(dx: 1, dy: 1),
            cornerWidth: max(radius - 1, 0),
            cornerHeight: max(radius - 1, 0),
            transform: nil
        )
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

        let button = buttonRect
        let columns = fieldColumns(in: button)
        let texts = closedFieldTexts
        let appearance = resolvedAppearance
        let foreground = selectedDate == nil
            ? (isEnabled ? theme.textSecondary : theme.textDisabled)
            : appearance.foregroundColor

        for index in 0..<min(columns.count, texts.count) {
            let column = columns[index]
            let isMonth = index == 1
            let leadingInset = isMonth ? 10 * fluentControlSize.metricScale : 0
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = isMonth ? .left : .center
            let rect = fluentSingleLineTextRect(
                CGRect(
                    x: column.minX + leadingInset,
                    y: column.minY,
                    width: max(column.width - leadingInset, 0),
                    height: column.height
                ),
                in: button,
                font: displayFont,
                topInset: 3 * fluentControlSize.metricScale,
                bottomInset: 6 * fluentControlSize.metricScale
            )
            (texts[index] as NSString).draw(in: rect, withAttributes: [
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
        binding: FluentBinding<Date?>?,
        date: Date?,
        minYear: Date?,
        maxYear: Date?,
        dayFormat: String?,
        monthFormat: String?,
        yearFormat: String?,
        calendarIdentifier: String?,
        yearVisible: Bool,
        header: String?
    ) {
        let requested = binding.map { $0.get() } ?? date
        isApplyingBinding = true
        isUpdatingConfiguration = true
        self.binding = binding
        self.minYear = minYear
        self.maxYear = maxYear
        self.dayFormat = dayFormat
        self.monthFormat = monthFormat
        self.yearFormat = yearFormat
        self.calendarIdentifier = calendarIdentifier
        self.yearVisible = yearVisible
        self.header = header
        isUpdatingConfiguration = false
        if selectedDate != requested {
            isApplyingBinding = true
            selectedDate = requested
            isApplyingBinding = false
        } else {
            coerceSelection()
        }
        isApplyingBinding = false
        synchronizeBinding()
        installObserver()
    }

    private var buttonRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: theme.controlHeight(for: fluentControlSize))
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
            title: "Date",
            controlState: controlState,
            isEnabled: isEnabled,
            theme: theme
        ))
    }

    private var resolvedCalendar: Calendar {
        var calendar = Calendar(identifier: FluentWinUIDatePickerControl.calendar(forIdentifier: calendarIdentifier))
        calendar.locale = .current
        calendar.timeZone = .current
        return calendar
    }

    var resolvedYearRange: ClosedRange<Int>? {
        let calendar = resolvedCalendar
        let lowerDate = minYear ?? calendar.date(byAdding: .year, value: -100, to: Date()) ?? Date()
        let upperDate = maxYear ?? calendar.date(byAdding: .year, value: 100, to: Date()) ?? Date()
        let lower = calendar.component(.year, from: lowerDate)
        let upper = calendar.component(.year, from: upperDate)
        guard lower <= upper else { return nil }
        return lower...upper
    }

    var hasValidYearRange: Bool { resolvedYearRange != nil }

    var closedFieldTexts: [String] {
        guard hasValidYearRange else { return yearVisible ? ["", "", ""] : ["", ""] }
        guard let selectedDate else {
            return yearVisible ? ["day", "month", "year"] : ["day", "month"]
        }
        let texts = [
            FluentWinUIDatePickerControl.format(dayFormat ?? "{day.integer}", field: .day, date: selectedDate, calendar: resolvedCalendar),
            FluentWinUIDatePickerControl.format(monthFormat ?? "{month.full}", field: .month, date: selectedDate, calendar: resolvedCalendar),
            FluentWinUIDatePickerControl.format(yearFormat ?? "{year.full}", field: .year, date: selectedDate, calendar: resolvedCalendar)
        ]
        return yearVisible ? texts : Array(texts.prefix(2))
    }

    private func fieldColumns(in button: CGRect) -> [CGRect] {
        let pixel = FluentPixelGeometry(backingScale: window?.backingScaleFactor).pixel
        if yearVisible {
            let totalWeight: CGFloat = 78 + 132 + 78
            let available = max(0, button.width - pixel * 2)
            let dayWidth = available * 78 / totalWeight
            let monthWidth = available * 132 / totalWeight
            let yearWidth = available * 78 / totalWeight
            let day = CGRect(x: button.minX, y: button.minY, width: dayWidth, height: button.height)
            let month = CGRect(
                x: button.minX + dayWidth + pixel,
                y: button.minY,
                width: monthWidth,
                height: button.height
            )
            let year = CGRect(
                x: button.minX + dayWidth + pixel + monthWidth + pixel,
                y: button.minY,
                width: yearWidth,
                height: button.height
            )
            return [day, month, year]
        }
        let available = max(0, button.width - pixel)
        let dayWidth = available * 78 / 210
        let monthWidth = available * 132 / 210
        return [
            CGRect(x: button.minX, y: button.minY, width: dayWidth, height: button.height),
            CGRect(
                x: button.minX + dayWidth + pixel,
                y: button.minY,
                width: monthWidth,
                height: button.height
            )
        ]
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
        surfaceLayer.name = "FluentKit.WinUIDatePicker.Surface"
        elevationBorderLayer.name = "FluentKit.WinUIDatePicker.ElevationBorder"
        firstDividerLayer.name = "FluentKit.WinUIDatePicker.FirstDivider"
        secondDividerLayer.name = "FluentKit.WinUIDatePicker.SecondDivider"
        focusOuterLayer.name = "FluentKit.WinUIDatePicker.FocusOuter"
        focusInnerLayer.name = "FluentKit.WinUIDatePicker.FocusInner"
        configureFluentElevationBorderLayer(elevationBorderLayer, mask: elevationBorderMask)
        layer?.addSublayer(surfaceLayer)
        layer?.addSublayer(elevationBorderLayer)
        layer?.addSublayer(firstDividerLayer)
        layer?.addSublayer(secondDividerLayer)
        for focus in [focusOuterLayer, focusInnerLayer] {
            focus.fillColor = NSColor.clear.cgColor
            focus.opacity = 0
            layer?.addSublayer(focus)
        }
        setAccessibilityRole(.popUpButton)
        fluentSetDefaultAccessibilityLabel("Date")
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
        surfaceLayer.cornerRadius = appearance.cornerRadius
        let dividerColor = (isEnabled ? theme.divider : theme.controlStrokeStrongDisabled).cgColor
        firstDividerLayer.backgroundColor = dividerColor
        secondDividerLayer.backgroundColor = dividerColor
        secondDividerLayer.isHidden = !yearVisible
        let showFocus = FluentFocusVisibility.isKeyboardFocusVisible(for: self)
        focusOuterLayer.strokeColor = theme.focusStrokeOuter.cgColor
        focusInnerLayer.strokeColor = theme.focusStrokeInner.cgColor
        focusOuterLayer.opacity = showFocus ? 1 : 0
        focusInnerLayer.opacity = showFocus ? 1 : 0
        CATransaction.commit()
        updateElevationBorder()
        needsLayout = true
        needsDisplay = true
    }

    private func updateElevationBorder() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFluentElevationBorderLayer(
            elevationBorderLayer,
            mask: elevationBorderMask,
            bounds: buttonRect,
            appearance: resolvedAppearance,
            visualYAxis: .resolved(for: layer, fallbackView: self),
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        )
        CATransaction.commit()
    }

    private func synchronizeBinding() {
        guard let binding, !isApplyingBinding, binding.get() != selectedDate else { return }
        isApplyingBinding = true
        binding.set(selectedDate)
        isApplyingBinding = false
    }

    private func installObserver() {
        observationGeneration &+= 1
        let generation = observationGeneration
        if let observerID { observedBinding?.removeObserver(observerID) }
        observedBinding = binding
        observerID = binding?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observationGeneration == generation, !self.isApplyingBinding,
                      let binding = self.binding else { return }
                let value = binding.get()
                guard self.selectedDate != value else { return }
                self.isApplyingBinding = true
                self.selectedDate = value
                self.isApplyingBinding = false
                self.synchronizeBinding()
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
        guard isEnabled, window != nil, hasValidYearRange else { return }
        let initial = clampedSelection(selectedDate ?? Date()) ?? (selectedDate ?? Date())
        pendingDate = initial

        let flyout = FluentWinUIDatePickerFlyout(
            date: initial,
            minYear: minYear,
            maxYear: maxYear,
            dayFormat: dayFormat,
            monthFormat: monthFormat,
            yearFormat: yearFormat,
            calendarIdentifier: calendarIdentifier,
            yearVisible: yearVisible,
            theme: theme,
            reduceMotion: reduceMotion
        )
        flyout.identifier = NSUserInterfaceItemIdentifier("FluentKit.WinUIDatePicker.Popover")
        flyout.onAccept = { [weak self] date in
            guard let self else { return }
            self.selectedDate = date
            self.pickerPopover?.performClose(nil)
        }
        flyout.onDismiss = { [weak self] in
            self?.pickerPopover?.performClose(nil)
        }

        let controller = NSViewController()
        controller.view = flyout
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !reduceMotion
        popover.contentSize = flyout.intrinsicContentSize
        popover.contentViewController = controller
        popover.delegate = self
        pickerPopover = popover
        updateAccessibilityMetadata()
        popover.show(relativeTo: buttonRect, of: self, preferredEdge: .minY)
    }

    private func coerceSelection() {
        guard let selectedDate else { return }
        guard let clamped = clampedSelection(selectedDate), clamped != selectedDate else { return }
        isApplyingBinding = true
        self.selectedDate = clamped
        isApplyingBinding = false
    }

    private func clampedSelection(_ value: Date?) -> Date? {
        guard let value, let range = resolvedYearRange else { return value }
        let calendar = resolvedCalendar
        let year = calendar.component(.year, from: value)
        guard year < range.lowerBound || year > range.upperBound else { return value }

        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: value)
        if year < range.lowerBound {
            return FluentWinUIDatePickerControl.boundaryDate(
                year: range.lowerBound,
                isStart: true,
                calendar: calendar,
                time: time
            )
        }
        return FluentWinUIDatePickerControl.boundaryDate(
            year: range.upperBound,
            isStart: false,
            calendar: calendar,
            time: time
        )
    }

    private func updateAccessibilityMetadata() {
        setAccessibilityLabel(header?.isEmpty == false ? header : "Date")
        if let selectedDate {
            setAccessibilityValue(FluentWinUIDatePickerControl.accessibilityDateString(selectedDate))
        } else {
            fluentSetDefaultAccessibilityValue("No date selected")
        }
        setAccessibilityExpanded(pickerPopover?.isShown == true)
    }

    public func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === pickerPopover else { return }
        pickerPopover = nil
        pendingDate = nil
        isPressed = false
        updateAccessibilityMetadata()
        updateAppearance()
    }

    fileprivate static func calendar(forIdentifier identifier: String?) -> Calendar.Identifier {
        guard let identifier else { return .gregorian }
        let normalized = identifier.lowercased().replacingOccurrences(of: "calendar", with: "")
        switch normalized {
        case "gregorian": return .gregorian
        case "buddhist": return .buddhist
        case "chinese", "chineselunar", "chineselunisolar": return .chinese
        case "hebrew": return .hebrew
        case "islamic": return .islamic
        case "islamicumalqura": return .islamicUmmAlQura
        case "islamiccivil": return .islamicCivil
        case "islamictabular": return .islamicTabular
        case "japanese": return .japanese
        case "persian": return .persian
        case "republicofchina": return .republicOfChina
        default: return .gregorian
        }
    }

    private static func boundaryDate(
        year: Int,
        isStart: Bool,
        calendar: Calendar,
        time: DateComponents
    ) -> Date? {
        let components = DateComponents(year: year, hour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0)
        guard let firstDay = calendar.date(from: components) else { return nil }
        if isStart { return firstDay }
        guard let nextYear = calendar.date(byAdding: DateComponents(year: 1), to: firstDay) else { return nil }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: nextYear) ?? firstDay
        return lastDay
    }

    static func format(
        _ pattern: String,
        field: FluentWinUIDateField,
        date: Date,
        calendar: Calendar
    ) -> String {
        let normalized: String
        switch (field, pattern) {
        case (.day, "day"): normalized = "{day.integer}"
        case (.month, "month"): normalized = "{month.full}"
        case (.year, "year"), (.year, "year.full"): normalized = "{year.full}"
        default: normalized = pattern
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone

        let values: [(String, String)] = [
            ("{dayofweek.full}", {
                formatter.dateFormat = "EEEE"
                return formatter.string(from: date)
            }()),
            ("{dayofweek.abbreviated}", {
                formatter.dateFormat = "EEE"
                return formatter.string(from: date)
            }()),
            ("{month.full}", {
                formatter.dateFormat = "MMMM"
                return formatter.string(from: date)
            }()),
            ("{month.abbreviated}", {
                formatter.dateFormat = "MMM"
                return formatter.string(from: date)
            }()),
            ("{day.integer}", String(calendar.component(.day, from: date))),
            ("{year.full}", String(calendar.component(.year, from: date)))
        ]

        return values.reduce(normalized) { partial, pair in
            partial.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    static func accessibilityDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum FluentWinUIDateField: Hashable, Sendable {
    case day
    case month
    case year
}

/// The transactional three-column presenter shown by ``FluentWinUIDatePickerControl``.
final class FluentWinUIDatePickerFlyout: NSView {
    var onAccept: ((Date) -> Void)?
    var onDismiss: (() -> Void)?

    private let initialDate: Date
    private let minYear: Date?
    private let maxYear: Date?
    private let dayFormat: String?
    private let monthFormat: String?
    private let yearFormat: String?
    private let calendarIdentifier: String?
    private let yearVisible: Bool
    private let theme: FluentTheme
    private let reduceMotion: Bool
    private var pendingDate: Date
    private let material = FluentMaterialView()
    private let highlight = NSView()
    private let firstDivider = NSView()
    private let secondDivider = NSView()
    private let footerDivider = NSView()
    private let daySelector = FluentWinUILoopingSelector()
    private let monthSelector = FluentWinUILoopingSelector()
    private let yearSelector = FluentWinUILoopingSelector()
    private let acceptButton = FluentWinUIDatePickerFlyoutButton(iconName: "checkmark", label: "Accept")
    private let dismissButton = FluentWinUIDatePickerFlyoutButton(iconName: "xmark", label: "Dismiss")
    private var years: [Int] = []
    private var isRefreshing = false
    private let itemHeight: CGFloat = 40
    private let footerHeight: CGFloat = 41

    init(
        date: Date,
        minYear: Date?,
        maxYear: Date?,
        dayFormat: String?,
        monthFormat: String?,
        yearFormat: String?,
        calendarIdentifier: String?,
        yearVisible: Bool,
        theme: FluentTheme,
        reduceMotion: Bool
    ) {
        initialDate = date
        pendingDate = date
        self.minYear = minYear
        self.maxYear = maxYear
        self.dayFormat = dayFormat
        self.monthFormat = monthFormat
        self.yearFormat = yearFormat
        self.calendarIdentifier = calendarIdentifier
        self.yearVisible = yearVisible
        self.theme = theme
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 296, height: 398)
    }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        material.frame = bounds
        let topRegion = CGRect(x: 0, y: footerHeight, width: bounds.width, height: bounds.height - footerHeight)
        let columns = columnFrames(in: topRegion)
        if columns.count == 3 {
            daySelector.frame = columns[0]
            monthSelector.frame = columns[1]
            yearSelector.frame = columns[2]
            firstDivider.frame = CGRect(x: columns[0].maxX, y: topRegion.minY, width: 2, height: topRegion.height)
            secondDivider.frame = CGRect(x: columns[1].maxX, y: topRegion.minY, width: 2, height: topRegion.height)
            firstDivider.isHidden = false
            secondDivider.isHidden = false
        } else if columns.count == 2 {
            daySelector.frame = columns[0]
            monthSelector.frame = columns[1]
            firstDivider.frame = CGRect(x: columns[0].maxX, y: topRegion.minY, width: 2, height: topRegion.height)
            firstDivider.isHidden = false
            secondDivider.isHidden = true
        }
        highlight.frame = CGRect(
            x: 4,
            y: topRegion.minY + (topRegion.height - itemHeight) / 2,
            width: max(bounds.width - 8, 0),
            height: itemHeight
        )
        footerDivider.frame = CGRect(x: 0, y: footerHeight - 2, width: bounds.width, height: 2)
        acceptButton.frame = CGRect(x: 0, y: 0, width: bounds.width / 2, height: footerHeight)
        dismissButton.frame = CGRect(
            x: bounds.width / 2,
            y: 0,
            width: bounds.width / 2,
            height: footerHeight
        )
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = theme.buttonCornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = theme.isHighContrast ? 2 : 1
        layer?.borderColor = theme.surfaceStrokeFlyout.cgColor

        material.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        material.fluentTheme = theme
        material.isMaterialEnabled = theme.materialEffectsEnabled
        material.fallbackColor = theme.flyoutSurfaceFill
        addSubview(material)

        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = theme.loopingSelectorItemSelectedBackground.cgColor
        highlight.layer?.cornerRadius = theme.buttonCornerRadius
        highlight.layer?.cornerCurve = .continuous
        addSubview(highlight)

        for view in [daySelector, monthSelector, yearSelector, firstDivider, secondDivider, footerDivider, acceptButton, dismissButton] {
            addSubview(view)
        }
        firstDivider.wantsLayer = true
        secondDivider.wantsLayer = true
        footerDivider.wantsLayer = true
        for divider in [firstDivider, secondDivider, footerDivider] {
            divider.layer?.backgroundColor = theme.divider.cgColor
        }

        for selector in [daySelector, monthSelector, yearSelector] {
            selector.theme = theme
            selector.reduceMotion = reduceMotion
            selector.itemHeight = itemHeight
            selector.foreground = theme.loopingSelectorItemForeground
            selector.selectedForeground = theme.loopingSelectorItemSelectedForeground
            selector.secondaryForeground = theme.textSecondary
        }
        daySelector.alignment = .center
        monthSelector.alignment = .left
        yearSelector.alignment = .center
        daySelector.shouldLoop = true
        monthSelector.shouldLoop = true
        yearSelector.shouldLoop = false
        yearSelector.isHidden = !yearVisible
        daySelector.identifier = NSUserInterfaceItemIdentifier("FluentKit.WinUIDatePicker.DaySelector")
        monthSelector.identifier = NSUserInterfaceItemIdentifier("FluentKit.WinUIDatePicker.MonthSelector")
        yearSelector.identifier = NSUserInterfaceItemIdentifier("FluentKit.WinUIDatePicker.YearSelector")

        acceptButton.theme = theme
        dismissButton.theme = theme
        acceptButton.target = self
        dismissButton.target = self
        acceptButton.action = #selector(accept)
        dismissButton.action = #selector(dismiss)

        daySelector.onSelectionChanged = { [weak self] index in self?.dayChanged(index) }
        monthSelector.onSelectionChanged = { [weak self] index in self?.monthChanged(index) }
        yearSelector.onSelectionChanged = { [weak self] index in self?.yearChanged(index) }

        refreshValues()
    }

    private var resolvedCalendar: Calendar {
        var calendar = Calendar(identifier: FluentWinUIDatePickerControl.calendar(forIdentifier: calendarIdentifier))
        calendar.locale = .current
        calendar.timeZone = .current
        return calendar
    }

    private var yearRange: ClosedRange<Int>? {
        let calendar = resolvedCalendar
        let lowerDate = minYear ?? calendar.date(byAdding: .year, value: -100, to: Date()) ?? Date()
        let upperDate = maxYear ?? calendar.date(byAdding: .year, value: 100, to: Date()) ?? Date()
        let lower = calendar.component(.year, from: lowerDate)
        let upper = calendar.component(.year, from: upperDate)
        guard lower <= upper else { return nil }
        return lower...upper
    }

    private func columnFrames(in rect: CGRect) -> [CGRect] {
        if yearSelector.isHidden {
            let available = max(0, rect.width - 2)
            let dayWidth = available * 78 / 210
            return [
                CGRect(x: rect.minX, y: rect.minY, width: dayWidth, height: rect.height),
                CGRect(x: rect.minX + dayWidth + 2, y: rect.minY, width: available - dayWidth, height: rect.height)
            ]
        }
        let available = max(0, rect.width - 4)
        let dayWidth = available * 78 / 288
        let monthWidth = available * 132 / 288
        let yearWidth = available * 78 / 288
        return [
            CGRect(x: rect.minX, y: rect.minY, width: dayWidth, height: rect.height),
            CGRect(x: rect.minX + dayWidth + 2, y: rect.minY, width: monthWidth, height: rect.height),
            CGRect(x: rect.minX + dayWidth + 2 + monthWidth + 2, y: rect.minY, width: yearWidth, height: rect.height)
        ]
    }

    private func refreshValues() {
        guard let yearRange else {
            isRefreshing = true
            daySelector.values = []
            monthSelector.values = []
            yearSelector.values = []
            years = []
            isRefreshing = false
            return
        }

        let calendar = resolvedCalendar
        years = Array(yearRange)
        let currentYear = calendar.component(.year, from: pendingDate)
        let yearIndex = years.firstIndex(of: currentYear) ?? 0
        let selectedYear = years[yearIndex]
        let monthDates = months(for: selectedYear, calendar: calendar)
        let monthIndex = clampedMonthIndex(for: pendingDate, monthDates: monthDates, calendar: calendar)
        let monthDate = monthDates[monthIndex]
        let dayDates = days(in: monthDate, calendar: calendar)
        let dayIndex = clampedDayIndex(for: pendingDate, dayDates: dayDates, calendar: calendar)

        isRefreshing = true
        yearSelector.values = yearVisible
            ? years.map {
                FluentWinUIDatePickerControl.format(yearFormat ?? "{year.full}", field: .year, date: calendar.date(from: DateComponents(year: $0)) ?? Date(), calendar: calendar)
            }
            : []
        monthSelector.values = monthDates.map {
            FluentWinUIDatePickerControl.format(monthFormat ?? "{month.full}", field: .month, date: $0, calendar: calendar)
        }
        daySelector.values = dayDates.map {
            FluentWinUIDatePickerControl.format(dayFormat ?? "{day.integer}", field: .day, date: $0, calendar: calendar)
        }
        yearSelector.selectedIndex = yearIndex
        monthSelector.selectedIndex = monthIndex
        daySelector.selectedIndex = dayIndex
        isRefreshing = false
    }

    private func months(for year: Int, calendar: Calendar) -> [Date] {
        guard let start = calendar.date(from: DateComponents(year: year)) else { return [Date()] }
        var result: [Date] = []
        for offset in 0..<14 {
            guard let date = calendar.date(byAdding: .month, value: offset, to: start) else { break }
            if calendar.component(.year, from: date) == year {
                result.append(date)
            } else {
                break
            }
        }
        return result.isEmpty ? [start] : result
    }

    private func days(in month: Date, calendar: Calendar) -> [Date] {
        guard let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [month] }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: month) }
    }

    private func clampedMonthIndex(for date: Date, monthDates: [Date], calendar: Calendar) -> Int {
        guard !monthDates.isEmpty else { return 0 }
        let target = calendar.dateInterval(of: .month, for: date)?.start ?? date
        for (index, monthDate) in monthDates.enumerated() {
            if calendar.isDate(monthDate, equalTo: target, toGranularity: .month) { return index }
        }
        return min(max(0, monthDates.count - 1), 0)
    }

    private func clampedDayIndex(for date: Date, dayDates: [Date], calendar: Calendar) -> Int {
        guard !dayDates.isEmpty else { return 0 }
        let day = calendar.component(.day, from: date)
        return min(max(day - 1, 0), dayDates.count - 1)
    }

    private func dayChanged(_ index: Int) {
        guard !isRefreshing else { return }
        let calendar = resolvedCalendar
        let dayDates = days(in: currentMonthDate(calendar), calendar: calendar)
        guard dayDates.indices.contains(index) else { return }
        pendingDate = withTime(from: pendingDate, appliedTo: dayDates[index], calendar: calendar)
    }

    private func monthChanged(_ index: Int) {
        guard !isRefreshing else { return }
        let calendar = resolvedCalendar
        guard let year = years.first(where: { $0 == calendar.component(.year, from: pendingDate) }) else { return }
        let monthDates = months(for: year, calendar: calendar)
        guard monthDates.indices.contains(index) else { return }
        pendingDate = withTime(from: pendingDate, appliedTo: monthDates[index], calendar: calendar)
        refreshValues()
    }

    private func yearChanged(_ index: Int) {
        guard !isRefreshing else { return }
        guard years.indices.contains(index) else { return }
        let calendar = resolvedCalendar
        var components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: pendingDate)
        components.year = years[index]
        if let date = calendar.date(from: components) {
            pendingDate = date
        }
        refreshValues()
    }

    private func currentMonthDate(_ calendar: Calendar) -> Date {
        let monthDates = months(for: calendar.component(.year, from: pendingDate), calendar: calendar)
        let index = clampedMonthIndex(for: pendingDate, monthDates: monthDates, calendar: calendar)
        return monthDates[index]
    }

    private func withTime(from source: Date, appliedTo date: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: source)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
    }

    @objc private func accept() {
        guard yearRange != nil else { return }
        onAccept?(pendingDate)
    }

    @objc private func dismiss() {
        onDismiss?()
    }
}

/// WinUI-style vertical selector that keeps the selected item centered and can wrap at either end.
///
/// Picker flyouts use this control directly. Applications normally use the declarative
/// `FluentLoopingSelector` factory below.
public final class FluentLoopingSelectorControl: NSControl {
    public var onSelectionChanged: ((Int) -> Void)?
    public var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    public var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    public var itemHeight: CGFloat = 40 {
        didSet {
            itemHeight = max(itemHeight, 20)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public var visibleItemCount = 7 {
        didSet {
            visibleItemCount = max(3, visibleItemCount | 1)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    public override var alignment: NSTextAlignment { didSet { needsDisplay = true } }
    public var foreground = NSColor.labelColor { didSet { needsDisplay = true } }
    public var selectedForeground = NSColor.labelColor { didSet { needsDisplay = true } }
    public var secondaryForeground = NSColor.secondaryLabelColor { didSet { needsDisplay = true } }
    public var shouldLoop = true
    public var showsSelectionBackground = false { didSet { needsDisplay = true } }

    public var values: [String] = [] {
        didSet {
            if selectedIndex >= values.count { selectedIndex = values.isEmpty ? 0 : values.count - 1 }
            needsDisplay = true
        }
    }

    public var selectedIndex = 0 {
        didSet {
            let normalized = normalizedIndex(selectedIndex)
            if normalized != selectedIndex {
                selectedIndex = normalized
                return
            }
            guard oldValue != selectedIndex else { return }
            if !isSuppressingCallback { onSelectionChanged?(selectedIndex) }
            updateAccessibilityMetadata()
            needsDisplay = true
        }
    }

    private var dragStartY: CGFloat = 0
    private var dragStartOffset: CGFloat = 0
    private var dragStartIndex = 0
    private var contentOffset: CGFloat = 0
    private var isDragging = false
    private var isPointerOver = false
    private var isPressed = false
    private var isSuppressingCallback = false
    private var scrollSnapWorkItem: DispatchWorkItem?

    public convenience init() {
        self.init(frame: .zero)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        setAccessibilityRole(.list)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
        setAccessibilityRole(.list)
    }

    public override var isFlipped: Bool { false }
    public override var acceptsFirstResponder: Bool { isEnabled && !values.isEmpty }
    public override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: CGFloat(visibleItemCount) * itemHeight)
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isDragging = false
                isPressed = false
            }
            setAccessibilityEnabled(isEnabled)
            needsDisplay = true
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    /// Replace a selector's model without leaving a drag/snap from its previous model active.
    func setItems(_ items: [String], selection: Int, looping: Bool) {
        guard values != items || selectedIndex != selection || shouldLoop != looping else { return }
        scrollSnapWorkItem?.cancel()
        scrollSnapWorkItem = nil
        isDragging = false
        isPressed = false
        contentOffset = 0
        isSuppressingCallback = true
        shouldLoop = looping
        values = items
        selectedIndex = selection
        isSuppressingCallback = false
        updateAccessibilityMetadata()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        if showsSelectionBackground, !values.isEmpty {
            let token = isPressed
                ? theme.loopingSelectorItemPressedBackground
                : theme.loopingSelectorItemSelectedBackground
            // WinUI's selector background resources are translucent brushes. Multiplying their
            // alpha for Disabled preserves the token; replacing it with 1 made the selected row
            // an opaque black/white slab and obscured its content.
            let fill = isEnabled
                ? token
                : token.withAlphaComponent(token.alphaComponent * 0.45)
            fill.setFill()
            NSBezierPath(
                roundedRect: CGRect(
                    x: 4,
                    y: bounds.midY - itemHeight / 2,
                    width: max(bounds.width - 8, 0),
                    height: itemHeight
                ),
                xRadius: theme.buttonCornerRadius,
                yRadius: theme.buttonCornerRadius
            ).fill()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let centerY = bounds.midY + contentOffset
        let radius = visibleItemCount / 2
        for offset in -radius...radius {
            let proposedIndex = selectedIndex + offset
            let index: Int
            if shouldLoop {
                index = wrappedIndex(proposedIndex)
            } else {
                guard values.indices.contains(proposedIndex) else { continue }
                index = proposedIndex
            }
            guard values.indices.contains(index) else { continue }
            let rect = CGRect(
                x: 0,
                // AppKit's unflipped Y axis grows upward. A selector's semantic order grows
                // downward, so later items must use the opposite physical offset.
                y: centerY - CGFloat(offset) * itemHeight - itemHeight / 2,
                width: bounds.width,
                height: itemHeight
            )
            let isSelected = offset == 0
            let color: NSColor
            if !isEnabled {
                color = theme.textDisabled
            } else if isSelected, isPressed {
                color = theme.loopingSelectorItemPressedForeground
            } else if isSelected {
                color = selectedForeground
            } else if isPointerOver || isPressed {
                color = foreground
            } else {
                color = foreground.withAlphaComponent(0.92)
            }
            let textRect = fluentSingleLineTextRect(
                rect,
                in: rect,
                font: theme.typography.font(for: .body),
                topInset: 3,
                bottomInset: 6,
                leadingInset: alignment == .left ? 9 : 0
            )
            (values[index] as NSString).draw(in: textRect, withAttributes: [
                .font: theme.typography.font(for: .body),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }

        if isEnabled, isPointerOver || isPressed {
            drawNavigationArrow(
                name: "chevron.up",
                rect: CGRect(x: 0, y: bounds.maxY - 34, width: bounds.width, height: 34)
            )
            drawNavigationArrow(
                name: "chevron.down",
                rect: CGRect(x: 0, y: 0, width: bounds.width, height: 34)
            )
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        isPressed = false
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled, !values.isEmpty else { return }
        FluentFocusVisibility.markPointerInteraction(in: window)
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if point.y > bounds.maxY - 34 {
            step(by: -1)
            return
        }
        if point.y < 34 {
            step(by: 1)
            return
        }
        dragStartY = point.y
        dragStartOffset = contentOffset
        dragStartIndex = selectedIndex
        isDragging = true
        isPressed = true
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let delta = convert(event.locationInWindow, from: nil).y - dragStartY
        applyProposedOffset(dragStartOffset + delta, baseIndex: dragStartIndex)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if abs(point.y - dragStartY) < 3 {
            let tappedOffset = -Int(((point.y - bounds.midY) / itemHeight).rounded())
            if tappedOffset != 0 { step(by: tappedOffset) }
            contentOffset = 0
            needsDisplay = true
        } else {
            snapContentOffset()
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        guard isEnabled, !values.isEmpty else { return }
        scrollSnapWorkItem?.cancel()

        if !event.hasPreciseScrollingDeltas {
            guard event.scrollingDeltaY != 0 else { return }
            step(by: event.scrollingDeltaY < 0 ? 1 : -1)
            return
        }

        // NSEvent deltas describe the scroll direction, while content moves in the opposite
        // direction. Keeping that distinction explicit also makes precise and wheel scrolling
        // agree: scrolling down advances to the following item.
        applyProposedOffset(contentOffset - event.scrollingDeltaY, baseIndex: selectedIndex)
        if event.phase == .ended
            || event.phase == .cancelled
            || event.momentumPhase == .ended {
            snapContentOffset()
            return
        }

        // Trackpads deliver a stream of small deltas. Preserve the residual between
        // events and snap only after the stream ends instead of cancelling every delta.
        let workItem = DispatchWorkItem { [weak self] in self?.snapContentOffset() }
        scrollSnapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: workItem)
    }

    private func applyProposedOffset(_ proposed: CGFloat, baseIndex: Int) {
        var offset = proposed
        var index = baseIndex
        while offset <= -itemHeight / 2, canMoveIndex(index, by: -1) {
            index = wrappedIndex(index - 1)
            offset += itemHeight
        }
        while offset >= itemHeight / 2, canMoveIndex(index, by: 1) {
            index = wrappedIndex(index + 1)
            offset -= itemHeight
        }
        contentOffset = offset
        if index != selectedIndex { selectedIndex = index }
        needsDisplay = true
    }

    private func snapContentOffset() {
        guard abs(contentOffset) > 0.001 else { return }
        contentOffset = 0
        needsDisplay = true
    }

    private func step(by delta: Int) {
        guard canMoveIndex(selectedIndex, by: delta) else { return }
        selectedIndex = wrappedIndex(selectedIndex + delta)
        contentOffset = 0
        needsDisplay = true
    }

    private func canMoveIndex(_ index: Int, by delta: Int) -> Bool {
        shouldLoop || values.indices.contains(index + delta)
    }

    private func wrappedIndex(_ index: Int) -> Int {
        guard !values.isEmpty else { return 0 }
        if shouldLoop {
            let count = values.count
            return ((index % count) + count) % count
        }
        return min(max(index, 0), values.count - 1)
    }

    private func normalizedIndex(_ index: Int) -> Int {
        guard !values.isEmpty else { return 0 }
        return wrappedIndex(index)
    }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled, !values.isEmpty, !event.modifierFlags.contains(.option) else {
            super.keyDown(with: event)
            return
        }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        let page = max(Int((bounds.height / itemHeight / 2).rounded(.down)), 1)
        switch event.keyCode {
        case 126: step(by: -1)              // Up
        case 125: step(by: 1)               // Down
        case 116: step(by: -page)           // Page Up
        case 121: step(by: page)            // Page Down
        case 115: selectedIndex = 0          // Home
        case 119: selectedIndex = values.count - 1 // End
        default:
            super.keyDown(with: event)
            return
        }
        needsDisplay = true
    }

    public override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled, canMoveIndex(selectedIndex, by: 1) else { return false }
        step(by: 1)
        return true
    }

    public override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled, canMoveIndex(selectedIndex, by: -1) else { return false }
        step(by: -1)
        return true
    }

    private func drawNavigationArrow(name: String, rect: CGRect) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: secondaryForeground))
        symbol.withSymbolConfiguration(configuration)?.draw(
            in: NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private func updateAccessibilityMetadata() {
        setAccessibilityRole(.list)
        setAccessibilityValue(values.indices.contains(selectedIndex) ? values[selectedIndex] : "")
    }
}

/// Backwards-compatible internal name retained for picker editors and source-compatible tests.
typealias FluentWinUILoopingSelector = FluentLoopingSelectorControl

/// Declarative public LoopingSelector. Its centered item is bound by index and remains stable
/// when the item labels are refreshed.
public struct FluentLoopingSelectorView: FluentUpdatablePrimitiveView {
    private let values: [String]
    private let selection: FluentBinding<Int>?
    private let selectedIndex: Int
    private let shouldLoop: Bool
    private let itemHeight: CGFloat
    private let visibleItemCount: Int
    private let alignment: NSTextAlignment
    private let accessibilityLabel: String?

    public init(
        _ values: [String],
        selection: FluentBinding<Int>? = nil,
        selectedIndex: Int = 0,
        shouldLoop: Bool = true,
        itemHeight: CGFloat = 40,
        visibleItemCount: Int = 7,
        alignment: NSTextAlignment = .center,
        accessibilityLabel: String? = nil
    ) {
        self.values = values
        self.selection = selection
        self.selectedIndex = selectedIndex
        self.shouldLoop = shouldLoop
        self.itemHeight = itemHeight
        self.visibleItemCount = visibleItemCount
        self.alignment = alignment
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let control = FluentLoopingSelectorControl()
        update(control, context: context)
        return control
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let control = view as? FluentLoopingSelectorControl else { return false }
        update(control, context: context)
        return true
    }

    private func update(_ control: FluentLoopingSelectorControl, context: FluentRenderContext) {
        control.theme = context.theme
        control.reduceMotion = context.reduceMotion
        control.values = values
        control.shouldLoop = shouldLoop
        control.itemHeight = itemHeight
        control.visibleItemCount = visibleItemCount
        control.alignment = alignment
        control.foreground = context.theme.loopingSelectorItemForeground
        control.selectedForeground = context.theme.loopingSelectorItemSelectedForeground
        control.secondaryForeground = context.theme.textSecondary
        control.showsSelectionBackground = true
        control.selectedIndex = selection?.get() ?? selectedIndex
        control.onSelectionChanged = { index in selection?.set(index) }
        control.setAccessibilityLabel(accessibilityLabel ?? "Looping selector")
    }
}

public func FluentLoopingSelector(
    _ values: [String],
    selection: FluentBinding<Int>? = nil,
    selectedIndex: Int = 0,
    shouldLoop: Bool = true,
    itemHeight: CGFloat = 40,
    visibleItemCount: Int = 7,
    alignment: NSTextAlignment = .center,
    accessibilityLabel: String? = nil
) -> FluentLoopingSelectorView {
    FluentLoopingSelectorView(
        values,
        selection: selection,
        selectedIndex: selectedIndex,
        shouldLoop: shouldLoop,
        itemHeight: itemHeight,
        visibleItemCount: visibleItemCount,
        alignment: alignment,
        accessibilityLabel: accessibilityLabel
    )
}

/// Flyout accept/dismiss button rendered with WinUI's subtle-fill template.
final class FluentWinUIDatePickerFlyoutButton: NSControl {
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    private let iconName: String
    private var isPointerOver = false
    private var isPressed = false

    init(iconName: String, label: String) {
        self.iconName = iconName
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.DateTimePickerFlyout.\(label)Button")
        wantsLayer = true
        layer?.cornerRadius = theme.buttonCornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if isPressed {
            fill = theme.subtleFillTertiary
        } else if isPointerOver {
            fill = theme.subtleFillSecondary
        } else {
            fill = .clear
        }
        fill.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: theme.buttonCornerRadius, yRadius: theme.buttonCornerRadius)
        path.fill()
        if theme.isHighContrast {
            theme.controlStrokeDefault.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        guard let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: theme.textPrimary))
        image.withSymbolConfiguration(configuration)?.draw(
            in: NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerOver = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isPointerOver = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        needsDisplay = true
        if inside, let action, let target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func performClick(_ sender: Any?) {
        if let action, let target { NSApp.sendAction(action, to: target, from: self) }
    }
}

/// Declarative WinUI-style three-column DatePicker.
public struct FluentWinUIDatePickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<Date?>?
    fileprivate let date: Date?
    fileprivate let minYear: Date?
    fileprivate let maxYear: Date?
    fileprivate let dayFormat: String?
    fileprivate let monthFormat: String?
    fileprivate let yearFormat: String?
    fileprivate let calendarIdentifier: String?
    fileprivate let yearVisible: Bool
    fileprivate let header: String?

    public init(
        selection: FluentBinding<Date?>? = nil,
        date: Date? = nil,
        minYear: Date? = nil,
        maxYear: Date? = nil,
        dayFormat: String? = nil,
        monthFormat: String? = nil,
        yearFormat: String? = nil,
        calendarIdentifier: String? = nil,
        yearVisible: Bool = true,
        header: String? = nil
    ) {
        self.binding = selection
        self.date = date
        self.minYear = minYear
        self.maxYear = maxYear
        self.dayFormat = dayFormat
        self.monthFormat = monthFormat
        self.yearFormat = yearFormat
        self.calendarIdentifier = calendarIdentifier
        self.yearVisible = yearVisible
        self.header = header
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let picker = FluentWinUIDatePickerControl(
            binding: binding,
            date: date,
            minYear: minYear,
            maxYear: maxYear,
            dayFormat: dayFormat,
            monthFormat: monthFormat,
            yearFormat: yearFormat,
            calendarIdentifier: calendarIdentifier,
            yearVisible: yearVisible,
            header: header
        )
        picker.theme = context.theme
        picker.reduceMotion = context.reduceMotion
        return picker
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let picker = view as? FluentWinUIDatePickerControl else { return false }
        picker.theme = context.theme
        picker.reduceMotion = context.reduceMotion
        picker.update(
            binding: binding,
            date: date,
            minYear: minYear,
            maxYear: maxYear,
            dayFormat: dayFormat,
            monthFormat: monthFormat,
            yearFormat: yearFormat,
            calendarIdentifier: calendarIdentifier,
            yearVisible: yearVisible,
            header: header
        )
        return true
    }
}

public func FluentWinUIDatePicker(
    selection: FluentBinding<Date?>? = nil,
    date: Date? = nil,
    minYear: Date? = nil,
    maxYear: Date? = nil,
    dayFormat: String? = nil,
    monthFormat: String? = nil,
    yearFormat: String? = nil,
    calendarIdentifier: String? = nil,
    yearVisible: Bool = true,
    header: String? = nil
) -> FluentWinUIDatePickerView {
    FluentWinUIDatePickerView(
        selection: selection,
        date: date,
        minYear: minYear,
        maxYear: maxYear,
        dayFormat: dayFormat,
        monthFormat: monthFormat,
        yearFormat: yearFormat,
        calendarIdentifier: calendarIdentifier,
        yearVisible: yearVisible,
        header: header
    )
}
