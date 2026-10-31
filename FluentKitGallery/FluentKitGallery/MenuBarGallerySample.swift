import AppKit
import FluentKit

struct MenuBarGallerySample: FluentView {
    @FluentState private var revision = 0
    @FluentState private var exportEnabled = true
    @FluentState private var status = "Choose a command, or schedule a refresh and open File › Export."

    private var menus: [FluentMenuBarItem] {
        let file = FluentMenuBarItem(id: "file", "File", accessKey: "F", items: [
            FluentMenuItem(id: "new", "New document", systemImageName: "doc", keyEquivalent: "n") { status = "New document" },
            .separator(id: "file-separator"),
            .submenu(id: "export", "Export", systemImageName: "square.and.arrow.up", isEnabled: exportEnabled) {
                FluentMenuItem(id: "png", "PNG · revision \(revision)", state: revision.isMultiple(of: 2) ? .off : .on) {
                    status = "Export PNG from revision \(revision)"
                }
                FluentMenuItem(id: "svg", "SVG", keyEquivalent: "e") { status = "Export SVG from revision \(revision)" }
                if revision > 0 {
                    FluentMenuItem(id: "pdf", "PDF", systemImageName: "doc.richtext") { status = "Export PDF" }
                }
            }
        ])
        let view = FluentMenuBarItem(id: "view", "View", accessKey: "V", items: [
            FluentMenuItem("Zoom in", keyEquivalent: "+") { status = "Zoom in" },
            FluentMenuItem("Zoom out", keyEquivalent: "-") { status = "Zoom out" }
        ])
        let help = FluentMenuBarItem(id: "help", "Help", accessKey: "H", items: [
            FluentMenuItem("About this sample") { status = "Option + F, V or H opens a menu. Arrow keys navigate menus and submenus." }
        ])
        return revision.isMultiple(of: 2) ? [file, view, help] : [view, file, help]
    }

    var body: some FluentView {
        FluentVStack(spacing: 12) {
            FluentMenuBarView(items: menus).frame(width: 480, height: 40)
            FluentToggleView("Enable export", isOn: $exportEnabled)
            FluentButtonView("Refresh in 2 seconds") {
                status = "Open File › Export now. The update also changes the menu order."
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    revision += 1
                    status = "Updated to revision \(revision). Open menus stay in place relative to their items."
                }
            }
            FluentText(status, style: .caption)
        }
    }
}
