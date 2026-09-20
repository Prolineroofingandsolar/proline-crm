import SwiftUI

#if os(iOS)
/// One card per customer holding everything owed to them, in the order they need chasing.
struct DeckCard: Identifiable {
    let id: String
    let lead: Lead?
    let actions: [CompanyAction]
    let priority: CompanyActionPriority
    var isOffice: Bool { lead == nil }

    /// One line that says where this job is, so the card explains itself without reading the rows.
    static func summary(for lead: Lead) -> String {
        let today = SupabaseService.today
        let type = lead.jobType.isEmpty ? "Job" : lead.jobType
        switch lead.stage {
        case .quoteSent:
            let sent = SupabaseService.date(from: lead.updatedAt).map { Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0 } ?? 0
            return "\(type) · quote sent \(sent == 0 ? "today" : sent == 1 ? "yesterday" : "\(sent) days ago") · \(CRMFormat.money(lead.value))"
        case .completed where lead.balance > 0, .waitingForPayment where lead.balance > 0:
            return "\(type) · balance \(CRMFormat.money(lead.balance)) · finished \(CRMFormat.relativeDay(lead.completedDate ?? lead.endDate).lowercased())"
        case .won where !lead.depositPaid && lead.deposit > 0, .scheduled where !lead.depositPaid && lead.deposit > 0:
            return "\(type) · deposit \(CRMFormat.money(lead.deposit)) to collect"
        case .surveyBooked where lead.surveyDate != nil, .newLead where lead.surveyDate != nil:
            return "\(type) · survey \(lead.surveyDate == today ? (lead.surveyTime ?? "today") : CRMFormat.relativeDay(lead.surveyDate).lowercased())"
        case .inProgress:
            return "\(type) · on site" + (lead.endDate.map { " · due \(CRMFormat.relativeDay($0).lowercased())" } ?? "")
        case .scheduled:
            return "\(type) · starts \(CRMFormat.relativeDay(lead.startDate).lowercased())"
        default:
            return "\(type) · \(lead.stage.displayName)"
        }
    }
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

    @State private var showingTomorrow = false
    private var today: String { SupabaseService.today }
    private var chosenDay: Date { Calendar.current.date(byAdding: .day, value: showingTomorrow ? 1 : 0, to: Calendar.current.startOfDay(for: .now)) ?? .now }
    private var chosenKey: String { SupabaseService.localDay(for: chosenDay) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                dayLine
                TimelineCard(day: chosenDay, dayKey: chosenKey, forecast: appState.weather.forecast)
                HStack(alignment: .firstTextBaseline) {
                    Text("Next up").font(.headline)
                    Spacer()
                    if !deck.isEmpty {
                        Button("\(current + 1) of \(deck.count) · \(remaining) to do") { showingAll = true }
                            .font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
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
                        .padding(.bottom, 10)
                }
                NumbersRow()
                if let forecast = appState.weather.forecast { WeekStrip(forecast: forecast) }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar(.hidden, for: .navigationBar)
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

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("Logo").resizable().scaledToFit().frame(height: 36).accessibilityLabel("ProLine Roofing & Solar")
            Spacer()
            if !appState.syncIssues.isEmpty {
                Button { appState.errorMessage = "Some CRM data is not currently synced: \(appState.syncIssues.joined(separator: ", ")). Pull down or tap Refresh." } label: { Image(systemName: "exclamationmark.icloud") }
                    .accessibilityLabel("Data sync issue")
            }
            Button { appState.showingGlobalSearch = true } label: { Image(systemName: "magnifyingglass").font(.body.weight(.medium)).frame(width: 36, height: 36) }
                .background(.background, in: Circle()).accessibilityLabel("Search")
            Button { appState.showingGlobalAddLead = true } label: { Image(systemName: "plus").font(.body.weight(.medium)).frame(width: 36, height: 36) }
                .background(.background, in: Circle()).accessibilityLabel("Add lead")
        }
    }

