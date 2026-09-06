import Contacts
import MapKit
import Observation

struct AddressSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
}

struct ResolvedAddress {
    let street: String
    let town: String
    let postcode: String
}

@MainActor @Observable
final class AddressSearchService: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var suggestionsSuppressed = false
    private(set) var suggestions: [AddressSuggestion] = []
    private(set) var errorMessage: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.5, longitude: -3.0),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
    }

    func search(_ query: String) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestionsSuppressed = false
        errorMessage = nil
        guard cleaned.count >= 3 else { suggestions = []; completer.queryFragment = ""; return }
        completer.queryFragment = cleaned
    }

    func clear() {
        suggestionsSuppressed = true
        suggestions = []
        completer.queryFragment = ""
        errorMessage = nil
    }

    func resolve(_ suggestion: AddressSuggestion) async -> ResolvedAddress {
        do {
            let request = MKLocalSearch.Request(completion: suggestion.completion)
            let response = try await MKLocalSearch(request: request).start()
            if let postal = response.mapItems.first?.placemark.postalAddress {
                let street = postal.street
                let town = [postal.city, postal.subLocality].first { !$0.isEmpty } ?? ""
                clear()
                return ResolvedAddress(street: street.isEmpty ? suggestion.title : street, town: town, postcode: postal.postalCode)
            }
        } catch {
            errorMessage = "That address could not be completed. You can still enter it manually."
        }
        clear()
        return ResolvedAddress(street: suggestion.title, town: suggestion.subtitle, postcode: "")
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !suggestionsSuppressed else { return }
        suggestions = completer.results.prefix(6).map {
            AddressSuggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard !suggestionsSuppressed else { return }
        suggestions = []
        errorMessage = "Address suggestions are temporarily unavailable. You can still enter it manually."
    }
}
