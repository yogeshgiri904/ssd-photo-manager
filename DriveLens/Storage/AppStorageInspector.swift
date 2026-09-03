import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct AppStorageReport: Equatable {
    var generatedAt: Date
    var activeCataloguePath: String?
    var mappedCatalogues: [CatalogueStorageSnapshot]
    var bookmarkBytes: Int64

    static let empty = AppStorageReport(
        generatedAt: Date(),
        activeCataloguePath: nil,
        mappedCatalogues: [],
        bookmarkBytes: 0
    )

    var activeCatalogue: CatalogueStorageSnapshot? {
        guard let activeCataloguePath else { return nil }
        return mappedCatalogues.first { $0.path == activeCataloguePath }
    }

    var totalCatalogueBytes: Int64 {
        mappedCatalogues.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    var totalDatabaseBytes: Int64 {
        mappedCatalogues.reduce(Int64(0)) { $0 + $1.databaseBytes }
    }

    var totalThumbnailBytes: Int64 {
        mappedCatalogues.reduce(Int64(0)) { $0 + $1.thumbnailBytes + $1.videoThumbnailBytes }
    }

    var totalKnownBytes: Int64 {
        totalCatalogueBytes + bookmarkBytes
    }

    var macResidentBytes: Int64 {
        bookmarkBytes + mappedCatalogues
            .filter(\.isStoredOnMac)
            .reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    var mediaStoredBytes: Int64 {
        mappedCatalogues
            .filter { !$0.isStoredOnMac }
            .reduce(Int64(0)) { $0 + $1.totalBytes }
    }
}

struct CatalogueStorageSnapshot: Identifiable, Hashable {
    var id: String { catalogueID }
    var catalogueID: String
    var name: String
    var path: String
    var isNamedCatalogue: Bool
    var isStoredOnMac: Bool
    var sourceCount: Int
    var sourceNames: [String]
    var isActive: Bool
    var hasSavedPermission: Bool
    var isReachable: Bool
    var lastOpenedAt: Date
    var databaseBytes: Int64
    var manifestBytes: Int64
    var thumbnailBytes: Int64
    var videoThumbnailBytes: Int64
    var geocodingCacheBytes: Int64
    var tempBytes: Int64
    var otherBytes: Int64
    var itemCount: Int?
    var photoCount: Int?
    var videoCount: Int?
    var missingItemCount: Int?
    var hashedItemCount: Int?
    var duplicateGroupCount: Int?
    var lastScanDate: Date?

    var totalBytes: Int64 {
        databaseBytes
        + manifestBytes
        + thumbnailBytes
        + videoThumbnailBytes
        + geocodingCacheBytes
        + tempBytes
        + otherBytes
    }

    var cacheBytes: Int64 {
        thumbnailBytes + videoThumbnailBytes + geocodingCacheBytes + tempBytes
    }
}

enum AppStorageInspector {
    static func buildReport(
        savedCatalogues: [SavedCatalogue],
        activeRootURL: URL?,
        activeDuplicateGroupCount: Int,
        bookmarkBytes: Int64
    ) -> AppStorageReport {
        var catalogueByID: [String: SavedCatalogue] = [:]

        for catalogue in savedCatalogues {
            catalogueByID[catalogue.id] = catalogue
        }

        if let activeRootURL {
            let activePath = activeRootURL.standardizedFileURL.path
            if !catalogueByID.values.contains(where: { $0.path == activePath }) {
                catalogueByID[activePath] = SavedCatalogue(
                    id: activePath,
                    name: activeRootURL.lastPathComponent,
                    path: activePath,
                    bookmarkData: nil,
                    lastOpenedAt: Date()
                )
            }
        }

        let activePath = activeRootURL?.standardizedFileURL.path
        let snapshots = catalogueByID.values
            .map { snapshot(for: $0, activePath: activePath, activeDuplicateGroupCount: activeDuplicateGroupCount) }
            .sorted {
                if $0.isActive != $1.isActive {
                    return $0.isActive
                }
                if $0.hasSavedPermission != $1.hasSavedPermission {
                    return $0.hasSavedPermission
                }
                return $0.lastOpenedAt > $1.lastOpenedAt
            }

        return AppStorageReport(
            generatedAt: Date(),
            activeCataloguePath: activePath,
            mappedCatalogues: snapshots,
            bookmarkBytes: bookmarkBytes
        )
    }

    private static func snapshot(
        for catalogue: SavedCatalogue,
        activePath: String?,
        activeDuplicateGroupCount: Int
    ) -> CatalogueStorageSnapshot {
        let rootURL = URL(fileURLWithPath: catalogue.path, isDirectory: true)
        let paths = CataloguePaths(rootURL: rootURL)
        let manager = FileManager.default
        let isStoredOnMac = isMacApplicationSupportCatalogueStorage(rootURL)
        let catalogueDirectoryBytes = allocatedSize(of: paths.catalogueDirectory)
        let databaseBytes = fileFamilySize(for: paths.databaseURL)
        let manifestBytes = allocatedSize(of: paths.manifestURL)
        let thumbnailBytes = allocatedSize(of: paths.thumbnailsDirectory)
        let videoThumbnailBytes = allocatedSize(of: paths.videoThumbnailsDirectory)
        let geocodingBytes = allocatedSize(of: paths.geocodingCacheDirectory)
        let tempBytes = allocatedSize(of: paths.tempDirectory)
        let knownBytes = databaseBytes + manifestBytes + thumbnailBytes + videoThumbnailBytes + geocodingBytes + tempBytes
        let metrics = readMetrics(from: paths.databaseURL)
        let isActive = catalogue.path == activePath

        return CatalogueStorageSnapshot(
            catalogueID: catalogue.id,
            name: catalogue.name,
            path: catalogue.path,
            isNamedCatalogue: catalogue.isNamedCatalogue,
            isStoredOnMac: isStoredOnMac,
            sourceCount: catalogue.isNamedCatalogue ? catalogue.sourceList.count : 1,
            sourceNames: catalogue.sourceList.map(\.name),
            isActive: isActive,
            hasSavedPermission: catalogue.hasSavedPermission,
            isReachable: manager.fileExists(atPath: rootURL.path),
            lastOpenedAt: catalogue.lastOpenedAt,
            databaseBytes: databaseBytes,
            manifestBytes: manifestBytes,
            thumbnailBytes: thumbnailBytes,
            videoThumbnailBytes: videoThumbnailBytes,
            geocodingCacheBytes: geocodingBytes,
            tempBytes: tempBytes,
            otherBytes: max(catalogueDirectoryBytes - knownBytes, 0),
            itemCount: metrics?.itemCount,
            photoCount: metrics?.photoCount,
            videoCount: metrics?.videoCount,
            missingItemCount: metrics?.missingItemCount,
            hashedItemCount: metrics?.hashedItemCount,
            duplicateGroupCount: isActive ? activeDuplicateGroupCount : metrics?.duplicateGroupCount,
            lastScanDate: metrics?.lastScanDate
        )
    }

    private static func isMacApplicationSupportCatalogueStorage(_ url: URL) -> Bool {
        guard let supportURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return false
        }

        let catalogueRoot = supportURL
            .appendingPathComponent("DriveLens", isDirectory: true)
            .appendingPathComponent("Catalogues", isDirectory: true)
            .standardizedFileURL
            .path
        let path = url.standardizedFileURL.path
        return path == catalogueRoot || path.hasPrefix(catalogueRoot + "/")
    }

    private static func fileFamilySize(for databaseURL: URL) -> Int64 {
        allocatedSize(of: databaseURL)
        + allocatedSize(of: URL(fileURLWithPath: databaseURL.path + "-wal"))
        + allocatedSize(of: URL(fileURLWithPath: databaseURL.path + "-shm"))
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileAllocatedSize(url)
        }

        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += fileAllocatedSize(fileURL)
        }
        return total
    }

    private static func fileAllocatedSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
              values.isRegularFile == true else {
            return 0
        }

        if let totalFileAllocatedSize = values.totalFileAllocatedSize {
            return Int64(totalFileAllocatedSize)
        }
        if let fileAllocatedSize = values.fileAllocatedSize {
            return Int64(fileAllocatedSize)
        }
        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }
        return 0
    }
}

