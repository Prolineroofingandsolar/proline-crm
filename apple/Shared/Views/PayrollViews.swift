import SwiftUI
import UniformTypeIdentifiers

enum PayrollMath {
    static func monday(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
  }
    static func key(_ date: Date) -> String {
        SupabaseService.localDay(for: date)
    }
  static func days(_ entries: [TimesheetEntry]) -> Double {
    entries.reduce(0) { $0 + ($1.type == "half" ? 0.5 : $1.type == "off" ? 0 : 1) }
  }
  static func gross(_ entries: [TimesheetEntry]) -> Double { entries.reduce(0) { $0 + $1.amount } }
  static func net(_ gross: Double, rate: Int) -> Double { gross * (1 - Double(rate) / 100) }
}

#if os(macOS)
  struct MacPayrollView: View {
    @Environment(AppState.self) private var appState
    @State private var tab = "Timesheets"
    @State private var weekStart = PayrollMath.monday(for: .now)
    @State private var showingAdd = false
    @State private var editingEntry: TimesheetEntry?
    @State private var quickEntry: QuickTimesheet?
    @State private var editingWorker: CRMUser?
    @State private var payingWorker: CRMUser?
    @State private var pendingPaidRunID: String?
    @State private var expandedWorkerID: String?
    private var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 4, to: weekStart)! }
    private var weekEntries: [TimesheetEntry] {
      let start = PayrollMath.key(weekStart)
      let end = PayrollMath.key(weekEnd)
      return appState.timesheets.filter { $0.date >= start && $0.date <= end }
    }
    private var adminWeekEntries: [TimesheetEntry] {
      let start = PayrollMath.key(weekStart)
      let end = PayrollMath.key(weekEnd)
      return appState.adminTimesheetChecks.filter { $0.date >= start && $0.date <= end }
    }
    private var weekNet: Double {
      Dictionary(grouping: weekEntries, by: \.userID).reduce(0) { total, group in
        let rate = appState.users.first(where: { $0.id == group.key })?.cisRate ?? 20
        return total + PayrollMath.net(PayrollMath.gross(group.value), rate: rate)
      }
    }
    private var workers: [CRMUser] {
      appState.users.filter { user in
        guard appState.isAdmin else { return user.id == appState.currentUser?.id }
        return user.role != "admin" || appState.timesheets.contains(where: { $0.userID == user.id })
      }.sorted { $0.name < $1.name }
    }

    var body: some View {
      weeklyRunDashboard
        .background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Timesheets").sheet(
        isPresented: $showingAdd
      ) { AddTimesheetView() }.sheet(item: $editingEntry) { AddTimesheetView(entry: $0) }.sheet(item: $editingWorker) { WorkerPaymentDetailsSheet(user: $0) }
        .sheet(item: $quickEntry) { seed in AddTimesheetView(defaultUserID: seed.userID, defaultDate: seed.date) }
        .sheet(item: $payingWorker) { LogWorkerPaymentSheet(user: $0) }
        .confirmationDialog("Confirm payment", isPresented: Binding(get: { pendingPaidRunID != nil }, set: { if !$0 { pendingPaidRunID = nil } }), titleVisibility: .visible) {
          Button("Mark as paid") {
            guard let id = pendingPaidRunID, let summary = runSummaries.first(where: { $0.id == id }) else { pendingPaidRunID = nil; return }
            Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: summary.weekStart, status: .paid) }
            pendingPaidRunID = nil
          }
          Button("Cancel", role: .cancel) { pendingPaidRunID = nil }
        } message: { Text("This records the weekly run as paid today. Check the amount and bank transfer before continuing.") }
    }

    private var selectedRunSummaries: [RunSummary] {
      let key = PayrollMath.key(weekStart)
      return runSummaries.filter { $0.weekStart == key }
    }
    private var availableWeeks: [Date] {
      let dates = Set(runSummaries.compactMap { SupabaseService.date(from: $0.weekStart) })
      return Array(dates.union([PayrollMath.monday(for: .now)])).sorted(by: >)
    }
    private var selectedGross: Double { selectedRunSummaries.reduce(0) { $0 + $1.gross } }
    private var selectedNet: Double { selectedRunSummaries.reduce(0) { $0 + $1.net } }
    private var selectedCIS: Double { selectedGross - selectedNet }
    private var runStep: Int {
      guard !selectedRunSummaries.isEmpty else { return 1 }
      if selectedRunSummaries.allSatisfy({ $0.status == .paid }) { return 3 }
      if selectedRunSummaries.allSatisfy({ $0.status == .scheduled || $0.status == .paid }) { return 2 }
      return 1
    }

    private var weeklyRunDashboard: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Weekly timesheets").font(.system(size: 27, weight: .bold))
            Text("Record the week, check deductions and prepare the pay run.").foregroundStyle(.secondary)
          }
          Spacer()
          Button { tab = tab == "Timesheets" ? "Runs" : "Timesheets" } label: {
            Label(tab == "Timesheets" ? "Pay runs" : "Edit timesheets", systemImage: tab == "Timesheets" ? "banknote" : "calendar")
          }.buttonStyle(.bordered)
          Button { quickEntry = QuickTimesheet(userID: "", date: defaultEntryDate) } label: { Label("Add work day", systemImage: "plus") }
            .buttonStyle(.borderedProminent).tint(.orange)
        }
        if tab == "Timesheets" {
          timesheets
        } else {
          payRunReview
        }
      }.padding(24)
    }

    private var payRunReview: some View {
      VStack(spacing: 14) {
        runProgressBanner
        weekDetailStrip
        HStack(alignment: .top, spacing: 14) {
          weekList
          workerRunPanel
        }
      }
    }

    private var weekDetailStrip: some View {
      HStack(spacing: 10) {
        weekDetail("Period", "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(weekEnd.formatted(.dateTime.day().month(.abbreviated)))", "calendar", .blue)
        weekDetail("Work recorded", "\(PayrollMath.days(weekEntries).formatted()) days", "clock.fill", .orange)
        weekDetail("Jobs covered", "\(Set(weekEntries.map(\.leadID)).count)", "briefcase.fill", .purple)
        weekDetail("Issues", "\(selectedRunSummaries.filter { missingBankDetails($0.user) }.count)", "exclamationmark.triangle.fill", selectedRunSummaries.contains { missingBankDetails($0.user) } ? .red : .green)
      }
    }
    private func weekDetail(_ title: String, _ value: String, _ icon: String, _ colour: Color) -> some View {
      HStack(spacing: 10) {
        Image(systemName: icon).foregroundStyle(colour).frame(width: 32, height: 32).background(colour.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).fontWeight(.semibold) }
        Spacer()
      }.padding(11).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }

    private var runProgressBanner: some View {
      HStack(spacing: 26) {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(weekEnd.formatted(date: .abbreviated, time: .omitted))").fontWeight(.semibold)
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(selectedNet, format: .currency(code: "GBP")).font(.system(size: 31, weight: .bold))
            Text("net pay").foregroundStyle(.white.opacity(0.72))
          }
          Text("\(selectedRunSummaries.count) workers included").foregroundStyle(.white.opacity(0.72))
        }
        Spacer()
        runStepView(1, "Review", "Check workers")
        Image(systemName: "minus").foregroundStyle(.white.opacity(0.45))
        runStepView(2, "Approve", "Lock this run")
        Image(systemName: "minus").foregroundStyle(.white.opacity(0.45))
        runStepView(3, "Paid", "Transfer complete")
      }.foregroundStyle(.white).padding(20).background(
        LinearGradient(colors: [Color(red: 0.02, green: 0.13, blue: 0.22), Color(red: 0.01, green: 0.20, blue: 0.32)], startPoint: .leading, endPoint: .trailing),
        in: RoundedRectangle(cornerRadius: 12))
    }
    private func runStepView(_ number: Int, _ title: String, _ subtitle: String) -> some View {
      VStack(spacing: 5) {
        Text("\(number)").fontWeight(.bold).frame(width: 31, height: 31).background(number <= runStep ? Color.orange : Color.clear, in: Circle()).overlay(Circle().stroke(.white.opacity(0.6)))
        Text(title).fontWeight(.semibold)
        Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.65))
      }.frame(width: 110)
    }

    private var weekList: some View {
      VStack(alignment: .leading, spacing: 10) {
        Text("Pay weeks").font(.title3.bold())
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(availableWeeks, id: \.self) { date in
              let summaries = runSummaries.filter { $0.weekStart == PayrollMath.key(date) }
              let total = summaries.reduce(0) { $0 + $1.net }
              Button { weekStart = date } label: {
                VStack(alignment: .leading, spacing: 7) {
                  HStack {
                    Text(weekRangeLabel(date)).fontWeight(.semibold)
                    Spacer()
                    Text(total, format: .currency(code: "GBP")).fontWeight(.bold)
                  }
                  HStack {
                    Text("\(summaries.count) workers").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(weekStatus(summaries)).font(.caption.bold()).foregroundStyle(weekStatusColor(summaries))
                  }
                }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(PayrollMath.key(date) == PayrollMath.key(weekStart) ? Color.orange : Color.secondary.opacity(0.2), lineWidth: PayrollMath.key(date) == PayrollMath.key(weekStart) ? 2 : 1))
              }.buttonStyle(.plain)
            }
          }
        }
      }.padding(14).frame(width: 310, height: 500, alignment: .top).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private var workerRunPanel: some View {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Workers in this run").font(.title3.bold())
            Text("Calculated from recorded work days").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button { quickEntry = QuickTimesheet(userID: "", date: defaultEntryDate) } label: { Label("Add worker", systemImage: "person.badge.plus") }
        }.padding(16)
        Divider()
        if selectedRunSummaries.isEmpty {
          ContentUnavailableView("No time recorded", systemImage: "calendar.badge.plus", description: Text("Add a worker's first work day for this week."))
            .frame(maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(selectedRunSummaries, id: \.id) { summary in workerRunRow(summary) }
            }
          }
        }
        Divider()
        HStack(spacing: 30) {
          runTotal("Gross", selectedGross)
          runTotal("CIS", selectedCIS)
          runTotal("Net", selectedNet)
          Spacer()
          if runStep == 1 {
            Button("Approve submitted run") { updateSelectedRun(to: .scheduled) }.buttonStyle(.borderedProminent).tint(.orange).disabled(selectedRunSummaries.isEmpty || selectedRunSummaries.contains(where: { missingBankDetails($0.user) || $0.status == .due }))
          } else if runStep == 2 {
            Button("Mark paid") { updateSelectedRun(to: .paid) }.buttonStyle(.borderedProminent).tint(.green)
          } else {
            Label("Run paid", systemImage: "checkmark.circle.fill").foregroundStyle(.green).fontWeight(.semibold)
          }
        }.padding(16)
      }.frame(maxWidth: .infinity, minHeight: 500, maxHeight: 500).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func workerRunRow(_ summary: RunSummary) -> some View {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Button {
            withAnimation(.easeInOut(duration: 0.18)) { expandedWorkerID = expandedWorkerID == summary.user.id ? nil : summary.user.id }
          } label: {
            HStack(spacing: 12) {
              Circle().fill(Color.orange.opacity(0.13)).frame(width: 42, height: 42).overlay(Text(initials(summary.user.name)).font(.caption.bold()).foregroundStyle(.orange))
              VStack(alignment: .leading, spacing: 3) {
                Text(summary.user.name).fontWeight(.semibold)
                Text("\(summary.days.formatted()) days · \(workerEntries(summary.user).count) entries · CIS \(summary.rate)%").font(.caption).foregroundStyle(.secondary)
                Label(summary.status == .due ? "Not submitted" : summary.status.displayName, systemImage: summary.status == .due ? "clock" : "checkmark.circle.fill")
                  .font(.caption2.bold()).foregroundStyle(summary.status == .due ? Color.secondary : Color.green)
              }
              Image(systemName: expandedWorkerID == summary.user.id ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
            }
          }.buttonStyle(.plain)
          Spacer()
          Text(summary.net, format: .currency(code: "GBP")).fontWeight(.bold).frame(width: 100, alignment: .trailing)
          if missingBankDetails(summary.user) {
            Button("Missing bank details") { editingWorker = summary.user }.buttonStyle(.bordered).tint(.red)
          } else {
            Label(summary.status.displayName, systemImage: summary.status == .due ? "clock" : "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(summary.status == .paid ? .green : summary.status == .scheduled ? .blue : summary.status == .submitted ? .orange : .secondary).frame(width: 105, alignment: .leading)
          }
          Menu { Button("Edit payment details") { editingWorker = summary.user }; Button("Log work day") { quickEntry = QuickTimesheet(userID: summary.user.id, date: defaultEntryDate) } } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
        }.padding(.horizontal, 16).frame(height: 68)
        if expandedWorkerID == summary.user.id { workerDayDetails(summary) }
        Divider()
      }
    }
    private func workerEntries(_ user: CRMUser) -> [TimesheetEntry] { weekEntries.filter { $0.userID == user.id }.sorted { $0.date < $1.date } }
    private func adminEntries(_ user: CRMUser) -> [TimesheetEntry] { adminWeekEntries.filter { $0.userID == user.id }.sorted { $0.date < $1.date } }
    private func timesheetCopiesMatch(_ user: CRMUser) -> Bool {
      let worker = workerEntries(user).map { "\($0.date)|\($0.leadID)|\($0.type)|\(String(format: "%.2f", $0.amount))" }
      let office = adminEntries(user).map { "\($0.date)|\($0.leadID)|\($0.type)|\(String(format: "%.2f", $0.amount))" }
      return !worker.isEmpty && worker == office
    }
    private func copyStatus(_ user: CRMUser) -> String {
      adminEntries(user).isEmpty ? "No office copy yet" : timesheetCopiesMatch(user) ? "Matches office copy" : "Does not match office copy"
    }
    private func workerDayDetails(_ summary: RunSummary) -> some View {
      VStack(spacing: 0) {
        HStack {
          Text("DAY").frame(width: 90, alignment: .leading)
          Text("JOB").frame(maxWidth: .infinity, alignment: .leading)
          Text("TIME").frame(width: 85, alignment: .leading)
          Text("AMOUNT").frame(width: 90, alignment: .trailing)
          Text("").frame(width: 58)
        }.font(.caption2.bold()).foregroundStyle(.secondary).padding(.horizontal, 24).frame(height: 30)
        ForEach(workerEntries(summary.user)) { entry in
          HStack {
            Text((SupabaseService.date(from: entry.date) ?? .now).formatted(.dateTime.weekday(.abbreviated).day())).frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
              let lead = appState.leads.first { $0.id == entry.leadID }
              Text(lead?.name ?? "Unknown job").fontWeight(.medium)
              Text(lead?.jobRef ?? entry.leadID).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.type == "half" ? "Half day" : entry.type == "off" ? "Off" : "Full day").frame(width: 85, alignment: .leading)
            Text(entry.amount, format: .currency(code: "GBP")).frame(width: 90, alignment: .trailing)
            Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.secondary).frame(width: 58)
          }.font(.caption).padding(.horizontal, 24).frame(height: 49).background(Color.secondary.opacity(0.035)).overlay(alignment: .bottom) { Divider().padding(.leading, 24) }
        }
        Button { quickEntry = QuickTimesheet(userID: summary.user.id, date: defaultEntryDate) } label: { Label("Add to office copy", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.orange).padding(.vertical, 10)
      }.background(Color.secondary.opacity(0.025))
    }
    private func runTotal(_ title: String, _ value: Double) -> some View { VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value, format: .currency(code: "GBP")).fontWeight(.bold) } }
    private var defaultEntryDate: Date {
      let today = Calendar.current.startOfDay(for: .now)
      return today >= weekStart && today <= weekEnd ? today : weekStart
    }
    private func weekRangeLabel(_ start: Date) -> String {
      let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
      return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    private func initials(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
    private func missingBankDetails(_ user: CRMUser) -> Bool { (user.bankAccountNumber ?? "").isEmpty || (user.bankSortCode ?? "").isEmpty }
    private func weekStatus(_ summaries: [RunSummary]) -> String { summaries.isEmpty ? "Empty" : summaries.allSatisfy { $0.status == .paid } ? "Paid" : summaries.allSatisfy { $0.status == .scheduled || $0.status == .paid } ? "Approved" : summaries.contains { $0.status == .submitted } ? "Submitted" : "In progress" }
    private func weekStatusColor(_ summaries: [RunSummary]) -> Color { summaries.allSatisfy { $0.status == .paid } && !summaries.isEmpty ? .green : summaries.allSatisfy { $0.status != .due } && !summaries.isEmpty ? .blue : .orange }
    private func updateSelectedRun(to status: PaymentStatus) { Task { for summary in selectedRunSummaries { await appState.setPaymentStatus(userID: summary.user.id, weekStart: summary.weekStart, status: status) } } }

    private var timesheets: some View {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 14) {
            Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart)! } label: { Image(systemName: "chevron.left") }
              .buttonStyle(.bordered).controlSize(.large)
            VStack(alignment: .leading, spacing: 5) {
              Text("\(weekStart.formatted(.dateTime.day().month(.wide))) – \(weekEnd.formatted(.dateTime.day().month(.wide).year()))").font(.title2.bold())
              Text("Monday to Friday · pay run due next Friday").font(.callout).foregroundStyle(.secondary)
            }
            Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)! } label: { Image(systemName: "chevron.right") }
              .buttonStyle(.bordered).controlSize(.large)
            Spacer()
          }
          HStack(spacing: 14) {
            timesheetSummaryMetric("DAYS RECORDED", PayrollMath.days(weekEntries).formatted(), .primary)
            timesheetSummaryMetric("BEFORE TAX", PayrollMath.gross(weekEntries).formatted(.currency(code: "GBP").precision(.fractionLength(0))), .orange)
            timesheetSummaryMetric("AFTER TAX", weekNet.formatted(.currency(code: "GBP").precision(.fractionLength(0))), .green)
            Spacer(minLength: 0)
          }
        }.padding(20).background(Color.orange.opacity(0.045), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.22)))
        VStack(spacing: 0) {
          HStack(spacing: 0) {
            Text("TEAM MEMBER").frame(width: 190, alignment: .leading)
            ForEach(0..<5, id: \.self) { offset in
              let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart)!
              VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.wide))).lineLimit(1)
                Text(date.formatted(.dateTime.day())).font(.headline).foregroundStyle(Calendar.current.isDateInToday(date) ? Color.orange : Color.primary)
              }.frame(maxWidth: .infinity)
            }
            Text("BEFORE TAX").frame(width: 100, alignment: .trailing)
            Text("AFTER TAX").frame(width: 100, alignment: .trailing)
          }
          .font(.caption2.bold()).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 58).background(Color.secondary.opacity(0.035)).overlay(alignment: .bottom) { Divider() }
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(workers) { user in workerRow(user) }
              if workers.isEmpty {
                ContentUnavailableView("No team members", systemImage: "person.2", description: Text("Create worker accounts in Settings first."))
                  .frame(minHeight: 220)
              }
            }
          }
          HStack {
            Text("Click a day to add, edit or remove work.")
            Spacer()
            Text("After tax uses the worker’s CIS rate.")
          }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 48).background(Color.secondary.opacity(0.025)).overlay(alignment: .top) { Divider() }
        }.background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary)).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.035), radius: 10, y: 3)
      }.frame(maxHeight: .infinity, alignment: .top)
    }
    private func timesheetSummaryMetric(_ title: String, _ value: String, _ colour: Color) -> some View {
      VStack(alignment: .leading, spacing: 7) {
        Text(title).font(.caption.bold()).foregroundStyle(.secondary)
        Text(value).font(.system(size: 24, weight: .semibold)).foregroundStyle(colour)
      }.padding(14).frame(width: 210, alignment: .leading).frame(minHeight: 78).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func workerRow(_ user: CRMUser) -> some View {
      let entries = weekEntries.filter { $0.userID == user.id }
      let gross = PayrollMath.gross(entries)
      let net = PayrollMath.net(gross, rate: user.cisRate ?? 20)
      return HStack(spacing: 0) {
        Button {
          editingWorker = user
        } label: {
          HStack {
            Circle().fill(Color.orange.opacity(0.12)).frame(width: 34, height: 34).overlay(
              Text(user.name.prefix(1)).font(.caption.bold()).foregroundStyle(.orange))
            VStack(alignment: .leading) {
              Text(user.name).fontWeight(.semibold)
              Text((user.dayRate ?? 0).formatted(.currency(code: "GBP")) + "/day · CIS \(user.cisRate ?? 20)%").font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
        }.buttonStyle(.plain).frame(width: 190)
        ForEach(0..<5, id: \.self) { offset in
          let date = PayrollMath.key(
            Calendar.current.date(byAdding: .day, value: offset, to: weekStart)!)
          if let entry = entries.first(where: { $0.date == date }) {
            let job = appState.leads.first { $0.id == entry.leadID }
            Button { editingEntry = entry } label: {
              VStack(spacing: 2) {
                Text(entry.type == "half" ? "½ day" : entry.type == "off" ? "Off" : "1 day").font(.headline)
                Text(entry.type == "off" ? "Not working" : job?.name ?? "Unknown job").font(.caption2.bold()).lineLimit(1)
                if entry.type != "off", let reference = job?.jobRef { Text(reference).font(.system(size: 8)).lineLimit(1) }
              }.foregroundStyle(entry.type == "off" ? Color.secondary : Color.orange).frame(maxWidth: .infinity, minHeight: 54).background(
                entry.type == "off" ? Color.secondary.opacity(0.07) : Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9)
              ).overlay(RoundedRectangle(cornerRadius: 9).stroke(entry.type == "off" ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.16))).padding(.horizontal, 4)
            }.buttonStyle(.plain).contextMenu {
              Button("Edit entry") { editingEntry = entry }
              Button("Delete", role: .destructive) { Task { await appState.deleteTimesheet(entry) } }
            }.help(entry.type == "off" ? "Not working" : "\(job?.name ?? "Unknown job") · \(job?.jobRef ?? "No reference")")
          } else {
            Button { quickEntry = QuickTimesheet(userID: user.id, date: Calendar.current.date(byAdding: .day, value: offset, to: weekStart)!) } label: {
              VStack(spacing: 3) { Image(systemName: "plus"); Text("Add day").font(.caption2) }.foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 54).background(Color.secondary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.10))).padding(.horizontal, 4)
            }.buttonStyle(.plain).help("Add \(user.name)'s time for \(date)")
          }
        }
        Text(gross, format: .currency(code: "GBP").precision(.fractionLength(0)))
          .fontWeight(.semibold).frame(width: 100, alignment: .trailing)
        Text(net, format: .currency(code: "GBP").precision(.fractionLength(0)))
          .fontWeight(.bold).foregroundStyle(.green).frame(width: 100, alignment: .trailing)
      }.padding(.horizontal, 18).frame(height: 76).overlay(alignment: .bottom) { Divider().padding(.leading, 18) }
    }

    private var balances: some View {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(workerBalances, id: \.user.id) { summary in
            VStack(spacing: 12) {
              HStack {
                Circle().fill(Color.orange.opacity(0.12)).frame(width: 44, height: 44).overlay(
                  Text(summary.user.name.prefix(1)).font(.headline).foregroundStyle(.orange))
                VStack(alignment: .leading) {
                  Text(summary.user.name).font(.headline)
                  Text(
                    "\(summary.gross.formatted(.currency(code: "GBP"))) gross · CIS \(summary.rate)%"
                  ).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                  Text(
                    summary.balance <= 0.01
                      ? "All paid" : "Owes \(summary.balance.formatted(.currency(code: "GBP")))"
                  ).font(.title3.bold()).foregroundStyle(summary.balance <= 0.01 ? .green : .orange)
                  Text("\(summary.paid.formatted(.currency(code: "GBP"))) paid").font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button("Pay") { payingWorker = summary.user }.buttonStyle(.borderedProminent)
                Button {
                  editingWorker = summary.user
                } label: {
                  Image(systemName: "pencil")
                }
              }
              ProgressView(value: min(summary.paid, summary.earned), total: max(1, summary.earned))
                .tint(.green)
              if !summary.payments.isEmpty {
                DisclosureGroup("\(summary.payments.count) payments") {
                  ForEach(summary.payments) { payment in
                    HStack {
                      Text(payment.date)
                      Text(payment.notes ?? "Payment").foregroundStyle(.secondary)
                      Spacer()
                      Text(payment.amount, format: .currency(code: "GBP"))
                      Button(role: .destructive) {
                        Task { await appState.deleteWorkerPayment(payment) }
                      } label: {
                        Image(systemName: "trash")
                      }.buttonStyle(.plain)
                    }.padding(.vertical, 5)
                  }
                }
              }
            }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(
              RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
          }
          if workerBalances.isEmpty {
            ContentUnavailableView(
              "No worker balances", systemImage: "wallet.pass",
              description: Text("Balances appear after timesheets are logged."))
          }
        }.padding(.horizontal, 24).padding(.bottom, 24)
      }
    }
    private var runs: some View {
      ScrollView {
        VStack(spacing: 16) {
          HStack(spacing: 12) {
            PayrollStatusMetric(
              "Due", runSummaries.filter { $0.status == .due }.reduce(0) { $0 + $1.net }, .orange)
            PayrollStatusMetric(
              "Scheduled",
              runSummaries.filter { $0.status == .scheduled }.reduce(0) { $0 + $1.net }, .blue)
            PayrollStatusMetric(
              "Paid", runSummaries.filter { $0.status == .paid }.reduce(0) { $0 + $1.net }, .green)
          }
          VStack(spacing: 0) {
            ForEach(runSummaries, id: \.id) { summary in
              HStack {
                Circle().fill(statusColor(summary.status).opacity(0.12)).frame(
                  width: 40, height: 40
                ).overlay(
                  Text(summary.user.name.prefix(1)).fontWeight(.bold).foregroundStyle(
                    statusColor(summary.status)))
                VStack(alignment: .leading) {
                  Text(summary.user.name).fontWeight(.semibold)
                  Text("Week of \(summary.weekStart) · \(summary.days.formatted()) days").font(
                    .caption
                  ).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                  Text(summary.net, format: .currency(code: "GBP")).fontWeight(.bold)
                  Text(
                    "\(summary.gross.formatted(.currency(code: "GBP"))) gross · CIS \(summary.rate)%"
                  ).font(.caption).foregroundStyle(.secondary)
                }
                Menu(summary.status.displayName) {
                  ForEach(PaymentStatus.allCases) { state in
                    Button(state.displayName) {
                      if state == .paid { pendingPaidRunID = summary.id }
                      else { Task { await appState.setPaymentStatus(userID: summary.user.id, weekStart: summary.weekStart, status: state) } }
                    }
                  }
                }.frame(width: 110)
              }.padding(14).overlay(alignment: .bottom) { Divider() }
            }
          }.background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(
            RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
          if runSummaries.isEmpty {
            ContentUnavailableView(
              "No payment runs", systemImage: "banknote",
              description: Text("Weekly runs appear after timesheets are logged."))
          }
        }.padding(.horizontal, 24).padding(.bottom, 24)
      }
    }

    private var workerBalances: [WorkerBalance] {
      Array(Set(appState.timesheets.map(\.userID))).compactMap { id in
        guard let user = appState.users.first(where: { $0.id == id }) else { return nil }
        let entries = appState.timesheets.filter { $0.userID == id }
        let gross = PayrollMath.gross(entries)
        let rate = user.cisRate ?? 20
        let earned = PayrollMath.net(gross, rate: rate)
        let payments = appState.workerPayments.filter { $0.userID == id }.sorted {
          $0.date > $1.date
        }
        let paid = payments.reduce(0) { $0 + $1.amount }
        return WorkerBalance(
          user: user, gross: gross, rate: rate, earned: earned, paid: paid, balance: earned - paid,
          payments: payments)
      }.sorted { $0.user.name < $1.user.name }
    }
    private var runSummaries: [RunSummary] {
      let grouped = Dictionary(grouping: appState.timesheets) { entry in
        "\(entry.userID)|\(PayrollMath.key(PayrollMath.monday(for: SupabaseService.date(from: entry.date) ?? .now)))"
      }
      return grouped.compactMap { key, entries in
        let parts = key.split(separator: "|").map(String.init)
        guard parts.count == 2, let user = appState.users.first(where: { $0.id == parts[0] }) else {
          return nil
        }
        let gross = PayrollMath.gross(entries)
        let rate = user.cisRate ?? 20
        let run = appState.paymentRuns.first { $0.userID == user.id && $0.weekStart == parts[1] }
        return RunSummary(
          id: key, user: user, weekStart: parts[1], days: PayrollMath.days(entries), gross: gross,
          rate: rate, net: PayrollMath.net(gross, rate: rate), status: run?.status ?? .due)
      }.sorted { $0.weekStart > $1.weekStart }
    }
    private func statusColor(_ status: PaymentStatus) -> Color {
      switch status {
      case .due: .orange
      case .submitted: .purple
      case .scheduled: .blue
      case .paid: .green
      }
    }
  }

  private struct WorkerBalance {
    let user: CRMUser
    let gross: Double
    let rate: Int
    let earned: Double
    let paid: Double
    let balance: Double
    let payments: [WorkerPayment]
  }
  private struct QuickTimesheet: Identifiable { let id = UUID(); let userID: String; let date: Date }
  private struct RunSummary {
    let id: String
    let user: CRMUser
    let weekStart: String
    let days: Double
    let gross: Double
    let rate: Int
    let net: Double
    let status: PaymentStatus
  }
  private struct PayrollPill: View {
    let title, value: String
    let tint: Color
    init(_ title: String, _ value: String, _ tint: Color) {
      self.title = title
      self.value = value
      self.tint = tint
    }
    var body: some View {
      VStack(alignment: .leading) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).fontWeight(.bold).foregroundStyle(tint)
      }.padding(.horizontal, 12).padding(.vertical, 7).background(
        tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
  }
  private struct PayrollStatusMetric: View {
    let title: String
    let value: Double
    let tint: Color
    init(_ title: String, _ value: Double, _ tint: Color) {
      self.title = title
      self.value = value
      self.tint = tint
    }
    var body: some View {
      VStack(alignment: .leading) {
        Text(title).foregroundStyle(tint)
        Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(
          .title2.bold())
      }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
        tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private struct WorkerPaymentDetailsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let user: CRMUser
    @State private var dayRate = 0.0
    @State private var cisRate = 20
    @State private var utr = ""
    @State private var bank = ""
    @State private var account = ""
    @State private var sortCode = ""
    @State private var isSaving = false
    var body: some View {
      NavigationStack {
        Form {
          Section("Pay") {
            TextField("Day rate", value: $dayRate, format: .number)
            Picker("CIS rate", selection: $cisRate) {
              Text("20%").tag(20)
              Text("30%").tag(30)
            }
            TextField("UTR number", text: $utr)
          }
          Section("Bank details") {
            TextField("Bank", text: $bank)
            TextField("Account number", text: $account)
            TextField("Sort code", text: $sortCode)
          }
        }.disabled(isSaving).navigationTitle("Payment details").toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              var changed = user
              changed.dayRate = dayRate
              changed.cisRate = cisRate
              changed.utrNumber = utr
              changed.bankName = bank
              changed.bankAccountNumber = account
              changed.bankSortCode = sortCode
              Task {
                isSaving = true
                defer { isSaving = false }
                if await appState.saveWorkerProfile(changed) { dismiss() }
              }
            }.disabled(dayRate < 0 || isSaving)
          }
        }
      }.frame(minWidth: 440, minHeight: 420).onAppear {
        dayRate = user.dayRate ?? 0
        cisRate = user.cisRate ?? 20
        utr = user.utrNumber ?? ""
        bank = user.bankName ?? ""
        account = user.bankAccountNumber ?? ""
        sortCode = user.bankSortCode ?? ""
      }
    }
  }

  private struct LogWorkerPaymentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let user: CRMUser
    @State private var amount = 0.0
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    var body: some View {
      NavigationStack {
        Form {
          TextField("Amount", value: $amount, format: .number)
          DatePicker("Payment date", selection: $date, displayedComponents: .date)
          TextField("Notes", text: $notes, axis: .vertical)
        }.disabled(isSaving).navigationTitle("Pay \(user.name)").toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save payment") {
              Task {
                isSaving = true
                defer { isSaving = false }
                if await appState.addWorkerPayment(
                  userID: user.id, amount: amount, date: PayrollMath.key(date),
                  notes: notes.isEmpty ? nil : notes) { dismiss() }
              }
            }.disabled(amount <= 0 || isSaving)
          }
        }
      }.frame(minWidth: 420, minHeight: 320)
    }
  }
