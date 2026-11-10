import SwiftUI

/// Today: what's booked, then everything that needs chasing, then a short summary.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var botAgents: [AIAgentRecord] = []
    @State private var botRuns: [AIAgentRunRecord] = []
    @State private var loadingBots = false
    @State private var botError = false
    @State private var assistantRequest = ""
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
            macDashboard.task { await loadBotUpdates() }
        #else
            List {
                Section("Ask ProLine Assistant") { assistantInput }
                if appState.isAdmin { botUpdatesSection }
                ActionQueueList()
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .task { await loadBotUpdates() }
        #endif
    }

    private var assistantInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type what you need, such as a task or a job update.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom) {
                TextField("e.g. Add a task to call John tomorrow", text: $assistantRequest, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder).onSubmit(openAssistant)
                Button("Ask") { openAssistant() }
                    .disabled(assistantRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func openAssistant() {
        let prompt = assistantRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        appState.assistantDraftPrompt = prompt
        assistantRequest = ""
        appState.showingAssistant = true
    }

    private var latestBotRuns: [AIAgentRunRecord] {
        let agentIDs = Set(botAgents.filter { $0.provider.lowercased() == "grok" }.map(\.id))
        var seen = Set<String>()
        return botRuns.filter { agentIDs.contains($0.agentID) && ["succeeded", "partial"].contains($0.status) && seen.insert($0.agentID).inserted }
    }

    private func loadBotUpdates() async {
        guard appState.isAdmin, !loadingBots else { return }
        loadingBots = true
        defer { loadingBots = false }
        do {
            async let agents = SupabaseService.shared.fetchAIAgents()
            async let runs = SupabaseService.shared.fetchAIAgentRuns()
            (botAgents, botRuns) = try await (agents, runs)
            botError = false
        } catch { botError = true }
    }

    private var botUpdatesSection: some View {
        Section {
            if loadingBots && botRuns.isEmpty {
                ProgressView("Loading bot updates…")
            } else if botError && botRuns.isEmpty {
                Text("Bot updates could not be loaded. Your CRM tasks are still below.").foregroundStyle(.secondary)
            } else if latestBotRuns.isEmpty {
                Text("No bot updates received yet. Your CRM tasks are below.").foregroundStyle(.secondary)
            } else {
                ForEach(latestBotRuns) { run in botRun(run) }
                if botError { Text("Couldn't refresh; showing the last loaded updates.").font(.caption).foregroundStyle(.secondary) }
            }
            Button { Task { await loadBotUpdates() } } label: { Label("Refresh bot updates", systemImage: "arrow.clockwise") }
                .disabled(loadingBots)
        } header: {
            Text("Grok Bot updates")
        } footer: {
            Text("Bot suggestions are separate from saved CRM tasks. Check the update time before acting.")
        }
    }

    private func botRun(_ run: AIAgentRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            let name = botAgents.first(where: { $0.id == run.agentID })?.name ?? "Grok Bot"
            Text(name).font(.headline)
            Text("Updated \(CRMFormat.addedAt(run.finishedAt ?? run.startedAt))")
                .font(.caption).foregroundStyle(.secondary)
            if let summary = run.summary, !summary.isEmpty { Text(summary).font(.subheadline) }
            ForEach(Array((run.items ?? []).enumerated()), id: \.offset) { _, item in
                if let title = item.title, !title.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(title, systemImage: "circle")
                        if let detail = item.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    }
                } else if let detail = item.detail, !detail.isEmpty {
                    Label(detail, systemImage: "circle")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
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
                            Text("Your priorities and updates for the day.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if appState.isAdmin {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Grok Bot updates", systemImage: "sparkles").font(.headline)
                                Spacer()
                                Button { Task { await loadBotUpdates() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                                    .disabled(loadingBots)
                            }
                            if loadingBots && botRuns.isEmpty { ProgressView("Loading bot updates…") }
                            else if botError && botRuns.isEmpty { Text("Bot updates could not be loaded.").foregroundStyle(.secondary) }
                            else if latestBotRuns.isEmpty { Text("No bot updates received yet.").foregroundStyle(.secondary) }
                            else { ForEach(latestBotRuns) { run in botRun(run); Divider() } }
                            if botError && !botRuns.isEmpty { Text("Couldn't refresh; showing last loaded updates.").font(.caption).foregroundStyle(.secondary) }
                            Text("Bot suggestions are separate from saved CRM tasks. Check the update time before acting.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(18).dashboardCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Ask ProLine Assistant", systemImage: "text.bubble").font(.headline)
                        assistantInput
                    }.padding(18).dashboardCard()

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
