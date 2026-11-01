import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Plex: innloggingen med en kode på plex.tv/link, serverne på kontoen, bibliotekene med filmer og serier, filene, og
/// hvor langt du har sett (tilbake til Plex, så det stemmer i de andre Plex-appene).

/// Henter en forespørsel: innholdet og HTTP-koden. Byttes ut i testene.
public typealias RequestFetch = @Sendable (URLRequest) async throws -> (Data, Int)

public let urlSessionRequestFetch: RequestFetch = { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// Det Plex vil vite om appen (X-Plex-…): navnet, versjonen og en fast id for denne installasjonen.
public struct PlexDevice: Hashable, Sendable {
    public let clientId: String
    public let platform: String
    public let deviceName: String
    public let version: String

    public init(clientId: String, platform: String, deviceName: String, version: String) {
        self.clientId = clientId
        self.platform = platform
        self.deviceName = deviceName
        self.version = version
    }

    public var headers: [String: String] {
        ["X-Plex-Product": "Fyrlys", "X-Plex-Version": version, "X-Plex-Client-Identifier": clientId,
         "X-Plex-Platform": platform, "X-Plex-Device": platform, "X-Plex-Device-Name": deviceName,
         "Accept": "application/json"]
    }
}

/// Koden som skrives inn på plex.tv/link.
public struct PlexPin: Hashable, Sendable {
    public let id: Int
    public let code: String
}

public struct PlexConnection: Codable, Hashable, Sendable {
    public let uri: String
    public let local: Bool
    public let relay: Bool

    public init(uri: String, local: Bool, relay: Bool) {
        self.uri = uri
        self.local = local
        self.relay = relay
    }
}

/// En Plex-server på kontoen.
public struct PlexServer: Codable, Hashable, Identifiable, Sendable {
    /// clientIdentifier
    public let id: String
    public let name: String
    public let accessToken: String
    public let owned: Bool
    public let connections: [PlexConnection]

    public init(id: String, name: String, accessToken: String, owned: Bool, connections: [PlexConnection]) {
        self.id = id
        self.name = name
        self.accessToken = accessToken
        self.owned = owned
        self.connections = connections
    }

    /// I den rekkefølgen de prøves: på hjemmenettet, så utenfra, så gjennom Plex sin relé (treg).
    public var ordered: [PlexConnection] {
        connections.filter { $0.local && !$0.relay } + connections.filter { !$0.local && !$0.relay }
            + connections.filter(\.relay)
    }
}

/// Feil fra Plex som kan vises.
func plexError(_ status: Int) -> SourceError {
    if status == 401 || status == 403 { return SourceError(L("Plex avviste innloggingen. Koble til Plex på nytt.")) }
    return SourceError(L("Plex svarte HTTP {code}", ["code": status]))
}

/// plex.tv: koden til plex.tv/link, kontoen og serverne.
public struct PlexAccountClient: Sendable {
    public let base: String
    let device: PlexDevice
    let fetch: RequestFetch

    public init(device: PlexDevice, base: String = "https://plex.tv",
                fetch: @escaping RequestFetch = urlSessionRequestFetch) {
        self.base = base
        self.device = device
        self.fetch = fetch
    }

    func request(_ path: String, method: String = "GET", token: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: base + path)!, timeoutInterval: 20)
        request.httpMethod = method
        for (key, value) in device.headers { request.setValue(value, forHTTPHeaderField: key) }
        if let token { request.setValue(token, forHTTPHeaderField: "X-Plex-Token") }
        return request
    }

    func json(_ request: URLRequest) async throws -> Any {
        let data: Data, status: Int
        do {
            (data, status) = try await fetch(request)
        } catch {
            throw SourceError(L("Får ikke kontakt med Plex"))
        }
        guard (200..<300).contains(status) else { throw plexError(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw SourceError(L("Plex svarte ikke som ventet"))
        }
        return json
    }

    /// En ny kode (fire tegn) til plex.tv/link.
    public func createPin() async throws -> PlexPin {
        let json = try await self.json(request("/api/v2/pins?strong=false", method: "POST"))
        guard let pin = parsePin(json) else { throw SourceError(L("Plex svarte ikke som ventet")) }
        return pin
    }

    /// Nøkkelen når koden er skrevet inn på plex.tv/link, ellers nil.
    public func token(for pin: PlexPin) async throws -> String? {
        let json = try await self.json(request("/api/v2/pins/\(pin.id)"))
        let token = text((json as? [String: Any])?["authToken"])
        return token.isEmpty ? nil : token
    }

    /// Serverne på kontoen (de du eier og de som er delt med deg).
    public func servers(token: String) async throws -> [PlexServer] {
        parseServers(try await json(request("/api/v2/resources?includeHttps=1&includeRelay=1", token: token)))
    }
}

