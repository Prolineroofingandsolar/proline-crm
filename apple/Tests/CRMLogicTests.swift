import XCTest

@testable import ProLine_CRM

final class CRMLogicTests: XCTestCase {
    func testDailyCompanyPlanRanksOverdueJobsBeforeQuotes() {
        var overdue = lead(id: "late", stage: .inProgress, value: 1000, balance: 500)
        overdue.endDate = "2026-09-05"
        let quote = lead(id: "quote", stage: .quoteSent, value: 1000, balance: 0)
        let result = OperationsInsights.answer(
            "Create my daily company plan. Rank what I need to do first, identify risks, and suggest the next best actions.",
            leads: [quote, overdue], tasks: [], today: "2026-09-06")
        XCTAssertTrue(result.text.contains("1. Recover overdue jobs"))
        XCTAssertTrue(result.text.contains("Follow up 1 sent quotes"))
        XCTAssertEqual(result.ids, ["late", "quote"])
    }

    func testDailyPlanWithNoRecordsDoesNotInventWork() {
        let result = OperationsInsights.answer("Create my daily company plan", leads: [], tasks: [], today: "2026-09-06")
        XCTAssertTrue(result.text.contains("No urgent items"))
        XCTAssertTrue(result.ids.isEmpty)
    }

    func testJobUpdateSuggestionPreservesQuantityAndDueDate() throws {
        let json =
            #"{"summary":"Front slope felted and battened.","suggestions":[{"id":"next-1","action":"add","task_id":null,"title":"Collect 12 packs of batten","reason":"Needed in the morning","due_date":"2026-09-06"}]}"#
            .data(using: .utf8)!
        let result = try JSONDecoder().decode(JobNoteAnalysis.self, from: json)
        XCTAssertEqual(result.summary, "Front slope felted and battened.")
        XCTAssertEqual(result.suggestions.first?.title, "Collect 12 packs of batten")
        XCTAssertEqual(result.suggestions.first?.dueDate, "2026-09-06")
        XCTAssertEqual(result.suggestions.first?.action, .add)
    }

    func testJobUpdateSuggestionAllowsNoStatedDueDate() throws {
        let json =
            #"{"summary":"Front slope prepared.","suggestions":[{"id":"next-2","action":"add","task_id":null,"title":"Photograph the front slope","reason":"Explicit next action"}]}"#
            .data(using: .utf8)!
        let result = try JSONDecoder().decode(JobNoteAnalysis.self, from: json)
        XCTAssertNil(result.suggestions.first?.dueDate)
    }

    func testJobUpdateDecodesProposedMaterial() throws {
        let json =
            #"{"summary":"Need more batten.","suggestions":[],"materials":[{"id":"mat-1","name":"Batten","quantity":12,"unit":"packs","reason":"Needed tomorrow"}],"analysis_mode":"ai"}"#
            .data(using: .utf8)!
        let result = try JSONDecoder().decode(JobNoteAnalysis.self, from: json)
        XCTAssertEqual(result.materials?.first?.name, "Batten")
        XCTAssertEqual(result.materials?.first?.quantity, 12)
        XCTAssertEqual(result.materials?.first?.unit, "packs")
        XCTAssertEqual(result.analysisMode, "ai")
    }

    func testJobTaskDecodesNestedSubtasksAndLegacyTasks() throws {
        let nested =
            #"{"id":"task-1","title":"Prepare roof","completed":false,"completedDate":null,"dueDate":"2026-09-08","isTemplate":false,"priority":"high","notes":"Front elevation first","subtasks":[{"id":"step-1","title":"Set scaffold","completed":true},{"id":"step-2","title":"Strip tiles","completed":false}]}"#
            .data(using: .utf8)!
        let task = try JSONDecoder().decode(CRMTask.self, from: nested)
        XCTAssertEqual(task.subtasks?.count, 2)
        XCTAssertEqual(task.subtasks?.first?.title, "Set scaffold")
        XCTAssertEqual(task.priority, "high")

        let legacy = #"{"id":"task-2","title":"Old task","completed":false}"#.data(using: .utf8)!
        let oldTask = try JSONDecoder().decode(CRMTask.self, from: legacy)
        XCTAssertNil(oldTask.subtasks)
        XCTAssertNil(oldTask.notes)
    }

