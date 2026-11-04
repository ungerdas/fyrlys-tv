import Foundation

/// Filmer og serier (VOD) fra Xtream: kategoriene, listene, detaljene og adressene.
public enum VODKind: String, Codable, Hashable, Sendable {
    case movies, series
}

/// En film eller en serie i en liste.
public struct VODItem: Codable, Hashable, Identifiable, Sendable {
    /// stream_id (film) eller series_id (serie)
    public let id: String
    public let kind: VODKind
    public let name: String
    public let poster: String?
    public let categoryId: String
    /// 0–10
    public let rating: Double?
    public let year: String?
    /// filmer: filtypen hos leverandøren (mp4, mkv …)
    public let ext: String?
    /// hvor den kommer fra: nil = IPTV-leverandøren, "plex" = Plex (id er da ratingKey)
    public var source: String?
    /// Plex: sett ferdig
    public var watched: Bool?
    /// merkene som sto i navnet hos leverandøren («PRE», «MULTI»; se `cleanTitle`)
    public var tags: [String]?
    /// da den ble lagt til hos leverandøren (sekunder siden 1970; «Nyeste først» og «Nylig lagt til»)
    public var added: Int?

    public init(id: String, kind: VODKind, name: String, poster: String? = nil, categoryId: String = "",
                rating: Double? = nil, year: String? = nil, ext: String? = nil, source: String? = nil,
                watched: Bool? = nil, tags: [String]? = nil, added: Int? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.poster = poster
        self.categoryId = categoryId
        self.rating = rating
        self.year = year
        self.ext = ext
        self.source = source
        self.watched = watched
        self.tags = tags
        self.added = added
    }

    public var isPlex: Bool { source == "plex" }

    /// nøkkelen for hvor langt man har sett (filmer; episodene har sin egen)
    public var progressKey: String { isPlex ? "plex:\(id)" : "\(kind.rawValue):\(id)" }
}

/// En episode i en serie.
public struct Episode: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let season: Int
    public let number: Int
    public let title: String
    public let plot: String
    /// «45 min» eller «01:02:03» som leverandøren skriver det
    public let duration: String
    public let image: String?
    public let ext: String
    /// nil = IPTV-leverandøren, "plex" = Plex
    public var source: String?
    /// Plex: fila på serveren (/library/parts/…), hvor langt du har sett (sekunder) og om den er sett
    public var fileKey: String?
    public var resume: Double = 0
    public var watched = false

    public init(id: String, season: Int, number: Int, title: String, plot: String = "", duration: String = "",
                image: String? = nil, ext: String = "mp4", source: String? = nil, fileKey: String? = nil,
                resume: Double = 0, watched: Bool = false) {
        self.id = id
        self.season = season
        self.number = number
        self.title = title
        self.plot = plot
        self.duration = duration
        self.image = image
        self.ext = ext
        self.source = source
        self.fileKey = fileKey
        self.resume = resume
        self.watched = watched
    }

    public var progressKey: String { source == "plex" ? "plex:\(id)" : "episode:\(id)" }
}

/// En film eller serie du har begynt på («Fortsett å se»): episoden du er midt i (serier), hvor langt du har kommet
/// (0–1, 0 når det ikke er kjent eller ikke begynt) og et bredt bilde (bakgrunnen eller episodebildet; nil: plakaten).
public struct VODResume: Codable, Hashable, Identifiable, Sendable {
    /// filmen eller serien
    public let item: VODItem
    public var episode: Episode?
    public var progress: Double
    public var image: String?

    public init(item: VODItem, episode: Episode? = nil, progress: Double = 0, image: String? = nil) {
        self.item = item
        self.episode = episode
        self.progress = progress
        self.image = image
    }

    public var id: String { item.id }
}

public struct Season: Hashable, Identifiable, Sendable {
    public let number: Int
    public let episodes: [Episode]
    public var id: Int { number }
}

/// Det som står på siden for en film eller serie.
public struct VODDetails: Sendable {
    public var plot = ""
    public var genre = ""
    public var cast = ""
    public var director = ""
    public var duration = ""
    public var year: String?
    public var backdrop: String?
    public var poster: String?
    public var rating: Double?
    /// filmer: filtypen fra detaljene (mer pålitelig enn lista)
    public var ext: String?
    /// serier
    public var seasons: [Season] = []
    /// Plex (filmer): fila på serveren, hvor langt du har sett (sekunder) og om den er sett
    public var fileKey: String?
    public var resume: Double = 0
    public var watched = false
    /// aldersgrensen («12+», «PG-13») og landet, når de er kjent
    public var age: String?
    public var country: String?
    /// bildet og lyden: «4K», «HDR», «H.265», «5.1», «Dolby Digital+» …
    public var quality: [String] = []

