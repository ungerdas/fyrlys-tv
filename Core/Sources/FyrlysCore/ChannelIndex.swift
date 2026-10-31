import Foundation

/// Kategoriene og kanalene slik appen bruker dem: oppslag på id og kategori, bare kategoriene som har kanaler, og
/// navnene med små bokstaver til søket. Lages én gang per liste og utenfor hovedtråden: med titusenvis av kanaler tar
/// det merkbar tid.
public struct ChannelIndex: Sendable {
    public let lists: Lists
    public let byId: [String: Channel]
    public let byCategory: [String: [Channel]]
    /// bare kategorier med kanaler, i leverandørens rekkefølge
    public let categories: [ChannelCategory]
    let categoryById: [String: ChannelCategory]
    /// kanalnavnene med små bokstaver, i samme rekkefølge som `channels`
    let searchNames: [String]
    /// plassene i `channels` for kanalene i hver kategori
    let positions: [String: [Int]]

    public init(_ lists: Lists) {
        self.lists = lists
        var byId: [String: Channel] = [:]
        var positions: [String: [Int]] = [:]
        byId.reserveCapacity(lists.channels.count)
        for (i, channel) in lists.channels.enumerated() {
            if byId[channel.id] == nil { byId[channel.id] = channel }
            positions[channel.categoryId, default: []].append(i)
        }
        self.byId = byId
        self.positions = positions
        byCategory = positions.mapValues { $0.map { lists.channels[$0] } }
        categories = lists.categories.filter { positions[$0.id] != nil }
        categoryById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        searchNames = lists.channels.map { $0.name.lowercased() }
    }

    public static let empty = ChannelIndex(Lists(categories: [], channels: []))

    public var channels: [Channel] { lists.channels }

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
        for id in favored { out += byCategory[id] ?? [] }
        for channel in channels where !set.contains(channel.categoryId) { out.append(channel) }
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
        for id in favored {
            for i in positions[id] ?? [] where words.allSatisfy({ searchNames[i].contains($0) }) {
                out.append(channels[i])
                if out.count >= limit { return out }
            }
        }
        for (i, name) in searchNames.enumerated()
        where !set.contains(channels[i].categoryId) && words.allSatisfy({ name.contains($0) }) {
            out.append(channels[i])
            if out.count >= limit { break }
        }
        return out
    }
}
