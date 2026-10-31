import AppKit
import FluentKit

@main struct ScrollChainingAudit {
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
        func wheel(_ amount: CGFloat, vertical: Bool, phase: Int64, time: Double) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:vertical ? Int32(amount):0,wheel2:vertical ? 0:Int32(amount),wheel3:0)!
            cg.timestamp = UInt64(time*1_000_000_000)
            cg.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase,value:phase)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1,value:vertical ? Double(amount):0)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2,value:vertical ? 0:Double(amount))
            return NSEvent(cgEvent:cg)!
        }
        var records: [[String:Any]] = []
        for dark in [false,true] { for rtl in [false,true] { for vertical in [false,true] { for edge in [0,1] {
            let name = "\(dark ? "dark":"light")-\(rtl ? "rtl":"ltr")-\(vertical ? "vertical":"horizontal")-edge\(edge)"
            let context = FluentRenderContext(theme:.custom(colorScheme:dark ? .dark:.light,materialEffectsEnabled:false),reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight)
            let innerState = FluentState(wrappedValue:edge), outerState = FluentState(wrappedValue:1)
            func label(_ text: String) -> some FluentView {
                FluentVStack(spacing:12) {
                    FluentText(text,style:.title)
                    FluentText("Nested scroll handoff",style:.caption)
                }.padding(24).background(context.theme.cardFill,cornerRadius:8)
            }
            let inner = FluentFlipView([0,1],selection:innerState.projectedValue,orientation:vertical ? .vertical:.horizontal) { label("Inner \($0)") }._makeView(in:context)
            let native = FluentFlipView([0,1,2],selection:outerState.projectedValue,orientation:vertical ? .vertical:.horizontal) { id in
                if id == 1 { return FluentAnyView(FluentNativeView(make:{inner},update:{_,_ in})) }
                return FluentAnyView(label("Outer \(id)"))
            }._makeView(in:context)
            let window = NSWindow(contentRect:NSRect(x:100,y:350,width:360,height:220),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false
            let stage = NSView(frame:NSRect(x:0,y:0,width:360,height:220)); stage.wantsLayer = true
            stage.layer?.backgroundColor = (dark ? NSColor(white:0.14,alpha:1):NSColor(white:0.95,alpha:1)).cgColor
            window.contentView = stage; stage.addSubview(native);native.frame = NSRect(x:20,y:20,width:320,height:180)
            window.makeKeyAndOrderFront(nil);native.layoutSubtreeIfNeeded()
            precondition(inner.bounds.size == native.bounds.size)
            let container = all(native).first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" }!
            func record(_ phase: String) throws {
                native.layoutSubtreeIfNeeded()
                let positions = container.subviews.filter { !$0.isHidden }.map { ["id":$0.identifier?.rawValue ?? "","x":$0.frame.minX,"y":$0.frame.minY] as [String:Any] }
                records.append(["variant":name,"phase":phase,"innerSelection":innerState.wrappedValue,"outerSelection":outerState.wrappedValue,"expectedOuter":edge == 0 ? 0:2,"positions":positions])
                try capture(stage,name+"-"+phase)
            }
            try record("initial")
            let extent: CGFloat = vertical ? 180:320
            let sign: CGFloat = (edge == 0 ? 1:-1) * (!vertical && rtl ? -1:1)
            inner.scrollWheel(with:wheel(sign,vertical:vertical,phase:1,time:10))
            inner.scrollWheel(with:wheel(sign*extent*0.7,vertical:vertical,phase:2,time:10.01))
            try record("partial")
            inner.scrollWheel(with:wheel(0,vertical:vertical,phase:4,time:11))
            try record("settled")
            window.close()
        }}}}
        print(String(decoding:try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
