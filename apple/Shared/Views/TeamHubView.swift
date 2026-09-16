import SwiftUI

struct TeamHubView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var message = ""
    @State private var showingPlan = false
    @State private var sending = false

    private var dayKey: String { SupabaseService.localDay(for: selectedDay) }
    private var plans: [TeamDayPlan] { appState.teamDayPlans.filter { $0.day == dayKey } }
    private var messages: [TeamMessage] { Array(appState.teamMessages.reversed()) }

    var body: some View {
        #if os(macOS)
            macChatHub
        #else
            mobileChatHub
                .navigationTitle("Team Hub")
                .sheet(isPresented: $showingPlan) { TeamPlanSheet(defaultDay: selectedDay) }
                .onAppear { appState.markTeamRead() }
                .onChange(of: appState.teamMessages.count) { _, _ in appState.markTeamRead() }
                .task { await liveLoop() }
        #endif
    }

    #if !os(macOS)
        private var mobileChatHub: some View {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Circle().fill(Color.accentColor).frame(width: 42, height: 42)
                        .overlay(Text("PT").font(.caption.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ProLine Team").font(.headline)
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 7, height: 7); Text("Live team chat")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { try? await appState.refreshTeam() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        showingPlan = true
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                    }.foregroundStyle(Color.accentColor)
                }.padding(.horizontal, 14).frame(height: 62).background(.background)
                Divider()

                VStack(spacing: 9) {
                    HStack {
                        Button {
                            selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(selectedDay.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                        Text("· \(plans.count) planned").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }.buttonStyle(.plain)
                    if !plans.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 9) {
                                ForEach(plans) { plan in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(plan.title).font(.caption.bold()).lineLimit(1); Spacer();
                                            Text(plan.startTime ?? "").font(.caption2).foregroundStyle(Color.accentColor)
                                        }
                                        if let lead = appState.leads.first(where: { $0.id == plan.leadID }) {
                                            Text("\(lead.name) · \(lead.jobRef)").font(.caption2).foregroundStyle(.blue).lineLimit(1)
                                        }
                                        if !plan.assignedTo.isEmpty {
                                            Label(plan.assignedTo.joined(separator: ", "), systemImage: "person.2.fill").font(.caption2)
                                                .foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }.padding(10).frame(width: 220, height: 66, alignment: .topLeading).background(
                                        .background, in: RoundedRectangle(cornerRadius: 12)
                                    ).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 9).background(Color.secondary.opacity(0.045))
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if messages.isEmpty {
                                ContentUnavailableView(
                                    "No messages yet", systemImage: "bubble.left.and.bubble.right",
                                    description: Text("Send the first update to your team.")
                                ).frame(minHeight: 330)
                            }
                            ForEach(messages) { item in
                                TeamMessageBubble(message: item, isMine: item.authorID == appState.currentUser?.id).id(item.id)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 14)
                    }
                    .background(Color.primary.opacity(0.03))
                    .onAppear { if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                    .onChange(of: messages.count) { _, _ in
                        if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                Divider()
                HStack(alignment: .bottom, spacing: 9) {
                    Menu {
                        Button {
                            showingPlan = true
                        } label: {
                            Label("Plan work", systemImage: "calendar.badge.plus")
                        }; Divider();
                        ForEach(appState.leads.filter { ![.paid, .lost].contains($0.stage) }.prefix(20)) { lead in
                            Button {
                                message += message.isEmpty ? "Regarding \(lead.name) (\(lead.jobRef)): " : " \(lead.jobRef)"
                            } label: {
                                Text("\(lead.name) · \(lead.jobRef)")
                            }
                        }
                    } label: {
                        Image(systemName: "plus").font(.headline).frame(width: 34, height: 34).background(
                            Color.secondary.opacity(0.12), in: Circle())
                    }
                    TextField("Message", text: $message, axis: .vertical).lineLimit(1...4).textFieldStyle(.plain).padding(.horizontal, 13)
                        .padding(.vertical, 9).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        send()
                    } label: {
                        if sending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill").foregroundStyle(.white)
                        }
                    }.buttonStyle(.plain).frame(width: 38, height: 38).background(Color.accentColor, in: Circle()).disabled(
                        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }.padding(.horizontal, 11).padding(.vertical, 9).background(.background)
            }
        }
    #endif

    #if os(macOS)
        private var macChatHub: some View {
            HSplitView {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Circle().fill(Color.accentColor.gradient).frame(width: 42, height: 42)
                            .overlay(Image(systemName: "person.3.fill").foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ProLine Team").font(.headline)
                            Text("\(appState.users.count) staff members").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { try? await appState.refreshTeam() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain).help("Refresh messages")
                    }.padding(16).background(Color(nsColor: .controlBackgroundColor))
                    Divider()
                    HStack {
                        Button {
                            selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(selectedDay.formatted(date: .abbreviated, time: .omitted)).fontWeight(.semibold);
                            Text("\(plans.count) planned").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }.buttonStyle(.plain).padding(14)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if plans.isEmpty {
                                ContentUnavailableView(
                                    "No work planned", systemImage: "calendar", description: Text("Plan jobs and crews for this day.")
                                )
                                .frame(minHeight: 230)
                            } else {
                                ForEach(plans) { plan in planSidebarCard(plan) }
                            }
                        }.padding(12)
                    }
                    Divider()
                    Button {
                        showingPlan = true
                    } label: {
                        Label("Plan work", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(14)
                }
                .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Circle().fill(Color.accentColor).frame(width: 42, height: 42)
                            .overlay(Text("PT").font(.caption.bold()).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ProLine Team Chat").font(.headline)
                            HStack(spacing: 5) {
                                Circle().fill(.green).frame(width: 7, height: 7); Text("Live · updates every 10 seconds")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(appState.teamMessages.count) messages").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 18).frame(height: 68).background(Color(nsColor: .controlBackgroundColor))
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                if messages.isEmpty {
                                    ContentUnavailableView(
                                        "No messages yet", systemImage: "bubble.left.and.bubble.right",
                                        description: Text("Send the first update to your team.")
                                    ).frame(minHeight: 360)
                                }
                                ForEach(messages) { item in
                                    TeamMessageBubble(message: item, isMine: item.authorID == appState.currentUser?.id).id(item.id)
                                }
                            }.padding(.horizontal, 22).padding(.vertical, 18)
                        }
                        .background(Color.primary.opacity(0.03))
                        .onAppear { if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                        .onChange(of: messages.count) { _, _ in
                            if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                        }
                    }
                    Divider()
                    HStack(alignment: .bottom, spacing: 12) {
                        Menu {
                            Button {
                                showingPlan = true
                            } label: {
                                Label("Plan work", systemImage: "calendar.badge.plus")
                            }; Divider();
                            ForEach(appState.leads.filter { ![.paid, .lost].contains($0.stage) }.prefix(20)) { lead in
                                Button {
                                    message += message.isEmpty ? "Regarding \(lead.name) (\(lead.jobRef)): " : " \(lead.jobRef)"
                                } label: {
                                    Label("\(lead.name) · \(lead.jobRef)", systemImage: "briefcase")
                                }
                            }
                        } label: {
                            Image(systemName: "plus").font(.headline).frame(width: 36, height: 36).background(
                                Color.secondary.opacity(0.12), in: Circle())
                        }.menuStyle(.borderlessButton).fixedSize()
                        TextField("Message the team", text: $message, axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.plain).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(.quaternary)
                            )
                            .onSubmit { send() }
                        Button {
                            send()
                        } label: {
                            if sending {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill").foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain).frame(width: 40, height: 40).background(Color.accentColor, in: Circle())
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    }.padding(14).background(Color(nsColor: .controlBackgroundColor))
                }.frame(minWidth: 520)
            }
            .navigationTitle("Team Hub")
            .sheet(isPresented: $showingPlan) { TeamPlanSheet(defaultDay: selectedDay) }
            .onAppear { appState.markTeamRead() }
            .onChange(of: appState.teamMessages.count) { _, _ in appState.markTeamRead() }
            .task { await liveLoop() }
        }

        private func planSidebarCard(_ plan: TeamDayPlan) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(plan.title).fontWeight(.semibold).lineLimit(1); Spacer();
                    Text([plan.startTime, plan.endTime].compactMap { $0 }.joined(separator: "–")).font(.caption.bold()).foregroundStyle(
                        Color.accentColor)
                }
                if let lead = appState.leads.first(where: { $0.id == plan.leadID }) {
                    NavigationLink {
                        LeadDetailView(leadID: lead.id)
                    } label: {
                        Label("\(lead.name) · \(lead.jobRef)", systemImage: "briefcase").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.blue)
                }
                if !plan.assignedTo.isEmpty {
                    Label(plan.assignedTo.joined(separator: ", "), systemImage: "person.2.fill").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        }
    #endif

    private var dayPlanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
                } label: {
                    Image(systemName: "chevron.left")
                }
                DatePicker("Day", selection: $selectedDay, displayedComponents: .date).labelsHidden()
                Button {
                    selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
                } label: {
                    Image(systemName: "chevron.right")
                }
                Spacer(); Text("\(plans.count) planned").font(.caption).foregroundStyle(.secondary)
            }
            Text("Day plan").font(.title2.bold())
            if plans.isEmpty {
                ContentUnavailableView(
                    "Nothing planned", systemImage: "calendar.badge.plus", description: Text("Add jobs, staff and timings for this day."))
            } else {
                ForEach(plans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(plan.title).font(.headline); Spacer();
                            Text([plan.startTime, plan.endTime].compactMap { $0 }.joined(separator: "–")).font(.caption.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                        if let lead = appState.leads.first(where: { $0.id == plan.leadID }) {
                            NavigationLink {
                                LeadDetailView(leadID: lead.id)
                            } label: {
                                Label("\(lead.name) · \(lead.jobRef)", systemImage: "briefcase")
                            }
                        }
                        if !plan.assignedTo.isEmpty {
                            Label(plan.assignedTo.joined(separator: ", "), systemImage: "person.2.fill").font(.subheadline)
                        }
                        if !plan.notes.isEmpty { Text(plan.notes).font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
                        .background, in: RoundedRectangle(cornerRadius: 12)
                    ).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }
            Spacer(minLength: 0)
        }.padding(18)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Team messages").font(.title2.bold()); Spacer();
                Text("Updates every 10 seconds").font(.caption).foregroundStyle(.green)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        ContentUnavailableView(
                            "No messages yet", systemImage: "bubble.left.and.bubble.right",
                            description: Text("Start the team conversation below."))
                    }
                    ForEach(messages) { item in
                        TeamMessageBubble(message: item, isMine: item.authorID == appState.currentUser?.id)
                    }
                }.padding(.vertical, 4)
            }
            HStack(alignment: .bottom) {
                TextField("Message the team…", text: $message, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button {
                    send()
                } label: {
                    if sending { ProgressView() } else { Image(systemName: "paperplane.fill") }
                }.buttonStyle(.borderedProminent).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
        }.padding(18)
    }

    private func send() {
        let value = message; sending = true
        Task {
            if await appState.sendTeamMessage(value) { message = "" }; sending = false
        }
    }

    private func liveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            try? await appState.refreshTeam(showErrors: false)
        }
    }
}

