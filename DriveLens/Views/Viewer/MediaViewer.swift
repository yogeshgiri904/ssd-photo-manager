import AVKit
import SwiftUI

struct MediaViewer: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isKeyboardFocused: Bool
    @StateObject private var videoController = VideoPlaybackController()
    var closeAction: (() -> Void)?
    @GestureState private var gestureScale: CGFloat = 1
    @State private var image: NSImage?
    @State private var imageLoadFailed = false
    @State private var baseScale: CGFloat = 1
    @State private var rotation: Angle = .zero
    @State private var interactionMessage: String?
    @State private var interactionMessageTask: Task<Void, Never>?

    private var displayScale: CGFloat {
        clampedScale(baseScale * gestureScale)
    }

    var body: some View {
        Group {
            if let item = appState.selectedMediaItem {
                VStack(spacing: 0) {
                    ViewerToolbar(
                        item: item,
                        scale: displayScale,
                        isImage: item.kind != .video,
                        isVideoPlaying: videoController.isPlaying,
                        canControlVideo: videoController.canControlPlayback,
                        close: closeViewer,
                        zoomOut: { zoomOut(showFeedback: true) },
                        zoomIn: { zoomIn(showFeedback: true) },
                        fit: { fitImage(showFeedback: true) },
                        actualSize: { actualSize(showFeedback: true) },
                        rotate: { rotateImage(showFeedback: true) },
                        toggleVideoPlayback: togglePlayback,
                        reveal: { appState.revealInFinder(item) },
                        copy: { appState.copyOriginal(item) },
                        share: { appState.shareOriginal(item) },
                        showInTimeline: {
                            appState.showInTimeline(item)
                            closeViewer()
                        },
                        showOnMap: {
                            appState.showOnMap(item)
                            closeViewer()
                        },
                        showInFolder: {
                            appState.showInFolder(item)
                            closeViewer()
                        }
                    )

                    Divider()

                    ZStack {
                        if item.kind == .video {
                            videoPreview(for: item)
                        } else {
                            imagePreview(for: item)
                        }

                        interactionHUD
                    }
                }
            } else {
                ContentUnavailableView("No Item Selected", systemImage: "photo.on.rectangle")
                    .frame(minWidth: 760, minHeight: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isKeyboardFocused)
        .onAppear {
            isKeyboardFocused = true
        }
        .task(id: appState.selectedMediaItem?.id) {
            await loadSelectedItem()
        }
        .onDisappear {
            interactionMessageTask?.cancel()
            videoController.reset()
        }
        .onExitCommand {
            closeViewer()
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .onKeyPress(.space) {
            guard appState.selectedMediaItem?.kind == .video else {
                return .ignored
            }
            togglePlayback()
            return .handled
        }
    }

    private func imagePreview(for item: MediaItem) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let stageSize = containedStageSize(in: geometry.size)

                ZStack {
                    Color(nsColor: .textBackgroundColor)

                    if let image {
                        CenteredZoomImageView(
                            image: image,
                            itemID: item.id,
                            scale: displayScale,
                            rotation: rotation,
                            stageSize: stageSize
                        )
                        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: baseScale)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: rotation)
                    } else if imageLoadFailed {
                        ContentUnavailableView {
                            Label("Preview Unavailable", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("The original image could not be opened. The catalogue record has not been changed.")
                        } actions: {
                            Button {
                                appState.revealInFinder(item)
                            } label: {
                                Label("Reveal in Finder", systemImage: "finder")
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading Preview")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ViewerNavigationOverlay(
                        canGoPrevious: appState.canSelectAdjacentItem(offset: -1),
                        canGoNext: appState.canSelectAdjacentItem(offset: 1),
                        previous: { navigateSelection(offset: -1) },
                        next: { navigateSelection(offset: 1) }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnificationGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            baseScale = clampedScale(baseScale * value)
                            showInteractionMessage("Zoom \(Int(displayScale * 100))%")
                        }
                )
                .simultaneousGesture(imageNavigationGesture)
                .onTapGesture(count: 2) {
                    toggleImageZoom()
                }
                .onTapGesture {
                    isKeyboardFocused = true
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ViewerStatusBar(item: item)
        }
    }

    private func videoPreview(for item: MediaItem) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black

                if let player = videoController.player {
                    AspectFitVideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if videoController.failureMessage != nil {
                        Color.black.opacity(0.72)
                        videoUnavailableView(for: item)
                    } else if videoController.isLoading {
                        ProgressView("Preparing Video")
                            .controlSize(.large)
                            .tint(.white)
                            .foregroundStyle(.white)
                    } else if videoController.canControlPlayback && !videoController.isPlaying {
                        Button(action: togglePlayback) {
                            Label("Play Video", systemImage: "play.fill")
                                .font(.title2.weight(.semibold))
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(.black.opacity(0.58), in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.36), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play video")
                    }
                } else if videoController.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    videoUnavailableView(for: item)
                }

                ViewerNavigationOverlay(
                    canGoPrevious: appState.canSelectAdjacentItem(offset: -1),
                    canGoNext: appState.canSelectAdjacentItem(offset: 1),
                    previous: { navigateSelection(offset: -1) },
                    next: { navigateSelection(offset: 1) }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ViewerDetailsPanel(item: item)
                .frame(width: 280)
        }
    }

    private func loadSelectedItem() async {
        videoController.reset()
        image = nil
        imageLoadFailed = false
        fitImage()

        guard let item = appState.selectedMediaItem else { return }
        guard let url = originalURL(for: item) else {
            if item.kind == .video {
                videoController.setUnavailable(
                    "The original video is unavailable. Connect the storage device to continue."
                )
            } else {
                imageLoadFailed = true
            }
            return
        }

        if item.kind == .video {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  FileManager.default.isReadableFile(atPath: url.path) else {
                videoController.setUnavailable(
                    "The original video is unavailable. Connect the storage device to continue."
                )
                return
            }
            await videoController.load(url: url)
        } else if let data = await Task.detached(priority: .userInitiated, operation: {
            try? Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
        }).value, !Task.isCancelled, let loadedImage = NSImage(data: data) {
            image = loadedImage
        } else {
            imageLoadFailed = true
        }
    }

    private var interactionHUD: some View {
        Group {
            if let interactionMessage {
                Text(interactionMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.58), in: Capsule())
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: interactionMessage)
    }

    private var imageNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 46)
            .onEnded { value in
                guard displayScale <= 1.01 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                guard abs(value.translation.width) > 70 else { return }
                navigateSelection(offset: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard let item = appState.selectedMediaItem else { return }

        if item.kind == .video {
            switch direction {
            case .left:
                if videoController.isPlaying {
                    seekVideo(by: -5)
                } else {
                    navigateSelection(offset: -1)
                }
            case .right:
                if videoController.isPlaying {
                    seekVideo(by: 5)
                } else {
                    navigateSelection(offset: 1)
                }
            case .up:
                if videoController.isPlaying {
                    adjustVolume(by: 0.08)
                }
            case .down:
                if videoController.isPlaying {
                    adjustVolume(by: -0.08)
                }
            default:
                break
            }
        } else {
            switch direction {
            case .left:
                navigateSelection(offset: -1)
            case .right:
                navigateSelection(offset: 1)
            case .up:
                zoomIn(showFeedback: true)
            case .down:
                zoomOut(showFeedback: true)
            default:
                break
            }
        }
    }

    private func navigateSelection(offset: Int) {
        appState.selectAdjacentItem(offset: offset)
    }

    private func togglePlayback() {
        if let isPlaying = videoController.togglePlayback() {
            showInteractionMessage(isPlaying ? "Playing" : "Paused")
        }
    }

    private func seekVideo(by seconds: Double) {
        guard videoController.seek(by: seconds) else { return }
        showInteractionMessage(seconds < 0 ? "\(Int(abs(seconds)))s Back" : "\(Int(seconds))s Forward")
    }

    private func adjustVolume(by delta: Float) {
        guard let volume = videoController.adjustVolume(by: delta) else { return }
        showInteractionMessage("Volume \(Int(volume * 100))%")
    }

    private func fitImage(showFeedback: Bool = false) {
        baseScale = 1
        rotation = .zero
        if showFeedback {
            showInteractionMessage("Fit")
        }
    }

    private func closeViewer() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }

    private func actualSize(showFeedback: Bool = false) {
        baseScale = 2
        if showFeedback {
            showInteractionMessage("200%")
        }
    }

    private func zoomIn(showFeedback: Bool = false) {
        baseScale = clampedScale(baseScale + 0.25)
        if showFeedback {
            showInteractionMessage("Zoom \(Int(baseScale * 100))%")
        }
    }

    private func zoomOut(showFeedback: Bool = false) {
        baseScale = clampedScale(baseScale - 0.25)
        if showFeedback {
            showInteractionMessage("Zoom \(Int(baseScale * 100))%")
        }
    }

    private func rotateImage(showFeedback: Bool = false) {
        rotation += .degrees(90)
        if showFeedback {
            showInteractionMessage("Rotated")
        }
    }

    private func toggleImageZoom() {
        if baseScale > 1.01 {
            fitImage(showFeedback: true)
        } else {
            actualSize(showFeedback: true)
        }
    }

    private func showInteractionMessage(_ message: String) {
        interactionMessageTask?.cancel()
        interactionMessage = message

        interactionMessageTask = Task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                interactionMessage = nil
            }
        }
    }

    private func originalURL(for item: MediaItem) -> URL? {
        appState.mediaURL(for: item)
    }

    private func videoUnavailableView(for item: MediaItem) -> some View {
        ContentUnavailableView {
            Label("Video Unavailable", systemImage: "film.stack")
        } description: {
            Text(videoController.failureMessage ?? "The video could not be opened.")
        } actions: {
            HStack(spacing: 8) {
                Button {
                    Task { await loadSelectedItem() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }

                Button {
                    appState.revealInFinder(item)
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Video unavailable")
    }

    private func containedStageSize(in size: CGSize) -> CGSize {
        CGSize(
            width: max(1, size.width - 48),
            height: max(1, size.height - 48)
        )
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.5), 5)
    }
}

@MainActor
private final class VideoPlaybackController: ObservableObject {
    private enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private var loadState: LoadState = .idle

    private var representedURL: URL?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?

    var isLoading: Bool {
        loadState == .loading
    }

    var canControlPlayback: Bool {
        loadState == .ready && player != nil
    }

    var failureMessage: String? {
        guard case .failed(let message) = loadState else { return nil }
        return message
    }

    func load(url: URL) async {
        reset()
        let requestedURL = url.standardizedFileURL
        representedURL = requestedURL
        loadState = .loading

        do {
            let asset = AVURLAsset(url: requestedURL)
            let isPlayable = try await asset.load(.isPlayable)
            guard !Task.isCancelled, representedURL == requestedURL else { return }
            guard isPlayable else {
                setFailure("This video format cannot be played on this Mac.")
                return
            }

            let playerItem = AVPlayerItem(asset: asset)
            let preparedPlayer = AVPlayer(playerItem: playerItem)
            preparedPlayer.actionAtItemEnd = .pause
            preparedPlayer.preventsDisplaySleepDuringVideoPlayback = true
            player = preparedPlayer
            observe(player: preparedPlayer, item: playerItem)
        } catch {
            guard representedURL == requestedURL else { return }
            setFailure("The video could not be opened. Check that the storage device is connected and the file can be read.")
        }
    }

    func setUnavailable(_ message: String) {
        reset()
        loadState = .failed(message)
    }

    @discardableResult
    func togglePlayback() -> Bool? {
        guard canControlPlayback, let player else { return nil }

        if player.timeControlStatus != .paused {
            player.pause()
            isPlaying = false
            return false
        }

        if let duration = player.currentItem?.duration.seconds,
           duration.isFinite,
           player.currentTime().seconds >= duration - 0.05 {
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
        return true
    }

    func seek(by seconds: Double) -> Bool {
        guard canControlPlayback, let player else { return false }
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite else { return false }

        let durationSeconds = player.currentItem?.duration.seconds
        let upperBound = durationSeconds?.isFinite == true
            ? durationSeconds ?? .greatestFiniteMagnitude
            : .greatestFiniteMagnitude
        let targetSeconds = min(max(0, currentSeconds + seconds), upperBound)
        player.seek(
            to: CMTime(seconds: targetSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        return true
    }

    func adjustVolume(by delta: Float) -> Float? {
        guard canControlPlayback, let player else { return nil }
        player.volume = min(max(player.volume + delta, 0), 1)
        return player.volume
    }

    func reset() {
        itemStatusObservation = nil
        timeControlObservation = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = nil
        representedURL = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        loadState = .idle
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player?.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadState = .ready
                case .failed:
                    self.setFailure("DriveLens could not play this video. The file may use a format or codec that is not supported on this Mac.")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak player] _, _ in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                self.isPlaying = player.timeControlStatus != .paused
            }
        }

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
        }
    }

    private func setFailure(_ message: String) {
        player?.pause()
        isPlaying = false
        loadState = .failed(message)
    }
}

