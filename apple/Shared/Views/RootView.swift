import MapKit
import SwiftUI

/// A customer/job pushed onto a navigation stack.
struct LeadRoute: Hashable { let id: String }

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabPaths: [AppSection: NavigationPath] = [:]
    @State private var morePath = NavigationPath()
    @State private var macPath = NavigationPath()
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    private func path(for section: AppSection) -> Binding<NavigationPath> {
        Binding(get: { tabPaths[section] ?? NavigationPath() }, set: { tabPaths[section] = $0 })
    }

    private var adminSidebarGroups: [(title: String, sections: [AppSection])] {
        [
            ("Work", [.dashboard, .pipeline, .jobs, .tasks, .calendar]),
            ("Customers", [.contacts, .email]),
            ("Business", [.accounts, .team, .fleet]),
            ("Resources", [.files, .tools])
        ]
    }
    private var workerSections: [AppSection] { [.dashboard, .calendar, .jobs, .tasks, .timesheet, .tools] }
    private var mobileTabs: [AppSection] { appState.usesAdminInterface ? [.dashboard, .pipeline, .jobs, .tasks] : [.dashboard, .jobs, .tasks] }

    var body: some View {
        @Bindable var appState = appState
        #if os(iOS)
        TabView(selection: $appState.selectedSection) {
            ForEach(mobileTabs) { section in
                NavigationStack(path: path(for: section)) {
                    SectionContent(section: section)
                        .navigationDestination(for: LeadRoute.self) { route in leadDestination(route.id) }
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                if !appState.syncIssues.isEmpty {
                                    Button(action: showSyncIssues) { Image(systemName: "exclamationmark.icloud") }
                                        .accessibilityLabel("Data sync issue")
                                }
                                if appState.usesAdminInterface {
                                    Button { appState.showingGlobalSearch = true } label: { Image(systemName: "magnifyingglass") }
                                        .accessibilityLabel("Search")
                                    if section == .dashboard || section == .pipeline {
                                        Button { appState.showingGlobalAddLead = true } label: { Image(systemName: "plus") }
                                            .accessibilityLabel("Add lead")
                                    }
                                }
                            }
                        }
                }
                .tabItem { Label(sectionLabel(section), systemImage: section.icon) }
                .badge(sectionBadge(section))
                .tag(section)
            }
            NavigationStack(path: $morePath) {
                Group {
                    if appState.usesAdminInterface { MobileMoreView() } else { WorkerMoreView() }
                }
                .navigationDestination(for: AppSection.self) { section in SectionContent(section: section) }
                .navigationDestination(for: LeadRoute.self) { route in leadDestination(route.id) }
            }
            .tabItem { Label("More", systemImage: "ellipsis") }
            .badge(appState.usesAdminInterface ? appState.unreadTeamCount : 0)
            .tag(AppSection.settings)
        }
        .sheet(isPresented: $appState.showingGlobalSearch) { GlobalSearchView() }
        .sheet(isPresented: $appState.showingAssistant) { OperationsAssistantView() }
        .sheet(isPresented: $appState.showingGlobalAddLead) { AddLeadView(defaultStage: .newLead) }
        .sheet(item: $appState.pendingCallOutcome) { CallOutcomeSheet(pending: $0) }
        .onAppear { ensureAllowedSelection() }
        .onChange(of: appState.selectedSection) { _, _ in ensureAllowedSelection() }
        .onChange(of: appState.pendingLeadID) { _, id in if let id { showLead(id) } }
        .onOpenURL(perform: openDeepLink)
        .onReceive(NotificationCenter.default.publisher(for: .crmNotificationDeepLink)) { note in
            if let url = note.object as? URL { openDeepLink(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !appState.isWorkerPreview {
                appState.resumePendingCall()
                Task { await appState.refresh(showErrors: false) }
            }
        }
        .task { await activeSyncLoop() }
        #else
        NavigationSplitView {
            List(selection: $appState.selectedSection) {
                if appState.isAdmin {
                    ForEach(adminSidebarGroups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.sections.filter(appState.canAccess)) { section in sidebarRow(section) }
                        }
                    }
                } else {
                    ForEach(workerSections) { section in sidebarRow(section) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                if let user = appState.currentUser {
                    Menu {
                        Button("Settings…") { openSettings() }
                        Divider()
                        Button("Sign Out", role: .destructive) { appState.signOut() }
                    } label: {
                        Label { VStack(alignment: .leading) { Text(user.name).lineLimit(1); Text(user.role.capitalized).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "person.crop.circle") }
                    }
                    .menuStyle(.borderlessButton)
                    .padding(12)
                }
            }
            .onChange(of: appState.selectedSection) { _, _ in macPath = NavigationPath() }
        } detail: {
            NavigationStack(path: $macPath) {
                SectionContent(section: appState.selectedSection)
                    .navigationDestination(for: LeadRoute.self) { route in leadDestination(route.id) }
            }
            .toolbar {
                if appState.isAdmin {
                    Button { appState.showingGlobalAddLead = true } label: { Label("Add lead", systemImage: "plus") }
                    Button { appState.showingGlobalSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
                }
                if !appState.syncIssues.isEmpty {
                    Button(action: showSyncIssues) { Label("Data sync issue", systemImage: "exclamationmark.icloud") }
                }
                Button { Task { await appState.refresh() } } label: {
                    if appState.isRefreshing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }.disabled(appState.isRefreshing || appState.isWorkerPreview)
            }
        }
        .sheet(isPresented: $appState.showingGlobalAddLead) { AddLeadView(defaultStage: .newLead) }
        .sheet(isPresented: $appState.showingGlobalSearch) { GlobalSearchView() }
        .sheet(isPresented: $appState.showingAssistant) { OperationsAssistantView() }
        .sheet(item: $appState.pendingCallOutcome) { CallOutcomeSheet(pending: $0) }
        .onChange(of: appState.pendingLeadID) { _, id in if let id { showLead(id) } }
        .onOpenURL(perform: openDeepLink)
        .onReceive(NotificationCenter.default.publisher(for: .crmNotificationDeepLink)) { note in
            if let url = note.object as? URL { openDeepLink(url) }
        }
        .onAppear { ensureAllowedSelection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !appState.isWorkerPreview {
                appState.resumePendingCall()
                Task { await appState.refresh(showErrors: false) }
            }
        }
        .task { await activeSyncLoop() }
        #endif
    }

    @ViewBuilder private func leadDestination(_ id: String) -> some View {
        if appState.usesAdminInterface { LeadDetailView(leadID: id) } else { WorkerJobDetailView(leadID: id) }
    }

    /// Pushes a lead onto whichever stack the user is looking at.
    private func showLead(_ id: String) {
        appState.pendingLeadID = nil
        appState.showingGlobalSearch = false
        #if os(iOS)
        if appState.selectedSection == .settings {
            morePath.append(LeadRoute(id: id))
        } else {
            let section = mobileTabs.contains(appState.selectedSection) ? appState.selectedSection : .dashboard
            appState.selectedSection = section
            tabPaths[section, default: NavigationPath()].append(LeadRoute(id: id))
        }
        #else
        macPath.append(LeadRoute(id: id))
        #endif
    }

    /// Shows a section, on iPhone by selecting its tab or pushing it inside More.
    private func showSection(_ section: AppSection) {
        guard appState.canAccess(section) else { return }
        #if os(iOS)
        if mobileTabs.contains(section) {
            appState.selectedSection = section
        } else {
            appState.selectedSection = .settings
            morePath = NavigationPath([section])
        }
        #else
        appState.selectedSection = section
        #endif
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "prolinecrm" else { return }
        let components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        guard let kind = components.first?.lowercased() else { return }
        if kind == "lead", components.count > 1 {
            appState.openLead(components[1])
        } else if kind == "team" {
            showSection(.team)
        } else if let section = AppSection.allCases.first(where: { $0.rawValue.lowercased() == kind }) {
            showSection(section)
        }
    }

    private func ensureAllowedSelection() {
        if !appState.canAccess(appState.selectedSection) && appState.selectedSection != .settings {
            appState.selectedSection = .dashboard
        }
        #if os(iOS)
        if !mobileTabs.contains(appState.selectedSection) && appState.selectedSection != .settings {
            // A section without a tab lives under More.
            let section = appState.selectedSection
            appState.selectedSection = .settings
            if appState.canAccess(section) { morePath = NavigationPath([section]) }
        }
        #endif
    }

    private func sectionLabel(_ section: AppSection) -> String {
        if section == .dashboard { return "Today" }
        guard appState.usesWorkerInterface else { return section.rawValue }
        switch section {
        case .jobs: return "My Jobs"
        case .tasks: return "My Tasks"
        case .timesheet: return "My Time"
        default: return section.rawValue
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        Label(sectionLabel(section), systemImage: section.icon)
            .badge(sectionBadge(section))
            .tag(section)
    }

    private func showSyncIssues() {
        appState.errorMessage = "Some CRM data is not currently synced: \(appState.syncIssues.joined(separator: ", ")). Existing data is still shown. Check your connection or Supabase setup, then tap Refresh."
    }

    private func activeSyncLoop() async {
        guard !appState.isWorkerPreview else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double(SyncPolicy.activeRefreshSeconds)))
            guard !Task.isCancelled, scenePhase == .active else { continue }
            await appState.refresh(showErrors: false)
        }
    }

    private func sectionBadge(_ section: AppSection) -> Int {
        switch section {
        case .tasks: appState.visibleGeneralTasks.filter { NotificationScope.includes($0, for: appState.currentUser) && !$0.completed && ($0.dueDate ?? "9999-12-31") <= SupabaseService.today }.count
        case .team: appState.unreadTeamCount
        case .pipeline: appState.leads.filter { $0.stage == .newLead }.count
        case .jobs: appState.leads.filter { ($0.endDate ?? "9999-12-31") < SupabaseService.today && ![.completed, .waitingForPayment, .paid, .lost].contains($0.stage) }.count
        default: 0
        }
    }
}

