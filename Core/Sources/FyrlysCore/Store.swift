import Foundation

/// Der små ting lagres (UserDefaults i appen, i minnet i testene).
public protocol KeyValueStore: AnyObject {
    func strings(_ key: String) -> [String]
    func set(_ value: [String], for key: String)
}

extension UserDefaults: KeyValueStore {
    public func strings(_ key: String) -> [String] { stringArray(forKey: key) ?? [] }
    public func set(_ value: [String], for key: String) { set(value as Any, forKey: key) }
}

public final class MemoryStore: KeyValueStore {
    var values: [String: [String]] = [:]
    public init() {}
    public func strings(_ key: String) -> [String] { values[key] ?? [] }
    public func set(_ value: [String], for key: String) { values[key] = value }
}

/// Favoritter og «sist sett» for én innlogging (kanal-id-ene er ulike hos ulike leverandører).
public final class Library {
    let store: KeyValueStore
    let loginId: String
    public static let recentMax = 20

    public init(store: KeyValueStore, loginId: String) {
        self.store = store
        self.loginId = loginId
    }

    func key(_ name: String) -> String { "\(name)@\(loginId)" }

    /// kanal-id-ene i favorittene, i den rekkefølgen de ble lagt til
    public var favorites: [String] { store.strings(key("favorites")) }

    public func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    /// Legger til eller fjerner; svaret er om den er favoritt etterpå.
    @discardableResult
    public func toggleFavorite(_ id: String) -> Bool {
        var list = favorites
        if let i = list.firstIndex(of: id) {
            list.remove(at: i)
            store.set(list, for: key("favorites"))
            return false
        }
        list.append(id)
        store.set(list, for: key("favorites"))
        return true
    }

    /// sist sett først
    public var recent: [String] { store.strings(key("recent")) }

    public func addRecent(_ id: String) {
        var list = recent.filter { $0 != id }
        list.insert(id, at: 0)
        store.set(Array(list.prefix(Library.recentMax)), for: key("recent"))
    }
}

/// Kanalene i den rekkefølgen id-ene står i (de som ikke finnes lenger, hoppes over).
public func channels(_ ids: [String], in byId: [String: Channel]) -> [Channel] {
    ids.compactMap { byId[$0] }
}

/// Søk i kanalnavnene: alle ordene må finnes, uten hensyn til store og små bokstaver.
public func search(_ query: String, in channels: [Channel], limit: Int = 200) -> [Channel] {
    let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
    guard !words.isEmpty else { return [] }
    var out: [Channel] = []
    for c in channels {
        let name = c.name.lowercased()
        if words.allSatisfy({ name.contains($0) }) {
            out.append(c)
            if out.count >= limit { break }
        }
    }
    return out
}