    public init() {}
}

extension XtreamClient {
    public func vodCategories(_ kind: VODKind) async throws -> [ChannelCategory] {
        parseCategories(try await api(kind == .movies ? "get_vod_categories" : "get_series_categories"))
    }

    /// Filmene eller seriene i en kategori.
    public func vodItems(_ kind: VODKind, category: String) async throws -> [VODItem] {
        parseVODItems(try await api(kind == .movies ? "get_vod_streams" : "get_series", ["category_id": category]),
                      kind: kind)
    }

    /// Alle filmene eller seriene (til søket; kan være mange tusen).
    public func allVODItems(_ kind: VODKind) async throws -> [VODItem] {
        parseVODItems(try await api(kind == .movies ? "get_vod_streams" : "get_series"), kind: kind)
    }

    public func vodDetails(_ item: VODItem) async throws -> VODDetails {
        switch item.kind {
        case .movies: return parseMovieInfo(try await api("get_vod_info", ["vod_id": item.id]))
        case .series: return parseSeriesInfo(try await api("get_series_info", ["series_id": item.id]))
        }
    }

    /// Filmen som fil. [ext] er filtypen hos leverandøren.
    public func movieURL(_ id: String, ext: String) -> URL {
        URL(string: "\(login.server)/movie/\(credsPath)/\(id).\(ext)")!
    }

    public func episodeURL(_ episode: Episode, ext: String? = nil) -> URL {
        URL(string: "\(login.server)/series/\(credsPath)/\(episode.id).\(ext ?? episode.ext)")!
    }
}

/// Filtypene Apples avspiller (AVPlayer) spiller selv.
public let nativeExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