private struct AspectFitVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.showsSharingServiceButton = false
        view.updatesNowPlayingInfoCenter = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.controlsStyle = .inline
        nsView.videoGravity = .resizeAspect
    }
}

private struct CenteredZoomImageView: NSViewRepresentable {
    let image: NSImage
    let itemID: MediaItem.ID
    let scale: CGFloat
    let rotation: Angle
    let stageSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = false
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = CenteredImageDocumentView()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let documentView = scrollView.documentView as? CenteredImageDocumentView else { return }

        let contentSize = scrollView.contentSize
        let viewportSize = CGSize(
            width: max(stageSize.width, contentSize.width),
            height: max(stageSize.height, contentSize.height)
        )
        let itemChanged = context.coordinator.itemID != itemID
        let imageChanged = context.coordinator.image !== image
        let scaleChanged = abs(context.coordinator.scale - scale) > 0.001
        let rotationChanged = abs(context.coordinator.rotationRadians - rotation.radians) > 0.001
        let viewportChanged = context.coordinator.stageSize != stageSize

        documentView.image = image
        documentView.scale = scale
        documentView.rotationRadians = rotation.radians
        documentView.viewportSize = viewportSize

        let documentSize = documentView.preferredDocumentSize()
        if documentView.frame.size != documentSize {
            documentView.setFrameSize(documentSize)
        }
        documentView.needsDisplay = true

