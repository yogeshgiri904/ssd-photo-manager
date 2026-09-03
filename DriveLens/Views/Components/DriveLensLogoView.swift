import SwiftUI

struct DriveLensLogoView: View {
    var size: CGFloat = 32
    var showsSubtleBackground = false

    var body: some View {
        Image("DriveLensLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background {
                if showsSubtleBackground {
                    RoundedRectangle(cornerRadius: min(size * 0.22, 12), style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: min(size * 0.22, 12), style: .continuous))
            .shadow(color: .black.opacity(showsSubtleBackground ? 0.14 : 0), radius: 8, y: 2)
            .accessibilityLabel("DriveLens")
    }
}

struct DriveLensBrandLockup: View {
    var logoSize: CGFloat = 28
    var titleFont: Font = .headline
    var subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            DriveLensLogoView(size: logoSize)

            VStack(alignment: .leading, spacing: 1) {
                Text("DriveLens")
                    .font(titleFont)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