private struct TeamMessageBubble: View {
    let message: TeamMessage
    let isMine: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 90)
            } else {
                Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 30, height: 30).overlay(
                    Text(message.authorName.prefix(1).uppercased()).font(.caption.bold()).foregroundStyle(Color.accentColor))
            }
            VStack(alignment: .leading, spacing: 5) {
                if !isMine { Text(message.authorName).font(.caption.bold()).foregroundStyle(Color.accentColor) }
                Text(message.body).textSelection(.enabled)
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(chatTime(message.createdAt)).font(.caption2).foregroundStyle(.secondary)

                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(isMine ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            if !isMine { Spacer(minLength: 90) }
        }
    }
    private func chatTime(_ raw: String) -> String {
        let value = raw.replacingOccurrences(of: "T", with: " ");
        return value.count >= 16 ? String(value.dropFirst(11).prefix(5)) : String(value.prefix(16))
    }
}

private struct TeamPlanSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var title = ""
    @State private var notes = ""
    @State private var start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: .now) ?? .now
    @State private var leadID = ""
    @State private var assigned: Set<String> = []
    @State private var saving = false
    init(defaultDay: Date) { _day = State(initialValue: defaultDay) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Work") {
                    TextField("Title", text: $title);
                    Picker("Job", selection: $leadID) {
                        Text("General / no job").tag("");
                        ForEach(appState.leads.filter { ![.paid, .lost].contains($0.stage) }) {
                            Text("\($0.name) · \($0.jobRef)").tag($0.id)
                        }
                    }; TextField("Notes, access or materials", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section("When") {
                    DatePicker("Day", selection: $day, displayedComponents: .date);
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute);
                    DatePicker("Finish", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section("Team") {
                    ForEach(appState.users) { user in
                        Toggle(
                            user.name,
                            isOn: Binding(
                                get: { assigned.contains(user.name) },
                                set: { isAssigned in
                                    if isAssigned { assigned.insert(user.name) } else { assigned.remove(user.name) }
                                }
                            ))
                    }
                }
            }.disabled(saving).navigationTitle("Plan work").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } };
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || assigned.isEmpty || saving)
                }
            }
        }.frame(minWidth: 480, minHeight: 590)
    }
    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
    private func save() {
        guard let user = appState.currentUser else { return }
        let plan = TeamDayPlan(
            id: UUID().uuidString, day: SupabaseService.localDay(for: day), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes, startTime: time(start), endTime: time(end), leadID: leadID.isEmpty ? nil : leadID, assignedTo: assigned.sorted(),
            createdBy: user.id, createdAt: SupabaseService.now)
        saving = true;
        Task {
            if await appState.saveTeamDayPlan(plan) { dismiss() }; saving = false
        }
    }
}
