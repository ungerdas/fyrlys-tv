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

    /// Hodene; X-Plex-Language etter språket i appen, så overskriftene Plex lager selv («Nylig lagt til i …»), kan
    /// komme på norsk (om serveren oversetter dem, er ikke sikkert).
    public var headers: [String: String] {
        ["X-Plex-Product": "Fyrlys", "X-Plex-Version": version, "X-Plex-Client-Identifier": clientId,
         "X-Plex-Platform": platform, "X-Plex-Device": platform, "X-Plex-Device-Name": deviceName,
         "X-Plex-Language": appLanguage == "en" ? "en" : "nb", "Accept": "application/json"]
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

    /// I den rekkefølgen de prøves: på hjemmenettet, så utenfra, så gjennom Plex sin relé (treg). På hjemmenettet også
    /// rett til adressen med http (etter https-adressen): noen rutere stopper navnene …plex.direct (de peker inn i
    /// hjemmenettet), og da svarte bare reléet. Bare til private adresser, så det aldri går over nettet uten https.
    public var ordered: [PlexConnection] {
        let home = connections.filter { $0.local && !$0.relay }
        let direct = home.compactMap { c in lanHTTP(c.uri).map { PlexConnection(uri: $0, local: true, relay: false) } }
        var seen = Set<String>()
        return (home + direct + connections.filter { !$0.local && !$0.relay } + connections.filter(\.relay))
            .filter { seen.insert($0.uri).inserted }
    }
}

/// http://192.168.1.10:32400 for https://192-168-1-10.<id>.plex.direct:32400 (navnet har adressen i seg), når
/// adressen er i et privat nett (10.x, 172.16–31.x, 192.168.x); ellers nil.
public func lanHTTP(_ uri: String) -> String? {
    guard let c = URLComponents(string: uri), c.scheme?.lowercased() == "https",
          let host = c.host?.lowercased(), host.hasSuffix(".plex.direct"),
          let label = host.split(separator: ".").first else { return nil }
    let address = label.replacingOccurrences(of: "-", with: ".")
    guard isPrivateIPv4(address) else { return nil }
    return "http://\(address):\(c.port ?? 32400)"
}

/// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 og 169.254.0.0/16 (som Fyrlys for Windows; ikke 127.x, det er
/// enheten selv).
public func isPrivateIPv4(_ address: String) -> Bool {
    let parts = address.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    let n = parts.compactMap { part -> Int? in
        guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let v = Int(part), v <= 255 else {
            return nil
        }
        return v
    }
    guard n.count == 4 else { return false }
    return n[0] == 10 || (n[0] == 172 && (16...31).contains(n[1])) || (n[0] == 192 && n[1] == 168)
        || (n[0] == 169 && n[1] == 254)
}

/// Rekkefølgen i et bibliotek hos Plex (som Fyrlys for Windows).
public enum PlexSort: String, CaseIterable, Sendable {
    /// nylig lagt til (serier: etter den nyeste episoden, som i Plex)
    case added
    /// A–Å
    case title
    /// nyeste utgivelser
    case released
    /// best vurdert
    case rating
    /// sist sett
    case viewed

    public func key(_ kind: VODKind) -> String {
        switch self {
        case .added: return kind == .series ? "episode.addedAt:desc" : "addedAt:desc"
        case .title: return "titleSort"
        case .released: return "originallyAvailableAt:desc"
        case .rating: return "audienceRating:desc"
        case .viewed: return "lastViewedAt:desc"
        }
    }
}

