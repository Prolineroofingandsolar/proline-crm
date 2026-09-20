import SwiftUI

#if os(iOS)
/// Weekly pay for the crew: one row per worker, swipe to approve or mark paid, tap for the week.
struct PayView: View {
    @Environment(AppState.self) private var appState
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var addingDay = false
    @State private var confirmingPaid: CRMUser?

    private var weekKey: String { PayrollMath.key(weekStart) }
    private var friday: Date { Calendar.current.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart }
    private var isCurrentWeek: Bool { weekStart >= PayrollMath.monday(for: .now) }
    private var workers: [CRMUser] { appState.users.filter { $0.role != "admin" && $0.dayRate != nil }.sorted { $0.name < $1.name } }

    struct WorkerWeek: Identifiable {
        let user: CRMUser
        let entries: [TimesheetEntry]
        let status: PaymentStatus
        var id: String { user.id }
        var gross: Double { PayrollMath.gross(entries) }
        var cis: Double { gross * Double(user.cisRate ?? 20) / 100 }
        var net: Double { gross - cis }
        var days: Double { PayrollMath.days(entries) }
        var missingBank: Bool { (user.bankAccountNumber ?? "").isEmpty || (user.bankSortCode ?? "").isEmpty }
    }

    private var weeks: [WorkerWeek] {
        workers.map { user in
            let entries = appState.timesheets.filter { $0.userID == user.id && $0.date >= weekKey && $0.date <= PayrollMath.key(friday) }
            let status = appState.paymentRuns.first { $0.userID == user.id && $0.weekStart == weekKey }?.status ?? .due
            return WorkerWeek(user: user, entries: entries, status: status)
        }
    }
    private var toPay: Double { weeks.filter { $0.status != .paid }.reduce(0) { $0 + $1.net } }

    var body: some View {
        List {
            Section {
                ForEach(weeks) { week in
                    NavigationLink { WorkerWeekView(user: week.user, weekStart: weekStart) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(week.user.name).fontWeight(.medium)
                                Text(week.entries.isEmpty ? "Nothing recorded" : "\(week.days.formatted()) days · \(CRMFormat.money(week.net))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if week.missingBank && week.status != .paid {
                                Text("No bank details").font(.caption).foregroundStyle(.red)
                            } else if week.status != .due {
                                Text(week.status.displayName).font(.subheadline).foregroundStyle(week.status == .paid ? Color.green : Color.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if week.status == .submitted && !week.missingBank {
                            Button("Approve") { Task { await appState.setPaymentStatus(userID: week.user.id, weekStart: weekKey, status: .scheduled) } }.tint(.accentColor)
                        } else if week.status == .scheduled {
                            Button("Paid") { confirmingPaid = week.user }.tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if week.status == .scheduled || week.status == .submitted {
                            Button("Reopen") { Task { await appState.setPaymentStatus(userID: week.user.id, weekStart: weekKey, status: .due) } }
                        }
                    }
                }
                if workers.isEmpty { Text("No workers with a day rate yet").foregroundStyle(.secondary) }
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(friday.formatted(.dateTime.day().month(.abbreviated)))").font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.right") }.disabled(isCurrentWeek)
                    }
                    .buttonStyle(.plain)
                    Text("\(workers.count) worker\(workers.count == 1 ? "" : "s") · \(CRMFormat.money(toPay)) to pay").font(.subheadline).foregroundStyle(.secondary)
                }
                .textCase(nil).padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pay")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink { CISView() } label: { Label("CIS return", systemImage: "doc.text") }
                    NavigationLink { ReportsView() } label: { Label("Reports", systemImage: "chart.bar") }
                    NavigationLink { AccountsWorkspaceView() } label: { Label("Accountant handover", systemImage: "square.and.arrow.up") }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingDay = true } label: { Label("Add work day", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $addingDay) { AddTimesheetView(defaultDate: isCurrentWeek ? .now : weekStart) }
        .confirmationDialog("Mark this week as paid?", isPresented: Binding(get: { confirmingPaid != nil }, set: { if !$0 { confirmingPaid = nil } }), titleVisibility: .visible) {
            Button("Mark paid") {
                if let user = confirmingPaid { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .paid) } }
                confirmingPaid = nil
            }
            Button("Cancel", role: .cancel) { confirmingPaid = nil }
        } message: { Text("Only after the bank transfer has gone.") }
    }
}

/// One worker's week: five day cells, the money, and the one button that applies.
struct WorkerWeekView: View {
    @Environment(AppState.self) private var appState
    let user: CRMUser
    let weekStart: Date
    @State private var editingDay: Date?

