import SwiftUI

struct AccountsWorkspaceView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", finance = "Money", reports = "Reports", timesheets = "Timesheets", cis = "CIS", handover =
            "Accountant handover";
        var id: String { rawValue }
    }
    @Environment(AppState.self) private var appState
    @State private var tab: Tab = .overview
    @State private var exporting = false
    @State private var exportDocument = CRMCSVDocument(text: "")
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Payments, payroll, CIS and accountant records in one place.").foregroundStyle(.secondary)
                }; Spacer();
                if tab == .handover {
                    Button {
                        prepareHandover()
                    } label: {
                        Label("Export accountant CSV", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            #if os(macOS)
                Picker("Accounts section", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            #else
                Picker("Accounts section", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                    .padding(.horizontal, 20).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
            #endif
            Divider()
            switch tab {
            case .overview: accountsOverview;
            case .finance: FinanceCentreView();
            case .reports: ReportsView();
            case .timesheets: TimesheetView();
            case .cis: CISView();
            case .handover: accountantHandover
            }
        }.navigationTitle("Accounts").fileExporter(
            isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
            defaultFilename: "ProLine-Accountant-Handover-\(SupabaseService.today)"
        ) { result in if case .failure = result { appState.errorMessage = "The accountant export could not be saved." } }
    }
    private var activeJobs: [Lead] {
        appState.leads.filter { [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains($0.stage) }
    }
    private var collected: Double { activeJobs.reduce(0) { $0 + max(0, $1.value - $1.balance) } }
    private var due: Double { activeJobs.reduce(0) { $0 + max(0, $1.balance) } }
    private var payroll: Double { appState.timesheets.reduce(0) { $0 + $1.amount } }
    private var accountsOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    accountMetric("Customer money in", collected, "arrow.down.circle.fill", .green);
                    accountMetric("Customer money due", due, "clock.badge.exclamationmark.fill", Color.accentColor);
                    accountMetric("Labour recorded", payroll, "person.2.fill", .blue);
                    accountMetric(
                        "Deposits waiting", activeJobs.filter { !$0.depositPaid && $0.deposit > 0 }.reduce(0) { $0 + $1.deposit },
                        "creditcard.fill", .red)
                };
                VStack(alignment: .leading, spacing: 12) {
                    Text("Simple weekly routine").font(.title3.bold());
                    routine("1", "Record deposits", "Open Money and mark customer deposits when they arrive.");
                    routine("2", "Approve timesheets", "Check worker days, rates and job references before payment.");
                    routine("3", "Check CIS", "Review deductions and export the monthly contractor return.");
                    routine("4", "Send to accountant", "Export the handover CSV containing jobs, money, wages and payment details.")
                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }.padding(24)
        }
    }
    private func accountMetric(_ title: String, _ value: Double, _ icon: String, _ colour: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary).frame(width: 44, height: 44);
            VStack(alignment: .leading) {
                Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(.title2.bold());
                Text(title).font(.caption).foregroundStyle(.secondary)
            }; Spacer()
        }.padding(15).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
    private func routine(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline).foregroundStyle(.white).frame(width: 28, height: 28).background(Color.accentColor, in: Circle());
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var accountantHandover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Accountant-ready export", systemImage: "building.columns.fill").font(.title2.bold()).foregroundStyle(
                    Color.accentColor);
                Text(
                    "One CSV includes customer job values, deposits, outstanding balances, timesheets and worker payments. Your accountant can filter the record_type column or import each group into their software."
                ).foregroundStyle(.secondary);
                VStack(alignment: .leading, spacing: 10) {
                    handoverLine("Customer jobs", "\(appState.leads.count) records");
                    handoverLine("Timesheet entries", "\(appState.timesheets.count) records");
                    handoverLine("Worker payments", "\(appState.workerPayments.count) records")
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(.quaternary));
                Button {
                    prepareHandover()
                } label: {
                    Label("Export accountant handover", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }.frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    private func handoverLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title); Spacer(); Text(value).foregroundStyle(.secondary)
        }
    }
    private func prepareHandover() {
        var rows = ["record_type,date,reference,name,description,gross_amount,deposit,paid_or_deducted,balance,status,notes"];
        rows += appState.leads.map {
            csvRow([
                "job", $0.createdAt, $0.jobRef, $0.name, $0.jobType, money($0.value), money($0.deposit), $0.depositPaid ? "yes" : "no",
                money($0.balance), $0.stage.rawValue, $0.address,
            ])
        };
        rows += appState.timesheets.map { entry in
            let worker = appState.users.first { $0.id == entry.userID }; let job = appState.leads.first { $0.id == entry.leadID };
            return csvRow([
                "timesheet", entry.date, job?.jobRef ?? entry.leadID, worker?.name ?? entry.userID, entry.type, money(entry.amount), "", "",
                "", "recorded", "",
            ])
        };
        rows += appState.workerPayments.map { payment in
            let worker = appState.users.first { $0.id == payment.userID };
            return csvRow([
                "worker_payment", payment.date, payment.id, worker?.name ?? payment.userID, "Worker payment", money(payment.amount), "",
                "yes", "", "paid", payment.notes ?? "",
            ])
        }; exportDocument = CRMCSVDocument(text: rows.joined(separator: "\n")); exporting = true
    }
    private func money(_ value: Double) -> String { String(format: "%.2f", value) }
    private func csvRow(_ values: [String]) -> String {
        values.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
    }
}
