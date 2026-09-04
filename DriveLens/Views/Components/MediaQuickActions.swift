import SwiftUI

struct MediaFavoriteButton: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]

    var body: some View {
        Button {
            Task { await appState.setFavorite(!allItemsAreFavorites, for: items) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(items.isEmpty)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint("Updates the DriveLens catalogue. Original photos and videos are not changed.")
    }

    private var allItemsAreFavorites: Bool {
        !items.isEmpty && items.allSatisfy(appState.favoriteState)
    }

    private var title: String {
        allItemsAreFavorites ? "Remove from Favorites" : "Mark as Favorite"
    }

    private var systemImage: String {
        allItemsAreFavorites ? "heart.slash" : "heart"
    }
}

struct AddToAlbumMenu: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]
    var allowsCreatingAlbum = true

    @State private var showingNewAlbumSheet = false

    var body: some View {
        Menu {
            if appState.customAlbums.isEmpty {
                Button("No Custom Albums") {}
                    .disabled(true)
            } else {
                Section("Custom Albums") {
                    ForEach(appState.customAlbums) { album in
                        Button {
                            add(to: album.name)
                        } label: {
                            Label(album.name, systemImage: "rectangle.stack")
                        }
                    }
                }
            }

            Divider()

            if allowsCreatingAlbum {
                Button {
                    showingNewAlbumSheet = true
                } label: {
                    Label("New Album…", systemImage: "plus")
                }
            } else {
                Button {
                    appState.select(.smartAlbums)
                } label: {
                    Label("Manage Albums…", systemImage: "rectangle.stack")
                }
            }
        } label: {
            Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
        }
        .disabled(items.isEmpty)
        .help("Add selected media to an album")
        .accessibilityLabel("Add to Album")
        .accessibilityHint("Choose an existing custom album or create a new one.")
        .sheet(isPresented: $showingNewAlbumSheet) {
            NewAlbumForMediaSheet(items: items)
                .environmentObject(appState)
                .frame(width: 440)
        }
    }

    private func add(to albumName: String) {
        Task { await appState.addToCustomAlbum(named: albumName, items: items) }
    }
}

private struct NewAlbumForMediaSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let items: [MediaItem]

    @State private var albumName = ""
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("New Custom Album")
                        .font(.title3.weight(.semibold))
                    Text("Create an album and add \(selectionText).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Album Name")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(albumName.count)/80")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(albumName.count > 80 ? Color.red : Color.secondary)
                        .accessibilityLabel("\(albumName.count) of 80 characters")
                }

                TextField("Enter album name", text: $albumName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(createAndAdd)
                    .accessibilityLabel("Album name")
            }

            Label(
                "DriveLens stores album membership in the catalogue. Original photos and videos are not changed.",
                systemImage: "checkmark.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: createAndAdd) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Creating album")
                    } else {
                        Text("Create and Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .onAppear { isNameFocused = true }
        .accessibilityElement(children: .contain)
    }

    private var normalizedName: String {
        albumName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving && !items.isEmpty && !normalizedName.isEmpty && normalizedName.count <= 80
    }

    private var selectionText: String {
        items.count == 1 ? "the selected item" : "\(items.count) selected items"
    }

    private func createAndAdd() {
        guard canSave else { return }
        if appState.customAlbums.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }) {
            appState.userMessage = "An album named “\(normalizedName)” already exists. Choose it from Add to Album."
            isNameFocused = true
            return
        }

        isSaving = true
        Task {
            if await appState.addToCustomAlbum(named: normalizedName, items: items) {
                dismiss()
            } else {
                isSaving = false
                isNameFocused = true
            }
        }
    }
}
