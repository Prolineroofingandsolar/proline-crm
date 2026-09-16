import SwiftUI
import UniformTypeIdentifiers

struct ContactsView: View {
    @Environment(AppState.self) private var appState; @State private var search = ""; @State private var showingAdd = false
    private var rows: [CRMContact] {
        appState.contacts.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.phone.contains(search)
                || $0.email.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        #if os(macOS)
            MacContactsView()
        #else
            List(rows) { contact in
                NavigationLink {
                    ContactDetailView(contactID: contact.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name).font(.headline);
                        Text([contact.phone, contact.email].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(
                            .secondary);
                        if !contact.address.isEmpty { Text(contact.address).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.searchable(text: $search).navigationTitle("Contacts").toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Label("New Contact", systemImage: "plus")
                }
            }.sheet(isPresented: $showingAdd) { ContactEditor(contact: nil) }
        #endif
    }
}

struct ContactDetailView: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss; let contactID: String;
    @State private var editing = false; @State private var confirmingDelete = false
    private var contact: CRMContact? { appState.contacts.first { $0.id == contactID } }
    private var related: [Lead] {
        guard let c = contact else { return [] };
        return appState.leads.filter {
            (!c.phone.isEmpty && $0.phone == c.phone) || (!c.email.isEmpty && $0.email.caseInsensitiveCompare(c.email) == .orderedSame)
        }
    }
    var body: some View {
        if let contact {
            List {
                Section("Contact") {
                    LabeledContent("Name", value: contact.name);
                    if !contact.phone.isEmpty { PhoneActionMenu(number: contact.phone, label: contact.phone) };
                    if let u = ContactLinks.email(contact.email) {
                        Link(contact.email, destination: u)
                    } else if !contact.email.isEmpty {
                        LabeledContent("Email", value: contact.email)
                    }; LabeledContent("Address", value: contact.address.isEmpty ? "Not added" : contact.address)
                };
                Section("Related leads and jobs") {
                    if related.isEmpty { Text("No related leads").foregroundStyle(.secondary) };
                    ForEach(related) { lead in
                        NavigationLink {
                            LeadDetailView(leadID: lead.id)
                        } label: {
                            LeadRow(lead: lead)
                        }
                    }
                }
            }.navigationTitle(contact.name).toolbar {
                Button("Edit") { editing = true };
                Menu {
                    Button("Delete contact", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }.sheet(isPresented: $editing) { ContactEditor(contact: contact) }.confirmationDialog(
                "Delete \(contact.name)?", isPresented: $confirmingDelete, titleVisibility: .visible
            ) { Button("Delete contact", role: .destructive) { Task { if await appState.deleteContact(contact) { dismiss() } } } }
        } else {
            ContentUnavailableView("Contact not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

struct ContactEditor: View {
    @Environment(AppState.self) private var appState; @Environment(\.dismiss) private var dismiss; let contact: CRMContact?;
    @State private var name = ""; @State private var phone = ""; @State private var email = ""; @State private var address = "";
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name); TextField("Phone", text: $phone); TextField("Email", text: $email);
                TextField("Address", text: $address, axis: .vertical)
            }.disabled(isSaving).navigationTitle(contact == nil ? "New Contact" : "Edit Contact").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) };
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true; defer { isSaving = false }; let saved: Bool;
                            if var changed = contact {
                                changed.name = name; changed.phone = phone; changed.email = email; changed.address = address;
                                saved = await appState.saveContact(changed)
                            } else {
                                saved = await appState.addContact(name: name, phone: phone, email: email, address: address)
                            }; if saved { dismiss() }
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }.frame(minWidth: 420, minHeight: 360).onAppear {
            guard let contact else { return }; name = contact.name; phone = contact.phone; email = contact.email; address = contact.address
        }
    }
}

struct FilesView: View {
    @Environment(AppState.self) private var appState; @State private var search = ""
    private var items: [(Lead, CRMFile)] {
        appState.leads.flatMap { lead in lead.files.map { (lead, $0) } }.filter {
            search.isEmpty || $0.1.name.localizedCaseInsensitiveContains(search) || $0.0.name.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        #if os(macOS)
            MacFilesView()
        #else
            List(items, id: \.1.id) { lead, file in
                VStack(alignment: .leading, spacing: 2) {
                    if let raw = file.url {
                        SecureAttachmentLink(locator: raw, label: file.name, icon: file.type == "image" ? "photo" : "doc")
                    } else {
                        Label(file.name, systemImage: file.type == "image" ? "photo" : "doc")
                    }
                    NavigationLink(value: LeadRoute(id: lead.id)) {
                        Text("\(lead.name) · \(CRMFormat.day(file.date))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.searchable(text: $search).navigationTitle("Files")
        #endif
    }
}

struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @State private var exporting = false
    @State private var exportDocument = CRMCSVDocument(text: "")
    var body: some View {
        #if os(macOS)
            MacReportsView()
        #else
            List {
                Section("Financial") {
                    LabeledContent(
                        "Total won",
                        value: appState.leads.filter {
                            [.won, .scheduled, .inProgress, .completed, .waitingForPayment, .paid].contains($0.stage)
                        }.reduce(0) { $0 + $1.value }.formatted(.currency(code: "GBP")));
                    LabeledContent(
                        "Paid revenue",
                        value: appState.leads.filter { $0.stage == .paid }.reduce(0) { $0 + $1.value }.formatted(.currency(code: "GBP")));
                    LabeledContent(
                        "Outstanding",
                        value: appState.leads.filter { $0.stage != .lost }.reduce(0) { $0 + $1.balance }.formatted(.currency(code: "GBP")))
                };
                Section("Pipeline") {
                    ForEach(LeadStage.allCases) { stage in
                        let rows = appState.leads.filter { $0.stage == stage };
                        LabeledContent(
                            stage.rawValue, value: "\(rows.count) · \(rows.reduce(0){$0+$1.value}.formatted(.currency(code:"GBP")))")
                    }
                };
                Section("Lead Sources") {
                    ForEach(Dictionary(grouping: appState.leads, by: \.source).keys.sorted(), id: \.self) { source in
                        LabeledContent(source.isEmpty ? "Unknown" : source, value: "\(appState.leads.filter{$0.source == source}.count)")
                    }
                }
            }.navigationTitle("Reports").toolbar {
                Button {
                    prepareExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }.disabled(appState.leads.isEmpty)
            }.fileExporter(
                isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
                defaultFilename: "ProLine-Job-Report-\(SupabaseService.today)"
            ) { result in if case .failure = result { appState.errorMessage = "The report could not be exported." } }
        #endif
    }
    private func prepareExport() { exportDocument = CRMCSVDocument(text: CRMReportExport.csv(leads: appState.leads)); exporting = true }
}

struct CRMCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
