import SwiftUI

struct MetadataInspectorView: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem?
    @State private var editingItem: MediaItem?
    @State private var isFileDetailsExpanded = true

    var body: some View {
        let selectedItems = appState.selectedOrCurrentVisibleItems()
        let isBatch = selectedItems.count > 1
        InspectorSidebar(
            title: isBatch ? "Selection" : "Inspector",
            subtitle: isBatch ? "\(selectedItems.count) items" : "Media details",
            systemImage: isBatch ? "square.stack" : "sidebar.right",
            isEmpty: item == nil && !isBatch,
            emptyTitle: "A closer look",
            emptySystemImage: "photo.on.rectangle.angled",
            emptyMessage: "Select a photo or video to see its details and edit metadata.",
            scrollsContent: !isBatch
        ) {
            if isBatch {
                MetadataEditingPanel(items: selectedItems)
            } else if let item {
                MediaInspectorSummary(item: item)

                DisclosureGroup(isExpanded: $isFileDetailsExpanded) {
                    VStack(spacing: 0) {
                        InspectorRow("Filename", item.filename)
                        InspectorRow("Path", item.relativePath)
                        InspectorRow("Type", item.kind.label)
                        InspectorRow("Favorite", appState.favoriteState(for: item) ? "Yes" : "No")
                    }
                    .padding(.top, 6)
                } label: {
                    Label("File details", systemImage: "doc")
                        .font(LensInspectorMetrics.section)
                }
                .padding(LensInspectorMetrics.cardInset)
                .lensSurface(radius: LensInspectorMetrics.radius)

                InspectorSection("Capture", systemImage: "calendar") {
                    InspectorRow("Created", item.captureDateLocalText)
                    InspectorRow("Source", item.dateSource.label)
                    if let duration = item.duration, duration.isFinite {
                        InspectorRow("Duration", duration.formatted(.number.precision(.fractionLength(0))) + " seconds")
                    }
                }

                InspectorSection("Camera", systemImage: "camera") {
                    InspectorRow("Camera", item.cameraText.isEmpty ? "Not recorded" : item.cameraText)
                    InspectorRow("Lens", item.lensModel ?? "Not recorded")
                }

                InspectorSection("Location", systemImage: "mappin.and.ellipse") {
                    InspectorRow("Place", item.placeText.isEmpty ? "Not recorded" : item.placeText)
                    if let latitude = item.latitude, let longitude = item.longitude {
                        InspectorRow("GPS", String(format: "%.5f, %.5f", latitude, longitude))
                    }
                    InspectorRow("Source", item.locationSource.label)
                }

                InspectorSection("Notes & keywords", systemImage: "text.alignleft") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.caption?.nilIfEmpty ?? "No caption")
                            .font(LensInspectorMetrics.body)
                            .foregroundStyle(item.caption?.nilIfEmpty == nil ? .secondary : .primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.keywords.isEmpty {
                            Label("No keywords", systemImage: "tag")
                                .font(LensInspectorMetrics.caption).foregroundStyle(.secondary)
                        } else {
                            LensFlowLayout(spacing: 5) {
                                ForEach(Array(item.keywords.enumerated()), id: \.offset) { _, keyword in
                                    Text(keyword)
                                        .font(LensInspectorMetrics.caption)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
                                        .textSelection(.enabled)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Keywords: " + item.keywords.joined(separator: ", "))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LensInspectorMetrics.cardInset)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isBatch, let item {
                InspectorActionBar(item: item) { editingItem = item }
            }
        }
        .sheet(item: $editingItem) { item in
            MediaMetadataEditorSheet(item: item).environmentObject(appState)
        }
        .accessibilityIdentifier("media-inspector")
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
    let scrollsContent: Bool
    private let content: Content

    init(
        title: String, subtitle: String, systemImage: String,
        isEmpty: Bool, emptyTitle: String, emptySystemImage: String, emptyMessage: String,
        scrollsContent: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.emptyMessage = emptyMessage
        self.scrollsContent = scrollsContent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).font(LensInspectorMetrics.section).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text(subtitle).font(LensInspectorMetrics.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, LensInspectorMetrics.inset)
            .frame(height: 44)
            Divider()
            if isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: emptySystemImage)
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, height: 64)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityHidden(true)
                    Text(emptyTitle).font(.system(size: 14, weight: .semibold))
                    Text(emptyMessage).font(LensInspectorMetrics.body)
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scrollsContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: LensInspectorMetrics.sectionSpacing) { content }
                        .padding(LensInspectorMetrics.inset)
                }
            } else {
                content
            }
        }
        .background(LensTheme.sidebar)
        .overlay(alignment: .leading) { LensTheme.line.frame(width: 1).allowsHitTesting(false) }
    }
}

