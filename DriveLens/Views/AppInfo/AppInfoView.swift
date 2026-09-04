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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                overview

                if let activeCatalogue = report.activeCatalogue {
                    activeCatalogueSection(activeCatalogue)
                }

                mappedCataloguesSection
                privacySection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1040, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("App Info")
        .task {
            await appState.refreshAppStorageReport()
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
            "Delete catalogue data?",
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
            Button("Move to Storage Root") {
                guard let movingCatalogue else { return }
                Task {
                    await appState.moveCatalogueToStorageRoot(id: movingCatalogue.catalogueID)
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
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                actions
            }

            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        HStack(spacing: 14) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("App Info")
                    .font(.system(size: 30, weight: .semibold))
                Text("Catalogue storage, mapped folders, permissions, and maintenance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if appState.isLoadingAppStorageReport {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button {
                Task { await appState.refreshAppStorageReport() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isLoadingAppStorageReport)

            Button {
                appState.revealActiveCatalogueFolder()
            } label: {
                Label("Reveal Storage", systemImage: "finder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(report.activeCatalogue == nil)
            .help("Reveal active catalogue storage in Finder")
        }
    }

    private var overview: some View {
        LazyVGrid(columns: overviewColumns, alignment: .leading, spacing: 12) {
            AppInfoMetricTile(title: "Stored on This Mac", value: bytes(report.macResidentBytes), systemImage: "internaldrive")
            AppInfoMetricTile(title: "Stored on Storage Roots", value: bytes(report.mediaStoredBytes), systemImage: "externaldrive")
            AppInfoMetricTile(title: "Catalogue Databases", value: bytes(report.totalDatabaseBytes), systemImage: "cylinder.split.1x2")
            AppInfoMetricTile(title: "Generated Thumbnails", value: bytes(report.totalThumbnailBytes), systemImage: "photo.stack")
            AppInfoMetricTile(title: "Catalogues", value: "\(report.mappedCatalogues.count)", systemImage: "rectangle.stack")
        }
    }

    private var overviewColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 250), spacing: 12)]
    }

    private func activeCatalogueSection(_ catalogue: CatalogueStorageSnapshot) -> some View {
        AppInfoSection(title: "Active Catalogue", subtitle: activeCatalogueSubtitle(catalogue)) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: factColumns, alignment: .leading, spacing: 10) {
                    CompactFact(title: "Items", value: optionalCount(catalogue.itemCount), systemImage: "rectangle.grid.3x2")
                    CompactFact(title: "Missing", value: optionalCount(catalogue.missingItemCount), systemImage: "questionmark.folder")
                    CompactFact(title: "Hashed", value: optionalCount(catalogue.hashedItemCount), systemImage: "number")
                    CompactFact(title: "Duplicates", value: optionalCount(catalogue.duplicateGroupCount), systemImage: "rectangle.on.rectangle")
                }

                VStack(spacing: 9) {
                    StorageRow(title: "SQLite catalogue", bytes: catalogue.databaseBytes, total: max(catalogue.totalBytes, 1), systemImage: "cylinder")
                    StorageRow(title: "Photo thumbnails", bytes: catalogue.thumbnailBytes, total: max(catalogue.totalBytes, 1), systemImage: "photo")
                    StorageRow(title: "Video thumbnails", bytes: catalogue.videoThumbnailBytes, total: max(catalogue.totalBytes, 1), systemImage: "film")
                    StorageRow(title: "Geocoding cache", bytes: catalogue.geocodingCacheBytes, total: max(catalogue.totalBytes, 1), systemImage: "map")
                    StorageRow(title: "Manifest and support files", bytes: catalogue.manifestBytes + catalogue.tempBytes + catalogue.otherBytes, total: max(catalogue.totalBytes, 1), systemImage: "doc")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        compactDatabaseButton(catalogue)
                        clearThumbnailsButton(catalogue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        compactDatabaseButton(catalogue)
                        clearThumbnailsButton(catalogue)
                    }
                }
            }
        }
    }

    private var factColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 135, maximum: 210), spacing: 10)]
    }

    private func activeCatalogueSubtitle(_ catalogue: CatalogueStorageSnapshot) -> String {
        guard catalogue.isNamedCatalogue else { return catalogue.path }
        let folderText = catalogue.sourceCount == 1 ? "1 imported folder" : "\(catalogue.sourceCount) imported folders"
        let storageText = catalogue.isStoredOnMac ? "stored on this Mac" : "stored in .drivelens at the storage root"
        return "\(folderText) • \(storageText) • \(catalogue.path)"
    }

    private func compactDatabaseButton(_ catalogue: CatalogueStorageSnapshot) -> some View {
        Button {
            showingCompactDatabaseConfirmation = true
        } label: {
            if appState.isCompactingCatalogue {
                Label("Compacting", systemImage: "hourglass")
            } else {
                Label("Compact Database", systemImage: "arrow.down.forward.and.arrow.up.backward")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.isCompactingCatalogue || catalogue.databaseBytes == 0)
    }

    private func clearThumbnailsButton(_ catalogue: CatalogueStorageSnapshot) -> some View {
        Button {
            showingClearThumbnailConfirmation = true
        } label: {
            if appState.isClearingAppCaches {
                Label("Clearing", systemImage: "hourglass")
            } else {
                Label("Clear Thumbnails", systemImage: "trash")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.isClearingAppCaches || catalogue.thumbnailBytes + catalogue.videoThumbnailBytes == 0)
    }

    private var mappedCataloguesSection: some View {
        AppInfoSection(
            title: "Catalogues",
            subtitle: report.mappedCatalogues.isEmpty ? "No saved catalogues yet" : "\(report.mappedCatalogues.count) saved catalogue\(report.mappedCatalogues.count == 1 ? "" : "s")"
        ) {
            if report.mappedCatalogues.isEmpty {
                ContentUnavailableView {
                    Label("No Catalogues", systemImage: "rectangle.stack.badge.questionmark")
                } description: {
                    Text("Choose folders to create the first catalogue. DriveLens stores catalogue data in .drivelens at the storage root.")
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(report.mappedCatalogues) { catalogue in
                        MappedCatalogueStorageRow(
                            catalogue: catalogue,
                            onRename: { beginRenaming(catalogue) },
                            onDelete: { beginDeleting(catalogue) },
                            onMoveToStorageRoot: { beginMoving(catalogue) }
                        )
                    }
                }
            }
        }
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
            return "DriveLens will move generated catalogue data to .drivelens at the storage root. Original photos and videos are not changed."
        }

        return "DriveLens will copy \(movingCatalogue.name)'s database, thumbnails, hashes, and caches into .drivelens at the storage root, verify the copied catalogue opens, then remove the old Mac-side copy. Original photos and videos are not changed."
    }

    private var privacySection: some View {
        AppInfoSection(title: "Privacy", subtitle: "Local by design") {
            VStack(alignment: .leading, spacing: 10) {
                Label("DriveLens stores catalogue data in .drivelens at the storage root whenever possible.", systemImage: "lock.shield")
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("New catalogues store metadata, thumbnails, geocoding cache, duplicate hashes, and indexes inside .drivelens at the root of the selected storage volume. This Mac keeps only small security-scoped bookmarks and catalogue pointers. Older catalogues can be moved from the Catalogues section.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label("Bookmark data", systemImage: "key")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(bytes(report.bookmarkBytes))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .font(.callout)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func optionalCount(_ value: Int?) -> String {
        guard let value else { return "Unknown" }
        return value.formatted(.number)
    }
}

private struct AppInfoSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppInfoMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CompactFact: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StorageRow: View {
    let title: String
    let bytes: Int64
    let total: Int64
    let systemImage: String

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(bytes) / Double(total), 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            ProgressView(value: fraction)
                .accessibilityLabel(title)
                .accessibilityValue(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        .padding(.vertical, 2)
    }
}

private struct MappedCatalogueStorageRow: View {
    let catalogue: CatalogueStorageSnapshot
    let onRename: () -> Void
    let onDelete: () -> Void
    let onMoveToStorageRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: statusSystemImage)
                    .font(.title3)
                    .foregroundStyle(catalogue.isReachable ? Color.accentColor : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 7) {
                    titleRow

                    Text(catalogueDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)

                    if let lastScanDate = catalogue.lastScanDate {
                        Text("Last scanned \(lastScanDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button {
                        onRename()
                    } label: {
                        Label("Rename Catalogue...", systemImage: "pencil")
                    }

                    if catalogue.isNamedCatalogue && catalogue.isStoredOnMac {
                        Button {
                            onMoveToStorageRoot()
                        } label: {
                            Label("Move to Storage Root...", systemImage: "externaldrive.badge.plus")
                        }
                        .disabled(catalogue.sourceCount == 0)
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Catalogue Data...", systemImage: "trash")
                    }
                } label: {
                    Label("Catalogue Actions", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Catalogue Actions")
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                MiniMetric(title: "Data", value: ByteCountFormatter.string(fromByteCount: catalogue.totalBytes, countStyle: .file))
                MiniMetric(title: "Items", value: catalogue.itemCount?.formatted(.number) ?? "Unknown")
                MiniMetric(title: "Cache", value: ByteCountFormatter.string(fromByteCount: catalogue.cacheBytes, countStyle: .file))
                MiniMetric(title: "Location", value: catalogue.isStoredOnMac ? "Mac" : "Root")
                MiniMetric(title: "Folders", value: catalogue.sourceCount.formatted(.number))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(catalogue.isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 108, maximum: 180), spacing: 8)]
    }

    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                titleText
                statusBadges
            }

            VStack(alignment: .leading, spacing: 6) {
                titleText
                statusBadges
            }
        }
    }

    private var titleText: some View {
        Text(catalogue.name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var statusBadges: some View {
        HStack(spacing: 6) {
            if catalogue.isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            Text(statusText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.45), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if catalogue.isNamedCatalogue {
            if catalogue.sourceCount == 0 { return "Empty" }
            return catalogue.isStoredOnMac ? "On Mac" : "Storage Root"
        }
        if catalogue.isReachable {
            return catalogue.hasSavedPermission ? "Available" : "Detected"
        }
        return catalogue.hasSavedPermission ? "Disconnected" : "Unavailable"
    }

    private var catalogueDetail: String {
        if catalogue.isNamedCatalogue {
            if catalogue.sourceNames.isEmpty {
                return "No folders imported yet"
            }
            let included = "Includes " + catalogue.sourceNames.prefix(3).joined(separator: ", ")
            let location = catalogue.isStoredOnMac ? "Stored on this Mac" : "Stored at storage root"
            return included + " • " + location + " • " + catalogue.path
        }
        return catalogue.path
    }

    private var statusSystemImage: String {
        if catalogue.isNamedCatalogue {
            return "rectangle.stack.fill"
        }
        if catalogue.isReachable {
            return "externaldrive.fill"
        }
        return "externaldrive.badge.xmark"
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }
}
