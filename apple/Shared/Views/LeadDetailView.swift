@preconcurrency import AVFoundation
import PhotosUI
@preconcurrency import Speech
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct PhoneActionMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    let number: String
    var label: String = "Phone"
    /// When the number belongs to a lead, calls are tracked so the outcome can be logged afterwards.
    var lead: Lead? = nil
    var body: some View {
        Menu {
            if let lead {
                Button {
                    if let url = appState.beginCall(to: lead) { openURL(url) }
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
            } else if let url = ContactLinks.telephone(number) {
                Link(destination: url) { Label("Call", systemImage: "phone.fill") }
            }
            if let url = ContactLinks.message(number) { Link(destination: url) { Label("Text message", systemImage: "message.fill") } }
            if let url = ContactLinks.whatsApp(number) {
                Link(destination: url) { Label("WhatsApp", systemImage: "bubble.left.and.bubble.right.fill") }
            }
            Divider()
            Button {
                copyNumber()
            } label: {
                Label("Copy number", systemImage: "doc.on.doc")
            }
        } label: {
            Label(label, systemImage: "phone.fill")
        }
    }
    private func copyNumber() {
        #if os(iOS)
            UIPasteboard.general.string = number
        #elseif os(macOS)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(number, forType: .string)
        #endif
    }
}

struct EmailActionMenu: View {
    let address: String
    var body: some View {
        Menu {
            if let url = ContactLinks.email(address) {
                Link(destination: url) {
                    Label("Compose email", systemImage: "envelope")
                }
            }
            Button {
                copyAddress()
            } label: {
                Label("Copy email address", systemImage: "doc.on.doc")
            }
        } label: {
            Label(address, systemImage: "envelope")
        }
    }

    private func copyAddress() {
        #if os(iOS)
            UIPasteboard.general.string = address
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
        #endif
    }
}