private struct MediaInspectorSummary: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { appState.viewInViewer(item) } label: {
                AsyncMediaThumbnailImage(item: item, fillsAvailableSpace: false, cornerRadius: LensInspectorMetrics.radius)
                    .frame(height: LensInspectorMetrics.previewHeight)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: item.kind == .video ? "play.fill" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black, in: Circle())
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: LensInspectorMetrics.radius)
                            .strokeBorder(isHovered ? Color.accentColor : LensTheme.line, lineWidth: isHovered ? 2 : 1)
                    }
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Open \(item.filename) in the viewer")
            .accessibilityLabel("Preview \(item.filename)")
            .accessibilityIdentifier("inspector-preview")

            VStack(alignment: .leading, spacing: 6) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(item.filename)
                HStack(spacing: 6) {
                    Label(item.kind.label, systemImage: item.kind == .video ? "film" : "photo")
                    if item.isMissing {
                        Text("·").accessibilityHidden(true)
                        Label("Original missing", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(LensInspectorMetrics.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                summaryMetric("Dimensions", value: dimensions, symbol: "aspectratio")
                Divider().frame(height: 26).padding(.horizontal, 10)
                summaryMetric("File size", value: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file), symbol: "doc")
            }
            .padding(LensInspectorMetrics.cardInset)
            .lensSurface(radius: LensInspectorMetrics.radius)
        }
    }

    private var dimensions: String {
        guard let width = item.width, let height = item.height else { return "Unknown" }
        return "\(width) × \(height)"
    }

    private func summaryMetric(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.85).help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct InspectorActionBar: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: edit) {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(InspectorActionButtonStyle(width: 64, tint: .accentColor))
            .help("Edit Metadata")
            .accessibilityLabel("Edit Metadata")
            .accessibilityIdentifier("inspector-edit-metadata")
            MediaFavoriteButton(items: [item])
                .buttonStyle(InspectorActionButtonStyle())
                .labelStyle(.iconOnly)
                .accessibilityValue(appState.favoriteState(for: item) ? "Favorite" : "Not a favorite")
            AddToAlbumMenu(items: [item])
                .labelStyle(.iconOnly)
                .menuStyle(InspectorActionMenuStyle())
            Menu {
                Section("Open") {
                    Button("Open in Viewer", systemImage: "arrow.up.left.and.arrow.down.right") { appState.viewInViewer(item) }
                    Button("Reveal in Finder", systemImage: "finder") { appState.revealInFinder(item) }
                }
                Section("Show In") {
                    Button("Timeline", systemImage: "calendar") { appState.showInTimeline(item) }
                    Button("Folder", systemImage: "folder") { appState.showInFolder(item) }
                    Button("Map", systemImage: "map") { appState.showOnMap(item) }
                        .disabled(item.latitude == nil || item.longitude == nil)
                }
                Section("Copy & Share") {
                    Button("Copy Original…", systemImage: "doc.on.doc") { appState.copyOriginal(item) }
                    Button("Share…", systemImage: "square.and.arrow.up") { appState.shareOriginal(item) }
                }
            } label: {
                Label("More Actions", systemImage: "ellipsis")
            }
            .menuStyle(InspectorActionMenuStyle())
            .help("Open, locate, copy, or share this item")
            .accessibilityLabel("More Actions")

            Button(role: .destructive) {
                appState.requestDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(InspectorActionButtonStyle(tint: .red))
            .help("Move original to Trash…")
            .accessibilityLabel("Move to Trash")
            .accessibilityHint("Asks for confirmation before moving the original file to Trash.")
            .accessibilityIdentifier("inspector-delete")
        }
        .labelStyle(.iconOnly)
        .frame(maxWidth: .infinity)
        .padding(LensInspectorMetrics.inset)
        .background(LensChrome())
        .overlay(alignment: .top) { Divider() }
    }
}

