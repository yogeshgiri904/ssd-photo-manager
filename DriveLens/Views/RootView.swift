import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Group {
                if appState.hasCompletedOnboarding {
                    mainInterface
                } else {
                    OnboardingView()
                }
            }

            if let progress = appState.scanProgress, !appState.hasCompletedOnboarding {
                ScanProgressView(progress: progress) {
                    appState.cancelScan()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(minWidth: 1060, minHeight: 680)
        .alert("DriveLens", isPresented: Binding(
            get: { appState.userMessage != nil },
            set: { if !$0 { appState.userMessage = nil } }
        )) {
            Button("OK") { appState.userMessage = nil }
        } message: {
            Text(appState.userMessage ?? "")
        }
        .sheet(isPresented: $appState.showingViewer) {
            if appState.selectedMediaItem != nil {
                MediaViewer()
                    .environmentObject(appState)
                    .frame(width: viewerModalSize.width, height: viewerModalSize.height)
            }
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
            Text("This moves \(item.filename) to the macOS Trash and removes its record from the DriveLens catalogue.")
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

                List(selection: sidebarSelection) {
                    ForEach(SidebarSection.allCases) { section in
                        SidebarRow(
                            section: section,
                            count: appState.sidebarCount(for: section)
                        )
                        .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("DriveLens")

                Divider()

                SidebarFooter(catalogue: appState.activeCatalogue, rootURL: appState.selectedRootURL, status: appState.ssdStatus, counts: appState.catalogueCounts) {
                    appState.requestMediaFolderReset()
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
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
                    TimelineView(items: appState.videoItems, title: "Videos", counts: appState.counts(for: .videos))
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

                if appState.ssdStatus.needsAttention {
                    StatusBanner(status: appState.ssdStatus)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    StatusBadge(status: appState.ssdStatus)

                    Menu {
                        Button {
                            Task { await appState.addFoldersToCurrentCatalogue() }
                        } label: {
                            Label("Add Folders to Catalogue...", systemImage: "folder.badge.plus")
                        }
                        .disabled(!appState.canAddFoldersToCatalogue)

                        Button {
                            appState.requestCatalogueUpdate()
                        } label: {
                            Label("Update Entire Catalogue", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!appState.canScan)

                        Button {
                            Task { await appState.chooseFoldersAndUpdateCatalogue() }
                        } label: {
                            Label("Update Folders...", systemImage: "folder.badge.gearshape")
                        }
                        .disabled(!appState.canScan)

                        Divider()

                        Button {
                            Task { await appState.openMissingFileRepair() }
                        } label: {
                            Label("Repair Missing Files...", systemImage: "link.badge.plus")
                        }
                        .disabled(!appState.canRepairMissingFiles)
                    } label: {
                        Label("Catalogue", systemImage: "rectangle.stack")
                    }
                    .labelStyle(.iconOnly)
                    .help("Catalogue actions")
                    .accessibilityLabel("Catalogue actions")

                    if appState.selectedSection != .appInfo {
                        Button {
                            appState.showingInspector.toggle()
                        } label: {
                            Label(appState.showingInspector ? "Hide Inspector" : "Show Inspector", systemImage: appState.showingInspector ? "sidebar.trailing" : "sidebar.right")
                        }
                        .labelStyle(.iconOnly)
                        .help(appState.showingInspector ? "Hide Inspector" : "Show Inspector")
                        .accessibilityLabel(appState.showingInspector ? "Hide Inspector" : "Show Inspector")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    TextField("Search", text: $appState.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .accessibilityLabel("Search catalogue")
                        .onSubmit {
                            appState.select(.search)
                            appState.refreshSearchResultCount()
                        }
                        .onChange(of: appState.searchText) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                appState.select(.search)
                            }
                            appState.refreshSearchResultCount()
                        }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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

    private var viewerModalSize: CGSize {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 820)
        return CGSize(
            width: max(980, frame.width * 0.94),
            height: max(640, frame.height * 0.90)
        )
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
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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
        .background(.bar)
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
                    .background(Color(nsColor: .textBackgroundColor))
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
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

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
        .background(.bar)
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
                    .font(.caption2)
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
            logoSize: 34,
            titleFont: .title3.weight(.semibold),
            subtitle: "Local media catalogue"
        )
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct SidebarFooter: View {
    let catalogue: SavedCatalogue?
    let rootURL: URL?
    let status: SSDStatus
    let counts: CatalogueCounts
    let chooseDifferentFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: status.systemImage)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if catalogue != nil || rootURL != nil {
                HStack(spacing: 10) {
                    SidebarFooterMetric(value: counts.totalItems, label: "Items")
                    SidebarFooterMetric(value: counts.photoLikeItems, label: "Photos")
                    SidebarFooterMetric(value: counts.videoLikeItems, label: "Videos")
                }
                .padding(.top, 2)

                Text(detailPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Button {
                    chooseDifferentFolder()
                } label: {
                    Label("Switch Catalogue", systemImage: "rectangle.stack.badge.person.crop")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.top, 4)
                .help("Choose, open, or create a catalogue")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
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

    var body: some View {
        Label(message, systemImage: status.systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 8, y: 2)
    }

    private var message: String {
        switch status {
        case .disconnected:
            return "Connect the storage device to continue viewing originals."
        case .permissionLost:
            return "DriveLens needs folder permission again. Choose the media folder to continue."
        case .catalogueCorrupted:
            return "The catalogue could not be read. Original photos and videos were not changed."
        case .notSelected:
            return "Choose folders to create or open a catalogue."
        case .connected:
            return "Storage connected."
        }
    }
}

private struct SidebarRow: View {
    let section: SidebarSection
    let count: Int?

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(section.title)
                Spacer(minLength: 8)
                countBadge
            }
        } icon: {
            Image(systemName: section.systemImage)
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 3)
        .accessibilityLabel(section.title)
    }

    @ViewBuilder
    private var countBadge: some View {
        if let count, count > 0 {
            Text(shortCount(count))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.55), in: Capsule())
                .accessibilityLabel("\(count) items")
        }
    }

    private func shortCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(value / 1_000_000)M"
        }
        if value >= 10_000 {
            return "\(value / 1_000)K"
        }
        return "\(value)"
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
