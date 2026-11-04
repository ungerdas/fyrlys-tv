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

    /// Bare favorittene (kanaler, filmer og serier), favorittkategoriene, egne strømmer og de skjulte Plex-bibliotekene
    /// deles.
    static func shared(_ key: String) -> Bool {
        key.hasPrefix("favorites@") || key.hasPrefix("favoriteCategories@") || key.hasPrefix("vodFavorites@")
            || key == "egne-strommer" || key == "plex-skjulte"
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
