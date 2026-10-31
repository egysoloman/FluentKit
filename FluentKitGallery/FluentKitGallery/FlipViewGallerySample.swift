import AppKit
import FluentKit

struct FlipViewGallerySample: FluentView {
    let theme: FluentTheme
    @FluentState private var pages = Array(0..<1000)
    @FluentState private var selection = 0
    @FluentState private var vertical = false
    @FluentState private var status = ""

    var body: some FluentView {
        FluentVStack(spacing: 12, alignment: .leading) {
            FluentText(pages.isEmpty ? "No pages" : "Page \(selection + 1) of \(pages.count)", style: .caption)
            FluentFlipView(pages, id: \.self, selection: $selection, orientation: vertical ? .vertical : .horizontal) { id in
                FluentVStack(spacing: 16) {
                    FluentText("Item \(id)", style: .title)
                    FluentText("Swipe along the page direction to move between items.", style: .body)
                    FluentButtonView("Use this item") { status = "Activated item \(id)" }
                }
                .padding(24)
                .background(theme.cardFill, cornerRadius: 8)
            }.frame(width: 420, height: 240)
            FluentToggleView("Vertical pages", isOn: $vertical)
            FluentHStack(spacing: 8) {
                FluentButtonView("Last") { selection = pages.count - 1 }.disabled(pages.isEmpty)
                FluentButtonView("Insert before") { pages.insert((pages.min() ?? 0) - 1, at: 0) }
                FluentButtonView("Remove current") { if pages.indices.contains(selection) { pages.remove(at: selection) } }.disabled(pages.isEmpty)
                FluentButtonView("Reset") { pages = Array(0..<1000); selection = 0 }
            }
            FluentText(status, style: .caption)
            FluentText("Trackpad gestures follow your motion. Mouse wheel and arrow keys also change pages; Home/End jumps to an edge.", style: .caption)
        }
    }
}
