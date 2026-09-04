import SwiftUI

@main
struct DriveLensApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await appState.restoreAccess()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Folders to Catalogue...") {
                    Task { await appState.addFoldersToCurrentCatalogue() }
                }
                .disabled(!appState.canAddFoldersToCatalogue)

                Button("Update Catalogue") {
                    appState.requestCatalogueUpdate()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!appState.canScan)

                Button("Update Folders...") {
                    Task { await appState.chooseFoldersAndUpdateCatalogue() }
                }
                .disabled(!appState.canScan)

                Button("Repair Missing Files...") {
                    Task { await appState.openMissingFileRepair() }
                }
                .disabled(!appState.canRepairMissingFiles)

                Divider()

                Button("Choose Catalogue...") {
                    appState.requestMediaFolderReset()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Navigate") {
                Button("Timeline") { appState.select(.timeline) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Places") { appState.select(.places) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Folders") { appState.select(.folders) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Search") { appState.select(.search) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Videos") { appState.select(.videos) }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Recently Added") { appState.select(.recentlyAdded) }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Smart Albums") { appState.select(.smartAlbums) }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Duplicates") { appState.select(.duplicates) }
                    .keyboardShortcut("8", modifiers: [.command])
                Button("Storage & Privacy") { appState.select(.appInfo) }
                    .keyboardShortcut("9", modifiers: [.command])

                Divider()

                Button(appState.showingInspector ? "Hide Inspector" : "Show Inspector") {
                    appState.showingInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Larger Thumbnails") {
                    appState.adjustGridSize(by: 12)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Smaller Thumbnails") {
                    appState.adjustGridSize(by: -12)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }

            CommandMenu("Media") {
                Button("Open in Viewer") {
                    if let item = appState.selectedMediaItem {
                        appState.viewInViewer(item)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(appState.selectedMediaItem == nil)

                Divider()

                Button("Select All Visible Media") {
                    appState.selectAllVisibleItems()
                }
                .keyboardShortcut("a", modifiers: [.command])

                Button("Clear Selection") {
                    appState.clearMediaSelection()
                }
                .disabled(appState.selectedMediaItemIDs.isEmpty)

                Divider()

                Button(favoriteCommandTitle) {
                    Task {
                        await appState.setFavorite(
                            !selectedItemsAreFavorites,
                            for: appState.selectedOrCurrentVisibleItems()
                        )
                    }
                }
                .disabled(!appState.hasSelectedOrCurrentMediaItems)

                Menu("Add to Album") {
                    if appState.customAlbums.isEmpty {
                        Button("No Custom Albums") {}
                            .disabled(true)
                    } else {
                        ForEach(appState.customAlbums) { album in
                            Button(album.name) {
                                Task {
                                    await appState.addToCustomAlbum(
                                        named: album.name,
                                        items: appState.selectedOrCurrentVisibleItems()
                                    )
                                }
                            }
                            .disabled(!appState.hasSelectedOrCurrentMediaItems)
                        }
                    }

                    Divider()

                    Button("Manage Albums…") {
                        appState.select(.smartAlbums)
                    }
                }

                Divider()

                Button("Find Duplicates") {
                    appState.select(.duplicates)
                    Task { await appState.findDuplicates() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(appState.isFindingDuplicates || !appState.canScan)

                Button("Move Extra Duplicate Copies to Trash...") {
                    appState.select(.duplicates)
                    appState.mergeAllDuplicateGroups()
                }
                .disabled(appState.duplicateGroups.isEmpty || appState.isFindingDuplicates)

                Divider()

                Button("Copy Selected Originals") {
                    appState.copySelectedMediaItems()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!appState.hasSelectedOrCurrentMediaItems)

                Button("Rename Selected Originals") {
                    appState.requestRenameSelectedMediaItems()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!appState.hasSelectedOrCurrentMediaItems)

                Button("Move to Trash...") {
                    appState.requestDeleteSelectedMediaItems()
                }
                .disabled(!appState.hasSelectedOrCurrentMediaItems)
            }

            CommandMenu("Timeline") {
                Button("Newest Capture First") {
                    Task { await appState.setTimelineSort(.captureNewest) }
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Oldest Capture First") {
                    Task { await appState.setTimelineSort(.captureOldest) }
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Recently Added First") {
                    Task { await appState.setTimelineSort(.recentlyAdded) }
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("File Name") {
                    Task { await appState.setTimelineSort(.fileName) }
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button("Largest Files") {
                    Task { await appState.setTimelineSort(.largestFile) }
                }
                .keyboardShortcut("5", modifiers: [.command, .option])
            }
        }
    }

    private var selectedItemsAreFavorites: Bool {
        let items = appState.selectedOrCurrentVisibleItems()
        return !items.isEmpty && items.allSatisfy(appState.favoriteState)
    }

    private var favoriteCommandTitle: String {
        selectedItemsAreFavorites ? "Remove from Favorites" : "Mark as Favorite"
    }
}
