import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var detailPath = NavigationPath()
    private var availableSections: [AppSection] {
        [.dashboard, .pipeline, .leads, .jobs, .tasks, .email, .calendar, .team, .contacts, .files, .fleet, .accounts, .tools, .settings].filter(appState.canAccess)
    }
    private var mobileTabs: [AppSection] { appState.isAdmin ? [.dashboard, .pipeline, .tasks] : [.pipeline, .tasks, .calendar] }
    var body: some View {
        @Bindable var appState = appState
        #if os(iOS)
        TabView(selection: $appState.selectedSection) {
            ForEach(mobileTabs) { section in
                NavigationStack {
                    SectionContent(section: section)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                if !appState.syncIssues.isEmpty {
                                    Button(action: showSyncIssues) { Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(.orange) }
                                        .accessibilityLabel("Data sync issue")
                                }
                                Button { appState.showingGlobalSearch = true } label: { Image(systemName: "magnifyingglass") }
                                Button { appState.showingAssistant = true } label: { Image(systemName: "sparkles") }
                                if section != .tasks && section != .pipeline {
                                    Button { appState.showingGlobalAddLead = true } label: { Image(systemName: "plus") }
                                }
                            }
                        }
                }
                    .tabItem { Label(section.rawValue, systemImage: section.icon) }
                    .badge(sectionBadge(section))
                    .tag(section)
            }
            NavigationStack { MobileMoreView() }
                .tabItem { Label("More", systemImage: "ellipsis") }
                .badge(appState.unreadTeamCount)
                .tag(AppSection.settings)
        }
        .sheet(isPresented: $appState.showingGlobalSearch) { GlobalSearchView() }
        .sheet(isPresented: $appState.showingAssistant) { OperationsAssistantView() }
        .sheet(isPresented: $appState.showingGlobalAddLead) { AddLeadView(defaultStage: .newLead) }
        .onAppear { ensureAllowedSelection() }
        .onOpenURL(perform: openDeepLink)
        .onReceive(NotificationCenter.default.publisher(for: .crmNotificationDeepLink)) { note in
            if let url = note.object as? URL { openDeepLink(url) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await appState.refresh(showErrors: false) } } }
        .task { await activeSyncLoop() }
        #else
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) { Text("PRO").foregroundStyle(.white); Text("LINE").foregroundStyle(Color(red: 1, green: 0.29, blue: 0.04)) }
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Text("ROOFING CRM").font(.system(size: 9, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.72))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                Button { appState.showingGlobalAddLead = true } label: { Label("Add lead", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9) }
                    .buttonStyle(.plain).foregroundStyle(.white).background(Color(red: 1, green: 0.29, blue: 0.04), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 16).padding(.bottom, 18)
                List(selection: $appState.selectedSection) {
                    ForEach(availableSections) { section in
                        HStack {
                            Label(section.rawValue, systemImage: section.icon)
                            Spacer()
                            let count = sectionBadge(section)
                            if count > 0 {
                                Text("\(count)").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange, in: Capsule()).foregroundStyle(.white)
                            }
                        }
                        .font(.system(size: 14, weight: appState.selectedSection == section ? .semibold : .regular))
                        .foregroundStyle(appState.selectedSection == section ? Color.white : Color.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).contentShape(Rectangle())
                        .tag(section)
                        .listRowBackground(appState.selectedSection == section ? Color.white.opacity(0.10) : Color.clear)
                    }
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden)
                .onChange(of: appState.selectedSection) { _, _ in
                    detailPath = NavigationPath()
                    appState.navigationResetID = UUID()
                }
            }
            .background(LinearGradient(colors: [Color(red: 0.025, green: 0.10, blue: 0.16), Color(red: 0.02, green: 0.14, blue: 0.21)], startPoint: .top, endPoint: .bottom))
            .safeAreaInset(edge: .bottom) {
                if let user = appState.currentUser {
                    HStack { Circle().fill(Color.orange).frame(width: 30, height: 30).overlay(Text(user.name.prefix(1)).font(.caption.bold()).foregroundStyle(.white)); VStack(alignment: .leading) { Text(user.name).lineLimit(1).font(.caption.bold()); Text(user.role.capitalized).font(.caption2).foregroundStyle(.white.opacity(0.55)) }; Spacer(); Menu { Button("Sign Out", role: .destructive) { appState.signOut() } } label: { Image(systemName: "chevron.down") } }
                        .foregroundStyle(.white).padding(16).background(Color.black.opacity(0.12))
                }
            }.navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 220)
        } detail: {
            NavigationStack {
                SectionContent(section: appState.selectedSection)
            }
            .id(appState.selectedSection)
            .toolbar {
                Button { appState.showingGlobalSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
                Button { appState.showingAssistant = true } label: { Label("Assistant", systemImage: "sparkles") }
                if !appState.syncIssues.isEmpty {
                    Button(action: showSyncIssues) { Label("Data sync issue", systemImage: "exclamationmark.icloud.fill") }.foregroundStyle(.orange)
                }
                Button { Task { await appState.refresh() } } label: {
                    if appState.isRefreshing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }.disabled(appState.isRefreshing)
            }
        }
        .sheet(isPresented: $appState.showingGlobalAddLead) { AddLeadView(defaultStage: .newLead) }
        .sheet(isPresented: $appState.showingGlobalSearch) { GlobalSearchView() }
        .sheet(isPresented: $appState.showingAssistant) { OperationsAssistantView() }
        .onOpenURL(perform: openDeepLink)
        .onReceive(NotificationCenter.default.publisher(for: .crmNotificationDeepLink)) { note in
            if let url = note.object as? URL { openDeepLink(url) }
        }
        .onAppear { ensureAllowedSelection() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await appState.refresh(showErrors: false) } } }
        .task { await activeSyncLoop() }
        #endif
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme == "prolinecrm" else { return }
        let components = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        guard let kind = components.first else { return }
        if kind == "lead", components.count > 1 {
            appState.selectedLeadID = components[1]
            appState.showingGlobalSearch = true
        } else if kind.caseInsensitiveCompare("team") == .orderedSame, appState.canAccess(.team) {
            appState.selectedSection = .team
        } else if let section = AppSection.allCases.first(where: { $0.rawValue.lowercased() == kind.lowercased() }), appState.canAccess(section) {
            appState.selectedSection = section
        }
    }

    private func ensureAllowedSelection() {
        if !appState.canAccess(appState.selectedSection) {
            appState.selectedSection = appState.isAdmin ? .dashboard : .pipeline
        }
        #if os(iOS)
        if !mobileTabs.contains(appState.selectedSection) && appState.selectedSection != .settings {
            appState.selectedSection = appState.isAdmin ? .dashboard : .pipeline
        }
        #endif
    }

    private func showSyncIssues() {
        appState.errorMessage = "Some CRM data is not currently synced: \(appState.syncIssues.joined(separator: ", ")). Existing data is still shown. Check your connection or Supabase setup, then tap Refresh."
    }

    private func activeSyncLoop() async {
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
        case .pipeline, .leads: appState.leads.filter { $0.stage == .newLead }.count
        case .jobs: appState.leads.filter { ($0.endDate ?? "9999-12-31") < SupabaseService.today && ![.completed, .paid, .lost].contains($0.stage) }.count
        default: 0
        }
    }
}

