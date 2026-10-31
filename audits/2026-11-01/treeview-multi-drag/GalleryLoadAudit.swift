import Foundation

@main struct GalleryLoadAudit {
    static func main() throws {
        typealias Entry = TreeViewGallerySample.Entry
        var entries = Entry.examples
        for id in ["plan", "notes"] {
            let entry = Entry.remove(id, from: &entries)!
            precondition(Entry.insert(entry, parentID: "remote", index: 99, into: &entries))
        }
        let before = entries.first { $0.id == "remote" }!.children.map(\.id)
        Entry.load("remote", in: &entries)
        let after = entries.first { $0.id == "remote" }!.children.map(\.id)
        let result: [String: Any] = ["beforeLoad": before, "afterLoad": after,
            "movedEntriesPreserved": Set(before).isSubset(of: Set(after))]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
