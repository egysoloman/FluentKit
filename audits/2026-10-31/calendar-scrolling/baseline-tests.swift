// The three original reproductions, usable in a separate e1c3300 checkout.
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
}
