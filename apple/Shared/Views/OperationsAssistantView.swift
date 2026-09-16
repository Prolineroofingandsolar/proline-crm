import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

private struct AssistantMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let leadIDs: [String]
    let actions: [CRMAssistantAction]
    enum Role { case user, assistant }
}

struct OperationsAssistantView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var messages = [
        AssistantMessage(
            role: .assistant,
            text:
                "I’m your roofing operations assistant. I can inspect the pipeline, turn updates into tasks, plan surveys or jobs, suggest stage changes and draft customer emails. I will always ask before changing anything.",
            leadIDs: [], actions: [])
    ]
    @State private var isThinking = false
    @State private var pendingAction: CRMAssistantAction?
    @State private var reviewQueue: [CRMAssistantAction] = []
    @State private var appliedActionIDs = Set<String>()
    @State private var isApplyingAction = false
    @State private var actionFailure: String?
    @State private var attachment: AssistantAttachment?
    @State private var choosingAttachment = false
    @State private var attachmentError: String?

    private let suggestions = [
        "Create my daily company plan", "Which quotes need following up?", "What is putting live jobs at risk?",
        "How can we grow this week?", "Show outstanding balances",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor);
                    Text("Gemini roofing operations assistant").font(.caption); Spacer();
                    Label("Approval required for changes", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).frame(height: 38).background(Color.accentColor.opacity(0.07))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { message in messageBubble(message).id(message.id) }
                            if isThinking {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small); Text("Checking your CRM…").foregroundStyle(.secondary)
                                }.padding(12)
                            }
                            if messages.count == 1 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Try asking").font(.caption.bold()).foregroundStyle(.secondary);
                                    ForEach(suggestions, id: \.self) { suggestion in
                                        Button(suggestion) { Task { await submit(suggestion) } }.buttonStyle(.bordered).controlSize(.small)
                                    }
                                }.padding(.top, 4)
                            }
                        }.padding(16)
                    }.onChange(of: messages.count) {
                        if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                Divider()
                if let attachment {
                    HStack(spacing: 10) {
                        Image(systemName: attachment.mimeType == "application/pdf" ? "doc.richtext" : "photo")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            self.attachment = nil; attachmentError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }.padding(.horizontal, 16).padding(.top, 10)
                }
                if let attachmentError {
                    Text(attachmentError).font(.caption).foregroundStyle(.red).padding(.horizontal, 16).padding(.top, 8)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                        chooseAttachment()
                    } label: {
                        Image(systemName: "paperclip.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor).help("Add a quote, PDF or job photo")
                    TextField("Ask about the roofing business…", text: $input, axis: .vertical).lineLimit(1...4).textFieldStyle(
                        .roundedBorder
                    ).onSubmit { submitInput() }
                    Button {
                        submitInput()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }.buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(
                        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }.padding(14)
            }
            .navigationTitle("ProLine Assistant")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $pendingAction) { action in actionReview(action) }
            .onAppear {
                guard let prompt = appState.assistantDraftPrompt else { return }
                appState.assistantDraftPrompt = nil
                Task { await submit(prompt) }
            }
            #if !os(macOS)
                .fileImporter(isPresented: $choosingAttachment, allowedContentTypes: [.pdf, .image]) { selectAttachment($0) }
            #endif
        }
        #if os(macOS)
            .frame(minWidth: 680, minHeight: 650)
        #endif
    }

    @ViewBuilder private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) };
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text).textSelection(.enabled);
                if !message.leadIDs.isEmpty {
                    ForEach(message.leadIDs.prefix(8), id: \.self) { id in
                        if let lead = appState.leads.first(where: { $0.id == id }) {
                            NavigationLink {
                                LeadDetailView(leadID: id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(lead.name).fontWeight(.semibold);
                                        Text("\(lead.jobRef) · \(lead.stage.displayName)").font(.caption).foregroundStyle(.secondary)
                                    }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.padding(10).background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                };
                ForEach(message.actions) { action in
                    Button {
                        actionFailure = nil; pendingAction = action
                    } label: {
                        HStack {
                            Image(systemName: appliedActionIDs.contains(action.id) ? "checkmark.circle.fill" : icon(for: action.kind))
                                .foregroundStyle(appliedActionIDs.contains(action.id) ? .green : Color.accentColor);
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title).fontWeight(.semibold);
                                Text(appliedActionIDs.contains(action.id) ? "Approved and applied" : action.explanation).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(2)
                            }; Spacer();
                            Text(appliedActionIDs.contains(action.id) ? "Done" : "Review").font(.caption.bold()).padding(.horizontal, 10)
                                .padding(.vertical, 6).background(
                                    appliedActionIDs.contains(action.id) ? Color.green.opacity(0.12) : Color.accentColor
                                ).foregroundStyle(appliedActionIDs.contains(action.id) ? Color.green : Color.white).clipShape(Capsule())
                        }.padding(10).background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(appliedActionIDs.contains(action.id))
                }
            }.padding(12).background(
                message.role == .user ? Color.accentColor : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12)
            ).foregroundStyle(message.role == .user ? Color.white : Color.primary); if message.role == .assistant { Spacer(minLength: 55) }
        }
    }

    private func submitInput() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; input = "";
        Task { await submit(value) }
    }
    @MainActor private func submit(_ prompt: String) async {
        guard !isThinking else { return }
        messages.append(AssistantMessage(role: .user, text: prompt, leadIDs: [], actions: [])); isThinking = true
        let history = messages.dropLast().suffix(12).map {
            AssistantConversationTurn(role: $0.role == .user ? "user" : "assistant", text: $0.text)
        }
        let submittedAttachment = attachment
        if let response = await appState.askAssistant(prompt, history: Array(history), attachment: submittedAttachment) {
            messages.append(
                AssistantMessage(role: .assistant, text: response.message, leadIDs: response.leadIDs, actions: response.actions))
            attachment = nil
            if let firstAction = response.actions.first {
                reviewQueue = Array(response.actions.dropFirst())
                pendingAction = firstAction
            }
        } else {
            let local = answer(prompt)
            let detail = appState.assistantErrorMessage.map { "\n\nConnection detail: \($0)" } ?? ""
            messages.append(
                AssistantMessage(
                    role: .assistant,
                    text: local.text
                        + "\n\nProline could not reach the live assistant, so this answer used the app’s local read-only fallback."
                        + detail, leadIDs: local.ids, actions: []))
        }
        isThinking = false
    }

    private func selectAttachment(_ result: Result<URL, Error>) {
        attachmentError = nil
        guard case let .success(url) = result else { attachmentError = "The file could not be opened."; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { attachmentError = "The file could not be read."; return }
        guard data.count <= 15 * 1_024 * 1_024 else { attachmentError = "Choose a file smaller than 15 MB."; return }
        let type = UTType(filenameExtension: url.pathExtension)
        let mime = type?.preferredMIMEType ?? ""
        guard mime == "application/pdf" || mime.hasPrefix("image/") else { attachmentError = "Use a PDF, JPEG, PNG or HEIC image."; return }
        attachment = AssistantAttachment(filename: url.lastPathComponent, mimeType: mime, data: data)
    }

    private func chooseAttachment() {
        attachmentError = nil
        #if os(macOS)
            let panel = NSOpenPanel()
            panel.title = "Choose a quote or job photo"
            panel.prompt = "Attach"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.pdf, .image]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            selectAttachment(.success(url))
        #else
            choosingAttachment = true
        #endif
    }

    @ViewBuilder private func actionReview(_ action: CRMAssistantAction) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Review proposed change", systemImage: "checkmark.shield").font(.title2.bold()); Spacer();
                    if !reviewQueue.isEmpty { Text("1 of \(reviewQueue.count + 1)").font(.caption.bold()).foregroundStyle(.secondary) }
                }; Text(action.title).font(.headline); Text(action.explanation).foregroundStyle(.secondary);
                if let id = action.leadID, let lead = appState.leads.first(where: { $0.id == id }),
                    action.kind == .recordDeposit || action.kind == .recordFinalPayment
                {
                    GroupBox("Payment being recorded") {
                        Text(action.kind == .recordDeposit ? lead.deposit : lead.balance, format: .currency(code: "GBP")).font(
                            .title2.bold()
                        ).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                } else if action.kind == .addMaterial, let name = action.value, let quantity = action.quantity, let unit = action.unit {
                    GroupBox("Material to add") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.headline); Text("Estimated quantity").font(.caption).foregroundStyle(.secondary)
                            }; Spacer(); Text("\(quantity.formatted()) \(unit)").font(.title3.bold()).foregroundStyle(Color.accentColor)
                        }.padding(.vertical, 6)
                    }
                } else if let id = action.leadID, let lead = appState.leads.first(where: { $0.id == id }),
                    [.setJobValue, .setDepositAmount, .setBalance].contains(action.kind), let raw = action.value, let proposed = Double(raw)
                {
                    GroupBox("Financial change") {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Current").font(.caption).foregroundStyle(.secondary);
                                Text(currentAmount(for: action.kind, lead: lead), format: .currency(code: "GBP"))
                            }; Image(systemName: "arrow.right");
                            VStack(alignment: .leading) {
                                Text("Proposed").font(.caption).foregroundStyle(.secondary);
                                Text(proposed, format: .currency(code: "GBP")).fontWeight(.bold)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                } else if let value = action.value {
                    GroupBox(reviewLabel(for: action.kind)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(value).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled);
                            if let secondary = action.secondaryValue, !secondary.isEmpty {
                                Label(secondary, systemImage: "calendar").foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                };
                if let id = action.leadID, let lead = appState.leads.first(where: { $0.id == id }) {
                    Label("\(lead.name) · \(lead.jobRef)", systemImage: "house")
                };
                if let actionFailure {
                    Label(actionFailure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading).background(
                            Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }; Spacer();
                HStack {
                    Button(reviewQueue.isEmpty ? "Cancel" : "Skip", role: .cancel) { advanceReviewQueue() }.disabled(isApplyingAction);
                    Spacer();
                    Button {
                        Task {
                            isApplyingAction = true; actionFailure = nil; let ok = await appState.executeAssistantAction(action);
                            isApplyingAction = false;
                            if ok {
                                appliedActionIDs.insert(action.id);
                                messages.append(
                                    AssistantMessage(
                                        role: .assistant, text: "Done — \(action.title) was approved and saved.",
                                        leadIDs: action.leadID.map { [$0] } ?? [], actions: []));
                                advanceReviewQueue()
                            } else {
                                actionFailure = appState.errorMessage ?? "The change could not be saved. Refresh the CRM and try again."
                            }
                        }
                    } label: {
                        if isApplyingAction {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(action.kind == .draftEmail ? "Approve draft" : (reviewQueue.isEmpty ? "Confirm change" : "Confirm & next"))
                        }
                    }.buttonStyle(.borderedProminent).disabled(isApplyingAction)
                }
            }.padding(24).navigationTitle("Assistant action")
        }
        #if os(macOS)
            .frame(width: 500, height: 390)
        #endif
    }

    private func currentAmount(for kind: CRMAssistantActionKind, lead: Lead) -> Double {
        switch kind {
        case .setJobValue: lead.value;
        case .setDepositAmount: lead.deposit;
        case .setBalance: lead.balance;
        default: 0
        }
    }
    private func reviewLabel(for kind: CRMAssistantActionKind) -> String {
        switch kind {
        case .addJobTask, .createGeneralTask: "Task to add";
        case .completeJobTask: "Task to complete";
        case .moveJobStage: "New pipeline stage";
        case .scheduleSurvey: "Survey date";
        case .scheduleJob: "Job dates";
        case .draftEmail: "Email draft";
        case .addJobNote: "Note to add";
        default: "Proposed value"
        }
    }
    private func advanceReviewQueue() {
        pendingAction = nil
        actionFailure = nil
        guard !reviewQueue.isEmpty else { return }
        let next = reviewQueue.removeFirst()
        DispatchQueue.main.async { pendingAction = next }
    }
    private func icon(for kind: CRMAssistantActionKind) -> String {
        switch kind {
        case .addJobTask, .createGeneralTask: "plus.circle";
        case .completeJobTask: "checkmark.circle";
        case .moveJobStage: "arrow.right.circle";
        case .scheduleSurvey, .scheduleJob: "calendar";
        case .draftEmail: "envelope";
        case .recordDeposit, .recordFinalPayment, .setJobValue, .setDepositAmount, .setBalance: "sterlingsign.circle";
        case .addJobNote: "note.text.badge.plus";
        case .addMaterial: "shippingbox"
        }
    }

    private func answer(_ prompt: String) -> (text: String, ids: [String]) {
        OperationsInsights.answer(prompt, leads: appState.leads, tasks: appState.visibleGeneralTasks, today: SupabaseService.today)
    }
}