struct LeadDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let leadID: String
    @State private var showingEdit = false
    @State private var showingSurveySchedule = false
    @State private var showingJobSchedule = false
    @State private var showingJobUpdate = false
    @State private var confirmingDelete = false
    @State private var confirmingDeposit = false
    @State private var confirmingFinalPayment = false
    var lead: Lead? { appState.leads.first { $0.id == leadID } }

    var body: some View {
        if let lead {
            Form {
                overview(lead)
                contact(lead)
                job(lead)
                dates(lead)
                if appState.isAdmin { costs(lead) }
                more(lead)
            }
            .formStyle(.grouped)
            .navigationTitle(lead.name)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                Button {
                    showingJobUpdate = true
                } label: {
                    Label("Voice update", systemImage: "mic")
                }
                Button("Edit") { showingEdit = true }
                Menu {
                    StageMenu(lead: lead)
                    Button(lead.surveyDate == nil ? "Book survey…" : "Edit survey…") { showingSurveySchedule = true }
                    Button(lead.startDate == nil ? "Schedule job…" : "Edit schedule…") { showingJobSchedule = true }
                    if appState.isAdmin {
                        Divider()
                        Button("Delete Lead", role: .destructive) { confirmingDelete = true }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            .sheet(isPresented: $showingEdit) { EditLeadView(lead: lead) }
            .sheet(isPresented: $showingSurveySchedule) { ScheduleSurveySheet(lead: lead) }
            .sheet(isPresented: $showingJobSchedule) { ScheduleJobSheet(lead: lead) }
            .sheet(isPresented: $showingJobUpdate) { JobUpdateSheet(leadID: lead.id) }
            .confirmationDialog("Record deposit payment?", isPresented: $confirmingDeposit, titleVisibility: .visible) {
                Button("Record \(CRMFormat.money(lead.deposit, pence: true)) deposit") { Task { await appState.recordDeposit(for: lead) } }
            } message: {
                Text("This reduces the outstanding balance. You can correct it later by editing the lead.")
            }
            .confirmationDialog("Mark this job as paid?", isPresented: $confirmingFinalPayment, titleVisibility: .visible) {
                Button("Mark paid") { Task { await appState.recordFinalPayment(for: lead) } }
            } message: {
                Text("This clears the balance and moves the job to Paid.")
            }
            .confirmationDialog("Delete \(lead.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Lead", role: .destructive) { Task { if await appState.deleteLead(lead) { dismiss() } } }
            } message: {
                Text("This permanently removes the customer lead and its job records.")
            }
        } else {
            ContentUnavailableView("Lead not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    // MARK: Sections

    private func overview(_ lead: Lead) -> some View {
        Section {
            if let step = AppState.nextStep(for: lead) {
                Button {
                    perform(step, for: lead)
                } label: {
                    Label(step.title, systemImage: step.systemImage)
                }
            }
            if let next = lead.tasks.first(where: { !$0.completed }) {
                Button {
                    Task { await appState.toggleLeadTask(leadID: lead.id, taskID: next.id) }
                } label: {
                    Label {
                        Text(next.title)
                    } icon: {
                        Image(systemName: "circle")
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("\(lead.jobType) · \(lead.stage.displayName)")
        }
    }

    private func contact(_ lead: Lead) -> some View {
        Section("Contact") {
            if !lead.phone.isEmpty { PhoneActionMenu(number: lead.phone, label: lead.phone, lead: lead) }
            if !lead.email.isEmpty { EmailActionMenu(address: lead.email) }
            if !lead.address.isEmpty {
                if let maps = ContactLinks.maps(address: lead.address) {
                    Link(destination: maps) { Label(lead.address, systemImage: "map") }
                } else {
                    Label(lead.address, systemImage: "map")
                }
            }
        }
    }

    private func job(_ lead: Lead) -> some View {
        Section("Job") {
            LabeledContent("Value", value: CRMFormat.money(lead.value, pence: true))
            if lead.deposit > 0 {
                LabeledContent("Deposit", value: CRMFormat.money(lead.deposit, pence: true) + (lead.depositPaid ? " · paid" : ""))
            }
            LabeledContent("Balance", value: CRMFormat.money(lead.balance, pence: true))
            if !lead.depositPaid && lead.deposit > 0 { Button("Record deposit paid") { confirmingDeposit = true } }
            if lead.balance > 0 && [.won, .scheduled, .inProgress, .completed, .waitingForPayment].contains(lead.stage) {
                Button("Mark balance paid") { confirmingFinalPayment = true }
            }
            if !lead.assignedTo.isEmpty { LabeledContent("Assigned to", value: lead.assignedTo) }
        }
    }

    private func dates(_ lead: Lead) -> some View {
        Section("Dates") {
            if let survey = lead.surveyDate {
                LabeledContent("Survey", value: [CRMFormat.day(survey), lead.surveyTime].compactMap { $0 }.joined(separator: " · "))
            }
            if let start = lead.startDate { LabeledContent("Starts", value: CRMFormat.day(start)) }
            if let end = lead.endDate { LabeledContent("Expected finish", value: CRMFormat.day(end)) }
            if lead.surveyDate == nil && lead.startDate == nil { Text("Nothing booked").foregroundStyle(.secondary) }
        }
    }

    private func costs(_ lead: Lead) -> some View {
        let entries = appState.timesheets.filter { $0.leadID == lead.id }
        let labour = entries.reduce(0) { $0 + $1.amount }
        let materials = lead.materials.reduce(0) { $0 + (($1.cost ?? 0) * max(1, $1.quantity)) }
        let profit = lead.value - labour - materials
        return Section {
            LabeledContent("Labour", value: "\(PayrollMath.days(entries).formatted()) days · \(CRMFormat.money(labour))")
            LabeledContent("Materials", value: CRMFormat.money(materials))
            LabeledContent("Forecast profit") {
                Text(CRMFormat.money(profit)).foregroundStyle(profit < 0 ? Color.red : Color.primary)
            }
        } header: {
            Text("Cost")
        }
    }

    private func more(_ lead: Lead) -> some View {
        Section {
            NavigationLink {
                LeadTasksView(leadID: lead.id)
            } label: {
                LabeledContent {
                    Text("\(lead.tasks.filter(\.completed).count) of \(lead.tasks.count)")
                } label: {
                    Label("Checklist", systemImage: "checklist")
                }
            }
            NavigationLink {
                LeadNotesView(leadID: lead.id)
            } label: {
                LabeledContent {
                    Text(lead.notes.isEmpty ? "" : "\(lead.notes.count)")
                } label: {
                    Label("Notes", systemImage: "note.text")
                }
            }
            NavigationLink {
                LeadPhotosView(leadID: lead.id)
            } label: {
                LabeledContent {
                    Text(lead.photos.isEmpty ? "" : "\(lead.photos.count)")
                } label: {
                    Label("Photos", systemImage: "photo")
                }
            }
            NavigationLink {
                LeadFilesView(leadID: lead.id)
            } label: {
                LabeledContent {
                    Text(lead.files.isEmpty ? "" : "\(lead.files.count)")
                } label: {
                    Label("Files", systemImage: "doc")
                }
            }
            NavigationLink {
                LeadMaterialsView(leadID: lead.id)
            } label: {
                LabeledContent {
                    Text(lead.materials.isEmpty ? "" : "\(lead.materials.count)")
                } label: {
                    Label("Materials", systemImage: "shippingbox")
                }
            }
            NavigationLink {
                LeadSurveyView(lead: lead).navigationTitle("Surveys")
            } label: {
                LabeledContent {
                    Text(surveyCount(lead))
                } label: {
                    Label("Surveys", systemImage: "ruler")
                }
            }
            NavigationLink {
                LeadQuotesView(lead: lead).navigationTitle("Quotes")
            } label: {
                LabeledContent {
                    Text(quoteCount(lead))
                } label: {
                    Label("Quotes", systemImage: "doc.text")
                }
            }
        }
    }

    private func surveyCount(_ lead: Lead) -> String {
        let n = appState.surveys.filter { $0.leadID == lead.id }.count; return n == 0 ? "" : "\(n)"
    }
    private func quoteCount(_ lead: Lead) -> String {
        let n = appState.quotes.filter { $0.leadID == lead.id }.count; return n == 0 ? "" : "\(n)"
    }

    private func perform(_ step: LeadStep, for lead: Lead) {
        switch step {
        case .bookSurvey: showingSurveySchedule = true
        case .scheduleJob: showingJobSchedule = true
        case .recordPayment: confirmingFinalPayment = true
        case .move(let stage): Task { await appState.move(lead, to: stage) }
        }
    }
}

// MARK: - Sub-screens

struct LeadTasksView: View {
    @Environment(AppState.self) private var appState
    let leadID: String
    @State private var adding = false
    @State private var editing: JobChecklistItem?
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    var body: some View {
        List {
            if let lead {
                Section {
                    ForEach(lead.tasks) { task in
                        HStack {
                            Button {
                                Task { await appState.toggleLeadTask(leadID: lead.id, taskID: task.id) }
                            } label: {
                                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(
                                    task.completed ? .green : .secondary)
                            }.buttonStyle(.plain)
                            Button {
                                editing = JobChecklistItem(lead: lead, task: task)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).strikethrough(task.completed).foregroundStyle(task.completed ? .secondary : .primary)
                                    if let due = task.dueDate {
                                        Text(CRMFormat.relativeDay(due)).font(.subheadline).foregroundStyle(
                                            !task.completed && due < SupabaseService.today ? Color.red : Color.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await appState.deleteLeadTask(leadID: lead.id, taskID: task.id) }
                            }
                        }
                    }
                    if lead.tasks.isEmpty { Text("Empty").foregroundStyle(.secondary) }
                } header: {
                    Text("\(lead.tasks.filter(\.completed).count) of \(lead.tasks.count) done")
                }
            }
        }
        .navigationTitle("Checklist")
        .toolbar {
            Button {
                adding = true
            } label: {
                Label("Add task", systemImage: "plus")
            }
        }
        .sheet(isPresented: $adding) { if let lead { AddLeadTaskSheet(lead: lead) } }
        .sheet(item: $editing) { EditJobTaskView(item: $0) }
    }
}

struct LeadNotesView: View {
    @Environment(AppState.self) private var appState
    let leadID: String
    @State private var newNote = ""
    @State private var saving = false
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    var body: some View {
        List {
            Section {
                TextField("Add a note…", text: $newNote, axis: .vertical).lineLimit(1...5)
                    .onSubmit(save)
                if !newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(saving ? "Saving…" : "Save note") { save() }.disabled(saving)
                }
            }
            if let lead {
                Section {
                    ForEach(lead.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.content).textSelection(.enabled)
                            Text([note.author, CRMFormat.day(note.date)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    if lead.notes.isEmpty { Text("Empty").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Notes")
    }
    private func save() {
        let value = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !saving else { return }
        saving = true
        Task {
            if await appState.addJobNote(leadID: leadID, content: value) { newNote = "" }; saving = false
        }
    }
}

struct LeadPhotosView: View {
    @Environment(AppState.self) private var appState
    let leadID: String
    @State private var adding = false
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 8)]
    var body: some View {
        ScrollView {
            if let lead {
                if lead.photos.isEmpty {
                    ContentUnavailableView("No photos", systemImage: "camera")
                    .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(["Before", "During", "After"], id: \.self) { category in
                            let photos = lead.photos.filter { $0.category == category }
                            if !photos.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(category).font(.headline)
                                    LazyVGrid(columns: columns, spacing: 8) {
                                        ForEach(photos) { photo in
                                            SecureThumbnail(locator: photo.url, caption: photo.caption)
                                                .contextMenu {
                                                    Button("Delete photo", role: .destructive) {
                                                        Task { await appState.deleteLeadPhoto(leadID: lead.id, photoID: photo.id) }
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Photos")
        .toolbar {
            Button {
                adding = true
            } label: {
                Label("Add photo", systemImage: "camera")
            }
        }
        .sheet(isPresented: $adding) { if let lead { AddPhotoSheet(lead: lead) } }
    }
}

struct LeadFilesView: View {
    @Environment(AppState.self) private var appState
    let leadID: String
    @State private var adding = false
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    var body: some View {
        List {
            if let lead {
                ForEach(lead.files) { file in
                    if let raw = file.url {
                        SecureAttachmentLink(locator: raw, label: file.name, icon: file.type == "image" ? "photo" : "doc")
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    Task { await appState.deleteLeadFile(leadID: lead.id, fileID: file.id) }
                                }
                            }
                    } else {
                        Label(file.name, systemImage: file.type == "image" ? "photo" : "doc")
                    }
                }
                if lead.files.isEmpty { Text("Empty").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Files")
        .toolbar {
            Button {
                adding = true
            } label: {
                Label("Upload file", systemImage: "plus")
            }
        }
        .sheet(isPresented: $adding) { if let lead { AddFileSheet(lead: lead) } }
    }
}

struct LeadMaterialsView: View {
    @Environment(AppState.self) private var appState
    let leadID: String
    @State private var adding = false
    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    var body: some View {
        List {
            if let lead {
                ForEach(lead.materials) { material in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(material.name).fontWeight(.medium); Spacer();
                            Text("\(material.quantity.formatted()) \(material.unit)").foregroundStyle(.secondary)
                        }
                        let detail = [material.supplier, material.cost.map { CRMFormat.money($0, pence: true) }].compactMap { $0 }.joined(
                            separator: " · ")
                        if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                        HStack {
                            Toggle("Ordered", isOn: binding(for: material, in: lead, delivered: false)).toggleStyle(.button).controlSize(
                                .small)
                            Toggle("Delivered", isOn: binding(for: material, in: lead, delivered: true)).toggleStyle(.button).controlSize(
                                .small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if lead.materials.isEmpty { Text("Empty").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Materials")
        .toolbar {
            Button {
                adding = true
            } label: {
                Label("Add material", systemImage: "plus")
            }
        }
        .sheet(isPresented: $adding) { if let lead { AddMaterialSheet(lead: lead) } }
    }
    private func binding(for material: CRMMaterial, in lead: Lead, delivered: Bool) -> Binding<Bool> {
        Binding(
            get: { delivered ? material.delivered : material.ordered },
            set: { value in
                Task {
                    await appState.setMaterialStatus(
                        leadID: lead.id, materialID: material.id, ordered: delivered ? (value ? true : material.ordered) : value,
                        delivered: delivered ? value : (value ? material.delivered : false))
                }
            }
        )
    }
}

/// A photo thumbnail loaded through a short-lived signed URL.
struct SecureThumbnail: View {
    let locator: String
    let caption: String?
    @State private var url: URL?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                } else if failed {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if let caption, !caption.isEmpty { Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .task(id: locator) { do { url = try await SupabaseService.shared.signedAttachmentURL(for: locator) } catch { failed = true } }
    }
}

private final class SpeechAudioBufferSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}

private func makeSpeechAudioTap(for sink: SpeechAudioBufferSink) -> AVAudioNodeTapBlock {
    { buffer, _ in
        sink.append(buffer)
    }
}

@MainActor
private final class JobUpdateSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_GB"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggleRecording() async {
        if isRecording { stopRecording() } else { await startRecording() }
    }

    func startRecording() async {
        errorMessage = nil
        guard recognizer != nil else { errorMessage = "Speech recognition is not available on this device."; return }
        guard await speechAccessAllowed() else {
            errorMessage = "Speech recognition permission is off. Enable it for ProLine CRM in Privacy & Security settings."
            return
        }
        #if os(iOS)
            guard await microphoneAccessAllowed() else {
                errorMessage = "Microphone permission is off. Enable it for ProLine CRM in Privacy & Security settings."
                return
            }
        #endif

        stopRecording()
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        request = newRequest

        #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                errorMessage = "ProLine CRM could not start the microphone: \(error.localizedDescription)"
                return
            }
        #endif

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { errorMessage = "No working microphone input was found."; return }
        removeInputTapIfNeeded()
        let bufferSink = SpeechAudioBufferSink(request: newRequest)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeSpeechAudioTap(for: bufferSink))
        tapInstalled = true
        guard let recognizer else { return }
        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            Task { @MainActor in
                if let text = result?.bestTranscription.formattedString { self?.transcript = text }
                if error != nil || result?.isFinal == true { self?.stopRecording() }
            }
        }
        do {
            audioEngine.prepare(); try audioEngine.start(); isRecording = true
        } catch {
            removeInputTapIfNeeded(); request = nil; recognitionTask = nil
            errorMessage = "ProLine CRM could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        if audioEngine.isRunning { audioEngine.stop() }
        removeInputTapIfNeeded()
        request?.endAudio(); recognitionTask?.cancel(); request = nil; recognitionTask = nil; isRecording = false
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func removeInputTapIfNeeded() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func speechAccessAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        @unknown default: return false
        }
    }

    #if os(iOS)
        private func microphoneAccessAllowed() async -> Bool {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
                }
            @unknown default: return false
            }
        }
    #endif
}

struct JobUpdateSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let leadID: String
    @StateObject private var speech = JobUpdateSpeechRecognizer()
    @State private var analysis: JobNoteAnalysis?
    @State private var progressNote = ""
    @State private var selectedSuggestionIDs: Set<String> = []
    @State private var selectedMaterialIDs: Set<String> = []
    @State private var includeProgressNote = true
    @State private var isAnalysing = false
    @State private var isSaving = false

    private var lead: Lead? { appState.leads.first { $0.id == leadID } }
    private var cleanTranscript: String { speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let lead {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Update job", systemImage: "mic.fill").font(.title2.bold())
                            Text("\(lead.name) · \(lead.jobRef)").foregroundStyle(.secondary)
                            Text(
                                "Describe what was completed today and anything needed next. Nothing is saved until you review and confirm it."
                            ).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
                        }
                        transcriptCard
                        if isAnalysing {
                            HStack(spacing: 12) {
                                ProgressView(); Text("Comparing this update with the job tasks and materials…").foregroundStyle(.secondary)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        } else if let analysis {
                            reviewCard(analysis, lead: lead)
                        }
                    } else {
                        ContentUnavailableView("Job not found", systemImage: "exclamationmark.triangle")
                    }
                }.padding(20)
            }
            .navigationTitle("Job update")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.stopRecording(); dismiss()
                    }.disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    if let analysis {
                        Button {
                            apply(analysis)
                        } label: {
                            if isSaving {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Confirm and save update", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                            }
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(
                            isSaving || (!includeProgressNote && selectedSuggestionIDs.isEmpty && selectedMaterialIDs.isEmpty))
                    } else {
                        Button {
                            analyse()
                        } label: {
                            Label("Review proposed changes", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(cleanTranscript.isEmpty || isAnalysing)
                    }
                }.padding(14).background(.bar)
            }
        }
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 700)
        #endif
        .onDisappear { speech.stopRecording() }
        .onChange(of: speech.transcript) { _, _ in
            if analysis != nil { analysis = nil; selectedSuggestionIDs = []; selectedMaterialIDs = [] }
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(speech.isRecording ? "Listening…" : "Spoken update").font(.headline)
                    Text(speech.isRecording ? "Speak naturally, then tap Stop." : "You can also type or correct the transcript.").font(
                        .caption
                    ).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await speech.toggleRecording() }
                } label: {
                    Label(speech.isRecording ? "Stop" : "Record", systemImage: speech.isRecording ? "stop.fill" : "mic.fill").font(
                        .headline
                    ).padding(.horizontal, 8).frame(minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(speech.isRecording ? .red : Color.accentColor)
            }
            TextEditor(text: $speech.transcript).frame(minHeight: 130).padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(
                        speech.isRecording ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: speech.isRecording ? 2 : 1))
            if let error = speech.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
            }
            if cleanTranscript.isEmpty {
                Text("Example: “I’ve felted and battened the front side, and I need 12 packs of batten in the morning.”").font(.caption)
                    .foregroundStyle(.secondary)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func reviewCard(_ analysis: JobNoteAnalysis, lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review before saving", systemImage: "checkmark.shield").font(.headline)
            if analysis.analysisMode == "note_only" {
                Label(
                    "AI suggestions are temporarily unavailable. Your spoken update is still ready to save as a progress note.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout).foregroundStyle(Color.accentColor).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            Toggle(isOn: $includeProgressNote) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add progress note").fontWeight(.semibold);
                    Text("Saved in this job’s Notes timeline").font(.caption).foregroundStyle(.secondary)
                }
            }
            if includeProgressNote {
                TextEditor(text: $progressNote).frame(minHeight: 86).padding(8).background(
                    Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider(); Text("Tasks for \(lead.name)").font(.headline)
            if analysis.suggestions.isEmpty {
                Text("No task changes were confidently identified. You can save the progress note only.").font(.callout).foregroundStyle(
                    .secondary)
            } else {
                ForEach(analysis.suggestions) { suggestion in
                    let selected = selectedSuggestionIDs.contains(suggestion.id)
                    Button {
                        toggle(suggestion.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(
                                selected ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(suggestion.action == .complete ? "Mark task completed" : "Add next-action task").font(.caption.bold())
                                    .foregroundStyle(suggestion.action == .complete ? .green : Color.accentColor)
                                Text(suggestion.title).fontWeight(.semibold).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                if let dueDate = suggestion.dueDate {
                                    Label(dueDate, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(suggestion.reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }; Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if suggestion.id != analysis.suggestions.last?.id { Divider().padding(.leading, 34) }
                }
                Text("Selected tasks will be saved inside \(lead.name)’s job—not as general tasks.").font(.caption).foregroundStyle(
                    .secondary)
            }
            if let materials = analysis.materials, !materials.isEmpty {
                Divider(); Text("Proposed materials").font(.headline)
                ForEach(materials) { material in
                    let selected = selectedMaterialIDs.contains(material.id)
                    Button {
                        toggleMaterialSuggestion(material.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(
                                selected ? Color.accentColor : .secondary)
                            Image(systemName: "shippingbox").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(material.name).fontWeight(.semibold).foregroundStyle(.primary)
                                Text("\(material.quantity.formatted()) \(material.unit)").font(.callout.bold()).foregroundStyle(
                                    Color.accentColor)
                                Text(material.reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }; Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("Selected items will be added to this job’s Materials list.").font(.caption).foregroundStyle(.secondary)
            }
            Text(
                "Existing job: \(lead.tasks.filter { !$0.completed }.count) open tasks · \(lead.tasks.filter(\.completed).count) completed"
            ).font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.25)))
    }

    private func analyse() {
        speech.stopRecording(); let transcript = cleanTranscript; guard !transcript.isEmpty else { return }
        Task {
            isAnalysing = true; defer { isAnalysing = false }
            if let result = await appState.analyseJobNote(leadID: leadID, note: transcript) {
                analysis = result; progressNote = result.summary; selectedSuggestionIDs = Set(result.suggestions.map(\.id));
                selectedMaterialIDs = Set((result.materials ?? []).map(\.id))
            }
        }
    }

    private func apply(_ analysis: JobNoteAnalysis) {
        let selected = analysis.suggestions.filter { selectedSuggestionIDs.contains($0.id) }
        let selectedMaterials = (analysis.materials ?? []).filter { selectedMaterialIDs.contains($0.id) }
        Task {
            isSaving = true; defer { isSaving = false }
            if await appState.applyJobUpdate(
                leadID: leadID, progressNote: includeProgressNote ? progressNote : nil, suggestions: selected, materials: selectedMaterials)
            {
                dismiss()
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedSuggestionIDs.contains(id) { selectedSuggestionIDs.remove(id) } else { selectedSuggestionIDs.insert(id) }
    }
    private func toggleMaterialSuggestion(_ id: String) {
        if selectedMaterialIDs.contains(id) { selectedMaterialIDs.remove(id) } else { selectedMaterialIDs.insert(id) }
    }
}

private struct AddLeadTaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var title = ""
    @State private var hasDueDate = true
    @State private var dueDate = Date()
    @State private var priority = "medium"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Next action", text: $title)
                TextField("Details, access or expected result", text: $notes, axis: .vertical).lineLimit(2...5)
                Picker("Priority", selection: $priority) {
                    Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
                }
                Toggle("Set due date", isOn: $hasDueDate)
                if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            }
            .navigationTitle("Add task for \(lead.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let due = hasDueDate ? SupabaseService.localDay(for: dueDate) : nil
                        Task {
                            if await appState.addLeadTask(
                                leadID: lead.id, title: title, dueDate: due, priority: priority, notes: notes.isEmpty ? nil : notes)
                            {
                                dismiss()
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 390)
    }
}

struct AddPhotoSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var caption = ""
    @State private var category: String
    @State private var selected: PickedAttachment?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var choosingFile = false
    @State private var uploading = false

    init(lead: Lead) {
        self.lead = lead
        // Default the category to where the job is.
        _category = State(
            initialValue: [.completed, .waitingForPayment, .paid].contains(lead.stage)
                ? "After" : (lead.stage == .inProgress ? "During" : "Before"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    #if os(iOS)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take photo", systemImage: "camera")
                            }
                        }
                    #endif
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        choosingFile = true
                    } label: {
                        Label("Choose file…", systemImage: "folder")
                    }
                    if let selected {
                        HStack {
                            if let image = selected.previewImage {
                                image.resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading) {
                                Text(selected.filename).lineLimit(1);
                                Text(ByteCountFormatter.string(fromByteCount: Int64(selected.data.count), countStyle: .file)).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Picker("Stage", selection: $category) { ForEach(["Before", "During", "After"], id: \.self) { Text($0) } }.pickerStyle(
                        .segmented)
                    TextField("Caption (optional)", text: $caption)
                }
                if uploading { Section { ProgressView("Uploading…") } }
            }
            .formStyle(.grouped)
            .navigationTitle("Add photo")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) { Button("Upload") { upload() }.disabled(selected == nil || uploading) }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in selected = loadAttachment(result) }
            .onChange(of: pickerItem) { _, item in Task { await load(item) } }
            #if os(iOS)
                .fullScreenCover(isPresented: $showingCamera) {
                    CameraPicker { data in
                        selected = PickedAttachment(
                            data: data, filename: "photo-\(Int(Date.now.timeIntervalSince1970)).jpg", contentType: "image/jpeg")
                    }
                    .ignoresSafeArea()
                }
            #endif
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), data.count <= 25 * 1_024 * 1_024 else { return }
        let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
        selected = PickedAttachment(
            data: data, filename: "photo-\(Int(Date.now.timeIntervalSince1970)).\(type?.preferredFilenameExtension ?? "jpg")",
            contentType: type?.preferredMIMEType ?? "image/jpeg")
    }

    private func upload() {
        guard let selected else { return }
        uploading = true
        Task {
            if await appState.uploadLeadPhoto(
                leadID: lead.id, data: selected.data, filename: selected.filename, contentType: selected.contentType, category: category,
                caption: caption.isEmpty ? nil : caption)
            {
                dismiss()
            }
            uploading = false
        }
    }
}

#if os(iOS)
    /// The system camera, returning a JPEG.
    struct CameraPicker: UIViewControllerRepresentable {
        let onCapture: (Data) -> Void
        @Environment(\.dismiss) private var dismiss

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: CameraPicker
            init(_ parent: CameraPicker) { self.parent = parent }
            func imagePickerController(
                _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8) {
                    parent.onCapture(data)
                }
                parent.dismiss()
            }
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        }
    }
#endif

struct AddFileSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var selected: PickedAttachment?
    @State private var choosing = false
    @State private var uploading = false
    var body: some View {
        NavigationStack {
            Form {
                Button {
                    choosing = true
                } label: {
                    Label(selected?.filename ?? "Choose document or image…", systemImage: "doc.badge.plus")
                }
                if let selected {
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(selected.data.count), countStyle: .file))
                }
                if uploading { ProgressView("Uploading securely…") }
            }
            .navigationTitle("Upload File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) { Button("Upload") { upload() }.disabled(selected == nil || uploading) }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.item]) { result in selected = loadAttachment(result) }
        }.frame(minWidth: 420, minHeight: 260)
    }
    private func upload() {
        guard let selected else { return }; uploading = true;
        Task {
            if await appState.uploadLeadFile(
                leadID: lead.id, data: selected.data, filename: selected.filename, contentType: selected.contentType)
            {
                dismiss()
            }; uploading = false
        }
    }
}

struct PickedAttachment {
    let data: Data
    let filename: String
    let contentType: String
    var previewImage: Image? {
        #if os(iOS)
            UIImage(data: data).map(Image.init(uiImage:))
        #else
            NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

func loadAttachment(_ result: Result<URL, Error>) -> PickedAttachment? {
    guard case let .success(url) = result else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url), data.count <= 25 * 1_024 * 1_024 else { return nil }
    let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    return PickedAttachment(data: data, filename: url.lastPathComponent, contentType: contentType)
}

struct SecureAttachmentLink: View {
    let locator: String
    let label: String
    let icon: String
    @State private var destination: URL?
    @State private var failed = false
    var body: some View {
        Group {
            if let destination {
                Link(destination: destination) { Label(label, systemImage: icon) }
            } else if failed {
                Label(label, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                HStack {
                    ProgressView().controlSize(.small); Text(label)
                }
            }
        }
        .task(id: locator) {
            do { destination = try await SupabaseService.shared.signedAttachmentURL(for: locator) } catch { failed = true }
        }
    }
}
struct AddMaterialSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var name = ""
    @State private var quantity = 1.0
    @State private var unit = "item"
    @State private var cost: Double?
    @State private var supplier = ""
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Material", text: $name)
                HStack {
                    TextField("Quantity", value: $quantity, format: .number); TextField("Unit", text: $unit).frame(maxWidth: 90)
                }
                TextField("Cost (optional)", value: $cost, format: .currency(code: "GBP"))
                TextField("Supplier (optional)", text: $supplier)
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .navigationTitle("Add material")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Add") {
                        isSaving = true
                        Task {
                            if await appState.addMaterial(
                                leadID: lead.id, name: name, quantity: quantity, unit: unit, cost: cost, supplier: supplier)
                            {
                                dismiss()
                            }; isSaving = false
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 300)
        #endif
    }
}

private struct EditLeadView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var lead: Lead
    @State private var depositPlan: DepositPlan
    @State private var addressSearch = AddressSearchService()
    @State private var selectedAddress = ""
    @State private var isSaving = false

    private var validDates: Bool {
        [lead.surveyDate, lead.startDate, lead.endDate].allSatisfy {
            $0 == nil || $0?.isEmpty == true || SupabaseService.date(from: $0!) != nil
        }
    }
    private var validEmail: Bool { lead.email.isEmpty || ContactLinks.email(lead.email) != nil }
    private var validDeposit: Bool { lead.deposit >= 0 && lead.deposit <= lead.value }
    private var canSave: Bool {
        !lead.name.trimmingCharacters(in: .whitespaces).isEmpty && validDates && validEmail && validDeposit && !isSaving
    }

    init(lead: Lead) {
        _lead = State(initialValue: lead)
        _depositPlan = State(initialValue: DepositPlan.matching(total: lead.value, deposit: lead.deposit))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $lead.name)
                    TextField("Phone", text: $lead.phone)
                    TextField("Email", text: $lead.email)
                    addressLookup
                }
                Section("Job") {
                    Picker("Work", selection: $lead.jobType) {
                        ForEach(AddLeadView.jobTypes, id: \.self) { Text($0) }
                        if !AddLeadView.jobTypes.contains(lead.jobType) { Text(lead.jobType).tag(lead.jobType) }
                    }
                    Picker("Stage", selection: $lead.stage) { ForEach(LeadStage.allCases) { Text($0.displayName).tag($0) } }
                    Picker("Source", selection: $lead.source) {
                        ForEach(AddLeadView.sources, id: \.self) { Text($0) }
                        if !AddLeadView.sources.contains(lead.source) {
                            Text(lead.source.isEmpty ? "Not set" : lead.source).tag(lead.source)
                        }
                    }
                    assigneePicker
                }
                Section {
                    TextField("Value", value: $lead.value, format: .currency(code: "GBP"))
                        .onChange(of: lead.value) { _, total in if let amount = depositPlan.amount(for: total) { lead.deposit = amount } }
                    Picker("Deposit", selection: $depositPlan) { ForEach(DepositPlan.allCases) { Text($0.rawValue).tag($0) } }
                        .onChange(of: depositPlan) { _, plan in if let amount = plan.amount(for: lead.value) { lead.deposit = amount } }
                    if depositPlan == .custom {
                        TextField("Deposit amount", value: $lead.deposit, format: .currency(code: "GBP"))
                    } else {
                        LabeledContent("Deposit to collect", value: CRMFormat.money(lead.deposit, pence: true))
                    }
                    Toggle("Deposit paid", isOn: $lead.depositPaid)
                } header: {
                    Text("Money")
                } footer: { if !validDeposit { Text("Deposit cannot be more than the job value.").foregroundStyle(.red) } }
                Section {
                    OptionalDateField(label: "Survey date", icon: "calendar", value: $lead.surveyDate)
                    if lead.surveyDate != nil {
                        TextField("Survey arrival time", text: Binding($lead.surveyTime, default: ""), prompt: Text("e.g. 09:30"))
                    }
                    OptionalDateField(label: "Job start", icon: "hammer", value: $lead.startDate)
                    OptionalDateField(label: "Expected finish", icon: "flag.checkered", value: $lead.endDate)
                } header: {
                    Text("Schedule")
                } footer: {
                    if !validDates { Text("One of the saved dates is invalid. Please select it again.").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .navigationTitle("Edit Lead")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        isSaving = true
                        Task {
                            if await appState.saveLead(lead) { dismiss() }; isSaving = false
                        }
                    }.disabled(!canSave)
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 600)
        #endif
    }

    private var assigneePicker: some View {
        Group {
            if appState.isAdmin {
                Picker("Assigned to", selection: $lead.assignedTo) {
                    Text("Unassigned").tag("")
                    ForEach(appState.users) { user in Text(user.name).tag(user.name) }
                    if !lead.assignedTo.isEmpty
                        && !appState.users.contains(where: { $0.name.caseInsensitiveCompare(lead.assignedTo) == .orderedSame })
                    {
                        Text(lead.assignedTo).tag(lead.assignedTo)
                    }
                }
            } else {
                LabeledContent("Assigned to", value: lead.assignedTo.isEmpty ? "Unassigned" : lead.assignedTo)
            }
        }
    }

    private var addressLookup: some View {
        Group {
            TextField("Address", text: $lead.address, axis: .vertical)
                .onChange(of: lead.address) { _, value in if value != selectedAddress { addressSearch.search(value) } }
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
            if let error = addressSearch.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func choose(_ suggestion: AddressSuggestion) {
        addressSearch.clear()
        Task {
            let resolved = await addressSearch.resolve(suggestion)
            let value = [resolved.street, resolved.town, resolved.postcode].filter { !$0.isEmpty }.joined(separator: ", ")
            selectedAddress = value; lead.address = value; addressSearch.clear()
        }
    }
}

struct ScheduleSurveySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let lead: Lead
    @State private var surveyDate: Date
    @State private var surveyTime: Date
    @State private var saving = false

    init(lead: Lead) {
        self.lead = lead
        _surveyDate = State(initialValue: lead.surveyDate.flatMap(SupabaseService.date(from:)) ?? Calendar.current.startOfDay(for: .now))
        let parts = (lead.surveyTime ?? "09:00").split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = parts.first ?? 9; components.minute = parts.count > 1 ? parts[1] : 0
        _surveyTime = State(initialValue: Calendar.current.date(from: components) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    LabeledContent("Name", value: lead.name); if !lead.address.isEmpty { LabeledContent("Address", value: lead.address) };
                    LabeledContent("Job", value: lead.jobType)
                }
                Section("Survey appointment") {
                    DatePicker("Survey date", selection: $surveyDate, displayedComponents: .date)
                    DatePicker("Arrival time", selection: $surveyTime, displayedComponents: .hourAndMinute)
                }
                Section {
                    Label(
                        "The survey will appear in the calendar and the lead will move to Survey Booked.",
                        systemImage: "calendar.badge.checkmark"
                    ).font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(lead.surveyDate == nil ? "Schedule survey" : "Edit survey")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving) }
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
            changed.surveyDate = PayrollMath.key(surveyDate)
            changed.surveyTime = String(
                format: "%02d:%02d", Calendar.current.component(.hour, from: surveyTime),
                Calendar.current.component(.minute, from: surveyTime))
            if lead.stage == .newLead { changed.stage = .surveyBooked }
            await appState.saveLead(changed)
            saving = false
            if appState.leads.first(where: { $0.id == lead.id })?.surveyDate == changed.surveyDate { dismiss() }
        }
    }
}

private struct OptionalDateField: View {
    let label: String
    let icon: String
    @Binding var value: String?
    private var date: Binding<Date> {
        Binding(
            get: { value.flatMap(SupabaseService.date(from:)) ?? Calendar.current.startOfDay(for: .now) },
            set: { value = PayrollMath.key($0) })
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(value == nil ? Color.secondary : Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if value == nil {
                    Text("Not scheduled").foregroundStyle(.secondary)
                } else {
                    Text(date.wrappedValue.formatted(date: .long, time: .omitted)).fontWeight(.medium)
                }
            }
            Spacer()
            if value == nil {
                Button("Choose date") { value = PayrollMath.key(Date.now) }.buttonStyle(.bordered)
            } else {
                DatePicker(label, selection: date, displayedComponents: .date).labelsHidden().datePickerStyle(.compact)
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Clear \(label.lowercased())")
            }
        }.padding(.vertical, 4)
    }
}
private extension Binding where Value == String {
    init(_ source: Binding<String?>, default fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
