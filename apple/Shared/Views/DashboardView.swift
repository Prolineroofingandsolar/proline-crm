import SwiftUI

/// Today: what's booked, then everything that needs chasing, then a short summary.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    private var today: String { SupabaseService.today }

    private var scheduledToday: [Lead] {
        appState.leads
            .filter { $0.surveyDate == today || $0.startDate == today || ($0.stage == .inProgress && ($0.endDate ?? today) >= today) }
            .sorted {
                ($0.surveyDate == today ? ($0.surveyTime ?? "00:00") : "99") < ($1.surveyDate == today ? ($1.surveyTime ?? "00:00") : "99")
            }
    }
    private var openLeads: Int {
        appState.leads.filter { [.newLead, .surveyBooked, .quotePreparing, .quoteSent].contains($0.stage) }.count
    }
    private var liveJobs: Int { appState.leads.filter { [.scheduled, .inProgress].contains($0.stage) }.count }
    private var awaitingPayment: Int { appState.leads.filter { $0.stage == .waitingForPayment }.count }
    private var toCollect: Double { CustomerMoneyPolicy.summary(leads: appState.leads).due }

    var body: some View {
        #if os(macOS)
            macDashboard
        #else
            List {
                scheduleSection
                ActionQueueList()
                Section {
                    LabeledContent("Leads", value: "\(openLeads)")
                    LabeledContent("Live jobs", value: "\(liveJobs)")
                    LabeledContent("To collect", value: toCollect.formatted(.currency(code: "GBP").precision(.fractionLength(0))))
                    NavigationLink { DashboardJobsMap().navigationTitle("Map") } label: { Label("Map", systemImage: "map") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
        #endif
    }

    private var scheduleSection: some View {
        Section {
            if scheduledToday.isEmpty {
                Text("Nothing booked").foregroundStyle(.secondary)
            } else {
                ForEach(scheduledToday) { lead in
                    NavigationLink(value: LeadRoute(id: lead.id)) { scheduleRow(lead) }
                }
            }
        } header: {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        }
    }

    private func scheduleRow(_ lead: Lead) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.name).fontWeight(.medium)
                Text(lead.address.isEmpty ? lead.jobType : lead.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if lead.surveyDate == today {
                Text(lead.surveyTime ?? "Survey").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(lead.stage == .inProgress ? "On site" : "Starts").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    #if os(macOS)
        private var macDashboard: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(.title2.bold())
                            Text("Your schedule, urgent work and business at a glance.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        DashboardMetricCard(title: "Open leads", value: "\(openLeads)", icon: "person.2", tint: .blue)
                        DashboardMetricCard(title: "Live jobs", value: "\(liveJobs)", icon: "hammer", tint: .orange)
                        DashboardMetricCard(
                            title: "Awaiting payment", value: "\(awaitingPayment)", icon: "clock.badge.exclamationmark", tint: .purple)
                        DashboardMetricCard(
                            title: "To collect", value: toCollect.formatted(.currency(code: "GBP").precision(.fractionLength(0))),
                            icon: "sterlingsign.circle", tint: .green)
                    }

                    VStack(spacing: 0) {
                        DashboardCardHeader(
                            title: "Today's schedule", subtitle: scheduledToday.isEmpty ? "No appointments or site visits" : "\(scheduledToday.count) booked",
                            icon: "calendar", tint: .blue)
                        Divider()
                        if scheduledToday.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nothing booked").fontWeight(.medium)
                                    Text("Your day is clear for follow-ups and outstanding work.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(18)
                        } else {
                            ForEach(scheduledToday) { lead in
                                NavigationLink(value: LeadRoute(id: lead.id)) {
                                    scheduleRow(lead)
                                        .padding(.horizontal, 18)
                                        .frame(minHeight: 62)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if lead.id != scheduledToday.last?.id { Divider().padding(.leading, 18) }
                            }
                        }
                    }
                    .dashboardCard()

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Action required").font(.title3.bold())
                            Text("Grouped by urgency so the next job is easy to find.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    ActionQueueList()

                    NavigationLink {
                        DashboardJobsMap().navigationTitle("Map")
                    } label: {
                        Label("Open jobs map", systemImage: "map")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Today")
        }
    #endif
}

#if os(macOS)
    private struct DashboardMetricCard: View {
        let title: String
        let value: String
        let icon: String
        let tint: Color

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.75)
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 70)
            .dashboardCard()
        }
    }

    struct DashboardCardHeader: View {
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color

        var body: some View {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
        }
    }

    extension View {
        fileprivate func dashboardCard() -> some View {
            background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .shadow(color: .black.opacity(0.025), radius: 6, y: 2)
        }
    }
#endif
