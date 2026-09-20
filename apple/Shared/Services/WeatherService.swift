import CoreLocation
import Foundation
import Observation

/// One hour of forecast.
struct WeatherHour: Sendable, Equatable {
    let date: Date
    let temperature: Double
    let rainChance: Int
    let code: Int
}

/// One day of forecast.
struct WeatherDay: Sendable, Equatable {
    let date: Date
    let maxTemperature: Double
    let code: Int
}

struct Forecast: Sendable, Equatable {
    let hours: [WeatherHour]
    let days: [WeatherDay]
    let fetchedAt: Date

    func hours(on day: Date, calendar: Calendar = .current) -> [WeatherHour] {
        hours.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The hour nearest to `date`.
    func hour(at date: Date) -> WeatherHour? {
        hours.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Weather symbols and the short site note, kept free of UI so they can be tested.
enum WeatherPolicy {
    /// WMO weather code → SF Symbol name.
    nonisolated static func symbol(for code: Int) -> String {
        switch code {
        case 0, 1: "sun.max"
        case 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...67: "cloud.rain"
        case 71...77: "cloud.snow"
        case 80...82: "cloud.heavyrain"
        case 95...99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    nonisolated static func isWet(_ code: Int) -> Bool { code >= 51 }

    /// "rain from 15:00", "dry from 11:00", or "dry all day" for the working day (07:00–18:00).
    nonisolated static func note(for hours: [WeatherHour], now: Date, calendar: Calendar = .current) -> String? {
        let working = hours.filter { calendar.component(.hour, from: $0.date) >= 7 && calendar.component(.hour, from: $0.date) <= 18 }
        guard !working.isEmpty else { return nil }
        let upcoming = working.filter { $0.date >= calendar.date(byAdding: .hour, value: -1, to: now) ?? now }
        let current = upcoming.first ?? working.last!
        let rainingNow = current.rainChance >= 50 || isWet(current.code)
        let format: (Date) -> String = { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        if rainingNow {
            if let clear = upcoming.first(where: { $0.rainChance < 30 && !isWet($0.code) }) { return "dry from \(format(clear.date))" }
            return "rain all day"
        }
        if let wet = upcoming.first(where: { $0.rainChance >= 50 || isWet($0.code) }) { return "rain from \(format(wet.date))" }
        return "dry all day"
    }
}

/// Open-Meteo forecast for the site. No key, no account; fails quietly so the UI just hides.
@MainActor @Observable
final class WeatherService {
    private(set) var forecast: Forecast?
    private(set) var coordinate: CLLocationCoordinate2D?
    private var lastCoordinateKey = ""

    /// Refreshes if the cached forecast is older than 30 minutes or the location moved.
    func refresh(near coordinate: CLLocationCoordinate2D?, fallbackAddress: String) async {
        var found = coordinate
        if found == nil { found = await geocode(fallbackAddress) }
        let resolved = found ?? CLLocationCoordinate2D(latitude: 51.38, longitude: -2.36)
        let key = String(format: "%.2f,%.2f", resolved.latitude, resolved.longitude)
        if key == lastCoordinateKey, let forecast, Date.now.timeIntervalSince(forecast.fetchedAt) < 1800 { return }
        do {
            forecast = try await fetch(resolved)
            self.coordinate = resolved
            lastCoordinateKey = key
        } catch {
            // Weather is a convenience; a failed fetch simply leaves the last forecast in place.
        }
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let stored = UserDefaults.standard.dictionary(forKey: "weatherCoordinate") as? [String: Double],
           stored["address"].map({ Double(clean.hashValue) == $0 }) == true, let lat = stored["lat"], let lng = stored["lng"] {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard let placemark = try? await CLGeocoder().geocodeAddressString(clean).first, let location = placemark.location else { return nil }
        UserDefaults.standard.set(["address": Double(clean.hashValue), "lat": location.coordinate.latitude, "lng": location.coordinate.longitude], forKey: "weatherCoordinate")
        return location.coordinate
    }

    private func fetch(_ coordinate: CLLocationCoordinate2D) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weathercode"),
            .init(name: "daily", value: "weathercode,temperature_2m_max"),
            .init(name: "timezone", value: "Europe/London"),
            .init(name: "forecast_days", value: "7"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = formatter.locale
        dayFormatter.timeZone = formatter.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let hours = zip(zip(payload.hourly.time, payload.hourly.temperature_2m), zip(payload.hourly.precipitation_probability, payload.hourly.weathercode))
            .compactMap { pair -> WeatherHour? in
                guard let date = formatter.date(from: pair.0.0) else { return nil }
                return WeatherHour(date: date, temperature: pair.0.1 ?? 0, rainChance: pair.1.0 ?? 0, code: pair.1.1 ?? 3)
            }
        let days = zip(zip(payload.daily.time, payload.daily.temperature_2m_max), payload.daily.weathercode)
            .compactMap { pair -> WeatherDay? in
                guard let date = dayFormatter.date(from: pair.0.0) else { return nil }
                return WeatherDay(date: date, maxTemperature: pair.0.1 ?? 0, code: pair.1 ?? 3)
            }
        return Forecast(hours: hours, days: days, fetchedAt: .now)
    }

    private struct Payload: Decodable {
        struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double?]; let precipitation_probability: [Int?]; let weathercode: [Int?] }
        struct Daily: Decodable { let time: [String]; let weathercode: [Int?]; let temperature_2m_max: [Double?] }
        let hourly: Hourly
        let daily: Daily
    }
}
