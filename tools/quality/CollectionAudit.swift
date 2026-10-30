import AppKit
import FluentKit

final class Counters { var bodies = 0; var makes = 0; var updates = 0; var attachments = 0 }
final class AttachmentView: NSView {
    let counters: Counters
    init(_ counters: Counters) { self.counters = counters; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 20) }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); counters.attachments += 1 }
}
struct Probe: FluentUpdatablePrimitiveView {
    let counters: Counters
    var body: NeverFluentView { NeverFluentView() }
    func _makeView(in context: FluentRenderContext) -> NSView {
        counters.makes += 1
        return NSTextField(labelWithString: "Unchanged sibling")
    }
    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool { counters.updates += 1; return true }
}
struct AuditScreen: FluentView {
    let text: FluentState<String>
    let counters: Counters
    let rows: Int
    let shell: Bool
    let navigation: Bool
    let native: AttachmentView
    var body: FluentAnyView {
        counters.bodies += 1
        let query = text.wrappedValue
        let content = FluentVStack(spacing: 0) {
            FluentTextFieldView(text: text.projectedValue, placeholder: "Type")
            FluentText(query)
            FluentListView(Array(0..<rows), rowHeight: 24) { _ in Probe(counters: counters) }.frame(height: 420)
            FluentNativeView(native)
        }
        if !shell { return FluentAnyView(content) }
        return FluentAnyView(FluentWindowShell(
            configuration: FluentWindowConfiguration(layout: .document, titleBarStyle: .extended,
                navigationPlacement: navigation ? .left : FluentWindowNavigationPlacement.none,
                backdrop: .solid, contentTransition: .none),
            title: "Input audit",
            items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
            selection: FluentBinding<String?>(get: { "home" }, set: { _ in }),
            header: { FluentEmptyView() }, content: { content }
        ))
    }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
@main struct CollectionAudit {
    @MainActor static func drain() async {
        for _ in 0..<4 { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } } }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var results: [[String: Any]] = []
        for configuration in [(false,false,1000),(true,false,1000),(false,false,5000),(true,false,5000)] {
            let (shell, navigation, rows) = configuration
            let counters = Counters()
            let state = FluentState(wrappedValue: "")
            let native = AttachmentView(counters)
            let host = FluentViewHost(AuditScreen(text: state, counters: counters, rows: rows, shell: shell, navigation: navigation, native: native),
                context: FluentRenderContext(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: true))
            let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 900,height: 700), styleMask: [.titled,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            await drain()
            let field = descendants(host).compactMap { $0 as? FluentTextField }.first!
            let before = (counters.bodies, counters.makes, counters.updates, counters.attachments)
            var elapsed: [Double] = []
            for i in 0..<10 {
                let start = ProcessInfo.processInfo.systemUptime
                field.stringValue = "audit-\(i)"
                field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
                await drain()
                host.layoutSubtreeIfNeeded()
                elapsed.append((ProcessInfo.processInfo.systemUptime - start)*1000)
            }
            let sorted = elapsed.sorted()
            results.append(["shell":shell,"navigation":navigation,"rows":rows,"textChanges":10,
                "bodyEvaluations":counters.bodies-before.0,"rowMakes":counters.makes-before.1,
                "rowUpdates":counters.updates-before.2,"nativeAttachments":counters.attachments-before.3,
                "meanMs":elapsed.reduce(0,+)/Double(elapsed.count),"p95Ms":sorted[Int(Double(sorted.count)*0.95)],
                "finalText":state.wrappedValue])
            window.close()
            await drain()
        }
        let data = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    }
}
