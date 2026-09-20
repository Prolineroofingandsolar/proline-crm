import AppIntents
import SwiftUI
import UserNotifications

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

enum SiriTaskPriority: String, AppEnum {
    case low, medium, high
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .low: "Low", .medium: "Medium", .high: "High",
    ]
}

struct AddCRMTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add ProLine CRM Task"
    static let description = IntentDescription("Adds an office or roofing task to your own ProLine CRM task list.")
    static let openAppWhenRun = false

    @Parameter(title: "Task") var taskTitle: String
    @Parameter(title: "Due date") var dueDate: Date?
    @Parameter(title: "Priority", default: .medium) var priority: SiriTaskPriority

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let userID = KeychainStore.get("supabaseAuthUserID"), KeychainStore.get("supabaseAccessToken") != nil else {
            return .result(dialog: "Open ProLine CRM and sign in before adding tasks with Siri.")
        }
        let cleanTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return .result(dialog: "Tell me what task you want to add.") }
        let task = GeneralTask(
            id: UUID().uuidString, title: cleanTitle, completed: false, completedDate: nil,
            dueDate: dueDate.map { SupabaseService.localDay(for: $0) }, priority: priority.rawValue,
            category: "General", notes: "Added with Siri", createdAt: SupabaseService.today,
            assignedTo: [userID]
        )
        do {
            try await SupabaseService.shared.insert(task, into: "general_tasks")
            let when = dueDate.map { " for \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
            return .result(dialog: "Added \(cleanTitle)\(when) to ProLine CRM.")
        } catch {
            return .result(dialog: "I couldn't save that task. Open ProLine CRM, check your connection, and try again.")
        }
    }
}

struct ProLineAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddCRMTaskIntent(),
            phrases: ["Add a task in \(.applicationName)", "Create a \(.applicationName) task"],
            shortTitle: "Add CRM Task", systemImageName: "checklist"
        )
    }
}

extension Notification.Name {
    static let crmNotificationDeepLink = Notification.Name("crmNotificationDeepLink")
    static let crmRemoteDeviceToken = Notification.Name("crmRemoteDeviceToken")
    static let crmRemoteRegistrationFailed = Notification.Name("crmRemoteRegistrationFailed")
}

#if os(iOS)
    final class ProLineAppDelegate: NSObject, UIApplicationDelegate {
        func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            NotificationCenter.default.post(name: .crmRemoteDeviceToken, object: deviceToken.map { String(format: "%02x", $0) }.joined())
        }
        func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            NotificationCenter.default.post(name: .crmRemoteRegistrationFailed, object: error.localizedDescription)
        }
    }
#elseif os(macOS)
    final class ProLineAppDelegate: NSObject, NSApplicationDelegate {
        func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            NotificationCenter.default.post(name: .crmRemoteDeviceToken, object: deviceToken.map { String(format: "%02x", $0) }.joined())
        }
        func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            NotificationCenter.default.post(name: .crmRemoteRegistrationFailed, object: error.localizedDescription)
        }
    }
#endif

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["url"] as? String,
            let url = URL(string: value)
        else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .crmNotificationDeepLink, object: url)
        }
    }
}

@main
struct ProLineCRMApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(ProLineAppDelegate.self) private var platformDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(ProLineAppDelegate.self) private var platformDelegate
    #endif
    @State private var appState = AppState()
    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        ProLineAppShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let token = appState.pendingWorkerInviteToken {
                    WorkerInviteSignupView(token: token)
                } else if appState.isAuthenticated {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environment(appState)
            .task {
                // The unit-test host launches this app too; leave the keychain and network alone there
                // so a test run never raises the macOS "wants to use your confidential information" dialog.
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                await appState.restoreSession(); appState.resumeRemoteNotificationsIfEnabled()
            }
            .onOpenURL { appState.open($0) }
            .onReceive(NotificationCenter.default.publisher(for: .crmRemoteDeviceToken)) { notification in
                guard let token = notification.object as? String else { return }
                Task { await appState.registerRemoteNotificationToken(token) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .crmRemoteRegistrationFailed)) { notification in
                appState.handleRemoteNotificationRegistrationFailure(notification.object as? String)
            }
            // The sign-in screen shows its own inline message; the alert is for the signed-in app.
            .alert(
                "ProLine CRM",
                isPresented: .init(
                    get: { appState.errorMessage != nil && (appState.isAuthenticated || appState.pendingWorkerInviteToken != nil) },
                    set: { if !$0 { appState.errorMessage = nil } })
            ) {
                Button("OK") { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
        #if os(macOS)
            .defaultSize(width: 1280, height: 820)
            .commands {
                SidebarCommands()
                CommandMenu("CRM") {
                    if appState.isAdmin {
                        Button("Search CRM…") { appState.showingGlobalSearch = true }.keyboardShortcut("k")
                        Button("New Lead…") { appState.showingGlobalAddLead = true }.keyboardShortcut("n")
                        Button("Operations Assistant…") { appState.showingAssistant = true }.keyboardShortcut(
                            "a", modifiers: [.command, .shift])
                        Divider()
                    }
                    Button("Refresh") { Task { await appState.refresh() } }.keyboardShortcut("r")
                    .disabled(appState.isWorkerPreview)
                }
            }
        #endif
        #if os(macOS)
            Settings {
                SettingsView().environment(appState).frame(minWidth: 520, minHeight: 560)
            }
        #endif
    }
}