#if os(iOS)
private struct MobileMoreView: View {
    @Environment(AppState.self) private var appState
    private var sections: [AppSection] {
        [.jobs, .team, .leads, .email, .calendar, .contacts, .files, .fleet, .accounts, .tools, .settings].filter(appState.canAccess)
    }
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("More").font(.largeTitle.bold())
                    Text("Everything you need to run the company.").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sections) { section in
                        NavigationLink { SectionContent(section: section) } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: section.icon).font(.title2).foregroundStyle(.orange)
                                Text(section.rawValue).font(.headline).foregroundStyle(.primary)
                                Text(detail(section)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
                            .padding(15).background(.background, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                        }.buttonStyle(.plain)
                    }
                }
                if let user = appState.currentUser {
                    HStack { Circle().fill(.orange.gradient).frame(width: 42, height: 42).overlay(Text(user.name.prefix(1)).font(.headline).foregroundStyle(.white)); VStack(alignment:.leading){Text(user.name).fontWeight(.semibold);Text(user.role.capitalized).font(.caption).foregroundStyle(.secondary)};Spacer();Button("Sign out",role:.destructive){appState.signOut()} }.padding(15).background(.background,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(.quaternary))
                }
            }.padding()
        }.background(Color(.systemGroupedBackground)).navigationBarTitleDisplayMode(.inline)
    }
    private func detail(_ section: AppSection) -> String { switch section { case .jobs:"Scheduled, active and completed work";case .team:"Messages and day planning";case .leads:"Enquiries and customers";case .email:"Gmail actions and follow-ups";case .calendar:"Surveys and job dates";case .contacts:"Customer directory";case .files:"Photos and documents";case .fleet:"Vans, MOT and servicing";case .accounts:"Money, reports, payroll and CIS";case .tools:"Roofing calculators for site";case .finance:"Deposits and balances";case .reports:"Performance and revenue";case .timesheet:"Hours and payroll";case .cis:"Contractor deductions";case .settings:"Team and app setup";default:"" } }
}
#endif

