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
    @AppStorage("remotePushRegistrationIssue") private var remotePushRegistrationIssue: String?
    @State private var companyID: String?
    @State private var savingCompany = false
    @State private var companyMessage: String?
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
                    Button(savingCompany ? "Saving…" : "Save company details") { saveCompany() }
                        .disabled(companyID == nil || savingCompany || businessName.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let companyMessage { Text(companyMessage).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    Text("Business details")
                }

                Section("Staff & access") {
                    NavigationLink { StaffManagementView() } label: {
                        Label("Manage staff", systemImage: "person.2.badge.gearshape")
                    }
                    Text("Add staff, manage invitations, change roles and remove or restore access.")
                        .font(.caption).foregroundStyle(.secondary)
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
                if remotePushRegistrationIssue != nil {
                    Button("Retry live notifications") { Task { await appState.enableNotifications() } }
                }
            } header: {
                Text("Notifications")
            } footer: {
                if let issue = remotePushRegistrationIssue {
                    Text("Live notifications are not connected: \(issue). Retry to reconnect this device.")
                }
            }
            .onChange(of: [notifyTeam, notifySurveys, notifyJobStarts, notifyTasks, notifyPayments]) {
                Task { await appState.scheduleNotifications() }
            }

            if appState.isAdmin {
                Section {
                    if let status = appState.gmailConnectionStatus, status.connected {
                        LabeledContent("Gmail", value: status.gmailAddress ?? "Connected")
                    } else if appState.gmailConnectionStatusUnavailable {
                        LabeledContent("Gmail", value: "Status unavailable")
                    } else {
                        LabeledContent("Gmail", value: "Not connected")
                    }
                    if appState.gmailConnectionStatus == nil && appState.gmailConnectionStatusUnavailable {
                        Button("Retry Gmail status") { Task { await appState.refreshGmailConnectionStatus() } }
                    } else {
                        Button(appState.gmailConnectionStatus?.connected == true ? "Reconnect Gmail" : "Connect Gmail") {
                            Task { if let url = await appState.gmailAuthorizationURL() { openURL(url) } }
                        }
                    }
                } header: {
                    Text("Gmail assistant")
                }

                PaperclipConnectionSection()

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
        .sheet(isPresented: $showingChangePassword) { ChangePasswordSheet() }
        .fileExporter(
            isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
            defaultFilename: "ProLine-CRM-Export-\(SupabaseService.today)"
        ) { result in
            if case .failure = result { appState.errorMessage = "The export could not be saved." }
        }
        .task { if appState.isAdmin { await loadCompany(); await appState.refreshGmailConnectionStatus() } }
    }

    @MainActor private func loadCompany() async {
        do {
            let details = try await SupabaseService.shared.fetchCompanyDetails()
            companyID = details.id; businessName = details.name
            // Retain an existing local value until the administrator first saves it to the company.
            if !details.phone.isEmpty || businessPhone.isEmpty { businessPhone = details.phone }
            if !details.email.isEmpty || businessEmail.isEmpty { businessEmail = details.email }
            if !details.address.isEmpty || businessAddress.isEmpty { businessAddress = details.address }
            if !details.vat.isEmpty || businessVAT.isEmpty { businessVAT = details.vat }
        } catch { companyMessage = "Company details could not be loaded. Reopen Settings to retry." }
    }
    private func saveCompany() {
        guard let id = companyID else { return }
        savingCompany = true; companyMessage = nil
        let details = CompanyDetails(id: id, name: businessName, phone: businessPhone, email: businessEmail, address: businessAddress, vat: businessVAT)
        Task {
            defer { savingCompany = false }
            do { try await SupabaseService.shared.saveCompanyDetails(details); companyMessage = "Company details saved." }
            catch { companyMessage = "Company details could not be saved. Your changes are still shown." }
        }
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

struct StaffManagementView: View {
    @Environment(AppState.self) private var appState
    @State private var directory: StaffDirectory?
    @State private var search = ""
    @State private var filter = "Active"
    @State private var loading = false
    @State private var error: String?
    @State private var notice: String?
    @State private var showingInvite = false
    @State private var showingAdd = false
    @State private var selected: StaffMember?
    @State private var cancelling: StaffInvitationSummary?
    @State private var confirmingCancel = false

    private var people: [StaffMember] {
        (directory?.staff ?? []).filter { person in
            (filter == "All" || (filter == "Active" ? person.active : !person.active)) &&
            (search.isEmpty || "\(person.name) \(person.email ?? "") \(person.roleLabel)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    stat("Active", count: directory?.staff.filter(\.active).count ?? 0)
                    Spacer()
                    stat("Admins", count: directory?.staff.filter { $0.active && $0.role == "admin" }.count ?? 0)
                    Spacer()
                    stat("Invited", count: directory?.invitations.filter { !$0.expired }.count ?? 0)
                }.padding(.vertical, 8)
                Button { showingInvite = true } label: { Label("Invite staff member", systemImage: "paperplane") }
                Button { showingAdd = true } label: { Label("Set up login or payroll worker", systemImage: "person.badge.plus") }
            } footer: { Text("Invitations let employees choose their own password. Share invitation links or codes privately.") }
            if let notice { Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.green) } }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } } } }
            Section {
                Picker("Show", selection: $filter) {
                    Text("Active staff").tag("Active")
                    Text("Removed access").tag("Removed")
                    Text("All staff").tag("All")
                }
                if loading && directory == nil { ProgressView("Loading staff…") }
                ForEach(people) { person in
                    Button { selected = person } label: {
                        HStack(spacing: 12) {
                            Text(initials(person.name)).font(.subheadline.bold())
                                .frame(width: 42, height: 42).background(.orange.opacity(0.12), in: Circle()).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name + (person.id == appState.currentUser?.id ? " · You" : "")).font(.headline)
                                Text(person.email ?? person.contactEmail ?? "Payroll only · no app login").font(.caption).foregroundStyle(.secondary)
                                Text(person.roleLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(person.active ? "Active" : "Removed").font(.caption.weight(.medium))
                                .foregroundStyle(person.active ? .green : .secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if !loading && people.isEmpty { Text(search.isEmpty ? "No staff in this view." : "No staff match your search.").foregroundStyle(.secondary) }
            } header: { Text("Staff") }
            if let invitations = directory?.invitations, !invitations.isEmpty {
                Section {
                    ForEach(invitations.filter { search.isEmpty || $0.email.localizedCaseInsensitiveContains(search) }) { invitation in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(invitation.email).font(.subheadline.bold())
                            Text(invitation.expired ? "Expired" : "Pending · expires \(String(invitation.expiresAt.prefix(10)))").font(.caption).foregroundStyle(.secondary)
                            Button("Cancel invitation", role: .destructive) { cancelling = invitation; confirmingCancel = true }
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Invitations") } footer: { Text("Codes are not stored in this list. Create a new invitation if the original was lost.") }
            }
        }
        .navigationTitle("Staff & access")
        .searchable(text: $search, prompt: "Name, email or role")
        .toolbar { ToolbarItem { Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(loading) } }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showingInvite, onDismiss: { Task { await reload() } }) { InviteWorkerSheet() }
        .sheet(isPresented: $showingAdd, onDismiss: { Task { await reload() } }) { AddSecureUserSheet() }
        .sheet(item: $selected, onDismiss: { Task { await reload() } }) { person in StaffMemberSheet(person: person) }
        .confirmationDialog("Cancel this invitation?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel invitation", role: .destructive) {
                if let invitation = cancelling {
                    Task {
                        do { try await SupabaseService.shared.cancelStaffInvitation(id: invitation.id); notice = "Invitation cancelled."; await reload() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            Button("Keep invitation", role: .cancel) { cancelling = nil }
        } message: { Text(cancelling?.email ?? "") }
    }

    private func stat(_ label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(directory == nil ? "—" : "\(count)").font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
    private func initials(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
    @MainActor private func reload() async {
        loading = true; defer { loading = false }
        do { directory = try await SupabaseService.shared.fetchStaffDirectory(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct StaffMemberSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let person: StaffMember
    @State private var name: String
    @State private var email: String
    @State private var contactEmail: String
    @State private var role: String
    @State private var rate: String
    @State private var cis: Int
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingRemoval = false
    @State private var originalPay: StaffPayDetails?
    @State private var utr = ""
    @State private var bank = ""
    @State private var account = ""
    @State private var sortCode = ""

    init(person: StaffMember) {
        self.person = person
        _name = State(initialValue: person.name)
        _email = State(initialValue: person.email ?? "")
        _contactEmail = State(initialValue: person.contactEmail ?? "")
        _role = State(initialValue: ["admin", "labourer"].contains(person.role) ? person.role : "worker")
        _rate = State(initialValue: person.dayRate.map { String($0) } ?? "")
        _cis = State(initialValue: person.cisRate ?? 20)
    }
    private var ownAccount: Bool { person.id == appState.currentUser?.id }
    private var validRate: Bool { rate.isEmpty || (Double(rate).map { $0.isFinite && $0 >= 0 && $0 <= 10000 } ?? false) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Staff member") {
                    if ownAccount { LabeledContent("Name", value: person.name) }
                    else { TextField("Full name", text: $name) }
                    if !ownAccount && person.email != nil {
                        TextField("Sign-in email", text: $email)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    } else {
                        LabeledContent("Sign-in", value: person.email ?? "Payroll only · no login")
                    }
                    if !ownAccount {
                        TextField("Contact email (optional)", text: $contactEmail)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    }
                    LabeledContent("Status", value: person.active ? "Active" : "Access removed")
                }
                if ownAccount {
                    Section { Text("Another administrator must change your role or pay settings. You cannot remove your own access.").foregroundStyle(.secondary) }
                } else {
                    if person.email != nil {
                        Section {
                            Button("Update sign-in email") { updateEmail() }
                                .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.lowercased() == person.email?.lowercased())
                        } header: { Text("Sign-in email") } footer: {
                            Text("The employee signs in with the new email and their existing password. Share the new address with them securely.")
                        }
                    }
                    Section {
                        Picker("Role", selection: $role) {
                            Text("Worker").tag("worker"); Text("Labourer").tag("labourer"); Text("Administrator").tag("admin")
                        }
                        Text(role == "admin" ? "Administrators manage staff, customers and company finances." : "Team members work on their assigned jobs, tasks and timesheets.")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Permissions") }
                    Section("Pay settings") {
                        TextField("Day rate (£)", text: $rate)
                        Picker("CIS deduction", selection: $cis) { Text("20%").tag(20); Text("30%").tag(30) }
                    }
                    Section("Bank and tax details") {
                        if originalPay == nil {
                            Button("Load bank and tax details") { loadPay() }.disabled(busy)
                        } else {
                            TextField("UTR (10 digits)", text: $utr)
                            TextField("Bank name", text: $bank)
                            TextField("Account number (8 digits)", text: $account)
                            TextField("Sort code (6 digits)", text: $sortCode)
                            Button("Save bank and tax details") { savePay() }.disabled(busy)
                        }
                    }
                    Section {
                        Button(person.active ? "Remove access" : "Restore staff access", role: person.active ? .destructive : nil) {
                            if person.active { confirmingRemoval = true } else { save(accessOnly: true) }
                        }.disabled(busy)
                    } footer: { Text("Work, timesheets and payments are kept when access is removed. Employees reset their own passwords from the sign-in screen.") }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if busy { ProgressView("Saving…") }
            }
            .formStyle(.grouped).navigationTitle(person.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) }
                if !ownAccount { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(busy || !validRate || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            }
            .confirmationDialog("Remove app access for \(person.name)?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove access", role: .destructive) { save(accessOnly: true) }
                Button("Keep access", role: .cancel) { }
            } message: { Text("Their jobs, timesheets and payments will be kept.") }
            .interactiveDismissDisabled(busy)
        }
        #if os(macOS)
            .frame(minWidth: 500, minHeight: 520)
        #endif
    }
    private func save(accessOnly: Bool = false) {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                if accessOnly {
                    if person.active { try await SupabaseService.shared.deactivateEmployee(id: person.id) }
                    else { try await SupabaseService.shared.restoreStaffMember(id: person.id) }
                } else {
                    try await SupabaseService.shared.updateStaffMember(id: person.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), role: role, dayRate: Double(rate), cisRate: cis)
                    let newContactEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if newContactEmail.lowercased() != (person.contactEmail ?? "").lowercased() {
                        do { try await SupabaseService.shared.updateStaffContactEmail(id: person.id, email: newContactEmail) }
                        catch { self.error = "Staff details were saved, but the contact email was not: \(error.localizedDescription)"; return }
                    }
                    let newEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let oldEmail = person.email, newEmail.lowercased() != oldEmail.lowercased() {
                        do { try await SupabaseService.shared.updateStaffEmail(id: person.id, email: newEmail) }
                        catch { self.error = "Staff details were saved, but the email was not changed: \(error.localizedDescription)"; return }
                    }
                }
                appState.users = try await SupabaseService.shared.fetchUsers()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func updateEmail() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await SupabaseService.shared.updateStaffEmail(id: person.id, email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func loadPay() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let pay = try await SupabaseService.shared.fetchStaffPay(id: person.id)
                originalPay = pay; utr = pay.utrNumber ?? ""; bank = pay.bankName ?? ""
                account = pay.account ?? ""; sortCode = pay.sortCode ?? ""
            } catch { self.error = error.localizedDescription }
        }
    }
    private func savePay() {
        guard let expected = originalPay else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let pay = StaffPayDetails(utrNumber: utr, bankName: bank, account: account, sortCode: sortCode)
                try await SupabaseService.shared.updateStaffPay(id: person.id, details: pay, expected: expected)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
