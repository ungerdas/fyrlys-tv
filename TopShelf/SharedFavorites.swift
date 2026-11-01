import Foundation
import Security

/// Favorittene til Top Shelf (Fyrlys på hjemskjermen til Apple TV): appen skriver kanalene (id, navn og logo) i en
/// felles nøkkelring-gruppe når favorittene endres, og utvidelsen leser dem. Både appen og utvidelsen er signert med
/// gruppen («<team>.no.fyrlys.tv.shared»); uten den (simulatoren i testene) gjøres ingenting.
struct SharedFavorite: Codable, Hashable {
    let id: String
    let name: String
    let logo: String?
}

enum SharedFavorites {
    static let service = "no.fyrlys.tv.topshelf"
    static let account = "favoritter"

    /// Gruppen med team-prefikset, funnet fra et element appen eller utvidelsen lagrer i sin egen gruppe.
    static var group: String? {
        if let cached { return cached }
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service + ".prefiks",
                                    kSecAttrAccount as String: "prefiks"]
        var add = probe
        add[kSecValueData as String] = Data("1".utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        var query = probe
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let found = (result as? [String: Any])?[kSecAttrAccessGroup as String] as? String,
              let dot = found.firstIndex(of: ".") else { return nil }
        let value = String(found[...dot]) + "no.fyrlys.tv.shared"
        cached = value
        return value
    }

    nonisolated(unsafe) private static var cached: String?

    private static func query(_ group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: group]
    }

    static func save(_ favorites: [SharedFavorite]) {
        guard let group, let data = try? JSONEncoder().encode(favorites) else { return }
        SecItemDelete(query(group) as CFDictionary)
        var add = query(group)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> [SharedFavorite] {
        guard let group else { return [] }
        var q = query(group)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return []
        }
        return (try? JSONDecoder().decode([SharedFavorite].self, from: data)) ?? []
    }

    /// fyrlys://kanal/<id>: Top Shelf åpner appen og spiller kanalen
    static func url(_ id: String) -> URL? {
        URL(string: "fyrlys://kanal/\(id)")
    }
}