    func testLegacyAndTimestampDatesParse() {
        XCTAssertNotNil(SupabaseService.date(from: "2026-08-09"))
        XCTAssertNotNil(SupabaseService.date(from: "2026-08-09T12:30:00Z"))
        XCTAssertNil(SupabaseService.date(from: "not-a-date"))
    }

    func testBusinessDayUsesLocalTimezoneAtBSTBoundary() {
        let instant = ISO8601DateFormatter().date(from: "2026-08-16T23:30:00Z")!
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(SupabaseService.localDay(for: instant, calendar: london), "2026-08-17")
        XCTAssertEqual(SupabaseService.localDay(for: instant, calendar: utc), "2026-08-16")
    }

    func testLeadStageDisplayNames() {
        XCTAssertEqual(LeadStage.newLead.displayName, "New Enquiry")
        XCTAssertEqual(LeadStage.quotePreparing.displayName, "Quote Preparing")
        XCTAssertEqual(LeadStage.waitingForPayment.displayName, "Waiting for Payment")
        XCTAssertEqual(Set(LeadStage.allCases).count, 11)
    }

    func testWidgetEmptySnapshotIsSafe() {
        XCTAssertEqual(WidgetSnapshot.empty.surveysToday, 0)
        XCTAssertEqual(WidgetSnapshot.empty.activeJobs, 0)
        XCTAssertEqual(WidgetSnapshot.empty.overdueJobs, 0)
    }

    func testStaffCannotAccessCompanyFinancialSections() {
        XCTAssertTrue(AppState.canAccess(.dashboard, role: "user"))
        XCTAssertTrue(AppState.canAccess(.jobs, role: "user"))
        XCTAssertTrue(AppState.canAccess(.tasks, role: "user"))
        XCTAssertTrue(AppState.canAccess(.timesheet, role: "casual"))
        XCTAssertFalse(AppState.canAccess(.pipeline, role: "user"))
        XCTAssertTrue(AppState.canAccess(.calendar, role: "user"))
        XCTAssertFalse(AppState.canAccess(.team, role: "user"))
        XCTAssertTrue(AppState.canAccess(.tools, role: "casual"))
        XCTAssertFalse(AppState.canAccess(.accounts, role: "user"))
        XCTAssertFalse(AppState.canAccess(.finance, role: "casual"))
        XCTAssertFalse(AppState.canAccess(.cis, role: "user"))
        XCTAssertFalse(AppState.canAccess(.reports, role: "user"))
        XCTAssertFalse(AppState.canAccess(.settings, role: nil))
        XCTAssertTrue(AppState.canAccess(.accounts, role: "admin"))
    }

    func testTeamPlanReminderOnlyTargetsAssignedWorker() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T06:00:00Z")!  // 07:00 BST
        let assigned = TeamDayPlan(
            id: "mine", day: "2026-08-24", title: "Start Oak Street roof", notes: "", startTime: "08:30", endTime: "16:30", leadID: nil,
            assignedTo: ["will conway"], createdBy: "admin", createdAt: "2026-08-23T12:00:00Z")
        let other = TeamDayPlan(
            id: "other", day: "2026-08-24", title: "Other job", notes: "", startTime: "09:00", endTime: nil, leadID: nil,
            assignedTo: ["Alex"], createdBy: "admin", createdAt: "2026-08-23T12:00:00Z")

        let reminders = TeamNotificationPolicy.plans(
            plans: [assigned, other], userName: "Will Conway", enabled: true, now: now, calendar: london)

