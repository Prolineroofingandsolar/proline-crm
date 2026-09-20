import CoreLocation
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

#if os(iOS)
    import ActivityKit
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

enum CompanyActionKind: String, Codable, Sendable {
    case generalTask, jobTask, survey, jobStart, overdueJob, quoteFollowUp, deposit, balance, timesheet
}

enum CompanyActionPriority: Int, Comparable, Sendable {
    case routine = 1
    case soon = 2
    case urgent = 3
    case critical = 4

    static func < (lhs: CompanyActionPriority, rhs: CompanyActionPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .routine: "Later";
        case .soon: "This week";
        case .urgent: "Today";
        case .critical: "Overdue"
        }
    }

    var tint: Color {
        switch self {
        case .routine: .secondary;
        case .soon: .blue;
        case .urgent: Color.accentColor;
        case .critical: .red
        }
    }
}

struct CompanyAction: Identifiable, Sendable {
    let id: String
    let kind: CompanyActionKind
    let priority: CompanyActionPriority
    let title: String
    let detail: String
    let reason: String
    let leadID: String?
    let generalTaskID: String?
    let leadTaskID: String?
    let dueDate: String?
}

@MainActor @Observable
final class AppState {
    private static let stageTasks: [LeadStage: [String]] = [
        .newLead: ["Call customer to discuss requirements", "Confirm contact details", "Check job location / access"],
        .surveyBooked: ["Confirm survey appointment with customer", "Prepare survey checklist", "Review job requirements before visit"],
        .quotePreparing: ["Complete measurements and specification", "Price labour and materials", "Prepare customer quotation"],
        .quoteSent: ["Follow up on quote within 3 days", "Answer customer questions", "Chase quote if no response after 7 days"],
        .won: ["Collect deposit", "Confirm start date with customer", "Order materials", "Brief the team on job details"],
        .scheduled: ["Confirm installation date", "Confirm access and scaffold", "Check materials and team availability"],
        .inProgress: ["Confirm materials delivered", "Daily progress check", "Take before & during photos", "Keep customer updated"],
        .completed: ["Final inspection with customer", "Take completion photos", "Send final invoice"],
        .paid: ["File all job paperwork", "Request customer review / referral", "Update job records"],
    ]
    var leads: [Lead] = []
    var users: [CRMUser] = []
    var contacts: [CRMContact] = []
    var generalTasks: [GeneralTask] = []
    /// Tasks that still belong to an active app workflow. We retain retired
    /// records in Supabase for audit/history, but they must not reappear in the
    /// UI or generate notifications after a feature is removed.
    var visibleGeneralTasks: [GeneralTask] {
        generalTasks.filter { !FleetTaskPolicy.isRetiredReminder($0) }
    }
    var timesheets: [TimesheetEntry] = []
    var adminTimesheetChecks: [TimesheetEntry] = []
    var paymentRuns: [PaymentRun] = []
    var workerPayments: [WorkerPayment] = []
    var surveys: [RoofSurvey] = []
    var quotes: [CRMQuote] = []
    var teamMessages: [TeamMessage] = []
    var teamDayPlans: [TeamDayPlan] = []
    var currentUser: CRMUser?
    /// Set by `openLead`; the root view pushes this lead onto the visible navigation stack and clears it.
    var pendingLeadID: String?
    /// Set to show a section from anywhere; the root view routes it (a tab, or a push inside More) and clears it.
    var pendingSection: AppSection?
    var selectedSection: AppSection = .dashboard
    var navigationResetID = UUID()
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var syncIssues: [String] = []
    var lastRefreshAt: Date?
    var showingGlobalSearch = false
    var showingGlobalAddLead = false
    var showingAssistant = false
    var assistantDraftPrompt: String?
    var pendingWorkerInviteToken: String?
    /// A call started from the app; when the user comes back we ask how it went.
    private var pendingCall: PendingCall?
    var pendingCallOutcome: PendingCall?
    /// Site weather for the Today screen.
    let weather = WeatherService()
    var assistantErrorMessage: String?
    var isAdminUsingSimpleView = UserDefaults.standard.bool(forKey: "adminUsesSimpleView")
    var gmailConnectionStatus: GmailConnectionStatus?
    var aiAuditEntries: [AIAuditEntry] = {
        guard let data = UserDefaults.standard.data(forKey: "aiActionAudit") else { return [] }
        return (try? JSONDecoder().decode([AIAuditEntry].self, from: data)) ?? []
    }()

