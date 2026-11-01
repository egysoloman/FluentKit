import Foundation

struct FluentCalendarConfiguration: Equatable {
    var calendar: Calendar
    var selectionMode: FluentCalendarSelectionMode
    var minDate: Date?
    var maxDate: Date?
    var blackoutDates: [Date]
    var isTodayHighlighted: Bool
    var numberOfWeeksInView: Int = 6

    private let defaultRange: ClosedRange<Date>

    init(calendar: Calendar, selectionMode: FluentCalendarSelectionMode, minDate: Date?, maxDate: Date?,
         blackoutDates: [Date], isTodayHighlighted: Bool, numberOfWeeksInView: Int = 6) {
        self.calendar = calendar; self.selectionMode = selectionMode; self.minDate = minDate; self.maxDate = maxDate
        self.blackoutDates = blackoutDates; self.isTodayHighlighted = isTodayHighlighted
        self.numberOfWeeksInView = min(8, max(2, numberOfWeeksInView))
        // WinUI DependencyProperty.cpp: Gregorian Jan 1 (current year - 100) through Dec 31 (+100).
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = calendar.timeZone
        let year = gregorian.component(.year, from: Date())
        let start = gregorian.date(from: DateComponents(year: year - 100, month: 1, day: 1))!
        let end = gregorian.date(from: DateComponents(year: year + 100, month: 12, day: 31))!
        defaultRange = start...end
    }
    var effectiveMinDate: Date { minDate ?? defaultRange.lowerBound }
    var effectiveMaxDate: Date { maxDate ?? defaultRange.upperBound }

}

struct FluentCalendarModel: Equatable {
    var configuration: FluentCalendarConfiguration
    var displayedDate: Date
    var focusedDate: Date
    var mode: FluentCalendarDisplayMode
    var selectedDates: [Date]
    var calendar: Calendar { configuration.calendar }

    init(configuration: FluentCalendarConfiguration, selectedDates: [Date], displayDate: Date?, mode: FluentCalendarDisplayMode) {
        self.configuration = configuration
        self.selectedDates = selectedDates
        self.displayedDate = displayDate ?? Date()
        self.focusedDate = self.displayedDate
        self.mode = mode
        self.selectedDates = normalizedSelection(selectedDates)
        self.displayedDate = clamped(self.displayedDate)
        self.focusedDate = self.displayedDate
    }

