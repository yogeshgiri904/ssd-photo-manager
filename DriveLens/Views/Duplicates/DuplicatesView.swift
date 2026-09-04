import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var appState: AppState

    private var selectedGroup: DuplicateGroup? {
        if let selectedDuplicateGroupID = appState.selectedDuplicateGroupID,
           let group = appState.duplicateGroups.first(where: { $0.id == selectedDuplicateGroupID }) {
            return group
        }
        return appState.duplicateGroups.first
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = DuplicateReviewLayout(width: geometry.size.width, showsInspector: appState.showingInspector)

            HStack(spacing: 0) {
                duplicateListColumn
                    .frame(width: layout.listWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .layoutPriority(1)

                Divider()

                DuplicateGroupDetail(group: selectedGroup)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(2)

                if layout.showsInspector {
                    Divider()

                    MetadataInspectorView(item: appState.selectedMediaItem)
                        .frame(width: layout.inspectorWidth)
                        .frame(maxHeight: .infinity)
                        .clipped()
                        .layoutPriority(1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle("Duplicates")
        .onAppear {
            appState.refreshDuplicateGroups()
            if let selectedGroup {
                appState.updateVisibleSelectionScope(selectedGroup.sortedItems)
            }
        }
        .onChange(of: appState.selectedDuplicateGroupID) { _, _ in
            if let selectedGroup {
                appState.updateVisibleSelectionScope(selectedGroup.sortedItems)
            }
        }
    }

    private var duplicateListColumn: some View {
        VStack(spacing: 0) {
            header
            Divider()
            groupList
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Duplicates")
                        .font(.title2.weight(.semibold))
                    Text(summaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    findDuplicatesButton
                    mergeAllButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    findDuplicatesButton
                    mergeAllButton
                }
            }
            .controlSize(.small)

            if appState.isFindingDuplicates {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.duplicateScanStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var findDuplicatesButton: some View {
        Button {
            Task { await appState.findDuplicates() }
        } label: {
            if appState.isFindingDuplicates {
                Label("Finding Duplicates", systemImage: "hourglass")
            } else {
                Label("Find Duplicates", systemImage: "magnifyingglass")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(appState.isFindingDuplicates || !appState.canScan)
        .help("Find exact duplicate files by content hash")
    }

    private var mergeAllButton: some View {
        Button {
            appState.mergeAllDuplicateGroups()
        } label: {
            Label("Move Extra Copies to Trash", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(appState.duplicateGroups.isEmpty || appState.isFindingDuplicates)
        .help("Keep one suggested original from each group and review the extra copies before moving them to Trash")
    }

    @ViewBuilder
    private var groupList: some View {
        if appState.duplicateGroups.isEmpty {
            ContentUnavailableView {
                Label("No Duplicate Groups", systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text("Run Find Duplicates to compare same-size files by SHA-256 content hash. Original photos and videos are not changed during the scan.")
            } actions: {
                Button {
                    Task { await appState.findDuplicates() }
                } label: {
                    Label("Find Duplicates", systemImage: "magnifyingglass")
                }
                .disabled(appState.isFindingDuplicates || !appState.canScan)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.duplicateGroups) { group in
                        DuplicateGroupButton(
                            group: group,
                            isSelected: group.id == appState.selectedDuplicateGroupID
                        ) {
                            appState.selectedDuplicateGroupID = group.id
                            appState.updateVisibleSelectionScope(group.sortedItems)
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.visible)
        }
    }

    private var summaryText: String {
        guard !appState.duplicateGroups.isEmpty else {
            return "Review exact duplicate originals safely"
        }

        let reclaimable = ByteCountFormatter.string(
            fromByteCount: appState.duplicateGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes },
            countStyle: .file
        )
        return "\(appState.duplicateGroups.count) groups, about \(reclaimable) recoverable"
    }
}

private struct DuplicateReviewLayout {
    let width: CGFloat
    let showsInspectorSetting: Bool

    init(width: CGFloat, showsInspector: Bool) {
        self.width = width
        self.showsInspectorSetting = showsInspector
    }

    var showsInspector: Bool {
        showsInspectorSetting && width >= 880
    }

    var inspectorWidth: CGFloat {
        min(max(width * 0.24, 280), 320)
    }

    var listWidth: CGFloat {
        let available = width - (showsInspector ? inspectorWidth : 0)
        return min(max(available * 0.27, 260), 320)
    }
}

private struct DuplicateGroupButton: View {
    let group: DuplicateGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.items.count) exact duplicate\(group.items.count == 1 ? "" : "s")")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: group.reclaimableBytes, countStyle: .file) + " recoverable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .background(selectionBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var selectionBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }
        return AnyShapeStyle(Color.clear)
    }
}

private struct DuplicateGroupDetail: View {
    @EnvironmentObject private var appState: AppState
    let group: DuplicateGroup?

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            detailContent
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var detailHeader: some View {
        if let group {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        titleBlock(group)
                        Spacer(minLength: 16)
                        actions(group)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        titleBlock(group)
                        actions(group)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            HStack {
                Label("Duplicate Review", systemImage: "rectangle.on.rectangle")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let group {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let keeper = group.suggestedKeeper {
                        SuggestedKeeperBanner(group: group, keeper: keeper)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 270), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(group.sortedItems, id: \.id) { item in
                            DuplicateItemCard(
                                item: item,
                                group: group,
                                isSuggestedKeeper: item.id == group.suggestedKeeper?.id
                            )
                        }
                    }
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView {
                Label("No Group Selected", systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text("Find duplicates, then choose a group to review exact copies.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func titleBlock(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(group.items.count) Exact Duplicates")
                .font(.title2.weight(.semibold))
            Text("Same SHA-256 content hash. Suggested keeper is based on quality, metadata, location, and clean filename.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func actions(_ group: DuplicateGroup) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.keepSuggestedDuplicateGroup(group)
            } label: {
                Label("Use Suggested Keeper...", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(group.duplicateItems.isEmpty)

            Button {
                appState.selectedMediaItemIDs = Set(group.duplicateItems.map(\.id))
                appState.updateVisibleSelectionScope(group.sortedItems)
            } label: {
                Label("Select Copies", systemImage: "checklist.checked")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Select all copies except the suggested keeper")
        }
    }
}

private struct SuggestedKeeperBanner: View {
    let group: DuplicateGroup
    let keeper: MediaItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested keeper: \(keeper.filename)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(group.keeperReasons.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct DuplicateItemCard: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    let group: DuplicateGroup
    let isSuggestedKeeper: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                AsyncThumbnailView(
                    item: item,
                    showsHoverOverlay: false,
                    cornerRadius: 7
                )
                .environmentObject(appState)
                .aspectRatio(1, contentMode: .fit)
                .onTapGesture {
                    appState.selectSingleMediaItem(item)
                }
                .onTapGesture(count: 2) {
                    appState.viewInViewer(item)
                }
                .contextMenu {
                    MediaFavoriteButton(items: [item])
                    AddToAlbumMenu(items: [item], allowsCreatingAlbum: false)

                    Divider()

                    Button {
                        appState.revealInFinder(item)
                    } label: {
                        Label("Reveal in Finder", systemImage: "finder")
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                if isSuggestedKeeper {
                    Label("Keep", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.filename)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(item.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Label(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file), systemImage: "externaldrive")
                    if let dimensions {
                        Label(dimensions, systemImage: "aspectratio")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            HStack(spacing: 7) {
                Button {
                    appState.keep(item, in: group)
                } label: {
                    Label("Keep This...", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(isSuggestedKeeper ? .accentColor : nil)
                .controlSize(.small)
                .disabled(group.items.count < 2)
                .help("Keep this original and move the other copies to Trash after confirmation")

                Spacer(minLength: 0)

                Button {
                    appState.revealInFinder(item)
                } label: {
                    Label("Reveal", systemImage: "finder")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal in Finder")
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSuggestedKeeper ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var dimensions: String? {
        guard let width = item.width, let height = item.height else { return nil }
        return "\(width) × \(height)"
    }
}