/// En Plex-server: bibliotekene, filmene og seriene, bildene og filene, og hvor langt du har sett.
public struct PlexClient: Sendable {
    /// adressen til serveren (den tilkoblingen som svarte)
    public let base: String
    public let token: String
    let device: PlexDevice
    let fetch: RequestFetch

    public init(base: String, token: String, device: PlexDevice,
                fetch: @escaping RequestFetch = urlSessionRequestFetch) {
        self.base = base.hasSuffix("/") ? String(base.dropLast()) : base
        self.token = token
        self.device = device
        self.fetch = fetch
    }

    func request(_ path: String, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: URL(string: base + path)!, timeoutInterval: timeout)
        for (key, value) in device.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    func json(_ path: String) async throws -> [String: Any] {
        let data: Data, status: Int
        do {
            (data, status) = try await fetch(request(path))
        } catch {
            throw SourceError(L("Får ikke kontakt med Plex-serveren"))
        }
        guard (200..<300).contains(status) else { throw plexError(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError(L("Plex svarte ikke som ventet"))
        }
        return json["MediaContainer"] as? [String: Any] ?? [:]
    }

    /// Svarer serveren på denne adressen (med nøkkelen)?
    public func ping(timeout: TimeInterval = 5) async -> Bool {
        guard let (_, status) = try? await fetch(request("/identity", timeout: timeout)) else { return false }
        return status == 200
    }

    /// Den første tilkoblingen til [server] som svarer, i rekkefølgen `ordered` (alle prøves samtidig).
    public static func reachable(_ server: PlexServer, device: PlexDevice,
                                 fetch: @escaping RequestFetch = urlSessionRequestFetch) async -> String? {
        let uris = server.ordered.map(\.uri)
        guard !uris.isEmpty else { return nil }
        return await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, uri) in uris.enumerated() {
                group.addTask {
                    (i, await PlexClient(base: uri, token: server.accessToken, device: device, fetch: fetch).ping())
                }
            }
            var answered = Set<Int>(), good = Set<Int>()
            for await (i, ok) in group {
                answered.insert(i)
                if ok { good.insert(i) }
                // den beste som kan svare, har svart: ingen bedre (lavere) står igjen
                if let best = good.min(), (0..<best).allSatisfy(answered.contains) {
                    group.cancelAll()
                    return uris[best]
                }
            }
            return good.min().map { uris[$0] }
        }
    }

    // ── innholdet ──

    /// Bibliotekene med filmer eller serier.
    public func libraries(_ kind: VODKind) async throws -> [ChannelCategory] {
        parseLibraries(try await json("/library/sections"), kind: kind)
    }

    /// Filmene eller seriene i et bibliotek, sist lagt til først.
    public func items(_ kind: VODKind, library: String) async throws -> [VODItem] {
        let path = "/library/sections/\(library)/all?sort=addedAt:desc&includeCollections=0"
        return parseItems(try await json(path), kind: kind, client: self, library: library)
    }

    /// Siden for en film, eller en serie med alle episodene.
    public func details(_ item: VODItem) async throws -> VODDetails {
        let container = try await json("/library/metadata/\(item.id)")
        guard let meta = (container["Metadata"] as? [[String: Any]])?.first else {
            throw SourceError(L("Plex svarte ikke som ventet"))
        }
        var details = parseDetails(meta, client: self)
        if item.kind == .series {
            details.seasons = parseEpisodes(try await json("/library/metadata/\(item.id)/allLeaves"), client: self)
        }
        return details
    }

    /// «Fortsett å se» fra Plex: filmene og seriene (episodene som serien sin) du har begynt på.
    public func continueWatching(_ kind: VODKind) async throws -> [VODItem] {
        let container: [String: Any]
        if let hub = try? await json("/hubs/continueWatching/items"), hub["Metadata"] != nil {
            container = hub
        } else {
            container = try await json("/library/onDeck")
        }
        return parseContinue(container, kind: kind, client: self)
    }

    // ── adresser (med nøkkelen i adressen: brukes av avspillerne og bildene) ──

    /// Et bilde fra Plex skalert på serveren.
    public func imageURL(_ path: String?, width: Int = 400, height: Int = 600) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var c = URLComponents(string: base + "/photo/:/transcode")!
        c.queryItems = [URLQueryItem(name: "width", value: String(width)),
                        URLQueryItem(name: "height", value: String(height)),
                        URLQueryItem(name: "minSize", value: "1"), URLQueryItem(name: "upscale", value: "1"),
                        URLQueryItem(name: "url", value: path), URLQueryItem(name: "X-Plex-Token", value: token)]
        return c.url?.absoluteString
    }

    /// Fila (/library/parts/…/file.mkv), som spilles rett fra serveren.
    public func fileURL(_ key: String) -> URL? {
        var c = URLComponents(string: base + key)
        c?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return c?.url
    }

    // ── hvor langt du har sett ──

    public enum PlayState: String, Sendable {
        case playing, paused, stopped
    }

    /// Forteller Plex hvor langt du har kommet (som de andre Plex-appene: «Fortsett» og «Spilles nå»).
    public func timeline(_ ratingKey: String, state: PlayState, time: Double, duration: Double) async {
        var c = URLComponents()
        c.queryItems = [URLQueryItem(name: "ratingKey", value: ratingKey),
                        URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
                        URLQueryItem(name: "state", value: state.rawValue),
                        URLQueryItem(name: "time", value: String(Int(time * 1000))),
                        URLQueryItem(name: "duration", value: String(Int(duration * 1000)))]
        _ = try? await fetch(request("/:/timeline?" + (c.percentEncodedQuery ?? ""), timeout: 15))
    }

    /// Merker filmen eller episoden som sett.
    public func scrobble(_ ratingKey: String) async {
        let path = "/:/scrobble?identifier=com.plexapp.plugins.library&key=\(ratingKey)"
        _ = try? await fetch(request(path, timeout: 15))
    }

    /// Tekst som kan vises eller logges: uten nøkkelen.
    public func redact(_ text: String) -> String {
        token.count >= 4 ? text.replacingOccurrences(of: token, with: "***") : text
    }
}

