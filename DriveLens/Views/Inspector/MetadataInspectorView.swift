import SwiftUI

struct MetadataInspectorView: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem?

    var body: some View {
        let selectedItems = appState.selectedOrCurrentVisibleItems()
        InspectorSidebar(
            title: selectedItems.count > 1 ? "Batch Metadata" : "Inspector",
            subtitle: selectedItems.count > 1 ? "\(selectedItems.count) items selected" : item?.filename ?? "No item selected",
            systemImage: selectedItems.count > 1 ? "square.stack.3d.up" : itemSymbol,
            isEmpty: item == nil && selectedItems.count < 2,
            emptyTitle: "No Selection",
            emptySystemImage: "sidebar.right",
            emptyMessage: "Select a thumbnail to inspect metadata and manage the original file."
        ) {
            if selectedItems.count > 1 {
                BatchMetadataPanel(items: selectedItems)
                    .environmentObject(appState)
            } else if let item {
                MediaInspectorSummary(item: item)
                InspectorActionBar(item: item)

                InspectorSection("Essentials") {
                    InspectorRow("Capture Date", item.captureDateLocalText)
                    InspectorRow("Date Source", item.dateSource.label)
                    InspectorRow("Location", item.placeText.isEmpty ? item.locationSource.label : item.placeText)
                    InspectorRow("Filename", item.filename)
                    InspectorRow("Relative Path", item.relativePath)
                }

                InspectorSection("Media") {
                    InspectorRow("Type", item.kind.label)
                    InspectorRow("File Size", ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    if let width = item.width, let height = item.height {
                        InspectorRow("Dimensions", "\(width) x \(height)")
                    }
                    if let duration = item.duration, duration.isFinite {
                        InspectorRow("Duration", format(duration))
                    }
                }

                InspectorSection("Camera") {
                    InspectorRow("Camera", item.cameraText.isEmpty ? "None" : item.cameraText)
                    InspectorRow("Lens", item.lensModel ?? "None")
                }

                InspectorSection("More Details") {
                    InspectorRow("Favorite", item.isFavorite ? "Yes" : "No")
                    InspectorRow("Caption", item.caption ?? "None")
                    InspectorRow("Keywords", item.keywords.isEmpty ? "None" : item.keywords.joined(separator: ", "))
                    if let latitude = item.latitude, let longitude = item.longitude {
                        InspectorRow("GPS", String(format: "%.5f, %.5f", latitude, longitude))
                    }
                }
            }
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var itemSymbol: String {
        switch item?.kind {
        case .video: "film"
        case .livePhoto: "photo"
        case .photo: "photo"
        case nil: "sidebar.right"
        }
    }
}

struct InspectorSidebar<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEmpty: Bool
    let emptyTitle: String
    let emptySystemImage: String
    let emptyMessage: String
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        isEmpty: Bool,
        emptyTitle: String,
        emptySystemImage: String,
        emptyMessage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.emptyMessage = emptyMessage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(14)
                }
                .scrollIndicators(.visible)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.bar)
    }
}

private struct MediaInspectorSummary: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncThumbnailView(
                item: item,
                showsHoverOverlay: false,
                showsSelection: false,
                cornerRadius: 7,
                fillsAvailableSpace: true
            )
            .environmentObject(appState)
            .frame(width: 92, height: 92)
            .onTapGesture {
                appState.viewInViewer(item)
            }
            .accessibilityHint("Click to view in preview")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: mediaSystemImage)
                        .foregroundStyle(.secondary)
                    Text(item.kind.label)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.35), in: Capsule())

                Text(item.filename)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(item.captureDateLocalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var mediaSystemImage: String {
        switch item.kind {
        case .video: "film"
        case .livePhoto: "photo"
        case .photo: "photo"
        }
    }
}

private struct InspectorActionBar: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalActions
            compactActions
        }
    }

    private var horizontalActions: some View {
        HStack(spacing: 7) {
            Button {
                appState.viewInViewer(item)
            } label: {
                Label("View", systemImage: item.kind == .video ? "play.rectangle" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .help("View in preview")

            Spacer(minLength: 0)

            inspectorButton("Reveal", systemImage: "finder") {
                appState.revealInFinder(item)
            }
            .help("Reveal in Finder")

            inspectorButton("Copy", systemImage: "doc.on.doc") {
                appState.copyOriginal(item)
            }
            .help("Copy original")

            inspectorButton("Share", systemImage: "square.and.arrow.up") {
                appState.shareOriginal(item)
            }
            .help("Share original")

            Button(role: .destructive) {
                appState.requestDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help("Move to Trash")
        }
    }

    private var compactActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button {
                    appState.viewInViewer(item)
                } label: {
                    Label("View", systemImage: item.kind == .video ? "play.rectangle" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .help("View in preview")

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    appState.requestDelete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help("Move to Trash")
            }

            HStack(spacing: 7) {
                inspectorButton("Reveal", systemImage: "finder") {
                    appState.revealInFinder(item)
                }
                .help("Reveal in Finder")

                inspectorButton("Copy", systemImage: "doc.on.doc") {
                    appState.copyOriginal(item)
                }
                .help("Copy original")

                inspectorButton("Share", systemImage: "square.and.arrow.up") {
                    appState.shareOriginal(item)
                }
                .help("Share original")

                Spacer(minLength: 0)
            }
        }
    }

    private func inspectorButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .controlSize(.small)
    }
}

