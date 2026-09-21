import AppKit
import ImageIO

/// NSCache is thread safe; cached values are immutable decoded pixel buffers.
final class ThumbnailMemoryCache {
    static let shared = ThumbnailMemoryCache()
    private let cache = NSCache<NSString, CGImage>()
    init() {
        cache.countLimit = 600
        cache.totalCostLimit = 96 * 1024 * 1024
    }
    func image(for url: URL, version: Date) -> CGImage? { cache.object(forKey: key(url, version)) }
    func insert(_ image: CGImage, for url: URL, version: Date) {
        cache.setObject(image, forKey: key(url, version), cost: image.bytesPerRow * image.height)
    }
    private func key(_ url: URL, _ version: Date) -> NSString { "\(url.path)|\(version.timeIntervalSince1970)" as NSString }
    func removeAll() { cache.removeAllObjects() }
}

/// Serial decoding bounds simultaneous disk work and large transient pixel allocations.
/// A second cache lookup after entering the actor coalesces queued requests for the same preview.
actor ThumbnailDecoder {
    static let shared = ThumbnailDecoder()
    private let cache: ThumbnailMemoryCache
    private let decodeImage: (URL) -> CGImage?
    init(cache: ThumbnailMemoryCache = .shared, decode: @escaping (URL) -> CGImage? = { ImageFileDecoder.decode($0, maximumPixelSize: 512) }) {
        self.cache = cache
        self.decodeImage = decode
    }
    func decode(_ url: URL, version: Date) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = cache.image(for: url, version: version) { return cached }
        guard let image = decodeImage(url), !Task.isCancelled else { return nil }
        cache.insert(image, for: url, version: version)
        return image
    }
}

actor OriginalImageLoader {
    static let shared = OriginalImageLoader()
    func load(_ url: URL) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let image = ImageFileDecoder.decode(url, maximumPixelSize: nil)
        return Task.isCancelled ? nil : image
    }
}

enum ImageFileDecoder {
    /// nil preserves full resolution for viewer zoom. ImageIO handles EXIF orientation off the UI thread.
    static func decode(_ url: URL, maximumPixelSize: Int?) -> CGImage? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize ?? max(width, height),
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
    }
}