    func sameDay(_ lhs: Date, _ rhs: Date) -> Bool { calendar.isDate(lhs, inSameDayAs: rhs) }
    func isBlackout(_ date: Date) -> Bool { configuration.blackoutDates.contains { sameDay(date, $0) } }
    func inRange(_ date: Date) -> Bool {
        if calendar.compare(date, to: configuration.effectiveMinDate, toGranularity: .day) == .orderedAscending { return false }
        if calendar.compare(date, to: configuration.effectiveMaxDate, toGranularity: .day) == .orderedDescending { return false }
        return true
    }
    func clamped(_ date: Date) -> Date {
        var result = date
        if result < configuration.effectiveMinDate { result = configuration.effectiveMinDate }
        if result > configuration.effectiveMaxDate { result = configuration.effectiveMaxDate }
        return result
    }
    func normalizedSelection(_ dates: [Date]) -> [Date] {
        guard configuration.selectionMode != .none else { return [] }
        let valid = dates.filter { inRange($0) && !isBlackout($0) }
        return configuration.selectionMode == .single ? Array(valid.prefix(1)) : valid
    }
    mutating func toggle(_ date: Date, allowsDeselection: Bool = true) {
        guard configuration.selectionMode != .none, inRange(date), !isBlackout(date) else { return }
        if selectedDates.contains(where: { sameDay($0, date) }) {
            if allowsDeselection { selectedDates = selectedDates.filter { !sameDay($0, date) } }
        } else if configuration.selectionMode == .single {
            selectedDates = [date]
        } else {
            selectedDates.append(date)
        }
    }
    func scope(for date: Date, mode: FluentCalendarDisplayMode? = nil) -> DateInterval {
        switch mode ?? self.mode {
        case .month: return FluentCalendarPeriods.interval(.month, containing: date, calendar: calendar)
        case .year: return FluentCalendarPeriods.interval(.year, containing: date, calendar: calendar)
        case .decade:
            var components = calendar.dateComponents([.era, .year], from: date)
            let decade = (components.year ?? 1) / 10 * 10
            components.year = max(1, decade)
            components.month = 1
            components.day = 1
            let lower = calendar.date(from: components) ?? date
            components.year = max(1, decade + 9)
            let upper = calendar.date(from: components) ?? date
            let a = calendar.dateInterval(of: .year, for: lower) ?? DateInterval(start: lower, duration: 0)
            let b = calendar.dateInterval(of: .year, for: upper) ?? DateInterval(start: upper, duration: 0)
            // Year numbers run backwards in a before-common-era calendar. Order dates,
            // not year labels, and clip the first/last decade to the actual era boundary.
            let nominal = DateInterval(start: min(a.start, b.start), end: max(a.end, b.end))
            return FluentCalendarPeriods.withinEra(nominal, containing: date, calendar: calendar)
        }
    }
    func intervalIsAvailable(_ interval: DateInterval) -> Bool {
        if interval.end <= calendar.startOfDay(for: configuration.effectiveMinDate) { return false }
        if interval.start > calendar.startOfDay(for: configuration.effectiveMaxDate) { return false }
        return interval.duration > 0
    }
    func shiftedDisplay(by offset: Int) -> Date? {
        var interval = scope(for: displayedDate)
        for _ in 0..<abs(offset) {
            let next = offset > 0 ? interval.end : interval.start.addingTimeInterval(-1)
            let following = scope(for: next)
            guard following != interval, following.duration > 0 else { return nil }
            interval = following
        }
        return interval.start
    }
    func canMove(by offset: Int) -> Bool {
        guard let next = shiftedDisplay(by: offset) else { return false }
        return intervalIsAvailable(scope(for: next))
    }
    mutating func move(by offset: Int) {
        guard canMove(by: offset), let date = shiftedDisplay(by: offset) else { return }
        displayedDate = clamped(date)
        focusedDate = displayedDate
    }
    /// Match CalendarView::CopyDate: changing a month/year item retains the smaller date fields.
    func mergingFocus(with source: Date) -> Date {
        copyingFocus(with: source, mode: mode)
    }
    private func copyingFocus(with source: Date, mode: FluentCalendarDisplayMode) -> Date {
        guard mode != .month else { return clamped(source) }
        let old = calendar.dateComponents(in: calendar.timeZone, from: focusedDate)
        let incoming = calendar.dateComponents(in: calendar.timeZone, from: source)
        var parts = DateComponents(era: incoming.era, year: incoming.year,
            month: mode == .decade ? old.month : incoming.month, day: 1)
        parts.isLeapMonth = mode == .decade ? old.isLeapMonth : incoming.isLeapMonth
        let year = scope(for: source, mode: .year)
        var month = calendar.date(from: parts) ?? source
        if month < year.start { month = year.start }
        else if month >= year.end { month = year.end.addingTimeInterval(-1) }
        let interval = scope(for: month, mode: .month)
        let firstDay = calendar.component(.day, from: interval.start)
        let lastDay = calendar.component(.day, from: interval.end.addingTimeInterval(-1))
        let day = min(lastDay, max(firstDay, old.day ?? firstDay))
        return clamped(calendar.date(byAdding: .day, value: day - firstDay, to: interval.start) ?? interval.start)
    }
    mutating func focusPage(by offset: Int) {
        let unit: Calendar.Component = mode == .month ? .month : .year
        var amount = mode == .decade ? offset * 10 : offset
        if mode == .decade, offset != 0, calendar.component(.year, from: focusedDate) == 10,
           let adjacent = calendar.date(byAdding: .year, value: offset > 0 ? 1 : -1, to: focusedDate),
           calendar.component(.era, from: adjacent) == calendar.component(.era, from: focusedDate),
           calendar.component(.year, from: adjacent) == 9 {
            // Skip year zero when entering years 1–9, in either numbering direction.
            amount += offset > 0 ? -1 : 1
        }
        let target = shiftedFocus(unit: unit, offset: amount)
        if mode == .decade, calendar.component(.era, from: target) != calendar.component(.era, from: focusedDate),
           let era = unitIndex(.year).eraInterval(containing: target) {
            // WinUI's virtual decade follows AddScopes: an era crossing lands at its
            // first year forwards, or the previous era's last year backwards.
            focusedDate = clamped(offset > 0 ? era.start : scope(for: era.end.addingTimeInterval(-1), mode: .year).start)
        } else {
            focusedDate = target
        }
    }
    private func unitIndex(_ unit: Calendar.Component) -> FluentCalendarUnitIndex {
        FluentCalendarUnitIndex(calendar: calendar, unit: unit,
            first: configuration.effectiveMinDate, last: configuration.effectiveMaxDate)
    }
    private func shiftedFocus(unit: Calendar.Component, offset: Int) -> Date {
        let index = unitIndex(unit)
        let targetIndex = index.index(of: focusedDate) + offset
        if targetIndex < 0 { return configuration.effectiveMinDate }
        if targetIndex >= index.count { return configuration.effectiveMaxDate }
        guard let target = index.date(at: targetIndex) else { return focusedDate }
        if calendar.component(.era, from: target) != calendar.component(.era, from: focusedDate) {
            let interval = FluentCalendarPeriods.interval(unit, containing: target, calendar: calendar)
            return clamped(offset > 0 ? interval.start : calendar.startOfDay(for: interval.end.addingTimeInterval(-1)))
        }
        return copyingFocus(with: target, mode: unit == .month ? .year : .decade)
    }
    var canShowFullScope: Bool {
        let columns = mode == .month ? 7 : 4
        let rows = mode == .month ? configuration.numberOfWeeksInView : 4
        let maximum = mode == .month ? (calendar.maximumRange(of: .day)?.count ?? 31)
            : mode == .year ? (calendar.maximumRange(of: .month)?.count ?? 13) : 10
        return (rows - 1) * columns + 1 >= maximum
    }
    /// WinUI compares coverage percentages of the first two visible scopes, retaining the first on ties.
    func dominantScope(in dates: [Date]) -> Date? {
        guard let first = dates.first, let last = dates.last else { return nil }
        let unit: Calendar.Component = mode == .month ? .day : mode == .year ? .month : .year
        let a = scope(for: first)
        guard last >= a.end else { return clamped(a.start) }
        let b = scope(for: a.end)
        func units(_ start: Date, _ end: Date) -> Double {
            if unit != .day, start < end {
                return Double(FluentCalendarUnitIndex(calendar: calendar, unit: unit,
                    first: start, last: end.addingTimeInterval(-1)).count)
            }
            return Double(max(1, calendar.dateComponents([unit], from: start, to: end).value(for: unit) ?? 1))
        }
        let afterLast = FluentCalendarPeriods.interval(unit, containing: last, calendar: calendar).end
        let firstShare = units(first, a.end) / units(a.start, a.end)
        let secondShare = units(b.start, min(b.end, afterLast)) / units(b.start, b.end)
        return clamped(firstShare < secondShare ? b.start : a.start)
    }
    var cellDates: [Date] {
        let start = scope(for: displayedDate).start
        switch mode {
        case .month:
            let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            guard let first = calendar.date(byAdding: .day, value: -offset, to: start) else { return [] }
            return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        case .year, .decade:
            let unit: Calendar.Component = mode == .year ? .month : .year
            let last = calendar.date(byAdding: unit, value: 16, to: start) ?? start
            let index = FluentCalendarUnitIndex(calendar: calendar, unit: unit, first: start, last: last)
            return (0..<min(16, index.count)).compactMap { index.date(at: $0) }
        }
    }
    func cellIsAvailable(_ date: Date) -> Bool {
        switch mode {
        case .month: return inRange(date)
        case .year: return intervalIsAvailable(scope(for: date, mode: .month))
        case .decade: return intervalIsAvailable(scope(for: date, mode: .year))
        }
    }
    func cellMatches(_ date: Date, _ other: Date) -> Bool {
        let component: Calendar.Component = mode == .month ? .day : mode == .year ? .month : .year
        return calendar.component(.era, from: date) == calendar.component(.era, from: other)
            && calendar.isDate(date, equalTo: other, toGranularity: component)
    }
    mutating func focus(offset: Int) {
        let component: Calendar.Component = mode == .month ? .day : mode == .year ? .month : .year
        if component != .day {
            focusedDate = shiftedFocus(unit: component, offset: offset)
            return
        }
        guard let next = calendar.date(byAdding: component, value: offset, to: focusedDate) else { return }
        focusedDate = clamped(next)
    }
}
