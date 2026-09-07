import SwiftUI

struct MediaQuickFilterBar: View {
    @FocusState private var focusedFilter: TimelineQuickFilter?
    var filters = TimelineQuickFilter.allCases
    let selectedFilter: TimelineQuickFilter
    let count: (TimelineQuickFilter) -> Int
    let onSelect: (TimelineQuickFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .padding(.leading, 5)

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
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media filters")
    }
}

struct CatalogueControlsHeader<Accessory: View>: View {
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

            accessory
            controls
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
                    .help("Back")
                    .accessibilityLabel("Back")
                }

                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

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
            CatalogueHeaderMetric(systemImage: "photo", value: counts.photos, label: "Photos")
            CatalogueHeaderMetric(systemImage: "film", value: counts.videos, label: "Videos")
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                quickFilters
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 24)

                compactControls
            }

            VStack(alignment: .leading, spacing: 7) {
                quickFilters
                compactControls
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

    private var quickFilters: some View {
        MediaQuickFilterBar(
            filters: filters,
            selectedFilter: selectedFilter,
            count: filterCount,
            onSelect: onSelectFilter
        )
    }

    private var compactControls: some View {
        HStack(spacing: 7) {
            sortMenu
            yearMenu
            gridSizeControl

            if hasActiveControls {
                Button(action: onReset) {
                    Label(resetLabel, systemImage: "arrow.counterclockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .help(resetLabel)
                .accessibilityLabel(resetLabel)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TimelineSortOption.allCases) { sort in
                Button {
                    onSelectSort(sort)
                } label: {
                    Label(sort.title, systemImage: sort == selectedSort ? "checkmark" : sort.systemImage)
                }
            }
        } label: {
            CatalogueMenuLabel(
                title: "Sort",
                value: selectedSort.title,
                systemImage: selectedSort.systemImage
            )
            .frame(minWidth: 136, alignment: .leading)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("Sort media")
    }

    private var yearMenu: some View {
        Menu {
            Button {
                onSelectYear(nil)
            } label: {
                Label("All Years", systemImage: selectedYear == nil ? "checkmark" : "calendar")
            }

            Divider()

            ForEach(years, id: \.self) { year in
                Button {
                    onSelectYear(year)
                } label: {
                    Label(String(year), systemImage: selectedYear == year ? "checkmark" : "calendar")
                }
            }
        } label: {
            CatalogueMenuLabel(
                title: "Year",
                value: selectedYear.map(String.init) ?? "All Years",
                systemImage: "calendar"
            )
            .frame(minWidth: 104, alignment: .leading)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .disabled(years.isEmpty)
        .help("Filter by capture year")
    }

    private var gridSizeControl: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.3x3")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(value: $gridSize, in: 92...220)
                .frame(width: 78)
                .accessibilityLabel("Thumbnail size")
                .accessibilityValue("\(Int(gridSize)) points")

            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
}

struct CatalogueMenuLabel: View {
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
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.caption.weight(.semibold))
                Text(filter.title)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        isFocused ? (isSelected ? Color.white.opacity(0.92) : Color.accentColor) : (isSelected ? Color.clear : Color.primary.opacity(0.10)),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show \(filter.title.lowercased()) media")
        .accessibilityLabel("\(filter.title), \(count) item\(count == 1 ? "" : "s")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
