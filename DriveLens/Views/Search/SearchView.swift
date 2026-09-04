import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(resultCount: appState.searchResultCount)
                .environmentObject(appState)

            Divider()

            TimelineView(items: appState.searchItems, title: "Search", showsHeader: false)
        }
        .navigationTitle("Search")
        .task {
            appState.refreshSearchResultCount()
        }
        .onChange(of: appState.searchText) { _, _ in
            appState.refreshSearchResultCount()
        }
        .onChange(of: appState.activeFilters) { _, _ in
            appState.refreshSearchResultCount()
        }
    }
}

private struct SearchHeader: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFocused: Bool
    let resultCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("Search", systemImage: "magnifyingglass")
                    .font(.title2.weight(.semibold))

                Spacer()

                Label("\(resultCount)", systemImage: "photo.stack")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("\(resultCount) search result\(resultCount == 1 ? "" : "s")")
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search filenames, dates, places, cameras, keywords", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .accessibilityLabel("Search catalogue")
                if !appState.searchText.isEmpty {
                    Button {
                        appState.searchText = ""
                    } label: {
                        Label("Clear Search", systemImage: "xmark.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear Search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSearchFocused ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.08), lineWidth: isSearchFocused ? 2 : 1)
            }

            HStack(spacing: 8) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                SearchFilterToggle(title: "Photos", systemImage: "photo", isOn: $appState.activeFilters.photosOnly)
                SearchFilterToggle(title: "Videos", systemImage: "film", isOn: $appState.activeFilters.videosOnly)
                Spacer()
                Button {
                    appState.searchText = ""
                    appState.activeFilters = SearchFilters()
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
                .disabled(appState.searchText.isEmpty && appState.activeFilters == SearchFilters())
                .help("Reset search and filters")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isSearchFocused = true
        }
    }

}

private struct SearchFilterToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .help(title)
        .accessibilityLabel("Show \(title.lowercased())")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
