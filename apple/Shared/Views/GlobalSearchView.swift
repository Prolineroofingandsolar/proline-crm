import SwiftUI

private enum SearchRoute: Hashable {
    case lead(String)
    case contact(String)
}

struct GlobalSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var path: [SearchRoute] = []

    private var leads: [Lead] {
        guard !query.isEmpty else { return Array(appState.leads.prefix(8)) }
        return appState.leads.filter { lead in
            [lead.name, lead.jobRef, lead.phone, lead.email, lead.address, lead.jobType]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.prefix(20).map { $0 }
    }
    private var contacts: [CRMContact] {
        guard appState.canAccess(.contacts) else { return [] }
        guard !query.isEmpty else { return [] }
        return appState.contacts.filter { contact in
            [contact.name, contact.phone, contact.email, contact.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.prefix(12).map { $0 }
    }
    private var tasks: [GeneralTask] {
        guard !query.isEmpty else { return [] }
        return appState.visibleGeneralTasks.filter {
            NotificationScope.includes($0, for: appState.currentUser)
                && ($0.title.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query))
        }.prefix(12).map { $0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !leads.isEmpty {
                    Section(query.isEmpty ? "Recent leads and jobs" : "Leads and jobs") {
                        ForEach(leads) { lead in
                            NavigationLink(value: SearchRoute.lead(lead.id)) {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains(
                                            lead.stage) ? "hammer" : "person.crop.circle"
                                    )
                                    .foregroundStyle(Color.accentColor).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lead.name).fontWeight(.semibold)
                                        Text("\(lead.jobRef) · \(lead.jobType) · \(lead.stage.displayName)").font(.caption).foregroundStyle(
                                            .secondary)
                                    }
                                    Spacer()
                                    Text(lead.value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(.subheadline.bold())
                                }
                            }
                        }
                    }
                }
                if !contacts.isEmpty {
                    Section("Contacts") {
                        ForEach(contacts) { contact in
                            NavigationLink(value: SearchRoute.contact(contact.id)) {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(contact.name).fontWeight(.semibold);
                                        Text([contact.phone, contact.email].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "person.crop.circle").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                if !tasks.isEmpty {
                    Section("Tasks") {
                        ForEach(tasks) { task in
                            Button {
                                appState.selectedSection = .tasks
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(
                                        task.completed ? .green : Color.accentColor);
                                    VStack(alignment: .leading) {
                                        Text(task.title);
                                        Text(
                                            [task.category, task.dueDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                                        ).font(.caption).foregroundStyle(.secondary)
                                    }; Spacer(); Image(systemName: "arrow.right")
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !query.isEmpty && leads.isEmpty && contacts.isEmpty && tasks.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .automatic, prompt: "Customer, job, postcode, phone or task")
            .navigationTitle("Search ProLine CRM")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case .lead(let id): LeadDetailView(leadID: id)
                case .contact(let id): ContactDetailView(contactID: id)
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 720, minHeight: 620)
        #endif
    }
}