        if itemChanged || imageChanged || scaleChanged || rotationChanged || viewportChanged {
            centerVisibleContent(in: scrollView)
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                centerVisibleContent(in: scrollView)
            }
        }

        context.coordinator.itemID = itemID
        context.coordinator.image = image
        context.coordinator.scale = scale
        context.coordinator.rotationRadians = rotation.radians
        context.coordinator.stageSize = stageSize
    }

    private func centerVisibleContent(in scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }

        let visibleSize = scrollView.contentSize
        let documentSize = documentView.bounds.size
        let origin = NSPoint(
            x: max(0, (documentSize.width - visibleSize.width) / 2),
            y: max(0, (documentSize.height - visibleSize.height) / 2)
        )

        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    final class Coordinator {
        var itemID: MediaItem.ID?
        weak var image: NSImage?
        var scale: CGFloat = 1
        var rotationRadians: Double = 0
        var stageSize: CGSize = .zero
    }
}

private final class CenteredImageDocumentView: NSView {
    var image: NSImage?
    var scale: CGFloat = 1
    var rotationRadians: Double = 0
    var viewportSize: CGSize = .zero

    override var isFlipped: Bool {
        true
    }

    func preferredDocumentSize() -> CGSize {
        let fittedSize = fittedImageSize()
        let zoomedSize = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        let rotatedSize = rotatedBoundingSize(for: zoomedSize)
        let inset: CGFloat = 48

        return CGSize(
            width: max(viewportSize.width, rotatedSize.width + inset),
            height: max(viewportSize.height, rotatedSize.height + inset)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let image else { return }

        NSGraphicsContext.current?.imageInterpolation = .high

        let fittedSize = fittedImageSize()
        let zoomedSize = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        let rect = CGRect(
            x: (bounds.width - zoomedSize.width) / 2,
            y: (bounds.height - zoomedSize.height) / 2,
            width: zoomedSize.width,
            height: zoomedSize.height
        )
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        NSGraphicsContext.saveGraphicsState()

        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: CGFloat(rotationRadians))
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func fittedImageSize() -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: max(1, viewportSize.width), height: max(1, viewportSize.height))
        }

        let availableSize = CGSize(
            width: max(1, viewportSize.width),
            height: max(1, viewportSize.height)
        )
        let ratio = min(availableSize.width / image.size.width, availableSize.height / image.size.height)

        return CGSize(
            width: max(1, image.size.width * ratio),
            height: max(1, image.size.height * ratio)
        )
    }

    private func rotatedBoundingSize(for size: CGSize) -> CGSize {
        let radians = CGFloat(rotationRadians)
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))

        return CGSize(
            width: size.width * cosine + size.height * sine,
            height: size.width * sine + size.height * cosine
        )
    }
}

