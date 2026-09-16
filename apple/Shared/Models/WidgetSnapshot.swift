import Foundation

#if os(iOS)
    import ActivityKit
#endif

#if os(iOS)
    struct ProLineTaskActivityAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable {
            var taskTitles: [String]
            var openCount: Int
            var overdueCount: Int
            var updatedAt: Date
        }
        var title: String
    }
#endif

struct WidgetSnapshot: Codable, Sendable {
    struct TaskItem: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var dueDate: String?
        var priority: String
    }

    var surveysToday: Int
    var overdueJobs: Int
    var activeJobs: Int
    var tasks: [TaskItem]
    var updatedAt: Date

    static let empty = WidgetSnapshot(surveysToday: 0, overdueJobs: 0, activeJobs: 0, tasks: [], updatedAt: .now)
    static let appGroup = "group.com.prolineroofingandsolar.crm"
    static let storageKey = "proline-widget-snapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(Self.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.storageKey)
    }

    init(surveysToday: Int, overdueJobs: Int, activeJobs: Int, tasks: [TaskItem] = [], updatedAt: Date) {
        self.surveysToday = surveysToday
        self.overdueJobs = overdueJobs
        self.activeJobs = activeJobs
        self.tasks = tasks
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case surveysToday, overdueJobs, activeJobs, tasks, updatedAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        surveysToday = try values.decode(Int.self, forKey: .surveysToday)
        overdueJobs = try values.decode(Int.self, forKey: .overdueJobs)
        activeJobs = try values.decode(Int.self, forKey: .activeJobs)
        tasks = try values.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}
