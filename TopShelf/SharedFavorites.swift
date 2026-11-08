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

/// «Fortsett å se» til Top Shelf (fra 0.2.4): filmen eller serien, bredbildet og hvor langt du har kommet.
struct SharedResume: Codable, Hashable {
    let id: String
    /// "movies" eller "series"
    let kind: String
    /// nil = IPTV-leverandøren, "plex" = Plex
    let source: String?
    let name: String
    /// «S1 E3» for en episode
    let episode: String?
    let image: String?
    let progress: Double
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
        write(favorites, account: account)
    }

    static func load() -> [SharedFavorite] {
        read(account: account) ?? []
    }

    static let resumeAccount = "fortsett"

    static func saveResume(_ entries: [SharedResume]) {
        write(entries, account: resumeAccount)
    }

    static func loadResume() -> [SharedResume] {
        read(account: resumeAccount) ?? []
    }

    private static func write<T: Encodable>(_ value: T, account: String) {
        guard let group, let data = try? JSONEncoder().encode(value) else { return }
        // det samme som før: ikke skriv (Top Shelf lastes på nytt for hver endring)
        if read(account: account, as: Data.self) == data { return }
        var q = query(group)
        q[kSecAttrAccount as String] = account
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func read(account: String, as: Data.Type) -> Data? {
        guard let group else { return nil }
        var q = query(group)
        q[kSecAttrAccount as String] = account
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func read<T: Decodable>(account: String) -> T? {
        guard let data = read(account: account, as: Data.self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// fyrlys://vod/<plex|iptv>/<movies|series>/<id>?navn=…: siden for filmen eller serien
    static func url(_ resume: SharedResume) -> URL? {
        var parts = URLComponents()
        parts.scheme = "fyrlys"
        parts.host = "vod"
        parts.path = "/\(resume.source ?? "iptv")/\(resume.kind)/\(resume.id)"
        parts.queryItems = [URLQueryItem(name: "navn", value: resume.name)]
        return parts.url
    }

    /// fyrlys://kanal/<id>: Top Shelf åpner appen og spiller kanalen
    static func url(_ id: String) -> URL? {
        URL(string: "fyrlys://kanal/\(id)")
    }
}
