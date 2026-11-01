import FyrlysCore
import Foundation
import Security

/// Innloggingene i nøkkelringen på enheten (kryptert, og bare for denne appen): den som er i bruk, først. Før 0.1.12
/// var det bare én («login»); den flyttes over første gang.
enum Keychain {
    static let service = "no.fyrlys.tv.login"

    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func saveAll(_ logins: [Login]) {
        SecItemDelete(query("logins") as CFDictionary)
        SecItemDelete(query("login") as CFDictionary)
        guard !logins.isEmpty, let data = try? JSONEncoder().encode(logins) else { return }
        var q = query("logins")
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func loadAll() -> [Login] {
        if let data = read("logins"), let logins = try? JSONDecoder().decode([Login].self, from: data) {
            return logins
        }
        if let data = read("login"), let login = try? JSONDecoder().decode(Login.self, from: data) {
            return [login]
        }
        return []
    }

    /// Plex-tilkoblingen (nøkkelen og serveren), under en egen konto.
    static func savePlex(_ data: Data?) {
        SecItemDelete(query("plex") as CFDictionary)
        guard let data else { return }
        var q = query("plex")
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func loadPlex() -> Data? { read("plex") }

    private static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
