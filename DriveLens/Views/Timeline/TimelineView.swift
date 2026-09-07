import AppKit
import SwiftUI

enum TimelineControlScope {
    case none
    case timeline
    case videos
    case recentlyAdded
    case smartAlbums
    case search
}

struct TimelineView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isGridFocused: Bool
    let items: [MediaItem]
    var title = "Timeline"
    var counts: CatalogueCounts?
    var showsHeader = true
    var showsQuickFilters = false
    var controlScope: TimelineControlScope = .none
    var backAction: (() -> Void)?

    private var groupedSections: [(String, [MediaItem])] {
        guard controlScope != .none else {
            return groupedByDate(items, date: \.captureDate, ascending: false)
        }

        switch activeSort {
        case .captureNewest:
            return groupedByDate(items, date: \.captureDate, ascending: false)
        case .captureOldest:
            return groupedByDate(items, date: \.captureDate, ascending: true)
        case .recentlyAdded:
            return groupedByDate(items, date: \.addedAt, ascending: false, prefix: "Added")
        case .fileName:
            return groupedByFilename(items)
        case .largestFile:
            return [("Largest Files", items.sorted { lhs, rhs in
                if lhs.fileSize == rhs.fileSize {
                    return lhs.captureDate > rhs.captureDate
                }
                return lhs.fileSize > rhs.fileSize
            })]
        }
    }

    private var activeSort: TimelineSortOption {
        switch controlScope {
        case .timeline:
            return appState.timelineSort
        case .videos:
            return appState.videoSort
        case .recentlyAdded:
            return appState.recentlyAddedSort
        case .smartAlbums:
            return appState.smartAlbumSort
        case .search:
            return appState.searchSort
        case .none:
            return .captureNewest
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if showsHeader {
                    TimelineHeader(title: title, items: items, counts: counts, showsQuickFilters: showsQuickFilters, controlScope: controlScope, backAction: backAction)
                        .environmentObject(appState)
                    Divider()
                }
                content
            }

            if appState.showingInspector {
                MetadataInspectorView(item: appState.selectedMediaItem)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
            }
        }
        .navigationTitle(title)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                let metrics = PhotoGridMetrics(width: geometry.size.width, targetItemWidth: appState.gridSize)

                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                            if items.isEmpty {
                                emptyState
                                    .frame(minHeight: max(420, geometry.size.height - 40))
                            } else {
                                if !showsQuickFilters {
                                    jumpStrip(proxy: proxy)
                                }

                                ForEach(groupedSections, id: \.0) { section, sectionItems in
                                    Section {
                                        LazyVGrid(columns: metrics.columns, alignment: .leading, spacing: metrics.spacing) {
                                            ForEach(sectionItems) { item in
                                                AsyncThumbnailView(item: item)
                                                    .environmentObject(appState)
                                                    .frame(width: metrics.itemWidth, height: metrics.itemWidth)
                                                    .id(item.id)
                                                    .onTapGesture(count: 2) {
                                                        open(item)
                                                    }
                                                    .simultaneousGesture(
                                                        TapGesture().onEnded {
                                                            select(item)
                                                        }
                                                    )
                                                    .contextMenu {
                                                        Button {
                                                            open(item)
                                                        } label: {
                                                            Label("Open in Viewer", systemImage: "arrow.up.left.and.arrow.down.right")
                                                        }

                                                        Button {
                                                            select(item)
                                                        } label: {
                                                            Label("Select", systemImage: "checkmark.circle")
                                                        }

                                                        Divider()

                                                        MediaFavoriteButton(items: batchItems(for: item))

                                                        AddToAlbumMenu(
                                                            items: batchItems(for: item),
                                                            allowsCreatingAlbum: false
                                                        )

                                                        Divider()

                                                        Button {
                                                            appState.copyMediaItems(batchItems(for: item))
                                                        } label: {
                                                            Label("Copy Original", systemImage: "doc.on.doc")
                                                        }

                                                        Button {
                                                            prepareRename(for: item)
                                                        } label: {
                                                            Label("Rename", systemImage: "pencil")
                                                        }

                                                        Divider()

                                                        Button(role: .destructive) {
                                                            requestDelete(for: item)
                                                        } label: {
                                                            Label("Move to Trash", systemImage: "trash")
                                                        }
                                                    }
                                                    .onAppear {
                                                        Task {
                                                            await appState.loadNextPageIfNeeded(currentItem: item)
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal, metrics.horizontalPadding)
                                        .padding(.bottom, 14)
                                    } header: {
                                        TimelineSectionHeader(title: section, count: sectionItems.count, horizontalPadding: metrics.horizontalPadding)
                                    }
                                }
                                loadingFooter
                            }
                        }
                        .padding(.top, items.isEmpty ? 0 : 8)
                        .padding(.bottom, appState.selectedMediaItemIDs.isEmpty ? 0 : 72)
                    }

                    if !appState.selectedMediaItemIDs.isEmpty {
                        BatchSelectionBar(
                            selectedCount: appState.selectedMediaItems(in: items).count,
                            totalCount: items.count
                        )
                        .environmentObject(appState)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .focusable()
                .focused($isGridFocused)
                .focusEffectDisabled()
                .overlay {
                    Rectangle()
                        .strokeBorder(isGridFocused ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isGridFocused = true
                    }
                )
                .onAppear {
                    isGridFocused = true
                    appState.updateVisibleSelectionScope(items)
                }
                .onChange(of: items.map(\.id)) { _, _ in
                    appState.updateVisibleSelectionScope(items)
                }
                .onMoveCommand { direction in
                    switch direction {
                    case .left, .up:
                        appState.selectAdjacentItem(offset: -1)
                    case .right, .down:
                        appState.selectAdjacentItem(offset: 1)
                    default:
                        break
                    }
                }
                .onKeyPress(.space) {
                    if let item = appState.selectedMediaItem {
                        open(item)
                        return .handled
                    }
                    return .ignored
                }
                .onDeleteCommand {
                    appState.requestDeleteSelectedMediaItems()
                }
                .onExitCommand {
                    if !appState.selectedMediaItemIDs.isEmpty {
                        appState.clearMediaSelection()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateSymbol)
        } description: {
            Text(emptyStateMessage)
        } actions: {
            if title == "Search" && hasActiveSearch {
                Button {
                    appState.clearSearch()
                } label: {
                    Label("Clear Search and Filters", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    appState.requestCatalogueUpdate()
                } label: {
                    Label("Update Catalogue", systemImage: "arrow.clockwise")
                }
                .disabled(!appState.canScan)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingFooter: some View {
        let total = counts?.totalItems ?? items.count
        return Group {
            if total > items.count {
                HStack {
                    Spacer()
                    Label("Showing \(items.count) of \(total)", systemImage: "square.grid.3x3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var emptyStateTitle: String {
        if title == "Search" { return hasActiveSearch ? "No Results" : "Search Your Catalogue" }
        if title == "Videos" { return "No Videos" }
        return "No Media"
    }

    private var emptyStateMessage: String {
        if title == "Search" {
            if !hasActiveSearch {
                return "Search by filename, date, place, camera, or keyword."
            }
            return "Try a different filename, date, place, camera, or filter combination."
        }
        if showsQuickFilters && controlScope != .none {
            return "Clear filters or update the catalogue to refresh indexed media from the selected folders."
        }
        return "Choose Update Catalogue to scan the selected folders. Original photos and videos are not changed."
    }

    private var emptyStateSymbol: String {
        if title == "Search" { return "magnifyingglass" }
        if title == "Videos" { return "film" }
        return "photo.on.rectangle.angled"
    }

    private var hasActiveSearch: Bool {
        !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || appState.searchQuickFilter != .all
            || appState.selectedSearchYear != nil
            || appState.searchSort != .captureNewest
    }

    private func jumpStrip(proxy: ScrollViewProxy) -> some View {
        let years = Array(Set(items.map { Calendar.current.component(.year, from: $0.captureDate) })).sorted(by: >)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(years, id: \.self) { year in
                    Button(String(year)) {
                        if let item = items.first(where: { Calendar.current.component(.year, from: $0.captureDate) == year }) {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                proxy.scrollTo(item.id, anchor: .top)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    private func groupedByDate(_ items: [MediaItem], date keyPath: KeyPath<MediaItem, Date>, ascending: Bool, prefix: String? = nil) -> [(String, [MediaItem])] {
        Dictionary(grouping: items) { item in
            let label = Self.dayFormatter.string(from: item[keyPath: keyPath])
            return prefix.map { "\($0) \(label)" } ?? label
        }
        .map { title, values in
            let sortedValues = values.sorted {
                ascending ? $0[keyPath: keyPath] < $1[keyPath: keyPath] : $0[keyPath: keyPath] > $1[keyPath: keyPath]
            }
            return (title, sortedValues)
        }
        .sorted { lhs, rhs in
            guard let left = lhs.1.first?[keyPath: keyPath], let right = rhs.1.first?[keyPath: keyPath] else {
                return lhs.0 < rhs.0
            }
            return ascending ? left < right : left > right
        }
    }

    private func groupedByFilename(_ items: [MediaItem]) -> [(String, [MediaItem])] {
        Dictionary(grouping: items) { item in
            guard let first = item.filename.trimmingCharacters(in: .whitespacesAndNewlines).first else {
                return "#"
            }
            return first.isLetter ? String(first).uppercased() : "#"
        }
        .map { key, values in
            (key, values.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending })
        }
        .sorted { lhs, rhs in
            if lhs.0 == "#" { return false }
            if rhs.0 == "#" { return true }
            return lhs.0 < rhs.0
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private func open(_ item: MediaItem) {
        appState.clearMediaSelection()
        appState.selectedMediaItem = item
        appState.showingViewer = true
    }

    private func select(_ item: MediaItem) {
        isGridFocused = true
        let flags = NSApp.currentEvent?.modifierFlags ?? []

        if appState.isSelectionModeEnabled {
            appState.toggleMediaSelection(item)
        } else if flags.contains(.command) {
            appState.toggleMediaSelection(item)
        } else if flags.contains(.shift) {
            appState.extendMediaSelection(to: item, in: items)
        } else {
            appState.selectSingleMediaItem(item)
        }
    }

    private func batchItems(for item: MediaItem) -> [MediaItem] {
        appState.selectedMediaItemIDs.contains(item.id) ? appState.selectedOrCurrentVisibleItems() : [item]
    }

    private func prepareRename(for item: MediaItem) {
        if appState.selectedMediaItemIDs.contains(item.id) {
            appState.requestRenameSelectedMediaItems()
        } else {
            appState.selectSingleMediaItem(item)
            appState.requestRenameSelectedMediaItems()
        }
    }

    private func requestDelete(for item: MediaItem) {
        if appState.selectedMediaItemIDs.contains(item.id) {
            appState.requestDeleteSelectedMediaItems()
        } else {
            appState.requestDelete(item)
        }
    }
}

private struct BatchSelectionBar: View {
    @EnvironmentObject private var appState: AppState
    let selectedCount: Int
    let totalCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullActions
            compactActions
        }
        .buttonStyle(.bordered)
        .menuStyle(.button)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .frame(maxWidth: 860)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection quick actions")
    }

    private var fullActions: some View {
        HStack(spacing: 10) {
            selectionLabel

            Spacer(minLength: 12)

            if selectedCount < totalCount {
                selectAllButton
            }

            MediaFavoriteButton(items: selectedItems)
            AddToAlbumMenu(items: selectedItems)
            copyButton
            renameButton
            trashButton

            Divider().frame(height: 22)
            clearButton
        }
    }

    private var compactActions: some View {
        HStack(spacing: 8) {
            selectionLabel
            Spacer(minLength: 8)

            if selectedCount < totalCount {
                selectAllButton.labelStyle(.iconOnly)
            }

            MediaFavoriteButton(items: selectedItems)
                .labelStyle(.iconOnly)
            AddToAlbumMenu(items: selectedItems)
                .labelStyle(.iconOnly)
            copyButton.labelStyle(.iconOnly)
            renameButton.labelStyle(.iconOnly)
            trashButton.labelStyle(.iconOnly)

            Divider().frame(height: 22)
            clearButton
        }
    }

    private var selectedItems: [MediaItem] {
        appState.selectedOrCurrentVisibleItems()
    }

    private var selectionLabel: some View {
        Label("\(selectedCount) selected", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize()
    }

    private var selectAllButton: some View {
        Button {
            appState.selectAllVisibleItems()
        } label: {
            Label("Select All", systemImage: "checklist.checked")
        }
        .help("Select all visible media")
    }

    private var copyButton: some View {
        Button {
            appState.copySelectedMediaItems()
        } label: {
            Label("Copy Originals", systemImage: "doc.on.doc")
        }
        .help("Copy selected originals")
    }

    private var renameButton: some View {
        Button {
            appState.requestRenameSelectedMediaItems()
        } label: {
            Label("Rename Originals", systemImage: "pencil")
        }
        .help("Rename selected originals")
    }

    private var trashButton: some View {
        Button(role: .destructive) {
            appState.requestDeleteSelectedMediaItems()
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
        .help("Move selected originals to Trash")
    }

    private var clearButton: some View {
        Button {
            appState.clearMediaSelection()
        } label: {
            Label("Clear Selection", systemImage: "xmark.circle")
        }
        .labelStyle(.iconOnly)
        .help("Clear selection")
    }
}

private struct TimelineHeader: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let items: [MediaItem]
    let counts: CatalogueCounts?
    let showsQuickFilters: Bool
    let controlScope: TimelineControlScope
    let backAction: (() -> Void)?

    var body: some View {
        if controlScope != .none {
            controlledHeader
        } else {
            compactHeader
        }
    }

    private var controlledHeader: some View {
        CatalogueControlsHeader(
            title: title,
            systemImage: headerSystemImage,
            summary: summary,
            counts: resolvedCounts,
            filters: availableQuickFilters,
            selectedFilter: activeQuickFilter,
            filterCount: quickFilterCount(for:),
            selectedSort: activeSort,
            selectedYear: selectedYear,
            years: years,
            gridSize: $appState.gridSize,
            hasActiveControls: hasActiveTimelineControls,
            resetLabel: "Reset Filters and Sorting",
            backAction: backAction,
            onSelectFilter: { filter in
                Task { await setQuickFilter(filter) }
            },
            onSelectSort: { sort in
                Task { await setSort(sort) }
            },
            onSelectYear: { year in
                Task { await setYear(year) }
            },
            onReset: {
                Task { await resetControls() }
            },
            accessory: EmptyView()
        )
    }

    private var compactHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                titleBlock
                Spacer()
                metrics
            }

            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                metrics
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let backAction {
                    Button(action: backAction) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Back to Smart Albums")
                    .accessibilityLabel("Back to Smart Albums")
                }

                Image(systemName: showsQuickFilters ? "rectangle.stack.fill" : "photo.stack")
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.title2.weight(.semibold))
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            CatalogueHeaderMetric(systemImage: "photo", value: photoCount, label: "Photos")
            CatalogueHeaderMetric(systemImage: "film", value: videoCount, label: "Videos")
        }
    }

    private var photoCount: Int {
        counts?.photos ?? items.filter { $0.kind == .photo || $0.kind == .livePhoto }.count
    }

    private var videoCount: Int {
        counts?.videos ?? items.filter { $0.kind == .video }.count
    }

    private var resolvedCounts: CatalogueCounts {
        counts ?? items.reduce(into: CatalogueCounts.zero) { result, item in
            result.totalItems += 1
            if item.kind == .video {
                result.videos += 1
            } else {
                result.photos += 1
            }
            if item.coordinate == nil {
                result.missingLocationItems += 1
            } else {
                result.locatedItems += 1
            }
        }
    }

    private var headerSystemImage: String {
        switch controlScope {
        case .timeline: "rectangle.stack.fill"
        case .videos: "film.fill"
        case .recentlyAdded: "clock.fill"
        case .smartAlbums: "sparkles.rectangle.stack"
        case .search: "magnifyingglass"
        case .none: "photo.stack"
        }
    }

    private var availableQuickFilters: [TimelineQuickFilter] {
        switch controlScope {
        case .videos:
            return [.all, .withLocation, .withoutLocation]
        default:
            return TimelineQuickFilter.allCases
        }
    }

    private var hasActiveTimelineControls: Bool {
        switch controlScope {
        case .timeline:
            return appState.timelineQuickFilter != .all || appState.selectedTimelineYear != nil || appState.timelineSort != .captureNewest
        case .videos:
            return appState.videoQuickFilter != .all || appState.selectedVideoYear != nil || appState.videoSort != .captureNewest
        case .recentlyAdded:
            return appState.recentlyAddedQuickFilter != .all || appState.selectedRecentlyAddedYear != nil || appState.recentlyAddedSort != .recentlyAdded
        case .smartAlbums:
            return appState.smartAlbumQuickFilter != .all || appState.selectedSmartAlbumYear != nil || appState.smartAlbumSort != .captureNewest
        case .search:
            return !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || appState.searchQuickFilter != .all
                || appState.selectedSearchYear != nil
                || appState.searchSort != .captureNewest
        case .none:
            return false
        }
    }

    private var summary: String {
        let total = counts?.totalItems ?? items.count
        guard total > 0 else { return "No indexed media" }

        if showsQuickFilters {
            let yearText = selectedYear.map { " from \($0)" } ?? ""
            let filterText = activeQuickFilter == .all ? "" : " · \(activeQuickFilter.title)"
            return "\(total) indexed item\(total == 1 ? "" : "s")\(yearText)\(filterText) · \(activeSort.title)"
        }

        return "\(total) catalogue item\(total == 1 ? "" : "s")"
    }

    private var activeQuickFilter: TimelineQuickFilter {
        switch controlScope {
        case .timeline:
            return appState.timelineQuickFilter
        case .videos:
            return appState.videoQuickFilter
        case .recentlyAdded:
            return appState.recentlyAddedQuickFilter
        case .smartAlbums:
            return appState.smartAlbumQuickFilter
        case .search:
            return appState.searchQuickFilter
        case .none:
            return .all
        }
    }

    private var selectedYear: Int? {
        switch controlScope {
        case .timeline:
            return appState.selectedTimelineYear
        case .videos:
            return appState.selectedVideoYear
        case .recentlyAdded:
            return appState.selectedRecentlyAddedYear
        case .smartAlbums:
            return appState.selectedSmartAlbumYear
        case .search:
            return appState.selectedSearchYear
        case .none:
            return nil
        }
    }

    private var years: [Int] {
        switch controlScope {
        case .timeline:
            return appState.timelineYears
        case .videos:
            return appState.videoYears
        case .recentlyAdded:
            return appState.recentlyAddedYears
        case .smartAlbums:
            return appState.smartAlbumYears
        case .search:
            return appState.searchYears
        case .none:
            return []
        }
    }

    private var activeSort: TimelineSortOption {
        switch controlScope {
        case .timeline:
            return appState.timelineSort
        case .videos:
            return appState.videoSort
        case .recentlyAdded:
            return appState.recentlyAddedSort
        case .smartAlbums:
            return appState.smartAlbumSort
        case .search:
            return appState.searchSort
        case .none:
            return .captureNewest
        }
    }

    private func quickFilterCount(for filter: TimelineQuickFilter) -> Int {
        switch controlScope {
        case .timeline:
            return appState.quickFilterCount(for: filter)
        case .videos:
            return appState.videoQuickFilterCount(for: filter)
        case .recentlyAdded:
            return appState.recentlyAddedQuickFilterCount(for: filter)
        case .smartAlbums:
            return appState.smartAlbumQuickFilterCount(for: filter)
        case .search:
            return appState.searchQuickFilterCount(for: filter)
        case .none:
            return 0
        }
    }

    private func setQuickFilter(_ filter: TimelineQuickFilter) async {
        switch controlScope {
        case .timeline:
            await appState.setTimelineQuickFilter(filter)
        case .videos:
            await appState.setVideoQuickFilter(filter)
        case .recentlyAdded:
            await appState.setRecentlyAddedQuickFilter(filter)
        case .smartAlbums:
            await appState.setSmartAlbumQuickFilter(filter)
        case .search:
            appState.setSearchQuickFilter(filter)
        case .none:
            break
        }
    }

    private func setYear(_ year: Int?) async {
        switch controlScope {
        case .timeline:
            await appState.setTimelineYear(year)
        case .videos:
            await appState.setVideoYear(year)
        case .recentlyAdded:
            await appState.setRecentlyAddedYear(year)
        case .smartAlbums:
            await appState.setSmartAlbumYear(year)
        case .search:
            appState.setSearchYear(year)
        case .none:
            break
        }
    }

    private func setSort(_ sort: TimelineSortOption) async {
        switch controlScope {
        case .timeline:
            await appState.setTimelineSort(sort)
        case .videos:
            await appState.setVideoSort(sort)
        case .recentlyAdded:
            await appState.setRecentlyAddedSort(sort)
        case .smartAlbums:
            await appState.setSmartAlbumSort(sort)
        case .search:
            appState.setSearchSort(sort)
        case .none:
            break
        }
    }

    private func resetControls() async {
        switch controlScope {
        case .timeline:
            await appState.resetTimelineControls()
        case .videos:
            await appState.resetVideoControls()
        case .recentlyAdded:
            await appState.resetRecentlyAddedControls()
        case .smartAlbums:
            await appState.resetSmartAlbumControls()
        case .search:
            appState.resetSearchControls()
        case .none:
            break
        }
    }
}

private struct TimelineSectionHeader: View {
    let title: String
    let count: Int
    let horizontalPadding: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.45), in: Capsule())
            Spacer()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct PhotoGridMetrics {
    let spacing: CGFloat = 6
    let horizontalPadding: CGFloat = 18
    let itemWidth: CGFloat
    let columns: [GridItem]

    init(width: CGFloat, targetItemWidth: CGFloat) {
        let availableWidth = max(1, width - horizontalPadding * 2)
        let preferredWidth = max(72, targetItemWidth)
        let count = max(1, Int((availableWidth + spacing) / (preferredWidth + spacing)))
        let exactWidth = floor((availableWidth - CGFloat(count - 1) * spacing) / CGFloat(count))
        itemWidth = max(64, exactWidth)
        columns = Array(
            repeating: GridItem(.fixed(itemWidth), spacing: spacing, alignment: .top),
            count: count
        )
    }
}