        XCTAssertEqual(reminders.map(\.id), ["team-plan-mine"])
        XCTAssertEqual(london.component(.hour, from: reminders[0].date), 8)
        XCTAssertEqual(london.component(.minute, from: reminders[0].date), 0)
        XCTAssertTrue(
            TeamNotificationPolicy.plans(plans: [assigned], userName: "Will Conway", enabled: false, now: now, calendar: london).isEmpty)
    }

    func testNotificationsOnlyIncludeWorkAssignedToStaffMember() {
        let will = CRMUser(
            id: "will", name: "Will Conway", username: "will", role: "user", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
            bankAccountNumber: nil, bankSortCode: nil)
        let admin = CRMUser(
            id: "admin", name: "Admin", username: "admin", role: "admin", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
            bankAccountNumber: nil, bankSortCode: nil)
        var assignedLead = lead(id: "assigned", stage: .scheduled, value: 1, balance: 1)
        assignedLead.assignedTo = "will conway"
        var otherLead = lead(id: "other", stage: .scheduled, value: 1, balance: 1)
        otherLead.assignedTo = "Someone Else"
        let assignedTask = GeneralTask(
            id: "assigned", title: "Measure roof", completed: false, completedDate: nil, dueDate: "2026-08-25", priority: "high",
            category: "Survey", notes: nil, createdAt: "2026-08-24", assignedTo: ["will"])
        let unassignedTask = GeneralTask(
            id: "shared", title: "Order tiles", completed: false, completedDate: nil, dueDate: "2026-08-25", priority: "medium",
            category: "Materials", notes: nil, createdAt: "2026-08-24", assignedTo: [])

        XCTAssertTrue(NotificationScope.includes(assignedLead, for: will))
        XCTAssertFalse(NotificationScope.includes(otherLead, for: will))
        XCTAssertTrue(NotificationScope.includes(assignedTask, for: will))
        XCTAssertFalse(NotificationScope.includes(unassignedTask, for: will))
        XCTAssertTrue(NotificationScope.includes(otherLead, for: admin))
        XCTAssertTrue(NotificationScope.includes(unassignedTask, for: admin))
    }

    func testLeadOwnershipUsesExactCaseInsensitiveTeamName() {
        let will = CRMUser(
            id: "will", name: "Will Conway", username: "will", role: "user", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
            bankAccountNumber: nil, bankSortCode: nil)
        var lead = lead(id: "lead", stage: .newLead, value: 1, balance: 1)
        lead.assignedTo = "will conway"
        XCTAssertTrue(LeadOwnership.isAssigned(lead, to: will))
        lead.assignedTo = "Will"
        XCTAssertFalse(LeadOwnership.isAssigned(lead, to: will))
        lead.assignedTo = ""
        XCTAssertFalse(LeadOwnership.isAssigned(lead, to: will))
        XCTAssertFalse(LeadOwnership.isAssigned(lead, to: nil))
    }

    func testStaffLeadScopeOnlyIncludesExactlyAssignedCustomers() {
        let staff = CRMUser(
            id: "will", name: "Will Conway", username: "will", role: "user", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
            bankAccountNumber: nil, bankSortCode: nil)
        let admin = CRMUser(
            id: "admin", name: "Admin", username: "admin", role: "admin", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
            bankAccountNumber: nil, bankSortCode: nil)
        var mine = lead(id: "mine", stage: .scheduled, value: 1, balance: 1)
        mine.assignedTo = "will conway"
        var another = lead(id: "another", stage: .scheduled, value: 1, balance: 1)
        another.assignedTo = "Will"
        var unassigned = lead(id: "unassigned", stage: .scheduled, value: 1, balance: 1)
        unassigned.assignedTo = ""

        XCTAssertEqual(LeadAccessScope.visible([mine, another, unassigned], for: staff).map(\.id), ["mine"])
        XCTAssertEqual(LeadAccessScope.visible([mine, another, unassigned], for: admin).count, 3)
        XCTAssertTrue(LeadAccessScope.visible([mine], for: nil).isEmpty)
    }

    func testJobReferencesAreReadableAndDifferAcrossDevices() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = ISO8601DateFormatter().date(from: "2026-08-24T13:35:07Z")!
        let first = JobReference.make(date: date, calendar: calendar, nonce: "A1B2C3D4-E5F6")
        let second = JobReference.make(date: date, calendar: calendar, nonce: "F9E8D7C6-B5A4")

        XCTAssertEqual(first, "JOB-260824-143507-A1B2")
        XCTAssertEqual(second, "JOB-260824-143507-F9E8")
        XCTAssertNotEqual(first, second)
    }

    func testStaffOnlyReceiveTheirOwnPayrollRecords() {
        let staff = CRMUser(
            id: "will", name: "Will", username: "will", role: "user", dayRate: 200, cisRate: 20, utrNumber: "mine", bankName: "Mine",
            bankAccountNumber: "12345678", bankSortCode: "112233")
        let other = CRMUser(
            id: "alex", name: "Alex", username: "alex", role: "user", dayRate: 300, cisRate: 20, utrNumber: "private", bankName: "Other",
            bankAccountNumber: "87654321", bankSortCode: "332211")
        let mine = TimesheetEntry(
            id: "mine", userID: "will", leadID: "job", date: "2026-08-17", type: "full", amount: 200, createdAt: "2026-08-17")
        let theirs = TimesheetEntry(
            id: "theirs", userID: "alex", leadID: "job", date: "2026-08-17", type: "full", amount: 300, createdAt: "2026-08-17")
        let visibleUsers = UserAccessScope.visible([staff, other], for: staff)

        XCTAssertEqual(TimesheetAccessScope.visible([mine, theirs], for: staff).map(\.id), ["mine"])
        XCTAssertEqual(visibleUsers.first(where: { $0.id == "will" })?.bankAccountNumber, "12345678")
        XCTAssertNil(visibleUsers.first(where: { $0.id == "alex" })?.bankAccountNumber)
        XCTAssertNil(visibleUsers.first(where: { $0.id == "alex" })?.dayRate)
        XCTAssertEqual(
            TimesheetAccessScope.visible(
                [mine, theirs],
                for: CRMUser(
                    id: "admin", name: "Admin", username: "admin", role: "admin", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
                    bankAccountNumber: nil, bankSortCode: nil)
            ).count, 2)
    }

    func testPayrollWeekStartsOnMondayAcrossWholeWeek() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(PayrollPolicy.weekStartKey(for: "2026-08-17", calendar: london), "2026-08-17")
        XCTAssertEqual(PayrollPolicy.weekStartKey(for: "2026-08-23", calendar: london), "2026-08-17")
        XCTAssertEqual(PayrollPolicy.weekStartKey(for: "2026-08-24", calendar: london), "2026-08-24")
        XCTAssertNil(PayrollPolicy.weekStartKey(for: "not-a-date", calendar: london))
    }

    func testStaffSharedDataScopesExcludeCoworkerRecords() {
        let staff = CRMUser(
            id: "will", name: "Will", username: "will", role: "user", dayRate: nil, cisRate: nil, utrNumber: nil, bankName: nil,
            bankAccountNumber: nil, bankSortCode: nil)
        let mine = GeneralTask(
            id: "mine", title: "My task", completed: false, completedDate: nil, dueDate: nil, priority: "medium", category: "General",
            notes: nil, createdAt: "2026-08-24", assignedTo: ["will"])
        let theirs = GeneralTask(
            id: "theirs", title: "Their task", completed: false, completedDate: nil, dueDate: nil, priority: "medium", category: "General",
            notes: nil, createdAt: "2026-08-24", assignedTo: ["alex"])
        var assignedLead = lead(id: "lead", stage: .scheduled, value: 1, balance: 1)
        assignedLead.phone = "07123456789"
        assignedLead.email = "mine@example.com"
        let related = CRMContact(id: "related", name: "Customer", phone: "07123456789", email: "", address: "", createdAt: "2026-08-24")
        let unrelated = CRMContact(
            id: "unrelated", name: "Other", phone: "07000000000", email: "other@example.com", address: "", createdAt: "2026-08-24")

        XCTAssertEqual(TaskAccessScope.visible([mine, theirs], for: staff).map(\.id), ["mine"])
        XCTAssertEqual(ContactAccessScope.visible([related, unrelated], leads: [assignedLead], for: staff).map(\.id), ["related"])
    }

    func testQuoteReferencesDoNotDependOnVisibleQuoteCount() {
        let date = ISO8601DateFormatter().date(from: "2026-08-24T13:35:07Z")!
        XCTAssertEqual(QuoteReference.make(date: date, nonce: "A1B2C3D4-E5F6"), "Q-2026-A1B2C3")
        XCTAssertNotEqual(QuoteReference.make(date: date, nonce: "A1B2C3D4"), QuoteReference.make(date: date, nonce: "F9E8D7C6"))
    }

    func testSameDayMorningNotificationSurvivesRefreshBeforeTrigger() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T06:30:00Z")!  // 07:30 BST
        let reminder = NotificationPolicy.reminderDate(for: "2026-08-24", hour: 8, calendar: london)
        XCTAssertNotNil(reminder)
        XCTAssertGreaterThan(reminder!, now)
        XCTAssertEqual(london.component(.hour, from: reminder!), 8)
    }

    func testDailyReminderMovesToTomorrowAfterItsHour() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T09:30:00Z")!  // 10:30 BST
        let reminder = NotificationPolicy.nextDailyReminder(hour: 9, now: now, calendar: london)!
        XCTAssertEqual(SupabaseService.localDay(for: reminder, calendar: london), "2026-08-25")
        XCTAssertEqual(london.component(.hour, from: reminder), 9)
    }

    func testPaymentReminderIsAdminOnlyAndUsesAmountActuallyDueNow() {
        var deposit = lead(id: "deposit", stage: .won, value: 10_000, balance: 10_000)
        deposit.deposit = 2_000
        deposit.depositPaid = false
        let completed = lead(id: "complete", stage: .completed, value: 8_000, balance: 3_000)
        let waiting = lead(id: "waiting", stage: .waitingForPayment, value: 7_000, balance: 2_000)
        let paid = lead(id: "paid", stage: .paid, value: 5_000, balance: 0)

        let admin = PaymentReminderPolicy.summary(leads: [deposit, completed, waiting, paid], isAdmin: true, enabled: true)
        XCTAssertEqual(admin.count, 3)
        XCTAssertEqual(admin.total, 7_000, accuracy: 0.001)
        XCTAssertEqual(PaymentReminderPolicy.summary(leads: [deposit], isAdmin: false, enabled: true).count, 0)
        XCTAssertEqual(PaymentReminderPolicy.summary(leads: [deposit], isAdmin: true, enabled: false).count, 0)
    }

    func testEmailIdentifiersNeverUseLegacyAuthenticationFallback() {
        XCTAssertEqual(AuthenticationPolicy.secureEmail(for: "worker@example.com"), "worker@example.com")
        XCTAssertEqual(AuthenticationPolicy.secureEmail(for: "  Worker@Example.com  "), "worker@example.com")
        XCTAssertEqual(AuthenticationPolicy.secureEmail(for: "willconway9"), "admin@prolineroofingandsolar.co.uk")
        XCTAssertNil(AuthenticationPolicy.secureEmail(for: "legacy-worker"))
    }

    func testNotificationQueueIsChronologicalAndCanBeSafelyCapped() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T06:00:00Z")!
        let tasks = (0..<70).map { index in
            GeneralTask(
                id: String(format: "%02d", index), title: "Task \(index)", completed: false, completedDate: nil,
                dueDate: index == 69 ? "2026-08-25" : "2026-08-24", priority: "medium", category: "General", notes: nil,
                createdAt: "2026-08-24", assignedTo: ["will"])
        }
        let plans = NotificationPolicy.plans(
            leads: [], tasks: tasks, notifySurveys: false, notifyJobStarts: false, notifyTasks: true, notifyPayments: false, isAdmin: false,
            now: now, calendar: london)
        let scheduled = Array(plans.prefix(NotificationPolicy.maximumPending))

        XCTAssertEqual(plans.count, 70)
        XCTAssertEqual(scheduled.count, 60)
        XCTAssertTrue(scheduled.allSatisfy { SupabaseService.localDay(for: $0.date, calendar: london) == "2026-08-24" })
        XCTAssertEqual(plans.last?.id, "task-69")
    }

    func testDisabledNotificationCategoriesProduceNoPlans() {
        var item = lead(id: "lead", stage: .scheduled, value: 1, balance: 1)
        item.surveyDate = "2026-08-25"
        item.startDate = "2026-08-26"
        let task = GeneralTask(
            id: "task", title: "Task", completed: false, completedDate: nil, dueDate: "2026-08-25", priority: "medium", category: "General",
            notes: nil, createdAt: "2026-08-24", assignedTo: [])
        let now = ISO8601DateFormatter().date(from: "2026-08-24T06:00:00Z")!
        XCTAssertTrue(
            NotificationPolicy.plans(
                leads: [item], tasks: [task], notifySurveys: false, notifyJobStarts: false, notifyTasks: false, notifyPayments: false,
                isAdmin: true, now: now
            ).isEmpty)
    }

    func testLeadUpdatesRequireTheLoadedSupabaseVersion() {
        let query = SupabaseWriteCondition.query(id: "lead-1", expectedUpdatedAt: "2026-08-24T12:30:00Z")
        XCTAssertEqual(query.first(where: { $0.name == "id" })?.value, "eq.lead-1")
        XCTAssertEqual(query.first(where: { $0.name == "updated_at" })?.value, "eq.2026-08-24T12:30:00Z")
        XCTAssertTrue(SupabaseWriteCondition.isConflict(returnedRowCount: 0))
        XCTAssertFalse(SupabaseWriteCondition.isConflict(returnedRowCount: 1))
    }

    func testSyncPolicyPreventsOverlappingOrSignedOutRefreshes() {
        XCTAssertTrue(SyncPolicy.shouldStart(isAuthenticated: true, isRefreshing: false))
        XCTAssertFalse(SyncPolicy.shouldStart(isAuthenticated: true, isRefreshing: true))
        XCTAssertFalse(SyncPolicy.shouldStart(isAuthenticated: false, isRefreshing: false))
    }

    func testRetiredFleetInsuranceAndTaxRemindersAreHidden() {
        let insurance = GeneralTask(
            id: "1", title: "AB12 CDE — Insurance", completed: false, completedDate: nil, dueDate: "2026-09-01", priority: "high",
            category: "Fleet", notes: nil, createdAt: "2026-08-24", assignedTo: [])
        let tax = GeneralTask(
            id: "2", title: "AB12 CDE — Road tax", completed: false, completedDate: nil, dueDate: "2026-09-01", priority: "high",
            category: "Renewal", notes: nil, createdAt: "2026-08-24", assignedTo: [])
        let mot = GeneralTask(
            id: "3", title: "AB12 CDE — MOT", completed: false, completedDate: nil, dueDate: "2026-09-01", priority: "high",
            category: "Fleet", notes: nil, createdAt: "2026-08-24", assignedTo: [])

        XCTAssertTrue(FleetTaskPolicy.isRetiredReminder(insurance))
        XCTAssertTrue(FleetTaskPolicy.isRetiredReminder(tax))
        XCTAssertFalse(FleetTaskPolicy.isRetiredReminder(mot))
    }

    func testPayrollHalfAndFullDays() {
        let entries = [
            TimesheetEntry(id: "1", userID: "u", leadID: "l", date: "2026-08-03", type: "full", amount: 240, createdAt: "2026-08-03"),
            TimesheetEntry(id: "2", userID: "u", leadID: "l", date: "2026-08-04", type: "half", amount: 120, createdAt: "2026-08-04"),
        ]
        XCTAssertEqual(PayrollMath.days(entries), 1.5)
        XCTAssertEqual(PayrollMath.gross(entries), 360)
    }

    func testCISNetCalculation() {
        XCTAssertEqual(PayrollMath.net(1_000, rate: 20), 800, accuracy: 0.001)
        XCTAssertEqual(PayrollMath.net(1_000, rate: 30), 700, accuracy: 0.001)
    }

    func testPayrollWeekStartsOnMonday() {
        let date = SupabaseService.date(from: "2026-08-09")!
        XCTAssertEqual(PayrollMath.key(PayrollMath.monday(for: date)), "2026-08-03")
    }

    func testAssistantOutstandingBalancesOnlyIncludesActiveJobs() {
        let won = lead(id: "won", stage: .won, value: 10_000, balance: 4_000)
        let paid = lead(id: "paid", stage: .paid, value: 8_000, balance: 0)
        let result = OperationsInsights.answer("show outstanding balances", leads: [won, paid], tasks: [], today: "2026-08-09")
        XCTAssertEqual(result.ids, ["won"])
        XCTAssertTrue(result.text.contains("£4,000"))
    }

    func testAssistantQuoteFollowUpsAreOldestFirst() {
        var newer = lead(id: "newer", stage: .quoteSent, value: 2_000, balance: 2_000)
        newer.updatedAt = "2026-08-09"
        var older = lead(id: "older", stage: .quoteSent, value: 3_000, balance: 3_000)
        older.updatedAt = "2026-08-01"
        let result = OperationsInsights.answer("quotes to follow up", leads: [newer, older], tasks: [], today: "2026-08-09")
        XCTAssertEqual(result.ids, ["older", "newer"])
        XCTAssertTrue(result.text.contains("2 sent quotes"))
    }

    func testAssistantTodayCountsOverdueTasksAndJobs() {
        var overdueJob = lead(id: "late", stage: .inProgress, value: 5_000, balance: 2_000)
        overdueJob.endDate = "2026-08-01"
        let task = GeneralTask(
            id: "task", title: "Order tiles", completed: false, completedDate: nil, dueDate: "2026-08-08", priority: "high",
            category: "Supplies", notes: nil, createdAt: "2026-08-01", assignedTo: [])
        let result = OperationsInsights.answer("what needs attention today", leads: [overdueJob], tasks: [task], today: "2026-08-09")
        XCTAssertTrue(result.text.contains("1 overdue task"))
        XCTAssertTrue(result.text.contains("1 job"))
        XCTAssertEqual(result.ids, ["late"])
    }

    func testReportCSVIncludesFinancialFieldsAndEscapesCustomerNames() {
        var item = lead(id: "42", stage: .won, value: 12_500, balance: 10_000)
        item.name = "Smith, \"Anne\""
        item.deposit = 2_500
        item.depositPaid = true
        let csv = CRMReportExport.csv(leads: [item])
        XCTAssertTrue(csv.contains("Deposit paid,Balance"))
        XCTAssertTrue(csv.contains("\"Smith, \"\"Anne\"\"\""))
        XCTAssertTrue(csv.contains("12500.00,2500.00,Yes,10000.00"))
    }

    func testQuoteCalculatesDiscountVATAndTotal() {
        let items = [
            QuoteLineItem(id: "1", description: "Roofing labour", category: "Labour", quantity: 2, unit: "day", unitPrice: 500),
            QuoteLineItem(id: "2", description: "Tiles", category: "Materials", quantity: 100, unit: "tile", unitPrice: 2.5),
        ]
        let quote = CRMQuote(
            id: "q", leadID: "l", quoteNumber: "Q-1", status: .draft, lineItems: items, vatRate: 20, discount: 50, validUntil: nil,
            terms: "", customerMessage: "", sentAt: nil, acceptedAt: nil, createdAt: "", updatedAt: "")
        XCTAssertEqual(quote.subtotal, 1_250, accuracy: 0.001)
        XCTAssertEqual(quote.vat, 240, accuracy: 0.001)
        XCTAssertEqual(quote.total, 1_440, accuracy: 0.001)
    }

    func testSurveyMeasurementsCalculateRoofArea() {
        let measurement = SurveyMeasurement(id: "m", label: "Main roof", length: 12.5, width: 8, unit: "m")
        XCTAssertEqual(measurement.area, 100, accuracy: 0.001)
    }

    func testQuotePDFIsGenerated() {
        let item = QuoteLineItem(
            id: "1", description: "Strip and re-tile main roof", category: "Roofing", quantity: 1, unit: "job", unitPrice: 12_500)
        let quote = CRMQuote(
            id: "q", leadID: "l", quoteNumber: "Q-2026-0001", status: .draft, lineItems: [item], vatRate: 20, discount: 500,
            validUntil: "2026-09-15", terms: "Deposit on acceptance. Balance on completion.",
            customerMessage: "Thank you for inviting us to quote for your roofing project.", sentAt: nil, acceptedAt: nil, createdAt: "",
            updatedAt: "")
        let pdf = QuotePDFRenderer.data(quote: quote, lead: lead(id: "l", stage: .quotePreparing, value: 0, balance: 0))
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(pdf.count, 1_000)
    }

    private func lead(id: String, stage: LeadStage, value: Double, balance: Double) -> Lead {
        Lead(
            id: id, jobRef: "JOB-\(id)", name: "Customer \(id)", phone: "", email: "", address: "Bristol", jobType: "Re-roof", stage: stage,
            value: value, deposit: 0, depositPaid: false, balance: balance, source: "", assignedTo: "", surveyDate: nil, surveyTime: nil,
            startDate: nil, endDate: nil, completedDate: nil, paidDate: nil, progress: 0, tasks: [], photos: [], notes: [], files: [],
            materials: [], wonDate: nil, myBuilderURL: nil, reviewRequestSent: nil, lat: nil, lng: nil, createdAt: "2026-08-01",
            updatedAt: "2026-08-01")
    }

    func testLeadDecodesRowsWithNullsAndUnknownStagesFromOtherClients() throws {
        let json = """
        [{"id":"1","name":"Mrs Green","stage":"Some Future Stage","source":null,"assigned_to":null,"progress":null,"value":null,"deposit":null,"deposit_paid":null,"balance":null,"tasks":null,"created_at":"2026-09-01","updated_at":"2026-09-01T09:00:00+00:00"}]
        """
        let leads = try JSONDecoder().decode([Lead].self, from: Data(json.utf8))
        XCTAssertEqual(leads.count, 1)
        XCTAssertEqual(leads[0].stage, .newLead)
        XCTAssertEqual(leads[0].source, "")
        XCTAssertEqual(leads[0].tasks, [])
    }

    func testContactLinksNeverTrapOnMessyInput() {
        XCTAssertEqual(ContactLinks.telephone("07000 000000")?.absoluteString, "tel:07000000000")
        XCTAssertNil(ContactLinks.telephone("call me"))
        XCTAssertNil(ContactLinks.email("john smith"))
        XCTAssertNotNil(ContactLinks.email(" john smith@example.com "))
        XCTAssertEqual(ContactLinks.whatsApp("07000 000000")?.absoluteString, "https://wa.me/447000000000")
        XCTAssertNil(ContactLinks.maps(address: "  "))
    }

    func testNextStepFollowsThePipeline() {
        var lead = Lead(id: "1", jobRef: "JOB-1", name: "Mr Taylor", phone: "", email: "", address: "", jobType: "Re-roof", stage: .newLead, value: 0, deposit: 0, depositPaid: false, balance: 0, source: "", assignedTo: "", surveyDate: nil, surveyTime: nil, startDate: nil, endDate: nil, completedDate: nil, paidDate: nil, progress: 0, tasks: [], photos: [], notes: [], files: [], materials: [], wonDate: nil, myBuilderURL: nil, reviewRequestSent: nil, lat: nil, lng: nil, createdAt: "2026-09-01", updatedAt: "2026-09-01")
        XCTAssertEqual(AppState.nextStep(for: lead), .bookSurvey)
        lead.surveyDate = "2026-09-20"
        XCTAssertEqual(AppState.nextStep(for: lead), .move(.surveyBooked))
        lead.stage = .won
        XCTAssertEqual(AppState.nextStep(for: lead), .scheduleJob)
        lead.stage = .completed; lead.balance = 500
        XCTAssertEqual(AppState.nextStep(for: lead), .move(.waitingForPayment))
        lead.stage = .paid
        XCTAssertNil(AppState.nextStep(for: lead))
    }

    func testWeatherSymbolsAndSiteNote() {
        XCTAssertEqual(WeatherPolicy.symbol(for: 0), "sun.max")
        XCTAssertEqual(WeatherPolicy.symbol(for: 61), "cloud.rain")
        XCTAssertEqual(WeatherPolicy.symbol(for: 95), "cloud.bolt.rain")
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let hours = (0...11).map { offset in
            WeatherHour(date: calendar.date(byAdding: .hour, value: offset, to: start)!, temperature: 14, rainChance: offset >= 8 ? 70 : 10, code: offset >= 8 ? 61 : 1)
        }
        let note = WeatherPolicy.note(for: hours, now: start, calendar: calendar)
        XCTAssertEqual(note, "rain from 15:00")
        XCTAssertEqual(WeatherPolicy.note(for: hours.map { WeatherHour(date: $0.date, temperature: 14, rainChance: 5, code: 1) }, now: start, calendar: calendar), "dry all day")
    }
}
