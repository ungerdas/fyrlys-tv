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
/// byttes). Fra IPTV-leverandøren, eller fra Plex (bibliotekene som kategorier, og «Fortsett å se», radene på Hjem og
/// søket fra Plex).
@MainActor
@Observable
final class VODModel {
    let kind: VODKind
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
    /// Plex: radene fra Hjem i Plex («Nytt fra …», «Nylig lagt til …»), vist under «Hjem» øverst i sidemenyen
    private(set) var rows: [VODRow] = []
    /// Plex: favorittene slik serveren har dem nå (plakatene, «sett»)
    private(set) var favoriteRow: [VODItem] = []

    /// «Hjem» først i sidemenyen og menyen: «Fortsett å se», favorittene og radene
    static let home = "hjem"
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

    init(kind: VODKind) {
        self.kind = kind
    }

    func reset(_ backend: VODBackend?) {
        generation += 1
        version += 1
        categoriesTask?.cancel()
        categoriesTask = nil
        self.backend = backend
        if case .plex = backend { isPlex = true } else { isPlex = false }
        categories = []
        items = [:]
        continueRow = []
        rows = []
        favoriteRow = []
        allItems = nil
        loadingCategories = false
        loadingItems = []
        loaded = false
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
                found = categories.isEmpty ? [] : [ChannelCategory(id: Self.home, name: L("Hjem"))] + categories
            case .plex(let client):
                // «Fortsett å se» samtidig med bibliotekene og radene (før etter hverandre)
                let kind = kind
                let resumeTask = Task { (try? await client.continueWatching(kind)) ?? [] }
                let libraries: [ChannelCategory]
                do {
                    libraries = try await client.libraries(kind)
                } catch {
                    resumeTask.cancel()
                    throw error
                }
                let home = (try? await client.rows(kind, libraries: libraries.map(\.id))) ?? []
                let resume = await resumeTask.value
                // avbrutt (en ny henting har tatt over): ikke tomme rader i stedet for dem som kommer
                guard gen == generation, !Task.isCancelled else { return }
                continueRow = resume
                rows = home
                found = libraries.isEmpty ? [] : [ChannelCategory(id: Self.home, name: L("Hjem"))] + libraries
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
        loadingItems.insert(category)
        do {
            let found: [VODItem]
            switch backend {
            case .xtream(let client): found = try await client.vodItems(kind, category: category)
            case .plex(let client): found = try await client.items(kind, library: category)
            default: found = []
            }
            guard gen == generation else { return }
            items[category] = found
            error = nil
        } catch {
            guard gen == generation else { return }
            // avbrutt fordi siden ble lukket eller tegnet på nytt: ingen feil, den hentes neste gang
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        loadingItems.remove(category)
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
            let found: [VODItem]?
            switch backend {
            case .xtream(let client): found = try? await client.vodItems(kind, category: shown)
            case .plex(let client): found = try? await client.items(kind, library: shown)
            default: found = nil
            }
            guard gen == generation else { return }
            // de andre kategoriene hentes på nytt når de velges
            items = items.filter { $0.key == shown }
            if let found { items[shown] = found }
        }
    }

    /// Plex: «Fortsett å se» og radene på nytt (etter at noe er sett).
    func refreshContinue() async {
        guard case .plex(let client) = backend else { return }
        let gen = generation
        guard let resume = try? await client.continueWatching(kind), gen == generation else { return }
        continueRow = resume
        let libraries = categories.map(\.id).filter { $0 != Self.home }
        guard let home = try? await client.rows(kind, libraries: libraries), gen == generation else { return }
        rows = home
    }

    /// Plex: favorittene ([stored], lagret som id og navn) slik serveren har dem nå, i samme rekkefølge. Det som er
    /// lagret, vises med en gang (uten plakat til svaret kommer).
    func refreshFavorites(_ stored: [VODItem]) async {
        guard case .plex(let client) = backend else {
            favoriteRow = []
            return
        }
        let known = Dictionary(favoriteRow.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        favoriteRow = stored.map { known[$0.id] ?? $0 }
        guard !stored.isEmpty else { return }
        let gen = generation
        guard let found = try? await client.items(ids: stored.map(\.id), kind: kind), gen == generation,
              !Task.isCancelled else { return }
        favoriteRow = found
    }

    /// Plex: hele raden («Se alle»).
    func rowItems(_ row: VODRow) async -> [VODRowItem] {
        guard case .plex(let client) = backend else { return row.items }
        return (try? await client.rowItems(row, kind: kind)) ?? row.items
    }

    /// Søket: Plex søker selv; hos IPTV-leverandøren hentes alle filmene eller seriene første gang, og søket går i
    /// navnene.
    func search(_ query: String) async throws -> [VODItem] {
        switch backend {
        case .plex(let client):
            return try await client.search(query, kind: kind)
        case .xtream(let client):
            let all: [VODItem]
            if let allItems {
                all = allItems
            } else {
                let gen = generation
                all = try await client.allVODItems(kind)
                if gen == generation { allItems = all }
            }
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
