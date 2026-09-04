import Foundation

struct SavedCatalogue: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var path: String
    var bookmarkData: Data?
    var cataloguesDirectoryBookmarkData: Data?
    var lastOpenedAt: Date
    var sources: [CatalogueSource]?

    var hasSavedPermission: Bool {
        if isNamedCatalogue {
            return true
        }
        return bookmarkData != nil || cataloguesDirectoryBookmarkData != nil || sourceList.contains(where: { $0.bookmarkData != nil })
    }

    var isNamedCatalogue: Bool {
        sources != nil
    }

    var sourceList: [CatalogueSource] {
        if let sources {
            return sources
        }

        return [
            CatalogueSource(
                id: path,
                name: URL(fileURLWithPath: path, isDirectory: true).lastPathComponent,
                rootPath: path,
                relativePrefix: "",
                bookmarkData: bookmarkData,
                addedAt: lastOpenedAt,
                lastScannedAt: nil
            )
        ]
    }

    var databaseURL: URL {
        return CataloguePaths(rootURL: URL(fileURLWithPath: path, isDirectory: true)).databaseURL
    }

    var catalogueDirectoryURL: URL {
        return CataloguePaths(rootURL: URL(fileURLWithPath: path, isDirectory: true)).catalogueDirectory
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case bookmarkData
        case cataloguesDirectoryBookmarkData
        case lastOpenedAt
        case sources
    }

    init(
        id: String,
        name: String,
        path: String,
        bookmarkData: Data?,
        cataloguesDirectoryBookmarkData: Data? = nil,
        lastOpenedAt: Date,
        sources: [CatalogueSource]? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.cataloguesDirectoryBookmarkData = cataloguesDirectoryBookmarkData
        self.lastOpenedAt = lastOpenedAt
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        cataloguesDirectoryBookmarkData = try container.decodeIfPresent(Data.self, forKey: .cataloguesDirectoryBookmarkData)
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        sources = try container.decodeIfPresent([CatalogueSource].self, forKey: .sources)
    }
}

struct CatalogueSource: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var rootPath: String
    var relativePrefix: String
    var bookmarkData: Data?
    var addedAt: Date
    var lastScannedAt: Date?

    var rootURL: URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    var isReachable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

