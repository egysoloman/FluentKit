import AppKit
import FluentKit
@main struct WorkspaceNotificationAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let view = FluentMaterialView(material: .nativeAcrylic)
        view.fluentTheme = .custom(colorScheme: .dark)
        let expected = view.material
        view.material = .menu
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let result: [String: Any] = ["expectedMaterial": expected.rawValue, "actualMaterial": view.material.rawValue, "refreshed": view.material == expected]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
    }
}
