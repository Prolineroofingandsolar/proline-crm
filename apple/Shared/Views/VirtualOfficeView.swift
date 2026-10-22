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

// MARK: - Office

struct VirtualOfficeView: View {
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
