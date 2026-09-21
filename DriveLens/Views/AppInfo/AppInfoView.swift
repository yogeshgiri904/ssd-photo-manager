import SwiftUI

struct AppInfoView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingClearThumbnailConfirmation = false
    @State private var showingCompactDatabaseConfirmation = false
    @State private var renamingCatalogue: CatalogueStorageSnapshot?
    @State private var renameText = ""
    @State private var deletingCatalogue: CatalogueStorageSnapshot?
    @State private var showingDeleteCatalogueConfirmation = false
    @State private var movingCatalogue: CatalogueStorageSnapshot?
    @State private var showingMoveCatalogueConfirmation = false

    private var report: AppStorageReport {
        appState.appStorageReport
    }

    @State private var catalogueQuery = ""
    @State private var catalogueScope = ReportCatalogueScope.all
    @State private var catalogueSort = ReportCatalogueSort.recent
    @FocusState private var searchFocused: Bool
    // Also used by the isolated visual verification harness; production always refreshes.
    var refreshOnAppear = true

    init(refreshOnAppear: Bool = true, initialQuery: String = "") {
        self.refreshOnAppear = refreshOnAppear
        _catalogueQuery = State(initialValue: initialQuery)
    }

    private var isInitialLoading: Bool {
        appState.isLoadingAppStorageReport && report == .empty
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: ReportStyle.sectionSpacing) {
                        if isInitialLoading {
                            loadingState
                        } else {
                            overview
                            if report.mappedCatalogues.contains(where: { !$0.isReachable || $0.itemCount == nil }) {
                                Label("Some catalogue data is unavailable. Connect the drive and refresh to update this report. Totals include readable storage only.", systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(12)
                                    .reportSurface()
                            }
                            if let activeCatalogue = report.activeCatalogue {
                                activeCatalogueSection(activeCatalogue)
                            }
                            mappedCataloguesSection(compact: geometry.size.width < 700)
                            privacySection
                        }
                    }
                    .padding(ReportStyle.pageInset)
                    .frame(maxWidth: 1360, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .background(ReportCanvas())
        }
        .navigationTitle("Storage & Privacy")
        .task {
            if refreshOnAppear { await appState.refreshAppStorageReport() }
        }
        .confirmationDialog(
            "Clear thumbnail cache?",
            isPresented: $showingClearThumbnailConfirmation
        ) {
            Button("Clear Thumbnail Cache", role: .destructive) {
                Task { await appState.clearActiveThumbnailCaches() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("DriveLens will remove generated photo and video thumbnails for the active catalogue. Original photos and videos are not changed. Run Update Catalogue to rebuild previews.")
        }
        .confirmationDialog(
            "Compact catalogue database?",
            isPresented: $showingCompactDatabaseConfirmation
        ) {
            Button("Compact Database") {
                Task { await appState.compactActiveCatalogueDatabase() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("DriveLens will compact the active SQLite catalogue to reclaim unused database space. Original photos and videos are not changed.")
        }
        .sheet(isPresented: renameSheetBinding) {
            CatalogueRenameSheet(
                name: $renameText,
                title: renamingCatalogue?.name ?? "Catalogue",
                onCancel: {
                    renamingCatalogue = nil
                    renameText = ""
                },
                onSave: {
                    guard let target = renamingCatalogue else { return }
                    Task {
                        await appState.renameCatalogue(id: target.catalogueID, to: renameText)
                        renamingCatalogue = nil
                        renameText = ""
                    }
                }
            )
            .frame(width: 420)
        }
        .confirmationDialog(
            "Delete Catalogue Data?",
            isPresented: $showingDeleteCatalogueConfirmation
        ) {
            Button("Delete Catalogue Data", role: .destructive) {
                guard let deletingCatalogue else { return }
                Task {
                    await appState.deleteCatalogue(id: deletingCatalogue.catalogueID)
                    self.deletingCatalogue = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deletingCatalogue = nil
            }
        } message: {
            Text(deleteCatalogueMessage)
        }
        .confirmationDialog(
            "Move catalogue storage?",
            isPresented: $showingMoveCatalogueConfirmation
        ) {
            Button("Move to Mapped Storage") {
                guard let movingCatalogue else { return }
                Task {
                    await appState.moveCatalogueToMappedStorage(id: movingCatalogue.catalogueID)
                    self.movingCatalogue = nil
                }
            }
            Button("Cancel", role: .cancel) {
                movingCatalogue = nil
            }
        } message: {
            Text(moveCatalogueMessage)
        }
    }

    private var renameSheetBinding: Binding<Bool> {
        Binding(
            get: { renamingCatalogue != nil },
            set: { isPresented in
                if !isPresented {
                    renamingCatalogue = nil
                    renameText = ""
                }
            }
        )
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                actions
            }
        }
        .frame(maxWidth: 1320, alignment: .leading)
        .padding(.horizontal, ReportStyle.pageInset)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(ReportHeaderMaterial())
    }

    private var titleBlock: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(ReportStyle.accentGradient, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.35)))
                .shadow(color: .indigo.opacity(0.18), radius: 4, y: 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Storage & Privacy")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("REPORTS  /  Library intelligence")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                appState.revealActiveCatalogueFolder()
            } label: {
                Label("Reveal Storage", systemImage: "folder")
            }
            .disabled(report.activeCatalogue?.isReachable != true)
            .help("Reveal active catalogue storage in Finder")

            Button {
                Task { await appState.refreshAppStorageReport() }
            } label: {
                HStack(spacing: 5) {
                    if appState.isLoadingAppStorageReport { ProgressView().controlSize(.mini) }
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .control])
            .disabled(appState.isLoadingAppStorageReport)
            .help("Refresh report (⌃⌘R)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Measuring catalogue storage…").font(.callout.weight(.medium))
            Text("Reading local metadata and generated caches.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .reportSurface()
        .accessibilityElement(children: .combine)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(report.mappedCatalogues.contains(where: { !$0.isReachable }) ? "STORAGE OVERVIEW · PARTIAL" : "STORAGE OVERVIEW").reportEyebrow()
                Spacer()
                Text(appState.isLoadingAppStorageReport ? "Refreshing report…" : "Updated \(report.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { overviewMetrics }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    overviewMetrics
                }
            }
        }
    }

    @ViewBuilder private var overviewMetrics: some View {
        ReportMetric(title: "On this Mac", value: bytes(report.macResidentBytes), detail: "Local catalogue data", icon: "internaldrive", color: .blue)
        ReportMetric(title: "With your media", value: bytes(report.mediaStoredBytes), detail: "External catalogue data", icon: "externaldrive", color: .teal)
        ReportMetric(title: "Databases", value: bytes(report.totalDatabaseBytes), detail: "Metadata & indexes", icon: "cylinder.split.1x2", color: .indigo)
        ReportMetric(title: "Thumbnails", value: bytes(report.totalThumbnailBytes), detail: "Generated previews", icon: "photo.stack", color: .purple)
    }

    private func activeCatalogueSection(_ catalogue: CatalogueStorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ReportIcon(symbol: catalogue.isStoredOnMac ? "internaldrive" : "externaldrive", color: .indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVE CATALOGUE").reportEyebrow()
                    Text(catalogue.name).font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle).help(catalogue.name)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                Label(catalogue.isReachable ? "Connected" : "Offline", systemImage: catalogue.isReachable ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(ReportStyle.canvas, in: Capsule())
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    storageBreakdown(catalogue).frame(minWidth: 310)
                    catalogueHealth(catalogue).frame(width: 230)
                        .padding(.leading, 20)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1) }
                }
                VStack(alignment: .leading, spacing: 16) {
                    storageBreakdown(catalogue)
                    Divider()
                    catalogueHealth(catalogue)
                }
            }
        }
        .padding(16)
        .reportSurface(accent: .indigo)
    }

    private func storageBreakdown(_ catalogue: CatalogueStorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(catalogue.isReachable ? bytes(catalogue.totalBytes) : "Unavailable")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("used by catalogue").font(.caption).foregroundStyle(.secondary)
            }
            ReportStorageChart(catalogue: catalogue)
            DisclosureGroup {
                Text(catalogue.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                Text("\(catalogue.sourceCount) imported folder\(catalogue.sourceCount == 1 ? "" : "s") • \(catalogue.isStoredOnMac ? "Stored on this Mac" : "Stored with media")")
                    .font(.caption).foregroundStyle(.secondary)
            } label: {
                Text("Storage location").font(.caption.weight(.medium))
            }
        }
    }

    private func catalogueHealth(_ catalogue: CatalogueStorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CATALOGUE HEALTH").reportEyebrow()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), alignment: .topLeading)], alignment: .leading, spacing: 10) {
                ReportFact(title: "Items", value: optionalCount(catalogue.itemCount), icon: "square.grid.2x2")
                ReportFact(title: "Missing files", value: optionalCount(catalogue.missingItemCount), icon: "questionmark.folder", attention: (catalogue.missingItemCount ?? 0) > 0)
                ReportFact(title: "Hashed items", value: optionalCount(catalogue.hashedItemCount), icon: "number")
                ReportFact(title: "Duplicate groups", value: optionalCount(catalogue.duplicateGroupCount), icon: "square.on.square")
            }
            Text(healthDescription(catalogue))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Menu {
                Button("Compact Database…") { showingCompactDatabaseConfirmation = true }
                    .disabled(maintenanceBusy || catalogue.databaseBytes == 0 || !catalogue.isReachable)
                Button("Clear Thumbnails…", role: .destructive) { showingClearThumbnailConfirmation = true }
                    .disabled(maintenanceBusy || catalogue.thumbnailBytes + catalogue.videoThumbnailBytes == 0 || !catalogue.isReachable)
            } label: {
                Label(maintenanceBusy ? "Maintenance in progress…" : "Maintenance", systemImage: "slider.horizontal.3")
            }
            .controlSize(.small)
            .disabled(maintenanceBusy)
            .help("Compact the database or clear generated thumbnails")
        }
    }

    private var maintenanceBusy: Bool {
        appState.isCompactingCatalogue || appState.isClearingAppCaches || appState.scanProgress != nil
    }

    private func healthDescription(_ catalogue: CatalogueStorageSnapshot) -> String {
        guard let photos = catalogue.photoCount, let videos = catalogue.videoCount, catalogue.isReachable else {
            return "Reconnect and refresh to read library details."
        }
        return "\(photos.formatted()) photos · \(videos.formatted()) videos"
    }

    private var filteredCatalogues: [CatalogueStorageSnapshot] {
        ReportCatalogueQuery.apply(to: report.mappedCatalogues, query: catalogueQuery, scope: catalogueScope, sort: catalogueSort)
    }

    private func mappedCataloguesSection(compact: Bool) -> some View {
        let catalogues = filteredCatalogues
        return ReportPanel(title: "Catalogues", subtitle: "\(catalogues.count) of \(report.mappedCatalogues.count)", icon: "rectangle.stack") {
            VStack(alignment: .leading, spacing: 10) {
                if report.mappedCatalogues.isEmpty {
                    reportEmptyState(title: "Your first catalogue starts here", description: "Choose a media folder to see storage, previews, and catalogue health.", icon: "externaldrive.badge.plus")
                    Button("Choose Folders…") { appState.requestMediaFolderReset() }
                        .controlSize(.small)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { catalogueSearch; scopePicker.frame(width: 228); sortMenu }
                        VStack(alignment: .leading, spacing: 8) {
                            catalogueSearch
                            HStack { scopePicker; sortMenu }
                        }
                    }
                    if catalogues.isEmpty {
                        reportEmptyState(title: "No matching catalogues", description: "Try a different name, folder, or storage location.", icon: "magnifyingglass")
                        Button("Clear Filters") { catalogueQuery = ""; catalogueScope = .all }
                            .controlSize(.small)
                    } else {
                        if !compact {
                            HStack(spacing: 16) {
                                Text("CATALOGUE").frame(maxWidth: .infinity, alignment: .leading)
                                Text("ITEMS").frame(width: 70, alignment: .trailing)
                                Text("STORAGE").frame(width: 85, alignment: .trailing)
                                Text("FOLDERS").frame(width: 55, alignment: .trailing)
                                Color.clear.frame(width: 50, height: 1)
                            }
                            .reportEyebrow().lineLimit(1).padding(.horizontal, 8).padding(.top, 4)
                            .accessibilityHidden(true)
                        }
                        LazyVStack(spacing: 0) {
                            ForEach(catalogues) { catalogue in
                                ReportCatalogueRow(catalogue: catalogue, compact: compact, maintenanceBusy: maintenanceBusy,
                                    onRename: { beginRenaming(catalogue) },
                                    onDelete: { beginDeleting(catalogue) },
                                    onMove: { beginMoving(catalogue) })
                                if catalogue.id != catalogues.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort catalogues", selection: $catalogueSort) {
                ForEach(ReportCatalogueSort.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").frame(width: 20, height: 20)
        }
        .menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Sort catalogues")
        .accessibilityValue(catalogueSort.rawValue)
        .help("Sort catalogues: \(catalogueSort.rawValue)")
    }

    private var catalogueSearch: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Filter catalogues", text: $catalogueQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { catalogueQuery = ""; searchFocused = false }
                .accessibilityLabel("Filter catalogues by name, path, or folder")
            if !catalogueQuery.isEmpty {
                Button { catalogueQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).help("Clear catalogue filter").accessibilityLabel("Clear catalogue filter")
            }
        }
        .font(.callout)
        .padding(8)
        .frame(minWidth: 160)
        .background(ReportStyle.canvas, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: searchFocused ? 2 : 1))
        .background {
            Button("Find Catalogue") { searchFocused = true }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .hidden().accessibilityHidden(true)
        }
        .help("Filter catalogues (⌥⌘F)")
    }

    private var scopePicker: some View {
        Picker("Storage location", selection: $catalogueScope) {
            ForEach(ReportCatalogueScope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
    }

    private func reportEmptyState(title: String, description: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }

    private func beginRenaming(_ catalogue: CatalogueStorageSnapshot) {
        renamingCatalogue = catalogue
        renameText = catalogue.name
    }

    private func beginDeleting(_ catalogue: CatalogueStorageSnapshot) {
        deletingCatalogue = catalogue
        showingDeleteCatalogueConfirmation = true
    }

    private func beginMoving(_ catalogue: CatalogueStorageSnapshot) {
        movingCatalogue = catalogue
        showingMoveCatalogueConfirmation = true
    }

    private var deleteCatalogueMessage: String {
        guard let deletingCatalogue else {
            return "DriveLens will delete catalogue metadata, thumbnails, and generated caches. Original photos and videos are not changed."
        }

        let scope = deletingCatalogue.isNamedCatalogue
            ? "\(deletingCatalogue.sourceCount) imported folder\(deletingCatalogue.sourceCount == 1 ? "" : "s")"
            : "legacy single-folder catalogue"
        return "This deletes metadata, thumbnails, indexes, duplicate hashes, and saved pointers for \(deletingCatalogue.name) (\(scope)). Original photos and videos are not changed."
    }

    private var moveCatalogueMessage: String {
        guard let movingCatalogue else {
            return "DriveLens will move generated catalogue data to `.drivelens` inside a mapped folder on the same storage device. Original photos and videos are not changed."
        }

        return "DriveLens will copy \(movingCatalogue.name)'s database, thumbnails, hashes, and caches into `.drivelens` inside a mapped folder, verify the copied catalogue opens, then remove the old Mac-side copy. Original photos and videos are not changed."
    }

    private var privacySection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.teal).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Local by design. Private by default.").font(.callout.weight(.semibold))
                DisclosureGroup {
                    Text("Catalogue data includes metadata, thumbnails, geocoding caches, duplicate hashes, and indexes. Mapped catalogues store this in .drivelens alongside your media. This Mac also keeps bookmarks and pointers to reopen them. Original photos and videos are not changed.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Bookmark data: \(bytes(report.bookmarkBytes))").font(.caption).monospacedDigit()
                } label: {
                    Text("About storage & permissions").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func bytes(_ value: Int64) -> String {
        value == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func optionalCount(_ value: Int?) -> String {
        guard let value else { return "Unknown" }
        return value.formatted(.number)
    }
}

private struct CatalogueRenameSheet: View {
    @Binding var name: String
    let title: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Rename Catalogue")
                        .font(.title3.weight(.semibold))
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TextField("Catalogue name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .accessibilityLabel("Catalogue name")

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(22)
        .background(LensTheme.sidebar)
    }
}

// MARK: - Report design system

private enum ReportStyle {
    static let canvas = LensTheme.sidebar
    static let surface = LensTheme.surface
    static let pageInset: CGFloat = LensTheme.pageInset
    static let sectionSpacing: CGFloat = 16
    static let radius: CGFloat = LensTheme.radius
    static let accentGradient = LensTheme.gradient
}

enum ReportCatalogueScope: String, CaseIterable, Identifiable {
    case all = "All", onMac = "On Mac", withMedia = "With Media"
    var id: String { rawValue }
}

enum ReportCatalogueSort: String, CaseIterable, Identifiable {
    case recent = "Recently opened", name = "Name", storage = "Largest storage", items = "Most items"
    var id: String { rawValue }
}

enum ReportCatalogueQuery {
    static func apply(to catalogues: [CatalogueStorageSnapshot], query: String, scope: ReportCatalogueScope, sort: ReportCatalogueSort) -> [CatalogueStorageSnapshot] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalogues.filter { catalogue in
            (scope == .all || (scope == .onMac ? catalogue.isStoredOnMac : !catalogue.isStoredOnMac))
            && (query.isEmpty || catalogue.name.localizedStandardContains(query)
                || catalogue.path.localizedStandardContains(query)
                || catalogue.sourceNames.contains { $0.localizedStandardContains(query) })
        }.sorted { lhs, rhs in
            switch sort {
            case .recent:
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                if lhs.lastOpenedAt != rhs.lastOpenedAt { return lhs.lastOpenedAt > rhs.lastOpenedAt }
            case .name: break
            case .storage:
                if lhs.isReachable != rhs.isReachable { return lhs.isReachable }
                if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            case .items:
                if lhs.itemCount != rhs.itemCount { return (lhs.itemCount ?? -1) > (rhs.itemCount ?? -1) }
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }
}

private struct ReportCanvas: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ReportStyle.canvas.overlay(alignment: .top) {
            if !reduceTransparency {
                LinearGradient(colors: [.indigo.opacity(0.04), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 380)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ReportIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

private struct ReportSurface: ViewModifier {
    var accent: Color = .clear
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: ReportStyle.radius).fill(ReportStyle.surface)
                    .overlay {
                        if !reduceTransparency && contrast != .increased {
                            RoundedRectangle(cornerRadius: ReportStyle.radius)
                                .fill(LinearGradient(colors: [accent.opacity(scheme == .dark ? 0.1 : 0.045), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: ReportStyle.radius)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.1), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.035), radius: 5, y: 2)
    }
}

private extension View {
    func reportSurface(accent: Color = .clear) -> some View { modifier(ReportSurface(accent: accent)) }
    func reportEyebrow() -> some View {
        font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
    }
}

private struct ReportHeaderMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        if reduceTransparency || contrast == .increased {
            ReportStyle.surface
        } else {
            Rectangle().fill(.bar)
        }
    }
}

private struct ReportPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(subtitle)
            }
            .font(.callout)
            Divider()
            content
        }
        .padding(16)
        .reportSurface()
    }
}

private struct ReportMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(minWidth: 115, maxWidth: .infinity, alignment: .leading)
        .reportSurface(accent: color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value). \(detail)")
    }
}

