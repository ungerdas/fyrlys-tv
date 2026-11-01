import Foundation

/// Kategoriene og kanalene slik appen bruker dem: oppslag på id og kategori, bare kategoriene som har kanaler, og
/// navnene med små bokstaver til søket. Lages én gang per liste og utenfor hovedtråden: med titusenvis av kanaler tar
/// det merkbar tid.
public struct ChannelIndex: Sendable {
    public let lists: Lists
    /// kanalene, med kanaler som er slått sammen (se `merged`) bare én gang
    public let channels: [Channel]
    public let byId: [String: Channel]
    public let byCategory: [String: [Channel]]
    /// bare kategorier med kanaler, i leverandørens rekkefølge
    public let categories: [ChannelCategory]
    /// kanalene som er slått sammen: id-en som er beholdt → alle id-ene (den beholdte først)
    public let merged: [String: [String]]
    /// nøklene (`channelKey`) kanalene ble slått sammen etter
    public let mergeKeys: Set<String>
    let categoryById: [String: ChannelCategory]
    /// kanalnavnene med små bokstaver, i samme rekkefølge som `channels`
    let searchNames: [String]
    /// plassene i `channels` for kanalene i hver kategori
    let positions: [String: [Int]]

    /// [keys]: kanaler med samme nøkkel (`channelKey`) blir én, som når de spilles fra samme egne strøm (NRK1 HD,
    /// NRK1 FHD og NRK 1 → NRK1). Den med programinfo og logo beholdes og står i alle kategoriene de andre sto i;
    /// id-ene til de andre peker til den.
    public init(_ lists: Lists, merging keys: Set<String> = []) {
        self.lists = lists
        mergeKeys = keys
        let source = lists.channels
        // gruppene: bare kanaler der nøkkelen kan finnes i navnet regnes ut (det regulære uttrykket koster)
        var keptFor: [Int: Int] = [:]
        var merged: [String: [String]] = [:]
        if !keys.isEmpty {
            var groups: [String: [Int]] = [:]
            for (i, channel) in source.enumerated() {
                let compact = String(channel.name.lowercased().filter { $0.isLetter || $0.isNumber })
                guard keys.contains(where: { compact.contains($0) }) else { continue }
                let key = channelKey(channel.name)
                if keys.contains(key) { groups[key, default: []].append(i) }
            }
            for members in groups.values where members.count > 1 {
                let score = { (i: Int) -> Int in (source[i].hasEpg ? 2 : 0) + (source[i].logo == nil ? 0 : 1) }
                let kept = members.reduce(members[0]) { best, i in score(i) > score(best) ? i : best }
                for i in members { keptFor[i] = kept }
                merged[source[kept].id] = [source[kept].id] + members.filter { $0 != kept }.map { source[$0].id }
            }
        }
        self.merged = merged
        // kanalene uten de som er slått inn i en annen
        var channels: [Channel] = []
        var newIndex: [Int: Int] = [:]
        channels.reserveCapacity(source.count)
        for (i, channel) in source.enumerated() where keptFor[i] == nil || keptFor[i] == i {
            newIndex[i] = channels.count
            channels.append(channel)
        }
        self.channels = channels
        // kategoriene: en sammenslått kanal står der hver av dem sto, én gang
        var positions: [String: [Int]] = [:]
        var placed = Set<String>()
        for (i, channel) in source.enumerated() {
            guard let at = newIndex[keptFor[i] ?? i] else { continue }
            if keptFor[i] != nil, !placed.insert("\(channel.categoryId)|\(at)").inserted { continue }
            positions[channel.categoryId, default: []].append(at)
        }
        var byId: [String: Channel] = [:]
        byId.reserveCapacity(source.count)
        for channel in channels where byId[channel.id] == nil { byId[channel.id] = channel }
        for (i, kept) in keptFor where i != kept { byId[source[i].id] = source[kept] }
        self.byId = byId
        self.positions = positions
        byCategory = positions.mapValues { $0.map { channels[$0] } }
        categories = lists.categories.filter { positions[$0.id] != nil }
        categoryById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // en sammenslått kanal finnes på navnene til alle (søk på «nrk1» finner «NRK 1» når «NRK1 HD» var med)
        if merged.isEmpty {
            searchNames = channels.map { $0.name.lowercased() }
        } else {
            var names: [String: String] = [:]
            for i in keptFor.keys { names[source[i].id] = source[i].name }
            searchNames = channels.map { channel in
                guard let ids = merged[channel.id] else { return channel.name.lowercased() }
                return ids.compactMap { names[$0] }.joined(separator: " | ").lowercased()
            }
        }
    }

    /// Id-ene en kanal har (flere når kanaler er slått sammen).
    public func ids(of channel: Channel) -> [String] { merged[channel.id] ?? [channel.id] }

    public static let empty = ChannelIndex(Lists(categories: [], channels: []))

    public func channels(in categoryId: String) -> [Channel] { byCategory[categoryId] ?? [] }

    public func category(_ id: String) -> ChannelCategory? { categoryById[id] }

    /// Samme kategorier og kanaler som [other] (når lista ble lagret, teller ikke).
    public func hasSameLists(as other: Lists) -> Bool {
        lists.categories == other.categories && lists.channels == other.channels
    }

    /// Kategori-id-ene i [ids] som finnes, uten doble, i samme rekkefølge.
    func existing(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { positions[$0] != nil && seen.insert($0).inserted }
    }

    /// Alle kanalene, med kanalene i kategoriene [first] først (i den rekkefølgen), så resten i leverandørens
    /// rekkefølge.
    public func channels(favoring first: [String]) -> [Channel] {
        let favored = existing(first)
        guard !favored.isEmpty else { return channels }
        let set = Set(favored)
        var out: [Channel] = []
        out.reserveCapacity(channels.count)
        var seen = Set<String>()
        for id in favored {
            for channel in byCategory[id] ?? [] where merged.isEmpty || seen.insert(channel.id).inserted {
                out.append(channel)
            }
        }
        for channel in channels where !set.contains(channel.categoryId) {
            if merged.isEmpty || seen.insert(channel.id).inserted { out.append(channel) }
        }
        return out
    }

    /// Søk i kanalnavnene: alle ordene må finnes, uten hensyn til store og små bokstaver. Treffene i kategoriene
    /// [first] kommer først (i den rekkefølgen), så resten i leverandørens rekkefølge.
    public func search(_ query: String, favoring first: [String] = [], limit: Int = 200) -> [Channel] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty, limit > 0 else { return [] }
        let favored = existing(first)
        let set = Set(favored)
        var out: [Channel] = []
        var seen = Set<Int>()
        for id in favored {
            for i in positions[id] ?? [] where words.allSatisfy({ searchNames[i].contains($0) }) {
                guard seen.insert(i).inserted else { continue }
                out.append(channels[i])
                if out.count >= limit { return out }
            }
        }
        for (i, name) in searchNames.enumerated()
        where !set.contains(channels[i].categoryId) && words.allSatisfy({ name.contains($0) }) {
            guard seen.insert(i).inserted else { continue }
            out.append(channels[i])
            if out.count >= limit { break }
        }
        return out
    }
}