/// /library/sections/<n>/genre: sjangrene (nøkkelen brukes i genre=).
public func parseGenres(_ container: [String: Any]) -> [ChannelCategory] {
    (container["Directory"] as? [[String: Any]] ?? []).compactMap { d in
        let key = text(d["key"]), title = text(d["title"]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !title.isEmpty else { return nil }
        return ChannelCategory(id: key, name: title)
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

    /// Brukerne i Plex Home («Hvem ser på?»), med den som eier kontoen først.
    public func homeUsers(token: String) async throws -> [PlexHomeUser] {
        parseHomeUsers(try await json(request("/api/v2/home/users", token: token)))
    }

    /// Bytter til [user] i Plex Home og gir nøkkelen til den brukeren ([pin] når brukeren har en). Nøkkelen til
    /// kontoen som er logget inn, må brukes (den du fikk fra plex.tv/link; en annen brukers nøkkel kan ikke bytte).
    public func switchUser(_ user: PlexHomeUser, pin: String?, token: String) async throws -> String {
        var query = ""
        if let pin, !pin.isEmpty, let encoded = pin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            query = "?pin=\(encoded)"
        }
        // plex.tv vil ha uuid-en i adressen (det numeriske id-et ga 404 hos eieren 6.11); uten uuid prøves id-et
        let keys = [user.uuid, String(user.id)].compactMap { $0 }.filter { !$0.isEmpty }
        var lastError: Error = SourceError(L("Plex svarte ikke som ventet"))
        for key in keys {
            do {
                let json = try await self.json(request("/api/v2/home/users/\(key)/switch" + query, method: "POST",
                                                       token: token))
                let newToken = text((json as? [String: Any])?["authToken"])
                guard !newToken.isEmpty else { throw SourceError(L("Plex svarte ikke som ventet")) }
                return newToken
            } catch {
                lastError = error
                // 404: feil nøkkel i adressen, prøv den neste; alt annet (galt PIN = 403) gis videre
                guard (error as? SourceError)?.message.contains("404") == true else { throw error }
            }
        }
        throw lastError
    }
}

/// En bruker i Plex Home.
public struct PlexHomeUser: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    /// uuid-en plex.tv vil ha i adressen for å bytte
    public var uuid: String?
    public let name: String
    /// bildet (avataren)
    public let thumb: String?
    public let admin: Bool
    /// må skrive PIN for å bytte til brukeren
    public let protected: Bool
    /// en begrenset bruker (barn)
    public let restricted: Bool

    public init(id: Int, uuid: String? = nil, name: String, thumb: String? = nil, admin: Bool = false,
                protected: Bool = false, restricted: Bool = false) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.thumb = thumb
        self.admin = admin
        self.protected = protected
        self.restricted = restricted
    }
}

