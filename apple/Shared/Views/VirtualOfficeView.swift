import Observation
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Provider-neutral AI control-room state. Cloud workforce records are authoritative;
/// Paperclip is polled separately as a comparison/fallback and may be offline.
@MainActor @Observable
final class VirtualOffice {
    enum Connection { case connecting, connected, failed(String) }

    var connection: Connection = .connecting
    var companies: [PaperclipCompany] = []
    var companyID = PaperclipSettings.companyID
    var agents: [PaperclipAgent] = []
    var runs: [PaperclipRun] = []
    var activity: [PaperclipActivity] = []
    var issues: [PaperclipIssue] = []
    var workforceAgents: [AIAgentRecord] = []
    var workforceRuns: [AIAgentRunRecord] = []
    var proposals: [AIActionProposalRecord] = []
    var integrations: [IntegrationHealthRecord] = []
    var cloudError: String?
    var isLoadingCloud = true
    var lastUpdated: Date?
    var busyAgentIDs: Set<String> = []

    var names: [String: String] { Dictionary(agents.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }) }

    private static let plannedAgents: [AIAgentRecord] = [
        .init(
            id: "local-bruce", slug: "bruce", name: "Bruce", title: "Chief of Staff", provider: "grok", status: "planned",
            active: false, pilot: false, colour: "#1e3a8a", accessory: "clipboard",
            instructions: "Prepare concise weekday plans and exception summaries. Coordinate the other roles. Never send, purchase, delete, change schedules, alter CRM records or make financial commitments without administrator approval.",
            scheduleLabel: "Weekdays 07:30 and 16:30", currentWork: nil, nextRunAt: nil, lastCheckinAt: nil, lastSuccessAt: nil,
            lastError: nil),
        .init(
            id: "local-stace", slug: "stace", name: "Stace", title: "Live Jobs Controller", provider: "grok",
            status: "setup_required", active: true, pilot: true, colour: "#f97316", accessory: "calendar_headset",
            instructions: "Own live-job visibility and scheduling exceptions. Flag overdue jobs, missing assignments, unpaid deposits, schedule clashes and decisions. Return no more than eight short items or 300 words and ask one clear question when human input is needed. Never contact customers or change CRM records.",
            scheduleLabel: "Weekdays 07:00, then every 30 minutes until 18:00", currentWork: nil, nextRunAt: nil, lastCheckinAt: nil,
            lastSuccessAt: nil, lastError: nil),
        .init(
            id: "local-rodney", slug: "rodney", name: "Rodney", title: "Growth Controller", provider: "grok", status: "planned",
            active: false, pilot: false, colour: "#16a34a", accessory: "quote_sheet",
            instructions: "Own website and MyBuilder leads, quote follow-ups, reviews and referrals. Prepare drafts only. Never send a customer message or commit a price without approval.",
            scheduleLabel: "07:00–21:00, five-minute fallback", currentWork: nil, nextRunAt: nil, lastCheckinAt: nil, lastSuccessAt: nil,
            lastError: nil),
        .init(
            id: "local-derrick", slug: "derrick", name: "Derrick", title: "Finance Controller", provider: "grok", status: "planned",
            active: false, pilot: false, colour: "#0f766e", accessory: "ledger_pound",
            instructions: "Own deposits, balances, invoices, CIS and payroll exceptions, and cash collection. Never move money, issue refunds or alter financial records without approval.",
            scheduleLabel: "Weekdays 09:00 and 15:00; Friday cash report", currentWork: nil, nextRunAt: nil, lastCheckinAt: nil,
            lastSuccessAt: nil, lastError: nil),
        .init(
            id: "local-big-john", slug: "big-john", name: "Big John", title: "Site Readiness Controller", provider: "grok",
            status: "planned", active: false, pilot: false, colour: "#ca8a04", accessory: "hard_hat_hammer",
            instructions: "Own materials, scaffolding, fleet, MOT, suppliers and next-day site readiness. Never place orders or commit supplier spend without approval.",
            scheduleLabel: "Weekdays 06:45 and 15:30", currentWork: nil, nextRunAt: nil, lastCheckinAt: nil, lastSuccessAt: nil,
            lastError: nil),
    ]

    private static let fallbackIntegrations: [IntegrationHealthRecord] = [
        .init(
            id: "local-proline", connector: "proline_mcp", displayName: "ProLine CRM", provider: "proline", status: "available",
            lastCheckedAt: nil, lastSuccessAt: nil, lastError: nil),
        .init(
            id: "local-grok", connector: "grok_bot", displayName: "Grok Bot", provider: "grok", status: "setup_required",
            lastCheckedAt: nil, lastSuccessAt: nil, lastError: nil),
        .init(
            id: "local-paperclip", connector: "paperclip", displayName: "Paperclip fallback", provider: "paperclip", status: "available",
            lastCheckedAt: nil, lastSuccessAt: nil, lastError: nil),
    ]

    func refresh() async {
        do {
            workforceAgents = try await SupabaseService.shared.fetchAIAgents()
            workforceRuns = try await SupabaseService.shared.fetchAIAgentRuns()
            proposals = try await SupabaseService.shared.fetchPendingAIActionProposals()
            integrations = try await SupabaseService.shared.fetchIntegrationHealth()
            cloudError = nil
        } catch {
            if workforceAgents.isEmpty { workforceAgents = Self.plannedAgents }
            if integrations.isEmpty { integrations = Self.fallbackIntegrations }
            cloudError = "The secure AI control room could not be refreshed. Your existing CRM data is still available."
        }
        isLoadingCloud = false
        await refreshPaperclip()
        lastUpdated = .now
    }

    private func refreshPaperclip() async {
        do {
            let companies = try await PaperclipService.companies()
            var companyID = self.companyID
            if !companies.contains(where: { $0.id == companyID }) { companyID = companies.first?.id ?? "" }
            self.companies = companies
            self.companyID = companyID
            guard !companyID.isEmpty else {
                agents = []; runs = []; activity = []; issues = []
                connection = .connected
                return
            }
            // Swift 6 treats sharing one local String across several `async let`
            // calls as a potential data race. These requests are small local calls;
            // perform them in sequence so the iOS target stays strictly Sendable-safe.
            self.agents = try await PaperclipService.agents(company: companyID)
            self.runs = try await PaperclipService.liveRuns(company: companyID)
            self.activity = try await PaperclipService.activity(company: companyID)
            self.issues = try await PaperclipService.openIssues(company: companyID)
            connection = .connected
        } catch {
            connection = .failed("Paperclip is not running or cannot be reached.")
        }
    }

    func select(company: String) {
        companyID = company
        PaperclipSettings.companyID = company
        agents = []; runs = []; activity = []; issues = []
        Task { await refresh() }
    }

    /// Runs a control action with the desk marked busy, then refreshes so the desk updates.
    func control(_ agentID: String, _ action: @Sendable () async throws -> Void) async throws {
        busyAgentIDs.insert(agentID)
        defer {
            busyAgentIDs.remove(agentID)
            Task { await refresh() }
        }
        try await action()
    }

    func run(for agentID: String) -> PaperclipRun? {
        let mine = runs.filter { $0.agentId == agentID }
        return mine.first { $0.status == "running" } ?? mine.first
    }
    func assignedIssues(for agentID: String) -> [PaperclipIssue] { issues.filter { $0.assigneeAgentId == agentID } }
    func currentIssue(for agentID: String) -> PaperclipIssue? {
        let mine = assignedIssues(for: agentID)
        let runIssue = run(for: agentID)?.issueId
        return mine.first { $0.id == runIssue } ?? mine.first { $0.status == "in_progress" }
    }
    func deskState(_ agent: PaperclipAgent) -> DeskState {
        if agent.status == "paused" { return .paused }
        if agent.status == "error" { return .error }
        let latest = run(for: agent.id)
        if latest?.status == "running" || agent.status == "running" { return .working }
        if latest?.status == "queued" { return .queued }
        return .idle
    }

    /// The top of the org chart gets its own office; each of their direct reports heads a room
    /// with everyone below them.
    var rooms: [(name: String, agents: [PaperclipAgent])] {
        let ids = Set(agents.map(\.id))
        let leaders = agents.filter { $0.reportsTo == nil || !ids.contains($0.reportsTo!) }
        func children(_ id: String) -> [PaperclipAgent] { agents.filter { $0.reportsTo == id } }
        func descendants(_ id: String) -> [PaperclipAgent] { children(id).flatMap { [$0] + descendants($0.id) } }

        var rooms: [(name: String, agents: [PaperclipAgent])] = []
        var placed = Set(leaders.map(\.id))
        if !leaders.isEmpty {
            rooms.append((leaders.count == 1 ? "\(leaders[0].displayRole)'s office" : "Leadership", leaders))
        }
        for leader in leaders {
            for head in children(leader.id) {
                let team = ([head] + descendants(head.id)).filter { !placed.contains($0.id) }
                team.forEach { placed.insert($0.id) }
                if !team.isEmpty { rooms.append(("\(head.displayRole) team", team)) }
            }
        }
        let leftovers = agents.filter { !placed.contains($0.id) }
        if !leftovers.isEmpty { rooms.append(("Open plan", leftovers)) }
        return rooms
    }
}