#if os(iOS)
private struct MobileMoreView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        List {
            Section("Work") {
                moreLink(.calendar)
                moreLink(.team)
            }
            Section("Customers") {
                moreLink(.contacts)
                moreLink(.email)
            }
            Section("Business") {
                moreLink(.accounts)
                moreLink(.fleet)
            }
            Section("Resources") {
                moreLink(.files)
                moreLink(.tools)
                Button { appState.showingAssistant = true } label: { Label("Ask ProLine", systemImage: "sparkles") }
            }
            Section {
                moreLink(.settings)
                if appState.isAdmin { Toggle("Simple mode", isOn: simpleModeBinding) }
            } footer: { if appState.isAdmin { Text("Simple mode shows the same streamlined app that workers use.") } }
        }
        .navigationTitle("More")
    }
    private var simpleModeBinding: Binding<Bool> {
        Binding(get: { appState.isAdminUsingSimpleView }, set: { appState.setMobileInterface(simple: $0) })
    }
    private func moreLink(_ section: AppSection) -> some View {
        NavigationLink(value: section) { Label(section.rawValue, systemImage: section.icon) }
            .badge(section == .team ? appState.unreadTeamCount : 0)
    }
}

private struct WorkerMoreView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        List {
            Section {
                NavigationLink(value: AppSection.calendar) { Label("Work calendar", systemImage: "calendar") }
                NavigationLink(value: AppSection.timesheet) { Label("My timesheet", systemImage: "clock") }
                NavigationLink(value: AppSection.tools) { Label("Roofing tools", systemImage: "ruler") }
            }
            if appState.isAdmin {
                Section { Toggle("Simple mode", isOn: simpleModeBinding) } footer: { Text("Turn off to return to the full CRM.") }
            }
            Section("Account") {
                LabeledContent("Signed in as", value: appState.currentUser?.name ?? "—")
                Button("Sign out", role: .destructive) { appState.signOut() }
            }
        }
        .navigationTitle("More")
    }
    private var simpleModeBinding: Binding<Bool> {
        Binding(get: { appState.isAdminUsingSimpleView }, set: { appState.setMobileInterface(simple: $0) })
    }
}
#endif

