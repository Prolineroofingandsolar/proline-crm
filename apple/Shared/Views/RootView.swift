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
            ("Resources", [.files, .tools]),
        ]
    }
    private var workerSections: [AppSection] { [.dashboard, .calendar, .jobs, .tasks, .timesheet, .tools] }
    private var mobileTabs: [AppSection] {
        appState.usesAdminInterface ? [.dashboard, .pipeline, .jobs, .tasks] : [.dashboard, .jobs, .tasks]
    }

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
                                        Button {
                                            appState.showingGlobalSearch = true
                                        } label: {
                                            Image(systemName: "magnifyingglass")
                                        }
                                        .accessibilityLabel("Search")
                                        if section == .dashboard || section == .pipeline {
                                            Button {
                                                appState.showingGlobalAddLead = true
                                            } label: {
                                                Image(systemName: "plus")
                                            }
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
        .onChange(of: appState.pendingSection) { _, section in if let section { appState.pendingSection = nil; showSection(section) } }
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
                            Label {
                                VStack(alignment: .leading) {
                                    Text(user.name).lineLimit(1); Text(user.role.capitalized).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "person.crop.circle")
                            }
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
                        Button {
                            appState.showingGlobalAddLead = true
                        } label: {
                            Label("Add lead", systemImage: "plus")
                        }
                        Button {
                            appState.showingGlobalSearch = true
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    if !appState.syncIssues.isEmpty {
                        Button(action: showSyncIssues) { Label("Data sync issue", systemImage: "exclamationmark.icloud") }
                    }
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        if appState.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }.disabled(appState.isRefreshing || appState.isWorkerPreview)
                }
            }
            .sheet(isPresented: $appState.showingGlobalAddLead) { AddLeadView(defaultStage: .newLead) }
            .sheet(isPresented: $appState.showingGlobalSearch) { GlobalSearchView() }
            .sheet(isPresented: $appState.showingAssistant) { OperationsAssistantView() }
            .sheet(item: $appState.pendingCallOutcome) { CallOutcomeSheet(pending: $0) }
            .onChange(of: appState.pendingLeadID) { _, id in if let id { showLead(id) } }
        .onChange(of: appState.pendingSection) { _, section in if let section { appState.pendingSection = nil; showSection(section) } }
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
        appState.errorMessage =
            "Some CRM data is not currently synced: \(appState.syncIssues.joined(separator: ", ")). Existing data is still shown. Check your connection or Supabase setup, then tap Refresh."
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
        case .tasks:
            appState.visibleGeneralTasks.filter {
                NotificationScope.includes($0, for: appState.currentUser) && !$0.completed
                    && ($0.dueDate ?? "9999-12-31") <= SupabaseService.today
            }.count
        case .team: appState.unreadTeamCount
        case .pipeline: appState.leads.filter { $0.stage == .newLead }.count
        case .jobs:
            appState.leads.filter {
                ($0.endDate ?? "9999-12-31") < SupabaseService.today && ![.completed, .waitingForPayment, .paid, .lost].contains($0.stage)
            }.count
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
                    Button {
                        appState.showingAssistant = true
                    } label: {
                        Label("Ask ProLine", systemImage: "sparkles")
                    }
                }
                Section {
                    moreLink(.settings)
                    if appState.isAdmin { Toggle("Simple mode", isOn: simpleModeBinding) }
                }
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
                    Section {
                        Toggle("Simple mode", isOn: simpleModeBinding)
                }
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
            ContentUnavailableView(
                "Administrator access required", systemImage: "lock.shield",
                description: Text("This section contains restricted company or financial information."))
        } else {
            switch section {
            case .dashboard:
                if appState.usesAdminInterface {
                    #if os(iOS)
                    CustomerDeckView()
                    #else
                    DashboardView()
                    #endif
                } else {
                    WorkerHomeView()
                }
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