enum DeskState {
    case working, queued, idle, paused, error

    var label: String {
        switch self {
        case .working: "Working"
        case .queued: "Queued"
        case .idle: "Idle"
        case .paused: "Paused"
        case .error: "Needs help"
        }
    }
    var color: Color {
        switch self {
        case .working: .green
        case .queued: .yellow
        case .idle: .gray
        case .paused: .red.opacity(0.7)
        case .error: .red
        }
    }
}

private let proLineOrange = Color(red: 1, green: 0.29, blue: 0.04)

private func formatCents(_ cents: Double) -> String { String(format: "$%.2f", cents / 100) }

private func timeAgo(_ raw: String?) -> String {
    guard let date = PaperclipService.date(raw) else { return "never" }
    let seconds = max(0, Int(Date.now.timeIntervalSince(date)))
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(seconds / 60)m ago" }
    if seconds < 86400 { return "\(seconds / 3600)h ago" }
    return "\(seconds / 86400)d ago"
}

private func avatarColor(_ id: String) -> Color {
    let palette: [Color] = [.orange, .blue, .purple, .green, .pink, .teal, .indigo, .mint]
    let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    return palette[hash % palette.count]
}

private func initials(_ name: String) -> String {
    let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }
    return letters.isEmpty ? "?" : letters.joined()
}

