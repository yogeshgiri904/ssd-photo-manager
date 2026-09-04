import Foundation
import SQLite3

final class CatalogueDatabase {
    private var db: OpaquePointer?
    private let isoFormatter = ISO8601DateFormatter()

    init(databaseURL: URL) throws {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw CatalogueDatabaseError.openFailed(message: lastError)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func replaceAll(with items: [MediaItem], summary: ScanSummary) throws {
        try transaction {
            try execute("DELETE FROM media_items;")
            try execute("DELETE FROM folders;")
            for item in items {
                try upsert(item)
            }
            try rebuildFolders()
            try insert(summary)
        }
    }

    func upsertChanged(_ items: [MediaItem], removedRelativePaths: [String], seenRelativePaths: [String], summary: ScanSummary) throws {
        try transaction {
            try markMissing(relativePaths: removedRelativePaths)
            try markAvailable(relativePaths: seenRelativePaths)
            for item in items {
                try upsert(item)
            }
            try rebuildFolders()
            try insert(summary)
        }
    }

    func deleteMediaItem(relativePath: String) throws {
        try transaction {
            try delete(relativePath: relativePath)
            try rebuildFolders()
        }
    }

    func fetchMissingMediaItems() throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE is_missing = 1
        ORDER BY folder_path COLLATE NOCASE ASC, filename COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    func remapMissingFiles(_ remaps: [MissingFileRemap]) throws -> Int {
        guard !remaps.isEmpty else { return 0 }

        let sql = """
        UPDATE media_items
        SET relative_path = ?,
            folder_path = ?,
            filename = ?,
            file_size = ?,
            modified_at = ?,
            is_missing = 0,
            updated_at = ?
        WHERE id = ?
          AND is_missing = 1
          AND NOT EXISTS (
            SELECT 1 FROM media_items AS existing
            WHERE existing.relative_path = ?
              AND existing.id != ?
          );
        """

        var repairedCount = 0
        try transaction {
            for remap in remaps {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw CatalogueDatabaseError.prepareFailed(message: lastError)
                }
                bind(statement, 1, remap.relativePath)
                bind(statement, 2, remap.folderPath)
                bind(statement, 3, remap.filename)
                bind(statement, 4, remap.fileSize)
                bind(statement, 5, isoFormatter.string(from: remap.modifiedAt))
                bind(statement, 6, isoFormatter.string(from: Date()))
                sqlite3_bind_int64(statement, 7, remap.id)
                bind(statement, 8, remap.relativePath)
                sqlite3_bind_int64(statement, 9, remap.id)

                let stepResult = sqlite3_step(statement)
                let changedRows = sqlite3_changes(db)
                sqlite3_finalize(statement)

                guard stepResult == SQLITE_DONE else {
                    throw CatalogueDatabaseError.writeFailed(message: lastError)
                }

                repairedCount += Int(changedRows)
            }
            try rebuildFolders()
        }
        return repairedCount
    }

    func compact() throws {
        try execute("VACUUM;")
    }

    @discardableResult
    func repairLivePhotoPairs() throws -> Int {
        let items = try fetchAllMediaItemsForPairing()
        let pairs = livePhotoRepairPairs(from: items)
        guard !pairs.isEmpty else { return 0 }

        var repairedCount = 0
        try transaction {
            for pair in pairs {
                try markLivePhoto(photo: pair.photo, video: pair.video)
                try delete(relativePath: pair.video.relativePath)
                if pair.photo.kind != .livePhoto {
                    repairedCount += 1
                }
            }
            try rebuildFolders()
        }
        return repairedCount
    }

    func updateMediaLocation(
        id: Int64,
        relativePath: String,
        folderPath: String,
        filename: String,
        fileSize: Int64,
        modifiedAt: Date
    ) throws {
        try transaction {
            let sql = """
            UPDATE media_items
            SET relative_path = ?,
                folder_path = ?,
                filename = ?,
                file_size = ?,
                modified_at = ?,
                updated_at = ?
            WHERE id = ?;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw CatalogueDatabaseError.prepareFailed(message: lastError)
            }
            defer { sqlite3_finalize(statement) }

            bind(statement, 1, relativePath)
            bind(statement, 2, folderPath)
            bind(statement, 3, filename)
            bind(statement, 4, fileSize)
            bind(statement, 5, isoFormatter.string(from: modifiedAt))
            bind(statement, 6, isoFormatter.string(from: Date()))
            sqlite3_bind_int64(statement, 7, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw CatalogueDatabaseError.writeFailed(message: lastError)
            }

            try rebuildFolders()
        }
    }

    func existingFingerprints() throws -> [String: FileFingerprint] {
        let sql = "SELECT relative_path, file_size, modified_at FROM media_items;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var results: [String: FileFingerprint] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = textColumn(statement, 0)
            let size = sqlite3_column_int64(statement, 1)
            let modified = dateColumn(statement, 2) ?? .distantPast
            results[path] = FileFingerprint(fileSize: size, modifiedAt: modified)
        }
        return results
    }

    func fetchDuplicateHashCandidates() throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE file_size > 0
          AND (content_hash IS NULL OR content_hash = '')
          AND file_size IN (
            SELECT file_size
            FROM media_items
            WHERE file_size > 0
            GROUP BY file_size
            HAVING COUNT(*) > 1
          )
        ORDER BY file_size DESC, relative_path COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    func updateContentHash(id: Int64, contentHash: String) throws {
        let sql = "UPDATE media_items SET content_hash = ?, updated_at = ? WHERE id = ?;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, contentHash)
        bind(statement, 2, isoFormatter.string(from: Date()))
        sqlite3_bind_int64(statement, 3, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    func fetchDuplicateGroups() throws -> [DuplicateGroup] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite,
               content_hash
        FROM media_items
        WHERE content_hash IN (
            SELECT content_hash
            FROM media_items
            WHERE content_hash IS NOT NULL AND content_hash != ''
            GROUP BY content_hash
            HAVING COUNT(*) > 1
        )
        ORDER BY content_hash ASC, file_size DESC, relative_path COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var groupedItems: [String: [MediaItem]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let item = readMediaItem(from: statement)
            let contentHash = textColumn(statement, 34)
            groupedItems[contentHash, default: []].append(item)
        }

        return groupedItems
            .map { DuplicateGroup(contentHash: $0.key, items: $0.value) }
            .sorted {
                if $0.reclaimableBytes == $1.reclaimableBytes {
                    return $0.items.count > $1.items.count
                }
                return $0.reclaimableBytes > $1.reclaimableBytes
            }
    }

    func countDuplicateGroups() throws -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM (
            SELECT content_hash
            FROM media_items
            WHERE content_hash IS NOT NULL AND content_hash != ''
            GROUP BY content_hash
            HAVING COUNT(*) > 1
        );
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    func fetchMedia(limit: Int, offset: Int) throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        ORDER BY capture_date DESC
        LIMIT ? OFFSET ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))
        sqlite3_bind_int(statement, 2, Int32(offset))

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    func fetchMedia(inFolderPath folderPath: String, limit: Int, offset: Int) throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE folder_path = ?
        ORDER BY capture_date DESC
        LIMIT ? OFFSET ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, folderPath)
        sqlite3_bind_int(statement, 2, Int32(limit))
        sqlite3_bind_int(statement, 3, Int32(offset))

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    func fetchVideos(limit: Int, offset: Int) throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE media_type = 'video'
        ORDER BY capture_date DESC
        LIMIT ? OFFSET ?;
        """
        return try fetchMedia(sql: sql, limit: limit, offset: offset)
    }

    func fetchRecentlyAdded(filter: TimelineQuickFilter = .all, year: Int? = nil, sort: TimelineSortOption = .recentlyAdded, limit: Int, offset: Int) throws -> [MediaItem] {
        try fetchTimeline(filter: filter, year: year, sort: sort, limit: limit, offset: offset)
    }

    func fetchRecentlyAddedCounts(filter: TimelineQuickFilter = .all, year: Int? = nil) throws -> CatalogueCounts {
        try fetchTimelineCounts(filter: filter, year: year)
    }

    func fetchRecentlyAddedYears(filter: TimelineQuickFilter = .all) throws -> [Int] {
        try fetchTimelineYears(filter: filter)
    }

    func fetchTimeline(filter: TimelineQuickFilter, year: Int? = nil, sort: TimelineSortOption = .captureNewest, limit: Int, offset: Int) throws -> [MediaItem] {
        let query = TimelineQuery(filter: filter, year: year)

        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        \(query.whereClause)
        ORDER BY \(sort.orderClause)
        LIMIT ? OFFSET ?;
        """
        return try fetchMedia(sql: sql, values: query.values, limit: limit, offset: offset)
    }

    func countTimeline(filter: TimelineQuickFilter, year: Int? = nil) throws -> Int {
        try fetchTimelineCounts(filter: filter, year: year).totalItems
    }

    func fetchTimelineCounts(filter: TimelineQuickFilter, year: Int? = nil) throws -> CatalogueCounts {
        let query = TimelineQuery(filter: filter, year: year)
        let sql = """
        SELECT
          COUNT(*),
          COALESCE(SUM(CASE WHEN media_type IN ('photo', 'livePhoto') THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN latitude IS NOT NULL AND longitude IS NOT NULL THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN latitude IS NULL OR longitude IS NULL THEN 1 ELSE 0 END), 0)
        FROM media_items
        \(query.whereClause);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in query.values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .zero
        }

        return CatalogueCounts(
            totalItems: Int(sqlite3_column_int(statement, 0)),
            photos: Int(sqlite3_column_int(statement, 1)),
            videos: Int(sqlite3_column_int(statement, 2)),
            locatedItems: Int(sqlite3_column_int(statement, 3)),
            missingLocationItems: Int(sqlite3_column_int(statement, 4))
        )
    }

