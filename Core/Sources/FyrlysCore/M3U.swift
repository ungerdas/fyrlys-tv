import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Innlogging med en M3U-lenke (kanallista) og eventuelt en XMLTV-lenke (TV-guiden), som i Fyrlys for Windows
// (`lib/core/m3u_source.dart`): kanalene og gruppene fra lista, programmene fra guiden. Filmer, serier, TV-arkiv og
// abonnementet finnes bare hos Xtream; en Xtream-lenke (get.php med brukernavn og passord) logges inn som Xtream.
// Lista og guiden leses rett fra bytene (store lister og guider på titalls MB går fort, også på en Apple TV).

/// En kanal fra en M3U-liste: adressen den spilles fra, og tvg-id og tvg-name (det den heter i TV-guiden).
public struct M3UChannel: Codable, Hashable, Sendable {
    public let url: String
    public let tvgId: String
    public let tvgName: String

    public init(url: String, tvgId: String = "", tvgName: String = "") {
        self.url = url
        self.tvgId = tvgId
        self.tvgName = tvgName
    }
}

/// En kanal i en M3U-liste.
public struct M3UEntry: Hashable, Sendable {
    public let name: String
    public let url: String
    public let tvgId: String
    public let tvgName: String
    public let logo: String?
    public let group: String
    public let number: Int?
}

/// Det som står i en M3U-liste: kanalene (filmer og episoder hoppes over), lenkene til TV-guiden øverst (url-tvg …)
/// og hvor mange filmer og episoder som ble hoppet over.
public struct M3UList: Sendable {
    public var entries: [M3UEntry] = []
    public var guides: [String] = []
    public var skippedVOD = 0

    public init() {}
}

// ── bytene ──

/// Teksten eller fila som bytes, så lange lister og guider kan leses uten å lage en String av alt.
struct Bytes {
    let b: UnsafeBufferPointer<UInt8>
    var count: Int { b.count }
    subscript(i: Int) -> UInt8 { b[i] }

    /// Teksten i [range] (UTF-8, feil tegn byttes ut; eller Latin-1).
    func text(_ range: Range<Int>, latin1: Bool = false) -> String {
        guard !range.isEmpty else { return "" }
        let slice = UnsafeBufferPointer(rebasing: b[range])
        if latin1 { return String(bytes: slice, encoding: .isoLatin1) ?? "" }
        return String(decoding: slice, as: UTF8.self)
    }

    /// Den neste [byte] fra [from] til [to].
    func index(of byte: UInt8, from: Int, to: Int) -> Int? {
        var i = from
        while i < to {
            if b[i] == byte { return i }
            i += 1
        }
        return nil
    }

    /// Den neste [needle] fra [from] til [to].
    func index(of needle: [UInt8], from: Int, to: Int) -> Int? {
        guard let first = needle.first else { return from }
        let last = to - needle.count
        var i = from
        while i <= last, let at = index(of: first, from: i, to: last + 1) {
            if has(needle, at: at, to: to) { return at }
            i = at + 1
        }
        return nil
    }

    /// [prefix] står ved [i].
    func has(_ prefix: [UInt8], at i: Int, to: Int) -> Bool {
        guard i >= 0, i + prefix.count <= to else { return false }
        for k in 0..<prefix.count where b[i + k] != prefix[k] { return false }
        return true
    }

    /// name="value" i [range], med små bokstaver i navnene (det første vinner), som `([\w-]+)="([^"]*)"`; [xml]:
    /// også name='value'.
    func attributes(_ range: Range<Int>, xml: Bool = false, latin1: Bool = false) -> [String: String] {
        var out: [String: String] = [:]
        var i = range.lowerBound
        var keyStart = -1
        while i < range.upperBound {
            let c = b[i]
            if isKeyByte(c) {
                if keyStart < 0 { keyStart = i }
                i += 1
            } else if c == eq, keyStart >= 0, i + 1 < range.upperBound,
                      b[i + 1] == quote || (xml && b[i + 1] == apostrophe) {
                let q = b[i + 1]
                guard let end = index(of: q, from: i + 2, to: range.upperBound) else { break }
                let key = text(keyStart..<i).lowercased()
                if out[key] == nil {
                    out[key] = text(i + 2..<end, latin1: latin1).trimmingCharacters(in: .whitespaces)
                }
                keyStart = -1
                i = end + 1
            } else {
                keyStart = -1
                i += 1
            }
        }
        return out
    }
}