private struct ReportFact: View {
    let title: String
    let value: String
    let icon: String
    var attention = false
    @Environment(\.colorScheme) private var scheme
    private var valueColor: Color {
        attention ? (scheme == .dark ? .orange : Color(red: 0.62, green: 0.30, blue: 0.02)) : .primary
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit()
                .foregroundStyle(valueColor)
            Label(title, systemImage: icon).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct ReportStoragePart: Identifiable {
    let title: String
    let bytes: Int64
    let color: Color
    var id: String { title }
}

private struct ReportStorageChart: View {
    let catalogue: CatalogueStorageSnapshot
    @Environment(\.colorSchemeContrast) private var contrast
    private var parts: [ReportStoragePart] {
        [
            .init(title: "Database", bytes: catalogue.databaseBytes, color: .indigo),
            .init(title: "Photo previews", bytes: catalogue.thumbnailBytes, color: .blue),
            .init(title: "Video previews", bytes: catalogue.videoThumbnailBytes, color: .teal),
            .init(title: "Geocoding cache", bytes: catalogue.geocodingCacheBytes, color: .orange),
            .init(title: "Support files", bytes: catalogue.manifestBytes + catalogue.tempBytes + catalogue.otherBytes, color: .secondary)
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            // A single proportional strip avoids a chart dependency or expensive offscreen compositing.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(part.color.gradient)
                            .frame(width: catalogue.isReachable && catalogue.totalBytes > 0 ? geometry.size.width * CGFloat(part.bytes) / CGFloat(catalogue.totalBytes) : 0)
                            .overlay(alignment: .trailing) {
                                if part.bytes > 0 { Rectangle().fill(ReportStyle.surface).frame(width: 1) }
                            }
                    }
                }
            }
            .frame(height: 14)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)