    var isAuthenticated: Bool { currentUser != nil }
    var isAdmin: Bool { currentUser?.role == "admin" }
    var usesWorkerInterface: Bool {
        #if os(iOS)
            !isAdmin || isAdminUsingSimpleView
        #else
            !isAdmin
        #endif
    }
    var usesAdminInterface: Bool { isAdmin && !usesWorkerInterface }
    var isWorkerPreview: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--worker-preview") || ProcessInfo.processInfo.arguments.contains("--admin-preview")
        #else
            false
        #endif
    }
    var unreadTeamCount: Int {
        let seen = UserDefaults.standard.string(forKey: "teamLastRead.\(currentUser?.id ?? "signed-out")") ?? ""
        return teamMessages.filter { $0.authorID != currentUser?.id && $0.createdAt > seen }.count
    }

    /// Shows a customer/job in place — on the current tab's stack on iPhone, in the
    /// detail column on Mac — instead of opening a search sheet.
    func openLead(_ id: String) {
        guard leads.contains(where: { $0.id == id }) else { errorMessage = "That customer or job is not available to you."; return }
        pendingLeadID = id
    }

    /// Starts a phone call and remembers it so the outcome can be logged in one tap
    /// when the user returns. Returns the URL to open, or nil if there is no usable number.
    func beginCall(to lead: Lead) -> URL? {
        guard let url = ContactLinks.telephone(lead.phone) else { return nil }
        let call = PendingCall(id: lead.id, leadName: lead.name, startedAt: .now)
        #if os(iOS)
            pendingCall = call
        #else
            pendingCallOutcome = call
        #endif
        return url
    }

    func resumePendingCall() {
        guard let call = pendingCall else { return }
        pendingCall = nil
        // Only ask if they plausibly just came back from the call.
        if Date.now.timeIntervalSince(call.startedAt) < 3600 { pendingCallOutcome = call }
    }

    @discardableResult
    func logCall(leadID: String, outcome: CallOutcome, note: String, followUp: Date?) async -> Bool {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = cleanNote.isEmpty ? "Call: \(outcome.title)" : "Call: \(outcome.title) — \(cleanNote)"
        let author = currentUser?.name ?? "Team member"
        let followUpTask = followUp.map {
            CRMTask(
                id: UUID().uuidString, title: "Follow up with customer", completed: false, completedDate: nil,
                dueDate: SupabaseService.localDay(for: $0), isTemplate: false, priority: "medium", notes: nil)
        }
        return await commitLead(leadID, fallback: "The call could not be logged.") { lead in
            lead.notes.insert(CRMNote(id: UUID().uuidString, content: content, date: SupabaseService.today, author: author), at: 0)
            if let followUpTask { lead.tasks.append(followUpTask) }
        }
    }

    func openAssistant(with prompt: String) {
        assistantDraftPrompt = prompt
        showingAssistant = true
    }

    func toggleMobileInterface() {
        setMobileInterface(simple: !isAdminUsingSimpleView)
    }

    func setMobileInterface(simple: Bool) {
        #if os(iOS)
            guard isAdmin else { return }
            guard isAdminUsingSimpleView != simple else { return }
            isAdminUsingSimpleView = simple
            UserDefaults.standard.set(isAdminUsingSimpleView, forKey: "adminUsesSimpleView")
            selectedSection = .dashboard
            navigationResetID = UUID()
            showingGlobalSearch = false
            showingGlobalAddLead = false
            showingAssistant = false
        #endif
    }

    /// One ranked operating queue for every surface.  Views should consume this
    /// rather than independently deciding what "needs attention" means.
    var companyActions: [CompanyAction] {
        let today = SupabaseService.today
        var actions: [CompanyAction] = []
        let visibleTasks = visibleGeneralTasks.filter { NotificationScope.includes($0, for: currentUser) && !$0.completed }

        for task in visibleTasks {
            let priority: CompanyActionPriority
            let reason: String
            if let due = task.dueDate, due < today {
                priority = .critical; reason = "Overdue since \(due)"
            } else if task.dueDate == today {
                priority = .urgent; reason = "Due today"
            } else if let due = task.dueDate {
                priority = .soon; reason = "Due \(due)"
            } else {
                priority = .routine; reason = "No date set"
            }
            actions.append(
                CompanyAction(
                    id: "task-\(task.id)", kind: .generalTask, priority: priority, title: task.title, detail: task.category, reason: reason,
                    leadID: nil, generalTaskID: task.id, leadTaskID: nil, dueDate: task.dueDate))
        }

        for lead in leads where ![.paid, .lost].contains(lead.stage) {
            if lead.surveyDate == today {
                actions.append(
                    CompanyAction(
                        id: "survey-\(lead.id)", kind: .survey, priority: .urgent, title: "Survey today",
                        detail: "\(lead.name) · \(lead.jobRef)", reason: "Survey booked for today", leadID: lead.id, generalTaskID: nil,
                        leadTaskID: nil, dueDate: today))
            }
            if lead.startDate == today {
                actions.append(
                    CompanyAction(
                        id: "start-\(lead.id)", kind: .jobStart, priority: .urgent, title: "Job starts today",
                        detail: "\(lead.name) · \(lead.jobRef)", reason: "Scheduled to start today", leadID: lead.id, generalTaskID: nil,
                        leadTaskID: nil, dueDate: today))
            }
            if let end = lead.endDate, end < today, ![.completed, .waitingForPayment].contains(lead.stage) {
                actions.append(
                    CompanyAction(
                        id: "overdue-job-\(lead.id)", kind: .overdueJob, priority: .critical, title: "Job is overdue",
                        detail: "\(lead.name) · \(lead.jobRef)", reason: "Expected finish was \(end)", leadID: lead.id, generalTaskID: nil,
                        leadTaskID: nil, dueDate: end))
            }
            if lead.stage == .quoteSent {
                let date = String(lead.updatedAt.prefix(10))
                let priority: CompanyActionPriority = date < today ? .soon : .routine
                actions.append(
                    CompanyAction(
                        id: "quote-\(lead.id)", kind: .quoteFollowUp, priority: priority, title: "Follow up quote",
                        detail: "\(lead.name) · \(lead.value.formatted(.currency(code: "GBP").precision(.fractionLength(0))))",
                        reason: "Quote is waiting for a decision", leadID: lead.id, generalTaskID: nil, leadTaskID: nil, dueDate: date))
            }
            if !lead.depositPaid && lead.deposit > 0 && [.won, .scheduled, .inProgress].contains(lead.stage) {
                actions.append(
                    CompanyAction(
                        id: "deposit-\(lead.id)", kind: .deposit, priority: .urgent, title: "Collect deposit",
                        detail: "\(lead.name) · \(lead.deposit.formatted(.currency(code: "GBP").precision(.fractionLength(0))))",
                        reason: "Deposit is still outstanding", leadID: lead.id, generalTaskID: nil, leadTaskID: nil, dueDate: nil))
            }
            if [.completed, .waitingForPayment].contains(lead.stage) && lead.balance > 0 {
                actions.append(
                    CompanyAction(
                        id: "balance-\(lead.id)", kind: .balance, priority: .urgent, title: "Collect final balance",
                        detail: "\(lead.name) · \(lead.balance.formatted(.currency(code: "GBP").precision(.fractionLength(0))))",
                        reason: "Job is complete and payment is due", leadID: lead.id, generalTaskID: nil, leadTaskID: nil, dueDate: nil))
            }
            for task in lead.tasks where !task.completed {
                let priority: CompanyActionPriority
                let reason: String
                if let due = task.dueDate, due < today {
                    priority = .critical; reason = "Overdue since \(due)"
                } else if task.dueDate == today {
                    priority = .urgent; reason = "Due today"
                } else if let due = task.dueDate {
                    priority = task.priority == "high" ? .urgent : .soon; reason = "Due \(due)"
                } else if task.priority == "high" {
                    priority = .urgent; reason = "High-priority job action"
                } else if task.priority == "low" {
                    priority = .routine; reason = "Low-priority job action"
                } else {
                    priority = .soon; reason = "Next checklist item for this job"
                }
                actions.append(
                    CompanyAction(
                        id: "job-task-\(lead.id)-\(task.id)", kind: .jobTask, priority: priority, title: task.title,
                        detail: "\(lead.name) · \(lead.jobRef)", reason: reason, leadID: lead.id, generalTaskID: nil, leadTaskID: task.id,
                        dueDate: task.dueDate))
            }
        }
        if isAdmin {
            let workers = users.filter { $0.role != "admin" && $0.dayRate != nil }
            for worker in workers where !timesheets.contains(where: { $0.userID == worker.id && $0.date == today }) {
                actions.append(
                    CompanyAction(
                        id: "timesheet-\(worker.id)-\(today)", kind: .timesheet, priority: .soon, title: "Timesheet missing",
                        detail: worker.name, reason: "No work day recorded for today", leadID: nil, generalTaskID: nil, leadTaskID: nil,
                        dueDate: today))
            }
        }
        return actions.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            let left = $0.dueDate ?? "9999-12-31", right = $1.dueDate ?? "9999-12-31"
            return left == right ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : left < right
        }
    }

    /// One exact queue shared by Dashboard → Action Required and Tasks.
    var taskActions: [CompanyAction] {
        companyActions.filter { $0.kind == .generalTask || $0.kind == .jobTask }
    }

    var operationalAlerts: [CompanyAction] {
        companyActions.filter { $0.kind != .generalTask && $0.kind != .jobTask }
    }

    func canAccess(_ section: AppSection) -> Bool {
        Self.canAccess(section, role: currentUser?.role)
    }

    nonisolated static func canAccess(_ section: AppSection, role: String?) -> Bool {
        if role == "admin" { return true }
        guard role != nil else { return false }
        return [.dashboard, .calendar, .jobs, .tasks, .timesheet, .tools].contains(section)
    }

    func restoreSession() async {
        #if DEBUG
            if isWorkerPreview {
                loadWorkerPreview()
                return
            }
        #endif
        if KeychainStore.get("supabaseRefreshToken") != nil {
            do {
                if let user = try await SupabaseService.shared.restoreAuthenticatedSession() {
                    currentUser = user
                    users = [user]
                    cacheSignedInUser(user)
                    syncIssues.removeAll { $0 == "Account connection" }
                    // Session restoration is automatic. Partial optional-module
                    // failures remain visible in `syncIssues` without interrupting
                    // launch with a modal alert.
                    await refresh(showErrors: false)
                    return
                }
            } catch is SupabaseSessionExpired {
                await SupabaseService.shared.signOutAuthenticatedSession()
                KeychainStore.remove("userID")
                errorMessage = "Your secure session has expired. Sign in again to continue."
                return
            } catch {
                if currentUser == nil, let cached = cachedSignedInUser() { currentUser = cached; users = [cached] }
                if !syncIssues.contains("Account connection") { syncIssues.append("Account connection") }
                return
            }
        }
        // Sessions from the retired username/password-hash login are not restored.
        KeychainStore.remove("userID")
    }

    #if DEBUG
        private func loadWorkerPreview() {
            let adminPreview = ProcessInfo.processInfo.arguments.contains("--admin-preview")
            let worker = CRMUser(
                id: "worker-preview", name: adminPreview ? "Will" : "Sam Worker", username: "worker-preview", role: adminPreview ? "admin" : "user", dayRate: nil, cisRate: nil,
                utrNumber: nil, bankName: nil, bankAccountNumber: nil, bankSortCode: nil)
            let today = SupabaseService.today
            if adminPreview { isAdminUsingSimpleView = false }
            currentUser = worker
            users = [worker]
            leads = [
                Lead(
                    id: "preview-job-1", jobRef: "JOB-104", name: "Mr Taylor", phone: "07000 000000", email: "",
                    address: "12 Sample Close, Bristol", jobType: "Re-roof", stage: .inProgress, value: 0, deposit: 0, depositPaid: false,
                    balance: 0, source: "Preview", assignedTo: worker.name, surveyDate: nil, surveyTime: nil, startDate: today,
                    endDate: nil, completedDate: nil, paidDate: nil, progress: 45,
                    tasks: [
                        CRMTask(
                            id: "preview-task-1", title: "Finish front elevation", completed: false, completedDate: nil, dueDate: today,
                            isTemplate: false),
                        CRMTask(
                            id: "preview-task-2", title: "Photograph completed work", completed: false, completedDate: nil, dueDate: today,
                            isTemplate: false),
                    ], photos: [], notes: [], files: [], materials: [], wonDate: today, myBuilderURL: nil, reviewRequestSent: nil, lat: nil,
                    lng: nil, createdAt: today, updatedAt: today),
                Lead(
                    id: "preview-job-2", jobRef: "JOB-108", name: "Mrs Green", phone: "07000 000000", email: "",
                    address: "8 Example Road, Bath", jobType: "Flat roof", stage: .scheduled, value: 0, deposit: 0, depositPaid: false,
                    balance: 0, source: "Preview", assignedTo: worker.name, surveyDate: nil, surveyTime: nil, startDate: today,
                    endDate: nil, completedDate: nil, paidDate: nil, progress: 0,
                    tasks: [
                        CRMTask(
                            id: "preview-task-3", title: "Check materials before leaving", completed: false, completedDate: nil,
                            dueDate: today, isTemplate: false)
                    ], photos: [], notes: [], files: [], materials: [], wonDate: today, myBuilderURL: nil, reviewRequestSent: nil, lat: nil,
                    lng: nil, createdAt: today, updatedAt: today),
            ]
            generalTasks = [
                GeneralTask(
                    id: "preview-general-1", title: "Send site photos to the office", completed: false, completedDate: nil, dueDate: today,
                    priority: "medium", category: "General", notes: nil, createdAt: today, assignedTo: [worker.id])
            ]
            if adminPreview {
                let yesterday = SupabaseService.localDay(for: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
                let lastWeek = SupabaseService.localDay(for: Calendar.current.date(byAdding: .day, value: -8, to: .now) ?? .now)
                leads += [
                    Lead(id: "preview-lead-1", jobRef: "JOB-201", name: "Mr Patel", phone: "07000 111222", email: "", address: "4 Orchard Way, Keynsham", jobType: "Solar Installation", stage: .quoteSent, value: 8400, deposit: 2520, depositPaid: false, balance: 8400, source: "Website", assignedTo: worker.name, surveyDate: nil, surveyTime: nil, startDate: nil, endDate: nil, completedDate: nil, paidDate: nil, progress: 0, tasks: [], photos: [], notes: [], files: [], materials: [], wonDate: nil, myBuilderURL: nil, reviewRequestSent: nil, lat: nil, lng: nil, createdAt: lastWeek, updatedAt: lastWeek),
                    Lead(id: "preview-lead-2", jobRef: "JOB-202", name: "Mrs Hughes", phone: "07000 333444", email: "", address: "19 Mill Lane, Bath", jobType: "Roof Repair", stage: .newLead, value: 0, deposit: 0, depositPaid: false, balance: 0, source: "Referral", assignedTo: worker.name, surveyDate: today, surveyTime: "10:30", startDate: nil, endDate: nil, completedDate: nil, paidDate: nil, progress: 0, tasks: [CRMTask(id: "preview-task-4", title: "Call customer to discuss requirements", completed: false, completedDate: nil, dueDate: yesterday, isTemplate: true)], photos: [], notes: [], files: [], materials: [], wonDate: nil, myBuilderURL: nil, reviewRequestSent: nil, lat: nil, lng: nil, createdAt: yesterday, updatedAt: yesterday),
                    Lead(id: "preview-lead-3", jobRef: "JOB-203", name: "Mr Okafor", phone: "", email: "", address: "2 Station Road, Bristol", jobType: "Flat Roof", stage: .completed, value: 3200, deposit: 960, depositPaid: true, balance: 2240, source: "Google", assignedTo: worker.name, surveyDate: nil, surveyTime: nil, startDate: lastWeek, endDate: yesterday, completedDate: yesterday, paidDate: nil, progress: 100, tasks: [], photos: [], notes: [], files: [], materials: [], wonDate: lastWeek, myBuilderURL: nil, reviewRequestSent: nil, lat: nil, lng: nil, createdAt: lastWeek, updatedAt: yesterday),
                ]
            }
            timesheets = []
            if ProcessInfo.processInfo.arguments.contains("--worker-preview-tools") {
                selectedSection = .tools
            } else if ProcessInfo.processInfo.arguments.contains("--worker-preview-calendar") {
                selectedSection = .calendar
            } else {
                selectedSection = .dashboard
            }
            syncIssues = []
            Task { await refreshWeather() }
        }
    #endif

    func signIn(username: String, password: String) async -> Bool {
        isLoading = true; defer { isLoading = false }
        if let secureEmail = AuthenticationPolicy.secureEmail(for: username) {
            do {
                // All sign-in goes through Supabase Auth. The old client-side password
                // hash comparison against `app_users` is gone: it required the anonymous
                // client to download every account's password hash.
                let user = try await SupabaseService.shared.signInWithPassword(email: secureEmail, password: password)
                errorMessage = nil
                currentUser = user
                users = [user]
                cacheSignedInUser(user)
                KeychainStore.remove("userID")
                await refresh(showErrors: false)
                return true
            } catch {
                await SupabaseService.shared.signOutAuthenticatedSession()
                errorMessage = "That email or password was not accepted."
                return false
            }
        }
        errorMessage = "Sign in with your email address. Usernames are no longer accepted."
        return false
    }

    func signOut() {
        let deviceToken = UserDefaults.standard.string(forKey: "nativePushDeviceToken")
        Task {
            if let deviceToken { try? await SupabaseService.shared.unregisterNativePushDevice(token: deviceToken) }
            await SupabaseService.shared.signOutAuthenticatedSession()
        }
        KeychainStore.remove("userID")
        clearLocalSession()
    }

    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "prolinecrm", url.host?.lowercased() == "join",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty
        else { return }
        pendingWorkerInviteToken = token
        if isAuthenticated { signOut() }
    }

    func createWorkerInvitation(email: String, role: String) async -> WorkerInvitation? {
        isLoading = true; defer { isLoading = false }
        do { return try await SupabaseService.shared.createWorkerInvitation(email: email, role: role) } catch {
            errorMessage = error.localizedDescription; return nil
        }
    }

    func createSecureUser(name: String, email: String, password: String, role: String, dayRate: Double?, cisRate: Int) async -> Bool {
        guard isAdmin else { errorMessage = "Only administrators can add users."; return false }
        do {
            try await SupabaseService.shared.createSecureUser(
                name: name, email: email, password: password, role: role, dayRate: dayRate, cisRate: cisRate);
            users = try await SupabaseService.shared.fetchUsers(); return true
        } catch { errorMessage = "The user could not be added: \(error.localizedDescription)"; return false }
    }

    func acceptWorkerInvitation(token: String, details: WorkerSignupDetails) async -> Bool {
        isLoading = true; defer { isLoading = false }
        do {
            let email = try await SupabaseService.shared.acceptWorkerInvitation(token: token, details: details)
            let user = try await SupabaseService.shared.signInWithPassword(email: email, password: details.password)
            currentUser = user; users = [user]; cacheSignedInUser(user); pendingWorkerInviteToken = nil
            await refresh(showErrors: false)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func clearLocalSession() {
        UserDefaults.standard.removeObject(forKey: "cachedSignedInUser")
        currentUser = nil
        leads = []
        users = []
        contacts = []
        generalTasks = []
        timesheets = []
        adminTimesheetChecks = []
        paymentRuns = []
        workerPayments = []
        surveys = []
        quotes = []
        teamMessages = []
        teamDayPlans = []
        syncIssues = []
        lastRefreshAt = nil
        WidgetSnapshot.empty.save()
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    private func expireSecureSession() async {
        await SupabaseService.shared.signOutAuthenticatedSession()
        KeychainStore.remove("userID")
        clearLocalSession()
        errorMessage = "Your secure session has expired or this account has been disabled. Sign in again to continue."
    }

    func refresh(showErrors: Bool = true) async {
        guard SyncPolicy.shouldStart(isAuthenticated: isAuthenticated, isRefreshing: isRefreshing) else { return }
        isRefreshing = true
        // Only the very first load blocks the UI. Background refreshes must not grey
        // out buttons across the app every minute.
        let ownsLoadingState = !isLoading && leads.isEmpty
        if ownsLoadingState { isLoading = true }
        defer {
            isRefreshing = false
            if ownsLoadingState { isLoading = false }
        }
        if KeychainStore.get("supabaseAccessToken") != nil {
            do {
                if let profile = try await SupabaseService.shared.validateAuthenticatedProfile() {
                    currentUser = profile; cacheSignedInUser(profile)
                }
            } catch is SupabaseSessionExpired {
                await expireSecureSession()
                return
            } catch {
                // A temporary connectivity failure is handled by the individual
                // dataset refreshes below; cached data and the session are retained.
            }
        }
        // Every dataset is fetched at once; each one fails independently so an
        // optional module can never blank the pipeline.
        let service = SupabaseService.shared
        let admin = isAdmin
        func attempt<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
            do { return .success(try await work()) } catch { return .failure(error) }
        }
        async let fetchedLeads = attempt { try await service.fetchLeads() }
        async let fetchedSurveys = attempt { try await service.fetchSurveys() }
        async let fetchedUsers = attempt { try await service.fetchUsers() }
        async let fetchedContacts = attempt { try await service.fetchContacts() }
        async let fetchedTasks = attempt { try await service.fetchTasks() }
        async let fetchedTimesheets = attempt { try await service.fetchTimesheets() }
        async let fetchedAdminChecks = attempt { admin ? try await service.fetchAdminTimesheetChecks() : [] }
        async let fetchedRuns = attempt { try await service.fetchPaymentRuns() }
        async let fetchedPayments = attempt { try await service.fetchWorkerPayments() }
        async let fetchedQuotes = attempt { try await service.fetchQuotes() }
        async let fetchedMessages = attempt { try await service.fetchTeamMessages() }
        async let fetchedPlans = attempt { try await service.fetchTeamDayPlans() }

        var failures: [String] = []
        func adopt<T>(_ result: Result<T, Error>, _ label: String, _ apply: (T) -> Void) {
            switch result {
            case .success(let value): apply(value);
            case .failure: failures.append(label)
            }
        }
        adopt(await fetchedLeads, "Leads and jobs") { leads = LeadAccessScope.visible($0, for: currentUser) }
        adopt(await fetchedSurveys, "Surveys") { surveys = WorkflowAccessScope.visible($0, leads: leads) }
        adopt(await fetchedUsers, "Team") { users = UserAccessScope.visible($0, for: currentUser) }
        adopt(await fetchedContacts, "Contacts") { contacts = ContactAccessScope.visible($0, leads: leads, for: currentUser) }
        adopt(await fetchedTasks, "Tasks and fleet") { generalTasks = TaskAccessScope.visible($0, for: currentUser) }
        adopt(await fetchedTimesheets, "Timesheets") { timesheets = TimesheetAccessScope.visible($0, for: currentUser) }
        if admin { adopt(await fetchedAdminChecks, "Admin timesheet copy") { adminTimesheetChecks = $0 } }
        adopt(await fetchedRuns, "Pay runs") { paymentRuns = PaymentAccessScope.visible($0, for: currentUser) }
        adopt(await fetchedPayments, "Payments") { workerPayments = PaymentAccessScope.visible($0, for: currentUser) }
        adopt(await fetchedQuotes, "Quotes") { quotes = WorkflowAccessScope.visible($0, leads: leads) }
        switch (await fetchedMessages, await fetchedPlans) {
        case (.success(let messages), .success(let plans)): adoptTeam(messages: messages, plans: plans)
        default: failures.append("Team Hub")
        }
        syncIssues = failures
        lastRefreshAt = .now
        if showErrors && !failures.isEmpty {
            errorMessage =
                "Some CRM data could not be refreshed: \(failures.joined(separator: ", ")). Existing data has been kept. Check your connection or Supabase setup, then try Refresh again."
        }
        updateWidget()
        await scheduleNotifications()
        Task { await refreshWeather() }
    }

    /// Forecast for wherever today's first booked job is (or the business address).
    func refreshWeather() async {
        let today = SupabaseService.today
        let booked = leads.first { ($0.surveyDate == today || $0.startDate == today || $0.stage == .inProgress) && $0.lat != nil && $0.lng != nil }
        let coordinate = booked.flatMap { lead in lead.lat.flatMap { lat in lead.lng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } }
        await weather.refresh(near: coordinate, fallbackAddress: UserDefaults.standard.string(forKey: "businessAddress") ?? "")
    }

    private func cacheSignedInUser(_ user: CRMUser) {
        if let data = try? JSONEncoder().encode(user) { UserDefaults.standard.set(data, forKey: "cachedSignedInUser") }
    }

    private func cachedSignedInUser() -> CRMUser? {
        guard let data = UserDefaults.standard.data(forKey: "cachedSignedInUser") else { return nil }
        return try? JSONDecoder().decode(CRMUser.self, from: data)
    }

    @discardableResult
    func move(_ lead: Lead, to stage: LeadStage) async -> Bool {
        guard lead.stage != stage else { return true }
        return await commitLead(lead.id, base: lead.updatedAt, fallback: "The stage change could not be saved.") { changed in
            changed = lead
            Self.apply(stage: stage, to: &changed)
        }
    }

    /// The next thing to do for a lead in its current stage, as one primary action.
    nonisolated static func nextStep(for lead: Lead) -> LeadStep? {
        switch lead.stage {
        case .newLead: return lead.surveyDate == nil ? .bookSurvey : .move(.surveyBooked)
        case .surveyBooked: return .move(.quotePreparing)
        case .quotePreparing: return .move(.quoteSent)
        case .quoteSent: return .move(.won)
        case .won: return lead.startDate == nil ? .scheduleJob : .move(.scheduled)
        case .scheduled: return .move(.inProgress)
        case .inProgress: return .move(.completed)
        case .completed: return lead.balance > 0 ? .move(.waitingForPayment) : .move(.paid)
        case .waitingForPayment: return .recordPayment
        case .paid, .lost: return nil
        }
    }

    private static func apply(stage: LeadStage, to lead: inout Lead) {
        let today = SupabaseService.today
        lead.stage = stage
        if stage == .won { lead.wonDate = lead.wonDate ?? today }
        if stage == .inProgress && lead.startDate == nil { lead.startDate = today }
        if [.completed, .waitingForPayment].contains(stage) { lead.completedDate = lead.completedDate ?? today }
        if stage == .paid { lead.paidDate = today; lead.balance = 0; if lead.deposit > 0 { lead.depositPaid = true } }
        // Keep everything already done and everything added by hand; drop only the
        // previous stage's untouched checklist, then add this stage's items.
        let kept = lead.tasks.filter { $0.completed || $0.isTemplate != true }
        let existing = Set(kept.map { $0.title.lowercased() })
        let fresh = (stageTasks[stage] ?? [])
            .filter { !existing.contains($0.lowercased()) }
            .map { CRMTask(id: UUID().uuidString, title: $0, completed: false, completedDate: nil, dueDate: nil, isTemplate: true) }
        lead.tasks = kept + fresh
    }

    @discardableResult
    func addLead(
        name: String, phone: String, email: String, address: String, jobType: String, stage: LeadStage, value: Double, deposit: Double,
        source: String, notes: String = "", createFollowUp: Bool = false
    ) async -> Bool {
        let today = SupabaseService.today
        var tasks = (Self.stageTasks[stage] ?? []).map {
            CRMTask(id: UUID().uuidString, title: $0, completed: false, completedDate: nil, dueDate: nil, isTemplate: true)
        }
        if createFollowUp {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            tasks.append(
                CRMTask(
                    id: UUID().uuidString, title: "Follow up with \(name)", completed: false, completedDate: nil,
                    dueDate: SupabaseService.localDay(for: tomorrow), isTemplate: false))
        }
        var leadNotes: [CRMNote] = []
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            leadNotes.append(
                CRMNote(
                    id: UUID().uuidString, content: notes.trimmingCharacters(in: .whitespacesAndNewlines), date: today,
                    author: currentUser?.name ?? ""))
        }
        let leadID = UUID().uuidString
        let lead = Lead(
            id: leadID, jobRef: JobReference.make(date: .now, nonce: leadID), name: name, phone: phone, email: email, address: address,
            jobType: jobType, stage: stage, value: value, deposit: min(max(0, deposit), value), depositPaid: false, balance: value,
            source: source, assignedTo: currentUser?.name ?? "", surveyDate: nil, surveyTime: nil,
            startDate: stage == .inProgress ? today : nil, endDate: nil,
            completedDate: [.completed, .waitingForPayment].contains(stage) ? today : nil, paidDate: stage == .paid ? today : nil,
            progress: 0, tasks: tasks, photos: [], notes: leadNotes, files: [], materials: [],
            wonDate: [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains(stage) ? today : nil,
            myBuilderURL: nil, reviewRequestSent: nil, lat: nil, lng: nil, createdAt: today, updatedAt: today)
        do {
            try await SupabaseService.shared.insertLead(lead)
            leads.insert(lead, at: 0)
            updateWidget()
            await scheduleNotifications()
            let recipients = users.filter { $0.id != currentUser?.id }.map(\.id)
            if !recipients.isEmpty {
                _ = try? await SupabaseService.shared.sendPushEvent(
                    "new_lead", name: lead.name, detail: lead.jobType, recordID: lead.id, userIDs: recipients)
            }
        } catch {
            errorMessage = "The new lead could not be saved: \(error.localizedDescription)"
            return false
        }

        // The customer/job is the primary record. Contact mirroring is a separate
        // convenience write and must never make a successfully created lead look
        // like it failed (which can cause a duplicate when the user retries).
        if !phone.isEmpty || !email.isEmpty {
            let contact = CRMContact(id: UUID().uuidString, name: name, phone: phone, email: email, address: address, createdAt: today)
            let duplicate = contacts.contains {
                (!phone.isEmpty && $0.phone == phone) || (!email.isEmpty && $0.email.caseInsensitiveCompare(email) == .orderedSame)
            }
            if !duplicate {
                do {
                    try await SupabaseService.shared.insert(contact, into: "contacts")
                    contacts.insert(contact, at: 0)
                } catch {
                    if !syncIssues.contains("Contacts") { syncIssues.append("Contacts") }
                    errorMessage =
                        "The lead was saved, but its contact-directory copy could not be created. You do not need to add the lead again."
                }
            }
        }
        return true
    }

    @discardableResult
    func saveLead(_ lead: Lead) async -> Bool {
        guard let old = leads.first(where: { $0.id == lead.id }) else {
            errorMessage = "This lead could not be found. Refresh and try again."; return false
        }
        guard isAdmin || old.assignedTo.caseInsensitiveCompare(lead.assignedTo) == .orderedSame else {
            errorMessage = "Only an administrator can reassign customer work."
            return false
        }
        var changed = lead
        // Money only moves when the figures that drive it move. Fixing a typo in an
        // address must never reset a balance that has been adjusted by hand.
        if changed.value != old.value || changed.deposit != old.deposit || changed.depositPaid != old.depositPaid {
            changed.balance = max(0, changed.value - (changed.depositPaid ? changed.deposit : 0))
        }
        if old.stage != changed.stage {
            var unchangedStage = changed; unchangedStage.stage = old.stage
            return await move(unchangedStage, to: changed.stage)
        }
        let saved = await commitLead(lead.id, base: lead.updatedAt, fallback: "Changes could not be saved.") { $0 = changed }
        // Contact mirroring is helpful, but it is not part of the lead write.
        // A missing/locked contacts table must never roll back a saved lead.
        if saved { try? await syncContact(from: changed) }
        return saved
    }

    // MARK: Lead write path
    //
    // Every change to a lead goes through `commitLead`. Two rules keep multi-device
    // editing safe:
    //  1. The conflict check uses the version the edit was *based on* — a sheet's copy,
    //     or the row as it stood when the user tapped — never whatever the last background
    //     refresh happened to load. An edit started before a refresh cannot silently
    //     overwrite a colleague's change.
    //  2. Writes to the same lead run one at a time, so two quick checklist taps never
    //     race each other into a false "someone else changed this" conflict.
    private var leadWriteQueues: [String: Task<Bool, Never>] = [:]

    /// Applies `mutate` to the in-memory row straight away (optimistic UI), then writes it.
    /// - Parameter base: the `updatedAt` the edit was based on. Pass it when saving a copy
    ///   that was taken earlier (a sheet). Leave nil for in-place taps, which are based on
    ///   whatever the row holds when the write actually runs.
    @discardableResult
    private func commitLead(_ leadID: String, base: String? = nil, fallback: String, mutate: @escaping @MainActor (inout Lead) -> Void)
        async -> Bool
    {
        guard let index = leads.firstIndex(where: { $0.id == leadID }) else {
            errorMessage = "This job could not be found. Refresh and try again."; return false
        }
        let snapshot = leads[index]
        var changed = snapshot
        mutate(&changed)
        changed.progress = Self.progress(of: changed.tasks)
        leads[index] = changed
        // Preview data has no server: keep the change locally so the UI can be exercised.
        if isWorkerPreview { return true }

        let previous = leadWriteQueues[leadID]
        let write = Task<Bool, Never> { @MainActor [self] in
            _ = await previous?.value
            guard let current = leads.firstIndex(where: { $0.id == leadID }) else { return false }
            var body: Lead
            let expected: String
            if let base { body = changed; expected = base } else { body = leads[current]; expected = leads[current].updatedAt }
            body.updatedAt = SupabaseService.now
            do {
                let saved = try await SupabaseService.shared.updateLead(body, expectedUpdatedAt: expected)
                if let now = leads.firstIndex(where: { $0.id == leadID }) { leads[now].updatedAt = saved?.updatedAt ?? body.updatedAt }
                updateWidget()
                await scheduleNotifications()
                return true
            } catch {
                if let now = leads.firstIndex(where: { $0.id == leadID }) { leads[now] = snapshot }
                reportLeadWrite(error, fallback: fallback)
                return false
            }
        }
        leadWriteQueues[leadID] = write
        let result = await write.value
        if leadWriteQueues[leadID] == write { leadWriteQueues[leadID] = nil }
        return result
    }

    @discardableResult
    func addJobNote(leadID: String, content: String) async -> Bool {
        let noteContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noteContent.isEmpty else {
            errorMessage = "Enter a note before saving."
            return false
        }
        guard var lead = leads.first(where: { $0.id == leadID }) else {
            errorMessage = "This job could not be found. Refresh and try again."
            return false
        }
        lead.notes.insert(
            CRMNote(
                id: UUID().uuidString,
                content: noteContent,
                date: SupabaseService.today,
                author: currentUser?.name ?? "Team member"
            ),
            at: 0
        )
        return await saveLead(lead)
    }

    func analyseJobNote(leadID: String, note: String) async -> JobNoteAnalysis? {
        guard let lead = leads.first(where: { $0.id == leadID }) else { return nil }
        guard KeychainStore.get("supabaseAccessToken") != nil else {
            errorMessage = "Sign out, then sign in with your secure email account to use voice job updates. No changes were saved."
            return nil
        }
        do { return try await SupabaseService.shared.analyseJobNote(lead: lead, note: note) } catch {
            if !syncIssues.contains("Roofing assistant") { syncIssues.append("Roofing assistant") }
            errorMessage = "ProLine CRM could not prepare the job update: \(error.localizedDescription). No changes were saved."
            return nil
        }
    }

    func applyJobTaskSuggestions(leadID: String, suggestions: [JobTaskSuggestion]) async -> Bool {
        await applyJobUpdate(leadID: leadID, progressNote: nil, suggestions: suggestions, materials: [])
    }

    func applyJobUpdate(leadID: String, progressNote: String?, suggestions: [JobTaskSuggestion], materials: [JobMaterialSuggestion] = [])
        async -> Bool
    {
        guard var lead = leads.first(where: { $0.id == leadID }) else { return false }
        if let progressNote {
            let cleanNote = progressNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanNote.isEmpty {
                lead.notes.insert(
                    CRMNote(id: UUID().uuidString, content: cleanNote, date: SupabaseService.today, author: currentUser?.name ?? ""), at: 0)
            }
        }
        func normalised(_ title: String) -> String {
            title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        func tokens(_ title: String) -> Set<String> {
            let ignored: Set<String> = ["a", "an", "and", "for", "of", "the", "to"]
            return Set(
                normalised(title).split(separator: " ").map(String.init).filter { !ignored.contains($0) }.map {
                    $0.count > 4 && $0.hasSuffix("s") ? String($0.dropLast()) : $0
                })
        }
        func isDuplicate(_ title: String) -> Bool {
            let proposed = tokens(title)
            return lead.tasks.contains { task in
                guard !task.completed else { return false }
                if normalised(task.title) == normalised(title) { return true }
                let current = tokens(task.title)
                guard !proposed.isEmpty, !current.isEmpty else { return false }
                return Double(proposed.intersection(current).count) / Double(min(proposed.count, current.count)) >= 0.8
            }
        }
        for suggestion in suggestions {
            switch suggestion.action {
            case .complete:
                guard let taskID = suggestion.taskID, let index = lead.tasks.firstIndex(where: { $0.id == taskID }),
                    !lead.tasks[index].completed
                else { continue }
                lead.tasks[index].completed = true; lead.tasks[index].completedDate = SupabaseService.today
            case .add:
                let cleanTitle = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanTitle.isEmpty && !isDuplicate(cleanTitle) {
                    lead.tasks.append(
                        CRMTask(
                            id: UUID().uuidString, title: cleanTitle, completed: false, completedDate: nil, dueDate: suggestion.dueDate,
                            isTemplate: false, priority: "medium", notes: suggestion.reason))
                }
            }
        }
        for material in materials where material.quantity.isFinite && material.quantity > 0 {
            let name = material.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = material.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !unit.isEmpty else { continue }
            if let index = lead.materials.firstIndex(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.unit.caseInsensitiveCompare(unit) == .orderedSame
            }) {
                lead.materials[index].quantity += material.quantity
            } else {
                lead.materials.append(
                    CRMMaterial(
                        id: UUID().uuidString, name: name, quantity: material.quantity, unit: unit, cost: nil, supplier: nil,
                        ordered: false, delivered: false))
            }
        }
        let completed = lead.tasks.filter(\.completed).count
        lead.progress = lead.tasks.isEmpty ? 0 : Int((Double(completed) / Double(lead.tasks.count) * 100).rounded())
        return await saveLead(lead)
    }

    func askAssistant(_ prompt: String, history: [AssistantConversationTurn] = [], attachment: AssistantAttachment? = nil) async
        -> CRMAssistantResponse?
    {
        guard let user = currentUser else { return nil }
        assistantErrorMessage = nil
        guard KeychainStore.get("supabaseAccessToken") != nil else {
            assistantErrorMessage = "Sign out, then sign in again as willconway9 to activate the secure Gemini connection."
            return nil
        }
        do {
            return try await SupabaseService.shared.askOperationsAssistant(
                prompt: prompt, history: history, attachment: attachment, leads: LeadAccessScope.visible(leads, for: user),
                tasks: TaskAccessScope.visible(visibleGeneralTasks, for: user), actions: companyActions, user: user)
        } catch { assistantErrorMessage = error.localizedDescription; return nil }
    }

    func executeAssistantAction(_ action: CRMAssistantAction) async -> Bool {
        errorMessage = nil
        guard action.requiresApproval, let user = currentUser else { return false }
        if let leadID = action.leadID, let lead = leads.first(where: { $0.id == leadID }), !isAdmin,
            lead.assignedTo.caseInsensitiveCompare(user.name) != .orderedSame
        {
            errorMessage = "You can only change jobs assigned to you."
            return false
        }
        let succeeded: Bool
        switch action.kind {
        case .addJobTask:
            guard let leadID = action.leadID, var lead = leads.first(where: { $0.id == leadID }), let title = action.value, !title.isEmpty
            else { return false }
            if !lead.tasks.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                lead.tasks.append(
                    CRMTask(
                        id: UUID().uuidString, title: title, completed: false, completedDate: nil, dueDate: action.secondaryValue,
                        isTemplate: false))
            }
            succeeded = await saveLead(lead)
        case .completeJobTask:
            guard let leadID = action.leadID, let taskID = action.taskID, let lead = leads.first(where: { $0.id == leadID }),
                let task = lead.tasks.first(where: { $0.id == taskID }), !task.completed
            else { return false }
            await toggleLeadTask(leadID: leadID, taskID: taskID)
            succeeded = leads.first(where: { $0.id == leadID })?.tasks.first(where: { $0.id == taskID })?.completed == true
        case .createGeneralTask:
            succeeded = await addGeneralTask(
                title: action.value ?? action.title, dueDate: action.secondaryValue, priority: "medium", category: "AI suggested")
        case .moveJobStage:
            guard let leadID = action.leadID, let lead = leads.first(where: { $0.id == leadID }), let raw = action.value,
                let stage = LeadStage(rawValue: raw)
            else { return false }
            succeeded = await move(lead, to: stage)
        case .scheduleSurvey:
            guard let leadID = action.leadID, var lead = leads.first(where: { $0.id == leadID }), let day = action.value else {
                return false
            }
            lead.surveyDate = day; lead.surveyTime = action.secondaryValue; succeeded = await saveLead(lead)
        case .scheduleJob:
            guard let leadID = action.leadID, var lead = leads.first(where: { $0.id == leadID }), let start = action.value else {
                return false
            }
            lead.startDate = start; lead.endDate = action.secondaryValue; succeeded = await saveLead(lead)
        case .draftEmail:
            succeeded = true
        case .recordDeposit:
            guard isAdmin, let leadID = action.leadID, let lead = leads.first(where: { $0.id == leadID }), lead.deposit > 0,
                !lead.depositPaid
            else { errorMessage = "Only an administrator can record an existing unpaid deposit."; return false }
            succeeded = await recordDeposit(for: lead)
        case .recordFinalPayment:
            guard isAdmin, let leadID = action.leadID, let lead = leads.first(where: { $0.id == leadID }), lead.balance > 0 else {
                errorMessage = "Only an administrator can record an outstanding final payment."; return false
            }
            succeeded = await recordFinalPayment(for: lead)
        case .setJobValue, .setDepositAmount, .setBalance:
            guard isAdmin, let leadID = action.leadID, var lead = leads.first(where: { $0.id == leadID }),
                let raw = action.value, let amount = Double(raw), amount >= 0
            else {
                errorMessage = "The proposed financial amount is invalid."
                return false
            }
            switch action.kind {
            case .setJobValue:
                guard amount >= lead.deposit else { errorMessage = "The job value cannot be lower than its deposit."; return false }
                lead.value = amount
                if lead.depositPaid { lead.balance = max(0, amount - lead.deposit) }
            case .setDepositAmount:
                guard amount <= lead.value else { errorMessage = "The deposit cannot exceed the job value."; return false }
                lead.deposit = amount
                if lead.depositPaid { lead.balance = max(0, lead.value - amount) }
            case .setBalance:
                guard amount <= lead.value else { errorMessage = "The balance cannot exceed the job value."; return false }
                lead.balance = amount
            default: break
            }
            succeeded = await saveLead(lead)
        case .addJobNote:
            guard let leadID = action.leadID, var lead = leads.first(where: { $0.id == leadID }),
                let content = action.value?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty
            else { return false }
            lead.notes.append(CRMNote(id: UUID().uuidString, content: content, date: SupabaseService.today, author: user.name))
            succeeded = await saveLead(lead)
        case .addMaterial:
            guard let leadID = action.leadID, var lead = leads.first(where: { $0.id == leadID }),
                let name = action.value?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                let quantity = action.quantity, quantity > 0,
                let unit = action.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty
            else { return false }
            if let index = lead.materials.firstIndex(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.unit.caseInsensitiveCompare(unit) == .orderedSame
            }) {
                lead.materials[index].quantity += quantity
            } else {
                lead.materials.append(
                    CRMMaterial(
                        id: UUID().uuidString, name: name, quantity: quantity, unit: unit, cost: nil, supplier: nil, ordered: false,
                        delivered: false))
            }
            succeeded = await saveLead(lead)
        }
        if succeeded {
            let entry = AIAuditEntry(
                id: UUID().uuidString, userID: user.id, userName: user.name, actionKind: action.kind.rawValue, actionTitle: action.title,
                leadID: action.leadID, outcome: action.kind == .draftEmail ? "drafted" : "approved", createdAt: SupabaseService.now)
            aiAuditEntries.insert(entry, at: 0)
            if let data = try? JSONEncoder().encode(Array(aiAuditEntries.prefix(250))) {
                UserDefaults.standard.set(data, forKey: "aiActionAudit")
            }
        }
        return succeeded
    }

    @discardableResult func recordDeposit(for lead: Lead) async -> Bool {
        guard lead.deposit > 0 else { errorMessage = "Add a deposit amount before recording payment."; return false }
        var changed = lead
        changed.depositPaid = true
        changed.balance = max(0, changed.value - changed.deposit)
        return await saveLead(changed)
    }

    @discardableResult func recordFinalPayment(for lead: Lead) async -> Bool {
        var changed = lead
        changed.depositPaid = changed.depositPaid || changed.deposit > 0
        changed.balance = 0
        changed.paidDate = SupabaseService.today
        changed.stage = .paid
        return await saveLead(changed)
    }

    @discardableResult
    func deleteLead(_ lead: Lead) async -> Bool {
        guard isAdmin else { errorMessage = "Only an administrator can permanently delete a customer or job."; return false }
        do {
            try await SupabaseService.shared.delete(from: "leads", id: lead.id); leads.removeAll { $0.id == lead.id }; updateWidget();
            await scheduleNotifications(); return true
        } catch { errorMessage = "The lead could not be deleted: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func addGeneralTask(
        title: String, dueDate: String?, priority: String, category: String, assignedTo: [String]? = nil, notes: String? = nil
    ) async -> Bool {
        let owners = assignedTo ?? currentUser.map { [$0.id] } ?? []
        guard isAdmin || owners == (currentUser.map { [$0.id] } ?? []) else {
            errorMessage = "Team members can only create tasks for themselves."; return false
        }
        let task = GeneralTask(
            id: UUID().uuidString, title: title, completed: false, completedDate: nil, dueDate: dueDate, priority: priority,
            category: category, notes: notes, createdAt: SupabaseService.today, assignedTo: owners)
        do {
            try await SupabaseService.shared.insert(task, into: "general_tasks"); generalTasks.insert(task, at: 0);
            await scheduleNotifications(); return true
        } catch { errorMessage = "Task could not be saved: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func addFleetVehicle(registration: String, detailsJSON: String) async -> Bool {
        let record = GeneralTask(
            id: UUID().uuidString, title: registration, completed: true, completedDate: SupabaseService.today, dueDate: nil,
            priority: "low", category: "Fleet Vehicle", notes: detailsJSON, createdAt: SupabaseService.today, assignedTo: [])
        do { try await SupabaseService.shared.insert(record, into: "general_tasks"); generalTasks.insert(record, at: 0); return true } catch
        { errorMessage = "The vehicle could not be saved: \(error.localizedDescription)"; return false }
    }

    func toggleGeneralTask(_ task: GeneralTask) async {
        var changed = task; changed.completed.toggle(); changed.completedDate = changed.completed ? SupabaseService.today : nil
        guard let index = generalTasks.firstIndex(where: { $0.id == task.id }) else { return }
        generalTasks[index] = changed
        if isWorkerPreview { return }
        do { try await SupabaseService.shared.update(changed, in: "general_tasks", id: task.id); await scheduleNotifications() } catch {
            generalTasks[index] = task; errorMessage = "Task could not be updated."
        }
    }

    @discardableResult
    func saveGeneralTask(_ task: GeneralTask) async -> Bool {
        guard let index = generalTasks.firstIndex(where: { $0.id == task.id }) else {
            errorMessage = "Task could not be found. Refresh and try again."; return false
        }
        let old = generalTasks[index]
        guard isAdmin || (old.assignedTo == (currentUser.map { [$0.id] } ?? []) && task.assignedTo == old.assignedTo) else {
            errorMessage = "Team members can only edit their own tasks."; return false
        }
        generalTasks[index] = task
        do {
            try await SupabaseService.shared.update(task, in: "general_tasks", id: task.id); await scheduleNotifications(); return true
        } catch { generalTasks[index] = old; errorMessage = "Task changes could not be saved: \(error.localizedDescription)"; return false }
    }

    func deleteGeneralTask(_ task: GeneralTask) async {
        guard isAdmin || task.assignedTo == (currentUser.map { [$0.id] } ?? []) else {
            errorMessage = "Team members can only delete their own tasks."; return
        }
        guard let index = generalTasks.firstIndex(where: { $0.id == task.id }) else { return }
        generalTasks.remove(at: index)
        do { try await SupabaseService.shared.delete(from: "general_tasks", id: task.id); await scheduleNotifications() } catch {
            generalTasks.insert(task, at: index); errorMessage = "Task could not be deleted."
        }
    }

    func toggleLeadTask(leadID: String, taskID: String) async {
        guard let lead = leads.first(where: { $0.id == leadID }), lead.tasks.contains(where: { $0.id == taskID }) else { return }
        await commitLead(leadID, fallback: "The task could not be updated.") { lead in
            guard let index = lead.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            lead.tasks[index].completed.toggle()
            lead.tasks[index].completedDate = lead.tasks[index].completed ? SupabaseService.today : nil
        }
    }

    @discardableResult
    func addLeadTask(leadID: String, title: String, dueDate: String?, priority: String = "medium", notes: String? = nil) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let task = CRMTask(
            id: UUID().uuidString, title: cleanTitle, completed: false, completedDate: nil, dueDate: dueDate, isTemplate: false,
            priority: priority, notes: notes)
        return await commitLead(leadID, fallback: "The task could not be added.") { $0.tasks.append(task) }
    }

    @discardableResult
    func updateLeadTask(
        leadID: String, taskID: String, title: String, dueDate: String?, priority: String, notes: String?, subtasks: [CRMSubtask]
    ) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtasks: [CRMSubtask] = subtasks.compactMap { subtask in
            let clean = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : CRMSubtask(id: subtask.id, title: clean, completed: subtask.completed)
        }
        return await commitLead(leadID, fallback: "The task changes could not be saved.") { lead in
            guard let index = lead.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            lead.tasks[index].title = cleanTitle
            lead.tasks[index].dueDate = dueDate
            lead.tasks[index].priority = ["low", "medium", "high"].contains(priority) ? priority : "medium"
            lead.tasks[index].notes = cleanNotes?.isEmpty == true ? nil : cleanNotes
            lead.tasks[index].subtasks = cleanSubtasks
        }
    }

    func toggleLeadSubtask(leadID: String, taskID: String, subtaskID: String) async {
        await commitLead(leadID, fallback: "The subtask could not be updated.") { lead in
            guard let taskIndex = lead.tasks.firstIndex(where: { $0.id == taskID }),
                let subtaskIndex = lead.tasks[taskIndex].subtasks?.firstIndex(where: { $0.id == subtaskID })
            else { return }
            lead.tasks[taskIndex].subtasks?[subtaskIndex].completed.toggle()
        }
    }

    func completeNextLeadTask(leadID: String, fallbackTitle: String) async {
        guard let lead = leads.first(where: { $0.id == leadID }) else { return }
        if let task = lead.tasks.first(where: { !$0.completed }) {
            await toggleLeadTask(leadID: leadID, taskID: task.id)
            return
        }
        let done = CRMTask(
            id: UUID().uuidString, title: fallbackTitle, completed: true, completedDate: SupabaseService.today, dueDate: nil,
            isTemplate: false)
        await commitLead(leadID, fallback: "The action could not be completed.") { $0.tasks.append(done) }
    }

    func deleteLeadTask(leadID: String, taskID: String) async {
        await commitLead(leadID, fallback: "The task could not be deleted.") { $0.tasks.removeAll { $0.id == taskID } }
    }

    @discardableResult
    func addMaterial(leadID: String, name: String, quantity: Double, unit: String, cost: Double?, supplier: String?) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, quantity > 0 else { return false }
        let material = CRMMaterial(
            id: UUID().uuidString, name: cleanName, quantity: quantity, unit: unit.isEmpty ? "item" : unit, cost: cost,
            supplier: supplier?.isEmpty == true ? nil : supplier, ordered: false, delivered: false)
        return await commitLead(leadID, fallback: "The material could not be added.") { $0.materials.append(material) }
    }

    func setMaterialStatus(leadID: String, materialID: String, ordered: Bool, delivered: Bool) async {
        await commitLead(leadID, fallback: "The material could not be updated.") { lead in
            guard let index = lead.materials.firstIndex(where: { $0.id == materialID }) else { return }
            lead.materials[index].ordered = ordered || delivered
            lead.materials[index].delivered = delivered
        }
    }

    func saveSurvey(_ survey: RoofSurvey) async -> Bool {
        var changed = survey; changed.updatedAt = SupabaseService.now
        do {
            if let index = surveys.firstIndex(where: { $0.id == changed.id }) {
                try await SupabaseService.shared.update(changed, in: "roof_surveys", id: changed.id)
                surveys[index] = changed
            } else {
                try await SupabaseService.shared.insert(changed, into: "roof_surveys")
                surveys.insert(changed, at: 0)
            }
            if changed.status == .completed, let lead = leads.first(where: { $0.id == changed.leadID }), lead.stage == .surveyBooked {
                await move(lead, to: .quotePreparing)
            }
            return true
        } catch { errorMessage = "Survey could not be saved. Check that the roofing workflow migration has been applied."; return false }
    }

    func deleteSurvey(_ survey: RoofSurvey) async {
        do { try await SupabaseService.shared.delete(from: "roof_surveys", id: survey.id); surveys.removeAll { $0.id == survey.id } } catch
        { errorMessage = "Survey could not be deleted." }
    }

    func saveQuote(_ quote: CRMQuote) async -> Bool {
        var changed = quote; changed.updatedAt = SupabaseService.now
        if changed.status == .sent && changed.sentAt == nil { changed.sentAt = SupabaseService.now }
        if changed.status == .accepted && changed.acceptedAt == nil { changed.acceptedAt = SupabaseService.now }
        do {
            if let index = quotes.firstIndex(where: { $0.id == changed.id }) {
                try await SupabaseService.shared.update(changed, in: "quotes", id: changed.id)
                quotes[index] = changed
            } else {
                try await SupabaseService.shared.insert(changed, into: "quotes")
                quotes.insert(changed, at: 0)
            }
            // A draft is just a draft. The job's value follows a quote only once the
            // customer has actually been sent it (or accepted it).
            if [.sent, .accepted].contains(changed.status), var lead = leads.first(where: { $0.id == changed.leadID }) {
                lead.value = changed.total; lead.balance = max(0, changed.total - (lead.depositPaid ? lead.deposit : 0))
                let target: LeadStage? =
                    changed.status == .accepted
                    ? .won : (lead.stage == .quotePreparing || lead.stage == .newLead || lead.stage == .surveyBooked ? .quoteSent : nil)
                if let target, lead.stage != target { await move(lead, to: target) } else { await saveLead(lead) }
            }
            return true
        } catch { errorMessage = "Quote could not be saved: \(error.localizedDescription)"; return false }
    }

    func generateQuoteDraft(for lead: Lead, brief: String, photos: [AssistantAttachment] = []) async -> GeneratedQuoteDraft? {
        assistantErrorMessage = nil
        guard KeychainStore.get("supabaseAccessToken") != nil else {
            assistantErrorMessage = "Sign out, then sign in again to use Gemini quote writing."
            return nil
        }
        let survey = surveys.filter { $0.leadID == lead.id }.sorted { $0.updatedAt > $1.updatedAt }.first
        do { return try await SupabaseService.shared.generateQuoteDraft(lead: lead, survey: survey, brief: brief, photos: photos) } catch {
            assistantErrorMessage = error.localizedDescription; return nil
        }
    }

    func deleteQuote(_ quote: CRMQuote) async {
        do { try await SupabaseService.shared.delete(from: "quotes", id: quote.id); quotes.removeAll { $0.id == quote.id } } catch {
            errorMessage = "Quote could not be deleted."
        }
    }

    private static func progress(of tasks: [CRMTask]) -> Int {
        tasks.isEmpty ? 0 : Int((Double(tasks.filter(\.completed).count) / Double(tasks.count) * 100).rounded())
    }

    private func reportLeadWrite(_ error: Error, fallback: String) {
        if error is SupabaseWriteConflict {
            errorMessage =
                "Someone else changed this customer or job after you opened it. Your change was not written over theirs. Refresh, review the latest details, then try again."
        } else {
            errorMessage = "\(fallback) \(error.localizedDescription)"
        }
    }

    func uploadLeadPhoto(leadID: String, data: Data, filename: String, contentType: String, category: String, caption: String?) async
        -> Bool
    {
        guard leads.contains(where: { $0.id == leadID }) else { return false }
        do {
            let locator = try await SupabaseService.shared.uploadAttachment(
                data: data, filename: filename, contentType: contentType, leadID: leadID)
            let photo = CRMPhoto(id: UUID().uuidString, url: locator, category: category, date: SupabaseService.today, caption: caption)
            let saved = await commitLead(leadID, fallback: "The photo could not be attached.") { $0.photos.append(photo) }
            if !saved { try? await SupabaseService.shared.deleteAttachment(locator: locator) }
            return saved
        } catch { errorMessage = "The photo could not be uploaded: \(error.localizedDescription)"; return false }
    }

    func uploadLeadFile(leadID: String, data: Data, filename: String, contentType: String) async -> Bool {
        guard leads.contains(where: { $0.id == leadID }) else { return false }
        do {
            let locator = try await SupabaseService.shared.uploadAttachment(
                data: data, filename: filename, contentType: contentType, leadID: leadID)
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            let type = contentType.hasPrefix("image/") ? "image" : (filename.lowercased().hasSuffix(".pdf") ? "pdf" : "document")
            let file = CRMFile(id: UUID().uuidString, name: filename, type: type, size: size, date: SupabaseService.today, url: locator)
            let saved = await commitLead(leadID, fallback: "The file could not be attached.") { $0.files.append(file) }
            if !saved { try? await SupabaseService.shared.deleteAttachment(locator: locator) }
            return saved
        } catch { errorMessage = "The file could not be uploaded: \(error.localizedDescription)"; return false }
    }

    func deleteLeadPhoto(leadID: String, photoID: String) async {
        guard let photo = leads.first(where: { $0.id == leadID })?.photos.first(where: { $0.id == photoID }) else { return }
        if await commitLead(leadID, fallback: "The photo could not be deleted.", mutate: { $0.photos.removeAll { $0.id == photoID } }) {
            try? await SupabaseService.shared.deleteAttachment(locator: photo.url)
        }
    }

    func deleteLeadFile(leadID: String, fileID: String) async {
        guard let file = leads.first(where: { $0.id == leadID })?.files.first(where: { $0.id == fileID }) else { return }
        if await commitLead(leadID, fallback: "The file could not be deleted.", mutate: { $0.files.removeAll { $0.id == fileID } }),
            let locator = file.url
        {
            try? await SupabaseService.shared.deleteAttachment(locator: locator)
        }
    }

    @discardableResult
    func addTimesheet(userID: String, leadID: String, date: String, halfDay: Bool) async -> Bool {
        guard !isWorkerPreview else { return false }
        guard isAdmin || currentUser?.id == userID else { errorMessage = "Team members can only record their own work days."; return false }
        guard !isTimesheetWeekLocked(userID: userID, date: date) else {
            errorMessage = "This pay week is approved or paid. Reopen it before changing timesheets."; return false
        }
        let rate = users.first { $0.id == userID }?.dayRate ?? 0
        if var existing = timesheets.first(where: { $0.userID == userID && $0.date == date }) {
            existing.leadID = leadID; existing.type = halfDay ? "half" : "full"; existing.amount = rate * (halfDay ? 0.5 : 1)
            return await saveTimesheet(existing)
        }
        let entry = TimesheetEntry(
            id: UUID().uuidString, userID: userID, leadID: leadID, date: date, type: halfDay ? "half" : "full",
            amount: rate * (halfDay ? 0.5 : 1), createdAt: SupabaseService.today)
        do { try await SupabaseService.shared.insert(entry, into: "timesheet_entries"); timesheets.append(entry); return true } catch {
            errorMessage = "Timesheet entry could not be saved: \(error.localizedDescription)"; return false
        }
    }

    @discardableResult
    func setTimesheetDay(userID: String, leadID: String, date: String, kind: String) async -> Bool {
        guard !isWorkerPreview else { return false }
        guard ["full", "half", "off"].contains(kind) else { return false }
        guard kind == "off" || !leadID.isEmpty else { errorMessage = "Choose the job worked on."; return false }
        guard isAdmin || currentUser?.id == userID else { errorMessage = "Team members can only record their own work days."; return false }
        guard !isTimesheetWeekLocked(userID: userID, date: date) else {
            errorMessage = "This week has been submitted and is locked. Ask an administrator to reopen it if something needs changing.";
            return false
        }
        let rate = users.first { $0.id == userID }?.dayRate ?? 0
        let amount = kind == "full" ? rate : kind == "half" ? rate * 0.5 : 0
        if var existing = timesheets.first(where: { $0.userID == userID && $0.date == date }) {
            existing.leadID = kind == "off" ? "" : leadID; existing.type = kind; existing.amount = amount
            return await saveTimesheet(existing)
        }
        let entry = TimesheetEntry(
            id: UUID().uuidString, userID: userID, leadID: kind == "off" ? "" : leadID, date: date, type: kind, amount: amount,
            createdAt: SupabaseService.now)
        do { try await SupabaseService.shared.insert(entry, into: "timesheet_entries"); timesheets.append(entry); return true } catch {
            errorMessage = "Work day could not be saved: \(error.localizedDescription)"; return false
        }
    }

    @discardableResult
    func saveTimesheet(_ entry: TimesheetEntry) async -> Bool {
        guard !isWorkerPreview else { return false }
        guard let index = timesheets.firstIndex(where: { $0.id == entry.id }) else {
            errorMessage = "Timesheet entry could not be found. Refresh and try again."; return false
        }
        let old = timesheets[index]
        guard isAdmin || (currentUser?.id == old.userID && entry.userID == old.userID) else {
            errorMessage = "Team members can only edit their own work days."; return false
        }
        guard !isTimesheetWeekLocked(userID: old.userID, date: old.date), !isTimesheetWeekLocked(userID: entry.userID, date: entry.date)
        else { errorMessage = "This pay week is approved or paid. Reopen it before changing timesheets."; return false }
        timesheets[index] = entry
        do { try await SupabaseService.shared.update(entry, in: "timesheet_entries", id: entry.id); return true } catch {
            timesheets[index] = old; errorMessage = "Timesheet changes could not be saved: \(error.localizedDescription)"; return false
        }
    }

    func deleteTimesheet(_ entry: TimesheetEntry) async {
        guard !isWorkerPreview else { return }
        guard isAdmin || currentUser?.id == entry.userID else { errorMessage = "Team members can only delete their own work days."; return }
        guard !isTimesheetWeekLocked(userID: entry.userID, date: entry.date) else {
            errorMessage = "This pay week is approved or paid. Reopen it before changing timesheets."; return
        }
        guard let index = timesheets.firstIndex(where: { $0.id == entry.id }) else { return }
        timesheets.remove(at: index)
        do { try await SupabaseService.shared.delete(from: "timesheet_entries", id: entry.id) } catch {
            timesheets.insert(entry, at: index); errorMessage = "Timesheet entry could not be deleted."
        }
    }

    @discardableResult
    func addAdminTimesheetCheck(userID: String, leadID: String, date: String, halfDay: Bool) async -> Bool {
        await setAdminTimesheetCheck(userID: userID, leadID: leadID, date: date, kind: halfDay ? "half" : "full")
    }

    @discardableResult
    func setAdminTimesheetCheck(userID: String, leadID: String, date: String, kind: String) async -> Bool {
        guard isAdmin else { errorMessage = "Only administrators can maintain the office timesheet copy."; return false }
        let rate = users.first { $0.id == userID }?.dayRate ?? 0
        if var existing = adminTimesheetChecks.first(where: { $0.userID == userID && $0.date == date }) {
            existing.leadID = kind == "off" ? "" : leadID
            existing.type = kind
            existing.amount = kind == "off" ? 0 : rate * (kind == "half" ? 0.5 : 1)
            return await saveAdminTimesheetCheck(existing)
        }
        let entry = TimesheetEntry(
            id: UUID().uuidString, userID: userID, leadID: kind == "off" ? "" : leadID, date: date, type: kind,
            amount: kind == "off" ? 0 : rate * (kind == "half" ? 0.5 : 1), createdAt: SupabaseService.now)
        do {
            try await SupabaseService.shared.insert(entry, into: "admin_timesheet_entries"); adminTimesheetChecks.append(entry); return true
        } catch { errorMessage = "Your office timesheet copy could not be saved: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func saveAdminTimesheetCheck(_ entry: TimesheetEntry) async -> Bool {
        guard isAdmin else { errorMessage = "Only administrators can maintain the office timesheet copy."; return false }
        guard let index = adminTimesheetChecks.firstIndex(where: { $0.id == entry.id }) else {
            errorMessage = "Office timesheet entry could not be found."; return false
        }
        let old = adminTimesheetChecks[index]; adminTimesheetChecks[index] = entry
        do { try await SupabaseService.shared.update(entry, in: "admin_timesheet_entries", id: entry.id); return true } catch {
            adminTimesheetChecks[index] = old; errorMessage = "Your office timesheet copy could not be updated."; return false
        }
    }

    func deleteAdminTimesheetCheck(_ entry: TimesheetEntry) async {
        guard isAdmin else { errorMessage = "Only administrators can maintain the office timesheet copy."; return }
        guard let index = adminTimesheetChecks.firstIndex(where: { $0.id == entry.id }) else { return }
        adminTimesheetChecks.remove(at: index)
        do { try await SupabaseService.shared.delete(from: "admin_timesheet_entries", id: entry.id) } catch {
            adminTimesheetChecks.insert(entry, at: index); errorMessage = "Office timesheet entry could not be deleted."
        }
    }

    private func isTimesheetWeekLocked(userID: String, date: String) -> Bool {
        guard let weekStart = PayrollPolicy.weekStartKey(for: date) else { return false }
        return paymentRuns.contains { $0.userID == userID && $0.weekStart == weekStart && $0.status != .due }
    }

    func setPaymentStatus(userID: String, weekStart: String, status: PaymentStatus) async {
        guard isAdmin else { errorMessage = "Only administrators can change payment-run status."; return }
        if let index = paymentRuns.firstIndex(where: { $0.userID == userID && $0.weekStart == weekStart }) {
            let old = paymentRuns[index]; var changed = old; changed.status = status;
            changed.paidDate = status == .paid ? SupabaseService.today : nil; paymentRuns[index] = changed
            do { try await SupabaseService.shared.update(changed, in: "payment_runs", id: changed.id) } catch {
                paymentRuns[index] = old; errorMessage = "Payment status could not be saved."
            }
        } else {
            let run = PaymentRun(
                id: UUID().uuidString, userID: userID, weekStart: weekStart, status: status,
                paidDate: status == .paid ? SupabaseService.today : nil, notes: nil, createdAt: SupabaseService.today)
            do { try await SupabaseService.shared.insert(run, into: "payment_runs"); paymentRuns.append(run) } catch {
                errorMessage = "Payment status could not be saved."
            }
        }
    }

    @discardableResult
    func submitTimesheetWeek(weekStart: String) async -> Bool {
        guard let user = currentUser else { return false }
        guard !isAdmin else { errorMessage = "Administrators approve worker submissions from the pay-run review."; return false }
        let monday = SupabaseService.date(from: weekStart) ?? .now
        let friday = Calendar.current.date(byAdding: .day, value: 4, to: monday) ?? monday
        let end = PayrollMath.key(friday)
        let completedDays = Set(timesheets.filter { $0.userID == user.id && $0.date >= weekStart && $0.date <= end }.map(\.date)).count
        guard completedDays == 5 else {
            errorMessage = "Complete all five weekdays, marking days you did not work as Off, before submitting."
            return false
        }
        if let index = paymentRuns.firstIndex(where: { $0.userID == user.id && $0.weekStart == weekStart }) {
            guard paymentRuns[index].status == .due else { errorMessage = "This week has already been submitted."; return false }
            let old = paymentRuns[index]; var changed = old; changed.status = .submitted;
            changed.notes = "Submitted \(SupabaseService.now)"; paymentRuns[index] = changed
            do { try await SupabaseService.shared.update(changed, in: "payment_runs", id: changed.id) } catch {
                paymentRuns[index] = old; errorMessage = "Your week could not be submitted: \(error.localizedDescription)"; return false
            }
        } else {
            let run = PaymentRun(
                id: UUID().uuidString, userID: user.id, weekStart: weekStart, status: .submitted, paidDate: nil,
                notes: "Submitted \(SupabaseService.now)", createdAt: SupabaseService.now)
            do { try await SupabaseService.shared.insert(run, into: "payment_runs"); paymentRuns.append(run) } catch {
                errorMessage = "Your week could not be submitted: \(error.localizedDescription)"; return false
            }
        }
        let admins = users.filter { $0.role == "admin" && $0.id != user.id }.map(\.id)
        if !admins.isEmpty {
            _ = try? await SupabaseService.shared.sendPushEvent(
                "task_assigned", detail: "\(user.name) submitted their Monday–Friday work record for review.", userIDs: admins)
        }
        return true
    }

    @discardableResult
    func addWorkerPayment(userID: String, amount: Double, date: String, notes: String?) async -> Bool {
        guard isAdmin else { errorMessage = "Only administrators can record worker payments."; return false }
        let payment = WorkerPayment(
            id: UUID().uuidString, userID: userID, amount: amount, date: date, notes: notes, createdAt: SupabaseService.today,
            monzoTransactionID: nil)
        do {
            try await SupabaseService.shared.insert(payment, into: "worker_payments"); workerPayments.insert(payment, at: 0); return true
        } catch { errorMessage = "Worker payment could not be saved: \(error.localizedDescription)"; return false }
    }

    func deleteWorkerPayment(_ payment: WorkerPayment) async {
        guard isAdmin else { errorMessage = "Only administrators can delete worker payments."; return }
        guard let index = workerPayments.firstIndex(where: { $0.id == payment.id }) else { return }
        workerPayments.remove(at: index)
        do { try await SupabaseService.shared.delete(from: "worker_payments", id: payment.id) } catch {
            workerPayments.insert(payment, at: index); errorMessage = "Worker payment could not be deleted."
        }
    }

    @discardableResult
    func saveWorkerProfile(_ user: CRMUser) async -> Bool {
        guard isAdmin else { errorMessage = "Only administrators can change worker payment details."; return false }
        guard let index = users.firstIndex(where: { $0.id == user.id }) else {
            errorMessage = "Worker could not be found. Refresh and try again."; return false
        }
        let old = users[index]; users[index] = user
        do {
            try await SupabaseService.shared.updateAuthenticatedProfile(user)
            if currentUser?.id == user.id { currentUser = user }
            return true
        } catch {
            users[index] = old; errorMessage = "Worker payment details could not be saved: \(error.localizedDescription)"; return false
        }
    }

    @discardableResult
    func addContact(name: String, phone: String, email: String, address: String) async -> Bool {
        let contact = CRMContact(
            id: UUID().uuidString, name: name, phone: phone, email: email, address: address, createdAt: SupabaseService.today)
        do { try await SupabaseService.shared.insert(contact, into: "contacts"); contacts.insert(contact, at: 0); return true } catch {
            errorMessage = "The contact could not be saved: \(error.localizedDescription)"; return false
        }
    }

    @discardableResult
    func saveContact(_ contact: CRMContact) async -> Bool {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else {
            errorMessage = "Contact could not be found. Refresh and try again."; return false
        }
        let old = contacts[index]; contacts[index] = contact
        do { try await SupabaseService.shared.update(contact, in: "contacts", id: contact.id); return true } catch {
            contacts[index] = old; errorMessage = "The contact could not be updated: \(error.localizedDescription)"; return false
        }
    }

    @discardableResult
    func deleteContact(_ contact: CRMContact) async -> Bool {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else {
            errorMessage = "Contact could not be found. Refresh and try again."; return false
        }
        contacts.remove(at: index)
        do { try await SupabaseService.shared.delete(from: "contacts", id: contact.id); return true } catch {
            contacts.insert(contact, at: index); errorMessage = "The contact could not be deleted: \(error.localizedDescription)";
            return false
        }
    }

    func refreshTeam(showErrors: Bool = true) async throws {
        do {
            async let fetchedMessages = SupabaseService.shared.fetchTeamMessages()
            async let fetchedPlans = SupabaseService.shared.fetchTeamDayPlans()
            let (messages, plans) = try await (fetchedMessages, fetchedPlans)
            adoptTeam(messages: messages, plans: plans)
        } catch {
            if !syncIssues.contains("Team Hub") { syncIssues.append("Team Hub") }
            if showErrors { errorMessage = "Team Hub could not be refreshed: \(error.localizedDescription)" }
            throw error
        }
    }

    private func adoptTeam(messages: [TeamMessage], plans: [TeamDayPlan]) {
        let oldIDs = Set(teamMessages.map(\.id))
        let hadMessages = !teamMessages.isEmpty
        teamMessages = messages
        teamDayPlans = plans
        // Push already announces new messages on registered devices; only fall back
        // to a local banner where this device has no push registration.
        if hadMessages, UserDefaults.standard.string(forKey: "nativePushDeviceToken") == nil,
            let newest = messages.first(where: { !oldIDs.contains($0.id) && $0.authorID != currentUser?.id })
        {
            Task { await notifyAboutTeamMessage(newest) }
        }
        syncIssues.removeAll { $0 == "Team Hub" }
    }

    @discardableResult
    func sendTeamMessage(_ body: String, day: String? = nil, leadID: String? = nil) async -> Bool {
        guard let user = currentUser else { return false }
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        let message = TeamMessage(
            id: UUID().uuidString, authorID: user.id, authorName: user.name, body: clean, day: day, leadID: leadID,
            createdAt: SupabaseService.now)
        do {
            try await SupabaseService.shared.insert(message, into: "team_messages")
            teamMessages.insert(message, at: 0); markTeamRead()
            let recipients = users.filter { $0.id != user.id }.map(\.id)
            if !recipients.isEmpty {
                _ = try? await SupabaseService.shared.sendPushEvent("team_message", name: user.name, detail: clean, userIDs: recipients)
            }
            return true
        } catch { errorMessage = "Message could not be sent: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func saveTeamDayPlan(_ plan: TeamDayPlan) async -> Bool {
        do {
            if teamDayPlans.contains(where: { $0.id == plan.id }) {
                try await SupabaseService.shared.update(plan, in: "team_day_plans", id: plan.id)
            } else {
                try await SupabaseService.shared.insert(plan, into: "team_day_plans")
            }
            try await refreshTeam(showErrors: false)
            await scheduleNotifications()
            return true
        } catch { errorMessage = "Day plan could not be saved: \(error.localizedDescription)"; return false }
    }

    func markTeamRead() {
        UserDefaults.standard.set(
            teamMessages.first?.createdAt ?? SupabaseService.now, forKey: "teamLastRead.\(currentUser?.id ?? "signed-out")")
    }

    private func notifyAboutTeamMessage(_ message: TeamMessage) async {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled"), preference("notifyTeam") else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(message.authorName) · Team Hub"
        content.body = message.body
        content.sound = .default
        content.userInfo = ["url": "prolinecrm://team"]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "team-message-\(message.id)", content: content, trigger: nil))
    }

    func changePassword(password: String) async -> Bool {
        do { try await SupabaseService.shared.updateAuthenticatedPassword(password); return true } catch {
            errorMessage = "The password could not be changed."; return false
        }
    }

    func enableNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]);
            if granted {
                UserDefaults.standard.set(true, forKey: "notificationsEnabled"); requestRemoteNotificationRegistration();
                await scheduleNotifications()
            } else {
                errorMessage = "Notifications are disabled in System Settings."
            }
        } catch { errorMessage = "Notification permission could not be requested." }
    }

    func registerRemoteNotificationToken(_ token: String) async {
        guard isAuthenticated else { return }
        #if DEBUG
            let environment = "development"
        #else
            let environment = "production"
        #endif
        #if os(iOS)
            let platform = "ios"
        #else
            let platform = "macos"
        #endif
        do {
            try await SupabaseService.shared.registerNativePushDevice(
                token: token, platform: platform, environment: environment, bundleID: Bundle.main.bundleIdentifier ?? "")
            UserDefaults.standard.set(token, forKey: "nativePushDeviceToken")
            syncIssues.removeAll { $0 == "Push notifications" }
        } catch {
            if !syncIssues.contains("Push notifications") { syncIssues.append("Push notifications") }
            errorMessage =
                "Notifications were allowed, but this device could not be connected to live updates: \(error.localizedDescription)"
        }
    }

    private func requestRemoteNotificationRegistration() {
        #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func resumeRemoteNotificationsIfEnabled() {
        guard isAuthenticated, UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        requestRemoteNotificationRegistration()
    }

    func handleRemoteNotificationRegistrationFailure(_ detail: String?) {
        UserDefaults.standard.removeObject(forKey: "nativePushDeviceToken")
        UserDefaults.standard.set(detail ?? "Apple Push registration unavailable", forKey: "remotePushRegistrationIssue")
        if !syncIssues.contains("Push notifications") { syncIssues.append("Push notifications") }
        // Local scheduled reminders remain available. A provisioning failure should
        // not interrupt normal CRM work with a technical system alert.
    }

    // Many taps in a row should produce one rebuild, not one per tap: rescheduling up
    // to 60 notifications and reloading widget timelines is system-rate-limited work.
    private var notificationRebuild: Task<Void, Never>?
    private var widgetRebuild: Task<Void, Never>?

    func scheduleNotifications() async {
        notificationRebuild?.cancel()
        notificationRebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self else { return }
            await self.rebuildNotifications()
        }
    }

    private func rebuildNotifications() async {
        await clearCRMNotifications()
        #if os(iOS)
            await updateTaskLiveActivities()
        #endif
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard notificationsEnabled else {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
            return
        }
        let operationalPlans = NotificationPolicy.plans(
            leads: notificationLeads,
            tasks: notificationTasks,
            notifySurveys: preference("notifySurveys"),
            notifyJobStarts: preference("notifyJobStarts"),
            notifyTasks: preference("notifyTasks"),
            notifyPayments: preference("notifyPayments"),
            isAdmin: isAdmin
        )
        let teamPlans = TeamNotificationPolicy.plans(
            plans: teamDayPlans,
            userName: currentUser?.name,
            enabled: preference("notifyTeam")
        )
        let plans = (operationalPlans + teamPlans).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let center = UNUserNotificationCenter.current()
        var failed = false
        for plan in plans.prefix(NotificationPolicy.maximumPending) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            if plan.id.hasPrefix("team-plan-") { content.userInfo = ["url": "prolinecrm://team"] }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: plan.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            } catch { failed = true }
        }
        if failed {
            if !syncIssues.contains("Notifications") { syncIssues.append("Notifications") }
        } else {
            syncIssues.removeAll { $0 == "Notifications" }
        }
        let overdueTasks = notificationTasks.filter { !$0.completed && ($0.dueDate ?? "9999-12-31") <= SupabaseService.today }.count
        let overdueJobs = notificationLeads.filter {
            ($0.endDate ?? "9999-12-31") < SupabaseService.today && ![.completed, .waitingForPayment, .paid, .lost].contains($0.stage)
        }.count
        let payments = PaymentReminderPolicy.summary(leads: notificationLeads, isAdmin: isAdmin, enabled: preference("notifyPayments"))
            .count
        try? await UNUserNotificationCenter.current().setBadgeCount(overdueTasks + overdueJobs + payments + unreadTeamCount)
    }

    func gmailAuthorizationURL() async -> URL? {
        do { return try await SupabaseService.shared.gmailAuthorizationURL() } catch {
            errorMessage = "Gmail connection could not start: \(error.localizedDescription)"; return nil
        }
    }
    func refreshGmailConnectionStatus() async {
        do { gmailConnectionStatus = try await SupabaseService.shared.gmailConnectionStatus() } catch { gmailConnectionStatus = nil }
    }
    func scanGmailNow() async -> Int? {
        do { let count = try await SupabaseService.shared.scanGmail(); await refresh(showErrors: false); return count } catch {
            errorMessage = "Gmail inbox could not be scanned: \(error.localizedDescription)"; return nil
        }
    }

    func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await enableNotifications(); return
        }
        guard UserDefaults.standard.string(forKey: "nativePushDeviceToken") != nil else {
            requestRemoteNotificationRegistration()
            errorMessage = "This device is registering with Apple. Wait a few seconds, then press Send test notification again."
            return
        }
        do {
            let sent = try await SupabaseService.shared.sendPushEvent("test", userIDs: currentUser.map { [$0.id] } ?? [])
            if sent == 0 { errorMessage = "No registered Apple devices were found. Re-enable notifications on this device and try again." }
        } catch { errorMessage = "The live test notification could not be sent: \(error.localizedDescription)" }
    }

    #if os(iOS)
        func startTaskLiveActivity() async {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                errorMessage = "Live Activities are disabled. Enable them for ProLine CRM in iPhone Settings."
                return
            }
            let state = taskActivityState()
            guard state.openCount > 0 else { errorMessage = "There are no current admin tasks to show."; return }
            do {
                if let current = Activity<ProLineTaskActivityAttributes>.activities.first {
                    await current.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(1800)))
                } else {
                    let attributes = ProLineTaskActivityAttributes(title: "Office tasks")
                    _ = try Activity<ProLineTaskActivityAttributes>.request(
                        attributes: attributes, content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(1800)),
                        pushType: nil)
                }
            } catch { errorMessage = "The task Live Activity could not start: \(error.localizedDescription)" }
        }

        private func updateTaskLiveActivities() async {
            let state = taskActivityState()
            for activity in Activity<ProLineTaskActivityAttributes>.activities {
                if state.openCount == 0 {
                    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
                } else {
                    await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(1800)))
                }
            }
        }

        private func taskActivityState() -> ProLineTaskActivityAttributes.ContentState {
            let today = SupabaseService.today
            let general = notificationTasks.filter { !$0.completed && FleetTaskPolicy.shouldShowInTaskList($0) }
                .map { (title: $0.title, due: $0.dueDate) }
            let jobs = notificationLeads.flatMap { lead in
                lead.tasks.filter { !$0.completed }.map { (title: "\(lead.name): \($0.title)", due: $0.dueDate) }
            }
            let sorted = (general + jobs).sorted { ($0.due ?? "9999", $0.title) < ($1.due ?? "9999", $1.title) }
            return .init(
                taskTitles: Array(sorted.prefix(3).map(\.title)), openCount: sorted.count,
                overdueCount: sorted.filter { ($0.due ?? "9999") < today }.count, updatedAt: .now)
        }
    #endif

    private func syncContact(from lead: Lead) async throws {
        guard !lead.phone.isEmpty || !lead.email.isEmpty else { return }
        if let index = contacts.firstIndex(where: {
            (!$0.phone.isEmpty && $0.phone == lead.phone)
                || (!$0.email.isEmpty && $0.email.caseInsensitiveCompare(lead.email) == .orderedSame)
        }) {
            var contact = contacts[index]; contact.name = lead.name; contact.phone = lead.phone; contact.email = lead.email;
            contact.address = lead.address
            try await SupabaseService.shared.update(contact, in: "contacts", id: contact.id); contacts[index] = contact
        } else {
            let contact = CRMContact(
                id: UUID().uuidString, name: lead.name, phone: lead.phone, email: lead.email, address: lead.address,
                createdAt: SupabaseService.today)
            try await SupabaseService.shared.insert(contact, into: "contacts"); contacts.insert(contact, at: 0)
        }
    }

    private func preference(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

    private var notificationLeads: [Lead] { leads.filter { NotificationScope.includes($0, for: currentUser) } }
    private var notificationTasks: [GeneralTask] { visibleGeneralTasks.filter { NotificationScope.includes($0, for: currentUser) } }

    private func clearCRMNotifications() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix("survey-") || $0.hasPrefix("start-") || $0.hasPrefix("task-") || $0.hasPrefix("payment-")
                || $0.hasPrefix("team-plan-")
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func updateWidget() {
        widgetRebuild?.cancel()
        widgetRebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            self.rebuildWidget()
        }
    }

    private func rebuildWidget() {
        let today = SupabaseService.today
        let widgetTasks =
            notificationTasks
            .filter { !$0.completed && $0.category != "Fleet Vehicle" && FleetTaskPolicy.shouldShowInTaskList($0) }
            .sorted {
                let left = $0.dueDate ?? "9999-12-31"
                let right = $1.dueDate ?? "9999-12-31"
                if left != right { return left < right }
                return $0.priority == "high" && $1.priority != "high"
            }
            .prefix(6)
            .map { WidgetSnapshot.TaskItem(id: $0.id, title: $0.title, dueDate: $0.dueDate, priority: $0.priority) }
        WidgetSnapshot(
            surveysToday: notificationLeads.filter { $0.surveyDate == today }.count,
            overdueJobs: notificationLeads.filter {
                ($0.endDate ?? today) < today && ![.completed, .waitingForPayment, .paid, .lost].contains($0.stage)
            }.count,
            activeJobs: notificationLeads.filter { $0.stage == .inProgress }.count,
            tasks: widgetTasks,
            updatedAt: .now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
            Task { await updateTaskLiveActivities() }
        #endif
    }
}