private let eq = UInt8(ascii: "="), quote = UInt8(ascii: "\""), apostrophe = UInt8(ascii: "'")
private let lt = UInt8(ascii: "<"), gt = UInt8(ascii: ">"), slash = UInt8(ascii: "/")

/// [\w-]: bokstav, tall, _ eller -
private func isKeyByte(_ c: UInt8) -> Bool {
    (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2D
}

private func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

private func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }

// ── M3U ──

/// En adresse til en film eller episode (ikke en direktekanal): /movie/, /series/ … i stien, eller en filtype som
/// .mp4 og .mkv til slutt.
func isVODURL(_ url: String) -> Bool {
    let u = url.lowercased()
    for part in ["/movie/", "/movies/", "/series/", "/vod/"] where u.contains(part) { return true }
    for ext in [".mp4", ".mkv", ".avi", ".mov", ".m4v", ".wmv"] where u.hasSuffix(ext) || u.contains(ext + "?") {
        return true
    }
    return false
}

private let extm3u = ascii("#EXTM3U"), extinf = ascii("#EXTINF"), extgrp = ascii("#EXTGRP:")

/// Leser en M3U-liste (også «extended» med tvg-id, tvg-name, tvg-logo, group-title, tvg-chno og #EXTGRP). #EXTM3U
/// øverst kreves ikke.
public func parseM3U(_ data: Data) -> M3UList {
    data.withUnsafeBytes { raw -> M3UList in
        let bytes = Bytes(b: raw.bindMemory(to: UInt8.self))
        var list = M3UList()
        var info: Range<Int>?
        var group: String?
        let n = bytes.count
        // BOM
        var start = n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0
        while start < n {
            var end = start
            while end < n, bytes[end] != 0x0A, bytes[end] != 0x0D { end += 1 }
            var a = start, z = end
            start = end + 1
            while a < z, isSpace(bytes[a]) { a += 1 }
            while z > a, isSpace(bytes[z - 1]) { z -= 1 }
            guard a < z else { continue }
            if bytes.has(extm3u, at: a, to: z) {
                let attributes = bytes.attributes(a..<z)
                for key in ["url-tvg", "x-tvg-url", "tvg-url"] {
                    for part in (attributes[key] ?? "").split(separator: ",") {
                        let url = part.trimmingCharacters(in: .whitespaces)
                        if url.hasPrefix("http"), !list.guides.contains(url) { list.guides.append(url) }
                    }
                }
            } else if bytes.has(extinf, at: a, to: z) {
                info = a..<z
                group = nil
            } else if bytes.has(extgrp, at: a, to: z) {
                group = bytes.text(a + extgrp.count..<z).trimmingCharacters(in: .whitespaces)
            } else if bytes[a] == UInt8(ascii: "#") {
                continue
            } else {
                guard let line = info else { continue }
                info = nil
                let url = bytes.text(a..<z)
                if isVODURL(url) {
                    list.skippedVOD += 1
                    continue
                }
                // navnet står etter det første kommaet utenfor anførselstegn
                var quoted = false
                var comma: Int?
                for k in line {
                    let c = bytes[k]
                    if c == quote { quoted.toggle() }
                    if c == UInt8(ascii: ","), !quoted {
                        comma = k
                        break
                    }
                }
                let attributes = bytes.attributes(line.lowerBound..<(comma ?? line.upperBound))
                var name = comma.map { bytes.text($0 + 1..<line.upperBound).trimmingCharacters(in: .whitespaces) } ?? ""
                if name.isEmpty { name = attributes["tvg-name"] ?? "" }
                guard !name.isEmpty else { continue }
                let logo = attributes["tvg-logo"] ?? ""
                let title = attributes["group-title"] ?? ""
                list.entries.append(M3UEntry(name: name, url: url, tvgId: attributes["tvg-id"] ?? "",
                                             tvgName: attributes["tvg-name"] ?? "",
                                             logo: logo.hasPrefix("http") ? logo : nil,
                                             group: title.isEmpty ? group ?? "" : title,
                                             number: attributes["tvg-chno"].flatMap { Int($0) }))
            }
        }
        return list
    }
}

