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
        .sheet(item: $editingGeneralTask) { AddTaskView(task: $0) }
        .sheet(item: $editingJobTask) { EditJobTaskView(item: $0) }
    }

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
    }

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