private struct SectionContent: View {
    @Environment(AppState.self) private var appState
    let section: AppSection
    var body: some View {
        if !appState.canAccess(section) && section != .settings {
            ContentUnavailableView("Administrator access required", systemImage: "lock.shield", description: Text("This section contains restricted company or financial information."))
        } else {
            switch section {
            case .dashboard: if appState.usesAdminInterface { DashboardView() } else { WorkerHomeView() }
            case .pipeline: PipelineView()
            case .jobs: if appState.usesAdminInterface { JobsView() } else { WorkerJobsView() }
            case .tasks: if appState.usesAdminInterface { TasksView() } else { WorkerTasksView() }
            case .email: EmailWorkspaceView()
            case .calendar: if appState.usesAdminInterface { CRMCalendarView() } else { WorkerCalendarView() }
            case .team: TeamHubView()
            case .contacts: ContactsView()
            case .files: FilesView()
            case .fleet: FleetView()
            case .accounts: AccountsWorkspaceView()
            case .finance: FinanceCentreView()
            case .reports: ReportsView()
            case .timesheet: TimesheetView()
            case .cis: CISView()
            case .tools: RoofingToolsView()
            case .settings: SettingsView()
            }
        }
    }
}

struct JobsView: View {
    @Environment(AppState.self) private var appState
    @State private var search="";@State private var stage:LeadStage?
    private var jobs:[Lead]{appState.leads.filter{[.won,.scheduled,.inProgress,.waitingForPayment].contains($0.stage)}.filter{lead in (stage==nil || lead.stage==stage) && (search.isEmpty || [lead.name,lead.jobRef,lead.address,lead.jobType].contains{$0.localizedCaseInsensitiveContains(search)})}}
    var body: some View {
        #if os(macOS)
        VStack(alignment:.leading,spacing:0){HStack{VStack(alignment:.leading,spacing:3){Text(appState.usesAdminInterface ? "Jobs" : "My Jobs").font(.system(size:29,weight:.bold));Text(appState.usesAdminInterface ? "Plan work, monitor delivery and get every job paid." : "Only work assigned to you.").foregroundStyle(.secondary)};Spacer();Text(appState.leads.filter{$0.stage == .inProgress}.count.description).font(.title2.bold()).foregroundStyle(.orange);Text("live jobs").foregroundStyle(.secondary)}.padding(.horizontal,24).padding(.top,18);if appState.usesAdminInterface{HStack(spacing:12){JobMetric("Scheduled",appState.leads.filter{$0.stage == .scheduled}.count,"calendar.badge.clock",.teal);JobMetric("In progress",appState.leads.filter{$0.stage == .inProgress}.count,"hammer",.orange);JobMetric("Awaiting payment",appState.leads.filter{$0.stage == .waitingForPayment}.count,"clock",.indigo);JobMetric("To collect",appState.leads.filter{[.won,.scheduled,.inProgress,.completed,.waitingForPayment].contains($0.stage)}.reduce(0){$0+$1.balance}.formatted(.currency(code:"GBP").precision(.fractionLength(0))),"sterlingsign.circle",.purple)}.padding(.horizontal,24).padding(.top,16)};HStack{HStack{Image(systemName:"magnifyingglass");TextField("Search customer, job or address…",text:$search)}.padding(.horizontal,10).frame(width:310,height:36).background(.background,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(.quaternary));Menu(stage?.displayName ?? "All job stages"){Button("All job stages"){stage=nil};ForEach([LeadStage.won,.scheduled,.inProgress,.waitingForPayment]){s in Button(s.displayName){stage=s}}};Spacer();Text("\(jobs.count) jobs").font(.caption).foregroundStyle(.secondary)}.padding(24);ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:290,maximum:380),spacing:14)],spacing:14){ForEach(jobs){lead in NavigationLink{jobDestination(lead)}label:{JobCard(lead:lead)}.buttonStyle(.plain)}}.padding(.horizontal,24).padding(.bottom,24)}.overlay{if jobs.isEmpty{ContentUnavailableView("No jobs assigned",systemImage:"hammer",description:Text(appState.usesAdminInterface ? "Jobs appear here after a lead is won." : "Your assigned jobs will appear here."))}}}.background(Color(nsColor:.windowBackgroundColor)).navigationTitle(appState.usesAdminInterface ? "Jobs" : "My Jobs")
        #else
        List(jobs){lead in NavigationLink{jobDestination(lead)}label:{LeadRow(lead:lead)}}.searchable(text:$search).navigationTitle(appState.usesAdminInterface ? "Jobs" : "My Jobs")
        #endif
    }
    @ViewBuilder private func jobDestination(_ lead: Lead) -> some View {
        if appState.usesAdminInterface { LeadDetailView(leadID: lead.id) } else { WorkerJobDetailView(leadID: lead.id) }
    }
}

