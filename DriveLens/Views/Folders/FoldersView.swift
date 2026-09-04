import SwiftUI

struct FoldersView: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]
    let folders: [FolderCatalogueSummary]
    @State private var sort: FolderSort = .name
    @State private var selectedFolderPath: String?
    @State private var selectedFolderItems: [MediaItem] = []
    @State private var isLoadingFolder = false

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

    var body: some View {
        VStack(spacing: 0) {
            folderHeader

            Divider()

            if selectedFolderPath == nil {
                if sortedFolders.isEmpty {
                    ContentUnavailableView {
                        Label("No folders yet", systemImage: "folder")
                    } description: {
                        Text("Update the catalogue to browse imported folder structure.")
                    } actions: {
                        Button {
                            appState.requestCatalogueUpdate()
                        } label: {
                            Label("Update Catalogue", systemImage: "arrow.clockwise")
                        }
                        .disabled(!appState.canScan)
                    }
                } else {
                    List(sortedFolders) { folder in
                        FolderRow(folder: folder)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                select(folder.path)
                            }
                            .contextMenu {
                                Button("Reveal Folder in Finder") {
                                    reveal(folder)
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
        return "\(sortedFolders.count) folder\(sortedFolders.count == 1 ? "" : "s") in this catalogue"
    }

    private func reveal(_ folder: FolderCatalogueSummary) {
        guard let url = appState.folderURL(forCatalogueFolderPath: folder.path) else { return }
        NSWorkspace.shared.open(url)
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
