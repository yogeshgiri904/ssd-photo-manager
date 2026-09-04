import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Updating Catalogue", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: cancel) {
                    Label("Cancel", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Cancel catalogue update")
                .accessibilityLabel("Cancel catalogue update")
            }

            ProgressView(value: Double(progress.filesScanned), total: Double(max(progress.totalFilesDiscovered, 1)))
                .progressViewStyle(.linear)

            Text(progress.currentFilename.isEmpty ? "Preparing catalogue update..." : progress.currentFilename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                metric("Checked", "\(progress.filesScanned) / \(progress.totalFilesDiscovered)")
                metric("New", "\(progress.newFiles)")
                metric("Already Indexed", "\(progress.alreadyIndexedFiles)")
                metric("Refreshed", "\(progress.refreshedFiles)")
                if progress.missingFiles > 0 {
                    metric("Missing", "\(progress.missingFiles)")
                }
                metric("Photos", "\(progress.photosFound)")
                metric("Videos", "\(progress.videosFound)")
                metric("Unsupported", "\(progress.unsupportedFiles)")
                metric("Errors", "\(progress.errors)")
                metric("Elapsed", format(progress.elapsedTime))
                if let remaining = progress.estimatedRemainingTime {
                    metric("Remaining", format(remaining))
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var progressText: String {
        guard progress.totalFilesDiscovered > 0 else { return "Discovering photos and videos" }
        let percent = Int((Double(progress.filesScanned) / Double(progress.totalFilesDiscovered)) * 100)
        return "\(percent)% complete"
    }
}
