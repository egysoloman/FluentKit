import AppKit
import FluentKit

@main struct VisualAudit {
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
        for dark in [false,true] { for rtl in [false,true] { for vertical in [false,true] {
            let name = "\(dark ? "dark":"light")-\(rtl ? "rtl":"ltr")-\(vertical ? "vertical":"horizontal")"
            let context = FluentRenderContext(theme:.custom(colorScheme:dark ? .dark:.light,materialEffectsEnabled:false),reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight)
            var items = Array(0..<1000)
            let selection = FluentState(wrappedValue:0)
            func content() -> some FluentUpdatablePrimitiveView {
                FluentFlipView(items,id:\.self,selection:selection.projectedValue,orientation:vertical ? .vertical:.horizontal) { id in
                    FluentVStack(spacing:12) {
                        FluentText("Item \(id)",style:.title)
                        FluentText("A page with a stable identity",style:.caption)
                        FluentButtonView("Action \(id)") {}
                    }.padding(24).background(context.theme.cardFill,cornerRadius:8)
                }
            }
            let native = content()._makeView(in:context)
            let window = NSWindow(contentRect:NSRect(x:100,y:350,width:360,height:220),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false
            let stage = NSView(frame:NSRect(x:0,y:0,width:360,height:220)); stage.wantsLayer = true
            stage.layer?.backgroundColor = (dark ? NSColor(white:0.14,alpha:1):NSColor(white:0.95,alpha:1)).cgColor
            window.contentView = stage; stage.addSubview(native);native.frame = NSRect(x:20,y:20,width:320,height:180)
            window.makeKeyAndOrderFront(nil);native.layoutSubtreeIfNeeded()
            let container = all(native).first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" }!
            func record(_ phase: String) throws {
                native.layoutSubtreeIfNeeded()
                let visible = container.subviews.filter { !$0.isHidden }
                let positions = visible.map { ["id":$0.identifier?.rawValue ?? "","x":$0.frame.minX,"y":$0.frame.minY] as [String:Any] }
                records.append(["variant":name,"phase":phase,"selection":selection.wrappedValue,"mounted":container.subviews.count,
                    "visible":visible.count,"positions":positions,"value":native.accessibilityValue() as? String ?? ""])
                try capture(stage,name+"-"+phase)
            }
            try record("initial")
            let extent: CGFloat = vertical ? 180:320
            let physicalSign: CGFloat = !vertical && rtl ? 1:-1
            native.scrollWheel(with:wheel(physicalSign*extent*0.25,vertical:vertical,phase:1,time:10))
            precondition(selection.wrappedValue == 0)
            try record("partial")
            for _ in 0..<30 { _ = content()._updateView(native,in:context) }
            try record("refresh")
            native.scrollWheel(with:wheel(0,vertical:vertical,phase:4,time:11))
            precondition(selection.wrappedValue == 0)
            try record("snapback")
            native.scrollWheel(with:wheel(physicalSign*extent*0.7,vertical:vertical,phase:1,time:20))
            native.scrollWheel(with:wheel(0,vertical:vertical,phase:4,time:20.01))
            precondition(selection.wrappedValue == 1)
            native.mouseEntered(with:NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!)
            try record("next")
            let retained = container.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Page.1" }!
            items.insert(-1,at:0); _ = content()._updateView(native,in:context)
            precondition(selection.wrappedValue == 2)
            precondition(container.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Page.2" } === retained)
            try record("reorder")
            native.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:119)!)
            precondition(selection.wrappedValue == 1000)
            try record("last")
            window.close()
        }}}
        print(String(decoding:try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
