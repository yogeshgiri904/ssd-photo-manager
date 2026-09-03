import CoreGraphics
import Foundation
import ImageIO

struct PhotoMetadataReader {
    private let filenameParser = FilenameDateParser()

    func read(url: URL, relativePath: String, thumbnailPath: String?) throws -> MediaItem {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw MetadataError.unreadable
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
        let fileSize = attributes[.size] as? NSNumber
        let selectedDate = captureDate(exif: exif, filename: url.lastPathComponent, modifiedAt: modifiedAt)
        let location = gpsLocation(from: gps)

        return MediaItem(
            id: 0,
            relativePath: relativePath,
            folderPath: NSString(string: relativePath).deletingLastPathComponent == "." ? "" : NSString(string: relativePath).deletingLastPathComponent,
            filename: url.lastPathComponent,
            kind: .photo,
            livePhotoGroupID: contentIdentifier(from: properties),
            captureDate: selectedDate.date,
            captureDateLocalText: localDateText(selectedDate.date),
            dateSource: selectedDate.source,
            width: properties[kCGImagePropertyPixelWidth] as? Int,
            height: properties[kCGImagePropertyPixelHeight] as? Int,
            orientation: properties[kCGImagePropertyOrientation] as? Int,
            duration: nil,
            fileSize: fileSize?.int64Value ?? 0,
            modifiedAt: modifiedAt,
            cameraMake: tiff?[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif?[kCGImagePropertyExifLensModel] as? String,
            caption: caption(from: iptc, properties: properties),
            keywords: keywords(from: iptc),
            latitude: location?.latitude,
            longitude: location?.longitude,
            city: nil,
            state: nil,
            country: nil,
            locationSource: location == nil ? .none : .exifGPS,
            thumbnailPath: thumbnailPath,
            videoThumbnailPath: nil,
            isMissing: false,
            isFavorite: false,
            addedAt: Date(),
            updatedAt: Date()
        )
    }

    private func captureDate(exif: [CFString: Any]?, filename: String, modifiedAt: Date) -> (date: Date, source: DateSource) {
        if let value = exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = parseEXIFDate(value) {
            return (date, .exifDateTimeOriginal)
        }

        if let value = exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
           let date = parseEXIFDate(value) {
            return (date, .exifCreateDate)
        }

        if let date = filenameParser.parse(filename) {
            return (date, .filename)
        }

        return (modifiedAt, .filesystemModified)
    }

    private func parseEXIFDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }

    private func localDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func gpsLocation(from gps: [CFString: Any]?) -> (latitude: Double, longitude: Double)? {
        guard var latitude = gps?[kCGImagePropertyGPSLatitude] as? Double,
              var longitude = gps?[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }

        if (gps?[kCGImagePropertyGPSLatitudeRef] as? String) == "S" {
            latitude *= -1
        }

        if (gps?[kCGImagePropertyGPSLongitudeRef] as? String) == "W" {
            longitude *= -1
        }

        return (latitude, longitude)
    }

    private func caption(from iptc: [CFString: Any]?, properties: [CFString: Any]) -> String? {
        if let caption = iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String {
            return caption
        }
        return properties[kCGImagePropertyPNGDescription] as? String
    }

    private func keywords(from iptc: [CFString: Any]?) -> [String] {
        if let keywords = iptc?[kCGImagePropertyIPTCKeywords] as? [String] {
            return keywords
        }
        return []
    }

    private func contentIdentifier(from properties: [CFString: Any]) -> String? {
        let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [CFString: Any]
        return makerApple?["17" as CFString] as? String
    }
}

enum MetadataError: Error {
    case unreadable
}
