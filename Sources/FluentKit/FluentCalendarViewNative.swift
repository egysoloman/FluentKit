import AppKit

class FluentCalendarViewNative: NSControl {
    var theme: FluentTheme { didSet { if oldValue != theme, !updatingProperties { refresh() } } }
    private(set) var model: FluentCalendarModel
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
    private let grid: FluentCalendarGridView
    private var isApplyingBinding = false
    private var updatingProperties = false
    private var refreshingViewport = false
    private var cellFormatter = DateFormatter()
    private var fullDateFormatter = DateFormatter()

    init(configuration: FluentCalendarConfiguration, selection: FluentBinding<[Date]>?, selectedDates: [Date],
         displayDate: Date?, displayMode: FluentCalendarDisplayMode, theme: FluentTheme,
         identifierPrefix: String = "FluentKit.CalendarView", onSelectionChanged: (([Date]) -> Void)?) {
        self.theme = theme
        model = FluentCalendarModel(configuration: configuration, selectedDates: selection?.get() ?? selectedDates,
            displayDate: displayDate, mode: displayMode)
        binding = selection; requestedSelection = selectedDates
        requestedDisplayDate = displayDate; requestedMode = displayMode
        self.onSelectionChanged = onSelectionChanged
        grid = FluentCalendarGridView(prefix: identifierPrefix)
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 350))
        identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Calendar")
        wantsLayer = true; layer?.cornerRadius = 8
        setAccessibilityElement(true); setAccessibilityRole(.group)
        fluentSetDefaultAccessibilityLabel("Calendar")
        previous.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".PreviousMonth")
        next.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".NextMonth")
        header.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Header")
        previous.glyph = .up; next.glyph = .down
        previous.fluentSetDefaultAccessibilityLabel("Previous"); next.fluentSetDefaultAccessibilityLabel("Next")
        previous.onInvoke = { [weak self] in self?.moveView(-1) }
        next.onInvoke = { [weak self] in self?.moveView(1) }
        header.onInvoke = { [weak self] in self?.upperLevel() }; header.isHeader = true
        [header, previous, next].forEach(addSubview)
        for index in 0..<7 {
            let label = NSTextField(labelWithString: ""); label.alignment = .center
            label.identifier = NSUserInterfaceItemIdentifier(identifierPrefix + ".Weekday.\(index)")
            weekdays.append(label); addSubview(label)
        }
        addSubview(grid)
        grid.configureCell = { [weak self] cell, date in self?.configure(cell, for: date) }
        grid.onVisibleDatesChanged = { [weak self] dates in self?.viewportChanged(dates) }
        layout()
        synchronizeBinding()
        refresh(display: model.focusedDate)
        installObserver()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { removeObserver() }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 310, height: 350 + CGFloat(model.configuration.numberOfWeeksInView - 6) * 44)
    }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { false }
    override var isEnabled: Bool { didSet { if oldValue != isEnabled { refresh() } } }
    override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        didSet { if oldValue != userInterfaceLayoutDirection { needsLayout = true } }
    }

    func update(configuration: FluentCalendarConfiguration, selection: FluentBinding<[Date]>?, selectedDates: [Date],
                displayDate: Date?, displayMode: FluentCalendarDisplayMode, theme: FluentTheme,
                onSelectionChanged: (([Date]) -> Void)?) {
        let reusesObservation = binding?.observationIdentity != nil && binding?.observationIdentity == selection?.observationIdentity
        if !reusesObservation { removeObserver() }
        binding = selection; self.onSelectionChanged = onSelectionChanged
        let oldModel = model, oldSelection = model.selectedDates
        model.configuration = configuration
        if let selection { model.selectedDates = FluentDependencyTracking.withoutTracking { selection.get() } }
        else if selectedDates != requestedSelection { model.selectedDates = selectedDates }
        requestedSelection = selectedDates
        model.selectedDates = model.normalizedSelection(model.selectedDates)
        let displayChanged = displayDate != requestedDisplayDate && displayDate != nil
        let modeChanged = displayMode != requestedMode
        if displayChanged, let displayDate { model.displayedDate = displayDate; model.focusedDate = displayDate }
        if modeChanged {
            if !displayChanged { reconcileFocusToViewport() }
            model.mode = displayMode
        }
        requestedDisplayDate = displayDate; requestedMode = displayMode
        model.displayedDate = model.clamped(model.displayedDate); model.focusedDate = model.clamped(model.focusedDate)
        let themeChanged = self.theme != theme
        updatingProperties = true; self.theme = theme; updatingProperties = false
        synchronizeBinding()
        if configuration.numberOfWeeksInView != oldModel.configuration.numberOfWeeksInView { invalidateIntrinsicContentSize() }
        if model != oldModel || themeChanged {
            refresh(display: displayChanged || modeChanged || oldModel.configuration.calendar != configuration.calendar ? model.focusedDate : nil)
        }
        if !reusesObservation { installObserver() }
        if oldSelection != model.selectedDates { onSelectionChanged?(model.selectedDates) }
    }
    func setSelectedDate(_ date: Date) {
        guard model.selectedDates != [date] else { return }
        model.selectedDates = model.normalizedSelection([date]); model.focusedDate = model.clamped(date)
        model.displayedDate = model.focusedDate; model.mode = .month
        refresh(display: model.focusedDate)
    }
    func updateLimits(minDate: Date?, maxDate: Date?) {
        guard model.configuration.minDate != minDate || model.configuration.maxDate != maxDate else { return }
        model.configuration.minDate = minDate; model.configuration.maxDate = maxDate
        model.selectedDates = model.normalizedSelection(model.selectedDates)
        model.displayedDate = model.clamped(model.displayedDate); model.focusedDate = model.clamped(model.focusedDate)
        refresh(display: model.focusedDate)
    }
    private func removeObserver() {
        observationGeneration &+= 1
        if let observerID { binding?.removeObserver(observerID) }; observerID = nil
    }
    private func installObserver() {
        let generation = observationGeneration
        observerID = binding?.observe { [weak self] _ in
            let deliver = { [weak self] in
                guard let self, self.observationGeneration == generation, !self.isApplyingBinding, let binding = self.binding else { return }
                let old = self.model.selectedDates
                self.model.selectedDates = self.model.normalizedSelection(FluentDependencyTracking.withoutTracking { binding.get() })
                self.synchronizeBinding()
                if old != self.model.selectedDates { self.refresh(); self.onSelectionChanged?(self.model.selectedDates) }
            }
            DispatchQueue.main.async(execute: deliver)
        }
    }
    private func synchronizeBinding() {
        guard let binding, !isApplyingBinding,
              FluentDependencyTracking.withoutTracking({ binding.get() }) != model.selectedDates else { return }
        isApplyingBinding = true; defer { isApplyingBinding = false }
        binding.set(model.selectedDates)
        model.selectedDates = model.normalizedSelection(FluentDependencyTracking.withoutTracking { binding.get() })
    }
    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.calendar = model.calendar; f.locale = model.calendar.locale ?? .current
        f.timeZone = model.calendar.timeZone; f.setLocalizedDateFormatFromTemplate(template); return f
    }
    private func refresh(display date: Date? = nil) {
        let hadCellFocus = grid.realizedCells.contains { window?.firstResponder === $0 }
        refreshingViewport = true
        if let date { model.displayedDate = model.clamped(date) }
        layer?.backgroundColor = theme.textControlBackground(focused: true, enabled: true).cgColor
        layer?.borderColor = theme.controlStroke.cgColor; layer?.borderWidth = theme.controlStrokeWidth
        cellFormatter = formatter(model.mode == .month ? "d" : model.mode == .year ? "MMM" : "y")
        if model.mode == .month { cellFormatter.dateFormat = "d" }
        else if model.mode == .decade { cellFormatter.dateFormat = "y" }
        fullDateFormatter = formatter("EEEE yMMMMd")
        let symbols = model.calendar.shortStandaloneWeekdaySymbols
        let abbreviated = symbols.map { String($0.prefix(2)) }
        let titles = Set(abbreviated).count == 7 ? abbreviated : symbols
        let caption = theme.typography.font(for: .caption)
        let font = NSFont(descriptor: caption.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold.rawValue]
        ]), size: caption.pointSize) ?? caption
        for index in weekdays.indices {
            let dayIndex = (index + model.calendar.firstWeekday - 1) % 7
            weekdays[index].stringValue = titles[dayIndex]
            weekdays[index].setAccessibilityLabel(model.calendar.standaloneWeekdaySymbols[dayIndex])
            weekdays[index].font = font; weekdays[index].textColor = isEnabled ? theme.textPrimary : theme.textDisabled
            weekdays[index].isHidden = model.mode != .month
        }
        grid.allowsScrolling = isEnabled
        layout()
        let changed = grid.setModel(model, rows: model.mode == .month ? model.configuration.numberOfWeeksInView : 4)
        if changed || date != nil {
            let target = date ?? model.focusedDate
            grid.scroll(to: model.canShowFullScope ? model.clamped(model.scope(for: target).start) : target, leading: true)
        }
        refreshingViewport = false
        grid.refreshCells()
        updateHeader(); updateTabOrder()
        if hadCellFocus, window?.firstResponder === self { focusCurrentCell() }
        setAccessibilityChildren([header, previous, next] + weekdays.filter { !$0.isHidden } + [grid])
        needsLayout = true
    }
    private func updateHeader() {
        let f = formatter(model.mode == .month ? "MMMM y" : "y")
        let scope = model.scope(for: model.displayedDate)
        if model.mode == .decade {
            let last = scope.end.addingTimeInterval(-1)
            header.title = "\(f.string(from: scope.start)) – \(f.string(from: last))"
        } else { header.title = f.string(from: model.displayedDate) }
        header.setAccessibilityLabel(header.title); header.isEnabled = isEnabled && model.mode != .decade
        previous.isEnabled = isEnabled && grid.canScrollBefore; next.isEnabled = isEnabled && grid.canScrollAfter
        [header, previous, next].forEach { $0.theme = theme; $0.userInterfaceLayoutDirection = userInterfaceLayoutDirection; $0.needsDisplay = true }
        setAccessibilityValue(header.title)
    }
    private func viewportChanged(_ dates: [Date]) {
        guard !refreshingViewport else { return }
        if let scope = model.dominantScope(in: dates), model.scope(for: scope) != model.scope(for: model.displayedDate) {
            model.displayedDate = scope
        }
        let scope = model.scope(for: model.displayedDate)
        for cell in grid.realizedCells {
            guard let date = grid.date(for: cell) else { continue }
            let outside = date < scope.start || date >= scope.end
            if cell.outOfScope != outside { cell.outOfScope = outside; cell.needsDisplay = true }
        }
        updateHeader(); updateTabOrder()
    }
    private func updateTabOrder() {
        let visible = grid.visibleCells
        let target = visible.first { grid.date(for: $0).map { model.cellMatches($0, model.focusedDate) } == true }
            ?? visible.first { $0.isEnabled }
        for cell in grid.realizedCells { cell.participatesInTabOrder = isEnabled && cell === target }
    }
    private func configure(_ cell: FluentCalendarButton, for date: Date) {
        cell.title = cellFormatter.string(from: date); cell.theme = theme; cell.roundDay = model.mode == .month
        cell.isEnabled = isEnabled && model.cellIsAvailable(date)
        cell.blackout = model.mode == .month && model.isBlackout(date)
        cell.selected = model.mode == .month && model.selectedDates.contains { model.sameDay($0, date) }
        cell.today = model.mode == .month && model.configuration.isTodayHighlighted && model.calendar.isDateInToday(date)
        let scope = model.scope(for: model.displayedDate); cell.outOfScope = date < scope.start || date >= scope.end
        cell.setAccessibilityLabel(fullDateFormatter.string(from: date)); cell.setAccessibilityValue(cell.selected ? 1 : 0)
        cell.setAccessibilitySelected(cell.selected); cell.setAccessibilityHelp(cell.blackout ? "Unavailable date" : nil)
        cell.onInvoke = { [weak self] in self?.activate(date) }
        cell.onFocus = { [weak self] in
            guard let self else { return }
            self.model.focusedDate = self.model.mergingFocus(with: date); self.updateTabOrder()
        }
        cell.onKey = { [weak self] in self?.handleKey($0) ?? false }; cell.needsDisplay = true
    }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width), height = max(0, bounds.height)
        let pad = min(8, min(width, height) / 2)
        let navSize = min(32, max(0, min((width - 2 * pad) / 3, height - 2 * pad)))
        let navY = max(pad, height - pad - navSize), nextX = max(pad, width - pad - navSize)
        let previousX = max(pad, nextX - navSize - min(4, pad))
        func mirror(_ rect: NSRect) -> NSRect {
            NSRect(x: userInterfaceLayoutDirection == .rightToLeft ? width - rect.maxX : rect.minX,
                y: rect.minY, width: rect.width, height: rect.height)
        }
        next.frame = mirror(NSRect(x: nextX, y: navY, width: navSize, height: navSize))
        previous.frame = mirror(NSRect(x: previousX, y: navY, width: navSize, height: navSize))
        header.frame = mirror(NSRect(x: pad, y: navY, width: max(0, previousX - 2 * pad), height: navSize))
        let headerHeight = min(48, max(0, height - 2 * pad))
        let weekdayHeight = model.mode == .month ? min(24, max(0, height - headerHeight - 2 * pad)) : 0
        let gridHeight = max(0, height - headerHeight - weekdayHeight - 2 * pad), gridWidth = max(0, width - 2 * pad)
        for index in weekdays.indices {
            weekdays[index].frame = mirror(NSRect(x: pad + CGFloat(index) * gridWidth / 7,
                y: pad + gridHeight, width: gridWidth / 7, height: weekdayHeight))
        }
        grid.userInterfaceLayoutDirection = userInterfaceLayoutDirection
        grid.frame = NSRect(x: pad, y: pad, width: gridWidth, height: gridHeight)
        grid.layoutSubtreeIfNeeded()
    }
    private func moveView(_ offset: Int) {
        guard isEnabled, offset < 0 ? grid.canScrollBefore : grid.canScrollAfter else { return }
        let target: Date
        if !model.canShowFullScope, let first = grid.visibleCells.first.flatMap({ grid.date(for: $0) }), let geometry = grid.geometry {
            var index = min(geometry.count - 1, max(0, geometry.index(of: first) + offset * grid.rows * geometry.columns))
            var candidate = geometry.date(at: index)
            let step = offset < 0 ? -1 : 1
            while candidate == nil && (0..<geometry.count).contains(index + step) {
                index += step; candidate = geometry.date(at: index)
            }
            target = candidate ?? first
        } else if offset < 0, let first = grid.visibleCells.first.flatMap({ grid.date(for: $0) }), first > model.scope(for: model.displayedDate).start {
            target = model.scope(for: model.displayedDate).start
        } else { target = model.shiftedDisplay(by: offset) ?? model.displayedDate }
        grid.scroll(to: model.clamped(target), leading: true)
    }
    private func reconcileFocusToViewport() {
        let visible = grid.visibleCells
        if visible.contains(where: { grid.date(for: $0).map { model.cellMatches($0, model.focusedDate) } == true }) { return }
        guard let first = visible.first.flatMap({ grid.date(for: $0) }) else { return }
        let target = max(first, model.clamped(model.scope(for: model.displayedDate).start))
        model.focusedDate = model.mergingFocus(with: target)
    }
    private func upperLevel() {
        guard isEnabled else { return }
        reconcileFocusToViewport()
        if model.mode == .month { model.mode = .year } else if model.mode == .year { model.mode = .decade }
        refresh(display: model.focusedDate)
    }
    private func activate(_ date: Date) {
        guard isEnabled, model.cellIsAvailable(date) else { return }
        model.focusedDate = model.mergingFocus(with: date)
        switch model.mode {
        case .month:
            guard !model.isBlackout(date) else { return }
            let old = model.selectedDates; model.toggle(date, allowsDeselection: allowsDeselection)
            synchronizeBinding(); refresh()
            if old != model.selectedDates { onSelectionChanged?(model.selectedDates) }
            onDateInvoked?(date)
        case .year:
            model.mode = .month; refresh(display: model.focusedDate); focusCurrentCell()
        case .decade:
            model.mode = .year; refresh(display: model.focusedDate); focusCurrentCell()
        }
    }
    private func focusCurrentCell() {
        grid.scroll(to: model.focusedDate, leading: false)
        if let cell = grid.cell(for: model.focusedDate), cell.isEnabled { window?.makeFirstResponder(cell) }
        grid.realizedCells.forEach { $0.needsDisplay = true }; updateTabOrder()
    }
    override func keyDown(with event: NSEvent) { if !handleKey(event) { super.keyDown(with: event) } }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        FluentFocusVisibility.markKeyboardInteraction(in: window)
        let modifiers = event.modifierFlags.intersection([.control, .command, .option, .shift])
        if modifiers == .control, event.keyCode == 126 || event.keyCode == 125 {
            if event.keyCode == 126 { upperLevel() }
            else {
                reconcileFocusToViewport()
                if model.mode == .decade { model.mode = .year } else if model.mode == .year { model.mode = .month }
                refresh(display: model.focusedDate)
            }
            focusCurrentCell(); return true
        }
        guard modifiers.isEmpty else { return false }
        let columns = model.mode == .month ? 7 : 4, rtl = userInterfaceLayoutDirection == .rightToLeft
        switch event.keyCode {
        case 123: model.focus(offset: rtl ? 1 : -1)
        case 124: model.focus(offset: rtl ? -1 : 1)
        case 126: model.focus(offset: -columns)
        case 125: model.focus(offset: columns)
        case 115: model.focusedDate = model.clamped(model.scope(for: model.displayedDate).start)
        case 119:
            let end = model.scope(for: model.displayedDate).end
            model.focusedDate = model.clamped(model.calendar.date(byAdding: .day, value: -1, to: end) ?? end)
        case 116: model.focusPage(by: -1)
        case 121: model.focusPage(by: 1)
        case 36, 49: activate(model.focusedDate); return true
        default: return false
        }
        focusCurrentCell(); return true
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
