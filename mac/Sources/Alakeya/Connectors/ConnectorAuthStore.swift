import Foundation
import Security

// ============================================================
// ConnectorAuthStore.swift
// Secrets (tokens, API keys) → Keychain.
// Non-sensitive state (status, email) → UserDefaults (encoded).
// ============================================================

final class ConnectorAuthStore {
    static let shared = ConnectorAuthStore()
    private let keychainService = "com.alakeya.connectors"
    private let statesKey       = "alakeya.connectors.states"
    private init() {}

    // MARK: - Keychain (tokens / API keys)

    func saveToken(_ token: String, for connectorID: String, account: String = "default") {
        let key  = "\(connectorID).\(account)"
        let data = Data(token.utf8)
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = q; newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func loadToken(for connectorID: String, account: String = "default") -> String? {
        let key = "\(connectorID).\(account)"
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken(for connectorID: String, account: String = "default") {
        let key = "\(connectorID).\(account)"
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }

    func hasToken(for connectorID: String) -> Bool {
        loadToken(for: connectorID) != nil
    }

    // MARK: - UserDefaults (non-sensitive state)

    func loadStates() -> [String: ConnectorConnectionState] {
        guard let data = UserDefaults.standard.data(forKey: statesKey),
              let states = try? JSONDecoder().decode([String: ConnectorConnectionState].self, from: data)
        else { return [:] }
        return states
    }

    func saveState(_ state: ConnectorConnectionState) {
        var states = loadStates()
        states[state.connectorID] = state
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: statesKey)
        }
    }

    func removeState(for connectorID: String) {
        var states = loadStates()
        states.removeValue(forKey: connectorID)
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: statesKey)
        }
    }
}
