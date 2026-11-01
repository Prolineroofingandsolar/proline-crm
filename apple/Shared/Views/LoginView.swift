import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var username = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var showingInviteCode = false
    @State private var showingRecovery = false

    var body: some View {
        VStack(spacing: 22) {
            Image("Logo").resizable().scaledToFit().frame(maxWidth: 240).accessibilityLabel("ProLine Roofing & Solar")
            VStack(spacing: 12) {
                TextField("Email or username", text: $username).textContentType(.username)
                SecureField("Password", text: $password).textContentType(.password)
            }.textFieldStyle(.roundedBorder)
            if let message = appState.errorMessage { Text(message).font(.callout).foregroundStyle(.red) }
            Button {
                Task { _ = await appState.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password) }
            } label: {
                HStack {
                    if appState.isLoading { ProgressView().controlSize(.small) }; Text("Sign In").frame(maxWidth: .infinity)
                }
            }.buttonStyle(.borderedProminent).disabled(username.isEmpty || password.isEmpty || appState.isLoading)
            Button("Forgot password?") { showingRecovery = true }.buttonStyle(.plain)
            Button("Join your team with an invite") { showingInviteCode = true }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
        .padding(32).frame(maxWidth: 390)
        .sheet(isPresented: $showingRecovery) { PasswordRecoveryView() }
        .sheet(isPresented: $showingInviteCode) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Paste invitation code", text: $inviteCode)
                    } footer: {
                        Text("Your administrator can copy this code from the worker invitation.")
                    }
                }
                .navigationTitle("Worker invitation")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingInviteCode = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue") {
                            appState.pendingWorkerInviteToken = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines);
                            showingInviteCode = false
                        }.disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            #if os(macOS)
                .frame(minWidth: 430, minHeight: 250)
            #endif
        }
    }
}

struct WorkerInviteSignupView: View {
    @Environment(AppState.self) private var appState
    let token: String
    @State private var name = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var cisRate = 20
    @State private var utrNumber = ""
    @State private var bankName = ""
    @State private var accountNumber = ""
    @State private var sortCode = ""

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 8 && password == confirmPassword }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your account") {
                    TextField("Full name", text: $name).textContentType(.name)
                    SecureField("Choose password", text: $password).textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirmPassword).textContentType(.newPassword)
                    if !confirmPassword.isEmpty && password != confirmPassword { Text("Passwords do not match.").foregroundStyle(.red) }
                }
                Section("Pay and CIS details") {
                    Picker("CIS deduction", selection: $cisRate) {
                        Text("20%").tag(20); Text("30%").tag(30)
                    }
                    TextField("UTR number — optional", text: $utrNumber)
                }
                Section("Bank details — optional") {
                    TextField("Bank name", text: $bankName)
                    TextField("Account number", text: $accountNumber)
                    TextField("Sort code", text: $sortCode)
                }
                Section {
                    Button {
                        join()
                    } label: {
                        HStack {
                            if appState.isLoading { ProgressView().controlSize(.small) };
                            Text("Create account and join ProLine").frame(maxWidth: .infinity)
                        }
                    }.buttonStyle(.borderedProminent).disabled(!valid || appState.isLoading)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Join ProLine CRM")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back to sign in") { appState.pendingWorkerInviteToken = nil } }
            }
        }
        #if os(macOS)
            .frame(minWidth: 540, minHeight: 650)
        #endif
    }

    private func join() {
        let details = WorkerSignupDetails(
            name: name.trimmingCharacters(in: .whitespaces), password: password, dayRate: nil, cisRate: cisRate, utrNumber: utrNumber,
            bankName: bankName, bankAccountNumber: accountNumber, bankSortCode: sortCode)
        Task { _ = await appState.acceptWorkerInvitation(token: token, details: details) }
    }
}

