import FyrlysCore
import Foundation
import Observation

/// Hvor filmene og seriene kommer fra.
enum VODBackend {
    case xtream(XtreamClient)
    case plex(PlexClient)
    /// Plex er valgt, men kobler til
    case waiting
    /// Plex er valgt, men svarer ikke (forklaringen)
    case unavailable(String)
}

/// Filmene eller seriene: kategoriene (hentes første gang fanen vises) med «Hjem» først, kategorien som er valgt, og
/// lista for hver kategori (hentes når den velges eller vises som rad på Hjem, og huskes til innloggingen eller kilden
/// byttes). Fanene Filmer og Serier fra IPTV-leverandøren, og Plex-fanen med filmer og serier sammen (bibliotekene som
/// kategorier, og «Fortsett å se», radene på Hjem og søket fra Plex).
@MainActor
@Observable
final class VODModel {
    /// filmer eller serier (IPTV-leverandøren), eller begge (Plex-fanen)
    let kinds: Set<VODKind>
    /// filmer eller serier (Filmer og Serier); i Plex-fanen bibliotekene hver for seg (`kind(of:)`)
    var kind: VODKind { kinds.contains(.movies) ? .movies : .series }
    /// Plex-fanen: filmer og serier sammen
    var mixed: Bool { kinds.count > 1 }
    private(set) var categories: [ChannelCategory] = []
    private(set) var items: [String: [VODItem]] = [:]
    private(set) var loadingCategories = false
    private(set) var loadingItems: Set<String> = []
    /// kategoriene er hentet (tom liste = leverandøren har ingen)
    private(set) var loaded = false
    private(set) var error: String?
    /// kategorien som vises
    var chosen: String?
    /// filmene og seriene kommer fra Plex
    private(set) var isPlex = false
    /// Plex: «Fortsett å se» fra Plex
    private(set) var continueRow: [VODResume] = []
    /// Plex: radene fra Hjem i Plex («Nytt fra …», «Nylig lagt til …»), vist under «Hjem» øverst i sidemenyen; med en
    /// egen rekkefølge på bibliotekene står radene i den rekkefølgen (som i Plex når bibliotekene flyttes)
    private(set) var rows: [VODRow] = []
    /// Plex: radene slik Plex sendte dem
    @ObservationIgnored private var plexRows: [VODRow] = []
    /// Plex: rekkefølgen som er valgt på bibliotekene (tom: som i Plex)
    @ObservationIgnored private var order: [String] = []
    /// Plex: favorittene slik serveren har dem nå (plakatene, «sett»)
    private(set) var favoriteRow: [VODItem] = []

    /// «Hjem» først i sidemenyen og menyen: «Fortsett å se», favorittene og radene
    static let home = "hjem"
    /// IPTV: «Alle filmer» eller «Alle serier» etter «Hjem» (hentes når den velges, eller for søket og «Nylig lagt til»)
    static let all = "alle"
    /// IPTV: rekkefølgen i kategoriene (i minnet til appen lukkes, som i Fyrlys for Windows)
    private(set) var sort: VODSort = .provider
    /// IPTV: kategoriene sortert (det tar litt tid med mange tusen, så det gjøres utenfor hovedtråden)
    private(set) var sorted: [String: (sort: VODSort, items: [VODItem])] = [:]
    /// IPTV: «Nylig lagt til» på Hjem (de 24 nyeste av alle); nil til de er hentet, tom når leverandøren ikke sier når
    /// noe ble lagt til
    private(set) var recent: [VODItem]?
    /// Plex: rekkefølgen i hvert bibliotek (i minnet), og hvor mange det er i alt (flere sider hentes når de nederste
    /// plakatene vises)
    private(set) var plexSorts: [String: PlexSort] = [:]
    private(set) var totals: [String: Int] = [:]
    /// telles opp når kilden byttes (fanen henter kategoriene på nytt)
    private(set) var version = 0
    /// «Prøv igjen» når Plex ikke svarer
    @ObservationIgnored var reconnect: (() -> Void)?