/// /api/v2/home/users: brukerne (`users`), eieren (admin) først.
public func parseHomeUsers(_ json: Any) -> [PlexHomeUser] {
    let list = ((json as? [String: Any])?["users"] as? [[String: Any]]) ?? (json as? [[String: Any]]) ?? []
    let users: [PlexHomeUser] = list.compactMap { u in
        guard let id = int(u["id"]) else { return nil }
        let name = nonEmpty(u["friendlyName"]) ?? nonEmpty(u["title"]) ?? nonEmpty(u["username"]) ?? ""
        guard !name.isEmpty else { return nil }
        return PlexHomeUser(id: id, uuid: nonEmpty(u["uuid"]), name: name, thumb: nonEmpty(u["thumb"]), admin: flag(u["admin"]),
                            protected: flag(u["protected"]), restricted: flag(u["restricted"]))
    }
    return users.filter(\.admin) + users.filter { !$0.admin }
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

    func json(_ path: String, timeout: TimeInterval = 30) async throws -> [String: Any] {
        let data: Data, status: Int
        do {
            (data, status) = try await fetch(request(path, timeout: timeout))
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

    /// Alle bibliotekene med filmer og serier (til valget av hvilke som vises).
    public func sections() async throws -> [PlexSection] {
        parseSections(try await json("/library/sections"))
    }

    /// Filmene eller seriene i et bibliotek, sist lagt til først.
    public func items(_ kind: VODKind, library: String) async throws -> [VODItem] {
        let path = "/library/sections/\(library)/all?sort=addedAt:desc&includeCollections=0"
        return parseItems(try await json(path), kind: kind, client: self, library: library)
    }

    /// En side (100 om gangen) av filmene eller seriene i et bibliotek, i rekkefølgen [sort] og eventuelt bare i
    /// sjangeren [genre], og hvor mange det er i alt.
    public func page(_ kind: VODKind, library: String, sort: PlexSort, genre: String?, start: Int,
                     size: Int = 100) async throws -> (items: [VODItem], total: Int) {
        var path = "/library/sections/\(library)/all?type=\(kind == .movies ? 1 : 2)&sort=\(sort.key(kind))"
            + "&includeCollections=0"
        if let genre, let encoded = genre.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            path += "&genre=\(encoded)"
        }
        path += "&X-Plex-Container-Start=\(start)&X-Plex-Container-Size=\(size)"
        let container = try await json(path)
        let items = parseItems(container, kind: kind, client: self, library: library)
        return (items, int(container["totalSize"]) ?? (start + items.count))
    }

    /// Sjangrene i et bibliotek.
    public func genres(library: String) async throws -> [ChannelCategory] {
        parseGenres(try await json("/library/sections/\(library)/genre"))
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

    /// «Fortsett å se» fra Plex: filmene og seriene (med episoden du er midt i, eller den neste) du har begynt på, sist
    /// sett først (filmer og serier om hverandre i Plex-fanen).
    public func continueWatching(_ kinds: Set<VODKind>) async throws -> [VODResume] {
        let container: [String: Any]
        if let hub = try? await json("/hubs/continueWatching/items"), hub["Metadata"] != nil {
            container = hub
        } else {
            container = try await json("/library/onDeck")
        }
        return parseContinue(container, kinds: kinds, client: self)
    }

    public func continueWatching(_ kind: VODKind) async throws -> [VODResume] {
        try await continueWatching([kind])
    }

    /// Filmene og seriene med disse id-ene (favorittene), i samme rekkefølge; de som ikke finnes lenger, er borte.
    public func items(ids: [String], kinds: Set<VODKind>) async throws -> [VODItem] {
        let wanted = ids.filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard !wanted.isEmpty else { return [] }
        let found = parseItems(try await json("/library/metadata/" + wanted.joined(separator: ",")), kinds: kinds,
                               client: self, library: "")
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return wanted.compactMap { byId[$0] }
    }

    public func items(ids: [String], kind: VODKind) async throws -> [VODItem] {
        try await items(ids: ids, kinds: [kind])
    }

    /// Søket i filmene og seriene på serveren (i den rekkefølgen Plex gir treffene).
    public func search(_ query: String, kinds: Set<VODKind>) async throws -> [VODItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let encoded = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            return []
        }
        return parseSearch(try await json("/hubs/search?query=\(encoded)&limit=50"), kinds: kinds, client: self)
    }

    public func search(_ query: String, kind: VODKind) async throws -> [VODItem] {
        try await search(query, kinds: [kind])
    }

    /// «Mer som dette»: den første raden Plex har for filmen eller serien med noe i (uten den selv), høyst 24.
    public func related(_ item: VODItem) async throws -> [VODItem] {
        parseRelated(try await json("/hubs/metadata/\(item.id)/related?count=24"), kind: item.kind, exclude: item.id,
                     client: self)
    }

    /// Alt i en rad på Hjem («Se alle»), når Plex sier det er flere enn de som vises.
    public func rowItems(_ row: VODRow, kinds: Set<VODKind>) async throws -> [VODRowItem] {
        guard let key = row.key, key.hasPrefix("/") else { return row.items }
        let path = key + (key.contains("?") ? "&" : "?") + "X-Plex-Container-Start=0&X-Plex-Container-Size=200"
        var seen = Set<String>()
        let items = (try await json(path)["Metadata"] as? [[String: Any]] ?? []).compactMap { m -> VODRowItem? in
            guard let item = rowItem(m, kinds: kinds, client: self), seen.insert(item.id).inserted else { return nil }
            return item
        }
        return items.isEmpty ? row.items : items
    }

    public func rowItems(_ row: VODRow, kind: VODKind) async throws -> [VODRowItem] {
        try await rowItems(row, kinds: [kind])
    }

    // ── adresser (med nøkkelen i adressen: brukes av avspillerne og bildene) ──

    /// Et bilde fra Plex skalert på serveren.
    /// Et bilde fra serveren i [width] × [height] (plakater 720 × 1080: skarpt på Apple TV 4K, som tegner med to
    /// piksler per punkt). Som Plex selv: bildet fyller rammen og beskjæres (`minSize=1`); med [fit] holdes hele
    /// bildet innenfor rammen i stedet, uten å forstørres (logoene, som har alle slags bredder).
    public func imageURL(_ path: String?, width: Int = 720, height: Int = 1080, fit: Bool = false) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var c = URLComponents(string: base + "/photo/:/transcode")!
        c.queryItems = [URLQueryItem(name: "width", value: String(width)),
                        URLQueryItem(name: "height", value: String(height)),
                        URLQueryItem(name: "minSize", value: fit ? "0" : "1"),
                        URLQueryItem(name: "upscale", value: fit ? "0" : "1"),
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

    /// Merker en film, serie, sesong eller episode som sett eller ikke sett (en serie eller sesong: alle episodene i
    /// den). Kaster når serveren ikke svarte ja.
    public func setWatched(_ ratingKey: String, _ watched: Bool) async throws {
        let path = "/:/\(watched ? "scrobble" : "unscrobble")?identifier=com.plexapp.plugins.library&key=\(ratingKey)"
        let status: Int
        do {
            (_, status) = try await fetch(request(path, timeout: 15))
        } catch {
            throw SourceError(L("Får ikke kontakt med Plex-serveren"))
        }
        guard (200..<300).contains(status) else { throw plexError(status) }
    }

    /// Markørene (introen og rulleteksten) og undertekstfilene ved siden av fila for en film eller episode (spilleren
    /// venter på dette, så ikke lenge).
    public func playInfo(_ ratingKey: String) async throws -> PlexPlayInfo {
        let container = try await json("/library/metadata/\(ratingKey)?includeMarkers=1", timeout: 6)
        guard let meta = (container["Metadata"] as? [[String: Any]])?.first else { return PlexPlayInfo() }
        return parsePlayInfo(meta, client: self)
    }

    /// En undertekstfil på serveren (/library/streams/<id>) som fil med riktig filtype, i UTF-8 (Plex gjør om
    /// tegnsettet, så æ, ø og å kommer riktig), med nøkkelen i adressen (VLC henter den).
    public func subtitleURL(_ key: String, ext: String) -> URL? {
        let last = key.split(separator: "/").last ?? ""
        var c = URLComponents(string: base + key + (last.contains(".") ? "" : "." + ext))
        c?.queryItems = [URLQueryItem(name: "encoding", value: "utf-8"), URLQueryItem(name: "X-Plex-Token", value: token)]
        return c?.url
    }

    /// Tekst som kan vises eller logges: uten nøkkelen.
    public func redact(_ text: String) -> String {
        token.count >= 4 ? text.replacingOccurrences(of: token, with: "***") : text
    }
}

/// Et merke Plex har funnet i en film eller episode: introen eller rulleteksten, i sekunder.
public struct PlexMarker: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case intro, credits
    }

    public let kind: Kind
    public let start: Double
    public let end: Double
    /// rulleteksten til slutt (etter den kommer ingenting mer av episoden)
    public let final: Bool

    public init(kind: Kind, start: Double, end: Double, final: Bool = false) {
        self.kind = kind
        self.start = start
        self.end = end
        self.final = final
    }

    /// [time] er inne i merket (de siste to sekundene teller ikke: da er det for sent å hoppe)
    public func covers(_ time: Double) -> Bool { time >= start && time < end - 2 }
}

