import Foundation

enum GalleryCoverage: String, CaseIterable, Hashable {
    case implemented
    case partial
    case platformAlternative
    case missing
    case notApplicable

    var title: String {
        switch self {
        case .implemented: return "Implemented"
        case .partial: return "Partial"
        case .platformAlternative: return "macOS alternative"
        case .missing: return "Missing"
        case .notApplicable: return "Not applicable"
        }
    }
}

struct GalleryItem: Hashable, Identifiable {
    let id: String
    let title: String
    let categoryID: String
    let coverage: GalleryCoverage
    let isNew: Bool
    let isUpdated: Bool
}

struct GalleryCategory: Hashable, Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let isSpecial: Bool
    let items: [GalleryItem]
}

enum GalleryDestination: nonisolated Hashable, Sendable {
    case home
    case all
    case category(String)
    case settings
}

struct GalleryRoute: nonisolated Hashable, Sendable {
    let destination: GalleryDestination?
    let selectedItemID: String?
    let searchText: String

    init(destination: GalleryDestination?, selectedItemID: String? = nil, searchText: String = "") {
        self.destination = destination
        self.selectedItemID = selectedItemID
        self.searchText = searchText
    }
}
