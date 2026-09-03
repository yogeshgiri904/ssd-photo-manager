import CoreLocation
import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: Int64
    var relativePath: String
    var folderPath: String
    var filename: String
    var kind: MediaKind
    var livePhotoGroupID: String?
    var captureDate: Date
    var captureDateLocalText: String
    var dateSource: DateSource
    var width: Int?
    var height: Int?
    var orientation: Int?
    var duration: TimeInterval?
    var fileSize: Int64
    var modifiedAt: Date
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var caption: String?
    var keywords: [String]
    var latitude: Double?
    var longitude: Double?
    var city: String?
    var state: String?
    var country: String?
    var locationSource: LocationSource
    var thumbnailPath: String?
    var videoThumbnailPath: String?
    var isMissing: Bool
    var isFavorite: Bool
    var addedAt: Date
    var updatedAt: Date

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isVideoLike: Bool {
        kind == .video || kind == .livePhoto
    }

    var placeText: String {
        [city, state, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var cameraText: String {
        [cameraMake, cameraModel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var yearMonthText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MMMM"
        return formatter.string(from: captureDate)
    }
}

enum MediaKind: String, CaseIterable, Hashable {
    case photo
    case video
    case livePhoto

    var label: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .livePhoto: "Photo"
        }
    }
}

enum DateSource: String, Hashable {
    case exifDateTimeOriginal
    case exifCreateDate
    case quickTimeCreationDate
    case mediaCreationDate
    case filename
    case filesystemModified
    case unknown

    var label: String {
        switch self {
        case .exifDateTimeOriginal: "EXIF DateTimeOriginal"
        case .exifCreateDate: "EXIF CreateDate"
        case .quickTimeCreationDate: "QuickTime creation date"
        case .mediaCreationDate: "Media creation date"
        case .filename: "Filename"
        case .filesystemModified: "File modification date"
        case .unknown: "Unknown"
        }
    }
}

enum LocationSource: String, Hashable {
    case exifGPS
    case quickTime
    case xmpGPS
    case manual
    case none

    var label: String {
        switch self {
        case .exifGPS: "EXIF GPS"
        case .quickTime: "QuickTime location"
        case .xmpGPS: "XMP GPS"
        case .manual: "Manual location"
        case .none: "No location"
        }
    }
}

struct CustomAlbum: Identifiable, Hashable {
    let id: Int64
    var name: String
    var itemCount: Int
    var createdAt: Date
    var updatedAt: Date
}

struct BatchMetadataSummary: Equatable {
    var selectedCount: Int
    var sharedKeywords: [String]
    var commonCaption: String?
    var hasMixedCaptions: Bool
    var commonLocationText: String?
    var hasMixedLocations: Bool
    var commonFavorite: Bool?

    static let empty = BatchMetadataSummary(
        selectedCount: 0,
        sharedKeywords: [],
        commonCaption: nil,
        hasMixedCaptions: false,
        commonLocationText: nil,
        hasMixedLocations: false,
        commonFavorite: nil
    )
}

struct MissingFolderRepairCandidate: Identifiable, Hashable {
    var id: String { folderPath }
    var folderPath: String
    var missingCount: Int
    var sampleFilenames: [String]

    var title: String {
        folderPath.isEmpty ? "All Missing Files" : folderPath
    }

    var subtitle: String {
        sampleFilenames.isEmpty ? "No sample files" : sampleFilenames.joined(separator: ", ")
    }
}

struct MissingFileRemap: Hashable {
    var id: Int64
    var relativePath: String
    var folderPath: String
    var filename: String
    var fileSize: Int64
    var modifiedAt: Date
}

struct MissingFileRepairResult: Equatable {
    var scannedCount: Int
    var matchedCount: Int
    var repairedCount: Int

    var skippedCount: Int {
        max(scannedCount - repairedCount, 0)
    }
}

struct SearchFilters: Equatable {
    var photosOnly = false
    var videosOnly = false
}

enum TimelineQuickFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case videos
    case withLocation
    case withoutLocation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .photos: "Photos"
        case .videos: "Videos"
        case .withLocation: "Mapped"
        case .withoutLocation: "No Location"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "rectangle.grid.3x2"
        case .photos: "photo"
        case .videos: "film"
        case .withLocation: "mappin.and.ellipse"
        case .withoutLocation: "location.slash"
        }
    }
}

enum TimelineSortOption: String, CaseIterable, Identifiable {
    case captureNewest
    case captureOldest
    case recentlyAdded
    case fileName
    case largestFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureNewest: "Newest Capture"
        case .captureOldest: "Oldest Capture"
        case .recentlyAdded: "Recently Added"
        case .fileName: "File Name"
        case .largestFile: "Largest Files"
        }
    }

    var systemImage: String {
        switch self {
        case .captureNewest: "calendar.badge.clock"
        case .captureOldest: "calendar"
        case .recentlyAdded: "clock.arrow.circlepath"
        case .fileName: "textformat.abc"
        case .largestFile: "externaldrive.badge.timemachine"
        }
    }
}

struct CatalogueCounts: Equatable {
    var totalItems: Int
    var photos: Int
    var videos: Int
    var locatedItems: Int
    var missingLocationItems: Int

    static let zero = CatalogueCounts(
        totalItems: 0,
        photos: 0,
        videos: 0,
        locatedItems: 0,
        missingLocationItems: 0
    )

    var videoLikeItems: Int {
        videos
    }

    var photoLikeItems: Int {
        photos
    }
}

