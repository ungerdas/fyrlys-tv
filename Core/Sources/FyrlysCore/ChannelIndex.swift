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
    /// landene som skal vises (kodene fra `countryOf`, "" = kategoriene uten land; nil: alle)
    public let countries: Set<String>?
    /// ryddige navn: «NOR: TV 2 [720p]» → «TV 2» med et 720p-merke (se `tidyChannelName`)
    public let tidy: Bool
    /// landene i hele lista fra leverandøren (også de som er skjult), til valget av land
    public let countryGroups: [CountryGroup]
    /// kanalene en egen strøm gjelder for: id → nøkkelen (også id-ene som er slått inn i en annen)
    let streamKeyById: [String: String]
    /// navnene på kanalene hver egen strøm gjelder for, hos leverandøren (til innstillingene)
    public let streamNames: [String: [String]]
    let categoryById: [String: ChannelCategory]
    /// kanalnavnene med små bokstaver, i samme rekkefølge som `channels`
    let searchNames: [String]
    /// plassene i `channels` for kanalene i hver kategori
    let positions: [String: [Int]]

    /// [keys]: kanaler med samme nøkkel (`channelKey`) blir én, som når de spilles fra samme egne strøm (NRK1 HD,
    /// NRK1 FHD og NRK 1 HD NO → NRK1). Den med programinfo og logo beholdes og står i alle kategoriene de andre sto
    /// i; id-ene til de andre peker til den. En kanal med «a/b» i navnet blir to når begge har en strøm
    /// («NRK 3/SUPER NO» → «NRK 3 NO» og «NRK SUPER NO», med id-en `<id>~nrksuper`).
    ///
    /// [countries]: bare kategoriene fra disse landene vises (i kategoriene, «Alle kanaler» og søket); finnes ingen av
    /// dem (leverandøren har byttet navn på kategoriene), vises alt. `byId` har også kanalene som er skjult, så
    /// favorittene og «Sist sett» står som før. [tidy]: ryddige kanal- og kategorinavn (som Fyrlys for Windows 2.1.47).
    public init(_ lists: Lists, merging keys: Set<String> = [], countries: Set<String>? = nil, tidy: Bool = false) {
        self.lists = lists
        mergeKeys = keys
        self.countries = countries
        self.tidy = tidy
        var source: [Channel] = []
        var keyAt: [Int: String] = [:]
        // landet i navnet («TV 2 HD DK»): en strøm uten land gjelder de norske, se `homeCountries`
        var countryAt: [Int: String] = [:]
        // delt ut av en annen kanal (har ikke egen programinfo eller logo)
        var derived = Set<Int>()
        if keys.isEmpty {
            source = lists.channels
        } else {
            source.reserveCapacity(lists.channels.count + 8)
            for channel in lists.channels {
                // bare kanaler der nøkkelen kan finnes i navnet regnes ut (de regulære uttrykkene koster)
                let compact = String(channel.name.lowercased().filter { $0.isLetter || $0.isNumber })
                guard channel.name.contains("/") || keys.contains(where: { compact.contains($0) }) else {
                    source.append(channel)
                    continue
                }
                let found = matchingStreamKeys(channel.name, in: keys)
                guard !found.isEmpty else {
                    source.append(channel)
                    continue
                }
                let country = channelKeyAndCountry(channel.name).country
                for (n, match) in found.enumerated() {
                    keyAt[source.count] = match.key
                    if let country { countryAt[source.count] = country }
                    if n == 0 {
                        source.append(match.name == channel.name ? channel : channel.renamed(match.name))
                    } else {
                        derived.insert(source.count)
                        source.append(channel.split(match.name, key: match.key))
                    }
                }
            }
        }
        // gruppene: kanalene med samme nøkkel (i Norge, eller i landet der kanalen finnes)
        var keptFor: [Int: Int] = [:]
        var merged: [String: [String]] = [:]
        var streamKeyById: [String: String] = [:]
        var streamNames: [String: [String]] = [:]
        if !keyAt.isEmpty {
            var groups: [String: [Int]] = [:]
            for (i, key) in keyAt.sorted(by: { $0.key < $1.key }) { groups[key, default: []].append(i) }
            for (key, all) in groups {
                let home = all.filter { countryAt[$0].map(homeCountries.contains) ?? true }
                let members = home.isEmpty ? all : home
                for i in members {
                    streamKeyById[source[i].id] = key
                    streamNames[key, default: []].append(source[i].name)
                }
                guard members.count > 1 else { continue }
                let score = { (i: Int) -> Int in
                    (derived.contains(i) ? 0 : 4) + (source[i].hasEpg ? 2 : 0) + (source[i].logo == nil ? 0 : 1)
                }
                let kept = members.reduce(members[0]) { best, i in score(i) > score(best) ? i : best }
                for i in members { keptFor[i] = kept }
                merged[source[kept].id] = [source[kept].id] + members.filter { $0 != kept }.map { source[$0].id }
            }
        }
        self.merged = merged
        self.streamKeyById = streamKeyById
        self.streamNames = streamNames
        // kanalene uten de som er slått inn i en annen (med ryddige navn når det er valgt)
        var channels: [Channel] = []
        var newIndex: [Int: Int] = [:]
        channels.reserveCapacity(source.count)
        for (i, channel) in source.enumerated() where keptFor[i] == nil || keptFor[i] == i {
            newIndex[i] = channels.count
            channels.append(tidy ? Self.tidied(channel) : channel)
        }
        // kategoriene: en sammenslått kanal står der hver av dem sto, én gang
        var positions: [String: [Int]] = [:]
        var placed = Set<String>()
        for (i, channel) in source.enumerated() {
            guard let at = newIndex[keptFor[i] ?? i] else { continue }
            if keptFor[i] != nil, !placed.insert("\(channel.categoryId)|\(at)").inserted { continue }
            positions[channel.categoryId, default: []].append(at)
        }
        // alle kanalene, også de som er skjult (favorittene og «Sist sett» står som før)
        var byId: [String: Channel] = [:]
        byId.reserveCapacity(source.count)
        for channel in channels where byId[channel.id] == nil { byId[channel.id] = channel }
        for (i, kept) in keptFor where i != kept {
            if let at = newIndex[kept] { byId[source[i].id] = channels[at] }
        }
        self.byId = byId
        // landet hver kategori hører til ("" = uten land), og landene i hele lista
        var countryById: [String: String] = [:]
        for category in lists.categories where countryById[category.id] == nil {
            countryById[category.id] = countryOf(category.name) ?? ""
        }
        countryGroups = FyrlysCore.countryGroups(lists.categories, lists.channels, countries: countryById)
        // bare landene som er valgt (finnes ingen av dem, vises alt heller enn ingenting)
        if let countries {
            let shown = Set(positions.keys.filter { countries.contains(countryById[$0] ?? "") })
            if !shown.isEmpty, shown.count < positions.count {
                var keep = [Bool](repeating: false, count: channels.count)
                for id in shown {
                    for at in positions[id] ?? [] { keep[at] = true }
                }
                var moved = [Int](repeating: -1, count: channels.count)
                var visible: [Channel] = []
                visible.reserveCapacity(channels.count)
                for at in channels.indices where keep[at] {
                    moved[at] = visible.count
                    visible.append(channels[at])
                }
                channels = visible
                positions = positions.filter { shown.contains($0.key) }.mapValues { $0.map { moved[$0] } }
            }
        }
        self.channels = channels
        self.positions = positions
        byCategory = positions.mapValues { $0.map { channels[$0] } }
        var categories = lists.categories.filter { positions[$0.id] != nil }
        if tidy {
            // flere land: koden står igjen foran kategorinavnet («SE · SPORT»), ellers blir to kategorier like
            let several = Set(categories.compactMap { countryById[$0.id] }.filter { !$0.isEmpty }).count > 1
            categories = categories.map { category in
                let name = tidyCategoryName(category.name, keepCountry: several)
                return name == category.name ? category : ChannelCategory(id: category.id, name: name)
            }
        }
        self.categories = categories
        categoryById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // en sammenslått kanal finnes på navnene til alle (søk på «nrk1» finner «NRK 1» når «NRK1 HD» var med)
        if merged.isEmpty {
            searchNames = channels.map { $0.name.lowercased() }
        } else {
            var names: [String: String] = [:]
            for i in keptFor.keys { names[source[i].id] = source[i].name }
            searchNames = channels.map { channel in
                guard let ids = merged[channel.id] else { return channel.name.lowercased() }
                let all = ids.compactMap { names[$0] }
                return (tidy ? [channel.name] + all : all).joined(separator: " | ").lowercased()
            }
        }
    }

    /// Kanalen med det ryddige navnet (se `tidyChannelName`), eller som den er.
    static func tidied(_ channel: Channel) -> Channel {
        let tidy = tidyChannelName(channel.name)
        guard tidy.name != channel.name || tidy.quality != nil else { return channel }
        return channel.tidied(name: tidy.name, quality: tidy.quality)
    }

    /// Lista har kanaler fra flere land (da kan du velge hvilke som vises).
    public var hasCountries: Bool { hasSeveralCountries(countryGroups) }

    /// Lagd med de samme valgene (nøklene, landene og ryddige navn).
    public func hasSameOptions(merging keys: Set<String>, countries: Set<String>?, tidy: Bool) -> Bool {
        mergeKeys == keys && self.countries == countries && self.tidy == tidy
    }

    /// Id-ene en kanal har (flere når kanaler er slått sammen).
    public func ids(of channel: Channel) -> [String] { merged[channel.id] ?? [channel.id] }

    /// Nøkkelen til den egne strømmen kanalen spilles fra (nil: leverandørens).
    public func streamKey(of channel: Channel) -> String? { streamKeyById[channel.id] }

    public static let empty = ChannelIndex(Lists(categories: [], channels: []))

    public func channels(in categoryId: String) -> [Channel] { byCategory[categoryId] ?? [] }

    public func category(_ id: String) -> ChannelCategory? { categoryById[id] }

    /// Samme kategorier og kanaler som [other] (når lista ble lagret, teller ikke).
    public func hasSameLists(as other: Lists) -> Bool {
        lists.categories == other.categories && lists.channels == other.channels && lists.guides == other.guides
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
