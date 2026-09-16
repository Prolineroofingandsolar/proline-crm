import Foundation

/// Human-readable versions of the ISO strings the database stores.
enum CRMFormat {
    /// "Tue 16 Sep" (adds the year when it isn't this year). Falls back to the raw value.
    static func day(_ iso: String?) -> String {
        guard let iso, let date = SupabaseService.date(from: iso) else { return iso ?? "Not set" }
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(
            sameYear ? .dateTime.weekday(.abbreviated).day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())
    }

    /// "Today", "Tomorrow", "Yesterday", or the day.
    static func relativeDay(_ iso: String?) -> String {
        guard let iso, let date = SupabaseService.date(from: iso) else { return iso ?? "Not set" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return day(iso)
    }

    static func money(_ value: Double, pence: Bool = false) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(pence ? 2 : 0)))
    }
}