public func parseM3U(_ text: String) -> M3UList { parseM3U(Data(text.utf8)) }

/// Ser det ut som en M3U-liste (#EXTM3U eller #EXTINF i begynnelsen)?
func looksLikeM3U(_ data: Data) -> Bool {
    let head = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
    return head.contains("#EXTM3U") || head.contains("#EXTINF")
}

/// Kategorien for kanaler uten gruppe (id-en er den samme på alle språk, bare navnet oversettes).
public let ungroupedCategory = "Uten kategori"

extension M3UList {
    /// Kategoriene (gruppene, i den rekkefølgen de kom) og kanalene med en id som er lik fra gang til gang (tvg-id og
    /// navnet, ellers gruppen og navnet; like får #2, #3 …), kanalnummeret (tvg-chno, ellers plassen i lista) og
    /// adressen. [hasGuide]: det finnes en TV-guide (programinfo for kanalene).
    public func lists(hasGuide: Bool) -> Lists {
        var categories: [ChannelCategory] = []
        var groups = Set<String>()
        var channels: [Channel] = []
        var seen = Set<String>()
        for (i, entry) in entries.enumerated() {
            let group = entry.group.isEmpty ? ungroupedCategory : entry.group
            if groups.insert(group).inserted {
                categories.append(ChannelCategory(id: group, name: entry.group.isEmpty ? L("Uten kategori") : group))
            }
            // samme id neste gang (favoritter og «sist sett»), selv om adressene i lista skulle endre seg
            let key = entry.tvgId.isEmpty ? "n:\(group)|\(entry.name)" : "id:\(entry.tvgId)|\(entry.name)"
            var id = stableHash(key)
            var number = 2
            while !seen.insert(id).inserted {
                id = stableHash("\(key)#\(number)")
                number += 1
            }
            channels.append(Channel(id: id, name: entry.name, categoryId: group, number: entry.number ?? (i + 1),
                                    logo: entry.logo, archiveDays: 0, hasEpg: hasGuide,
                                    m3u: M3UChannel(url: entry.url, tvgId: entry.tvgId, tvgName: entry.tvgName)))
        }
        return Lists(categories: categories, channels: channels, guides: guides)
    }
}

/// [text] som lenke: «http://» foran når det mangler. Feil når den er tom ([empty]) eller ikke har noen server.
public func normalizeLink(_ text: String, empty: String) throws -> String {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { throw SourceError(empty) }
    let link = t.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) == nil ? "http://" + t : t
    guard let host = URLComponents(string: link)?.host, !host.isEmpty else { throw SourceError(L("Ugyldig lenke")) }
    return link
}

