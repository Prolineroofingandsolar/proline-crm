import SwiftUI

struct TimesheetView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        #if os(macOS)
            if appState.usesAdminInterface { MacPayrollView() } else { WorkerWeeklyPayView() }
        #else
            if appState.usesAdminInterface { MobileAdminPayReview() } else { WorkerWeeklyPayView() }
        #endif
    }
}

private struct WorkerWeekDay: Identifiable {
    let date: Date
    let entry: TimesheetEntry?
    var id: String { PayrollMath.key(date) }
}

private struct WorkerWeeklyPayView: View {
    @Environment(AppState.self) private var appState
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var editingDay: WorkerWeekDay?
    @State private var confirmingSubmit = false
    private var user: CRMUser? { appState.currentUser }
    private var weekKey: String { PayrollMath.key(weekStart) }
    private var friday: Date { Calendar.current.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart }
    private var payDate: Date { Calendar.current.date(byAdding: .day, value: 11, to: weekStart) ?? friday }
    private var entries: [TimesheetEntry] {
        guard let id = user?.id else { return [] }
        return appState.timesheets.filter { $0.userID == id && $0.date >= weekKey && $0.date <= PayrollMath.key(friday) }
    }
    private var run: PaymentRun? { appState.paymentRuns.first { $0.userID == user?.id && $0.weekStart == weekKey } }
    private var locked: Bool { run.map { $0.status != .due } ?? false }
    private var complete: Bool { Set(entries.map(\.date)).count == 5 }
    private var gross: Double { PayrollMath.gross(entries) }
    private var cis: Double { gross * Double(user?.cisRate ?? 20) / 100 }
    private var canSubmitNow: Bool { Date.now >= friday || weekStart < PayrollMath.monday(for: .now) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("My work week").font(.title2.bold());
                            Text(
                                "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(friday.formatted(.dateTime.day().month(.abbreviated)))"
                            ).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                        } label: {
                            Image(systemName: "chevron.right")
                        }.disabled(weekStart >= PayrollMath.monday(for: .now))
                    }
                    HStack(spacing: 12) {
                        payMetric("Days", PayrollMath.days(entries).formatted(), "calendar", .blue)
                        payMetric("Gross", gross.formatted(.currency(code: "GBP")), "sterlingsign", Color.accentColor)
                        payMetric("After CIS", (gross - cis).formatted(.currency(code: "GBP")), "banknote", .green)
                    }
                    Label(
                        "Expected payment: Friday \(payDate.formatted(.dateTime.day().month(.wide)))",
                        systemImage: "calendar.badge.checkmark"
                    ).font(.subheadline.bold()).foregroundStyle(.blue)
                }.padding(16).background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { offset in
                        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                        let entry = entries.first { $0.date == PayrollMath.key(date) }
                        Button {
                            editingDay = WorkerWeekDay(date: date, entry: entry)
                        } label: {
                            dayRow(date, entry)
                        }.buttonStyle(.plain).disabled(locked)
                    }
                }

                if let rate = user?.dayRate, rate > 0 {
                    Text(
                        "Calculated using your saved \(rate.formatted(.currency(code: "GBP"))) day rate and \(user?.cisRate ?? 20)% CIS rate."
                    ).font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Ask an administrator to add your day rate before submitting.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.accentColor).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
                            Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                if let run {
                    Label(
                        run.status == .submitted
                            ? "Submitted for admin review"
                            : run.status == .scheduled ? "Approved for payment" : run.status == .paid ? "Paid" : "Week reopened",
                        systemImage: run.status == .paid ? "checkmark.seal.fill" : "lock.fill"
                    )
                    .font(.headline).foregroundStyle(run.status == .paid ? .green : run.status == .scheduled ? .blue : Color.accentColor)
                    .padding(14).frame(maxWidth: .infinity).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Button {
                        confirmingSubmit = true
                    } label: {
                        Label(complete ? "Submit week for payment" : "Complete all five days", systemImage: "paperplane.fill").frame(
                            maxWidth: .infinity
                        ).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!complete || !canSubmitNow || (user?.dayRate ?? 0) <= 0)
                    if complete && !canSubmitNow {
                        Text("Submission opens after Friday’s work is complete.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(16).frame(maxWidth: 720)
        }
        .navigationTitle("My Timesheet")
        .sheet(item: $editingDay) { WorkerDayEntrySheet(day: $0) }
        .confirmationDialog("Submit this week?", isPresented: $confirmingSubmit, titleVisibility: .visible) {
            Button("Submit and lock week") { Task { _ = await appState.submitTimesheetWeek(weekStart: weekKey) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Your administrator will review it and schedule payment for the following Friday. You cannot edit it after submitting unless they reopen it."
            )
        }
    }

    private func dayRow(_ date: Date, _ entry: TimesheetEntry?) -> some View {
        let isOff = entry?.type == "off"
        let iconName = entry == nil ? "plus" : (isOff ? "minus" : "hammer.fill")
        let iconColor: Color = entry == nil || isOff ? .secondary : Color.accentColor
        let iconBackground: Color =
            entry == nil
            ? Color.secondary.opacity(0.1)
            : (isOff ? Color.secondary.opacity(0.14) : Color.accentColor.opacity(0.14))
        return HStack(spacing: 13) {
            Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.headline).frame(width: 42, alignment: .leading)
            Circle()
                .fill(iconBackground)
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: iconName).foregroundStyle(iconColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.map { $0.type == "half" ? "Half day" : $0.type == "off" ? "Off" : "Full day" } ?? "Add work day").fontWeight(
                    .semibold)
                if let entry, entry.type != "off" {
                    Text(appState.leads.first { $0.id == entry.leadID }.map { "\($0.name) · \($0.jobRef)" } ?? "Job not found").font(
                        .caption
                    ).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(entry == nil ? "Tap to record this day" : "Not working").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let entry, entry.amount > 0 { Text(entry.amount, format: .currency(code: "GBP")).fontWeight(.bold) }
            Image(systemName: locked ? "lock.fill" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(entry == nil ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.18)))
    }

    private func payMetric(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).foregroundStyle(tint); Text(value).font(.headline);
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WorkerDayEntrySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let day: WorkerWeekDay
    @State private var kind: String
    @State private var leadID: String
    @State private var saving = false
    init(day: WorkerWeekDay) {
        self.day = day; _kind = State(initialValue: day.entry?.type ?? "full"); _leadID = State(initialValue: day.entry?.leadID ?? "")
    }
    private var jobs: [Lead] {
        appState.leads.filter { [.won, .scheduled, .inProgress, .completed].contains($0.stage) }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day", selection: $kind) {
                        Text("Full day").tag("full"); Text("Half day").tag("half"); Text("Off").tag("off")
                    }.pickerStyle(.segmented)
                }
                if kind != "off" {
                    Section("Job worked on") {
                        Picker("Job", selection: $leadID) {
                            Text("Choose job").tag(""); ForEach(jobs) { Text("\($0.name) · \($0.jobRef)").tag($0.id) }
                        }
                    }
                }
                Section {
                    LabeledContent("Date", value: day.date.formatted(date: .complete, time: .omitted));
                    if kind != "off", let rate = appState.currentUser?.dayRate {
                        LabeledContent("Amount", value: (rate * (kind == "half" ? 0.5 : 1)).formatted(.currency(code: "GBP")))
                    }
                }
            }.navigationTitle("Record \(day.date.formatted(.dateTime.weekday(.wide)))").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || (kind != "off" && leadID.isEmpty))
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 340)
        #endif
    }
    private func save() {
        Task {
            saving = true;
            if await appState.setTimesheetDay(
                userID: appState.currentUser?.id ?? "", leadID: leadID, date: PayrollMath.key(day.date), kind: kind)
            {
                dismiss()
            }; saving = false
        }
    }
}