/// Filtypene en film eller episode hentes som: den leverandøren oppgir (mkv, avi … spilles med VLC), eller mp4 og så
/// HLS når den ikke er oppgitt.
public func playableExtensions(_ ext: String?) -> [String] {
    let e = (ext ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return e.isEmpty ? ["mp4", "m3u8"] : [e]
}

/// Hvem som spiller en adresse: Apples avspiller for filtypene den kan (med kontrollene til Apple), ellers VLC.
public enum PlayEngine: Sendable {
    case native, vlc
}

public struct PlayAttempt: Hashable, Sendable {
    public let url: URL
    public let engine: PlayEngine

    public init(_ url: URL, _ engine: PlayEngine) {
        self.url = url
        self.engine = engine
    }
}

/// Rekkefølgen adressene prøves i: hver med Apples avspiller når den kan filtypen, ellers med VLC. Er ingen av dem for
/// VLC, prøves den første med VLC til slutt (en mp4 med lyd Apple-enhetene ikke kan, for eksempel).
public func playAttempts(_ urls: [URL]) -> [PlayAttempt] {
    var attempts = urls.map { url in
        PlayAttempt(url, nativeExtensions.contains(url.pathExtension.lowercased()) ? .native : .vlc)
    }
    if !attempts.contains(where: { $0.engine == .vlc }), let first = urls.first {
        attempts.append(PlayAttempt(first, .vlc))
    }
    return attempts
}

// ── tolking ──

func rating(_ value: Any?) -> Double? {
    let s = text(value).replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
    guard let r = Double(s), r > 0 else { return nil }
    return min(r, 10)
}

/// Året fra «2021-05-03», «2021» eller navnet («Film (2021)»).
func year(_ values: Any?..., name: String = "") -> String? {
    for value in values {
        let s = text(value).trimmingCharacters(in: .whitespaces)
        if s.count >= 4, let y = Int(s.prefix(4)), (1900...2100).contains(y) { return String(y) }
    }
    if let r = name.range(of: #"\((19|20)\d\d\)"#, options: .regularExpression) {
        return String(name[r].dropFirst().dropLast())
    }
    return nil
}

func nonEmpty(_ value: Any?) -> String? {
    let s = text(value).trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? nil : s
}

/// backdrop_path er en liste med adresser (eller én adresse).
func firstURL(_ value: Any?) -> String? {
    if let list = value as? [Any] { return list.lazy.compactMap { nonEmpty($0) }.first }
    return nonEmpty(value)
}

/// Et navn fra leverandøren uten merkene på slutten, som i Fyrlys for Windows: «Matchbox the Movie [PRE] [2026]» gir
/// tittelen «Matchbox the Movie», merket «PRE» og året 2026. Bare merker i [ ] eller ( ) på slutten (høyst 24 tegn);
/// et år blir året (det siste), et navn som bare er et merke («[4K]»), står.
public struct CleanTitle: Hashable, Sendable {
    public let title: String
    public let tags: [String]
    public let year: String?
}

public func cleanTitle(_ raw: String) -> CleanTitle {
    let name = raw.trimmingCharacters(in: .whitespaces)
    var rest = name
    var tags: [String] = []
    var year: String?
    while let range = rest.range(of: #"\s*[\[(]([^\[\]()]{1,24})[\])]\s*$"#, options: .regularExpression),
          range.lowerBound > rest.startIndex {
        let tag = String(rest[range]).trimmingCharacters(in: .whitespaces).dropFirst().dropLast()
            .trimmingCharacters(in: .whitespaces)
        if tag.range(of: #"^(19|20)\d{2}$"#, options: .regularExpression) != nil {
            if year == nil { year = tag }
        } else if !tag.isEmpty {
            tags.insert(tag, at: 0)
        }
        rest = String(rest[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
    return CleanTitle(title: rest.isEmpty ? name : rest, tags: tags, year: year)
}

/// Tittelen på en episode uten serien og «S01E03» foran («Kysten - S01E03 - Tåka» blir «Tåka»); uten koden bare
/// seriens navn foran. Står ingenting igjen, den som den var.
public func cleanEpisodeTitle(_ raw: String, series: String) -> String {
    let title = raw.trimmingCharacters(in: .whitespaces)
    var rest = title
    if let range = rest.range(of: #"^.*?\bS\d{1,2}\s*E\d{1,3}\b[\s\-–:|.]*"#,
                              options: [.regularExpression, .caseInsensitive]) {
        rest = String(rest[range.upperBound...])
    } else if !series.isEmpty, rest.lowercased().hasPrefix(series.lowercased()) {
        rest = String(rest.dropFirst(series.count)).trimmingCharacters(in: CharacterSet(charactersIn: " -–:|."))
    }
    rest = rest.trimmingCharacters(in: .whitespaces)
    return rest.isEmpty ? title : rest
}

public func parseVODItems(_ json: Any, kind: VODKind) -> [VODItem] {
    var seen = Set<String>()
    return objectList(json).compactMap { v in
        let id = text(v[kind == .movies ? "stream_id" : "series_id"])
        let name = text(v["name"]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
        let poster = nonEmpty(v[kind == .movies ? "stream_icon" : "cover"])
        let r = rating(v["rating"]) ?? rating(v["rating_5based"]).map { $0 * 2 }
        let clean = cleanTitle(name)
        return VODItem(id: id, kind: kind, name: clean.title, poster: poster, categoryId: text(v["category_id"]),
                       rating: r, year: year(v["year"], v["releaseDate"], v["release_date"], name: name) ?? clean.year,
                       ext: nonEmpty(v["container_extension"]), tags: clean.tags.isEmpty ? nil : clean.tags,
                       added: int(v[kind == .movies ? "added" : "last_modified"]))
    }
}

/// Rekkefølgen på filmene eller seriene: som hos leverandøren (eller Plex), nyeste først (da de ble lagt til) eller
/// etter navnet.
public enum VODSort: String, CaseIterable, Sendable {
    case provider, newest, name
}

/// [items] i rekkefølgen [sort]; like (eller uten dato) står som hos leverandøren. Navnene som i en norsk ordbok
/// (æ, ø og å til slutt).
public func sortVOD(_ items: [VODItem], _ sort: VODSort) -> [VODItem] {
    switch sort {
    case .provider:
        return items
    case .newest:
        return items.enumerated().sorted { a, b in
            let x = a.element.added ?? 0, y = b.element.added ?? 0
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    case .name:
        let norsk = Locale(identifier: "nb_NO")
        return items.enumerated().sorted { a, b in
            switch a.element.name.compare(b.element.name, options: [.caseInsensitive], locale: norsk) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// «4K», «1080p», «720p» eller «SD» etter høyden på bildet.
func resolutionText(_ height: Int) -> String? {
    if height >= 2000 { return "4K" }
    if height >= 1000 { return "1080p" }
    if height >= 700 { return "720p" }
    return height > 0 ? "SD" : nil
}

func videoCodecText(_ codec: String) -> String? {
    switch codec.lowercased() {
    case "": return nil
    case "h264", "avc", "avc1": return "H.264"
    case "hevc", "h265", "hvc1", "hev1": return "H.265"
    case "av1": return "AV1"
    case "vp9": return "VP9"
    case "mpeg2video": return "MPEG-2"
    default: return codec.uppercased()
    }
}

func channelsText(_ channels: Int) -> String? {
    if channels >= 8 { return "7.1" }
    if channels >= 6 { return "5.1" }
    return channels == 2 ? "Stereo" : nil
}

/// Lydkodeken (ikke AAC, som nesten alt har).
func audioCodecText(_ codec: String) -> String? {
    switch codec.lowercased() {
    case "", "aac": return nil
    case "ac3": return "Dolby Digital"
    case "eac3": return "Dolby Digital+"
    case "truehd": return "Dolby TrueHD"
    case "dts", "dca": return "DTS"
    case "mp3", "flac", "opus": return codec.lowercased()
    default: return codec.uppercased()
    }
}

/// Kvaliteten i rekkefølge: oppløsningen, HDR, videokodeken, kanalene og lydkodeken.
func qualityBadges(height: Int?, hdr: Bool, video: String, channels: Int?, audio: String) -> [String] {
    [height.flatMap(resolutionText), hdr ? "HDR" : nil, videoCodecText(video), channels.flatMap(channelsText),
     audioCodecText(audio)].compactMap { $0 }
}

/// «12+» for et tall, ellers som den står («PG-13»); nil når den mangler.
func ageText(_ value: Any?) -> String? {
    guard let s = nonEmpty(value) else { return nil }
    if let n = Int(s), n >= 0 { return n == 0 ? nil : "\(n)+" }
    return s
}

/// Tekst som ikke sier noe («n/a», «not yet available», «-» …) er tom.
func meaningful(_ value: Any?) -> String? {
    guard let s = nonEmpty(value) else { return nil }
    let filler: Set<String> = ["n/a", "na", "none", "null", "tba", "tbd", "-", "--", "not yet available",
                               "coming soon", "no description", "unknown"]
    return filler.contains(s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))) ? nil : s
}

/// get_vod_info: {"info": {...}, "movie_data": {...}} (info kan være en tom liste).
public func parseMovieInfo(_ json: Any) -> VODDetails {
    let root = json as? [String: Any] ?? [:]
    let info = root["info"] as? [String: Any] ?? [:]
    let data = root["movie_data"] as? [String: Any] ?? [:]
    var d = VODDetails()
    d.plot = meaningful(info["plot"]) ?? meaningful(info["description"]) ?? ""
    d.genre = meaningful(info["genre"]) ?? ""
    d.cast = meaningful(info["cast"]) ?? meaningful(info["actors"]) ?? ""
    d.director = meaningful(info["director"]) ?? ""
    if let seconds = int(info["duration_secs"]), seconds > 0 {
        d.duration = minutesText(Int((Double(seconds) / 60).rounded()))
    } else {
        d.duration = durationText(nonEmpty(info["duration"]) ?? "")
    }
    d.year = year(info["releasedate"], info["release_date"], info["year"], name: text(data["name"]))
    d.backdrop = firstURL(info["backdrop_path"])
    d.poster = nonEmpty(info["movie_image"]) ?? nonEmpty(info["cover_big"])
    d.rating = rating(info["rating"])
    d.ext = nonEmpty(data["container_extension"])
    d.age = ageText(meaningful(info["age"]) ?? meaningful(info["mpaa_rating"]))
    d.country = meaningful(info["country"])
    let video = info["video"] as? [String: Any] ?? [:]
    let audio = info["audio"] as? [String: Any] ?? [:]
    let transfer = text(video["color_transfer"]).lowercased()
    d.quality = qualityBadges(height: int(video["height"]), hdr: transfer == "smpte2084" || transfer == "arib-std-b67",
                              video: text(video["codec_name"]), channels: int(audio["channels"]),
                              audio: text(audio["codec_name"]))
    return d
}

/// get_series_info: {"info": {...}, "episodes": {"1": [...], ...}} (episodene kan også være en liste med lister).
public func parseSeriesInfo(_ json: Any) -> VODDetails {
    let root = json as? [String: Any] ?? [:]
    let info = root["info"] as? [String: Any] ?? [:]
    var d = VODDetails()
    let series = cleanTitle(text(info["name"])).title
    d.plot = meaningful(info["plot"]) ?? ""
    d.genre = meaningful(info["genre"]) ?? ""
    d.cast = meaningful(info["cast"]) ?? ""
    d.director = meaningful(info["director"]) ?? ""
    d.year = year(info["releaseDate"], info["release_date"], name: text(info["name"]))
    d.backdrop = firstURL(info["backdrop_path"])
    d.poster = nonEmpty(info["cover"])
    d.rating = rating(info["rating"])

    var raw: [(Int, [[String: Any]])] = []
    if let map = root["episodes"] as? [String: Any] {
        for (key, value) in map { raw.append((Int(key) ?? 0, value as? [[String: Any]] ?? [])) }
    } else if let lists = root["episodes"] as? [Any] {
        for (i, value) in lists.enumerated() { raw.append((i + 1, value as? [[String: Any]] ?? [])) }
    }
    var seasons: [Season] = []
    for (number, list) in raw {
        let episodes: [Episode] = list.compactMap { e in
            let id = text(e["id"])
            guard !id.isEmpty else { return nil }
            let info = e["info"] as? [String: Any] ?? [:]
            let season = int(e["season"]) ?? number
            let n = int(e["episode_num"]) ?? 0
            return Episode(id: id, season: season, number: n,
                           title: nonEmpty(e["title"]).map { cleanEpisodeTitle($0, series: series) }
                               ?? L("Episode {n}", ["n": n]),
                           plot: meaningful(info["plot"]) ?? "",
                           duration: durationText(nonEmpty(info["duration"]) ?? ""),
                           image: nonEmpty(info["movie_image"]),
                           ext: nonEmpty(e["container_extension"]) ?? "mp4")
        }.sorted { $0.number < $1.number }
        if !episodes.isEmpty { seasons.append(Season(number: episodes[0].season, episodes: episodes)) }
    }
    d.seasons = seasons.sorted { seasonOrder($0.number) < seasonOrder($1.number) }
    return d
}

/// Rekkefølgen på sesongene: 1, 2, 3 … og spesialene (sesong 0) til slutt, som i Plex.
public func seasonOrder(_ number: Int) -> Int { number == 0 ? Int.max : number }

/// Episodene før og etter [current] i den rekkefølgen de ses: sesong for sesong, uten spesialene (sesong 0); ser du
/// en spesial, de andre spesialene. Neste etter den siste i en sesong er den første i neste sesong.
public func neighbours(of current: Episode, in seasons: [Season]) -> (previous: Episode?, next: Episode?) {
    let sorted = seasons.sorted { seasonOrder($0.number) < seasonOrder($1.number) }
    let special = current.season == 0
    let list = sorted.filter { special ? $0.number == 0 : $0.number != 0 }
        .flatMap { $0.episodes.sorted { $0.number < $1.number } }
    guard let i = list.firstIndex(where: { $0.id == current.id })
            ?? list.firstIndex(where: { $0.season == current.season && $0.number == current.number }) else {
        return (nil, nil)
    }
    return (i > 0 ? list[i - 1] : nil, i + 1 < list.count ? list[i + 1] : nil)
}

/// «1 t 32 min» eller «44 min».
public func minutesText(_ minutes: Int) -> String {
    let m = max(1, minutes)
    if m < 60 { return L("{n} min", ["n": m]) }
    return m % 60 == 0 ? L("{h} t", ["h": m / 60]) : L("{h} t {m} min", ["h": m / 60, "m": m % 60])
}

/// Lengden slik leverandøren skriver den («01:32:00») som «1 t 32 min»; annen tekst («45 min») står som den er.
public func durationText(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespaces)
    let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
    guard parts.count == 3, let h = parts[0], let m = parts[1], let s = parts[2], h >= 0, m >= 0, s >= 0 else {
        return t
    }
    let total = h * 60 + m + (s >= 30 ? 1 : 0)
    return total > 0 ? minutesText(total) : t
}

/// Søket i filmene eller seriene: alle ordene må stå i navnet (store og små bokstaver likt); de som begynner med det
/// som er skrevet, først.
public func searchVOD(_ query: String, in items: [VODItem], limit: Int = 200) -> [VODItem] {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    let words = q.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return [] }
    var first: [VODItem] = [], rest: [VODItem] = []
    for item in items {
        let name = item.name.lowercased()
        guard words.allSatisfy({ name.contains($0) }) else { continue }
        if name.hasPrefix(q) { first.append(item) } else { rest.append(item) }
        if first.count >= limit { break }
    }
    return Array((first + rest).prefix(limit))
}
