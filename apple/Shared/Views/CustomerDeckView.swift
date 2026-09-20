import SwiftUI

#if os(iOS)
/// One card per customer holding everything owed to them, in the order they need chasing.
struct DeckCard: Identifiable {
    let id: String
    let lead: Lead?
    let actions: [CompanyAction]
    let priority: CompanyActionPriority
    var isOffice: Bool { lead == nil }
}

/// iPhone admin Today: a deck of customers. Tick what's done on the card, swipe right for the
/// next customer, left to go back. Swiping never changes data.
struct CustomerDeckView: View {
    @Environment(AppState.self) private var appState
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var showingAll = false

    /// Card order is pinned for the session so a card never moves while you're working on it.
    /// New customers join at the end; a finished card stays until you swipe past it.
    @State private var order: [String] = []

    private var grouped: [String: [CompanyAction]] {
        var groups: [String: [CompanyAction]] = [:]
        for action in appState.companyActions where action.kind != .timesheet {
            groups[action.leadID ?? "office", default: []].append(action)
        }
        return groups
    }
    // Before the first sync (one frame) fall back to the ranked order so the screen never flashes empty.
    private var deck: [DeckCard] { (order.isEmpty ? ranked(Array(grouped.keys)) : order).compactMap(card(for:)) }
    private var current: Int { min(index, max(0, deck.count - 1)) }
    private var remaining: Int { deck.reduce(0) { $0 + $1.actions.count } }

    private func card(for id: String) -> DeckCard? {
        let lead = id == "office" ? nil : appState.leads.first { $0.id == id }
        if id != "office" && lead == nil { return nil }
        let items = grouped[id] ?? []
        return DeckCard(id: id, lead: lead, actions: items, priority: items.map(\.priority).max() ?? .routine)
    }

    private func ranked(_ ids: [String]) -> [String] {
        ids.compactMap(card(for:))
            .sorted { left, right in
                if left.priority != right.priority { return left.priority > right.priority }
                let l = left.actions.compactMap(\.dueDate).min() ?? "9999-12-31"
                let r = right.actions.compactMap(\.dueDate).min() ?? "9999-12-31"
                return l < r
            }
            .map(\.id)
    }

    /// Adds newly-actionable customers to the end of the deck, in priority order, and drops
    /// finished cards the user has already swiped past. Never reorders what's on screen.
    private func syncOrder() {
        let groups = grouped
        let known = Set(order)
        let newcomers = ranked(groups.keys.filter { !known.contains($0) })
        var next = order
        var position = index
        for (offset, id) in order.enumerated().reversed() {
            let gone = card(for: id) == nil
            let finished = (groups[id] ?? []).isEmpty && offset < index
            if gone || finished {
                next.remove(at: offset)
                if offset < index { position -= 1 }
            }
        }
        next += newcomers
        if next != order { order = next }
        index = max(0, min(position, max(0, next.count - 1)))
    }

