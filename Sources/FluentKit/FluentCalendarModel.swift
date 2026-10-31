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
        case .month: return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        case .year: return calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 0)
        case .decade:
            var components = calendar.dateComponents([.era, .year], from: date)
            components.year = max(1, (components.year ?? 1) / 10 * 10)
            components.month = 1
            components.day = 1
            let start = calendar.date(from: components) ?? date
            let end = calendar.date(byAdding: .year, value: 10, to: start) ?? start
            return DateInterval(start: start, end: max(start, end))
        }
    }
    func intervalIsAvailable(_ interval: DateInterval) -> Bool {
        if interval.end <= calendar.startOfDay(for: configuration.effectiveMinDate) { return false }
        if interval.start > calendar.startOfDay(for: configuration.effectiveMaxDate) { return false }
        return interval.duration > 0
    }
    func shiftedDisplay(by offset: Int) -> Date? {
        let component: Calendar.Component = mode == .month ? .month : .year
        let amount = mode == .decade ? offset * 10 : offset
        return calendar.date(byAdding: component, value: amount, to: scope(for: displayedDate).start)
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
        guard mode != .month else { return clamped(source) }
        let old = calendar.dateComponents(in: calendar.timeZone, from: focusedDate)
        let incoming = calendar.dateComponents(in: calendar.timeZone, from: source)
        var parts = DateComponents(era: incoming.era, year: incoming.year,
            month: mode == .decade ? old.month : incoming.month, day: 1)
        parts.isLeapMonth = mode == .decade ? old.isLeapMonth : incoming.isLeapMonth
        let year = scope(for: source, mode: .year)
        var month = calendar.date(from: parts) ?? source
        if month >= year.end || month < year.start {
            month = calendar.date(byAdding: .month, value: -1, to: year.end) ?? source
        }
        let days = calendar.range(of: .day, in: .month, for: month) ?? 1..<29
        let day = min(days.upperBound - 1, max(days.lowerBound, old.day ?? 1))
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        return clamped(calendar.date(byAdding: .day, value: day - days.lowerBound, to: start) ?? start)
    }
    mutating func focusPage(by offset: Int) {
        let component: Calendar.Component = mode == .month ? .month : .year
        if let date = calendar.date(byAdding: component, value: mode == .decade ? offset * 10 : offset, to: focusedDate) {
            focusedDate = clamped(date)
        }
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
            Double(max(1, calendar.dateComponents([unit], from: start, to: end).value(for: unit) ?? 1))
        }
        let afterLast = calendar.date(byAdding: unit, value: 1, to: last) ?? b.end
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
        case .year:
            return (0..<16).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
        case .decade:
            return (0..<16).compactMap { calendar.date(byAdding: .year, value: $0, to: start) }
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
        return calendar.isDate(date, equalTo: other, toGranularity: component)
    }
    mutating func focus(offset: Int) {
        let component: Calendar.Component = mode == .month ? .day : mode == .year ? .month : .year
        guard let next = calendar.date(byAdding: component, value: offset, to: focusedDate) else { return }
        focusedDate = clamped(next)
    }
}