struct FolderCatalogueSummary: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var name: String
    var itemCount: Int
    var photoCount: Int
    var videoCount: Int
    var newestCaptureDate: Date?
    var oldestCaptureDate: Date?
    var representativeMediaID: Int64?
}

struct SmartAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let kind: SmartAlbumKind
    let itemCount: Int
    let sortPriority: Int

    var isPlaceholder: Bool {
        switch kind {
        case .people:
            return true
        default:
            return false
        }
    }
}

enum SmartAlbumKind: Hashable {
    case screenshots
    case largeVideos
    case recentlyEdited
    case missingLocation
    case favorites
    case cameraModel(make: String, model: String)
    case trip(city: String, state: String, country: String)
    case customAlbum(id: Int64)
    case people
}

struct PlaceCluster: Identifiable, Hashable {
    var id: String { "\(latitudeBucket):\(longitudeBucket)" }
    var latitudeBucket: Double
    var longitudeBucket: Double
    var latitude: Double
    var longitude: Double
    var itemCount: Int
    var representativeMediaID: Int64?
    var representativeFilename: String
}

struct DuplicateGroup: Identifiable, Hashable {
    let contentHash: String
    let items: [MediaItem]

    var id: String { contentHash }

    var sortedItems: [MediaItem] {
        items.sorted { lhs, rhs in
            let lhsScore = keeperScore(for: lhs)
            let rhsScore = keeperScore(for: rhs)
            if lhsScore == rhsScore {
                let lhsNamePenalty = duplicateNamePenalty(for: lhs.filename)
                let rhsNamePenalty = duplicateNamePenalty(for: rhs.filename)
                if lhsNamePenalty != rhsNamePenalty {
                    return lhsNamePenalty < rhsNamePenalty
                }

                let lhsNameLength = filenameStem(lhs.filename).count
                let rhsNameLength = filenameStem(rhs.filename).count
                if lhsNameLength != rhsNameLength {
                    return lhsNameLength < rhsNameLength
                }

                return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
            return lhsScore > rhsScore
        }
    }

    var suggestedKeeper: MediaItem? {
        sortedItems.first
    }

    var duplicateItems: [MediaItem] {
        guard let suggestedKeeper else { return [] }
        return items.filter { $0.id != suggestedKeeper.id }
    }

    var reclaimableBytes: Int64 {
        guard let suggestedKeeper else { return 0 }
        return items.reduce(Int64(0)) { $0 + $1.fileSize } - suggestedKeeper.fileSize
    }

    var keeperReasons: [String] {
        guard let keeper = suggestedKeeper else { return [] }
        var reasons: [String] = []

        let maxArea = items.map(pixelArea).max() ?? 0
        if pixelArea(for: keeper) == maxArea, maxArea > 0 {
            reasons.append("highest resolution")
        }

        if keeper.coordinate != nil {
            reasons.append("has GPS")
        }

        if keeper.dateSource != .filesystemModified && keeper.dateSource != .unknown {
            reasons.append("embedded capture date")
        }

        if !keeper.cameraText.isEmpty || keeper.lensModel?.isEmpty == false {
            reasons.append("camera metadata")
        }

        if pathLooksOriginal(keeper.relativePath) {
            reasons.append("archive folder")
        }

        if duplicateNamePenalty(for: keeper.filename) == 0,
           items.contains(where: { duplicateNamePenalty(for: $0.filename) > 0 || filenameStem($0.filename).count > filenameStem(keeper.filename).count }) {
            reasons.append("clean filename")
        }

        return reasons.isEmpty ? ["best stable location"] : reasons
    }

    func itemsToDelete(keeping keeper: MediaItem) -> [MediaItem] {
        items.filter { $0.id != keeper.id }
    }

    private func keeperScore(for item: MediaItem) -> Int64 {
        var score = pixelArea(for: item)

        if item.dateSource != .filesystemModified && item.dateSource != .unknown {
            score += 6_000_000
        }
        if item.coordinate != nil {
            score += 5_000_000
        }
        if !item.cameraText.isEmpty {
            score += 2_000_000
        }
        if item.lensModel?.isEmpty == false {
            score += 1_000_000
        }
        if pathLooksOriginal(item.relativePath) {
            score += 3_000_000
        }

        score += min(item.fileSize / 1_000_000, 500)
        return score
    }

    private func pixelArea(for item: MediaItem) -> Int64 {
        guard let width = item.width, let height = item.height else { return 0 }
        return Int64(width * height)
    }

    private func pathLooksOriginal(_ path: String) -> Bool {
        let lowercasedPath = path.lowercased()
        let preferredTokens = ["dcim", "original", "archive", "camera", "photos library", "masters", "originals"]
        let weakerTokens = ["whatsapp", "download", "downloads", "export", "exports", "compressed", "edited"]

        if weakerTokens.contains(where: lowercasedPath.contains) {
            return false
        }

        return preferredTokens.contains(where: lowercasedPath.contains)
    }

    private func duplicateNamePenalty(for filename: String) -> Int {
        let stem = filenameStem(filename).lowercased()
        var penalty = 0

        if stem.range(of: #"\s*\([0-9]+\)$"#, options: .regularExpression) != nil {
            penalty += 100
        }
        if stem.range(of: #"[-_\s]+copy(\s+[0-9]+)?$"#, options: .regularExpression) != nil {
            penalty += 80
        }
        if stem.range(of: #"[-_\s]+duplicate(\s+[0-9]+)?$"#, options: .regularExpression) != nil {
            penalty += 80
        }
        if stem.range(of: #"[-_\s]+[0-9]+$"#, options: .regularExpression) != nil {
            penalty += 35
        }

        return penalty
    }

    private func filenameStem(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }
}
