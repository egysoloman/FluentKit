import AppKit

/// Arithmetic item source: no array proportional to the supported date range is constructed.
struct FluentCalendarGridGeometry: Equatable {
    let calendar: Calendar
    let mode: FluentCalendarDisplayMode
    let first: Date
    let count: Int
    let leadingSlots: Int
    private let indexingCalendar: Calendar
    private let firstIndexDate: Date
    private let unitIndex: FluentCalendarUnitIndex?
    var columns: Int { mode == .month ? 7 : 4 }
    var unit: Calendar.Component { mode == .month ? .day : mode == .year ? .month : .year }
    var rowCount: Int { (count + leadingSlots + columns - 1) / columns }

    init(model: FluentCalendarModel) {
        calendar = model.calendar; mode = model.mode
        let unit: Calendar.Component = mode == .month ? .day : mode == .year ? .month : .year
        let minDate = model.configuration.effectiveMinDate, maxDate = model.configuration.effectiveMaxDate
        first = FluentCalendarPeriods.interval(unit, containing: minDate, calendar: calendar).start
        let last = FluentCalendarPeriods.interval(unit, containing: maxDate, calendar: calendar).start
        unitIndex = mode == .month ? nil : FluentCalendarUnitIndex(calendar: calendar, unit: unit, first: minDate, last: maxDate)
        // Index month cells by civil dates, not elapsed local days. A date-line change can
        // skip an entire local day (Apia, 2011-12-30); that slot must remain empty so that
        // every later date stays under the correct weekday column.
        var indexing = calendar
        if mode == .month { indexing.timeZone = TimeZone(secondsFromGMT: 0)! }
        indexingCalendar = indexing
        firstIndexDate = mode == .month ? Self.project(first, from: calendar, to: indexing) : first
        let lastIndexDate = mode == .month ? Self.project(last, from: calendar, to: indexing) : last
        count = unitIndex?.count ?? max(1, (indexing.dateComponents([unit], from: firstIndexDate, to: lastIndexDate).value(for: unit) ?? 0) + 1)
        leadingSlots = mode == .month ? (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7 : 0
    }
    func date(at index: Int) -> Date? {
        guard (0..<count).contains(index) else { return nil }
        if let unitIndex { return unitIndex.date(at: index) }
        guard let date = indexingCalendar.date(byAdding: unit, value: index, to: firstIndexDate) else { return nil }
        guard mode == .month else { return date }
        let parts = indexingCalendar.dateComponents([.era, .year, .month, .day], from: date)
        guard let local = calendar.date(from: parts),
              calendar.dateComponents([.era, .year, .month, .day], from: local) == parts else { return nil }
        return calendar.startOfDay(for: local)
    }
    func index(of date: Date) -> Int {
        if let unitIndex { return unitIndex.index(of: date) }
        let start = calendar.dateInterval(of: unit, for: date)?.start ?? date
        let indexed = mode == .month ? Self.project(start, from: calendar, to: indexingCalendar) : start
        return min(count - 1, max(0, indexingCalendar.dateComponents([unit], from: firstIndexDate, to: indexed).value(for: unit) ?? 0))
    }
    private static func project(_ date: Date, from source: Calendar, to target: Calendar) -> Date {
        target.date(from: source.dateComponents([.era, .year, .month, .day], from: date)) ?? date
    }
    func row(of index: Int) -> Int { (index + leadingSlots) / columns }
    func indices(firstRow: Int, lastRow: Int) -> Range<Int> {
        let lower = min(count, max(0, firstRow * columns - leadingSlots))
        let upper = min(count, max(lower, (lastRow + 1) * columns - leadingSlots))
        return lower..<upper
    }
}

private final class FluentCalendarDocumentView: NSView {
    override var isFlipped: Bool { true }
    // A long date range needs a coordinate space, not a bitmap the size of that space.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
}

final class FluentCalendarGridView: NSScrollView {
    private(set) var geometry: FluentCalendarGridGeometry?
    private(set) var rowHeight: CGFloat = 1
    private(set) var rows = 6
    var allowsScrolling = true
    var configureCell: ((FluentCalendarButton, Date) -> Void)?
    var onVisibleDatesChanged: (([Date]) -> Void)?
    private let document = FluentCalendarDocumentView()
    private var active: [Int: FluentCalendarButton] = [:]
    private var spare: [FluentCalendarButton] = []
    private var boundsObserver: NSObjectProtocol?
    private var updating = false
    private var previousVisibleIndices: [Int] = []
    private var previousSize = NSSize.zero
    private var pendingTopRow: CGFloat?
    private let prefix: String

    init(prefix: String) {
        self.prefix = prefix
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(prefix + ".Scroll")
        drawsBackground = false; borderType = .noBorder
        hasHorizontalScroller = false; hasVerticalScroller = false
        horizontalScrollElasticity = .none; verticalScrollElasticity = .none
        document.wantsLayer = true; document.identifier = NSUserInterfaceItemIdentifier(prefix + ".Document")
        documentView = document
        contentView.postsBoundsChangedNotifications = true
        contentView.wantsLayer = true; contentView.layer?.masksToBounds = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            self?.active.values.forEach { $0.clearPointerHover() }
            self?.realize()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }
    override var frame: NSRect {
        willSet {
            if newValue.size != frame.size, pendingTopRow == nil {
                pendingTopRow = contentView.bounds.minY / rowHeight
            }
        }
    }
    override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        didSet { if oldValue != userInterfaceLayoutDirection { realize(forceLayout: true) } }
    }
    override func scrollWheel(with event: NSEvent) {
        if allowsScrolling { super.scrollWheel(with: event) }
        else { nextResponder?.scrollWheel(with: event) }
    }
    var visibleIndices: Range<Int> {
        guard let geometry, contentView.bounds.height > 0 else { return 0..<0 }
        return geometry.indices(firstRow: Int(floor(contentView.bounds.minY / rowHeight + 0.0000001)),
            lastRow: Int(ceil(contentView.bounds.maxY / rowHeight - 0.000001)) - 1)
    }
    var visibleCells: [FluentCalendarButton] {
        visibleIndices.compactMap { active[$0] }.filter { $0.frame.intersects(contentView.bounds) }
    }
    var realizedCells: [FluentCalendarButton] { active.keys.sorted().compactMap { active[$0] } }
    func date(for cell: FluentCalendarButton) -> Date? {
        cell.representedDate
    }
    func cell(for date: Date) -> FluentCalendarButton? { geometry.flatMap { active[$0.index(of: date)] } }
    var canScrollBefore: Bool { contentView.bounds.minY > 0.5 }
    var canScrollAfter: Bool { contentView.bounds.maxY < document.frame.height - 0.5 }

