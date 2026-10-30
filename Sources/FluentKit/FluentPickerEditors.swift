import AppKit

private struct FluentCalendarCellButtonStyle: FluentButtonStyle {
    func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance {
        let base = FluentAutomaticButtonStyle().appearance(for: configuration)
        return FluentButtonAppearance(
            backgroundColor: base.backgroundColor,
            foregroundColor: base.foregroundColor,
            borderColor: base.borderColor,
            borderGradientColors: base.borderGradientColors,
            borderGradientEdge: base.borderGradientEdge,
            borderWidth: base.borderWidth,
            cornerRadius: base.cornerRadius,
            contentInsets: NSEdgeInsetsZero,
            focusRingColor: base.focusRingColor,
            focusRingWidth: base.focusRingWidth
        )
    }
}

/// The hierarchical WinUI CalendarView: Month -> Year -> Decade. The month-year header is an
/// active button that drills upward; previous/next move by the current view's unit.
final class FluentCalendarPickerEditorView: NSView {
    private enum ViewMode { case month, year, decade }
    private enum CellKind {
        case none
        case date(Date)
        case month(Date)
        case year(Date)
    }

    var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            previousButton.theme = theme
            nextButton.theme = theme
            headerButton.theme = theme
            for label in weekdayLabels { label.textColor = theme.textSecondary }
            for button in dayButtons { button.theme = theme }
        }
    }

    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone
    let minDate: Date?
    let maxDate: Date?
    let onSelect: (Date) -> Void

    private var viewMode = ViewMode.month
    private var displayedDate: Date
    private var selectedDate: Date
    private let previousButton = FluentButton(title: "‹", role: .standard)
    private let nextButton = FluentButton(title: "›", role: .standard)
    private let headerButton = FluentButton(title: "", role: .standard)
    private var weekdayLabels: [NSTextField] = []
    private var dayButtons: [FluentButton] = []
    private var scrollAccumulator: CGFloat = 0
    private var scrollResetWorkItem: DispatchWorkItem?

    init(
        selectedDate: Date,
        displayedMonth: Date? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        minDate: Date? = nil,
        maxDate: Date? = nil,
        theme: FluentTheme = .current,
        onSelect: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.displayedDate = displayedMonth ?? selectedDate
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
        self.minDate = minDate
        self.maxDate = maxDate
        self.theme = theme
        self.onSelect = onSelect
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Calendar")

        previousButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.PreviousMonth")
        nextButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.NextMonth")
        previousButton.onClick = { [weak self] in self?.moveView(by: -1) }
        nextButton.onClick = { [weak self] in self?.moveView(by: 1) }
        previousButton.theme = theme
        nextButton.theme = theme
        addSubview(previousButton)
        addSubview(nextButton)

        headerButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Header")
        headerButton.theme = theme
        headerButton.font = .systemFont(ofSize: 14, weight: .semibold)
        headerButton.onClick = { [weak self] in self?.showUpperLevel() }
        addSubview(headerButton)

        let weekdaySymbols = calendar.shortStandaloneWeekdaySymbols
        for index in 0..<7 {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.font = .systemFont(ofSize: 11)
            label.textColor = theme.textSecondary
            label.stringValue = String(weekdaySymbols[index].prefix(2))
            weekdayLabels.append(label)
            addSubview(label)
        }
        for index in 0..<42 {
            let button = FluentButton(title: "", role: .standard)
            button.theme = theme
            button.fluentStyle = FluentCalendarCellButtonStyle()
            button.focusRingType = .none
            button.font = .systemFont(ofSize: 13)
            button.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Day.\(index)")
            button.onClick = { [weak self] in self?.selectCell(index) }
            dayButtons.append(button)
            addSubview(button)
        }
        updateCurrentView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 264) }

    override func layout() {
        super.layout()
        let headerHeight: CGFloat = 36
        let weekdayHeight: CGFloat = 20
        previousButton.frame = NSRect(x: 0, y: bounds.maxY - headerHeight, width: 36, height: 28)
        nextButton.frame = NSRect(x: bounds.maxX - 36, y: bounds.maxY - headerHeight, width: 36, height: 28)
        headerButton.frame = NSRect(
            x: 36,
            y: bounds.maxY - headerHeight,
            width: max(0, bounds.width - 72),
            height: 28
        )

        let weekdayTop = bounds.maxY - headerHeight - weekdayHeight
        let gridTop = bounds.minY
        let gridHeight = weekdayTop - gridTop
        for index in 0..<7 {
            weekdayLabels[index].frame = NSRect(
                x: CGFloat(index) * (bounds.width / 7),
                y: weekdayTop,
                width: bounds.width / 7,
                height: weekdayHeight
            )
            weekdayLabels[index].isHidden = viewMode != .month
        }
        switch viewMode {
        case .month:
            let columnWidth = bounds.width / 7
            let rowHeight = gridHeight / 6
            for index in 0..<42 {
                let row = index / 7
                let column = index % 7
                // AppKit's default coordinate system grows upward. Calendar rows are semantic
                // top-to-bottom, so row zero belongs directly below the weekday header.
                dayButtons[index].frame = NSRect(
                    x: CGFloat(column) * columnWidth + 2,
                    y: gridTop + CGFloat(5 - row) * rowHeight + 1,
                    width: max(0, columnWidth - 4),
                    height: max(0, rowHeight - 2)
                )
            }
        case .year, .decade:
            let columnWidth = bounds.width / 4
            let rowHeight = (gridHeight + weekdayHeight) / 3
            for index in 0..<42 {
                guard index < 12 else {
                    dayButtons[index].frame = .zero
                    continue
                }
                let row = index / 4
                let column = index % 4
                dayButtons[index].frame = NSRect(
                    x: CGFloat(column) * columnWidth + 3,
                    y: gridTop + CGFloat(2 - row) * rowHeight + 3,
                    width: max(0, columnWidth - 6),
                    height: max(0, rowHeight - 6)
                )
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollResetWorkItem?.cancel()
        if !event.hasPreciseScrollingDeltas {
            guard event.scrollingDeltaY != 0 else { return }
            moveView(by: event.scrollingDeltaY < 0 ? 1 : -1)
            return
        }

        scrollAccumulator += event.scrollingDeltaY
        let threshold: CGFloat = 20
        while abs(scrollAccumulator) >= threshold {
            let offset = scrollAccumulator < 0 ? 1 : -1
            moveView(by: offset)
            scrollAccumulator += scrollAccumulator < 0 ? threshold : -threshold
        }
        if event.phase == .ended
            || event.phase == .cancelled
            || event.momentumPhase == .ended {
            scrollAccumulator = 0
            return
        }
        let workItem = DispatchWorkItem { [weak self] in self?.scrollAccumulator = 0 }
        scrollResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: workItem)
    }

    func setSelectedDate(_ date: Date) {
        guard selectedDate != date else { return }
        selectedDate = date
        displayedDate = date
        viewMode = .month
        updateCurrentView()
    }

    private func moveView(by offset: Int) {
        switch viewMode {
        case .month:
            displayedDate = calendar.date(byAdding: .month, value: offset, to: displayedDate) ?? displayedDate
        case .year:
            displayedDate = calendar.date(byAdding: .year, value: offset, to: displayedDate) ?? displayedDate
        case .decade:
            displayedDate = calendar.date(byAdding: .year, value: offset * 10, to: displayedDate) ?? displayedDate
        }
        updateCurrentView()
    }

    private func showUpperLevel() {
        switch viewMode {
        case .month:
            viewMode = .year
            displayedDate = startOfYear(displayedDate)
        case .year:
            viewMode = .decade
            displayedDate = startOfDecade(displayedDate)
        case .decade:
            return
        }
        updateCurrentView()
    }

    private func selectCell(_ index: Int) {
        let state = cellState(at: index)
        switch state.kind {
        case .none:
            return
        case let .date(date):
            selectedDate = date
            updateCurrentView()
            onSelect(date)
        case let .month(date):
            displayedDate = date
            viewMode = .month
            updateCurrentView()
        case let .year(date):
            displayedDate = date
            viewMode = .year
            updateCurrentView()
        }
    }

    private func updateCurrentView() {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        switch viewMode {
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            headerButton.title = formatter.string(from: displayedDate)
        case .year:
            formatter.dateFormat = "yyyy"
            headerButton.title = formatter.string(from: displayedDate)
        case .decade:
            let year = calendar.component(.year, from: displayedDate)
            let start = year - year % 10
            headerButton.title = "\(start) – \(start + 9)"
        }
        for index in 0..<42 {
            let state = cellState(at: index)
            let button = dayButtons[index]
            switch state.kind {
            case .none:
                button.title = ""
                button.isEnabled = false
                button.isHidden = viewMode != .month
                button.role = .standard
            default:
                button.title = state.title
                button.isEnabled = state.isEnabled
                button.isHidden = false
                button.role = state.isSelected ? .primary : .standard
            }
        }
        needsLayout = true
    }

    private struct CellState {
        let title: String
        let kind: CellKind
        let isSelected: Bool
        let isEnabled: Bool
    }

    private func cellState(at index: Int) -> CellState {
        switch viewMode {
        case .month:
            let start = calendar.dateInterval(of: .month, for: displayedDate)?.start ?? displayedDate
            let firstWeekday = calendar.component(.weekday, from: start)
            let weekdayOffset = (firstWeekday - calendar.firstWeekday + 7) % 7
            let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: start) ?? start
            let date = calendar.date(byAdding: .day, value: index, to: gridStart) ?? gridStart
            guard calendar.isDate(date, equalTo: displayedDate, toGranularity: .month) else {
                return CellState(title: "", kind: .none, isSelected: false, isEnabled: false)
            }
            return CellState(
                title: "\(calendar.component(.day, from: date))",
                kind: .date(date),
                isSelected: calendar.isDate(date, equalTo: selectedDate, toGranularity: .day),
                isEnabled: isEnabled(date)
            )
        case .year:
            guard index < 12 else {
                return CellState(title: "", kind: .none, isSelected: false, isEnabled: false)
            }
            let start = startOfYear(displayedDate)
            let date = calendar.date(byAdding: .month, value: index, to: start) ?? start
            return CellState(
                title: String(calendar.shortMonthSymbols[index].prefix(3)),
                kind: .month(date),
                isSelected: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
                    && calendar.component(.year, from: date) == calendar.component(.year, from: selectedDate),
                isEnabled: monthRangeEnabled(date)
            )
        case .decade:
            guard index < 12 else {
                return CellState(title: "", kind: .none, isSelected: false, isEnabled: false)
            }
            let start = startOfDecade(displayedDate)
            let date = calendar.date(byAdding: .year, value: index, to: start) ?? start
            return CellState(
                title: "\(calendar.component(.year, from: date))",
                kind: .year(date),
                isSelected: calendar.component(.year, from: date) == calendar.component(.year, from: selectedDate),
                isEnabled: yearRangeEnabled(date)
            )
        }
    }

    private func startOfYear(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
    }

    private func startOfDecade(_ date: Date) -> Date {
        var components = calendar.dateComponents([.year], from: date)
        components.year = (components.year ?? 0) - (components.year ?? 0) % 10
        components.month = 1
        components.day = 1
        return calendar.date(from: components) ?? date
    }

    private func isEnabled(_ date: Date) -> Bool {
        if let minDate, calendar.compare(date, to: minDate, toGranularity: .day) == .orderedAscending {
            return false
        }
        if let maxDate, calendar.compare(date, to: maxDate, toGranularity: .day) == .orderedDescending {
            return false
        }
        return true
    }

    private func monthRangeEnabled(_ monthStart: Date) -> Bool {
        let range = calendar.dateInterval(of: .month, for: monthStart) ?? DateInterval()
        let end = range.end.addingTimeInterval(-1)
        if let minDate, end < minDate { return false }
        if let maxDate, range.start > maxDate { return false }
        return true
    }

    private func yearRangeEnabled(_ yearStart: Date) -> Bool {
        let range = calendar.dateInterval(of: .year, for: yearStart) ?? DateInterval()
        let end = range.end.addingTimeInterval(-1)
        if let minDate, end < minDate { return false }
        if let maxDate, range.start > maxDate { return false }
        return true
    }
}

