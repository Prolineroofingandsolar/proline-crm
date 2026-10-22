import Foundation

/// Talks to the user's self-hosted Paperclip server (https://paperclip.ing), which runs their AI agent
/// "company". On the Mac it is usually `http://localhost:3100`; from an iPhone it has to be the Mac's
/// LAN or Tailscale address, with a board API key because Paperclip then runs in authenticated mode.
enum PaperclipSettings {
    static let defaultURL = "http://localhost:3100"
    private static let urlKey = "paperclipURL"
    private static let companyKey = "paperclipCompanyID"
    private static let apiKeyKey = "paperclipBoardKey"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: urlKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultURL }
        set {
            var trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            UserDefaults.standard.set(trimmed, forKey: urlKey)
        }
    }
    static var companyID: String {
        get { UserDefaults.standard.string(forKey: companyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: companyKey) }
    }
    static var apiKey: String {
        get { KeychainStore.get(apiKeyKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { KeychainStore.remove(apiKeyKey) } else { KeychainStore.set(trimmed, for: apiKeyKey) }
        }
    }
}

struct PaperclipCompany: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct PaperclipAgent: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var role: String
    var title: String?
    var status: String
    var reportsTo: String?
    var budgetMonthlyCents: Double
    var spentMonthlyCents: Double
    var lastHeartbeatAt: String?

    var displayRole: String {
        if let title, !title.isEmpty { return title }
        return role.capitalized
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, role, title, status, reportsTo, budgetMonthlyCents, spentMonthlyCents, lastHeartbeatAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Agent"
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "general"
        title = try c.decodeIfPresent(String.self, forKey: .title)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "idle"
        reportsTo = try c.decodeIfPresent(String.self, forKey: .reportsTo)
        budgetMonthlyCents = (try? c.decodeIfPresent(Double.self, forKey: .budgetMonthlyCents)) ?? 0
        spentMonthlyCents = (try? c.decodeIfPresent(Double.self, forKey: .spentMonthlyCents)) ?? 0
        lastHeartbeatAt = try c.decodeIfPresent(String.self, forKey: .lastHeartbeatAt)
    }
}

struct PaperclipRun: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let agentId: String
    let status: String
    let issueId: String?
}

struct PaperclipActivity: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let actorType: String
    let actorId: String
    let action: String
    let entityType: String
    let entityId: String
    let agentId: String?
    let createdAt: String
    let detailTitle: String?

    private enum CodingKeys: String, CodingKey { case id, actorType, actorId, action, entityType, entityId, agentId, createdAt, details }
    private struct Details: Decodable { let title: String?; let identifier: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        actorType = try c.decodeIfPresent(String.self, forKey: .actorType) ?? "system"
        actorId = try c.decodeIfPresent(String.self, forKey: .actorId) ?? ""
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        entityType = try c.decodeIfPresent(String.self, forKey: .entityType) ?? ""
        entityId = try c.decodeIfPresent(String.self, forKey: .entityId) ?? ""
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        let details = try? c.decodeIfPresent(Details.self, forKey: .details)
        detailTitle = details?.title ?? details?.identifier
    }

    /// "You · paused · Lena", using agent names where we have them.
    func summary(names: [String: String]) -> String {
        let who: String =
            switch actorType {
            case "agent": names[actorId] ?? "An agent"
            case "user": "You"
            default: "Paperclip"
            }
        let verb = (action.split(separator: ".").last.map(String.init) ?? action).replacingOccurrences(of: "_", with: " ")
        let target =
            entityType == "agent"
            ? names[entityId] ?? "an agent"
            : detailTitle.map { "“\($0)”" } ?? entityType.replacingOccurrences(of: "_", with: " ")
        return "\(who) · \(verb) · \(target)"
    }
}

struct PaperclipIssue: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let identifier: String?
    let title: String
    let status: String
    let assigneeAgentId: String?
}

private struct PaperclipListWrapper<T: Decodable>: Decodable {
    let items: [T]?
    let issues: [T]?
    let data: [T]?
}

struct PaperclipError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Stateless HTTP client. Every Paperclip route used by the app lives here.
enum PaperclipService {
    static func companies() async throws -> [PaperclipCompany] {
        try await list("/api/companies")
    }
    static func agents(company: String) async throws -> [PaperclipAgent] {
        try await list("/api/companies/\(company)/agents").filter { (agent: PaperclipAgent) in agent.status != "terminated" }
    }
    static func liveRuns(company: String) async throws -> [PaperclipRun] {
        try await list("/api/companies/\(company)/live-runs")
    }
    static func activity(company: String) async throws -> [PaperclipActivity] {
        try await list("/api/companies/\(company)/activity?limit=60")
    }
    static func openIssues(company: String) async throws -> [PaperclipIssue] {
        try await list("/api/companies/\(company)/issues?status=backlog,todo,in_progress,in_review,blocked&limit=200")
    }

    static func pause(agent: String) async throws { try await send("POST", "/api/agents/\(agent)/pause", body: [String: String]()) }
    static func resume(agent: String) async throws { try await send("POST", "/api/agents/\(agent)/resume", body: [String: String]()) }
    static func wake(agent: String) async throws {
        try await send(
            "POST", "/api/agents/\(agent)/wakeup",
            body: ["source": "on_demand", "triggerDetail": "manual", "reason": "Woken from ProLine Virtual Office"])
    }
    static func assignTask(company: String, agent: String, title: String, details: String) async throws {
        var body = ["title": title, "assigneeAgentId": agent, "status": "todo"]
        if !details.isEmpty { body["description"] = details }
        try await send("POST", "/api/companies/\(company)/issues", body: body)
    }
    static func message(issue: String, text: String) async throws {
        try await send("POST", "/api/issues/\(issue)/comments", body: ["body": text])
    }

    // MARK: - Transport

    private static func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        let base = PaperclipSettings.baseURL
        guard let url = URL(string: base + path) else { throw PaperclipError(message: "The Paperclip address “\(base)” isn't valid.") }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let key = PaperclipSettings.apiKey
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PaperclipError(message: "Can't reach Paperclip at \(base). Is it running?")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 {
                throw PaperclipError(message: "Paperclip refused access. Add a board API key in Settings → Virtual Office.")
            }
            struct ErrorBody: Decodable { let error: String? }
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw PaperclipError(message: detail ?? "Paperclip returned \(status).")
        }
        return data
    }

    private static func send(_ method: String, _ path: String, body: [String: String]) async throws {
        _ = try await request(method, path, body: try JSONEncoder().encode(body))
    }

    /// Some Paperclip list routes return a bare array, others wrap it in an object.
    private static func list<T: Decodable>(_ path: String) async throws -> [T] {
        let data = try await request("GET", path)
        if let items = try? JSONDecoder().decode([T].self, from: data) { return items }
        if let wrapped = try? JSONDecoder().decode(PaperclipListWrapper<T>.self, from: data), let items = wrapped.items ?? wrapped.issues ?? wrapped.data {
            return items
        }
        throw PaperclipError(message: "Paperclip sent something ProLine didn't understand for \(path).")
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
