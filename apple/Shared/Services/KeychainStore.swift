import Foundation
import Security

/// Small string store on the keychain.
///
/// On the Mac the items live in the data-protection keychain (the same one iOS uses). The legacy
/// login keychain guards items with a per-binary access list, so every rebuild of the app made
/// macOS ask "ProLine wants to use your confidential information…" — the data-protection keychain
/// trusts the app's signing identity instead and never prompts.
enum KeychainStore {
    private static func baseQuery(_ key: String, legacy: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ProLineCRM", kSecAttrAccount as String: key,
        ]
        #if os(macOS)
            if !legacy { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(key)
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        if let value = read(baseQuery(key)) { return value }
        #if os(macOS)
            // One-off move of items saved by earlier builds into the login keychain.
            if let value = read(baseQuery(key, legacy: true)) {
                set(value, for: key)
                SecItemDelete(baseQuery(key, legacy: true) as CFDictionary)
                return value
            }
        #endif
        return nil
    }

    private static func read(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        #if os(macOS)
            SecItemDelete(baseQuery(key, legacy: true) as CFDictionary)
        #endif
    }
}
