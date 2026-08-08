import Foundation
import Security

/// Dünner Keychain-Wrapper. Speichert kleine Datenmengen geräteintern.
///
/// kSecAttrAccessibleWhenUnlockedThisDeviceOnly: der Eintrag verlässt das Gerät
/// nie (kein iCloud-Keychain-Sync, kein Backup-Transfer auf ein neues Gerät)
/// und ist nur bei entsperrtem Gerät lesbar. Für einen Besitzfaktor ist genau
/// das richtig – ein mitgesyncter Schlüssel wäre kein Besitzfaktor mehr.
enum KeychainStore {

    enum Key: String {
        case registeredCardHash = "de.keyfocus.registeredCardHash"
    }

    @discardableResult
    static func save(_ data: Data, for key: Key) -> Bool {
        // Erst löschen: SecItemAdd schlägt bei vorhandenem Eintrag mit
        // errSecDuplicateItem fehl, ein Update wäre der zweite Roundtrip.
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(_ key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
