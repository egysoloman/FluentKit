import AppKit
import FluentKit
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