struct PendingCall: Identifiable, Sendable {
    let id: String
    let leadName: String
    let startedAt: Date
}

enum CallOutcome: String, CaseIterable, Identifiable, Sendable {
    case spoke, noAnswer, voicemail
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spoke: "Spoke to customer";
        case .noAnswer: "No answer";
        case .voicemail: "Left voicemail"
        }
    }
    var short: String {
        switch self {
        case .spoke: "Spoke";
        case .noAnswer: "No answer";
        case .voicemail: "Voicemail"
        }
    }
}

enum NotificationScope {
    nonisolated static func includes(_ lead: Lead, for user: CRMUser?) -> Bool {
        guard let user else { return false }
        if user.role == "admin" { return true }
        return LeadOwnership.isAssigned(lead, to: user)
    }

    nonisolated static func includes(_ task: GeneralTask, for user: CRMUser?) -> Bool {
        guard let user else { return false }
        if user.role == "admin" { return true }
        return task.assignedTo.contains(user.id)
    }
}

enum LeadOwnership {
    nonisolated static func isAssigned(_ lead: Lead, to user: CRMUser?) -> Bool {
        guard let user else { return false }
        let owner = lead.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !owner.isEmpty && !name.isEmpty && owner.caseInsensitiveCompare(name) == .orderedSame
    }
}

