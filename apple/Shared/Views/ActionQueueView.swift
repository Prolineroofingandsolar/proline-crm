import SwiftUI

/// The whole ranked "what needs doing" queue, grouped Overdue / Today / This week / Later,
/// with the actions you can take inline. Shared by the iPhone and Mac dashboards.
struct ActionQueueList: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    /// Show `.routine` items too (collapsed by default on the dashboard).
    var showLater = false
    @State private var editingGeneralTask: GeneralTask?
    @State private var editingJobTask: JobChecklistItem?
    @State private var laterExpanded = false

    private var actions: [CompanyAction] {
        // One row per lead or task, highest priority first.
        var seen = Set<String>()
        return appState.companyActions.filter { action in
            let key =
                action.leadTaskID.map { "job-task-\($0)" } ?? action.generalTaskID.map { "task-\($0)" } ?? action.leadID.map {
                    "lead-\($0)"
                } ?? action.id
            return seen.insert(key).inserted
        }
    }
    private func group(_ priority: CompanyActionPriority) -> [CompanyAction] { actions.filter { $0.priority == priority } }

    var body: some View {
        queueContent
        .sheet(item: $editingGeneralTask) { AddTaskView(task: $0) }
        .sheet(item: $editingJobTask) { EditJobTaskView(item: $0) }
    }

    @ViewBuilder private var queueContent: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 14) {
                if actions.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're all caught up").fontWeight(.semibold)
                            Text("There is nothing that needs chasing right now.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(18)
                    .dashboardActionCard()
                } else {
                    ForEach([CompanyActionPriority.critical, .urgent, .soon], id: \.rawValue) { priority in
                        let rows = group(priority)
                        if !rows.isEmpty { macGroup(priority, rows: rows) }
                    }
                    let later = group(.routine)
                    if !later.isEmpty {
                        macGroup(.routine, rows: showLater || laterExpanded ? later : [])
                    }
                }
            }
        #else
            Group {
                if actions.isEmpty {
                    Section { Label("Nothing to chase", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                } else {
                    ForEach([CompanyActionPriority.critical, .urgent, .soon], id: \.rawValue) { priority in
                        let rows = group(priority)
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { action in row(action) }
                            } header: {
                                Text(priority.label)
                            }
                        }
                    }
                    let later = group(.routine)
                    if !later.isEmpty {
                        Section {
                            if showLater || laterExpanded {
                                ForEach(later) { action in row(action) }
                            } else {
                                Button("Show \(later.count) more") { laterExpanded = true }
                            }
                        } header: {
                            Text("Later")
                        }
                    }
                }
            }
        #endif
    }

    #if os(macOS)
        private func macGroup(_ priority: CompanyActionPriority, rows: [CompanyAction]) -> some View {
            let allRows = group(priority)
            return VStack(spacing: 0) {
                DashboardCardHeader(
                    title: priority.label, subtitle: groupSubtitle(priority, count: allRows.count), icon: groupIcon(priority), tint: priority.tint)
                if !rows.isEmpty {
                    Divider()
                    ForEach(rows) { action in
                        row(action).padding(.horizontal, 16)
                        if action.id != rows.last?.id { Divider().padding(.leading, 62) }
                    }
                } else {
                    Divider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { laterExpanded = true }
                    } label: {
                        HStack {
                            Text("Show \(allRows.count) lower-priority \(allRows.count == 1 ? "item" : "items")")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .dashboardActionCard()
        }

        private func groupIcon(_ priority: CompanyActionPriority) -> String {
            switch priority {
            case .critical: "exclamationmark.triangle.fill"
            case .urgent: "sun.max.fill"
            case .soon: "calendar"
            case .routine: "tray.full"
            }
        }

        private func groupSubtitle(_ priority: CompanyActionPriority, count: Int) -> String {
            let item = count == 1 ? "item" : "items"
            return switch priority {
            case .critical: "\(count) overdue \(item)"
            case .urgent: "\(count) \(item) to handle today"
            case .soon: "\(count) \(item) coming up"
            case .routine: "\(count) lower-priority \(item)"
            }
        }
    #endif

    private func row(_ action: CompanyAction) -> some View {
        CompanyActionRow(
            action: action, lead: action.leadID.flatMap { id in appState.leads.first { $0.id == id } },
            complete: canComplete(action) ? { complete(action) } : nil,
            call: { lead in if let url = appState.beginCall(to: lead) { openURL(url) } },
            open: { open(action) })
    }

    private func canComplete(_ action: CompanyAction) -> Bool { action.generalTaskID != nil || action.leadTaskID != nil }

    private func complete(_ action: CompanyAction) {
        if let taskID = action.generalTaskID, let task = appState.generalTasks.first(where: { $0.id == taskID }) {
            Task { await appState.toggleGeneralTask(task) }
        } else if let leadID = action.leadID, let taskID = action.leadTaskID {
            Task { await appState.toggleLeadTask(leadID: leadID, taskID: taskID) }
        }
    }

    private func open(_ action: CompanyAction) {
        if let taskID = action.generalTaskID, let task = appState.generalTasks.first(where: { $0.id == taskID }) {
            editingGeneralTask = task
        } else if let leadID = action.leadID, let lead = appState.leads.first(where: { $0.id == leadID }),
            let taskID = action.leadTaskID, let task = lead.tasks.first(where: { $0.id == taskID })
        {
            editingJobTask = JobChecklistItem(lead: lead, task: task)
        } else if let leadID = action.leadID {
            appState.openLead(leadID)
        } else if action.kind == .timesheet {
            appState.selectedSection = .timesheet
        }
    }
}

struct CompanyActionRow: View {
    let action: CompanyAction
    let lead: Lead?
    let complete: (() -> Void)?
    let call: (Lead) -> Void
    let open: () -> Void

    var body: some View {
        #if os(macOS)
            HStack(spacing: 12) {
                if let complete {
                    Button(action: complete) {
                        Image(systemName: "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete \(action.title)")
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(action.priority.tint)
                        .frame(width: 30, height: 30)
                        .background(action.priority.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                }
                if let lead, opensLeadDirectly {
                    NavigationLink(value: LeadRoute(id: lead.id)) { macActionLabel }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(action.title)")
                } else {
                    Button(action: open) { macActionLabel }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(action.title)")
                }
                if let lead, ContactLinks.telephone(lead.phone) != nil {
                    Button { call(lead) } label: {
                        Image(systemName: "phone")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .help("Call \(lead.name)")
                    .accessibilityLabel("Call \(lead.name)")
                }
            }
            .frame(minHeight: 62)
        #else
        HStack(spacing: 12) {
            if let complete {
                Button(action: complete) { Image(systemName: "circle").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Complete \(action.title)")
            } else {
                Image(systemName: icon).foregroundStyle(action.priority == .critical ? Color.red : Color.secondary).frame(width: 26)
            }
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).fontWeight(.medium).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(action.priority == .critical ? Color.red : Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(action.title)")
            if let lead, ContactLinks.telephone(lead.phone) != nil {
                Button {
                    call(lead)
                } label: {
                    Image(systemName: "phone")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Call \(lead.name)")
            }
        }
        .padding(.vertical, 2)
        #endif
    }

    #if os(macOS)
        private var opensLeadDirectly: Bool {
            lead != nil && action.generalTaskID == nil && action.leadTaskID == nil && action.kind != .timesheet
        }

        private var macActionLabel: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title).fontWeight(.semibold).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(detail).foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.tertiary)
                        Text(action.reason).foregroundStyle(action.priority == .critical ? Color.red : Color.secondary)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    #endif

    private var detail: String {
        // The section header already says when; the row only needs who.
        action.detail
    }
    private var icon: String {
        switch action.kind {
        case .survey: "calendar"
        case .jobStart, .overdueJob, .jobTask: "hammer"
        case .quoteFollowUp: "doc.text"
        case .deposit, .balance: "sterlingsign.circle"
        case .timesheet: "clock"
        case .generalTask: "checklist"
        }
    }
}

#if os(macOS)
    private extension View {
        func dashboardActionCard() -> some View {
            background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .shadow(color: .black.opacity(0.025), radius: 6, y: 2)
        }
    }
#endif