    @ObservationIgnored private var backend: VODBackend?
    @ObservationIgnored private var generation = 0
    /// hentingen av kategoriene som pågår (eies av modellen, se `loadCategories`)
    @ObservationIgnored private var categoriesTask: Task<Void, Never>?
    /// da kategoriene sist ble hentet (hentes på nytt når appen kommer fram etter en halvtime)
    @ObservationIgnored private var loadedAt: Date?
    /// IPTV-leverandøren: alle filmene eller seriene, hentet første gang det søkes
    @ObservationIgnored private var allItems: [VODItem]?
    /// hentingen av alle som pågår (søket, «Alle» og «Nylig lagt til» venter på den samme)
    @ObservationIgnored private var allTask: Task<[VODItem], Error>?
    /// telles opp per kategori når rekkefølgen byttes, så et sent svar for den forrige ikke brukes
    @ObservationIgnored private var requests: [String: Int] = [:]
    @ObservationIgnored private var loadingMore: Set<String> = []
    /// sett ferdig mens appen har vært åpen (nøklene for hvor langt): begynner fra start neste gang, selv om Plex ikke
    /// har fått med seg det ennå
    @ObservationIgnored var finishedHere: Set<String> = []

    init(kind: VODKind) {
        kinds = [kind]
    }

    init(kinds: Set<VODKind>) {
        self.kinds = kinds
    }

    /// Plex: om bibliotekene har filmer eller serier
    private(set) var libraryKinds: [String: VODKind] = [:]

    /// Filmer eller serier i [category] (et bibliotek i Plex-fanen).
    func kind(of category: String) -> VODKind { libraryKinds[category] ?? kind }

    /// Plex: bibliotekene som ikke vises (sidemenyen, Hjem, «Fortsett å se» og søket)
    @ObservationIgnored private var hidden: Set<String> = []

    func reset(_ backend: VODBackend?, hidden: Set<String> = [], order: [String] = []) {
        generation += 1
        version += 1
        self.hidden = hidden
        self.order = order
        categoriesTask?.cancel()
        categoriesTask = nil
        self.backend = backend
        if case .plex = backend { isPlex = true } else { isPlex = false }
        categories = []
        libraryKinds = [:]
        items = [:]
        continueRow = []
        rows = []
        plexRows = []
        favoriteRow = []
        allItems = nil
        allTask?.cancel()
        allTask = nil
        sorted = [:]
        recent = nil
        plexSorts = [:]
        totals = [:]
        requests = [:]
        loadingMore = []
        loadingCategories = false
        loadingItems = []
        loaded = false
        hiddenAll = false
        error = nil
        if case .unavailable(let message) = backend { error = message }
        chosen = nil
    }

    /// Henter kategoriene (med Plex også «Fortsett å se» og radene). Hentingen eies av modellen, ikke av fanen som ba om
    /// den: avbrytes fanens oppgave (fanen tegnes på nytt eller lukkes), fortsetter hentingen, og en ny venter på den.
    /// Før kunne et avbrudd midt i gi tomme rader (feilene der svelges) eller «Får ikke kontakt», og en ny henting ble
    /// stoppet av den som pågikk.
    func loadCategories(force: Bool = false) async {
        guard let backend, force || !loaded else { return }
        if force {
            switch backend {
            case .unavailable:
                reconnect?()
            case .plex where error != nil:
                // Plex svarte ikke: let etter adressen som svarer nå (hjemme eller ute); fanen hentes på nytt etterpå
                reconnect?()
                return
            default:
                break
            }
        }
        if let running = categoriesTask {
            if !force {
                await running.value
                return
            }
            running.cancel()
        }
        let gen = generation
        let task = Task { await fetchCategories(gen) }
        categoriesTask = task
        await task.value
        if gen == generation, categoriesTask == task { categoriesTask = nil }
    }