/// En undertekstfil ved siden av filmen eller episoden på serveren (ikke inni fila).
public struct PlexSubtitle: Hashable, Sendable {
    public let url: URL
    /// språkkoden fra Plex («nor», «eng»), tom når den ikke er kjent
    public let language: String
    /// navnet Plex viser («Norsk (SRT External)»)
    public let name: String
    public let forced: Bool
    /// valgt i Plex (i en av Plex-appene)
    public let selected: Bool
}

/// Det som trengs når en film eller episode fra Plex spilles: markørene og undertekstfilene, og språkene til
/// undertekstene inni fila.
public struct PlexPlayInfo: Sendable {
    public var markers: [PlexMarker] = []
    public var subtitles: [PlexSubtitle] = []
    public var embeddedSubtitleLanguages: [String] = []
    /// en undertekst inni fila er valgt i Plex
    public var embeddedSubtitleSelected = false

    public init() {}

    /// Undertekstfila som skal vises fra start: den som er valgt i Plex, ellers en på [preferred] (norsk) når fila
    /// ikke har undertekster på det språket selv (og ingen andre er valgt i Plex). Tvungne (bare det som sies på andre
    /// språk) velges ikke av seg selv.
    public func chosenSubtitle(preferred: Set<String>) -> PlexSubtitle? {
        if let selected = subtitles.first(where: \.selected) { return selected }
        guard !embeddedSubtitleSelected, !preferred.isEmpty,
              !embeddedSubtitleLanguages.contains(where: { preferred.contains($0.lowercased()) }) else { return nil }
        return subtitles.first { !$0.forced && preferred.contains($0.language.lowercased()) }
    }
}