enum OperationsInsights {
    static func answer(_ prompt: String, leads: [Lead], tasks: [GeneralTask], today: String) -> (text: String, ids: [String]) {
        let query = prompt.lowercased()
        if query.contains("daily") || query.contains("company plan") || query.contains("plan my day") || query.contains("priorit")
            || query.contains("risk")
        {
            let active = leads.filter { ![.completed, .waitingForPayment, .paid, .lost].contains($0.stage) }
            let overdue = active.filter { !($0.endDate ?? "").isEmpty && ($0.endDate ?? "") < today }.sorted {
                ($0.endDate ?? "") < ($1.endDate ?? "")
            }
            let dueTasks = tasks.filter { !$0.completed && !($0.dueDate ?? "").isEmpty && ($0.dueDate ?? "") <= today }.sorted {
                ($0.dueDate ?? "") < ($1.dueDate ?? "")
            }
            let surveys = active.filter { $0.surveyDate == today }
            let deposits = active.filter { [.won, .scheduled, .inProgress].contains($0.stage) && $0.deposit > 0 && !$0.depositPaid }
            let balances = leads.filter { [.completed, .waitingForPayment].contains($0.stage) && $0.balance > 0 }.sorted {
                $0.balance > $1.balance
            }
            let enquiries = active.filter { $0.stage == .newLead }
            let quotes = active.filter { $0.stage == .quoteSent }.sorted { $0.updatedAt < $1.updatedAt }
            var lines: [String] = []
            var ids: [String] = []
            func add(_ text: String, _ rows: [Lead]) {
                lines.append("\(lines.count + 1). \(text)")
                for row in rows where !ids.contains(row.id) { ids.append(row.id) }
            }
            if !overdue.isEmpty {
                add(
                    "Recover overdue jobs: \(overdue.prefix(3).map(\.name).joined(separator: ", ")). Confirm blockers, crew and a revised finish date; these jobs are past their planned end date.",
                    overdue)
            }
            if !dueTasks.isEmpty {
                add(
                    "Complete \(dueTasks.count) tasks due today or overdue: \(dueTasks.prefix(3).map(\.title).joined(separator: ", ")). Confirm an owner and resolve blockers.",
                    [])
            }
            if !surveys.isEmpty {
                add(
                    "Confirm today’s surveys: \(surveys.prefix(3).map(\.name).joined(separator: ", ")). Check access and attendance.",
                    surveys)
            }
            if !deposits.isEmpty {
                add(
                    "Check unpaid deposits on \(deposits.count) won or active jobs. Confirm payment arrangements before committing further materials or labour.",
                    deposits)
            }
            if !balances.isEmpty {
                add(
                    "Review completed-job balances of \(balances.reduce(0) { $0 + $1.balance }.formatted(.currency(code: "GBP"))). Check agreed payment terms and follow up where due.",
                    balances)
            }
            if !enquiries.isEmpty {
                add("Contact \(enquiries.count) new enquiries to qualify the work and agree the next step.", enquiries)
            }
            if !quotes.isEmpty {
                add(
                    "Follow up \(quotes.count) sent quotes, starting with the oldest updated: \(quotes.prefix(3).map(\.name).joined(separator: ", ")). Confirm the customer’s decision and next contact date.",
                    quotes)
            }
            if lines.isEmpty {
                return (
                    "No urgent items were identified in the available CRM records. Review upcoming work, crew availability and materials before planning the day. Missing dates or records may hide risks.",
                    []
                )
            }
            return (
                "Daily company plan — ranked from available CRM records:\n\n" + lines.joined(separator: "\n\n")
                    + "\n\nCheck crew availability, materials and weather before confirming the plan; these risks have not been verified.",
                ids
            )
        }
        if query.contains("quote") || query.contains("follow") {
            let rows = leads.filter { $0.stage == .quoteSent }.sorted { $0.updatedAt < $1.updatedAt }
            let value = rows.reduce(0) { $0 + $1.value }
            return rows.isEmpty
                ? ("There are no sent quotes waiting for follow-up.", [])
                : (
                    "\(rows.count) sent quote\(rows.count == 1 ? "" : "s") need attention, worth \(value.formatted(.currency(code: "GBP"))). Oldest updates are shown first.",
                    rows.map(\.id)
                )
        }
        if query.contains("balance") || query.contains("payment") || query.contains("owe") {
            let rows = leads.filter {
                $0.balance > 0 && [.won, .scheduled, .inProgress, .completed, .waitingForPayment].contains($0.stage)
            }.sorted { $0.balance > $1.balance }
            let total = rows.reduce(0) { $0 + $1.balance }
            return rows.isEmpty
                ? ("No active jobs have an outstanding balance.", [])
                : (
                    "Outstanding customer balances total \(total.formatted(.currency(code: "GBP"))) across \(rows.count) job\(rows.count == 1 ? "" : "s").",
                    rows.map(\.id)
                )
        }
        if query.contains("survey") {
            let rows = leads.filter { ($0.surveyDate ?? "") >= today }.sorted { ($0.surveyDate ?? "") < ($1.surveyDate ?? "") }
            return rows.isEmpty
                ? ("No upcoming surveys are currently booked.", [])
                : (
                    "The next \(min(rows.count, 8)) survey\(rows.count == 1 ? " is" : "s are") listed below. The earliest is \(rows.first?.surveyDate ?? "not dated").",
                    rows.map(\.id)
                )
        }
        if query.contains("task") || query.contains("attention") || query.contains("overdue") || query.contains("today") {
            let overdueTasks = tasks.filter { !$0.completed && ($0.dueDate ?? "9999-12-31") < today }
            let newLeads = leads.filter { $0.stage == .newLead }
            let quoteLeads = leads.filter { $0.stage == .quoteSent }
            let overdueJobs = leads.filter {
                ($0.endDate ?? "9999-12-31") < today && ![.completed, .waitingForPayment, .paid, .lost].contains($0.stage)
            }
            let text =
                "Today: \(newLeads.count) new enquir\(newLeads.count == 1 ? "y" : "ies"), \(quoteLeads.count) quote follow-up\(quoteLeads.count == 1 ? "" : "s"), \(overdueTasks.count) overdue task\(overdueTasks.count == 1 ? "" : "s"), and \(overdueJobs.count) job\(overdueJobs.count == 1 ? "" : "s") beyond the planned end date."
            return (text, Array((newLeads + quoteLeads + overdueJobs).map(\.id).prefix(8)))
        }
        if query.contains("active") || query.contains("pipeline") || query.contains("summary") || query.contains("week") {
            let active = leads.filter { [.won, .scheduled, .inProgress].contains($0.stage) }
            let pipeline = leads.filter { ![.paid, .lost].contains($0.stage) }.reduce(0) { $0 + $1.value }
            let inProgress = active.filter { $0.stage == .inProgress }
            return (
                "The open pipeline is \(pipeline.formatted(.currency(code: "GBP"))). There are \(active.count) won or active jobs, including \(inProgress.count) currently in progress.",
                active.map(\.id)
            )
        }
        let matches = leads.filter { lead in
            [lead.name, lead.jobRef, lead.address, lead.jobType].contains { $0.localizedCaseInsensitiveContains(prompt) }
        }
        if !matches.isEmpty { return ("I found \(matches.count) matching CRM record\(matches.count == 1 ? "" : "s").", matches.map(\.id)) }
        return (
            "I couldn’t match that request yet. Try asking about today’s priorities, quote follow-ups, surveys, active jobs, outstanding balances, or a customer/job name.",
            []
        )
    }
}
