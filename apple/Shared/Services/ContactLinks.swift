import Foundation

/// Builds phone, message and email links from the free-text values customers
/// give us. Every function returns nil rather than trapping on a stray space,
/// so a typo in a contact field can never crash a screen.
enum ContactLinks {
    static func digits(_ raw: String) -> String { raw.filter { $0.isNumber || $0 == "+" } }

    static func telephone(_ raw: String) -> URL? {
        let value = digits(raw)
        return value.isEmpty ? nil : URL(string: "tel:\(value)")
    }

    static func message(_ raw: String) -> URL? {
        let value = digits(raw)
        return value.isEmpty ? nil : URL(string: "sms:\(value)")
    }

    static func whatsApp(_ raw: String) -> URL? {
        var value = digits(raw)
        if value.hasPrefix("0") { value = "44" + value.dropFirst() }
        value = value.replacingOccurrences(of: "+", with: "")
        return value.isEmpty ? nil : URL(string: "https://wa.me/\(value)")
    }

    static func email(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("@"),
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "mailto:\(encoded)")
    }

    static func maps(address: String) -> URL? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, var parts = URLComponents(string: "https://maps.apple.com/") else { return nil }
        parts.queryItems = [URLQueryItem(name: "q", value: value)]
        return parts.url
    }
}
