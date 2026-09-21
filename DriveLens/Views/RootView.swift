import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        ZStack {
            Group {
                if appState.hasCompletedOnboarding {
                    mainInterface
                } else {
                    OnboardingView()
                }
            }
            // Keep the library mounted so closing preview restores its scroll and navigation state.
            .opacity(appState.showingViewer ? 0 : 1)
            .disabled(appState.showingViewer)
            .allowsHitTesting(!appState.showingViewer)
            .accessibilityHidden(appState.showingViewer)

            if appState.showingViewer {
                MediaViewer(closeAction: { appState.showingViewer = false })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("full-window-media-preview")
            }

            if let progress = appState.scanProgress, !appState.hasCompletedOnboarding {
                ScanProgressView(progress: progress) {
                    appState.cancelScan()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if let actionNotice = appState.actionNotice {
                ActionNotice(message: actionNotice)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .toolbar(appState.showingViewer ? .hidden : .automatic, for: .windowToolbar)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .alert("DriveLens", isPresented: Binding(
            get: { appState.userMessage != nil },
            set: { if !$0 { appState.userMessage = nil } }
        )) {
            Button("OK") { appState.userMessage = nil }
        } message: {
            Text(appState.userMessage ?? "")
        }
        .sheet(isPresented: renameSheetBinding) {
            BatchRenameSheet(items: appState.renameItems)
                .environmentObject(appState)
                .frame(width: 440)
        }
        .sheet(isPresented: $appState.showingMissingRepairSheet) {
            MissingFileRepairSheet()
                .environmentObject(appState)
                .frame(width: 680, height: 520)
        }
        .confirmationDialog(
            "Choose folders again?",
            isPresented: $appState.showingResetConfirmation
        ) {
            Button("Choose Folders") {
                appState.resetMediaFolderSelection()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("DriveLens will close the current view and return to folder selection. Existing catalogue data and original photos and videos are not changed.")
        }
        .confirmationDialog(
            "Update catalogue?",
            isPresented: $appState.showingRescanConfirmation
        ) {
            Button("Update Catalogue") {
                Task { await appState.updateCatalogue() }
            }
            .disabled(!appState.canScan)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("DriveLens will scan the imported folders again and refresh new, changed, already indexed, and missing items. Original photos and videos are not changed.")
        }
        .confirmationDialog(
            "Move item to Trash?",
            isPresented: deleteConfirmationBinding,
            presenting: appState.pendingDeleteItem
        ) { item in
            Button("Move to Trash", role: .destructive) {
                Task { await appState.deleteMediaItem(item) }
            }
            Button("Cancel", role: .cancel) {
                appState.pendingDeleteItem = nil
            }
        } message: { item in
            Text("This moves the original file \(item.filename) to Trash and removes its catalogue record.")
        }
        .confirmationDialog(
            batchDeleteDialogTitle,
            isPresented: batchDeleteConfirmationBinding
        ) {
            Button(batchDeleteButtonTitle, role: .destructive) {
                let items = appState.pendingBatchDeleteItems
                Task { await appState.deleteMediaItems(items) }
            }
            Button("Cancel", role: .cancel) {
                appState.pendingBatchDeleteItems = []
                appState.pendingBatchDeleteContext = .selection
            }
        } message: {
            Text(batchDeleteMessage)
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarBrandHeader()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        SidebarNavigationSection("LIBRARY", sections: [.timeline, .places, .folders, .search])
                        SidebarNavigationSection("COLLECTIONS", sections: [.videos, .recentlyAdded, .smartAlbums, .duplicates])
                        SidebarNavigationSection("WORKSPACE", sections: [.appInfo])
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .navigationTitle("DriveLens")
                .background(LensTheme.sidebar)
                .onMoveCommand { direction in
                    let sections = SidebarSection.allCases
                    guard let index = sections.firstIndex(of: appState.selectedSection) else { return }
                    if direction == .up { appState.select(sections[max(0, index - 1)]) }
                    if direction == .down { appState.select(sections[min(sections.count - 1, index + 1)]) }
                }

                Divider()

                SidebarFooter(catalogue: appState.activeCatalogue, rootURL: appState.selectedRootURL, status: appState.ssdStatus, counts: appState.catalogueCounts) {
                    appState.requestMediaFolderReset()
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if appState.ssdStatus.needsAttention && appState.selectedSection != .appInfo {
                    StatusBanner(status: appState.ssdStatus) {
                        appState.requestMediaFolderReset()
                    }
                    .padding(.horizontal, LensHeaderMetrics.inset)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(LensTheme.canvas)
                }
                ZStack {
                    switch appState.selectedSection {
                    case .timeline:
                        TimelineView(
                            items: appState.filteredItems(),
                            counts: appState.countsForCurrentTimelineFilter(),
                            showsQuickFilters: true,
                            controlScope: .timeline
                        )
                    case .places:
                        PlacesView(items: appState.placeItems, clusters: appState.placeClusters, counts: appState.catalogueCounts)
                    case .folders:
                        FoldersView(items: appState.mediaItems, folders: appState.folderSummaries)
                    case .search:
                        SearchView()
                    case .videos:
                        TimelineView(
                            items: appState.videoItems,
                            title: "Videos",
                            counts: appState.countsForCurrentVideoFilter(),
                            showsQuickFilters: true,
                            controlScope: .videos
                        )
                    case .recentlyAdded:
                        TimelineView(
                            items: appState.recentlyAddedItems,
                            title: "Recently Added",
                            counts: appState.countsForCurrentRecentlyAddedFilter(),
                            showsQuickFilters: true,
                            controlScope: .recentlyAdded
                        )
                    case .smartAlbums:
                        SmartAlbumsView()
                    case .duplicates:
                        DuplicatesView()
                    case .appInfo:
                        AppInfoView()
                    }

                    if let progress = appState.scanProgress {
                        ScanProgressView(progress: progress) {
                            appState.cancelScan()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }

                }
            }
            .toolbar { LibraryWindowToolbar() }

        }
        .navigationSplitViewStyle(.balanced)
        .lensScrollEdges()
        .searchable(text: $appState.searchText, placement: .toolbar, prompt: "Search Catalogue")
        .onSubmit(of: .search) {
            appState.select(.search)
            appState.refreshSearch()
        }
        .onChange(of: appState.searchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appState.select(.search)
            }
            if appState.selectedSection != .search {
                appState.refreshSearch()
            }
        }
    }

    private var sidebarSelection: Binding<SidebarSection?> {
        Binding {
            appState.selectedSection
        } set: { newValue in
            if let newValue {
                appState.select(newValue)
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            appState.pendingDeleteItem != nil
        } set: { isPresented in
            if !isPresented {
                appState.pendingDeleteItem = nil
            }
        }
    }

    private var batchDeleteConfirmationBinding: Binding<Bool> {
        Binding {
            !appState.pendingBatchDeleteItems.isEmpty
        } set: { isPresented in
            if !isPresented {
                appState.pendingBatchDeleteItems = []
                appState.pendingBatchDeleteContext = .selection
            }
        }
    }

    private var renameSheetBinding: Binding<Bool> {
        Binding {
            appState.showingRenameSheet
        } set: { isPresented in
            appState.showingRenameSheet = isPresented
            if !isPresented {
                appState.renameItems = []
            }
        }
    }

    private var batchDeleteButtonTitle: String {
        let count = appState.pendingBatchDeleteItems.count
        return appState.pendingBatchDeleteContext.buttonTitle(count: count)
    }

    private var batchDeleteDialogTitle: String {
        appState.pendingBatchDeleteContext.dialogTitle(count: appState.pendingBatchDeleteItems.count)
    }

    private var batchDeleteMessage: String {
        appState.pendingBatchDeleteContext.message(count: appState.pendingBatchDeleteItems.count)
    }


}

/// Keep global catalogue commands in native window chrome; browsing controls live with their grid.
private struct LibraryWindowToolbar: ToolbarContent {
    @EnvironmentObject private var appState: AppState

    var body: some ToolbarContent {
        ToolbarItem(id: "catalogue", placement: .principal) {
            CatalogueToolbarMenu()
        }
        ToolbarItem(id: "update-catalogue", placement: .primaryAction) {
            Button {
                if appState.scanProgress != nil { appState.cancelScan() }
                else { appState.requestCatalogueUpdate() }
            } label: {
                Label(appState.scanProgress == nil ? "Update Catalogue" : "Cancel Update",
                      systemImage: appState.scanProgress == nil ? "arrow.triangle.2.circlepath" : "stop.circle")
            }
            .disabled(appState.scanProgress == nil && !appState.canScan)
            .help(appState.scanProgress == nil ? "Update Catalogue · ⇧⌘R" : "Cancel catalogue update")
            .accessibilityIdentifier("header-update")
        }
        ToolbarItem(id: "add-folders", placement: .primaryAction) {
            Button {
                Task { await appState.addFoldersToCurrentCatalogue() }
            } label: {
                Label("Add Folders", systemImage: "folder.badge.plus")
            }
            .disabled(!appState.canAddFoldersToCatalogue)
            .help("Add folders to this catalogue")
            .accessibilityIdentifier("header-add-folders")
        }
        if appState.selectedSection != .appInfo {
            ToolbarItem(id: "organize-media", placement: .primaryAction) {
                HeaderMediaActionsMenu(items: appState.selectedOrCurrentVisibleItems())
            }
            ToolbarItem(id: "toggle-inspector", placement: .primaryAction) {
                Button {
                    appState.showingInspector.toggle()
                } label: {
                    Label(appState.showingInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
                }
                .tint(appState.showingInspector ? .accentColor : .primary)
                .help(appState.showingInspector ? "Hide Inspector · ⌥⌘I" : "Show Inspector · ⌥⌘I")
                .accessibilityValue(appState.showingInspector ? "Visible" : "Hidden")
                .accessibilityIdentifier("header-inspector")
            }
        }
    }
}

private struct CatalogueToolbarMenu: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Menu {
            Section(appState.activeCatalogueName) {
                Text("\(appState.catalogueCounts.totalItems.formatted()) items · \(appState.ssdStatus.title)")
                Button("Update Catalogue", systemImage: "arrow.triangle.2.circlepath") { appState.requestCatalogueUpdate() }
                    .disabled(!appState.canScan)
                Button("Add Folders…", systemImage: "folder.badge.plus") {
                    Task { await appState.addFoldersToCurrentCatalogue() }
                }
                .disabled(!appState.canAddFoldersToCatalogue)
                Button("Update Folders…", systemImage: "folder.badge.gearshape") {
                    Task { await appState.chooseFoldersAndUpdateCatalogue() }
                }
                .disabled(!appState.canScan)
                Button("Repair Missing Files…", systemImage: "link.badge.plus") {
                    Task { await appState.openMissingFileRepair() }
                }
                .disabled(!appState.canRepairMissingFiles)
            }
            Divider()
            Button("Show Catalogue Storage", systemImage: "externaldrive") { appState.revealActiveCatalogueFolder() }
            Button("Storage & Privacy", systemImage: "info.circle") { appState.select(.appInfo) }
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
            Divider()
            Button("Switch Catalogue…", systemImage: "rectangle.stack") { appState.requestMediaFolderReset() }
        } label: {
            Label(toolbarTitle, systemImage: appState.ssdStatus.needsAttention
                  ? "externaldrive.badge.exclamationmark" : "externaldrive")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .help(appState.activeCatalogueName + " · " + (appState.scanProgress.map(scanSummary) ?? appState.ssdStatus.title)
              + "\nCatalogue actions, storage, and settings")
        .accessibilityLabel("Catalogue: " + appState.activeCatalogueName)
        .accessibilityValue(appState.scanProgress.map(scanSummary) ?? appState.ssdStatus.title)
        .accessibilityIdentifier("header-catalogue")
    }

    private var toolbarTitle: String {
        if let progress = appState.scanProgress { return scanSummary(progress) }
        // AppKit extracts a Menu's label for the native toolbar, bypassing SwiftUI frame limits.
        // Bound only the chrome title; the menu, tooltip, and accessibility retain the full name.
        let name = appState.activeCatalogueName
        return name.count > 24 ? String(name.prefix(17)) + "…" + String(name.suffix(6)) : name
    }

    private func scanSummary(_ progress: ScanProgress) -> String {
        guard progress.totalFilesDiscovered > 0 else { return "Discovering files…" }
        let fraction = min(1, max(0, Double(progress.filesScanned) / Double(progress.totalFilesDiscovered)))
        return "Updating · \(Int(fraction * 100))%"
    }
}

private struct HeaderMediaActionsMenu: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]
    @State private var showingNewAlbumSheet = false

    var body: some View {
        Menu {
            Button {
                Task { await appState.setFavorite(!allItemsAreFavorites, for: items) }
            } label: {
                Label(favoriteTitle, systemImage: favoriteSystemImage)
            }

            Menu {
                if appState.customAlbums.isEmpty {
                    Button("No Custom Albums") { }
                        .disabled(true)
                } else {
                    Section("Custom Albums") {
                        ForEach(appState.customAlbums) { album in
                            Button {
                                Task { await appState.addToCustomAlbum(named: album.name, items: items) }
                            } label: {
                                Label(album.name, systemImage: "rectangle.stack")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    showingNewAlbumSheet = true
                } label: {
                    Label("New Album…", systemImage: "plus")
                }
            } label: {
                Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.badge.plus")
                if items.count > 1 {
                    Text(items.count.formatted()).font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .controlSize(.regular)
        .disabled(items.isEmpty)
        .help("Organize selected media")
        .accessibilityLabel("Organize selected media")
        .accessibilityValue("\(items.count) selected")
        .accessibilityIdentifier("header-organize")
        .accessibilityHint("Mark as favorite or add selected media to an album.")
        .sheet(isPresented: $showingNewAlbumSheet) {
            NewAlbumForMediaSheet(items: items)
                .environmentObject(appState)
                .frame(width: 440)
        }
    }

    private var allItemsAreFavorites: Bool {
        !items.isEmpty && items.allSatisfy { appState.favoriteState(for: $0) }
    }

    private var favoriteTitle: String {
        allItemsAreFavorites ? "Remove from Favorites" : "Mark as Favorite"
    }

    private var favoriteSystemImage: String {
        allItemsAreFavorites ? "heart.slash" : "heart"
    }
}

private struct ActionNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .lensSurface(radius: 9)
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
    }
}

private struct BatchRenameSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    let items: [MediaItem]
    @State private var baseName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: items.count == 1 ? "pencil" : "text.cursor")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Base Name")
                    .font(.callout.weight(.medium))

                TextField("Enter file name", text: $baseName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit {
                        rename()
                    }
            }

            if items.count > 1 {
                Label("DriveLens keeps each original file extension and adds 001, 002, 003 in the current order.", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items.prefix(4), id: \.id) { item in
                        Label(item.filename, systemImage: item.kind == .video ? "film" : "photo")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if items.count > 4 {
                        Text("+ \(items.count - 4) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Cancel") {
                    close()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(title) {
                    rename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || items.isEmpty)
            }
        }
        .padding(22)
        .onAppear {
            baseName = suggestedBaseName
            isNameFocused = true
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        items.count == 1 ? "Rename Item" : "Rename \(items.count) Items"
    }

    private var subtitle: String {
        items.count == 1
            ? "Rename the original file and update its catalogue record."
            : "Rename selected originals in place and update their catalogue records."
    }

    private var suggestedBaseName: String {
        guard items.count == 1, let item = items.first else {
            return "DriveLens Media"
        }
        return URL(fileURLWithPath: item.filename).deletingPathExtension().lastPathComponent
    }

    private func rename() {
        let currentItems = items
        Task {
            await appState.renameMediaItems(currentItems, baseName: baseName)
        }
    }

    private func close() {
        appState.showingRenameSheet = false
        appState.renameItems = []
        dismiss()
    }
}

private struct MissingFileRepairSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .task {
            await appState.refreshMissingRepairCandidates()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Repair Missing Files")
                    .font(.title3.weight(.semibold))
                Text("Relink moved folders and remap catalogue paths without rescanning the entire library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(LensChrome())
    }

    @ViewBuilder
    private var content: some View {
        if appState.missingRepairCandidates.isEmpty {
            ContentUnavailableView {
                Label("No Missing Files", systemImage: "checkmark.circle")
            } description: {
                Text("Run Update Catalogue after moving or disconnecting files. Missing folders will appear here for quick relinking.")
            } actions: {
                Button {
                    Task { await appState.refreshMissingRepairCandidates() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                List(selection: $appState.selectedMissingRepairCandidateID) {
                    Section("Missing Folders") {
                        ForEach(appState.missingRepairCandidates) { candidate in
                            MissingFolderRepairRow(candidate: candidate)
                                .tag(candidate.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 250, idealWidth: 280)

                Divider()

                repairDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(LensTheme.canvas)
            }
        }
    }

    private var repairDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let candidate = appState.selectedMissingRepairCandidate {
                VStack(alignment: .leading, spacing: 5) {
                    Label(candidate.title, systemImage: candidate.folderPath.isEmpty ? "externaldrive" : "folder")
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Text("\(candidate.missingCount) missing item\(candidate.missingCount == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("How Relink Works")
                        .font(.callout.weight(.semibold))
                    Label("Choose the folder where these files live now.", systemImage: "1.circle")
                    Label("DriveLens matches the old folder structure by filename path and file size.", systemImage: "2.circle")
                    Label("Only catalogue paths are updated. Originals and metadata are not rewritten.", systemImage: "3.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample Files")
                        .font(.callout.weight(.semibold))
                    ForEach(candidate.sampleFilenames, id: \.self) { filename in
                        Label(filename, systemImage: "photo")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()
            } else {
                ContentUnavailableView("Choose a Missing Folder", systemImage: "folder.badge.questionmark")
            }
        }
        .padding(18)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await appState.refreshMissingRepairCandidates() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isRepairingMissingFiles)

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                Task { await appState.chooseReplacementFolderForMissingRepair() }
            } label: {
                if appState.isRepairingMissingFiles {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Relink Folder", systemImage: "link")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(appState.selectedMissingRepairCandidate == nil || appState.isRepairingMissingFiles)
        }
        .controlSize(.regular)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(LensChrome())
    }
}

private struct MissingFolderRepairRow: View {
    let candidate: MissingFolderRepairCandidate

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(candidate.missingCount)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text(candidate.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: candidate.folderPath.isEmpty ? "externaldrive" : "folder")
        }
        .padding(.vertical, 3)
        .accessibilityLabel("\(candidate.title), \(candidate.missingCount) missing items")
    }
}

private struct SidebarBrandHeader: View {
    var body: some View {
        DriveLensBrandLockup(
            logoSize: 32,
            titleFont: .title3.weight(.semibold),
            subtitle: "Your private photo library"
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarFooter: View {
    let catalogue: SavedCatalogue?
    let rootURL: URL?
    let status: SSDStatus
    let counts: CatalogueCounts
    let chooseDifferentFolder: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showsDetails.toggle() } label: {
                HStack(spacing: 9) {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(status.needsAttention ? Color.orange : Color.secondary)
                        .frame(width: 28, height: 32)
                        .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 12, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Text(status.needsAttention ? status.title : "\(counts.totalItems.formatted()) items")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: showsDetails ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Catalogue details")
            .accessibilityLabel("Catalogue: " + title)
            .accessibilityValue(showsDetails ? "Expanded" : "Collapsed")

            if showsDetails {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    SidebarFooterMetric(value: counts.photoLikeItems, label: "Photos")
                    SidebarFooterMetric(value: counts.videoLikeItems, label: "Videos")
                }
                Text(detailPath).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            if catalogue != nil || rootURL != nil {
                Button(action: chooseDifferentFolder) {
                    HStack {
                        Text("Switch Catalogue")
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(LensQuietButtonStyle())
                .help("Choose, open, or create a catalogue · ⇧⌘O")
            }
        }
        .padding(LensTheme.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LensTheme.sidebar)
    }

    private var title: String {
        catalogue?.name ?? rootURL?.lastPathComponent ?? "No catalogue selected"
    }

    private var subtitle: String {
        guard let catalogue else { return status.title }
        let sourceCount = catalogue.sourceList.count
        if sourceCount == 0 {
            return "Ready for folders"
        }
        return "\(sourceCount) folder\(sourceCount == 1 ? "" : "s") imported"
    }

    private var detailPath: String {
        if let catalogue, catalogue.isNamedCatalogue {
            return catalogue.sourceList.map(\.name).prefix(3).joined(separator: ", ")
        }
        return rootURL?.path ?? ""
    }
}

private struct StatusBadge: View {
    let status: SSDStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 7))
            .help(status.title)
    }

    private var foreground: Color {
        status == .connected ? .secondary : .orange
    }
}

private struct StatusBanner: View {
    let status: SSDStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: status.systemImage)
                .font(.callout.weight(.medium))

            Divider()
                .frame(height: 18)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .accessibilityElement(children: .contain)
    }

    private var message: String {
        switch status {
        case .disconnected:
            return "Connect the storage device to continue."
        case .permissionLost:
            return "DriveLens needs folder permission again. Choose the media folder to continue."
        case .catalogueCorrupted:
            return "The catalogue could not be read. Original photos and videos are not changed."
        case .notSelected:
            return "Choose folders to create or open a catalogue."
        case .connected:
            return "Storage connected."
        }
    }

    private var actionTitle: String {
        switch status {
        case .permissionLost:
            return "Choose Folder"
        case .disconnected, .catalogueCorrupted, .notSelected, .connected:
            return "Choose Catalogue"
        }
    }
}

private struct SidebarNavigationSection: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let sections: [SidebarSection]

    init(_ title: String, sections: [SidebarSection]) {
        self.title = title
        self.sections = sections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).lensEyebrow().padding(.horizontal, 10).padding(.bottom, 5)
            ForEach(sections) { section in
                Button { appState.select(section) } label: {
                    SidebarRow(section: section, count: appState.sidebarCount(for: section), isSelected: section == appState.selectedSection)
                }
                .buttonStyle(LensQuietButtonStyle())
                .accessibilityAddTraits(section == appState.selectedSection ? .isSelected : [])
            }
        }
    }
}

private struct SidebarRow: View {
    let section: SidebarSection
    let count: Int?
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(section.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count, count > 0 {
                Text(count.formatted(.number.notation(.compactName)))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 3).frame(height: LensTheme.rowHeight - 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7).fill(LensTheme.selectedFill)
                    .padding(.horizontal, -8).padding(.vertical, -6)
            }
        }
        .overlay {
            if isSelected && contrast == .increased {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 1)
                    .padding(.horizontal, -8).padding(.vertical, -6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title)
        .accessibilityValue(count.map { "\($0) items" } ?? "")
    }
}


private struct SidebarFooterMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
