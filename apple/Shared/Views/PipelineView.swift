import SwiftUI

/// The two halves of the pipeline: winning work, then delivering and getting paid for it.
enum PipelineLane: String, CaseIterable, Identifiable {
    case sales = "Sales", jobs = "Jobs"
    var id: String { rawValue }
    var stages: [LeadStage] {
        switch self {
        case .sales: [.newLead, .surveyBooked, .quotePreparing, .quoteSent]
        case .jobs: [.won, .scheduled, .inProgress, .completed, .waitingForPayment]
        }
    }
}

struct PipelineView: View {
    @Environment(AppState.self) private var appState
    @State private var lane: PipelineLane = .sales
    @State private var stage: LeadStage = .newLead
    @State private var search = ""
    @State private var showingAdd = false

    private var matching: [Lead] {
        appState.leads.filter { lead in
            search.isEmpty
                || [lead.name, lead.jobRef, lead.address, lead.jobType, lead.phone].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    private func leads(in stage: LeadStage) -> [Lead] {
        matching.filter { $0.stage == stage }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        #if os(macOS)
            board
                .searchable(text: $search, prompt: "Search customer, job or address")
                .toolbar {
                    ToolbarItem(placement: .principal) { lanePicker.frame(width: 200) }
                    ToolbarItem {
                        NavigationLink {
                            CompletedJobsArchiveView()
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                }
                .navigationTitle("Pipeline")
                .sheet(isPresented: $showingAdd) { AddLeadView(defaultStage: lane == .sales ? .newLead : .won) }
        #else
            list
                .searchable(text: $search, prompt: "Search customer, job or address")
                .toolbar {
                    ToolbarItem(placement: .principal) { lanePicker }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            CompletedJobsArchiveView()
                        } label: {
                            Image(systemName: "archivebox")
                        }.accessibilityLabel("Archive")
                    }
                }
                .navigationTitle("Pipeline")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingAdd) { AddLeadView(defaultStage: stage) }
        #endif
    }

    private var lanePicker: some View {
        Picker("Pipeline", selection: $lane) { ForEach(PipelineLane.allCases) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented)
            .onChange(of: lane) { _, value in if !value.stages.contains(stage) { stage = value.stages[0] } }
    }

    #if os(iOS)
        // MARK: iPhone — one list, one stage at a time (or every stage while searching)

        private var list: some View {
            List {
                if search.isEmpty {
                    Section {
                        ForEach(leads(in: stage)) { lead in PipelineRow(lead: lead) }
                        if leads(in: stage).isEmpty {
                            Text("Nothing in \(stage.displayName)").foregroundStyle(.secondary)
                        }
                    } header: {
                        stageChooser
                    }
                } else {
                    ForEach(LeadStage.allCases) { stage in
                        let rows = leads(in: stage)
                        if !rows.isEmpty {
                            Section(stage.displayName) { ForEach(rows) { lead in PipelineRow(lead: lead) } }
                        }
                    }
                    if matching.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
            .listStyle(.insetGrouped)
        }

        private var stageChooser: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lane.stages) { item in
                        let count = leads(in: item).count
                        Button {
                            withAnimation(.snappy) { stage = item }
                        } label: {
                            Text(count > 0 ? "\(item.displayName) \(count)" : item.displayName)
                                .font(.subheadline.weight(stage == item ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(stage == item ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(stage == item ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .textCase(nil)
            .padding(.vertical, 4)
        }

    #endif

    #if os(macOS)
        // MARK: Mac — a board of columns

        private var board: some View {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(lane.stages) { stage in
                        StageColumn(stage: stage, leads: leads(in: stage), onAdd: { showingAdd = true })
                    }
                }
                .padding(20)
            }
        }
    #endif
}

/// One lead in the iPhone pipeline list: tap for detail, swipe for the next step or a call.
struct PipelineRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    let lead: Lead
    @State private var showingSchedule = false
    @State private var showingSurvey = false

    var body: some View {
        NavigationLink(value: LeadRoute(id: lead.id)) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(lead.name).fontWeight(.medium)
                    Spacer()
                    if lead.value > 0 {
                        Text(lead.value, format: .currency(code: "GBP").precision(.fractionLength(0))).foregroundStyle(.secondary)
                    }
                }
                Text([lead.jobType, lead.address].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(
                    .secondary
                ).lineLimit(1)
                if let next = lead.tasks.first(where: { !$0.completed }) {
                    Text(next.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let step = AppState.nextStep(for: lead) {
                Button {
                    perform(step)
                } label: {
                    Label(step.title, systemImage: step.systemImage)
                }.tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            if ContactLinks.telephone(lead.phone) != nil {
                Button {
                    if let url = appState.beginCall(to: lead) { openURL(url) }
                } label: {
                    Label("Call", systemImage: "phone")
                }.tint(.green)
            }
        }
        .contextMenu { StageMenu(lead: lead) }
        .sheet(isPresented: $showingSchedule) { ScheduleJobSheet(lead: lead) }
        .sheet(isPresented: $showingSurvey) { ScheduleSurveySheet(lead: lead) }
    }

    private func perform(_ step: LeadStep) {
        switch step {
        case .bookSurvey: showingSurvey = true
        case .scheduleJob: showingSchedule = true
        case .recordPayment: Task { await appState.recordFinalPayment(for: lead) }
        case .move(let stage): Task { await appState.move(lead, to: stage) }
        }
    }
}

/// Every stage, for the rare move that isn't the next step.
struct StageMenu: View {
    @Environment(AppState.self) private var appState
    let lead: Lead
    var body: some View {
        Menu("Move to…") {
            ForEach(LeadStage.allCases.filter { $0 != lead.stage }) { stage in
                Button(stage.displayName) { Task { await appState.move(lead, to: stage) } }
            }
        }
    }
}

#if os(macOS)
    private struct StageColumn: View {
        let stage: LeadStage
        let leads: [Lead]
        let onAdd: () -> Void
        @Environment(AppState.self) private var appState

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stage.displayName).font(.headline)
                    Spacer()
                    Text(leads.count, format: .number).foregroundStyle(.secondary)
                }
                if !leads.isEmpty {
                    Text(leads.reduce(0) { $0 + $1.value }, format: .currency(code: "GBP").precision(.fractionLength(0)))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(leads) { lead in MacLeadCard(lead: lead).draggable(lead.id) }
                        if stage == .newLead || stage == .won {
                            Button(action: onAdd) { Label("Add lead", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(
                                .bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(width: 270)
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, let lead = appState.leads.first(where: { $0.id == id }) else { return false }
                Task { await appState.move(lead, to: stage) }
                return true
            }
        }
    }

    private struct MacLeadCard: View {
        @Environment(AppState.self) private var appState
        @Environment(\.openURL) private var openURL
        let lead: Lead
        @State private var showingSchedule = false
        @State private var showingSurvey = false
        private var nextTask: CRMTask? { lead.tasks.first { !$0.completed } }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(value: LeadRoute(id: lead.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(lead.name).fontWeight(.semibold).lineLimit(1)
                            Spacer()
                            if lead.value > 0 { Text(lead.value, format: .currency(code: "GBP").precision(.fractionLength(0))) }
                        }
                        Text([lead.jobType, lead.address].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                            .foregroundStyle(.secondary).lineLimit(2)
                        if let nextTask {
                            Label(nextTask.title, systemImage: "circle").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !lead.assignedTo.isEmpty { Text(lead.assignedTo).font(.caption).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack {
                    if let step = AppState.nextStep(for: lead) {
                        Button(step.title) { perform(step) }.controlSize(.small)
                    }
                    Spacer()
                    if ContactLinks.telephone(lead.phone) != nil {
                        Button {
                            if let url = appState.beginCall(to: lead) { openURL(url) }
                        } label: {
                            Image(systemName: "phone")
                        }.controlSize(.small).help("Call \(lead.name)")
                    }
                    Menu {
                        StageMenu(lead: lead)
                        Button(lead.startDate == nil ? "Schedule job…" : "Edit schedule…") { showingSchedule = true }
                        Button(lead.surveyDate == nil ? "Book survey…" : "Edit survey…") { showingSurvey = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .sheet(isPresented: $showingSchedule) { ScheduleJobSheet(lead: lead) }
            .sheet(isPresented: $showingSurvey) { ScheduleSurveySheet(lead: lead) }
        }

        private func perform(_ step: LeadStep) {
            switch step {
            case .bookSurvey: showingSurvey = true
            case .scheduleJob: showingSchedule = true
            case .recordPayment: Task { await appState.recordFinalPayment(for: lead) }
            case .move(let stage): Task { await appState.move(lead, to: stage) }
            }
        }
    }
#endif

struct LeadRow: View {
    let lead: Lead
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lead.name).fontWeight(.medium)
            Text([lead.jobType, lead.stage.displayName].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(
                .secondary)
        }
    }
}

struct CompletedJobsArchiveView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    private var archived: [Lead] {
        appState.leads.filter { [LeadStage.completed, .paid, .lost].contains($0.stage) }.filter {
            search.isEmpty || [$0.name, $0.jobRef, $0.address, $0.jobType].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    private func archiveDate(_ lead: Lead) -> String { lead.completedDate ?? lead.paidDate ?? String(lead.updatedAt.prefix(10)) }
    private var years: [String] { Array(Set(archived.map { String(archiveDate($0).prefix(4)) })).sorted(by: >) }
    private func months(in year: String) -> [String] {
        Array(Set(archived.map { String(archiveDate($0).prefix(7)) }.filter { $0.hasPrefix(year) })).sorted(by: >)
    }
    private func jobs(in month: String) -> [Lead] {
        archived.filter { archiveDate($0).hasPrefix(month) }.sorted { archiveDate($0) > archiveDate($1) }
    }
    private func monthTitle(_ key: String) -> String {
        guard let date = SupabaseService.date(from: key + "-01") else { return key }; return date.formatted(.dateTime.month(.wide))
    }
    var body: some View {
        List {
            ForEach(years, id: \.self) { year in
                Section(year) {
                    ForEach(months(in: year), id: \.self) { month in
                        DisclosureGroup {
                            ForEach(jobs(in: month)) { lead in
                                NavigationLink {
                                    LeadDetailView(leadID: lead.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(lead.name).fontWeight(.semibold);
                                            Text("\(lead.jobRef) · \(lead.jobType)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text(lead.value, format: .currency(code: "GBP").precision(.fractionLength(0))).fontWeight(
                                                .semibold);
                                            Text(archiveDate(lead)).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical, 4)
                                }
                            }
                        } label: {
                            HStack {
                                Text(monthTitle(month)).fontWeight(.semibold); Spacer();
                                Text("\(jobs(in:month).count)").font(.caption.bold()).foregroundStyle(.secondary).padding(6).background(
                                    .quaternary, in: Circle())
                            }
                        }
                    }
                }
            }
            if archived.isEmpty {
                ContentUnavailableView(
                    "Archive is empty", systemImage: "archivebox", description: Text("Completed, paid and lost work appears here."))
            }
        }.navigationTitle("Archive").searchable(text: $search, prompt: "Search archive")
    }
}

struct ScheduleJobSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var saving = false

    init(lead: Lead) {
        self.lead = lead
        let start = lead.startDate.flatMap(SupabaseService.date(from:)) ?? Calendar.current.startOfDay(for: .now)
        _startDate = State(initialValue: start)
        _endDate = State(
            initialValue: lead.endDate.flatMap(SupabaseService.date(from:)) ?? Calendar.current.date(byAdding: .day, value: 4, to: start)
                ?? start)
    }

    private var duration: Int {
        max(
            1,
            (Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)
            ).day ?? 0) + 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    LabeledContent("Customer", value: lead.name)
                    LabeledContent("Work", value: lead.jobType)
                    if !lead.address.isEmpty { LabeledContent("Address", value: lead.address) }
                }
                Section("Schedule") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Expected finish", selection: $endDate, in: startDate..., displayedComponents: .date)
                    LabeledContent("Time allowed", value: "\(duration) \(duration == 1 ? "day" : "days")")
                }
                Section {
                    Label("This job will appear across these dates in the calendar.", systemImage: "calendar.badge.checkmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(lead.startDate == nil ? "Schedule job" : "Edit schedule")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving || endDate < startDate) }
            }
        }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 430)
        #endif
    }

    private func save() {
        saving = true
        Task {
            var changed = lead
            changed.startDate = PayrollMath.key(startDate)
            changed.endDate = PayrollMath.key(endDate)
            // Only a won job becomes Scheduled here. Editing dates on a live job, or
            // pencilling dates onto an enquiry, must not move it through the pipeline.
            if changed.stage == .won { changed.stage = .scheduled }
            await appState.saveLead(changed)
            saving = false
            if appState.leads.first(where: { $0.id == lead.id })?.startDate == changed.startDate { dismiss() }
        }
    }
}

/// New enquiry. Three things are required — who, how to reach them, and what for.
/// Everything else can be added on the lead later.
struct AddLeadView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let defaultStage: LeadStage
    @AppStorage("lastLeadSource") private var source = "Website"
    @AppStorage("lastJobType") private var jobType = "Roof Repair"
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var value = 0.0
    @State private var depositPlan: DepositPlan = .thirty
    @State private var deposit = 0.0
    @State private var showingEstimate = false
    @State private var createFollowUp = true
    @State private var isSaving = false
    @State private var addressSearch = AddressSearchService()
    @State private var chosenAddress = ""
    @State private var chosenCustomer = ""

    static let jobTypes = [
        "Roof Repair", "New Roof", "Flat Roof", "Solar Installation", "Solar + Battery", "Guttering", "Fascias & Soffits", "Chimney Repair",
        "Roof Inspection", "Other",
    ]
    static let sources = ["Website", "Referral", "Google", "Facebook", "Checkatrade", "MyBuilder", "Phone", "Returning Customer", "Other"]

    private var emailIsValid: Bool { email.isEmpty || ContactLinks.email(email) != nil }
    private var contactIsValid: Bool {
        !phone.trimmingCharacters(in: .whitespaces).isEmpty || !email.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && contactIsValid && emailIsValid && !isSaving }

    private var previousCustomers: [PreviousCustomer] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query != chosenCustomer else { return [] }
        var results: [PreviousCustomer] = []
        var seen = Set<String>()
        for lead in appState.leads where lead.name.localizedCaseInsensitiveContains(query) {
            let key = [lead.name, lead.phone, lead.email].joined(separator: "|").lowercased()
            if seen.insert(key).inserted {
                results.append(
                    PreviousCustomer(
                        id: "lead-\(lead.id)", name: lead.name, phone: lead.phone, email: lead.email, address: lead.address,
                        detail: "\(lead.jobType) · \(lead.stage.displayName)"))
            }
        }
        for contact in appState.contacts where contact.name.localizedCaseInsensitiveContains(query) {
            let key = [contact.name, contact.phone, contact.email].joined(separator: "|").lowercased()
            if seen.insert(key).inserted {
                results.append(
                    PreviousCustomer(
                        id: "contact-\(contact.id)", name: contact.name, phone: contact.phone, email: contact.email,
                        address: contact.address, detail: "Saved customer"))
            }
        }
        return Array(results.prefix(4))
    }

    init(defaultStage: LeadStage) { self.defaultStage = defaultStage }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Customer name", text: $name)
                        #if os(iOS)
                            .textContentType(.name).textInputAutocapitalization(.words)
                        #endif
                        .onChange(of: name) { _, value in if value != chosenCustomer { chosenCustomer = "" } }
                    ForEach(previousCustomers) { customer in
                        Button {
                            choose(customer)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(customer.name).foregroundStyle(.primary);
                                    Text(customer.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.left").foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                            .keyboardType(.phonePad).textContentType(.telephoneNumber)
                        #endif
                    TextField("Email", text: $email)
                        #if os(iOS)
                            .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Customer")
                } footer: {
                    if !emailIsValid {
                        Text("Enter a valid email address.").foregroundStyle(.red)
                    } else if !contactIsValid && !name.isEmpty {
                        Text("Add a phone number or email so the customer can be contacted.")
                    }
                }

                Section {
                    TextField("Address", text: $address, axis: .vertical)
                        .onChange(of: address) { _, value in if value != chosenAddress { addressSearch.search(value) } }
                    ForEach(addressSearch.suggestions) { suggestion in
                        Button {
                            choose(suggestion)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(suggestion.title).foregroundStyle(.primary);
                                if !suggestion.subtitle.isEmpty { Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Picker("Work", selection: $jobType) { ForEach(Self.jobTypes, id: \.self) { Text($0) } }
                    Picker("Heard about us", selection: $source) { ForEach(Self.sources, id: \.self) { Text($0) } }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                } header: {
                    Text("Job")
                } footer: {
                    if let error = addressSearch.errorMessage { Text(error) }
                }

                Section {
                    DisclosureGroup("Estimate & deposit", isExpanded: $showingEstimate) {
                        TextField("Estimated value", value: $value, format: .currency(code: "GBP"))
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: value) { _, total in if let amount = depositPlan.amount(for: total) { deposit = amount } }
                        Picker("Deposit", selection: $depositPlan) { ForEach(DepositPlan.allCases) { Text($0.rawValue).tag($0) } }
                            .onChange(of: depositPlan) { _, plan in if let amount = plan.amount(for: value) { deposit = amount } }
                        if depositPlan == .custom {
                            TextField("Deposit amount", value: $deposit, format: .currency(code: "GBP"))
                        } else if value > 0 {
                            LabeledContent("Deposit to collect", value: deposit.formatted(.currency(code: "GBP")))
                        }
                    }
                    Toggle("Follow up tomorrow", isOn: $createFollowUp)
                } footer: {
                    Text("The value is usually set by the quote. Leave it blank for now if you don't know it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Lead")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Add") { save() }.disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        #if os(macOS)
            .frame(minWidth: 480, idealWidth: 520, minHeight: 560)
        #endif
    }

    private func choose(_ suggestion: AddressSuggestion) {
        addressSearch.clear()
        Task {
            let resolved = await addressSearch.resolve(suggestion)
            let full = [resolved.street, resolved.town, resolved.postcode].filter { !$0.isEmpty }.joined(separator: ", ")
            chosenAddress = full
            address = full
            addressSearch.clear()
        }
    }

    private func choose(_ customer: PreviousCustomer) {
        chosenCustomer = customer.name
        name = customer.name
        phone = customer.phone
        email = customer.email
        chosenAddress = customer.address
        address = customer.address
        source = "Returning Customer"
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            let saved = await appState.addLead(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                jobType: jobType, stage: defaultStage, value: value, deposit: showingEstimate || value > 0 ? deposit : 0, source: source,
                notes: notes, createFollowUp: createFollowUp)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct PreviousCustomer: Identifiable {
    let id: String
    let name: String
    let phone: String
    let email: String
    let address: String
    let detail: String
}
