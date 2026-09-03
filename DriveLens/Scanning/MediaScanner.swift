import Foundation

struct ScanProgress: Equatable {
    var status: ScanStatus = .idle
    var currentFilename = ""
    var filesScanned = 0
    var totalFilesDiscovered = 0
    var photosFound = 0
    var videosFound = 0
    var newFiles = 0
    var alreadyIndexedFiles = 0
    var refreshedFiles = 0
    var missingFiles = 0
    var unsupportedFiles = 0
    var errors = 0
    var startedAt = Date()

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    var estimatedRemainingTime: TimeInterval? {
        guard filesScanned > 0, totalFilesDiscovered > filesScanned else { return nil }
        let secondsPerFile = elapsedTime / Double(filesScanned)
        return Double(totalFilesDiscovered - filesScanned) * secondsPerFile
    }
}

enum ScanStatus: String, Equatable {
    case idle
    case discovering
    case scanning
    case cancelled
    case completed
}

struct ScanSummary: Equatable {
    var filesDiscovered: Int
    var filesScanned: Int
    var photosFound: Int
    var videosFound: Int
    var newFiles: Int
    var alreadyIndexedFiles: Int
    var refreshedFiles: Int
    var missingFiles: Int
    var unsupportedFiles: Int
    var errors: Int
    var startedAt: Date
    var completedAt: Date?
    var status: String
}

final class MediaScanner {
    private let rootURL: URL
    private let paths: CataloguePaths
    private let database: CatalogueDatabase
    private let sourcePrefix: String
    private let metadataReader = MediaMetadataReader()
    private let thumbnailGenerator = ThumbnailGenerator()

