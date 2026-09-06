import Foundation

struct GmailConnectionStatus: Decodable {
    let connected: Bool
    let gmailAddress: String?
    let lastScannedAt: String?
    enum CodingKeys: String, CodingKey {
        case connected
        case gmailAddress = "gmail_address"
        case lastScannedAt = "last_scanned_at"
    }
}

actor SupabaseService {
    static let shared = SupabaseService()
    private let baseURL = URL(string: "https://qzvdzzvkocmulcfujyea.supabase.co/rest/v1")!
    private let storageURL = URL(string: "https://qzvdzzvkocmulcfujyea.supabase.co/storage/v1")!
    private let authURL = URL(string: "https://qzvdzzvkocmulcfujyea.supabase.co/auth/v1")!
    private let functionsURL = URL(string: "https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmR6enZrb2NtdWxjZnVqeWVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NzIxNjUsImV4cCI6MjA5NDQ0ODE2NX0.g42AvuElukfbpgbg9Y6XImnuHQ2Po5GEaVVGMz3Siu0"
    private let decoder: JSONDecoder = { let value = JSONDecoder(); return value }()

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, _) = try await authenticatedData(for: request)
        return try decoder.decode(type, from: data)
    }

    private func authenticatedData(for originalRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (firstData, firstResponse) = try await URLSession.shared.data(for: originalRequest)
        guard let firstHTTP = firstResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if firstHTTP.statusCode == 401, KeychainStore.get("supabaseRefreshToken") != nil {
            do { try await refreshAccessToken() }
            catch { throw SupabaseSessionExpired() }
            var retry = originalRequest
            guard let token = KeychainStore.get("supabaseAccessToken") else { throw SupabaseSessionExpired() }
            retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard 200..<300 ~= retryHTTP.statusCode else {
                if retryHTTP.statusCode == 401 || retryHTTP.statusCode == 403 { throw SupabaseSessionExpired() }
                throw SupabaseHTTPError(statusCode: retryHTTP.statusCode, message: Self.safeServerMessage(from: retryData))
            }
            return (retryData, retryHTTP)
        }
        guard 200..<300 ~= firstHTTP.statusCode else { throw SupabaseHTTPError(statusCode: firstHTTP.statusCode, message: Self.safeServerMessage(from: firstData)) }
        return (firstData, firstHTTP)
    }

    private nonisolated static func safeServerMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["error"] as? String ?? object["message"] as? String)?.prefix(240).description
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken = KeychainStore.get("supabaseRefreshToken") else { throw SupabaseSessionExpired() }
        var refresh = URLRequest(url: authURL.appending(path: "token").appending(queryItems: [.init(name: "grant_type", value: "refresh_token")]))
        refresh.httpMethod = "POST"
        refresh.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        refresh.setValue(anonKey, forHTTPHeaderField: "apikey")
        refresh.setValue("application/json", forHTTPHeaderField: "Content-Type")
        persist(try await executeAuth(refresh))
    }

    func fetchLeads() async throws -> [Lead] {
        let urlRequest = try request(path: "leads", query: [.init(name: "select", value: "*"), .init(name: "order", value: "updated_at.desc")])
        let (data, _) = try await authenticatedData(for: urlRequest)
        // Older web builds sometimes saved JSONB arrays as JSON strings. Normalise
        // those rows so one legacy notes/files value cannot blank the whole pipeline.
        guard var rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        for rowIndex in rows.indices {
            for key in ["tasks", "photos", "notes", "files", "materials"] {
                if let string = rows[rowIndex][key] as? String {
                    if let nested = string.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: nested),
                       let array = parsed as? [Any] { rows[rowIndex][key] = array }
                    else { rows[rowIndex][key] = [] }
                } else if rows[rowIndex][key] is NSNull {
                    rows[rowIndex][key] = []
                }
            }
        }
        return try decoder.decode([Lead].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    func fetchUsers() async throws -> [CRMUser] {
        if KeychainStore.get("supabaseAccessToken") != nil {
            let profiles: [AuthProfile] = try await execute(request(path: "profiles", query: [.init(name: "select", value: "*")]), as: [AuthProfile].self)
            return profiles.filter { $0.active != false }.map(profileUser)
        }
        return try await execute(request(path: "app_users", query: [.init(name: "select", value: "*")]), as: [CRMUser].self)
    }

    func fetchContacts() async throws -> [CRMContact] { try await fetch("contacts", as: CRMContact.self) }
    func fetchTasks() async throws -> [GeneralTask] { try await fetch("general_tasks", as: GeneralTask.self) }
    func fetchTimesheets() async throws -> [TimesheetEntry] { try await fetch("timesheet_entries", as: TimesheetEntry.self) }
    func fetchPaymentRuns() async throws -> [PaymentRun] { try await fetch("payment_runs", as: PaymentRun.self) }
    func fetchWorkerPayments() async throws -> [WorkerPayment] { try await fetch("worker_payments", as: WorkerPayment.self) }
    func fetchSurveys() async throws -> [RoofSurvey] { try await fetch("roof_surveys", as: RoofSurvey.self) }
    func fetchAdminTimesheetChecks() async throws -> [TimesheetEntry] { try await fetch("admin_timesheet_entries", as: TimesheetEntry.self) }
    func fetchQuotes() async throws -> [CRMQuote] { try await fetch("quotes", as: CRMQuote.self) }
    func fetchTeamMessages() async throws -> [TeamMessage] {
        try await execute(request(path: "team_messages", query: [.init(name: "select", value: "*"), .init(name: "order", value: "created_at.desc"), .init(name: "limit", value: "200")]), as: [TeamMessage].self)
    }
    func fetchTeamDayPlans() async throws -> [TeamDayPlan] {
        try await execute(request(path: "team_day_plans", query: [.init(name: "select", value: "*"), .init(name: "order", value: "day.asc,start_time.asc")]), as: [TeamDayPlan].self)
    }

    func lookupMOT(registration: String) async throws -> MOTVehicleLookup {
        var lookup = URLRequest(url: functionsURL.appending(path: "mot-lookup"))
        lookup.httpMethod = "POST"
        lookup.httpBody = try JSONSerialization.data(withJSONObject: ["registration": registration])
        lookup.setValue(anonKey, forHTTPHeaderField: "apikey")
        lookup.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        lookup.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: lookup)
        return try decoder.decode(MOTVehicleLookup.self, from: data)
    }

    func analyseJobNote(lead: Lead, note: String) async throws -> JobNoteAnalysis {
        struct TaskRecord: Encodable { let id: String; let title: String; let completed: Bool; let dueDate: String?; enum CodingKeys: String, CodingKey { case id, title, completed; case dueDate = "due_date" } }
        struct Payload: Encodable {
            let jobType: String; let stage: String; let note: String; let tasks: [TaskRecord]; let today: String
            enum CodingKeys: String, CodingKey { case stage, note, tasks, today; case jobType = "job_type" }
        }
        var call = URLRequest(url: functionsURL.appending(path: "analyse-job-note"))
        call.httpMethod = "POST"
        call.timeoutInterval = 35
        call.httpBody = try JSONEncoder().encode(Payload(jobType: lead.jobType, stage: lead.stage.rawValue, note: note, tasks: lead.tasks.map { .init(id: $0.id, title: $0.title, completed: $0.completed, dueDate: $0.dueDate) }, today: Self.today))
        call.setValue(anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: call)
        return try decoder.decode(JobNoteAnalysis.self, from: data)
    }

    func askOperationsAssistant(prompt: String, history: [AssistantConversationTurn], attachment: AssistantAttachment? = nil, leads: [Lead], tasks: [GeneralTask], user: CRMUser) async throws -> CRMAssistantResponse {
        struct SafeUser: Encodable { let id: String; let name: String; let role: String }
        struct SafeTask: Encodable { let id: String; let title: String; let completed: Bool; let dueDate: String?; let priority: String; let category: String; let assignedTo: [String] }
        struct SafeJobTask: Encodable { let id: String; let title: String; let completed: Bool; let dueDate: String? }
        struct SafeNote: Encodable { let content: String; let date: String }
        struct SafeLead: Encodable {
            let id: String; let jobRef: String; let customerName: String; let address: String; let jobType: String; let stage: String
            let value: Double; let deposit: Double; let depositPaid: Bool; let balance: Double; let assignedTo: String; let surveyDate: String?; let surveyTime: String?
            let startDate: String?; let endDate: String?; let progress: Int; let tasks: [SafeJobTask]; let recentNotes: [SafeNote]
        }
        struct Payload: Encodable { let prompt: String; let history: [AssistantConversationTurn]; let attachment: AssistantAttachment?; let leads: [SafeLead]; let tasks: [SafeTask]; let user: SafeUser; let today: String }
        let safeLeads = leads.prefix(250).map { lead in
            SafeLead(id: lead.id, jobRef: lead.jobRef, customerName: lead.name, address: lead.address, jobType: lead.jobType,
                     stage: lead.stage.rawValue, value: lead.value, deposit: lead.deposit, depositPaid: lead.depositPaid, balance: lead.balance, assignedTo: lead.assignedTo,
                     surveyDate: lead.surveyDate, surveyTime: lead.surveyTime, startDate: lead.startDate, endDate: lead.endDate,
                     progress: lead.progress,
                     tasks: lead.tasks.map { SafeJobTask(id: $0.id, title: $0.title, completed: $0.completed, dueDate: $0.dueDate) },
                     recentNotes: lead.notes.suffix(3).map { SafeNote(content: $0.content, date: $0.date) })
        }
        let safeTasks = tasks.prefix(250).map { SafeTask(id: $0.id, title: $0.title, completed: $0.completed, dueDate: $0.dueDate, priority: $0.priority, category: $0.category, assignedTo: $0.assignedTo) }
        var call = URLRequest(url: functionsURL.appending(path: "operations-assistant"))
        call.httpMethod = "POST"
        call.timeoutInterval = attachment == nil ? 35 : 60
        call.httpBody = try JSONEncoder().encode(Payload(prompt: prompt, history: Array(history.suffix(12)), attachment: attachment, leads: safeLeads, tasks: safeTasks, user: .init(id: user.id, name: user.name, role: user.role), today: Self.today))
        call.setValue(anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: call)
        return try decoder.decode(CRMAssistantResponse.self, from: data)
    }

    func gmailAuthorizationURL() async throws -> URL {
        struct Reply: Decodable { let authorizationURL: String; enum CodingKeys: String, CodingKey { case authorizationURL = "authorization_url" } }
        var call = URLRequest(url: functionsURL.appending(path: "gmail-oauth-start")); call.httpMethod = "POST"
        call.setValue(anonKey, forHTTPHeaderField: "apikey"); call.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await authenticatedData(for: call)
        guard let url = URL(string: try decoder.decode(Reply.self, from: data).authorizationURL) else { throw URLError(.badURL) }; return url
    }
    func gmailConnectionStatus() async throws -> GmailConnectionStatus {
        var call = URLRequest(url: functionsURL.appending(path: "gmail-status")); call.httpMethod = "GET"; call.timeoutInterval = 12
        call.setValue(anonKey, forHTTPHeaderField: "apikey"); call.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await authenticatedData(for: call)
        return try decoder.decode(GmailConnectionStatus.self, from: data)
    }
    func scanGmail() async throws -> Int {
        struct Reply: Decodable { let tasksCreated: Int; enum CodingKeys: String, CodingKey { case tasksCreated = "tasks_created" } }
        var call = URLRequest(url: functionsURL.appending(path: "gmail-scan")); call.httpMethod = "POST"
        call.timeoutInterval = 75
        call.setValue(anonKey, forHTTPHeaderField: "apikey"); call.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await authenticatedData(for: call); return try decoder.decode(Reply.self, from: data).tasksCreated
    }

    func generateQuoteDraft(lead: Lead, survey: RoofSurvey?, brief: String, photos: [AssistantAttachment]) async throws -> GeneratedQuoteDraft {
        struct QuoteContext: Encodable {
            let customerName: String
            let address: String
            let jobType: String
            let currentJobValue: Double
            let brief: String
            let notes: [String]
            let materials: [String]
            let survey: RoofSurvey?
            let photos: [AssistantAttachment]
        }
        var call = URLRequest(url: functionsURL.appending(path: "generate-quote"))
        call.httpMethod = "POST"
        call.timeoutInterval = 40
        call.httpBody = try JSONEncoder().encode(QuoteContext(
            customerName: lead.name,
            address: lead.address,
            jobType: lead.jobType,
            currentJobValue: lead.value,
            brief: brief,
            notes: lead.notes.suffix(8).map(\.content),
            materials: lead.materials.map { "\($0.name): \($0.quantity.formatted()) \($0.unit)" },
            survey: survey,
            photos: Array(photos.prefix(4))
        ))
        call.setValue(anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: call)
        return try decoder.decode(GeneratedQuoteDraft.self, from: data)
    }

    func signInWithPassword(email: String, password: String) async throws -> CRMUser {
        var request = URLRequest(url: authURL.appending(path: "token").appending(queryItems: [.init(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = try await executeAuth(request)
        persist(session)
        return try await fetchAuthenticatedProfile(userID: session.user.id)
    }

    func createWorkerInvitation(email: String, role: String) async throws -> WorkerInvitation {
        guard let token = KeychainStore.get("supabaseAccessToken") else { throw SupabaseSessionExpired() }
        var call = URLRequest(url: functionsURL.appending(path: "worker-invite"))
        call.httpMethod = "POST"
        call.timeoutInterval = 20
        call.httpBody = try JSONSerialization.data(withJSONObject: ["action": "create", "email": email, "role": role])
        call.setValue(anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: call)
        return try decoder.decode(WorkerInvitation.self, from: data)
    }

    func createSecureUser(name: String, email: String, password: String, role: String, dayRate: Double?, cisRate: Int) async throws {
        guard let token = KeychainStore.get("supabaseAccessToken") else { throw SupabaseSessionExpired() }
        var payload: [String: Any] = ["action": "create_user", "name": name, "email": email, "password": password, "role": role, "cis_rate": cisRate]
        if let dayRate { payload["day_rate"] = dayRate }
        var call = URLRequest(url: functionsURL.appending(path: "worker-invite")); call.httpMethod = "POST"; call.timeoutInterval = 20
        call.httpBody = try JSONSerialization.data(withJSONObject: payload)
        call.setValue(anonKey, forHTTPHeaderField: "apikey"); call.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await authenticatedData(for: call)
    }

    func acceptWorkerInvitation(token: String, details: WorkerSignupDetails) async throws -> String {
        var payload: [String: Any] = [
            "action": "accept", "token": token, "name": details.name, "password": details.password,
            "cis_rate": details.cisRate, "utr_number": details.utrNumber, "bank_name": details.bankName,
            "bank_account_number": details.bankAccountNumber, "bank_sort_code": details.bankSortCode
        ]
        if let dayRate = details.dayRate { payload["day_rate"] = dayRate }
        var call = URLRequest(url: functionsURL.appending(path: "worker-invite"))
        call.httpMethod = "POST"
        call.timeoutInterval = 25
        call.httpBody = try JSONSerialization.data(withJSONObject: payload)
        call.setValue(anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: call)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= http.statusCode else { throw SupabaseHTTPError(statusCode: http.statusCode, message: Self.safeServerMessage(from: data)) }
        struct Result: Decodable { let email: String }
        return try decoder.decode(Result.self, from: data).email
    }

    func restoreAuthenticatedSession() async throws -> CRMUser? {
        guard let refreshToken = KeychainStore.get("supabaseRefreshToken") else { return nil }
        var request = URLRequest(url: authURL.appending(path: "token").appending(queryItems: [.init(name: "grant_type", value: "refresh_token")]))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = try await executeAuth(request)
        persist(session)
        return try await fetchAuthenticatedProfile(userID: session.user.id)
    }

    func validateAuthenticatedProfile() async throws -> CRMUser? {
        guard KeychainStore.get("supabaseAccessToken") != nil else { return nil }
        guard let userID = KeychainStore.get("supabaseAuthUserID") else { throw SupabaseSessionExpired() }
        return try await fetchAuthenticatedProfile(userID: userID)
    }

    func signOutAuthenticatedSession() async {
        if let token = KeychainStore.get("supabaseAccessToken") {
            // Revoke only this device's refresh token. The default Supabase logout
            // scope is global, which would also sign the same user out on their
            // iPhone, Mac and any other active device.
            var request = URLRequest(url: authURL.appending(path: "logout").appending(queryItems: [.init(name: "scope", value: "local")]))
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.remove("supabaseAccessToken")
        KeychainStore.remove("supabaseRefreshToken")
        KeychainStore.remove("supabaseAuthUserID")
        KeychainStore.remove("supabaseOrganisationID")
    }

    func registerNativePushDevice(token: String, platform: String, environment: String, bundleID: String) async throws {
        guard let userID = KeychainStore.get("supabaseAuthUserID") else { throw SupabaseSessionExpired() }
        let body = try JSONSerialization.data(withJSONObject: [
            "user_id": userID, "device_token": token, "platform": platform, "environment": environment,
            "bundle_id": bundleID, "active": true, "last_seen_at": ISO8601DateFormatter().string(from: Date())
        ])
        var deviceRequest = try request(path: "native_push_devices", method: "POST", query: [.init(name: "on_conflict", value: "device_token")], body: body)
        deviceRequest.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await authenticatedData(for: deviceRequest)
    }

    func unregisterNativePushDevice(token: String) async throws {
        var deviceRequest = try request(path: "native_push_devices", method: "DELETE", query: [.init(name: "device_token", value: "eq.\(token)")])
        deviceRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await authenticatedData(for: deviceRequest)
        UserDefaults.standard.removeObject(forKey: "nativePushDeviceToken")
    }

    func sendPushEvent(_ event: String, name: String = "", detail: String = "", recordID: String = "", userIDs: [String] = []) async throws -> Int {
        guard let token = KeychainStore.get("supabaseAccessToken") else { throw SupabaseSessionExpired() }
        var call = URLRequest(url: functionsURL.appending(path: "send-push"))
        call.httpMethod = "POST"
        call.timeoutInterval = 20
        call.httpBody = try JSONSerialization.data(withJSONObject: ["event": event, "name": name, "detail": detail, "record_id": recordID, "user_ids": userIDs])
        call.setValue(anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: call)
        struct Delivery: Decodable { let nativeSent: Int; let nativeFailed: Int; enum CodingKeys: String, CodingKey { case nativeSent = "native_sent"; case nativeFailed = "native_failed" } }
        let delivery = try decoder.decode(Delivery.self, from: data)
        if delivery.nativeSent == 0, delivery.nativeFailed > 0 { throw SupabaseHTTPError(statusCode: 503, message: "Apple Push is not fully configured yet.") }
        return delivery.nativeSent
    }

    func updateAuthenticatedProfile(_ user: CRMUser) async throws {
        let payload: [String: Any?] = [
            "name": user.name, "username": user.username,
            "day_rate": user.dayRate, "cis_rate": user.cisRate, "utr_number": user.utrNumber,
            "bank_name": user.bankName, "bank_account_number": user.bankAccountNumber,
            "bank_sort_code": user.bankSortCode
        ]
        let body = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        var profileRequest = try request(path: "profiles", method: "PATCH", query: [.init(name: "id", value: "eq.\(user.id)")], body: body)
        profileRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await authenticatedData(for: profileRequest)
    }

    func updateAuthenticatedPassword(_ password: String) async throws {
        guard let token = KeychainStore.get("supabaseAccessToken") else { throw URLError(.userAuthenticationRequired) }
        var passwordRequest = URLRequest(url: authURL.appending(path: "user"))
        passwordRequest.httpMethod = "PUT"
        passwordRequest.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        passwordRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        passwordRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        passwordRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await authenticatedData(for: passwordRequest)
    }

    private func executeAuth(_ request: URLRequest) async throws -> AuthSession {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= http.statusCode else { throw SupabaseSessionExpired() }
        return try decoder.decode(AuthSession.self, from: data)
    }

    private func persist(_ session: AuthSession) {
        KeychainStore.set(session.accessToken, for: "supabaseAccessToken")
        KeychainStore.set(session.refreshToken, for: "supabaseRefreshToken")
        KeychainStore.set(session.user.id, for: "supabaseAuthUserID")
    }

    private func fetchAuthenticatedProfile(userID: String) async throws -> CRMUser {
        let rows: [AuthProfile] = try await execute(request(path: "profiles", query: [.init(name: "id", value: "eq.\(userID)"), .init(name: "select", value: "*")]), as: [AuthProfile].self)
        guard let profile = rows.first, profile.active != false else { throw SupabaseSessionExpired() }
        if let organisationID = profile.organisationID { KeychainStore.set(organisationID, for: "supabaseOrganisationID") }
        return profileUser(profile)
    }

    private func profileUser(_ profile: AuthProfile) -> CRMUser { CRMUser(id: profile.id, name: profile.name, username: profile.email ?? profile.username ?? "", passwordHash: "", role: profile.role, dayRate: profile.dayRate, cisRate: profile.cisRate, utrNumber: profile.utrNumber, bankName: profile.bankName, bankAccountNumber: profile.bankAccountNumber, bankSortCode: profile.bankSortCode, organizationID: profile.organisationID) }

    private func fetch<T: Decodable>(_ table: String, as type: T.Type) async throws -> [T] {
        try await execute(request(path: table, query: [.init(name: "select", value: "*")]), as: [T].self)
    }

    func insert<T: Codable>(_ value: T, into table: String) async throws {
        let _: [T] = try await execute(request(path: table, method: "POST", body: try JSONEncoder().encode(value)), as: [T].self)
    }

    func update<T: Codable>(_ value: T, in table: String, id: String) async throws {
        let _: [T] = try await execute(request(path: table, method: "PATCH", query: [.init(name: "id", value: "eq.\(id)")], body: try JSONEncoder().encode(value)), as: [T].self)
    }

    func delete(from table: String, id: String) async throws {
        let request = try request(path: table, method: "DELETE", query: [.init(name: "id", value: "eq.\(id)")])
        let (data, _) = try await authenticatedData(for: request)
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [Any], !rows.isEmpty else { throw SupabaseWriteConflict() }
    }

    func insertLead(_ lead: Lead) async throws { try await insert(lead, into: "leads") }
    func updateLead(_ lead: Lead, expectedUpdatedAt: String? = nil) async throws {
        let query = SupabaseWriteCondition.query(id: lead.id, expectedUpdatedAt: expectedUpdatedAt)
        let rows: [Lead] = try await execute(request(path: "leads", method: "PATCH", query: query, body: try JSONEncoder().encode(lead)), as: [Lead].self)
        guard !SupabaseWriteCondition.isConflict(returnedRowCount: rows.count) else { throw SupabaseWriteConflict() }
    }

    /// Uploads customer data to a private Storage bucket. Lead JSON stores this
    /// stable locator rather than a public or expiring signed URL.
    func uploadAttachment(data: Data, filename: String, contentType: String, leadID: String) async throws -> String {
        let cleanName = filename.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let organisationID = KeychainStore.get("supabaseOrganisationID") ?? "legacy"
        let path = "\(organisationID)/leads/\(leadID)/\(UUID().uuidString)-\(cleanName.isEmpty ? "attachment" : cleanName)"
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        var upload = URLRequest(url: storageURL.appending(path: "object/crm-attachments/\(encodedPath)"))
        upload.httpMethod = "POST"
        upload.httpBody = data
        upload.setValue(anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        upload.setValue(contentType, forHTTPHeaderField: "Content-Type")
        upload.setValue("false", forHTTPHeaderField: "x-upsert")
        _ = try await authenticatedData(for: upload)
        return "storage://crm-attachments/\(path)"
    }

    func signedAttachmentURL(for locator: String, expiresIn: Int = 3600) async throws -> URL {
        guard let value = parseStorageLocator(locator) else {
            guard let direct = URL(string: locator) else { throw URLError(.badURL) }
            return direct
        }
        let encodedPath = value.path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        var sign = URLRequest(url: storageURL.appending(path: "object/sign/\(value.bucket)/\(encodedPath)"))
        sign.httpMethod = "POST"
        sign.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": expiresIn])
        sign.setValue(anonKey, forHTTPHeaderField: "apikey")
        sign.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        sign.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await authenticatedData(for: sign)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = (object["signedURL"] ?? object["signedUrl"]) as? String else { throw URLError(.badServerResponse) }
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        guard let resolved = URL(string: raw, relativeTo: storageURL)?.absoluteURL else { throw URLError(.badURL) }
        return resolved
    }

    func deleteAttachment(locator: String) async throws {
        guard let value = parseStorageLocator(locator) else { return }
        let encodedPath = value.path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        var request = URLRequest(url: storageURL.appending(path: "object/\(value.bucket)/\(encodedPath)"))
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(KeychainStore.get("supabaseAccessToken") ?? anonKey)", forHTTPHeaderField: "Authorization")
        _ = try await authenticatedData(for: request)
    }

    private func parseStorageLocator(_ locator: String) -> (bucket: String, path: String)? {
        guard locator.hasPrefix("storage://"), let url = URL(string: locator), let bucket = url.host else { return nil }
        return (bucket, String(url.path.drop(while: { $0 == "/" })))
    }

    func updateStage(leadID: String, stage: LeadStage) async throws -> Lead {
        let payload = try JSONSerialization.data(withJSONObject: ["stage": stage.rawValue, "updated_at": Self.today])
        let response: [Lead] = try await execute(request(path: "leads", method: "PATCH", query: [.init(name: "id", value: "eq.\(leadID)")], body: payload), as: [Lead].self)
        guard let lead = response.first else { throw URLError(.cannotParseResponse) }
        return lead
    }

    static var now: String { ISO8601DateFormatter().string(from: .now) }
    static var today: String { localDay(for: .now) }
    nonisolated static func localDay(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func date(from raw: String) -> Date? {
        if let value = ISO8601DateFormatter().date(from: raw) { return value }
        return DateFormatter.isoDay.date(from: String(raw.prefix(10)))
    }
}

struct SupabaseWriteConflict: LocalizedError {
    var errorDescription: String? { "This record was changed on another device." }
}

struct SupabaseSessionExpired: LocalizedError {
    var errorDescription: String? { "Your secure session has expired." }
}

struct SupabaseHTTPError: LocalizedError {
    let statusCode: Int
    var message: String? = nil
    var errorDescription: String? { message.map { "The server returned HTTP \(statusCode): \($0)" } ?? "The server returned HTTP \(statusCode)." }
}

enum SupabaseWriteCondition {
    nonisolated static func query(id: String, expectedUpdatedAt: String?) -> [URLQueryItem] {
        var result = [URLQueryItem(name: "id", value: "eq.\(id)")]
        if let expectedUpdatedAt, !expectedUpdatedAt.isEmpty {
            result.append(.init(name: "updated_at", value: "eq.\(expectedUpdatedAt)"))
        }
        return result
    }

    nonisolated static func isConflict(returnedRowCount: Int) -> Bool { returnedRowCount == 0 }
}

struct MOTVehicleLookup: Decodable {
    let registration: String
    let make: String
    let model: String
    let fuelType: String
    let colour: String
    let firstUsedDate: String
    let motExpiryDate: String
    let odometerValue: String
    let odometerUnit: String
    let motTestCount: Int
}

private struct MOTLookupError: Decodable { let error: String }
private struct MOTLookupFailure: LocalizedError { let message: String; var errorDescription: String? { message } }

private struct AuthSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token"; case user }
}

private struct AuthUser: Decodable { let id: String }

private struct AuthProfile: Decodable {
    let id: String
    let name: String
    let email: String?
    let username: String?
    let role: String
    let active: Bool?
    let dayRate: Double?
    let cisRate: Int?
    let utrNumber: String?
    let bankName: String?
    let bankAccountNumber: String?
    let bankSortCode: String?
    let organisationID: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, username, role, active
        case dayRate = "day_rate"; case cisRate = "cis_rate"; case utrNumber = "utr_number"
        case bankName = "bank_name"; case bankAccountNumber = "bank_account_number"; case bankSortCode = "bank_sort_code"
        case organisationID = "organisation_id"
    }
}

private extension DateFormatter {
    static let isoDay: DateFormatter = { let value = DateFormatter(); value.calendar = Calendar(identifier: .iso8601); value.locale = Locale(identifier: "en_US_POSIX"); value.dateFormat = "yyyy-MM-dd"; return value }()
}
