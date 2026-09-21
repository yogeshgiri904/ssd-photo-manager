import SwiftUI

struct MediaQuickFilterBar: View {
    @FocusState private var focusedFilter: TimelineQuickFilter?
    var filters = TimelineQuickFilter.allCases
    let selectedFilter: TimelineQuickFilter
    let count: (TimelineQuickFilter) -> Int
    let onSelect: (TimelineQuickFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(filters) { filter in
                    MediaQuickFilterPill(
                        filter: filter,
                        count: count(filter),
                        isSelected: selectedFilter == filter,
                        isFocused: focusedFilter == filter,
                        action: { onSelect(filter) }
                    )
                    .focused($focusedFilter, equals: filter)
                }
            }
            .padding(.vertical, 3)

        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media filters")
    }
}

struct CatalogueControlsHeader<Accessory: View>: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let systemImage: String
    let summary: String
    let counts: CatalogueCounts
    var filters = TimelineQuickFilter.allCases
    let selectedFilter: TimelineQuickFilter
    let filterCount: (TimelineQuickFilter) -> Int
    let selectedSort: TimelineSortOption
    let selectedYear: Int?
    let years: [Int]
    @Binding var gridSize: Double
    let hasActiveControls: Bool
    let resetLabel: String
    let backAction: (() -> Void)?
    let onSelectFilter: (TimelineQuickFilter) -> Void
    let onSelectSort: (TimelineSortOption) -> Void
    let onSelectYear: (Int?) -> Void
    let onReset: () -> Void
    let accessory: Accessory
    var body: some View {
        VStack(alignment: .leading, spacing: LensHeaderMetrics.sectionGap) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    titleBlock.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    metrics
                    selectionButton
                }
                HStack(spacing: 12) {
                    titleBlock
                    Spacer(minLength: 4)
                    selectionButton
                }
            }
            accessory
            controls
        }
        .padding(.horizontal, LensHeaderMetrics.inset)
        .padding(.vertical, LensHeaderMetrics.verticalInset)
        .background(LensTheme.canvas)
        .accessibilityIdentifier("catalogue-browsing-header")
    }

    private var titleBlock: some View {
        HStack(spacing: 10) {
            if let backAction {
                Button(action: backAction) { Label("Back", systemImage: "chevron.left") }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.small)
                    .help("Back").accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LensHeaderMetrics.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(LensHeaderMetrics.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).help(summary)
            }
        }
    }

    private var selectionButton: some View {
        Button { appState.toggleSelectionMode() } label: {
            Label(appState.isSelectionModeEnabled ? "Done" : "Select",
                  systemImage: appState.isSelectionModeEnabled ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .disabled(counts.totalItems == 0 && !appState.isSelectionModeEnabled)
        .tint(appState.isSelectionModeEnabled ? .accentColor : .primary)
        .help(appState.isSelectionModeEnabled ? "Finish selecting media" : "Select multiple photos and videos")
        .accessibilityValue(appState.isSelectionModeEnabled ? "Selection mode on" : "Selection mode off")
        .accessibilityIdentifier("header-selection-mode")
    }

    private var metrics: some View {
        Group {
            if !appState.selectedMediaItemIDs.isEmpty {
                Text("\(appState.selectedMediaItemIDs.count.formatted()) selected")
                    .foregroundStyle(Color.accentColor)
                    .font(LensHeaderMetrics.subtitle.weight(.medium))
            } else {
                HStack(spacing: 12) {
                    CatalogueHeaderMetric(systemImage: "photo", value: counts.photos, label: "Photos")
                    CatalogueHeaderMetric(systemImage: "film", value: counts.videos, label: "Videos")
                }
            }
        }
        .fixedSize()
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                quickFilters.frame(minWidth: 470, maxWidth: .infinity)
                Divider().frame(height: 22)
                optionsRow(compact: false).fixedSize()
            }
            VStack(alignment: .leading, spacing: 9) {
                quickFilters
                Divider()
                ViewThatFits(in: .horizontal) {
                    optionsRow(compact: false)
                    optionsRow(compact: true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            sortMenu(compact: true)
                            yearMenu
                            Spacer(minLength: 0)
                            resetButton
                        }
                        HStack {
                            Text("Thumbnail size").font(LensHeaderMetrics.subtitle).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            gridSizeControl
                        }
                    }
                }
            }
        }
        .controlSize(.small)
    }

    private var quickFilters: some View {
        MediaQuickFilterBar(filters: filters, selectedFilter: selectedFilter,
                            count: filterCount, onSelect: onSelectFilter)
    }

    private func optionsRow(compact: Bool) -> some View {
        HStack(spacing: 8) {
            sortMenu(compact: compact)
            yearMenu
            resetButton
            Spacer(minLength: 12)
            gridSizeControl
        }
    }

    @ViewBuilder private var resetButton: some View {
        if hasActiveControls {
            Button(action: onReset) { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.bordered)
                .help(resetLabel)
                .accessibilityLabel(resetLabel)
                .accessibilityIdentifier("header-reset-controls")
        }
    }

    private var sortOptions: some View {
        ForEach(TimelineSortOption.allCases) { sort in
            Button { onSelectSort(sort) } label: {
                Label(sort.title, systemImage: sort == selectedSort ? "checkmark" : sort.systemImage)
            }
        }
    }

    private var yearOptions: some View {
        Group {
            Button { onSelectYear(nil) } label: {
                Label("All Years", systemImage: selectedYear == nil ? "checkmark" : "calendar")
            }
            ForEach(years, id: \.self) { year in
                Button { onSelectYear(year) } label: {
                    Label(String(year), systemImage: selectedYear == year ? "checkmark" : "calendar")
                }
            }
        }
    }

    private func sortMenu(compact: Bool) -> some View {
        Menu { sortOptions } label: {
            Label(compact ? "Sort" : shortSortTitle, systemImage: "arrow.up.arrow.down")
                .font(LensHeaderMetrics.control)
                .fixedSize()
        }
        .menuStyle(.button)
        .help("Sort: " + selectedSort.title)
        .accessibilityLabel("Sort media")
        .accessibilityValue(selectedSort.title)
        .accessibilityIdentifier("header-sort")
    }

    private var shortSortTitle: String {
        switch selectedSort {
        case .captureNewest: "Newest"
        case .captureOldest: "Oldest"
        case .recentlyAdded: "Added"
        case .fileName: "Name"
        case .largestFile: "Size"
        }
    }

    private var yearMenu: some View {
        Menu { yearOptions } label: {
            Label(selectedYear.map(String.init) ?? "All years", systemImage: "calendar")
                .font(LensHeaderMetrics.control).fixedSize()
        }
        .menuStyle(.button)
        .disabled(years.isEmpty)
        .help("Filter by capture year")
        .accessibilityLabel("Capture year")
        .accessibilityValue(selectedYear.map(String.init) ?? "All years")
        .accessibilityIdentifier("header-year")
    }

    private var gridSizeControl: some View {
        HStack(spacing: 5) {
            Button { gridSize = max(92, gridSize - 12) } label: {
                Image(systemName: "square.grid.3x3").font(.system(size: 11)).frame(width: 18, height: 22)
            }
            .disabled(gridSize <= 92)
            .help("Smaller thumbnails · ⌘−")
            .accessibilityLabel("Smaller thumbnails")
            Slider(value: $gridSize, in: 92...220) { Text("Thumbnail size") }
                .labelsHidden()
                .frame(width: LensHeaderMetrics.sliderWidth)
                .accessibilityLabel("Thumbnail size")
                .accessibilityValue("\(Int(gridSize)) points")
                .accessibilityIdentifier("header-thumbnail-size")
            Button { gridSize = min(220, gridSize + 12) } label: {
                Image(systemName: "square.grid.2x2").font(.system(size: 13)).frame(width: 18, height: 22)
            }
            .disabled(gridSize >= 220)
            .help("Larger thumbnails · ⌘+")
            .accessibilityLabel("Larger thumbnails")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help("Thumbnail size · ⌘+ / ⌘−")
    }

}

struct CatalogueMenuLabel: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(minHeight: 22, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("\(title): \(value)")
    }
}

struct CatalogueHeaderMetric: View {
    let systemImage: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label.lowercased())")
    }
}

private struct MediaQuickFilterPill: View {
    let filter: TimelineQuickFilter
    let count: Int
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.caption.weight(.semibold))
                Text(filter.title)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(isSelected ? LensTheme.selectedFill : (hovered ? LensTheme.hoverFill : Color.clear), in: RoundedRectangle(cornerRadius: LensTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LensTheme.controlRadius)
                    .stroke(
                        isFocused ? Color.accentColor : (contrast == .increased ? Color.primary.opacity(0.65) : Color.clear),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: LensTheme.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Show \(filter.title.lowercased()) media")
        .accessibilityLabel("\(filter.title), \(count) item\(count == 1 ? "" : "s")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
