import Foundation

/// A stable-identity snapshot shared by Fluent collection controls.
///
/// Snapshots own ordering only; row or cell content remains in the collection view that consumes
/// them. Section and item identifiers must be unique, which keeps selection, moves, accessibility,
/// and native view reuse deterministic.
public struct FluentCollectionSnapshot<SectionID: Hashable, ItemID: Hashable>: Equatable {
    private var sections: [SectionID] = []
    private var itemsBySection: [SectionID: [ItemID]] = [:]

    public init() {}

    public init(section: SectionID, items: [ItemID]) {
        appendSections([section])
        appendItems(items, toSection: section)
    }

    public var sectionIdentifiers: [SectionID] { sections }
    public var itemIdentifiers: [ItemID] { sections.flatMap { itemsBySection[$0] ?? [] } }
    public var numberOfSections: Int { sections.count }
    public var numberOfItems: Int { itemIdentifiers.count }

    public func itemIdentifiers(inSection section: SectionID) -> [ItemID] {
        itemsBySection[section] ?? []
    }

    public func indexOfSection(_ section: SectionID) -> Int? { sections.firstIndex(of: section) }

    public func indexOfItem(_ item: ItemID) -> Int? { itemIdentifiers.firstIndex(of: item) }

    public func sectionIdentifier(containing item: ItemID) -> SectionID? {
        sections.first { itemsBySection[$0]?.contains(item) == true }
    }

    public mutating func appendSections(_ identifiers: [SectionID]) {
        insertSections(identifiers, at: sections.count)
    }

    public mutating func insertSections(_ identifiers: [SectionID], before section: SectionID) {
        guard let index = sections.firstIndex(of: section) else {
            preconditionFailure("Cannot insert before an unknown Fluent collection section")
        }
        insertSections(identifiers, at: index)
    }

    public mutating func insertSections(_ identifiers: [SectionID], after section: SectionID) {
        guard let index = sections.firstIndex(of: section) else {
            preconditionFailure("Cannot insert after an unknown Fluent collection section")
        }
        insertSections(identifiers, at: index + 1)
    }

    public mutating func deleteSections(_ identifiers: [SectionID]) {
        let requested = Set(identifiers)
        sections.removeAll { requested.contains($0) }
        identifiers.forEach { itemsBySection.removeValue(forKey: $0) }
    }

    public mutating func moveSection(_ section: SectionID, before destination: SectionID) {
        moveSection(section, relativeTo: destination, offset: 0)
    }

    public mutating func moveSection(_ section: SectionID, after destination: SectionID) {
        moveSection(section, relativeTo: destination, offset: 1)
    }

    public mutating func appendItems(_ identifiers: [ItemID], toSection section: SectionID? = nil) {
        guard let destination = section ?? sections.last else {
            preconditionFailure("A Fluent collection snapshot needs a section before appending items")
        }
        guard itemsBySection[destination] != nil else {
            preconditionFailure("Cannot append items to an unknown Fluent collection section")
        }
        validateNewItems(identifiers)
        itemsBySection[destination, default: []].append(contentsOf: identifiers)
    }

    public mutating func insertItems(_ identifiers: [ItemID], before item: ItemID) {
        insertItems(identifiers, relativeTo: item, offset: 0)
    }

    public mutating func insertItems(_ identifiers: [ItemID], after item: ItemID) {
        insertItems(identifiers, relativeTo: item, offset: 1)
    }

    public mutating func deleteItems(_ identifiers: [ItemID]) {
        let requested = Set(identifiers)
        for section in sections {
            itemsBySection[section]?.removeAll { requested.contains($0) }
        }
    }

    public mutating func moveItem(_ item: ItemID, before destination: ItemID) {
        moveItem(item, relativeTo: destination, offset: 0)
    }

    public mutating func moveItem(_ item: ItemID, after destination: ItemID) {
        moveItem(item, relativeTo: destination, offset: 1)
    }

    /// Returns the native Swift difference for section ordering, including inferred moves.
    public func sectionDifference(
        from previous: FluentCollectionSnapshot
    ) -> CollectionDifference<SectionID> {
        sections.difference(from: previous.sections).inferringMoves()
    }

    /// Returns the native Swift difference for one section, including inferred moves.
    public func itemDifference(
        from previous: FluentCollectionSnapshot,
        inSection section: SectionID
    ) -> CollectionDifference<ItemID> {
        itemIdentifiers(inSection: section)
            .difference(from: previous.itemIdentifiers(inSection: section))
            .inferringMoves()
    }

    private mutating func insertSections(_ identifiers: [SectionID], at index: Int) {
        precondition(index >= 0 && index <= sections.count, "Invalid Fluent collection section index")
        precondition(Set(identifiers).count == identifiers.count, "Fluent collection section IDs must be unique")
        precondition(Set(identifiers).isDisjoint(with: sections), "Fluent collection section IDs must be unique")
        sections.insert(contentsOf: identifiers, at: index)
        identifiers.forEach { itemsBySection[$0] = [] }
    }

    private mutating func moveSection(_ section: SectionID, relativeTo destination: SectionID, offset: Int) {
        guard section != destination,
              let sourceIndex = sections.firstIndex(of: section),
              let originalDestination = sections.firstIndex(of: destination) else { return }
        sections.remove(at: sourceIndex)
        let adjustedDestination = originalDestination - (sourceIndex < originalDestination ? 1 : 0)
        sections.insert(section, at: adjustedDestination + offset)
    }

    private mutating func insertItems(_ identifiers: [ItemID], relativeTo item: ItemID, offset: Int) {
        guard let section = sectionIdentifier(containing: item),
              let index = itemsBySection[section]?.firstIndex(of: item) else {
            preconditionFailure("Cannot insert relative to an unknown Fluent collection item")
        }
        validateNewItems(identifiers)
        itemsBySection[section]?.insert(contentsOf: identifiers, at: index + offset)
    }

    private mutating func moveItem(_ item: ItemID, relativeTo destination: ItemID, offset: Int) {
        guard item != destination,
              let sourceSection = sectionIdentifier(containing: item),
              let destinationSection = sectionIdentifier(containing: destination),
              let sourceIndex = itemsBySection[sourceSection]?.firstIndex(of: item),
              let originalDestination = itemsBySection[destinationSection]?.firstIndex(of: destination) else { return }
        itemsBySection[sourceSection]?.remove(at: sourceIndex)
        let adjustedDestination = sourceSection == destinationSection && sourceIndex < originalDestination
            ? originalDestination - 1
            : originalDestination
        itemsBySection[destinationSection]?.insert(item, at: adjustedDestination + offset)
    }

    private func validateNewItems(_ identifiers: [ItemID]) {
        precondition(Set(identifiers).count == identifiers.count, "Fluent collection item IDs must be unique")
        precondition(Set(identifiers).isDisjoint(with: itemIdentifiers), "Fluent collection item IDs must be unique")
    }
}
