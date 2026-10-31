import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Leverandørene vil ofte bare snakke med kjente spillere.
public let xtreamUserAgent = "VLC/3.0.21 LibVLC/3.0.21"

/// En feil som kan vises for brukeren.
public struct SourceError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Henter en adresse: innholdet og HTTP-koden. Byttes ut i testene.
public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

/// Henter med URLSession og User-Agent som VLC.
public let urlSessionFetch: Fetch = { url in
    var request = URLRequest(url: url, timeoutInterval: 60)
    request.setValue(xtreamUserAgent, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// Xtream Codes: player_api.php for listene og programinfo, /live/<bruker>/<passord>/<id>.m3u8 for kanalene.
public struct XtreamClient: Sendable {
    public let login: Login
    let fetch: Fetch

    public init(login: Login, fetch: @escaping Fetch = urlSessionFetch) {
        self.login = login
        self.fetch = fetch
    }

    // ── adresser ──

    public func apiURL(action: String? = nil, _ params: [String: String] = [:]) -> URL {
        var c = URLComponents(string: login.server + "/player_api.php")!
        var items = [URLQueryItem(name: "username", value: login.username),
                     URLQueryItem(name: "password", value: login.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for key in params.keys.sorted() { items.append(URLQueryItem(name: key, value: params[key])) }
        c.queryItems = items
        return c.url!
    }

    /// brukernavn og passord som deler av en sti
    var credsPath: String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        let user = login.username.addingPercentEncoding(withAllowedCharacters: allowed) ?? login.username
        let pass = login.password.addingPercentEncoding(withAllowedCharacters: allowed) ?? login.password
        return "\(user)/\(pass)"
    }

    /// Kanalen som HLS (det Apple TV spiller).
    public func liveURL(_ channel: Channel) -> URL {
        URL(string: "\(login.server)/live/\(credsPath)/\(channel.id).m3u8")!
    }

    /// Tekst som kan vises eller logges: uten brukernavn og passord.
    public func redact(_ text: String) -> String {
        var out = text
        for secret in [login.password, login.username] where secret.count >= 3 {
            for variant in Set([secret, secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? secret]) {
                out = out.replacingOccurrences(of: variant, with: "***")
            }
        }
        return out
    }

    // ── spørringer ──

    func api(_ action: String? = nil, _ params: [String: String] = [:]) async throws -> Any {
        let data: Data
        let status: Int
        do {
            (data, status) = try await fetch(apiURL(action: action, params))
        } catch {
            throw SourceError(L("Får ikke kontakt med IPTV-serveren"))
        }
        if status == 401 || status == 403 { throw SourceError(L("Serveren avviste innloggingen")) }
        if status >= 400 { throw SourceError(L("IPTV-serveren svarte HTTP {code}", ["code": status])) }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw SourceError(L("Serveren svarte ikke som en Xtream-server"))
        }
        return json
    }

    /// Sjekker innloggingen og gir abonnementet.
    public func account() async throws -> Account {
        let json = try await api()
        guard let info = (json as? [String: Any])?["user_info"] as? [String: Any] else {
            throw SourceError(L("Serveren svarte ikke som en Xtream-server"))
        }
        if let auth = info["auth"], int(auth) == 0 { throw SourceError(L("Serveren avviste innloggingen")) }
        return parseAccount(info)
    }

    public func categories() async throws -> [ChannelCategory] {
        parseCategories(try await api("get_live_categories"))
    }

    public func channels() async throws -> [Channel] {
        parseChannels(try await api("get_live_streams"))
    }

    /// Programmene som går nå og senere for en kanal.
    public func epg(_ channel: Channel, limit: Int = 8) async throws -> [Program] {
        cleanPrograms(parseShortEPG(try await api("get_short_epg", ["stream_id": channel.id, "limit": String(limit)])))
    }
}

// ── tolking (Xtream er ikke nøye på typer: tall kommer som tekst, tekst som tall, og null) ──

func int(_ value: Any?) -> Int? {
    switch value {
    case let i as Int: return i
    case let d as Double: return Int(d)
    case let s as String: return Int(s.trimmingCharacters(in: .whitespaces)) ?? Double(s).map { Int($0) }
    case let n as NSNumber: return n.intValue
    default: return nil
    }
}

func text(_ value: Any?) -> String {
    switch value {
    case let s as String: return s
    case let i as Int: return String(i)
    case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

public func parseAccount(_ info: [String: Any]) -> Account {
    let expires = int(info["exp_date"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
    return Account(status: text(info["status"]), expires: expires,
                   maxConnections: int(info["max_connections"]) ?? 0,
                   activeConnections: int(info["active_cons"]) ?? 0)
}

public func parseCategories(_ json: Any) -> [ChannelCategory] {
    guard let list = json as? [[String: Any]] else { return [] }
    var seen = Set<String>()
    return list.compactMap { c in
        let id = text(c["category_id"])
        let name = text(c["category_name"]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
        return ChannelCategory(id: id, name: name)
    }
}

public func parseChannels(_ json: Any) -> [Channel] {
    guard let list = json as? [[String: Any]] else { return [] }
    var seen = Set<String>()
    return list.compactMap { c in
        let id = text(c["stream_id"])
        let name = text(c["name"]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
        let logo = text(c["stream_icon"]).trimmingCharacters(in: .whitespaces)
        let archive = int(c["tv_archive"]) == 1 ? max(1, int(c["tv_archive_duration"]) ?? 1) : 0
        let epgId = text(c["epg_channel_id"]).trimmingCharacters(in: .whitespaces)
        return Channel(id: id, name: name, categoryId: text(c["category_id"]), number: int(c["num"]),
                       logo: logo.isEmpty ? nil : logo, archiveDays: archive, hasEpg: !epgId.isEmpty)
    }
}

/// get_short_epg: titlene og beskrivelsene er base64.
public func parseShortEPG(_ json: Any) -> [Program] {
    guard let list = (json as? [String: Any])?["epg_listings"] as? [[String: Any]] else { return [] }
    return list.compactMap { e in
        guard let start = int(e["start_timestamp"]), let stop = int(e["stop_timestamp"] ?? e["end_timestamp"]),
              stop > start else { return nil }
        return Program(title: base64Text(text(e["title"])), description: base64Text(text(e["description"])),
                       start: Date(timeIntervalSince1970: TimeInterval(start)),
                       stop: Date(timeIntervalSince1970: TimeInterval(stop)))
    }
}

/// Base64 til tekst; er det ikke base64, er det teksten selv.
func base64Text(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    var padded = trimmed
    while padded.count % 4 != 0 { padded += "=" }
    if let data = Data(base64Encoded: padded), let decoded = String(data: data, encoding: .utf8) {
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
}