            Grid(horizontalSpacing: 12, verticalSpacing: 7) {
                ForEach(parts) { part in
                    GridRow {
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2).fill(part.color).frame(width: 7, height: 7)
                            Text(part.title)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(catalogue.isReachable ? ByteCountFormatter.string(fromByteCount: part.bytes, countStyle: .file) : "—")
                            .fontWeight(.medium).monospacedDigit().gridColumnAlignment(.trailing)
                        Text(catalogue.isReachable && catalogue.totalBytes > 0 ? (Double(part.bytes) / Double(catalogue.totalBytes)).formatted(.percent.precision(.fractionLength(0))) : "—")
                            .foregroundStyle(.secondary).monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ReportCatalogueRow: View {
    let catalogue: CatalogueStorageSnapshot
    let compact: Bool
    let maintenanceBusy: Bool
    let onRename: () -> Void
    let onDelete: () -> Void
    let onMove: () -> Void
    @State private var hovering = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { identity; Spacer(minLength: 4); rowActions }
                    metrics.padding(.leading, 44)
                }
            } else {
                HStack(spacing: 16) {
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    metrics
                    rowActions.frame(width: 50)
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    Text(catalogue.path).textSelection(.enabled)
                    Text(catalogue.sourceNames.isEmpty ? "\(catalogue.sourceCount) imported folders" : "Includes " + catalogue.sourceNames.joined(separator: ", "))
                    if let date = catalogue.lastScanDate {
                        Text("Last scanned \(date.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text("Generated cache: \(ByteCountFormatter.string(fromByteCount: catalogue.cacheBytes, countStyle: .file)) • \(catalogue.hasSavedPermission ? "Saved folder permission" : "No saved folder permission")")
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? (contrast == .increased ? 0.12 : 0.035) : 0)))
        .onHover { hovering = $0 }
        .contextMenu { catalogueActions }
        .accessibilityElement(children: .contain)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            ReportIcon(symbol: catalogue.isReachable ? (catalogue.isStoredOnMac ? "internaldrive" : "externaldrive") : "externaldrive.badge.xmark", color: catalogue.isReachable ? .indigo : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(catalogue.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle).help(catalogue.name)
                    if catalogue.isActive {
                        Text("Active").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Label(status, systemImage: catalogue.isReachable ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var status: String {
        if !catalogue.isReachable { return "Disconnected • data unavailable" }
        if catalogue.itemCount == nil { return "Catalogue metrics unavailable" }
        return catalogue.isStoredOnMac ? "On this Mac" : "With media"
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            column("Items", value: catalogue.itemCount?.formatted() ?? "—", width: 70)
            column("Storage", value: catalogue.isReachable ? ByteCountFormatter.string(fromByteCount: catalogue.totalBytes, countStyle: .file) : "—", width: 85)
            column("Folders", value: catalogue.sourceCount.formatted(), width: 55)
        }
        .fixedSize()
    }

    private func column(_ title: String, value: String, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
            if compact { Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .frame(width: width, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value == "—" ? "Unavailable" : value)")
    }

    private var rowActions: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down").frame(width: 18, height: 20)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(expanded ? "Hide" : "Show") details for \(catalogue.name)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .help(expanded ? "Hide catalogue details" : "Show path, folders, and last scan")
            Menu { catalogueActions } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 20)
            }
            .menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Actions for \(catalogue.name)").help("Catalogue actions")
        }
    }

    @ViewBuilder private var catalogueActions: some View {
        Button("Rename Catalogue…", systemImage: "pencil", action: onRename)
            .disabled(maintenanceBusy)
        if catalogue.isNamedCatalogue && catalogue.isStoredOnMac {
            Button("Move to Mapped Storage…", systemImage: "externaldrive.badge.plus", action: onMove)
                .disabled(maintenanceBusy || catalogue.sourceCount == 0 || !catalogue.isReachable)
        }
        Divider()
        Button("Delete Catalogue Data…", systemImage: "trash", role: .destructive, action: onDelete)
            .disabled(maintenanceBusy)
    }
}