    var body: some View {
        VStack(spacing: 16) {
            if deck.isEmpty {
                allClear
            } else {
                DeckCardView(card: deck[current])
                    .offset(offset)
                    .rotationEffect(.degrees(Double(offset.width / 20)))
                    .gesture(dragGesture)
                    .id(deck[current].id)
                    .background {
                        // A hint that more cards follow, sized to the card in front.
                        if current + 1 < deck.count {
                            RoundedRectangle(cornerRadius: 20).fill(.background)
                                .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                                .scaleEffect(0.96)
                                .offset(y: 12)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: offset)
                Text("\(current + 1) of \(deck.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if remaining > 0 { Button("\(remaining) to do") { showingAll = true } }
            }
        }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                List { ActionQueueList(showLater: true) }
                    .navigationTitle("Everything")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAll = false } } }
            }
        }
        .onAppear(perform: syncOrder)
        .onChange(of: Set(grouped.keys)) { _, _ in syncOrder() }
        .onChange(of: appState.leads.count) { _, _ in syncOrder() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in offset = value.translation }
            .onEnded { value in
                let width = value.translation.width
                guard abs(width) > 110 else { offset = .zero; return }
                let forward = width > 0
                guard forward ? current + 1 < deck.count : current > 0 else { offset = .zero; return }
                offset = CGSize(width: forward ? 600 : -600, height: value.translation.height)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        index = forward ? current + 1 : current - 1
                        offset = CGSize(width: forward ? -80 : 80, height: 0)
                        if forward { syncOrder() }
                    }
                    offset = .zero
                }
            }
    }

    private var allClear: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Nothing to chase").font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DeckCardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    let card: DeckCard
    @State private var confirmingDeposit = false
    @State private var confirmingBalance = false
    @State private var showingSurvey = false
    @State private var showingSchedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if card.actions.isEmpty {
                Label("All done", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(card.actions) { action in
                        DeckItemRow(action: action, lead: card.lead, call: call, record: record)
                        if action.id != card.actions.last?.id { Divider() }
                    }
                }
            }
            if let lead = card.lead { footer(lead) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .confirmationDialog("Record deposit as paid?", isPresented: $confirmingDeposit, titleVisibility: .visible) {
            if let lead = card.lead { Button("Record \(CRMFormat.money(lead.deposit, pence: true))") { Task { await appState.recordDeposit(for: lead) } } }
        }
        .confirmationDialog("Mark this job as paid?", isPresented: $confirmingBalance, titleVisibility: .visible) {
            if let lead = card.lead { Button("Mark paid") { Task { await appState.recordFinalPayment(for: lead) } } }
        }
        .sheet(isPresented: $showingSurvey) { if let lead = card.lead { ScheduleSurveySheet(lead: lead) } }
        .sheet(isPresented: $showingSchedule) { if let lead = card.lead { ScheduleJobSheet(lead: lead) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if card.priority == .critical { Circle().fill(.red).frame(width: 8, height: 8) }
                Text(card.priority.label).font(.subheadline).foregroundStyle(card.priority == .critical ? Color.red : Color.secondary)
            }
            if let lead = card.lead {
                Text(lead.name).font(.title2.weight(.semibold))
                Text([lead.jobType, lead.stage.displayName].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                if !lead.address.isEmpty { Text(lead.address).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            } else {
                Text("Office").font(.title2.weight(.semibold))
            }
        }
    }

    private func footer(_ lead: Lead) -> some View {
        HStack(spacing: 10) {
            if ContactLinks.telephone(lead.phone) != nil {
                Button { call(lead) } label: { Image(systemName: "phone").frame(minWidth: 28) }.accessibilityLabel("Call \(lead.name)")
            }
            if let step = AppState.nextStep(for: lead) {
                Button { perform(step, for: lead) } label: { Text(step.title).lineLimit(1).frame(maxWidth: .infinity) }
            }
            NavigationLink(value: LeadRoute(id: lead.id)) { Image(systemName: "arrow.up.right").frame(minWidth: 28) }.accessibilityLabel("Open \(lead.name)")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func call(_ lead: Lead) { if let url = appState.beginCall(to: lead) { openURL(url) } }

    private func record(_ action: CompanyAction) {
        if action.kind == .deposit { confirmingDeposit = true } else { confirmingBalance = true }
    }

    private func perform(_ step: LeadStep, for lead: Lead) {
        switch step {
        case .bookSurvey: showingSurvey = true
        case .scheduleJob: showingSchedule = true
        case .recordPayment: confirmingBalance = true
        case .move(let stage): Task { await appState.move(lead, to: stage) }
        }
    }
}

private struct DeckItemRow: View {
    @Environment(AppState.self) private var appState
    let action: CompanyAction
    let lead: Lead?
    let call: (Lead) -> Void
    let record: (CompanyAction) -> Void

    private var isTask: Bool { action.generalTaskID != nil || action.leadTaskID != nil }
    private var overdue: Bool { action.priority == .critical }

    var body: some View {
        HStack(spacing: 12) {
            if isTask {
                Button(action: complete) { Image(systemName: "circle").font(.title2).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete \(action.title)")
            } else {
                Image(systemName: icon).foregroundStyle(overdue ? Color.red : Color.secondary).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(overdue ? Color.red : Color.secondary) }
            }
            Spacer()
            if action.kind == .quoteFollowUp, let lead, ContactLinks.telephone(lead.phone) != nil {
                Button("Call") { call(lead) }.buttonStyle(.bordered).controlSize(.small)
            }
            if action.kind == .deposit || action.kind == .balance {
                Button("Record") { record(action) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 12)
    }

    private var title: String {
        switch action.kind {
        case .survey: "Survey" + (lead?.surveyTime.map { " · \($0)" } ?? "")
        case .jobStart: "Starts today"
        case .overdueJob: "Job overdue"
        case .quoteFollowUp: "Follow up quote" + (lead.map { " · \(CRMFormat.money($0.value))" } ?? "")
        case .deposit: "Collect deposit" + (lead.map { " · \(CRMFormat.money($0.deposit))" } ?? "")
        case .balance: "Collect balance" + (lead.map { " · \(CRMFormat.money($0.balance))" } ?? "")
        default: action.title
        }
    }

    private var subtitle: String? {
        switch action.kind {
        case .generalTask, .jobTask:
            guard let due = action.dueDate else { return nil }
            return CRMFormat.relativeDay(due)
        case .overdueJob:
            return lead?.endDate.map { "Expected finish \(CRMFormat.day($0))" }
        default: return nil
        }
    }

    private var icon: String {
        switch action.kind {
        case .survey: "calendar"
        case .jobStart, .overdueJob: "hammer"
        case .quoteFollowUp: "doc.text"
        case .deposit, .balance: "sterlingsign"
        default: "circle"
        }
    }

    private func complete() {
        if let taskID = action.generalTaskID, let task = appState.generalTasks.first(where: { $0.id == taskID }) {
            Task { await appState.toggleGeneralTask(task) }
        } else if let leadID = action.leadID, let taskID = action.leadTaskID {
            Task { await appState.toggleLeadTask(leadID: leadID, taskID: taskID) }
        }
    }
}
#endif