/// Er [link] en Xtream-lenke (get.php eller player_api.php med brukernavn og passord i spørringen), er dette
/// innloggingen: den prøves som Xtream først (da kommer filmer, serier og TV-arkivet med).
public func xtreamLogin(fromM3U link: String) -> Login? {
    guard let c = URLComponents(string: link), let host = c.host, !host.isEmpty else { return nil }
    let path = c.path.lowercased()
    let file = ["get.php", "player_api.php"].first { path.hasSuffix("/" + $0) }
    guard let file else { return nil }
    func value(_ name: String) -> String? {
        c.queryItems?.first { $0.name.lowercased() == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
    guard let user = value("username"), let password = value("password") else { return nil }
    var server = "\(c.scheme ?? "http")://\(host)"
    if let port = c.port { server += ":\(port)" }
    // en sti foran get.php (http://iptv.example/tv/get.php) hører til serveren
    server += c.path.dropLast(file.count + 1)
    return Login(server: server, username: user, password: password)
}

/// Adressene en kanal fra en M3U-liste spilles fra: en Xtream-adresse til en .ts-strøm (/live/<bruker>/<passord>/
/// <id>.ts, eller uten /live/ og filtype) først som HLS (/live/…/<id>.m3u8, det Apple sin avspiller kan), så den
/// som står i lista.
public func m3uPlayURLs(_ link: String) -> [URL] {
    guard let original = URL(string: link) else { return [] }
    guard var c = URLComponents(string: link), c.query?.isEmpty ?? true else { return [original] }
    let parts = c.path.split(separator: "/").map(String.init)
    let live = parts.first == "live" ? Array(parts.dropFirst()) : parts
    guard live.count == 3 else { return [original] }
    let last = live[2]
    let ts = last.lowercased().hasSuffix(".ts")
    let id = ts ? String(last.dropLast(3)) : last
    guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return [original] }
    c.path = "/live/\(live[0])/\(live[1])/\(id).m3u8"
    guard let hls = c.url, hls != original else { return [original] }
    return [hls, original]
}

// ── TV-guiden (XMLTV) ──

/// Kanalene i lista (tvg-id og navnene), så bare programmene for dem tas med fra en stor guide.
public struct XMLTVWanted: Equatable, Sendable {
    public var ids = Set<String>()
    /// navnene og tvg-name med små bokstaver
    public var names = Set<String>()

    public init(channels: [Channel]) {
        for channel in channels {
            guard let m3u = channel.m3u else { continue }
            if !m3u.tvgId.isEmpty { ids.insert(m3u.tvgId) }
            names.insert(channel.name.lowercased())
            if !m3u.tvgName.isEmpty { names.insert(m3u.tvgName.lowercased()) }
        }
    }
}

/// Programmene i en XMLTV-guide per kanal-id, og visningsnavnene på kanalene (små bokstaver → id).
public struct XMLTVGuide: Sendable {
    public var programs: [String: [Program]] = [:]
    public var names: [String: String] = [:]

    public init() {}

    /// Programmene for en kanal fra lista: etter tvg-id, ellers navnet og så tvg-name mot visningsnavnene i guiden.
    public func programs(tvgId: String, name: String, tvgName: String) -> [Program] {
        if !tvgId.isEmpty, let found = programs[tvgId] { return found }
        let id = names[name.lowercased()] ?? (tvgName.isEmpty ? nil : names[tvgName.lowercased()])
        return id.flatMap { programs[$0] } ?? []
    }

    public func programs(for channel: Channel) -> [Program] {
        guard let m3u = channel.m3u else { return [] }
        return programs(tvgId: m3u.tvgId, name: channel.name, tvgName: m3u.tvgName)
    }

    public var isEmpty: Bool { programs.isEmpty && names.isEmpty }
}

/// «20261104193000 +0100» i sekunder siden 1970 (uten sone: UTC; uten sekunder: 0).
func xmltvSeconds(_ text: String) -> TimeInterval? {
    let u = Array(text.utf8)
    var i = 0
    while i < u.count, isSpace(u[i]) { i += 1 }
    func number(_ length: Int) -> Int? {
        guard i + length <= u.count else { return nil }
        var value = 0
        for k in i..<(i + length) {
            let d = Int(u[k]) - 48
            guard d >= 0, d <= 9 else { return nil }
            value = value * 10 + d
        }
        i += length
        return value
    }
    guard let year = number(4), let month = number(2), let day = number(2), let hour = number(2),
          let minute = number(2), (1...12).contains(month), (1...31).contains(day) else { return nil }
    let second = number(2) ?? 0
    while i < u.count, u[i] == 0x20 || u[i] == 0x09 { i += 1 }
    var offset = 0
    if i < u.count, u[i] == UInt8(ascii: "+") || u[i] == UInt8(ascii: "-") {
        let sign = u[i] == UInt8(ascii: "-") ? -1 : 1
        i += 1
        if let h = number(2), let m = number(2) { offset = sign * (h * 3600 + m * 60) }
    }
    let days = daysFromCivil(year, month, day)
    return TimeInterval(days * 86400 + hour * 3600 + minute * 60 + second - offset)
}

/// «20261104193000 +0100» som tidspunkt.
public func xmltvDate(_ text: String) -> Date? { xmltvSeconds(text).map { Date(timeIntervalSince1970: $0) } }

/// Dager fra 1970-01-01 til datoen (den gregorianske kalenderen; days_from_civil fra Howard Hinnant).
func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}