enum AuthenticationPolicy {
    nonisolated static func secureEmail(for identifier: String) -> String? {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("@") { return value }
        // Keep the familiar CRM username while authenticating the admin through
        // Supabase Auth so protected AI and storage functions receive a real JWT.
        if value == "willconway9" { return "admin@prolineroofingandsolar.co.uk" }
        return nil
    }
}

enum LeadAccessScope {
    nonisolated static func visible(_ leads: [Lead], for user: CRMUser?) -> [Lead] {
        guard let user else { return [] }
        if user.role == "admin" { return leads }
        return leads.filter { LeadOwnership.isAssigned($0, to: user) }
    }
}

enum UserAccessScope {
    nonisolated static func visible(_ users: [CRMUser], for currentUser: CRMUser?) -> [CRMUser] {
        guard let currentUser else { return [] }
        if currentUser.role == "admin" { return users }
        return users.map { user in
            guard user.id != currentUser.id else { return user }
            var publicUser = user
            publicUser.dayRate = nil
            publicUser.cisRate = nil
            publicUser.utrNumber = nil
            publicUser.bankName = nil
            publicUser.bankAccountNumber = nil
            publicUser.bankSortCode = nil
            return publicUser
        }
    }
}

enum TimesheetAccessScope {
    nonisolated static func visible(_ entries: [TimesheetEntry], for user: CRMUser?) -> [TimesheetEntry] {
        guard let user else { return [] }
        return user.role == "admin" ? entries : entries.filter { $0.userID == user.id }
    }
}

