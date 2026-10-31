import AppKit
import FluentKit

@main struct PopupDensityAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func all(_ view:NSView) -> [NSView] { [view]+view.subviews.flatMap(all) }
        func capture(_ view:NSView,_ name:String) throws {
            view.layoutSubtreeIfNeeded();view.displayIfNeeded();CATransaction.flush()
            let size=view.bounds.size
            let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*2),pixelsHigh:Int(size.height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let cg=NSGraphicsContext(bitmapImageRep:image)!.cgContext;cg.scaleBy(x:2,y:2)
            if view.isFlipped { cg.translateBy(x:0,y:size.height);cg.scaleBy(x:1,y:-1) }
            view.layer!.render(in:cg)
            try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        var records:[[String:Any]]=[]
        for dark in [false,true] { for rtl in [false,true] { for device in ["mouse","trackpad","keyboard","direct-touch"] {
            let theme=FluentTheme.custom(colorScheme:dark ? .dark:.light,materialEffectsEnabled:false)
            let window=NSWindow(contentRect:NSRect(x:150,y:250,width:400,height:300),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            let selected=FluentState<String?>(wrappedValue:"中文")
            let combo=FluentComboBox(options:["中文","英文"],selection:selected.projectedValue)._makeView(in:FluentRenderContext(theme:theme,reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight))
            window.contentView?.addSubview(combo);combo.frame=NSRect(x:20,y:200,width:180,height:32)
            window.makeKeyAndOrderFront(nil);combo.layoutSubtreeIfNeeded()
            let tracker=FluentInputDeviceTracker.shared
            var classification:FluentInputDeviceType
            var subtype:Int16 = -1
            if device=="mouse" || device=="trackpad" {
                let event=NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!.cgEvent!
                if device=="trackpad" { event.setIntegerValueField(.mouseEventSubtype,value:Int64(NSEvent.EventSubtype.touch.rawValue)) }
                let native=NSEvent(cgEvent:event)!;subtype=native.subtype.rawValue
                classification=FluentInputDeviceTracker.deviceType(for:native)!
            } else { classification=device=="keyboard" ? .keyboard:.touch }
            tracker.record(classification,in:window)
            let name="\(dark ? "dark":"light")-\(rtl ? "rtl":"ltr")-\(device)"
            let native=all(combo).compactMap { $0 as? NSComboBox }.first!
            native.performClick(nil)
            let panel=window.childWindows!.first!
            let root=panel.contentView!
            let rows=all(root).filter { $0.accessibilityRole() == .row }
            records.append(["variant":name,"kind":"combo","device":String(describing:classification),"subtype":subtype,"width":panel.frame.width,"height":panel.frame.height,"rowHeights":rows.map { $0.frame.height }])
            try capture(root,name+"-combo")
            native.performClick(nil)
            tracker.record(classification,in:window)
            let menu=FluentMenuFlyout(items:[FluentMenuItem("中文") {},FluentMenuItem("英文") {}],theme:theme,reduceMotion:true)
            menu.present(relativeTo:combo)
            let menuPanel=window.childWindows!.first!
            let menuRoot=menuPanel.contentView!
            let menuRows=all(menuRoot).filter { $0.accessibilityRole() == .menuItem }
            records.append(["variant":name,"kind":"menu","device":String(describing:classification),"subtype":subtype,"width":menuPanel.frame.width,"height":menuPanel.frame.height,"rowHeights":menuRows.map { $0.frame.height }])
            try capture(menuRoot,name+"-menu")
            menu.dismiss(animated:false);window.close()
        }}}
        print(String(decoding:try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
