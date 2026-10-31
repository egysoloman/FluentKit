import AppKit
import FluentKit

@main struct TitleBarAudit {
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
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:code == 49 ? " ":"",charactersIgnoringModifiers:code == 49 ? " ":"",isARepeat:false,keyCode:code)!
        }
        var records: [[String:Any]] = []
        for dark in [false,true] { for rtl in [false,true] { for height: CGFloat in [32,48] {
            let name = "\(dark ? "dark":"light")-\(rtl ? "rtl":"ltr")-\(Int(height))"
            let context = FluentRenderContext(theme:.custom(colorScheme:dark ? .dark:.light,materialEffectsEnabled:false),reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight)
            var calls = 0
            func definition(_ visible: Bool) -> FluentTitleBar {
                FluentTitleBar(title:"Settings",heightMode:.fixed(height),isBackButtonVisible:visible,
                    extendsIntoWindowChrome:false,onBack:{ calls += 1 })
            }
            let native = definition(true)._makeView(in:context)
            let window = NSWindow(contentRect:NSRect(x:100,y:350,width:340,height:80),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false
            let stage = NSView(frame:NSRect(x:0,y:0,width:340,height:80)); stage.wantsLayer = true
            stage.layer?.backgroundColor = (dark ? NSColor(white:0.125,alpha:1):NSColor(white:0.95,alpha:1)).cgColor
            window.contentView = stage; stage.addSubview(native);native.frame = NSRect(x:10,y:16,width:320,height:height)
            window.makeKeyAndOrderFront(nil);native.layoutSubtreeIfNeeded()
            let back = all(native).first { $0.identifier?.rawValue == "FluentKit.TitleBar.Back" } as! NSButton
            func record(_ phase: String) throws {
                native.layoutSubtreeIfNeeded()
                records.append(["variant":name,"phase":phase,"calls":calls,"width":back.frame.width,"height":back.frame.height])
                try capture(stage,name+"-"+phase)
            }
            try record("normal")
            back.mouseEntered(with:NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!)
            try record("hover")
            back.keyDown(with:key(49));try record("pressed")
            back.keyDown(with:key(53))
            _ = definition(false)._updateView(native,in:context);native.layoutSubtreeIfNeeded()
            _ = definition(true)._updateView(native,in:context);native.layoutSubtreeIfNeeded()
            try record("redisplayed")
            window.close()
        }}}
        print(String(decoding:try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