/// A custom Fluent calendar month used by CalendarDatePicker's flyout. Day cells are real
/// FluentButton instances; only the grid math and weekday header remain calendar-owned.
final class FluentCalendarMonthEditorView: NSView {
    private enum DayState: Equatable {
        case empty
        case value(Date, isSelected: Bool)
    }

    var theme: FluentTheme = .current {
        didSet {
            guard oldValue != theme else { return }
            previousButton.theme = theme
            nextButton.theme = theme
            monthLabel.textColor = theme.textPrimary
            for label in weekdayLabels { label.textColor = theme.textSecondary }
            for button in dayButtons { button.theme = theme }
        }
    }

    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone
    let minDate: Date?
    let maxDate: Date?
    let onSelect: (Date) -> Void

    private var displayedMonth: Date
    private var selectedDate: Date
    private let previousButton = FluentButton(title: "‹", role: .standard)
    private let nextButton = FluentButton(title: "›", role: .standard)
    private let monthLabel = NSTextField(labelWithString: "")
    private var weekdayLabels: [NSTextField] = []
    private var dayButtons: [FluentButton] = []

    init(
        selectedDate: Date,
        displayedMonth: Date? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        minDate: Date? = nil,
        maxDate: Date? = nil,
        theme: FluentTheme = .current,
        onSelect: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.displayedMonth = displayedMonth ?? selectedDate
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
        self.minDate = minDate
        self.maxDate = maxDate
        self.theme = theme
        self.onSelect = onSelect
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Calendar")

        previousButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.PreviousMonth")
        nextButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.NextMonth")
        previousButton.onClick = { [weak self] in self?.moveMonth(by: -1) }
        nextButton.onClick = { [weak self] in self?.moveMonth(by: 1) }
        previousButton.theme = theme
        nextButton.theme = theme
        addSubview(previousButton)
        addSubview(nextButton)

        monthLabel.alignment = .center
        monthLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        monthLabel.textColor = theme.textPrimary
        monthLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.MonthLabel")
        addSubview(monthLabel)

        let weekdaySymbols = calendar.shortStandaloneWeekdaySymbols
        for index in 0..<7 {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.font = .systemFont(ofSize: 11)
            label.textColor = theme.textSecondary
            label.stringValue = String(weekdaySymbols[index].prefix(2))
            weekdayLabels.append(label)
            addSubview(label)
        }
        for index in 0..<42 {
            let button = FluentButton(title: "", role: .standard)
            button.theme = theme
            button.fluentStyle = FluentCalendarCellButtonStyle()
            button.focusRingType = .none
            button.font = .systemFont(ofSize: 13)
            button.identifier = NSUserInterfaceItemIdentifier("FluentKit.CalendarDatePicker.Day.\(index)")
            button.onClick = { [weak self] in self?.selectDay(index) }
            dayButtons.append(button)
            addSubview(button)
        }
        updateDisplayedMonth()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 280, height: 264)
    }

    override func layout() {
        super.layout()
        let headerHeight: CGFloat = 36
        let weekdayHeight: CGFloat = 20
        previousButton.frame = NSRect(x: 0, y: bounds.maxY - headerHeight, width: 36, height: 28)
        nextButton.frame = NSRect(x: bounds.maxX - 36, y: bounds.maxY - headerHeight, width: 36, height: 28)
        monthLabel.frame = NSRect(x: 36, y: bounds.maxY - headerHeight, width: max(0, bounds.width - 72), height: 28)

        let weekdayTop = bounds.maxY - headerHeight - weekdayHeight
        let dayTop = weekdayTop - (bounds.height - headerHeight - weekdayHeight) + 4
        let columnWidth = bounds.width / 7
        let dayHeight = (bounds.height - headerHeight - weekdayHeight - 4) / 6
        for index in 0..<7 {
            weekdayLabels[index].frame = NSRect(
                x: CGFloat(index) * columnWidth,
                y: weekdayTop,
                width: columnWidth,
                height: weekdayHeight
            )
        }
        for index in 0..<42 {
            let row = index / 7
            let column = index % 7
            dayButtons[index].frame = NSRect(
                x: CGFloat(column) * columnWidth + 2,
                y: dayTop + CGFloat(row) * dayHeight + 1,
                width: max(0, columnWidth - 4),
                height: max(0, dayHeight - 2)
            )
        }
    }

    func setSelectedDate(_ date: Date) {
        guard selectedDate != date else { return }
        selectedDate = date
        displayedMonth = date
        updateDisplayedMonth()
    }

    private func moveMonth(by offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
        updateDisplayedMonth()
    }

    private func selectDay(_ index: Int) {
        guard case let .value(date, _) = state(for: index), isEnabled(date) else { return }
        selectedDate = date
        updateDisplayedMonth()
        onSelect(date)
    }

    private func updateDisplayedMonth() {
        var calendar = calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.stringValue = formatter.string(from: displayedMonth)

        let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let firstWeekday = calendar.component(.weekday, from: start)
        let weekdayOffset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: start) ?? start
        for index in 0..<42 {
            let date = calendar.date(byAdding: .day, value: index, to: gridStart) ?? gridStart
            let state = calendar.isDate(date, equalTo: selectedDate, toGranularity: .day)
                ? DayState.value(date, isSelected: true)
                : (calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                    ? DayState.value(date, isSelected: false)
                    : .empty)
            let button = dayButtons[index]
            switch state {
            case .empty:
                button.title = ""
                button.isEnabled = false
                button.role = .standard
            case let .value(date, isSelected):
                button.title = "\(calendar.component(.day, from: date))"
                button.isEnabled = isEnabled(date)
                button.role = isSelected ? .primary : .standard
            }
        }
    }

    private func state(for index: Int) -> DayState {
        var calendar = calendar
        calendar.timeZone = timeZone
        let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let firstWeekday = calendar.component(.weekday, from: start)
        let weekdayOffset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: start) ?? start
        let date = calendar.date(byAdding: .day, value: index, to: gridStart) ?? gridStart
        guard calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month) else { return .empty }
        return .value(date, isSelected: calendar.isDate(date, equalTo: selectedDate, toGranularity: .day))
    }

    private func isEnabled(_ date: Date) -> Bool {
        if let minDate, date < minDate { return false }
        if let maxDate, date > maxDate { return false }
        return true
    }
}

