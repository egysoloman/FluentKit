import Foundation

/// The noneditable ComboBox's character search is independent of arrow-key previews.
/// Match WinUI's one-second prefix lifetime and circular search order using native Unicode
/// folding on macOS, without treating an unmatched extension as a new single-character query.
struct FluentComboBoxTextSearch {
    private var prefix = ""
    private var lastInputTime: TimeInterval?

    func isSearching(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let lastInputTime else { return false }
        return !prefix.isEmpty && time >= lastInputTime && time - lastInputTime <= 1
    }

    mutating func reset() { prefix = ""; lastInputTime = nil }

    mutating func append(_ characters: String, titles: [String], selectedIndex: Int?,
                         at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int? {
        let startsNewSearch = !isSearching(at: time)
        if startsNewSearch { prefix = "" }
        lastInputTime = time
        // Bound retained input without splitting a surrogate pair or grapheme cluster.
        for character in characters {
            guard prefix.utf16.count + String(character).utf16.count <= 256 else { break }
            prefix.append(character)
        }
        guard !prefix.isEmpty, !titles.isEmpty else { return nil }
        let current = selectedIndex.flatMap { titles.indices.contains($0) ? $0 : nil }
        let start = startsNewSearch ? ((current ?? -1) + 1) % titles.count : current ?? 0
        let query = Self.fold(prefix)
        for offset in titles.indices {
            let index = (start + offset) % titles.count
            let title = String(titles[index].drop(while: { $0 == " " }))
            if Self.fold(title).hasPrefix(query) { return index }
        }
        return nil
    }

    private static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
