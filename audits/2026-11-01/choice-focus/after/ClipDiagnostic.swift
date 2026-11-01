import AppKit
import FluentKit
@main struct ClipDiagnostic {
    @MainActor static func main() {
        _ = NSApplication.shared
        let c = FluentCheckBox()
        func log(_ phase: String) { print(phase, "view:", c.clipsToBounds, "layer:", c.layer!.masksToBounds) }
        log("init")
        c.clipsToBounds = false; log("view false")
        c.frame = NSRect(x: 0, y: 0, width: 180, height: 32); c.layoutSubtreeIfNeeded(); log("layout")
        c.layer!.masksToBounds = false; log("layer false")
        c.theme = .custom(colorScheme: .dark); log("theme")
        c.layer!.masksToBounds = false
        c.layer!.cornerRadius = 8; log("changed corner radius")
        c.layer!.backgroundColor = NSColor.white.cgColor; log("changed background")
    }
}