private struct WorkerJobsView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var showingCompleted = false

    private var jobs: [Lead] {
        appState.leads
            .filter { showingCompleted ? [.completed, .waitingForPayment, .paid].contains($0.stage) : [.won, .scheduled, .inProgress].contains($0.stage) }
            .filter { search.isEmpty || [$0.name, $0.jobRef, $0.address, $0.jobType].contains { $0.localizedCaseInsensitiveContains(search) } }
            .sorted { ($0.startDate ?? "9999", $0.name) < ($1.startDate ?? "9999", $1.name) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("Jobs", selection: $showingCompleted) {
                    Text("Current").tag(false)
                    Text("Completed").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 2)

                if jobs.isEmpty {
                    ContentUnavailableView(
                        showingCompleted ? "No completed jobs" : "No current jobs",
                        systemImage: showingCompleted ? "checkmark.seal" : "hammer",
                        description: Text(search.isEmpty ? "Your assigned jobs will appear here." : "Try a different search.")
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(jobs) { lead in
                        NavigationLink { WorkerJobDetailView(leadID: lead.id) } label: {
                            WorkerJobRow(lead: lead)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 720)
        }
        .background(Color.primary.opacity(0.025))
        .navigationTitle("My Jobs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $search, prompt: "Customer, job or address")
    }
}

private struct WorkerHomeView: View {
    @Environment(AppState.self) private var appState
    private var today: String { SupabaseService.today }
    private var firstName: String { appState.currentUser?.name.split(separator: " ").first.map(String.init) ?? "there" }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Morning" : hour < 18 ? "Afternoon" : "Evening"
    }
    private var todayJobs: [Lead] {
        appState.leads.filter { lead in
            guard [.won, .scheduled, .inProgress].contains(lead.stage), let start = lead.startDate, start <= today else { return false }
            if let end = lead.endDate { return end >= today }
            return start == today
        }.sorted { ($0.stage == .inProgress ? 0 : 1, $0.name) < ($1.stage == .inProgress ? 0 : 1, $1.name) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                        Text("\(greeting), \(firstName)").font(.title2.bold())
                    }
                    Spacer()
                    Circle().fill(.orange.gradient).frame(width: 44, height: 44)
                        .overlay(Text(firstName.prefix(1)).font(.headline).foregroundStyle(.white))
                }

                if let firstJob = todayJobs.first {
                    NavigationLink { WorkerJobDetailView(leadID: firstJob.id) } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label(firstJob.stage == .inProgress ? "JOB TODAY" : "NEXT JOB", systemImage: firstJob.stage == .inProgress ? "hammer.fill" : "calendar")
                                    .font(.caption.bold()).tracking(0.5)
                                Spacer()
                                Text(firstJob.jobRef).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.72))
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(firstJob.name).font(.title2.bold())
                                Text(firstJob.jobType).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                                if !firstJob.address.isEmpty {
                                    Label(firstJob.address, systemImage: "mappin.and.ellipse")
                                        .font(.subheadline).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
                                }
                            }
                            HStack {
                                Text("Open job").font(.headline)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").font(.title2)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(18)
                        .background(
                            LinearGradient(colors: [Color(red: 0.04, green: 0.16, blue: 0.23), Color(red: 0.03, green: 0.28, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(todayJobs.dropFirst()) { lead in
                        NavigationLink { WorkerJobDetailView(leadID: lead.id) } label: { WorkerJobRow(lead: lead) }
                            .buttonStyle(.plain)
                    }
                } else {
                    Label("No job booked today", systemImage: "sun.max.fill")
                        .font(.headline).foregroundStyle(.secondary).padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }

                HStack(spacing: 12) {
                    NavigationLink { TimesheetView() } label: {
                        quickAction(
                            todayEntry == nil ? "Record time" : "Time recorded",
                            todayEntry == nil ? "clock.fill" : "checkmark.circle.fill",
                            todayEntry == nil ? .orange : .green
                        )
                    }
                    Button { appState.selectedSection = .tasks } label: {
                        quickAction(dueTasks.isEmpty ? "No tasks due" : "\(dueTasks.count) task\(dueTasks.count == 1 ? "" : "s") due", "checklist", dueTasks.isEmpty ? .green : .orange)
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Text("Due today").font(.headline)
                    Spacer()
                    if !dueTasks.isEmpty {
                        Button("See all") { appState.selectedSection = .tasks }.font(.subheadline.weight(.semibold))
                    }
                }
                if dueTasks.isEmpty {
                    Label("You’re all caught up", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dueTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                            Button { Task { await appState.toggleGeneralTask(task) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "circle").font(.title3).foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title).fontWeight(.semibold).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                        Text(task.dueDate == today ? "Due today" : "Overdue").font(.caption).foregroundStyle(task.dueDate == today ? .orange : .red)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                            if index < min(dueTasks.count, 3) - 1 { Divider().padding(.leading, 34) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(16)
            .frame(maxWidth: 720)
        }
        .background(Color.primary.opacity(0.025))
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func quickAction(_ title: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            Text(title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.12)))
    }
}

private struct WorkerJobRow: View {
    let lead: Lead
    private var tint: Color { lead.stage == .inProgress ? .orange : lead.stage == .scheduled ? .blue : lead.stage == .waitingForPayment ? .indigo : [.completed, .paid].contains(lead.stage) ? .green : .teal }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: lead.stage == .inProgress ? "hammer.fill" : lead.stage == .scheduled ? "calendar" : lead.stage == .waitingForPayment ? "clock.fill" : [.completed, .paid].contains(lead.stage) ? "checkmark" : "house.fill")
                .font(.headline).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(lead.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(lead.jobRef).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Text(lead.address.isEmpty ? lead.jobType : lead.address).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(lead.stage.displayName).font(.caption.bold()).foregroundStyle(tint)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.1)))
    }
}

private struct WorkerCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private var days: [Date] { (0..<21).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) } }
    private var selectedJobs: [Lead] { jobs(on: selected) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tap a day to see where you’re working.").font(.subheadline).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) { ForEach(days, id: \.self) { day in dayButton(day) } }
                }
                HStack {
                    Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.title3.bold())
                    Spacer()
                    Text("\(selectedJobs.count) job\(selectedJobs.count == 1 ? "" : "s")").font(.caption.bold()).foregroundStyle(.secondary)
                }
                if selectedJobs.isEmpty {
                    Label("No work booked for this day", systemImage: "calendar.badge.checkmark").foregroundStyle(.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(selectedJobs) { lead in
                    NavigationLink { WorkerJobDetailView(leadID: lead.id) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(.orange).frame(width: 48, height: 48).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lead.name).font(.headline).foregroundStyle(.primary)
                                Text(lead.jobType).font(.subheadline).foregroundStyle(.secondary)
                                Label(lead.address.isEmpty ? "Address not added" : lead.address, systemImage: "location.fill").font(.caption).foregroundStyle(lead.address.isEmpty ? .red : .blue).lineLimit(2)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                    }.buttonStyle(.plain)
                }
            }.padding(16).frame(maxWidth: 720)
        }
        .background(Color.primary.opacity(0.025))
        .navigationTitle("Work Calendar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        let selectedDay = Calendar.current.isDate(day, inSameDayAs: selected)
        let count = jobs(on: day).count
        return Button { selected = day } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption.bold())
                Text("\(Calendar.current.component(.day, from: day))").font(.headline)
                Circle().fill(count > 0 ? Color.orange : Color.clear).frame(width: 7, height: 7)
            }.frame(width: 50, height: 70).foregroundStyle(selectedDay ? Color.orange : Color.primary).background(selectedDay ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(selectedDay ? Color.orange : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) jobs")
    }
}