enum TaskAccessScope {
    nonisolated static func visible(_ tasks: [GeneralTask], for user: CRMUser?) -> [GeneralTask] {
        guard let user else { return [] }
        return user.role == "admin" ? tasks : tasks.filter { $0.assignedTo.contains(user.id) }
    }
}

enum ContactAccessScope {
    nonisolated static func visible(_ contacts: [CRMContact], leads: [Lead], for user: CRMUser?) -> [CRMContact] {
        guard let user else { return [] }
        if user.role == "admin" { return contacts }
        let phones = Set(leads.map(\.phone).filter { !$0.isEmpty })
        let emails = Set(leads.map { $0.email.lowercased() }.filter { !$0.isEmpty })
        return contacts.filter { phones.contains($0.phone) || emails.contains($0.email.lowercased()) }
    }
}

enum WorkflowAccessScope {
    nonisolated static func visible(_ surveys: [RoofSurvey], leads: [Lead]) -> [RoofSurvey] {
        let ids = Set(leads.map(\.id))
        return surveys.filter { ids.contains($0.leadID) }
    }

    nonisolated static func visible(_ quotes: [CRMQuote], leads: [Lead]) -> [CRMQuote] {
        let ids = Set(leads.map(\.id))
        return quotes.filter { ids.contains($0.leadID) }
    }
}

