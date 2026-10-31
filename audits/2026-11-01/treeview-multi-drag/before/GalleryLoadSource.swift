// Audit-only visibility change: private Entry becomes internal; implementation unchanged.
import AppKit
import FluentKit

struct TreeViewGallerySample: FluentView {
    struct Entry {
        let id: String
        let title: String
        var children: [Entry] = []
        var isUnrealized = false
        static var examples: [Entry] {
            [Entry(id: "work", title: "Work", children: [
                Entry(id: "plan", title: "Plan"),
                Entry(id: "specs", title: "Specs", children: [Entry(id: "spec-a", title: "Spec A")])
            ]), Entry(id: "remote", title: "Remote", isUnrealized: true), Entry(id: "notes", title: "Notes")]
        }
        static func remove(_ id: String, from entries: inout [Entry]) -> Entry? {
            if let index = entries.firstIndex(where: { $0.id == id }) { return entries.remove(at: index) }
            for index in entries.indices {
                if let result = remove(id, from: &entries[index].children) { return result }
            }
            return nil
        }
        static func insert(_ entry: Entry, parentID: String?, index: Int, into entries: inout [Entry]) -> Bool {
            guard let parentID else { entries.insert(entry, at: min(max(0, index), entries.count)); return true }
            for offset in entries.indices {
                if entries[offset].id == parentID {
                    entries[offset].children.insert(entry, at: min(max(0, index), entries[offset].children.count))
                    return true
                }
                if insert(entry, parentID: parentID, index: index, into: &entries[offset].children) { return true }
            }
            return false
        }
        static func load(_ id: String, in entries: inout [Entry]) {
            for index in entries.indices {
                if entries[index].id == id, entries[index].isUnrealized {
                    entries[index].children = [Entry(id: "remote-a", title: "Shared document"), Entry(id: "remote-b", title: "Reference")]
                    entries[index].isUnrealized = false
                    return
                }
                load(id, in: &entries[index].children)
            }
        }
    }
    @FluentState private var entries = Entry.examples
    @FluentState private var multiple = true
    @FluentState private var checked: Set<String> = ["plan"]
    @FluentState private var selected: String? = "plan"
    @FluentState private var expanded: Set<String> = ["work"]
    @FluentState private var status = "Open Remote to load its children."

    private func nodes(_ entries: [Entry]) -> [FluentTreeViewNode<String>] {
        entries.map { entry in
            FluentTreeViewNode(id: entry.id, children: nodes(entry.children), hasUnrealizedChildren: entry.isUnrealized) {
                FluentText(entry.title)
            }
        }
    }
    var body: some FluentView {
        FluentVStack(spacing: 12) {
            FluentToggleView("Multiple selection", isOn: $multiple)
            FluentTreeView(nodes: nodes(entries), selection: multiple ? .multiple($checked) : .single($selected))
                .expandedIDs($expanded)
                .onExpanding { id in
                    var next = entries
                    Entry.load(id, in: &next)
                    entries = next
                    status = "Expanded \(id)"
                }
                .onCollapsed { status = "Collapsed \($0)" }
                .onItemInvoked { status = "Invoked \($0)" }
                .onMove { move in
                    var next = entries
                    if let entry = Entry.remove(move.id, from: &next),
                       Entry.insert(entry, parentID: move.parentID, index: move.index, into: &next) {
                        entries = next
                        status = "Moved \(entry.title)"
                    }
                }
                .frame(width: 440, height: 280)
            FluentHStack(spacing: 12) {
                FluentButtonView("Collapse all") { expanded = [] }
                FluentButtonView("Reset tree") {
                    entries = Entry.examples
                    checked = ["plan"]
                    selected = "plan"
                    expanded = ["work"]
                    status = "Open Remote to load its children."
                }
            }
            FluentText(multiple ? "Checked: \(checked.count)" : "Selected: \(selected ?? "none")")
            FluentText(status, style: .caption)
            FluentText("Drag one item to move it. Use arrow keys to browse and Space to toggle a check box.", style: .caption)
        }
    }
}
