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

    /// Return the UTF-16 end of the matching prefix in the displayed title. Folding may
    /// change length, so native suffix selection must end on an actual grapheme boundary.
    static func completionPrefixEnd(in title: String, for query: String) -> Int? {
        completionPrefixEnd(in: title, foldedQuery: fold(query))
    }

    static func completion<Option>(in options: [Option], title: (Option) -> String,
                                   for query: String) -> (option: Option, prefixEnd: Int)? {
        let needle = fold(query)
        guard !needle.isEmpty else { return nil }
        for option in options {
            if let end = completionPrefixEnd(in: title(option), foldedQuery: needle) { return (option, end) }
        }
        return nil
    }

    private static func completionPrefixEnd(in title: String, foldedQuery needle: String) -> Int? {
        guard !needle.isEmpty else { return nil }
        let trimmed = String(title.drop(while: { $0 == " " }))
        guard fold(trimmed).hasPrefix(needle) else { return nil }
        let leading = title.utf16.count - trimmed.utf16.count
        var prefix = ""
        for character in trimmed {
            prefix.append(character)
            if fold(prefix).hasPrefix(needle) { return leading + prefix.utf16.count }
        }
        return nil
    }

    static func equalsIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive, locale: .current) == .orderedSame
    }

    private static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        // Latin, already-katakana and other scripts need no transliterator. Avoid its setup
        // and per-string work on every option in a large search, retaining the kana path.
        guard folded.unicodeScalars.contains(where: { (0x3040...0x309F).contains($0.value) }) else { return folded }
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