    @discardableResult func setModel(_ model: FluentCalendarModel, rows: Int) -> Bool {
        let next = FluentCalendarGridGeometry(model: model)
        let changed = geometry != next
        if changed {
            if active.values.contains(where: { window?.firstResponder === $0 }) { window?.makeFirstResponder(superview) }
            for cell in active.values { recycle(cell) }
            active.removeAll(); previousVisibleIndices = []
            geometry = next
        }
        self.rows = rows
        updateMetrics()
        return changed
    }
    override func layout() {
        super.layout()
        updateMetrics()
    }
    private func updateMetrics() {
        guard !updating, let geometry else { return }
        updating = true
        let oldRow = pendingTopRow ?? contentView.bounds.minY / rowHeight
        pendingTopRow = nil
        let size = contentView.bounds.size
        let height = max(1, size.height / CGFloat(rows))
        let changed = height != rowHeight || size != previousSize
        rowHeight = height; previousSize = size
        document.frame = NSRect(x: 0, y: 0, width: max(0, size.width), height: max(size.height, CGFloat(geometry.rowCount) * rowHeight))
        if changed {
            contentView.scroll(to: NSPoint(x: 0, y: min(max(0, oldRow * rowHeight), max(0, document.frame.height - size.height))))
            reflectScrolledClipView(contentView)
        }
        updating = false
        realize(forceLayout: true)
    }
    func scroll(to date: Date, leading: Bool) {
        guard let geometry else { return }
        let top = CGFloat(geometry.row(of: geometry.index(of: date))) * rowHeight
        var y = contentView.bounds.minY
        if leading || top < y { y = top }
        else if top + rowHeight > contentView.bounds.maxY { y = top + rowHeight - contentView.bounds.height }
        y = min(max(0, y), max(0, document.frame.height - contentView.bounds.height))
        contentView.scroll(to: NSPoint(x: 0, y: y)); reflectScrolledClipView(contentView)
        realize()
    }
    func refreshCells() {
        guard let geometry else { return }
        for (index, cell) in active {
            if let date = geometry.date(at: index) { configureCell?(cell, date) }
        }
        realize(forceLayout: true)
    }
    private func recycle(_ cell: FluentCalendarButton) {
        cell.prepareForReuse(); cell.isHidden = true; spare.append(cell)
    }
    private func realize(forceLayout: Bool = false) {
        guard !updating, pendingTopRow == nil, let geometry else { return }
        updating = true
        let visible = visibleIndices
        let firstRow = Int(floor(contentView.bounds.minY / rowHeight + 0.0000001))
        let lastRow = Int(ceil(contentView.bounds.maxY / rowHeight - 0.000001)) - 1
        let wanted = contentView.bounds.height > 0 ? geometry.indices(firstRow: max(0, firstRow - 1), lastRow: lastRow + 1) : 0..<0
        // Keep the actual responder alive while it is offscreen; it must never turn into another date.
        for index in Array(active.keys) where !wanted.contains(index) {
            guard let cell = active[index], window?.firstResponder !== cell else { continue }
            active.removeValue(forKey: index); recycle(cell)
        }
        let width = document.bounds.width / CGFloat(geometry.columns)
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        var added = false
        for index in wanted {
            if active[index] == nil, let date = geometry.date(at: index) {
                let cell = spare.popLast() ?? FluentCalendarButton()
                if cell.superview == nil { document.addSubview(cell) }
                cell.identifier = NSUserInterfaceItemIdentifier(prefix + ".Day.\(index)")
                cell.isHidden = false; cell.representedDate = date; active[index] = cell
                configureCell?(cell, date); added = true
            }
        }
        for (index, cell) in active {
            if forceLayout || added {
                let column = (index + geometry.leadingSlots) % geometry.columns
                let x = CGFloat(rtl ? geometry.columns - column - 1 : column) * width
                cell.frame = NSRect(x: x + min(1, width / 2), y: CGFloat(geometry.row(of: index)) * rowHeight + min(1.5, rowHeight / 2),
                    width: max(0, width - 2), height: max(0, rowHeight - 3))
                cell.userInterfaceLayoutDirection = userInterfaceLayoutDirection
            }
            let exposed = visible.contains(index) && cell.frame.intersects(contentView.bounds)
            cell.setAccessibilityElement(exposed)
            if !exposed { cell.participatesInTabOrder = false }
        }
        document.setAccessibilityChildren(visibleCells)
        let exposed = visible.filter { active[$0]?.frame.intersects(contentView.bounds) == true }
        let changed = previousVisibleIndices != exposed
        previousVisibleIndices = exposed
        updating = false
        if changed || forceLayout { onVisibleDatesChanged?(exposed.compactMap { geometry.date(at: $0) }) }
    }
}
