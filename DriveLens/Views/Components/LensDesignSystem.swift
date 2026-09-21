import AppKit
import SwiftUI

/// Shared semantic tokens. Dynamic system colors retain native appearance and contrast behavior.
enum LensTheme {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let gradient = LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let pageInset: CGFloat = 20
    static let compactInset: CGFloat = 12
    static let rowHeight: CGFloat = 30
    static let gridSpacing: CGFloat = 8
    static let selectedFill = Color.accentColor.opacity(0.10)
    static let hoverFill = Color.primary.opacity(0.05)
    static let radius: CGFloat = 12
    static let controlRadius: CGFloat = 7
    static let title = Font.system(size: 23, weight: .semibold)
    static let eyebrow = Font.system(size: 10, weight: .semibold)
}

struct LensChrome: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        if reduceTransparency || contrast == .increased {
            LensTheme.surface
        } else {
            Rectangle().fill(.bar)
        }
    }
}

struct LensSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = LensTheme.radius
    func body(content: Content) -> some View {
        content
            .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(contrast == .increased ? Color.primary.opacity(0.6) : LensTheme.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct LensSectionTitle: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LensTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(LensTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(LensTheme.title).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Plain controls keep system keyboard focus while adding a quiet pointer affordance.
struct LensQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, isEnabled: isEnabled)
    }
    private struct QuietButton: View {
        let configuration: Configuration
        let isEnabled: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hovered && isEnabled ? 0.06 : 0), in: RoundedRectangle(cornerRadius: LensTheme.controlRadius))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: LensTheme.controlRadius))
                .onHover { hovered = $0 }
        }
    }
}

extension View {
    /// Our fixed headers already separate scrolling content from window chrome.
    @ViewBuilder func lensScrollEdges() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }

    func lensSurface(radius: CGFloat = LensTheme.radius) -> some View { modifier(LensSurface(radius: radius)) }
    func lensEyebrow() -> some View {
        font(LensTheme.eyebrow).tracking(0.8).foregroundStyle(.secondary)
    }
}

struct LensSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearance = "system"
    @State private var selectedTab: Int

    init(selectedTab: Int = 0) {
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            general
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
                .tag(0)
            shortcuts
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(1)
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .background(LensTheme.sidebar)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }

    private var general: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(["system", "light", "dark"], id: \.self) { theme in
                        AppearanceOption(title: theme.capitalized, theme: theme, isSelected: appearance == theme) {
                            appearance = theme
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Contrast, motion, and transparency follow your Mac’s accessibility settings.")
            }
            Section("Browsing") {
                LabeledContent("Thumbnail size") {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3").foregroundStyle(.secondary).accessibilityHidden(true)
                        Slider(value: $appState.gridSize, in: 92...220)
                            .frame(width: 150).accessibilityLabel("Thumbnail size")
                        Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                Toggle("Show inspector", isOn: $appState.showingInspector)
                Text("In compact windows, details open from the Inspect button below the grid.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Catalogue") {
                LabeledContent("Storage & Privacy") {
                    Button("Open", systemImage: "arrow.up.forward") {
                        appState.select(.appInfo)
                        openWindow(id: "library")
                    }
                    .accessibilityLabel("Open Storage & Privacy")
                }
                Text("Manage catalogues, review storage, and clear generated previews.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Navigate") {
                shortcut("Library destinations", keys: "⌘1 – ⌘9")
                shortcut("Show or hide inspector", keys: "⌥⌘I")
                shortcut("Choose catalogue", keys: "⇧⌘O")
            }
            Section("Browse & preview") {
                shortcut("Move between items", keys: "← ↑ ↓ →")
                shortcut("Open selected item", keys: "Space")
                shortcut("Close preview or clear selection", keys: "Esc")
                shortcut("Resize thumbnails", keys: "⌘+ / ⌘−")
            }
            Section("Catalogue") {
                shortcut("Update catalogue", keys: "⇧⌘R")
                shortcut("Find duplicates", keys: "⇧⌘D")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        LabeledContent(title) {
            Text(keys).font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppearanceOption: View {
    let title: String
    let theme: String
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    miniature(dark: theme == "dark")
                    if theme == "system" { miniature(dark: true) }
                }
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected || focused ? Color.accentColor : LensTheme.line, lineWidth: isSelected || focused ? 2 : 1)
                }
                HStack(spacing: 4) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(title).fontWeight(isSelected ? .semibold : .regular)
                }
                .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .accessibilityLabel(title + " appearance")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func miniature(dark: Bool) -> some View {
        HStack(spacing: 5) {
            VStack(spacing: 4) {
                Capsule().fill(Color.accentColor.opacity(0.6)).frame(height: 4)
                Capsule().fill(Color.gray.opacity(0.3)).frame(height: 3)
                Capsule().fill(Color.gray.opacity(0.3)).frame(height: 3)
                Spacer(minLength: 0)
            }
            .padding(6).frame(width: 30)
            .background(dark ? Color(white: 0.19) : Color(white: 0.91))
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color.gray.opacity(0.45)).frame(width: 20, height: 3)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.25))
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.4))
                }
            }
            .padding(.vertical, 9).padding(.trailing, 6)
        }
        .background(dark ? Color(white: 0.12) : .white)
        .accessibilityHidden(true)
    }
}

/// Shared dimensions for inspector surfaces and metadata forms.
enum LensInspectorMetrics {
    static let actionHeight: CGFloat = 28
    static let inset: CGFloat = 12
    static let cardInset: CGFloat = 10
    static let sectionSpacing: CGFloat = 18
    static let radius: CGFloat = 9
    static let previewHeight: CGFloat = 144
    static let section = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
}

/// Wraps intrinsic-size labels without a GeometryReader or per-label state updates.
struct LensFlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 280, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, entry) in result.entries.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + entry.origin.x, y: bounds.minY + entry.origin.y),
                                 proposal: ProposedViewSize(entry.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, entries: [CGRect]) {
        let width = max(0, width)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var entries: [CGRect] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            entries.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), entries)
    }
}

/// Header rhythm shared by library browsing controls and compact fallback layouts.
enum LensHeaderMetrics {
    static let inset: CGFloat = 16
    static let verticalInset: CGFloat = 14
    static let sectionGap: CGFloat = 12
    static let sliderWidth: CGFloat = 88
    static let title = Font.system(size: 21, weight: .semibold)
    static let subtitle = Font.system(size: 12)
    static let control = Font.system(size: 11, weight: .medium)
}