struct SecurityScopedBookmarkStore {
    private let key = "DriveLens.selectedMediaRootBookmark"
    private let cataloguesKey = "DriveLens.savedCatalogues"
    private let activeCatalogueKey = "DriveLens.activeCatalogueID"

    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
        saveCatalogue(url: url, bookmarkData: data)
    }

    func loadBookmark() -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    func saveActiveCatalogueID(_ id: String?) {
        if let id {
            UserDefaults.standard.set(id, forKey: activeCatalogueKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeCatalogueKey)
        }
    }

    func loadActiveCatalogueID() -> String? {
        UserDefaults.standard.string(forKey: activeCatalogueKey)
    }

    func loadSavedCatalogues() -> [SavedCatalogue] {
        var merged: [String: SavedCatalogue] = [:]

        if let data = UserDefaults.standard.data(forKey: cataloguesKey),
           let catalogues = try? JSONDecoder().decode([SavedCatalogue].self, from: data) {
            for catalogue in catalogues {
                merged[catalogue.id] = catalogue
            }
        }

        for catalogue in discoverMountedCatalogues() where merged[catalogue.id] == nil {
            merged[catalogue.id] = catalogue
        }

        return merged.values.sorted {
            if $0.hasSavedPermission != $1.hasSavedPermission {
                return $0.hasSavedPermission
            }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
    }

    func removeSavedCatalogue(id: String) {
        let catalogues = loadSavedCatalogues().filter { $0.id != id }
        persistSavedCatalogues(catalogues)
        if loadActiveCatalogueID() == id {
            saveActiveCatalogueID(nil)
        }
    }

    func savedCatalogue(id: String) -> SavedCatalogue? {
        loadSavedCatalogues().first { $0.id == id }
    }

    @discardableResult
    func renameCatalogue(id: String, to rawName: String) -> SavedCatalogue? {
        var catalogues = loadSavedCatalogues()
        guard let index = catalogues.firstIndex(where: { $0.id == id }) else { return nil }
        catalogues[index].name = sanitizedCatalogueName(rawName)
        catalogues[index].lastOpenedAt = Date()
        persistSavedCatalogues(catalogues)
        return catalogues[index]
    }

    func deleteCatalogue(id: String, removingStoredData: Bool) throws {
        guard let catalogue = savedCatalogue(id: id) else { return }

        guard removingStoredData else {
            removeSavedCatalogue(id: id)
            return
        }
        let removableURL = try removableCatalogueURL(for: catalogue)

        try withCatalogueStorageAccess(for: catalogue) {
            if FileManager.default.fileExists(atPath: removableURL.path) {
                try FileManager.default.removeItem(at: removableURL)
            }
        }

        removeSavedCatalogue(id: id)
    }

    private func resolvedCatalogueStorageURL(for catalogue: SavedCatalogue) throws -> URL? {
        guard let bookmarkData = catalogue.bookmarkData else { return nil }
        var stale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private func removableCatalogueURL(for catalogue: SavedCatalogue) throws -> URL {
        if catalogue.isNamedCatalogue {
            return try resolvedCatalogueStorageURL(for: catalogue)
                ?? URL(fileURLWithPath: catalogue.path, isDirectory: true)
        }

        if let resolvedRootURL = try resolvedCatalogueStorageURL(for: catalogue) {
            return CataloguePaths(rootURL: resolvedRootURL).catalogueDirectory
        }

        return catalogue.catalogueDirectoryURL
    }

    private func withCatalogueStorageAccess<T>(for catalogue: SavedCatalogue, operation: () throws -> T) throws -> T {
        guard let url = try resolvedCatalogueMutationAccessURL(for: catalogue) else {
            return try operation()
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

    private func resolvedCatalogueMutationAccessURL(for catalogue: SavedCatalogue) throws -> URL? {
        guard let bookmarkData = catalogue.cataloguesDirectoryBookmarkData ?? catalogue.bookmarkData else {
            return nil
        }

        var stale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: activeCatalogueKey)
    }

    func storedBookmarkByteCount() -> Int64 {
        let selectedBookmarkBytes = UserDefaults.standard.data(forKey: key)?.count ?? 0
        let savedCataloguesBytes = UserDefaults.standard.data(forKey: cataloguesKey)?.count ?? 0
        return Int64(selectedBookmarkBytes + savedCataloguesBytes)
    }

    func createCatalogue(named rawName: String) throws -> SavedCatalogue {
        try createCatalogue(named: rawName, storageRootURL: nil)
    }

    func createCatalogue(named rawName: String, storageRootURL: URL?) throws -> SavedCatalogue {
        let name = sanitizedCatalogueName(rawName)
        let id = UUID().uuidString
        let directory = try catalogueDirectory(id: id, storageRootURL: storageRootURL)
        let cataloguesDirectory = directory.deletingLastPathComponent()
        let catalogue = SavedCatalogue(
            id: id,
            name: name,
            path: directory.path,
            bookmarkData: try? directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ),
            cataloguesDirectoryBookmarkData: try? cataloguesDirectory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ),
            lastOpenedAt: Date(),
            sources: []
        )
        try CataloguePaths(rootURL: directory).prepare()
        saveCatalogue(catalogue)
        saveActiveCatalogueID(id)
        return catalogue
    }

    func saveCatalogue(_ catalogue: SavedCatalogue) {
        var catalogues = loadSavedCatalogues().filter { $0.id != catalogue.id }
        var updated = catalogue
        updated.lastOpenedAt = Date()
        catalogues.insert(updated, at: 0)
        persistSavedCatalogues(Array(catalogues.prefix(20)))
    }

    func addSources(_ urls: [URL], to catalogue: SavedCatalogue) throws -> SavedCatalogue {
        guard catalogue.isNamedCatalogue else { return catalogue }

        var updated = catalogue
        var sources = catalogue.sourceList
        var usedPrefixes = Set(sources.map(\.relativePrefix))
        var seenPaths = Set(sources.map(\.rootPath))

        for url in urls.map(\.standardizedFileURL) {
            let path = url.path
            guard seenPaths.insert(path).inserted else { continue }
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let prefix = uniquePrefix(base: url.lastPathComponent, usedPrefixes: &usedPrefixes)
            sources.append(
                CatalogueSource(
                    id: UUID().uuidString,
                    name: url.lastPathComponent,
                    rootPath: path,
                    relativePrefix: prefix,
                    bookmarkData: bookmark,
                    addedAt: Date(),
                    lastScannedAt: nil
                )
            )
        }

        updated.sources = sources
        saveCatalogue(updated)
        return updated
    }

    private func saveCatalogue(url: URL, bookmarkData: Data) {
        let standardizedPath = url.standardizedFileURL.path
        var catalogues = loadSavedCatalogues().filter { $0.id != standardizedPath }
        catalogues.insert(
            SavedCatalogue(
                id: standardizedPath,
                name: url.lastPathComponent,
                path: standardizedPath,
                bookmarkData: bookmarkData,
                lastOpenedAt: Date(),
                sources: nil
            ),
            at: 0
        )
        persistSavedCatalogues(Array(catalogues.prefix(8)))
    }

    private func persistSavedCatalogues(_ catalogues: [SavedCatalogue]) {
        let persistentCatalogues = catalogues.filter { $0.isNamedCatalogue || $0.hasSavedPermission }
        guard let data = try? JSONEncoder().encode(persistentCatalogues) else { return }
        UserDefaults.standard.set(data, forKey: cataloguesKey)
    }

    private func discoverMountedCatalogues() -> [SavedCatalogue] {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard let volumeURLs = try? FileManager.default.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [URL] = []
        for volumeURL in volumeURLs where isDirectory(volumeURL) {
            candidates.append(volumeURL)

            if let childURLs = try? FileManager.default.contentsOfDirectory(
                at: volumeURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                candidates.append(contentsOf: childURLs.filter(isDirectory))
            }
        }

        var seen = Set<String>()
        return candidates.compactMap { rootURL in
            let standardizedURL = rootURL.standardizedFileURL
            let path = standardizedURL.path
            guard seen.insert(path).inserted else { return nil }

            let databaseURL = CataloguePaths(rootURL: standardizedURL).databaseURL
            guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

            let modificationDate = (try? FileManager.default.attributesOfItem(atPath: databaseURL.path)[.modificationDate] as? Date) ?? Date.distantPast
            return SavedCatalogue(
                id: path,
                name: standardizedURL.lastPathComponent,
                path: path,
                bookmarkData: nil,
                lastOpenedAt: modificationDate,
                sources: nil
            )
        }
    }

    private func applicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("DriveLens/Catalogues", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func catalogueDirectory(id: String, storageRootURL: URL?) throws -> URL {
        let directory: URL
        if let storageRootURL {
            directory = storageRootURL
                .standardizedFileURL
                .appendingPathComponent(".drivelens", isDirectory: true)
                .appendingPathComponent("catalogues", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
        } else {
            directory = try applicationSupportDirectory().appendingPathComponent(id, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sanitizedCatalogueName(_ rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Catalogue" : name
    }

    private func uniquePrefix(base: String, usedPrefixes: inout Set<String>) -> String {
        let cleanBase = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let prefixBase = cleanBase.isEmpty ? "Media Folder" : cleanBase

        var candidate = prefixBase
        var index = 2
        while usedPrefixes.contains(candidate) {
            candidate = "\(cleanBase) \(index)"
            index += 1
        }
        usedPrefixes.insert(candidate)
        return candidate
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
