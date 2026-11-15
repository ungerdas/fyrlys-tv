import Foundation

/// Innloggingene slik de deles i iCloud (appens nøkkel–verdi-lagring), så en innlogging lagt til på én enhet dukker
/// opp på de andre: lista, og id-ene til de som er fjernet (så de ikke kommer tilbake fra en annen enhet).
public struct SyncedLogins: Codable, Equatable, Sendable {
    public var logins: [Login]
    public var removed: [String]

    public init(logins: [Login] = [], removed: [String] = []) {
        self.logins = logins
        self.removed = removed
    }

    /// så mange fjernede id-er huskes (de eldste glemmes)
    public static let removedLimit = 50
}

/// [local] (rekkefølgen her: den i bruk først) flettet med det som kom fra iCloud: de som er fjernet på en annen
/// enhet, tas bort (unntatt [keep], den som er i bruk her), de som er endret der (navnet, klienten), får den nye
/// versjonen, og de som er nye, kommer til slutt. [removedHere]: fjernet på denne enheten, og skal ikke komme tilbake.
public func mergeLogins(local: [Login], cloud: SyncedLogins, removedHere: Set<String> = [],
                        keep: String? = nil) -> [Login] {
    let gone = Set(cloud.removed).union(removedHere)
    let theirs = Dictionary(cloud.logins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    var result: [Login] = []
    for login in local where !gone.contains(login.id) || login.id == keep {
        guard seen.insert(login.id).inserted else { continue }
        result.append(theirs[login.id] ?? login)
    }
    for login in cloud.logins where !gone.contains(login.id) || login.id == keep {
        guard seen.insert(login.id).inserted else { continue }
        result.append(login)
    }
    return result
}

/// Det som skal til iCloud: lista, og de fjernede (høyst `removedLimit`, de nyeste sist), uten dem som finnes igjen.
public func syncedLogins(_ logins: [Login], removed: [String]) -> SyncedLogins {
    let present = Set(logins.map(\.id))
    var kept: [String] = []
    for id in removed where !present.contains(id) && !kept.contains(id) { kept.append(id) }
    return SyncedLogins(logins: logins, removed: Array(kept.suffix(SyncedLogins.removedLimit)))
}
