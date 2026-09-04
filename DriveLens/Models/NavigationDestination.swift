import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case timeline
    case places
    case folders
    case search
    case videos
    case recentlyAdded
    case smartAlbums
    case duplicates
    case appInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .places: "Places"
        case .folders: "Folders"
        case .search: "Search"
        case .videos: "Videos"
        case .recentlyAdded: "Recently Added"
        case .smartAlbums: "Smart Albums"
        case .duplicates: "Duplicates"
        case .appInfo: "Storage & Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: "calendar"
        case .places: "map"
        case .folders: "folder"
        case .search: "magnifyingglass"
        case .videos: "film"
        case .recentlyAdded: "clock"
        case .smartAlbums: "sparkles.rectangle.stack"
        case .duplicates: "rectangle.on.rectangle"
        case .appInfo: "info.circle"
        }
    }
}