    private var weekKey: String { PayrollMath.key(weekStart) }
    private var days: [Date] { (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) } }
    private var entries: [TimesheetEntry] { appState.timesheets.filter { $0.userID == user.id && $0.date >= weekKey && $0.date <= PayrollMath.key(days.last ?? weekStart) } }
    private var status: PaymentStatus { appState.paymentRuns.first { $0.userID == user.id && $0.weekStart == weekKey }?.status ?? .due }
    private var gross: Double { PayrollMath.gross(entries) }
    private var cis: Double { gross * Double(user.cisRate ?? 20) / 100 }
    private var locked: Bool { status == .scheduled || status == .paid }

    var body: some View {
        List {
            Section {
                ForEach(days, id: \.self) { day in
                    let entry = entries.first { $0.date == PayrollMath.key(day) }
                    Button { editingDay = day } label: {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).frame(width: 44, alignment: .leading).foregroundStyle(Color.secondary)
                            Text(label(for: entry)).foregroundStyle(entry == nil ? Color.secondary : Color.primary)
                            Spacer()
                            if let entry, entry.type != "off" { Text(entry.type == "half" ? "½ day" : "Full").font(.subheadline).foregroundStyle(Color.secondary) }
                            if !locked { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(.tertiaryLabel)) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                }
            } header: { Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(days.last?.formatted(.dateTime.day().month(.abbreviated)) ?? "")") }

            Section {
                LabeledContent("Gross", value: CRMFormat.money(gross, pence: true))
                LabeledContent("CIS \(user.cisRate ?? 20)%", value: "−\(CRMFormat.money(cis, pence: true))")
                LabeledContent("To pay") { Text(CRMFormat.money(gross - cis, pence: true)).fontWeight(.semibold) }
            }

            Section {
                switch status {
                case .due:
                    Text(entries.isEmpty ? "Nothing recorded yet" : "Waiting for \(user.name.split(separator: " ").first.map(String.init) ?? "them") to submit").foregroundStyle(.secondary)
                    if !entries.isEmpty { Button("Approve anyway") { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .scheduled) } } }
                case .submitted:
                    Button("Approve") { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .scheduled) } }
                case .scheduled:
                    Button("Mark paid") { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .paid) } }
                    Button("Reopen") { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .due) } }
                case .paid:
                    Label("Paid", systemImage: "checkmark.seal").foregroundStyle(.green)
                }
            } footer: {
                if (user.bankAccountNumber ?? "").isEmpty || (user.bankSortCode ?? "").isEmpty { Text("No bank details on file.").foregroundStyle(.red) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { editingDay.map { DayEdit(date: $0) } }, set: { editingDay = $0?.date })) { edit in
            let existing = entries.first { $0.date == PayrollMath.key(edit.date) }
            AddTimesheetView(entry: existing, defaultUserID: user.id, defaultDate: edit.date)
        }
    }

    private func label(for entry: TimesheetEntry?) -> String {
        guard let entry else { return "—" }
        if entry.type == "off" { return "Off" }
        return appState.leads.first { $0.id == entry.leadID }.map { $0.name } ?? "Job"
    }

    private struct DayEdit: Identifiable { let date: Date; var id: Date { date } }
}

/// Who owes what. Swipe to record.
struct MoneyView: View {
    @Environment(AppState.self) private var appState
    @State private var confirming: MoneyRow?

    struct MoneyRow: Identifiable {
        enum Kind { case deposit, balance }
        let lead: Lead
        let kind: Kind
        var id: String { lead.id + (kind == .deposit ? "-d" : "-b") }
        var amount: Double { kind == .deposit ? lead.deposit : lead.balance }
        var overdue: Bool { kind == .balance && [.completed, .waitingForPayment].contains(lead.stage) }
    }

    private var rows: [MoneyRow] {
        var result: [MoneyRow] = []
        for lead in appState.leads where ![.paid, .lost].contains(lead.stage) {
            if !lead.depositPaid && lead.deposit > 0 && [.won, .scheduled, .inProgress].contains(lead.stage) { result.append(MoneyRow(lead: lead, kind: .deposit)) }
            if lead.balance > 0 && [.completed, .waitingForPayment].contains(lead.stage) { result.append(MoneyRow(lead: lead, kind: .balance)) }
        }
        return result.sorted { ($0.overdue ? 0 : 1, $0.lead.updatedAt) < ($1.overdue ? 0 : 1, $1.lead.updatedAt) }
    }
    private var total: Double { rows.reduce(0) { $0 + $1.amount } }
    private var overdueTotal: Double { rows.filter(\.overdue).reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    NavigationLink(value: LeadRoute(id: row.lead.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.lead.name).fontWeight(.medium)
                                Text(row.kind == .deposit ? "Deposit" : "Balance · finished \(CRMFormat.relativeDay(row.lead.completedDate ?? row.lead.endDate).lowercased())")
                                    .font(.subheadline).foregroundStyle(row.overdue ? Color.red : Color.secondary)
                            }
                            Spacer()
                            Text(CRMFormat.money(row.amount)).fontWeight(.medium).monospacedDigit()
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Record") { confirming = row }.tint(.green)
                    }
                }
                if rows.isEmpty { Text("Nothing owed").foregroundStyle(.secondary) }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CRMFormat.money(total)).font(.title2.weight(.semibold)).foregroundStyle(.primary)
                    Text(overdueTotal > 0 ? "\(CRMFormat.money(overdueTotal)) overdue" : "to collect").font(.subheadline).foregroundStyle(overdueTotal > 0 ? Color.red : Color.secondary)
                }
                .textCase(nil).padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Money")
        .toolbar {
            Menu {
                NavigationLink { ReportsView() } label: { Label("Reports", systemImage: "chart.bar") }
                NavigationLink { AccountsWorkspaceView() } label: { Label("Accountant handover", systemImage: "square.and.arrow.up") }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .confirmationDialog(confirming.map { "Record \(CRMFormat.money($0.amount, pence: true)) from \($0.lead.name)?" } ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button(confirming?.kind == .deposit ? "Deposit received" : "Paid in full") {
                if let row = confirming {
                    Task { if row.kind == .deposit { await appState.recordDeposit(for: row.lead) } else { await appState.recordFinalPayment(for: row.lead) } }
                }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }
}
#endif