private struct SectionContent: View {
    @Environment(AppState.self) private var appState
    let section: AppSection
    var body: some View {
        if !appState.canAccess(section) {
            ContentUnavailableView("Administrator access required", systemImage: "lock.shield", description: Text("This section contains restricted company or financial information."))
        } else {
            switch section {
            case .dashboard: DashboardView()
            case .pipeline: PipelineView()
            case .leads: LeadListView(stages: [.newLead, .surveyBooked, .quoteSent], title: "Leads")
            case .jobs: JobsView()
            case .tasks: TasksView()
            case .email: EmailWorkspaceView()
            case .calendar: CRMCalendarView()
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
    private var jobs:[Lead]{appState.leads.filter{[.won,.scheduled,.inProgress,.completed,.paid].contains($0.stage)}.filter{lead in (stage==nil || lead.stage==stage) && (search.isEmpty || [lead.name,lead.jobRef,lead.address,lead.jobType].contains{$0.localizedCaseInsensitiveContains(search)})}}
    var body: some View {
        #if os(macOS)
        VStack(alignment:.leading,spacing:0){HStack{VStack(alignment:.leading,spacing:3){Text("Jobs").font(.system(size:29,weight:.bold));Text("Plan work, monitor delivery and get every job paid.").foregroundStyle(.secondary)};Spacer();Text(appState.leads.filter{$0.stage == .inProgress}.count.description).font(.title2.bold()).foregroundStyle(.orange);Text("live jobs").foregroundStyle(.secondary)}.padding(.horizontal,24).padding(.top,18);HStack(spacing:12){JobMetric("Scheduled",appState.leads.filter{$0.stage == .scheduled}.count,"calendar.badge.clock",.teal);JobMetric("In progress",appState.leads.filter{$0.stage == .inProgress}.count,"hammer",.orange);JobMetric("Completed",appState.leads.filter{$0.stage == .completed}.count,"checkmark.seal",.green);JobMetric("To collect",appState.leads.filter{[.won,.scheduled,.inProgress,.completed].contains($0.stage)}.reduce(0){$0+$1.balance}.formatted(.currency(code:"GBP").precision(.fractionLength(0))),"sterlingsign.circle",.purple)}.padding(.horizontal,24).padding(.top,16);HStack{HStack{Image(systemName:"magnifyingglass");TextField("Search customer, job or address…",text:$search)}.padding(.horizontal,10).frame(width:310,height:36).background(.background,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(.quaternary));Menu(stage?.displayName ?? "All job stages"){Button("All job stages"){stage=nil};ForEach([LeadStage.won,.scheduled,.inProgress,.completed,.paid]){s in Button(s.displayName){stage=s}}};Spacer();Text("\(jobs.count) jobs").font(.caption).foregroundStyle(.secondary)}.padding(24);ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:290,maximum:380),spacing:14)],spacing:14){ForEach(jobs){lead in NavigationLink{LeadDetailView(leadID:lead.id)}label:{JobCard(lead:lead)}.buttonStyle(.plain)}}.padding(.horizontal,24).padding(.bottom,24)}.overlay{if jobs.isEmpty{ContentUnavailableView("No matching jobs",systemImage:"hammer",description:Text("Jobs appear here after a lead is won."))}}}.background(Color(nsColor:.windowBackgroundColor)).navigationTitle("Jobs")
        #else
        List(jobs){lead in NavigationLink{LeadDetailView(leadID:lead.id)}label:{LeadRow(lead:lead)}}.searchable(text:$search).navigationTitle("Jobs")
        #endif
    }
}