enum PaymentAccessScope {
    nonisolated static func visible(_ runs: [PaymentRun], for user: CRMUser?) -> [PaymentRun] {
        guard let user else { return [] }
        return user.role == "admin" ? runs : runs.filter { $0.userID == user.id }
    }

    nonisolated static func visible(_ payments: [WorkerPayment], for user: CRMUser?) -> [WorkerPayment] {
        guard let user else { return [] }
        return user.role == "admin" ? payments : payments.filter { $0.userID == user.id }
    }
}

enum PayrollPolicy {
    nonisolated static func weekStartKey(for day: String, calendar: Calendar = .current) -> String? {
        guard let date = SupabaseService.date(from: day) else { return nil }
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let start = mondayCalendar.startOfDay(for: date)
        let weekday = mondayCalendar.component(.weekday, from: start)
        guard let monday = mondayCalendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: start) else { return nil }
        return SupabaseService.localDay(for: monday, calendar: mondayCalendar)
    }
}

enum JobReference {
    /// Human-readable and collision resistant across multiple staff devices.
    /// Example: JOB-260824-143507-A1B2.
    nonisolated static func make(date: Date, calendar: Calendar = .current, nonce: String) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = (parts.year ?? 0) % 100
        let suffix = nonce.uppercased().filter(\.isHexDigit).prefix(4)
        return String(
            format: "JOB-%02d%02d%02d-%02d%02d%02d-%@", year, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0,
            parts.second ?? 0, String(suffix))
    }
}

