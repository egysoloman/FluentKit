import AppKit

/// A virtualized paging control with adjacent-page caching, axis-aware navigation and single-page
/// gesture settling. Only mounted pages evaluate their content. Keep durable page state in the model:
/// pages outside the cache are unmounted. Selection is zero-based, clamped, or -1 when empty.
/// The default initializer identifies pages by position; use `id:` to preserve identity on edits.
public struct FluentFlipView<Data: RandomAccessCollection, Content: FluentView>: FluentUpdatablePrimitiveView {
    private let data: Data
    private let selection: FluentBinding<Int>?
    private let orientation: NSUserInterfaceLayoutOrientation
    private let onSelectionChanged: ((Int) -> Void)?
    private let content: (Data.Element) -> Content
    private let identity: ((Data.Element) -> AnyHashable)?

    public init(_ data: Data, selection: FluentBinding<Int>? = nil,
                orientation: NSUserInterfaceLayoutOrientation = .horizontal,
                onSelectionChanged: ((Int) -> Void)? = nil,
                @FluentViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.selection = selection; self.orientation = orientation
        self.onSelectionChanged = onSelectionChanged; self.content = content; identity = nil
    }

    /// Stable IDs preserve the selected item and mounted native content when items move.
    /// IDs should be unique; duplicate IDs are distinguished by their occurrence in the input.
    public init<ID: Hashable>(_ data: Data, id: KeyPath<Data.Element, ID>, selection: FluentBinding<Int>? = nil,
                orientation: NSUserInterfaceLayoutOrientation = .horizontal,
                onSelectionChanged: ((Int) -> Void)? = nil,
                @FluentViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.selection = selection; self.orientation = orientation
        self.onSelectionChanged = onSelectionChanged; self.content = content
        identity = { AnyHashable($0[keyPath: id]) }
    }

    public var body: NeverFluentView { NeverFluentView() }
    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentFlipViewHost(source: makeSource(), selection: selection, orientation: orientation,
            onSelectionChanged: onSelectionChanged, context: context)
    }
    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFlipViewHost else { return false }
        host.update(source: makeSource(), selection: selection, orientation: orientation,
            onSelectionChanged: onSelectionChanged, context: context)
        return true
    }
    private func makeSource() -> FluentFlipViewSource {
        let count = data.count
        let idAt: (Int) -> AnyHashable
        let indexOf: (AnyHashable) -> Int?
        if let identity {
            var ids: [AnyHashable] = [], indices: [AnyHashable: Int] = [:], occurrences: [AnyHashable: Int] = [:]
            ids.reserveCapacity(count)
            for element in data {
                let raw = identity(element), occurrence = occurrences[raw, default: 0]
                occurrences[raw] = occurrence + 1
                let id = AnyHashable(FluentFlipPageIdentity.identified(raw, occurrence))
                indices[id] = ids.count; ids.append(id)
            }
            idAt = { ids[$0] }; indexOf = { indices[$0] }
        } else {
            idAt = { AnyHashable(FluentFlipPageIdentity.position($0)) }
            indexOf = { id in
                guard let value = id.base as? FluentFlipPageIdentity, case let .position(index) = value,
                      (0..<count).contains(index) else { return nil }
                return index
            }
        }
        return FluentFlipViewSource(count: count, id: idAt, index: indexOf, view: { index in
            let element = data[data.index(data.startIndex, offsetBy: index)]
            // Evaluate the builder inside the page host's dependency scope, including when a
            // page is first realized by a gesture rather than during the parent's render.
            return FluentAnyView(FluentFlipPageBody(element: element, content: content))
        })
    }
}

private enum FluentFlipPageIdentity: Hashable {
    case position(Int)
    case identified(AnyHashable, Int)
}
private struct FluentFlipPageBody<Element, Content: FluentView>: FluentView {
    let element: Element
    let content: (Element) -> Content
    var body: Content { content(element) }
}
struct FluentFlipViewSource {
    let count: Int
    let id: (Int) -> AnyHashable
    let index: (AnyHashable) -> Int?
    let view: (Int) -> FluentAnyView
}
