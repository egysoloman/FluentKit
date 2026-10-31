import AppKit
import FluentKit

struct AutoSuggestBoxGallerySample: FluentView {
    @FluentState private var text = ""
    @FluentState private var revision = 0
    @FluentState private var updateText = true
    @FluentState private var status = "Type a to show a scrollable list. Use Up/Down, Escape or Return."
    @FluentState private var change = "Waiting for input"

    var body: some FluentView {
        let names = ["Apple", "Apricot", "Avocado", "Banana", "Blackberry", "Cantaloupe", "Date",
            "Dragon fruit", "Grape", "Guava", "Mango", "Nectarine", "Orange", "Papaya", "Peach", "Pear"]
        let ordered = revision.isMultiple(of: 2) ? names : names.reversed()
        let version = revision
        return FluentVStack(spacing: 12, alignment: .leading) {
            FluentText("Suggestions stay attached to the field and scroll to the keyboard selection.", style: .caption)
            FluentAutoSuggestBox(
                $text.textInput(.init(commitPolicy: .committedText)),
                placeholder: "Search fruit", header: "Fruit", querySystemImageName: "magnifyingglass",
                suggestions: { query in
                    guard !query.isEmpty else { return [] }
                    return ordered.filter { $0.localizedCaseInsensitiveContains(query) }.map {
                        FluentAutoSuggestBoxSuggestion(id: $0, title: $0, subtitle: "Revision \(version)", systemImageName: "leaf")
                    }
                },
                updateTextOnSelect: updateText, maxSuggestionListHeight: 164,
                onTextChangedEvent: { change = "\($0.reason): \($0.text)" },
                onSuggestionChosen: { status = "Preview: \($0.title)" },
                onSubmit: { query, suggestion in status = "Submitted: \(query) · \(suggestion?.title ?? "raw query")" }
            ).frame(width: 360)
            FluentToggleView("Update text while navigating suggestions", isOn: $updateText)
            FluentHStack {
                FluentButtonView("Refresh in 2 seconds") {
                    status = "Return to the field and select a suggestion before the refresh."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { revision += 1 }
                }
                FluentButtonView("Reset text") { text = "" }
            }
            FluentText(change, style: .caption)
            FluentText(status, style: .caption)
        }
    }
}
