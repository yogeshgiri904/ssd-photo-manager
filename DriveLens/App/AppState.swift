import AppKit
import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRootURL: URL?
    @Published var activeCatalogue: SavedCatalogue?
    @Published var hasCompletedOnboarding = false
    @Published var ssdStatus: SSDStatus = .notSelected
    @Published var selectedSection: SidebarSection = .timeline
    @Published var mediaItems: [MediaItem] = []
    @Published var videoItems: [MediaItem] = []
    @Published var recentlyAddedItems: [MediaItem] = []
    @Published var placeItems: [MediaItem] = []
    @Published var placeClusters: [PlaceCluster] = []
    @Published var selectedPlaceClusterID: PlaceCluster.ID?
    @Published var searchItems: [MediaItem] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var smartAlbums: [SmartAlbum] = []
    @Published var customAlbums: [CustomAlbum] = []
    @Published var selectedSmartAlbumID: SmartAlbum.ID?
    @Published var smartAlbumItems: [MediaItem] = []
    @Published var isLoadingSmartAlbum = false
    @Published var smartAlbumQuickFilter: TimelineQuickFilter = .all
    @Published var smartAlbumSort: TimelineSortOption = .captureNewest
    @Published var selectedSmartAlbumYear: Int?
    @Published var smartAlbumYears: [Int] = []
    @Published var smartAlbumCounts: CatalogueCounts = .zero
    @Published var smartAlbumScopeCounts: CatalogueCounts = .zero
    @Published var smartAlbumResultCount = 0
    @Published var folderSummaries: [FolderCatalogueSummary] = []
    @Published var selectedMediaItem: MediaItem?
    @Published var showingViewer = false
    @Published var showingInspector = true
    @Published var gridSize: Double = 132
    @Published var timelineQuickFilter: TimelineQuickFilter = .all
    @Published var timelineSort: TimelineSortOption = .captureNewest
    @Published var selectedTimelineYear: Int?
    @Published var timelineYears: [Int] = []
    @Published var timelineCounts: CatalogueCounts = .zero
    @Published var timelineScopeCounts: CatalogueCounts = .zero
    @Published var timelineResultCount = 0
    @Published var recentlyAddedQuickFilter: TimelineQuickFilter = .all
    @Published var recentlyAddedSort: TimelineSortOption = .recentlyAdded
    @Published var selectedRecentlyAddedYear: Int?
    @Published var recentlyAddedYears: [Int] = []
    @Published var recentlyAddedCounts: CatalogueCounts = .zero
    @Published var recentlyAddedScopeCounts: CatalogueCounts = .zero
    @Published var recentlyAddedResultCount = 0
    @Published var searchText = ""
    @Published var activeFilters = SearchFilters()
    @Published var focusedFolderPath: String?
    @Published var scanProgress: ScanProgress?
    @Published var scanSummary: ScanSummary?
    @Published var catalogueCounts: CatalogueCounts = .zero
    @Published var duplicateGroupCount = 0
    @Published var selectedDuplicateGroupID: DuplicateGroup.ID?
    @Published var isFindingDuplicates = false
    @Published var duplicateScanStatus = ""
    @Published var appStorageReport: AppStorageReport = .empty
    @Published var isLoadingAppStorageReport = false
    @Published var isClearingAppCaches = false
    @Published var isCompactingCatalogue = false
    @Published var searchResultCount = 0
    @Published var userMessage: String?
    @Published var actionNotice: String?
    @Published var showingResetConfirmation = false
    @Published var showingRescanConfirmation = false
    @Published var pendingDeleteItem: MediaItem?
    @Published var savedCatalogues: [SavedCatalogue] = []
    @Published var selectedMediaItemIDs = Set<Int64>()
    @Published var isSelectionModeEnabled = false
    @Published var pendingBatchDeleteItems: [MediaItem] = []
    @Published var pendingBatchDeleteContext: BatchDeleteContext = .selection
    @Published var renameItems: [MediaItem] = []
    @Published var showingRenameSheet = false
    @Published var mediaMutationRevision = 0
    @Published var showingMissingRepairSheet = false
    @Published var missingRepairCandidates: [MissingFolderRepairCandidate] = []
    @Published var selectedMissingRepairCandidateID: MissingFolderRepairCandidate.ID?
    @Published var isRepairingMissingFiles = false

    private let bookmarkStore = SecurityScopedBookmarkStore()
    private var database: CatalogueDatabase?
    private var accessURL: URL?
    private var isAccessingSecurityScope = false
    private var sourceAccessURLs: [URL] = []
    private var catalogueAccessURL: URL?
    private var scanTask: Task<Void, Never>?
    private var isLoadingPage = false
    private var lastSelectedMediaItemID: Int64?
    private var visibleSelectionScopeItems: [MediaItem] = []
    private var actionNoticeTask: Task<Void, Never>?
    private let pageSize = 500

    init() {
        savedCatalogues = bookmarkStore.loadSavedCatalogues()
    }

    var canScan: Bool {
        guard scanProgress == nil else { return false }
        if let activeCatalogue {
            return activeCatalogue.sourceList.contains { $0.rootURL.isReachableDirectory }
        }
        return selectedRootURL != nil
    }

    var catalogueURL: URL? {
        if let activeCatalogue {
            return activeCatalogue.databaseURL
        }
        return selectedRootURL.map { CataloguePaths(rootURL: $0).databaseURL }
    }

    var catalogueRootURL: URL? {
        if let activeCatalogue {
            return URL(fileURLWithPath: activeCatalogue.path, isDirectory: true)
        }
        return selectedRootURL
    }

    var canRepairMissingFiles: Bool {
        database != nil && scanProgress == nil && activeMediaSources.contains { $0.rootURL.isReachableDirectory }
    }

    var canAddFoldersToCatalogue: Bool {
        scanProgress == nil
    }

    var activeCatalogueName: String {
        activeCatalogue?.name ?? selectedRootURL?.lastPathComponent ?? "No Catalogue"
    }

    var activeMediaSources: [CatalogueSource] {
        if let activeCatalogue {
            return activeCatalogue.sourceList
        }
        guard let selectedRootURL else { return [] }
        return [
            CatalogueSource(
                id: selectedRootURL.path,
                name: selectedRootURL.lastPathComponent,
                rootPath: selectedRootURL.path,
                relativePrefix: "",
                bookmarkData: nil,
                addedAt: Date(),
                lastScannedAt: nil
            )
        ]
    }

    var hasSelectedOrCurrentMediaItems: Bool {
        !selectedOrCurrentVisibleItems().isEmpty
    }

    var selectedSmartAlbum: SmartAlbum? {
        guard let selectedSmartAlbumID else { return nil }
        return smartAlbums.first { $0.id == selectedSmartAlbumID }
    }

    var selectedMissingRepairCandidate: MissingFolderRepairCandidate? {
        guard let selectedMissingRepairCandidateID else { return nil }
        return missingRepairCandidates.first { $0.id == selectedMissingRepairCandidateID }
    }

    func restoreAccess() async {
        refreshSavedCatalogues()

        if let activeID = bookmarkStore.loadActiveCatalogueID(),
           let catalogue = savedCatalogues.first(where: { $0.id == activeID }) {
            await openSavedCatalogue(catalogue)
            return
        }

        guard let bookmark = bookmarkStore.loadBookmark() else {
            ssdStatus = .notSelected
            return
        }

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            beginAccessing(url)
            try bookmarkStore.saveBookmark(for: url)
            bookmarkStore.saveActiveCatalogueID(url.standardizedFileURL.path)
            activeCatalogue = SavedCatalogue(
                id: url.standardizedFileURL.path,
                name: url.lastPathComponent,
                path: url.standardizedFileURL.path,
                bookmarkData: bookmark,
                lastOpenedAt: Date(),
                sources: nil
            )
            selectedRootURL = url
            hasCompletedOnboarding = true
            try openCatalogue(at: url)
            await loadTimeline()
            refreshSavedCatalogues()
        } catch {
            ssdStatus = .permissionLost
            userMessage = "DriveLens needs permission to access this media folder again. Choose the folder to continue."
        }
    }

    func chooseFolderAndPrepare() async {
        await chooseFolderAndPrepare(initialDirectory: nil)
    }

    func requestAccess(for catalogue: SavedCatalogue) async {
        await chooseFolderAndPrepare(initialDirectory: URL(fileURLWithPath: catalogue.path, isDirectory: true))
    }

    private func chooseFolderAndPrepare(initialDirectory: URL?) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = initialDirectory
        panel.prompt = "Choose Media Folder"
        panel.message = "Choose the folder that contains your photos and videos. Original photos and videos are not changed."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            beginAccessing(url)
            try bookmarkStore.saveBookmark(for: url)
            activeCatalogue = SavedCatalogue(
                id: url.standardizedFileURL.path,
                name: url.lastPathComponent,
                path: url.standardizedFileURL.path,
                bookmarkData: nil,
                lastOpenedAt: Date(),
                sources: nil
            )
            try CataloguePaths(rootURL: url).prepare()
            selectedRootURL = url
            try openCatalogue(at: url)
            await loadTimeline()
            refreshSavedCatalogues()
        } catch {
            userMessage = "The folder could not be opened. \(error.localizedDescription)"
            ssdStatus = .permissionLost
        }
    }

    func refreshSavedCatalogues() {
        savedCatalogues = bookmarkStore.loadSavedCatalogues()
    }

    @discardableResult
    func createCatalogue(named rawName: String, storageRootURL: URL? = nil, showsCreationMessage: Bool = true) async -> Bool {
        do {
            let catalogue = try bookmarkStore.createCatalogue(named: rawName, storageRootURL: storageRootURL)
            activeCatalogue = catalogue
            selectedRootURL = nil
            try openCatalogue(catalogue)
            hasCompletedOnboarding = true
            refreshSavedCatalogues()
            if showsCreationMessage {
                userMessage = "Created \(catalogue.name). Add folders to start indexing photos and videos."
            }
            return true
        } catch {
            userMessage = "Could not create catalogue: \(error.localizedDescription)"
            return false
        }
    }

    func createCatalogueByChoosingFolders() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Choose one or more photo or video folders. DriveLens stores catalogue data in .drivelens at the storage root. Original photos and videos are not changed."
        panel.prompt = "Create Catalogue"

        guard panel.runModal() == .OK else { return }

        let folderURLs = panel.urls.map(\.standardizedFileURL).filter(\.isReachableDirectory)
        guard !folderURLs.isEmpty else {
            userMessage = "Choose at least one reachable folder."
            return
        }

        let catalogueName = Self.defaultCatalogueName(for: folderURLs)
        guard let storageRootURL = await storageRootForCatalogue(for: folderURLs) else {
            userMessage = "Choose folders on a storage device where DriveLens can create .drivelens at the root."
            return
        }

        guard await createCatalogue(named: catalogueName, storageRootURL: storageRootURL, showsCreationMessage: false) else { return }
        await addFolderURLsToCurrentCatalogue(folderURLs)
    }

    func addFoldersToCurrentCatalogue() async {
        guard let catalogue = activeCatalogue else {
            await createCatalogueByChoosingFolders()
            return
        }

        guard catalogue.isNamedCatalogue else {
            await createCatalogueFromLegacyByChoosingFolders(catalogue)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Choose one or more folders to add to \(catalogue.name). DriveLens will index them in this catalogue only."
        panel.prompt = "Add Folders"

        guard panel.runModal() == .OK else { return }

        await addFolderURLsToCurrentCatalogue(panel.urls)
    }

    private func createCatalogueFromLegacyByChoosingFolders(_ legacyCatalogue: SavedCatalogue) async {
        let legacyRootURL = URL(fileURLWithPath: legacyCatalogue.path, isDirectory: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = legacyRootURL
        panel.message = "Choose folders to combine with \(legacyCatalogue.name). DriveLens will create a private multi-folder catalogue. Original photos and videos are not changed."
        panel.prompt = "Create Multi-Folder Catalogue"

        guard panel.runModal() == .OK else { return }

        let folderURLs = ([legacyRootURL] + panel.urls)
            .map(\.standardizedFileURL)
            .filter(\.isReachableDirectory)
        guard folderURLs.count > 1 else {
            userMessage = "Choose at least one additional reachable folder."
            return
        }

        let catalogueName = Self.defaultCatalogueName(for: folderURLs)
        guard let storageRootURL = await storageRootForCatalogue(for: folderURLs) else {
            userMessage = "Choose folders on a storage device where DriveLens can create .drivelens at the root."
            return
        }

        guard await createCatalogue(named: catalogueName, storageRootURL: storageRootURL, showsCreationMessage: false) else { return }
        await addFolderURLsToCurrentCatalogue(folderURLs)
    }

    private func addFolderURLsToCurrentCatalogue(_ urls: [URL]) async {
        guard let catalogue = activeCatalogue, catalogue.isNamedCatalogue else {
            userMessage = "Open or create a catalogue before adding folders."
            return
        }

        do {
            let folderURLs = urls.map(\.standardizedFileURL).filter(\.isReachableDirectory)
            guard !folderURLs.isEmpty else {
                userMessage = "Choose at least one reachable folder."
                return
            }

            let beforeIDs = Set(catalogue.sourceList.map(\.id))
            let updated = try bookmarkStore.addSources(folderURLs, to: catalogue)
            activeCatalogue = updated
            refreshSavedCatalogues()
            beginAccessingSources(updated.sourceList)

            let newSources = updated.sourceList.filter { !beforeIDs.contains($0.id) }
            guard !newSources.isEmpty else {
                userMessage = "Those folders are already in \(updated.name)."
                return
            }

            await runScan(rebuild: false, sources: newSources)
        } catch {
            userMessage = "Could not add folders: \(error.localizedDescription)"
        }
    }

    func renameCatalogue(id: SavedCatalogue.ID, to rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            userMessage = "Enter a catalogue name."
            return
        }

        guard let updated = bookmarkStore.renameCatalogue(id: id, to: name) else {
            userMessage = "Could not find that catalogue."
            return
        }

        if activeCatalogue?.id == id {
            activeCatalogue = updated
        }
        refreshSavedCatalogues()
        await refreshAppStorageReport()
        userMessage = "Renamed catalogue to \(updated.name)."
    }

    func deleteCatalogue(id: SavedCatalogue.ID) async {
        guard let catalogue = bookmarkStore.savedCatalogue(id: id) ?? activeCatalogueForDeletion(id: id) else {
            userMessage = "Could not find that catalogue."
            return
        }
        let resolvedID = catalogue.id
        let wasActive = activeCatalogue?.id == resolvedID || activeCatalogue?.path == id

        do {
            if wasActive {
                database = nil
            }
            if bookmarkStore.savedCatalogue(id: resolvedID) == nil {
                bookmarkStore.saveCatalogue(catalogue)
            }
            try bookmarkStore.deleteCatalogue(id: resolvedID, removingStoredData: true)
            refreshSavedCatalogues()

            if wasActive {
                resetMediaFolderSelection()
                refreshSavedCatalogues()
            } else {
                await refreshAppStorageReport()
            }

            userMessage = "Deleted metadata, thumbnails, indexes, caches, and the saved pointer for \(catalogue.name). Original photos and videos are not changed."
        } catch {
            if await deleteNamedCatalogueAfterChoosingCataloguesFolder(catalogue, wasActive: wasActive, originalError: error) {
                return
            }

            if activeCatalogue?.id == resolvedID {
                try? openCatalogue(catalogue)
            }
            userMessage = "Could not delete catalogue data: \(error.localizedDescription)"
        }
    }

    private func activeCatalogueForDeletion(id: SavedCatalogue.ID) -> SavedCatalogue? {
        guard let activeCatalogue else { return nil }
        if activeCatalogue.id == id || activeCatalogue.path == id {
            return activeCatalogue
        }
        return nil
    }

    private func deleteNamedCatalogueAfterChoosingCataloguesFolder(
        _ catalogue: SavedCatalogue,
        wasActive: Bool,
        originalError: Error
    ) async -> Bool {
        guard catalogue.isNamedCatalogue else { return false }

        let expectedCataloguesURL = URL(fileURLWithPath: catalogue.path, isDirectory: true)
            .standardizedFileURL
            .deletingLastPathComponent()

        guard expectedCataloguesURL.lastPathComponent == "catalogues" else {
            return false
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = expectedCataloguesURL.deletingLastPathComponent()
        panel.prompt = "Allow Deletion"
        panel.message = "Select the .drivelens/catalogues folder so DriveLens can delete only \(catalogue.id). Original photos and videos are not changed."

        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            if wasActive {
                try? openCatalogue(catalogue)
            }
            userMessage = "Delete cancelled. DriveLens needs permission for the .drivelens/catalogues folder."
            return true
        }

        let selectedCataloguesURL = cataloguesDirectoryURL(fromDeletePermissionSelection: selectedURL)
        guard selectedCataloguesURL.path == expectedCataloguesURL.path else {
            if wasActive {
                try? openCatalogue(catalogue)
            }
            userMessage = "Choose the matching .drivelens/catalogues folder for this catalogue."
            return true
        }

        let didStartAccessing = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        let targetURL = selectedCataloguesURL.appendingPathComponent(catalogue.id, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }

            bookmarkStore.removeSavedCatalogue(id: catalogue.id)
            refreshSavedCatalogues()

            if wasActive {
                resetMediaFolderSelection()
                refreshSavedCatalogues()
            } else {
                await refreshAppStorageReport()
            }

            userMessage = "Deleted metadata, thumbnails, indexes, caches, and the saved pointer for \(catalogue.name). Original photos and videos are not changed."
            return true
        } catch {
            if wasActive {
                try? openCatalogue(catalogue)
            }
            userMessage = "Could not delete catalogue data after permission was granted: \(error.localizedDescription). Earlier macOS message: \(originalError.localizedDescription)"
            return true
        }
    }

    private func cataloguesDirectoryURL(fromDeletePermissionSelection selectedURL: URL) -> URL {
        let standardizedURL = selectedURL.standardizedFileURL
        if standardizedURL.lastPathComponent == "catalogues" {
            return standardizedURL
        }
        if standardizedURL.lastPathComponent == ".drivelens" {
            return standardizedURL
                .appendingPathComponent("catalogues", isDirectory: true)
                .standardizedFileURL
        }

        return standardizedURL
            .appendingPathComponent(".drivelens", isDirectory: true)
            .appendingPathComponent("catalogues", isDirectory: true)
            .standardizedFileURL
    }

    func moveCatalogueToStorageRoot(id: SavedCatalogue.ID) async {
        guard var catalogue = bookmarkStore.savedCatalogue(id: id), catalogue.isNamedCatalogue else {
            userMessage = "Choose a named catalogue to move."
            return
        }

        guard let storageRootURL = await storageRootForCatalogue(for: catalogue.sourceList.map(\.rootURL)) else {
            userMessage = "Connect a writable storage device to continue."
            return
        }

        let destinationRootURL = storageRootURL
            .standardizedFileURL
            .appendingPathComponent(".drivelens", isDirectory: true)
            .appendingPathComponent("catalogues", isDirectory: true)
            .appendingPathComponent(catalogue.id, isDirectory: true)
        let sourceRootURL = URL(fileURLWithPath: catalogue.path, isDirectory: true).standardizedFileURL

        guard sourceRootURL.path != destinationRootURL.path else {
            userMessage = "\(catalogue.name) is already stored at the media storage root."
            return
        }

        let wasActive = activeCatalogue?.id == catalogue.id
        let manager = FileManager.default

        do {
            guard manager.fileExists(atPath: sourceRootURL.path) else {
                userMessage = "Could not find the current catalogue storage folder."
                return
            }
            guard !manager.fileExists(atPath: destinationRootURL.path) else {
                userMessage = "A catalogue storage folder already exists in \(storageRootURL.lastPathComponent)."
                return
            }

            if wasActive {
                database = nil
            }

            try manager.createDirectory(
                at: destinationRootURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try manager.copyItem(at: sourceRootURL, to: destinationRootURL)

            let migratedDatabase = try CatalogueDatabase(
                databaseURL: CataloguePaths(rootURL: destinationRootURL).databaseURL
            )
            try migratedDatabase.repairLivePhotoPairs()

            catalogue.path = destinationRootURL.path
            catalogue.bookmarkData = try? destinationRootURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            catalogue.cataloguesDirectoryBookmarkData = try? destinationRootURL.deletingLastPathComponent().bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkStore.saveCatalogue(catalogue)
            refreshSavedCatalogues()

            if wasActive {
                activeCatalogue = catalogue
                database = migratedDatabase
                selectedRootURL = nil
                ssdStatus = catalogue.sourceList.contains { $0.rootURL.isReachableDirectory } ? .connected : .disconnected
            }

            if sourceRootURL.isMacApplicationSupportCatalogueStorage {
                try? manager.removeItem(at: sourceRootURL)
            }

            await refreshAppStorageReport()
            userMessage = "Moved \(catalogue.name) to \(storageRootURL.lastPathComponent)/.drivelens. This Mac now keeps only the saved pointer. Original photos and videos are not changed."
        } catch {
            if wasActive {
                try? openCatalogue(catalogue)
            }
            userMessage = "Could not move catalogue storage: \(error.localizedDescription)"
        }
    }

    func openSavedCatalogue(_ catalogue: SavedCatalogue) async {
        if catalogue.isNamedCatalogue {
            do {
                let resolvedCatalogue = resolveSources(for: catalogue)
                activeCatalogue = resolvedCatalogue
                selectedRootURL = nil
                beginAccessingSources(resolvedCatalogue.sourceList)
                try openCatalogue(resolvedCatalogue)
                bookmarkStore.saveActiveCatalogueID(resolvedCatalogue.id)
                bookmarkStore.saveCatalogue(resolvedCatalogue)
                await loadTimeline()
                hasCompletedOnboarding = true
                refreshSavedCatalogues()
            } catch {
                ssdStatus = .permissionLost
                userMessage = "Connect the storage device to continue. If the folders moved, add them again."
            }
            return
        }

        guard let bookmarkData = catalogue.bookmarkData else {
            await requestAccess(for: catalogue)
            return
        }

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            beginAccessing(url)
            try bookmarkStore.saveBookmark(for: url)
            activeCatalogue = SavedCatalogue(
                id: catalogue.id,
                name: catalogue.name,
                path: url.standardizedFileURL.path,
                bookmarkData: bookmarkData,
                lastOpenedAt: Date(),
                sources: nil
            )

            selectedRootURL = url
            try openCatalogue(at: url)
            bookmarkStore.saveActiveCatalogueID(catalogue.id)
            await loadTimeline()
            hasCompletedOnboarding = true
            refreshSavedCatalogues()
        } catch {
            ssdStatus = .permissionLost
            userMessage = "Could not open that saved catalogue. Choose the folder again to refresh macOS permission."
        }
    }

    func forgetSavedCatalogue(_ catalogue: SavedCatalogue) {
        bookmarkStore.removeSavedCatalogue(id: catalogue.id)
        refreshSavedCatalogues()
        userMessage = "Removed \(catalogue.name) from Saved Catalogues. Its catalogue data and original photos and videos are not changed."
    }

    func buildCatalogue() async {
        let completed = await runScan(rebuild: activeCatalogue?.isNamedCatalogue == true ? false : true)
        if completed {
            hasCompletedOnboarding = true
        }
    }

    func updateCatalogue() async {
        await runScan(rebuild: false)
    }

    func chooseFoldersAndUpdateCatalogue() async {
        if let catalogue = activeCatalogue, catalogue.isNamedCatalogue {
            await chooseFoldersAndUpdateNamedCatalogue(catalogue)
            return
        }

        guard let rootURL = selectedRootURL else {
            userMessage = "Open a catalogue before updating folders."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = rootURL
        panel.message = "Choose one or more folders inside \(rootURL.lastPathComponent) to update."
        panel.prompt = "Update Folders"

        guard panel.runModal() == .OK else { return }

        let folderURLs = panel.urls.map(\.standardizedFileURL)
        let validFolders = folderURLs.filter { folderURL in
            folderURL.isReachableDirectory && folderURL.isSameOrDescendant(of: rootURL)
        }

        guard !validFolders.isEmpty else {
            userMessage = "Choose folders inside the active imported folder."
            return
        }

        await runScan(rebuild: false, scopeURLs: validFolders)
    }

    private func chooseFoldersAndUpdateNamedCatalogue(_ catalogue: SavedCatalogue) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Choose existing catalogue folders to rescan, or choose new folders to add to \(catalogue.name)."
        panel.prompt = "Update Folders"

        guard panel.runModal() == .OK else { return }

        var sourceScopes: [(source: CatalogueSource, urls: [URL])] = []
        var newSourceURLs: [URL] = []

        for folderURL in panel.urls.map(\.standardizedFileURL).filter(\.isReachableDirectory) {
            if let source = source(forFolderURL: folderURL, in: catalogue.sourceList) {
                if let index = sourceScopes.firstIndex(where: { $0.source.id == source.id }) {
                    sourceScopes[index].urls.append(folderURL)
                } else {
                    sourceScopes.append((source, [folderURL]))
                }
            } else {
                newSourceURLs.append(folderURL)
            }
        }

        do {
            var updatedCatalogue = catalogue
            var newSources: [CatalogueSource] = []
            if !newSourceURLs.isEmpty {
                let existingIDs = Set(catalogue.sourceList.map(\.id))
                updatedCatalogue = try bookmarkStore.addSources(newSourceURLs, to: catalogue)
                activeCatalogue = updatedCatalogue
                refreshSavedCatalogues()
                newSources = updatedCatalogue.sourceList.filter { !existingIDs.contains($0.id) }
            }

            let allSources = updatedCatalogue.sourceList
            beginAccessingSources(allSources)

            var sourceScans = sourceScopes
            sourceScans.append(contentsOf: newSources.map { ($0, [$0.rootURL]) })

            guard !sourceScans.isEmpty else {
                userMessage = "Choose folders inside existing sources, or choose new folders to import."
                return
            }

            await runScan(rebuild: false, sourceScopes: sourceScans)
        } catch {
            userMessage = "Could not update folders: \(error.localizedDescription)"
        }
    }

    func requestCatalogueUpdate() {
        showingRescanConfirmation = true
    }

    func openMissingFileRepair() async {
        showingMissingRepairSheet = true
        await refreshMissingRepairCandidates()
    }

    func refreshMissingRepairCandidates() async {
        guard let database else {
            missingRepairCandidates = []
            selectedMissingRepairCandidateID = nil
            return
        }

        do {
            let missingItems = try database.fetchMissingMediaItems()
            missingRepairCandidates = Self.missingRepairCandidates(from: missingItems)
            if let selectedMissingRepairCandidateID,
               missingRepairCandidates.contains(where: { $0.id == selectedMissingRepairCandidateID }) {
                return
            }
            selectedMissingRepairCandidateID = missingRepairCandidates.first?.id
        } catch {
            userMessage = "Could not load missing files: \(error.localizedDescription)"
        }
    }

    func chooseReplacementFolderForMissingRepair() async {
        guard let candidate = selectedMissingRepairCandidate else {
            userMessage = "Choose a missing folder to relink."
            return
        }
        guard let source = source(forRelativePath: candidate.folderPath) ?? activeMediaSources.first else {
            userMessage = "Open a catalogue source before repairing missing files."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = source.rootURL
        panel.message = "Choose the current location for \(candidate.title)."
        panel.prompt = "Relink Folder"

        guard panel.runModal() == .OK, let folderURL = panel.url?.standardizedFileURL else { return }
        await repairMissingFiles(candidate: candidate, replacementFolderURL: folderURL)
    }

    func repairMissingFiles(candidate: MissingFolderRepairCandidate, replacementFolderURL: URL) async {
        guard let database else {
            userMessage = "Open a catalogue before repairing missing files."
            return
        }

        let replacementFolderURL = replacementFolderURL.standardizedFileURL
        guard let replacementSource = source(forFolderURL: replacementFolderURL, in: activeMediaSources),
              replacementFolderURL.isReachableDirectory else {
            userMessage = "Choose a replacement folder inside an imported catalogue folder."
            return
        }

        isRepairingMissingFiles = true
        defer { isRepairingMissingFiles = false }

        do {
            let replacementFolderPath = catalogueRelativePath(
                for: replacementFolderURL,
                rootURL: replacementSource.rootURL,
                sourcePrefix: replacementSource.relativePrefix
            )
            let missingItems = try database.fetchMissingMediaItems().filter {
                Self.relativePath($0.relativePath, isInsideFolder: candidate.folderPath)
            }

            var remaps: [MissingFileRemap] = []
            var matchedCount = 0

            for item in missingItems {
                let suffix = Self.relativeSuffix(for: item.relativePath, removingFolder: candidate.folderPath)
                let newRelativePath = Self.joinRelativePath(folder: replacementFolderPath, suffix: suffix)
                guard let fileURL = mediaURL(forRelativePath: newRelativePath) else { continue }

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    continue
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard item.fileSize == 0 || item.fileSize == size else { continue }

                matchedCount += 1
                remaps.append(
                    MissingFileRemap(
                        id: item.id,
                        relativePath: newRelativePath,
                        folderPath: Self.folderPath(for: newRelativePath),
                        filename: fileURL.lastPathComponent,
                        fileSize: size,
                        modifiedAt: attributes[.modificationDate] as? Date ?? Date()
                    )
                )
            }

            let repairedCount = try database.remapMissingFiles(remaps)
            mediaMutationRevision += 1
            await loadTimeline()
            await refreshMissingRepairCandidates()

            let result = MissingFileRepairResult(
                scannedCount: missingItems.count,
                matchedCount: matchedCount,
                repairedCount: repairedCount
            )
            userMessage = Self.missingRepairMessage(result: result, folderName: candidate.title)
        } catch {
            userMessage = "Could not repair missing files: \(error.localizedDescription)"
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanProgress = nil
        userMessage = "Catalogue update cancelled. Choose Update Catalogue when you are ready to continue."
    }

    func resetMediaFolderSelection() {
        scanTask?.cancel()
        scanTask = nil
        scanProgress = nil
        scanSummary = nil
        catalogueCounts = .zero
        searchResultCount = 0
        duplicateGroupCount = 0
        selectedDuplicateGroupID = nil
        smartAlbums = []
        customAlbums = []
        selectedSmartAlbumID = nil
        smartAlbumItems = []
        isLoadingSmartAlbum = false
        smartAlbumQuickFilter = .all
        smartAlbumSort = .captureNewest
        selectedSmartAlbumYear = nil
        smartAlbumYears = []
        smartAlbumCounts = .zero
        smartAlbumScopeCounts = .zero
        smartAlbumResultCount = 0
        isFindingDuplicates = false
        duplicateScanStatus = ""
        appStorageReport = .empty
        isLoadingAppStorageReport = false
        isClearingAppCaches = false
        isCompactingCatalogue = false
        database = nil
        activeCatalogue = nil
        selectedRootURL = nil
        selectedMediaItem = nil
        pendingDeleteItem = nil
        pendingBatchDeleteItems = []
        pendingBatchDeleteContext = .selection
        renameItems = []
        showingRenameSheet = false
        showingMissingRepairSheet = false
        missingRepairCandidates = []
        selectedMissingRepairCandidateID = nil
        isRepairingMissingFiles = false
        isSelectionModeEnabled = false
        visibleSelectionScopeItems = []
        clearMediaSelection()
        showingViewer = false
        timelineQuickFilter = .all
        timelineSort = .captureNewest
        selectedTimelineYear = nil
        timelineYears = []
        timelineCounts = .zero
        timelineScopeCounts = .zero
        timelineResultCount = 0
        recentlyAddedQuickFilter = .all
        recentlyAddedSort = .recentlyAdded
        selectedRecentlyAddedYear = nil
        recentlyAddedYears = []
        recentlyAddedCounts = .zero
        recentlyAddedScopeCounts = .zero
        recentlyAddedResultCount = 0
        searchText = ""
        activeFilters = SearchFilters()
        focusedFolderPath = nil
        mediaItems = []
        videoItems = []
        recentlyAddedItems = []
        placeItems = []
        placeClusters = []
        selectedPlaceClusterID = nil
        searchItems = []
        duplicateGroups = []
        smartAlbums = []
        customAlbums = []
        selectedSmartAlbumID = nil
        smartAlbumItems = []
        smartAlbumQuickFilter = .all
        smartAlbumSort = .captureNewest
        selectedSmartAlbumYear = nil
        smartAlbumYears = []
        smartAlbumCounts = .zero
        smartAlbumScopeCounts = .zero
        smartAlbumResultCount = 0
        folderSummaries = []
        selectedSection = .timeline
        hasCompletedOnboarding = false
        ssdStatus = .notSelected
        showingRescanConfirmation = false
        showingResetConfirmation = false
        bookmarkStore.clear()
        stopAccessingSecurityScopedResources()
    }

    func requestMediaFolderReset() {
        showingResetConfirmation = true
    }

    func select(_ section: SidebarSection) {
        if selectedSection != section {
            clearMediaSelection()
            visibleSelectionScopeItems = []
            isSelectionModeEnabled = false
        }
        selectedSection = section
        if section != .folders {
            focusedFolderPath = nil
        }
        if section == .appInfo {
            Task { await refreshAppStorageReport() }
        }
        if section == .smartAlbums {
            Task { await refreshSmartAlbums() }
        }
    }

    func adjustGridSize(by delta: Double) {
        gridSize = min(max(gridSize + delta, 92), 220)
    }

    func setTimelineQuickFilter(_ filter: TimelineQuickFilter) async {
        timelineQuickFilter = filter
        guard let database else {
            mediaItems = []
            timelineYears = []
            timelineCounts = .zero
            timelineScopeCounts = .zero
            timelineResultCount = 0
            return
        }

        do {
            timelineYears = try database.fetchTimelineYears(filter: filter)
            if let selectedTimelineYear, !timelineYears.contains(selectedTimelineYear) {
                self.selectedTimelineYear = nil
            }
            mediaItems = try database.fetchTimeline(filter: filter, year: selectedTimelineYear, sort: timelineSort, limit: pageSize, offset: 0)
            timelineCounts = try database.fetchTimelineCounts(filter: filter, year: selectedTimelineYear)
            timelineScopeCounts = try timelineScopeCounts(for: selectedTimelineYear, in: database)
            timelineResultCount = timelineCounts.totalItems
            selectedMediaItem = mediaItems.first
        } catch {
            userMessage = "Could not apply filter: \(error.localizedDescription)"
        }
    }

    func setTimelineYear(_ year: Int?) async {
        selectedTimelineYear = year
        guard let database else {
            mediaItems = []
            timelineCounts = .zero
            timelineScopeCounts = .zero
            timelineResultCount = 0
            return
        }

        do {
            mediaItems = try database.fetchTimeline(filter: timelineQuickFilter, year: year, sort: timelineSort, limit: pageSize, offset: 0)
            timelineCounts = try database.fetchTimelineCounts(filter: timelineQuickFilter, year: year)
            timelineScopeCounts = try timelineScopeCounts(for: year, in: database)
            timelineResultCount = timelineCounts.totalItems
            selectedMediaItem = mediaItems.first
        } catch {
            userMessage = "Could not apply year filter: \(error.localizedDescription)"
        }
    }

    func setTimelineSort(_ sort: TimelineSortOption) async {
        timelineSort = sort
        guard let database else {
            mediaItems = []
            timelineCounts = .zero
            timelineResultCount = 0
            return
        }

        do {
            mediaItems = try database.fetchTimeline(filter: timelineQuickFilter, year: selectedTimelineYear, sort: sort, limit: pageSize, offset: 0)
            timelineCounts = try database.fetchTimelineCounts(filter: timelineQuickFilter, year: selectedTimelineYear)
            timelineResultCount = timelineCounts.totalItems
            selectedMediaItem = mediaItems.first
        } catch {
            userMessage = "Could not sort timeline: \(error.localizedDescription)"
        }
    }

    func resetTimelineControls() async {
        timelineQuickFilter = .all
        timelineSort = .captureNewest
        selectedTimelineYear = nil
        guard let database else {
            mediaItems = []
            timelineYears = []
            timelineCounts = .zero
            timelineScopeCounts = .zero
            timelineResultCount = 0
            return
        }

        do {
            timelineYears = try database.fetchTimelineYears(filter: .all)
            mediaItems = try database.fetchTimeline(filter: .all, year: nil, sort: .captureNewest, limit: pageSize, offset: 0)
            timelineCounts = try database.fetchTimelineCounts(filter: .all, year: nil)
            timelineScopeCounts = catalogueCounts
            timelineResultCount = timelineCounts.totalItems
            selectedMediaItem = mediaItems.first
        } catch {
            userMessage = "Could not reset timeline filters: \(error.localizedDescription)"
        }
    }

    func setRecentlyAddedQuickFilter(_ filter: TimelineQuickFilter) async {
        recentlyAddedQuickFilter = filter
        guard let database else {
            recentlyAddedItems = []
            recentlyAddedYears = []
            recentlyAddedCounts = .zero
            recentlyAddedScopeCounts = .zero
            recentlyAddedResultCount = 0
            return
        }

        do {
            recentlyAddedYears = try database.fetchRecentlyAddedYears(filter: filter)
            if let selectedRecentlyAddedYear, !recentlyAddedYears.contains(selectedRecentlyAddedYear) {
                self.selectedRecentlyAddedYear = nil
            }
            recentlyAddedItems = try database.fetchRecentlyAdded(filter: filter, year: selectedRecentlyAddedYear, sort: recentlyAddedSort, limit: pageSize, offset: 0)
            recentlyAddedCounts = try database.fetchRecentlyAddedCounts(filter: filter, year: selectedRecentlyAddedYear)
            recentlyAddedScopeCounts = try recentlyAddedScopeCounts(for: selectedRecentlyAddedYear, in: database)
            recentlyAddedResultCount = recentlyAddedCounts.totalItems
            selectedMediaItem = recentlyAddedItems.first
        } catch {
            userMessage = "Could not apply recently added filter: \(error.localizedDescription)"
        }
    }

    func setRecentlyAddedYear(_ year: Int?) async {
        selectedRecentlyAddedYear = year
        guard let database else {
            recentlyAddedItems = []
            recentlyAddedCounts = .zero
            recentlyAddedScopeCounts = .zero
            recentlyAddedResultCount = 0
            return
        }

        do {
            recentlyAddedItems = try database.fetchRecentlyAdded(filter: recentlyAddedQuickFilter, year: year, sort: recentlyAddedSort, limit: pageSize, offset: 0)
            recentlyAddedCounts = try database.fetchRecentlyAddedCounts(filter: recentlyAddedQuickFilter, year: year)
            recentlyAddedScopeCounts = try recentlyAddedScopeCounts(for: year, in: database)
            recentlyAddedResultCount = recentlyAddedCounts.totalItems
            selectedMediaItem = recentlyAddedItems.first
        } catch {
            userMessage = "Could not apply recently added year filter: \(error.localizedDescription)"
        }
    }

    func setRecentlyAddedSort(_ sort: TimelineSortOption) async {
        recentlyAddedSort = sort
        guard let database else {
            recentlyAddedItems = []
            recentlyAddedCounts = .zero
            recentlyAddedResultCount = 0
            return
        }

        do {
            recentlyAddedItems = try database.fetchRecentlyAdded(filter: recentlyAddedQuickFilter, year: selectedRecentlyAddedYear, sort: sort, limit: pageSize, offset: 0)
            recentlyAddedCounts = try database.fetchRecentlyAddedCounts(filter: recentlyAddedQuickFilter, year: selectedRecentlyAddedYear)
            recentlyAddedResultCount = recentlyAddedCounts.totalItems
            selectedMediaItem = recentlyAddedItems.first
        } catch {
            userMessage = "Could not sort recently added items: \(error.localizedDescription)"
        }
    }

    func resetRecentlyAddedControls() async {
        recentlyAddedQuickFilter = .all
        recentlyAddedSort = .recentlyAdded
        selectedRecentlyAddedYear = nil
        guard let database else {
            recentlyAddedItems = []
            recentlyAddedYears = []
            recentlyAddedCounts = .zero
            recentlyAddedScopeCounts = .zero
            recentlyAddedResultCount = 0
            return
        }

        do {
            recentlyAddedYears = try database.fetchRecentlyAddedYears(filter: .all)
            recentlyAddedItems = try database.fetchRecentlyAdded(filter: .all, year: nil, sort: .recentlyAdded, limit: pageSize, offset: 0)
            recentlyAddedCounts = try database.fetchRecentlyAddedCounts(filter: .all, year: nil)
            recentlyAddedScopeCounts = catalogueCounts
            recentlyAddedResultCount = recentlyAddedCounts.totalItems
            selectedMediaItem = recentlyAddedItems.first
        } catch {
            userMessage = "Could not reset recently added filters: \(error.localizedDescription)"
        }
    }

    func loadTimeline() async {
        guard let database else { return }
        do {
            timelineYears = try database.fetchTimelineYears(filter: timelineQuickFilter)
            if let selectedTimelineYear, !timelineYears.contains(selectedTimelineYear) {
                self.selectedTimelineYear = nil
            }
            mediaItems = try database.fetchTimeline(filter: timelineQuickFilter, year: selectedTimelineYear, sort: timelineSort, limit: pageSize, offset: 0)
            videoItems = try database.fetchVideos(limit: pageSize, offset: 0)
            recentlyAddedYears = try database.fetchRecentlyAddedYears(filter: recentlyAddedQuickFilter)
            if let selectedRecentlyAddedYear, !recentlyAddedYears.contains(selectedRecentlyAddedYear) {
                self.selectedRecentlyAddedYear = nil
            }
            recentlyAddedItems = try database.fetchRecentlyAdded(filter: recentlyAddedQuickFilter, year: selectedRecentlyAddedYear, sort: recentlyAddedSort, limit: pageSize, offset: 0)
            placeClusters = try database.fetchPlaceClusters()
            if let selectedPlaceClusterID,
               let selectedCluster = placeClusters.first(where: { $0.id == selectedPlaceClusterID }) {
                placeItems = try database.fetchLocatedMedia(in: selectedCluster, limit: pageSize, offset: 0)
            } else {
                selectedPlaceClusterID = nil
                placeItems = try database.fetchLocatedMedia(limit: pageSize, offset: 0)
            }
            searchItems = try database.fetchMedia(searchText: searchText, filters: activeFilters, limit: pageSize, offset: 0)
            duplicateGroups = try database.fetchDuplicateGroups()
            customAlbums = try database.fetchCustomAlbums()
            smartAlbums = try database.fetchSmartAlbums()
            if let selectedSmartAlbumID,
               let selectedAlbum = smartAlbums.first(where: { $0.id == selectedSmartAlbumID }) {
                smartAlbumYears = try database.fetchSmartAlbumYears(album: selectedAlbum, filter: smartAlbumQuickFilter)
                if let selectedSmartAlbumYear, !smartAlbumYears.contains(selectedSmartAlbumYear) {
                    self.selectedSmartAlbumYear = nil
                }
                try loadSmartAlbumContent(selectedAlbum, in: database)
            } else if selectedSmartAlbumID != nil {
                selectedSmartAlbumID = nil
                smartAlbumItems = []
                smartAlbumYears = []
                smartAlbumCounts = .zero
                smartAlbumScopeCounts = .zero
                smartAlbumResultCount = 0
            }
            duplicateGroupCount = duplicateGroups.count
            if let selectedDuplicateGroupID, !duplicateGroups.contains(where: { $0.id == selectedDuplicateGroupID }) {
                self.selectedDuplicateGroupID = duplicateGroups.first?.id
            } else if selectedDuplicateGroupID == nil {
                selectedDuplicateGroupID = duplicateGroups.first?.id
            }
            scanSummary = try database.latestScanSummary()
            catalogueCounts = try database.fetchCatalogueCounts()
            timelineCounts = try database.fetchTimelineCounts(filter: timelineQuickFilter, year: selectedTimelineYear)
            timelineScopeCounts = try timelineScopeCounts(for: selectedTimelineYear, in: database)
            timelineResultCount = timelineCounts.totalItems
            recentlyAddedCounts = try database.fetchRecentlyAddedCounts(filter: recentlyAddedQuickFilter, year: selectedRecentlyAddedYear)
            recentlyAddedScopeCounts = try recentlyAddedScopeCounts(for: selectedRecentlyAddedYear, in: database)
            recentlyAddedResultCount = recentlyAddedCounts.totalItems
            searchResultCount = catalogueCounts.totalItems
            folderSummaries = try database.fetchFolderSummaries()
            ssdStatus = activeMediaSources.isEmpty || activeMediaSources.contains { $0.rootURL.isReachableDirectory } ? .connected : .disconnected
        } catch {
            ssdStatus = .catalogueCorrupted
            userMessage = "The catalogue could not be read. Original photos and videos are not changed."
        }
    }

    func loadNextPageIfNeeded(currentItem item: MediaItem) async {
        guard let database, !isLoadingPage else {
            return
        }

        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            switch selectedSection {
            case .timeline:
                guard mediaItems.suffix(40).contains(where: { $0.id == item.id }) else { return }
                let nextPage = try database.fetchTimeline(filter: timelineQuickFilter, year: selectedTimelineYear, sort: timelineSort, limit: pageSize, offset: mediaItems.count)
                mediaItems.append(contentsOf: nextPage)
            case .recentlyAdded:
                guard recentlyAddedItems.suffix(40).contains(where: { $0.id == item.id }) else { return }
                let nextPage = try database.fetchRecentlyAdded(filter: recentlyAddedQuickFilter, year: selectedRecentlyAddedYear, sort: recentlyAddedSort, limit: pageSize, offset: recentlyAddedItems.count)
                recentlyAddedItems.append(contentsOf: nextPage)
            case .smartAlbums:
                guard smartAlbumItems.suffix(40).contains(where: { $0.id == item.id }),
                      let selectedSmartAlbum else { return }
                let nextPage = try database.fetchSmartAlbumItems(
                    album: selectedSmartAlbum,
                    filter: smartAlbumQuickFilter,
                    year: selectedSmartAlbumYear,
                    sort: smartAlbumSort,
                    limit: pageSize,
                    offset: smartAlbumItems.count
                )
                smartAlbumItems.append(contentsOf: nextPage)
            default:
                return
            }
        } catch {
            userMessage = "Could not load more catalogue items: \(error.localizedDescription)"
        }
    }

    func loadItems(inFolderPath folderPath: String) async -> [MediaItem] {
        guard let database else { return [] }
        do {
            return try database.fetchMedia(inFolderPath: folderPath, limit: pageSize, offset: 0)
        } catch {
            userMessage = "Could not load folder items: \(error.localizedDescription)"
            return []
        }
    }

    func selectPlaceCluster(_ cluster: PlaceCluster) async {
        selectedPlaceClusterID = cluster.id
        guard let database else { return }

        do {
            placeItems = try database.fetchLocatedMedia(in: cluster, limit: pageSize, offset: 0)
            selectedMediaItem = placeItems.first
            updateVisibleSelectionScope(placeItems)
        } catch {
            userMessage = "Could not load mapped media: \(error.localizedDescription)"
        }
    }

    func clearPlaceClusterSelection() async {
        selectedPlaceClusterID = nil
        guard let database else {
            placeItems = []
            return
        }

        do {
            placeItems = try database.fetchLocatedMedia(limit: pageSize, offset: 0)
            selectedMediaItem = placeItems.first
            updateVisibleSelectionScope(placeItems)
        } catch {
            userMessage = "Could not load mapped media: \(error.localizedDescription)"
        }
    }

    func filteredItems() -> [MediaItem] {
        mediaItems
    }

    func updateVisibleSelectionScope(_ items: [MediaItem]) {
        visibleSelectionScopeItems = items

        if selectedSection != .places {
            let visibleIDs = Set(items.map(\.id))
            selectedMediaItemIDs = selectedMediaItemIDs.intersection(visibleIDs)
        }
    }

    private func visibleItemsForSelection() -> [MediaItem] {
        if !visibleSelectionScopeItems.isEmpty {
            return visibleSelectionScopeItems
        }

        switch selectedSection {
        case .timeline:
            return mediaItems
        case .recentlyAdded:
            return recentlyAddedItems
        case .smartAlbums:
            return smartAlbumItems
        case .duplicates:
            if let selectedDuplicateGroupID,
               let group = duplicateGroups.first(where: { $0.id == selectedDuplicateGroupID }) {
                return group.sortedItems
            }
            return duplicateGroups.first?.sortedItems ?? []
        case .videos:
            return videoItems
        case .places:
            return placeItems
        case .search:
            return searchItems
        case .folders:
            return mediaItems
        case .appInfo:
            return []
        }
    }

    func quickFilterCount(for filter: TimelineQuickFilter) -> Int {
        let counts = selectedTimelineYear == nil ? catalogueCounts : timelineScopeCounts

        switch filter {
        case .all:
            return counts.totalItems
        case .photos:
            return counts.photoLikeItems
        case .videos:
            return counts.videoLikeItems
        case .withLocation:
            return counts.locatedItems
        case .withoutLocation:
            return counts.missingLocationItems
        }
    }

    func recentlyAddedQuickFilterCount(for filter: TimelineQuickFilter) -> Int {
        let counts = selectedRecentlyAddedYear == nil ? catalogueCounts : recentlyAddedScopeCounts

        switch filter {
        case .all:
            return counts.totalItems
        case .photos:
            return counts.photoLikeItems
        case .videos:
            return counts.videoLikeItems
        case .withLocation:
            return counts.locatedItems
        case .withoutLocation:
            return counts.missingLocationItems
        }
    }

    func smartAlbumQuickFilterCount(for filter: TimelineQuickFilter) -> Int {
        let counts = smartAlbumScopeCounts

        switch filter {
        case .all:
            return counts.totalItems
        case .photos:
            return counts.photoLikeItems
        case .videos:
            return counts.videoLikeItems
        case .withLocation:
            return counts.locatedItems
        case .withoutLocation:
            return counts.missingLocationItems
        }
    }

    func countsForCurrentTimelineFilter() -> CatalogueCounts {
        timelineCounts == .zero && selectedTimelineYear == nil && timelineQuickFilter == .all
            ? catalogueCounts
            : timelineCounts
    }

    func countsForCurrentRecentlyAddedFilter() -> CatalogueCounts {
        recentlyAddedCounts == .zero && selectedRecentlyAddedYear == nil && recentlyAddedQuickFilter == .all
            ? catalogueCounts
            : recentlyAddedCounts
    }

    func countsForCurrentSmartAlbumFilter() -> CatalogueCounts {
        smartAlbumCounts
    }

    private func timelineScopeCounts(for year: Int?, in database: CatalogueDatabase) throws -> CatalogueCounts {
        if year == nil {
            return catalogueCounts
        }
        return try database.fetchTimelineCounts(filter: .all, year: year)
    }

    private func recentlyAddedScopeCounts(for year: Int?, in database: CatalogueDatabase) throws -> CatalogueCounts {
        if year == nil {
            return catalogueCounts
        }
        return try database.fetchRecentlyAddedCounts(filter: .all, year: year)
    }

    private func smartAlbumScopeCounts(for year: Int?, album: SmartAlbum, in database: CatalogueDatabase) throws -> CatalogueCounts {
        try database.fetchSmartAlbumCounts(album: album, filter: .all, year: year)
    }

    private func loadSmartAlbumContent(_ album: SmartAlbum, in database: CatalogueDatabase) throws {
        smartAlbumItems = try database.fetchSmartAlbumItems(
            album: album,
            filter: smartAlbumQuickFilter,
            year: selectedSmartAlbumYear,
            sort: smartAlbumSort,
            limit: pageSize,
            offset: 0
        )
        smartAlbumCounts = try database.fetchSmartAlbumCounts(
            album: album,
            filter: smartAlbumQuickFilter,
            year: selectedSmartAlbumYear
        )
        smartAlbumScopeCounts = try smartAlbumScopeCounts(for: selectedSmartAlbumYear, album: album, in: database)
        smartAlbumResultCount = smartAlbumCounts.totalItems
    }

    func sidebarCount(for section: SidebarSection) -> Int? {
        switch section {
        case .timeline:
            return catalogueCounts.totalItems
        case .places:
            return catalogueCounts.locatedItems
        case .folders:
            return folderSummaries.count
        case .search:
            return searchResultCount
        case .videos:
            return catalogueCounts.videoLikeItems
        case .recentlyAdded:
            return recentlyAddedResultCount == 0 ? catalogueCounts.totalItems : recentlyAddedResultCount
        case .smartAlbums:
            return smartAlbums.filter { !$0.isPlaceholder }.count
        case .duplicates:
            return duplicateGroupCount
        case .appInfo:
            return savedCatalogues.count
        }
    }

    func refreshSearchResultCount() {
        guard let database else {
            searchResultCount = filteredItems().count
            searchItems = filteredItems()
            return
        }

        do {
            searchResultCount = try database.countMedia(searchText: searchText, filters: activeFilters)
            searchItems = try database.fetchMedia(searchText: searchText, filters: activeFilters, limit: pageSize, offset: 0)
        } catch {
            searchResultCount = filteredItems().count
            searchItems = filteredItems()
        }
    }

    func counts(for section: SidebarSection) -> CatalogueCounts {
        switch section {
        case .timeline:
            return catalogueCounts
        case .recentlyAdded:
            return countsForCurrentRecentlyAddedFilter()
        case .videos:
            return CatalogueCounts(
                totalItems: catalogueCounts.videoLikeItems,
                photos: 0,
                videos: catalogueCounts.videos,
                locatedItems: 0,
                missingLocationItems: 0
            )
        case .smartAlbums:
            return countsForCurrentSmartAlbumFilter()
        case .places, .folders, .search, .duplicates, .appInfo:
            return catalogueCounts
        }
    }

    func refreshSmartAlbums() async {
        guard let database else {
            smartAlbums = []
            selectedSmartAlbumID = nil
            smartAlbumItems = []
            customAlbums = []
            smartAlbumYears = []
            smartAlbumCounts = .zero
            smartAlbumScopeCounts = .zero
            smartAlbumResultCount = 0
            return
        }

        do {
            smartAlbums = try database.fetchSmartAlbums()
            customAlbums = try database.fetchCustomAlbums()
            guard let selectedSmartAlbumID else { return }

            if let album = smartAlbums.first(where: { $0.id == selectedSmartAlbumID }) {
                smartAlbumYears = try database.fetchSmartAlbumYears(album: album, filter: smartAlbumQuickFilter)
                if let selectedSmartAlbumYear, !smartAlbumYears.contains(selectedSmartAlbumYear) {
                    self.selectedSmartAlbumYear = nil
                }
                try loadSmartAlbumContent(album, in: database)
            } else {
                self.selectedSmartAlbumID = nil
                smartAlbumItems = []
                smartAlbumYears = []
                smartAlbumCounts = .zero
                smartAlbumScopeCounts = .zero
                smartAlbumResultCount = 0
            }
        } catch {
            userMessage = "Could not load smart albums: \(error.localizedDescription)"
        }
    }

    func openSmartAlbum(_ album: SmartAlbum) async {
        let albumChanged = selectedSmartAlbumID != album.id
        selectedSmartAlbumID = album.id
        clearMediaSelection()
        visibleSelectionScopeItems = []
        if albumChanged {
            smartAlbumQuickFilter = .all
            smartAlbumSort = .captureNewest
            selectedSmartAlbumYear = nil
        }

        guard !album.isPlaceholder else {
            smartAlbumItems = []
            selectedMediaItem = nil
            smartAlbumYears = []
            smartAlbumCounts = .zero
            smartAlbumScopeCounts = .zero
            smartAlbumResultCount = 0
            return
        }

        guard let database else {
            smartAlbumItems = []
            selectedMediaItem = nil
            return
        }

        isLoadingSmartAlbum = true
        defer { isLoadingSmartAlbum = false }

        do {
            smartAlbumYears = try database.fetchSmartAlbumYears(album: album, filter: smartAlbumQuickFilter)
            if let selectedSmartAlbumYear, !smartAlbumYears.contains(selectedSmartAlbumYear) {
                self.selectedSmartAlbumYear = nil
            }
            try loadSmartAlbumContent(album, in: database)
            selectedMediaItem = smartAlbumItems.first
        } catch {
            userMessage = "Could not open \(album.title): \(error.localizedDescription)"
            smartAlbumItems = []
        }
    }

    func setSmartAlbumQuickFilter(_ filter: TimelineQuickFilter) async {
        smartAlbumQuickFilter = filter
        guard let database, let selectedSmartAlbum else {
            smartAlbumItems = []
            smartAlbumYears = []
            smartAlbumCounts = .zero
            smartAlbumScopeCounts = .zero
            smartAlbumResultCount = 0
            return
        }

        do {
            smartAlbumYears = try database.fetchSmartAlbumYears(album: selectedSmartAlbum, filter: filter)
            if let selectedSmartAlbumYear, !smartAlbumYears.contains(selectedSmartAlbumYear) {
                self.selectedSmartAlbumYear = nil
            }
            try loadSmartAlbumContent(selectedSmartAlbum, in: database)
            selectedMediaItem = smartAlbumItems.first
        } catch {
            userMessage = "Could not apply smart album filter: \(error.localizedDescription)"
        }
    }

    func setSmartAlbumYear(_ year: Int?) async {
        selectedSmartAlbumYear = year
        guard let database, let selectedSmartAlbum else {
            smartAlbumItems = []
            smartAlbumCounts = .zero
            smartAlbumScopeCounts = .zero
            smartAlbumResultCount = 0
            return
        }

        do {
            try loadSmartAlbumContent(selectedSmartAlbum, in: database)
            selectedMediaItem = smartAlbumItems.first
        } catch {
            userMessage = "Could not apply smart album year filter: \(error.localizedDescription)"
        }
    }

    func setSmartAlbumSort(_ sort: TimelineSortOption) async {
        smartAlbumSort = sort
        guard let database, let selectedSmartAlbum else {
            smartAlbumItems = []
            smartAlbumCounts = .zero
            smartAlbumResultCount = 0
            return
        }

        do {
            try loadSmartAlbumContent(selectedSmartAlbum, in: database)
            selectedMediaItem = smartAlbumItems.first
        } catch {
            userMessage = "Could not sort smart album: \(error.localizedDescription)"
        }
    }

    func resetSmartAlbumControls() async {
        smartAlbumQuickFilter = .all
        smartAlbumSort = .captureNewest
        selectedSmartAlbumYear = nil
        guard let database, let selectedSmartAlbum else {
            smartAlbumItems = []
            smartAlbumYears = []
            smartAlbumCounts = .zero
            smartAlbumScopeCounts = .zero
            smartAlbumResultCount = 0
            return
        }

        do {
            smartAlbumYears = try database.fetchSmartAlbumYears(album: selectedSmartAlbum, filter: .all)
            try loadSmartAlbumContent(selectedSmartAlbum, in: database)
            selectedMediaItem = smartAlbumItems.first
        } catch {
            userMessage = "Could not reset smart album filters: \(error.localizedDescription)"
        }
    }

    func closeSmartAlbum() {
        selectedSmartAlbumID = nil
        smartAlbumItems = []
        smartAlbumQuickFilter = .all
        smartAlbumSort = .captureNewest
        selectedSmartAlbumYear = nil
        smartAlbumYears = []
        smartAlbumCounts = .zero
        smartAlbumScopeCounts = .zero
        smartAlbumResultCount = 0
        clearMediaSelection()
        visibleSelectionScopeItems = []
    }

    func batchMetadataSummary(for items: [MediaItem]) -> BatchMetadataSummary {
        guard !items.isEmpty else { return .empty }

        let keywordSets = items.map { Set($0.keywords.map(\.localizedLowercase)) }
        let sharedLowercaseKeywords = keywordSets.dropFirst().reduce(keywordSets.first ?? []) { partial, next in
            partial.intersection(next)
        }
        let sharedKeywords = items
            .flatMap(\.keywords)
            .filter { sharedLowercaseKeywords.contains($0.localizedLowercase) }
            .reduce(into: [String]()) { output, keyword in
                if !output.contains(where: { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }) {
                    output.append(keyword)
                }
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let captions = items.map { ($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let firstCaption = captions.first ?? ""
        let hasMixedCaptions = captions.contains { $0 != firstCaption }

        let locations = items.map { item -> String in
            if !item.placeText.isEmpty { return item.placeText }
            if let latitude = item.latitude, let longitude = item.longitude {
                return String(format: "%.5f, %.5f", latitude, longitude)
            }
            return ""
        }
        let firstLocation = locations.first ?? ""
        let hasMixedLocations = locations.contains { $0 != firstLocation }

        let favoriteValues = Set(items.map(\.isFavorite))

        return BatchMetadataSummary(
            selectedCount: items.count,
            sharedKeywords: sharedKeywords,
            commonCaption: hasMixedCaptions || firstCaption.isEmpty ? nil : firstCaption,
            hasMixedCaptions: hasMixedCaptions,
            commonLocationText: hasMixedLocations || firstLocation.isEmpty ? nil : firstLocation,
            hasMixedLocations: hasMixedLocations,
            commonFavorite: favoriteValues.count == 1 ? favoriteValues.first : nil
        )
    }

    func addKeyword(_ keyword: String, to items: [MediaItem]) async {
        let itemIDs = items.map(\.id)
        guard let database, !itemIDs.isEmpty else { return }

        do {
            try database.addKeyword(keyword, to: itemIDs)
            mediaMutationRevision += 1
            await loadTimeline()
            userMessage = "Added keyword to \(itemIDs.count) item\(itemIDs.count == 1 ? "" : "s")."
        } catch {
            userMessage = "Could not add keyword: \(error.localizedDescription)"
        }
    }

    func setCaption(_ caption: String, for items: [MediaItem]) async {
        let itemIDs = items.map(\.id)
        guard let database, !itemIDs.isEmpty else { return }

        do {
            try database.setUserCaption(caption, for: itemIDs)
            mediaMutationRevision += 1
            await loadTimeline()
            userMessage = "Updated caption for \(itemIDs.count) item\(itemIDs.count == 1 ? "" : "s")."
        } catch {
            userMessage = "Could not update caption: \(error.localizedDescription)"
        }
    }

    func setFavorite(_ isFavorite: Bool, for items: [MediaItem]) async {
        let itemIDs = items.map(\.id)
        guard !itemIDs.isEmpty else { return }
        guard let database else {
            userMessage = "Connect the storage device to continue."
            return
        }

        do {
            try database.setFavorite(isFavorite, for: itemIDs)
            updateFavoriteState(isFavorite, for: Set(itemIDs))
            mediaMutationRevision += 1
            smartAlbums = try database.fetchSmartAlbums()
            if let selectedSmartAlbumID,
               let selectedAlbum = smartAlbums.first(where: { $0.id == selectedSmartAlbumID }),
               case .favorites = selectedAlbum.kind {
                try loadSmartAlbumContent(selectedAlbum, in: database)
            }
            showActionNotice(
                isFavorite
                    ? "Marked \(itemIDs.count) item\(itemIDs.count == 1 ? "" : "s") as favorite."
                    : "Removed \(itemIDs.count) item\(itemIDs.count == 1 ? "" : "s") from Favorites."
            )
        } catch {
            userMessage = "Could not update favorites: \(error.localizedDescription)"
        }
    }

    func favoriteState(for item: MediaItem) -> Bool {
        if let selectedMediaItem, selectedMediaItem.id == item.id {
            return selectedMediaItem.isFavorite
        }
        if let visibleItem = visibleSelectionScopeItems.first(where: { $0.id == item.id }) {
            return visibleItem.isFavorite
        }
        return item.isFavorite
    }

    private func updateFavoriteState(_ isFavorite: Bool, for itemIDs: Set<Int64>) {
        func update(_ items: inout [MediaItem]) {
            for index in items.indices where itemIDs.contains(items[index].id) {
                items[index].isFavorite = isFavorite
            }
        }

        update(&mediaItems)
        update(&videoItems)
        update(&recentlyAddedItems)
        update(&placeItems)
        update(&searchItems)
        update(&smartAlbumItems)
        update(&visibleSelectionScopeItems)

        if var selectedMediaItem, itemIDs.contains(selectedMediaItem.id) {
            selectedMediaItem.isFavorite = isFavorite
            self.selectedMediaItem = selectedMediaItem
        }
    }

    func setLocation(latitudeText: String, longitudeText: String, city: String, state: String, country: String, for items: [MediaItem]) async {
        let itemIDs = items.map(\.id)
        guard let database, !itemIDs.isEmpty else { return }
        guard let latitude = Double(latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let longitude = Double(longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            userMessage = "Enter a valid latitude and longitude."
            return
        }

        do {
            try database.setManualLocation(
                latitude: latitude,
                longitude: longitude,
                city: city,
                state: state,
                country: country,
                for: itemIDs
            )
            mediaMutationRevision += 1
            await loadTimeline()
            userMessage = "Set location for \(itemIDs.count) item\(itemIDs.count == 1 ? "" : "s")."
        } catch {
            userMessage = "Could not update location: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addToCustomAlbum(named name: String, items: [MediaItem]) async -> Bool {
        let itemIDs = items.map(\.id)
        guard !itemIDs.isEmpty else { return false }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            userMessage = "Enter an album name."
            return false
        }
        guard normalizedName.count <= 80 else {
            userMessage = "Album names can contain up to 80 characters."
            return false
        }
        guard let database else {
            userMessage = "Connect the storage device to continue."
            return false
        }

        do {
            guard let result = try database.addItems(itemIDs, toCustomAlbumNamed: normalizedName) else {
                userMessage = "Enter an album name."
                return false
            }
            let album = result.album
            customAlbums = try database.fetchCustomAlbums()
            smartAlbums = try database.fetchSmartAlbums()
            mediaMutationRevision += 1
            if let selectedSmartAlbumID,
               let selectedAlbum = smartAlbums.first(where: { $0.id == selectedSmartAlbumID }),
               case .customAlbum = selectedAlbum.kind {
                try loadSmartAlbumContent(selectedAlbum, in: database)
            }
            showActionNotice(
                albumNotice(
                    albumName: album.name,
                    addedCount: result.addedCount,
                    requestedCount: itemIDs.count
                )
            )
            return true
        } catch {
            userMessage = "Could not update custom album: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func createCustomAlbum(named rawName: String) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            userMessage = "Enter an album name."
            return false
        }
        guard name.count <= 80 else {
            userMessage = "Album names can contain up to 80 characters."
            return false
        }
        guard let database else {
            userMessage = "Open a catalogue before creating an album."
            return false
        }

        do {
            let albums = try database.fetchCustomAlbums()
            guard !albums.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                userMessage = "An album named “\(name)” already exists."
                return false
            }
            guard let album = try database.createCustomAlbum(named: name) else {
                userMessage = "Enter an album name."
                return false
            }
            customAlbums = try database.fetchCustomAlbums()
            smartAlbums = try database.fetchSmartAlbums()
            userMessage = "Created “\(album.name)”. Add selected photos and videos from the Inspector."
            return true
        } catch {
            userMessage = "The album could not be created. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func renameCustomAlbum(_ album: CustomAlbum, to rawName: String) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            userMessage = "Enter an album name."
            return false
        }
        guard name.count <= 80 else {
            userMessage = "Album names can contain up to 80 characters."
            return false
        }
        guard let database else {
            userMessage = "Connect the storage device to continue."
            return false
        }

        do {
            let albums = try database.fetchCustomAlbums()
            guard !albums.contains(where: {
                $0.id != album.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                userMessage = "An album named “\(name)” already exists."
                return false
            }
            guard let renamedAlbum = try database.renameCustomAlbum(id: album.id, to: name) else {
                userMessage = "The album is no longer available."
                return false
            }
            customAlbums = try database.fetchCustomAlbums()
            smartAlbums = try database.fetchSmartAlbums()
            userMessage = "Renamed the album to “\(renamedAlbum.name)”."
            return true
        } catch {
            userMessage = "The album could not be renamed. \(error.localizedDescription)"
            return false
        }
    }

    func deleteCustomAlbum(_ album: CustomAlbum) async {
        guard let database else {
            userMessage = "Connect the storage device to continue."
            return
        }

        do {
            let isSelectedAlbum: Bool
            if case .customAlbum(let selectedID)? = selectedSmartAlbum?.kind {
                isSelectedAlbum = selectedID == album.id
            } else {
                isSelectedAlbum = false
            }

            try database.deleteCustomAlbum(id: album.id)
            if isSelectedAlbum {
                closeSmartAlbum()
            }
            customAlbums = try database.fetchCustomAlbums()
            smartAlbums = try database.fetchSmartAlbums()
            userMessage = "Deleted “\(album.name)” from DriveLens. Original photos and videos are not changed."
        } catch {
            userMessage = "The album could not be deleted. \(error.localizedDescription)"
        }
    }

    private func showActionNotice(_ message: String) {
        actionNoticeTask?.cancel()
        actionNotice = message
        actionNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.actionNotice = nil
        }
    }

    private func albumNotice(albumName: String, addedCount: Int, requestedCount: Int) -> String {
        if addedCount == 0 {
            return requestedCount == 1
                ? "The selected item is already in “\(albumName)”."
                : "All selected items are already in “\(albumName)”."
        }

        let addedText = "Added \(addedCount) item\(addedCount == 1 ? "" : "s") to “\(albumName)”."
        let existingCount = requestedCount - addedCount
        guard existingCount > 0 else { return addedText }
        return addedText + " \(existingCount) \(existingCount == 1 ? "was" : "were") already there."
    }

    private static func missingRepairCandidates(from missingItems: [MediaItem]) -> [MissingFolderRepairCandidate] {
        guard !missingItems.isEmpty else { return [] }

        var buckets: [String: [MediaItem]] = [:]
        for item in missingItems {
            buckets["", default: []].append(item)

            let components = item.folderPath
                .split(separator: "/")
                .map(String.init)
            var prefix = ""
            for component in components {
                prefix = prefix.isEmpty ? component : prefix + "/" + component
                buckets[prefix, default: []].append(item)
            }
        }

        return buckets.map { path, items in
            MissingFolderRepairCandidate(
                folderPath: path,
                missingCount: items.count,
                sampleFilenames: Array(items.map(\.filename).prefix(3))
            )
        }
        .sorted {
            if $0.folderPath.isEmpty != $1.folderPath.isEmpty {
                return $0.folderPath.isEmpty
            }
            if $0.missingCount != $1.missingCount {
                return $0.missingCount > $1.missingCount
            }
            return $0.folderPath.localizedStandardCompare($1.folderPath) == .orderedAscending
        }
    }

    private static func relativePath(_ relativePath: String, isInsideFolder folderPath: String) -> Bool {
        folderPath.isEmpty || relativePath == folderPath || relativePath.hasPrefix(folderPath + "/")
    }

    private static func relativeSuffix(for relativePath: String, removingFolder folderPath: String) -> String {
        guard !folderPath.isEmpty else { return relativePath }
        if relativePath == folderPath { return (relativePath as NSString).lastPathComponent }
        return String(relativePath.dropFirst(folderPath.count + 1))
    }

    private static func joinRelativePath(folder: String, suffix: String) -> String {
        let cleanFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanSuffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleanFolder.isEmpty { return cleanSuffix }
        if cleanSuffix.isEmpty { return cleanFolder }
        return cleanFolder + "/" + cleanSuffix
    }

    private static func folderPath(for relativePath: String) -> String {
        let folder = (relativePath as NSString).deletingLastPathComponent
        return folder == "." ? "" : folder
    }

    private static func missingRepairMessage(result: MissingFileRepairResult, folderName: String) -> String {
        if result.repairedCount == 0 {
            if result.matchedCount == 0 {
                return "No matching files were found for \(folderName). Choose the folder that contains those originals now."
            }
            return "Found \(result.matchedCount) matching file\(result.matchedCount == 1 ? "" : "s"), but DriveLens could not remap them because those catalogue paths already exist."
        }

        var message = "Repaired \(result.repairedCount) missing file\(result.repairedCount == 1 ? "" : "s") in \(folderName)."
        if result.skippedCount > 0 {
            message += " \(result.skippedCount) item\(result.skippedCount == 1 ? "" : "s") still need attention."
        }
        return message
    }

    private static func scanCompletionMessage(summary: ScanSummary, rebuild: Bool, scopeCount: Int?) -> String {
        let title: String
        if rebuild {
            title = "Catalogue build finished"
        } else if let scopeCount, scopeCount > 0 {
            title = "Folder update finished for \(scopeCount) folder\(scopeCount == 1 ? "" : "s")"
        } else {
            title = "Catalogue update finished"
        }

        var details: [String] = [
            "\(summary.filesScanned) supported file\(summary.filesScanned == 1 ? "" : "s") scanned"
        ]

        if rebuild {
            details.append("\(summary.newFiles) indexed")
        } else {
            details.append("\(summary.newFiles) new")
            details.append("\(summary.refreshedFiles) refreshed")
            details.append("\(summary.alreadyIndexedFiles) already indexed")
            if summary.missingFiles > 0 {
                details.append("\(summary.missingFiles) marked missing")
            }
        }

        if summary.unsupportedFiles > 0 {
            details.append("\(summary.unsupportedFiles) unsupported file\(summary.unsupportedFiles == 1 ? "" : "s") skipped")
        }
        if summary.errors > 0 {
            details.append("\(summary.errors) file\(summary.errors == 1 ? "" : "s") could not be indexed")
        }

        let mediaBreakdown = "\(summary.photosFound) photo\(summary.photosFound == 1 ? "" : "s"), \(summary.videosFound) video\(summary.videosFound == 1 ? "" : "s")"
        return title + ". " + details.joined(separator: ", ") + ". Found \(mediaBreakdown)."
    }

    func revealInFinder(_ item: MediaItem) {
        guard let url = mediaURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func viewInViewer(_ item: MediaItem) {
        selectedMediaItem = item
        showingViewer = true
    }

    func selectSingleMediaItem(_ item: MediaItem) {
        selectedMediaItem = item
        selectedMediaItemIDs.removeAll()
        lastSelectedMediaItemID = item.id
    }

    func toggleMediaSelection(_ item: MediaItem) {
        if selectedMediaItemIDs.isEmpty,
           let selectedMediaItem,
           selectedMediaItem.id != item.id {
            selectedMediaItemIDs.insert(selectedMediaItem.id)
        }

        if selectedMediaItemIDs.contains(item.id) {
            selectedMediaItemIDs.remove(item.id)
        } else {
            selectedMediaItemIDs.insert(item.id)
        }

        selectedMediaItem = item
        lastSelectedMediaItemID = item.id
    }

    func extendMediaSelection(to item: MediaItem, in items: [MediaItem]) {
        guard let anchorID = lastSelectedMediaItemID,
              let anchorIndex = items.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = items.firstIndex(where: { $0.id == item.id }) else {
            selectedMediaItemIDs.insert(item.id)
            selectedMediaItem = item
            lastSelectedMediaItemID = item.id
            return
        }

        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedMediaItemIDs.formUnion(items[bounds].map(\.id))
        selectedMediaItem = item
    }

    func selectAllVisibleItems() {
        let items = visibleItemsForSelection()
        selectedMediaItemIDs = Set(items.map(\.id))
        if selectedMediaItem == nil {
            selectedMediaItem = items.first
        }
        lastSelectedMediaItemID = selectedMediaItem?.id ?? items.first?.id
    }

    func clearMediaSelection() {
        selectedMediaItemIDs.removeAll()
        isSelectionModeEnabled = false
        lastSelectedMediaItemID = selectedMediaItem?.id
    }

    func toggleSelectionMode() {
        isSelectionModeEnabled.toggle()

        if isSelectionModeEnabled {
            let visibleItems = visibleItemsForSelection()
            if let selectedMediaItem,
               visibleItems.contains(where: { $0.id == selectedMediaItem.id }) {
                selectedMediaItemIDs.insert(selectedMediaItem.id)
                lastSelectedMediaItemID = selectedMediaItem.id
            }
        } else {
            clearMediaSelection()
        }
    }

    func selectedMediaItems(in items: [MediaItem]) -> [MediaItem] {
        items.filter { selectedMediaItemIDs.contains($0.id) }
    }

    func selectedOrCurrentVisibleItems() -> [MediaItem] {
        let visibleItems = visibleItemsForSelection()
        let selectedItems = selectedMediaItems(in: visibleItems)
        if !selectedItems.isEmpty {
            return selectedItems
        }

        if let selectedMediaItem, visibleItems.contains(where: { $0.id == selectedMediaItem.id }) {
            return [selectedMediaItem]
        }

        return []
    }

    func requestDelete(_ item: MediaItem) {
        pendingDeleteItem = item
    }

    func requestDeleteSelectedMediaItems() {
        let items = selectedOrCurrentVisibleItems()
        guard !items.isEmpty else { return }

        if items.count == 1, let item = items.first {
            requestDelete(item)
        } else {
            pendingBatchDeleteContext = .selection
            pendingBatchDeleteItems = items
        }
    }

    func deletePendingMediaItem() async {
        guard let item = pendingDeleteItem else { return }
        await deleteMediaItem(item)
    }

    func deleteMediaItem(_ item: MediaItem) async {
        guard let fileURL = mediaURL(for: item), let database else {
            userMessage = "Open a catalogue before moving an item to Trash."
            pendingDeleteItem = nil
            return
        }

        do {
            let originalExists = FileManager.default.fileExists(atPath: fileURL.path)
            if originalExists {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL)
            }

            try database.deleteMediaItem(relativePath: item.relativePath)

            selectedMediaItemIDs.remove(item.id)
            if selectedMediaItem?.id == item.id {
                selectedMediaItem = nil
                showingViewer = false
            }

            pendingDeleteItem = nil
            mediaMutationRevision += 1
            await loadTimeline()

            if selectedMediaItem == nil {
                selectedMediaItem = visibleItemsForSelection().first
            }

            userMessage = originalExists
                ? "Moved \(item.filename) to Trash."
                : "Removed missing item from the catalogue."
        } catch {
            pendingDeleteItem = nil
            userMessage = "Could not move \(item.filename) to Trash: \(error.localizedDescription)"
        }
    }

    func deleteMediaItems(_ items: [MediaItem]) async {
        guard let database else {
            userMessage = "Open a catalogue before moving items to Trash."
            pendingBatchDeleteItems = []
            return
        }

        var deletedIDs = Set<Int64>()
        var deletedCount = 0
        var missingCount = 0
        var failedCount = 0

        for item in items {
            guard let fileURL = mediaURL(for: item) else {
                failedCount += 1
                continue
            }

            do {
                let originalExists = FileManager.default.fileExists(atPath: fileURL.path)
                if originalExists {
                    var trashedURL: NSURL?
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL)
                    deletedCount += 1
                } else {
                    missingCount += 1
                }

                try database.deleteMediaItem(relativePath: item.relativePath)
                deletedIDs.insert(item.id)
            } catch {
                failedCount += 1
            }
        }

        selectedMediaItemIDs.subtract(deletedIDs)
        if let selectedMediaItem, deletedIDs.contains(selectedMediaItem.id) {
            self.selectedMediaItem = nil
            showingViewer = false
        }

        pendingBatchDeleteItems = []
        pendingBatchDeleteContext = .selection
        mediaMutationRevision += 1
        await loadTimeline()

        if selectedMediaItem == nil {
            selectedMediaItem = visibleItemsForSelection().first
        }

        userMessage = deletionSummary(deletedCount: deletedCount, missingCount: missingCount, failedCount: failedCount)
    }

    func copySelectedMediaItems() {
        copyMediaItems(selectedOrCurrentVisibleItems())
    }

    func copyMediaItems(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        guard !activeMediaSources.isEmpty else {
            userMessage = "Open a catalogue before copying originals."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = items.count == 1 ? "Copy Here" : "Copy \(items.count) Items Here"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        var copiedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for item in items {
            guard let source = mediaURL(for: item) else {
                skippedCount += 1
                continue
            }
            guard FileManager.default.fileExists(atPath: source.path) else {
                skippedCount += 1
                continue
            }

            do {
                let target = uniqueDestinationURL(for: item.filename, in: destination)
                try FileManager.default.copyItem(at: source, to: target)
                copiedCount += 1
            } catch {
                failedCount += 1
            }
        }

        userMessage = copySummary(copiedCount: copiedCount, skippedCount: skippedCount, failedCount: failedCount, destinationName: destination.lastPathComponent)
    }

    func requestRenameSelectedMediaItems() {
        let items = selectedOrCurrentVisibleItems()
        guard !items.isEmpty else { return }
        renameItems = items
        showingRenameSheet = true
    }

    func renameMediaItems(_ items: [MediaItem], baseName rawBaseName: String) async {
        guard let database else {
            userMessage = "Open a catalogue before renaming originals."
            showingRenameSheet = false
            renameItems = []
            return
        }

        let baseName = sanitizedFileStem(rawBaseName)
        guard !baseName.isEmpty else {
            userMessage = "Enter a valid file name before renaming."
            return
        }

        var plans: [(item: MediaItem, source: URL, target: URL, sourceRoot: URL, sourcePrefix: String)] = []
        var plannedTargets = Set<String>()

        do {
            for (index, item) in items.enumerated() {
                guard let catalogueSource = source(for: item),
                      let source = mediaURL(for: item) else {
                    throw BatchMediaOperationError.missingOriginal(item.filename)
                }
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw BatchMediaOperationError.missingOriginal(item.filename)
                }

                let extensionText = source.pathExtension
                let stem = items.count == 1 ? baseName : "\(baseName) \(String(format: "%03d", index + 1))"
                let filename = extensionText.isEmpty ? stem : "\(stem).\(extensionText)"
                let target = source.deletingLastPathComponent().appendingPathComponent(filename)

                if source.standardizedFileURL.path == target.standardizedFileURL.path {
                    continue
                }

                guard plannedTargets.insert(target.standardizedFileURL.path).inserted else {
                    throw BatchMediaOperationError.duplicateTarget(filename)
                }

                if FileManager.default.fileExists(atPath: target.path) {
                    throw BatchMediaOperationError.targetExists(filename)
                }

                plans.append((item, source, target, catalogueSource.rootURL, catalogueSource.relativePrefix))
            }

            guard !plans.isEmpty else {
                showingRenameSheet = false
                renameItems = []
                userMessage = "No files were renamed because the names are already current."
                return
            }

            var renamedIDs = Set<Int64>()
            for plan in plans {
                try FileManager.default.moveItem(at: plan.source, to: plan.target)
                let attributes = try FileManager.default.attributesOfItem(atPath: plan.target.path)
                let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? plan.item.fileSize
                let newRelativePath = catalogueRelativePath(
                    for: plan.target,
                    rootURL: plan.sourceRoot,
                    sourcePrefix: plan.sourcePrefix
                )
                try database.updateMediaLocation(
                    id: plan.item.id,
                    relativePath: newRelativePath,
                    folderPath: Self.folderPath(for: newRelativePath),
                    filename: plan.target.lastPathComponent,
                    fileSize: size,
                    modifiedAt: modifiedAt
                )
                renamedIDs.insert(plan.item.id)
            }

            selectedMediaItemIDs.subtract(renamedIDs)
            showingRenameSheet = false
            renameItems = []
            mediaMutationRevision += 1
            await loadTimeline()
            selectedMediaItem = visibleItemsForSelection().first
            userMessage = "Renamed \(plans.count) original file\(plans.count == 1 ? "" : "s") and updated the catalogue."
        } catch {
            userMessage = "The original files could not be renamed. \(error.localizedDescription)"
        }
    }

    func findDuplicates() async {
        guard let database else {
            userMessage = "Open a catalogue before finding duplicates."
            return
        }

        isFindingDuplicates = true
        duplicateScanStatus = "Preparing duplicate review"
        defer {
            isFindingDuplicates = false
            duplicateScanStatus = ""
        }

        do {
            let candidates = try database.fetchDuplicateHashCandidates()
            var hashedCount = 0
            var missingCount = 0
            var failedCount = 0

            for (index, item) in candidates.enumerated() {
                if Task.isCancelled { break }

                duplicateScanStatus = "Checking \(index + 1) of \(candidates.count): \(item.filename)"
                guard let fileURL = mediaURL(for: item) else {
                    missingCount += 1
                    continue
                }

                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    missingCount += 1
                    continue
                }

                do {
                    let hash = try await Task.detached(priority: .utility) {
                        try Self.sha256HexDigest(for: fileURL)
                    }.value
                    try database.updateContentHash(id: item.id, contentHash: hash)
                    hashedCount += 1
                } catch {
                    failedCount += 1
                }
            }

            duplicateGroups = try database.fetchDuplicateGroups()
            duplicateGroupCount = duplicateGroups.count
            selectedDuplicateGroupID = duplicateGroups.first?.id

            let reclaimable = ByteCountFormatter.string(
                fromByteCount: duplicateGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes },
                countStyle: .file
            )

            if duplicateGroups.isEmpty {
                userMessage = "No exact duplicates found. Checked \(hashedCount) candidate item\(hashedCount == 1 ? "" : "s") by content hash."
            } else {
                var message = "Found \(duplicateGroups.count) exact duplicate group\(duplicateGroups.count == 1 ? "" : "s") with about \(reclaimable) recoverable."
                if missingCount > 0 || failedCount > 0 {
                    var issues: [String] = []
                    if missingCount > 0 {
                        issues.append("\(missingCount) original\(missingCount == 1 ? " was" : "s were") unavailable")
                    }
                    if failedCount > 0 {
                        issues.append("\(failedCount) file\(failedCount == 1 ? "" : "s") could not be read")
                    }
                    message += " " + issues.joined(separator: "; ") + "."
                }
                userMessage = message
            }
        } catch {
            userMessage = "Could not find duplicates: \(error.localizedDescription)"
        }
    }

    func refreshDuplicateGroups() {
        guard let database else {
            duplicateGroups = []
            duplicateGroupCount = 0
            selectedDuplicateGroupID = nil
            return
        }

        do {
            duplicateGroups = try database.fetchDuplicateGroups()
            duplicateGroupCount = duplicateGroups.count
            if let selectedDuplicateGroupID, duplicateGroups.contains(where: { $0.id == selectedDuplicateGroupID }) {
                return
            }
            selectedDuplicateGroupID = duplicateGroups.first?.id
        } catch {
            duplicateGroups = []
            duplicateGroupCount = 0
            selectedDuplicateGroupID = nil
        }
    }

    func keepSuggestedDuplicateGroup(_ group: DuplicateGroup) {
        guard let keeper = group.suggestedKeeper else { return }
        pendingBatchDeleteContext = .duplicateGroup
        pendingBatchDeleteItems = group.itemsToDelete(keeping: keeper)
    }

    func mergeAllDuplicateGroups() {
        let items = duplicateGroups.flatMap(\.duplicateItems)
        guard !items.isEmpty else {
            userMessage = "No extra duplicate copies are available."
            return
        }

        pendingBatchDeleteContext = .allDuplicates
        pendingBatchDeleteItems = items
    }

    func refreshAppStorageReport() async {
        guard !isLoadingAppStorageReport else { return }

        refreshSavedCatalogues()
        let catalogues = savedCatalogues
        let activeRootURL = activeCatalogue.map { URL(fileURLWithPath: $0.path, isDirectory: true) } ?? selectedRootURL
        let activeDuplicateGroupCount = duplicateGroupCount
        let bookmarkBytes = bookmarkStore.storedBookmarkByteCount()

        isLoadingAppStorageReport = true
        defer { isLoadingAppStorageReport = false }

        let report = await Task.detached(priority: .utility) {
            AppStorageInspector.buildReport(
                savedCatalogues: catalogues,
                activeRootURL: activeRootURL,
                activeDuplicateGroupCount: activeDuplicateGroupCount,
                bookmarkBytes: bookmarkBytes
            )
        }.value

        appStorageReport = report
    }

    func revealActiveCatalogueFolder() {
        guard let catalogueURL else {
            userMessage = "Open a catalogue before revealing catalogue storage."
            return
        }

        let catalogueDirectory = catalogueURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([catalogueDirectory])
    }

    func clearActiveThumbnailCaches() async {
        guard let catalogueRootURL else {
            userMessage = "Open a catalogue before clearing thumbnail caches."
            return
        }

        isClearingAppCaches = true
        defer { isClearingAppCaches = false }

        do {
            let paths = CataloguePaths(rootURL: catalogueRootURL)
            try await Task.detached(priority: .utility) {
                let manager = FileManager.default
                if manager.fileExists(atPath: paths.thumbnailsDirectory.path) {
                    try manager.removeItem(at: paths.thumbnailsDirectory)
                }
                if manager.fileExists(atPath: paths.videoThumbnailsDirectory.path) {
                    try manager.removeItem(at: paths.videoThumbnailsDirectory)
                }
                try manager.createDirectory(at: paths.thumbnailsDirectory, withIntermediateDirectories: true)
                try manager.createDirectory(at: paths.videoThumbnailsDirectory, withIntermediateDirectories: true)
            }.value
            ThumbnailMemoryCache.shared.removeAll()
            await refreshAppStorageReport()
            userMessage = "Deleted the generated thumbnail cache. Original photos and videos are not changed. Choose Update Catalogue to rebuild previews."
        } catch {
            userMessage = "The thumbnail cache could not be deleted. \(error.localizedDescription) Original photos and videos are not changed."
        }
    }

    func compactActiveCatalogueDatabase() async {
        guard let database else {
            userMessage = "Open a catalogue before compacting the catalogue database."
            return
        }

        isCompactingCatalogue = true
        defer { isCompactingCatalogue = false }

        do {
            try database.compact()
            await refreshAppStorageReport()
            userMessage = "Compacted the catalogue database."
        } catch {
            userMessage = "Could not compact catalogue database: \(error.localizedDescription)"
        }
    }

    func keep(_ keeper: MediaItem, in group: DuplicateGroup) {
        pendingBatchDeleteContext = .duplicateGroup
        pendingBatchDeleteItems = group.itemsToDelete(keeping: keeper)
    }

    func shareOriginal(_ item: MediaItem) {
        guard let url = mediaURL(for: item),
              let contentView = NSApp.keyWindow?.contentView else {
            return
        }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    func showInTimeline(_ item: MediaItem) {
        searchText = ""
        selectedMediaItem = item
        selectedSection = .timeline
    }

    func showOnMap(_ item: MediaItem) {
        searchText = ""
        selectedMediaItem = item
        selectedSection = .places
    }

    func showInFolder(_ item: MediaItem) {
        searchText = ""
        focusedFolderPath = item.folderPath
        selectedMediaItem = item
        selectedSection = .folders
    }

    func selectAdjacentItem(offset: Int) {
        let visibleItems = visibleItemsForSelection()
        guard let selectedMediaItem,
              let index = visibleItems.firstIndex(where: { $0.id == selectedMediaItem.id }) else {
            self.selectedMediaItem = visibleItems.first
            selectedMediaItemIDs.removeAll()
            return
        }
        let newIndex = min(max(index + offset, 0), visibleItems.count - 1)
        self.selectedMediaItem = visibleItems[newIndex]
        selectedMediaItemIDs.removeAll()
        lastSelectedMediaItemID = visibleItems[newIndex].id
    }

    func copyOriginal(_ item: MediaItem) {
        copyMediaItems([item])
    }

    func mediaURL(for item: MediaItem) -> URL? {
        mediaURL(forRelativePath: item.relativePath)
    }

    func thumbnailURL(for path: String) -> URL? {
        catalogueRootURL?.appendingPathComponent(path)
    }

    func folderURL(forCatalogueFolderPath folderPath: String) -> URL? {
        mediaURL(forRelativePath: folderPath)
    }

    private func mediaURL(forRelativePath relativePath: String) -> URL? {
        guard let source = source(forRelativePath: relativePath) else { return nil }
        let suffix = relativeSuffix(forCataloguePath: relativePath, sourcePrefix: source.relativePrefix)
        guard !suffix.isEmpty else { return source.rootURL }
        return source.rootURL.appendingPathComponent(suffix)
    }

    private func source(for item: MediaItem) -> CatalogueSource? {
        source(forRelativePath: item.relativePath)
    }

    private func source(forRelativePath relativePath: String) -> CatalogueSource? {
        let sources = activeMediaSources.sorted {
            $0.relativePrefix.count > $1.relativePrefix.count
        }
        return sources.first { source in
            source.relativePrefix.isEmpty ||
            relativePath == source.relativePrefix ||
            relativePath.hasPrefix(source.relativePrefix + "/")
        }
    }

    private func source(forFolderURL folderURL: URL, in sources: [CatalogueSource]) -> CatalogueSource? {
        let standardizedURL = folderURL.standardizedFileURL
        return sources
            .filter { standardizedURL.isSameOrDescendant(of: $0.rootURL.standardizedFileURL) }
            .sorted { $0.rootPath.count > $1.rootPath.count }
            .first
    }

    private func relativeSuffix(forCataloguePath relativePath: String, sourcePrefix: String) -> String {
        let trimmedPrefix = sourcePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPrefix.isEmpty else { return relativePath }
        if relativePath == trimmedPrefix { return "" }
        if relativePath.hasPrefix(trimmedPrefix + "/") {
            return String(relativePath.dropFirst(trimmedPrefix.count + 1))
        }
        return relativePath
    }

    private func catalogueRelativePath(for fileURL: URL, rootURL: URL, sourcePrefix: String) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let suffix: String
        if filePath == rootPath {
            suffix = ""
        } else if filePath.hasPrefix(rootPath + "/") {
            suffix = String(filePath.dropFirst(rootPath.count + 1))
        } else {
            suffix = fileURL.lastPathComponent
        }

        let trimmedPrefix = sourcePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPrefix.isEmpty else { return suffix }
        return suffix.isEmpty ? trimmedPrefix : trimmedPrefix + "/" + suffix
    }

    private func deletionSummary(deletedCount: Int, missingCount: Int, failedCount: Int) -> String {
        var parts: [String] = []
        if deletedCount > 0 {
            parts.append("Moved \(deletedCount) item\(deletedCount == 1 ? "" : "s") to Trash")
        }
        if missingCount > 0 {
            parts.append("removed \(missingCount) missing catalogue item\(missingCount == 1 ? "" : "s")")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) item\(failedCount == 1 ? "" : "s") could not be moved to Trash")
        }
        return parts.isEmpty ? "No items changed." : parts.joined(separator: ", ") + "."
    }

    private func copySummary(copiedCount: Int, skippedCount: Int, failedCount: Int, destinationName: String) -> String {
        var parts: [String] = []
        if copiedCount > 0 {
            parts.append("Copied \(copiedCount) item\(copiedCount == 1 ? "" : "s") to \(destinationName)")
        }
        if skippedCount > 0 {
            parts.append("skipped \(skippedCount) missing original\(skippedCount == 1 ? "" : "s")")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) item\(failedCount == 1 ? "" : "s") could not be copied")
        }
        return parts.isEmpty ? "No items copied." : parts.joined(separator: ", ") + "."
    }

    private func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let originalURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension

        for index in 2...999 {
            let candidateName = pathExtension.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(pathExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(pathExtension)
    }

    private func sanitizedFileStem(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        return value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func storageRootForCatalogue(for folderURLs: [URL]) async -> URL? {
        guard let rootURL = preferredCatalogueStorageRoot(for: folderURLs) else {
            return nil
        }

        if rootURL.canHostDriveLensRootCatalogue {
            return rootURL
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = rootURL
        panel.prompt = "Allow Storage Root"
        panel.message = "Select the root of \(rootURL.lastPathComponent) so DriveLens can create .drivelens there."

        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            return nil
        }

        let selectedRootURL = selectedURL.storageRootURL.standardizedFileURL
        guard selectedURL.path == selectedRootURL.path, selectedRootURL.path == rootURL.path else {
            userMessage = "Select the storage root itself so DriveLens can keep .drivelens in one easy-to-find place."
            return nil
        }

        guard selectedRootURL.canHostDriveLensRootCatalogue else {
            userMessage = "DriveLens could not write to \(selectedRootURL.lastPathComponent). Check drive permissions and try again."
            return nil
        }

        return selectedRootURL
    }

    private func preferredCatalogueStorageRoot(for folderURLs: [URL]) -> URL? {
        var seen = Set<String>()
        return folderURLs
            .map { $0.storageRootURL.standardizedFileURL }
            .first { rootURL in
                seen.insert(rootURL.path).inserted && rootURL.isReachableDirectory
            }
    }

    private static func defaultCatalogueName(for folderURLs: [URL]) -> String {
        let folderNames = folderURLs
            .map { $0.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if folderNames.count == 1, let name = folderNames.first {
            return name
        }

        if folderNames.count > 1 {
            return "\(folderNames.count) Folders Catalogue"
        }

        return "Media Catalogue"
    }

    nonisolated private static func sha256HexDigest(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func runScan(rebuild: Bool, scopeURLs: [URL]? = nil) async -> Bool {
        if let activeCatalogue, activeCatalogue.isNamedCatalogue {
            let scopes: [(source: CatalogueSource, urls: [URL]?)] = activeCatalogue.sourceList.map { source in
                (source, nil)
            }
            return await runScan(rebuild: false, sourceScopes: scopes)
        }

        guard let rootURL = selectedRootURL else { return false }
        scanTask?.cancel()
        var completedSuccessfully = false

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                let paths = CataloguePaths(rootURL: rootURL)
                try paths.prepare()
                let db = try CatalogueDatabase(databaseURL: paths.databaseURL)
                let scanner = MediaScanner(rootURL: rootURL, paths: paths, database: db)

                await MainActor.run {
                    self.scanSummary = nil
                    self.scanProgress = ScanProgress()
                    self.userMessage = nil
                }

                let summary = try await scanner.scan(rebuild: rebuild, scopeURLs: scopeURLs) { progress in
                    Task { @MainActor in
                        self.scanProgress = progress
                    }
                }
                _ = try db.repairLivePhotoPairs()

                await MainActor.run {
                    self.database = db
                    self.scanProgress = nil
                    self.scanSummary = summary
                    self.userMessage = Self.scanCompletionMessage(
                        summary: summary,
                        rebuild: rebuild,
                        scopeCount: scopeURLs?.count
                    )
                }
                await self.loadTimeline()
                completedSuccessfully = true
            } catch is CancellationError {
                await MainActor.run {
                    self.scanProgress = nil
                    self.userMessage = "Catalogue update cancelled. Choose Update Catalogue when you are ready to continue."
                }
            } catch {
                await MainActor.run {
                    self.scanProgress = nil
                    self.userMessage = "The catalogue update stopped. \(error.localizedDescription) Original photos and videos are not changed."
                    self.ssdStatus = rootURL.isReachableDirectory ? .connected : .disconnected
                }
            }
        }

        await scanTask?.value
        scanTask = nil
        return completedSuccessfully
    }

    @discardableResult
    private func runScan(rebuild: Bool, sources: [CatalogueSource]) async -> Bool {
        let scopes: [(source: CatalogueSource, urls: [URL]?)] = sources.map { ($0, nil) }
        return await runScan(rebuild: rebuild, sourceScopes: scopes)
    }

    @discardableResult
    private func runScan(rebuild: Bool, sourceScopes: [(source: CatalogueSource, urls: [URL]?)]) async -> Bool {
        guard let activeCatalogue, activeCatalogue.isNamedCatalogue else { return false }
        let reachableScopes = sourceScopes.filter { $0.source.rootURL.isReachableDirectory }
        guard !reachableScopes.isEmpty else {
            userMessage = "Connect the storage device to continue. None of the imported folders are currently available."
            return false
        }

        scanTask?.cancel()
        var completedSuccessfully = false
        let catalogueRoot = URL(fileURLWithPath: activeCatalogue.path, isDirectory: true)

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                let paths = CataloguePaths(rootURL: catalogueRoot)
                try paths.prepare()
                let db = try CatalogueDatabase(databaseURL: paths.databaseURL)

                await MainActor.run {
                    self.scanSummary = nil
                    self.scanProgress = ScanProgress()
                    self.userMessage = nil
                }

                var summaries: [ScanSummary] = []
                let totalScopes = reachableScopes.count

                for (scopeIndex, sourceScope) in reachableScopes.enumerated() {
                    try Task.checkCancellation()
                    let completedFilesScanned = summaries.reduce(0) { $0 + $1.filesScanned }
                    let completedFilesDiscovered = summaries.reduce(0) { $0 + $1.filesDiscovered }
                    let completedPhotos = summaries.reduce(0) { $0 + $1.photosFound }
                    let completedVideos = summaries.reduce(0) { $0 + $1.videosFound }
                    let completedNewFiles = summaries.reduce(0) { $0 + $1.newFiles }
                    let completedAlreadyIndexed = summaries.reduce(0) { $0 + $1.alreadyIndexedFiles }
                    let completedRefreshed = summaries.reduce(0) { $0 + $1.refreshedFiles }
                    let completedMissing = summaries.reduce(0) { $0 + $1.missingFiles }
                    let completedUnsupported = summaries.reduce(0) { $0 + $1.unsupportedFiles }
                    let completedErrors = summaries.reduce(0) { $0 + $1.errors }
                    let scanner = MediaScanner(
                        rootURL: sourceScope.source.rootURL,
                        paths: paths,
                        database: db,
                        sourcePrefix: sourceScope.source.relativePrefix
                    )
                    let summary = try await scanner.scan(rebuild: false, scopeURLs: sourceScope.urls) { progress in
                        Task { @MainActor in
                            var labelledProgress = progress
                            labelledProgress.currentFilename = sourceScope.source.name + (progress.currentFilename.isEmpty ? "" : " / " + progress.currentFilename)
                            labelledProgress.filesScanned += completedFilesScanned
                            labelledProgress.totalFilesDiscovered += completedFilesDiscovered
                            labelledProgress.photosFound += completedPhotos
                            labelledProgress.videosFound += completedVideos
                            labelledProgress.newFiles += completedNewFiles
                            labelledProgress.alreadyIndexedFiles += completedAlreadyIndexed
                            labelledProgress.refreshedFiles += completedRefreshed
                            labelledProgress.missingFiles += completedMissing
                            labelledProgress.unsupportedFiles += completedUnsupported
                            labelledProgress.errors += completedErrors
                            if totalScopes > 1 {
                                labelledProgress.currentFilename = "Folder \(scopeIndex + 1) of \(totalScopes): " + labelledProgress.currentFilename
                            }
                            self.scanProgress = labelledProgress
                        }
                    }
                    summaries.append(summary)
                }

                _ = try db.repairLivePhotoPairs()
                let summary = Self.combinedScanSummary(summaries)

                await MainActor.run {
                    self.database = db
                    self.scanProgress = nil
                    self.scanSummary = summary
                    self.markSourcesScanned(reachableScopes.map { $0.source.id })
                    self.userMessage = Self.scanCompletionMessage(
                        summary: summary,
                        rebuild: rebuild,
                        scopeCount: reachableScopes.count
                    )
                    self.ssdStatus = .connected
                }
                await self.loadTimeline()
                completedSuccessfully = true
            } catch is CancellationError {
                await MainActor.run {
                    self.scanProgress = nil
                    self.userMessage = "Catalogue update cancelled. Choose Update Catalogue when you are ready to continue."
                }
            } catch {
                await MainActor.run {
                    self.scanProgress = nil
                    self.userMessage = "The catalogue update stopped. \(error.localizedDescription) Original photos and videos are not changed."
                    self.ssdStatus = reachableScopes.contains { $0.source.rootURL.isReachableDirectory } ? .connected : .disconnected
                }
            }
        }

        await scanTask?.value
        scanTask = nil
        return completedSuccessfully
    }

    private func markSourcesScanned(_ sourceIDs: [CatalogueSource.ID]) {
        guard var catalogue = activeCatalogue, catalogue.isNamedCatalogue else { return }
        let scannedIDs = Set(sourceIDs)
        let now = Date()
        catalogue.sources = catalogue.sourceList.map { source in
            var updated = source
            if scannedIDs.contains(source.id) {
                updated.lastScannedAt = now
            }
            return updated
        }
        activeCatalogue = catalogue
        bookmarkStore.saveCatalogue(catalogue)
        refreshSavedCatalogues()
    }

    private func openCatalogue(at rootURL: URL) throws {
        try CataloguePaths(rootURL: rootURL).prepare()
        let paths = CataloguePaths(rootURL: rootURL)
        let openedDatabase = try CatalogueDatabase(databaseURL: paths.databaseURL)
        try openedDatabase.repairLivePhotoPairs()
        database = openedDatabase
        ssdStatus = rootURL.isReachableDirectory ? .connected : .disconnected
    }

    private func openCatalogue(_ catalogue: SavedCatalogue) throws {
        let rootURL = URL(fileURLWithPath: catalogue.path, isDirectory: true)
        try CataloguePaths(rootURL: rootURL).prepare()
        let openedDatabase = try CatalogueDatabase(databaseURL: catalogue.databaseURL)
        try openedDatabase.repairLivePhotoPairs()
        database = openedDatabase
        ssdStatus = catalogue.sourceList.isEmpty || catalogue.sourceList.contains { $0.rootURL.isReachableDirectory } ? .connected : .disconnected
    }

    private func resolveSources(for catalogue: SavedCatalogue) -> SavedCatalogue {
        var updated = catalogue
        if catalogue.isNamedCatalogue, let bookmarkData = catalogue.bookmarkData {
            do {
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                updated.path = url.standardizedFileURL.path
                if stale {
                    updated.bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
            } catch {
                updated.path = catalogue.path
            }
        }

        let resolvedSources = catalogue.sourceList.map { source in
            guard let bookmarkData = source.bookmarkData else { return source }
            do {
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                var resolved = source
                resolved.rootPath = url.standardizedFileURL.path
                if stale {
                    resolved.bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                return resolved
            } catch {
                return source
            }
        }
        updated.sources = resolvedSources
        return updated
    }

    private func beginAccessing(_ url: URL) {
        stopAccessingSecurityScopedResources()

        accessURL = url
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        ssdStatus = url.isReachableDirectory ? .connected : .disconnected
    }

    private func beginAccessingSources(_ sources: [CatalogueSource]) {
        stopAccessingSecurityScopedResources()
        sourceAccessURLs = sources.map(\.rootURL)
        for url in sourceAccessURLs {
            _ = url.startAccessingSecurityScopedResource()
        }
        if let activeCatalogue {
            beginAccessingCatalogueStorage(activeCatalogue)
        }
        ssdStatus = sourceAccessURLs.isEmpty || sourceAccessURLs.contains { $0.isReachableDirectory } ? .connected : .disconnected
    }

    private func beginAccessingCatalogueStorage(_ catalogue: SavedCatalogue) {
        guard let bookmarkData = catalogue.cataloguesDirectoryBookmarkData ?? catalogue.bookmarkData else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return
        }
        catalogueAccessURL = url
        _ = url.startAccessingSecurityScopedResource()
    }

    private func stopAccessingSecurityScopedResources() {
        if isAccessingSecurityScope, let accessURL {
            accessURL.stopAccessingSecurityScopedResource()
        }
        for url in sourceAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        catalogueAccessURL?.stopAccessingSecurityScopedResource()
        accessURL = nil
        sourceAccessURLs = []
        catalogueAccessURL = nil
        isAccessingSecurityScope = false
    }
}

