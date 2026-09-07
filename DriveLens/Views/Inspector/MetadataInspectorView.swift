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
            emptyMessage: "Select a thumbnail to inspect metadata, preview media, or manage the original file."
        ) {
            if selectedItems.count > 1 {
                BatchMetadataPanel(items: selectedItems)
                    .environmentObject(appState)
            } else if let item {
                MediaInspectorSummary(item: item)
                InspectorActionBar(item: item)

                InspectorSection("Essentials") {
                    InspectorRow("Created Date", item.captureDateLocalText)
                    InspectorRow("Date Source", item.dateSource.label)
                    InspectorRow("Location", item.placeText.isEmpty ? item.locationSource.label : item.placeText)
                    InspectorRow("Filename", item.filename)
                    InspectorRow("Relative Path", item.relativePath)
                }

                InspectorSection("Media") {
                    InspectorRow("Type", item.kind.label)
                    InspectorRow("File Size", ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    if let width = item.width, let height = item.height {
                        InspectorRow("Dimensions", "\(width) × \(height)")
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
                    InspectorRow("Favorite", appState.favoriteState(for: item) ? "Yes" : "No")
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
            .accessibilityLabel("Preview \(item.filename)")
            .accessibilityHint("Opens this item in the viewer.")

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
            .help("Open in viewer")

            Spacer(minLength: 0)

            favoriteButton
            albumMenu

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
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help("Move to Trash")
            .accessibilityLabel("Move to Trash")
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
                .help("Open in viewer")

                Spacer(minLength: 0)

                favoriteButton
                albumMenu

                Button(role: .destructive) {
                    appState.requestDelete(item)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help("Move to Trash")
                .accessibilityLabel("Move to Trash")
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

    private var favoriteButton: some View {
        MediaFavoriteButton(items: [item])
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .controlSize(.small)
    }

    private var albumMenu: some View {
        AddToAlbumMenu(items: [item])
            .menuStyle(.button)
            .labelStyle(.iconOnly)
            .controlSize(.small)
    }
}

private struct BatchMetadataPanel: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]

    @State private var keyword = ""
    @State private var replaceKeywords = false
    @State private var keywordsText = ""
    @State private var updateCaption = false
    @State private var caption = ""
    @State private var updateCreatedDate = false
    @State private var createdDate = Date()
    @State private var updateCameraDetails = false
    @State private var cameraMake = ""
    @State private var cameraModel = ""
    @State private var lensModel = ""
    @State private var updateLocation = false
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var city = ""
    @State private var state = ""
    @State private var country = ""
    @State private var favoriteChoice: BatchFavoriteChoice = .leaveUnchanged
    @State private var albumName = ""
    @State private var metadataError: String?

    private var summary: BatchMetadataSummary {
        appState.batchMetadataSummary(for: items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BatchSelectionSummary(items: items)

            InspectorSection("Shared Metadata") {
                InspectorRow("Created Date", createdDateSummaryText)
                InspectorRow("Keywords", summary.sharedKeywords.isEmpty ? "None shared" : summary.sharedKeywords.joined(separator: ", "))
                InspectorRow("Caption", summary.hasMixedCaptions ? "Mixed" : summary.commonCaption ?? "None")
                InspectorRow("Camera", cameraSummaryText)
                InspectorRow("Location", summary.hasMixedLocations ? "Mixed" : summary.commonLocationText ?? "None")
                InspectorRow("Favorite", favoriteText)
            }

            InspectorSection("Edit Metadata") {
                VStack(alignment: .leading, spacing: 12) {
                    metadataToggle("Created Date", systemImage: "calendar", isOn: $updateCreatedDate) {
                        DatePicker(
                            "Created Date",
                            selection: $createdDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .accessibilityLabel("Created date")
                    }

                    metadataToggle("Keywords", systemImage: "tag", isOn: $replaceKeywords) {
                        TextField("Comma-separated keywords", text: $keywordsText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Keywords")
                    }

                    metadataToggle("Caption", systemImage: "text.quote", isOn: $updateCaption) {
                        TextField(summary.hasMixedCaptions ? "Replace mixed captions" : "Caption", text: $caption)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Caption")
                    }

                    metadataToggle("Camera", systemImage: "camera", isOn: $updateCameraDetails) {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                TextField("Make", text: $cameraMake)
                                TextField("Model", text: $cameraModel)
                            }
                            GridRow {
                                TextField("Lens", text: $lensModel)
                                    .gridCellColumns(2)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityElement(children: .contain)
                    }

                    metadataToggle("Location", systemImage: "mappin.and.ellipse", isOn: $updateLocation) {
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
                        .accessibilityElement(children: .contain)
                    }

                    HStack(spacing: 9) {
                        Label("Favorite", systemImage: "heart")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 104, alignment: .leading)

                        Picker("Favorite", selection: $favoriteChoice) {
                            ForEach(BatchFavoriteChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("Favorite")
                    }

                    if let metadataError {
                        Text(metadataError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(metadataError)
                    }

                    HStack(spacing: 8) {
                        Button {
                            applyMetadataEdits()
                        } label: {
                            Label("Apply Changes", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!hasPendingMetadataChange)

                        Button {
                            resetEditableFields()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
            }

            InspectorSection("Add Keyword") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Keyword", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addKeyword() }
                        .accessibilityLabel("Keyword to add")
                    Button {
                        addKeyword()
                    } label: {
                        Label("Add Keyword", systemImage: "tag")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            resetEditableFields()
        }
        .onChange(of: items.map(\.id)) { _, _ in
            resetEditableFields()
        }
    }

    @ViewBuilder
    private func metadataToggle<Content: View>(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: isOn) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(title)

            content()
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1 : 0.55)
                .padding(.leading, 22)
        }
    }

    private var favoriteText: String {
        guard let isFavorite = summary.commonFavorite else { return "Mixed" }
        return isFavorite ? "Yes" : "No"
    }

    private var createdDateSummaryText: String {
        summary.hasMixedCaptureDates ? "Mixed" : summary.commonCaptureDate.map(formatDate) ?? "None"
    }

    private var cameraSummaryText: String {
        if summary.hasMixedCameraDetails {
            return "Mixed"
        }
        let camera = [summary.commonCameraMake, summary.commonCameraModel, summary.commonLensModel]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        return camera.isEmpty ? "None" : camera
    }

    private var hasPendingMetadataChange: Bool {
        replaceKeywords
            || updateCaption
            || updateCreatedDate
            || updateCameraDetails
            || updateLocation
            || favoriteChoice != .leaveUnchanged
    }

    private func addKeyword() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        keyword = ""
        Task { await appState.addKeyword(value, to: items) }
    }

    private func applyMetadataEdits() {
        metadataError = nil
        let coordinates = parsedCoordinates()
        if let error = coordinates.error {
            metadataError = error
            return
        }

        let update = BatchMetadataUpdate(
            replaceKeywords: replaceKeywords ? parsedKeywords(from: keywordsText) : nil,
            caption: updateCaption ? caption : nil,
            createdDate: updateCreatedDate ? createdDate : nil,
            cameraMake: cameraMake.nilIfEmpty,
            cameraModel: cameraModel.nilIfEmpty,
            lensModel: lensModel.nilIfEmpty,
            updatesCameraDetails: updateCameraDetails,
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            city: city.nilIfEmpty,
            state: state.nilIfEmpty,
            country: country.nilIfEmpty,
            updatesLocation: updateLocation,
            favorite: favoriteChoice.favoriteValue
        )

        Task { await appState.applyBatchMetadataUpdate(update, to: items) }
    }

    private func addToAlbum() {
        let value = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task { await appState.addToCustomAlbum(named: value, items: items) }
    }

    private func resetEditableFields() {
        replaceKeywords = false
        updateCaption = false
        updateCreatedDate = false
        updateCameraDetails = false
        updateLocation = false
        favoriteChoice = .leaveUnchanged
        metadataError = nil
        keywordsText = summary.commonKeywords?.joined(separator: ", ") ?? ""
        caption = summary.commonCaption ?? ""
        createdDate = summary.commonCaptureDate ?? items.first?.captureDate ?? Date()
        cameraMake = summary.commonCameraMake ?? ""
        cameraModel = summary.commonCameraModel ?? ""
        lensModel = summary.commonLensModel ?? ""

        if !summary.hasMixedLocations, let first = items.first {
            latitude = first.latitude.map { String(format: "%.6f", $0) } ?? ""
            longitude = first.longitude.map { String(format: "%.6f", $0) } ?? ""
            city = first.city ?? ""
            state = first.state ?? ""
            country = first.country ?? ""
        } else {
            latitude = ""
            longitude = ""
            city = ""
            state = ""
            country = ""
        }
    }

    private func parsedCoordinates() -> (latitude: Double?, longitude: Double?, error: String?) {
        guard updateLocation else { return (nil, nil, nil) }
        let latitudeText = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latitudeText.isEmpty || !longitudeText.isEmpty else {
            return (nil, nil, nil)
        }
        guard !latitudeText.isEmpty, !longitudeText.isEmpty else {
            return (nil, nil, "Enter both latitude and longitude, or leave both blank.")
        }
        guard let latitude = Double(latitudeText),
              let longitude = Double(longitudeText),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return (nil, nil, "Enter a valid latitude and longitude.")
        }
        return (latitude, longitude, nil)
    }

    private func parsedKeywords(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.localizedLowercase).inserted }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum BatchFavoriteChoice: String, CaseIterable, Identifiable {
    case leaveUnchanged
    case favorite
    case notFavorite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leaveUnchanged: "Leave Unchanged"
        case .favorite: "Mark as Favorite"
        case .notFavorite: "Remove from Favorites"
        }
    }

    var favoriteValue: Bool? {
        switch self {
        case .leaveUnchanged: nil
        case .favorite: true
        case .notFavorite: false
        }
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
