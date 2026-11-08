import AppKit
import FluentKit

// Compile as a normal client, without @testable: new lifecycle overrides must preserve
// the extension points that AppBarButton previously inherited from AppKit.
private final class AppBarLifecycleOverrideCheck: FluentAppBarButton {
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event) }
    override func cancelOperation(_ sender: Any?) { super.cancelOperation(sender) }
    override func viewDidHide() { super.viewDidHide() }
    override func viewWillMove(toSuperview newSuperview: NSView?) { super.viewWillMove(toSuperview: newSuperview) }
    override func viewWillMove(toWindow newWindow: NSWindow?) { super.viewWillMove(toWindow: newWindow) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow() }
}

@main struct AppearanceAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let typography = FluentTypography()
        var materials: [String:String] = [:]
        for (name,material) in [("mica",FluentMaterial.mica),("acrylic",FluentMaterial.acrylic),("liquidGlass",FluentMaterial.liquidGlass)] {
            let view = FluentMaterialView(material:material)
            view.fluentTheme = .custom(colorScheme:.light)
            materials[name] = view.resolvedBackend.rawValue
        }
        var fonts: [String:Any] = [:]
        for (name,style) in [("largeTitle",FluentTextStyle.largeTitle),("title",.title),("title2",.title2),("headline",.headline),("body",.body),("caption",.caption)] {
            let font=typography.font(for:style)
            fonts[name] = ["name":font.fontName,"size":font.pointSize]
        }
        let output:[String:Any] = ["nativeGlassAvailable":FluentMaterialView.isNativeGlassAvailable,"materials":materials,"fonts":fonts,"os":ProcessInfo.processInfo.operatingSystemVersionString]
        let data=try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    }
}