/// A custom Fluent time editor built from three FluentList columns. It replaces the system
/// NSDatePicker stepper that used to live inside TimePicker's popover.
final class FluentTimePickerEditorView: NSView {
    let initialTime: FluentTime
    let minuteIncrement: Int
    let clockIdentifier: FluentClockIdentifier
    let locale: Locale
    var theme: FluentTheme
    let onChange: (FluentTime) -> Void

    private let hourValues: [Int]
    private let minuteValues: [Int]
    private let usesTwelveHour: Bool
    private let highlight = NSView()
    private let firstDivider = NSView()
    private let secondDivider = NSView()
    private let hourSelector = FluentWinUILoopingSelector()
    private let minuteSelector = FluentWinUILoopingSelector()
    private let periodSelector = FluentWinUILoopingSelector()

    init(
        time: FluentTime,
        minuteIncrement: Int,
        clockIdentifier: FluentClockIdentifier,
        locale: Locale,
        theme: FluentTheme,
        onChange: @escaping (FluentTime) -> Void
    ) {
        initialTime = time
        self.minuteIncrement = minuteIncrement
        self.clockIdentifier = clockIdentifier
        self.locale = locale
        self.theme = theme
        self.onChange = onChange

        usesTwelveHour = clockIdentifier == .twelveHour
            || (clockIdentifier == .system && Self.localeUsesTwelveHour(locale))
        hourValues = usesTwelveHour ? Array(1...12) : Array(0..<24)
        minuteValues = minuteIncrement == 0
            ? [0]
            : Array(stride(from: 0, to: 60, by: minuteIncrement))
        let initialHour = usesTwelveHour
            ? (time.hour % 12 == 0 ? 12 : time.hour % 12)
            : time.hour
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.TimePicker.Editor")
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = theme.loopingSelectorItemSelectedBackground.cgColor
        highlight.layer?.cornerRadius = theme.buttonCornerRadius
        for divider in [firstDivider, secondDivider] {
            divider.wantsLayer = true
            divider.layer?.backgroundColor = theme.divider.cgColor
        }
        addSubview(highlight)
        for selector in [hourSelector, minuteSelector, periodSelector] {
            selector.theme = theme
            selector.itemHeight = 40
            selector.foreground = theme.loopingSelectorItemForeground
            selector.selectedForeground = theme.loopingSelectorItemSelectedForeground
            selector.secondaryForeground = theme.textSecondary
            selector.shouldLoop = true
            addSubview(selector)
        }
        periodSelector.shouldLoop = false
        addSubview(firstDivider)
        addSubview(secondDivider)
        periodSelector.isHidden = !usesTwelveHour
        secondDivider.isHidden = !usesTwelveHour
        hourSelector.values = hourValues.map { String(format: "%02d", $0) }
        minuteSelector.values = minuteValues.map { String(format: "%02d", $0) }
        periodSelector.values = ["AM", "PM"]
        hourSelector.selectedIndex = hourValues.firstIndex(of: initialHour) ?? 0
        minuteSelector.selectedIndex = minuteValues.firstIndex(of: time.minute) ?? 0
        periodSelector.selectedIndex = time.hour < 12 ? 0 : 1
        hourSelector.onSelectionChanged = { [weak self] _ in self?.emitPending() }
        minuteSelector.onSelectionChanged = { [weak self] _ in self?.emitPending() }
        periodSelector.onSelectionChanged = { [weak self] _ in self?.emitPending() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 242, height: 357) }

