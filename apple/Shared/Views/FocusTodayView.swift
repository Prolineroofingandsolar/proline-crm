import SwiftUI

#if os(iOS)
/// iPhone admin Today: one thing at a time. The most important action, one button
/// to deal with it, one to skip it. Everything else is a tap away, not on screen.
struct FocusTodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var skipped: [String] = []
    @State private var editingGeneralTask: GeneralTask?
    @State private var editingJobTask: JobChecklistItem?
    @State private var showingAll = false

    private var today: String { SupabaseService.today }

    /// One row per lead or task, ranked, with anything skipped this session moved to the back.
    private var queue: [CompanyAction] {
        var seen = Set<String>()
        let ranked = appState.companyActions.filter { action in
            let key = action.leadTaskID.map { "job-task-\($0)" } ?? action.generalTaskID.map { "task-\($0)" } ?? action.leadID.map { "lead-\($0)" } ?? action.id
            return seen.insert(key).inserted
        }
        let live = ranked.filter { !skipped.contains($0.id) }
        let parked = skipped.compactMap { id in ranked.first { $0.id == id } }
        return live + parked
    }
    private var current: CompanyAction? { queue.first }
    private var currentLead: Lead? { current?.leadID.flatMap { id in appState.leads.first { $0.id == id } } }
    private var bookedToday: [Lead] {
        appState.leads.filter { $0.surveyDate == today || $0.startDate == today }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let action = current {
                    focusCard(action)
                } else {
                    allClear
                }
                if !bookedToday.isEmpty { booked }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar {
            if queue.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Button("\(queue.count) to do") { showingAll = true }
                }
            }
        }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                List { ActionQueueList(showLater: true) }
                    .navigationTitle("Everything")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAll = false } } }
            }
        }
        .sheet(item: $editingGeneralTask) { AddTaskView(task: $0) }
        .sheet(item: $editingJobTask) { EditJobTaskView(item: $0) }
    }

    // MARK: The one thing

    private func focusCard(_ action: CompanyAction) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                if action.priority == .critical { Circle().fill(.red).frame(width: 8, height: 8) }
                Text(action.priority.label).font(.subheadline).foregroundStyle(action.priority == .critical ? Color.red : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(action.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if !action.detail.isEmpty { Text(action.detail).font(.title3).foregroundStyle(.secondary) }
            }
            HStack(spacing: 10) {
                primaryButton(action)
                if let lead = currentLead, ContactLinks.telephone(lead.phone) != nil, !isCallPrimary(action) {
                    Button {
                        if let url = appState.beginCall(to: lead) { openURL(url) }
                    } label: { Image(systemName: "phone").frame(height: 24) }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                if action.leadID != nil && action.kind != .survey && action.kind != .jobStart && action.kind != .overdueJob {
                    Button {
                        open(action)
                    } label: { Image(systemName: "arrow.up.right").frame(height: 24) }
                    .buttonStyle(.bordered).controlSize(.large)
                }
            }
            if queue.count > 1 {
                Button("Skip for now") { withAnimation(.snappy) { skipped.append(action.id) } }
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .animation(.snappy, value: action.id)
    }

    @ViewBuilder private func primaryButton(_ action: CompanyAction) -> some View {
        if action.generalTaskID != nil || action.leadTaskID != nil {
            Button { complete(action) } label: { Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 24) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if isCallPrimary(action), let lead = currentLead {
            Button { if let url = appState.beginCall(to: lead) { openURL(url) } } label: { Label("Call", systemImage: "phone").frame(maxWidth: .infinity, minHeight: 24) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if action.kind == .timesheet {
            Button { appState.pendingSection = .timesheet } label: { Label("Open", systemImage: "clock").frame(maxWidth: .infinity, minHeight: 24) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Button { open(action) } label: { Label("Open", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 24) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func isCallPrimary(_ action: CompanyAction) -> Bool {
        action.kind == .quoteFollowUp && currentLead.map { ContactLinks.telephone($0.phone) != nil } == true
    }

    private var allClear: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Nothing to chase").font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var booked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Booked today").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(bookedToday) { lead in
                    NavigationLink(value: LeadRoute(id: lead.id)) {
                        HStack {
                            Text(lead.name).foregroundStyle(Color.primary)
                            Spacer()
                            Text(lead.surveyDate == today ? (lead.surveyTime ?? "Survey") : "Start").foregroundStyle(Color.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(.tertiaryLabel))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    if lead.id != bookedToday.last?.id { Divider().padding(.leading, 16) }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

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
                  let taskID = action.leadTaskID, let task = lead.tasks.first(where: { $0.id == taskID }) {
            editingJobTask = JobChecklistItem(lead: lead, task: task)
        } else if let leadID = action.leadID {
            appState.openLead(leadID)
        }
    }
}
#endif
