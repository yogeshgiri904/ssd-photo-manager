import AppKit
import ImageIO
import SwiftUI

struct AsyncThumbnailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let item: MediaItem
    private let showsBadge: Bool
    private let showsHoverOverlay: Bool
    private let showsSelection: Bool
    private let cornerRadius: CGFloat
    private let fillsAvailableSpace: Bool
    @State private var isHovered = false

    init(
        item: MediaItem,
        showsBadge: Bool = true,
        showsHoverOverlay: Bool = true,
        showsSelection: Bool = true,
        cornerRadius: CGFloat = 9,
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
                    .transition(reduceMotion ? .identity : .scale(scale: 0.85).combined(with: .opacity))
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
                    RoundedRectangle(cornerRadius: max(0, cornerRadius - 1))
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                        .padding(3)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPrimarySelected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isBatchSelected)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityAddTraits(showsSelection && (isPrimarySelected || isBatchSelected) ? .isSelected : [])
        }
        .aspectRatio(1, contentMode: .fit)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Select the item or use the Open in Viewer action")
        .accessibilityAction {
            appState.selectSingleMediaItem(item)
        }
        .accessibilityAction(named: Text("Open in Viewer")) {
            appState.viewInViewer(item)
        }
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
        return Color.primary.opacity(contrast == .increased ? 0.45 : 0.06)
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
            .background(LensTheme.surface, in: Circle())
            .accessibilityLabel("Selected")
    }

    @ViewBuilder
    private func thumbnailContent(size: CGFloat) -> some View {
        AsyncMediaThumbnailImage(
            item: item,
            fillsAvailableSpace: fillsAvailableSpace,
            cornerRadius: cornerRadius
        )
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func mediaBadges(size: CGFloat) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 6) {
                if item.isMissing {
                    statusBadge(title: "Missing", systemImage: "exclamationmark.triangle.fill")
                } else if appState.favoriteState(for: item) {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(reduceTransparency ? 1 : 0.78), in: Circle())
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
                        .background(.black.opacity(reduceTransparency ? 1 : 0.78), in: Capsule())
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
                    .frame(maxWidth: max(44, size - (showsBadge && item.kind == .video ? 64 : 12)), alignment: .leading)
                    .background(.black.opacity(reduceTransparency ? 1 : 0.78), in: RoundedRectangle(cornerRadius: 5))
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
        var parts = [item.filename, item.kind.label, item.captureDateLocalText]
        if appState.favoriteState(for: item) { parts.append("Favorite") }
        if item.isMissing { parts.append("Original file missing") }
        return parts.joined(separator: ", ")
    }
}

/// Loads one generated catalogue thumbnail into any rectangular surface.
/// Interactive thumbnail views and album covers share this loader and cache.
struct AsyncMediaThumbnailImage: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem
    var fillsAvailableSpace = true
    var cornerRadius: CGFloat = 0
    var showsPlaceholderLabel = true
    @State private var image: NSImage?
    @State private var loadFailed = false
    private let cache = ThumbnailMemoryCache.shared

    var body: some View {
        GeometryReader { geometry in
            thumbnailContent(size: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .task(id: thumbnailIdentity) {
            await loadThumbnail()
        }
        .onDisappear { image = nil }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func thumbnailContent(size: CGSize) -> some View {
        if let image {
            if fillsAvailableSpace {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .saturation(item.isMissing ? 0.15 : 1)
                    .opacity(item.isMissing ? 0.45 : 1)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .saturation(item.isMissing ? 0.15 : 1)
                    .opacity(item.isMissing ? 0.45 : 1)
            }
        } else {
            Rectangle()
                .fill(Color(nsColor: .underPageBackgroundColor))
                .frame(width: size.width, height: size.height)
                .overlay {
                    if showsPlaceholderLabel {
                        VStack(spacing: 6) {
                            Image(systemName: loadFailed ? "photo.badge.exclamationmark" : item.kind == .video ? "film" : "photo")
                                .font(.title2)
                            Text(loadFailed ? "No preview" : item.kind.label)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private func loadThumbnail() async {
        image = nil
        loadFailed = false
        let path = item.thumbnailPath ?? item.videoThumbnailPath
        guard let path, let url = appState.thumbnailURL(for: path) else { loadFailed = true; return }
        if let cached = cache.image(for: url, version: item.updatedAt) {
            image = NSImage(cgImage: cached, size: NSSize(width: cached.width, height: cached.height))
            return
        }
        // The decoder actor serializes disk reads and forces pixel decoding off the UI actor.
        let decoded = await ThumbnailDecoder.shared.decode(url, version: item.updatedAt)
        guard !Task.isCancelled else { return }
        guard let decoded else { loadFailed = true; return }
        let loaded = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        image = loaded
    }

    private var thumbnailIdentity: String {
        [appState.catalogueRootURL?.path, item.relativePath, item.thumbnailPath, item.videoThumbnailPath,
         String(item.updatedAt.timeIntervalSince1970)]
            .compactMap { $0 }.joined(separator: "|")
    }

}