/// Språkkodene for norsk slik Plex og filene skriver dem.
public let norwegianLanguageCodes: Set<String> = ["nor", "nob", "nno", "no", "nb", "nn", "norwegian"]

/// Filtypen for en undertekstfil fra Plex (codec): srt, vtt, sup (PGS) eller det Plex kaller den (ass …); nil når den
/// mangler, og for VobSub (to filer).
func subtitleExtension(_ codec: String) -> String? {
    switch codec.lowercased() {
    case "srt", "subrip": return "srt"
    case "vtt", "webvtt": return "vtt"
    case "pgs", "hdmv_pgs_subtitle": return "sup"
    case "", "vobsub": return nil
    case let other: return other.allSatisfy { $0.isLetter || $0.isNumber } ? other : nil
    }
}

/// /library/metadata/<id>?includeMarkers=1: markørene, og undertekstene i den første fila (de med key er filer ved
/// siden av).
public func parsePlayInfo(_ m: [String: Any], client: PlexClient) -> PlexPlayInfo {
    var info = PlexPlayInfo()
    let raw = m["Marker"] as? [[String: Any]] ?? []
    var markers: [PlexMarker] = raw.compactMap { marker in
        guard let kind = PlexMarker.Kind(rawValue: text(marker["type"]).lowercased()),
              let start = int(marker["startTimeOffset"]), let end = int(marker["endTimeOffset"]), end > start
        else { return nil }
        return PlexMarker(kind: kind, start: Double(start) / 1000, end: Double(end) / 1000,
                          final: flag(marker["final"]))
    }.sorted { $0.start < $1.start }
    // eldre servere merker ikke rulleteksten til slutt: da er det den siste
    if !markers.contains(where: \.final), let last = markers.lastIndex(where: { $0.kind == .credits }) {
        let credits = markers[last]
        markers[last] = PlexMarker(kind: .credits, start: credits.start, end: credits.end, final: true)
    }
    info.markers = markers
    let media = (m["Media"] as? [[String: Any]])?.first
    let part = (media?["Part"] as? [[String: Any]])?.first
    for stream in part?["Stream"] as? [[String: Any]] ?? [] where int(stream["streamType"]) == 3 {
        let language = text(stream["languageCode"])
        if let key = nonEmpty(stream["key"]) {
            guard let ext = subtitleExtension(text(stream["codec"])), let url = client.subtitleURL(key, ext: ext)
            else { continue }
            let name = nonEmpty(stream["displayTitle"]) ?? nonEmpty(stream["title"]) ?? nonEmpty(stream["language"])
                ?? L("Undertekster")
            info.subtitles.append(PlexSubtitle(url: url, language: language, name: name,
                                               forced: flag(stream["forced"]), selected: flag(stream["selected"])))
        } else {
            if !language.isEmpty { info.embeddedSubtitleLanguages.append(language) }
            if flag(stream["selected"]) { info.embeddedSubtitleSelected = true }
        }
    }
    return info
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

/// Et bibliotek med filmer eller serier på serveren.
public struct PlexSection: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: VODKind
}

