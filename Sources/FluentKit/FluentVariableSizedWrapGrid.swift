import AppKit

/// The WinUI `VariableSizedWrapGrid.Orientation` value.
public enum FluentVariableSizedWrapGridOrientation: Hashable, Sendable {
    case vertical
    case horizontal
}

/// One axis value for `HorizontalChildrenAlignment` and `VerticalChildrenAlignment`.
///
/// WinUI exposes these as `HorizontalAlignment` and `VerticalAlignment`, whose `Left`/`Top`,
/// `Center`, `Right`/`Bottom`, and `Stretch` values share the same offsets. A single axis-neutral
/// enum keeps both properties usable without naming the axis twice.
public enum FluentVariableSizedWrapGridAlignment: Hashable, Sendable {
    case leading
    case center
    case trailing
    case stretch
}

/// The `VariableSizedWrapGrid.RowSpan` and `ColumnSpan` attached-property pair.
public struct FluentVariableSizedWrapGridCell: Equatable, Sendable {
    public var rowSpan: Int
    public var columnSpan: Int

    public init(rowSpan: Int = 1, columnSpan: Int = 1) {
        self.rowSpan = max(rowSpan, 1)
        self.columnSpan = max(columnSpan, 1)
    }
}

private var fluentWrapGridCellKey: UInt8 = 0

