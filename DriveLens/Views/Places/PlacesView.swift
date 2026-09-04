import MapKit
import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var appState: AppState
    let items: [MediaItem]
    let clusters: [PlaceCluster]
    let counts: CatalogueCounts
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 160)
        )
    )

    var body: some View {
        VStack(spacing: 0) {
            PlacesHeader(locatedCount: counts.locatedItems, missingCount: counts.missingLocationItems, clusterCount: clusters.count) {
                zoomToMedia()
            }
            Divider()

            ZStack {
                if clusters.isEmpty {
                    ContentUnavailableView {
                        Label("No GPS information", systemImage: "map")
                    } description: {
                        Text("No indexed media has GPS metadata yet. Timeline and Folders still include every item.")
                    } actions: {
                        Button {
                            appState.requestCatalogueUpdate()
                        } label: {
                            Label("Update Catalogue", systemImage: "arrow.clockwise")
                        }
                        .disabled(!appState.canScan)
                    }
                } else {
                    Map(position: $position) {
                        ForEach(clusters) { cluster in
                            Annotation(cluster.representativeFilename, coordinate: cluster.coordinate, anchor: .bottom) {
                                Button {
                                    select(cluster)
                                } label: {
                                    MapClusterMarker(cluster: cluster, isSelected: cluster.id == appState.selectedPlaceClusterID)
                                }
                                .buttonStyle(.plain)
                                .help("\(cluster.itemCount) items near this location")
                            }
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .mapStyle(.standard(elevation: .flat))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                zoomToMedia()
            }
            .onChange(of: clusters) { _, _ in
                zoomToMedia()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(stripTitle, systemImage: appState.selectedPlaceClusterID == nil ? "photo.stack" : "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(stripCountText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    if appState.selectedPlaceClusterID != nil {
                        Button {
                            Task { await appState.clearPlaceClusterSelection() }
                        } label: {
                            Label("Show All", systemImage: "xmark.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Show all mapped media")
                        .accessibilityLabel("Show all mapped media")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items.prefix(80)) { item in
                            AsyncThumbnailView(item: item)
                                .environmentObject(appState)
                                .frame(width: 84, height: 84)
                                .onTapGesture(count: 2) {
                                    appState.selectedMediaItem = item
                                    appState.showingViewer = true
                                }
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        appState.selectedMediaItem = item
                                    }
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(height: 128)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Places")
    }

    private var selectedCluster: PlaceCluster? {
        guard let selectedPlaceClusterID = appState.selectedPlaceClusterID else { return nil }
        return clusters.first { $0.id == selectedPlaceClusterID }
    }

    private var stripTitle: String {
        guard appState.selectedPlaceClusterID != nil else { return "Mapped Media" }

        if let place = items.first?.placeText, !place.isEmpty {
            return place
        }

        return "Selected Location"
    }

    private var stripCountText: String {
        if let selectedCluster {
            return "\(items.prefix(80).count) of \(selectedCluster.itemCount) shown"
        }

        return "\(items.prefix(80).count) shown"
    }

    private func select(_ cluster: PlaceCluster) {
        focus(cluster)
        Task {
            await appState.selectPlaceCluster(cluster)
        }
    }

    private func focus(_ cluster: PlaceCluster) {
        withAnimation(.easeInOut(duration: 0.22)) {
            position = .region(
                MKCoordinateRegion(
                    center: cluster.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                )
            )
        }
    }

    private func zoomToMedia() {
        guard !clusters.isEmpty else { return }

        var rect = MKMapRect.null
        for cluster in clusters {
            let point = MKMapPoint(cluster.coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.union(pointRect)
        }

        let paddedRect = rect.insetBy(dx: -max(rect.width * 0.18, 50_000), dy: -max(rect.height * 0.18, 50_000))
        withAnimation(.easeInOut(duration: 0.28)) {
            position = .rect(paddedRect)
        }
    }
}

private struct PlacesHeader: View {
    let locatedCount: Int
    let missingCount: Int
    let clusterCount: Int
    let zoomToMedia: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    titleBlock
                    Spacer()
                    actions
                    metrics
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        titleBlock
                        Spacer()
                        actions
                    }
                    metrics
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Places", systemImage: "map")
                .font(.title2.weight(.semibold))
            Text(locatedCount == 0 ? "No mapped media yet" : "\(clusterCount) location cluster\(clusterCount == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        Button {
            zoomToMedia()
        } label: {
            Label("Zoom to Media", systemImage: "scope")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(locatedCount == 0)
        .help("Zoom map to all mapped media")
        .accessibilityLabel("Zoom map to media")
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            HeaderCountPill(systemImage: "mappin.and.ellipse", value: locatedCount, label: "Mapped")
            HeaderCountPill(systemImage: "location.slash", value: missingCount, label: "No Location")
        }
    }
}

private struct HeaderCountPill: View {
    let systemImage: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct MapClusterMarker: View {
    let cluster: PlaceCluster
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "photo.stack.fill")
            Text(shortCount(cluster.itemCount))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: isSelected ? Color.accentColor.opacity(0.28) : .clear, radius: 8, y: 2)
    }

    private func shortCount(_ value: Int) -> String {
        if value >= 1_000 {
            return "\(value / 1_000)K"
        }
        return "\(value)"
    }
}

private extension PlaceCluster {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