// ── tolking ──

func double(_ value: Any?) -> Double? {
    switch value {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let s as String: return Double(s.replacingOccurrences(of: ",", with: "."))
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}

public func parsePin(_ json: Any) -> PlexPin? {
    guard let o = json as? [String: Any], let id = int(o["id"]) else { return nil }
    let code = text(o["code"])
    return code.isEmpty ? nil : PlexPin(id: id, code: code)
}

/// /api/v2/resources: bare serverne (ikke spillerne), de du eier først.
public func parseServers(_ json: Any) -> [PlexServer] {
    guard let list = json as? [[String: Any]] else { return [] }
    let servers: [PlexServer] = list.compactMap { r in
        guard text(r["provides"]).split(separator: ",").contains("server") else { return nil }
        let id = text(r["clientIdentifier"]), token = text(r["accessToken"])
        guard !id.isEmpty, !token.isEmpty else { return nil }
        let connections: [PlexConnection] = (r["connections"] as? [[String: Any]] ?? []).compactMap { c in
            let uri = text(c["uri"])
            guard !uri.isEmpty else { return nil }
            return PlexConnection(uri: uri, local: flag(c["local"]), relay: flag(c["relay"]))
        }
        return PlexServer(id: id, name: text(r["name"]), accessToken: token, owned: flag(r["owned"]),
                          connections: connections)
    }
    return servers.filter(\.owned) + servers.filter { !$0.owned }
}

func flag(_ value: Any?) -> Bool {
    if let b = value as? Bool { return b }
    return int(value) == 1 || text(value).lowercased() == "true"
}

/// /library/sections: bibliotekene med filmer (movie) eller serier (show).
public func parseLibraries(_ container: [String: Any], kind: VODKind) -> [ChannelCategory] {
    let type = kind == .movies ? "movie" : "show"
    return (container["Directory"] as? [[String: Any]] ?? []).compactMap { d in
        let key = text(d["key"])
        guard text(d["type"]) == type, !key.isEmpty else { return nil }
        return ChannelCategory(id: key, name: text(d["title"]))
    }
}

/// «112 min»
func minutes(_ ms: Any?) -> String {
    guard let ms = int(ms), ms > 0 else { return "" }
    return L("{n} min", ["n": Int((Double(ms) / 60000).rounded())])
}

func plexRating(_ m: [String: Any]) -> Double? {
    guard let r = double(m["audienceRating"]) ?? double(m["rating"]), r > 0 else { return nil }
    return min(r, 10)
}

/// Den første fila: filtypen og nøkkelen (/library/parts/…).
func firstPart(_ m: [String: Any]) -> (container: String?, key: String?) {
    let media = (m["Media"] as? [[String: Any]])?.first
    let part = (media?["Part"] as? [[String: Any]])?.first
    let container = nonEmpty(part?["container"]) ?? nonEmpty(media?["container"])
    return (container, nonEmpty(part?["key"]))
}

func tags(_ value: Any?, limit: Int = 6) -> String {
    (value as? [[String: Any]] ?? []).prefix(limit).compactMap { nonEmpty($0["tag"]) }.joined(separator: ", ")
}

func plexItem(_ m: [String: Any], kind: VODKind, client: PlexClient, library: String) -> VODItem? {
    let id = text(m["ratingKey"])
    let name = text(m["title"]).trimmingCharacters(in: .whitespaces)
    guard !id.isEmpty, !name.isEmpty else { return nil }
    let watched: Bool
    if kind == .series {
        let leaves = int(m["leafCount"]) ?? 0
        watched = leaves > 0 && (int(m["viewedLeafCount"]) ?? 0) >= leaves
    } else {
        watched = (int(m["viewCount"]) ?? 0) > 0
    }
    return VODItem(id: id, kind: kind, name: name, poster: client.imageURL(nonEmpty(m["thumb"])),
                   categoryId: library, rating: plexRating(m), year: int(m["year"]).map { String($0) },
                   ext: kind == .movies ? firstPart(m).container : nil, source: "plex", watched: watched)
}

public func parseItems(_ container: [String: Any], kind: VODKind, client: PlexClient,
                       library: String) -> [VODItem] {
    let type = kind == .movies ? "movie" : "show"
    var seen = Set<String>()
    return (container["Metadata"] as? [[String: Any]] ?? []).compactMap { m in
        guard text(m["type"]) == type, let item = plexItem(m, kind: kind, client: client, library: library),
              seen.insert(item.id).inserted else { return nil }
        return item
    }
}

/// /library/metadata/<id>: handlingen, sjangrene, rollene, regissøren, lengden, fila og hvor langt du har sett.
public func parseDetails(_ m: [String: Any], client: PlexClient) -> VODDetails {
    var d = VODDetails()
    d.plot = nonEmpty(m["summary"]) ?? ""
    d.genre = tags(m["Genre"], limit: 3)
    d.cast = tags(m["Role"])
    d.director = tags(m["Director"], limit: 2)
    d.duration = minutes(m["duration"])
    d.year = int(m["year"]).map { String($0) }
    d.backdrop = client.imageURL(nonEmpty(m["art"]), width: 1280, height: 720)
    d.poster = client.imageURL(nonEmpty(m["thumb"]))
    d.rating = plexRating(m)
    let part = firstPart(m)
    d.ext = part.container
    d.fileKey = part.key
    d.resume = Double(int(m["viewOffset"]) ?? 0) / 1000
    d.watched = (int(m["viewCount"]) ?? 0) > 0
    return d
}

/// /library/metadata/<serie>/allLeaves: alle episodene, sesong for sesong.
/// Én episode fra Plex.
func plexEpisode(_ e: [String: Any], client: PlexClient) -> Episode? {
    let id = text(e["ratingKey"])
    guard !id.isEmpty, text(e["type"]).isEmpty || text(e["type"]) == "episode" else { return nil }
    let n = int(e["index"]) ?? 0
    let part = firstPart(e)
    return Episode(id: id, season: int(e["parentIndex"]) ?? 1, number: n,
                   title: nonEmpty(e["title"]) ?? L("Episode {n}", ["n": n]),
                   plot: nonEmpty(e["summary"]) ?? "", duration: minutes(e["duration"]),
                   image: client.imageURL(nonEmpty(e["thumb"]), width: 480, height: 270),
                   ext: part.container ?? "mkv", source: "plex", fileKey: part.key,
                   resume: Double(int(e["viewOffset"]) ?? 0) / 1000,
                   watched: (int(e["viewCount"]) ?? 0) > 0)
}

public func parseEpisodes(_ container: [String: Any], client: PlexClient) -> [Season] {
    let episodes: [Episode] = (container["Metadata"] as? [[String: Any]] ?? []).compactMap {
        plexEpisode($0, client: client)
    }
    let groups = Dictionary(grouping: episodes, by: \.season)
    return groups.keys.sorted().map { number in
        Season(number: number, episodes: (groups[number] ?? []).sorted { $0.number < $1.number })
    }
}

/// «Fortsett å se»: filmene som de er, episodene som serien sin (én gang hver).
public func parseContinue(_ container: [String: Any], kind: VODKind, client: PlexClient) -> [VODItem] {
    var seen = Set<String>()
    return (container["Metadata"] as? [[String: Any]] ?? []).compactMap { m in
        let item: VODItem?
        switch (kind, text(m["type"])) {
        case (.movies, "movie"):
            item = plexItem(m, kind: .movies, client: client, library: text(m["librarySectionID"]))
        case (.series, "episode"):
            let id = text(m["grandparentRatingKey"]), name = text(m["grandparentTitle"])
            item = id.isEmpty || name.isEmpty ? nil
                : VODItem(id: id, kind: .series, name: name,
                          poster: client.imageURL(nonEmpty(m["grandparentThumb"])),
                          categoryId: text(m["librarySectionID"]), source: "plex")
        default:
            item = nil
        }
        guard let item, seen.insert(item.id).inserted else { return nil }
        return item
    }
}

// ── radene på «Hjem» (som Hjem i Plex) ──

/// En film eller serie i en rad; i rader med episoder (som «Nytt fra …») også episoden, som spilles med en gang.
public struct VODRowItem: Hashable, Identifiable, Sendable {
    /// filmen eller serien (åpnes som egen side)
    public let item: VODItem
    public let episode: Episode?

    public init(item: VODItem, episode: Episode? = nil) {
        self.item = item
        self.episode = episode
    }

    public var id: String { episode.map { "e\($0.id)" } ?? item.id }
}

/// En rad på «Hjem»: tittelen fra Plex («Nytt fra …», «Nylig lagt til …») og det som står i den.
public struct VODRow: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [VODRowItem]

    public init(id: String, title: String, items: [VODRowItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// Serien en sesong eller episode hører til (med seriens plakat).
func parentShow(_ m: [String: Any], key: String, client: PlexClient) -> VODItem? {
    let id = text(m["\(key)RatingKey"]), name = text(m["\(key)Title"])
    guard !id.isEmpty, !name.isEmpty else { return nil }
    return VODItem(id: id, kind: .series, name: name, poster: client.imageURL(nonEmpty(m["\(key)Thumb"])),
                   categoryId: text(m["librarySectionID"]), source: "plex")
}

func rowItem(_ m: [String: Any], kind: VODKind, client: PlexClient) -> VODRowItem? {
    let library = text(m["librarySectionID"])
    switch (kind, text(m["type"])) {
    case (.movies, "movie"):
        return plexItem(m, kind: .movies, client: client, library: library).map { VODRowItem(item: $0) }
    case (.series, "show"):
        return plexItem(m, kind: .series, client: client, library: library).map { VODRowItem(item: $0) }
    case (.series, "season"):
        return parentShow(m, key: "parent", client: client).map { VODRowItem(item: $0) }
    case (.series, "episode"):
        guard let show = parentShow(m, key: "grandparent", client: client),
              let episode = plexEpisode(m, client: client) else { return nil }
        return VODRowItem(item: show, episode: episode)
    default:
        return nil
    }
}

/// /hubs/promoted og /hubs/sections/<n>: radene med filmer eller serier (episodene som episoder), uten «Fortsett å
/// se» (den har sin egen rad) og uten rader med noe annet (musikk, spillelister, kanaler).
public func parseHubs(_ container: [String: Any], kind: VODKind, client: PlexClient) -> [VODRow] {
    (container["Hub"] as? [[String: Any]] ?? []).compactMap { hub in
        let title = text(hub["title"]).trimmingCharacters(in: .whitespaces)
        let id = nonEmpty(hub["hubIdentifier"]) ?? title
        guard !title.isEmpty, !id.lowercased().contains("continuewatching"), !id.lowercased().contains("ondeck")
        else { return nil }
        var seen = Set<String>()
        let items = (hub["Metadata"] as? [[String: Any]] ?? []).compactMap { m -> VODRowItem? in
            guard let item = rowItem(m, kind: kind, client: client), seen.insert(item.id).inserted else { return nil }
            return item
        }
        return items.isEmpty ? nil : VODRow(id: id, title: title, items: items)
    }
}

extension PlexClient {
    /// Radene på Hjem i Plex for bibliotekene med filmer eller serier; har ikke serveren noen der, radene i hvert
    /// bibliotek (Anbefalt).
    public func rows(_ kind: VODKind, libraries: [String]) async throws -> [VODRow] {
        guard !libraries.isEmpty else { return [] }
        let ids = libraries.joined(separator: ",")
        let query = "count=20&excludeContinueWatching=1&includeMeta=1"
        let home = "/hubs/promoted?contentDirectoryID=\(ids)&pinnedContentDirectoryID=\(ids)&" + query
        var rows: [VODRow] = []
        if let container = try? await json(home) {
            rows = parseHubs(container, kind: kind, client: self)
        }
        if rows.isEmpty {
            for library in libraries {
                if let container = try? await json("/hubs/sections/\(library)?" + query) {
                    rows += parseHubs(container, kind: kind, client: self)
                }
            }
        }
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    /// Én episode (fila mangler noen ganger i radene).
    public func episode(_ id: String) async throws -> Episode? {
        (try await json("/library/metadata/\(id)")["Metadata"] as? [[String: Any]])?.first.flatMap {
            plexEpisode($0, client: self)
        }
    }
}
