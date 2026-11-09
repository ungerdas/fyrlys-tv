import Foundation

/// En kategori hos leverandøren (ikke `Category`: det navnet finnes alt i Objective-C-kjøretiden) (f.eks. «Norge» eller «Sport»).
public struct ChannelCategory: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// En direktekanal.
public struct Channel: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let categoryId: String
    /// kanalnummeret hos leverandøren (num), når det finnes
    public let number: Int?
    /// adressen til logoen, når den finnes
    public let logo: String?
    /// dager i TV-arkivet (0: ingen)
    public let archiveDays: Int
    /// leverandøren har programinfo for kanalen (epg_channel_id); uten den hentes ingen
    public let hasEpg: Bool
    /// kanalen hos leverandøren når denne er delt ut av den («NRK SUPER» fra «NRK 3/SUPER», se `ChannelIndex`)
    public let source: String?
    /// en kanal fra en M3U-liste: adressen og det den heter i TV-guiden (XMLTV)
    public let m3u: M3UChannel?

    public init(id: String, name: String, categoryId: String, number: Int? = nil, logo: String? = nil,
                archiveDays: Int = 0, hasEpg: Bool = true, source: String? = nil, m3u: M3UChannel? = nil) {
        self.id = id
        self.name = name
        self.categoryId = categoryId
        self.number = number
        self.logo = logo
        self.archiveDays = archiveDays
        self.hasEpg = hasEpg
        self.source = source
        self.m3u = m3u
    }

    enum CodingKeys: String, CodingKey {
        case id, name, categoryId, number, logo, archiveDays, hasEpg, source, m3u
    }

    /// Id-en hos leverandøren (adressen, programinfoen og arkivet).
    public var streamId: String { source ?? id }

    /// Samme kanal med et annet navn.
    public func renamed(_ name: String) -> Channel {
        Channel(id: id, name: name, categoryId: categoryId, number: number, logo: logo, archiveDays: archiveDays,
                hasEpg: hasEpg, source: source, m3u: m3u)
    }

    /// En kanal delt ut av denne ([key] er nøkkelen den spilles fra): egen id, programinfo og arkiv herfra, men ikke
    /// logoen (den er den første kanalens).
    public func split(_ name: String, key: String) -> Channel {
        Channel(id: "\(id)~\(key)", name: name, categoryId: categoryId, number: number, logo: nil,
                archiveDays: archiveDays, hasEpg: hasEpg, source: streamId, m3u: m3u)
    }

    /// (lister lagret før hasEpg fantes, leses med programinfo for alle)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        categoryId = try c.decode(String.self, forKey: .categoryId)
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        archiveDays = try c.decodeIfPresent(Int.self, forKey: .archiveDays) ?? 0
        hasEpg = try c.decodeIfPresent(Bool.self, forKey: .hasEpg) ?? true
        source = try c.decodeIfPresent(String.self, forKey: .source)
        m3u = try c.decodeIfPresent(M3UChannel.self, forKey: .m3u)
    }

    /// Programinfo hentes bare for kanaler som har det, og ikke for eventkanaler (kampen står i navnet, som i Fyrlys
    /// på Windows).
    public var wantsEpg: Bool { hasEpg && nameParts(name).sub.isEmpty }
}

/// Et program i TV-guiden.
public struct Program: Codable, Hashable, Sendable {
    public let title: String
    public let description: String
    public let start: Date
    public let stop: Date

    public init(title: String, description: String = "", start: Date, stop: Date) {
        self.title = title
        self.description = description
        self.start = start
        self.stop = stop
    }

    /// hvor langt programmet har kommet ved [now], fra 0 til 1
    public func progress(at now: Date) -> Double {
        let length = stop.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / length))
    }
}

/// Det leverandøren sier om abonnementet.
public struct Account: Hashable, Sendable {
    public let status: String
    public let expires: Date?
    public let maxConnections: Int
    public let activeConnections: Int

    public init(status: String = "", expires: Date? = nil, maxConnections: Int = 0, activeConnections: Int = 0) {
        self.status = status
        self.expires = expires
        self.maxConnections = maxConnections
        self.activeConnections = activeConnections
    }
}

/// Innloggingen hos leverandøren: Xtream Codes (server, brukernavn og passord), eller en M3U-liste (lenken til lista og
/// eventuelt til TV-guiden).
public struct Login: Codable, Hashable, Sendable {
    /// f.eks. «http://iptv.example:8080», uten / til slutt (en M3U-liste: serveren lista ligger på)
    public let server: String
    public let username: String
    public let password: String
    /// navnet du har gitt innloggingen («Hjemme», «Sport»); nil: «bruker på server»
    public var name: String?
    /// lenken til M3U-lista (nil: Xtream Codes)
    public let m3u: String?
    /// lenken til TV-guiden (XMLTV) du har oppgitt for M3U-lista (nil: den som står i lista)
    public let epg: String?
    /// klienten (User-Agent) serveren godtok da VLC ble avvist ved innloggingen; nil: VLC
    public var userAgent: String?

