import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ThumbnailGenerator {
    func generatePhotoThumbnail(sourceURL: URL, destinationURL: URL, maxPixelSize: Int = 320) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
        try writeJPEG(image, to: destinationURL)
    }

    func generateVideoThumbnail(sourceURL: URL, destinationURL: URL, maxPixelSize: Int = 320) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let image = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        try writeJPEG(image, to: destinationURL)
    }

    private func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}