    func fetchTimelineYears(filter: TimelineQuickFilter) throws -> [Int] {
        let query = TimelineQuery(filter: filter, year: nil)
        let sql = """
        SELECT DISTINCT substr(capture_date, 1, 4)
        FROM media_items
        \(query.whereClause)
        ORDER BY substr(capture_date, 1, 4) DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in query.values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }

        var years: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let year = Int(textColumn(statement, 0)) {
                years.append(year)
            }
        }
        return years
    }

    func fetchLocatedMedia(limit: Int, offset: Int) throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE latitude IS NOT NULL AND longitude IS NOT NULL
        ORDER BY capture_date DESC
        LIMIT ? OFFSET ?;
        """
        return try fetchMedia(sql: sql, limit: limit, offset: offset)
    }

    func fetchLocatedMedia(in cluster: PlaceCluster, limit: Int, offset: Int) throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE ROUND(latitude, 2) = ? AND ROUND(longitude, 2) = ?
        ORDER BY capture_date DESC
        LIMIT ? OFFSET ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cluster.latitudeBucket)
        sqlite3_bind_double(statement, 2, cluster.longitudeBucket)
        sqlite3_bind_int(statement, 3, Int32(limit))
        sqlite3_bind_int(statement, 4, Int32(offset))

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    func fetchPlaceClusters(limit: Int = 900) throws -> [PlaceCluster] {
        let sql = """
        SELECT
          ROUND(latitude, 2) AS latitude_bucket,
          ROUND(longitude, 2) AS longitude_bucket,
          AVG(latitude),
          AVG(longitude),
          COUNT(*),
          MIN(id),
          MIN(filename)
        FROM media_items
        WHERE latitude IS NOT NULL AND longitude IS NOT NULL
        GROUP BY latitude_bucket, longitude_bucket
        ORDER BY COUNT(*) DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var clusters: [PlaceCluster] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            clusters.append(
                PlaceCluster(
                    latitudeBucket: sqlite3_column_double(statement, 0),
                    longitudeBucket: sqlite3_column_double(statement, 1),
                    latitude: sqlite3_column_double(statement, 2),
                    longitude: sqlite3_column_double(statement, 3),
                    itemCount: Int(sqlite3_column_int(statement, 4)),
                    representativeMediaID: optionalInt64Column(statement, 5),
                    representativeFilename: textColumn(statement, 6)
                )
            )
        }
        return clusters
    }

    func fetchCatalogueCounts() throws -> CatalogueCounts {
        let sql = """
        SELECT
          COUNT(*),
          COALESCE(SUM(CASE WHEN media_type IN ('photo', 'livePhoto') THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN latitude IS NOT NULL AND longitude IS NOT NULL THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN latitude IS NULL OR longitude IS NULL THEN 1 ELSE 0 END), 0)
        FROM media_items;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .zero
        }

        return CatalogueCounts(
            totalItems: Int(sqlite3_column_int(statement, 0)),
            photos: Int(sqlite3_column_int(statement, 1)),
            videos: Int(sqlite3_column_int(statement, 2)),
            locatedItems: Int(sqlite3_column_int(statement, 3)),
            missingLocationItems: Int(sqlite3_column_int(statement, 4))
        )
    }

    func fetchSmartAlbums() throws -> [SmartAlbum] {
        var albums: [SmartAlbum] = [
            SmartAlbum(
                id: SmartAlbumKind.screenshots.id,
                title: "Screenshots",
                subtitle: "Screen captures from macOS, iPhone, and exports",
                systemImage: "camera.viewfinder",
                kind: .screenshots,
                itemCount: try countMedia(whereClause: SmartAlbumKind.screenshots.whereClause),
                sortPriority: 10
            ),
            SmartAlbum(
                id: SmartAlbumKind.largeVideos.id,
                title: "Large Videos",
                subtitle: "Videos larger than 200 MB",
                systemImage: "film.stack",
                kind: .largeVideos,
                itemCount: try countMedia(whereClause: SmartAlbumKind.largeVideos.whereClause),
                sortPriority: 20
            ),
            SmartAlbum(
                id: SmartAlbumKind.recentlyEdited.id,
                title: "Recently Edited",
                subtitle: "Edited, exported, or modified after capture",
                systemImage: "wand.and.stars",
                kind: .recentlyEdited,
                itemCount: try countMedia(whereClause: SmartAlbumKind.recentlyEdited.whereClause),
                sortPriority: 30
            ),
            SmartAlbum(
                id: SmartAlbumKind.missingLocation.id,
                title: "Missing Location",
                subtitle: "Media without GPS metadata",
                systemImage: "location.slash",
                kind: .missingLocation,
                itemCount: try countMedia(whereClause: SmartAlbumKind.missingLocation.whereClause),
                sortPriority: 40
            ),
            SmartAlbum(
                id: SmartAlbumKind.favorites.id,
                title: "Favorites",
                subtitle: "Items marked in DriveLens",
                systemImage: "heart.fill",
                kind: .favorites,
                itemCount: try countMedia(whereClause: SmartAlbumKind.favorites.whereClause),
                sortPriority: 60
            )
        ]

        albums.append(contentsOf: try fetchCameraModelSmartAlbums())
        albums.append(contentsOf: try fetchTripSmartAlbums())
        albums.append(contentsOf: try fetchCustomAlbumSmartAlbums())
        albums.append(
            SmartAlbum(
                id: SmartAlbumKind.people.id,
                title: "People",
                subtitle: "Ready for future local face grouping",
                systemImage: "person.2.crop.square.stack",
                kind: .people,
                itemCount: 0,
                sortPriority: 900
            )
        )

        return albums.sorted {
            if $0.sortPriority == $1.sortPriority {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.sortPriority < $1.sortPriority
        }
    }

    func fetchSmartAlbumItems(
        album: SmartAlbum,
        filter: TimelineQuickFilter = .all,
        year: Int? = nil,
        sort: TimelineSortOption = .captureNewest,
        limit: Int,
        offset: Int
    ) throws -> [MediaItem] {
        guard !album.isPlaceholder else { return [] }
        let query = smartAlbumQuery(album: album, filter: filter, year: year)

        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        \(query.whereClause)
        ORDER BY \(sort.orderClause)
        LIMIT ? OFFSET ?;
        """
        return try fetchMedia(sql: sql, values: query.values, limit: limit, offset: offset)
    }

    func fetchSmartAlbumCounts(album: SmartAlbum, filter: TimelineQuickFilter = .all, year: Int? = nil) throws -> CatalogueCounts {
        guard !album.isPlaceholder else { return .zero }
        let query = smartAlbumQuery(album: album, filter: filter, year: year)
        let sql = """
        SELECT
          COUNT(*),
          COALESCE(SUM(CASE WHEN media_type IN ('photo', 'livePhoto') THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN latitude IS NOT NULL AND longitude IS NOT NULL THEN 1 ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN latitude IS NULL OR longitude IS NULL THEN 1 ELSE 0 END), 0)
        FROM media_items
        \(query.whereClause);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in query.values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return .zero }
        return CatalogueCounts(
            totalItems: Int(sqlite3_column_int(statement, 0)),
            photos: Int(sqlite3_column_int(statement, 1)),
            videos: Int(sqlite3_column_int(statement, 2)),
            locatedItems: Int(sqlite3_column_int(statement, 3)),
            missingLocationItems: Int(sqlite3_column_int(statement, 4))
        )
    }

    func fetchSmartAlbumYears(album: SmartAlbum, filter: TimelineQuickFilter = .all) throws -> [Int] {
        guard !album.isPlaceholder else { return [] }
        let query = smartAlbumQuery(album: album, filter: filter, year: nil)
        let sql = """
        SELECT DISTINCT substr(capture_date, 1, 4)
        FROM media_items
        \(query.whereClause)
        ORDER BY substr(capture_date, 1, 4) DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in query.values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }

        var years: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let year = Int(textColumn(statement, 0)) {
                years.append(year)
            }
        }
        return years
    }

    func fetchCustomAlbums() throws -> [CustomAlbum] {
        let sql = """
        SELECT custom_albums.id, custom_albums.name, COUNT(custom_album_items.media_item_id),
               custom_albums.created_at, custom_albums.updated_at
        FROM custom_albums
        LEFT JOIN custom_album_items ON custom_album_items.album_id = custom_albums.id
        GROUP BY custom_albums.id
        ORDER BY custom_albums.name COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var albums: [CustomAlbum] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            albums.append(
                CustomAlbum(
                    id: sqlite3_column_int64(statement, 0),
                    name: textColumn(statement, 1),
                    itemCount: Int(sqlite3_column_int(statement, 2)),
                    createdAt: dateColumn(statement, 3) ?? Date(),
                    updatedAt: dateColumn(statement, 4) ?? Date()
                )
            )
        }
        return albums
    }

    func createCustomAlbum(named rawName: String) throws -> CustomAlbum? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let now = isoFormatter.string(from: Date())
        try upsertCustomAlbum(name: name, timestamp: now)
        return try fetchCustomAlbums().first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    func renameCustomAlbum(id: Int64, to rawName: String) throws -> CustomAlbum? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let sql = "UPDATE custom_albums SET name = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, name)
        bind(statement, 2, isoFormatter.string(from: Date()))
        sqlite3_bind_int64(statement, 3, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
        return try fetchCustomAlbums().first { $0.id == id }
    }

    func deleteCustomAlbum(id: Int64) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM custom_albums WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    func addKeyword(_ keyword: String, to itemIDs: [Int64]) throws {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyword.isEmpty, !itemIDs.isEmpty else { return }

        try transaction {
            for id in itemIDs {
                var keywords = try userKeywords(for: id)
                if !keywords.contains(where: { $0.localizedCaseInsensitiveCompare(normalizedKeyword) == .orderedSame }) {
                    keywords.append(normalizedKeyword)
                }
                try updateUserKeywords(keywords, for: id)
            }
        }
    }

    func setUserCaption(_ caption: String, for itemIDs: [Int64]) throws {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        try updateMediaItems(
            sql: "UPDATE media_items SET user_caption = ?, updated_at = ? WHERE id = ?;",
            itemIDs: itemIDs,
            updatedAtIndex: 2,
            itemIDIndex: 3,
            bindValues: { statement in
                bind(statement, 1, trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    func setFavorite(_ isFavorite: Bool, for itemIDs: [Int64]) throws {
        try updateMediaItems(
            sql: "UPDATE media_items SET is_favorite = ?, updated_at = ? WHERE id = ?;",
            itemIDs: itemIDs,
            updatedAtIndex: 2,
            itemIDIndex: 3,
            bindValues: { statement in
                sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
            }
        )
    }

    func setManualLocation(latitude: Double, longitude: Double, city: String?, state: String?, country: String?, for itemIDs: [Int64]) throws {
        let sql = """
        UPDATE media_items
        SET latitude = ?,
            longitude = ?,
            city = ?,
            state = ?,
            country = ?,
            location_source = 'manual',
            user_latitude = ?,
            user_longitude = ?,
            user_city = ?,
            user_state = ?,
            user_country = ?,
            updated_at = ?
        WHERE id = ?;
        """

        try updateMediaItems(sql: sql, itemIDs: itemIDs, updatedAtIndex: 11, itemIDIndex: 12) { statement in
            sqlite3_bind_double(statement, 1, latitude)
            sqlite3_bind_double(statement, 2, longitude)
            bind(statement, 3, city?.nilIfEmpty)
            bind(statement, 4, state?.nilIfEmpty)
            bind(statement, 5, country?.nilIfEmpty)
            sqlite3_bind_double(statement, 6, latitude)
            sqlite3_bind_double(statement, 7, longitude)
            bind(statement, 8, city?.nilIfEmpty)
            bind(statement, 9, state?.nilIfEmpty)
            bind(statement, 10, country?.nilIfEmpty)
        }
    }

    func addItems(
        _ itemIDs: [Int64],
        toCustomAlbumNamed rawName: String
    ) throws -> (album: CustomAlbum, addedCount: Int)? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !itemIDs.isEmpty else { return nil }
        let now = isoFormatter.string(from: Date())
        var addedCount = 0

        try transaction {
            try upsertCustomAlbum(name: name, timestamp: now)
            let albumID = try customAlbumID(named: name)
            for id in itemIDs {
                if try insertCustomAlbumItem(albumID: albumID, mediaItemID: id, timestamp: now) {
                    addedCount += 1
                }
            }
            try touchCustomAlbum(id: albumID, timestamp: now)
        }

        guard let album = try fetchCustomAlbums().first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return nil
        }
        return (album, addedCount)
    }

    func countMedia(searchText: String, filters: SearchFilters) throws -> Int {
        let query = MediaQuery(searchText: searchText, filters: filters)
        let sql = "SELECT COUNT(*) FROM media_items \(query.whereClause);"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in query.values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    func fetchMedia(searchText: String, filters: SearchFilters, limit: Int, offset: Int) throws -> [MediaItem] {
        let query = MediaQuery(searchText: searchText, filters: filters)
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        \(query.whereClause)
        ORDER BY capture_date DESC
        LIMIT ? OFFSET ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in query.values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }
        sqlite3_bind_int(statement, Int32(query.values.count + 1), Int32(limit))
        sqlite3_bind_int(statement, Int32(query.values.count + 2), Int32(offset))

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    func fetchFolderSummaries() throws -> [FolderCatalogueSummary] {
        let sql = """
        SELECT path, name, item_count, photo_count, video_count, newest_capture_date, oldest_capture_date, representative_media_id
        FROM folders
        ORDER BY name COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var folders: [FolderCatalogueSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            folders.append(
                FolderCatalogueSummary(
                    path: textColumn(statement, 0),
                    name: textColumn(statement, 1),
                    itemCount: Int(sqlite3_column_int(statement, 2)),
                    photoCount: Int(sqlite3_column_int(statement, 3)),
                    videoCount: Int(sqlite3_column_int(statement, 4)),
                    newestCaptureDate: dateColumn(statement, 5),
                    oldestCaptureDate: dateColumn(statement, 6),
                    representativeMediaID: optionalInt64Column(statement, 7)
                )
            )
        }
        return folders
    }

    func latestScanSummary() throws -> ScanSummary? {
        let sql = """
        SELECT files_discovered, files_scanned, photos_found, videos_found,
               new_files, already_indexed_files, refreshed_files, missing_files,
               unsupported_files, errors, started_at, completed_at, status
        FROM scan_runs
        ORDER BY id DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return ScanSummary(
            filesDiscovered: Int(sqlite3_column_int(statement, 0)),
            filesScanned: Int(sqlite3_column_int(statement, 1)),
            photosFound: Int(sqlite3_column_int(statement, 2)),
            videosFound: Int(sqlite3_column_int(statement, 3)),
            newFiles: Int(sqlite3_column_int(statement, 4)),
            alreadyIndexedFiles: Int(sqlite3_column_int(statement, 5)),
            refreshedFiles: Int(sqlite3_column_int(statement, 6)),
            missingFiles: Int(sqlite3_column_int(statement, 7)),
            unsupportedFiles: Int(sqlite3_column_int(statement, 8)),
            errors: Int(sqlite3_column_int(statement, 9)),
            startedAt: dateColumn(statement, 10) ?? Date(),
            completedAt: dateColumn(statement, 11),
            status: textColumn(statement, 12)
        )
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS media_items (
          id INTEGER PRIMARY KEY,
          relative_path TEXT NOT NULL UNIQUE,
          folder_path TEXT NOT NULL,
          filename TEXT NOT NULL,
          media_type TEXT NOT NULL,
          live_photo_group_id TEXT,
          capture_date TEXT NOT NULL,
          capture_date_local TEXT NOT NULL,
          date_source TEXT NOT NULL,
          width INTEGER,
          height INTEGER,
          orientation INTEGER,
          duration_seconds REAL,
          file_size INTEGER NOT NULL,
          modified_at TEXT NOT NULL,
          camera_make TEXT,
          camera_model TEXT,
          lens_model TEXT,
          caption TEXT,
          keywords TEXT,
          latitude REAL,
          longitude REAL,
          city TEXT,
          state TEXT,
          country TEXT,
          location_source TEXT NOT NULL,
          thumbnail_path TEXT,
          video_thumbnail_path TEXT,
          is_missing INTEGER NOT NULL DEFAULT 0,
          added_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        """)

        if !columnExists("content_hash", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN content_hash TEXT;")
        }
        if !columnExists("user_keywords", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_keywords TEXT;")
        }
        if !columnExists("user_caption", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_caption TEXT;")
        }
        if !columnExists("is_favorite", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;")
        }
        if !columnExists("user_latitude", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_latitude REAL;")
        }
        if !columnExists("user_longitude", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_longitude REAL;")
        }
        if !columnExists("user_city", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_city TEXT;")
        }
        if !columnExists("user_state", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_state TEXT;")
        }
        if !columnExists("user_country", in: "media_items") {
            try execute("ALTER TABLE media_items ADD COLUMN user_country TEXT;")
        }

        try execute("""
        CREATE TABLE IF NOT EXISTS scan_runs (
          id INTEGER PRIMARY KEY,
          started_at TEXT NOT NULL,
          completed_at TEXT,
          status TEXT NOT NULL,
          files_discovered INTEGER DEFAULT 0,
          files_scanned INTEGER DEFAULT 0,
          photos_found INTEGER DEFAULT 0,
          videos_found INTEGER DEFAULT 0,
          new_files INTEGER DEFAULT 0,
          already_indexed_files INTEGER DEFAULT 0,
          refreshed_files INTEGER DEFAULT 0,
          missing_files INTEGER DEFAULT 0,
          unsupported_files INTEGER DEFAULT 0,
          errors INTEGER DEFAULT 0
        );
        """)
        if !columnExists("new_files", in: "scan_runs") {
            try execute("ALTER TABLE scan_runs ADD COLUMN new_files INTEGER DEFAULT 0;")
        }
        if !columnExists("already_indexed_files", in: "scan_runs") {
            try execute("ALTER TABLE scan_runs ADD COLUMN already_indexed_files INTEGER DEFAULT 0;")
        }
        if !columnExists("refreshed_files", in: "scan_runs") {
            try execute("ALTER TABLE scan_runs ADD COLUMN refreshed_files INTEGER DEFAULT 0;")
        }
        if !columnExists("missing_files", in: "scan_runs") {
            try execute("ALTER TABLE scan_runs ADD COLUMN missing_files INTEGER DEFAULT 0;")
        }

        try execute("""
        CREATE TABLE IF NOT EXISTS folders (
          path TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          parent_path TEXT,
          item_count INTEGER DEFAULT 0,
          photo_count INTEGER DEFAULT 0,
          video_count INTEGER DEFAULT 0,
          newest_capture_date TEXT,
          oldest_capture_date TEXT,
          representative_media_id INTEGER
        );
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS custom_albums (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS custom_album_items (
          album_id INTEGER NOT NULL,
          media_item_id INTEGER NOT NULL,
          added_at TEXT NOT NULL,
          PRIMARY KEY (album_id, media_item_id),
          FOREIGN KEY(album_id) REFERENCES custom_albums(id) ON DELETE CASCADE,
          FOREIGN KEY(media_item_id) REFERENCES media_items(id) ON DELETE CASCADE
        );
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS geocoding_cache (
          key TEXT PRIMARY KEY,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          city TEXT,
          state TEXT,
          country TEXT,
          updated_at TEXT NOT NULL
        );
        """)

        try execute("CREATE INDEX IF NOT EXISTS idx_media_capture_date ON media_items(capture_date);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_folder ON media_items(folder_path);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_filename_nocase ON media_items(filename COLLATE NOCASE);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_file_size ON media_items(file_size);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_type ON media_items(media_type);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_location ON media_items(latitude, longitude);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_added_at ON media_items(added_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_change_detection ON media_items(relative_path, file_size, modified_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_content_hash ON media_items(content_hash);")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_favorite ON media_items(is_favorite);")
        try execute("CREATE INDEX IF NOT EXISTS idx_custom_album_items_media ON custom_album_items(media_item_id);")
    }

    private func upsert(_ item: MediaItem) throws {
        let sql = """
        INSERT INTO media_items (
          relative_path, folder_path, filename, media_type, live_photo_group_id,
          capture_date, capture_date_local, date_source, width, height, orientation,
          duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
          caption, keywords, latitude, longitude, city, state, country, location_source,
          thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, content_hash
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
        ON CONFLICT(relative_path) DO UPDATE SET
          folder_path=excluded.folder_path,
          filename=excluded.filename,
          media_type=excluded.media_type,
          live_photo_group_id=excluded.live_photo_group_id,
          capture_date=excluded.capture_date,
          capture_date_local=excluded.capture_date_local,
          date_source=excluded.date_source,
          width=excluded.width,
          height=excluded.height,
          orientation=excluded.orientation,
          duration_seconds=excluded.duration_seconds,
          file_size=excluded.file_size,
          modified_at=excluded.modified_at,
          camera_make=excluded.camera_make,
          camera_model=excluded.camera_model,
          lens_model=excluded.lens_model,
          caption=excluded.caption,
          keywords=excluded.keywords,
          latitude=COALESCE(media_items.user_latitude, excluded.latitude),
          longitude=COALESCE(media_items.user_longitude, excluded.longitude),
          city=COALESCE(media_items.user_city, excluded.city),
          state=COALESCE(media_items.user_state, excluded.state),
          country=COALESCE(media_items.user_country, excluded.country),
          location_source=CASE
            WHEN media_items.user_latitude IS NOT NULL AND media_items.user_longitude IS NOT NULL THEN 'manual'
            ELSE excluded.location_source
          END,
          thumbnail_path=excluded.thumbnail_path,
          video_thumbnail_path=excluded.video_thumbnail_path,
          is_missing=excluded.is_missing,
          content_hash=NULL,
          updated_at=excluded.updated_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, item.relativePath)
        bind(statement, 2, item.folderPath)
        bind(statement, 3, item.filename)
        bind(statement, 4, item.kind.rawValue)
        bind(statement, 5, item.livePhotoGroupID)
        bind(statement, 6, isoFormatter.string(from: item.captureDate))
        bind(statement, 7, item.captureDateLocalText)
        bind(statement, 8, item.dateSource.rawValue)
        bind(statement, 9, item.width)
        bind(statement, 10, item.height)
        bind(statement, 11, item.orientation)
        bind(statement, 12, item.duration)
        bind(statement, 13, item.fileSize)
        bind(statement, 14, isoFormatter.string(from: item.modifiedAt))
        bind(statement, 15, item.cameraMake)
        bind(statement, 16, item.cameraModel)
        bind(statement, 17, item.lensModel)
        bind(statement, 18, item.caption)
        bind(statement, 19, item.keywords.joined(separator: ","))
        bind(statement, 20, item.latitude)
        bind(statement, 21, item.longitude)
        bind(statement, 22, item.city)
        bind(statement, 23, item.state)
        bind(statement, 24, item.country)
        bind(statement, 25, item.locationSource.rawValue)
        bind(statement, 26, item.thumbnailPath)
        bind(statement, 27, item.videoThumbnailPath)
        sqlite3_bind_int(statement, 28, item.isMissing ? 1 : 0)
        bind(statement, 29, isoFormatter.string(from: item.addedAt))
        bind(statement, 30, isoFormatter.string(from: item.updatedAt))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func delete(relativePath: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM media_items WHERE relative_path = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, relativePath)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func markMissing(relativePaths: [String]) throws {
        guard !relativePaths.isEmpty else { return }
        try setMissing(true, relativePaths: relativePaths)
    }

    private func markAvailable(relativePaths: [String]) throws {
        guard !relativePaths.isEmpty else { return }
        try setMissing(false, relativePaths: relativePaths)
    }

    private func setMissing(_ isMissing: Bool, relativePaths: [String]) throws {
        guard !relativePaths.isEmpty else { return }

        let sql = "UPDATE media_items SET is_missing = ?, updated_at = ? WHERE relative_path = ?;"
        for path in relativePaths {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw CatalogueDatabaseError.prepareFailed(message: lastError)
            }

            sqlite3_bind_int(statement, 1, isMissing ? 1 : 0)
            bind(statement, 2, isoFormatter.string(from: Date()))
            bind(statement, 3, path)

            let stepResult = sqlite3_step(statement)
            sqlite3_finalize(statement)

            guard stepResult == SQLITE_DONE else {
                throw CatalogueDatabaseError.writeFailed(message: lastError)
            }
        }
    }

    private func markLivePhoto(photo: MediaItem, video: MediaItem) throws {
        let sql = """
        UPDATE media_items
        SET media_type = 'livePhoto',
            live_photo_group_id = COALESCE(NULLIF(?, ''), NULLIF(?, ''), live_photo_group_id),
            duration_seconds = ?,
            video_thumbnail_path = ?,
            updated_at = ?
        WHERE relative_path = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, photo.livePhotoGroupID?.nilIfEmpty)
        bind(statement, 2, video.livePhotoGroupID?.nilIfEmpty)
        bind(statement, 3, video.duration)
        bind(statement, 4, video.videoThumbnailPath)
        bind(statement, 5, isoFormatter.string(from: Date()))
        bind(statement, 6, photo.relativePath)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func insert(_ summary: ScanSummary) throws {
        let sql = """
        INSERT INTO scan_runs (
          started_at, completed_at, status, files_discovered, files_scanned,
          photos_found, videos_found, new_files, already_indexed_files,
          refreshed_files, missing_files, unsupported_files, errors
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, isoFormatter.string(from: summary.startedAt))
        bind(statement, 2, summary.completedAt.map { isoFormatter.string(from: $0) })
        bind(statement, 3, summary.status)
        sqlite3_bind_int(statement, 4, Int32(summary.filesDiscovered))
        sqlite3_bind_int(statement, 5, Int32(summary.filesScanned))
        sqlite3_bind_int(statement, 6, Int32(summary.photosFound))
        sqlite3_bind_int(statement, 7, Int32(summary.videosFound))
        sqlite3_bind_int(statement, 8, Int32(summary.newFiles))
        sqlite3_bind_int(statement, 9, Int32(summary.alreadyIndexedFiles))
        sqlite3_bind_int(statement, 10, Int32(summary.refreshedFiles))
        sqlite3_bind_int(statement, 11, Int32(summary.missingFiles))
        sqlite3_bind_int(statement, 12, Int32(summary.unsupportedFiles))
        sqlite3_bind_int(statement, 13, Int32(summary.errors))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func rebuildFolders() throws {
        try execute("DELETE FROM folders;")
        try execute("""
        INSERT INTO folders (path, name, parent_path, item_count, photo_count, video_count, newest_capture_date, oldest_capture_date, representative_media_id)
        SELECT
          folder_path,
          CASE WHEN folder_path = '' THEN 'Media Folder' ELSE substr(folder_path, length(rtrim(folder_path, replace(folder_path, '/', ''))) + 1) END,
          NULL,
          COUNT(*),
          SUM(CASE WHEN media_type IN ('photo', 'livePhoto') THEN 1 ELSE 0 END),
          SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END),
          MAX(capture_date),
          MIN(capture_date),
          MIN(id)
        FROM media_items
        GROUP BY folder_path;
        """)
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try work()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastError
            sqlite3_free(errorMessage)
            throw CatalogueDatabaseError.writeFailed(message: message)
        }
    }

    private func columnExists(_ columnName: String, in tableName: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(tableName));", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if textColumn(statement, 1) == columnName {
                return true
            }
        }

        return false
    }

    private func countMedia(whereClause: String, values: [String] = []) throws -> Int {
        let sql = "SELECT COUNT(*) FROM media_items WHERE \(whereClause);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func fetchCameraModelSmartAlbums(limit: Int = 8) throws -> [SmartAlbum] {
        let sql = """
        SELECT COALESCE(camera_make, ''), COALESCE(camera_model, ''), COUNT(*)
        FROM media_items
        WHERE camera_model IS NOT NULL AND TRIM(camera_model) != ''
        GROUP BY COALESCE(camera_make, ''), COALESCE(camera_model, '')
        ORDER BY COUNT(*) DESC, COALESCE(camera_model, '') COLLATE NOCASE ASC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var albums: [SmartAlbum] = []
        var index = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let make = textColumn(statement, 0)
            let model = textColumn(statement, 1)
            let count = Int(sqlite3_column_int(statement, 2))
            let kind = SmartAlbumKind.cameraModel(make: make, model: model)
            let title = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
            albums.append(
                SmartAlbum(
                    id: kind.id,
                    title: title.isEmpty ? "Camera Model" : title,
                    subtitle: "Captured on this camera",
                    systemImage: "camera.aperture",
                    kind: kind,
                    itemCount: count,
                    sortPriority: 100 + index
                )
            )
            index += 1
        }
        return albums
    }

    private func fetchTripSmartAlbums(limit: Int = 8) throws -> [SmartAlbum] {
        let sql = """
        SELECT COALESCE(city, ''), COALESCE(state, ''), COALESCE(country, ''), COUNT(*), MAX(capture_date)
        FROM media_items
        WHERE (
            (city IS NOT NULL AND TRIM(city) != '')
            OR (state IS NOT NULL AND TRIM(state) != '')
            OR (country IS NOT NULL AND TRIM(country) != '')
        )
        GROUP BY COALESCE(city, ''), COALESCE(state, ''), COALESCE(country, '')
        HAVING COUNT(*) >= 2
        ORDER BY MAX(capture_date) DESC, COUNT(*) DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var albums: [SmartAlbum] = []
        var index = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let city = textColumn(statement, 0)
            let state = textColumn(statement, 1)
            let country = textColumn(statement, 2)
            let count = Int(sqlite3_column_int(statement, 3))
            let title = [city, state, country].filter { !$0.isEmpty }.joined(separator: ", ")
            let kind = SmartAlbumKind.trip(city: city, state: state, country: country)
            albums.append(
                SmartAlbum(
                    id: kind.id,
                    title: title.isEmpty ? "Trip" : title,
                    subtitle: "Location-based travel group",
                    systemImage: "map",
                    kind: kind,
                    itemCount: count,
                    sortPriority: 300 + index
                )
            )
            index += 1
        }
        return albums
    }

    private func fetchCustomAlbumSmartAlbums() throws -> [SmartAlbum] {
        try fetchCustomAlbums().enumerated().map { index, album in
            let kind = SmartAlbumKind.customAlbum(id: album.id)
            return SmartAlbum(
                id: kind.id,
                title: album.name,
                subtitle: album.itemCount == 0 ? "Add selected items from the Inspector" : "Album you created",
                systemImage: "rectangle.stack",
                kind: kind,
                itemCount: album.itemCount,
                sortPriority: 600 + index
            )
        }
    }

    private func updateMediaItems(
        sql: String,
        itemIDs: [Int64],
        updatedAtIndex: Int32,
        itemIDIndex: Int32,
        bindValues: (OpaquePointer?) -> Void
    ) throws {
        guard !itemIDs.isEmpty else { return }
        try transaction {
            for id in itemIDs {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw CatalogueDatabaseError.prepareFailed(message: lastError)
                }
                defer { sqlite3_finalize(statement) }

                bindValues(statement)
                bind(statement, updatedAtIndex, isoFormatter.string(from: Date()))
                sqlite3_bind_int64(statement, itemIDIndex, id)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw CatalogueDatabaseError.writeFailed(message: lastError)
                }
            }
        }
    }

    private func userKeywords(for id: Int64) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT user_keywords FROM media_items WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return [] }
        return textColumn(statement, 0)
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateUserKeywords(_ keywords: [String], for id: Int64) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE media_items SET user_keywords = ?, updated_at = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, keywords.isEmpty ? nil : keywords.joined(separator: ","))
        bind(statement, 2, isoFormatter.string(from: Date()))
        sqlite3_bind_int64(statement, 3, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func upsertCustomAlbum(name: String, timestamp: String) throws {
        let sql = """
        INSERT INTO custom_albums (name, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET updated_at=excluded.updated_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, name)
        bind(statement, 2, timestamp)
        bind(statement, 3, timestamp)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func customAlbumID(named name: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM custom_albums WHERE name = ? COLLATE NOCASE LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, name)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CatalogueDatabaseError.writeFailed(message: "Custom album was not created.")
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func insertCustomAlbumItem(albumID: Int64, mediaItemID: Int64, timestamp: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO custom_album_items (album_id, media_item_id, added_at) VALUES (?, ?, ?);", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, albumID)
        sqlite3_bind_int64(statement, 2, mediaItemID)
        bind(statement, 3, timestamp)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
        return sqlite3_changes(db) > 0
    }

    private func touchCustomAlbum(id: Int64, timestamp: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE custom_albums SET updated_at = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, timestamp)
        sqlite3_bind_int64(statement, 2, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogueDatabaseError.writeFailed(message: lastError)
        }
    }

    private func smartAlbumQuery(album: SmartAlbum, filter: TimelineQuickFilter, year: Int?) -> (whereClause: String, values: [String]) {
        let timelineQuery = TimelineQuery(filter: filter, year: year)
        var clauses = [album.kind.whereClause]
        if !timelineQuery.conditionClause.isEmpty {
            clauses.append(timelineQuery.conditionClause)
        }
        return (
            "WHERE " + clauses.map { "(\($0))" }.joined(separator: " AND "),
            album.kind.values + timelineQuery.values
        )
    }

    private func fetchMedia(sql: String, values: [String] = [], limit: Int, offset: Int) throws -> [MediaItem] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            bind(statement, Int32(index + 1), value)
        }
        sqlite3_bind_int(statement, Int32(values.count + 1), Int32(limit))
        sqlite3_bind_int(statement, Int32(values.count + 2), Int32(offset))

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    private func fetchAllMediaItemsForPairing() throws -> [MediaItem] {
        let sql = """
        SELECT id, relative_path, folder_path, filename, media_type, live_photo_group_id,
               capture_date, capture_date_local, date_source, width, height, orientation,
               duration_seconds, file_size, modified_at, camera_make, camera_model, lens_model,
               caption, keywords, latitude, longitude, city, state, country, location_source,
               thumbnail_path, video_thumbnail_path, is_missing, added_at, updated_at, user_keywords, user_caption, is_favorite
        FROM media_items
        WHERE media_type IN ('photo', 'video', 'livePhoto')
        ORDER BY folder_path COLLATE NOCASE ASC, filename COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogueDatabaseError.prepareFailed(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(readMediaItem(from: statement))
        }
        return items
    }

    private func readMediaItem(from statement: OpaquePointer?) -> MediaItem {
        let fileKeywords = textColumn(statement, 19)
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let userKeywords = optionalTextColumn(statement, 31)?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        var keywordSet = Set<String>()
        let keywords = (fileKeywords + userKeywords).filter { keyword in
            keywordSet.insert(keyword.localizedLowercase).inserted
        }

        return MediaItem(
            id: sqlite3_column_int64(statement, 0),
            relativePath: textColumn(statement, 1),
            folderPath: textColumn(statement, 2),
            filename: textColumn(statement, 3),
            kind: MediaKind(rawValue: textColumn(statement, 4)) ?? .photo,
            livePhotoGroupID: optionalTextColumn(statement, 5),
            captureDate: dateColumn(statement, 6) ?? Date(),
            captureDateLocalText: textColumn(statement, 7),
            dateSource: DateSource(rawValue: textColumn(statement, 8)) ?? .unknown,
            width: optionalIntColumn(statement, 9),
            height: optionalIntColumn(statement, 10),
            orientation: optionalIntColumn(statement, 11),
            duration: optionalDoubleColumn(statement, 12),
            fileSize: sqlite3_column_int64(statement, 13),
            modifiedAt: dateColumn(statement, 14) ?? Date(),
            cameraMake: optionalTextColumn(statement, 15),
            cameraModel: optionalTextColumn(statement, 16),
            lensModel: optionalTextColumn(statement, 17),
            caption: optionalTextColumn(statement, 32) ?? optionalTextColumn(statement, 18),
            keywords: keywords,
            latitude: optionalDoubleColumn(statement, 20),
            longitude: optionalDoubleColumn(statement, 21),
            city: optionalTextColumn(statement, 22),
            state: optionalTextColumn(statement, 23),
            country: optionalTextColumn(statement, 24),
            locationSource: LocationSource(rawValue: textColumn(statement, 25)) ?? .none,
            thumbnailPath: optionalTextColumn(statement, 26),
            videoThumbnailPath: optionalTextColumn(statement, 27),
            isMissing: sqlite3_column_int(statement, 28) == 1,
            isFavorite: sqlite3_column_int(statement, 33) == 1,
            addedAt: dateColumn(statement, 29) ?? Date(),
            updatedAt: dateColumn(statement, 30) ?? Date()
        )
    }

    private var lastError: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(statement, index, value)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func optionalTextColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return textColumn(statement, index)
    }

    private func optionalIntColumn(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func optionalInt64Column(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func optionalDoubleColumn(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func dateColumn(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        optionalTextColumn(statement, index).flatMap { isoFormatter.date(from: $0) }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct LivePhotoRepairPair {
    let photo: MediaItem
    let video: MediaItem
}

private func livePhotoRepairPairs(from items: [MediaItem]) -> [LivePhotoRepairPair] {
    var pairs: [LivePhotoRepairPair] = []
    var consumedPhotoPaths = Set<String>()
    var consumedVideoPaths = Set<String>()

    let groupedByIdentifier = Dictionary(
        grouping: items.filter { $0.livePhotoGroupID?.nilIfEmpty != nil },
        by: { $0.livePhotoGroupID ?? "" }
    )

    for groupItems in groupedByIdentifier.values {
        guard let photo = groupItems.first(where: { $0.kind == .photo || $0.kind == .livePhoto }),
              let video = groupItems.first(where: { $0.kind == .video }),
              !consumedPhotoPaths.contains(photo.relativePath),
              !consumedVideoPaths.contains(video.relativePath) else {
            continue
        }

        pairs.append(LivePhotoRepairPair(photo: photo, video: video))
        consumedPhotoPaths.insert(photo.relativePath)
        consumedVideoPaths.insert(video.relativePath)
    }

    var videosByStem = Dictionary(
        grouping: items.filter { item in
            item.kind == .video
                && !consumedVideoPaths.contains(item.relativePath)
                && item.livePhotoFallbackVideoCandidate
        },
        by: { $0.livePhotoStemKey }
    )

    for photo in items where (photo.kind == .photo || photo.kind == .livePhoto)
        && !consumedPhotoPaths.contains(photo.relativePath)
        && photo.livePhotoFallbackPhotoCandidate {
        let key = photo.livePhotoStemKey
        guard let candidate = videosByStem[key]?.min(by: { lhs, rhs in
            abs(lhs.captureDate.timeIntervalSince(photo.captureDate)) < abs(rhs.captureDate.timeIntervalSince(photo.captureDate))
        }) else {
            continue
        }

        pairs.append(LivePhotoRepairPair(photo: photo, video: candidate))
        consumedPhotoPaths.insert(photo.relativePath)
        consumedVideoPaths.insert(candidate.relativePath)
        videosByStem[key]?.removeAll { $0.relativePath == candidate.relativePath }
    }

    return pairs
}

private extension MediaItem {
    var livePhotoStemKey: String {
        let path = NSString(string: relativePath)
        let folder = path.deletingLastPathComponent == "." ? "" : path.deletingLastPathComponent
        let filename = NSString(string: path.lastPathComponent)
        let stem = filename.deletingPathExtension.localizedLowercase
        return folder.isEmpty ? stem : folder + "/" + stem
    }

    var livePhotoFallbackPhotoCandidate: Bool {
        ["heic", "heif", "jpg", "jpeg"].contains(fileExtension)
    }

    var livePhotoFallbackVideoCandidate: Bool {
        fileExtension == "mov"
    }

    private var fileExtension: String {
        NSString(string: relativePath).pathExtension.localizedLowercase
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension TimelineSortOption {
    var orderClause: String {
        switch self {
        case .captureNewest:
            return "capture_date DESC, id DESC"
        case .captureOldest:
            return "capture_date ASC, id ASC"
        case .recentlyAdded:
            return "added_at DESC, id DESC"
        case .fileName:
            return "filename COLLATE NOCASE ASC, capture_date DESC, id DESC"
        case .largestFile:
            return "file_size DESC, capture_date DESC, id DESC"
        }
    }
}

private struct TimelineQuery {
    let whereClause: String
    let conditionClause: String
    let values: [String]

    init(filter: TimelineQuickFilter, year: Int?) {
        var clauses: [String] = []
        var values: [String] = []

        switch filter {
        case .all:
            break
        case .photos:
            clauses.append("media_type IN ('photo', 'livePhoto')")
        case .videos:
            clauses.append("media_type = 'video'")
        case .withLocation:
            clauses.append("(latitude IS NOT NULL AND longitude IS NOT NULL)")
        case .withoutLocation:
            clauses.append("(latitude IS NULL OR longitude IS NULL)")
        }

        if let year {
            clauses.append("substr(capture_date, 1, 4) = ?")
            values.append(String(year))
        }

        conditionClause = clauses.joined(separator: " AND ")
        whereClause = clauses.isEmpty ? "" : "WHERE " + conditionClause
        self.values = values
    }
}

private extension SmartAlbumKind {
    var id: String {
        switch self {
        case .screenshots:
            return "screenshots"
        case .largeVideos:
            return "large-videos"
        case .recentlyEdited:
            return "recently-edited"
        case .missingLocation:
            return "missing-location"
        case .favorites:
            return "favorites"
        case .cameraModel(let make, let model):
            return "camera:" + [make, model].joined(separator: ":").lowercased()
        case .trip(let city, let state, let country):
            return "trip:" + [city, state, country].joined(separator: ":").lowercased()
        case .customAlbum(let id):
            return "custom-album:\(id)"
        case .people:
            return "people"
        }
    }

    var whereClause: String {
        switch self {
        case .screenshots:
            return """
            (
              lower(filename) LIKE 'screenshot%'
              OR lower(filename) LIKE 'screen shot%'
              OR lower(relative_path) LIKE '%/screenshots/%'
              OR lower(relative_path) LIKE '%/screen shots/%'
              OR lower(folder_path) LIKE '%screenshot%'
            )
            """
        case .largeVideos:
            return "media_type = 'video' AND file_size >= 209715200"
        case .recentlyEdited:
            return """
            (
              lower(filename) LIKE '%edited%'
              OR lower(filename) LIKE '%edit%'
              OR lower(filename) LIKE '%export%'
              OR lower(folder_path) LIKE '%edited%'
              OR lower(folder_path) LIKE '%exports%'
              OR (
                date_source != 'filesystemModified'
                AND julianday(modified_at) - julianday(capture_date) >= 1
              )
            )
            """
        case .missingLocation:
            return "(latitude IS NULL OR longitude IS NULL)"
        case .favorites:
            return "is_favorite = 1"
        case .cameraModel:
            return "COALESCE(camera_make, '') = ? AND COALESCE(camera_model, '') = ?"
        case .trip(let city, let state, let country):
            var clauses: [String] = []
            if city.isEmpty {
                clauses.append("(city IS NULL OR TRIM(city) = '')")
            } else {
                clauses.append("city = ?")
            }
            if state.isEmpty {
                clauses.append("(state IS NULL OR TRIM(state) = '')")
            } else {
                clauses.append("state = ?")
            }
            if country.isEmpty {
                clauses.append("(country IS NULL OR TRIM(country) = '')")
            } else {
                clauses.append("country = ?")
            }
            return clauses.joined(separator: " AND ")
        case .customAlbum:
            return "EXISTS (SELECT 1 FROM custom_album_items WHERE custom_album_items.media_item_id = media_items.id AND custom_album_items.album_id = ?)"
        case .people:
            return "0"
        }
    }

    var values: [String] {
        switch self {
        case .cameraModel(let make, let model):
            return [make, model]
        case .trip(let city, let state, let country):
            return [city, state, country].filter { !$0.isEmpty }
        case .customAlbum(let id):
            return [String(id)]
        default:
            return []
        }
    }

    var orderClause: String {
        switch self {
        case .largeVideos:
            return "file_size DESC, capture_date DESC, id DESC"
        case .recentlyEdited:
            return "modified_at DESC, capture_date DESC, id DESC"
        default:
            return "capture_date DESC, id DESC"
        }
    }
}

private struct MediaQuery {
    let whereClause: String
    let values: [String]

    init(searchText: String, filters: SearchFilters) {
        var clauses: [String] = []
        var values: [String] = []
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedSearch.isEmpty {
            clauses.append("""
            (
              lower(filename) LIKE ?
              OR lower(folder_path) LIKE ?
              OR lower(capture_date) LIKE ?
              OR lower(capture_date_local) LIKE ?
              OR lower(COALESCE(caption, '')) LIKE ?
              OR lower(COALESCE(keywords, '')) LIKE ?
              OR lower(COALESCE(city, '')) LIKE ?
              OR lower(COALESCE(state, '')) LIKE ?
              OR lower(COALESCE(country, '')) LIKE ?
              OR lower(COALESCE(camera_make, '') || ' ' || COALESCE(camera_model, '')) LIKE ?
              OR lower(media_type) LIKE ?
            )
            """)
            let likeValue = "%\(trimmedSearch.localizedLowercase)%"
            values.append(contentsOf: Array(repeating: likeValue, count: 11))
        }

        if filters.photosOnly || filters.videosOnly {
            var typeClauses: [String] = []
            if filters.photosOnly {
                typeClauses.append("media_type IN ('photo', 'livePhoto')")
            }
            if filters.videosOnly {
                typeClauses.append("media_type = 'video'")
            }
            clauses.append("(" + typeClauses.joined(separator: " OR ") + ")")
        }

        whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        self.values = values
    }
}

struct FileFingerprint: Equatable {
    let fileSize: Int64
    let modifiedAt: Date
}

enum CatalogueDatabaseError: LocalizedError {
    case openFailed(message: String)
    case prepareFailed(message: String)
    case writeFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): "Could not open catalogue: \(message)"
        case .prepareFailed(let message): "Could not prepare catalogue query: \(message)"
        case .writeFailed(let message): "Could not write catalogue: \(message)"
        }
    }
}
