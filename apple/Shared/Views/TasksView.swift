import SwiftUI

struct JobChecklistItem: Identifiable {
    let lead: Lead
    let task: CRMTask
    var id: String { "\(lead.id)-\(task.id)" }
}

struct TasksView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAdd = false
    @State private var editingTask: GeneralTask?
    @State private var editingJobTask: JobChecklistItem?
    @State private var search = ""
    @State private var scope = "Open"
    @State private var priority = "All priorities"
    @State private var expandedJobIDs: Set<String> = []
    private var today: String { SupabaseService.today }
    private var mine: [GeneralTask] {
        appState.visibleGeneralTasks.filter {
            $0.category != "Fleet Vehicle" && FleetTaskPolicy.shouldShowInTaskList($0)
                && NotificationScope.includes($0, for: appState.currentUser)
        }
    }
    private var rows: [GeneralTask] {
        mine.filter { task in
            let text =
                search.isEmpty || task.title.localizedCaseInsensitiveContains(search)
                || task.category.localizedCaseInsensitiveContains(search)
            let state =
                switch scope {
                case "Today": !task.completed && task.dueDate == today;
                case "Overdue": !task.completed && (task.dueDate ?? "9999") < today;
                case "Completed": task.completed;
                case "All": true;
                case "Mine": !task.completed && isMyTask(task);
                default: !task.completed
                }
            return text && state && (priority == "All priorities" || task.priority.capitalized == priority)
        }.sorted {
            ($0.dueDate ?? "9999", $0.priority) == ($1.dueDate ?? "9999", $1.priority)
                ? $0.title < $1.title : ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999")
        }
    }
    private var checklistItems: [JobChecklistItem] {
        appState.leads
            .filter { ![LeadStage.completed, .lost].contains($0.stage) }
            .flatMap { lead in lead.tasks.map { JobChecklistItem(lead: lead, task: $0) } }
    }
    private var checklistRows: [JobChecklistItem] {
        checklistItems.filter { item in
            let matchesSearch =
                search.isEmpty || item.task.title.localizedCaseInsensitiveContains(search)
                || item.lead.name.localizedCaseInsensitiveContains(search) || item.lead.jobRef.localizedCaseInsensitiveContains(search)
            let matchesState =
                switch scope {
                case "Today": !item.task.completed && item.task.dueDate == today;
                case "Overdue": !item.task.completed && (item.task.dueDate ?? "9999") < today;
                case "Completed": item.task.completed;
                case "All": true;
                case "Mine": !item.task.completed && LeadOwnership.isAssigned(item.lead, to: appState.currentUser);
                default: !item.task.completed
                }
            return matchesSearch && matchesState && (priority == "All priorities" || priority == "Medium")
        }.sorted { ($0.task.dueDate ?? "9999", $0.lead.name) < ($1.task.dueDate ?? "9999", $1.lead.name) }
    }
    private var visibleCount: Int { rows.count + checklistRows.count }
    private var jobTaskGroups: [JobTaskGroup] {
        appState.leads.compactMap { lead in
            let items = checklistRows.filter { $0.lead.id == lead.id }
            return items.isEmpty ? nil : JobTaskGroup(lead: lead, items: items)
        }.sorted {
            let left = $0.items.first(where: { !$0.task.completed })?.task.dueDate ?? "9999-12-31"
            let right = $1.items.first(where: { !$0.task.completed })?.task.dueDate ?? "9999-12-31"
            return left == right ? $0.lead.name.localizedCaseInsensitiveCompare($1.lead.name) == .orderedAscending : left < right
        }
    }
    var body: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep every customer promise and job action on track.").foregroundStyle(.secondary)
                    }; Spacer();
                    Button {
                        showingAdd = true
                    } label: {
                        Label("New task", systemImage: "plus").foregroundStyle(.white).padding(.horizontal, 16).frame(height: 38)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 24).padding(.top, 18)
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass"); TextField("Search tasks…", text: $search)
                    }.padding(.horizontal, 10).frame(width: 280, height: 36).background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary));
                    Picker("", selection: $scope) { ForEach(["Open", "Today", "Overdue", "Completed"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).frame(width: 330);
                    Menu(priority) {
                        Button("All priorities") { priority = "All priorities" };
                        ForEach(["High", "Medium", "Low"], id: \.self) { p in Button(p) { priority = p } }
                    }; Spacer(); Text("\(visibleCount) tasks").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.vertical, 16)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !rows.isEmpty {
                            VStack(spacing: 0) {
                                HStack {
                                    Label("All general tasks", systemImage: "checklist").font(.headline); Spacer();
                                    Text("\(rows.count)").font(.caption.bold()).foregroundStyle(.secondary)
                                }.padding(16)
                                Divider()
                                ForEach(rows) { task in
                                    MacGeneralTaskCardRow(
                                        task: task, userName: owner(task), action: { Task { await appState.toggleGeneralTask(task) } },
                                        onEdit: { editingTask = task }, onDelete: { Task { await appState.deleteGeneralTask(task) } })
                                    if task.id != rows.last?.id { Divider().padding(.leading, 54) }
                                }
                            }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                        }
                        ForEach(jobTaskGroups) { group in
                            MacJobTaskCard(
                                group: group, isExpanded: expandedJobIDs.contains(group.id),
                                toggleExpanded: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedJobIDs.contains(group.id) {
                                            expandedJobIDs.remove(group.id)
                                        } else {
                                            expandedJobIDs.insert(group.id)
                                        }
                                    }
                                }, toggleTask: { taskID in Task { await appState.toggleLeadTask(leadID: group.lead.id, taskID: taskID) } },
                                editTask: { task in editingJobTask = JobChecklistItem(lead: group.lead, task: task) })
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }.overlay {
                    if visibleCount == 0 {
                        ContentUnavailableView(
                            "No tasks here", systemImage: "checkmark.circle", description: Text("Try another filter or create a new task."))
                    }
                }
            }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Tasks").onAppear {
                if expandedJobIDs.isEmpty { expandedJobIDs = Set(jobTaskGroups.prefix(3).map(\.id)) }
            }.sheet(isPresented: $showingAdd) { AddTaskView() }.sheet(item: $editingTask) { AddTaskView(task: $0) }.sheet(
                item: $editingJobTask
            ) { EditJobTaskView(item: $0) }
        #else
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(visibleCount) tasks \(scope == "Completed" ? "completed" : "pending")").font(.title3.bold())
                            Text("\(rows.count) general · \(checklistRows.count) job-related").font(.subheadline).foregroundStyle(
                                .secondary)
                        }
                        Spacer()
                    }
                    Picker("Task view", selection: $scope) {
                        Text("To Do").tag("Open")
                        Text("Mine").tag("Mine")
                        Text("Done").tag("Completed")
                        Text("All").tag("All")
                    }.pickerStyle(.segmented)

                    if !rows.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Label("General tasks", systemImage: "checklist").font(.headline); Spacer();
                                Text("\(rows.count)").font(.caption.bold()).foregroundStyle(.secondary)
                            }.padding(15)
                            Divider()
                            ForEach(rows) { task in
                                MobileGeneralTaskRow(
                                    task: task, owner: owner(task), toggle: { Task { await appState.toggleGeneralTask(task) } },
                                    edit: { editingTask = task })
                                if task.id != rows.last?.id { Divider().padding(.leading, 50) }
                            }
                        }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(.quaternary)
                        ).shadow(color: .black.opacity(0.035), radius: 8, y: 3)
                    }

                    ForEach(jobTaskGroups) { group in
                        MobileJobTaskCard(
                            group: group, isExpanded: expandedJobIDs.contains(group.id),
                            toggleExpanded: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedJobIDs.contains(group.id) {
                                        expandedJobIDs.remove(group.id)
                                    } else {
                                        expandedJobIDs.insert(group.id)
                                    }
                                }
                            }, toggleTask: { taskID in Task { await appState.toggleLeadTask(leadID: group.lead.id, taskID: taskID) } },
                            editTask: { task in editingJobTask = JobChecklistItem(lead: group.lead, task: task) })
                    }
                    if visibleCount == 0 {
                        ContentUnavailableView(
                            "No tasks here", systemImage: "checkmark.circle", description: Text("Try another view or add a general task.")
                        ).padding(.top, 60)
                    }
                }.padding(16)
            }
            .background(Color(.systemGroupedBackground)).navigationTitle("Tasks").searchable(text: $search, prompt: "Search tasks")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if appState.isAdmin {
                        Button {
                            Task { await appState.startTaskLiveActivity() }
                        } label: {
                            Image(systemName: "livephoto")
                        }.accessibilityLabel("Start task Live Activity")
                    }
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }.accessibilityLabel("Add general task")
                }
            }
            .onAppear { if expandedJobIDs.isEmpty { expandedJobIDs = Set(jobTaskGroups.prefix(2).map(\.id)) } }
            .sheet(isPresented: $showingAdd) { AddTaskView() }.sheet(item: $editingTask) { AddTaskView(task: $0) }.sheet(
                item: $editingJobTask
            ) { EditJobTaskView(item: $0) }
        #endif
    }
    private func isMyTask(_ task: GeneralTask) -> Bool {
        guard let user = appState.currentUser else { return false }; return task.assignedTo.contains(user.id)
    }
    private func owner(_ task: GeneralTask) -> String {
        guard let id = task.assignedTo.first else { return appState.currentUser?.name ?? "Me" };
        return appState.users.first { $0.id == id }?.name ?? "Team member"
    }
}

