import AppKit
import SwiftUI

struct DriveLensLogoView: View {
    var size: CGFloat = 32
    var showsSubtleBackground = false
    var isDecorative = false

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: min(size * 0.22, 12), style: .continuous))
            .shadow(color: .black.opacity(showsSubtleBackground ? 0.2 : 0), radius: 12, y: 4)
            .accessibilityLabel("DriveLens")
            .accessibilityHidden(isDecorative)
    }
}

struct DriveLensBrandLockup: View {
    var logoSize: CGFloat = 28
    var titleFont: Font = .headline
    var subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DriveLensLogoView(size: logoSize, isDecorative: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("DriveLens")
                    .font(titleFont)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "DriveLens, \($0)" } ?? "DriveLens")
    }
}

struct OptionsMenuLabel: View {
    var title = "More Actions"
    var size: CGFloat = 28

    var body: some View {
        VStack(spacing: max(2, size * 0.09)) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.secondary.opacity(0.92))
                    .frame(width: max(2.6, size * 0.105), height: max(2.6, size * 0.105))
            }
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel(title)
    }
}
