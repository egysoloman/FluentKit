import Foundation

struct FluentCalendarConfiguration: Equatable {
    var calendar: Calendar
    var selectionMode: FluentCalendarSelectionMode
    var minDate: Date?
    var maxDate: Date?
    var blackoutDates: [Date]
    var isTodayHighlighted: Bool
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
        if let min = configuration.minDate, calendar.compare(date, to: min, toGranularity: .day) == .orderedAscending { return false }
        if let max = configuration.maxDate, calendar.compare(date, to: max, toGranularity: .day) == .orderedDescending { return false }
        return true
    }
    func clamped(_ date: Date) -> Date {
        var result = date
        if let min = configuration.minDate, result < min { result = min }
        if let max = configuration.maxDate, result > max { result = max }
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
        if let min = configuration.minDate, interval.end <= calendar.startOfDay(for: min) { return false }
        if let max = configuration.maxDate, interval.start > calendar.startOfDay(for: max) { return false }
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
        let interval = scope(for: displayedDate)
        if focusedDate < interval.start || focusedDate >= interval.end { displayedDate = focusedDate }
    }
}