private struct JobTaskGroup: Identifiable { let lead: Lead; let items: [JobChecklistItem]; var id: String { lead.id } }

#if os(iOS)
    private struct MobileGeneralTaskRow: View {
        let task: GeneralTask; let owner: String; let toggle: () -> Void; let edit: () -> Void
        var body: some View {
            HStack(spacing: 12) {
                Button(action: toggle) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(
                        task.completed ? .green : .secondary)
                }.buttonStyle(.plain);
                Button(action: edit) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).fontWeight(.medium).foregroundStyle(.primary).strikethrough(task.completed);
                        Text([task.category, task.dueDate, owner].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 15).padding(.vertical, 12)
        }
    }

    private struct MobileJobTaskCard: View {
        @Environment(AppState.self) private var appState
        let group: JobTaskGroup; let isExpanded: Bool; let toggleExpanded: () -> Void; let toggleTask: (String) -> Void;
        let editTask: (CRMTask) -> Void
        private var completed: Int { group.items.filter(\.task.completed).count }
        private var progress: Double { group.items.isEmpty ? 0 : Double(completed) / Double(group.items.count) }
        var body: some View {
            VStack(spacing: 0) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 12) {
                        Text(group.lead.name.prefix(1)).font(.headline).foregroundStyle(Color.accentColor).frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 12));
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Text(group.lead.name).font(.headline).foregroundStyle(.primary).lineLimit(1);
                                Text(group.lead.jobType).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 7).padding(
                                    .vertical, 3
                                ).background(Color.secondary.opacity(0.09), in: Capsule()).lineLimit(1)
                            };
                            HStack(spacing: 9) {
                                ProgressView(value: progress).frame(maxWidth: 125);
                                Text("\(completed)/\(group.items.count) done").font(.caption).foregroundStyle(.secondary)
                            }
                        }; Spacer(); Text(isExpanded ? "Close" : "Open").font(.subheadline.bold()).foregroundStyle(Color.accentColor);
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                    }.padding(15).contentShape(Rectangle())
                }.buttonStyle(.plain);
                if isExpanded {
                    Divider();
                    ForEach(group.items) { item in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Button {
                                    toggleTask(item.task.id)
                                } label: {
                                    Image(systemName: item.task.completed ? "checkmark.circle.fill" : "circle").font(.title2)
                                        .foregroundStyle(item.task.completed ? .green : .secondary)
                                }.buttonStyle(.plain);
                                Button {
                                    editTask(item.task)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.task.title).foregroundStyle(.primary).strikethrough(item.task.completed);
                                        HStack(spacing: 8) {
                                            if let due = item.task.dueDate {
                                                Label(due, systemImage: "calendar").foregroundStyle(
                                                    !item.task.completed && due < SupabaseService.today ? .red : .secondary)
                                            };
                                            Text((item.task.priority ?? "medium").capitalized).foregroundStyle(
                                                item.task.priority == "high" ? .red : .secondary);
                                            if let steps = item.task.subtasks, !steps.isEmpty {
                                                Text("\(steps.filter(\.completed).count)/\(steps.count) steps").foregroundStyle(
                                                    Color.accentColor)
                                            }
                                        }.font(.caption2);
                                        if let notes = item.task.notes, !notes.isEmpty {
                                            Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain);
                                Button {
                                    editTask(item.task)
                                } label: {
                                    Image(systemName: "pencil.circle").font(.title3)
                                }.buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityLabel("Edit task")
                            }.padding(.horizontal, 17).padding(.vertical, 12);
                            if let steps = item.task.subtasks, !steps.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(steps) { step in
                                        Button {
                                            Task {
                                                await appState.toggleLeadSubtask(
                                                    leadID: group.lead.id, taskID: item.task.id, subtaskID: step.id)
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: step.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(
                                                    step.completed ? .green : Color.accentColor);
                                                Text(step.title).font(.subheadline).foregroundStyle(.primary).strikethrough(step.completed);
                                                Spacer()
                                            }.padding(.leading, 52).padding(.trailing, 17).frame(minHeight: 40)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }; if item.id != group.items.last?.id { Divider().padding(.leading, 52) }
                        }
                    }; Divider();
                    NavigationLink {
                        if appState.isAdmin { LeadDetailView(leadID: group.lead.id) } else { WorkerJobDetailView(leadID: group.lead.id) }
                    } label: {
                        Label("Open job", systemImage: "arrow.right.circle").font(.subheadline.bold()).foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.vertical, 12)
                    }
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.quaternary)
            ).shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        }
    }