struct InviteWorkerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "worker"
    @State private var invitation: WorkerInvitation?

    var body: some View {
        NavigationStack {
            Form {
                if let invitation {
                    Section("Invitation ready") {
                        Label(invitation.email, systemImage: "envelope.fill")
                        Text(
                            "Send this to the worker. They can tap the link after installing ProLine CRM, or paste the code on the sign-in screen."
                        ).foregroundStyle(.secondary)
                        ShareLink(item: invitation.link) { Label("Share invitation link", systemImage: "square.and.arrow.up") }
                        Button {
                            copy(invitation.link)
                        } label: {
                            Label("Copy link", systemImage: "doc.on.doc")
                        }
                        LabeledContent("Invitation code") { Text(invitation.code).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    Section { Label("Single use · expires in 7 days", systemImage: "clock.badge.checkmark").foregroundStyle(.secondary) }
                } else {
                    Section("Worker") {
                        TextField("Email address", text: $email).textContentType(.emailAddress)
                        Picker("Access", selection: $role) {
                            Text("Labourer").tag("labourer")
                            Text("Worker").tag("worker")
                            Text("Administrator").tag("admin")
                        }
                    }
                    Section {
                        Text(
                            "The worker supplies their own name, password, CIS, UTR and bank details. An administrator sets their day rate after they join. They will automatically join your ProLine company account."
                        ).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) { if let message = appState.errorMessage { Text(message).font(.callout).foregroundStyle(.red).padding() } }
            .navigationTitle(invitation == nil ? "Invite staff member" : "Share invitation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(invitation == nil ? "Cancel" : "Done") { dismiss() }.disabled(appState.isLoading) }
                if invitation == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create invite") { create() }.disabled(!email.contains("@") || appState.isLoading)
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 510, minHeight: 410)
        #endif
    }

    private func create() {
        Task {
            invitation = await appState.createWorkerInvitation(email: email.trimmingCharacters(in: .whitespacesAndNewlines), role: role)
        }
    }
    private func copy(_ value: String) {
        #if os(iOS)
            UIPasteboard.general.string = value
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

struct AddSecureUserSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role = "worker"
    @State private var dayRate = ""
    @State private var cisRate = 20
    @State private var loginEnabled = true
    @State private var busy = false
    private var validRate: Bool { dayRate.isEmpty || (Double(dayRate.replacingOccurrences(of: ",", with: ".")).map { $0.isFinite && $0 >= 0 && $0 <= 10000 } ?? false) }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (!loginEnabled || (email.contains("@") && password.count >= 8))
            && (!(!loginEnabled && role == "admin")) && validRate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Staff details") { TextField("Full name", text: $name).textContentType(.name) }
                Section {
                    Toggle("Give this person an app login", isOn: $loginEnabled)
                    if loginEnabled {
                        TextField("Employee email", text: $email).textContentType(.emailAddress)
                        SecureField("Temporary password (at least 8 characters)", text: $password).textContentType(.newPassword)
                    }
                } header: { Text("App access") } footer: {
                    Text(loginEnabled ? "Share the login privately and ask them to change their password. Use Invite staff instead if they should choose their own password." : "Payroll only. They can be recorded on timesheets but cannot sign in.")
                }
                .onChange(of: loginEnabled) { if !loginEnabled && role == "admin" { role = "labourer" } }
                Section("Access") {
                    Picker("Role", selection: $role) {
                        Text("Worker").tag("worker"); Text("Labourer").tag("labourer"); if loginEnabled { Text("Administrator").tag("admin") }
                    }
                }
                if let message = appState.errorMessage { Section { Text(message).foregroundStyle(.red) } }
                Section("Payroll") {
                    TextField("Day rate (optional)", text: $dayRate);
                    Picker("CIS rate", selection: $cisRate) {
                        Text("20%").tag(20); Text("30%").tag(30)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add staff member")
            .interactiveDismissDisabled(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Add staff") { create() }.disabled(!valid || busy) }
            }
        }
        #if os(macOS)
            .frame(minWidth: 500, minHeight: 480)
        #endif
    }

    private func create() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            let rate = Double(dayRate.replacingOccurrences(of: ",", with: "."))
            if await appState.createSecureUser(
                name: name.trimmingCharacters(in: .whitespaces), email: loginEnabled ? email.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                password: loginEnabled ? password : "", role: role, dayRate: rate, cisRate: cisRate)
            {
                dismiss()
            }
        }
    }
}

private struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var sent = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Employee email", text: $email).textContentType(.emailAddress)
                if sent {
                    Text("Enter the recovery code from your email. If the email contains a reset link instead, use that link in the online CRM.")
                    TextField("Recovery code", text: $code)
                    SecureField("New password (at least 8 characters)", text: $password).textContentType(.newPassword)
                }
                if let message { Text(message).font(.callout) }
                Button(sent ? "Save new password" : "Send recovery email") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            if sent {
                                try await SupabaseService.shared.completePasswordRecovery(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                                message = "Password updated. Close this window and sign in with your new password."
                            } else {
                                try await SupabaseService.shared.requestPasswordRecovery(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                                sent = true
                                message = "Check your email for recovery instructions."
                            }
                        } catch { message = error.localizedDescription }
                    }
                }.disabled(busy || email.isEmpty || (sent && (code.isEmpty || password.count < 8)))
                if busy { ProgressView() }
            }
            .navigationTitle("Reset password")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
            .frame(minWidth: 430, minHeight: 320)
        #endif
    }
}