private struct BatchMetadataPanel: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]

    @State private var keyword = ""
    @State private var caption = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var city = ""
    @State private var state = ""
    @State private var country = ""
    @State private var albumName = ""

    private var summary: BatchMetadataSummary {
        appState.batchMetadataSummary(for: items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BatchSelectionSummary(items: items)

            InspectorSection("Shared Metadata") {
                InspectorRow("Keywords", summary.sharedKeywords.isEmpty ? "None shared" : summary.sharedKeywords.joined(separator: ", "))
                InspectorRow("Caption", summary.hasMixedCaptions ? "Mixed" : summary.commonCaption ?? "None")
                InspectorRow("Location", summary.hasMixedLocations ? "Mixed" : summary.commonLocationText ?? "None")
                InspectorRow("Favorite", favoriteText)
            }

            InspectorSection("Keywords") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Add keyword", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addKeyword() }
                    Button {
                        addKeyword()
                    } label: {
                        Label("Add Keyword", systemImage: "tag")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
            }

            InspectorSection("Caption") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(summary.hasMixedCaptions ? "Replace mixed captions" : "Set caption", text: $caption)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { setCaption() }
                    Button {
                        setCaption()
                    } label: {
                        Label("Apply Caption", systemImage: "text.quote")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
            }

            InspectorSection("Location") {
                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            TextField("Latitude", text: $latitude)
                            TextField("Longitude", text: $longitude)
                        }
                        GridRow {
                            TextField("City", text: $city)
                            TextField("State", text: $state)
                        }
                        GridRow {
                            TextField("Country", text: $country)
                                .gridCellColumns(2)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        setLocation()
                    } label: {
                        Label("Set Location", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(latitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || longitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
            }

            InspectorSection("Favorite") {
                HStack(spacing: 8) {
                    Button {
                        Task { await appState.setFavorite(true, for: items) }
                    } label: {
                        Label("Mark", systemImage: "heart.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        Task { await appState.setFavorite(false, for: items) }
                    } label: {
                        Label("Remove", systemImage: "heart.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
            }

            InspectorSection("Custom Album") {
                VStack(alignment: .leading, spacing: 8) {
                    if !appState.customAlbums.isEmpty {
                        Menu {
                            ForEach(appState.customAlbums) { album in
                                Button(album.name) {
                                    albumName = album.name
                                }
                            }
                        } label: {
                            Label(albumName.isEmpty ? "Choose Existing Album" : albumName, systemImage: "rectangle.stack")
                        }
                        .menuStyle(.button)
                        .controlSize(.small)
                    }

                    TextField("Album name", text: $albumName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addToAlbum() }

                    Button {
                        addToAlbum()
                    } label: {
                        Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
            }
        }
        .onAppear {
            caption = summary.commonCaption ?? ""
        }
        .onChange(of: items.map(\.id)) { _, _ in
            caption = summary.commonCaption ?? ""
        }
    }

    private var favoriteText: String {
        guard let isFavorite = summary.commonFavorite else { return "Mixed" }
        return isFavorite ? "Yes" : "No"
    }

    private func addKeyword() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        keyword = ""
        Task { await appState.addKeyword(value, to: items) }
    }

    private func setCaption() {
        Task { await appState.setCaption(caption, for: items) }
    }

    private func setLocation() {
        Task {
            await appState.setLocation(
                latitudeText: latitude,
                longitudeText: longitude,
                city: city,
                state: state,
                country: country,
                for: items
            )
        }
    }

    private func addToAlbum() {
        let value = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task { await appState.addToCustomAlbum(named: value, items: items) }
    }
}

private struct BatchSelectionSummary: View {
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("\(items.count) Selected")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
            }

            HStack(spacing: 8) {
                MiniCount(systemImage: "photo", value: photoCount, label: "Photos")
                MiniCount(systemImage: "film", value: videoCount, label: "Videos")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var photoCount: Int {
        items.filter { $0.kind == .photo || $0.kind == .livePhoto }.count
    }

    private var videoCount: Int {
        items.filter { $0.kind == .video }.count
    }
}

private struct MiniCount: View {
    let systemImage: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 86, alignment: .leading)

                Text(value)
                    .font(.caption)
                    .foregroundStyle(value == "None" ? .secondary : .primary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 106)
                .opacity(0.55)
        }
    }
}