#endif

#if os(macOS)
    private struct MacGeneralTaskCardRow: View {
        let task: GeneralTask; let userName: String; let action: () -> Void; let onEdit: () -> Void; let onDelete: () -> Void;
        @State private var confirmingDelete = false;
        private var tint: Color { task.priority == "high" ? .red : task.priority == "low" ? .green : Color.accentColor };
        var body: some View {
            HStack(spacing: 13) {
                Button(action: action) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(
                        task.completed ? .green : .secondary)
                }.buttonStyle(.plain);
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).fontWeight(.medium).foregroundStyle(.primary).strikethrough(task.completed);
                        Text([task.category, task.dueDate, userName].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain);
                Text(task.priority.capitalized).font(.caption.bold()).foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(tint.opacity(0.1), in: Capsule());
                Menu {
                    Button("Edit", action: onEdit); Button(task.completed ? "Mark incomplete" : "Mark complete", action: action); Divider();
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton)
            }.padding(.horizontal, 16).frame(minHeight: 62).confirmationDialog("Delete this task?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
    private struct MacJobTaskCard: View {
        @Environment(AppState.self) private var appState; let group: JobTaskGroup; let isExpanded: Bool; let toggleExpanded: () -> Void;
        let toggleTask: (String) -> Void; let editTask: (CRMTask) -> Void;
        private var completed: Int { group.items.filter(\.task.completed).count };
        private var progress: Double { group.items.isEmpty ? 0 : Double(completed) / Double(group.items.count) };
        var body: some View {
            VStack(spacing: 0) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 14) {
                        Text(group.lead.name.prefix(1)).font(.title3.bold()).foregroundStyle(Color.accentColor).frame(width: 46, height: 46)
                            .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 12));
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(group.lead.name).font(.headline).foregroundStyle(.primary);
                                Text(group.lead.jobType).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(
                                    .vertical, 3
                                ).background(Color.secondary.opacity(0.09), in: Capsule());
                                Text(group.lead.jobRef).font(.caption).foregroundStyle(.secondary)
                            };
                            HStack(spacing: 10) {
                                ProgressView(value: progress).frame(width: 180);
                                Text("\(completed)/\(group.items.count) done").font(.caption).foregroundStyle(.secondary)
                            }
                        }; Spacer(); Text(isExpanded ? "Close" : "Open").font(.subheadline.bold()).foregroundStyle(Color.accentColor);
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                    }.padding(16).contentShape(Rectangle())
                }.buttonStyle(.plain);
                if isExpanded {
                    Divider();
                    ForEach(group.items) { item in
                        VStack(spacing: 0) {
                            HStack(spacing: 13) {
                                Button {
                                    toggleTask(item.task.id)
                                } label: {
                                    Image(systemName: item.task.completed ? "checkmark.circle.fill" : "circle").font(.title2)
                                        .foregroundStyle(item.task.completed ? .green : .secondary)
                                }.buttonStyle(.plain);
                                Button {
                                    editTask(item.task)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.task.title).fontWeight(.medium).foregroundStyle(.primary).strikethrough(
                                            item.task.completed);
                                        HStack {
                                            if let due = item.task.dueDate {
                                                Label(due, systemImage: "calendar").foregroundStyle(
                                                    !item.task.completed && due < SupabaseService.today ? .red : .secondary)
                                            }; Text((item.task.priority ?? "medium").capitalized);
                                            if let steps = item.task.subtasks, !steps.isEmpty {
                                                Text("\(steps.filter(\.completed).count)/\(steps.count) steps").foregroundStyle(
                                                    Color.accentColor)
                                            }
                                        }.font(.caption).foregroundStyle(.secondary);
                                        if let notes = item.task.notes, !notes.isEmpty {
                                            Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain); Button("Edit") { editTask(item.task) }.buttonStyle(.bordered)
                            }.padding(.horizontal, 18).frame(minHeight: 68);
                            if let steps = item.task.subtasks, !steps.isEmpty {
                                ForEach(steps) { step in
                                    Button {
                                        Task {
                                            await appState.toggleLeadSubtask(
                                                leadID: group.lead.id, taskID: item.task.id, subtaskID: step.id)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: step.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(
                                                step.completed ? .green : Color.accentColor);
                                            Text(step.title).foregroundStyle(.primary).strikethrough(step.completed); Spacer()
                                        }.padding(.leading, 58).padding(.trailing, 18).frame(height: 38)
                                    }.buttonStyle(.plain)
                                }
                            }; if item.id != group.items.last?.id { Divider().padding(.leading, 56) }
                        }
                    }; Divider();
                    NavigationLink {
                        if appState.isAdmin { LeadDetailView(leadID: group.lead.id) } else { WorkerJobDetailView(leadID: group.lead.id) }
                    } label: {
                        Label("Open job", systemImage: "arrow.right.circle").font(.subheadline.bold()).foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 12)
                    }
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.quaternary)
            ).shadow(color: .black.opacity(0.025), radius: 6, y: 2)
        }
    }