private struct MobileAdminPayReview: View {
    @Environment(AppState.self) private var appState
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var confirmingPaid: AdminPaySummary?
    @State private var addingTimesheet = false
    @State private var quickAddUserID: String?
    private var friday: Date { Calendar.current.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart }
    private var weekKey: String { PayrollMath.key(weekStart) }
    private var entries: [TimesheetEntry] { appState.timesheets.filter { $0.date >= weekKey && $0.date <= PayrollMath.key(friday) } }
    private var defaultEntryDate: Date {
        let today = Calendar.current.startOfDay(for: .now); return today >= weekStart && today <= friday ? today : weekStart
    }
    private var summaries: [AdminPaySummary] {
        Dictionary(grouping: entries, by: \.userID).compactMap { userID, rows in
            guard let user = appState.users.first(where: { $0.id == userID }) else { return nil }
            let gross = PayrollMath.gross(rows), rate = user.cisRate ?? 20
            let status = appState.paymentRuns.first { $0.userID == userID && $0.weekStart == weekKey }?.status ?? .due
            return AdminPaySummary(user: user, entries: rows, gross: gross, cis: gross * Double(rate) / 100, status: status)
        }.sorted {
            let leftPriority = $0.status == .submitted ? 0 : 1
            let rightPriority = $1.status == .submitted ? 0 : 1
            return leftPriority == rightPriority
                ? $0.user.name.localizedStandardCompare($1.user.name) == .orderedAscending
                : leftPriority < rightPriority
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                HStack {
                    Button {
                        weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                    } label: {
                        Image(systemName: "chevron.left")
                    }; Spacer();
                    VStack {
                        Text("Weekly payments").font(.title2.bold());
                        Text(
                            "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(friday.formatted(.dateTime.day().month(.abbreviated)))"
                        ).foregroundStyle(.secondary)
                    }; Spacer();
                    Button {
                        weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                    } label: {
                        Image(systemName: "chevron.right")
                    }.disabled(weekStart >= PayrollMath.monday(for: .now))
                }
                HStack(spacing: 10) {
                    adminMetric("Submitted", summaries.filter { $0.status == .submitted }.count, Color.accentColor);
                    adminMetric("Approved", summaries.filter { $0.status == .scheduled }.count, .blue);
                    adminMetric("Net total", summaries.reduce(0) { $0 + $1.gross - $1.cis }.formatted(.currency(code: "GBP")), .green)
                }
                ForEach(summaries) { summary in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle().fill(Color.accentColor.opacity(0.14)).frame(width: 43, height: 43).overlay(
                                Text(summary.user.name.prefix(1)).fontWeight(.bold).foregroundStyle(Color.accentColor));
                            VStack(alignment: .leading) {
                                Text(summary.user.name).fontWeight(.bold);
                                Text("\(PayrollMath.days(summary.entries).formatted()) days · \(summary.entries.count)/5 recorded").font(
                                    .caption
                                ).foregroundStyle(.secondary)
                            }; Spacer();
                            Text(summary.status.displayName).font(.caption.bold()).foregroundStyle(
                                summary.status == .submitted
                                    ? Color.accentColor
                                    : summary.status == .scheduled ? .blue : summary.status == .paid ? .green : .secondary)
                        }
                        HStack {
                            amount("Gross", summary.gross); amount("CIS", summary.cis); amount("To pay", summary.gross - summary.cis)
                        }
                        if summary.missingPaymentDetails {
                            Label("Add bank details before approval", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold()).foregroundStyle(.red)
                        }
                        if summary.status == .submitted {
                            Button("Approve for next Friday") {
                                Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: weekKey, status: .scheduled) }
                            }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, alignment: .trailing).disabled(
                                summary.missingPaymentDetails)
                        } else if summary.status == .scheduled {
                            HStack {
                                Button("Reopen") {
                                    Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: weekKey, status: .due) }
                                }; Spacer(); Button("Mark paid") { confirmingPaid = summary }.buttonStyle(.borderedProminent).tint(.green)
                            }
                        } else if summary.status == .paid {
                            Label("Payment recorded", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        } else {
                            Label("Waiting for worker to submit", systemImage: "clock").foregroundStyle(.secondary)
                        }
                        if summary.status == .due || summary.status == .submitted {
                            Button {
                                quickAddUserID = summary.user.id
                            } label: {
                                Label("Log work day", systemImage: "plus").font(.caption.bold())
                            }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
                if summaries.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "No work recorded", systemImage: "calendar",
                            description: Text("Add a work day for a worker or wait for their submission."))
                        Button {
                            addingTimesheet = true
                        } label: {
                            Label("Add work day", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }.padding(16)
        }
        .navigationTitle("Subcontractor Pay")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingTimesheet = true
                } label: {
                    Image(systemName: "plus")
                }.accessibilityLabel("Add work day")
            }
        }
        .sheet(isPresented: $addingTimesheet) { AddTimesheetView(defaultDate: defaultEntryDate) }
        .sheet(item: Binding(get: { quickAddUserID.map { QuickAddSeed(userID: $0) } }, set: { quickAddUserID = $0?.userID })) { seed in
            AddTimesheetView(defaultUserID: seed.userID, defaultDate: defaultEntryDate)
        }
        .confirmationDialog(
            "Confirm payment", isPresented: Binding(get: { confirmingPaid != nil }, set: { if !$0 { confirmingPaid = nil } }),
            titleVisibility: .visible
        ) {
            Button("Mark paid") {
                guard let summary = confirmingPaid else { return };
                Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: weekKey, status: .paid) }; confirmingPaid = nil
            }; Button("Cancel", role: .cancel) { confirmingPaid = nil }
        } message: {
            Text("Confirm the bank transfer has been made before recording this payment.")
        }
    }
    private func adminMetric(_ title: String, _ value: Int, _ tint: Color) -> some View { adminMetric(title, "\(value)", tint) }
    private func adminMetric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.headline).foregroundStyle(tint); Text(title).font(.caption).foregroundStyle(.secondary)
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    private func amount(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary); Text(value, format: .currency(code: "GBP")).fontWeight(.bold)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdminPaySummary: Identifiable {
    let user: CRMUser; let entries: [TimesheetEntry]; let gross: Double; let cis: Double; let status: PaymentStatus
    var id: String { user.id }
    var missingPaymentDetails: Bool {
        (user.bankAccountNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (user.bankSortCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct QuickAddSeed: Identifiable { let userID: String; var id: String { userID } }

struct AddTimesheetView: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss
    let entry: TimesheetEntry?
    let adminCopy: Bool
    @State private var userID = ""; @State private var leadID = ""; @State private var date = Date(); @State private var kind = "full";
    @State private var isSaving = false
    init(entry: TimesheetEntry? = nil, defaultUserID: String = "", defaultDate: Date? = nil, adminCopy: Bool = false) {
        self.entry = entry; self.adminCopy = adminCopy; _userID = State(initialValue: entry?.userID ?? defaultUserID);
        _leadID = State(initialValue: entry?.leadID ?? "");
        _date = State(initialValue: entry.flatMap { SupabaseService.date(from: $0.date) } ?? defaultDate ?? .now);
        _kind = State(initialValue: entry?.type ?? "full")
    }
    // Timesheets are calendar days, not instants. ISO8601FormatStyle defaults to UTC,
    // which can turn local midnight on 17 August into 16 August during BST.
    private var dateKey: String { PayrollMath.key(date) }
    private var sourceEntries: [TimesheetEntry] { adminCopy ? appState.adminTimesheetChecks : appState.timesheets }
    private var duplicate: Bool { sourceEntries.contains { $0.userID == userID && $0.date == dateKey && $0.id != entry?.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Who and when") {
                    Picker("Worker", selection: $userID) {
                        Text("Select worker").tag("")
                        ForEach(appState.isAdmin ? appState.users : appState.users.filter { $0.id == appState.currentUser?.id }) {
                            Text($0.name).tag($0.id)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Work") {
                    if kind != "off" {
                        Picker("Job", selection: $leadID) {
                            Text("Select job").tag("")
                            ForEach(appState.leads.filter { [.won, .scheduled, .inProgress, .completed].contains($0.stage) }) {
                                Text("\($0.jobRef) · \($0.name)").tag($0.id)
                            }
                        }
                    }
                    Picker("Time", selection: $kind) {
                        Text("Full day").tag("full"); Text("Half day").tag("half"); Text("Off").tag("off")
                    }.pickerStyle(.segmented)
                    if let rate = appState.users.first(where: { $0.id == userID })?.dayRate {
                        LabeledContent(
                            "Amount", value: (kind == "off" ? 0 : rate * (kind == "half" ? 0.5 : 1)).formatted(.currency(code: "GBP")))
                    }
                }
                if duplicate {
                    Section {
                        Label("This worker already has an entry for that date.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(adminCopy ? "Office Timesheet Copy" : (entry == nil ? "Add Work Day" : "Edit Work Day"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { if isSaving { ProgressView() } else { Text("Save") } }
                        .disabled(userID.isEmpty || (leadID.isEmpty && kind != "off") || duplicate || isSaving)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 410)
        .onAppear {
            if userID.isEmpty, !appState.isAdmin { userID = appState.currentUser?.id ?? "" }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            let saved: Bool
            if var changed = entry {
                changed.userID = userID; changed.leadID = kind == "off" ? "" : leadID; changed.date = dateKey
                changed.type = kind
                let rate = appState.users.first { $0.id == userID }?.dayRate ?? 0
                changed.amount = kind == "off" ? 0 : rate * (kind == "half" ? 0.5 : 1)
                saved = adminCopy ? await appState.saveAdminTimesheetCheck(changed) : await appState.saveTimesheet(changed)
            } else {
                saved =
                    adminCopy
                    ? await appState.setAdminTimesheetCheck(userID: userID, leadID: leadID, date: dateKey, kind: kind)
                    : await appState.setTimesheetDay(userID: userID, leadID: leadID, date: dateKey, kind: kind)
            }
            if saved { dismiss() }
        }
    }
}
