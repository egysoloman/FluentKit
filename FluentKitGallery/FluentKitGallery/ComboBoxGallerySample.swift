import AppKit
import FluentKit

struct ComboBoxGallerySample: FluentView {
    @FluentState private var options = Array(0..<8)
    @FluentState private var selection: Int? = 2
    @FluentState private var editableSelection: Int? = 2
    @FluentState private var text = "Option 2"
    @FluentState private var request = 0
    @FluentState private var immediateSelection = false
    @FluentState private var status = "Queue a change, then open either list before the two-second delay ends."

    var body: some FluentView {
        FluentVStack(spacing: 12, alignment: .leading) {
            FluentText("Live options", style: .bodyStrong)
            FluentText("Tab to a field. Use F4 or Option+Up/Down to open or close; Escape restores the opening value.",
                       style: .caption)
            FluentText("In the first field, type Option 5 to search. Spaces extend the query; matching selects immediately.",
                       style: .caption)
            FluentButtonView(immediateSelection ? "Selection: while browsing" : "Selection: when confirmed") {
                immediateSelection.toggle()
            }
            FluentComboBox(options: options, selection: $selection,
                title: { "Option \($0)" })
                .selectionChangedTrigger(immediateSelection ? .always : .committed).frame(width: 280)
            FluentText("Editable value", style: .caption)
            FluentText("Type Opt to complete an option. Delete the selected suffix to keep a custom prefix.", style: .caption)
            FluentComboBox(options: options, selection: $editableSelection, mode: .editable,
                text: $text.textInput(.init(commitPolicy: .committedText)),
                title: { "Option \($0)" })
                .selectionChangedTrigger(immediateSelection ? .always : .committed).frame(width: 280)
            FluentHStack {
                FluentButtonView("Append in 2 seconds") { schedule(.append) }
                FluentButtonView("Reverse in 2 seconds") { schedule(.reverse) }
            }
            FluentHStack {
                FluentButtonView("Remove selections in 2 seconds") { schedule(.removeSelections) }
                FluentButtonView("Reset text in 2 seconds") { schedule(.resetText) }
            }
            FluentHStack {
                FluentButtonView("Reset") {
                    request += 1
                    options = Array(0..<8)
                    selection = 2
                    editableSelection = 2
                    text = "Option 2"
                    status = "Reset. Queue a change and open either list."
                }
            }
            FluentText("Selected: \(selection.map(String.init) ?? "none") · Editable: \(editableSelection.map(String.init) ?? "none")",
                       style: .caption)
            FluentText(status, style: .caption)
        }
    }

    private enum Change { case append, reverse, removeSelections, resetText }

    private func schedule(_ change: Change) {
        request += 1
        let current = request
        status = change == .resetText
            ? "Edit the text now. An external reset will arrive in two seconds; composition finishes first."
            : "Open either list now. Its options will update in two seconds."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard request == current else { return }
            switch change {
            case .append: options.append((options.max() ?? -1) + 1)
            case .reverse: options.reverse()
            case .removeSelections:
                let removed = Set([selection, editableSelection].compactMap { $0 })
                options.removeAll { removed.contains($0) }
            case .resetText:
                text = options.first.map { "Option \($0)" } ?? "Reset value"
                status = "Text reset sent. A pending composition keeps its native editor until it finishes."
                return
            }
            status = "Updated: \(options.count) options. Nonempty lists stay open; editable text is preserved."
        }
    }
}
