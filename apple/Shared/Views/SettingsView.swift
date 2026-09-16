import SwiftUI
import UniformTypeIdentifiers

/// One settings screen for every platform. On Mac it is also the Settings window (⌘,).
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @AppStorage("businessName") private var businessName = "Proline Roofing & Solar Ltd"
    @AppStorage("businessPhone") private var businessPhone = ""
    @AppStorage("businessEmail") private var businessEmail = ""
    @AppStorage("businessAddress") private var businessAddress = ""
    @AppStorage("businessVAT") private var businessVAT = ""
    @AppStorage("notifySurveys") private var notifySurveys = true
    @AppStorage("notifyJobStarts") private var notifyJobStarts = true
    @AppStorage("notifyTasks") private var notifyTasks = true
    @AppStorage("notifyPayments") private var notifyPayments = true
    @AppStorage("notifyTeam") private var notifyTeam = true
    @State private var showingAddUser = false
    @State private var showingInviteWorker = false
    @State private var showingChangePassword = false
    @State private var exporting = false
    @State private var exportDocument = CRMCSVDocument(text: "")

    var body: some View {
        Form {
            if appState.isAdmin {
                Section {
                    TextField("Business name", text: $businessName)
                    TextField("Phone", text: $businessPhone)
                    TextField("Email", text: $businessEmail)
                    TextField("VAT number", text: $businessVAT)
                    TextField("Address", text: $businessAddress, axis: .vertical).lineLimit(2...4)
                } header: {
                    Text("Business details")
                } footer: {
                    Text("Printed on quotes. Stored on this device.")
                }

                Section {
                    ForEach(appState.users) { user in
                        LabeledContent(user.name) { Text(user.role.capitalized).foregroundStyle(.secondary) }
                    }
                    Button {
                        showingInviteWorker = true
                    } label: {
                        Label("Invite team member", systemImage: "paperplane")
                    }
                    Button {
                        showingAddUser = true
                    } label: {
                        Label("Add user", systemImage: "person.crop.circle.badge.plus")
                    }
                } header: {
                    Text("Team")
                } footer: {
                    Text("Invited workers choose their own password and enter their own pay, CIS and bank details.")
                }
            }

            Section {
                Toggle("Team messages", isOn: $notifyTeam)
                Toggle("Survey reminders", isOn: $notifySurveys)
                Toggle("Job starts", isOn: $notifyJobStarts)
                Toggle("Tasks due", isOn: $notifyTasks)
                if appState.isAdmin { Toggle("Customer payments", isOn: $notifyPayments) }
                Button("Enable notifications") { Task { await appState.enableNotifications() } }
                Button("Send test notification") { Task { await appState.sendTestNotification() } }
            } header: {
                Text("Notifications")
            } footer: {
                if UserDefaults.standard.string(forKey: "remotePushRegistrationIssue") != nil {
                    Text("Local reminders are working. Live push needs the App ID and provisioning profile refreshed in Apple Developer.")
                }
            }
            .onChange(of: [notifyTeam, notifySurveys, notifyJobStarts, notifyTasks, notifyPayments]) {
                Task { await appState.scheduleNotifications() }
            }

            if appState.isAdmin {
                Section {
                    if let status = appState.gmailConnectionStatus, status.connected {
                        LabeledContent("Gmail", value: status.gmailAddress ?? "Connected")
                    } else {
                        LabeledContent("Gmail", value: "Not connected")
                    }
                    Button(appState.gmailConnectionStatus?.connected == true ? "Reconnect Gmail" : "Connect Gmail") {
                        Task { if let url = await appState.gmailAuthorizationURL() { openURL(url) } }
                    }
                } header: {
                    Text("Gmail assistant")
                } footer: {
                    Text(
                        "Important customer emails become tasks and suggested replies are saved as Gmail drafts. Nothing is ever sent automatically."
                    )
                }

                Section("Data") {
                    Button("Export CRM data as CSV") { prepareExport() }
                }
            }

            Section("Account") {
                LabeledContent("Signed in as", value: appState.currentUser?.name ?? "—")
                Button("Change password…") { showingChangePassword = true }
                Button("Sign out", role: .destructive) { appState.signOut() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showingAddUser) { AddSecureUserSheet() }
        .sheet(isPresented: $showingInviteWorker) { InviteWorkerSheet() }
        .sheet(isPresented: $showingChangePassword) { ChangePasswordSheet() }
        .fileExporter(
            isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
            defaultFilename: "ProLine-CRM-Export-\(SupabaseService.today)"
        ) { result in
            if case .failure = result { appState.errorMessage = "The export could not be saved." }
        }
        .task { if appState.isAdmin { await appState.refreshGmailConnectionStatus() } }
    }

    private func prepareExport() {
        var lines = ["record_type,id,name,reference,status,value,date"]
        lines += appState.leads.map {
            "lead,\(csv($0.id)),\(csv($0.name)),\(csv($0.jobRef)),\(csv($0.stage.rawValue)),\($0.value),\(csv($0.updatedAt))"
        }
        lines += appState.contacts.map { "contact,\(csv($0.id)),\(csv($0.name)),,,0,\(csv($0.createdAt))" }
        lines += appState.visibleGeneralTasks.map {
            "task,\(csv($0.id)),\(csv($0.title)),,\($0.completed ? "completed" : "open"),0,\(csv($0.dueDate ?? ""))"
        }
        lines += appState.timesheets.map { entry in
            let worker = appState.users.first { $0.id == entry.userID }?.name ?? entry.userID
            return "timesheet,\(csv(entry.id)),\(csv(worker)),\(csv(entry.leadID)),\(csv(entry.type)),\(entry.amount),\(csv(entry.date))"
        }
        exportDocument = CRMCSVDocument(text: lines.joined(separator: "\n"))
        exporting = true
    }
    private func csv(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}

private struct ChangePasswordSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    var body: some View {
        NavigationStack {
            Form {
                SecureField("New password", text: $password).textContentType(.newPassword)
                SecureField("Confirm password", text: $confirm).textContentType(.newPassword)
                if !confirm.isEmpty && password != confirm { Text("Passwords do not match.").foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Change password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await appState.changePassword(password: password) { dismiss() } } }
                        .disabled(password.count < 8 || password != confirm)
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 220)
        #endif
    }
}