    private func fetchCategories(_ gen: Int) async {
        guard let backend else { return }
        let found: [ChannelCategory]
        loadingCategories = true
        defer { if gen == generation { loadingCategories = false } }
        do {
            switch backend {
            case .xtream(let client):
                let categories = try await client.vodCategories(kind)
                let all = ChannelCategory(id: Self.all, name: kind == .movies ? L("Alle filmer") : L("Alle serier"))
                found = categories.isEmpty ? [] : [ChannelCategory(id: Self.home, name: L("Hjem")), all] + categories
            case .plex(let client):
                // «Fortsett å se» samtidig med bibliotekene og radene (før etter hverandre)
                let kinds = kinds
                let resumeTask = Task { (try? await client.continueWatching(kinds)) ?? [] }
                let sections: [PlexSection]
                do {
                    sections = try await client.sections().filter { kinds.contains($0.kind) }
                } catch {
                    resumeTask.cancel()
                    throw error
                }
                let shown = ordered(sections.filter { !hidden.contains($0.id) }) { $0.id }
                let home = shown.isEmpty ? [] : ((try? await client.rows(kinds, libraries: shown.map(\.id))) ?? [])
                let resume = await resumeTask.value
                // avbrutt (en ny henting har tatt over): ikke tomme rader i stedet for dem som kommer
                guard gen == generation, !Task.isCancelled else { return }
                libraryKinds = Dictionary(sections.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
                continueRow = visible(resume)
                plexRows = visible(home)
                rows = arranged(plexRows)
                hiddenAll = !sections.isEmpty && shown.isEmpty
                found = shown.isEmpty ? []
                    : [ChannelCategory(id: Self.home, name: L("Hjem"))]
                        + shown.map { ChannelCategory(id: $0.id, name: $0.name) }
            case .waiting:
                return
            case .unavailable(let message):
                error = message
                return
            }
            guard gen == generation, !Task.isCancelled else { return }
            categories = found
            loaded = true
            loadedAt = Date()
            error = nil
            if chosen == nil || !found.contains(where: { $0.id == chosen }) { chosen = found.first?.id }
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func load(_ category: String) async {
        guard let backend, category != Self.home, items[category] == nil, !loadingItems.contains(category) else {
            return
        }
        let gen = generation
        let request = requests[category] ?? 0
        loadingItems.insert(category)
        defer { if gen == generation, request == requests[category] ?? 0 { loadingItems.remove(category) } }
        do {
            let found: [VODItem]
            var total: Int?
            switch backend {
            case .xtream(let client):
                found = category == Self.all ? try await everything(client)
                    : try await client.vodItems(kind, category: category)
            case .plex(let client):
                // en side om gangen (store bibliotek), i rekkefølgen som er valgt
                let page = try await client.page(kind(of: category), library: category, sort: plexSort(category),
                                                 genre: nil, start: 0)
                found = page.items
                total = page.total
            default:
                found = []
            }
            guard gen == generation, request == requests[category] ?? 0 else { return }
            items[category] = found
            totals[category] = total
            error = nil
        } catch {
            guard gen == generation, request == requests[category] ?? 0 else { return }
            // avbrutt fordi siden ble lukket eller tegnet på nytt: ingen feil, den hentes neste gang
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// IPTV: alle filmene eller seriene (én henting, som søket, «Alle» og «Nylig lagt til» deler).
    private func everything(_ client: XtreamClient) async throws -> [VODItem] {
        if let allItems { return allItems }
        if let allTask { return try await allTask.value }
        let gen = generation
        let kind = kind
        let task = Task { try await client.allVODItems(kind) }
        allTask = task
        do {
            let all = try await task.value
            if gen == generation {
                allItems = all
                allTask = nil
            }
            return all
        } catch {
            if gen == generation { allTask = nil }
            throw error
        }
    }

    /// IPTV: «Nylig lagt til» på Hjem: de 24 nyeste av alle (hentes første gang Hjem vises).
    func loadRecent() async {
        guard case .xtream(let client) = backend, recent == nil else { return }
        let gen = generation
        guard let all = try? await everything(client), gen == generation else { return }
        let newest = await Task.detached(priority: .userInitiated) {
            all.contains { $0.added != nil } ? Array(sortVOD(all, .newest).prefix(24)) : []
        }.value
        if gen == generation { recent = newest }
    }

    // ── rekkefølgen ──

    /// IPTV: en annen rekkefølge; kategoriene som er hentet, sorteres utenfor hovedtråden.
    func setSort(_ new: VODSort) {
        guard new != sort else { return }
        sort = new
    }

    /// Plakatene i [category] slik de vises: hos leverandøren i rekkefølgen som er valgt (når den er sortert; til da
    /// som hos leverandøren), hos Plex slik serveren sorterte dem.
    func shown(_ category: String) -> [VODItem]? {
        guard let list = items[category] else { return nil }
        guard !isPlex, sort != .provider else { return list }
        if let done = sorted[category], done.sort == sort, done.items.count == list.count { return done.items }
        return list
    }

    /// Sorterer [category] i rekkefølgen som er valgt (kalles av siden når kategorien eller rekkefølgen endres).
    func prepareSorted(_ category: String) async {
        guard !isPlex, sort != .provider, let list = items[category] else { return }
        if let done = sorted[category], done.sort == sort, done.items.count == list.count { return }
        let want = sort, gen = generation
        let result = await Task.detached(priority: .userInitiated) { sortVOD(list, want) }.value
        guard gen == generation, want == sort else { return }
        sorted[category] = (want, result)
    }

    func plexSort(_ category: String) -> PlexSort { plexSorts[category] ?? .added }

    /// Plex: en annen rekkefølge i biblioteket: hentes på nytt fra starten.
    func setPlexSort(_ new: PlexSort, for category: String) {
        guard new != plexSort(category) else { return }
        plexSorts[category] = new
        restart(category)
    }

    private func restart(_ category: String) {
        requests[category, default: 0] += 1
        items[category] = nil
        totals[category] = nil
        loadingItems.remove(category)
        loadingMore.remove(category)
        Task { await load(category) }
    }

    /// Plex: det er flere i biblioteket enn de som er hentet.
    func hasMore(_ category: String) -> Bool {
        guard isPlex, let have = items[category]?.count, let total = totals[category] else { return false }
        return have < total
    }

    /// Plex: neste side (100), når de nederste plakatene vises. En tom side avslutter (uansett hva Plex sa om antallet).
    func loadMore(_ category: String) async {
        guard case .plex(let client) = backend, let have = items[category], hasMore(category),
              !loadingMore.contains(category) else { return }
        let gen = generation, request = requests[category] ?? 0
        loadingMore.insert(category)
        defer { if gen == generation, request == requests[category] ?? 0 { loadingMore.remove(category) } }
        guard let page = try? await client.page(kind(of: category), library: category, sort: plexSort(category),
                                                genre: nil, start: have.count),
              gen == generation, request == requests[category] ?? 0, let now = items[category] else { return }
        var seen = Set(now.map(\.id))
        let more = page.items.filter { seen.insert($0.id).inserted }
        items[category] = now + more
        totals[category] = more.isEmpty ? now.count : page.total
    }

    /// IPTV: «Mer fra <kategori>» på siden for en film eller serie: de første i kategorien (som hos leverandøren), uten
    /// den selv.
    func moreFrom(_ item: VODItem) async -> (title: String, items: [VODItem]) {
        guard !item.isPlex, !item.categoryId.isEmpty else { return ("", []) }
        await load(item.categoryId)
        let list = (items[item.categoryId] ?? []).filter { $0.id != item.id }.prefix(24)
        let name = cleanTitle(self.name(item.categoryId)).title
        return (name.isEmpty ? L("Mer som dette") : L("Mer fra {category}", ["category": name]), Array(list))
    }

    func details(_ item: VODItem) async throws -> VODDetails {
        switch backend {
        case .xtream(let client): return try await client.vodDetails(item)
        case .plex(let client): return try await client.details(item)
        default: throw SourceError(L("Ikke logget inn"))
        }
    }

    /// Appen er framme igjen: er det en halvtime siden sist, hentes «Fortsett å se», radene og kategorien som vises
    /// på nytt (nye filmer fra serveren, det som er sett på andre enheter), de andre når de vises igjen.
    func refreshIfOld() {
        guard loaded, let at = loadedAt, Date().timeIntervalSince(at) > 1800, let backend else { return }
        loadedAt = Date()
        let gen = generation
        let shown = chosen
        Task {
            await refreshContinue()
            guard let shown, shown != Self.home, gen == generation else { return }
            var found: [VODItem]?
            var total: Int?
            switch backend {
            case .xtream(let client):
                if shown == Self.all {
                    allItems = nil
                    found = try? await everything(client)
                } else {
                    found = try? await client.vodItems(kind, category: shown)
                }
            case .plex(let client):
                let page = try? await client.page(kind(of: shown), library: shown, sort: plexSort(shown),
                                                  genre: nil, start: 0)
                found = page?.items
                total = page?.total
            default:
                found = nil
            }
            guard gen == generation else { return }
            // de andre kategoriene hentes på nytt når de velges
            items = items.filter { $0.key == shown }
            totals = totals.filter { $0.key == shown }
            sorted = [:]
            recent = nil
            if let found {
                items[shown] = found
                totals[shown] = total
            }
        }
    }

    /// Plex: «Fortsett å se» og radene på nytt (etter at noe er sett).
    func refreshContinue() async {
        guard case .plex(let client) = backend else { return }
        let gen = generation
        guard let resume = try? await client.continueWatching(kinds), gen == generation else { return }
        continueRow = visible(resume)
        let libraries = categories.map(\.id).filter { $0 != Self.home }
        guard let home = try? await client.rows(kinds, libraries: libraries), gen == generation else { return }
        plexRows = visible(home)
        rows = arranged(plexRows)
    }

    // ── Plex: rekkefølgen på bibliotekene ──

    /// Plex: bibliotekene i en annen rekkefølge (sidemenyen og radene på Hjem), uten å hente noe på nytt.
    func setOrder(_ order: [String]) {
        guard order != self.order else { return }
        self.order = order
        guard isPlex, !categories.isEmpty else { return }
        let libraries = ordered(categories.filter { $0.id != Self.home }) { $0.id }
        categories = categories.filter { $0.id == Self.home } + libraries
        rows = arranged(plexRows)
    }

    /// [items] i rekkefølgen som er valgt på bibliotekene ([library] gir biblioteket); de som ikke er med der, står etter
    /// i den rekkefølgen de hadde.
    private func ordered<T>(_ items: [T], library: (T) -> String) -> [T] {
        guard !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { a, b in
            let ra = rank[library(a.element)] ?? Int.max, rb = rank[library(b.element)] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Radene fra Plex med bibliotekene i rekkefølgen som er valgt (uten valgt rekkefølge: som Plex sendte dem).
    private func arranged(_ rows: [VODRow]) -> [VODRow] {
        ordered(rows) { row in
            // biblioteket det meste i raden kommer fra
            var count: [String: Int] = [:]
            for entry in row.items where !entry.item.categoryId.isEmpty { count[entry.item.categoryId, default: 0] += 1 }
            return count.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
        }
    }

    /// Plex: alle bibliotekene er skjult (siden sier det, med valget av bibliotekene)
    private(set) var hiddenAll = false

    /// Uten det som er fra et skjult bibliotek (det uten bibliotek, står).
    private func visible(_ items: [VODResume]) -> [VODResume] {
        hidden.isEmpty ? items : items.filter { !hidden.contains($0.item.categoryId) }
    }

    private func visible(_ items: [VODItem]) -> [VODItem] {
        hidden.isEmpty ? items : items.filter { !hidden.contains($0.categoryId) }
    }

    private func visible(_ rows: [VODRow]) -> [VODRow] {
        guard !hidden.isEmpty else { return rows }
        return rows.compactMap { row in
            let items = row.items.filter { !hidden.contains($0.item.categoryId) }
            return items.isEmpty ? nil : VODRow(id: row.id, title: row.title, items: items, key: row.key, more: row.more)
        }
    }

    /// Plex: favorittene ([stored], lagret som id og navn; filmer og serier) slik serveren har dem nå, i samme
    /// rekkefølge. Det som er lagret, vises med en gang (uten plakat til svaret kommer).
    func refreshFavorites(_ stored: [VODItem]) async {
        guard case .plex(let client) = backend else {
            favoriteRow = []
            return
        }
        let known = Dictionary(favoriteRow.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        favoriteRow = stored.map { known[$0.id] ?? $0 }
        guard !stored.isEmpty else { return }
        let gen = generation
        guard let found = try? await client.items(ids: stored.map(\.id), kinds: kinds), gen == generation,
              !Task.isCancelled else { return }
        favoriteRow = found
    }

    /// Plex: hele raden («Se alle»).
    func rowItems(_ row: VODRow) async -> [VODRowItem] {
        guard case .plex(let client) = backend else { return row.items }
        let all = (try? await client.rowItems(row, kinds: kinds)) ?? row.items
        return hidden.isEmpty ? all : all.filter { !hidden.contains($0.item.categoryId) }
    }

    /// Søket: Plex søker selv (filmer og serier i Plex-fanen); hos IPTV-leverandøren hentes alle filmene eller seriene
    /// første gang, og søket går i navnene.
    func search(_ query: String) async throws -> [VODItem] {
        switch backend {
        case .plex(let client):
            return visible(try await client.search(query, kinds: kinds))
        case .xtream(let client):
            let all = try await everything(client)
            return await Task.detached(priority: .userInitiated) { searchVOD(query, in: all) }.value
        default:
            return []
        }
    }

    /// Plex: episoden med fila (i radene mangler den noen ganger).
    func withFile(_ episode: Episode) async -> Episode {
        guard episode.fileKey == nil, case .plex(let client) = backend,
              let full = try? await client.episode(episode.id) else { return episode }
        return full
    }

    /// Det som spilles for en episode av [show]: fila (hos Plex hentes den når den mangler), adressene og hvor den
    /// begynner: der du slapp (det enheten vet; ellers det Plex vet, også fra de andre Plex-appene), og fra start når
    /// den er sett ferdig her. nil: ingen fil.
    func play(_ episode: Episode, show: VODItem, app: AppModel, image: String?, seasons: [Season]?) async -> VODPlay? {
        let full = await withFile(episode)
        let urls = episodeURLs(full)
        guard !urls.isEmpty else { return nil }
        let key = full.progressKey
        let saved = app.progress(key)
        let start = saved > 0 ? saved : (finishedHere.contains(key) ? 0 : full.resume)
        let subtitle = L("Sesong {s}, episode {e}", ["s": full.season, "e": full.number]) + ": " + full.title
        return VODPlay(id: key, urls: urls, title: show.name, subtitle: subtitle, progressKey: key, start: start,
                       item: show, plex: full.source == "plex" ? full.id : nil, episode: full, image: image,
                       seasons: seasons)
    }

    /// Plex: markørene og undertekstfilene for en film eller episode (nil: ikke Plex, eller serveren svarte ikke).
    func playInfo(_ ratingKey: String) async -> PlexPlayInfo? {
        guard case .plex(let client) = backend else { return nil }
        return try? await client.playInfo(ratingKey)
    }

    /// Plex: merk en film, serie eller episode som sett eller ikke sett på serveren.
    func setWatched(_ ratingKey: String, _ watched: Bool) async throws {
        guard case .plex(let client) = backend else { return }
        try await client.setWatched(ratingKey, watched)
    }

    /// Plex: «Mer som dette» (tom når det ikke er noe, eller serveren ikke svarte).
    func related(_ item: VODItem) async -> [VODItem] {
        guard item.isPlex, case .plex(let client) = backend else { return [] }
        return (try? await client.related(item)) ?? []
    }

    /// Adressene til en film, i den rekkefølgen de prøves.
    func movieURLs(_ item: VODItem, _ details: VODDetails?) -> [URL] {
        switch backend {
        case .xtream(let client):
            return playableExtensions(details?.ext ?? item.ext).map { client.movieURL(item.id, ext: $0) }
        case .plex(let client):
            return details?.fileKey.flatMap(client.fileURL).map { [$0] } ?? []
        default:
            return []
        }
    }

    func episodeURLs(_ episode: Episode) -> [URL] {
        switch backend {
        case .xtream(let client):
            return playableExtensions(episode.ext).map { client.episodeURL(episode, ext: $0) }
        case .plex(let client):
            return episode.fileKey.flatMap(client.fileURL).map { [$0] } ?? []
        default:
            return []
        }
    }

    func name(_ category: String?) -> String {
        categories.first { $0.id == category }?.name ?? ""
    }
}
