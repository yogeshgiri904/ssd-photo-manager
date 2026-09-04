import SwiftUI

struct SmartAlbumsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var albumFilter = ""
    @State private var showingAlbumEditor = false
    @State private var albumToEdit: CustomAlbum?
    @State private var albumPendingDeletion: CustomAlbum?

    var body: some View {
        Group {
            if let album = appState.selectedSmartAlbum {
                albumDetail(album)
            } else {
                overview
            }
        }
        .navigationTitle("Smart Albums")
        .task { await appState.refreshSmartAlbums() }
        .sheet(isPresented: $showingAlbumEditor, onDismiss: { albumToEdit = nil }) {
            CustomAlbumEditorSheet(album: albumToEdit)
                .environmentObject(appState)
                .frame(width: 440)
        }
        .alert(
            "Delete “\(albumPendingDeletion?.name ?? "Album")”?",
            isPresented: deleteConfirmationBinding,
            presenting: albumPendingDeletion
        ) { album in
            Button("Cancel", role: .cancel) { albumPendingDeletion = nil }
            Button("Delete Album", role: .destructive) {
                albumPendingDeletion = nil
                Task { await appState.deleteCustomAlbum(album) }
            }
        } message: { album in
            Text("“\(album.name)” will be removed from DriveLens. Original photos and videos are not changed.")
        }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            SmartAlbumsHeader(
                totalCount: appState.smartAlbums.filter { !$0.isPlaceholder }.count,
                deviceCount: albums(in: .devices).count,
                customCount: appState.customAlbums.count,
                filterText: $albumFilter,
                createAction: { presentAlbumEditor() },
                refreshAction: { Task { await appState.refreshSmartAlbums() } }
            )

            Divider()

            ScrollView {
                if filteredGroups.isEmpty {
                    noResults.frame(minHeight: 420)
                } else {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(filteredGroups) { group in
                            albumSection(group)
                        }
                    }
                    .padding(18)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    private func albumSection(_ group: SmartAlbumGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SmartAlbumSectionHeader(category: group.category, count: group.albums.count)

            if group.albums.isEmpty && group.category == .custom {
                EmptyCustomAlbumsCard { presentAlbumEditor() }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(group.albums) { album in
                        albumCard(album)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumCard(_ album: SmartAlbum) -> some View {
        if case .customAlbum(let albumID) = album.kind,
           let customAlbum = appState.customAlbums.first(where: { $0.id == albumID }) {
            SmartAlbumCard(
                album: album,
                action: { Task { await appState.openSmartAlbum(album) } },
                renameAction: { presentAlbumEditor(customAlbum) },
                deleteAction: { albumPendingDeletion = customAlbum }
            )
        } else {
            SmartAlbumCard(album: album) {
                Task { await appState.openSmartAlbum(album) }
            }
        }
    }

    private func albumDetail(_ album: SmartAlbum) -> some View {
        VStack(spacing: 0) {
            if album.isPlaceholder {
                detailHeader(for: album)
                Divider()
                peoplePlaceholder
            } else if isEmptyCustomAlbum(album) {
                detailHeader(for: album)
                Divider()
                emptyCustomAlbum
            } else {
                ZStack {
                    TimelineView(
                        items: appState.smartAlbumItems,
                        title: album.title,
                        counts: appState.countsForCurrentSmartAlbumFilter(),
                        showsQuickFilters: true,
                        controlScope: .smartAlbums,
                        backAction: { appState.closeSmartAlbum() }
                    )

                    if appState.isLoadingSmartAlbum {
                        ProgressView()
                            .controlSize(.large)
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Loading \(album.title)")
                    }
                }
            }
        }
    }

    private func detailHeader(for album: SmartAlbum) -> some View {
        SmartAlbumDetailHeader(album: album) { appState.closeSmartAlbum() }
    }

    private var peoplePlaceholder: some View {
        ContentUnavailableView {
            Label("People Albums Are Coming Later", systemImage: "person.2.crop.square.stack")
        } description: {
            Text("DriveLens does not currently analyze faces. Future people grouping will be designed for local, private processing.")
        } actions: {
            Button("Back to Smart Albums") { appState.closeSmartAlbum() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyCustomAlbum: some View {
        ContentUnavailableView {
            Label("This Album Is Empty", systemImage: "rectangle.stack")
        } description: {
            Text("Select photos or videos in the catalogue, then choose this album in the Inspector. Original photos and videos are not changed.")
        } actions: {
            Button("Back to Smart Albums") { appState.closeSmartAlbum() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("No Albums Found", systemImage: "magnifyingglass")
        } description: {
            Text("No album names, descriptions, or sections match “\(albumFilter.trimmingCharacters(in: .whitespacesAndNewlines))”.")
        } actions: {
            Button("Clear Filter") { albumFilter = "" }
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredGroups: [SmartAlbumGroup] {
        let query = albumFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        return SmartAlbumCategory.allCases.compactMap { category in
            let categoryAlbums = albums(in: category)
            let matches: [SmartAlbum]

            if query.isEmpty {
                matches = categoryAlbums
            } else if category.title.localizedCaseInsensitiveContains(query)
                        || category.subtitle.localizedCaseInsensitiveContains(query) {
                matches = categoryAlbums
            } else {
                matches = categoryAlbums.filter {
                    $0.title.localizedCaseInsensitiveContains(query)
                        || $0.subtitle.localizedCaseInsensitiveContains(query)
                }
            }

            guard !matches.isEmpty || (query.isEmpty && category == .custom) else { return nil }
            return SmartAlbumGroup(category: category, albums: matches)
        }
    }

    private func albums(in category: SmartAlbumCategory) -> [SmartAlbum] {
        appState.smartAlbums.filter(category.includes)
    }

    private func isEmptyCustomAlbum(_ album: SmartAlbum) -> Bool {
        guard album.itemCount == 0 else { return false }
        if case .customAlbum = album.kind { return true }
        return false
    }

    private func presentAlbumEditor(_ album: CustomAlbum? = nil) {
        albumToEdit = album
        showingAlbumEditor = true
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { albumPendingDeletion != nil },
            set: { if !$0 { albumPendingDeletion = nil } }
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 230, maximum: 330), spacing: 12, alignment: .top)]
    }
}

private enum SmartAlbumCategory: String, CaseIterable, Identifiable {
    case highlights
    case devices
    case places
    case custom
    case catalogueHealth
    case comingLater

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlights: "Highlights"
        case .devices: "Devices"
        case .places: "Places"
        case .custom: "Custom Albums"
        case .catalogueHealth: "Catalogue Health"
        case .comingLater: "Coming Later"
        }
    }

    var subtitle: String {
        switch self {
        case .highlights: "Useful groups created automatically from catalogue metadata"
        case .devices: "Photos and videos grouped by camera make and model"
        case .places: "Travel groups created from available location metadata"
        case .custom: "Albums you create and organize yourself"
        case .catalogueHealth: "Items that may need metadata attention"
        case .comingLater: "Features planned for a future DriveLens update"
        }
    }

    var systemImage: String {
        switch self {
        case .highlights: "sparkles"
        case .devices: "camera"
        case .places: "map"
        case .custom: "rectangle.stack"
        case .catalogueHealth: "wrench.and.screwdriver"
        case .comingLater: "clock"
        }
    }

    func includes(_ album: SmartAlbum) -> Bool {
        switch (self, album.kind) {
        case (.highlights, .screenshots),
             (.highlights, .largeVideos),
             (.highlights, .recentlyEdited),
             (.highlights, .favorites),
             (.devices, .cameraModel),
             (.places, .trip),
             (.custom, .customAlbum),
             (.catalogueHealth, .missingLocation),
             (.comingLater, .people):
            return true
        default:
            return false
        }
    }
}

private struct SmartAlbumGroup: Identifiable {
    let category: SmartAlbumCategory
    let albums: [SmartAlbum]
    var id: SmartAlbumCategory.ID { category.id }
}

private struct SmartAlbumsHeader: View {
    let totalCount: Int
    let deviceCount: Int
    let customCount: Int
    @Binding var filterText: String
    let createAction: () -> Void
    let refreshAction: () -> Void
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    titleBlock
                    Spacer(minLength: 16)
                    metrics
                    actionButtons
                }

                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    metrics
                    actionButtons
                }
            }

            filterField.frame(maxWidth: 560)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Smart Albums", systemImage: "sparkles.rectangle.stack")
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text("Browse automatic groups and albums you create.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            HeaderBadge(systemImage: "rectangle.stack", value: totalCount, label: "albums")
            if deviceCount > 0 {
                HeaderBadge(systemImage: "camera", value: deviceCount, label: "devices")
            }
            HeaderBadge(systemImage: "person.crop.rectangle.stack", value: customCount, label: "custom")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: createAction) {
                Label("New Album", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Create a custom album")

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Refresh smart albums")
            .accessibilityLabel("Refresh smart albums")
        }
    }

    private var filterField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter albums", text: $filterText)
                .textFieldStyle(.plain)
                .focused($isFilterFocused)
                .accessibilityLabel("Filter smart albums")

            if !filterText.isEmpty {
                Button { filterText = "" } label: {
                    Label("Clear Filter", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear album filter")
                .accessibilityLabel("Clear album filter")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFilterFocused ? Color.accentColor.opacity(0.68) : Color.primary.opacity(0.09),
                    lineWidth: isFilterFocused ? 2 : 1
                )
        }
    }
}

private struct SmartAlbumSectionHeader: View {
    let category: SmartAlbumCategory
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: category.systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline.weight(.semibold))
                Text(category.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("\(count)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: Capsule())
                .accessibilityLabel("\(count) album\(count == 1 ? "" : "s")")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyCustomAlbumsCard: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text("Create Your First Album")
                    .font(.headline)
                Text("Organize selected photos and videos without moving the original files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Button(action: action) {
                Label("New Album", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SmartAlbumDetailHeader: View {
    let album: SmartAlbum
    let backAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                backButton
                albumTitle
                Spacer(minLength: 12)
                HeaderBadge(systemImage: album.systemImage, value: album.itemCount, label: "items")
            }

            VStack(alignment: .leading, spacing: 10) {
                backButton
                HStack(alignment: .center, spacing: 12) {
                    albumTitle
                    Spacer(minLength: 10)
                    HeaderBadge(systemImage: album.systemImage, value: album.itemCount, label: "items")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var backButton: some View {
        Button(action: backAction) {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Back to Smart Albums")
    }

    private var albumTitle: some View {
        HStack(spacing: 10) {
            Image(systemName: album.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(album.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SmartAlbumCard: View {
    let album: SmartAlbum
    let action: () -> Void
    var renameAction: (() -> Void)?
    var deleteAction: (() -> Void)?
    @State private var isHovering = false

    init(
        album: SmartAlbum,
        action: @escaping () -> Void,
        renameAction: (() -> Void)? = nil,
        deleteAction: (() -> Void)? = nil
    ) {
        self.album = album
        self.action = action
        self.renameAction = renameAction
        self.deleteAction = deleteAction
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 5) {
                        Text(album.title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(album.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    if album.isPlaceholder {
                        Text("Coming Later")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.55), in: Capsule())
                    } else {
                        Text("\(album.itemCount) item\(album.itemCount == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        isHovering ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                        lineWidth: isHovering ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            if let renameAction {
                Button(action: renameAction) {
                    Label("Rename Album", systemImage: "pencil")
                }
            }
            if renameAction != nil && deleteAction != nil {
                Divider()
            }
            if let deleteAction {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete Album", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(album.isPlaceholder ? "Shows information about this planned feature" : "Opens this album")
    }

    private var accessibilityLabel: String {
        album.isPlaceholder
            ? "\(album.title), coming later"
            : "\(album.title), \(album.itemCount) item\(album.itemCount == 1 ? "" : "s")"
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(album.isPlaceholder ? 0.10 : 0.14))
            Image(systemName: album.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(album.isPlaceholder ? .secondary : Color.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 40, height: 40)
    }

    private var cardBackground: Color {
        isHovering
            ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.09)
            : Color(nsColor: .controlBackgroundColor)
    }
}

private struct CustomAlbumEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let album: CustomAlbum?
    @State private var name: String
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    init(album: CustomAlbum?) {
        self.album = album
        _name = State(initialValue: album?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: album == nil ? "rectangle.stack.badge.plus" : "pencil")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Album Name")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(name.count)/80")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(name.count > 80 ? Color.red : Color.secondary)
                        .accessibilityLabel("\(name.count) of 80 characters")
                }

                TextField("Enter album name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(save)
                    .accessibilityLabel("Album name")
            }

            Label(
                "Albums organize catalogue records only. Original photos and videos are not changed.",
                systemImage: "checkmark.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Saving album")
                    } else {
                        Text(actionTitle)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .onAppear { isNameFocused = true }
        .accessibilityElement(children: .contain)
    }

    private var title: String { album == nil ? "New Custom Album" : "Rename Album" }

    private var subtitle: String {
        album == nil
            ? "Create an album, then add selected items from the Inspector."
            : "Choose a clear, distinct name for this album."
    }

    private var actionTitle: String { album == nil ? "Create Album" : "Rename Album" }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving
            && !trimmedName.isEmpty
            && trimmedName.count <= 80
            && (album == nil || album?.name != trimmedName)
    }

    private func save() {
        guard canSave else { return }
        isSaving = true

        Task {
            let didSave: Bool
            if let album {
                didSave = await appState.renameCustomAlbum(album, to: trimmedName)
            } else {
                didSave = await appState.createCustomAlbum(named: trimmedName)
            }

            if didSave {
                dismiss()
            } else {
                isSaving = false
                isNameFocused = true
            }
        }
    }
}

private struct HeaderBadge: View {
    let systemImage: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