private extension AppState {
    static func combinedScanSummary(_ summaries: [ScanSummary]) -> ScanSummary {
        guard let first = summaries.first else {
            let now = Date()
            return ScanSummary(
                filesDiscovered: 0,
                filesScanned: 0,
                photosFound: 0,
                videosFound: 0,
                newFiles: 0,
                alreadyIndexedFiles: 0,
                refreshedFiles: 0,
                missingFiles: 0,
                unsupportedFiles: 0,
                errors: 0,
                startedAt: now,
                completedAt: now,
                status: "completed"
            )
        }

        return ScanSummary(
            filesDiscovered: summaries.reduce(0) { $0 + $1.filesDiscovered },
            filesScanned: summaries.reduce(0) { $0 + $1.filesScanned },
            photosFound: summaries.reduce(0) { $0 + $1.photosFound },
            videosFound: summaries.reduce(0) { $0 + $1.videosFound },
            newFiles: summaries.reduce(0) { $0 + $1.newFiles },
            alreadyIndexedFiles: summaries.reduce(0) { $0 + $1.alreadyIndexedFiles },
            refreshedFiles: summaries.reduce(0) { $0 + $1.refreshedFiles },
            missingFiles: summaries.reduce(0) { $0 + $1.missingFiles },
            unsupportedFiles: summaries.reduce(0) { $0 + $1.unsupportedFiles },
            errors: summaries.reduce(0) { $0 + $1.errors },
            startedAt: summaries.map(\.startedAt).min() ?? first.startedAt,
            completedAt: summaries.compactMap(\.completedAt).max(),
            status: summaries.contains { $0.status != "completed" } ? "partial" : "completed"
        )
    }
}