#if os(macOS)
private struct JobMetric:View{let title:String;let value:String;let icon:String;let tint:Color;init(_ title:String,_ value:Int,_ icon:String,_ tint:Color){self.title=title;self.value="\(value)";self.icon=icon;self.tint=tint};init(_ title:String,_ value:String,_ icon:String,_ tint:Color){self.title=title;self.value=value;self.icon=icon;self.tint=tint};var body:some View{HStack(spacing:12){Image(systemName:icon).font(.title2).foregroundStyle(tint);VStack(alignment:.leading){Text(value).font(.title2.bold());Text(title).font(.caption).foregroundStyle(.secondary)}}.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.quaternary))}}
private struct JobCard:View{let lead:Lead;private var tint:Color{switch lead.stage{case .scheduled:.teal;case .inProgress:.orange;case .completed,.paid:.green;default:.blue}};var body:some View{VStack(alignment:.leading,spacing:12){HStack{Text(lead.jobRef).font(.caption.bold()).foregroundStyle(.secondary);Spacer();Text(lead.stage.displayName).font(.caption.bold()).foregroundStyle(tint).padding(.horizontal,8).padding(.vertical,4).background(tint.opacity(0.1),in:Capsule())};VStack(alignment:.leading,spacing:3){Text(lead.name).font(.headline);Text(lead.jobType).foregroundStyle(.secondary);Label(lead.address.isEmpty ? "Address not added":lead.address,systemImage:"mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)};ProgressView(value:Double(lead.progress),total:100).tint(tint);HStack{Text("\(lead.progress)% complete").font(.caption).foregroundStyle(.secondary);Spacer();Text(lead.value,format:.currency(code:"GBP").precision(.fractionLength(0))).fontWeight(.semibold)};HStack{Label(lead.startDate ?? "Date not set",systemImage:"calendar");Spacer();Image(systemName:"chevron.right")}.font(.caption).foregroundStyle(.secondary)}.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(.quaternary)).contentShape(Rectangle())}}
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @AppStorage("notifyTeam") private var notifyTeam = true
    @State private var showingInviteWorker = false
    @State private var showingAddUser = false
    var body: some View {
        #if os(macOS)
        MacSettingsView()
        #else
        Form {
            Section("Notifications") { Toggle("Team messages", isOn: $notifyTeam); Button("Enable Native Notifications") { Task { await appState.enableNotifications() } } }
            if appState.isAdmin {
                Section("Users") {
                    ForEach(appState.users) { user in LabeledContent(user.name) { Text(user.role.capitalized).foregroundStyle(.secondary) } }
                    Button { showingAddUser = true } label: { Label("Add user", systemImage: "person.crop.circle.badge.plus") }
                    Button { showingInviteWorker = true } label: { Label("Invite user", systemImage: "paperplane") }
                }
                Section("Gmail assistant") {
                    if let status = appState.gmailConnectionStatus, status.connected { LabeledContent(status.gmailAddress ?? "Connected") { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } } else { Label("Gmail not connected", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                    Text("Important emails become admin tasks and useful replies are saved to Gmail Drafts. Nothing is ever sent automatically.").font(.caption).foregroundStyle(.secondary)
                    Button(appState.gmailConnectionStatus?.connected == true ? "Reconnect Gmail" : "Connect Gmail") { Task { if let url = await appState.gmailAuthorizationURL() { openURL(url) } } }
                }
            }
            Section("Account") { LabeledContent("Signed in as", value: appState.currentUser?.name ?? "—"); Button("Sign Out", role: .destructive) { appState.signOut() } }
        }
        .formStyle(.grouped).navigationTitle("Settings")
        .sheet(isPresented: $showingAddUser) { AddSecureUserSheet() }
        .sheet(isPresented: $showingInviteWorker) { InviteWorkerSheet() }
        .task { await appState.refreshGmailConnectionStatus() }
        #endif
    }
}
