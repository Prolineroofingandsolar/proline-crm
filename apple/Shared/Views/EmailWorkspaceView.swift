import SwiftUI

struct EmailWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var scanning = false
    @State private var scanSummary: String?
    private var emailTasks: [GeneralTask] {
        appState.visibleGeneralTasks.filter { $0.category.caseInsensitiveCompare("Email") == .orderedSame }
            .sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gmail assistant").font(.largeTitle.bold());
                        Text("Important messages, follow-ups and prepared Gmail drafts.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        scan()
                    } label: {
                        if scanning { ProgressView() } else { Label("Scan now", systemImage: "arrow.clockwise") }
                    }.buttonStyle(.borderedProminent).disabled(scanning || appState.gmailConnectionStatus?.connected != true)
                }
                HStack(spacing: 12) {
                    emailMetric(
                        appState.gmailConnectionStatus?.connected == true ? "Connected" : "Not connected", "Gmail",
                        appState.gmailConnectionStatus?.connected == true ? .green : Color.accentColor)
                    emailMetric("\(emailTasks.filter { !$0.completed }.count)", "Open email actions", .blue)
                    emailMetric(
                        appState.gmailConnectionStatus?.lastScannedAt.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") }
                            ?? "Never", "Last scan", .gray)
                }
                if let address = appState.gmailConnectionStatus?.gmailAddress {
                    Label(address, systemImage: "envelope.fill").foregroundStyle(.secondary)
                }
                if let scanSummary { Label(scanSummary, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if appState.gmailConnectionStatus?.connected != true {
                    Button("Connect Gmail") { Task { if let url = await appState.gmailAuthorizationURL() { openURL(url) } } }.buttonStyle(
                        .borderedProminent)
                }
                Text("Email actions").font(.title2.bold())
                if emailTasks.isEmpty {
                    ContentUnavailableView(
                        "No email actions yet", systemImage: "envelope.open",
                        description: Text(
                            "Scan Gmail now. Important customer emails will appear here and in Tasks; suggested replies stay in Gmail Drafts."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(emailTasks) { task in
                            HStack(spacing: 13) {
                                Button {
                                    Task { await appState.toggleGeneralTask(task) }
                                } label: {
                                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(
                                        task.completed ? .green : Color.accentColor)
                                }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).fontWeight(.semibold).strikethrough(task.completed);
                                    Text(task.notes ?? "Created from Gmail").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer();
                                if let due = task.dueDate {
                                    Text(due).font(.caption.bold()).foregroundStyle(
                                        !task.completed && due < SupabaseService.today ? Color.red : Color.secondary)
                                }
                            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
                                RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                        }
                    }
                }
            }.padding(24)
        }.navigationTitle("Email").task { await appState.refreshGmailConnectionStatus() }
    }
    private func scan() {
        scanning = true;
        Task {
            let count = await appState.scanGmailNow(); await appState.refreshGmailConnectionStatus();
            scanSummary = count.map { "Scan complete · \($0) new action\($0 == 1 ? "" : "s")" }; scanning = false
        }
    }
    private func emailMetric(_ value: String, _ title: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
