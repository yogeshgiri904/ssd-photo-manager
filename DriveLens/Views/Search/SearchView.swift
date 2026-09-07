import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(resultCount: appState.searchResultCount)
                .environmentObject(appState)

            Divider()

            TimelineView(
                items: appState.searchItems,
                title: "Search",
                counts: appState.countsForCurrentSearchFilter(),
                showsHeader: false,
                showsQuickFilters: true,
                controlScope: .search
            )
        }
        .navigationTitle("Search Catalogue")
        .task(id: appState.searchText) {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            appState.refreshSearch()
        }
    }
}

private struct SearchHeader: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFocused: Bool
    let resultCount: Int

    private var hasSearchCriteria: Bool {
        !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || appState.searchQuickFilter != .all
            || appState.selectedSearchYear != nil
            || appState.searchSort != .captureNewest
    }

    var body: some View {
        CatalogueControlsHeader(
            title: "Search Catalogue",
            systemImage: "magnifyingglass",
            summary: summary,
            counts: appState.countsForCurrentSearchFilter(),
            filters: TimelineQuickFilter.allCases,
            selectedFilter: appState.searchQuickFilter,
            filterCount: appState.searchQuickFilterCount(for:),
            selectedSort: appState.searchSort,
            selectedYear: appState.selectedSearchYear,
            years: appState.searchYears,
            gridSize: $appState.gridSize,
            hasActiveControls: hasSearchCriteria,
            resetLabel: "Clear Search and Filters",
            backAction: nil,
            onSelectFilter: appState.setSearchQuickFilter,
            onSelectSort: appState.setSearchSort,
            onSelectYear: appState.setSearchYear,
            onReset: {
                appState.resetSearchControls()
                isSearchFocused = true
            },
            accessory: searchField
        )
        .onAppear {
            if appState.searchText.isEmpty {
                isSearchFocused = true
            }
        }
    }

    private var summary: String {
        guard resultCount > 0 else {
            return hasSearchCriteria ? "No matching catalogue items" : "Search your catalogue"
        }

        let yearText = appState.selectedSearchYear.map { " from \($0)" } ?? ""
        let filterText = appState.searchQuickFilter == .all ? "" : " · \(appState.searchQuickFilter.title)"
        return "\(resultCount) result\(resultCount == 1 ? "" : "s")\(yearText)\(filterText) · \(appState.searchSort.title)"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            TextField("Search filenames, dates, places, cameras, captions, or keywords", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    appState.refreshSearch()
                }
                .accessibilityLabel("Search catalogue")
                .accessibilityHint("Search by filename, date, place, camera, caption, or keyword")

            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                    isSearchFocused = true
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search text")
                .accessibilityLabel("Clear search text")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSearchFocused ? Color.accentColor.opacity(0.72) : Color.primary.opacity(0.10),
                    lineWidth: isSearchFocused ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(isSearchFocused ? 0.08 : 0.03), radius: 3, y: 1)
    }
}