#endif

struct CISView: View {
  @Environment(AppState.self) private var appState
  @State private var month = Calendar.current.component(.month, from: .now)
  @State private var year = Calendar.current.component(.year, from: .now)
  @State private var exporting = false
  @State private var exportDocument = CISCSVDocument(text: "")
  private var entries: [TimesheetEntry] {
    appState.timesheets.filter {
      guard let date = SupabaseService.date(from: $0.date) else { return false }
      return Calendar.current.component(.month, from: date) == month
        && Calendar.current.component(.year, from: date) == year
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("CIS Returns").font(.system(size: 29, weight: .bold))
            Text("Monthly contractor deductions and payment statements.").foregroundStyle(
              .secondary)
          }
          Spacer()
          Picker("Month", selection: $month) {
            ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
          }.frame(width: 150)
          Picker("Year", selection: $year) {
            ForEach((year - 3)...(year + 1), id: \.self) { Text(String($0)).tag($0) }
          }.frame(width: 90)
          Button { prepareExport() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).disabled(rows.isEmpty)
        }
        HStack(spacing: 12) {
          CISMetric("Gross labour", totalGross, .blue)
          CISMetric("CIS deducted", totalDeduction, .red)
          CISMetric("Net payable", totalNet, .green)
          CISMetric("Contractors", Double(rows.count), .orange, currency: false)
        }
        VStack(spacing: 0) {
          HStack {
            Text("Contractor").frame(maxWidth: .infinity, alignment: .leading)
            Text("UTR").frame(width: 140, alignment: .leading)
            Text("Days").frame(width: 60, alignment: .trailing)
            Text("Gross").frame(width: 100, alignment: .trailing)
            Text("CIS").frame(width: 100, alignment: .trailing)
            Text("Net").frame(width: 100, alignment: .trailing)
          }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 16).frame(
            height: 42
          ).background(.background).overlay(alignment: .bottom) { Divider() }
          ForEach(rows, id: \.user.id) { row in
            CISContractorDisclosure(row: row, leads: appState.leads)
          }
          if rows.isEmpty {
            ContentUnavailableView(
              "No CIS activity", systemImage: "doc.text",
              description: Text("Timesheet entries for CIS workers will appear here."))
          }
        }.background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(
          RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
        Text(
          "Verify contractor status and submit the monthly CIS return to HMRC by the applicable deadline. Figures are calculated from recorded timesheets and each worker’s configured CIS rate."
        ).font(.caption).foregroundStyle(.secondary)
      }.padding(24)
    }.navigationTitle("CIS").fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: String(format: "ProLine-CIS-%04d-%02d", year, month)) { result in if case .failure = result { appState.errorMessage = "The CIS report could not be exported." } }
  }
  private func prepareExport() {
    let period = String(format: "%04d-%02d", year, month)
    var lines = ["period,contractor,utr,cis_rate,days,gross_labour,cis_deducted,net_payable"]
    lines += rows.map { row in
      [period, row.user.name, row.user.utrNumber ?? "", "\(row.user.cisRate ?? 20)", row.days.formatted(), String(format: "%.2f", row.gross), String(format: "%.2f", row.deduction), String(format: "%.2f", row.net)].map(csvField).joined(separator: ",")
    }
    lines.append([period, "TOTAL", "", "", "", String(format: "%.2f", totalGross), String(format: "%.2f", totalDeduction), String(format: "%.2f", totalNet)].map(csvField).joined(separator: ","))
    exportDocument = CISCSVDocument(text: lines.joined(separator: "\n"))
    exporting = true
  }
  private func csvField(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
  private var rows: [CISRow] {
    Array(Set(entries.map(\.userID))).compactMap { id in
      guard let user = appState.users.first(where: { $0.id == id }) else { return nil }
      let workerEntries = entries.filter { $0.userID == id }
      let gross = PayrollMath.gross(workerEntries)
      let rate = user.cisRate ?? 20
      let deduction = gross * Double(rate) / 100
      return CISRow(
        user: user, entries: workerEntries, days: PayrollMath.days(workerEntries), gross: gross,
        deduction: deduction, net: gross - deduction)
    }.sorted { $0.user.name < $1.user.name }
  }
  private var totalGross: Double { rows.reduce(0) { $0 + $1.gross } }
  private var totalDeduction: Double { rows.reduce(0) { $0 + $1.deduction } }
  private var totalNet: Double { rows.reduce(0) { $0 + $1.net } }
}
private struct CISCSVDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.commaSeparatedText] }
  var text: String
  init(text: String) { self.text = text }
  init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
