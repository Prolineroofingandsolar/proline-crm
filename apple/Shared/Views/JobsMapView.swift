import MapKit
import SwiftUI

struct DashboardJobsMap: View {
    @Environment(AppState.self) private var appState
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: String?
    @State private var locating = false
    @State private var attemptedAutomaticLocation = false
    @State private var failedCount = 0

    private var records: [Lead] {
        appState.leads.filter {
            let hasAddress = !$0.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let upcomingSurvey = $0.stage == .surveyBooked && ($0.surveyDate ?? "") >= SupabaseService.today
            let operationalJob = $0.stage == .scheduled || $0.stage == .inProgress
            return hasAddress && (upcomingSurvey || operationalJob)
        }
    }
    private var mapped: [Lead] { records.filter { $0.lat != nil && $0.lng != nil } }
    private var missing: [Lead] { records.filter { $0.lat == nil || $0.lng == nil } }
    private var selectedLead: Lead? { mapped.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ZStack(alignment: .topTrailing) {
                map
                VStack(alignment: .trailing, spacing: 10) {
                    stats
                    #if os(macOS)
                        if let lead = selectedLead { jobPanel(lead).frame(width: 330) }
                    #endif
                }.padding(14)
            }
            #if os(iOS)
                if let lead = selectedLead { jobPanel(lead).padding(12) }
            #endif
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            guard !attemptedAutomaticLocation else { return }
            attemptedAutomaticLocation = true
            if !missing.isEmpty { await locateMissing() }
        }
    }

    private var header: some View {
        #if os(macOS)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Upcoming work map").font(.headline)
                    Text("Booked surveys, scheduled work and jobs currently on site.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if locating { ProgressView().controlSize(.small) }
                Button {
                    Task { await locateMissing() }
                } label: {
                    Label(missing.isEmpty ? "All addresses located" : "Locate \(missing.count) missing", systemImage: "mappin.and.ellipse")
                }.disabled(locating || missing.isEmpty)
                Button {
                    openRoute()
                } label: {
                    Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                }.disabled(mapped.isEmpty)
            }
            .padding(14)
            .overlay(alignment: .bottom) { Divider() }
        #else
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("Upcoming work map").font(.headline)
                    Spacer(minLength: 8)
                    Button {
                        openRoute()
                    } label: {
                        Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(mapped.isEmpty)
                }
                Text("Booked surveys and upcoming or active jobs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if locating {
                    Label {
                        Text("Locating addresses…")
                    } icon: {
                        ProgressView().controlSize(.mini)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else if !missing.isEmpty {
                    Button {
                        Task { await locateMissing() }
                    } label: {
                        Label("Locate \(missing.count) missing address\(missing.count == 1 ? "" : "es")", systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                } else {
                    Label("Addresses ready", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            .padding(14)
            .overlay(alignment: .bottom) { Divider() }
        #endif
    }

    private var map: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(mapped) { lead in
                Marker(
                    lead.name, systemImage: markerIcon(lead), coordinate: CLLocationCoordinate2D(latitude: lead.lat!, longitude: lead.lng!)
                )
                .tint(markerTint(lead)).tag(lead.id)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControls {
            MapCompass(); MapScaleView(); MapPitchToggle(); MapUserLocationButton()
        }
        .frame(height: mapHeight)
    }

    private var mapHeight: CGFloat {
        #if os(macOS)
            430
        #else
            320
        #endif
    }

    private var stats: some View {
        #if os(macOS)
            HStack(spacing: 12) {
                Label("\(mapped.filter { $0.stage == .surveyBooked }.count) surveys", systemImage: "ruler")
                    .foregroundStyle(Color.accentColor)
                Label("\(mapped.filter { $0.stage == .scheduled }.count) upcoming", systemImage: "calendar.badge.clock")
                    .foregroundStyle(.blue)
                Label("\(mapped.filter { $0.stage == .inProgress }.count) active", systemImage: "hammer.fill")
                    .foregroundStyle(.red)
                if failedCount > 0 { Text("\(failedCount) not found").foregroundStyle(Color.accentColor) }
            }
            .font(.caption.bold()).padding(9).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8)).shadow(radius: 4)
        #else
            HStack(spacing: 14) {
                compactStat(mapped.filter { $0.stage == .surveyBooked }.count, "ruler", Color.accentColor)
                compactStat(mapped.filter { $0.stage == .scheduled }.count, "calendar.badge.clock", .blue)
                compactStat(mapped.filter { $0.stage == .inProgress }.count, "hammer.fill", .red)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.ultraThickMaterial, in: Capsule()).shadow(radius: 4)
        #endif
    }

    #if os(iOS)
        private func compactStat(_ count: Int, _ icon: String, _ tint: Color) -> some View {
            Label("\(count)", systemImage: icon).font(.caption.bold()).foregroundStyle(tint)
        }
    #endif

    private func jobPanel(_ lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(lead.name).font(.headline);
                    Text("\(lead.jobRef) · \(lead.stage.displayName)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer();
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain)
            }
            Label(lead.address, systemImage: "mappin").font(.subheadline).lineLimit(2)
            HStack {
                Text(lead.jobType); Spacer(); Text(lead.value, format: .currency(code: "GBP")).fontWeight(.semibold)
            }.font(.subheadline)
            HStack {
                Button {
                    openDirections(to: lead)
                } label: {
                    Label("Directions", systemImage: "car")
                }.buttonStyle(.borderedProminent)
                NavigationLink {
                    LeadDetailView(leadID: lead.id)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }.buttonStyle(.bordered)
            }
        }
        .padding(15).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12)).shadow(
            color: .black.opacity(0.15), radius: 10, y: 4)
    }

    @MainActor
    private func locateMissing() async {
        guard !locating else { return }
        let targets = missing
        locating = true; failedCount = 0
        for lead in targets {
            if let coordinate = await geocode(lead.address) {
                var changed = lead; changed.lat = coordinate.latitude; changed.lng = coordinate.longitude
                await appState.saveLead(changed)
            } else {
                failedCount += 1
            }
        }
        locating = false; camera = .automatic
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = address + ", United Kingdom"; request.resultTypes = .address
        return try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate
    }

    private func openDirections(to lead: Lead) {
        guard let lat = lead.lat, let lng = lead.lng else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)));
        item.name = "\(lead.name) · \(lead.jobRef)"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openRoute() {
        let stops = mapped.prefix(10).map { lead -> MKMapItem in
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lead.lat!, longitude: lead.lng!)));
            item.name = lead.name; return item
        }
        MKMapItem.openMaps(
            with: [MKMapItem.forCurrentLocation()] + stops,
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func markerIcon(_ lead: Lead) -> String {
        lead.stage == .surveyBooked ? "ruler" : (lead.stage == .inProgress ? "hammer.fill" : "calendar.badge.clock")
    }
    private func markerTint(_ lead: Lead) -> Color {
        switch lead.stage {
        case .surveyBooked: Color.accentColor;
        case .inProgress: .red;
        case .scheduled: .blue;
        default: .gray
        }
    }
}
