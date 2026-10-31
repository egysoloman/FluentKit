import AppKit
import FluentKit

struct SplitButtonGallerySample: FluentView {
    let toggle: Bool
    @FluentState private var checked = false
    @FluentState private var enabled = true
    @FluentState private var revision = 0
    @FluentState private var status = "The main region performs an action; the arrow opens a separate menu."

    var body: some FluentView {
        let version = revision
        return FluentVStack(spacing: 12, alignment: .leading) {
            FluentText("Use Space or Return for the main action; Option+Down or F4 opens the menu.", style: .caption)
            FluentHStack {
                if toggle {
                    FluentToggleSplitButtonView("Favorite", isChecked: $checked, action: {
                        status = "Favorite is now \(checked ? "on" : "off")"
                    }) { menu(version) }.disabled(!enabled)
                } else {
                    FluentSplitButtonView("Save", action: { status = "Saved with revision \(version)" }) {
                        menu(version)
                    }.disabled(!enabled)
                }
            }
            FluentToggleView("Enabled", isOn: $enabled)
            if toggle { FluentToggleView("Favorite (shared state)", isOn: $checked) }
            FluentButtonView("Refresh menu in 2 seconds") {
                status = "Open the menu before the refresh to see its items update."
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { revision += 1 }
            }
            FluentText(status, style: .caption)
        }
    }

    private func menu(_ version: Int) -> [FluentMenuItem] {
        [FluentMenuItem(id: "copy", "Save a copy · revision \(version)") { status = "Copy saved with revision \(version)" },
         .submenu(id: "export", "Export") {
            FluentMenuItem(id: "pdf", "PDF") { status = "PDF exported with revision \(version)" }
            FluentMenuItem(id: "image", "Image") { status = "Image exported with revision \(version)" }
         }]
    }
}