/// Tekst i XML: uten CDATA, og med &amp; &lt; &gt; &quot; &apos; og &#228; / &#xE4; som tegn.
func xmltvText(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("<![CDATA["), t.hasSuffix("]]>") {
        return String(t.dropFirst(9).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard t.contains("&") else { return t }
    var out = ""
    var rest = t[...]
    while let amp = rest.range(of: "&#") {
        out += rest[..<amp.lowerBound]
        let after = rest[amp.upperBound...]
        var index = after.startIndex
        let hex = index < after.endIndex && (after[index] == "x" || after[index] == "X")
        if hex { index = after.index(after: index) }
        let digits = index
        while index < after.endIndex, after[index].isHexDigit { index = after.index(after: index) }
        if index > digits, index < after.endIndex, after[index] == ";",
           let value = UInt32(after[digits..<index], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) {
            out.unicodeScalars.append(scalar)
            rest = after[after.index(after: index)...]
        } else {
            out += "&#"
            rest = after
        }
    }
    out += rest
    return out.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

private let programmeOpen = ascii("<programme"), programmeClose = ascii("</programme>")
private let channelOpen = ascii("<channel"), channelClose = ascii("</channel>")
private let displayOpen = ascii("<display-name"), displayClose = ascii("</display-name>")
private let titleOpen = ascii("<title"), titleClose = ascii("</title>")
private let descOpen = ascii("<desc"), descClose = ascii("</desc>")

extension Bytes {
    /// Teksten i det første <[open] …>…</…> i [range].
    fileprivate func element(_ open: [UInt8], _ close: [UInt8], in range: Range<Int>, latin1: Bool) -> String? {
        var from = range.lowerBound
        while let at = index(of: open, from: from, to: range.upperBound) {
            let next = at + open.count
            guard next < range.upperBound else { return nil }
            // <title> eller <title lang="no">, ikke <titles>
            if b[next] == gt || isSpace(b[next]) {
                guard let end = index(of: gt, from: next, to: range.upperBound) else { return nil }
                if b[end - 1] == slash { return "" }
                guard let stop = index(of: close, from: end + 1, to: range.upperBound) else { return nil }
                return xmltvText(text(end + 1..<stop, latin1: latin1))
            }
            from = next
        }
        return nil
    }

    /// Fila sier at den er Latin-1 (<?xml … encoding="ISO-8859-1"?>).
    fileprivate var declaresLatin1: Bool {
        let head = text(0..<min(count, 256)).lowercased()
        guard head.contains("<?xml") else { return false }
        return ["iso-8859-1", "iso8859-1", "latin1", "latin-1", "windows-1252"].contains {
            head.contains("\"\($0)\"") || head.contains("'\($0)'")
        }
    }
}

/// Leser en XMLTV-guide: kanalene med visningsnavnene, og programmene fra to timer før [now] til et døgn etter,
/// sortert. Med [wanted] bare programmene for de kanalene (kanalene står først i en XMLTV-fil, så navnene er kjent).
public func parseXMLTV(_ data: Data, now: Date = Date(), wanted: XMLTVWanted? = nil) -> XMLTVGuide {
    let earliest = now.timeIntervalSince1970 - 2 * 3600, latest = now.timeIntervalSince1970 + 24 * 3600
    return data.withUnsafeBytes { raw -> XMLTVGuide in
        let bytes = Bytes(b: raw.bindMemory(to: UInt8.self))
        let latin1 = bytes.declaresLatin1
        var guide = XMLTVGuide()
        var wantedIds = wanted?.ids ?? []
        let n = bytes.count
        var i = 0
        while let at = bytes.index(of: lt, from: i, to: n) {
            if bytes.has(programmeOpen, at: at, to: n), at + programmeOpen.count < n,
               isSpace(bytes[at + programmeOpen.count]) {
                guard let end = bytes.index(of: gt, from: at, to: n) else { break }
                guard bytes[end - 1] != slash else {
                    i = end + 1
                    continue
                }
                guard let close = bytes.index(of: programmeClose, from: end + 1, to: n) else { break }
                i = close + programmeClose.count
                let attributes = bytes.attributes(at + programmeOpen.count..<end, xml: true, latin1: latin1)
                guard let channel = attributes["channel"].map(xmltvText), !channel.isEmpty,
                      wanted == nil || wantedIds.contains(channel),
                      let start = attributes["start"].flatMap(xmltvSeconds),
                      let stop = attributes["stop"].flatMap(xmltvSeconds),
                      stop > earliest, start <= latest, stop > start else { continue }
                let title = bytes.element(titleOpen, titleClose, in: end + 1..<close, latin1: latin1) ?? ""
                guard !title.isEmpty else { continue }
                let description = bytes.element(descOpen, descClose, in: end + 1..<close, latin1: latin1) ?? ""
                guide.programs[channel, default: []].append(
                    Program(title: title, description: description, start: Date(timeIntervalSince1970: start),
                            stop: Date(timeIntervalSince1970: stop)))
            } else if bytes.has(channelOpen, at: at, to: n), at + channelOpen.count < n,
                      isSpace(bytes[at + channelOpen.count]) {
                guard let end = bytes.index(of: gt, from: at, to: n) else { break }
                guard bytes[end - 1] != slash,
                      let close = bytes.index(of: channelClose, from: end + 1, to: n) else {
                    i = end + 1
                    continue
                }
                i = close + channelClose.count
                guard let id = bytes.attributes(at + channelOpen.count..<end, xml: true, latin1: latin1)["id"]
                    .map(xmltvText), !id.isEmpty else { continue }
                var cursor = end + 1
                while cursor < close, let name = bytes.index(of: displayOpen, from: cursor, to: close) {
                    guard let nameEnd = bytes.index(of: gt, from: name, to: close),
                          let nameClose = bytes.index(of: displayClose, from: nameEnd + 1, to: close) else { break }
                    cursor = nameClose + displayClose.count
                    let key = xmltvText(bytes.text(nameEnd + 1..<nameClose, latin1: latin1)).lowercased()
                    guard !key.isEmpty else { continue }
                    if guide.names[key] == nil { guide.names[key] = id }
                    if let wanted, wanted.names.contains(key) { wantedIds.insert(id) }
                }
            } else {
                i = at + 1
            }
        }
        for (id, list) in guide.programs { guide.programs[id] = cleanPrograms(list) }
        return guide
    }
}

public func parseXMLTV(_ text: String, now: Date = Date(), wanted: XMLTVWanted? = nil) -> XMLTVGuide {
    parseXMLTV(Data(text.utf8), now: now, wanted: wanted)
}

// ── gzip ──

/// Det som ble lastet ned, er gzip (1F 8B): TV-guider er ofte .xml.gz.
func isGzip(_ data: Data) -> Bool {
    data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
}

/// DEFLATE-dataene i en gzip-fil: uten hodet (med navn, kommentar og det andre som kan stå der) og uten de åtte
/// bytene til slutt (sjekksummen og lengden).
func gzipDeflate(_ data: Data) -> Data? {
    let b = [UInt8](data)
    guard b.count >= 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { return nil }
    let flags = b[3]
    var i = 10
    if flags & 0x04 != 0 {
        guard i + 2 <= b.count else { return nil }
        i += 2 + (Int(b[i]) | (Int(b[i + 1]) << 8))
    }
    for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
        while i < b.count, b[i] != 0 { i += 1 }
        i += 1
    }
    if flags & 0x02 != 0 { i += 2 }
    guard i < b.count - 8 else { return nil }
    return Data(b[i..<(b.count - 8)])
}

/// [data] pakket ut når det er gzip (ellers som det er); nil når det ikke lar seg pakke ut.
public func unpackGzip(_ data: Data) -> Data? {
    guard isGzip(data) else { return data }
    #if canImport(Darwin)
    guard let deflate = gzipDeflate(data) else { return nil }
    // .zlib er DEFLATE uten hode hos Apple
    return try? (deflate as NSData).decompressed(using: .zlib) as Data
    #else
    return nil
    #endif
}

// ── kilden ──

/// En M3U-liste som kilde: kanalene og kategoriene fra lista, og programinfoen fra TV-guiden (XMLTV): lenken du har
/// oppgitt, ellers de som står i lista, den første som virker. Guiden hentes første gang det trengs programinfo og
/// så hver sjette time; feiler den, prøves den igjen etter fem minutter (ellers ville hvert kort prøvd på nytt).
public actor M3USource {
    public nonisolated let login: Login
    private let fetch: Fetch
    private let clock: @Sendable () -> Date
    private var listGuides: [String] = []
    private var wanted: XMLTVWanted?
    private var guide: XMLTVGuide?
    private var guideAt: Date?
    private var failedAt: Date?
    private var loading: Task<XMLTVGuide?, Never>?

    public static let guideAge: TimeInterval = 6 * 3600
    public static let retryAfter: TimeInterval = 300

    public init(login: Login, fetch: @escaping Fetch = urlSessionFetch,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.login = login
        self.fetch = fetch
        self.clock = clock
    }

    /// Henter og leser lista. Feil når den ikke kan hentes, ikke er en M3U-liste eller ikke har kanaler.
    public func lists() async throws -> Lists {
        guard let link = login.m3u, let url = URL(string: link) else { throw SourceError(L("Ugyldig lenke")) }
        let data = try await download(url, guide: false)
        let list = parseM3U(data)
        guard !list.entries.isEmpty else {
            if list.skippedVOD > 0 { throw SourceError(L("Lista har bare filmer og serier, ingen TV-kanaler")) }
            if !looksLikeM3U(data) { throw SourceError(L("Lenken ga ikke en M3U-liste")) }
            throw SourceError(L("Fant ingen kanaler i lista"))
        }
        let lists = list.lists(hasGuide: login.epg != nil || !list.guides.isEmpty)
        remember(lists)
        return lists
    }

    /// Lista som vises (fra sist, eller nettopp hentet): lenkene til TV-guiden i den, og kanalene den skal ha
    /// programmene for (er det nye kanaler, leses guiden på nytt neste gang).
    public func remember(_ lists: Lists) {
        if let guides = lists.guides { listGuides = guides }
        let next = XMLTVWanted(channels: lists.channels)
        guard next != wanted else { return }
        if wanted != nil, guide != nil { guideAt = nil }
        wanted = next
    }

    /// Lenkene til TV-guiden: din, ellers de som står i lista.
    var guideURLs: [URL] {
        (login.epg.map { [$0] } ?? listGuides).compactMap { URL(string: $0) }
    }

    /// Programmene som ikke er slutt, for en kanal fra lista (tomt uten TV-guide).
    public func programs(for channel: Channel) async -> [Program] {
        await programs(for: channel, limit: 24)
    }

    public func programs(for channel: Channel, limit: Int) async -> [Program] {
        guard channel.m3u != nil, let guide = await currentGuide() else { return [] }
        let now = clock()
        return Array(guide.programs(for: channel).lazy.filter { $0.stop > now }.prefix(limit))
    }

    private func currentGuide() async -> XMLTVGuide? {
        let now = clock()
        if let guide, let at = guideAt, now.timeIntervalSince(at) < Self.guideAge { return guide }
        if let failedAt, now.timeIntervalSince(failedAt) < Self.retryAfter { return guide }
        if let loading { return await loading.value }
        let task = Task { await self.fetchGuide() }
        loading = task
        let result = await task.value
        loading = nil
        return result
    }

    private func fetchGuide() async -> XMLTVGuide? {
        for url in guideURLs {
            guard let data = try? await download(url, guide: true) else { continue }
            let found = parseXMLTV(data, now: clock(), wanted: wanted)
            guard !found.isEmpty else { continue }
            guide = found
            guideAt = clock()
            failedAt = nil
            return found
        }
        // ingen virket: det vi hadde (eller ingenting), og et nytt forsøk om litt
        failedAt = clock()
        return guide
    }

    /// M3U-lista eller TV-guiden ([guide]; det står i feilmeldingene), pakket ut når den er gzip.
    private func download(_ url: URL, guide: Bool) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await fetch(url)
        } catch {
            // hvorfor (serveren finnes ikke, porten er stengt …)
            let reason = connectionProblem(error).message
            throw SourceError(guide ? L("Får ikke hentet TV-guiden: {reason}", ["reason": reason])
                : L("Får ikke hentet M3U-lista: {reason}", ["reason": reason]), failure: .unreachable)
        }
        if status == 401 || status == 403 {
            throw SourceError(guide ? L("Serveren avviste TV-guiden (HTTP {code})", ["code": status])
                : L("Serveren avviste M3U-lista (HTTP {code})", ["code": status]))
        }
        if status >= 400 {
            throw SourceError(guide ? L("Serveren svarte HTTP {code} for TV-guiden", ["code": status])
                : L("Serveren svarte HTTP {code} for M3U-lista", ["code": status]))
        }
        guard let unpacked = unpackGzip(data) else {
            throw SourceError(guide ? L("Får ikke pakket ut TV-guiden") : L("Får ikke pakket ut M3U-lista"))
        }
        return unpacked
    }
}
