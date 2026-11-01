import Foundation

/// Foundation's civil month/year intervals can include two eras. CalendarView treats each
/// partial period as a separate item, as Windows.Globalization.Calendar does.
enum FluentCalendarPeriods {
    static func interval(_ unit: Calendar.Component, containing date: Date, calendar: Calendar) -> DateInterval {
        let nominal = calendar.dateInterval(of: unit, for: date) ?? DateInterval(start: date, duration: 0)
        return withinEra(nominal, containing: date, calendar: calendar)
    }

    static func withinEra(_ interval: DateInterval, containing date: Date, calendar: Calendar) -> DateInterval {
        guard interval.duration > 0 else { return interval }
        let era = calendar.component(.era, from: date)
        var start = interval.start, end = interval.end
        if calendar.component(.era, from: start) != era {
            start = boundary(from: start, to: date, calendar: calendar) { $0 != era }
        }
        let last = end.addingTimeInterval(-1)
        if calendar.component(.era, from: last) != era {
            end = boundary(from: date, to: last, calendar: calendar) { $0 == era }
        }
        return DateInterval(start: start, end: max(start, end))
    }

    static func eraStarts(from first: Date, through last: Date, calendar: Calendar) -> [Date] {
        var starts = [first]
        let lastEra = calendar.component(.era, from: last)
        var current = first
        while current < last {
            let era = calendar.component(.era, from: current)
            guard era != lastEra else { break }
            let next = boundary(from: current, to: last, calendar: calendar) { $0 == era }
            guard next > current else { break }
            starts.append(next)
            current = next
        }
        return starts
    }

    private static func boundary(from first: Date, to last: Date, calendar: Calendar,
                                 isBeforeBoundary: (Int) -> Bool) -> Date {
        // Do not trust dateInterval(of: .era).end: Foundation may derive that endpoint by
        // adding a number of years to the era's first day, missing a midyear transition.
        // Era IDs are chronological; locate actual component changes without a date table.
        var lower = first, upper = last
        while upper.timeIntervalSince(lower) > 0.5 {
            let middle = lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
            guard middle > lower, middle < upper else { break }
            if isBeforeBoundary(calendar.component(.era, from: middle)) { lower = middle }
            else { upper = middle }
        }
        let day = calendar.startOfDay(for: upper)
        return day > first && !isBeforeBoundary(calendar.component(.era, from: day)) ? day : upper
    }
}

/// Arithmetic within an era, with one segment per era rather than an array of dates.
/// The anchor is a full civil period; the exposed first item can start partway through it.
struct FluentCalendarUnitIndex: Equatable {
    private struct Segment: Equatable {
        let start: Date
        let end: Date
        let anchor: Date
        let offset: Int
        let count: Int
    }
    let calendar: Calendar
    let unit: Calendar.Component
    private let segments: [Segment]
    let count: Int

    init(calendar: Calendar, unit: Calendar.Component, first: Date, last: Date) {
        self.calendar = calendar; self.unit = unit
        let start = FluentCalendarPeriods.interval(unit, containing: first, calendar: calendar).start
        let lastPeriod = FluentCalendarPeriods.interval(unit, containing: max(first, last), calendar: calendar)
        let starts = FluentCalendarPeriods.eraStarts(from: start, through: lastPeriod.start, calendar: calendar)
        var segments: [Segment] = [], count = 0
        for (index, begin) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : lastPeriod.end
            let anchor = calendar.dateInterval(of: unit, for: begin)?.start ?? begin
            let lastAnchor = calendar.dateInterval(of: unit, for: end.addingTimeInterval(-1))?.start ?? begin
            let units = max(1, (calendar.dateComponents([unit], from: anchor, to: lastAnchor).value(for: unit) ?? 0) + 1)
            segments.append(Segment(start: begin, end: end, anchor: anchor, offset: count, count: units))
            count += units
        }
        self.segments = segments; self.count = count
    }

    func date(at index: Int) -> Date? {
        guard (0..<count).contains(index), let segment = segments.last(where: { $0.offset <= index }),
              let date = calendar.date(byAdding: unit, value: index - segment.offset, to: segment.anchor) else { return nil }
        return max(segment.start, date)
    }

    func index(of date: Date) -> Int {
        guard let segment = segments.last(where: { $0.start <= date }) ?? segments.first else { return 0 }
        let nominal = calendar.dateInterval(of: unit, for: date)?.start ?? date
        let offset = calendar.dateComponents([unit], from: segment.anchor, to: nominal).value(for: unit) ?? 0
        return min(count - 1, max(0, segment.offset + min(segment.count - 1, max(0, offset))))
    }

    func eraInterval(containing date: Date) -> DateInterval? {
        guard let segment = segments.last(where: { $0.start <= date }) ?? segments.first else { return nil }
        return DateInterval(start: segment.start, end: segment.end)
    }
}
