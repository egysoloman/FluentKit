import AppKit

/// A lightweight drag source wrapper for declarative views.
/// The payload is encoded by the caller so FluentKit does not impose a model format.
public struct FluentDragSource<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let payload: NSPasteboardWriting

    public init(_ payload: NSPasteboardWriting, @FluentViewBuilder content: () -> Content) {
        self.payload = payload
        self.content = content()
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentDragSourceHost(payload: payload, content: content._mount(in: context))
        host.updateContent = { [content] nativeView, updateContext in content._update(nativeView, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentDragSourceHost else { return false }
        host.payload = payload
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentDragSourceHost: NSView {
    var payload: NSPasteboardWriting
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var dragStart: NSPoint?

    init(payload: NSPasteboardWriting, content: NSView) {
        self.payload = payload
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - start.x, location.y - start.y)
        guard distance >= 4 else { return }
        let draggingItem = NSDraggingItem(pasteboardWriter: payload)
        draggingItem.setDraggingFrame(bounds, contents: bitmapImage())
        beginDraggingSession(with: [draggingItem], event: event, source: DragSource(window: window, startPoint: start))
        self.dragStart = nil
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }

    private func bitmapImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            layer?.render(in: context)
        }
        image.unlockFocus()
        return image
    }
}

private final class DragSource: NSObject, NSDraggingSource {
    let window: NSWindow
    let startPoint: NSPoint
    init(window: NSWindow, startPoint: NSPoint) { self.window = window; self.startPoint = startPoint }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {}
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {}
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {}
}

/// A drop target that accepts pasteboard data and reports the first matching item to the caller.
public struct FluentDropTarget<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let types: [NSPasteboard.PasteboardType]
    private let onDrop: ([NSPasteboardItem]) -> Void

    public init(types: [NSPasteboard.PasteboardType], @FluentViewBuilder content: () -> Content, onDrop: @escaping ([NSPasteboardItem]) -> Void) {
        self.types = types
        self.content = content()
        self.onDrop = onDrop
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentDropTargetHost(types: types, onDrop: onDrop, content: content._mount(in: context))
        host.updateContent = { [content] nativeView, updateContext in content._update(nativeView, in: updateContext) }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentDropTargetHost else { return false }
        host.types = types
        host.onDrop = onDrop
        host.registerForDraggedTypes(types)
        return host.updateContent?(host.contentView, context) ?? false
    }
}

private final class FluentDropTargetHost: NSView {
    var types: [NSPasteboard.PasteboardType]
    var onDrop: ([NSPasteboardItem]) -> Void
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }
    private var isDropTargeted = false { didSet { needsDisplay = true } }

    init(types: [NSPasteboard.PasteboardType], onDrop: @escaping ([NSPasteboardItem]) -> Void, content: NSView) {
        self.types = types
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes(types)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard supports(sender.draggingPasteboard) else { return [] }
        isDropTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isDropTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isDropTargeted = false }
        let items = sender.draggingPasteboard.pasteboardItems ?? []
        guard supports(sender.draggingPasteboard), !items.isEmpty else { return false }
        onDrop(items)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isDropTargeted else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        dirtyRect.fill()
    }

    private func supports(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(where: types.contains) == true
    }
}
