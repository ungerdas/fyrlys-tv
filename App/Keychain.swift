import FyrlysCore
import Foundation
import Security

/// Innloggingen i nøkkelringen på Apple TV-en (kryptert, og bare for denne appen).
enum Keychain {
    static let service = "no.fyrlys.tv.login"
    static let account = "login"

    static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ login: Login) {
        guard let data = try? JSONEncoder().encode(login) else { return }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Login? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Login.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