    override func layout() {
        super.layout()
        let count: CGFloat = usesTwelveHour ? 3 : 2
        let dividerCount = count - 1
        let dividerWidth: CGFloat = 2
        let columnWidth = max(0, (bounds.width - dividerCount * dividerWidth) / count)
        highlight.frame = NSRect(
            x: 4,
            y: bounds.midY - 20,
            width: max(bounds.width - 8, 0),
            height: 40
        )
        hourSelector.frame = NSRect(x: 0, y: 0, width: columnWidth, height: bounds.height)
        firstDivider.frame = NSRect(x: columnWidth, y: 0, width: dividerWidth, height: bounds.height)
        minuteSelector.frame = NSRect(x: columnWidth + dividerWidth, y: 0, width: columnWidth, height: bounds.height)
        if usesTwelveHour {
            secondDivider.frame = NSRect(
                x: (columnWidth + dividerWidth) * 2 - dividerWidth,
                y: 0,
                width: dividerWidth,
                height: bounds.height
            )
            periodSelector.frame = NSRect(
                x: (columnWidth + dividerWidth) * 2,
                y: 0,
                width: columnWidth,
                height: bounds.height
            )
        }
    }

    func updateTheme(_ theme: FluentTheme) {
        self.theme = theme
        highlight.layer?.backgroundColor = theme.loopingSelectorItemSelectedBackground.cgColor
        for divider in [firstDivider, secondDivider] {
            divider.layer?.backgroundColor = theme.divider.cgColor
        }
        for selector in [hourSelector, minuteSelector, periodSelector] {
            selector.theme = theme
            selector.foreground = theme.loopingSelectorItemForeground
            selector.selectedForeground = theme.loopingSelectorItemSelectedForeground
            selector.secondaryForeground = theme.textSecondary
        }
        needsDisplay = true
    }