    init(rootURL: URL, paths: CataloguePaths, database: CatalogueDatabase, sourcePrefix: String = "") {
        self.rootURL = rootURL
        self.paths = paths
        self.database = database
        self.sourcePrefix = sourcePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func scan(rebuild: Bool, scopeURLs: [URL]? = nil, progress: @escaping (ScanProgress) -> Void) async throws -> ScanSummary {
        let startedAt = Date()
        var current = ScanProgress(status: .discovering, startedAt: startedAt)
        progress(current)

        let scanRoots = normalizedScopeURLs(scopeURLs)
        let discovered = try discoverFiles(in: scanRoots)
        current.totalFilesDiscovered = discovered.supported.count + discovered.unsupported
        current.unsupportedFiles = discovered.unsupported
        current.status = .scanning
        progress(current)

        let existing = rebuild ? [:] : try database.existingFingerprints()
        var seenPaths = Set<String>()
        var changedItems: [MediaItem] = []
        var allItemsForRebuild: [MediaItem] = []

        for fileURL in discovered.supported {
            try Task.checkCancellation()

            let relativePath = catalogueRelativePath(for: fileURL)
            seenPaths.insert(relativePath)
            current.currentFilename = fileURL.lastPathComponent
            current.filesScanned += 1
            let kind = SupportedMedia.kind(forExtension: fileURL.pathExtension.localizedLowercase)

            if kind == .video {
                current.videosFound += 1
            } else {
                current.photosFound += 1
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let fingerprint = FileFingerprint(fileSize: size, modifiedAt: modifiedAt)

            if !rebuild, existing[relativePath] == fingerprint {
                current.alreadyIndexedFiles += 1
                progress(current)
                continue
            }

            let photoThumbnailURL = thumbnailURL(for: relativePath, video: false)
            let posterThumbnailURL = thumbnailURL(for: relativePath, video: true)

            if kind == .video {
                try? await thumbnailGenerator.generateVideoThumbnail(sourceURL: fileURL, destinationURL: posterThumbnailURL)
            } else {
                try? thumbnailGenerator.generatePhotoThumbnail(sourceURL: fileURL, destinationURL: photoThumbnailURL)
            }

            if var item = await metadataReader.read(
                url: fileURL,
                relativePath: relativePath,
                thumbnailPath: kind == .video ? nil : paths.relativePath(for: photoThumbnailURL),
                videoThumbnailPath: kind == .video ? paths.relativePath(for: posterThumbnailURL) : nil
            ) {
                item = item.withUpdatedFingerprint(fileSize: size, modifiedAt: modifiedAt)
                changedItems.append(item)
                allItemsForRebuild.append(item)
                if rebuild || existing[relativePath] == nil {
                    current.newFiles += 1
                } else {
                    current.refreshedFiles += 1
                }
            } else {
                current.errors += 1
            }

            progress(current)
        }

        let scannedPrefixes = scanRoots.map { catalogueRelativePath(for: $0) }
        let removed = rebuild ? [] : existing.keys.filter { path in
            pathIsInScannedScope(path, prefixes: scannedPrefixes) && !seenPaths.contains(path)
        }
        current.missingFiles = removed.count
        let summary = ScanSummary(
            filesDiscovered: current.totalFilesDiscovered,
            filesScanned: current.filesScanned,
            photosFound: current.photosFound,
            videosFound: current.videosFound,
            newFiles: current.newFiles,
            alreadyIndexedFiles: current.alreadyIndexedFiles,
            refreshedFiles: current.refreshedFiles,
            missingFiles: current.missingFiles,
            unsupportedFiles: current.unsupportedFiles,
            errors: current.errors,
            startedAt: startedAt,
            completedAt: Date(),
            status: "completed"
        )

        if rebuild {
            try database.replaceAll(with: pairedItems(from: allItemsForRebuild), summary: summary)
        } else {
            try database.upsertChanged(
                pairedItems(from: changedItems),
                removedRelativePaths: Array(removed),
                seenRelativePaths: Array(seenPaths),
                summary: summary
            )
        }

        var completed = current
        completed.status = .completed
        progress(completed)
        return summary
    }

    private func discoverFiles(in roots: [URL]) throws -> (supported: [URL], unsupported: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey]
        var supported: [URL] = []
        var unsupported = 0
        var seenPaths = Set<String>()

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                try Task.checkCancellation()

                if fileURL.lastPathComponent == ".media-catalog" || fileURL.lastPathComponent == ".drivelens" {
                    enumerator.skipDescendants()
                    continue
                }

                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }

                if SupportedMedia.isSupported(url: fileURL) {
                    let path = fileURL.standardizedFileURL.path
                    if seenPaths.insert(path).inserted {
                        supported.append(fileURL)
                    }
                } else {
                    unsupported += 1
                }
            }
        }

        return (supported, unsupported)
    }

    private func normalizedScopeURLs(_ scopeURLs: [URL]?) -> [URL] {
        guard let scopeURLs, !scopeURLs.isEmpty else { return [rootURL] }

        let unique = scopeURLs
            .map(\.standardizedFileURL)
            .filter { isSameOrDescendant($0, of: rootURL.standardizedFileURL) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .reduce(into: [URL]()) { output, url in
                let path = url.path
                if output.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
                    return
                }
                output.append(url)
            }

        return unique.isEmpty ? [rootURL] : unique
    }

    private func pathIsInScannedScope(_ relativePath: String, prefixes: [String]) -> Bool {
        prefixes.contains { prefix in
            prefix.isEmpty || relativePath == prefix || relativePath.hasPrefix(prefix + "/")
        }
    }

    private func isSameOrDescendant(_ url: URL, of rootURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func catalogueRelativePath(for fileURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let sourceRelativePath: String
        if filePath == rootPath {
            sourceRelativePath = ""
        } else if filePath.hasPrefix(rootPath + "/") {
            let start = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
            sourceRelativePath = String(filePath[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            sourceRelativePath = fileURL.lastPathComponent
        }

        guard !sourcePrefix.isEmpty else { return sourceRelativePath }
        guard !sourceRelativePath.isEmpty else { return sourcePrefix }
        return sourcePrefix + "/" + sourceRelativePath
    }

    private func thumbnailURL(for relativePath: String, video: Bool) -> URL {
        let safeName = relativePath
            .replacingOccurrences(of: "/", with: "__")
            .replacingOccurrences(of: ":", with: "_")
        let directory = video ? paths.videoThumbnailsDirectory : paths.thumbnailsDirectory
        return directory.appendingPathComponent(safeName).appendingPathExtension("jpg")
    }

    private func pairedItems(from items: [MediaItem]) -> [MediaItem] {
        var consumedVideoPaths = Set<String>()
        var output: [MediaItem] = []

        let groups = Dictionary(grouping: items.filter { $0.livePhotoGroupID?.isEmpty == false }) { item in
            item.livePhotoGroupID ?? ""
        }

        for groupItems in groups.values {
            guard var photo = groupItems.first(where: { $0.kind == .photo }),
                  let video = groupItems.first(where: { $0.kind == .video }) else {
                continue
            }
            photo.kind = .livePhoto
            photo.videoThumbnailPath = video.videoThumbnailPath
            photo.duration = video.duration
            consumedVideoPaths.insert(video.relativePath)
            output.append(photo)
        }

        let alreadyOutputPhotoPaths = Set(output.map(\.relativePath))
        for item in items where !consumedVideoPaths.contains(item.relativePath) && !alreadyOutputPhotoPaths.contains(item.relativePath) {
            output.append(item)
        }

        return pairedByFilenameFallback(output)
    }

    private func pairedByFilenameFallback(_ items: [MediaItem]) -> [MediaItem] {
        var videosByStem = Dictionary(grouping: items.filter { $0.kind == .video }) { item in
            stem(for: item.relativePath)
        }
        var consumedVideos = Set<String>()
        var output: [MediaItem] = []

        for var item in items {
            guard item.kind == .photo,
                  let candidate = videosByStem[stem(for: item.relativePath)]?.first(where: { video in
                      abs(video.captureDate.timeIntervalSince(item.captureDate)) < 4
                  }) else {
                continue
            }

            item.kind = .livePhoto
            item.videoThumbnailPath = candidate.videoThumbnailPath
            item.duration = candidate.duration
            consumedVideos.insert(candidate.relativePath)
            output.append(item)
            videosByStem[stem(for: item.relativePath)]?.removeAll { $0.relativePath == candidate.relativePath }
        }

        let livePhotoPaths = Set(output.map(\.relativePath))
        for item in items where !livePhotoPaths.contains(item.relativePath) && !consumedVideos.contains(item.relativePath) {
            output.append(item)
        }

        return output
    }

    private func stem(for relativePath: String) -> String {
        let url = URL(fileURLWithPath: relativePath)
        let folder = url.deletingLastPathComponent().path
        return folder + "/" + url.deletingPathExtension().lastPathComponent.localizedLowercase
    }
}

private extension MediaItem {
    func withUpdatedFingerprint(fileSize: Int64, modifiedAt: Date) -> MediaItem {
        var copy = self
        copy.fileSize = fileSize
        copy.modifiedAt = modifiedAt
        copy.updatedAt = Date()
        return copy
    }
}
