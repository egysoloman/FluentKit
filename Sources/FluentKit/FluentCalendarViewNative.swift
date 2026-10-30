import AppKit

class FluentCalendarViewNative: NSControl {
    var theme: FluentTheme { didSet { if oldValue != theme { refresh() } } }
    private(set) var model: FluentCalendarModel
    private let identifierPrefix: String
    private var binding: FluentBinding<[Date]>?
    private var observerID: UUID?
    private var observationGeneration: UInt64 = 0
    private var requestedSelection: [Date]
    private var requestedDisplayDate: Date?
    private var requestedMode: FluentCalendarDisplayMode
    private var onSelectionChanged: (([Date]) -> Void)?
    var onDateInvoked: ((Date) -> Void)?
    var allowsDeselection = true
    private let previous = FluentCalendarButton()
    private let next = FluentCalendarButton()
    private let header = FluentCalendarButton()
    private var weekdays: [NSTextField] = []
    private var cells: [FluentCalendarButton] = []
    private var dates: [Date] = []
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollTime: TimeInterval?
    private var isApplyingBinding = false

    init(configuration: FluentCalendarConfiguration, selection: FluentBinding<[Date]>?, selectedDates: [Date],
         displayDate: Date?, displayMode: FluentCalendarDisplayMode, theme: FluentTheme,
         identifierPrefix: String = "FluentKit.CalendarView", onSelectionChanged: (([Date]) -> Void)?) {
        self.theme = theme
        self.model = FluentCalendarModel(configuration: configuration, selectedDates: selection?.get() ?? selectedDates,
            displayDate: displayDate, mode: displayMode)
        self.binding = selection
        self.requestedSelection = selectedDates
        self.requestedDisplayDate = displayDate
        self.requestedMode = displayMode
        self.identifierPrefix = identifierPrefix
        self.onSelectionChanged = onSelectionChanged
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Calendar")
        wantsLayer = true
        layer?.cornerRadius = 8
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        fluentSetDefaultAccessibilityLabel("Calendar")
        previous.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".PreviousMonth")
        next.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".NextMonth")
        header.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Header")
        previous.glyph = .up
        next.glyph = .down
        previous.fluentSetDefaultAccessibilityLabel("Previous")
        next.fluentSetDefaultAccessibilityLabel("Next")
        previous.onInvoke = { [weak self] in self?.moveView(-1) }
        next.onInvoke = { [weak self] in self?.moveView(1) }
        header.onInvoke = { [weak self] in self?.upperLevel() }
        header.isHeader = true
        [header, previous, next].forEach(addSubview)
        for index in 0..<7 {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Weekday.\(index)")
            weekdays.append(label)
            addSubview(label)
        }
        for index in 0..<42 {
            let cell = FluentCalendarButton()
            cell.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Day.\(index)")
            cell.onInvoke = { [weak self] in self?.activate(index) }
            cell.onFocus = { [weak self] in
                guard let self, self.dates.indices.contains(index) else { return }
                self.model.focusedDate = self.dates[index]
                for (cellIndex, cell) in self.cells.enumerated() { cell.participatesInTabOrder = cellIndex == index }
            }
            cell.onKey = { [weak self] event in self?.handleKey(event) ?? false }
            cells.append(cell)
            addSubview(cell)
        }
        synchronizeBinding()
        refresh()
        installObserver()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { removeObserver() }
    override var intrinsicContentSize: NSSize { NSSize(width: 310, height: 350) }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { false }
    override var isEnabled: Bool { didSet { if oldValue != isEnabled { refresh() } } }

    func update(configuration: FluentCalendarConfiguration, selection: FluentBinding<[Date]>?, selectedDates: [Date],
                displayDate: Date?, displayMode: FluentCalendarDisplayMode, theme: FluentTheme,
                onSelectionChanged: (([Date]) -> Void)?) {
        removeObserver()
        binding = selection
        self.onSelectionChanged = onSelectionChanged
        let oldModel = model
        let oldSelection = model.selectedDates
        model.configuration = configuration
        if let selection { model.selectedDates = selection.get() }
        else if selectedDates != requestedSelection { model.selectedDates = selectedDates }
        requestedSelection = selectedDates
        model.selectedDates = model.normalizedSelection(model.selectedDates)
        if displayDate != requestedDisplayDate, let displayDate {
            model.displayedDate = displayDate
            model.focusedDate = displayDate
        }
        if displayMode != requestedMode { model.mode = displayMode }
        requestedDisplayDate = displayDate
        requestedMode = displayMode
        model.displayedDate = model.clamped(model.displayedDate)
        model.focusedDate = model.clamped(model.focusedDate)
        let themeChanged = self.theme != theme
        self.theme = theme
        synchronizeBinding()
        if model != oldModel && !themeChanged { refresh() }
        installObserver()
        if oldSelection != model.selectedDates { onSelectionChanged?(model.selectedDates) }
    }

    func setSelectedDate(_ date: Date) {
        guard model.selectedDates != [date] else { return }
        model.selectedDates = model.normalizedSelection([date])
        model.displayedDate = model.clamped(date)
        model.focusedDate = model.displayedDate
        model.mode = .month
        refresh()
    }

    func updateLimits(minDate: Date?, maxDate: Date?) {
        guard model.configuration.minDate != minDate || model.configuration.maxDate != maxDate else { return }
        model.configuration.minDate = minDate
        model.configuration.maxDate = maxDate
        model.selectedDates = model.normalizedSelection(model.selectedDates)
        model.displayedDate = model.clamped(model.displayedDate)
        model.focusedDate = model.clamped(model.focusedDate)
        refresh()
    }

    private func removeObserver() {
        observationGeneration &+= 1
        if let observerID { binding?.removeObserver(observerID) }
        observerID = nil
    }
    private func installObserver() {
        let generation = observationGeneration
        observerID = binding?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observationGeneration == generation, !self.isApplyingBinding,
                      let binding = self.binding else { return }
                let old = self.model.selectedDates
                self.model.selectedDates = self.model.normalizedSelection(binding.get())
                self.synchronizeBinding()
                if old != self.model.selectedDates {
                    self.refresh()
                    self.onSelectionChanged?(self.model.selectedDates)
                }
            }
        }
    }
    private func synchronizeBinding() {
        guard let binding, !isApplyingBinding, binding.get() != model.selectedDates else { return }
        isApplyingBinding = true
        defer { isApplyingBinding = false }
        binding.set(model.selectedDates)
    }

    private func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = model.calendar
        formatter.locale = model.calendar.locale ?? .current
        formatter.timeZone = model.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private func refresh() {
        guard !cells.isEmpty else { return }
        layer?.backgroundColor = theme.textControlBackground(focused: true, enabled: true).cgColor
        layer?.borderColor = theme.controlStroke.cgColor
        layer?.borderWidth = theme.controlStrokeWidth
        let headerFormatter = formatter(model.mode == .month ? "MMMM y" : "y")
        let scope = model.scope(for: model.displayedDate)
        if model.mode == .decade {
            let last = model.calendar.date(byAdding: .year, value: -1, to: scope.end) ?? scope.start
            header.title = "\(headerFormatter.string(from: scope.start)) – \(headerFormatter.string(from: last))"
        } else { header.title = headerFormatter.string(from: model.displayedDate) }
        header.setAccessibilityLabel(header.title)
        header.isEnabled = isEnabled && model.mode != .decade
        previous.isEnabled = isEnabled && model.canMove(by: -1)
        next.isEnabled = isEnabled && model.canMove(by: 1)
        [header, previous, next].forEach { $0.theme = theme; $0.needsDisplay = true }
        let symbols = model.calendar.shortStandaloneWeekdaySymbols
        let abbreviated = symbols.map { String($0.prefix(2)) }
        // Some languages share a leading article (for example Arabic); truncating each name
        // would produce seven identical labels. Preserve the locale's complete short names then.
        let titles = Set(abbreviated).count == 7 ? abbreviated : symbols
        let caption = theme.typography.font(for: .caption)
        let weekdayFont = NSFont(descriptor: caption.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold.rawValue]
        ]), size: caption.pointSize) ?? caption
        for index in weekdays.indices {
            let dayIndex = (index + model.calendar.firstWeekday - 1) % 7
            weekdays[index].stringValue = titles[dayIndex]
            weekdays[index].setAccessibilityLabel(model.calendar.standaloneWeekdaySymbols[dayIndex])
            weekdays[index].font = weekdayFont
            weekdays[index].textColor = isEnabled ? theme.textPrimary : theme.textDisabled
            weekdays[index].isHidden = model.mode != .month
        }
        dates = model.cellDates
        let cellFormatter = formatter(model.mode == .month ? "d" : model.mode == .year ? "MMM" : "y")
        // Day/year cells contain numbers, not date phrases such as “12日” or “2026年”.
        // A fixed field pattern retains localized digits without adding the locale's date units.
        if model.mode == .month { cellFormatter.dateFormat = "d" }
        else if model.mode == .decade { cellFormatter.dateFormat = "y" }
        let fullDateFormatter = formatter("EEEE yMMMMd")
        for (index, cell) in cells.enumerated() {
            cell.isHidden = !dates.indices.contains(index)
            guard dates.indices.contains(index) else { cell.title = ""; continue }
            let date = dates[index]
            cell.title = cellFormatter.string(from: date)
            cell.theme = theme
            cell.roundDay = model.mode == .month
            cell.participatesInTabOrder = model.cellMatches(date, model.focusedDate)
            cell.isEnabled = isEnabled && model.cellIsAvailable(date)
            cell.blackout = model.mode == .month && model.isBlackout(date)
            cell.selected = model.mode == .month && model.selectedDates.contains { model.sameDay($0, date) }
            cell.today = model.mode == .month && model.configuration.isTodayHighlighted && model.calendar.isDateInToday(date)
            cell.outOfScope = date < scope.start || date >= scope.end
            cell.setAccessibilityLabel(fullDateFormatter.string(from: date))
            cell.setAccessibilityValue(cell.selected ? 1 : 0)
            cell.setAccessibilityHelp(cell.blackout ? "Unavailable date" : nil)
            cell.needsDisplay = true
        }
        setAccessibilityChildren([header, previous, next] + weekdays.filter { !$0.isHidden } + cells.filter { !$0.isHidden })
        setAccessibilityValue(header.title)
        if cells.contains(where: { window?.firstResponder === $0 }) { focusCurrentCell() }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width), height = max(0, bounds.height)
        let pad = min(8, min(width, height) / 2)
        let navSize = min(32, max(0, min((width - 2 * pad) / 3, height - 2 * pad)))
        let navY = max(pad, height - pad - navSize)
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let nextX = max(pad, width - pad - navSize)
        let previousX = max(pad, nextX - navSize - min(4, pad))
        func mirror(_ rect: NSRect) -> NSRect {
            NSRect(x: rtl ? width - rect.maxX : rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        }
        next.frame = mirror(NSRect(x: nextX, y: navY, width: navSize, height: navSize))
        previous.frame = mirror(NSRect(x: previousX, y: navY, width: navSize, height: navSize))
        header.frame = mirror(NSRect(x: pad, y: navY, width: max(0, previousX - 2 * pad), height: navSize))
        let headerHeight = min(48, max(0, height - 2 * pad))
        let weekdayHeight = model.mode == .month ? min(24, max(0, height - headerHeight - 2 * pad)) : 0
        let gridHeight = max(0, height - headerHeight - weekdayHeight - 2 * pad)
        let gridWidth = max(0, width - 2 * pad)
        for index in weekdays.indices {
            weekdays[index].frame = mirror(NSRect(x: pad + CGFloat(index) * gridWidth / 7,
                y: pad + gridHeight, width: gridWidth / 7, height: weekdayHeight))
        }
        let columns = model.mode == .month ? 7 : 4
        let rows = model.mode == .month ? 6 : 4
        let columnWidth = gridWidth / CGFloat(columns), rowHeight = gridHeight / CGFloat(rows)
        for (index, cell) in cells.enumerated() {
            guard dates.indices.contains(index) else { cell.frame = .zero; continue }
            let marginX = min(1, columnWidth / 2), marginY = min(1.5, rowHeight / 2)
            cell.frame = mirror(NSRect(x: pad + CGFloat(index % columns) * columnWidth + marginX,
                y: pad + CGFloat(rows - 1 - index / columns) * rowHeight + marginY,
                width: max(0, columnWidth - 2 * marginX), height: max(0, rowHeight - 2 * marginY)))
        }
    }

    private func moveView(_ offset: Int) {
        guard isEnabled, model.canMove(by: offset) else { return }
        model.move(by: offset)
        refresh()
    }
    private func upperLevel() {
        guard isEnabled else { return }
        if model.mode == .month { model.mode = .year }
        else if model.mode == .year { model.mode = .decade }
        refresh()
    }
    private func activate(_ index: Int) {
        guard isEnabled, dates.indices.contains(index), model.cellIsAvailable(dates[index]) else { return }
        let date = dates[index]
        model.focusedDate = date
        switch model.mode {
        case .month:
            guard !model.isBlackout(date) else { return }
            let old = model.selectedDates
            model.toggle(date, allowsDeselection: allowsDeselection)
            synchronizeBinding()
            refresh()
            if old != model.selectedDates { onSelectionChanged?(model.selectedDates) }
            onDateInvoked?(date)
        case .year:
            model.displayedDate = model.clamped(date)
            model.mode = .month
            refresh()
            focusCurrentCell()
        case .decade:
            model.displayedDate = model.clamped(date)
            model.mode = .year
            refresh()
            focusCurrentCell()
        }
    }
    private func focusCurrentCell() {
        guard let index = dates.firstIndex(where: { model.cellMatches($0, model.focusedDate) }), cells[index].isEnabled else { return }
        window?.makeFirstResponder(cells[index])
        cells.forEach { $0.needsDisplay = true }
    }
    override func keyDown(with event: NSEvent) { if !handleKey(event) { super.keyDown(with: event) } }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        let modifiers = event.modifierFlags.intersection([.control, .command, .option, .shift])
        if modifiers == .control, event.keyCode == 126 || event.keyCode == 125 {
            if event.keyCode == 126 { upperLevel() }
            else {
                if model.mode == .decade { model.mode = .year }
                else if model.mode == .year { model.mode = .month }
                model.displayedDate = model.focusedDate
                refresh()
            }
            focusCurrentCell()
            return true
        }
        guard modifiers.isEmpty else { return false }
        let columns = model.mode == .month ? 7 : 4
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        switch event.keyCode {
        case 123: model.focus(offset: rtl ? 1 : -1)
        case 124: model.focus(offset: rtl ? -1 : 1)
        case 126: model.focus(offset: -columns)
        case 125: model.focus(offset: columns)
        case 115: model.focusedDate = model.clamped(model.scope(for: model.displayedDate).start)
        case 119:
            let end = model.scope(for: model.displayedDate).end
            model.focusedDate = model.clamped(model.calendar.date(byAdding: .day, value: -1, to: end) ?? end)
        case 116: model.move(by: -1)
        case 121: model.move(by: 1)
        case 36, 49:
            if let index = dates.firstIndex(where: { model.cellMatches($0, model.focusedDate) }) { activate(index) }
            return true
        default: return false
        }
        refresh()
        focusCurrentCell()
        return true
    }
    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, !event.modifierFlags.contains(.control) else { super.scrollWheel(with: event); return }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { super.scrollWheel(with: event); return }
        if lastScrollTime.map({ event.timestamp - $0 > 0.09 }) != false { scrollAccumulator = 0 }
        lastScrollTime = event.timestamp
        if !event.hasPreciseScrollingDeltas { moveView(delta < 0 ? 1 : -1); return }
        scrollAccumulator += delta
        if abs(scrollAccumulator) >= 20 {
            moveView(scrollAccumulator < 0 ? 1 : -1)
            scrollAccumulator = 0
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended { scrollAccumulator = 0 }
    }
}

/// CalendarDatePicker uses the same calendar as the embedded CalendarView while retaining its
/// nonoptional-date contract: activating the current day commits it rather than clearing it.
final class FluentCalendarPickerEditorView: FluentCalendarViewNative {
    init(selectedDate: Date, displayedMonth: Date? = nil, calendar: Calendar = .current,
         locale: Locale = .current, timeZone: TimeZone = .current, minDate: Date? = nil, maxDate: Date? = nil,
         theme: FluentTheme = .current, onSelect: @escaping (Date) -> Void) {
        var resolved = calendar
        resolved.locale = locale
        resolved.timeZone = timeZone
        super.init(configuration: .init(calendar: resolved, selectionMode: .single, minDate: minDate, maxDate: maxDate,
            blackoutDates: [], isTodayHighlighted: true), selection: nil, selectedDates: [selectedDate],
            displayDate: displayedMonth ?? selectedDate, displayMode: .month, theme: theme,
            identifierPrefix: "FluentKit.CalendarDatePicker", onSelectionChanged: nil)
        allowsDeselection = false
        onDateInvoked = onSelect
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
