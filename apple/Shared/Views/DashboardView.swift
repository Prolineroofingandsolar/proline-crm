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
    private var toCollect: Double { appState.leads.filter { ![.paid, .lost].contains($0.stage) }.reduce(0) { $0 + $1.balance } }

    var body: some View {
        List {
            Section {
                if scheduledToday.isEmpty {
                    Text("Nothing booked").foregroundStyle(.secondary)
                } else {
                    ForEach(scheduledToday) { lead in
                        NavigationLink(value: LeadRoute(id: lead.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lead.name).fontWeight(.medium)
                                    Text(lead.address.isEmpty ? lead.jobType : lead.address).font(.subheadline)
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if lead.surveyDate == today {
                                    Text(lead.surveyTime ?? "Survey").font(.subheadline).foregroundStyle(.secondary)
                                } else {
                                    Text(lead.stage == .inProgress ? "On site" : "Starts").font(.subheadline).foregroundStyle(
                                        .secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            }

            ActionQueueList()

            Section {
                LabeledContent("Leads", value: "\(openLeads)")
                LabeledContent("Live jobs", value: "\(liveJobs)")
                LabeledContent("To collect", value: toCollect.formatted(.currency(code: "GBP").precision(.fractionLength(0))))
                NavigationLink { DashboardJobsMap().navigationTitle("Map") } label: { Label("Map", systemImage: "map") }
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #else
            .listStyle(.inset)
        #endif
        .navigationTitle("Today")
    }
}
