import AVFoundation
import CoreLocation
import Foundation

struct VideoMetadataReader {
    private let filenameParser = FilenameDateParser()

    func read(url: URL, relativePath: String, videoThumbnailPath: String?) async throws -> MediaItem {
        let asset = AVURLAsset(url: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
        let fileSize = attributes[.size] as? NSNumber

        let metadata = try await asset.load(.metadata)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let dimensions = try await tracks.first?.load(.naturalSize)
        let selectedDate = await captureDate(metadata: metadata, filename: url.lastPathComponent, modifiedAt: modifiedAt)
        let coordinate = await location(from: metadata)
        let caption = await metadata.stringValue(for: .commonKeyDescription)
        let contentIdentifier = await contentIdentifier(from: metadata)

        return MediaItem(
            id: 0,
            relativePath: relativePath,
            folderPath: NSString(string: relativePath).deletingLastPathComponent == "." ? "" : NSString(string: relativePath).deletingLastPathComponent,
            filename: url.lastPathComponent,
            kind: .video,
            livePhotoGroupID: contentIdentifier,
            captureDate: selectedDate.date,
            captureDateLocalText: localDateText(selectedDate.date),
            dateSource: selectedDate.source,
            width: dimensions.map { Int(abs($0.width)) },
            height: dimensions.map { Int(abs($0.height)) },
            orientation: nil,
            duration: CMTimeGetSeconds(duration),
            fileSize: fileSize?.int64Value ?? 0,
            modifiedAt: modifiedAt,
            cameraMake: nil,
            cameraModel: nil,
            lensModel: nil,
            caption: caption,
            keywords: [],
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            city: nil,
            state: nil,
            country: nil,
            locationSource: coordinate == nil ? .none : .quickTime,
            thumbnailPath: nil,
            videoThumbnailPath: videoThumbnailPath,
            isMissing: false,
            isFavorite: false,
            addedAt: Date(),
            updatedAt: Date()
        )
    }

    private func captureDate(metadata: [AVMetadataItem], filename: String, modifiedAt: Date) async -> (date: Date, source: DateSource) {
        if let date = await metadata.dateValue(forIdentifier: .quickTimeMetadataCreationDate) {
            return (date, .quickTimeCreationDate)
        }

        if let date = await metadata.dateValue(forIdentifier: .commonIdentifierCreationDate) {
            return (date, .mediaCreationDate)
        }

        if let date = filenameParser.parse(filename) {
            return (date, .filename)
        }

        return (modifiedAt, .filesystemModified)
    }

    private func location(from metadata: [AVMetadataItem]) async -> CLLocationCoordinate2D? {
        guard let location = await metadata.stringValue(forIdentifier: .quickTimeMetadataLocationISO6709) else {
            return nil
        }
        return CLLocationCoordinate2D(iso6709: location)
    }

    private func contentIdentifier(from metadata: [AVMetadataItem]) async -> String? {
        guard let item = metadata.first(where: { item in
            item.identifier?.rawValue.localizedCaseInsensitiveContains("content.identifier") == true
        }) else {
            return nil
        }
        return try? await item.load(.stringValue)
    }

    private func localDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension Array where Element == AVMetadataItem {
    func stringValue(for key: AVMetadataKey) async -> String? {
        guard let item = first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.stringValue)
    }

    func stringValue(forIdentifier identifier: AVMetadataIdentifier) async -> String? {
        guard let item = first(where: { $0.identifier == identifier }) else { return nil }
        return try? await item.load(.stringValue)
    }

    func dateValue(forIdentifier identifier: AVMetadataIdentifier) async -> Date? {
        guard let text = await stringValue(forIdentifier: identifier) else { return nil }
        return ISO8601DateFormatter().date(from: text) ?? quickTimeFormatter.date(from: text)
    }

    private var quickTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

private extension CLLocationCoordinate2D {
    init?(iso6709 string: String) {
        let pattern = #"^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..<string.endIndex, in: string)),
              let latitudeRange = Range(match.range(at: 1), in: string),
              let longitudeRange = Range(match.range(at: 2), in: string),
              let latitude = Double(string[latitudeRange]),
              let longitude = Double(string[longitudeRange]) else {
            return nil
        }
        self.init(latitude: latitude, longitude: longitude)
    }
}
