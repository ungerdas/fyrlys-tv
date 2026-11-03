import Foundation

/// TV-arkivet (timeshift hos Xtream), som i Fyrlys for Windows: programmene de siste dagene fra
/// get_simple_data_table, og adressen til et program fra et gitt sted, med starten i serverens klokke.

/// Et program i arkivet. [available]: leverandøren har det (has_archive); det som går nå, kan alltid ses fra start.
public struct ArchiveItem: Hashable, Identifiable, Sendable {
    public let program: Program
    public let available: Bool
    public var id: Date { program.start }
}

/// Hvor langt serverens klokke er foran UTC (sekunder): time_now (serverens tid) mot timestamp_now i server_info,
/// rundet til nærmeste kvarter. nil når serveren ikke sier det.
public func serverClockOffset(_ serverInfo: Any?) -> TimeInterval? {
    guard let info = serverInfo as? [String: Any], let stamp = int(info["timestamp_now"]) else { return nil }
    let wallText = text(info["time_now"])
    guard let m = wallText.range(of: #"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?"#, options: .regularExpression)
    else { return nil }
    let digits = wallText[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    guard digits.count >= 5 else { return nil }
    var c = DateComponents()
    c.year = digits[0]
    c.month = digits[1]
    c.day = digits[2]
    c.hour = digits[3]
    c.minute = digits[4]
    c.second = digits.count > 5 ? digits[5] : 0
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    guard let wall = utc.date(from: c) else { return nil }
    let diff = wall.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(stamp)))
    let quarters = (diff / 900).rounded()
    guard abs(quarters) <= 14 * 4 else { return nil }
    return quarters * 900
}

/// Serverens klokke da [t] var. Går den likt med enheten nå (eller sier ikke serveren noe), brukes enhetens tidssone
/// med sommertid og vintertid; ellers serverens forskjell slik den er nå.
public func archiveOffset(_ t: Date, server: TimeInterval?, zone: TimeZone = .current, now: Date = Date())
    -> TimeInterval {
    let local = TimeInterval(zone.secondsFromGMT(for: t))
    guard let server, server != TimeInterval(zone.secondsFromGMT(for: now)) else { return local }
    return server
}

/// «2026-10-26:20-00»: starten i arkivet slik Xtream vil ha den, i serverens tid.
public func xtreamTime(_ t: Date, offset: TimeInterval) -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let c = utc.dateComponents([.year, .month, .day, .hour, .minute], from: t.addingTimeInterval(offset))
    return String(format: "%04d-%02d-%02d:%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
}

/// Programmene fra get_simple_data_table som har begynt de siste [days] dagene, eldst først.
public func parseArchive(_ json: Any, now: Date, days: Int) -> [ArchiveItem] {
    guard let list = (json as? [String: Any])?["epg_listings"] as? [[String: Any]] else { return [] }
    let from = now.addingTimeInterval(-TimeInterval(days) * 86400)
    var seen = Set<Date>()
    let items: [ArchiveItem] = list.compactMap { e in
        guard let a = int(e["start_timestamp"]), let b = int(e["stop_timestamp"] ?? e["end_timestamp"]), b > a
        else { return nil }
        let start = Date(timeIntervalSince1970: TimeInterval(a))
        let stop = Date(timeIntervalSince1970: TimeInterval(b))
        guard start <= now, start >= from, seen.insert(start).inserted else { return nil }
        let flag = e["has_archive"]
        let saved = flag == nil || flag is NSNull || int(flag) == 1 || (flag as? Bool) == true
        return ArchiveItem(program: Program(title: base64Text(text(e["title"])),
                                            description: base64Text(text(e["description"])),
                                            start: start, stop: stop),
                           available: saved || stop > now)
    }
    return items.sorted { $0.program.start < $1.program.start }
}

extension XtreamClient {
    /// Programmene i arkivet for en kanal (tom når kanalen ikke har arkiv).
    public func archive(_ channel: Channel, now: Date = Date()) async throws -> [ArchiveItem] {
        guard channel.archiveDays > 0 else { return [] }
        return parseArchive(try await api("get_simple_data_table", ["stream_id": channel.streamId]), now: now,
                            days: channel.archiveDays)
    }

    /// Hvor langt serverens klokke er foran UTC (spørres én gang per innlogging): nil når serveren ikke sier det;
    /// feil når den ikke svarte (da spørres det igjen neste gang, i stedet for å gjette tidssonen resten av økta).
    public func serverClock() async throws -> TimeInterval? {
        let json = try await api() as? [String: Any]
        return serverClockOffset(json?["server_info"])
    }

    /// Adressene til [program] i arkivet fra [from] sekunder inn (på minuttet: arkivet ligger i biter på ett minutt),
    /// ut programmet: HLS først, MPEG-TS som reserve.
    public func archiveURLs(_ channel: Channel, _ program: Program, from: TimeInterval = 0, serverClock: TimeInterval?,
                            zone: TimeZone = .current, now: Date = Date()) -> [URL] {
        let raw = program.start.addingTimeInterval(max(0, from)).timeIntervalSince1970
        let at = Date(timeIntervalSince1970: raw - raw.truncatingRemainder(dividingBy: 60))
        let minutes = max(1, Int((program.stop.timeIntervalSince(at) / 60).rounded(.up)))
        let start = xtreamTime(at, offset: archiveOffset(at, server: serverClock, zone: zone, now: now))
        let base = "\(login.server)/timeshift/\(credsPath)/\(minutes)/\(start)/\(channel.streamId)"
        return ["\(base).m3u8", "\(base).ts"].compactMap { URL(string: $0) }
    }
}
