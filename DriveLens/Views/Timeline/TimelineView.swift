import AppKit
import SwiftUI

enum TimelineControlScope {
    case none
    case timeline
    case recentlyAdded
    case smartAlbums
}

struct TimelineView: View {
    @EnvironmentObject private var appState: AppState
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
        case .recentlyAdded:
            return appState.recentlyAddedSort
        case .smartAlbums:
            return appState.smartAlbumSort
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .focusable()
                .focused($isGridFocused)
                .focusEffectDisabled()
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
            if title == "Search" {
                Button {
                    appState.searchText = ""
                    appState.activeFilters = SearchFilters()
                    appState.refreshSearchResultCount()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
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
        if title == "Search" { return "No matching media" }
        if title == "Videos" { return "No videos in the catalogue" }
        return "No media in the catalogue"
    }

    private var emptyStateMessage: String {
        if title == "Search" {
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

    private func jumpStrip(proxy: ScrollViewProxy) -> some View {
        let years = Array(Set(items.map { Calendar.current.component(.year, from: $0.captureDate) })).sorted(by: >)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(years, id: \.self) { year in
                    Button(String(year)) {
                        if let item = items.first(where: { Calendar.current.component(.year, from: $0.captureDate) == year }) {
                            withAnimation(.snappy) {
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
        HStack(spacing: 10) {
            Label(selectionText, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if selectedCount < totalCount {
                Button {
                    appState.selectAllVisibleItems()
                } label: {
                    Label("Select All", systemImage: "checklist.checked")
                }
                .help("Select all visible media")
            }

            Button {
                appState.copySelectedMediaItems()
            } label: {
                Label("Copy Originals", systemImage: "doc.on.doc")
            }
            .help("Copy selected originals")

            Button {
                appState.requestRenameSelectedMediaItems()
            } label: {
                Label("Rename Originals", systemImage: "pencil")
            }
            .help("Rename selected originals")

            Button(role: .destructive) {
                appState.requestDeleteSelectedMediaItems()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .help("Move selected originals to Trash")

            Divider()
                .frame(height: 22)

            Button {
                appState.clearMediaSelection()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .labelStyle(.iconOnly)
            .help("Clear selection")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .frame(maxWidth: 680)
        .accessibilityElement(children: .contain)
    }

    private var selectionText: String {
        "\(selectedCount) selected"
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
            mainTimelineHeader
        } else {
            compactHeader
        }
    }

    private var mainTimelineHeader: some View {
        VStack(alignment: .leading, spacing: 11) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    titleBlock
                    Spacer(minLength: 16)
                    metrics
                }

                VStack(alignment: .leading, spacing: 10) {
                    titleBlock
                    metrics
                }
            }

            filterAndSortRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var filterAndSortRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                quickFilters
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 24)

                compactViewControls
            }

            VStack(alignment: .leading, spacing: 7) {
                quickFilters
                compactViewControls
            }
        }
        .controlSize(.small)
        .padding(5)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var compactViewControls: some View {
        HStack(spacing: 7) {
            sortMenu
            yearMenu
            gridSizeControl

            if hasActiveTimelineControls {
                Button {
                    Task { await resetControls() }
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .help("Reset filters and sorting")
                .accessibilityLabel("Reset filters and sorting")
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            HeaderMetric(systemImage: "photo", value: "\(photoCount)", label: "Photos")
            HeaderMetric(systemImage: "film", value: "\(videoCount)", label: "Videos")
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TimelineSortOption.allCases) { sort in
                Button {
                    Task { await setSort(sort) }
                } label: {
                    Label(sort.title, systemImage: sort == activeSort ? "checkmark" : sort.systemImage)
                }
            }
        } label: {
            TimelineMenuLabel(
                title: "Sort",
                value: activeSort.title,
                systemImage: activeSort.systemImage
            )
            .frame(width: 128, alignment: .leading)
        }
        .menuStyle(.button)
        .help("Sort media")
    }

    private var yearMenu: some View {
        Menu {
            Button {
                Task { await setYear(nil) }
            } label: {
                Label("All Years", systemImage: selectedYear == nil ? "checkmark" : "calendar")
            }

            Divider()

            ForEach(years, id: \.self) { year in
                Button {
                    Task { await setYear(year) }
                } label: {
                    Label(String(year), systemImage: selectedYear == year ? "checkmark" : "calendar")
                }
            }
        } label: {
            TimelineMenuLabel(title: "Year", value: selectedYearTitle, systemImage: "calendar")
                .frame(width: 92, alignment: .leading)
        }
        .menuStyle(.button)
        .disabled(years.isEmpty)
        .help("Filter by capture year")
    }

    private var gridSizeControl: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
            Slider(value: $appState.gridSize, in: 92...220)
                .frame(width: 78)
            Image(systemName: "square.grid.3x3")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .help("Adjust thumbnail size")
    }

    private var quickFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .padding(.leading, 5)

                ForEach(TimelineQuickFilter.allCases) { filter in
                    QuickFilterPill(
                        filter: filter,
                        count: quickFilterCount(for: filter),
                        isSelected: activeQuickFilter == filter
                    ) {
                        Task {
                            await setQuickFilter(filter)
                        }
                    }
                }
            }
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityLabel("Quick filters")
    }

    private var photoCount: Int {
        counts?.photos ?? items.filter { $0.kind == .photo || $0.kind == .livePhoto }.count
    }

    private var videoCount: Int {
        counts?.videos ?? items.filter { $0.kind == .video }.count
    }

    private var selectedYearTitle: String {
        selectedYear.map(String.init) ?? "All Years"
    }

    private var hasActiveTimelineControls: Bool {
        switch controlScope {
        case .timeline:
            return appState.timelineQuickFilter != .all || appState.selectedTimelineYear != nil || appState.timelineSort != .captureNewest
        case .recentlyAdded:
            return appState.recentlyAddedQuickFilter != .all || appState.selectedRecentlyAddedYear != nil || appState.recentlyAddedSort != .recentlyAdded
        case .smartAlbums:
            return appState.smartAlbumQuickFilter != .all || appState.selectedSmartAlbumYear != nil || appState.smartAlbumSort != .captureNewest
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
        case .recentlyAdded:
            return appState.recentlyAddedQuickFilter
        case .smartAlbums:
            return appState.smartAlbumQuickFilter
        case .none:
            return .all
        }
    }

    private var selectedYear: Int? {
        switch controlScope {
        case .timeline:
            return appState.selectedTimelineYear
        case .recentlyAdded:
            return appState.selectedRecentlyAddedYear
        case .smartAlbums:
            return appState.selectedSmartAlbumYear
        case .none:
            return nil
        }
    }

    private var years: [Int] {
        switch controlScope {
        case .timeline:
            return appState.timelineYears
        case .recentlyAdded:
            return appState.recentlyAddedYears
        case .smartAlbums:
            return appState.smartAlbumYears
        case .none:
            return []
        }
    }

    private var activeSort: TimelineSortOption {
        switch controlScope {
        case .timeline:
            return appState.timelineSort
        case .recentlyAdded:
            return appState.recentlyAddedSort
        case .smartAlbums:
            return appState.smartAlbumSort
        case .none:
            return .captureNewest
        }
    }

    private func quickFilterCount(for filter: TimelineQuickFilter) -> Int {
        switch controlScope {
        case .timeline:
            return appState.quickFilterCount(for: filter)
        case .recentlyAdded:
            return appState.recentlyAddedQuickFilterCount(for: filter)
        case .smartAlbums:
            return appState.smartAlbumQuickFilterCount(for: filter)
        case .none:
            return 0
        }
    }

    private func setQuickFilter(_ filter: TimelineQuickFilter) async {
        switch controlScope {
        case .timeline:
            await appState.setTimelineQuickFilter(filter)
        case .recentlyAdded:
            await appState.setRecentlyAddedQuickFilter(filter)
        case .smartAlbums:
            await appState.setSmartAlbumQuickFilter(filter)
        case .none:
            break
        }
    }

    private func setYear(_ year: Int?) async {
        switch controlScope {
        case .timeline:
            await appState.setTimelineYear(year)
        case .recentlyAdded:
            await appState.setRecentlyAddedYear(year)
        case .smartAlbums:
            await appState.setSmartAlbumYear(year)
        case .none:
            break
        }
    }

    private func setSort(_ sort: TimelineSortOption) async {
        switch controlScope {
        case .timeline:
            await appState.setTimelineSort(sort)
        case .recentlyAdded:
            await appState.setRecentlyAddedSort(sort)
        case .smartAlbums:
            await appState.setSmartAlbumSort(sort)
        case .none:
            break
        }
    }

    private func resetControls() async {
        switch controlScope {
        case .timeline:
            await appState.resetTimelineControls()
        case .recentlyAdded:
            await appState.resetRecentlyAddedControls()
        case .smartAlbums:
            await appState.resetSmartAlbumControls()
        case .none:
            break
        }
    }
}

private struct TimelineMenuLabel: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .frame(minWidth: 0, alignment: .leading)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct HeaderMetric: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
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
    }
}

private struct QuickFilterPill: View {
    let filter: TimelineQuickFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.caption.weight(.semibold))
                Text(filter.title)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            }
            .font(.caption2.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Show \(filter.title)")
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
