#if os(macOS)
    import SwiftUI

    struct MacContactsView: View {
        @Environment(AppState.self) private var appState
        @State private var search = ""
        @State private var selection: CRMContact.ID?
        @State private var sortOrder = [KeyPathComparator(\CRMContact.name)]
        @State private var showingAdd = false
        @State private var editing: CRMContact?
        @State private var deleting: CRMContact?

        private var rows: [CRMContact] {
            appState.contacts
                .filter { contact in
                    search.isEmpty
                        || [contact.name, contact.phone, contact.email, contact.address].contains {
                            $0.localizedCaseInsensitiveContains(search)
                        }
                }
                .sorted(using: sortOrder)
        }
        private var selected: CRMContact? { rows.first { $0.id == selection } }
        private func related(_ contact: CRMContact) -> [Lead] {
            appState.leads.filter {
                (!$0.phone.isEmpty && $0.phone == contact.phone)
                    || (!$0.email.isEmpty && $0.email.caseInsensitiveCompare(contact.email) == .orderedSame)
            }
        }

        var body: some View {
            HSplitView {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Phone", value: \.phone) { Text($0.phone.isEmpty ? "—" : $0.phone) }
                    TableColumn("Email", value: \.email) { Text($0.email.isEmpty ? "—" : $0.email) }
                    TableColumn("Address", value: \.address) { Text($0.address.isEmpty ? "—" : $0.address).lineLimit(1) }
                    TableColumn("Jobs") { Text("\(related($0).count)") }.width(50)
                }
                .contextMenu(forSelectionType: CRMContact.ID.self) { ids in
                    if let id = ids.first, let contact = rows.first(where: { $0.id == id }) {
                        Button("Edit…") { editing = contact }
                        Button("Delete", role: .destructive) { deleting = contact }
                    }
                }
                .frame(minWidth: 480)
                if let contact = selected { inspector(contact).frame(minWidth: 280, idealWidth: 320, maxWidth: 380) }
            }
            .searchable(text: $search, prompt: "Name, phone, email or address")
            .navigationTitle("Contacts")
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Label("New contact", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) { ContactEditor(contact: nil) }
            .sheet(item: $editing) { ContactEditor(contact: $0) }
            .confirmationDialog(
                "Delete \(deleting?.name ?? "contact")?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible
            ) {
                Button("Delete contact", role: .destructive) {
                    if let deleting { Task { await appState.deleteContact(deleting) }; self.deleting = nil }
                }
            }
        }

        private func inspector(_ contact: CRMContact) -> some View {
            Form {
                Section(contact.name) {
                    if !contact.phone.isEmpty { PhoneActionMenu(number: contact.phone, label: contact.phone) }
                    if !contact.email.isEmpty { EmailActionMenu(address: contact.email) }
                    if !contact.address.isEmpty { Label(contact.address, systemImage: "map") }
                    LabeledContent("Customer since", value: CRMFormat.day(contact.createdAt))
                }
                Section("Related work") {
                    ForEach(related(contact)) { lead in
                        NavigationLink(value: LeadRoute(id: lead.id)) { LeadRow(lead: lead) }
                    }
                    if related(contact).isEmpty { Text("No related leads or jobs").foregroundStyle(.secondary) }
                }
                Section {
                    Button("Edit…") { editing = contact }
                    Button("Delete", role: .destructive) { deleting = contact }
                }
            }
            .formStyle(.grouped)
        }
    }

    struct MacFilesView: View {
        @Environment(AppState.self) private var appState
        @State private var search = ""
        @State private var type = "All files"
        private var all: [(Lead, CRMFile)] {
            appState.leads.flatMap { lead in lead.files.map { (lead, $0) } }
        }
        private var rows: [(Lead, CRMFile)] {
            all.filter { lead, file in
                (search.isEmpty || file.name.localizedCaseInsensitiveContains(search)
                    || lead.name.localizedCaseInsensitiveContains(search)
                    || lead.jobRef.localizedCaseInsensitiveContains(search))
                    && (type == "All files"
                        || (type == "Images" ? file.type == "image" : file.type != "image"))
            }.sorted { $0.1.date > $1.1.date }
        }
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quotes, surveys, photos and paperwork across every job.").foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    Text("\(all.count)").font(.title2.bold())
                    Text("documents").foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 18)
                HStack(spacing: 12) {
                    FileMetric("All files", all.count, "folder", .blue)
                    FileMetric("Images", all.filter { $0.1.type == "image" }.count, "photo", .purple)
                    FileMetric("Documents", all.filter { $0.1.type != "image" }.count, "doc.text", Color.accentColor)
                    FileMetric("Jobs with files", Set(all.map { $0.0.id }).count, "briefcase", .green)
                }.padding(24)
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search files or customers…", text: $search)
                    }.padding(.horizontal, 10).frame(width: 310, height: 36).background(
                        .background, in: RoundedRectangle(cornerRadius: 8)
                    ).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    Picker("", selection: $type) {
                        ForEach(["All files", "Images", "Documents"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented).frame(width: 280)
                    Spacer()
                    Text("\(rows.count) results").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 16)
                HStack {
                    Text("File").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Customer / job").frame(width: 230, alignment: .leading)
                    Text("Type").frame(width: 100, alignment: .leading)
                    Text("Added").frame(width: 110, alignment: .leading)
                    Text("").frame(width: 30)
                }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 24).frame(
                    height: 40
                ).background(.background).overlay(alignment: .bottom) { Divider() }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.1.id) { lead, file in
                            HStack {
                                Image(systemName: file.type == "image" ? "photo.fill" : "doc.fill").font(.title2)
                                    .foregroundStyle(file.type == "image" ? .purple : .blue).frame(width: 38)
                                VStack(alignment: .leading) {
                                    Text(file.name).fontWeight(.semibold)
                                    Text(file.size ?? "Size not recorded").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                NavigationLink {
                                    LeadDetailView(leadID: lead.id)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(lead.name)
                                        Text(lead.jobRef).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain).frame(width: 230, alignment: .leading)
                                Text(file.type.capitalized).frame(width: 100, alignment: .leading)
                                Text(CRMFormat.day(file.date)).frame(width: 110, alignment: .leading)
                                Group {
                                    if let raw = file.url {
                                        SecureAttachmentLink(locator: raw, label: "Open", icon: "arrow.up.right.square")
                                    } else {
                                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).help("No file URL saved")
                                    }
                                }.frame(width: 70, alignment: .leading)
                            }.font(.subheadline).padding(.horizontal, 24).frame(height: 62).overlay(
                                alignment: .bottom
                            ) { Divider() }
                        }
                    }.overlay {
                        if rows.isEmpty {
                            ContentUnavailableView("No matching files", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
            }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Files")
        }
    }
    private struct FileMetric: View {
        let title: String
        let value: Int
        let icon: String
        let tint: Color
        init(_ title: String, _ value: Int, _ icon: String, _ tint: Color) {
            self.title = title
            self.value = value
            self.icon = icon
            self.tint = tint
        }
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading) {
                    Text("\(value)").font(.title2.bold())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
                .background, in: RoundedRectangle(cornerRadius: 8)
            ).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
    }

    struct MacReportsView: View {
        @Environment(AppState.self) private var appState
        @State private var exporting = false
        @State private var exportDocument = CRMCSVDocument(text: "")
        private var paid: Double {
            appState.leads.filter { $0.stage == .paid }.reduce(0) { $0 + $1.value }
        }
        private var pipeline: Double {
            appState.leads.filter { ![.paid, .lost].contains($0.stage) }.reduce(0) { $0 + $1.value }
        }
        private var outstanding: Double {
            appState.leads.filter { $0.stage != .lost }.reduce(0) { $0 + $1.balance }
        }
        private var average: Double {
            let valued = appState.leads.filter { $0.value > 0 }
            return valued.isEmpty ? 0 : valued.reduce(0) { $0 + $1.value } / Double(valued.count)
        }
        private var maximumStage: Double {
            max(
                1,
                LeadStage.allCases.map { stage in
                    appState.leads.filter { $0.stage == stage }.reduce(0) { $0 + $1.value }
                }.max() ?? 1)
        }
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("A live commercial view of the roofing business.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            exportDocument = CRMCSVDocument(text: CRMReportExport.csv(leads: appState.leads))
                            exporting = true
                        } label: {
                            Label("Export job report", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent).disabled(appState.leads.isEmpty)
                    }
                    HStack(spacing: 12) {
                        ReportMetric("Paid revenue", paid, "sterlingsign.circle", .green)
                        ReportMetric("Open pipeline", pipeline, "chart.line.uptrend.xyaxis", .blue)
                        ReportMetric("Outstanding", outstanding, "exclamationmark.circle", Color.accentColor)
                        ReportMetric("Average job", average, "briefcase", .purple)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        reportPanel("Pipeline funnel") {
                            VStack(spacing: 12) {
                                ForEach(LeadStage.allCases) { stage in
                                    let rows = appState.leads.filter { $0.stage == stage }
                                    let value = rows.reduce(0) { $0 + $1.value }
                                    HStack {
                                        Text(stage.displayName).frame(width: 115, alignment: .leading)
                                        GeometryReader { proxy in
                                            RoundedRectangle(cornerRadius: 4).fill(stageTint(stage).opacity(0.75)).frame(
                                                width: max(3, proxy.size.width * value / maximumStage))
                                        }.frame(height: 12)
                                        Text("\(rows.count)").frame(width: 28, alignment: .trailing)
                                        Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).frame(
                                            width: 90, alignment: .trailing)
                                    }.font(.caption)
                                }
                            }
                        }
                        reportPanel("Lead sources") {
                            VStack(spacing: 12) {
                                ForEach(
                                    Dictionary(grouping: appState.leads, by: \.source).sorted {
                                        $0.value.count > $1.value.count
                                    }.prefix(8), id: \.key
                                ) { source, leads in
                                    HStack {
                                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                        Text(source.isEmpty ? "Unknown" : source)
                                        Spacer()
                                        Text("\(leads.count)").fontWeight(.semibold)
                                        Text(sourcePercent(leads.count)).foregroundStyle(.secondary).frame(
                                            width: 38, alignment: .trailing)
                                    }.font(.subheadline)
                                }
                            }
                        }.frame(width: 340)
                    }
                    reportPanel("Outstanding balances") {
                        VStack(spacing: 0) {
                            ForEach(
                                appState.leads.filter { $0.balance > 0 && $0.stage != .lost }.sorted {
                                    $0.balance > $1.balance
                                }.prefix(12)
                            ) { lead in
                                NavigationLink {
                                    LeadDetailView(leadID: lead.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(lead.name).fontWeight(.medium)
                                            Text("\(lead.jobRef) · \(lead.stage.displayName)").font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(lead.balance, format: .currency(code: "GBP")).fontWeight(.semibold)
                                            .foregroundStyle(Color.accentColor)
                                    }.padding(.vertical, 9).overlay(alignment: .bottom) { Divider() }
                                }.buttonStyle(.plain)
                            }
                            if appState.leads.allSatisfy({ $0.balance <= 0 || $0.stage == .lost }) {
                                ContentUnavailableView(
                                    "Nothing outstanding", systemImage: "checkmark.seal",
                                    description: Text("All recorded balances are clear."))
                            }
                        }
                    }
                }.padding(24)
            }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("Reports")
                .fileExporter(
                    isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
                    defaultFilename: "ProLine-Job-Report-\(SupabaseService.today)"
                ) { result in
                    if case .failure = result { appState.errorMessage = "The report could not be exported." }
                }
        }
        private func reportPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
            -> some View
        {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.headline)
                content()
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
                .background, in: RoundedRectangle(cornerRadius: 12)
            ).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        }
        private func stageTint(_ stage: LeadStage) -> Color {
            switch stage {
            case .newLead: .blue
            case .surveyBooked: Color.accentColor
            case .quotePreparing, .quoteSent: .purple
            case .won, .paid: .green
            case .scheduled: .teal
            case .inProgress: .cyan
            case .completed: .mint
            case .waitingForPayment: .indigo
            case .lost: .gray
            }
        }
        private func sourcePercent(_ count: Int) -> String {
            let percentage = Double(count) / Double(max(1, appState.leads.count)) * 100
            return "\(Int(percentage.rounded()))%"
        }
    }
    private struct ReportMetric: View {
        let title: String
        let value: Double
        let icon: String
        let tint: Color
        init(_ title: String, _ value: Double, _ icon: String, _ tint: Color) {
            self.title = title
            self.value = value
            self.icon = icon
            self.tint = tint
        }
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading) {
                    Text(value, format: .currency(code: "GBP").precision(.fractionLength(0))).font(
                        .title2.bold())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
                .background, in: RoundedRectangle(cornerRadius: 8)
            ).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
    }
#endif
