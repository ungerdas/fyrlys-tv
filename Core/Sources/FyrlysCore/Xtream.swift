import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Leverandørene vil ofte bare snakke med kjente spillere.
public let xtreamUserAgent = "VLC/3.0.21 LibVLC/3.0.21"

/// En feil som kan vises for brukeren, og hva slags feil det var (se `SourceFailure`).
public struct SourceError: Error, LocalizedError, Equatable {
    public let message: String
    public let failure: SourceFailure
    public init(_ message: String, failure: SourceFailure = .other) {
        self.message = message
        self.failure = failure
    }
    public var errorDescription: String? { message }
}

/// Henter en adresse: innholdet og HTTP-koden. Byttes ut i testene.
public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

/// Henter med URLSession og [userAgent] (VLC, med mindre innloggingen fant en annen klient serveren godtar).
public func makeURLSessionFetch(userAgent: String) -> Fetch {
    { url in
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Henter med URLSession og User-Agent som VLC.
public let urlSessionFetch: Fetch = makeURLSessionFetch(userAgent: xtreamUserAgent)

/// Xtream Codes: player_api.php for listene og programinfo, /live/<bruker>/<passord>/<id>.m3u8 for kanalene.
public struct XtreamClient: Sendable {
    public let login: Login
    let fetch: Fetch

    /// Uten [fetch]: URLSession med klienten innloggingen bruker (`Login.agent`).
    public init(login: Login, fetch: Fetch? = nil) {
        self.login = login
        self.fetch = fetch ?? makeURLSessionFetch(userAgent: login.agent)
    }

    /// Sjekker innloggingen hos leverandøren: som VLC først, og avviser serveren det (avvist, tomt, en nettside, en
    /// forbindelse som lukkes), som de andre klientene i `loginUserAgents` etter tur. Gir innloggingen med klienten som
    /// virket (`userAgent`, nil for VLC) og abonnementet. [fetchFor] lager hentingen for en klient (testene).
    public static func signIn(_ login: Login,
                              fetchFor: (String) -> Fetch = { makeURLSessionFetch(userAgent: $0) })
        async throws -> (login: Login, account: Account) {
        var first: SourceError?
        for (index, agent) in loginUserAgents.enumerated() {
            var attempt = login
            attempt.userAgent = index == 0 ? nil : agent
            let client = XtreamClient(login: attempt, fetch: fetchFor(agent))
            do {
                let account = try await client.account()
                if index > 0 {
                    AppLog.shared.add("Innloggingen virket som klient \(index + 1) av \(loginUserAgents.count)")
                }
                return (attempt, account)
            } catch let error as SourceError {
                guard error.failure == .rejected || error.failure == .notXtream else { throw error }
                AppLog.shared.add("Innloggingen som klient \(index + 1) av \(loginUserAgents.count): \(error.failure.rawValue)")
                first = first ?? error
            }
        }
        throw first ?? SourceError(L("Får ikke kontakt med IPTV-serveren"), failure: .unreachable)
    }

    // ── adresser ──

    /// Adressen til player_api.php. Feil når serveradressen ikke er gyldig («iptv.example:8O8O» med bokstaven O).
    public func apiURL(action: String? = nil, _ params: [String: String] = [:]) throws -> URL {
        guard var c = URLComponents(string: login.server + "/player_api.php"), c.host?.isEmpty == false else {
            throw SourceError(L("Serveradressen er ikke gyldig: {server}", ["server": login.server]))
        }
        var items = [URLQueryItem(name: "username", value: login.username),
                     URLQueryItem(name: "password", value: login.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for key in params.keys.sorted() { items.append(URLQueryItem(name: key, value: params[key])) }
        c.queryItems = items
        // «+» står igjen i spørringen, og PHP leser det som mellomrom («a+b» som passord ble avvist)
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = c.url else {
            throw SourceError(L("Serveradressen er ikke gyldig: {server}", ["server": login.server]))
        }
        return url
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
        URL(string: "\(login.server)/live/\(credsPath)/\(channel.streamId).m3u8")!
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
        let url = try apiURL(action: action, params)
        let data: Data
        let status: Int
        do {
            (data, status) = try await fetch(url)
        } catch {
            throw connectionProblem(error)
        }
        if let problem = xtreamResponseProblem(status, data) { throw problem }
        guard let json = decodeJSONLenient(data) else { throw xtreamNotJSON(data) }
        // avvist (feil passord, utløpt): noen svarer med kontoen og auth 0 i stedet for lista som ble spurt etter
        if let info = (json as? [String: Any])?["user_info"] as? [String: Any], !xtreamAuthorized(info) {
            throw Self.wrongLogin
        }
        return json
    }

    static let wrongLogin = SourceError(L("Feil brukernavn eller passord, eller abonnementet er ikke aktivert ennå. Sjekk store og små bokstaver."),
                                        failure: .wrongLogin)

    /// Sjekker innloggingen og gir abonnementet.
    public func account() async throws -> Account {
        let json = try await api()
        guard let info = (json as? [String: Any])?["user_info"] as? [String: Any] else {
            // et tomt objekt eller en liste: ikke svaret på en innlogging
            throw SourceError(L("Serveren svarte ikke som en Xtream-server"), failure: .notXtream)
        }
        guard xtreamAuthorized(info) else { throw Self.wrongLogin }
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
        cleanPrograms(parseShortEPG(try await api("get_short_epg", ["stream_id": channel.streamId, "limit": String(limit)])))
    }
}

// ── tolking (Xtream er ikke nøye på typer: tall kommer som tekst, tekst som tall, og null) ──

func int(_ value: Any?) -> Int? {
    switch value {
    case let i as Int: return i
    case let d as Double: return wholeNumber(d)
    case let s as String:
        let t = s.trimmingCharacters(in: .whitespaces)
        return Int(t) ?? Double(t).flatMap(wholeNumber)
    case let n as NSNumber: return n.intValue
    default: return nil
    }
}

/// Et desimaltall som heltall; nil for «nan», «inf» og tall for store for Int (`Int(d)` krasjer på dem).
func wholeNumber(_ d: Double) -> Int? {
    guard d.isFinite, abs(d) < 9e18 else { return nil }
    return Int(d)
}

func text(_ value: Any?) -> String {
    switch value {
    case let s as String: return s
    case let i as Int: return String(i)
    case let d as Double:
        if let whole = wholeNumber(d), Double(whole) == d { return String(whole) }
        return d.isFinite ? String(d) : ""
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

/// Lista i et svar: en liste med objekter, eller (hos noen leverandører) et objekt med objektene som verdier, i
/// rekkefølgen til nøklene («0», «1», …).
func objectList(_ json: Any) -> [[String: Any]] {
    if let list = json as? [[String: Any]] { return list }
    if let list = json as? [Any] { return list.compactMap { $0 as? [String: Any] } }
    guard let dict = json as? [String: Any], dict["user_info"] == nil else { return [] }
    return dict.sorted { a, b in
        switch (Int(a.key), Int(b.key)) {
        case let (x?, y?): return x < y
        default: return a.key < b.key
        }
    }.compactMap { $0.value as? [String: Any] }
}

public func parseAccount(_ info: [String: Any]) -> Account {
    let expires = int(info["exp_date"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
    return Account(status: text(info["status"]), expires: expires,
                   maxConnections: int(info["max_connections"]) ?? 0,
                   activeConnections: int(info["active_cons"]) ?? 0)
}

public func parseCategories(_ json: Any) -> [ChannelCategory] {
    let list = objectList(json)
    var seen = Set<String>()
    return list.compactMap { c in
        let id = text(c["category_id"])
        let name = text(c["category_name"]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
        return ChannelCategory(id: id, name: name)
    }
}

public func parseChannels(_ json: Any) -> [Channel] {
    let list = objectList(json)
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

/// Base64 til tekst; er det ikke base64, er det teksten selv. Klartekst som tilfeldigvis er gyldig base64 («Film»,
/// «TBA»), gir styretegn når den dekodes, og blir da stående som den er.
func base64Text(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    var padded = trimmed
    while padded.count % 4 != 0 { padded += "=" }
    if let data = Data(base64Encoded: padded), let decoded = String(data: data, encoding: .utf8),
       !decoded.unicodeScalars.contains(where: { scalar in
           scalar == "\u{FFFD}" || (scalar.properties.generalCategory == .control && !"\t\n\r".unicodeScalars.contains(scalar))
       }) {
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
}
