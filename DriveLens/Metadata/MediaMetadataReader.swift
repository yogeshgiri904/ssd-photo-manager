import Foundation
import UniformTypeIdentifiers

struct MediaMetadataReader {
    private let photoReader = PhotoMetadataReader()
    private let videoReader = VideoMetadataReader()

    func read(url: URL, relativePath: String, thumbnailPath: String?, videoThumbnailPath: String?) async -> MediaItem? {
        let ext = url.pathExtension.localizedLowercase
        let kind = SupportedMedia.kind(forExtension: ext)

        do {
            switch kind {
            case .photo, .livePhoto:
                return try photoReader.read(url: url, relativePath: relativePath, thumbnailPath: thumbnailPath)
            case .video:
                return try await videoReader.read(url: url, relativePath: relativePath, videoThumbnailPath: videoThumbnailPath)
            case nil:
                return nil
            }
        } catch {
            return nil
        }
    }
}

enum SupportedMedia {
    static let photoExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "gif", "dng"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static func kind(forExtension ext: String) -> MediaKind? {
        if photoExtensions.contains(ext) { return .photo }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }

    static func isSupported(url: URL) -> Bool {
        kind(forExtension: url.pathExtension.localizedLowercase) != nil
    }
}