// Buttons and menus use the same surface instead of their different native bezel heights.
private struct InspectorActionSurface: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    var width: CGFloat = 32
    var tint: Color = .primary
    var isPressed = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: width, height: LensInspectorMetrics.actionHeight)
            .background(tint.opacity(isPressed ? 0.18 : isHovered ? 0.12 : 0.07),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(tint.opacity(contrast == .increased ? 0.6 : 0.1), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 && isEnabled }
    }
}

private struct InspectorActionButtonStyle: ButtonStyle {
    var width: CGFloat = 32
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(InspectorActionSurface(width: width, tint: tint, isPressed: configuration.isPressed))
    }
}

private struct InspectorActionMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .modifier(InspectorActionSurface())
    }
}

struct MediaMetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Edit Metadata", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                Text(item.filename)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Edits stay in DriveLens. Original files remain unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            Divider()
            MetadataEditingPanel(items: [item], onSave: { dismiss() }, onClose: { dismiss() })
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .frame(width: 480, height: 500)
        .accessibilityIdentifier("metadata-editor")
        .background(LensTheme.sidebar)
    }
}

private struct MetadataEditingPanel: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]
    var onSave: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var isSaving = false
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

    @State private var summary: BatchMetadataSummary = .empty

    var body: some View {
        ScrollView {
            editorContents.padding(LensInspectorMetrics.inset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editingActions
                .padding(LensInspectorMetrics.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LensChrome())
                .overlay(alignment: .top) { Divider() }
        }
        .disabled(isSaving)
        .onAppear { resetEditableFields() }
        .onChange(of: items) { oldItems, newItems in
            if oldItems.map(\.id) != newItems.map(\.id) {
                resetEditableFields()
            } else {
                summary = appState.batchMetadataSummary(for: newItems)
            }
        }
    }

    private var editingActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pendingFieldCount == 0 ? "Choose fields to edit" : "\(pendingFieldCount) field\(pendingFieldCount == 1 ? "" : "s") selected")
                .font(LensInspectorMetrics.caption)
                .foregroundStyle(.secondary)
            if let metadataError {
                Text(metadataError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(metadataError)
                    .accessibilityIdentifier("metadata-error")
            }
            HStack(spacing: 8) {
                Button {
                    applyMetadataEdits()
                } label: {
                    Label(isSaving ? "Saving…" : "Apply", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasPendingMetadataChange || isSaving)
                .accessibilityLabel("Apply metadata changes")
                .accessibilityIdentifier("metadata-apply")

                Button {
                    resetEditableFields()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasPendingMetadataChange)
                .accessibilityIdentifier("metadata-reset")
                if let onClose {
                    Spacer()
                    Button("Close", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private var editorContents: some View {
        VStack(alignment: .leading, spacing: 16) {
            if items.count > 1 {
                BatchSelectionSummary(items: items)

                DisclosureGroup("Shared metadata") {
                    InspectorRow("Created Date", createdDateSummaryText)
                    InspectorRow("Keywords", summary.sharedKeywords.isEmpty ? "None shared" : summary.sharedKeywords.joined(separator: ", "))
                    InspectorRow("Caption", summary.hasMixedCaptions ? "Mixed" : summary.commonCaption ?? "None")
                    InspectorRow("Camera", cameraSummaryText)
                    InspectorRow("Location", summary.hasMixedLocations ? "Mixed" : summary.commonLocationText ?? "None")
                    InspectorRow("Favorite", favoriteText)
                }
                .font(LensInspectorMetrics.section)
                .padding(LensInspectorMetrics.cardInset)
                .lensSurface(radius: LensInspectorMetrics.radius)
            }

            InspectorSection("Edit fields", systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 0) {
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
                        TextField(summary.hasMixedCaptions ? "Replace mixed captions" : "Caption", text: $caption, axis: .vertical)
                            .lineLimit(2...5)
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
                                TextField("Latitude", text: $latitude).accessibilityIdentifier("metadata-latitude")
                                TextField("Longitude", text: $longitude).accessibilityIdentifier("metadata-longitude")
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
                        Spacer(minLength: 4)

                        Picker("Favorite", selection: $favoriteChoice) {
                            ForEach(BatchFavoriteChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("Favorite")
                    }
                    .padding(LensInspectorMetrics.cardInset)
                }
            }

            if items.count > 1 {
                DisclosureGroup("Add a keyword to all") {
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
                    .padding(.top, 10)
                }
                .font(LensInspectorMetrics.section)
                .padding(LensInspectorMetrics.cardInset)
                .lensSurface(radius: LensInspectorMetrics.radius)

                DisclosureGroup("Add to an album") {
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
                    .padding(.top, 10)
                }
                .font(LensInspectorMetrics.section)
                .padding(LensInspectorMetrics.cardInset)
                .lensSurface(radius: LensInspectorMetrics.radius)
            }
        }
    }

    @ViewBuilder
    private func metadataToggle<Content: View>(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: isOn) {
                Label(title, systemImage: systemImage)
                    .font(LensInspectorMetrics.section)
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel("Edit " + title)
            .accessibilityValue(isOn.wrappedValue ? "Editing" : "Unchanged")
            .accessibilityIdentifier("metadata-field-" + title)

            if isOn.wrappedValue {
                content()
                    .padding(.leading, 22)
            } else {
                Text(fieldSummary(title))
                    .font(LensInspectorMetrics.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LensInspectorMetrics.cardInset)
        .padding(.vertical, 8)
        .background(isOn.wrappedValue ? Color.accentColor.opacity(0.045) : Color.clear)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 32) }
    }

    private func fieldSummary(_ title: String) -> String {
        switch title {
        case "Created Date": return createdDateSummaryText
        case "Keywords": return summary.hasMixedKeywords ? "Mixed keywords" : summary.sharedKeywords.isEmpty ? "No keywords" : summary.sharedKeywords.joined(separator: ", ")
        case "Caption": return summary.hasMixedCaptions ? "Mixed captions" : summary.commonCaption ?? "No caption"
        case "Camera": return cameraSummaryText
        case "Location": return summary.hasMixedLocations ? "Mixed locations" : summary.commonLocationText ?? "No location"
        default: return "Unchanged"
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

    private var pendingFieldCount: Int {
        [replaceKeywords, updateCaption, updateCreatedDate, updateCameraDetails, updateLocation,
         favoriteChoice != .leaveUnchanged].filter { $0 }.count
    }

    private var hasPendingMetadataChange: Bool { pendingFieldCount > 0 }

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

        guard !isSaving else { return }
        isSaving = true
        Task {
            let saved = await appState.applyBatchMetadataUpdate(update, to: items)
            isSaving = false
            if saved {
                onSave?()
            } else {
                metadataError = appState.userMessage ?? "Could not save metadata. Please try again."
            }
        }
    }

    private func addToAlbum() {
        let value = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task { await appState.addToCustomAlbum(named: value, items: items) }
    }

    private func resetEditableFields() {
        summary = appState.batchMetadataSummary(for: items)
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
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(items.count) items selected")
                    .font(LensInspectorMetrics.section).monospacedDigit()
                Text("\(photoCount) photo\(photoCount == 1 ? "" : "s") · \(videoCount) video\(videoCount == 1 ? "" : "s")")
                    .font(LensInspectorMetrics.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var photoCount: Int {
        items.filter { $0.kind == .photo || $0.kind == .livePhoto }.count
    }

    private var videoCount: Int {
        items.filter { $0.kind == .video }.count
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
    let systemImage: String?
    private let content: Content

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true) }
                Text(title).accessibilityAddTraits(.isHeader)
            }
            .font(LensInspectorMetrics.section)
            .padding(.horizontal, 2)
            VStack(spacing: 0) { content }
                .lensSurface(radius: LensInspectorMetrics.radius)
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundStyle(value == "None" || value == "Not recorded" ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(LensInspectorMetrics.body)
        .padding(.horizontal, LensInspectorMetrics.cardInset)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
