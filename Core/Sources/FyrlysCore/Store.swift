import Foundation

/// [first] i sin rekkefølge og så det i [second] som ikke er der fra før (to enheters favoritter første gang de møtes i
/// iCloud: ingen av dem mister noe).
public func mergeIds(_ first: [String], _ second: [String]) -> [String] {
    var seen = Set(first)
    var out = first
    for id in second where seen.insert(id).inserted {
        out.append(id)
    }
    return out
}

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

/// Favoritter, favorittkategorier og «sist sett» for én innlogging (id-ene er ulike hos ulike leverandører). Holdes i
/// minnet og skrives til lagringen ved hver endring: å lese lagringen for hvert kort som tegnes, er for tregt.
public final class Library {
    let store: KeyValueStore
    let loginId: String
    public static let recentMax = 20

    /// kanal-id-ene i favorittene, i den rekkefølgen de ble lagt til
    public private(set) var favorites: [String]
    private var favoriteSet: Set<String>
    /// kategori-id-ene i favorittkategoriene, øverste først
    public private(set) var favoriteCategories: [String]
    /// sist sett først
    public private(set) var recent: [String]

    public init(store: KeyValueStore, loginId: String) {
        self.store = store
        self.loginId = loginId
        favorites = store.strings(Library.key("favorites", loginId))
        favoriteSet = Set(favorites)
        favoriteCategories = store.strings(Library.key("favoriteCategories", loginId))
        recent = store.strings(Library.key("recent", loginId))
    }

    static func key(_ name: String, _ loginId: String) -> String { "\(name)@\(loginId)" }

    /// Leser alt på nytt fra lagringen (når en annen enhet har endret favorittene via iCloud).
    public func reload() {
        favorites = store.strings(key("favorites"))
        favoriteSet = Set(favorites)
        favoriteCategories = store.strings(key("favoriteCategories"))
        recent = store.strings(key("recent"))
    }

    func key(_ name: String) -> String { Library.key(name, loginId) }

    public func isFavorite(_ id: String) -> Bool { favoriteSet.contains(id) }

    /// Legger til eller fjerner; svaret er om den er favoritt etterpå.
    @discardableResult
    public func toggleFavorite(_ id: String) -> Bool {
        if let i = favorites.firstIndex(of: id) {
            favorites.remove(at: i)
            favoriteSet.remove(id)
        } else {
            favorites.append(id)
            favoriteSet.insert(id)
        }
        store.set(favorites, for: key("favorites"))
        return favoriteSet.contains(id)
    }

    public func isFavoriteCategory(_ id: String) -> Bool { favoriteCategories.contains(id) }

    /// Legger til (nederst blant favorittkategoriene) eller fjerner; svaret er om den er favoritt etterpå.
    @discardableResult
    public func toggleFavoriteCategory(_ id: String) -> Bool {
        if let i = favoriteCategories.firstIndex(of: id) {
            favoriteCategories.remove(at: i)
            store.set(favoriteCategories, for: key("favoriteCategories"))
            return false
        }
        favoriteCategories.append(id)
        store.set(favoriteCategories, for: key("favoriteCategories"))
        return true
    }

    /// Bytter plass med kategorien over (-1) eller under (1), som i Fyrlys på Windows. Med [shown] hoppes kategorier
    /// som ikke vises (ikke finnes hos leverandøren lenger) over, så flyttingen alltid synes.
    public func moveFavoriteCategory(_ id: String, by step: Int, shown: Set<String>? = nil) {
        guard step != 0, let i = favoriteCategories.firstIndex(of: id) else { return }
        let direction = step < 0 ? -1 : 1
        var j = i + direction
        while favoriteCategories.indices.contains(j), let shown, !shown.contains(favoriteCategories[j]) {
            j += direction
        }
        guard favoriteCategories.indices.contains(j) else { return }
        favoriteCategories.swapAt(i, j)
        store.set(favoriteCategories, for: key("favoriteCategories"))
    }

    /// Ny rekkefølge for favorittkategoriene som vises (dra og slipp på iPhone); de som ikke vises (ikke finnes hos
    /// leverandøren lenger), legges bakerst, og ingen kategorier legges til eller fjernes her.
    public func setFavoriteCategoryOrder(_ shown: [String]) {
        var seen = Set<String>()
        let ordered = shown.filter { isFavoriteCategory($0) && seen.insert($0).inserted }
        favoriteCategories = ordered + favoriteCategories.filter { !seen.contains($0) }
        store.set(favoriteCategories, for: key("favoriteCategories"))
    }

    public func addRecent(_ id: String) {
        var list = recent.filter { $0 != id }
        list.insert(id, at: 0)
        recent = Array(list.prefix(Library.recentMax))
        store.set(recent, for: key("recent"))
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