private struct WorkerTasksView: View {
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
                    taskRow(title: item.task.title, detail: "\(item.lead.name) · \(dueText(item.task.dueDate))", overdue: isOverdue(item.task.dueDate)) {
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
        HStack { Text(title).font(.title3.bold()); Spacer(); Text("\(count)").font(.caption.bold()).foregroundStyle(.secondary) }
            .textCase(nil)
    }
    private func taskRow(title: String, detail: String, overdue: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle").font(.title3).foregroundStyle(.orange).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(detail).font(.caption).foregroundStyle(overdue ? .red : .secondary)
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
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    var body: some View {
        Group {
            if let lead {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) { Text(lead.name).font(.largeTitle.bold()); Text("\(lead.jobRef) · \(lead.jobType)").foregroundStyle(.secondary); Text(lead.stage.displayName).font(.caption.bold()).foregroundStyle(.orange).padding(.horizontal, 9).padding(.vertical, 5).background(Color.orange.opacity(0.12), in: Capsule()) }
                        VStack(spacing: 0) {
                            workerDetailRow("Address", lead.address.isEmpty ? "Not added" : lead.address, "mappin.and.ellipse")
                            if !lead.phone.isEmpty { HStack { Label("Customer", systemImage: "phone.fill"); Spacer(); PhoneActionMenu(number: lead.phone, label: lead.phone) }.padding(15) }
                            if let start = lead.startDate { workerDetailRow("Starts", start, "calendar") }
                            if let end = lead.endDate { workerDetailRow("Expected finish", end, "flag.checkered") }
                        }.background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                        if !lead.address.isEmpty { WorkerJobMapCard(lead: lead) }
                        HStack(spacing: 10) {
                            Button { showingAddNote = true } label: { Label("Add note", systemImage: "square.and.pencil").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7) }
                                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                            Button { showingUpdate = true } label: { Label("Voice update", systemImage: "mic.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7) }
                                .buttonStyle(.bordered).tint(.orange).controlSize(.large).disabled(appState.isWorkerPreview)
                        }
                        HStack { Text("Job notes").font(.title3.bold()); Spacer(); Text(lead.notes.isEmpty ? "None yet" : "\(lead.notes.count)").font(.caption.bold()).foregroundStyle(.secondary) }
                        if lead.notes.isEmpty {
                            Label("No notes yet. Add one to keep everyone up to date.", systemImage: "note.text.badge.plus")
                                .foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(lead.notes.enumerated()), id: \.element.id) { index, note in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "note.text").foregroundStyle(.orange).frame(width: 28, height: 28)
                                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(note.content).frame(maxWidth: .infinity, alignment: .leading)
                                            Text([note.author, note.date].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(15)
                                    if index < lead.notes.count - 1 { Divider().padding(.leading, 55) }
                                }
                            }.background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                        }
                        HStack { Text("Checklist").font(.title3.bold()); Spacer(); Text("\(lead.tasks.filter(\.completed).count)/\(lead.tasks.count)").font(.caption.bold()).foregroundStyle(.secondary) }
                        if lead.tasks.isEmpty { Text("No checklist items yet.").foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 14)) }
                        ForEach(lead.tasks) { task in Button { Task { await appState.toggleLeadTask(leadID: lead.id, taskID: task.id) } } label: { HStack(spacing: 13) { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(task.completed ? .green : .orange); VStack(alignment: .leading, spacing: 3) { Text(task.title).fontWeight(.semibold).foregroundStyle(.primary).strikethrough(task.completed); if let due = task.dueDate { Text(due).font(.caption).foregroundStyle(!task.completed && due < SupabaseService.today ? .red : .secondary) } }; Spacer() }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) }
                    }.padding(16).frame(maxWidth: 720)
                }.background(Color.secondary.opacity(0.045)).navigationTitle("Job")
                    .sheet(isPresented: $showingUpdate) { JobUpdateSheet(leadID: lead.id) }
                    .sheet(isPresented: $showingAddNote) { WorkerAddJobNoteSheet(leadID: lead.id) }
            } else { ContentUnavailableView("Job not found", systemImage: "hammer", description: Text("This job may no longer be assigned to you.")) }
        }
    }
    private func workerDetailRow(_ title: String, _ value: String, _ icon: String) -> some View { HStack(spacing: 12) { Label(title, systemImage: icon); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.padding(15) }
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
                        if note.isEmpty { Text("What happened on the job?").foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8) }
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
    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = lead.lat, let lng = lead.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    private var mapsURL: URL? { ContactLinks.maps(address: lead.address) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Job location", systemImage: "map.fill").font(.headline)
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                    Marker(lead.name, coordinate: coordinate).tint(.orange)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.quaternary))
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "map").font(.largeTitle).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) { Text(lead.address).fontWeight(.semibold); Text("Tap below to see the map and get directions.").font(.caption).foregroundStyle(.secondary) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            }
            if let mapsURL {
                Link(destination: mapsURL) { Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7) }.buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}