private extension NSView {
    var fluentWrapGridCell: FluentVariableSizedWrapGridCell {
        get {
            (objc_getAssociatedObject(self, &fluentWrapGridCellKey) as? NSValue)
                .map(\.sizeValue)
                .map { FluentVariableSizedWrapGridCell(
                    rowSpan: max(Int($0.height), 1),
                    columnSpan: max(Int($0.width), 1)
                ) }
                ?? FluentVariableSizedWrapGridCell()
        }
        set {
            objc_setAssociatedObject(
                self,
                &fluentWrapGridCellKey,
                NSValue(size: NSSize(
                    width: CGFloat(newValue.columnSpan),
                    height: CGFloat(newValue.rowSpan)
                )),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/// Wraps a declarative child with the spans consumed by an enclosing `FluentVariableSizedWrapGrid`.
public struct FluentVariableSizedWrapGridPositionedView<Content: FluentView>:
    FluentUpdatablePrimitiveView
{
    fileprivate let content: Content
    fileprivate let cell: FluentVariableSizedWrapGridCell

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = content._mount(in: context)
        view.fluentWrapGridCell = cell
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        view.fluentWrapGridCell = cell
        view.superview?.needsLayout = true
        return content._update(view, in: context)
    }
}

public extension FluentView {
    /// Sets the `VariableSizedWrapGrid.RowSpan` and `ColumnSpan` used by an enclosing
    /// `FluentVariableSizedWrapGrid`. Values at or below zero are normalized to one, matching
    /// `VariableSizedWrapGrid::GetRowAndColumnSpan`.
    func variableSizedWrapGridPosition(
        rowSpan: Int = 1,
        columnSpan: Int = 1
    ) -> FluentVariableSizedWrapGridPositionedView<Self> {
        FluentVariableSizedWrapGridPositionedView(
            content: self,
            cell: FluentVariableSizedWrapGridCell(rowSpan: rowSpan, columnSpan: columnSpan)
        )
    }
}

private struct FluentVariableSizedWrapGridConfiguration {
    var itemWidth: CGFloat?
    var itemHeight: CGFloat?
    var orientation: FluentVariableSizedWrapGridOrientation
    var maximumRowsOrColumns: Int
    var horizontalChildrenAlignment: FluentVariableSizedWrapGridAlignment
    var verticalChildrenAlignment: FluentVariableSizedWrapGridAlignment
}

/// The declarative WinUI `VariableSizedWrapGrid`.
///
/// Children are packed through an occupancy map rather than a fixed grid, so unequal
/// `RowSpan`/`ColumnSpan` values reuse empty cells just like the WinUI implementation. The host
/// reports the WinUI measure result as its intrinsic size and re-runs the same packing pass
/// against the final AppKit slot in `layout()`.
public struct FluentVariableSizedWrapGridView<Content: FluentView>:
    FluentUpdatablePrimitiveView
{
    fileprivate let content: FluentAnyView
    fileprivate let configuration: FluentVariableSizedWrapGridConfiguration

    public init(
        itemWidth: CGFloat? = nil,
        itemHeight: CGFloat? = nil,
        orientation: FluentVariableSizedWrapGridOrientation = .vertical,
        maximumRowsOrColumns: Int = 0,
        horizontalChildrenAlignment: FluentVariableSizedWrapGridAlignment = .leading,
        verticalChildrenAlignment: FluentVariableSizedWrapGridAlignment = .leading,
        @FluentViewBuilder content: () -> Content
    ) {
        self.content = FluentAnyView(content())
        self.configuration = FluentVariableSizedWrapGridConfiguration(
            itemWidth: itemWidth.flatMap { $0.isNaN ? nil : $0 },
            itemHeight: itemHeight.flatMap { $0.isNaN ? nil : $0 },
            orientation: orientation,
            maximumRowsOrColumns: maximumRowsOrColumns,
            horizontalChildrenAlignment: horizontalChildrenAlignment,
            verticalChildrenAlignment: verticalChildrenAlignment
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentVariableSizedWrapGridHost(configuration: configuration)
        let children = content.children ?? [content]
        host.setChildren(children.map { $0.mount(context) })
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentVariableSizedWrapGridHost else { return false }
        let children = content.children ?? [content]
        guard host.subviews.count == children.count else { return false }

        host.update(configuration: configuration)
        for index in children.indices {
            let nativeChild = host.subviews[index]
            let child = children[index]
            if !child._update(nativeChild, in: context) {
                host.replaceChild(at: index, with: child.mount(context))
            }
        }
        return true
    }
}

public func FluentVariableSizedWrapGrid<Content: FluentView>(
    itemWidth: CGFloat? = nil,
    itemHeight: CGFloat? = nil,
    orientation: FluentVariableSizedWrapGridOrientation = .vertical,
    maximumRowsOrColumns: Int = 0,
    horizontalChildrenAlignment: FluentVariableSizedWrapGridAlignment = .leading,
    verticalChildrenAlignment: FluentVariableSizedWrapGridAlignment = .leading,
    @FluentViewBuilder content: () -> Content
) -> FluentVariableSizedWrapGridView<Content> {
    FluentVariableSizedWrapGridView(
        itemWidth: itemWidth,
        itemHeight: itemHeight,
        orientation: orientation,
        maximumRowsOrColumns: maximumRowsOrColumns,
        horizontalChildrenAlignment: horizontalChildrenAlignment,
        verticalChildrenAlignment: verticalChildrenAlignment,
        content: content
    )
}

private struct FluentWrapGridPoint: Hashable {
    var row: Int
    var column: Int
}

private struct FluentWrapGridInternalRect {
    var row: Int
    var column: Int
    var rowSpan: Int
    var columnSpan: Int
}

/// Faithful port of `VariableSizedWrapGrid::OccupancyMap`.
///
/// Like the original, the map always packs in an internal row-major coordinate system. Horizontal
/// orientation swaps the row/column spans before filling and swaps them back when converting the
/// stored location into an unoriented rectangle.
private struct FluentWrapGridOccupancyMap {
    let maxRow: Int
    let maxCol: Int
    let isHorizontal: Bool
    let itemSize: NSSize

    private var occupied: [FluentWrapGridPoint: Int] = [:]
    private var rects: [FluentWrapGridInternalRect]
    private var currentRow = 0
    private var currentColumn = 0
    private(set) var elementCount: Int

    init(
        maxRow: Int,
        maxCol: Int,
        isHorizontal: Bool,
        itemSize: NSSize,
        itemCount: Int
    ) {
        self.maxRow = max(1, maxRow)
        self.maxCol = max(1, maxCol)
        self.isHorizontal = isHorizontal
        self.itemSize = itemSize
        self.rects = Array(
            repeating: .init(row: 0, column: 0, rowSpan: 0, columnSpan: 0),
            count: itemCount
        )
        self.elementCount = itemCount
    }

    mutating func findAndFillNextAvailableRect(
        rowSpan: Int,
        columnSpan: Int,
        elementIndex: Int
    ) -> Bool {
        let isFull = findNextAvailableRectInternal(rowSpan: rowSpan, columnSpan: columnSpan)
        if !isFull {
            fillCurrentItemRect(
                rowSpan: rowSpan,
                columnSpan: columnSpan,
                elementIndex: elementIndex
            )
        }
        return isFull
    }

    func rect(forElementAt index: Int) -> FluentWrapGridInternalRect {
        rects[index]
    }

    func unorientedRect(forElementAt index: Int) -> NSRect {
        let rect = rects[index]
        if isHorizontal {
            return NSRect(
                x: itemSize.width * CGFloat(rect.row),
                y: itemSize.height * CGFloat(rect.column),
                width: itemSize.width * CGFloat(rect.rowSpan),
                height: itemSize.height * CGFloat(rect.columnSpan)
            )
        }
        return NSRect(
            x: itemSize.width * CGFloat(rect.column),
            y: itemSize.height * CGFloat(rect.row),
            width: itemSize.width * CGFloat(rect.columnSpan),
            height: itemSize.height * CGFloat(rect.rowSpan)
        )
    }

    mutating func updateElementCount(_ count: Int) {
        elementCount = min(max(0, count), rects.count)
    }

    private mutating func findNextAvailableRectInternal(
        rowSpan requestedRowSpan: Int,
        columnSpan requestedColumnSpan: Int
    ) -> Bool {
        let rowSpan = min(requestedRowSpan, maxRow)
        var columnSpan = min(requestedColumnSpan, maxCol)

        while currentColumn < maxCol {
            var isOccupied = true

            if currentRow == maxRow {
                currentRow = 0
                currentColumn += 1
                if currentColumn >= maxCol { break }
            }

            for column in 0..<columnSpan {
                if column + currentColumn >= maxCol {
                    columnSpan = maxCol - currentColumn
                    break
                }

                for row in 0..<rowSpan {
                    isOccupied = true
                    if currentRow + row < maxRow && currentColumn + column < maxCol {
                        isOccupied = occupied[
                            FluentWrapGridPoint(
                                row: currentRow + row,
                                column: currentColumn + column
                            )
                        ] != nil
                    }
                    if isOccupied { break }
                }

                if isOccupied { break }
            }

            if isOccupied {
                currentRow += 1
                if currentRow == maxRow || currentRow + rowSpan > maxRow {
                    currentRow = 0
                    currentColumn += 1
                }
            } else {
                break
            }
        }

        if currentColumn >= maxCol || currentRow >= maxRow {
            currentColumn = 0
            currentRow = 0
            return true
        }
        return false
    }

    private mutating func fillCurrentItemRect(
        rowSpan: Int,
        columnSpan: Int,
        elementIndex: Int
    ) {
        let origin = FluentWrapGridPoint(row: currentRow, column: currentColumn)
        var filledRowSpan = 0
        var filledColumnSpan = 0

        for column in 0..<columnSpan {
            for row in 0..<rowSpan {
                guard currentColumn + column < maxCol,
                      currentRow + row < maxRow else { continue }
                occupied[FluentWrapGridPoint(
                    row: currentRow + row,
                    column: currentColumn + column
                )] = elementIndex
                filledRowSpan = max(filledRowSpan, row + 1)
                filledColumnSpan = max(filledColumnSpan, column + 1)
            }
        }

        let storageIndex = elementIndex - 1
        rects[storageIndex] = FluentWrapGridInternalRect(
            row: origin.row,
            column: origin.column,
            rowSpan: filledRowSpan,
            columnSpan: filledColumnSpan
        )

        currentRow += rowSpan
        if currentRow >= maxRow {
            currentRow = 0
            currentColumn += 1
        }
    }
}

private struct FluentVariableSizedWrapGridLayoutResult {
    var naturalSize: NSSize
    var frames: [NSRect]
}

private enum FluentVariableSizedWrapGridLayoutEngine {
    static func resolve(
        configuration: FluentVariableSizedWrapGridConfiguration,
        children: [NSView],
        availableSize: NSSize,
        finalSize: NSSize
    ) -> FluentVariableSizedWrapGridLayoutResult {
        guard !children.isEmpty else {
            return FluentVariableSizedWrapGridLayoutResult(naturalSize: .zero, frames: [])
        }

        let isHorizontal = configuration.orientation == .horizontal
        let hasFixedWidth = configuration.itemWidth.map { $0.isFinite } == true
        let hasFixedHeight = configuration.itemHeight.map { $0.isFinite } == true

        let spans = children.map { $0.fluentWrapGridCell }

        // WinUI measures the first child before resolving missing cell dimensions. AppKit has no
        // measure constraint, so the unconstrained natural size plays the same role; explicit
        // ItemWidth/ItemHeight are recommended for tiles that must wrap at a fixed cadence.
        var itemWidth = hasFixedWidth ? max(0, configuration.itemWidth ?? 0) : availableSize.width
        var itemHeight = hasFixedHeight ? max(0, configuration.itemHeight ?? 0) : availableSize.height
        let firstDesiredSize = FluentVariableSizedWrapGridLayoutEngine.measuredNaturalSize(
            of: children[0]
        )
        if !hasFixedWidth {
            itemWidth = max(0, firstDesiredSize.width)
        }
        if !hasFixedHeight {
            itemHeight = max(0, firstDesiredSize.height)
        }
        let directItemSize = isHorizontal ? itemWidth : itemHeight
        let indirectItemSize = isHorizontal ? itemHeight : itemWidth
        let directAvailableSize = isHorizontal ? availableSize.width : availableSize.height
        let indirectAvailableSize = isHorizontal ? availableSize.height : availableSize.width

        let rowTileCount = spans.reduce(0) { $0 + $1.rowSpan }
        let columnTileCount = spans.reduce(0) { $0 + $1.columnSpan }

        var itemsPerLine: Int
        if directAvailableSize.isInfinite {
            itemsPerLine = isHorizontal ? columnTileCount : rowTileCount
        } else if directItemSize > 0 {
            itemsPerLine = Int(floor(directAvailableSize / directItemSize))
        } else {
            itemsPerLine = isHorizontal ? columnTileCount : rowTileCount
        }
        itemsPerLine = max(1, itemsPerLine)
        if configuration.maximumRowsOrColumns > 0 {
            itemsPerLine = min(itemsPerLine, configuration.maximumRowsOrColumns)
        }

        var maxColumn = isHorizontal ? rowTileCount : columnTileCount
        if indirectAvailableSize.isFinite {
            let availableCells = indirectItemSize > 0
                ? Int(floor(indirectAvailableSize / indirectItemSize))
                : Int.max
            maxColumn = min(availableCells, maxColumn)
        }
        maxColumn = max(1, maxColumn)

        var map = FluentWrapGridOccupancyMap(
            maxRow: itemsPerLine,
            maxCol: maxColumn,
            isHorizontal: isHorizontal,
            itemSize: NSSize(width: itemWidth, height: itemHeight),
            itemCount: children.count
        )

        for (index, span) in spans.enumerated() {
            let internalRowSpan = isHorizontal ? span.columnSpan : span.rowSpan
            let internalColumnSpan = isHorizontal ? span.rowSpan : span.columnSpan
            let isFull = map.findAndFillNextAvailableRect(
                rowSpan: internalRowSpan,
                columnSpan: internalColumnSpan,
                elementIndex: index + 1
            )
            if isFull {
                map.updateElementCount(index)
                break
            }
        }

        var usedRows = 0
        var usedColumns = 0
        for index in 0..<map.elementCount {
            let rect = map.rect(forElementAt: index)
            usedRows = max(usedRows, rect.row + rect.rowSpan)
            usedColumns = max(usedColumns, rect.column + rect.columnSpan)
        }

        let horizontalLines = isHorizontal ? usedRows : usedColumns
        let verticalLines = isHorizontal ? usedColumns : usedRows
        let horizontalAlignment = isHorizontal
            ? configuration.verticalChildrenAlignment
            : configuration.horizontalChildrenAlignment
        let verticalAlignment = isHorizontal
            ? configuration.horizontalChildrenAlignment
            : configuration.verticalChildrenAlignment

        let horizontalRequired = itemWidth * CGFloat(horizontalLines)
        let verticalRequired = itemHeight * CGFloat(verticalLines)
        let horizontalOffsets = computeAlignmentOffsets(
            alignment: horizontalAlignment,
            availableSize: availableSize.width,
            requiredSize: horizontalRequired,
            totalLines: horizontalLines
        )
        let verticalOffsets = computeAlignmentOffsets(
            alignment: verticalAlignment,
            availableSize: availableSize.height,
            requiredSize: verticalRequired,
            totalLines: verticalLines
        )

        let naturalWidth = horizontalRequired
            + horizontalOffsets.justification * CGFloat(horizontalLines + 1)
            + horizontalOffsets.starting * 2
        let naturalHeight = verticalRequired
            + verticalOffsets.justification * CGFloat(verticalLines + 1)
            + verticalOffsets.starting * 2

        let arrangeOffsets = (
            horizontal: computeAlignmentOffsets(
                alignment: horizontalAlignment,
                availableSize: finalSize.width,
                requiredSize: horizontalRequired,
                totalLines: horizontalLines
            ),
            vertical: computeAlignmentOffsets(
                alignment: verticalAlignment,
                availableSize: finalSize.height,
                requiredSize: verticalRequired,
                totalLines: verticalLines
            )
        )

        var frames: [NSRect] = []
        frames.reserveCapacity(map.elementCount)
        var totalJustification = NSSize.zero
        for index in 0..<map.elementCount {
            var rect = map.unorientedRect(forElementAt: index)
            let span = spans[index]

            // WinUI allows a tile whose span meets the maximum to escape the occupancy map's
            // clipping when it starts on the first line. Reproduce that override verbatim.
            if rect.minY == 0 || rect.minX == 0 {
                if !isHorizontal,
                   rect.minY == 0,
                   span.rowSpan >= usedRows {
                    let height = min(CGFloat(span.rowSpan) * itemHeight, finalSize.height)
                    rect.size.height = max(rect.size.height, height)
                } else if isHorizontal,
                          rect.minX == 0,
                          span.columnSpan >= usedRows {
                    let width = min(CGFloat(span.columnSpan) * itemWidth, finalSize.width)
                    rect.size.width = max(rect.size.width, width)
                }
            }

            if index % usedRows == 0 {
                if isHorizontal {
                    totalJustification.width = 0
                    totalJustification.height =
                        arrangeOffsets.vertical.justification * CGFloat(index / usedRows + 1)
                } else {
                    totalJustification.height = 0
                    totalJustification.width =
                        arrangeOffsets.horizontal.justification * CGFloat(index / usedRows + 1)
                }
            }

            if isHorizontal {
                totalJustification.width += arrangeOffsets.horizontal.justification
            } else {
                totalJustification.height += arrangeOffsets.vertical.justification
            }

            rect.origin.x += arrangeOffsets.horizontal.starting + totalJustification.width
            rect.origin.y += arrangeOffsets.vertical.starting + totalJustification.height
            frames.append(rect)
        }

        return FluentVariableSizedWrapGridLayoutResult(
            naturalSize: NSSize(width: naturalWidth, height: naturalHeight),
            frames: frames
        )
    }

    private static func computeAlignmentOffsets(
        alignment: FluentVariableSizedWrapGridAlignment,
        availableSize: CGFloat,
        requiredSize: CGFloat,
        totalLines: Int
    ) -> (starting: CGFloat, justification: CGFloat) {
        guard availableSize.isFinite else { return (0, 0) }
        switch alignment {
        case .center:
            return (max((availableSize - requiredSize) / 2, 0), 0)
        case .trailing:
            return (max(availableSize - requiredSize, 0), 0)
        case .stretch:
            return (0, max((availableSize - requiredSize) / CGFloat(max(1, totalLines) + 1), 0))
        case .leading:
            return (0, 0)
        }
    }

    private static func measuredNaturalSize(of child: NSView) -> NSSize {
        // Lay the leaf out directly instead of calling layoutSubtreeIfNeeded; the latter can
        // bubble back into this grid while its intrinsic size is being resolved and recurse.
        child.layout()
        var size = child.intrinsicContentSize
        if size.width == NSView.noIntrinsicMetric {
            size.width = child.fittingSize.width
        }
        if size.height == NSView.noIntrinsicMetric {
            size.height = child.fittingSize.height
        }
        return NSSize(width: max(0, size.width), height: max(0, size.height))
    }
}

private final class FluentVariableSizedWrapGridHost: NSView {
    private var configuration: FluentVariableSizedWrapGridConfiguration

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        FluentVariableSizedWrapGridLayoutEngine.resolve(
            configuration: configuration,
            children: subviews,
            availableSize: NSSize(
                width: CGFloat.infinity,
                height: CGFloat.infinity
            ),
            finalSize: NSSize(
                width: CGFloat.infinity,
                height: CGFloat.infinity
            )
        ).naturalSize
    }

    init(configuration: FluentVariableSizedWrapGridConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.VariableSizedWrapGrid")
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Variable sized wrap grid")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setChildren(_ children: [NSView]) {
        children.forEach { child in
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        needsLayout = true
    }

    func replaceChild(at index: Int, with child: NSView) {
        guard subviews.indices.contains(index) else { return }
        subviews[index].removeFromSuperview()
        child.translatesAutoresizingMaskIntoConstraints = false
        if index < subviews.count {
            addSubview(child, positioned: .below, relativeTo: subviews[index])
        } else {
            addSubview(child)
        }
        needsLayout = true
    }

    func update(configuration: FluentVariableSizedWrapGridConfiguration) {
        self.configuration = configuration
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let result = FluentVariableSizedWrapGridLayoutEngine.resolve(
            configuration: configuration,
            children: subviews,
            availableSize: bounds.size,
            finalSize: bounds.size
        )
        for index in subviews.indices {
            subviews[index].frame = index < result.frames.count ? result.frames[index] : .zero
        }
    }
}
