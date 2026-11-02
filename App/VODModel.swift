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

/// Filmene eller seriene: kategoriene (hentes første gang fanen vises), kategorien som er valgt, og lista for hver
/// kategori (hentes når den velges, og huskes til innloggingen eller kilden byttes). Fra IPTV-leverandøren, eller
/// fra Plex (bibliotekene som kategorier, og «Fortsett å se» fra Plex).
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
    private(set) var continueRow: [VODItem] = []
    /// Plex: radene fra Hjem i Plex («Nytt fra …», «Nylig lagt til …»), vist under «Hjem» øverst i sidemenyen
    private(set) var rows: [VODRow] = []

    /// «Hjem» i sidemenyen (Plex)
    static let home = "hjem"
    /// telles opp når kilden byttes (fanen henter kategoriene på nytt)
    private(set) var version = 0
    /// «Prøv igjen» når Plex ikke svarer
    @ObservationIgnored var reconnect: (() -> Void)?

    @ObservationIgnored private var backend: VODBackend?
    @ObservationIgnored private var generation = 0
    /// hentingen av kategoriene som pågår (eies av modellen, se `loadCategories`)
    @ObservationIgnored private var categoriesTask: Task<Void, Never>?

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
        if case .unavailable = backend, force { reconnect?() }
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
                found = try await client.vodCategories(kind)
            case .plex(let client):
                let libraries = try await client.libraries(kind)
                let resume = (try? await client.continueWatching(kind)) ?? []
                let home = (try? await client.rows(kind, libraries: libraries.map(\.id))) ?? []
                // avbrutt (en ny henting har tatt over): ikke tomme rader i stedet for dem som kommer
                guard gen == generation, !Task.isCancelled else { return }
                continueRow = resume
                rows = home
                found = (resume.isEmpty && home.isEmpty ? [] : [ChannelCategory(id: Self.home, name: L("Hjem"))])
                    + libraries
            case .waiting:
                return
            case .unavailable(let message):
                error = message
                return
            }
            guard gen == generation, !Task.isCancelled else { return }
            categories = found
            loaded = true
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
