import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0

    private let pages = [
        OnboardingPage(
            title: "Your media stays where it is",
            message: "DriveLens builds a private local catalogue without moving, renaming, or uploading your photos and videos.",
            image: "externaldrive"
        ),
        OnboardingPage(
            title: "Browse by time and place",
            message: "Use capture dates, folders and GPS metadata to find media quickly.",
            image: "calendar.badge.clock"
        ),
        OnboardingPage(
            title: "Choose folders to catalogue",
            message: "Select one or more folders. DriveLens stores generated catalogue data in .drivelens at the storage root, and you can rename it later in App Info.",
            image: "folder.badge.plus"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)

            VStack(spacing: 26) {
                DriveLensLogoView(size: 92, showsSubtleBackground: true)

                VStack(spacing: 10) {
                    Text(pages[step].title)
                        .font(.system(size: 32, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text(pages[step].message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }

                if step == 2 {
                    folderSelectionPanel
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 44)

            Spacer(minLength: 28)

            VStack(spacing: 18) {
                StepIndicator(count: pages.count, selectedIndex: step)
                footer
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 34)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshSavedCatalogues()
            if !appState.savedCatalogues.isEmpty && appState.activeCatalogue == nil && appState.selectedRootURL == nil {
                step = 2
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                step = max(0, step - 1)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(step == 0)

            Spacer()

            if step < pages.count - 1 {
                Button {
                    step += 1
                } label: {
                    Label("Continue", systemImage: "chevron.right")
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    Task { await appState.createCatalogueByChoosingFolders() }
                } label: {
                    Label("Choose Folders", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private var folderSelectionPanel: some View {
        CatalogueChooserPanel(catalogues: appState.savedCatalogues)
            .environmentObject(appState)
            .frame(maxWidth: 700)
    }
}

private struct CatalogueChooserPanel: View {
    @EnvironmentObject private var appState: AppState
    let catalogues: [SavedCatalogue]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CatalogueChooserHeader()

            if catalogues.isEmpty {
                EmptyCatalogueChooserState()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Saved Catalogues")
                            .font(.headline)

                        Text("\(catalogues.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.45), in: Capsule())

                        Spacer()
                    }

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(catalogues) { catalogue in
                                SavedCatalogueRow(catalogue: catalogue)
                                    .environmentObject(appState)
                            }
                        }
                        .padding(1)
                    }
                    .frame(maxHeight: 260)
                    .scrollIndicators(.visible)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct CatalogueChooserHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create From Folders")
                        .font(.headline)
                    Text("Pick one or more folders. Originals stay in place; DriveLens stores metadata, thumbnails, and indexes in .drivelens at the storage root.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                CatalogueSetupBadge(title: "Originals unchanged", systemImage: "checkmark.shield")
                CatalogueSetupBadge(title: "Local catalogue", systemImage: "lock.shield")
                CatalogueSetupBadge(title: ".drivelens storage", systemImage: "folder")
            }
        }
    }
}

private struct CatalogueSetupBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

private struct EmptyCatalogueChooserState: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("No saved catalogues")
                    .font(.callout.weight(.semibold))
                Text("Choose folders to create your first private catalogue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SavedCatalogueRow: View {
    @EnvironmentObject private var appState: AppState
    let catalogue: SavedCatalogue
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBackground)
                Image(systemName: statusSystemImage)
                    .font(.title3)
                    .foregroundStyle(iconForeground)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        title
                        badges
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        title
                        badges
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Last opened \(relativeDate)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            Menu {
                Button {
                    Task { await appState.openSavedCatalogue(catalogue) }
                } label: {
                    Label(openTitle, systemImage: catalogue.hasSavedPermission ? "arrow.right.circle" : "lock.open")
                }
                .disabled(!isReachable)

                if catalogue.hasSavedPermission {
                    Button {
                        appState.forgetSavedCatalogue(catalogue)
                    } label: {
                        Label("Forget Saved Pointer", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Catalogue actions")
            .accessibilityLabel("Catalogue actions")

            openButton
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isActive ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            guard isReachable else { return }
            Task { await appState.openSavedCatalogue(catalogue) }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var openButton: some View {
        if isReachable {
            Button {
                Task { await appState.openSavedCatalogue(catalogue) }
            } label: {
                Label(openTitle, systemImage: catalogue.hasSavedPermission ? "arrow.right.circle" : "lock.open")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(actionHelp)
        } else {
            Button {
                Task { await appState.openSavedCatalogue(catalogue) }
            } label: {
                Label(openTitle, systemImage: catalogue.hasSavedPermission ? "arrow.right.circle" : "lock.open")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
            .help(actionHelp)
        }
    }

    private var title: some View {
        Text(catalogue.name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if isActive {
                CatalogueStatusBadge(title: "Active", tint: .accentColor)
            }
            CatalogueStatusBadge(title: storageStatus, tint: isReachable ? .secondary : .orange)
            if hasCatalogue {
                CatalogueStatusBadge(title: catalogue.hasSavedPermission ? "Saved" : "Detected", tint: .secondary)
            }
        }
    }

    private var isReachable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: catalogue.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private var isActive: Bool {
        appState.activeCatalogue?.id == catalogue.id
    }

    private var hasCatalogue: Bool {
        FileManager.default.fileExists(atPath: catalogue.databaseURL.path)
    }

    private var statusSystemImage: String {
        if catalogue.isNamedCatalogue {
            return "rectangle.stack.fill"
        }
        return isReachable ? "externaldrive.fill" : "externaldrive.badge.xmark"
    }

    private var iconForeground: Color {
        if isReachable {
            return isActive ? .white : .accentColor
        }
        return .secondary
    }

    private var iconBackground: Color {
        if isActive {
            return .accentColor
        }
        if isReachable {
            return Color.accentColor.opacity(0.12)
        }
        return Color.secondary.opacity(0.12)
    }

    private var rowBackground: Color {
        if isActive {
            return Color.accentColor.opacity(0.09)
        }
        if isHovering {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.08)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.42)
        }
        return Color.primary.opacity(isHovering ? 0.12 : 0.08)
    }

    private var actionHelp: String {
        if !isReachable {
            return "Connect the storage device to open this catalogue"
        }
        return catalogue.hasSavedPermission ? "Open this saved catalogue" : "Grant macOS permission for this detected catalogue"
    }

    private var openTitle: String {
        catalogue.hasSavedPermission ? "Open" : "Allow Access"
    }

    private var storageStatus: String {
        if !isReachable {
            return "Disconnected"
        }
        if catalogue.isNamedCatalogue {
            return catalogue.path.contains("/.drivelens/catalogues/") ? "Storage Root" : "On Mac"
        }
        return "Legacy"
    }

    private var subtitle: String {
        if catalogue.isNamedCatalogue {
            let count = catalogue.sourceList.count
            if count == 0 {
                return "No folders imported yet"
            }
            let names = catalogue.sourceList.map(\.name).prefix(2).joined(separator: ", ")
            let more = count > 2 ? " and \(count - 2) more" : ""
            return "\(count) imported folder\(count == 1 ? "" : "s"): \(names)\(more)"
        }
        return catalogue.path
    }

    private var relativeDate: String {
        Self.relativeFormatter.localizedString(for: catalogue.lastOpenedAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private struct CatalogueStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct StepIndicator: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.24))
                    .frame(width: index == selectedIndex ? 24 : 7, height: 7)
                    .animation(.snappy(duration: 0.2), value: selectedIndex)
            }
        }
        .accessibilityLabel("Step \(selectedIndex + 1) of \(count)")
    }
}

private struct OnboardingPage {
    let title: String
    let message: String
    let image: String
}
