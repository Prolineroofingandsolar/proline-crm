#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsView: View {
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
    @State private var selection = "Business"
    @State private var showingAddUser = false
    @State private var showingInviteWorker = false
    @State private var passwordUser: CRMUser?
    @State private var deletingUser: CRMUser?
    @State private var exporting = false
    @State private var exportDocument = CSVDocument(text: "")

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Settings").font(.system(size: 29, weight: .bold)).padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 12)
                ForEach([("Business", "building.2"), ("Accounts", "person.2"), ("Notifications", "bell"), ("Email automation", "envelope.badge"), ("Pipeline", "rectangle.3.group"), ("Data & Privacy", "lock.shield")], id: \.0) { item in
                    Button { selection = item.0 } label: { Label(item.0, systemImage: item.1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 38).background(selection == item.0 ? Color.orange.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(selection == item.0 ? .orange : .primary) }.buttonStyle(.plain)
                }
                Spacer()
                if let user = appState.currentUser { HStack { Circle().fill(Color.orange).frame(width: 34, height: 34).overlay(Text(user.name.prefix(1)).foregroundStyle(.white)); VStack(alignment: .leading) { Text(user.name).fontWeight(.semibold); Text(user.role.capitalized).font(.caption).foregroundStyle(.secondary) } }.padding(12) }
            }.frame(width: 205).padding(.horizontal, 10).background(Color(nsColor: .controlBackgroundColor))
            Divider()
            ScrollView { Group { switch selection { case "Accounts": accounts; case "Notifications": notifications; case "Email automation": emailAutomation; case "Pipeline": pipeline; case "Data & Privacy": privacy; default: business } }.frame(maxWidth: 820, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .topLeading) }
        }.navigationTitle("Settings").sheet(isPresented: $showingAddUser) { if KeychainStore.get("supabaseAccessToken") != nil { AddSecureUserSheet() } else { AddAccountSheet() } }.sheet(isPresented: $showingInviteWorker) { InviteWorkerSheet() }.sheet(item: $passwordUser) { ChangePasswordSheet(user: $0) }.confirmationDialog("Delete \(deletingUser?.name ?? "account")?", isPresented: Binding(get: { deletingUser != nil }, set: { if !$0 { deletingUser = nil } }), titleVisibility: .visible) { Button("Delete account", role: .destructive) { if let deletingUser { Task { await appState.deleteUser(deletingUser) }; self.deletingUser = nil } } }.fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "ProLine-CRM-Export-\(SupabaseService.today)") { result in if case .failure = result { appState.errorMessage = "The CSV export could not be saved." } }
    }

    private var business: some View { SettingsPage(title: "Business details", subtitle: "Used on customer documents and company communications.") { SettingsCard { Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) { GridRow { SettingsField("Business name", text: $businessName); SettingsField("Phone", text: $businessPhone) }; GridRow { SettingsField("Email", text: $businessEmail); SettingsField("VAT number", text: $businessVAT) }; GridRow { SettingsField("Address", text: $businessAddress, axis: .vertical).gridCellColumns(2) } }; HStack { Label("Changes save automatically on this Mac.", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green); Spacer() }.padding(.top, 8) } } }

    private var accounts: some View {
        let secureAuth = KeychainStore.get("supabaseAccessToken") != nil
        return SettingsPage(title: "Accounts", subtitle: "Manage who can use ProLine CRM and what they can access.") {
            HStack {
                Text("Team accounts").font(.headline); Spacer()
                if secureAuth && appState.isAdmin { Button { showingAddUser = true } label: { Label("Add user", systemImage: "person.crop.circle.badge.plus") }.buttonStyle(.borderedProminent).tint(.orange); Button { showingInviteWorker = true } label: { Label("Invite user", systemImage: "paperplane") }.buttonStyle(.bordered) }
                else if !secureAuth { Button { showingAddUser = true } label: { Label("Add account", systemImage: "plus") }.buttonStyle(.borderedProminent) }
            }
            if secureAuth { Label("Create a secure link and send it to the worker. They choose their password and enter their own pay, CIS and bank details; passwords are never visible to you.", systemImage: "lock.shield.fill").font(.callout).foregroundStyle(.secondary).padding(12).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }
            SettingsCard { VStack(spacing: 0) { ForEach(appState.users) { user in HStack { Circle().fill(user.role == "admin" ? Color.orange.opacity(0.12) : Color.blue.opacity(0.1)).frame(width: 42, height: 42).overlay(Text(user.name.prefix(1)).fontWeight(.bold).foregroundStyle(user.role == "admin" ? .orange : .blue)); VStack(alignment: .leading) { Text(user.name).fontWeight(.semibold); Text(user.username).font(.caption).foregroundStyle(.secondary) }; Text(user.role.capitalized).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()); Spacer(); if !secureAuth || user.id == appState.currentUser?.id { Button("Change password") { passwordUser = user } }; if !secureAuth && user.id != appState.currentUser?.id { Button(role: .destructive) { deletingUser = user } label: { Image(systemName: "trash") } } }.padding(.vertical, 11).overlay(alignment: .bottom) { Divider() } } } }
        }
    }

    private var notifications: some View { SettingsPage(title: "Native notifications", subtitle: "Choose which operational reminders appear in Notification Centre.") { SettingsCard { VStack(spacing: 14) { NotificationToggle("Team messages", "Notify me when another member of staff posts in Team Hub.", "bubble.left.and.bubble.right.fill", value: $notifyTeam); NotificationToggle("Survey reminders", "Morning reminder for every booked survey.", "calendar", value: $notifySurveys); NotificationToggle("Job starts", "Remind the team when scheduled work begins.", "hammer", value: $notifyJobStarts); NotificationToggle("Tasks due", "Morning reminders for incomplete CRM tasks.", "checklist", value: $notifyTasks); if appState.isAdmin { NotificationToggle("Payments", "One daily summary of deposits and completed-job balances to collect.", "sterlingsign.circle", value: $notifyPayments) } }.onChange(of: notifyTeam) { Task { await appState.scheduleNotifications() } }.onChange(of: notifySurveys) { Task { await appState.scheduleNotifications() } }.onChange(of: notifyJobStarts) { Task { await appState.scheduleNotifications() } }.onChange(of: notifyTasks) { Task { await appState.scheduleNotifications() } }.onChange(of: notifyPayments) { Task { await appState.scheduleNotifications() } } }; if UserDefaults.standard.string(forKey: "remotePushRegistrationIssue") != nil { Label("Local reminders are working. Live push updates need the Mac App ID and development profile refreshed in Apple Developer.", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }; HStack { Button("Enable notifications") { Task { await appState.enableNotifications() } }.buttonStyle(.borderedProminent); Button("Send test notification") { Task { await appState.sendTestNotification() } }.buttonStyle(.bordered) } } }

    private var pipeline: some View { SettingsPage(title: "Pipeline stages", subtitle: "The native workflow uses the same stages and automatic checklists as the web CRM.") { SettingsCard { VStack(spacing: 0) { ForEach(Array(LeadStage.allCases.enumerated()), id: \.element.id) { index, stage in HStack { Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 25, height: 25).background(stageColor(stage), in: Circle()); VStack(alignment: .leading) { Text(stage.displayName).fontWeight(.semibold); Text(stageDescription(stage)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(appState.leads.filter { $0.stage == stage }.count)").font(.caption.bold()).padding(6).background(.quaternary, in: Circle()) }.padding(.vertical, 9).overlay(alignment: .bottom) { Divider() } } } } } }

    private var privacy: some View { SettingsPage(title: "Data & Privacy", subtitle: "Export company data and review the current security state.") { SettingsCard { VStack(alignment: .leading, spacing: 12) { Label("Supabase live data", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Text("Leads, contacts, tasks, timesheets and payroll records are loaded from the shared Supabase project.").foregroundStyle(.secondary); Divider(); Label("Authentication migration required", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text("The compatibility login remains active until the web app and database are migrated together to Supabase Auth and row-level security.").foregroundStyle(.secondary); Button("Export CRM data as CSV") { prepareExport() }.buttonStyle(.bordered) } }; SettingsCard { HStack { VStack(alignment: .leading) { Text("Sign out").fontWeight(.semibold); Text("Clears locally cached CRM and widget data from this Mac.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Sign out", role: .destructive) { appState.signOut() } } } } }

    private func prepareExport() {
        var lines = ["record_type,id,name,reference,status,value,date"]
        lines += appState.leads.map { lead in
            "lead,\(csv(lead.id)),\(csv(lead.name)),\(csv(lead.jobRef)),\(csv(lead.stage.rawValue)),\(lead.value),\(csv(lead.updatedAt))"
        }
        lines += appState.contacts.map { contact in
            "contact,\(csv(contact.id)),\(csv(contact.name)),,,0,\(csv(contact.createdAt))"
        }
        lines += appState.visibleGeneralTasks.map { task in
            "task,\(csv(task.id)),\(csv(task.title)),,\(task.completed ? "completed" : "open"),0,\(csv(task.dueDate ?? ""))"
        }
        lines += appState.timesheets.map { entry in
            let workerName = appState.users.first { user in user.id == entry.userID }?.name ?? entry.userID
            return "timesheet,\(csv(entry.id)),\(csv(workerName)),\(csv(entry.leadID)),\(csv(entry.type)),\(entry.amount),\(csv(entry.date))"
        }
        exportDocument = CSVDocument(text: lines.joined(separator: "\n"))
        exporting = true
    }
    private func csv(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
    private func stageColor(_ stage: LeadStage) -> Color { switch stage { case .newLead: .blue; case .surveyBooked: .orange; case .quotePreparing, .quoteSent: .purple; case .won, .paid: .green; case .scheduled: .teal; case .inProgress: .cyan; case .completed: .mint; case .waitingForPayment: .indigo; case .lost: .gray } }
    private func stageDescription(_ stage: LeadStage) -> String { switch stage { case .newLead: "A new customer enquiry awaiting contact."; case .surveyBooked: "A roof survey has been arranged."; case .quotePreparing: "Measurements and pricing are being prepared."; case .quoteSent: "The customer has received a quotation."; case .won: "The customer accepted the work."; case .scheduled: "Dates, labour and materials are being planned."; case .inProgress: "Work is active on site."; case .completed: "Work is complete and retained for historical compatibility."; case .waitingForPayment: "Work is finished and the final balance is outstanding."; case .paid: "The account is fully settled."; case .lost: "The opportunity did not proceed." } }
}

private struct SettingsPage<Content: View>: View { let title, subtitle: String; @ViewBuilder let content: Content; init(title: String, subtitle: String, @ViewBuilder content: () -> Content) { self.title = title; self.subtitle = subtitle; self.content = content() }; var body: some View { VStack(alignment: .leading, spacing: 18) { VStack(alignment: .leading, spacing: 4) { Text(title).font(.title.bold()); Text(subtitle).foregroundStyle(.secondary) }; content }.frame(maxWidth: .infinity, alignment: .leading) } }
private struct SettingsCard<Content: View>: View { @ViewBuilder let content: Content; init(@ViewBuilder content: () -> Content) { self.content = content() }; var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary)) } }
private struct SettingsField: View { let title: String; @Binding var text: String; var axis: Axis = .horizontal; init(_ title: String, text: Binding<String>, axis: Axis = .horizontal) { self.title = title; _text = text; self.axis = axis }; var body: some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption.bold()).foregroundStyle(.secondary); TextField(title, text: $text, axis: axis).textFieldStyle(.roundedBorder) }.frame(maxWidth: .infinity) } }
private struct NotificationToggle: View { let title, detail, icon: String; @Binding var value: Bool; init(_ title: String, _ detail: String, _ icon: String, value: Binding<Bool>) { self.title = title; self.detail = detail; self.icon = icon; _value = value }; var body: some View { Toggle(isOn: $value) { HStack(spacing: 12) { Image(systemName: icon).font(.title3).foregroundStyle(.orange).frame(width: 34); VStack(alignment: .leading) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) } } } } }

private struct AddAccountSheet: View { @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss; @State private var name = ""; @State private var username = ""; @State private var password = ""; @State private var confirm = ""; @State private var role = "user"; private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && username.count >= 3 && password.count >= 6 && password == confirm }; var body: some View { NavigationStack { Form { TextField("Name", text: $name); TextField("Username", text: $username); SecureField("Password", text: $password); SecureField("Confirm password", text: $confirm); Picker("Role", selection: $role) { Text("Administrator").tag("admin"); Text("Team member").tag("user"); Text("Casual worker").tag("casual") }; if !confirm.isEmpty && password != confirm { Text("Passwords do not match.").foregroundStyle(.red) } }.navigationTitle("New account").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { if await appState.addUser(name: name, username: username, password: password, role: role) { dismiss() } } }.disabled(!valid) } } }.frame(minWidth: 430, minHeight: 420) } }
private struct ChangePasswordSheet: View { @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss; let user: CRMUser; @State private var password = ""; @State private var confirm = ""; var body: some View { NavigationStack { Form { SecureField("New password", text: $password); SecureField("Confirm password", text: $confirm); if !confirm.isEmpty && password != confirm { Text("Passwords do not match.").foregroundStyle(.red) } }.navigationTitle("Password for \(user.name)").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { if await appState.changePassword(userID: user.id, password: password) { dismiss() } } }.disabled(password.count < 6 || password != confirm) } } }.frame(minWidth: 400, minHeight: 260) } }