    /// Klienten for spørringene og strømmene hos leverandøren.
    public var agent: String { userAgent ?? xtreamUserAgent }

    public init(server: String, username: String, password: String, name: String? = nil) {
        self.server = Login.normalize(server)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name
        m3u = nil
        epg = nil
    }

    /// En M3U-liste: [link] til lista og eventuelt [epg] til TV-guiden.
    public init(m3u link: String, epg: String? = nil, name: String? = nil) {
        let c = URLComponents(string: link)
        var origin = "\(c?.scheme ?? "http")://\(c?.host ?? "")"
        if let port = c?.port { origin += ":\(port)" }
        server = Login.normalize(origin)
        username = ""
        password = ""
        self.name = name
        m3u = link
        self.epg = epg.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Innloggingen er en M3U-liste (ikke Xtream Codes).
    public var isM3U: Bool { m3u != nil }

    /// «iptv.example:8080/» → «http://iptv.example:8080»
    public static func normalize(_ server: String) -> String {
        // mellomrom hører aldri hjemme i en serveradresse («iptv.example.com :8080»)
        var s = String(server.filter { !$0.isWhitespace })
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        // en hel adresse til player_api.php eller get.php: bare serveren
        for tail in ["/player_api.php", "/get.php"] {
            if let range = s.range(of: tail, options: [.caseInsensitive]) {
                s = String(s[..<range.lowerBound])
            }
        }
        return s
    }

    /// Den samme kontoen får samme id (favorittene følger den), uten passordet. En M3U-liste: lenken uten passordet
    /// (som i Fyrlys for Windows).
    public var id: String {
        if let m3u { return stableHash("m3u|" + withoutPassword(m3u)) }
        return stableHash("\(server.lowercased())|\(username)")
    }

    /// Navnet du har gitt den, ellers «bruker på iptv.example» (eller «M3U-liste fra iptv.example»).
    public var label: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return defaultLabel
    }

    /// «bruker på iptv.example» (serveren uten port), «M3U-liste fra iptv.example»
    public var defaultLabel: String {
        let host = URL(string: server)?.host ?? server
        if isM3U { return L("M3U-liste fra {host}", ["host": host]) }
        return L("{user} på {host}", ["user": username, "host": host])
    }

    /// Med navnet [name] (tomt: tilbake til «bruker på server»), høyst 40 tegn.
    public func named(_ name: String) -> Login {
        var copy = self
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        copy.name = trimmed.isEmpty ? nil : trimmed
        return copy
    }
}

/// [link] uten password, pass og pwd i spørringen.
func withoutPassword(_ link: String) -> String {
    guard var c = URLComponents(string: link), let items = c.queryItems, !items.isEmpty else { return link }
    let kept = items.filter { !["password", "pass", "pwd"].contains($0.name.lowercased()) }
    guard kept.count != items.count else { return link }
    c.queryItems = kept.isEmpty ? nil : kept
    return c.string ?? link
}

/// En kort, stabil id (FNV-1a, 64 bit, i heksadesimal) som er lik fra gang til gang og på alle maskiner.
public func stableHash(_ text: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(hash, radix: 16)
}

/// Programmet som går nå og det neste, fra en liste sortert etter start.
public func nowAndNext(_ programs: [Program], at now: Date) -> (now: Program?, next: Program?) {
    var current: Program?
    for p in programs {
        if p.start <= now && now < p.stop {
            current = p
        } else if p.start > now {
            return (current, p)
        }
    }
    return (current, nil)
}

/// Programmene sortert etter start, uten doble (samme start og tittel) og uten overlapp: et program som begynner før
/// det forrige slutter, kutter det forrige.
public func cleanPrograms(_ programs: [Program]) -> [Program] {
    let sorted = programs.sorted { $0.start == $1.start ? $0.stop < $1.stop : $0.start < $1.start }
    var out: [Program] = []
    for p in sorted where p.stop > p.start {
        if let last = out.last {
            if last.start == p.start {
                // samme start: det lengste vinner, så ingen hull
                if p.stop > last.stop { out[out.count - 1] = p }
                continue
            }
            if last.stop > p.start {
                out[out.count - 1] = Program(title: last.title, description: last.description, start: last.start,
                                             stop: p.start)
            }
        }
        out.append(p)
    }
    return out
}
