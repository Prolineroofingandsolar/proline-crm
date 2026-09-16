import Foundation

enum CRMReportExport {
    static func csv(leads: [Lead]) -> String {
        let header = ["Job reference", "Customer", "Phone", "Email", "Address", "Job type", "Stage", "Value", "Deposit", "Deposit paid", "Balance", "Source", "Owner", "Survey date", "Start date", "End date"]
        let rows = leads.sorted { $0.jobRef.localizedStandardCompare($1.jobRef) == .orderedAscending }.map { lead in
            [lead.jobRef, lead.name, lead.phone, lead.email, lead.address, lead.jobType, lead.stage.displayName, decimal(lead.value), decimal(lead.deposit), lead.depositPaid ? "Yes" : "No", decimal(lead.balance), lead.source, lead.assignedTo, lead.surveyDate ?? "", lead.startDate ?? "", lead.endDate ?? ""]
        }
        return ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }
    private static func decimal(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum LeadStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case newLead = "New Lead"
    case surveyBooked = "Survey Booked"
    case quotePreparing = "Quote Preparing"
    case quoteSent = "Quote Sent"
    case won = "Won"
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case waitingForPayment = "Waiting for Payment"
    case paid = "Paid"
    case lost = "Lost"
    var id: String { rawValue }
    var displayName: String { self == .newLead ? "New Enquiry" : rawValue }
}

struct CRMSubtask: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var completed: Bool
}

struct CRMTask: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var completed: Bool
    var completedDate: String?
    var dueDate: String?
    var isTemplate: Bool?
    var priority: String? = nil
    var notes: String? = nil
    var subtasks: [CRMSubtask]? = nil
    enum CodingKeys: String, CodingKey { case id, title, completed, priority, notes, subtasks, dueDate = "dueDate", isTemplate = "isTemplate", completedDate = "completedDate" }
}

struct CRMPhoto: Codable, Identifiable, Hashable, Sendable { let id: String; var url: String; var category: String; var date: String; var caption: String? }
struct CRMNote: Codable, Identifiable, Hashable, Sendable { let id: String; var content: String; var date: String; var author: String }

enum JobTaskSuggestionAction: String, Codable, Sendable { case complete, add }
struct JobTaskSuggestion: Codable, Identifiable, Hashable, Sendable {
    var id: String; var action: JobTaskSuggestionAction; var taskID: String?; var title: String; var reason: String; var dueDate: String?
    enum CodingKeys: String, CodingKey { case id, action, title, reason; case taskID = "task_id"; case dueDate = "due_date" }
}
struct JobMaterialSuggestion: Codable, Identifiable, Hashable, Sendable {
    var id: String; var name: String; var quantity: Double; var unit: String; var reason: String
}
struct JobNoteAnalysis: Codable, Sendable {
    var summary: String; var suggestions: [JobTaskSuggestion]; var materials: [JobMaterialSuggestion]?; var analysisMode: String?
    enum CodingKeys: String, CodingKey { case summary, suggestions, materials; case analysisMode = "analysis_mode" }
}

enum CRMAssistantActionKind: String, Codable, Sendable {
    case addJobTask = "add_job_task", completeJobTask = "complete_job_task", createGeneralTask = "create_general_task"
    case moveJobStage = "move_job_stage", scheduleSurvey = "schedule_survey", scheduleJob = "schedule_job", draftEmail = "draft_email"
    case recordDeposit = "record_deposit", recordFinalPayment = "record_final_payment"
    case setJobValue = "set_job_value", setDepositAmount = "set_deposit_amount", setBalance = "set_balance"
    case addJobNote = "add_job_note", addMaterial = "add_material"
}
struct AssistantConversationTurn: Codable, Sendable { let role: String; let text: String }
struct AssistantAttachment: Codable, Sendable {
    let filename: String
    let mimeType: String
    let data: Data
    enum CodingKeys: String, CodingKey { case filename, data; case mimeType = "mime_type" }
}
struct CRMAssistantAction: Codable, Identifiable, Hashable, Sendable {
    var id: String; var kind: CRMAssistantActionKind; var title: String; var explanation: String
    var leadID: String?; var taskID: String?; var value: String?; var secondaryValue: String?; var quantity: Double?; var unit: String?; var requiresApproval: Bool
    enum CodingKeys: String, CodingKey { case id, kind, title, explanation, value, quantity, unit; case leadID = "lead_id"; case taskID = "task_id"; case secondaryValue = "secondary_value"; case requiresApproval = "requires_approval" }
}
struct CRMAssistantResponse: Codable, Sendable {
    var message: String; var leadIDs: [String]; var actions: [CRMAssistantAction]
    enum CodingKeys: String, CodingKey { case message, actions; case leadIDs = "lead_ids" }
}
struct AIAuditEntry: Codable, Identifiable, Sendable {
    let id: String; let userID: String; let userName: String; let actionKind: String; let actionTitle: String
    let leadID: String?; let outcome: String; let createdAt: String
}
struct CRMFile: Codable, Identifiable, Hashable, Sendable { let id: String; var name: String; var type: String; var size: String?; var date: String; var url: String? }
struct CRMMaterial: Codable, Identifiable, Hashable, Sendable { let id: String; var name: String; var quantity: Double; var unit: String; var cost: Double?; var supplier: String?; var ordered: Bool; var delivered: Bool }