    private func emitPending() {
        let hourOption = hourValues[min(max(hourSelector.selectedIndex, 0), hourValues.count - 1)]
        let minuteOption = minuteValues[min(max(minuteSelector.selectedIndex, 0), minuteValues.count - 1)]
        let hour: Int
        if usesTwelveHour {
            let period = periodSelector.selectedIndex == 1 ? 12 : 0
            hour = (hourOption % 12) + period
        } else {
            hour = hourOption
        }
        onChange(FluentTime(hour: hour, minute: minuteOption))
    }

    private static func localeUsesTwelveHour(_ locale: Locale) -> Bool {
        DateFormatter.dateFormat(
            fromTemplate: "j",
            options: 0,
            locale: locale
        )?.contains("a") == true
    }
}

/// A WinUI ColorSpectrum-style hue/saturation surface. Brightness is controlled by the adjacent
/// third-dimension slider, matching the source ColorPicker template structure.
final class FluentColorSpectrumView: NSView {
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.55
            needsDisplay = true
        }
    }
    var color: NSColor = .white {
        didSet {
            guard color != oldValue else { return }
            needsDisplay = true
        }
    }
    var onSelect: ((NSColor) -> Void)?

    private var spectrumImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if spectrumImage == nil || spectrumImage?.size != bounds.size {
            spectrumImage = makeSpectrumImage(size: bounds.size)
        }
        spectrumImage?.draw(in: bounds)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if color.usingColorSpace(.sRGB)?.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) == nil {
            (hue, saturation, brightness, alpha) = (0, 0, 0, 1)
        }
        let point = CGPoint(x: hue * bounds.width, y: saturation * bounds.height)
        let indicator = NSBezierPath(
            ovalIn: NSRect(
                x: point.x - 7,
                y: point.y - 7,
                width: 14,
                height: 14
            )
        )
        NSColor.white.setStroke()
        indicator.lineWidth = 3
        indicator.stroke()
        NSColor.black.withAlphaComponent(0.4).setStroke()
        indicator.lineWidth = 1
        indicator.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        select(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        select(at: convert(event.locationInWindow, from: nil))
    }

    private func select(at point: NSPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let hue = min(max(point.x / bounds.width, 0), 1)
        let saturation = min(max(point.y / bounds.height, 0), 1)
        // The two-dimensional surface edits hue and saturation only. Preserve the third
        // dimension instead of silently forcing brightness to 100% on every pointer sample.
        let brightness = color.hsbComponents.brightness
        color = NSColor(
            calibratedHue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: 1
        )
        onSelect?(color)
        needsDisplay = true
    }

    private func makeSpectrumImage(size: NSSize) -> NSImage? {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }
        guard let pixels = representation.bitmapData else { return nil }
        for y in 0..<height {
            let saturation = height == 1 ? 1 : CGFloat(y) / CGFloat(height - 1)
            for x in 0..<width {
                let hue = width == 1 ? 1 : CGFloat(x) / CGFloat(width - 1)
                let color = NSColor(calibratedHue: hue, saturation: saturation, brightness: 1, alpha: 1)
                    .usingColorSpace(.deviceRGB) ?? NSColor.white
                let offset = y * width * 4 + x * 4
                pixels[offset] = UInt8(color.redComponent * 255)
                pixels[offset + 1] = UInt8(color.greenComponent * 255)
                pixels[offset + 2] = UInt8(color.blueComponent * 255)
                pixels[offset + 3] = 255
            }
        }
        return NSImage(size: size, flipped: false) { rect in
            representation.draw(in: rect)
            return true
        }
    }
}

