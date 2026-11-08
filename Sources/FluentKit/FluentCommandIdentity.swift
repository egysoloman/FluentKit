import Foundation

/// Shared identity semantics for native bars and detached command flyouts. Explicit IDs can
/// move between groups; omitted IDs follow the documented group/position fallback. Duplicate
/// IDs remain deterministic without trapping, but callers should use unique IDs for reordering.
enum FluentCommandBarItemIdentity: Hashable {
    case explicit(AnyHashable, occurrence: Int)
    case position(primary: Bool, index: Int)

    static func resolve(
        primary: [FluentCommandBarItem], secondary: [FluentCommandBarItem]
    ) -> (primary: [Self], secondary: [Self]) {
        var occurrences: [AnyHashable: Int] = [:]
        func identities(_ items: [FluentCommandBarItem], isPrimary: Bool) -> [Self] {
            items.enumerated().map { index, item in
                guard let id = item.id else { return .position(primary: isPrimary, index: index) }
                let occurrence = occurrences[id, default: 0]
                occurrences[id] = occurrence + 1
                return .explicit(id, occurrence: occurrence)
            }
        }
        return (identities(primary, isPrimary: true), identities(secondary, isPrimary: false))
    }
}
