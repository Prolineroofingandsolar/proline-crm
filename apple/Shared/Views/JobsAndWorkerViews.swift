import MapKit
import SwiftUI

struct JobsView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var stage: LeadStage?
    private let jobStages: [LeadStage] = [.won, .scheduled, .inProgress, .completed, .waitingForPayment]
    private var jobs: [Lead] {
        appState.leads
            .filter { jobStages.contains($0.stage) }
            .filter {
                (stage == nil || $0.stage == stage)
                    && (search.isEmpty
                        || [$0.name, $0.jobRef, $0.address, $0.jobType].contains { $0.localizedCaseInsensitiveContains(search) })
            }
            .sorted { ($0.startDate ?? "9999", $0.name) < ($1.startDate ?? "9999", $1.name) }
    }
    var body: some View {
        List {
            ForEach(jobs) { lead in
                NavigationLink(value: LeadRoute(id: lead.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lead.name).fontWeight(.medium)
                            Text([lead.jobType, lead.address].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(lead.stage.displayName).font(.subheadline)
                            if let start = lead.startDate { Text(CRMFormat.relativeDay(start)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if jobs.isEmpty {
                Text(search.isEmpty ? "No jobs yet. Jobs appear here once a lead is won." : "No matching jobs").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search, prompt: "Customer, job or address")
        .navigationTitle("Jobs")
        .toolbar {
            Picker("Stage", selection: $stage) {
                Text("All stages").tag(LeadStage?.none)
                ForEach(jobStages) { Text($0.displayName).tag(LeadStage?.some($0)) }
            }
        }
    }
}

struct WorkerJobsView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var showingCompleted = false
    private var jobs: [Lead] {
        appState.leads
            .filter {
                showingCompleted
                    ? [.completed, .waitingForPayment, .paid].contains($0.stage) : [.won, .scheduled, .inProgress].contains($0.stage)
            }
            .filter {
                search.isEmpty || [$0.name, $0.jobRef, $0.address, $0.jobType].contains { $0.localizedCaseInsensitiveContains(search) }
            }
            .sorted { ($0.startDate ?? "9999", $0.name) < ($1.startDate ?? "9999", $1.name) }
    }
    var body: some View {
        List {
            Section {
                ForEach(jobs) { lead in NavigationLink(value: LeadRoute(id: lead.id)) { WorkerJobRow(lead: lead) } }
                if jobs.isEmpty {
                    Text(search.isEmpty ? (showingCompleted ? "No completed jobs" : "No current jobs") : "No matching jobs")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Picker("Jobs", selection: $showingCompleted) {
                    Text("Current").tag(false); Text("Completed").tag(true)
                }
                .pickerStyle(.segmented).textCase(nil).padding(.vertical, 4)
            }
        }
        .navigationTitle("My Jobs")
        .searchable(text: $search, prompt: "Customer, job or address")
    }
}

/// A worker's day: the job they're on, then what's due.
struct WorkerHomeView: View {
    @Environment(AppState.self) private var appState
    private var today: String { SupabaseService.today }
    private var todayJobs: [Lead] {
        appState.leads.filter { lead in
            guard [.won, .scheduled, .inProgress].contains(lead.stage), let start = lead.startDate, start <= today else { return false }
            if let end = lead.endDate { return end >= today }
            return start == today
        }.sorted { ($0.stage == .inProgress ? 0 : 1, $0.name) < ($1.stage == .inProgress ? 0 : 1, $1.name) }
    }
    private var upcomingJobs: [Lead] {
        appState.leads.filter { lead in
            guard [.won, .scheduled].contains(lead.stage), let start = lead.startDate, start > today else { return false }
            return true
        }.sorted { ($0.startDate ?? "9999", $0.name) < ($1.startDate ?? "9999", $1.name) }.prefix(3).map { $0 }
    }
    private var dueTasks: [GeneralTask] {
        appState.visibleGeneralTasks
            .filter { !$0.completed && ($0.dueDate ?? today) <= today }
            .sorted { ($0.dueDate ?? "9999", $0.title) < ($1.dueDate ?? "9999", $1.title) }
    }
    private var todayEntry: TimesheetEntry? {
        guard let id = appState.currentUser?.id else { return nil }
        return appState.timesheets.first { $0.userID == id && $0.date == today }
    }

    var body: some View {
        List {
            Section {
                if todayJobs.isEmpty {
                    Text("No job booked today").foregroundStyle(.secondary)
                } else {
                    ForEach(todayJobs) { lead in NavigationLink(value: LeadRoute(id: lead.id)) { WorkerJobRow(lead: lead) } }
                }
            } header: {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            }

            if !upcomingJobs.isEmpty {
                Section("Coming up") {
                    ForEach(upcomingJobs) { lead in NavigationLink(value: LeadRoute(id: lead.id)) { WorkerJobRow(lead: lead) } }
                }
            }

            Section {
                NavigationLink(value: AppSection.timesheet) {
                    Label(
                        todayEntry == nil ? "Record today's time" : "Time recorded for today",
                        systemImage: todayEntry == nil ? "clock" : "checkmark.circle")
                }
            }

            Section {
                ForEach(dueTasks) { task in
                    Button {
                        Task { await appState.toggleGeneralTask(task) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).foregroundStyle(.primary)
                                Text(task.dueDate == today ? "Due today" : "Overdue").font(.subheadline).foregroundStyle(
                                    task.dueDate == today ? Color.secondary : Color.red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if dueTasks.isEmpty { Label("You’re all caught up", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            } header: {
                Text("Due today")
            }
        }
        .navigationTitle("Today")
        .navigationDestination(for: AppSection.self) { section in
            switch section {
            case .timesheet: TimesheetView()
            case .tools: RoofingToolsView()
            default: WorkerCalendarView()
            }
        }
    }
}

private struct WorkerJobRow: View {
    let lead: Lead
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.name).fontWeight(.medium)
                Text(lead.address.isEmpty ? lead.jobType : lead.address).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(lead.stage == .inProgress ? "On site" : lead.stage.displayName).font(.subheadline)
                if let start = lead.startDate, lead.stage != .inProgress {
                    Text(CRMFormat.relativeDay(start)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WorkerCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private var days: [Date] {
        (0..<21).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) }
    }
    private var selectedJobs: [Lead] { jobs(on: selected) }

    var body: some View {
        List {
            Section {
                ForEach(selectedJobs) { lead in NavigationLink(value: LeadRoute(id: lead.id)) { WorkerJobRow(lead: lead) } }
                if selectedJobs.isEmpty { Text("No work booked").foregroundStyle(.secondary) }
            } header: {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(days, id: \.self) { day in dayButton(day) } }
                    }
                    Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                }
                .textCase(nil).padding(.vertical, 4)
            }
        }
        .navigationTitle("Work Calendar")
    }

    private func jobs(on day: Date) -> [Lead] {
        let key = PayrollMath.key(day)
        return appState.leads.filter { lead in
            guard [.won, .scheduled, .inProgress].contains(lead.stage), let start = lead.startDate else { return false }
            if let finish = lead.endDate { return start <= key && finish >= key }
            return start == key || (lead.stage == .inProgress && key == SupabaseService.today && start <= key)
        }.sorted { ($0.startDate ?? "9999", $0.name) < ($1.startDate ?? "9999", $1.name) }
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        let count = jobs(on: day).count
        return Button {
            selected = day
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption)
                Text("\(Calendar.current.component(.day, from: day))").font(.headline)
                Circle().fill(count > 0 ? Color.accentColor : Color.clear).frame(width: 6, height: 6)
            }
            .frame(width: 44, height: 62)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) jobs")
    }
}

struct WorkerTasksView: View {
    @Environment(AppState.self) private var appState
    private var personalTasks: [GeneralTask] {
        appState.visibleGeneralTasks
            .filter { !$0.completed && $0.category != "Fleet Vehicle" }
            .sorted { ($0.dueDate ?? "9999", $0.title) < ($1.dueDate ?? "9999", $1.title) }
    }
    private var jobTasks: [JobChecklistItem] {
        appState.leads
            .filter { ![LeadStage.completed, .lost].contains($0.stage) }
            .flatMap { lead in lead.tasks.filter { !$0.completed }.map { JobChecklistItem(lead: lead, task: $0) } }
            .sorted { ($0.task.dueDate ?? "9999", $0.lead.name) < ($1.task.dueDate ?? "9999", $1.lead.name) }
    }
    var body: some View {
        List {
            Section {
                ForEach(personalTasks) { task in
                    taskRow(title: task.title, detail: dueText(task.dueDate), overdue: isOverdue(task.dueDate)) {
                        Task { await appState.toggleGeneralTask(task) }
                    }
                }
                if personalTasks.isEmpty { emptyTasks("No personal tasks") }
            } header: {
                taskHeading("For me", count: personalTasks.count)
            }

            Section {
                ForEach(jobTasks) { item in
                    taskRow(
                        title: item.task.title, detail: "\(item.lead.name) · \(dueText(item.task.dueDate))",
                        overdue: isOverdue(item.task.dueDate)
                    ) {
                        Task { await appState.toggleLeadTask(leadID: item.lead.id, taskID: item.task.id) }
                    }
                }
                if jobTasks.isEmpty { emptyTasks("No job tasks") }
            } header: {
                taskHeading("On my jobs", count: jobTasks.count)
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #else
            .listStyle(.inset)
        #endif
        .navigationTitle("Tasks")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    private func taskHeading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title3.bold()); Spacer(); Text("\(count)").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .textCase(nil)
    }
    private func taskRow(title: String, detail: String, overdue: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle").font(.title3).foregroundStyle(Color.accentColor).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(detail).font(.caption).foregroundStyle(overdue ? Color.red : Color.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Marks this task complete")
    }
    private func dueText(_ dueDate: String?) -> String {
        guard let dueDate else { return "No due date" }
        if dueDate == SupabaseService.today { return "Due today" }
        if dueDate < SupabaseService.today { return "Overdue" }
        return "Due \(dueDate)"
    }
    private func isOverdue(_ dueDate: String?) -> Bool { (dueDate ?? "9999") < SupabaseService.today }
    private func emptyTasks(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary).padding(.vertical, 5)
    }
}

struct WorkerJobDetailView: View {
    @Environment(AppState.self) private var appState
    let leadID: String
    @State private var showingUpdate = false
    @State private var showingAddNote = false
    @State private var showingAddPhoto = false
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }

    var body: some View {
        if let lead {
            Form {
                Section {
                    LabeledContent("Stage", value: lead.stage.displayName)
                    if let start = lead.startDate { LabeledContent("Starts", value: CRMFormat.relativeDay(start)) }
                    if let end = lead.endDate { LabeledContent("Expected finish", value: CRMFormat.relativeDay(end)) }
                } header: {
                    Text([lead.jobType, lead.jobRef].filter { !$0.isEmpty }.joined(separator: " · "))
                }

                Section("Site") {
                    if !lead.address.isEmpty {
                        if let maps = ContactLinks.maps(address: lead.address) {
                            Link(destination: maps) { Label(lead.address, systemImage: "map") }
                        } else {
                            Label(lead.address, systemImage: "map")
                        }
                    } else {
                        Text("Address not added").foregroundStyle(.secondary)
                    }
                    if !lead.phone.isEmpty { PhoneActionMenu(number: lead.phone, label: "Call customer", lead: lead) }
                    if lead.lat != nil && lead.lng != nil { WorkerJobMapCard(lead: lead) }
                }

                Section {
                    Button {
                        showingAddPhoto = true
                    } label: {
                        Label("Add photo", systemImage: "camera")
                    }
                    Button {
                        showingAddNote = true
                    } label: {
                        Label("Add note", systemImage: "square.and.pencil")
                    }
                    Button {
                        showingUpdate = true
                    } label: {
                        Label("Voice update", systemImage: "mic")
                    }.disabled(appState.isWorkerPreview)
                }

                Section {
                    ForEach(lead.tasks) { task in
                        Button {
                            Task { await appState.toggleLeadTask(leadID: lead.id, taskID: task.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(
                                    task.completed ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).strikethrough(task.completed).foregroundStyle(task.completed ? .secondary : .primary)
                                    if let due = task.dueDate {
                                        Text(CRMFormat.relativeDay(due)).font(.subheadline).foregroundStyle(
                                            !task.completed && due < SupabaseService.today ? Color.red : Color.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if lead.tasks.isEmpty { Text("No checklist items yet").foregroundStyle(.secondary) }
                } header: {
                    Text("Checklist · \(lead.tasks.filter(\.completed).count) of \(lead.tasks.count) done")
                }

                Section {
                    NavigationLink {
                        LeadPhotosView(leadID: lead.id)
                    } label: {
                        LabeledContent {
                            Text(lead.photos.isEmpty ? "" : "\(lead.photos.count)")
                        } label: {
                            Label("Photos", systemImage: "photo")
                        }
                    }
                    NavigationLink {
                        LeadNotesView(leadID: lead.id)
                    } label: {
                        LabeledContent {
                            Text(lead.notes.isEmpty ? "" : "\(lead.notes.count)")
                        } label: {
                            Label("Notes", systemImage: "note.text")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(lead.name)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showingUpdate) { JobUpdateSheet(leadID: lead.id) }
            .sheet(isPresented: $showingAddNote) { WorkerAddJobNoteSheet(leadID: lead.id) }
            .sheet(isPresented: $showingAddPhoto) { AddPhotoSheet(lead: lead) }
        } else {
            ContentUnavailableView("Job not found", systemImage: "hammer", description: Text("This job may no longer be assigned to you."))
        }
    }
}

private struct WorkerAddJobNoteSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let leadID: String
    @State private var note = ""
    @State private var isSaving = false
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("What happened on the job?").foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $note).frame(minHeight: 170).scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Job note")
                } footer: {
                    Text("Your name and today's date will be added automatically.")
                }
            }
            .navigationTitle("Add Note")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }.fontWeight(.semibold)
                        .disabled(trimmedNote.isEmpty || isSaving || appState.isWorkerPreview)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
    private func save() {
        guard !trimmedNote.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            let saved = await appState.addJobNote(leadID: leadID, content: trimmedNote)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct WorkerJobMapCard: View {
    let lead: Lead
    var body: some View {
        if let lat = lead.lat, let lng = lead.lng {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            ) {
                Marker(lead.name, coordinate: coordinate)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .listRowInsets(EdgeInsets())
        }
    }
}