/// The WinUI ColorPicker layout: spectrum, third-dimension (brightness) slider, hue and
/// saturation sliders, and a preview rectangle. All interactive parts are Fluent controls.
final class FluentWinUIColorPickerEditorView: NSControl {
    var theme: FluentTheme {
        didSet {
            guard oldValue != theme else { return }
            spectrum.layer?.borderColor = theme.controlStroke.cgColor
            preview.layer?.borderColor = theme.controlStroke.cgColor
            for slider in sliders { slider.theme = theme }
            for label in labels { label.textColor = theme.textSecondary }
        }
    }

    var onChange: (NSColor) -> Void
    private var pendingColor: NSColor
    private let spectrum: FluentColorSpectrumView
    private let preview = NSView()
    private let hueSlider: FluentSlider
    private let saturationSlider: FluentSlider
    private let brightnessSlider: FluentSlider
    private var sliders: [FluentSlider] { [hueSlider, saturationSlider, brightnessSlider] }
    private var labels: [NSTextField] = []
    private var isSyncing = false

    init(
        color: NSColor,
        theme: FluentTheme,
        onChange: @escaping (NSColor) -> Void
    ) {
        pendingColor = color
        self.theme = theme
        self.onChange = onChange
        spectrum = FluentColorSpectrumView(frame: .zero)
        let components = color.hsbComponents
        hueSlider = FluentSlider(value: Double(components.hue * 360), range: 0...360)
        saturationSlider = FluentSlider(value: Double(components.saturation * 100), range: 0...100)
        brightnessSlider = FluentSlider(value: Double(components.brightness * 100), range: 0...100)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Editor")
        spectrum.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Spectrum")
        preview.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Preview")

        spectrum.color = color
        spectrum.layer?.borderColor = theme.controlStroke.cgColor
        spectrum.onSelect = { [weak self] newColor in
            guard let self else { return }
            self.isSyncing = true
            self.pendingColor = newColor
            self.hueSlider.value = Double(newColor.hsbComponents.hue * 360)
            self.saturationSlider.value = Double(newColor.hsbComponents.saturation * 100)
            self.isSyncing = false
            self.preview.layer?.backgroundColor = newColor.cgColor
            self.onChange(newColor)
        }
        addSubview(spectrum)

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 5
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = theme.controlStroke.cgColor
        preview.layer?.backgroundColor = pendingColor.cgColor
        addSubview(preview)

        let titles = ["Hue", "Saturation", "Brightness"]
        for (index, slider) in sliders.enumerated() {
            slider.theme = theme
            slider.onValueChanged = { [weak self] _ in self?.emitColor() }
            slider.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Slider.\(index)")
            addSubview(slider)
            let label = NSTextField(labelWithString: titles[index])
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = theme.textSecondary
            addSubview(label)
            labels.append(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet {
            spectrum.isEnabled = isEnabled
            for slider in sliders { slider.isEnabled = isEnabled }
            preview.alphaValue = isEnabled ? 1 : 0.55
            for label in labels {
                label.textColor = isEnabled ? theme.textSecondary : theme.textDisabled
            }
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 350) }

    override func layout() {
        super.layout()
        let topMargin: CGFloat = 6
        let previewHeight: CGFloat = 26
        let previewGap: CGFloat = 10
        let labelWidth: CGFloat = 74
        let sliderHeight: CGFloat = 30
        let sliderSpacing: CGFloat = 4
        let spectrumGap: CGFloat = 12

        preview.frame = NSRect(
            x: 0,
            y: bounds.maxY - topMargin - previewHeight,
            width: bounds.width,
            height: previewHeight
        )

        // AppKit's native coordinate system grows upward. Arrange the rows bottom-up so Hue is
        // visually closest to the spectrum while Brightness stays at the bottom; this also keeps
        // every label outside the spectrum for arbitrarily constrained heights.
        for (index, slider) in sliders.enumerated() {
            let y = CGFloat(sliders.count - index - 1) * (sliderHeight + sliderSpacing)
            labels[index].frame = NSRect(x: 0, y: y + 4, width: labelWidth, height: 20)
            slider.frame = NSRect(
                x: labelWidth,
                y: y,
                width: max(0, bounds.width - labelWidth),
                height: sliderHeight
            )
        }
        let sliderStackHeight = CGFloat(sliders.count) * sliderHeight
            + CGFloat(max(sliders.count - 1, 0)) * sliderSpacing
        let spectrumY = sliderStackHeight + spectrumGap
        let spectrumTop = preview.frame.minY - previewGap
        spectrum.frame = NSRect(
            x: 0,
            y: spectrumY,
            width: bounds.width,
            height: max(0, spectrumTop - spectrumY)
        )
    }

    func updateColor(_ color: NSColor) {
        // Declarative binding updates are model synchronization, not user input. Writing through
        // `value` here used to invoke each slider's callback, write the color binding again, and
        // schedule another render indefinitely while dragging. Suppress callbacks and preserve an
        // active drag while bringing all three controls up to date.
        isSyncing = true
        defer { isSyncing = false }
        pendingColor = color
        spectrum.color = color
        preview.layer?.backgroundColor = color.cgColor
        let components = color.hsbComponents
        hueSlider.setValueFromBinding(Double(components.hue * 360), cancelInteraction: false)
        saturationSlider.setValueFromBinding(Double(components.saturation * 100), cancelInteraction: false)
        brightnessSlider.setValueFromBinding(Double(components.brightness * 100), cancelInteraction: false)
    }

    func update(color: NSColor, theme: FluentTheme, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        self.theme = theme
        updateColor(color)
    }

    private func emitColor() {
        guard !isSyncing else { return }
        let hue = CGFloat(hueSlider.value / 360)
        let saturation = CGFloat(saturationSlider.value / 100)
        let brightness = CGFloat(brightnessSlider.value / 100)
        let color = NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        pendingColor = color
        spectrum.color = color
        preview.layer?.backgroundColor = color.cgColor
        onChange(color)
    }
}

/// A custom Fluent color editor using three FluentSliders and a small palette. It replaces the
/// system NSColorPanel that NSColorWell would otherwise activate.
final class FluentColorPickerEditorView: NSView {
    var theme: FluentTheme {
        didSet {
            guard oldValue != theme else { return }
            for slider in sliders { slider.theme = theme }
            for label in labels { label.textColor = theme.textSecondary }
            preview.layer?.borderColor = theme.controlStroke.cgColor
            needsDisplay = true
        }
    }

    let onChange: (NSColor) -> Void
    private var pendingColor: NSColor
    private let preview = NSView()
    private let redSlider: FluentSlider
    private let greenSlider: FluentSlider
    private let blueSlider: FluentSlider
    private var sliders: [FluentSlider] { [redSlider, greenSlider, blueSlider] }
    private var labels: [NSTextField] = []
    private var swatches: [FluentColorSwatchButton] = []

    init(
        color: NSColor,
        theme: FluentTheme,
        onChange: @escaping (NSColor) -> Void
    ) {
        pendingColor = color
        self.theme = theme
        self.onChange = onChange
        let rgb = color.rgbComponents
        redSlider = FluentSlider(value: Double(rgb.red * 255), range: 0...255)
        greenSlider = FluentSlider(value: Double(rgb.green * 255), range: 0...255)
        blueSlider = FluentSlider(value: Double(rgb.blue * 255), range: 0...255)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Editor")

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 5
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = theme.controlStroke.cgColor
        preview.layer?.backgroundColor = pendingColor.cgColor
        addSubview(preview)

        let titles = ["R", "G", "B"]
        for (index, slider) in sliders.enumerated() {
            slider.theme = theme
            slider.minimumValue = 0
            slider.maximumValue = 255
            slider.onValueChanged = { [weak self] _ in self?.emitColor() }
            slider.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Slider.\(index)")
            addSubview(slider)
            let label = NSTextField(labelWithString: titles[index])
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = theme.textSecondary
            addSubview(label)
            labels.append(label)
        }

        let palette: [NSColor] = [
            .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
            .systemBlue, .systemPurple, .systemPink, .systemGray, .white
        ]
        for (index, paletteColor) in palette.enumerated() {
            let swatch = FluentColorSwatchButton(color: paletteColor)
            swatch.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Swatch.\(index)")
            swatch.onClick = { [weak self] in
                self?.updateColor(paletteColor)
            }
            addSubview(swatch)
            swatches.append(swatch)
        }
        updateSliders()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 176) }

    override func layout() {
        super.layout()
        preview.frame = NSRect(x: 0, y: bounds.maxY - 36, width: bounds.width, height: 30)
        let sliderHeight: CGFloat = 28
        let labelWidth: CGFloat = 18
        for (index, slider) in sliders.enumerated() {
            let y = bounds.maxY - 44 - CGFloat(index) * (sliderHeight + 4)
            labels[index].frame = NSRect(x: 0, y: y + 5, width: labelWidth, height: 18)
            slider.frame = NSRect(
                x: labelWidth,
                y: y,
                width: max(0, bounds.width - labelWidth),
                height: sliderHeight
            )
        }
        let swatchTop = bounds.maxY - 44 - 3 * 32 - 10
        let swatchSize: CGFloat = 24
        let swatchSpacing: CGFloat = 6
        for (index, swatch) in swatches.enumerated() {
            let column = index % 5
            let row = index / 5
            swatch.frame = NSRect(
                x: CGFloat(column) * (swatchSize + swatchSpacing),
                y: swatchTop - CGFloat(row) * (swatchSize + swatchSpacing),
                width: swatchSize,
                height: swatchSize
            )
        }
    }

    func updateColor(_ color: NSColor) {
        pendingColor = color
        preview.layer?.backgroundColor = color.cgColor
        updateSliders()
        onChange(color)
    }

    private func emitColor() {
        let red = CGFloat(redSlider.value / 255)
        let green = CGFloat(greenSlider.value / 255)
        let blue = CGFloat(blueSlider.value / 255)
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        pendingColor = color
        preview.layer?.backgroundColor = color.cgColor
        onChange(color)
    }

    private func updateSliders() {
        let rgb = pendingColor.rgbComponents
        redSlider.value = Double(rgb.red * 255)
        greenSlider.value = Double(rgb.green * 255)
        blueSlider.value = Double(rgb.blue * 255)
    }
}

private final class FluentColorSwatchButton: NSButton {
    var onClick: (() -> Void)?

    init(color: NSColor) {
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = color.luminance > 0.5
            ? NSColor.black.withAlphaComponent(0.18).cgColor
            : NSColor.white.withAlphaComponent(0.24).cgColor
        layer?.backgroundColor = color.cgColor
        target = self
        action = #selector(invoke)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invoke() { onClick?() }
}

private extension NSColor {
    var rgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let resolved = usingColorSpace(.sRGB) ?? self
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
    }

    var hsbComponents: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let resolved = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        return (hue, saturation, brightness)
    }

    var luminance: CGFloat {
        let rgb = rgbComponents
        return 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }
}
