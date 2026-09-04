import AppKit
import SwiftUI

struct AsyncThumbnailView: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    private let showsBadge: Bool
    private let showsHoverOverlay: Bool
    private let showsSelection: Bool
    private let cornerRadius: CGFloat
    private let fillsAvailableSpace: Bool
    @State private var image: NSImage?
    @State private var isHovered = false
    private let cache = ThumbnailMemoryCache.shared

    init(
        item: MediaItem,
        showsBadge: Bool = true,
        showsHoverOverlay: Bool = true,
        showsSelection: Bool = true,
        cornerRadius: CGFloat = 4,
        fillsAvailableSpace: Bool = true
    ) {
        self.item = item
        self.showsBadge = showsBadge
        self.showsHoverOverlay = showsHoverOverlay
        self.showsSelection = showsSelection
        self.cornerRadius = cornerRadius
        self.fillsAvailableSpace = fillsAvailableSpace
    }

    var body: some View {
        GeometryReader { geometry in
            let size = floor(min(geometry.size.width, geometry.size.height))

            ZStack {
                thumbnailContent(size: size)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                mediaBadges(size: size)

                if showsHoverOverlay && isHovered {
                    hoverLabel(size: size)
                    .transition(.opacity)
                }

                if showsSelection && isBatchSelected {
                    VStack {
                        HStack {
                            selectionBadge
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .overlay {
                if showsSelection && isPrimarySelected && !isBatchSelected {
                    RoundedRectangle(cornerRadius: cornerRadius - 1)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                        .padding(3)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isPrimarySelected)
            .animation(.easeOut(duration: 0.12), value: isBatchSelected)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityAddTraits(showsSelection && (isPrimarySelected || isBatchSelected) ? .isSelected : [])
        }
        .aspectRatio(1, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .task(id: item.relativePath) {
            await loadThumbnail()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-click to open the viewer")
    }

    private var borderColor: Color {
        if showsSelection && isBatchSelected {
            return Color.accentColor
        }
        if showsSelection && isPrimarySelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.primary.opacity(0.22)
        }
        return Color.primary.opacity(0.06)
    }

    private var borderWidth: CGFloat {
        showsSelection && (isPrimarySelected || isBatchSelected) ? 2 : 1
    }

    private var isPrimarySelected: Bool {
        appState.selectedMediaItem?.id == item.id
    }

    private var isBatchSelected: Bool {
        appState.selectedMediaItemIDs.contains(item.id)
    }

    private var selectionBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .background(.regularMaterial, in: Circle())
            .accessibilityLabel("Selected")
    }

    @ViewBuilder
    private func thumbnailContent(size: CGFloat) -> some View {
        if let image {
            if fillsAvailableSpace {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .saturation(item.isMissing ? 0.15 : 1)
                    .opacity(item.isMissing ? 0.45 : 1)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .saturation(item.isMissing ? 0.15 : 1)
                    .opacity(item.isMissing ? 0.45 : 1)
            }
        } else {
            Rectangle()
                .fill(Color(nsColor: .underPageBackgroundColor))
                .frame(width: size, height: size)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: item.kind == .video ? "film" : "photo")
                            .font(.title2)
                        Text(item.kind.label)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
    }

    @ViewBuilder
    private func mediaBadges(size: CGFloat) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 6) {
                if item.isMissing {
                    statusBadge(title: "Missing", systemImage: "exclamationmark.triangle.fill")
                } else if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.48), in: Circle())
                        .accessibilityLabel("Favorite")
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                if showsBadge && item.kind == .video {
                    Text(durationText)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.52), in: Capsule())
                        .accessibilityLabel("Video duration \(durationText)")
                }
            }
        }
        .padding(6)
        .frame(width: size, height: size)
        .clipped()
    }

    private func hoverLabel(size: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Text(item.filename)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: max(44, size - 12), alignment: .leading)
                    .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 5))
                Spacer(minLength: 0)
            }
        }
        .padding(6)
        .frame(width: size, height: size)
        .clipped()
    }

    private func statusBadge(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.red.opacity(0.82), in: Capsule())
    }

    private var durationText: String {
        guard let duration = item.duration, duration.isFinite else { return "Video" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var accessibilityText: String {
        [item.filename, item.kind.label, item.captureDateLocalText].joined(separator: ", ")
    }

    private func loadThumbnail() async {
        let path = item.thumbnailPath ?? item.videoThumbnailPath
        guard let path, let url = appState.thumbnailURL(for: path) else { return }

        if let cached = cache.image(for: url) {
            image = cached
            return
        }

        guard let loaded = NSImage(contentsOf: url) else { return }
        cache.insert(loaded, for: url)
        await MainActor.run {
            image = loaded
        }
    }
}

private final class ThumbnailMemoryCache {
    static let shared = ThumbnailMemoryCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 600
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        let pixels = max(1, Int(image.size.width * image.size.height))
        cache.setObject(image, forKey: url as NSURL, cost: pixels * 4)
    }
}