    private var dayLine: some View {
        HStack(alignment: .center) {
            Button { withAnimation(.snappy) { showingTomorrow.toggle() } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(showingTomorrow ? "Tomorrow" : chosenDay.formatted(.dateTime.weekday(.wide))).font(.title2.weight(.semibold)).foregroundStyle(.primary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    Text("\(chosenDay.formatted(.dateTime.day().month(.abbreviated))) · \(bookedCount) booked").font(.subheadline).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showingTomorrow ? "Show today" : "Show tomorrow")
            Spacer()
            if let forecast = appState.weather.forecast, let now = forecast.hour(at: showingTomorrow ? chosenDay.addingTimeInterval(9 * 3600) : .now) {
                HStack(spacing: 6) {
                    Image(systemName: WeatherPolicy.symbol(for: now.code)).foregroundStyle(WeatherPolicy.isWet(now.code) ? Color.blue : (now.code <= 1 ? Color.accentColor : Color.secondary))
                    Text("\(Int(now.temperature.rounded()))°").fontWeight(.medium)
                    if let note = WeatherPolicy.note(for: forecast.hours(on: chosenDay), now: showingTomorrow ? chosenDay : .now) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.background, in: Capsule())
            }
        }
        .padding(.horizontal, 2)
    }

    private var bookedCount: Int { TimelineCard.bookings(in: appState.leads, dayKey: chosenKey, today: today, timesheets: appState.timesheets).count }

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
                Text(DeckCard.summary(for: lead)).foregroundStyle(.secondary)
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

#if os(iOS)
/// Today's bookings in time order.
struct TimelineCard: View {
    @Environment(AppState.self) private var appState
    let day: Date
    let dayKey: String
    let forecast: Forecast?

    struct Booking: Identifiable {
        enum Kind { case survey, start, onSite }
        let lead: Lead
        let kind: Kind
        let time: String?
        let crew: Int
        var id: String { lead.id + (kind == .survey ? "-s" : "-j") }
    }

    static func bookings(in leads: [Lead], dayKey: String, today: String, timesheets: [TimesheetEntry]) -> [Booking] {
        var rows: [Booking] = []
        for lead in leads {
            let crew = Set(timesheets.filter { $0.leadID == lead.id && $0.date == dayKey && $0.type != "off" }.map(\.userID)).count
            if lead.surveyDate == dayKey { rows.append(Booking(lead: lead, kind: .survey, time: lead.surveyTime, crew: 0)) }
            if lead.startDate == dayKey && lead.stage != .inProgress { rows.append(Booking(lead: lead, kind: .start, time: nil, crew: crew)) }
            else if lead.stage == .inProgress, let start = lead.startDate, start <= dayKey, (lead.endDate ?? dayKey) >= dayKey {
                rows.append(Booking(lead: lead, kind: .onSite, time: nil, crew: crew))
            }
        }
        return rows.sorted { ($0.time ?? ($0.kind == .onSite ? "00:00" : "99")) < ($1.time ?? ($1.kind == .onSite ? "00:00" : "99")) }
    }

    private var rows: [Booking] { Self.bookings(in: appState.leads, dayKey: dayKey, today: SupabaseService.today, timesheets: appState.timesheets) }
    private var nextID: String? {
        let now = Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        guard Calendar.current.isDateInToday(day) else { return rows.first?.id }
        return rows.first { $0.kind == .onSite || ($0.time ?? "99") >= now }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("Nothing booked").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            ForEach(rows) { booking in
                let isNext = booking.id == nextID
                Button { appState.openLead(booking.lead.id) } label: {
                    HStack(spacing: 12) {
                        Text(booking.time ?? "—").font(.subheadline.weight(isNext ? .semibold : .regular)).foregroundStyle(isNext ? Color.accentColor : Color.secondary).frame(width: 44, alignment: .leading)
                        Image(systemName: icon(booking.kind)).foregroundStyle(isNext ? Color.accentColor : Color.secondary).frame(width: 22)
                        (Text(surname(booking.lead.name)).fontWeight(isNext ? .semibold : .regular) + Text("  \(detail(booking))").foregroundStyle(.secondary))
                            .lineLimit(1)
                        Spacer()
                        trailing(booking, isNext: isNext)
                    }
                    .padding(.vertical, 11).padding(.horizontal, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if booking.id != rows.last?.id { Divider().padding(.leading, 14) }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func trailing(_ booking: Booking, isNext: Bool) -> some View {
        if let rain = rainChance(for: booking) { Text("rain \(rain)%").font(.caption).foregroundStyle(.blue) }
        else if booking.crew > 0 { Text("\(booking.crew) on site").font(.caption).foregroundStyle(.secondary) }
        else if isNext { Text("next").font(.caption).foregroundStyle(Color.accentColor) }
    }

    private func rainChance(for booking: Booking) -> Int? {
        guard let forecast, booking.kind != .onSite else { return nil }
        let parts = (booking.time ?? "08:00").split(separator: ":").compactMap { Int($0) }
        guard let at = Calendar.current.date(bySettingHour: parts.first ?? 8, minute: 0, second: 0, of: day), let hour = forecast.hour(at: at) else { return nil }
        return hour.rainChance >= 50 ? hour.rainChance : nil
    }

    private func icon(_ kind: Booking.Kind) -> String { switch kind { case .survey: "ruler"; case .start: "truck.box"; case .onSite: "hammer" } }
    private func surname(_ name: String) -> String { name.split(separator: " ").last.map(String.init) ?? name }
    private func detail(_ booking: Booking) -> String {
        let town = booking.lead.address.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
        switch booking.kind {
        case .survey: return ["survey", town].filter { !$0.isEmpty }.joined(separator: " · ")
        case .start: return "\(booking.lead.jobType.lowercased()) start"
        case .onSite: return booking.lead.jobType.lowercased()
        }
    }
}

/// Three numbers, each with the one detail that matters.
struct NumbersRow: View {
    @Environment(AppState.self) private var appState
    private var today: String { SupabaseService.today }
    private var live: [Lead] { appState.leads.filter { ![.paid, .lost].contains($0.stage) } }
    private var toCollect: Double { live.reduce(0) { $0 + $1.balance } }
    private var overdue: Double { live.filter { [.completed, .waitingForPayment].contains($0.stage) }.reduce(0) { $0 + $1.balance } }
    private var quotes: [Lead] { appState.leads.filter { $0.stage == .quoteSent } }
    private var workers: [CRMUser] { appState.users.filter { $0.role != "admin" && $0.dayRate != nil } }
    private var onSite: Int { Set(appState.timesheets.filter { $0.date == today && $0.type != "off" }.map(\.userID)).count }
    private var unrecorded: Int { workers.filter { worker in !appState.timesheets.contains { $0.userID == worker.id && $0.date == today } }.count }

    var body: some View {
        HStack(spacing: 8) {
            Button { appState.pendingSection = .accounts } label: {
                tile("To collect", CRMFormat.money(toCollect), overdue > 0 ? "\(CRMFormat.money(overdue)) overdue" : nil, warn: overdue > 0)
            }.buttonStyle(.plain)
            tile("Quotes out", "\(quotes.count)", quotes.isEmpty ? nil : CRMFormat.money(quotes.reduce(0) { $0 + $1.value }))
            tile("Crew", workers.isEmpty ? "—" : "\(onSite) of \(workers.count)", unrecorded > 0 ? "\(unrecorded) unrecorded" : nil)
        }
    }

    private func tile(_ label: String, _ value: String, _ note: String?, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(note ?? " ").font(.caption2).foregroundStyle(warn ? Color.red : Color.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The next five working days' weather, for planning the van.
struct WeekStrip: View {
    let forecast: Forecast
    private var days: [WeatherDay] {
        Array(forecast.days.filter { !Calendar.current.isDateInToday($0.date) && $0.date > .now && Calendar.current.component(.weekday, from: $0.date) != 1 }.prefix(5))
    }
    var body: some View {
        if !days.isEmpty {
            HStack {
                ForEach(days, id: \.date) { day in
                    VStack(spacing: 3) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: WeatherPolicy.symbol(for: day.code)).font(.body).frame(height: 22)
                            .foregroundStyle(WeatherPolicy.isWet(day.code) ? Color.blue : (day.code <= 1 ? Color.accentColor : Color.secondary))
                        Text("\(Int(day.maxTemperature.rounded()))°").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 6)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
#endif
