import FyrlysCore
import Foundation

/// Favorittene og «Dine kategorier» i iCloud (nøkkel–verdi-lagringen), så de er de samme på iPhone, iPad og Apple TV
/// med samme Apple-ID. Alt ligger også i UserDefaults på enheten, og «sist sett» bare der. Uten iCloud (ikke logget
/// inn, eller appen er ikke signert med iCloud) virker alt som før, bare uten deling.
final class CloudStore: KeyValueStore {
    private let local: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    init(local: UserDefaults) {
        self.local = local
        cloud.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Bare favorittene (kanaler, filmer og serier), favorittkategoriene, landene som vises, egne strømmer og de
    /// skjulte Plex-bibliotekene deles.
    static func shared(_ key: String) -> Bool {
        key.hasPrefix("favorites@") || key.hasPrefix("favoriteCategories@") || key.hasPrefix("vodFavorites@")
            || key.hasPrefix("land@") || key == "egne-strommer" || key == "plex-skjulte" || key == "feilrapport-tv"
    }

    private static func mergedKey(_ key: String) -> String { "icloud-flettet@" + key }

    func strings(_ key: String) -> [String] {
        let mine = local.strings(key)
        guard Self.shared(key) else { return mine }
        let theirs = cloud.array(forKey: key) as? [String]
        // første gang på denne enheten: det som lå her fra før, flettes inn i det som er i iCloud
        if !local.bool(forKey: Self.mergedKey(key)) {
            local.set(true, forKey: Self.mergedKey(key))
            let merged = mergeIds(theirs ?? [], mine)
            if merged != theirs { cloud.set(merged, forKey: key) }
            local.set(merged, for: key)
            return merged
        }
        if let theirs {
            local.set(theirs, for: key)
            return theirs
        }
        return mine
    }

    func set(_ value: [String], for key: String) {
        local.set(value, for: key)
        if Self.shared(key) { cloud.set(value, forKey: key) }
    }

    /// [changed] kalles (på hovedtråden) når en annen enhet har endret noe. Ved den første synkroniseringen med iCloud
    /// flettes det enheten hadde, inn i det som kom, ellers gjelder det som kom.
    func observe(_ changed: @escaping () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []).filter(Self.shared)
            guard !keys.isEmpty else { return }
            for key in keys {
                let theirs = self.cloud.array(forKey: key) as? [String] ?? []
                if reason == NSUbiquitousKeyValueStoreInitialSyncChange {
                    let merged = mergeIds(theirs, self.local.strings(key))
                    if merged != theirs { self.cloud.set(merged, forKey: key) }
                    self.local.set(merged, for: key)
                } else {
                    self.local.set(theirs, for: key)
                }
            }
            changed()
        }
    }
}

/// Innloggingene i iCloud (nøkkelen «innlogginger»), så en innlogging lagt til på Apple TV, iPhone, iPad eller Mac
/// finnes på de andre med samme Apple-ID. Apple TV synker ikke iCloud-nøkkelringen, så de ligger i appens iCloud-data
/// (kryptert av Apple); på enheten ligger de fortsatt i nøkkelringen. Kan slås av i innstillingene. Ikke i testene.
@MainActor
final class LoginCloud {
    static let key = "innlogginger"
    static let offKey = "innlogginger-icloud-av"
    static let removedKey = "innlogginger-fjernet"

    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var enabled: Bool {
        get { !TestSupport.isActive && !defaults.bool(forKey: Self.offKey) }
        set { defaults.set(!newValue, forKey: Self.offKey) }
    }

    /// Det som ligger i iCloud (nil: ingenting, eller av).
    func load() -> SyncedLogins? {
        guard enabled, let data = cloud.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(SyncedLogins.self, from: data)
    }

    func push(_ logins: [Login]) {
        guard enabled else { return }
        let synced = syncedLogins(logins, removed: removedHere)
        guard let data = try? JSONEncoder().encode(synced), cloud.data(forKey: Self.key) != data else { return }
        cloud.set(data, forKey: Self.key)
    }

    /// Fjernet på denne enheten (logget ut, eller fjernet i lista): skal ikke komme tilbake fra en annen enhet.
    var removedHere: [String] { defaults.stringArray(forKey: Self.removedKey) ?? [] }

    func noteRemoved(_ id: String) {
        defaults.set(Array((removedHere.filter { $0 != id } + [id]).suffix(SyncedLogins.removedLimit)),
                     forKey: Self.removedKey)
    }

    /// Lagt til igjen.
    func noteAdded(_ id: String) {
        defaults.set(removedHere.filter { $0 != id }, forKey: Self.removedKey)
    }

    /// [changed] når en annen enhet har endret innloggingene.
    func observe(_ changed: @escaping () -> Void) {
        guard observer == nil else { return }
        cloud.synchronize()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(LoginCloud.key) else { return }
            MainActor.assumeIsolated { changed() }
        }
    }
}
