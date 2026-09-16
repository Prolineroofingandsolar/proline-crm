import SwiftUI
import WidgetKit

#if os(iOS)
    import ActivityKit
#endif

struct ProLineEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }

struct ProLineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProLineEntry {
        .init(
            date: .now,
            snapshot: .init(
                surveysToday: 2, overdueJobs: 1, activeJobs: 3,
                tasks: [
                    .init(id: "1", title: "Call customer about roof survey", dueDate: nil, priority: "high"),
                    .init(id: "2", title: "Send revised quotation", dueDate: nil, priority: "medium"),
                ], updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (ProLineEntry) -> Void) { completion(.init(date: .now, snapshot: .load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProLineEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now, snapshot: .load())], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct ProLineWidgetView: View {
    let entry: ProLineEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ProLine Today", systemImage: "house.lodge.fill").font(.headline).foregroundStyle(.orange)
            HStack {
                Metric(value: entry.snapshot.surveysToday, label: "Surveys")
                Metric(value: entry.snapshot.activeJobs, label: "Active")
                Metric(value: entry.snapshot.overdueJobs, label: "Overdue", warning: entry.snapshot.overdueJobs > 0)
            }
            Spacer(minLength: 0)
            Text("Updated \(entry.snapshot.updatedAt, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
        }.containerBackground(.background, for: .widget)
    }
}

private struct Metric: View {
    let value: Int; let label: String; var warning = false
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(warning ? .red : .primary);
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProLineTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProLineToday", provider: ProLineProvider()) { ProLineWidgetView(entry: $0) }
            .configurationDisplayName("ProLine Today").description("Surveys, active jobs and overdue work.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProLineTaskListWidgetView: View {
    let entry: ProLineEntry
    private var overdueCount: Int {
        let today = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        return entry.snapshot.tasks.filter { ($0.dueDate ?? "9999-12-31") < today }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Task list", systemImage: "checklist").font(.headline).foregroundStyle(.orange)
                Spacer()
                if overdueCount > 0 { Text("\(overdueCount) overdue").font(.caption2.bold()).foregroundStyle(.red) }
            }
            if entry.snapshot.tasks.isEmpty {
                Spacer()
                Label("No open tasks", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.snapshot.tasks.prefix(5)) { task in
                    HStack(spacing: 7) {
                        Image(systemName: "circle").font(.caption).foregroundStyle(task.priority == "high" ? .red : .orange)
                        Text(task.title).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        if let due = task.dueDate {
                            Text(shortDate(due)).font(.caption2).foregroundStyle(
                                due < String(ISO8601DateFormatter().string(from: .now).prefix(10)) ? .red : .secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "prolinecrm://tasks"))
        .containerBackground(.background, for: .widget)
    }

    private func shortDate(_ value: String) -> String {
        let pieces = value.split(separator: "-")
        guard pieces.count == 3, let month = Int(pieces[1]), (1...12).contains(month) else { return value }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(Int(pieces[2]) ?? 0) \(months[month - 1])"
    }
}

struct ProLineTaskListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProLineTaskList", provider: ProLineProvider()) { ProLineTaskListWidgetView(entry: $0) }
            .configurationDisplayName("ProLine Tasks")
            .description("Your next roofing CRM tasks and overdue actions.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#if os(iOS)
    struct ProLineTaskLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: ProLineTaskActivityAttributes.self) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Office tasks", systemImage: "checklist").font(.headline).foregroundStyle(.orange); Spacer();
                        Text("\(context.state.openCount) open").font(.caption.bold())
                    }
                    ForEach(context.state.taskTitles.prefix(3), id: \.self) { title in
                        Label(title, systemImage: "circle").font(.caption).lineLimit(1)
                    }
                    if context.state.overdueCount > 0 {
                        Label("\(context.state.overdueCount) overdue", systemImage: "exclamationmark.triangle.fill").font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }.padding().activityBackgroundTint(Color.black.opacity(0.86)).activitySystemActionForegroundColor(.white)
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) { Label("Tasks", systemImage: "checklist").foregroundStyle(.orange) }
                    DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.openCount) open").font(.caption.bold()) }
                    DynamicIslandExpandedRegion(.bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(context.state.taskTitles.prefix(2), id: \.self) { Text("• \($0)").font(.caption).lineLimit(1) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } compactLeading: {
                    Image(systemName: "checklist").foregroundStyle(.orange)
                } compactTrailing: {
                    Text("\(context.state.openCount)")
                } minimal: {
                    Image(systemName: context.state.overdueCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle").foregroundStyle(
                        context.state.overdueCount > 0 ? .red : .orange)
                }
            }
        }
    }
#endif

@main
struct ProLineWidgets: WidgetBundle {
    var body: some Widget {
        ProLineTodayWidget()
        ProLineTaskListWidget()
        #if os(iOS)
            ProLineTaskLiveActivity()
        #endif
    }
}