#if os(macOS)
private struct JobMetric:View{let title:String;let value:String;let icon:String;let tint:Color;init(_ title:String,_ value:Int,_ icon:String,_ tint:Color){self.title=title;self.value="\(value)";self.icon=icon;self.tint=tint};init(_ title:String,_ value:String,_ icon:String,_ tint:Color){self.title=title;self.value=value;self.icon=icon;self.tint=tint};var body:some View{HStack(spacing:12){Image(systemName:icon).font(.title2).foregroundStyle(tint);VStack(alignment:.leading){Text(value).font(.title2.bold());Text(title).font(.caption).foregroundStyle(.secondary)}}.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.quaternary))}}
private struct JobCard:View{let lead:Lead;private var tint:Color{switch lead.stage{case .scheduled:.teal;case .inProgress:.orange;case .waitingForPayment:.indigo;case .completed,.paid:.green;default:.blue}};var body:some View{VStack(alignment:.leading,spacing:12){HStack{Text(lead.jobRef).font(.caption.bold()).foregroundStyle(.secondary);Spacer();Text(lead.stage.displayName).font(.caption.bold()).foregroundStyle(tint).padding(.horizontal,8).padding(.vertical,4).background(tint.opacity(0.1),in:Capsule())};VStack(alignment:.leading,spacing:3){Text(lead.name).font(.headline);Text(lead.jobType).foregroundStyle(.secondary);Label(lead.address.isEmpty ? "Address not added":lead.address,systemImage:"mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)};ProgressView(value:Double(lead.progress),total:100).tint(tint);HStack{Text("\(lead.progress)% complete").font(.caption).foregroundStyle(.secondary);Spacer();Text(lead.value,format:.currency(code:"GBP").precision(.fractionLength(0))).fontWeight(.semibold)};HStack{Label(lead.startDate ?? "Date not set",systemImage:"calendar");Spacer();Image(systemName:"chevron.right")}.font(.caption).foregroundStyle(.secondary)}.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(.quaternary)).contentShape(Rectangle())}}
#endif
