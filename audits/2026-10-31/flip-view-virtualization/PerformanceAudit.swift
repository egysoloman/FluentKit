import AppKit
import FluentKit

@main struct PerformanceAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        var builds = 0, makes = 0, updates = 0, count = 1000
        let selection = FluentState(wrappedValue: 0), context = FluentRenderContext(reduceMotion: true)
        func content() -> some FluentUpdatablePrimitiveView {
            FluentFlipView(Array(0..<count), selection: selection.projectedValue) { value in
                builds += 1
                return FluentNativeView(make: { makes += 1; return NSTextField(labelWithString: "") },
                    update: { (field: NSTextField, _) in updates += 1; field.stringValue = String(value) })
            }
        }
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        var rows: [[String:Any]] = []
        let start = DispatchTime.now().uptimeNanoseconds
        let native = content()._makeView(in: context)
        native.frame = NSRect(x:0, y:0, width:320, height:180); native.layoutSubtreeIfNeeded()
        func record(_ name: String, since: UInt64, repeats: Int) {
            rows.append(["phase":name,"builders":builds,"makes":makes,"updates":updates,
                "mountedPages":all(native).filter { $0 is NSTextField }.count,"selection":selection.wrappedValue,
                "meanProcessingMs":Double(DispatchTime.now().uptimeNanoseconds-since)/1_000_000/Double(repeats)])
            builds = 0; makes = 0; updates = 0
        }
        record("initial", since:start, repeats:1)
        let beforeRefresh = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<30 { _ = content()._updateView(native, in:context); native.layoutSubtreeIfNeeded() }
        record("refresh30", since:beforeRefresh, repeats:30)
        let beforeJump = DispatchTime.now().uptimeNanoseconds
        native.keyDown(with:NSEvent.keyEvent(with:.keyDown, location:.zero, modifierFlags:[], timestamp:0,
            windowNumber:0, context:nil, characters:"", charactersIgnoringModifiers:"", isARepeat:false, keyCode:119)!)
        record("last", since:beforeJump, repeats:1)
        let beforeAppend = DispatchTime.now().uptimeNanoseconds
        count += 1; _ = content()._updateView(native, in:context); native.layoutSubtreeIfNeeded()
        record("append", since:beforeAppend, repeats:1)
        print(String(decoding:try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