struct CSVDocument: FileDocument { static var readableContentTypes: [UTType] { [.commaSeparatedText] }; var text: String; init(text: String) { self.text = text }; init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }; func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) } }
private extension MacSettingsView {
    var emailAutomation: some View {
        SettingsPage(title: "Gmail assistant", subtitle: "Your inbox is monitored automatically—there is nothing to scan manually.") {
            SettingsCard { VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "envelope.badge.fill").font(.system(size: 27)).foregroundStyle(.orange).frame(width: 48, height: 48).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        if let status = appState.gmailConnectionStatus, status.connected {
                            Label("Gmail connected", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                            Text(status.gmailAddress ?? "Connected account").font(.callout).foregroundStyle(.secondary)
                        } else if appState.gmailConnectionStatus == nil {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking Gmail connection…").font(.callout).foregroundStyle(.secondary) }
                        } else {
                            Label("Gmail not connected", systemImage: "exclamationmark.circle.fill").font(.headline).foregroundStyle(.orange)
                            Text("Connect the company inbox to start automatic checks.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text("Important customer replies, quote decisions, leaks, complaints, payment deadlines and scheduling changes become admin tasks. When useful, a reply is prepared in Gmail Drafts for you to approve and send.").foregroundStyle(.secondary)
                Label("Emails are never sent automatically", systemImage: "hand.raised.fill").font(.callout.weight(.medium))
                Button(appState.gmailConnectionStatus?.connected == true ? "Reconnect Gmail" : "Connect Gmail") { Task { if let url = await appState.gmailAuthorizationURL() { openURL(url) } } }.buttonStyle(.borderedProminent).tint(.orange)
            } }
        }
        .task {
            for _ in 0..<60 {
                await appState.refreshGmailConnectionStatus()
                if appState.gmailConnectionStatus?.connected == true { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
#endif
