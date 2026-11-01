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
    /// telles opp når kilden byttes (fanen henter kategoriene på nytt)
    private(set) var version = 0
    /// «Prøv igjen» når Plex ikke svarer
    @ObservationIgnored var reconnect: (() -> Void)?

    @ObservationIgnored private var backend: VODBackend?
    @ObservationIgnored private var generation = 0

    init(kind: VODKind) {
        self.kind = kind
    }

    func reset(_ backend: VODBackend?) {
        generation += 1
        version += 1
        self.backend = backend
        if case .plex = backend { isPlex = true } else { isPlex = false }
        categories = []
        items = [:]
        continueRow = []
        loadingCategories = false
        loadingItems = []
        loaded = false
        error = nil
        if case .unavailable(let message) = backend { error = message }
        chosen = nil
    }

    func loadCategories(force: Bool = false) async {
        guard let backend, !loadingCategories, force || !loaded else { return }
        let gen = generation
        let found: [ChannelCategory]
        loadingCategories = true
        defer { if gen == generation { loadingCategories = false } }
        do {
            switch backend {
            case .xtream(let client):
                found = try await client.vodCategories(kind)
            case .plex(let client):
                found = try await client.libraries(kind)
                let resume = (try? await client.continueWatching(kind)) ?? []
                guard gen == generation else { return }
                continueRow = resume
            case .waiting:
                return
            case .unavailable(let message):
                error = message
                if force { reconnect?() }
                return
            }
            guard gen == generation else { return }
            categories = found
            loaded = true
            error = nil
            if chosen == nil || !found.contains(where: { $0.id == chosen }) { chosen = found.first?.id }
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func load(_ category: String) async {
        guard let backend, items[category] == nil, !loadingItems.contains(category) else { return }
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
            self.error = error.localizedDescription
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

    /// Plex: «Fortsett å se» på nytt (etter at noe er sett).
    func refreshContinue() async {
        guard case .plex(let client) = backend else { return }
        let gen = generation
        guard let resume = try? await client.continueWatching(kind), gen == generation else { return }
        continueRow = resume
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
