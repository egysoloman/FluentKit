import XCTest
@testable import FluentKit

final class CalendarEraBoundaryTests: XCTestCase {
    private var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        c.locale = Locale(identifier: "ja_JP")
        return c
    }
    private var japanese: Calendar {
        var c = Calendar(identifier: .japanese)
        c.timeZone = gregorian.timeZone; c.locale = gregorian.locale
        return c
    }
    private func date(_ year: Int, _ month: Int = 1, _ day: Int = 1) -> Date {
        gregorian.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func model(_ display: Date, mode: FluentCalendarDisplayMode,
                       range: ClosedRange<Date>? = nil, calendar: Calendar? = nil) -> FluentCalendarModel {
        let range = range ?? date(1900)...date(2100, 12, 31)
        return FluentCalendarModel(configuration: .init(calendar: calendar ?? japanese, selectionMode: .single,
            minDate: range.lowerBound, maxDate: range.upperBound, blackoutDates: [], isTodayHighlighted: true),
            selectedDates: [], displayDate: display, mode: mode)
    }

    func testMonthYearAndDecadeScopesStopAtEraBoundaries() {
        let m = model(date(2019, 5, 1), mode: .decade)
        for (day, mode, start, end) in [
            (date(1989, 1, 7), FluentCalendarDisplayMode.month, date(1989), date(1989, 1, 8)),
            (date(1989, 1, 8), .month, date(1989, 1, 8), date(1989, 2)),
            (date(2019, 4, 30), .year, date(2019), date(2019, 5)),
            (date(2019, 5, 1), .year, date(2019, 5), date(2020)),
            (date(2019, 4, 30), .decade, date(2018), date(2019, 5)),
            (date(2019, 5, 1), .decade, date(2019, 5), date(2028))
        ] {
            XCTAssertEqual(m.scope(for: day, mode: mode), DateInterval(start: start, end: end), "\(day), \(mode)")
        }
    }

    func testYearAndMonthItemSourcesIncludeBothPartialPeriods() {
        for (mode, range, expected) in [
            (FluentCalendarDisplayMode.decade, date(2018)...date(2020, 12, 31),
             [date(2018), date(2019), date(2019, 5), date(2020)]),
            (.year, date(1989)...date(1989, 2, 28), [date(1989), date(1989, 1, 8), date(1989, 2)])
        ] {
            let geometry = FluentCalendarGridGeometry(model: model(range.lowerBound, mode: mode, range: range))
            XCTAssertEqual((0..<geometry.count).compactMap { geometry.date(at: $0) }, expected)
            for (index, day) in expected.enumerated() {
                XCTAssertEqual(geometry.index(of: day), index)
            }
        }
    }

    func testDrillingIntoPartialYearsClampsOnlyUnavailableMonthAndDay() {
        for (old, target, expected) in [
            (date(2018, 1, 7), date(2019, 5), date(2019, 5, 7)),
            (date(1988, 1, 1), date(1989, 1, 8), date(1989, 1, 8)),
            (date(1988, 1, 31), date(1989, 1, 8), date(1989, 1, 31)),
            (date(2018, 12, 31), date(2019), date(2019, 4, 30))
        ] {
            let m = model(old, mode: .decade)
            XCTAssertEqual(m.mergingFocus(with: target), expected)
        }
    }

    func testScopeNavigationVisitsPartialEraInsteadOfSkippingToTheNextCivilYear() {
        var m = model(date(2019, 4, 30), mode: .year)
        XCTAssertEqual(m.shiftedDisplay(by: 1), date(2019, 5))
        m.displayedDate = date(2019, 5)
        XCTAssertEqual(m.shiftedDisplay(by: -1), date(2019))
        m.mode = .decade
        XCTAssertEqual(m.shiftedDisplay(by: -1), date(2018))
        m.displayedDate = date(2028)
        XCTAssertEqual(m.shiftedDisplay(by: -1), date(2019, 5), "The first decade is years 1–9")
    }

    func testArrowAndPageNavigationVisitPartialPeriodsInBothDirections() {
        var m = model(date(2019, 4, 30), mode: .decade)
        m.focus(offset: 1)
        XCTAssertEqual(m.focusedDate, date(2019, 5))
        m.focus(offset: -1)
        XCTAssertEqual(m.focusedDate, date(2019, 4, 30))
        m.focusPage(by: 1)
        XCTAssertEqual(m.focusedDate, date(2019, 5))
        m.focusPage(by: -1)
        XCTAssertEqual(m.focusedDate, date(2019))
        m = model(date(2028, 6, 10), mode: .decade)
        m.focusPage(by: -1)
        XCTAssertEqual(m.focusedDate, date(2019, 6, 10), "Year 10 pages back to year 1, not the previous era")
        m = model(date(1989, 1, 7), mode: .month)
        m.focusPage(by: 1)
        XCTAssertEqual(m.focusedDate, date(1989, 1, 8))
        m.focusPage(by: -1)
        XCTAssertEqual(m.focusedDate, date(1989, 1, 7))
        m = model(date(2019, 4, 30), mode: .year)
        m.focusPage(by: 1)
        XCTAssertEqual(m.focusedDate, date(2019, 5))
        XCTAssertTrue(m.selectedDates.isEmpty)
    }

    @MainActor
    func testNativeYearCellsStayDistinctAndDrillIntoTheSelectedEra() throws {
        _ = NSApplication.shared
        let selection = FluentState(wrappedValue: [Date]())
        let view = try XCTUnwrap(FluentCalendarView(selection: selection.projectedValue,
            displayDate: date(2019, 4, 30), displayMode: .decade,
            range: date(2000)...date(2038, 12, 31), calendar: japanese)
            ._makeView(in: .init(reduceMotion: true)) as? FluentCalendarViewNative)
        view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
        view.layoutSubtreeIfNeeded()
        func all(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(all) }
        let grid = try XCTUnwrap(all(view).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let oldEra = try XCTUnwrap(grid.cell(for: date(2019, 4, 30)))
        let newEra = try XCTUnwrap(grid.cell(for: date(2019, 5)))
        XCTAssertFalse(oldEra === newEra)
        XCTAssertEqual(oldEra.title, "31")
        XCTAssertEqual(newEra.title, "1")
        XCTAssertFalse(view.model.cellMatches(date(2019), date(2019, 5)))
        newEra.performClick(nil)
        XCTAssertEqual(view.model.mode, .year)
        XCTAssertEqual(view.model.focusedDate, date(2019, 5, 30))
        XCTAssertTrue(selection.wrappedValue.isEmpty)
        try XCTUnwrap(grid.cell(for: date(2019, 5))).performClick(nil)
        XCTAssertEqual(view.model.mode, .month)
        try XCTUnwrap(grid.cell(for: date(2019, 5, 30))).performClick(nil)
        XCTAssertEqual(selection.wrappedValue, [date(2019, 5, 30)])
    }

    func testFirstDecadeAndReverseNumberedEraHaveChronologicalScopes() {
        let c = gregorian
        func day(_ era: Int, _ year: Int) -> Date {
            c.date(from: DateComponents(era: era, year: year, month: 1, day: 1))!
        }
        let range = day(0, 30)...day(1, 30)
        let m = model(day(1, 5), mode: .decade, range: range, calendar: c)
        XCTAssertEqual(m.scope(for: day(1, 5)), DateInterval(start: day(1, 1), end: day(1, 10)))
        XCTAssertEqual(m.scope(for: day(0, 15)), DateInterval(start: day(0, 19), end: day(0, 9)))
        XCTAssertEqual(m.scope(for: day(0, 1)), DateInterval(start: day(0, 9), end: day(1, 1)))
        var backwards = model(day(0, 10), mode: .decade, range: range, calendar: c)
        backwards.focusPage(by: -1)
        XCTAssertEqual(backwards.focusedDate, day(0, 20))
        backwards.focusedDate = day(0, 10)
        backwards.focusPage(by: 1)
        XCTAssertEqual(backwards.focusedDate, day(0, 1), "Reverse-numbered eras also have a nine-year first decade")
    }

    func testAlignedEraChangesAndLeapMonthsDoNotCreateDuplicateItems() {
        for id in [Calendar.Identifier.chinese, .hebrew, .republicOfChina] {
            var c = Calendar(identifier: id); c.timeZone = gregorian.timeZone
            for mode in [FluentCalendarDisplayMode.year, .decade] {
                let m = model(date(2023, 3, 25), mode: mode, range: date(1900)...date(2080, 12, 31), calendar: c)
                let grid = FluentCalendarGridGeometry(model: m)
                var previous: Date?
                for index in 0..<grid.count {
                    guard let value = grid.date(at: index) else { XCTFail("Missing \(id) item \(index)"); continue }
                    XCTAssertEqual(grid.index(of: value), index)
                    if let previous { XCTAssertGreaterThan(value, previous) }
                    previous = value
                }
                let first = c.dateInterval(of: grid.unit, for: m.configuration.effectiveMinDate)!.start
                let last = c.dateInterval(of: grid.unit, for: m.configuration.effectiveMaxDate)!.start
                XCTAssertEqual(grid.count, (c.dateComponents([grid.unit], from: first, to: last).value(for: grid.unit) ?? 0) + 1)
            }
        }
    }

    @MainActor
    func testLongJapaneseRangeKeepsCellsVirtualizedAndIndicesReversible() throws {
        _ = NSApplication.shared
        let view = try XCTUnwrap(FluentCalendarView(displayDate: date(2019, 5), displayMode: .decade,
            range: date(1000)...date(3000, 12, 31), calendar: japanese)
            ._makeView(in: .init(reduceMotion: true)) as? FluentCalendarViewNative)
        view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
        view.layoutSubtreeIfNeeded()
        let grid = try XCTUnwrap(view.subviews.first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let geometry = try XCTUnwrap(grid.geometry)
        XCTAssertGreaterThan(geometry.count, 2001, "Partial era years need their own cells")
        for index in stride(from: 0, to: geometry.count, by: 17) {
            let value = try XCTUnwrap(geometry.date(at: index))
            XCTAssertEqual(geometry.index(of: value), index)
            let scope = view.model.scope(for: value)
            XCTAssertGreaterThanOrEqual(value, scope.start)
            XCTAssertLessThan(value, scope.end)
            grid.scroll(to: value, leading: true)
            XCTAssertLessThanOrEqual(grid.realizedCells.count, 24)
        }
    }
}
