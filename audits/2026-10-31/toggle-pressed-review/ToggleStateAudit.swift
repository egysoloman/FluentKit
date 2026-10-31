import AppKit
import FluentKit

// Exact application override read from Fluent IME/SettingsWindow.swift (2026-10-31).
private struct SettingsToggleStyle: FluentToggleStyle {
    func appearance(for configuration: FluentToggleStyleConfiguration) -> FluentToggleAppearance {
        let theme = configuration.theme
        return FluentToggleAppearance(trackColor: configuration.isOn ? theme.accent : .clear,
            trackBorderColor: configuration.isOn ? .clear : theme.textSecondary.withAlphaComponent(0.55),
            trackBorderWidth: configuration.isOn ? 0 : 1,
            knobColor: configuration.isOn ? .white : theme.textSecondary,
            labelColor: theme.textPrimary, knobShadowColor: .clear, knobDiameter: 12)
    }
}
private final class Stage: NSView { override var isFlipped: Bool { true } }
@main struct ToggleStateAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared;NSApp.setActivationPolicy(.accessory);NSApp.finishLaunching()
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func layer(_ name:String,_ root:CALayer)->CALayer? {
            if root.name==name { return root };return root.sublayers?.compactMap { layer(name,$0) }.first
        }
        var records:[[String:Any]]=[]
        for dark in [false,true] {
            let stage=Stage(frame:NSRect(x:0,y:0,width:640,height:230));stage.wantsLayer=true
            stage.layer?.backgroundColor=(dark ? NSColor(white:0.13,alpha:1):.white).cgColor
            let window=NSWindow(contentRect:stage.bounds,styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=stage;window.orderFront(nil)
            func label(_ title:String,_ x:CGFloat,_ y:CGFloat) {
                let view=NSTextField(labelWithString:title);view.font = .systemFont(ofSize:12)
                view.textColor=dark ? .white:.black;view.frame=NSRect(x:x,y:y,width:200,height:22);stage.addSubview(view)
            }
            label("WinUI / FluentKit default",10,8);label("IME fixed-size override",330,8)
            for (stateIndex,state) in ["normal","hover","pressed"].enumerated() {
                for custom in [false,true] { for on in [false,true] {
                    let x=CGFloat(custom ? 330:10)+CGFloat(stateIndex)*100
                    let y:CGFloat=on ? 135:47
                    let toggle=FluentToggle(title:"",isOn:on);toggle.theme = .custom(colorScheme:dark ? .dark:.light,materialEffectsEnabled:false)
                    toggle.reduceMotion=true
                    if custom { toggle.fluentStyle=SettingsToggleStyle() }
                    stage.addSubview(toggle);toggle.frame=NSRect(x:x,y:y,width:40,height:26);toggle.layoutSubtreeIfNeeded()
                    let point=toggle.convert(NSPoint(x:20,y:13),to:nil)
                    func event(_ type:NSEvent.EventType)->NSEvent {
                        NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                    }
                    if state != "normal" { toggle.mouseEntered(with:event(.mouseMoved)) }
                    if state == "pressed" { toggle.mouseDown(with:event(.leftMouseDown)) }
                    let knob=layer("FluentKit.Toggle.Knob",toggle.layer!)!
                    let track=layer("FluentKit.Toggle.Track",toggle.layer!)!
                    let expected:CGSize=custom || state=="normal" ? CGSize(width:12,height:12):state=="hover" ? CGSize(width:14,height:14):CGSize(width:17,height:14)
                    precondition(knob.bounds.size == expected && track.bounds.size == CGSize(width:40,height:20))
                    precondition(toggle.isOn == on)
                    label("\(state) \(on ? "On":"Off")",x,y+29)
                    label("\(Int(knob.bounds.width))×\(Int(knob.bounds.height))",x,y+47)
                    records.append(["dark":dark,"override":custom,"on":on,"state":state,"knobWidth":knob.bounds.width,"knobHeight":knob.bounds.height])
                }}
            }
            stage.layoutSubtreeIfNeeded();stage.displayIfNeeded();CATransaction.flush()
            let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1280,pixelsHigh:460,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let cg=NSGraphicsContext(bitmapImageRep:image)!.cgContext;cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:230);cg.scaleBy(x:1,y:-1)
            stage.layer!.render(in:cg)
            try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(dark ? "dark.png":"light.png"))
            window.close()
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