/// /library/sections: bibliotekene med filmer og serier (i den rekkefølgen Plex har dem; musikk og bilder står ikke).
public func parseSections(_ container: [String: Any]) -> [PlexSection] {
    (container["Directory"] as? [[String: Any]] ?? []).compactMap { d in
        let key = text(d["key"])
        let kind: VODKind
        switch text(d["type"]) {
        case "movie": kind = .movies
        case "show": kind = .series
        default: return nil
        }
        return key.isEmpty ? nil : PlexSection(id: key, name: text(d["title"]), kind: kind)
    }
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

/// «1 t 52 min»
func minutes(_ ms: Any?) -> String {
    guard let ms = int(ms), ms > 0 else { return "" }
    return minutesText(Int((Double(ms) / 60000).rounded()))
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

/// Filmer (movie) eller serier (show) etter typen hos Plex; nil for alt annet.
func plexKind(_ type: String) -> VODKind? {
    switch type {
    case "movie": return .movies
    case "show": return .series
    default: return nil
    }
}

public func parseItems(_ container: [String: Any], kinds: Set<VODKind>, client: PlexClient,
                       library: String) -> [VODItem] {
    var seen = Set<String>()
    return (container["Metadata"] as? [[String: Any]] ?? []).compactMap { m in
        guard let kind = plexKind(text(m["type"])), kinds.contains(kind),
              let item = plexItem(m, kind: kind, client: client, library: library),
              seen.insert(item.id).inserted else { return nil }
        return item
    }
}

public func parseItems(_ container: [String: Any], kind: VODKind, client: PlexClient,
                       library: String) -> [VODItem] {
    parseItems(container, kinds: [kind], client: client, library: library)
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
    d.backdrop = client.imageURL(nonEmpty(m["art"]), width: 1920, height: 1080)
    d.poster = client.imageURL(nonEmpty(m["thumb"]))
    d.rating = plexRating(m)
    let part = firstPart(m)
    d.ext = part.container
    d.fileKey = part.key
    d.resume = Double(int(m["viewOffset"]) ?? 0) / 1000
    d.watched = (int(m["viewCount"]) ?? 0) > 0
    d.age = nonEmpty(m["contentRating"])
    d.country = tags(m["Country"], limit: 1).isEmpty ? nil : tags(m["Country"], limit: 1)
    d.quality = plexQuality(m)
    d.logo = client.imageURL(plexImage(m, type: "clearLogo"), width: 1600, height: 800, fit: true)
    d.tagline = nonEmpty(m["tagline"])
    d.studio = nonEmpty(m["studio"])
    d.people = plexPeople(m["Role"], client: client)
    return d
}

/// Et bilde av typen [type] («clearLogo», «background», «coverPoster») i lista Image, når Plex har det.
func plexImage(_ m: [String: Any], type: String) -> String? {
    (m["Image"] as? [[String: Any]] ?? []).first { text($0["type"]) == type }.flatMap { nonEmpty($0["url"]) }
}

/// Rollene med rollenavn og bilde (høyst 12).
func plexPeople(_ value: Any?, client: PlexClient, limit: Int = 12) -> [VODPerson] {
    var seen = Set<String>()
    return (value as? [[String: Any]] ?? []).compactMap { r -> VODPerson? in
        guard let name = nonEmpty(r["tag"]), seen.insert(name).inserted else { return nil }
        return VODPerson(name: name, role: nonEmpty(r["role"]),
                         image: client.imageURL(nonEmpty(r["thumb"]), width: 400, height: 400))
    }.prefix(limit).map { $0 }
}

/// Bildet og lyden fra den første fila: oppløsningen (høyden, ellers videoResolution), HDR (fra videostrømmen, bare
/// på siden for filmen eller episoden), kodekene og kanalene.
func plexQuality(_ m: [String: Any]) -> [String] {
    guard let media = (m["Media"] as? [[String: Any]])?.first else { return [] }
    var height = int(media["height"])
    if height == nil {
        switch text(media["videoResolution"]).lowercased() {
        case "4k": height = 2160
        case "1080": height = 1080
        case "720": height = 720
        case "576", "480", "sd": height = 480
        default: break
        }
    }
    let part = (media["Part"] as? [[String: Any]])?.first
    let video = (part?["Stream"] as? [[String: Any]] ?? []).first { int($0["streamType"]) == 1 }
    let transfer = text(video?["colorTrc"]).lowercased()
    let hdr = transfer == "smpte2084" || transfer == "arib-std-b67" || flag(video?["DOVIPresent"])
    return qualityBadges(height: height, hdr: hdr, video: text(media["videoCodec"]),
                         channels: int(media["audioChannels"]), audio: text(media["audioCodec"]))
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
                   image: client.imageURL(nonEmpty(e["thumb"]), width: 960, height: 540),
                   ext: part.container ?? "mkv", source: "plex", fileKey: part.key,
                   resume: Double(int(e["viewOffset"]) ?? 0) / 1000,
                   watched: (int(e["viewCount"]) ?? 0) > 0)
}

public func parseEpisodes(_ container: [String: Any], client: PlexClient) -> [Season] {
    let episodes: [Episode] = (container["Metadata"] as? [[String: Any]] ?? []).compactMap {
        plexEpisode($0, client: client)
    }
    let groups = Dictionary(grouping: episodes, by: \.season)
    return groups.keys.sorted { seasonOrder($0) < seasonOrder($1) }.map { number in
        Season(number: number, episodes: (groups[number] ?? []).sorted { $0.number < $1.number })
    }
}

/// «Fortsett å se»: filmene som de er, episodene med serien sin (én gang per serie), med hvor langt du har kommet og
/// et bredt bilde (bakgrunnen til filmen eller serien, ellers episodebildet).
public func parseContinue(_ container: [String: Any], kind: VODKind, client: PlexClient) -> [VODResume] {
    parseContinue(container, kinds: [kind], client: client)
}

public func parseContinue(_ container: [String: Any], kinds: Set<VODKind>, client: PlexClient) -> [VODResume] {
    var seen = Set<String>()
    return (container["Metadata"] as? [[String: Any]] ?? []).compactMap { m in
        let resume: VODResume?
        let progress = fraction(m["viewOffset"], of: m["duration"])
        switch text(m["type"]) {
        case "movie" where kinds.contains(.movies):
            resume = plexItem(m, kind: .movies, client: client, library: text(m["librarySectionID"])).map {
                VODResume(item: $0, progress: progress, image: wideImage(m, ["art", "thumb"], client: client))
            }
        case "episode" where kinds.contains(.series):
            resume = parentShow(m, key: "grandparent", client: client).map {
                VODResume(item: $0, episode: plexEpisode(m, client: client), progress: progress,
                          image: wideImage(m, ["grandparentArt", "art", "thumb"], client: client))
            }
        default:
            resume = nil
        }
        guard let resume, seen.insert(resume.id).inserted else { return nil }
        return resume
    }
}

/// Hvor langt (0–1) av lengden; 0 når noe mangler.
func fraction(_ offset: Any?, of duration: Any?) -> Double {
    guard let o = int(offset), let d = int(duration), o > 0, d > 0 else { return 0 }
    return min(1, Double(o) / Double(d))
}

/// Det første bildet som finnes av [keys], i bredformat.
func wideImage(_ m: [String: Any], _ keys: [String], client: PlexClient) -> String? {
    for key in keys {
        if let path = nonEmpty(m[key]) { return client.imageURL(path, width: 1280, height: 720) }
    }
    return nil
}

/// /hubs/metadata/<id>/related: filmene eller seriene i den første raden som har noen (uten [exclude]), høyst 24.
public func parseRelated(_ container: [String: Any], kind: VODKind, exclude: String,
                         client: PlexClient) -> [VODItem] {
    let type = kind == .movies ? "movie" : "show"
    for hub in container["Hub"] as? [[String: Any]] ?? [] {
        var seen: Set<String> = [exclude]
        let items = (hub["Metadata"] as? [[String: Any]] ?? []).compactMap { m -> VODItem? in
            guard text(m["type"]) == type,
                  let item = plexItem(m, kind: kind, client: client, library: text(m["librarySectionID"])),
                  seen.insert(item.id).inserted else { return nil }
            return item
        }
        if !items.isEmpty { return Array(items.prefix(24)) }
    }
    return []
}

/// /hubs/search: filmene eller seriene i treffene (ikke episoder, skuespillere og annet).
public func parseSearch(_ container: [String: Any], kind: VODKind, client: PlexClient) -> [VODItem] {
    parseSearch(container, kinds: [kind], client: client)
}

/// /hubs/search: filmene og seriene i treffene, i rekkefølgen til Plex (ikke episoder, skuespillere og annet).
public func parseSearch(_ container: [String: Any], kinds: Set<VODKind>, client: PlexClient) -> [VODItem] {
    var seen = Set<String>()
    var found: [VODItem] = []
    var hubs = container["Hub"] as? [[String: Any]] ?? []
    if hubs.isEmpty, let metadata = container["Metadata"] { hubs = [["Metadata": metadata]] }
    for hub in hubs {
        for m in hub["Metadata"] as? [[String: Any]] ?? [] {
            guard let kind = plexKind(text(m["type"])), kinds.contains(kind) else { continue }
            if let item = plexItem(m, kind: kind, client: client, library: text(m["librarySectionID"])),
               seen.insert(item.id).inserted {
                found.append(item)
            }
        }
    }
    return found
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

/// En rad på «Hjem»: tittelen fra Plex («Nytt fra …», «Nylig lagt til …») og det som står i den, og hvor resten
/// hentes («Se alle») når Plex sier det er flere.
public struct VODRow: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [VODRowItem]
    /// adressen til hele raden hos Plex
    public var key: String?
    /// Plex har flere enn de som står i raden
    public var more = false

    public init(id: String, title: String, items: [VODRowItem], key: String? = nil, more: Bool = false) {
        self.id = id
        self.title = title
        self.items = items
        self.key = key
        self.more = more
    }
}

/// Serien en sesong eller episode hører til (med seriens plakat).
func parentShow(_ m: [String: Any], key: String, client: PlexClient) -> VODItem? {
    let id = text(m["\(key)RatingKey"]), name = text(m["\(key)Title"])
    guard !id.isEmpty, !name.isEmpty else { return nil }
    return VODItem(id: id, kind: .series, name: name, poster: client.imageURL(nonEmpty(m["\(key)Thumb"])),
                   categoryId: text(m["librarySectionID"]), source: "plex")
}

func rowItem(_ m: [String: Any], kinds: Set<VODKind>, client: PlexClient) -> VODRowItem? {
    let library = text(m["librarySectionID"])
    let series = kinds.contains(.series)
    switch text(m["type"]) {
    case "movie" where kinds.contains(.movies):
        return plexItem(m, kind: .movies, client: client, library: library).map { VODRowItem(item: $0) }
    case "show" where series:
        return plexItem(m, kind: .series, client: client, library: library).map { VODRowItem(item: $0) }
    case "season" where series:
        return parentShow(m, key: "parent", client: client).map { VODRowItem(item: $0) }
    case "episode" where series:
        guard let show = parentShow(m, key: "grandparent", client: client),
              let episode = plexEpisode(m, client: client) else { return nil }
        return VODRowItem(item: show, episode: episode)
    default:
        return nil
    }
}

public func parseHubs(_ container: [String: Any], kind: VODKind, client: PlexClient) -> [VODRow] {
    parseHubs(container, kinds: [kind], client: client)
}

/// /hubs/promoted og /hubs/sections/<n>: radene med filmer og serier (episodene som episoder), uten «Fortsett å se»
/// (den har sin egen rad) og uten rader med noe annet (musikk, spillelister, kanaler).
public func parseHubs(_ container: [String: Any], kinds: Set<VODKind>, client: PlexClient) -> [VODRow] {
    (container["Hub"] as? [[String: Any]] ?? []).compactMap { hub in
        let title = text(hub["title"]).trimmingCharacters(in: .whitespaces)
        let id = nonEmpty(hub["hubIdentifier"]) ?? title
        guard !title.isEmpty, !id.lowercased().contains("continuewatching"), !id.lowercased().contains("ondeck")
        else { return nil }
        var seen = Set<String>()
        let items = (hub["Metadata"] as? [[String: Any]] ?? []).compactMap { m -> VODRowItem? in
            guard let item = rowItem(m, kinds: kinds, client: client), seen.insert(item.id).inserted else {
                return nil
            }
            return item
        }
        return items.isEmpty ? nil
            : VODRow(id: id, title: title, items: items, key: nonEmpty(hub["key"]), more: flag(hub["more"]))
    }
}

extension PlexClient {
    public func rows(_ kind: VODKind, libraries: [String]) async throws -> [VODRow] {
        try await rows([kind], libraries: libraries)
    }

    /// Radene på Hjem i Plex for bibliotekene (med filmer og serier om hverandre, som Hjem i Plex); har ikke serveren
    /// noen der, radene i hvert bibliotek (Anbefalt).
    public func rows(_ kinds: Set<VODKind>, libraries: [String]) async throws -> [VODRow] {
        guard !libraries.isEmpty else { return [] }
        let ids = libraries.joined(separator: ",")
        let query = "count=20&excludeContinueWatching=1&includeMeta=1"
        let home = "/hubs/promoted?contentDirectoryID=\(ids)&pinnedContentDirectoryID=\(ids)&" + query
        var rows: [VODRow] = []
        if let container = try? await json(home) {
            rows = parseHubs(container, kinds: kinds, client: self)
        }
        if rows.isEmpty {
            for library in libraries {
                if let container = try? await json("/hubs/sections/\(library)?" + query) {
                    rows += parseHubs(container, kinds: kinds, client: self)
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
