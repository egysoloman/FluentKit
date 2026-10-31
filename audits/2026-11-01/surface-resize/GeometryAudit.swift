import AppKit
import FluentKit

final class Root: NSView {
    let material = FluentMaterialView(material:.mica)
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        material.isMaterialEnabled = false
        material.fallbackColor = NSColor(srgbRed:0.125,green:0.125,blue:0.125,alpha:1)
        addSubview(material)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() { super.layout(); material.frame = bounds }
}
@main struct GeometryAudit {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let window = NSWindow(contentRect:NSRect(x:100,y:100,width:640,height:480),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let root = Root(frame:NSRect(x:0,y:0,width:640,height:480)); window.contentView = root
        root.layout();window.makeKeyAndOrderFront(nil)
        for size in [NSSize(width:640,height:480),NSSize(width:1400,height:850),NSSize(width:400,height:300)] {
            window.setContentSize(size);root.layoutSubtreeIfNeeded();window.displayIfNeeded()
            let fallback = root.material.layer!.sublayers!.first { $0.name == "FluentKit.Material.OpaqueFallback" }!
            print("root",root.bounds,"material",root.material.bounds,"fallback",fallback.frame,"needsLayout",root.material.needsLayout)
        }
        window.close()
    }
}
