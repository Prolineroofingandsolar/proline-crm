import SwiftUI

#if os(iOS)
/// Who is on which job, one day at a time. Tap a name under a job to put them on it;
/// tap again to take them off. The same days feed Pay.
struct CrewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.startOfDay(for: .now)

    private var dayKey: String { PayrollMath.key(day) }
    private var workers: [CRMUser] { appState.users.filter { $0.role != "admin" && $0.dayRate != nil }.sorted { $0.name < $1.name } }
    private var jobs: [Lead] {
        appState.leads.filter { [.won, .scheduled, .inProgress].contains($0.stage) }
            .sorted { ($0.stage == .inProgress ? 0 : 1, $0.startDate ?? "9") < ($1.stage == .inProgress ? 0 : 1, $1.startDate ?? "9") }
    }
    /// This week and the next two, Mon–Sat.
    private var days: [Date] {
        let monday = PayrollMath.monday(for: .now)
        return (0..<21).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: monday) }
            .filter { Calendar.current.component(.weekday, from: $0) != 1 || Calendar.current.isDateInToday($0) }
    }
    private func entry(_ user: CRMUser) -> TimesheetEntry? { appState.timesheets.first { $0.userID == user.id && $0.date == dayKey } }
    private var unassigned: [CRMUser] { workers.filter { entry($0).map { $0.type == "off" || $0.leadID.isEmpty } ?? true } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    dayStrip
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(jobs) { job in
                    Section {
                        chips(for: job)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.name).font(.headline).foregroundStyle(.primary)
                            Text([job.jobType, town(job.address)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                }
                if jobs.isEmpty { Section { Text("No live jobs to put people on").foregroundStyle(.secondary) } }
                if workers.isEmpty { Section { Text("Add workers with a day rate in Team Hub").foregroundStyle(.secondary) } }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if !unassigned.isEmpty && !jobs.isEmpty {
                    Text("Not out: \(unassigned.map(firstName).joined(separator: ", "))")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(10).background(.bar)
                }
            }
        }
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { candidate in
                        let selected = Calendar.current.isDate(candidate, inSameDayAs: day)
                        let key = PayrollMath.key(candidate)
                        let crewCount = Set(appState.timesheets.filter { $0.date == key && $0.type != "off" && !$0.leadID.isEmpty }.map(\.userID)).count
                        Button { day = candidate } label: {
                            VStack(spacing: 2) {
                                Text(candidate.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                                Text(candidate.formatted(.dateTime.day())).font(.headline)
                                Text(crewCount > 0 ? "\(crewCount)" : " ").font(.caption2)
                            }
                            .frame(width: 48, height: 60)
                            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .overlay(alignment: .top) {
                                if Calendar.current.isDateInToday(candidate) && !selected {
                                    Circle().fill(Color.accentColor).frame(width: 5, height: 5).padding(.top, 4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(key)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(dayKey, anchor: .leading) }
        }
    }

    private func chips(for job: Lead) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(workers) { worker in
                let current = entry(worker)
                let onThisJob = current?.leadID == job.id && current?.type != "off"
                let elsewhere = !onThisJob && (current.map { !$0.leadID.isEmpty && $0.type != "off" } ?? false)
                Button {
                    Task {
                        if onThisJob, let current { await appState.deleteTimesheet(current) } else {
                            await appState.setTimesheetDay(userID: worker.id, leadID: job.id, date: dayKey, kind: "full")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if onThisJob { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(firstName(worker))
                        if onThisJob && current?.type == "half" { Text("½").font(.caption) }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(onThisJob ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(onThisJob ? Color.white : elsewhere ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(worker.name), \(onThisJob ? "on this job" : elsewhere ? "on another job" : "not out")")
            }
        }
        .padding(.vertical, 4)
    }

    private func firstName(_ user: CRMUser) -> String { user.name.split(separator: " ").first.map(String.init) ?? user.name }
    private func town(_ address: String) -> String { address.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? "" }
}

/// Wraps its children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(proposal: proposal, subviews: subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
#endif