enum SurveyStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned, inProgress = "in_progress", completed
    var id: String { rawValue }
    var displayName: String { self == .inProgress ? "In Progress" : rawValue.capitalized }
}

struct SurveyMeasurement: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var length: Double
    var width: Double
    var unit: String
    var area: Double { length * width }
}

struct RoofSurvey: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var leadID: String
    var status: SurveyStatus
    var surveyorID: String?
    var scheduledAt: String?
    var completedAt: String?
    var roofType: String
    var covering: String
    var storeys: Int
    var pitchDegrees: Double?
    var accessNotes: String
    var scaffoldRequired: Bool
    var asbestosSuspected: Bool
    var hazards: [String]
    var measurements: [SurveyMeasurement]
    var findings: String
    var recommendations: String
    var createdAt: String
    var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, status, hazards, measurements, findings, recommendations
        case leadID = "lead_id"; case surveyorID = "surveyor_id"; case scheduledAt = "scheduled_at"; case completedAt = "completed_at"
        case roofType = "roof_type"; case covering, storeys; case pitchDegrees = "pitch_degrees"; case accessNotes = "access_notes"
        case scaffoldRequired = "scaffold_required"; case asbestosSuspected = "asbestos_suspected"
        case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

enum QuoteStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft, sent, accepted, declined, expired
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct QuoteLineItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var description: String
    var category: String
    var quantity: Double
    var unit: String
    var unitPrice: Double
    var total: Double { quantity * unitPrice }
    enum CodingKeys: String, CodingKey { case id, description, category, quantity, unit; case unitPrice = "unit_price" }
}

struct GeneratedQuoteScopeItem: Codable, Hashable, Sendable {
    var heading: String
    var details: String
}

struct GeneratedQuoteDraft: Codable, Sendable {
    var introduction: String
    var scopeItems: [GeneratedQuoteScopeItem]
    var guarantee: String
    var terms: String
    var recommendedPrice: Double?
    var priceRangeLow: Double?
    var priceRangeHigh: Double?
    var pricingBasis: String?
    enum CodingKeys: String, CodingKey {
        case introduction, guarantee, terms
        case scopeItems = "scope_items"
        case recommendedPrice = "recommended_price"
        case priceRangeLow = "price_range_low"
        case priceRangeHigh = "price_range_high"
        case pricingBasis = "pricing_basis"
    }
}

struct CRMQuote: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var leadID: String
    var quoteNumber: String
    var status: QuoteStatus
    var lineItems: [QuoteLineItem]
    var vatRate: Double
    var discount: Double
    var validUntil: String?
    var terms: String
    var customerMessage: String
    var sentAt: String?
    var acceptedAt: String?
    var createdAt: String
    var updatedAt: String
    var subtotal: Double { lineItems.reduce(0) { $0 + $1.total } }
    var vat: Double { max(0, subtotal - discount) * vatRate / 100 }
    var total: Double { max(0, subtotal - discount) + vat }
    enum CodingKeys: String, CodingKey {
        case id, status, discount, terms
        case leadID = "lead_id"; case quoteNumber = "quote_number"; case lineItems = "line_items"; case vatRate = "vat_rate"
        case validUntil = "valid_until"; case customerMessage = "customer_message"; case sentAt = "sent_at"; case acceptedAt = "accepted_at"
        case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

struct Lead: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var jobRef: String
    var name: String
    var phone: String
    var email: String
    var address: String
    var jobType: String
    var stage: LeadStage
    var value: Double
    var deposit: Double
    var depositPaid: Bool
    var balance: Double
    var source: String
    var assignedTo: String
    var surveyDate: String?
    var surveyTime: String?
    var startDate: String?
    var endDate: String?
    var completedDate: String?
    var paidDate: String?
    var progress: Int
    var tasks: [CRMTask]
    var photos: [CRMPhoto]
    var notes: [CRMNote]
    var files: [CRMFile]
    var materials: [CRMMaterial]
    var wonDate: String?
    var myBuilderURL: String?
    var reviewRequestSent: Bool?
    var lat: Double?
    var lng: Double?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, address, value, deposit, balance, source, progress, tasks, stage, photos, notes, files, materials, lat, lng
        case jobRef = "job_ref"; case jobType = "job_type"; case depositPaid = "deposit_paid"
        case assignedTo = "assigned_to"; case surveyDate = "survey_date"; case surveyTime = "survey_time"
        case startDate = "start_date"; case endDate = "end_date"; case completedDate = "completed_date"
        case paidDate = "paid_date"; case createdAt = "created_at"; case updatedAt = "updated_at"
        case wonDate = "won_date"; case myBuilderURL = "mybuilder_url"; case reviewRequestSent = "review_request_sent"
    }
}

