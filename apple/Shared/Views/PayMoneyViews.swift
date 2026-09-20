import SwiftUI

#if os(iOS)
/// The pay calendar: one week at a time, whoever is on that week, tap the days they're in, tick when the money has gone.
/// Weeks run into the future because the crew is paid in advance.
struct PayView: View {
    @Environment(AppState.self) private var appState
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var didPickWeek = false
    @State private var addingWorker = false
    @State private var confirmingPaid: CRMUser?
    @State private var manualDay: DayEdit?

    private var weekKey: String { PayrollMath.key(weekStart) }
    private var days: [Date] { (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) } }
    private var thisMonday: Date { PayrollMath.monday(for: .now) }
    private var workers: [CRMUser] { appState.users.filter { $0.role != "admin" && $0.dayRate != nil }.sorted { $0.name < $1.name } }

    struct WorkerWeek: Identifiable {
        let user: CRMUser
        let entries: [TimesheetEntry]
        let paid: Bool
        var id: String { user.id }
        var gross: Double { PayrollMath.gross(entries) }
        var net: Double { gross * (1 - Double(user.cisRate ?? 20) / 100) }
        var days: Double { PayrollMath.days(entries) }
        var missingBank: Bool { (user.bankAccountNumber ?? "").isEmpty || (user.bankSortCode ?? "").isEmpty }
    }

    /// Only people with days in this week — the crew changes week to week.
    private var onThisWeek: [WorkerWeek] {
        workers.compactMap { user in
            let entries = appState.timesheets.filter { $0.userID == user.id && $0.date >= weekKey && $0.date <= PayrollMath.key(days.last ?? weekStart) && $0.type != "off" }
            guard !entries.isEmpty else { return nil }
            let paid = appState.paymentRuns.first { $0.userID == user.id && $0.weekStart == weekKey }?.status == .paid
            return WorkerWeek(user: user, entries: entries, paid: paid)
        }
    }
    private var notOnThisWeek: [CRMUser] { workers.filter { user in !onThisWeek.contains { $0.user.id == user.id } } }
    private var toPay: Double { onThisWeek.filter { !$0.paid }.reduce(0) { $0 + $1.net } }
    private var paidCount: Int { onThisWeek.filter(\.paid).count }

    private var weekLabel: String {
        let offset = Calendar.current.dateComponents([.day], from: thisMonday, to: weekStart).day ?? 0
        switch offset {
        case 0: return "This week"
        case 7: return "Next week"
        case -7: return "Last week"
        default: return weekStart.formatted(.dateTime.year())
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(onThisWeek) { week in
                    row(week)
                }
                if onThisWeek.isEmpty { Text("Nobody on this week yet").foregroundStyle(.secondary) }
                if !notOnThisWeek.isEmpty {
                    Button { addingWorker = true } label: { Label("Add someone", systemImage: "plus") }
                }
            } header: {
                header
            } footer: {
                if !onThisWeek.isEmpty { Text("Tap a day to add or remove it. Tick once the transfer has gone.") }
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
        }
        .onAppear {
            // Land on the week that still needs paying: this week, or next once this one is done.
            guard !didPickWeek else { return }
            didPickWeek = true
            if !onThisWeek.isEmpty, onThisWeek.allSatisfy(\.paid) { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart }
        }
        .confirmationDialog("Add to \(weekLabel.lowercased())", isPresented: $addingWorker, titleVisibility: .visible) {
            ForEach(notOnThisWeek) { user in
                Button(user.name) { Task { await fill(user) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Starts with Monday to Friday. Tap days to change.") }
        .confirmationDialog(confirmingPaid.map { "Paid \($0.name)?" } ?? "", isPresented: Binding(get: { confirmingPaid != nil }, set: { if !$0 { confirmingPaid = nil } }), titleVisibility: .visible) {
            Button("Mark paid") {
                if let user = confirmingPaid { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .paid) } }
                confirmingPaid = nil
            }
            Button("Cancel", role: .cancel) { confirmingPaid = nil }
        } message: { Text("Only after the bank transfer has gone.") }
        .sheet(item: $manualDay) { edit in
            AddTimesheetView(defaultUserID: edit.userID, defaultDate: edit.date)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                Spacer()
                VStack(spacing: 1) {
                    Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(days.last?.formatted(.dateTime.day().month(.abbreviated)) ?? "")").font(.headline).foregroundStyle(.primary)
                    Text(weekLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
            }
            .buttonStyle(.plain)
            HStack {
                if toPay > 0 {
                    Text("\(CRMFormat.money(toPay)) to pay").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                } else if !onThisWeek.isEmpty {
                    Label("All paid", systemImage: "checkmark.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(.green)
                }
                Spacer()
                if !onThisWeek.isEmpty { Text("\(paidCount) of \(onThisWeek.count) paid").font(.subheadline).foregroundStyle(.secondary) }
            }
        }
        .textCase(nil).padding(.vertical, 4)
    }

    private func row(_ week: WorkerWeek) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    NavigationLink { WorkerWeekView(user: week.user, weekStart: weekStart) } label: {
                        Text(week.user.name).fontWeight(.medium).foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    if week.missingBank && !week.paid { Text("· no bank details").font(.caption).foregroundStyle(.red) }
                }
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { day in
                        let key = PayrollMath.key(day)
                        let entry = week.entries.first { $0.date == key }
                        DayChip(letter: day.formatted(.dateTime.weekday(.narrow)), kind: entry?.type, locked: week.paid) {
                            Task { await cycle(week.user, day: day, entry: entry) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(CRMFormat.money(week.net)).fontWeight(.semibold).monospacedDigit().foregroundStyle(week.paid ? Color.secondary : Color.primary)
                Text("\(week.days.formatted()) day\(week.days == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if week.paid { Task { await appState.setPaymentStatus(userID: week.user.id, weekStart: weekKey, status: .due) } } else { confirmingPaid = week.user }
            } label: {
                Image(systemName: week.paid ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(week.paid ? Color.green : Color(.tertiaryLabel))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(week.paid ? "Paid, tap to undo" : "Mark paid")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if !week.paid {
                Button("Remove", role: .destructive) { Task { for entry in week.entries { await appState.deleteTimesheet(entry) } } }
            }
        }
    }

    /// none → full → half → none.
    private func cycle(_ user: CRMUser, day: Date, entry: TimesheetEntry?) async {
        let key = PayrollMath.key(day)
        switch entry?.type {
        case nil, "off":
            guard let job = job(on: key) else { manualDay = DayEdit(userID: user.id, date: day); return }
            await appState.setTimesheetDay(userID: user.id, leadID: job, date: key, kind: "full")
        case "full":
            await appState.setTimesheetDay(userID: user.id, leadID: entry?.leadID ?? "", date: key, kind: "half")
        default:
            if let entry { await appState.deleteTimesheet(entry) }
        }
    }

    /// Mon–Fri full days as the starting point; the admin then taps off the days that don't apply.
    private func fill(_ user: CRMUser) async {
        for day in days {
            let key = PayrollMath.key(day)
            guard let job = job(on: key) else { manualDay = DayEdit(userID: user.id, date: day); return }
            await appState.setTimesheetDay(userID: user.id, leadID: job, date: key, kind: "full")
        }
    }

    /// The job booked that day, else the first live job; nil means the admin has to pick.
    private func job(on day: String) -> String? {
        let live = appState.leads.filter { [.scheduled, .inProgress].contains($0.stage) }
        let booked = live.first { ($0.startDate ?? "") <= day && day <= ($0.endDate ?? $0.startDate ?? "") }
        return (booked ?? live.first ?? appState.leads.first { $0.stage == .won })?.id
    }

    struct DayEdit: Identifiable { let userID: String; let date: Date; var id: String { userID + PayrollMath.key(date) } }
}

/// One day in the pay calendar: filled = full day, half = half day, empty = not in.
private struct DayChip: View {
    let letter: String
    let kind: String?
    let locked: Bool
    let action: () -> Void

    private var isOn: Bool { kind == "full" || kind == "half" }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.accentColor.opacity(kind == "half" ? 0.35 : 1) : Color(.tertiarySystemFill))
                if kind == "half" {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
                Text(letter).font(.subheadline.weight(.semibold)).foregroundStyle(isOn && kind != "half" ? Color.white : Color.primary)
            }
            .frame(width: 34, height: 34)
            .opacity(locked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!locked)
        .accessibilityLabel("\(letter): \(kind == "half" ? "half day" : isOn ? "full day" : "not in")")
    }
}

/// One worker's week: which job each day, the money, and paid or not.
struct WorkerWeekView: View {
    @Environment(AppState.self) private var appState
    let user: CRMUser
    let weekStart: Date
    @State private var editingDay: Date?

    private var weekKey: String { PayrollMath.key(weekStart) }
    private var days: [Date] { (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) } }
    private var entries: [TimesheetEntry] { appState.timesheets.filter { $0.userID == user.id && $0.date >= weekKey && $0.date <= PayrollMath.key(days.last ?? weekStart) } }
    private var paid: Bool { appState.paymentRuns.first { $0.userID == user.id && $0.weekStart == weekKey }?.status == .paid }
    private var gross: Double { PayrollMath.gross(entries) }
    private var cis: Double { gross * Double(user.cisRate ?? 20) / 100 }

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
                            if !paid { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(.tertiaryLabel)) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(paid)
                }
            } header: { Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(days.last?.formatted(.dateTime.day().month(.abbreviated)) ?? "")") }

            Section {
                LabeledContent("Gross", value: CRMFormat.money(gross, pence: true))
                LabeledContent("CIS \(user.cisRate ?? 20)%", value: "−\(CRMFormat.money(cis, pence: true))")
                LabeledContent("To pay") { Text(CRMFormat.money(gross - cis, pence: true)).fontWeight(.semibold) }
            }

            Section {
                if paid {
                    Label("Paid", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Undo") { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .due) } }
                } else {
                    Button("Mark paid") { Task { await appState.setPaymentStatus(userID: user.id, weekStart: weekKey, status: .paid) } }.disabled(entries.isEmpty)
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
