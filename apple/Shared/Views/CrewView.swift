import SwiftUI

#if os(iOS)
/// The admin's expected crew plan, one day at a time. Worker-submitted timesheets stay
/// separate so Pay can compare their week with this office copy before approval.
struct CrewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    private func entry(_ user: CRMUser) -> TimesheetEntry? { appState.adminTimesheetChecks.first { $0.userID == user.id && $0.date == dayKey } }
    private var unassigned: [CRMUser] { workers.filter { entry($0).map { $0.type == "off" || $0.leadID.isEmpty } ?? true } }
    private var assigned: [CRMUser] { workers.filter { entry($0).map { $0.type != "off" && !$0.leadID.isEmpty } ?? false } }
    private var jobsWithCrew: Int { Set(assigned.compactMap { entry($0)?.leadID }).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plan the day").font(.title2.bold())
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 2)

                    dayStrip
                    summaryCard

                    HStack {
                        Text("Jobs").font(.headline)
                        Spacer()
                        Text("Tap a name to assign or move them")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 2)

                    if jobs.isEmpty {
                        ContentUnavailableView("No live jobs", systemImage: "hammer", description: Text("Scheduled and active jobs will appear here."))
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        LazyVGrid(columns: jobColumns, alignment: .leading, spacing: 14) {
                            ForEach(jobs) { job in jobCard(for: job) }
                        }
                    }

                    if !workers.isEmpty { unassignedCard }
                    if workers.isEmpty {
                        ContentUnavailableView("No crew members", systemImage: "person.2", description: Text("Add workers with a day rate in Team Hub."))
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var jobColumns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]
            : [GridItem(.flexible(), alignment: .top)]
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                summaryMetric(value: "\(assigned.count) of \(workers.count)", label: "Assigned", icon: "person.2.fill")
                Divider().frame(height: 42).padding(.horizontal, 14)
                summaryMetric(value: "\(jobsWithCrew)", label: "Jobs covered", icon: "hammer.fill")
            }
            if !unassigned.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("\(unassigned.count) not out today").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(unassigned.map(firstName).joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }

    private func summaryMetric(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.headline).foregroundStyle(.tint)
                .frame(width: 34, height: 34).background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { candidate in
                        let selected = Calendar.current.isDate(candidate, inSameDayAs: day)
                        let key = PayrollMath.key(candidate)
                        let crewCount = Set(appState.adminTimesheetChecks.filter { $0.date == key && $0.type != "off" && !$0.leadID.isEmpty }.map(\.userID)).count
                        Button { day = candidate } label: {
                            VStack(spacing: 3) {
                                Text(candidate.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.medium))
                                Text(candidate.formatted(.dateTime.day())).font(.title3.bold())
                                HStack(spacing: 2) {
                                    Image(systemName: "person.fill").font(.system(size: 8))
                                    Text("\(crewCount)").font(.caption2.weight(.semibold))
                                }
                                .opacity(crewCount > 0 ? 1 : 0)
                            }
                            .frame(width: 56, height: 70)
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
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
            .onAppear { proxy.scrollTo(dayKey, anchor: .leading) }
        }
    }

    private func jobCard(for job: Lead) -> some View {
        let jobCrew = workers.filter { entry($0)?.leadID == job.id && entry($0)?.type != "off" }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: job.stage == .inProgress ? "hammer.fill" : "calendar")
                    .font(.headline).foregroundStyle(.tint)
                    .frame(width: 40, height: 40).background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name).font(.headline)
                    Text([job.jobType, town(job.address)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(jobCrew.count) crew").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(Color(.tertiarySystemFill), in: Capsule())
            }
            Divider()
            FlowLayout(spacing: 8) {
                ForEach(workers) { worker in
                    let current = entry(worker)
                    let onThisJob = current?.leadID == job.id && current?.type != "off"
                    let elsewhere = !onThisJob && (current.map { !$0.leadID.isEmpty && $0.type != "off" } ?? false)
                    Button {
                        Task {
                            if onThisJob, let current { await appState.deleteAdminTimesheetCheck(current) } else {
                                await appState.setAdminTimesheetCheck(userID: worker.id, leadID: job.id, date: dayKey, kind: "full")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: onThisJob ? "checkmark.circle.fill" : elsewhere ? "arrow.left.arrow.right.circle" : "circle")
                                .font(.caption.weight(.semibold))
                            Text(firstName(worker))
                            if onThisJob && current?.type == "half" { Text("½").font(.caption) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(onThisJob ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                        .foregroundStyle(onThisJob ? Color.white : elsewhere ? Color.secondary : Color.primary)
                        .overlay(Capsule().stroke(elsewhere ? Color.secondary.opacity(0.3) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(worker.name), \(onThisJob ? "on this job" : elsewhere ? "on another job" : "not out")")
                    .accessibilityHint(onThisJob ? "Remove from this job" : elsewhere ? "Move to this job" : "Assign to this job")
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }

    private var unassignedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: unassigned.isEmpty ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                .font(.title3).foregroundStyle(unassigned.isEmpty ? Color.green : Color.orange)
                .frame(width: 40, height: 40)
                .background((unassigned.isEmpty ? Color.green : Color.orange).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(unassigned.isEmpty ? "Everyone is assigned" : "Not out today").font(.headline)
                Text(unassigned.isEmpty ? "The whole team has a job." : unassigned.map(\.name).joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(unassigned.isEmpty ? Color.green.opacity(0.25) : Color.orange.opacity(0.3)))
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