private struct CISRow {
  let user: CRMUser
  let entries: [TimesheetEntry]
  let days, gross, deduction, net: Double
}
private struct CISContractorDisclosure: View {
  let row: CISRow
  let leads: [Lead]
  private var utr: String {
    guard let value = row.user.utrNumber, !value.isEmpty else { return "Not set" }
    return value
  }
  var body: some View {
    DisclosureGroup {
      VStack(spacing: 0) {
        ForEach(row.entries.sorted { $0.date < $1.date }) { entry in
          CISEntryRow(
            entry: entry,
            jobRef: leads.first(where: { $0.id == entry.leadID })?.jobRef ?? "Job")
        }
      }.padding(.horizontal, 16)
    } label: {
      HStack {
        Text(row.user.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
        Text(utr).foregroundStyle(utr == "Not set" ? Color.red : Color.primary).frame(
          width: 140, alignment: .leading)
        Text(row.days.formatted()).frame(width: 60, alignment: .trailing)
        Text(row.gross, format: .currency(code: "GBP")).frame(width: 100, alignment: .trailing)
        Text(row.deduction, format: .currency(code: "GBP")).foregroundStyle(.red).frame(
          width: 100, alignment: .trailing)
        Text(row.net, format: .currency(code: "GBP")).fontWeight(.bold).frame(
          width: 100, alignment: .trailing)
      }.padding(.horizontal, 16).frame(height: 58)
    }.padding(.horizontal, 0).overlay(alignment: .bottom) { Divider() }
  }
}
private struct CISEntryRow: View {
  let entry: TimesheetEntry
  let jobRef: String
  var body: some View {
    HStack {
      Text(entry.date); Text(jobRef); Spacer()
      Text(entry.type == "half" ? "Half day" : entry.type == "off" ? "Off" : "Full day")
      Text(entry.amount, format: .currency(code: "GBP"))
    }.font(.caption).padding(.vertical, 6)
  }
}
private struct CISMetric: View {
  let title: String
  let value: Double
  let tint: Color
  let currency: Bool
  init(_ title: String, _ value: Double, _ tint: Color, currency: Bool = true) {
    self.title = title
    self.value = value
    self.tint = tint
    self.currency = currency
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      if currency {
        Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(
          .title2.bold()
        ).foregroundStyle(tint)
      } else {
        Text(Int(value).description).font(.title2.bold()).foregroundStyle(tint)
      }
    }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
      .background, in: RoundedRectangle(cornerRadius: 10)
    ).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
  }
}