private struct CatalogueDatabaseMetrics {
    var itemCount: Int
    var photoCount: Int
    var videoCount: Int
    var missingItemCount: Int
    var hashedItemCount: Int
    var duplicateGroupCount: Int
    var lastScanDate: Date?
}

private extension AppStorageInspector {
    static func readMetrics(from databaseURL: URL) -> CatalogueDatabaseMetrics? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        guard tableExists("media_items", db: db) else {
            return nil
        }

        let hasContentHash = columnExists("content_hash", in: "media_items", db: db)
        let countsSQL = """
        SELECT
          COUNT(*),
          SUM(CASE WHEN media_type = 'photo' THEN 1 ELSE 0 END),
          SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END),
          SUM(CASE WHEN is_missing = 1 THEN 1 ELSE 0 END),
          SUM(CASE WHEN (hasContentHash ? "content_hash IS NOT NULL AND content_hash != ''" : "0") THEN 1 ELSE 0 END)
        FROM media_items;
        """

        let countValues = readIntRow(sql: countsSQL, db: db, columns: 5)
        let duplicateGroupCount = hasContentHash ? readIntValue(sql: """
        SELECT COUNT(*)
        FROM (
            SELECT content_hash
            FROM media_items
            WHERE content_hash IS NOT NULL AND content_hash != ''
            GROUP BY content_hash
            HAVING COUNT(*) > 1
        );
        """, db: db) : 0

        return CatalogueDatabaseMetrics(
            itemCount: countValues[safe: 0] ?? 0,
            photoCount: countValues[safe: 1] ?? 0,
            videoCount: countValues[safe: 2] ?? 0,
            missingItemCount: countValues[safe: 3] ?? 0,
            hashedItemCount: countValues[safe: 4] ?? 0,
            duplicateGroupCount: duplicateGroupCount,
            lastScanDate: latestScanDate(db: db)
        )
    }

    static func latestScanDate(db: OpaquePointer?) -> Date? {
        guard tableExists("scan_runs", db: db) else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT completed_at FROM scan_runs WHERE completed_at IS NOT NULL ORDER BY id DESC LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: String(cString: text))
    }

    static func readIntValue(sql: String, db: OpaquePointer?) -> Int {
        readIntRow(sql: sql, db: db, columns: 1).first ?? 0
    }

    static func readIntRow(sql: String, db: OpaquePointer?, columns: Int) -> [Int] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return Array(repeating: 0, count: columns)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return Array(repeating: 0, count: columns)
        }

        return (0..<columns).map { Int(sqlite3_column_int(statement, Int32($0))) }
    }

    static func tableExists(_ tableName: String, db: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    static func columnExists(_ columnName: String, in tableName: String, db: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(tableName));", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: text) == columnName {
                return true
            }
        }
        return false
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
