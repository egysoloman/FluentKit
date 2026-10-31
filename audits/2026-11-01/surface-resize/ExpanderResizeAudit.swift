import AppKit
import FluentKit

@main struct ExpanderResizeAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func capture(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); CATransaction.flush()
            let size = view.bounds.size
            let image = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*2),pixelsHigh:Int(size.height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let context = NSGraphicsContext(bitmapImageRep:image)!.cgContext; context.scaleBy(x:2,y:2)
            if view.isFlipped { context.translateBy(x:0,y:size.height);context.scaleBy(x:1,y:-1) }
            view.layer!.render(in:context)
            try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        var records: [[String:Any]] = []
        for dark in [false,true] {
            let context = FluentRenderContext(theme:.custom(colorScheme:dark ? .dark:.light,materialEffectsEnabled:false),reduceMotion:true)
            let expanded = FluentState(wrappedValue:false)
            let root = FluentViewHost(FluentVStack(spacing:16,alignment:.width) {
                FluentExpander("Expandable content",isExpanded:expanded.projectedValue) {
                    FluentText("Content stays inside the expanded surface.").frame(height:80)
                }
                FluentSettingsExpander("Settings group",description:"This row should fill the available width.",isExpanded:expanded.projectedValue) {
                    FluentText("A setting inside the group").frame(height:80)
                }
            }.padding(20),context:context)
            let window = NSWindow(contentRect:NSRect(x:100,y:250,width:400,height:420),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false;window.contentView = root; window.makeKeyAndOrderFront(nil)
            root.wantsLayer = true;root.layer?.backgroundColor = context.theme.windowBackground.cgColor
            for (round, width) in [CGFloat(400),1200,400].enumerated() { for isExpanded in [false,true] {
                window.setContentSize(NSSize(width:width,height:420)); expanded.wrappedValue = isExpanded
                root.layoutSubtreeIfNeeded()
                let name = "\(dark ? "dark":"light")-\(round)-\(Int(width))-\(isExpanded ? "expanded":"collapsed")"
                let sizes = all(root).filter { $0.identifier?.rawValue == "FluentKit.Expander" || $0.identifier?.rawValue == "FluentKit.Settings.Expander" || $0.identifier?.rawValue.hasSuffix(".Header") == true }.map {
                    ["id":$0.identifier!.rawValue,"width":$0.bounds.width,"height":$0.bounds.height] as [String:Any]
                }
                records.append(["variant":name,"sizes":sizes]);try capture(root,name)
            }}
            window.close()
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
