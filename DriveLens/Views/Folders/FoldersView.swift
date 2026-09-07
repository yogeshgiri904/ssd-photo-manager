import SwiftUI

struct FoldersView: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]
    let folders: [FolderCatalogueSummary]
    @State private var sort: FolderSort = .name
    @State private var selectedFolderPath: String?
    @State private var selectedFolderItems: [MediaItem] = []
    @State private var isLoadingFolder = false
    @State private var sourcePendingRemoval: CatalogueSource?

    private var sortedFolders: [FolderCatalogueSummary] {
        folders
            .sorted { lhs, rhs in
                switch sort {
                case .name:
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case .newest:
                    return (lhs.newestCaptureDate ?? .distantPast) > (rhs.newestCaptureDate ?? .distantPast)
                case .oldest:
                    return (lhs.oldestCaptureDate ?? .distantFuture) < (rhs.oldestCaptureDate ?? .distantFuture)
                }
            }
    }

    private var selectedFolderSummary: FolderCatalogueSummary? {
        guard let selectedFolderPath else { return nil }
        return folders.first { $0.path == selectedFolderPath }
    }

    private var mappedSources: [CatalogueSource] {
        guard appState.activeCatalogue?.isNamedCatalogue == true else { return [] }
        return appState.activeMediaSources.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            folderHeader

            Divider()

            if selectedFolderPath == nil {
                if sortedFolders.isEmpty && mappedSources.isEmpty {
                    ContentUnavailableView {
                        Label("No Folders", systemImage: "folder")
                    } description: {
                        Text("Add a folder to begin cataloguing photos and videos. Original photos and videos are not changed.")
                    } actions: {
                        Button {
                            appState.requestCatalogueUpdate()
                        } label: {
                            Label("Update Catalogue", systemImage: "arrow.clockwise")
                        }
                        .disabled(!appState.canScan)

                        Button {
                            Task { await appState.addFoldersToCurrentCatalogue() }
                        } label: {
                            Label("Add Folders", systemImage: "folder.badge.plus")
                        }
                        .disabled(!appState.canAddFoldersToCatalogue)
                    }
                } else {
                    List {
                        if !mappedSources.isEmpty {
                            Section {
                                ForEach(mappedSources) { source in
                                    MappedFolderRow(
                                        source: source,
                                        itemCount: indexedItemCount(for: source),
                                        isRemoving: appState.removingCatalogueFolderID == source.id,
                                        isRemovalDisabled: !appState.canRemoveMappedFolders,
                                        onReveal: { reveal(source) },
                                        onRemove: { sourcePendingRemoval = source }
                                    )
                                }
                            } header: {
                                Text("Mapped Folders")
                            } footer: {
                                Text("Removing a mapped folder deletes its catalogue metadata and generated previews. Original photos and videos are not changed.")
                            }
                        }

                        if !sortedFolders.isEmpty {
                            Section("Indexed Folders") {
                                ForEach(sortedFolders) { folder in
                                    Button {
                                        select(folder.path)
                                    } label: {
                                        FolderRow(folder: folder)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens this folder in the catalogue")
                                    .contextMenu {
                                        Button {
                                            reveal(folder)
                                        } label: {
                                            Label("Reveal in Finder", systemImage: "finder")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                ZStack {
                    TimelineView(items: selectedFolderItems, title: folderName(for: selectedFolderPath ?? ""), showsHeader: false)

                    if isLoadingFolder {
                        ProgressView("Loading Folder")
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Loading folder")
                    }
                }
            }
        }
        .navigationTitle("Folders")
        .confirmationDialog(
            sourcePendingRemoval.map { "Remove “\($0.name)” from the catalogue?" } ?? "Remove folder from the catalogue?",
            isPresented: sourceRemovalBinding
        ) {
            Button("Remove Folder from Catalogue", role: .destructive) {
                guard let source = sourcePendingRemoval else { return }
                Task {
                    await appState.removeMappedFolder(source)
                    sourcePendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                sourcePendingRemoval = nil
            }
        } message: {
            Text(sourceRemovalMessage)
        }
        .onAppear {
            selectedFolderPath = appState.focusedFolderPath
            if let selectedFolderPath {
                loadFolder(selectedFolderPath)
            }
        }
        .onChange(of: appState.focusedFolderPath) { _, newValue in
            selectedFolderPath = newValue
            if let newValue {
                loadFolder(newValue)
            } else {
                selectedFolderItems = []
                isLoadingFolder = false
            }
        }
        .onChange(of: appState.catalogueCounts) { _, _ in
            if let selectedFolderPath {
                loadFolder(selectedFolderPath)
            }
        }
        .onChange(of: appState.mediaMutationRevision) { _, _ in
            if let selectedFolderPath {
                loadFolder(selectedFolderPath)
            }
        }
    }

    private var sourceRemovalBinding: Binding<Bool> {
        Binding(
            get: { sourcePendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    sourcePendingRemoval = nil
                }
            }
        )
    }

    private var sourceRemovalMessage: String {
        guard let source = sourcePendingRemoval else {
            return "DriveLens will remove the folder mapping and its indexed catalogue data. Original photos and videos are not changed."
        }
        let count = indexedItemCount(for: source)
        let itemText = count == 1 ? "1 indexed item" : "\(count) indexed items"
        return "DriveLens will remove this folder mapping and \(itemText), including metadata, favorites, album references, and generated previews. Original photos and videos are not changed."
    }

    private var folderHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    titleBlock
                    Spacer()
                    headerAction
                }

                VStack(alignment: .leading, spacing: 10) {
                    titleBlock
                    headerAction
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBlock: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedFolderPath == nil ? "folder" : "folder.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("Folders")
                        .font(.title2.weight(.semibold))
                    if let selectedFolderPath {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(folderName(for: selectedFolderPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Text(folderSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var headerAction: some View {
        if selectedFolderPath == nil {
            Picker("Sort", selection: $sort) {
                ForEach(FolderSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .accessibilityLabel("Sort folders")
        } else {
            Button {
                self.selectedFolderPath = nil
                appState.focusedFolderPath = nil
            } label: {
                Label("All Folders", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var folderSubtitle: String {
        if selectedFolderPath != nil {
            let count = selectedFolderSummary?.itemCount ?? selectedFolderItems.count
            return "\(count) item\(count == 1 ? "" : "s") in this folder"
        }
        if !mappedSources.isEmpty {
            let sourceCount = mappedSources.count
            let itemCount = appState.catalogueCounts.totalItems
            return "\(sourceCount) mapped folder\(sourceCount == 1 ? "" : "s") • \(itemCount) indexed item\(itemCount == 1 ? "" : "s")"
        }
        return "\(sortedFolders.count) folder\(sortedFolders.count == 1 ? "" : "s") in this catalogue"
    }

    private func reveal(_ folder: FolderCatalogueSummary) {
        guard let url = appState.folderURL(forCatalogueFolderPath: folder.path) else { return }
        NSWorkspace.shared.open(url)
    }

    private func reveal(_ source: CatalogueSource) {
        guard source.isReachable else { return }
        NSWorkspace.shared.open(source.rootURL)
    }

    private func indexedItemCount(for source: CatalogueSource) -> Int {
        folders.reduce(into: 0) { count, folder in
            if path(folder.path, isInside: source.relativePrefix) {
                count += folder.itemCount
            }
        }
    }

    private func path(_ candidate: String, isInside sourcePrefix: String) -> Bool {
        sourcePrefix.isEmpty || candidate == sourcePrefix || candidate.hasPrefix(sourcePrefix + "/")
    }

    private func select(_ path: String) {
        selectedFolderPath = path
        appState.focusedFolderPath = path
        loadFolder(path)
    }

    private func loadFolder(_ path: String) {
        Task {
            isLoadingFolder = true
            selectedFolderItems = []
            selectedFolderItems = await appState.loadItems(inFolderPath: path)
            isLoadingFolder = false
        }
    }

    private func folderName(for path: String) -> String {
        path.isEmpty ? "Media Folder" : URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct MappedFolderRow: View {
    let source: CatalogueSource
    let itemCount: Int
    let isRemoving: Bool
    let isRemovalDisabled: Bool
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.isReachable ? "folder.fill" : "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(source.isReachable ? Color.accentColor : Color.secondary)
                .frame(width: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(source.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text(source.isReachable ? "Connected" : "Disconnected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(source.isReachable ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }

                Text(source.rootPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)

            if isRemoving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Removing folder")
            } else {
                Menu {
                    Button(action: onReveal) {
                        Label("Reveal in Finder", systemImage: "finder")
                    }
                    .disabled(!source.isReachable)

                    Divider()

                    Button(role: .destructive, action: onRemove) {
                        Label("Remove Folder from Catalogue…", systemImage: "minus.circle")
                    }
                    .disabled(isRemovalDisabled)
                } label: {
                    OptionsMenuLabel(title: "Actions for \(source.name)")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .accessibilityLabel("Actions for \(source.name)")
            }
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button(action: onReveal) {
                Label("Reveal in Finder", systemImage: "finder")
            }
            .disabled(!source.isReachable)

            Button(role: .destructive, action: onRemove) {
                Label("Remove Folder from Catalogue…", systemImage: "minus.circle")
            }
            .disabled(isRemovalDisabled)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct FolderRow: View {
    let folder: FolderCatalogueSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.callout.weight(.semibold))
                Text(folder.path.isEmpty ? "Imported media folder" : folder.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(folder.itemCount) item\(folder.itemCount == 1 ? "" : "s")")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text("\(folder.photoCount) photo\(folder.photoCount == 1 ? "" : "s")  \(folder.videoCount) video\(folder.videoCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private enum FolderSort: String, CaseIterable, Identifiable {
    case name
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
}