// MARK: - Office

struct VirtualOfficeView: View {
    @Environment(AppState.self) private var appState
    @State private var office = VirtualOffice()
    @State private var selectedAgent: PaperclipAgent?
    @State private var selectedWorkforceAgent: AIAgentRecord?
    @State private var showingSettings = false
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var wide: Bool {
        #if os(macOS)
            true
        #else
            sizeClass == .regular
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controlRoomHeader

                if let cloudError = office.cloudError {
                    Label(cloudError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }

                ControlRoomBoard(
                    approvals: proposalItems,
                    urgent: urgentItems,
                    waiting: waitingItems,
                    money: moneyItems,
                    openLead: appState.openLead)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your AI team").font(.title2.bold())
                        Spacer()
                        Text("\(orderedAgents.filter(\.active).count) active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if office.isLoadingCloud && orderedAgents.isEmpty {
                        ProgressView("Loading the office…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    } else if orderedAgents.isEmpty {
                        ContentUnavailableView(
                            "AI team unavailable", systemImage: "person.3.sequence",
                            description: Text("Only administrators can see the secure workforce control room."))
                    } else {
                        ForEach(orderedAgents) { agent in
                            Button { selectedWorkforceAgent = agent } label: {
                                WorkforceAgentRow(agent: agent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !office.integrations.isEmpty {
                    ConnectorHealthStrip(integrations: office.integrations)
                }

                if appState.isAdmin, !office.workforceRuns.isEmpty {
                    DisclosureGroup("Administrator run history") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(office.workforceRuns.prefix(12)) { run in
                                WorkforceRunRow(run: run, agentName: workforceName(run.agentID))
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                }

                DisclosureGroup("Paperclip fallback") {
                    VStack(alignment: .leading, spacing: 12) {
                        switch office.connection {
                        case .failed(let message):
                            PaperclipOfflineCard(message: message) { showingSettings = true }
                        case .connecting:
                            ProgressView("Checking Paperclip…")
                        case .connected:
                            if office.agents.isEmpty {
                                Text("Paperclip is connected but has no agents in this company.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(office.agents) { agent in
                                    Button { selectedAgent = agent } label: {
                                        HStack {
                                            Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
                                            Text(agent.name).fontWeight(.semibold)
                                            Text(office.deskState(agent).label).foregroundStyle(.secondary)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            }
            .padding()
        }
        .background(Color.gray.opacity(0.06))
        .navigationTitle("Virtual Office")
        .toolbar {
            ToolbarItem {
                Button { Task { await office.refresh() } } label: {
                    Label("Refresh office", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem {
                Button { showingSettings = true } label: {
                    Label("Connection", systemImage: "gearshape")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await office.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .sheet(item: $selectedAgent) { agent in
            AgentDetailSheet(office: office, agentID: agent.id)
        }
        .sheet(item: $selectedWorkforceAgent) { agent in
            WorkforceAgentDetailSheet(
                agent: agent,
                runs: office.workforceRuns.filter { $0.agentID == agent.id },
                integrations: office.integrations)
        }
        .sheet(isPresented: $showingSettings, onDismiss: { Task { await office.refresh() } }) {
            NavigationStack { PaperclipConnectionForm() }
                #if os(macOS)
                    .frame(minWidth: 460, minHeight: 360)
                #endif
        }
    }

    private var orderedAgents: [AIAgentRecord] {
        let order = ["bruce", "stace", "rodney", "derrick", "big-john"]
        return office.workforceAgents.sorted {
            (order.firstIndex(of: $0.slug) ?? 99, $0.name) < (order.firstIndex(of: $1.slug) ?? 99, $1.name)
        }
    }

    private var controlRoomHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            BotAvatar(slug: "stace", size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("Business control room").font(.title.bold())
                Text("Everything needing attention, followed by the bots responsible for it.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let lastUpdated = office.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var proposalItems: [ControlRoomItem] {
        office.proposals.prefix(8).map {
            ControlRoomItem(id: $0.id, title: $0.title, detail: $0.summary, leadID: nil)
        }
    }

    private var urgentItems: [ControlRoomItem] {
        appState.companyActions.filter { $0.priority >= .urgent && ![.deposit, .balance].contains($0.kind) }.prefix(8).map {
            ControlRoomItem(id: $0.id, title: $0.title, detail: "\($0.detail) · \($0.reason)", leadID: $0.leadID)
        }
    }

    private var waitingItems: [ControlRoomItem] {
        let jobs = appState.leads.filter {
            [.won, .scheduled, .inProgress].contains($0.stage) && $0.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map {
            ControlRoomItem(id: "job-\($0.id)", title: "\($0.name) has no owner", detail: "\($0.jobRef) · \($0.stage.displayName)", leadID: $0.id)
        }
        let tasks = appState.visibleGeneralTasks.filter { !$0.completed && $0.assignedTo.isEmpty }.prefix(8).map {
            ControlRoomItem(id: "task-\($0.id)", title: $0.title, detail: "Unassigned · \($0.category)", leadID: nil)
        }
        return Array((jobs + tasks).prefix(8))
    }

    private var moneyItems: [ControlRoomItem] {
        appState.companyActions.filter { [.deposit, .balance].contains($0.kind) }.prefix(8).map {
            ControlRoomItem(id: $0.id, title: $0.title, detail: $0.detail, leadID: $0.leadID)
        }
    }

    private func workforceName(_ id: String) -> String {
        office.workforceAgents.first { $0.id == id }?.name ?? "Agent"
    }
}

private struct ControlRoomItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let leadID: String?
}

private struct ControlRoomBoard: View {
    let approvals: [ControlRoomItem]
    let urgent: [ControlRoomItem]
    let waiting: [ControlRoomItem]
    let money: [ControlRoomItem]
    let openLead: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)], spacing: 14) {
            ControlRoomQueueCard(
                title: "Needs your approval", icon: "checkmark.seal.fill", tint: .purple,
                items: approvals, emptyMessage: "Nothing is waiting for approval.", openLead: openLead)
            ControlRoomQueueCard(
                title: "Urgent today", icon: "exclamationmark.triangle.fill", tint: .red,
                items: urgent, emptyMessage: "No urgent exceptions right now.", openLead: openLead)
            ControlRoomQueueCard(
                title: "Waiting on someone", icon: "person.crop.circle.badge.clock", tint: .orange,
                items: waiting, emptyMessage: "Nothing is stuck or unassigned.", openLead: openLead)
            ControlRoomQueueCard(
                title: "Money to chase", icon: "sterlingsign.circle.fill", tint: .teal,
                items: money, emptyMessage: "No deposits or balances need chasing.", openLead: openLead)
        }
    }
}

private struct ControlRoomQueueCard: View {
    let title: String
    let icon: String
    let tint: Color
    let items: [ControlRoomItem]
    let emptyMessage: String
    let openLead: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12), in: Capsule())
            }
            if items.isEmpty {
                Text(emptyMessage).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(4)) { item in
                    Group {
                        if let leadID = item.leadID {
                            Button { openLead(leadID) } label: { itemRow(item, showsChevron: true) }
                                .buttonStyle(.plain)
                        } else {
                            itemRow(item, showsChevron: false)
                        }
                    }
                    if item.id != items.prefix(4).last?.id { Divider() }
                }
                if items.count > 4 {
                    Text("+ \(items.count - 4) more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.18)))
    }

    private func itemRow(_ item: ControlRoomItem, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if showsChevron { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
    }
}

private struct WorkforceAgentRow: View {
    let agent: AIAgentRecord

    var body: some View {
        HStack(spacing: 14) {
            BotAvatar(slug: agent.slug, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(agent.name).font(.headline)
                    if agent.pilot {
                        Text("PILOT").font(.caption2.bold()).foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(agent.title).font(.subheadline).foregroundStyle(.secondary)
                Text(agent.currentWork ?? defaultWork(agent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 5) {
                AgentStatusPill(status: agent.status)
                Text("Next: \(futureLabel(agent.nextRunAt))")
                Text("Checked in: \(timeAgo(agent.lastCheckinAt))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(botColor(agent.slug).opacity(0.20)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func defaultWork(_ agent: AIAgentRecord) -> String {
        if agent.status == "setup_required" { return "Waiting for the secure Grok Bot connection." }
        if agent.status == "planned" { return "Planned for after Stace passes the five-day pilot." }
        return "Waiting for the next scheduled check."
    }
}

private struct BotAvatar: View {
    let slug: String
    let size: CGFloat

    var body: some View {
        let tint = botColor(slug)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(tint.gradient)
                .frame(width: size, height: size)
            VStack(spacing: size * 0.04) {
                HStack(spacing: size * 0.12) {
                    Circle().fill(.white).frame(width: size * 0.10, height: size * 0.10)
                    Circle().fill(.white).frame(width: size * 0.10, height: size * 0.10)
                }
                Capsule().fill(.white.opacity(0.85)).frame(width: size * 0.30, height: size * 0.06)
                Image(systemName: botAccessory(slug))
                    .font(.system(size: size * 0.20, weight: .bold))
                    .foregroundStyle(.white)
            }
            Capsule().fill(tint).frame(width: size * 0.08, height: size * 0.20).offset(y: -size * 0.55)
            Circle().fill(tint).frame(width: size * 0.16, height: size * 0.16).offset(y: -size * 0.66)
        }
        .frame(width: size, height: size)
        .padding(.top, size * 0.10)
        .accessibilityHidden(true)
    }
}

private struct AgentStatusPill: View {
    let status: String
    var body: some View {
        let tint = agentStatusColor(status)
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(readableStatus(status)).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.11), in: Capsule())
    }
}

private struct ConnectorHealthStrip: View {
    let integrations: [IntegrationHealthRecord]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(integrations) { integration in
                    HStack(spacing: 8) {
                        Circle().fill(integrationColor(integration.status)).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(integration.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(readableStatus(integration.status)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
}

private struct WorkforceRunRow: View {
    let run: AIAgentRunRecord
    let agentName: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(agentStatusColor(run.status)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(agentName) · \(readableStatus(run.status))").font(.subheadline.weight(.semibold))
                Text(run.summary ?? run.error ?? "No summary supplied.").font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            Text(timeAgo(run.startedAt)).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct WorkforceAgentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let agent: AIAgentRecord
    let runs: [AIAgentRunRecord]
    let integrations: [IntegrationHealthRecord]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        BotAvatar(slug: agent.slug, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(agent.title).foregroundStyle(.secondary)
                            AgentStatusPill(status: agent.status)
                            Text(agent.provider.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Current work") {
                    Text(agent.currentWork ?? (agent.status == "planned" ? "Waiting for the Stace pilot to pass." : "Waiting for setup or the next scheduled check."))
                    LabeledContent("Schedule", value: agent.scheduleLabel ?? "Not scheduled")
                    LabeledContent("Next run", value: futureLabel(agent.nextRunAt))
                    LabeledContent("Last check-in", value: timeAgo(agent.lastCheckinAt))
                    if let lastError = agent.lastError { Label(lastError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
                Section("Instructions") {
                    Text(agent.instructions).textSelection(.enabled)
                }
                Section("Safety") {
                    Label("Customer messages require approval", systemImage: "checkmark.shield.fill")
                    Label("Schedule and CRM changes require approval", systemImage: "checkmark.shield.fill")
                    Label("Payments and purchases require approval", systemImage: "checkmark.shield.fill")
                }
                if !runs.isEmpty {
                    Section("Recent check-ins") {
                        ForEach(runs.prefix(12)) { run in WorkforceRunRow(run: run, agentName: agent.name) }
                    }
                }
                if agent.slug == "stace", integrations.first(where: { $0.connector == "grok_bot" })?.status == "setup_required" {
                    Section("Pilot setup") {
                        Label("Grok Bot connection still required", systemImage: "link.badge.plus")
                            .foregroundStyle(.orange)
                        Text("No subscription or API billing has been activated from ProLine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(agent.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(minWidth: 500, minHeight: 620)
        #endif
    }
}

private func botColor(_ slug: String) -> Color {
    switch slug {
    case "bruce": Color(red: 0.12, green: 0.23, blue: 0.54)
    case "stace": .orange
    case "rodney": .green
    case "derrick": .teal
    case "big-john": Color(red: 0.82, green: 0.60, blue: 0.04)
    default: .gray
    }
}

private func botAccessory(_ slug: String) -> String {
    switch slug {
    case "bruce": "list.clipboard.fill"
    case "stace": "calendar.badge.clock"
    case "rodney": "doc.text.fill"
    case "derrick": "sterlingsign.circle.fill"
    case "big-john": "hammer.fill"
    default: "gearshape.fill"
    }
}

private func readableStatus(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}

private func agentStatusColor(_ status: String) -> Color {
    switch status {
    case "running", "succeeded", "connected", "available": .green
    case "setup_required", "partial", "queued": .orange
    case "error", "failed", "degraded": .red
    case "paused": .yellow
    default: .gray
    }
}

private func integrationColor(_ status: String) -> Color { agentStatusColor(status) }

private func futureLabel(_ raw: String?) -> String {
    guard let date = PaperclipService.date(raw) else { return "Not scheduled" }
    if date <= .now { return "Due now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: .now)
}

private struct AgentDeskCard: View {
    let agent: PaperclipAgent
    let state: DeskState
    let currentIssue: PaperclipIssue?

    private var bubble: String {
        if let currentIssue { return currentIssue.title }
        switch state {
        case .working: return "Working on something…"
        case .paused: return "On a break"
        case .error: return "Needs help"
        default: return "Waiting for work"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bubble)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(state == .working ? Color.green.opacity(0.12) : Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(state == .working ? Color.green : Color.secondary)

            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(avatarColor(agent.id)).frame(width: 46, height: 46)
                        .overlay(Text(initials(agent.name)).font(.headline).foregroundStyle(.white))
                        .overlay(Circle().strokeBorder(state.color.opacity(0.6), lineWidth: 3))
                    Circle().fill(state.color).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.background, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name).font(.headline).lineLimit(1)
                    Text(agent.displayRole).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: state == .working ? "desktopcomputer.and.arrow.down" : "desktopcomputer")
                    .foregroundStyle(state == .working ? Color.green : Color.secondary)
                    .symbolEffect(.pulse, isActive: state == .working)
                Text(state.label)
                Spacer()
                Text(timeAgo(agent.lastHeartbeatAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if agent.budgetMonthlyCents > 0 {
                let used = min(1, agent.spentMonthlyCents / agent.budgetMonthlyCents)
                ProgressView(value: used)
                    .tint(used >= 0.9 ? .red : used >= 0.7 ? .yellow : proLineOrange)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct Noticeboard: View {
    let office: VirtualOffice

    var body: some View {
        VStack(spacing: 16) {
            GroupBox("Work board") {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        count("In progress", "in_progress", .green)
                        count("To do", "todo", proLineOrange)
                    }
                    GridRow {
                        count("In review", "in_review", .blue)
                        count("Blocked", "blocked", .red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider().padding(.vertical, 4)
                let spent = office.agents.reduce(0.0) { $0 + $1.spentMonthlyCents }
                let budget = office.agents.reduce(0.0) { $0 + $1.budgetMonthlyCents }
                Text("Spend this month: \(Text(formatCents(spent)).bold())\(budget > 0 ? " of \(formatCents(budget))" : "")")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Office chatter") {
                VStack(alignment: .leading, spacing: 10) {
                    if office.activity.isEmpty {
                        Text("Quiet in here. Nothing has happened yet.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(office.activity.prefix(30)) { entry in
                        ActivityRow(entry: entry, names: office.names)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func count(_ label: String, _ status: String, _ color: Color) -> some View {
        VStack(alignment: .leading) {
            Text("\(office.issues.filter { $0.status == status }.count)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ActivityRow: View {
    let entry: PaperclipActivity
    let names: [String: String]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeAgo(entry.createdAt)).font(.caption2).foregroundStyle(.tertiary).frame(width: 52, alignment: .leading)
            Text(entry.summary(names: names)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct PaperclipOfflineCard: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "wifi.slash")
                .font(.headline)
                .foregroundStyle(.red)
            #if os(macOS)
                Text("Paperclip is not running on this Mac. Start Paperclip, or open Connection settings to use a different address.")
                Text("The Virtual Office reconnects automatically when Paperclip becomes available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            #else
                Text("Your agents run in Paperclip on your Mac. To see them from here, set Paperclip's address to your Mac's network or Tailscale address, and add a board API key.")
            #endif
            Button("Connection settings…", action: openSettings)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Agent detail

private struct AgentDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let office: VirtualOffice
    let agentID: String
    @State private var showingNewTask = false
    @State private var note = ""
    @State private var sending = false
    @State private var confirmation: String?

    private var agent: PaperclipAgent? { office.agents.first { $0.id == agentID } }

    var body: some View {
        NavigationStack {
            if let agent {
                let state = office.deskState(agent)
                let busy = office.busyAgentIDs.contains(agent.id)
                let current = office.currentIssue(for: agent.id) ?? office.assignedIssues(for: agent.id).first
                Form {
                    Section {
                        HStack(spacing: 12) {
                            Circle().fill(avatarColor(agent.id)).frame(width: 48, height: 48)
                                .overlay(Text(initials(agent.name)).font(.headline).foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayRole).foregroundStyle(.secondary)
                                Label { Text("\(state.label) · last check-in \(timeAgo(agent.lastHeartbeatAt))") } icon: {
                                    Circle().fill(state.color).frame(width: 8, height: 8)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    Section {
                        if state == .paused {
                            Button { perform("\(agent.name) is back at work") { try await PaperclipService.resume(agent: $0) } } label: {
                                Label("Resume", systemImage: "play.fill")
                            }
                        } else {
                            Button { perform("\(agent.name) paused") { try await PaperclipService.pause(agent: $0) } } label: {
                                Label("Pause", systemImage: "pause.fill")
                            }
                        }
                        Button { perform("\(agent.name) woken up") { try await PaperclipService.wake(agent: $0) } } label: {
                            Label("Run now", systemImage: "bolt.fill")
                        }
                        .disabled(state == .paused)
                        Button { showingNewTask = true } label: { Label("Give a task", systemImage: "list.bullet.clipboard") }
                    } header: {
                        Text("Controls")
                    } footer: {
                        if let confirmation { Label(confirmation, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .disabled(busy)

                    Section("Doing now") {
                        if let current {
                            VStack(alignment: .leading, spacing: 2) {
                                if let identifier = current.identifier { Text(identifier).font(.caption).foregroundStyle(.secondary) }
                                Text(current.title)
                            }
                            HStack {
                                TextField("Message \(agent.name) about this…", text: $note, axis: .vertical)
                                    .lineLimit(1...4)
                                    .onSubmit { send(to: current.id) }
                                Button { send(to: current.id) } label: {
                                    if sending { ProgressView() } else { Image(systemName: "paperplane.fill") }
                                }
                                .disabled(sending || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            Text("Nothing assigned. Give them a task to get started.").foregroundStyle(.secondary)
                        }
                    }

                    if agent.budgetMonthlyCents > 0 {
                        Section("Budget this month") {
                            LabeledContent("Spent", value: "\(formatCents(agent.spentMonthlyCents)) of \(formatCents(agent.budgetMonthlyCents))")
                        }
                    }

                    Section("Their to-do list") {
                        let mine = office.assignedIssues(for: agent.id)
                        if mine.isEmpty { Text("No open tasks.").foregroundStyle(.secondary) }
                        ForEach(mine) { issue in
                            LabeledContent(issue.title) {
                                Text(issue.status.replacingOccurrences(of: "_", with: " ")).font(.caption)
                            }
                        }
                    }

                    Section("Recent activity") {
                        let mine = office.activity.filter { $0.agentId == agentID || $0.actorId == agentID || $0.entityId == agentID }
                        if mine.isEmpty { Text("No activity yet.").foregroundStyle(.secondary) }
                        ForEach(mine.prefix(20)) { entry in ActivityRow(entry: entry, names: office.names) }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(agent.name)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $showingNewTask) { NewAgentTaskSheet(office: office, agent: agent) }
            } else {
                ContentUnavailableView("Agent not found", systemImage: "person.crop.circle.badge.questionmark")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func perform(_ success: String, _ action: @escaping @Sendable (String) async throws -> Void) {
        let id = agentID
        confirmation = nil
        Task {
            do {
                try await office.control(id) { try await action(id) }
                confirmation = success
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func send(to issueID: String) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await PaperclipService.message(issue: issueID, text: text)
                note = ""
                confirmation = "Message sent"
                await office.refresh()
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct NewAgentTaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let office: VirtualOffice
    let agent: PaperclipAgent
    @State private var title = ""
    @State private var details = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("What should they do?", text: $title, prompt: Text("e.g. Draft follow-ups for this week's roof surveys"))
                TextField("Details (optional)", text: $details, axis: .vertical).lineLimit(4...10)
            }
            .formStyle(.grouped)
            .navigationTitle("Give \(agent.name) a task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") { assign() }
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 300)
        #endif
    }

    private func assign() {
        let company = office.companyID
        let agentID = agent.id
        let taskTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            do {
                try await office.control(agentID) {
                    try await PaperclipService.assignTask(company: company, agent: agentID, title: taskTitle, details: taskDetails)
                }
                dismiss()
            } catch {
                saving = false
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Connection settings

/// Where Paperclip lives and the optional board API key, as a sheet from the office.
struct PaperclipConnectionForm: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form { PaperclipConnectionSection() }
            .formStyle(.grouped)
            .navigationTitle("Virtual Office")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// The connection fields themselves, also shown inline in Settings.
struct PaperclipConnectionSection: View {
    @State private var address = PaperclipSettings.baseURL
    @State private var apiKey = PaperclipSettings.apiKey

    var body: some View {
        Section {
            TextField("Paperclip address", text: $address, prompt: Text(PaperclipSettings.defaultURL))
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
            SecureField("Board API key (only if Paperclip asks you to sign in)", text: $apiKey)
        } header: {
            Text("Virtual Office")
        } footer: {
            Text(
                "Where ProLine finds Paperclip, the app that runs your AI agents. On your Mac, leave it as \(PaperclipSettings.defaultURL). From an iPhone, use your Mac's Tailscale or network address and a board API key from Paperclip."
            )
        }
        .onChange(of: address) { _, value in PaperclipSettings.baseURL = value.isEmpty ? PaperclipSettings.defaultURL : value }
        .onChange(of: apiKey) { _, value in PaperclipSettings.apiKey = value }
    }
}