#endif

struct EditJobTaskView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let item: JobChecklistItem
    @State private var title: String
    @State private var notes: String
    @State private var priority: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var subtasks: [CRMSubtask]
    @State private var newSubtask = ""
    @State private var isSaving = false

    init(item: JobChecklistItem) {
        self.item = item
        _title = State(initialValue: item.task.title)
        _notes = State(initialValue: item.task.notes ?? "")
        _priority = State(initialValue: item.task.priority ?? "medium")
        _hasDueDate = State(initialValue: item.task.dueDate != nil)
        _dueDate = State(initialValue: item.task.dueDate.flatMap { SupabaseService.date(from: $0) } ?? .now)
        _subtasks = State(initialValue: item.task.subtasks ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action required") {
                    TextField("What needs doing?", text: $title)
                    TextField("Details, access or expected result", text: $notes, axis: .vertical).lineLimit(3...7)
                }
                Section("Planning") {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
                    }
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                }
                Section("Subtasks") {
                    ForEach($subtasks) { $subtask in
                        HStack {
                            Button {
                                subtask.completed.toggle()
                            } label: {
                                Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(
                                    subtask.completed ? .green : Color.accentColor)
                            }.buttonStyle(.plain)
                            TextField("Step", text: $subtask.title)
                            Button(role: .destructive) {
                                subtasks.removeAll { $0.id == subtask.id }
                            } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add a step", text: $newSubtask).onSubmit { addSubtask() }
                        Button("Add") { addSubtask() }.disabled(newSubtask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("Related job") {
                    LabeledContent("Customer", value: item.lead.name); LabeledContent("Reference", value: item.lead.jobRef)
                }
            }
            .disabled(isSaving)
            .navigationTitle("Edit job task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }.frame(minWidth: 420, minHeight: 450)
    }

    private func save() {
        let due = hasDueDate ? SupabaseService.localDay(for: dueDate) : nil
        Task {
            isSaving = true; defer { isSaving = false }
            if await appState.updateLeadTask(
                leadID: item.lead.id, taskID: item.task.id, title: title, dueDate: due, priority: priority, notes: notes, subtasks: subtasks
            ) {
                dismiss()
            }
        }
    }
    private func addSubtask() {
        let clean = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        subtasks.append(CRMSubtask(id: UUID().uuidString, title: clean, completed: false)); newSubtask = ""
    }
}

struct AddTaskView: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss
    let task: GeneralTask?
    @State private var title: String; @State private var dueDate: Date; @State private var hasDate: Bool;
    @State private var priority: String; @State private var category: String; @State private var assignee: String;
    @State private var notes: String; @State private var isSaving = false
    init(task: GeneralTask? = nil) {
        self.task = task; _title = State(initialValue: task?.title ?? "");
        _dueDate = State(initialValue: task?.dueDate.flatMap { SupabaseService.date(from: $0) } ?? .now);
        _hasDate = State(initialValue: task?.dueDate != nil || task == nil); _priority = State(initialValue: task?.priority ?? "medium");
        _category = State(initialValue: task?.category ?? "General"); _assignee = State(initialValue: task?.assignedTo.first ?? "");
        _notes = State(initialValue: task?.notes ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title)
                TextField("Category", text: $category)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                Picker("Assigned to", selection: $assignee) {
                    if appState.isAdmin {
                        Text("Me").tag("")
                        ForEach(appState.users) { Text($0.name).tag($0.id) }
                    } else if let current = appState.currentUser {
                        Text("Me").tag(current.id)
                    }
                }
                Picker("Priority", selection: $priority) {
                    Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
                }
                Toggle("Due date", isOn: $hasDate)
                if hasDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            }
            .disabled(isSaving)
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { if isSaving { ProgressView() } else { Text("Save") } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 440)
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            let saved: Bool
            if var changed = task {
                changed.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                changed.category = category
                changed.notes = notes.isEmpty ? nil : notes
                changed.priority = priority
                changed.dueDate = hasDate ? PayrollMath.key(dueDate) : nil
                changed.assignedTo = assignee.isEmpty ? (appState.currentUser.map { [$0.id] } ?? []) : [assignee]
                saved = await appState.saveGeneralTask(changed)
            } else {
                saved = await appState.addGeneralTask(
                    title: title, dueDate: hasDate ? PayrollMath.key(dueDate) : nil, priority: priority, category: category,
                    assignedTo: assignee.isEmpty ? nil : [assignee], notes: notes.isEmpty ? nil : notes)
            }
            if saved { dismiss() }
        }
    }
}