enum SSDStatus: Equatable {
    case notSelected
    case connected
    case disconnected
    case permissionLost
    case catalogueCorrupted

    var title: String {
        switch self {
        case .notSelected: "No catalogue selected"
        case .connected: "Storage connected"
        case .disconnected: "Storage disconnected"
        case .permissionLost: "Permission needed"
        case .catalogueCorrupted: "Catalogue problem"
        }
    }

    var systemImage: String {
        switch self {
        case .connected: "externaldrive.fill"
        case .disconnected: "externaldrive.badge.xmark"
        case .permissionLost: "lock.trianglebadge.exclamationmark"
        case .catalogueCorrupted: "exclamationmark.triangle"
        case .notSelected: "externaldrive"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .disconnected, .permissionLost, .catalogueCorrupted:
            return true
        case .notSelected, .connected:
            return false
        }
    }
}

enum BatchDeleteContext: Equatable {
    case selection
    case duplicateGroup
    case allDuplicates

    func dialogTitle(count: Int) -> String {
        switch self {
        case .selection:
            return count == 1 ? "Move item to Trash?" : "Move selected items to Trash?"
        case .duplicateGroup:
            return "Move duplicate copies to Trash?"
        case .allDuplicates:
            return "Move extra duplicate copies to Trash?"
        }
    }

