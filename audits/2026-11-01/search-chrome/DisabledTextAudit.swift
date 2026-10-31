import AppKit
import FluentKit
@main struct DisabledTextAudit {
 @MainActor static func main() throws {
  _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
  var rows: [[String:Any]] = []
  for dark in [false,true] {
   let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
   let search = FluentSearchTextField(placeholder:"查找设置"); search.theme = theme
   let text = FluentTextField(placeholder:"查找设置"); text.theme = theme
   let secure = FluentSecureTextField(placeholder:"查找设置"); secure.theme = theme
   for field: NSTextField in [search,text,secure] {
    field.frame = NSRect(x:0,y:0,width:220,height:32)
    for enabled in [true,false,true] {
     field.isEnabled = enabled
     let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:440,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
     let cg = NSGraphicsContext(bitmapImageRep:bitmap)!.cgContext
     NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:cg,flipped:true)
     cg.scaleBy(x:2,y:2); cg.translateBy(x:0,y:32); cg.scaleBy(x:1,y:-1)
     field.cell!.draw(withFrame:field.bounds,in:field)
     NSGraphicsContext.restoreGraphicsState()
     var alpha: CGFloat = 0
     for y in 10..<52 { for x in 64..<145 { alpha = max(alpha,bitmap.colorAt(x:x,y:y)!.alphaComponent) } }
     rows.append(["type":String(describing:type(of:field)),"dark":dark,"enabled":enabled,"inkAlpha":alpha])
    }
   }
  }
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]))
 }
}