private struct ViewerNavigationOverlay: View {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            navigationButton(
                title: "Previous File",
                systemImage: "chevron.left",
                isEnabled: canGoPrevious,
                shortcut: .leftArrow,
                action: previous
            )

            Spacer(minLength: 80)

            navigationButton(
                title: "Next File",
                systemImage: "chevron.right",
                isEnabled: canGoNext,
                shortcut: .rightArrow,
                action: next
            )
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navigationButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 54)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 0.96 : 0.32)
        .keyboardShortcut(shortcut, modifiers: [.command])
        .accessibilityLabel(title)
    }
}

private struct ViewerToolbar: View {
    let item: MediaItem
    let scale: CGFloat
    let isImage: Bool
    let isVideoPlaying: Bool
    let canControlVideo: Bool
    let close: () -> Void
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let fit: () -> Void
    let actualSize: () -> Void
    let rotate: () -> Void
    let toggleVideoPlayback: () -> Void
    let reveal: () -> Void
    let copy: () -> Void
    let share: () -> Void
    let showInTimeline: () -> Void
    let showOnMap: () -> Void
    let showInFolder: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Label("Close", systemImage: "xmark")
            }
            .keyboardShortcut(.cancelAction)
            .help("Close")

            Divider()
                .frame(height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            ControlGroup {
                MediaFavoriteButton(items: [item])
                AddToAlbumMenu(items: [item])
            }

            if isImage {
                ControlGroup {
                    Button(action: zoomOut) {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .help("Zoom Out")

                    Button(action: fit) {
                        Text("\(Int(scale * 100))%")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .frame(minWidth: 42)
                    }
                    .help("Fit to Window")

                    Button(action: zoomIn) {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .help("Zoom In")

                    Button(action: actualSize) {
                        Label("Zoom to 200%", systemImage: "1.magnifyingglass")
                    }
                    .help("Zoom to 200%")

                    Button(action: rotate) {
                        Label("Rotate", systemImage: "rotate.right")
                    }
                    .help("Rotate Preview")
                }
            } else {
                Button(action: toggleVideoPlayback) {
                    Label(isVideoPlaying ? "Pause Video" : "Play Video", systemImage: isVideoPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(!canControlVideo)
                .accessibilityLabel(isVideoPlaying ? "Pause video" : "Play video")
            }

            ControlGroup {
                Button(action: reveal) {
                    Label("Reveal in Finder", systemImage: "finder")
                }
                .help("Reveal in Finder")

                Button(action: copy) {
                    Label("Copy Original", systemImage: "doc.on.doc")
                }
                .help("Copy Original")

                Button(action: share) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share")
            }

            Menu {
                Button("Timeline", action: showInTimeline)
                Button("Map", action: showOnMap)
                Button("Folder", action: showInFolder)
            } label: {
                OptionsMenuLabel(title: "Show in", size: 30)
            }
            .menuStyle(.borderlessButton)
            .help("Show In")
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

private struct ViewerStatusBar: View {
    let item: MediaItem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                metadata
            }

            VStack(alignment: .leading, spacing: 4) {
                metadata
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var metadata: some View {
        Label(item.kind.label, systemImage: item.kind == .video ? "film" : "photo")
        Label(item.captureDateLocalText, systemImage: "calendar")
        if let dimensions = dimensionsText {
            Label(dimensions, systemImage: "aspectratio")
        }
        if !item.cameraText.isEmpty {
            Label(item.cameraText, systemImage: "camera")
        }
        if item.coordinate != nil {
            Label(item.placeText.isEmpty ? "Location Available" : item.placeText, systemImage: "mappin.and.ellipse")
        }
    }

    private var dimensionsText: String? {
        guard let width = item.width, let height = item.height else { return nil }
        return "\(width) × \(height)"
    }
}

private struct ViewerDetailsPanel: View {
    @EnvironmentObject private var appState: AppState
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label(item.kind.label, systemImage: item.kind == .video ? "film" : "photo")
                    .font(.subheadline.weight(.semibold))

                Text(item.captureDateLocalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                DetailRow(title: "Duration", value: durationText)
                DetailRow(title: "Dimensions", value: dimensionsText)
                DetailRow(title: "Camera", value: item.cameraText.isEmpty ? nil : item.cameraText)
                DetailRow(title: "Location", value: item.placeText.isEmpty ? (item.coordinate == nil ? nil : "Location Available") : item.placeText)
                DetailRow(title: "Favorite", value: appState.favoriteState(for: item) ? "Yes" : "No")
                DetailRow(title: "File", value: item.filename)
            }

            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var durationText: String? {
        guard let duration = item.duration, duration.isFinite else { return nil }
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var dimensionsText: String? {
        guard let width = item.width, let height = item.height else { return nil }
        return "\(width) × \(height)"
    }
}

private struct DetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
        }
    }
}