    func buttonTitle(count: Int) -> String {
        "Move to Trash"
    }

    func message(count: Int) -> String {
        switch self {
        case .selection:
            return "This moves \(count) original file\(count == 1 ? "" : "s") to Trash and removes the corresponding catalogue record\(count == 1 ? "" : "s")."
        case .duplicateGroup:
            return "DriveLens keeps the suggested or chosen original and moves \(count) duplicate cop\(count == 1 ? "y" : "ies") to Trash."
        case .allDuplicates:
            return "DriveLens keeps one suggested original from each group and moves \(count) duplicate cop\(count == 1 ? "y" : "ies") to Trash."
        }
    }
}

private enum BatchMediaOperationError: LocalizedError {
    case missingOriginal(String)
    case duplicateTarget(String)
    case targetExists(String)

    var errorDescription: String? {
        switch self {
        case .missingOriginal(let filename):
            return "Could not rename because \(filename) is missing."
        case .duplicateTarget(let filename):
            return "The rename pattern would create duplicate file name \(filename)."
        case .targetExists(let filename):
            return "A file named \(filename) already exists in that folder."
        }
    }
}

private extension URL {
    var isReachableDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var isWritableDirectory: Bool {
        isReachableDirectory && FileManager.default.isWritableFile(atPath: path)
    }

    var storageRootURL: URL {
        let ownPath = standardizedFileURL.path
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        ) ?? []

        return volumes
            .map(\.standardizedFileURL)
            .filter { volumeURL in
                let volumePath = volumeURL.path
                return ownPath == volumePath || ownPath.hasPrefix(volumePath == "/" ? "/" : volumePath + "/")
            }
            .sorted { $0.path.count > $1.path.count }
            .first ?? standardizedFileURL
    }

    var canHostDriveLensRootCatalogue: Bool {
        guard isReachableDirectory else { return false }
        let probeDirectory = appendingPathComponent(".drivelens", isDirectory: true)
            .appendingPathComponent(".write-check-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: probeDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: probeDirectory)
            return true
        } catch {
            return false
        }
    }

    var isMacApplicationSupportCatalogueStorage: Bool {
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
        let ownPath = standardizedFileURL.path
        return ownPath == catalogueRoot || ownPath.hasPrefix(catalogueRoot + "/")
    }

    func isSameOrDescendant(of rootURL: URL) -> Bool {
        let path = standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
