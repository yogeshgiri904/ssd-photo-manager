import SwiftUI

struct SmartAlbumsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let album = appState.selectedSmartAlbum {
                albumDetail(album)
            } else {
                overview
            }
        }
        .navigationTitle("Smart Albums")
        .task {
            await appState.refreshSmartAlbums()
        }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            SmartAlbumsHeader(
                title: "Smart Albums",
                subtitle: "Auto-created groups from local catalogue metadata",
                count: appState.smartAlbums.filter { !$0.isPlaceholder }.count,
                action: {
                    Task { await appState.refreshSmartAlbums() }
                }
            )

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(appState.smartAlbums) { album in
                        SmartAlbumCard(album: album) {
                            Task { await appState.openSmartAlbum(album) }
                        }
                    }
                }
                .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func albumDetail(_ album: SmartAlbum) -> some View {
        VStack(spacing: 0) {
            if album.isPlaceholder {
                SmartAlbumDetailHeader(album: album) {
                    appState.closeSmartAlbum()
                }
                Divider()
                peoplePlaceholder
            } else {
                ZStack {
                    TimelineView(
                        items: appState.smartAlbumItems,
                        title: album.title,
                        counts: appState.countsForCurrentSmartAlbumFilter(),
                        showsQuickFilters: true,
                        controlScope: .smartAlbums,
                        backAction: {
                            appState.closeSmartAlbum()
                        }
                    )

                    if appState.isLoadingSmartAlbum {
                        ProgressView()
                            .controlSize(.large)
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Loading smart album")
                    }
                }
            }
        }
    }

    private var peoplePlaceholder: some View {
        ContentUnavailableView {
            Label("People", systemImage: "person.2.crop.square.stack")
        } description: {
            Text("A private placeholder for future people grouping. No face analysis runs today.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 12, alignment: .top)]
    }
}

private struct SmartAlbumsHeader: View {
    let title: String
    let subtitle: String
    let count: Int
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                metrics
                refreshButton
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                HStack(spacing: 10) {
                    metrics
                    refreshButton
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "sparkles.rectangle.stack")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metrics: some View {
        HeaderBadge(systemImage: "rectangle.stack", value: count, label: "active albums")
    }

    private var refreshButton: some View {
        Button(action: action) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Refresh smart albums")
        .accessibilityLabel("Refresh smart albums")
    }
}

private struct SmartAlbumDetailHeader: View {
    let album: SmartAlbum
    let backAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Button(action: backAction) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                albumTitle

                Spacer(minLength: 12)

                HeaderBadge(systemImage: album.systemImage, value: album.itemCount, label: "items")
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(action: backAction) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                HStack(alignment: .center, spacing: 12) {
                    albumTitle
                    Spacer(minLength: 10)
                    HeaderBadge(systemImage: album.systemImage, value: album.itemCount, label: "items")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var albumTitle: some View {
        HStack(spacing: 10) {
            Image(systemName: album.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(album.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SmartAlbumCard: View {
    let album: SmartAlbum
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    icon

                    VStack(alignment: .leading, spacing: 5) {
                        Text(album.title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(album.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    if album.isPlaceholder {
                        Text("Coming Later")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.55), in: Capsule())
                    } else {
                        Text("\(album.itemCount) item\(album.itemCount == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor.opacity(0.34) : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(album.title), \(album.itemCount) item\(album.itemCount == 1 ? "" : "s")")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor.opacity(album.isPlaceholder ? 0.10 : 0.14))
            Image(systemName: album.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(album.isPlaceholder ? .secondary : Color.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 38, height: 38)
    }

    private var cardBackground: Color {
        isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }
}

private struct HeaderBadge: View {
    let systemImage: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 7) {
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
    }
}
