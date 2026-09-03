import Foundation

struct CataloguePaths {
    let rootURL: URL

    var catalogueDirectory: URL {
        rootURL.appendingPathComponent(".media-catalog", isDirectory: true)
    }

    var databaseURL: URL {
        catalogueDirectory.appendingPathComponent("catalog.sqlite")
    }

    var manifestURL: URL {
        catalogueDirectory.appendingPathComponent("catalog.json")
    }

    var thumbnailsDirectory: URL {
        catalogueDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    var videoThumbnailsDirectory: URL {
        catalogueDirectory.appendingPathComponent("video-thumbnails", isDirectory: true)
    }

    var geocodingCacheDirectory: URL {
        catalogueDirectory.appendingPathComponent("geocoding-cache", isDirectory: true)
    }

    var tempDirectory: URL {
        catalogueDirectory.appendingPathComponent("temp", isDirectory: true)
    }

    func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: catalogueDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: videoThumbnailsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: geocodingCacheDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let manifest = CatalogueManifest(createdAt: Date(), schemaVersion: 1)
        if !manager.fileExists(atPath: manifestURL.path) {
            let data = try JSONEncoder.driveLens.encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])
        }
    }

    func relativePath(for fileURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
        let start = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        return String(filePath[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct CatalogueManifest: Codable {
    let createdAt: Date
    let schemaVersion: Int
}

extension JSONEncoder {
    static var driveLens: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