enum QuoteReference {
    /// Stable across staff devices without relying on a locally visible quote count.
    nonisolated static func make(date: Date, calendar: Calendar = .current, nonce: String) -> String {
        let year = calendar.component(.year, from: date)
        let suffix = nonce.uppercased().filter(\.isHexDigit).prefix(6)
        return "Q-\(year)-\(suffix)"
    }
}

enum NotificationPolicy {
    static let maximumPending = 60

    nonisolated static func reminderDate(for day: String, hour: Int, calendar: Calendar = .current) -> Date? {
        guard let date = SupabaseService.date(from: day) else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
    }

    nonisolated static func nextDailyReminder(hour: Int, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)
        if let today, today > now { return today }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)
    }

    nonisolated static func plans(
        leads: [Lead], tasks: [GeneralTask], notifySurveys: Bool, notifyJobStarts: Bool,
        notifyTasks: Bool, notifyPayments: Bool, isAdmin: Bool,
        now: Date = .now, calendar: Calendar = .current
    ) -> [CRMNotificationPlan] {
        var result: [CRMNotificationPlan] = []
        for lead in leads {
            if notifySurveys, let day = lead.surveyDate,
                let date = reminderDate(for: day, hour: 8, calendar: calendar), date > now
            {
                result.append(.init(id: "survey-\(lead.id)", title: "Survey due", body: "\(lead.name) · \(lead.jobType)", date: date))
            }
            if notifyJobStarts, let day = lead.startDate,
                let date = reminderDate(for: day, hour: 7, calendar: calendar), date > now
            {
                result.append(.init(id: "start-\(lead.id)", title: "Job starts", body: "\(lead.name) · \(lead.jobType)", date: date))
            }
        }
        if notifyTasks {
            for task in tasks where !task.completed {
                guard let day = task.dueDate,
                    let date = reminderDate(for: day, hour: 8, calendar: calendar), date > now
                else { continue }
                result.append(.init(id: "task-\(task.id)", title: "Task due", body: task.title, date: date))
            }
            if let date = nextDailyReminder(hour: 9, now: now, calendar: calendar) {
                for lead in leads where ![LeadStage.completed, .waitingForPayment, .paid, .lost].contains(lead.stage) {
                    guard let updated = SupabaseService.date(from: String(lead.updatedAt.prefix(10))),
                        let staleCutoff = calendar.date(byAdding: .day, value: -3, to: now), updated < staleCutoff
                    else { continue }
                    let days = max(3, calendar.dateComponents([.day], from: updated, to: now).day ?? 3)
                    result.append(
                        .init(
                            id: "stale-lead-\(lead.id)", title: "Customer needs an update",
                            body: "\(lead.name) · no update for \(days) days", date: date))
                }
            }
        }
        let payments = PaymentReminderPolicy.summary(leads: leads, isAdmin: isAdmin, enabled: notifyPayments)
        if payments.count > 0, let date = nextDailyReminder(hour: 9, now: now, calendar: calendar) {
            result.append(
                .init(
                    id: "payment-summary", title: "Customer payments need attention",
                    body:
                        "\(payments.count) payment\(payments.count == 1 ? "" : "s") · \(payments.total.formatted(.currency(code: "GBP"))) to collect",
                    date: date
                ))
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

enum TeamNotificationPolicy {
    nonisolated static func plans(
        plans: [TeamDayPlan], userName: String?, enabled: Bool,
        now: Date = .now, calendar: Calendar = .current
    ) -> [CRMNotificationPlan] {
        guard enabled, let userName, !userName.isEmpty else { return [] }
        return plans.compactMap { plan in
            guard plan.assignedTo.contains(where: { $0.caseInsensitiveCompare(userName) == .orderedSame }),
                let workDate = workDate(day: plan.day, time: plan.startTime, calendar: calendar),
                let reminder = calendar.date(byAdding: .minute, value: -30, to: workDate),
                reminder > now
            else { return nil }
            let time = plan.startTime.map { " at \($0)" } ?? ""
            return CRMNotificationPlan(
                id: "team-plan-\(plan.id)", title: "Work starts in 30 minutes",
                body: "\(plan.title)\(time)", date: reminder
            )
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    nonisolated private static func workDate(day: String, time: String?, calendar: Calendar) -> Date? {
        guard let base = SupabaseService.date(from: day) else { return nil }
        let values = (time ?? "08:00").split(separator: ":").compactMap { Int($0) }
        guard values.count >= 2 else { return nil }
        return calendar.date(bySettingHour: values[0], minute: values[1], second: 0, of: base)
    }
}

struct CRMNotificationPlan: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

enum PaymentReminderPolicy {
    nonisolated static func summary(leads: [Lead], isAdmin: Bool, enabled: Bool) -> (count: Int, total: Double) {
        guard isAdmin, enabled else { return (0, 0) }
        let actionable = leads.filter { lead in
            guard ![LeadStage.paid, .lost].contains(lead.stage), lead.balance > 0 else { return false }
            return [.completed, .waitingForPayment].contains(lead.stage)
                || (!lead.depositPaid && lead.deposit > 0 && [.won, .scheduled, .inProgress].contains(lead.stage))
        }
        return (
            actionable.count,
            actionable.reduce(0) { total, lead in
                total + ([.completed, .waitingForPayment].contains(lead.stage) ? lead.balance : lead.deposit)
            }
        )
    }
}

enum FleetTaskPolicy {
    nonisolated static func isRetiredReminder(_ task: GeneralTask) -> Bool {
        guard ["Fleet", "Vehicle", "Renewal"].contains(task.category) else { return false }
        return task.title.localizedCaseInsensitiveContains("insurance")
            || task.title.localizedCaseInsensitiveContains("road tax")
    }

    nonisolated static func shouldShowInTaskList(_ task: GeneralTask, today: Date = .now) -> Bool {
        guard ["Fleet", "Vehicle", "Renewal"].contains(task.category), let due = task.dueDate, let date = SupabaseService.date(from: due)
        else { return true }
        let revealDate = Calendar.current.date(byAdding: .day, value: -45, to: date) ?? date
        return today >= revealDate
    }
}

enum SyncPolicy {
    static let activeRefreshSeconds: UInt64 = 60
    nonisolated static func shouldStart(isAuthenticated: Bool, isRefreshing: Bool) -> Bool {
        isAuthenticated && !isRefreshing
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", pipeline = "Pipeline", jobs = "Jobs", tasks = "Tasks", email = "Email", calendar = "Calendar", team =
        "Team Hub", contacts = "Contacts", files = "Files", fleet = "Fleet", accounts = "Accounts", finance = "Finance", reports =
        "Reports", timesheet = "Timesheet", cis = "CIS", tools = "Tools", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: "chart.bar";
        case .pipeline: "rectangle.3.group";
        case .jobs: "briefcase";
        case .tasks: "checklist";
        case .email: "envelope.badge";
        case .calendar: "calendar";
        case .team: "bubble.left.and.bubble.right.fill";
        case .contacts: "person.crop.circle";
        case .files: "folder";
        case .fleet: "car.2";
        case .accounts: "building.columns";
        case .finance: "sterlingsign.circle";
        case .reports: "chart.pie";
        case .timesheet: "clock";
        case .cis: "doc.text";
        case .tools: "wrench.and.screwdriver";
        case .settings: "gearshape"
        }
    }
}
