import Observation
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Live state of the user's Paperclip agents, polled while the Virtual Office is open.
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
    var lastUpdated: Date?
    var busyAgentIDs: Set<String> = []

    var names: [String: String] { Dictionary(agents.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }) }

    func refresh() async {
        do {
            let companies = try await PaperclipService.companies()
            var companyID = self.companyID
            if !companies.contains(where: { $0.id == companyID }) { companyID = companies.first?.id ?? "" }
            self.companies = companies
            self.companyID = companyID
            guard !companyID.isEmpty else {
                agents = []; runs = []; activity = []; issues = []
                connection = .connected
                lastUpdated = .now
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
            lastUpdated = .now
        } catch {
            connection = .failed(error.localizedDescription)
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

// MARK: - Native ProLine workforce control room

@MainActor @Observable
final class WorkforceOffice {
    enum Connection { case connecting, connected, failed(String) }

    var connection: Connection = .connecting
    var agents: [WorkforceAgent] = []
    var runs: [WorkforceRun] = []
    var proposals: [WorkforceProposal] = []
    var connectors: [WorkforceConnector] = []
    var acceptance: [WorkforceAcceptance] = []
    var actions: [WorkforceAction] = []
    var settings: WorkforceSettings?
    var busyAgentIDs: Set<String> = []
    var busyProposalIDs: Set<String> = []
    var lastUpdated: Date?

    func refresh() async {
        do {
            agents = try await SupabaseService.shared.fetchWorkforceAgents()
            runs = try await SupabaseService.shared.fetchWorkforceRuns()
            proposals = try await SupabaseService.shared.fetchWorkforceProposals()
            connectors = try await SupabaseService.shared.fetchWorkforceConnectors()
            acceptance = try await SupabaseService.shared.fetchWorkforceAcceptance()
            actions = try await SupabaseService.shared.fetchWorkforceActions()
            settings = try await SupabaseService.shared.fetchWorkforceSettings()
            connection = .connected
            lastUpdated = .now
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    func latestRun(for agentID: String) -> WorkforceRun? { runs.first { $0.agentId == agentID } }
    func gate(for agentID: String) -> WorkforceAcceptance? { acceptance.first { $0.agentId == agentID } }
    func name(for agentID: String) -> String { agents.first { $0.id == agentID }?.name ?? "AI agent" }

    func run(_ agent: WorkforceAgent) async throws {
        busyAgentIDs.insert(agent.id)
        defer { busyAgentIDs.remove(agent.id) }
        _ = try await SupabaseService.shared.runWorkforceAgent(id: agent.id)
        await refresh()
    }

    func review(_ proposal: WorkforceProposal, approved: Bool) async throws {
        busyProposalIDs.insert(proposal.id)
        defer { busyProposalIDs.remove(proposal.id) }
        _ = try await SupabaseService.shared.reviewWorkforceProposal(id: proposal.id, approved: approved)
        await refresh()
    }
}

struct VirtualOfficeView: View {
    @Environment(AppState.self) private var appState
    @State private var office = WorkforceOffice()
    @State private var selectedAgent: WorkforceAgent?
    @State private var showingUsage = false
    @State private var showingFallback = false

    private var pending: [WorkforceProposal] { office.proposals.filter { $0.status == "pending" } }
    private var urgent: [WorkforceRun] {
        office.runs.filter { $0.status == "failed" || $0.status == "partial" }.prefix(8).map { $0 }
    }
    private var waiting: [WorkforceAgent] {
        office.agents.filter { $0.status == "degraded" || $0.status == "error" || ($0.active && $0.lastCheckinAt == nil) }
    }
    private var money: [WorkforceProposal] { pending.filter { $0.category == "finance" || $0.category == "purchase" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controlHeader
                switch office.connection {
                case .connecting where office.agents.isEmpty:
                    ProgressView("Opening your AI office…").frame(maxWidth: .infinity).padding(.top, 80)
                case .failed(let message):
                    ContentUnavailableView(
                        "Control room is not ready", systemImage: "exclamationmark.triangle",
                        description: Text(message))
                default:
                    decisionBoard
                    if !pending.isEmpty { approvalQueue }
                    agentGrid
                    connectorStrip
                    evidenceLog
                }
            }
            .padding()
        }
        .background(Color.gray.opacity(0.06))
        .navigationTitle("AI Workforce")
        .toolbar {
            ToolbarItem { Button { showingUsage = true } label: { Label("Usage", systemImage: "gauge.with.dots.needle.50percent") } }
            ToolbarItem { Button { Task { await office.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            ToolbarItem { Button { showingFallback = true } label: { Label("Paperclip fallback", systemImage: "lifepreserver") } }
        }
        .task {
            while !Task.isCancelled {
                await office.refresh()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .sheet(item: $selectedAgent) { agent in
            WorkforceAgentSheet(office: office, agent: agent)
        }
        .sheet(isPresented: $showingUsage) {
            WorkforceUsageSheet(office: office)
        }
        .sheet(isPresented: $showingFallback) {
            NavigationStack { PaperclipConnectionForm() }
                #if os(macOS)
                    .frame(minWidth: 460, minHeight: 360)
                #endif
        }
    }

    private var controlHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(proLineOrange.gradient)
                Image(systemName: "building.2.crop.circle.fill").font(.title).foregroundStyle(.white)
            }.frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("ProLine control room").font(.title2.bold())
                Text("The bots run in the cloud. Closing this Mac does not stop a correctly connected Grok routine.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(office.settings?.autoTopupEnabled == false ? "Paid top-ups off" : "Check top-ups", systemImage: "creditcard")
                    Label("Paperclip fallback \(office.settings?.paperclipFallbackEnabled == true ? "on" : "off")", systemImage: "lifepreserver")
                    Label("Reports: max \(office.settings?.maxReportItems ?? 8) items", systemImage: "text.badge.checkmark")
                }.font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text((office.settings?.targetPlan ?? "premium").capitalized).font(.headline)
                Text(office.settings?.weeklyUsagePercent.map { "\(Int($0))% this week" } ?? "Usage not measured")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
    }

    private var decisionBoard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            WorkforceQueueCard(title: "Needs your approval", icon: "checkmark.shield", colour: .orange,
                rows: pending.map { $0.title }, empty: "Nothing waiting")
            WorkforceQueueCard(title: "Urgent today", icon: "exclamationmark.triangle", colour: .red,
                rows: urgent.compactMap(\.summary), empty: "No new urgent exceptions")
            WorkforceQueueCard(title: "Waiting on someone", icon: "person.crop.circle.badge.clock", colour: .blue,
                rows: waiting.map { "\($0.name): \($0.lastError ?? $0.currentWork ?? "waiting for first check-in")" }, empty: "Nobody is blocked")
            WorkforceQueueCard(title: "Money to chase", icon: "sterlingsign.circle", colour: .teal,
                rows: money.map { $0.title }, empty: "No payment proposal waiting")
        }
    }

    private var agentGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR TEAM").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 12)], spacing: 12) {
                ForEach(office.agents.sorted { (office.gate(for: $0.id)?.activationOrder ?? 99) < (office.gate(for: $1.id)?.activationOrder ?? 99) }) { agent in
                    Button { selectedAgent = agent } label: {
                        WorkforceAgentCard(agent: agent, run: office.latestRun(for: agent.id), gate: office.gate(for: agent.id))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var approvalQueue: some View {
        GroupBox("Approval queue") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Approval records your decision; it does not send, purchase, pay, delete or change a live schedule automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(pending.prefix(8)) { proposal in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(proposal.title).font(.headline)
                            Spacer()
                            Text(proposal.riskLevel.uppercased()).font(.caption2.bold())
                                .foregroundStyle(proposal.riskLevel == "critical" || proposal.riskLevel == "high" ? Color.red : Color.orange)
                        }
                        Text(proposal.summary).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Label(office.name(for: proposal.agentId), systemImage: "sparkles")
                            Spacer()
                            Button("Reject", role: .destructive) { review(proposal, approved: false) }
                            Button("Approve proposal") { review(proposal, approved: true) }.buttonStyle(.borderedProminent)
                        }.font(.caption)
                    }
                    .padding(12).background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .disabled(office.busyProposalIDs.contains(proposal.id))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func review(_ proposal: WorkforceProposal, approved: Bool) {
        Task {
            do { try await office.review(proposal, approved: approved) }
            catch { appState.errorMessage = error.localizedDescription }
        }
    }

    private var connectorStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTORS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(office.connectors) { connector in
                        Label(connector.displayName, systemImage: connector.status == "connected" || connector.status == "available" ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(connector.status == "connected" || connector.status == "available" ? Color.green : Color.orange)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.background, in: Capsule()).overlay(Capsule().strokeBorder(.quaternary))
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private var evidenceLog: some View {
        GroupBox("Evidence-backed activity") {
            VStack(alignment: .leading, spacing: 10) {
                if office.actions.isEmpty { Text("No bot has changed an internal note or task yet.").foregroundStyle(.secondary) }
                ForEach(office.actions.prefix(12)) { action in
                    HStack(alignment: .firstTextBaseline) {
                        Text(office.name(for: action.agentId)).font(.caption.weight(.semibold)).frame(width: 72, alignment: .leading)
                        Text(action.summary).font(.subheadline)
                        Spacer()
                        Text(timeAgo(action.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WorkforceQueueCard: View {
    let title: String
    let icon: String
    let colour: Color
    let rows: [String]
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(colour)
            if rows.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { _, row in
                Text(row).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(14).frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colour.opacity(0.2)))
    }
}

private struct WorkforceAgentCard: View {
    let agent: WorkforceAgent
    let run: WorkforceRun?
    let gate: WorkforceAcceptance?

    private var colour: Color { Color(hexString: agent.colour) ?? .gray }
    private var symbol: String {
        switch agent.slug {
        case "bruce": "clipboard.fill"
        case "stace": "calendar.badge.clock"
        case "rodney": "chart.line.uptrend.xyaxis"
        case "derrick": "sterlingsign.circle.fill"
        case "big-john": "hammer.fill"
        default: "sparkles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(colour.gradient)
                    Image(systemName: symbol).font(.title2).foregroundStyle(.white)
                }.frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name).font(.headline)
                    Text(agent.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text((gate?.gateStatus ?? "planned").replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(colour.opacity(0.12), in: Capsule()).foregroundStyle(colour)
            }
            Text(agent.currentWork ?? run?.summary ?? (agent.active ? "Ready for the next cloud check" : "Locked until the previous pilot passes"))
                .font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Label(agent.status.capitalized, systemImage: agent.active ? "cloud.fill" : "lock.fill")
                Spacer()
                Text(agent.nextRunAt.map { "Next \(timeAgoFuture($0))" } ?? "No run booked")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(agent.active ? colour.opacity(0.45) : Color.gray.opacity(0.18)))
    }
}

private struct WorkforceAgentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let office: WorkforceOffice
    let agent: WorkforceAgent
    @State private var saving = false
    @State private var remote = false
    @State private var correctOrg = false
    @State private var duplicateFree = false
    @State private var boundaries = false
    @State private var concise = false

    private var gate: WorkforceAcceptance? { office.gate(for: agent.id) }
    private var checks: WorkforceAcceptanceChecks? {
        guard gate != nil else { return nil }
        var value = WorkforceAcceptanceChecks(gate!)
        value.remoteRunConfirmed = remote; value.correctOrganisationConfirmed = correctOrg
        value.duplicateFreeConfirmed = duplicateFree; value.approvalBoundariesConfirmed = boundaries
        value.conciseReportsConfirmed = concise
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    Text(agent.instructions)
                    if let schedule = agent.scheduleLabel { LabeledContent("Schedule", value: schedule) }
                    LabeledContent("Provider", value: agent.provider.capitalized)
                }
                Section("Controls") {
                    Button { runNow() } label: {
                        if office.busyAgentIDs.contains(agent.id) { ProgressView() } else { Label("Run a cloud check now", systemImage: "bolt.fill") }
                    }.disabled(!agent.active || office.busyAgentIDs.contains(agent.id))
                    if !agent.active && gate?.gateStatus == "ready" {
                        Button("Activate five-day pilot") { activate() }
                    }
                    if !agent.active && gate?.gateStatus != "ready" {
                        Label("Locked until the previous agent passes", systemImage: "lock.fill").foregroundStyle(.secondary)
                    }
                }
                if gate?.gateStatus == "pilot" {
                    Section {
                        Toggle("Runs while the Mac is off", isOn: $remote)
                        Toggle("Uses the correct ProLine organisation", isOn: $correctOrg)
                        Toggle("Does not duplicate alerts", isOn: $duplicateFree)
                        Toggle("Respects approval boundaries", isOn: $boundaries)
                        Toggle("Reports stay short and clear", isOn: $concise)
                        Button("Save checks") { saveGate(finalize: false) }
                        Button("Pass pilot and unlock next bot") { saveGate(finalize: true) }
                            .disabled(checks?.allPassed != true)
                    } header: {
                        Text("Five-day acceptance gate")
                    } footer: {
                        Text("ProLine also verifies five separate successful business days before this bot can pass.")
                    }
                }
                if let run = office.latestRun(for: agent.id) {
                    Section("Latest check-in") {
                        Text(run.summary ?? run.error ?? "No summary")
                        LabeledContent("Items", value: "\(run.itemCount) of 8 maximum")
                        LabeledContent("Status", value: run.status.capitalized)
                    }
                }
            }.formStyle(.grouped).navigationTitle(agent.name)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear {
                    guard let gate else { return }
                    remote = gate.remoteRunConfirmed; correctOrg = gate.correctOrganisationConfirmed
                    duplicateFree = gate.duplicateFreeConfirmed; boundaries = gate.approvalBoundariesConfirmed
                    concise = gate.conciseReportsConfirmed
                }
        }
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private func runNow() {
        Task { do { try await office.run(agent) } catch { appState.errorMessage = error.localizedDescription } }
    }
    private func activate() {
        Task { do { _ = try await SupabaseService.shared.activateWorkforceAgent(id: agent.id); await office.refresh() }
            catch { appState.errorMessage = error.localizedDescription } }
    }
    private func saveGate(finalize: Bool) {
        guard let checks else { return }
        saving = true
        Task { defer { saving = false }; do {
            _ = try await SupabaseService.shared.updateWorkforceAcceptance(agentID: agent.id, checks: checks, finalize: finalize)
            await office.refresh()
        } catch { appState.errorMessage = error.localizedDescription } }
    }
}

private struct WorkforceUsageSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let office: WorkforceOffice
    @State private var usage = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Weekly Grok usage") {
                    TextField("Percentage used", text: $usage, prompt: Text("e.g. 42"))
                    Text(WorkforcePolicy.usageAdvice(percent: Double(usage) ?? office.settings?.weeklyUsagePercent))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Cost controls") {
                    Label("Automatic paid top-ups are recorded as off", systemImage: "checkmark.shield.fill")
                    Text("ProLine never buys a plan or enables API billing from this screen.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).navigationTitle("Usage check")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving || Double(usage) == nil) }
                }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 320)
        #endif
    }
    private func save() {
        guard let value = Double(usage), 0...100 ~= value else { return }
        saving = true
        Task { defer { saving = false }; do {
            _ = try await SupabaseService.shared.recordWorkforceUsage(percent: value)
            await office.refresh(); dismiss()
        } catch { appState.errorMessage = error.localizedDescription } }
    }
}

private func timeAgoFuture(_ raw: String) -> String {
    guard let date = PaperclipService.date(raw) else { return "soon" }
    let seconds = Int(date.timeIntervalSinceNow)
    if seconds <= 0 { return "now" }
    if seconds < 3600 { return "in \(max(1, seconds / 60))m" }
    if seconds < 86_400 { return "in \(seconds / 3600)h" }
    return "in \(seconds / 86_400)d"
}

private extension Color {
    init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}

// MARK: - Paperclip fallback

private struct PaperclipOfficeView: View {
    @State private var office = VirtualOffice()
    @State private var selectedAgent: PaperclipAgent?
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
                switch office.connection {
                case .failed(let message):
                    PaperclipOfflineCard(message: message) { showingSettings = true }
                case .connecting where office.agents.isEmpty:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                default:
                    if office.agents.isEmpty {
                        ContentUnavailableView(
                            "The office is empty", systemImage: "building.2",
                            description: Text("Hire your first agent in Paperclip and they'll appear here at their desk."))
                    } else {
                        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 20)) : AnyLayout(VStackLayout(spacing: 20))
                        layout {
                            VStack(spacing: 20) {
                                ForEach(Array(office.rooms.enumerated()), id: \.offset) { _, room in roomView(room.name, room.agents) }
                            }
                            .frame(maxWidth: .infinity)
                            Noticeboard(office: office)
                                .frame(maxWidth: wide ? 300 : .infinity)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.gray.opacity(0.06))
        .navigationTitle("Virtual Office")
        .toolbar {
            ToolbarItem { statusPill }
            if office.companies.count > 1 {
                ToolbarItem {
                    Menu {
                        ForEach(office.companies) { company in
                            Button(company.name) { office.select(company: company.id) }
                        }
                    } label: {
                        Label(office.companies.first { $0.id == office.companyID }?.name ?? "Company", systemImage: "building.2")
                    }
                }
            }
            ToolbarItem {
                Button { Task { await office.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            ToolbarItem {
                Button { showingSettings = true } label: { Label("Connection", systemImage: "gearshape") }
            }
            if let url = URL(string: PaperclipSettings.baseURL) {
                ToolbarItem {
                    Link(destination: url) { Label("Open Paperclip", systemImage: "arrow.up.right.square") }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await office.refresh()
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .sheet(item: $selectedAgent) { agent in
            AgentDetailSheet(office: office, agentID: agent.id)
        }
        .sheet(isPresented: $showingSettings, onDismiss: { Task { await office.refresh() } }) {
            NavigationStack { PaperclipConnectionForm() }
                #if os(macOS)
                    .frame(minWidth: 460, minHeight: 360)
                #endif
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) =
            switch office.connection {
            case .connected:
                ("\(office.agents.filter { office.deskState($0) == .working }.count) of \(office.agents.count) working", .green)
            case .failed: ("Paperclip not running", .red)
            case .connecting: ("Connecting…", .gray)
            }
        return Label { Text(text) } icon: { Circle().fill(color).frame(width: 7, height: 7) }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func roomView(_ name: String, _ agents: [PaperclipAgent]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14, alignment: .top)], spacing: 26) {
                ForEach(agents) { agent in
                    Button { selectedAgent = agent } label: {
                        AgentDeskCard(
                            agent: agent, state: office.deskState(agent), currentIssue: office.currentIssue(for: agent.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.quaternary))
    }
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "wifi.slash").font(.headline).foregroundStyle(.red)
                #if os(macOS)
                    Text("Paperclip is the engine that runs your agents, so it has to be running on this Mac. To make it start on its own whenever your Mac starts, do this once in Terminal:")
                    CopyableCommand(step: "1", command: "npx paperclipai@latest install --yes")
                    CopyableCommand(step: "2", note: "Open a new Terminal window, then:", command: "paperclipai service install")
                    Text("This page reconnects on its own once Paperclip is running.").font(.caption).foregroundStyle(.secondary)
                #else
                    Text("Your agents run in Paperclip on your Mac. To see them from here, set Paperclip's address to your Mac's network or Tailscale address, and add a board API key.")
                #endif
                Button("Connection settings…", action: openSettings)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if os(macOS)
    private struct CopyableCommand: View {
        let step: String
        var note: String?
        let command: String
        @State private var copied = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.map { "Step \(step): \($0)" } ?? "Step \(step)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copied = true
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
#endif

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
