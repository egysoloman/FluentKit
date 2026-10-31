import AppKit
import FluentKit

@MainActor private final class DragTrace: NSObject, NSOutlineViewDataSource {
    let original: NSOutlineViewDataSource
    let output: URL
    var events: [[String: Any]] = []
    init(_ original: NSOutlineViewDataSource, output: URL) { self.original = original; self.output = output }
    func log(_ event: String, _ fields: [String: Any] = [:]) {
        events.append(fields.merging(["event": event]) { _, new in new })
        try! JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("drag-events.json"))
    }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original.responds(to: selector) }
    override func forwardingTarget(for selector: Selector!) -> Any? { original.responds(to: selector) ? original : super.forwardingTarget(for: selector) }
    func outlineView(_ view: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { original.outlineView?(view, numberOfChildrenOfItem: item) ?? 0 }
    func outlineView(_ view: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { original.outlineView!(view, child: index, ofItem: item) }
    func outlineView(_ view: NSOutlineView, isItemExpandable item: Any) -> Bool { original.outlineView?(view, isItemExpandable: item) ?? false }
    func outlineView(_ view: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        log("writer", ["row": view.row(forItem: item)])
        return original.outlineView?(view, pasteboardWriterForItem: item)
    }
    func outlineView(_ view: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt point: NSPoint, forItems items: [Any]) {
        log("begin", ["rows": items.map { view.row(forItem: $0) },
                      "pasteboardTypes": (session.draggingPasteboard.types ?? []).map(\.rawValue),
                      "registeredTypes": view.registeredDraggedTypes.map(\.rawValue),
                      "localMask": view.draggingSession(session, sourceOperationMaskFor: .withinApplication).rawValue])
        original.outlineView?(view, draggingSession: session, willBeginAt: point, forItems: items)
        session.enumerateDraggingItems(options: [], for: view, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragging, index, _ in
            guard index == 0, let components = dragging.imageComponents else { return }
            self.log("image", ["components": components.map { ["key": $0.key.rawValue, "frame": NSStringFromRect($0.frame)] }])
            let size = dragging.draggingFrame.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)
            for component in components { (component.contents as? NSImage)?.draw(in: component.frame) }
            NSGraphicsContext.restoreGraphicsState()
            try! bitmap.representation(using: .png, properties: [:])!.write(to: self.output.appendingPathComponent("drag-preview.png"))
        }
    }
    func outlineView(_ view: NSOutlineView, draggingSession session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        log("end", ["operation": operation.rawValue]); original.outlineView?(view, draggingSession: session, endedAt: point, operation: operation)
    }
    func outlineView(_ view: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let result = original.outlineView?(view, validateDrop: info, proposedItem: item, proposedChildIndex: index) ?? []
        log("validate", ["source": String(describing: type(of: info.draggingSource as Any)), "sameSource": info.draggingSource as? NSOutlineView === view,
                         "row": item.map { view.row(forItem: $0) } ?? -1, "index": index, "operation": result.rawValue])
        return result
    }
    func outlineView(_ view: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let result = original.outlineView?(view, acceptDrop: info, item: item, childIndex: index) ?? false
        log("accept", ["index": index, "accepted": result]); return result
    }
}

@MainActor private final class Recorder: NSObject {
    let host: NSView
    let output: URL
    var states: [[String: Any]] = []
    init(_ host: NSView, output: URL) { self.host = host; self.output = output }
    func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @objc func record(_ sender: Any?) {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
        let outline = all(host).compactMap { $0 as? NSOutlineView }.first!
        var rows: [[String: Any]] = []
        for i in 0..<outline.numberOfRows {
            guard let item = outline.item(atRow: i), let cell = outline.view(atColumn: 0, row: i, makeIfNecessary: true) else { continue }
            rows.append(["labels": all(cell).compactMap { ($0 as? NSTextField)?.stringValue },
                         "depth": outline.level(forItem: item), "expanded": outline.isItemExpanded(item)])
        }
        states.append(["rows": rows, "text": all(host).compactMap { ($0 as? NSTextField)?.stringValue }])
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        cg.scaleBy(x: 2, y: 2)
        if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
        host.layer!.render(in: cg)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("state-\(states.count).png"))
        try! JSONSerialization.data(withJSONObject: states, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("states.json"))
    }
    @objc func quit(_ sender: Any?) { NSApp.stop(nil) }
}

@main struct TreeDragInteractive {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                         : Bundle.main.object(forInfoDictionaryKey: "AuditOutputPath") as! String)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        let host = FluentViewHost(TreeViewGallerySample(), context: FluentRenderContext(theme: theme, reduceMotion: false))
        host.wantsLayer = true; host.layer?.backgroundColor = theme.windowBackground.cgColor
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "TreeView drag review"; window.appearance = NSAppearance(named: .aqua)
        window.contentView = host; window.center(); window.makeKeyAndOrderFront(nil)
        let recorder = Recorder(host, output: output), menu = NSMenu(), root = NSMenuItem(), submenu = NSMenu()
        host.layoutSubtreeIfNeeded()
        let outline = recorder.all(host).compactMap { $0 as? NSOutlineView }.first!
        let trace = DragTrace(outline.dataSource!, output: output)
        outline.dataSource = trace
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { event in
            if event.window === window { trace.log("mouse", ["type": event.type.rawValue, "location": NSStringFromPoint(event.locationInWindow)]) }
            return event
        }
        root.submenu = submenu; menu.addItem(root)
        let capture = NSMenuItem(title: "Record tree", action: #selector(Recorder.record(_:)), keyEquivalent: "s")
        capture.keyEquivalentModifierMask = [.command, .shift]; capture.target = recorder; submenu.addItem(capture)
        let quit = NSMenuItem(title: "Quit review", action: #selector(Recorder.quit(_:)), keyEquivalent: "q")
        quit.target = recorder; submenu.addItem(quit); NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
        withExtendedLifetime((recorder, trace)) { NSApp.run() }
        if let monitor { NSEvent.removeMonitor(monitor) }
        window.close()
    }
}
