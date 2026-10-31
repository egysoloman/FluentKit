import XCTest
@testable import FluentKit

final class CalendarScrollingTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.locale = Locale(identifier: "en_US"); c.firstWeekday = 1; return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    @MainActor private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @MainActor private func make(_ control: FluentCalendarView) throws -> FluentCalendarViewNative {
        _ = NSApplication.shared
        let native = try XCTUnwrap(control._makeView(in: .init(reduceMotion: true)) as? FluentCalendarViewNative)
        native.frame = NSRect(origin: .zero, size: native.intrinsicContentSize); native.layoutSubtreeIfNeeded()
        return native
    }
    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    @MainActor func testCalendarUsesContinuousViewportAndRetainsDayIdentityDuringPartialScroll() throws {
        let native = try make(FluentCalendarView(displayDate: date(2026, 5, 10), calendar: calendar))
        let scroll = try XCTUnwrap(all(native).first { $0 is NSScrollView } as? NSScrollView)
        let doc = try XCTUnwrap(scroll.documentView)
        let before = scroll.contentView.bounds.origin.y
        let cell = try XCTUnwrap(all(doc).first { $0 is FluentCalendarButton && !$0.visibleRect.isEmpty })
        let title = cell.accessibilityLabel()
        let screenY = cell.convert(cell.bounds, to: native).minY
        scroll.contentView.scroll(to: NSPoint(x: 0, y: before + 10)); scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(scroll.contentView.bounds.minY, before + 10, accuracy: 0.01)
        XCTAssertTrue(cell.superview === doc); XCTAssertEqual(cell.accessibilityLabel(), title)
        XCTAssertEqual(cell.convert(cell.bounds, to: native).minY, screenY + 10, accuracy: 0.01)
        XCTAssertGreaterThan(doc.frame.height, 100_000)
        XCTAssertLessThanOrEqual(all(doc).filter { $0 is FluentCalendarButton }.count, 70)
    }
    @MainActor func testPageNavigationPreservesDayInsteadOfJumpingToFirst() throws {
        let native = try make(FluentCalendarView(displayDate: date(2026, 1, 31), calendar: calendar))
        native.keyDown(with: key(121))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: native.model.focusedDate), DateComponents(year: 2026, month: 2, day: 28))
        native.keyDown(with: key(116))
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: native.model.focusedDate), DateComponents(month: 1, day: 28))
    }
    @MainActor func testDefaultRangeUsesGregorianHundredYearBoundaries() throws {
        let native = try make(FluentCalendarView(calendar: calendar))
        let year = calendar.component(.year, from: Date())
        XCTAssertTrue(native.model.inRange(date(year - 100, 1, 1)))
        XCTAssertTrue(native.model.inRange(date(year + 100, 12, 31)))
        XCTAssertFalse(native.model.inRange(date(year - 101, 12, 31)))
        XCTAssertFalse(native.model.inRange(date(year + 101, 1, 1)))
    }
    @MainActor func testLargeRangesRecycleCellsAndExposeOnlyVisibleDates() throws {
        for mode in FluentCalendarDisplayMode.allCases {
            let native = try make(FluentCalendarView(displayDate: date(2026, 5, 10), displayMode: mode,
                range: date(1000, 1, 1)...date(3000, 12, 31), calendar: calendar))
            let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
            let doc = try XCTUnwrap(grid.documentView)
            var instances = Set<ObjectIdentifier>()
            for step in 0..<60 {
                let fraction = CGFloat((step * 17) % 60) / 60
                grid.contentView.scroll(to: NSPoint(x: 0, y: fraction * max(0, doc.frame.height - grid.contentView.bounds.height)))
                grid.reflectScrolledClipView(grid.contentView)
                let cells = all(doc).compactMap { $0 as? FluentCalendarButton }
                instances.formUnion(cells.map(ObjectIdentifier.init))
                XCTAssertLessThanOrEqual(cells.count, mode == .month ? 70 : 32)
                let accessible = doc.accessibilityChildren()?.compactMap { $0 as? FluentCalendarButton } ?? []
                XCTAssertEqual(accessible.count, grid.visibleCells.count)
                XCTAssertTrue(accessible.allSatisfy { !$0.visibleRect.isEmpty })
            }
            XCTAssertLessThanOrEqual(instances.count, mode == .month ? 70 : 32, "scrolling must recycle rather than repeatedly allocate views")
        }
    }
    @MainActor func testOffscreenFocusKeepsItsDateAndKeyboardBringsItBack() throws {
        let state = FluentState(wrappedValue: [Date]())
        let native = try make(FluentCalendarView(selection: state.projectedValue, displayDate: date(2026, 5, 10), calendar: calendar))
        let window = NSWindow(contentRect: native.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = native; window.makeKeyAndOrderFront(nil); defer { window.close() }
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let cell = try XCTUnwrap(grid.cell(for: date(2026, 5, 10)))
        XCTAssertTrue(window.makeFirstResponder(cell))
        grid.contentView.scroll(to: NSPoint(x: 0, y: grid.contentView.bounds.minY + 50_000)); grid.reflectScrolledClipView(grid.contentView)
        XCTAssertTrue(window.firstResponder === cell)
        XCTAssertEqual(cell.representedDate, date(2026, 5, 10)); XCTAssertTrue(cell.visibleRect.isEmpty)
        XCTAssertFalse(cell.isAccessibilityElement())
        cell.keyDown(with: key(124))
        XCTAssertEqual(native.model.focusedDate, date(2026, 5, 11))
        let current = try XCTUnwrap(grid.cell(for: date(2026, 5, 11)))
        XCTAssertTrue(window.firstResponder === current); XCTAssertFalse(current.visibleRect.isEmpty)
        current.keyDown(with: key(49)); XCTAssertEqual(state.wrappedValue, [date(2026, 5, 11)])
    }
    @MainActor func testHeaderFollowsVisibleScopeAndParentRefreshDoesNotJump() throws {
        let state = FluentState(wrappedValue: [Date]())
        func content() -> FluentCalendarView {
            FluentCalendarView(selection: state.projectedValue, displayDate: date(2026, 1, 10), calendar: calendar)
        }
        let native = try make(content()), context = FluentRenderContext()
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        grid.scroll(to: date(2026, 1, 21), leading: true)
        XCTAssertEqual(calendar.component(.month, from: native.model.displayedDate), 2, "February has greater visible coverage than January")
        let origin = grid.contentView.bounds.origin
        let cells = grid.visibleCells
        for _ in 0..<30 { XCTAssertTrue(content()._updateView(native, in: context)) }
        XCTAssertEqual(grid.contentView.bounds.origin, origin)
        XCTAssertEqual(grid.visibleCells.map(ObjectIdentifier.init), cells.map(ObjectIdentifier.init))
        state.wrappedValue = [date(2026, 2, 14)]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(grid.contentView.bounds.origin, origin)
        XCTAssertTrue(try XCTUnwrap(grid.cell(for: date(2026, 2, 14))).selected)
    }
    @MainActor func testShortViewportNavigationDoesNotSkipDatesAndResizeKeepsTopRow() throws {
        func content(_ rows: Int) -> FluentCalendarView {
            FluentCalendarView(displayDate: date(2026, 5, 12), calendar: calendar, numberOfWeeksInView: rows)
        }
        let native = try make(content(2)), context = FluentRenderContext()
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let first = try XCTUnwrap(grid.visibleCells.first?.representedDate)
        let next = try XCTUnwrap(all(native).first { $0.identifier?.rawValue.hasSuffix(".NextMonth") == true } as? NSButton)
        next.performClick(nil)
        XCTAssertEqual(grid.visibleCells.first?.representedDate, calendar.date(byAdding: .day, value: 14, to: first))
        let top = grid.visibleCells.first?.representedDate
        XCTAssertTrue(content(8)._updateView(native, in: context))
        native.frame.size = native.intrinsicContentSize; native.layoutSubtreeIfNeeded()
        XCTAssertEqual(grid.visibleCells.first?.representedDate, top)
        XCTAssertEqual(grid.rows, 8); XCTAssertEqual(grid.visibleCells.count, 56)
        XCTAssertTrue(content(99)._updateView(native, in: context)); XCTAssertEqual(grid.rows, 8)
        XCTAssertTrue(content(0)._updateView(native, in: context)); XCTAssertEqual(grid.rows, 2)
    }
    @MainActor func testRangeChangesAndRTLKeepValidGeometryAndSelection() throws {
        let first = date(2026, 5, 10), last = date(2026, 5, 20)
        let native = try make(FluentCalendarView(displayDate: first, calendar: calendar))
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let cell = try XCTUnwrap(grid.cell(for: first)), oldX = cell.frame.minX
        native.userInterfaceLayoutDirection = .rightToLeft; native.layoutSubtreeIfNeeded()
        XCTAssertEqual(cell.frame.maxX, grid.documentView!.bounds.width - oldX, accuracy: 0.01)
        let context = FluentRenderContext(layoutDirection: .rightToLeft)
        XCTAssertTrue(FluentCalendarView(displayDate: first, range: first...last, calendar: calendar)._updateView(native, in: context))
        XCTAssertEqual(grid.geometry?.count, 11)
        XCTAssertEqual(grid.contentView.bounds.origin.y, 0)
        XCTAssertFalse(grid.canScrollBefore); XCTAssertFalse(grid.canScrollAfter)
        XCTAssertTrue(grid.realizedCells.allSatisfy { first...last ~= $0.representedDate! })
    }
    @MainActor func testDateArithmeticHandlesDSTSkippedDaysAndThirteenMonthYears() throws {
        for (zone, start, end) in [("America/Los_Angeles", date(2026,3,1), date(2026,3,20)),
                                   ("Pacific/Apia", date(2011,12,26), date(2012,1,4))] {
            var c = calendar; c.timeZone = TimeZone(identifier: zone)!
            let native = try make(FluentCalendarView(displayDate: start, range: start...end, calendar: c))
            let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
            let geometry = try XCTUnwrap(grid.geometry)
            let dates = (0..<geometry.count).compactMap { geometry.date(at: $0) }
            XCTAssertEqual(Set(dates).count, dates.count)
            for index in 0..<geometry.count {
                guard let day = geometry.date(at: index) else { continue }
                XCTAssertEqual(geometry.index(of: day), index)
                XCTAssertEqual(c.component(.hour, from: day), 0)
                XCTAssertEqual((index + geometry.leadingSlots) % 7,
                    (c.component(.weekday, from: day) - c.firstWeekday + 7) % 7,
                    "Dates must remain under the correct weekday after a time-zone day is skipped")
            }
            if zone == "Pacific/Apia" {
                XCTAssertEqual(geometry.count - dates.count, 1, "December 30 did not exist locally; retain its empty weekday slot")
                c.firstWeekday = 6
                let lower = c.date(from: DateComponents(year: 2011, month: 12, day: 16))!
                let upper = c.date(from: DateComponents(year: 2012, month: 1, day: 31))!
                let compact = try make(FluentCalendarView(displayDate: lower, range: lower...upper, calendar: c, numberOfWeeksInView: 2))
                let viewport = try XCTUnwrap(all(compact).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
                let initial = viewport.contentView.bounds.minY
                try XCTUnwrap(all(compact).first { $0.identifier?.rawValue.hasSuffix(".NextMonth") == true } as? NSButton).performClick(nil)
                XCTAssertGreaterThan(viewport.contentView.bounds.minY, initial, "Paging onto the missing December 30 slot must continue to the next valid date")
            }
        }
        var hebrew = Calendar(identifier: .hebrew); hebrew.timeZone = calendar.timeZone; hebrew.locale = calendar.locale
        let start = hebrew.date(from: DateComponents(year: 5784, month: 1, day: 1))!
        let native = try make(FluentCalendarView(displayDate: start, displayMode: .year, calendar: hebrew))
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let months = grid.visibleCells.compactMap(\.representedDate).filter { hebrew.component(.year, from: $0) == 5784 }
        XCTAssertEqual(Set(months.map { hebrew.component(.month, from: $0) }).count, 13)
    }

    @MainActor func testLevelChangeUsesVisibleScopeAfterScrollingAwayFromFocus() throws {
        let native = try make(FluentCalendarView(displayDate: date(2026, 5, 10), calendar: calendar))
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        grid.scroll(to: date(2050, 7, 1), leading: true)
        XCTAssertEqual(calendar.component(.year, from: native.model.displayedDate), 2050)
        let header = try XCTUnwrap(all(native).first { $0.identifier?.rawValue.hasSuffix(".Header") == true } as? NSButton)
        header.performClick(nil)
        XCTAssertEqual(native.model.mode, .year)
        XCTAssertEqual(calendar.component(.year, from: native.model.focusedDate), 2050)
        XCTAssertEqual(calendar.component(.year, from: native.model.displayedDate), 2050)
    }
    @MainActor func testMonthAndYearActivationPreserveSmallerDateFieldsAndClampInvalidDays() throws {
        let native = try make(FluentCalendarView(displayDate: date(2026, 1, 31), calendar: calendar))
        let window = NSWindow(contentRect: native.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = native; window.makeKeyAndOrderFront(nil); defer { window.close() }
        let grid = try XCTUnwrap(all(native).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let header = try XCTUnwrap(all(native).first { $0.identifier?.rawValue.hasSuffix(".Header") == true } as? NSButton)
        header.performClick(nil)
        XCTAssertEqual(native.model.mode, .year)
        try XCTUnwrap(grid.cell(for: date(2026, 2, 1))).performClick(nil)
        XCTAssertEqual(native.model.mode, .month)
        XCTAssertEqual(native.model.focusedDate, date(2026, 2, 28))
        header.performClick(nil); header.performClick(nil)
        XCTAssertEqual(native.model.mode, .decade)
        try XCTUnwrap(grid.cell(for: date(2028, 1, 1))).performClick(nil)
        XCTAssertEqual(native.model.mode, .year)
        XCTAssertEqual(native.model.focusedDate, date(2028, 2, 28))
    }

}