struct CRMUser: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var username: String
    var passwordHash: String
    var role: String
    var dayRate: Double?
    var cisRate: Int?
    var utrNumber: String?
    var bankName: String?
    var bankAccountNumber: String?
    var bankSortCode: String?
    var organizationID: String? = nil
    enum CodingKeys: String, CodingKey {
        case id, name, username, role
        case passwordHash = "password_hash"
        case dayRate = "day_rate"; case cisRate = "cis_rate"; case utrNumber = "utr_number"
        case bankName = "bank_name"; case bankAccountNumber = "bank_account_number"; case bankSortCode = "bank_sort_code"
        case organizationID = "organisation_id"
    }
}

struct WorkerInvitation: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let link: String
    let code: String
    let expiresAt: String
    enum CodingKeys: String, CodingKey { case id, email, link, code; case expiresAt = "expires_at" }
}

struct WorkerSignupDetails: Sendable {
    var name: String
    var password: String
    var dayRate: Double?
    var cisRate: Int
    var utrNumber: String
    var bankName: String
    var bankAccountNumber: String
    var bankSortCode: String
}

struct CRMContact: Codable, Identifiable, Hashable, Sendable {
    let id: String; var name: String; var phone: String; var email: String; var address: String; var createdAt: String
    enum CodingKeys: String, CodingKey { case id, name, phone, email, address; case createdAt = "created_at" }
}

struct GeneralTask: Codable, Identifiable, Hashable, Sendable {
    let id: String; var title: String; var completed: Bool; var completedDate: String?; var dueDate: String?; var priority: String; var category: String; var notes: String?; var createdAt: String; var assignedTo: [String]
    enum CodingKeys: String, CodingKey { case id, title, completed, priority, category, notes; case completedDate = "completed_date"; case dueDate = "due_date"; case createdAt = "created_at"; case assignedTo = "assigned_to" }
}

struct TeamMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var authorID: String
    var authorName: String
    var body: String
    var day: String?
    var leadID: String?
    var createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, body, day
        case authorID = "author_id"; case authorName = "author_name"
        case leadID = "lead_id"; case createdAt = "created_at"
    }
}

struct TeamDayPlan: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var day: String
    var title: String
    var notes: String
    var startTime: String?
    var endTime: String?
    var leadID: String?
    var assignedTo: [String]
    var createdBy: String
    var createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, day, title, notes
        case startTime = "start_time"; case endTime = "end_time"; case leadID = "lead_id"
        case assignedTo = "assigned_to"; case createdBy = "created_by"; case createdAt = "created_at"
    }
}

struct TimesheetEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String; var userID: String; var leadID: String; var date: String; var type: String; var amount: Double; var createdAt: String
    enum CodingKeys: String, CodingKey { case id, date, type, amount; case userID = "user_id"; case leadID = "lead_id"; case createdAt = "created_at" }
}

enum PaymentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case due, submitted, scheduled, paid
    var id: String { rawValue }
    var displayName: String { switch self { case .due: "Draft"; case .submitted: "Submitted"; case .scheduled: "Approved"; case .paid: "Paid" } }
}

enum DepositPlan: String, CaseIterable, Identifiable, Sendable {
    case none = "No deposit"
    case ten = "10%"
    case twenty = "20%"
    case twentyFive = "25%"
    case thirty = "30%"
    case custom = "Custom"

    var id: String { rawValue }
    var rate: Double? {
        switch self {
        case .none: 0
        case .ten: 0.10
        case .twenty: 0.20
        case .twentyFive: 0.25
        case .thirty: 0.30
        case .custom: nil
        }
    }
    func amount(for total: Double) -> Double? { rate.map { max(0, total * $0) } }
    static func matching(total: Double, deposit: Double) -> DepositPlan {
        guard total > 0 else { return deposit == 0 ? .thirty : .custom }
        return [.none, .ten, .twenty, .twentyFive, .thirty].first {
            abs(($0.amount(for: total) ?? -1) - deposit) < 0.01
        } ?? .custom
    }
}

struct PaymentRun: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var userID: String
    var weekStart: String
    var status: PaymentStatus
    var paidDate: String?
    var notes: String?
    var createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userID = "user_id"; case weekStart = "week_start"; case paidDate = "paid_date"; case createdAt = "created_at"
    }
}

struct WorkerPayment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var userID: String
    var amount: Double
    var date: String
    var notes: String?
    var createdAt: String
    var monzoTransactionID: String?
    enum CodingKeys: String, CodingKey {
        case id, amount, date, notes
        case userID = "user_id"; case createdAt = "created_at"; case monzoTransactionID = "monzo_transaction_id"
    }
}
