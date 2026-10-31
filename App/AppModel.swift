import FyrlysCore
import Foundation
import Observation

/// Tilstanden i appen: innloggingen, kategoriene og kanalene, favoritter, favorittkategorier og «sist sett», og
/// abonnementet.
@MainActor
@Observable
final class AppModel {
    enum Phase { case starting, signedOut, ready }

    var phase: Phase = .starting
    private(set) var login: Login?
    private(set) var client: XtreamClient?
    /// kategoriene og kanalene med oppslagene (lages i bakgrunnen og byttes bare når lista er endret)
    private(set) var index = ChannelIndex.empty
    /// alle kanalene, med kanalene i favorittkategoriene først
    private(set) var allChannels: [Channel] = []
    private(set) var account: Account?
    var loading = false
    var error: String?

    /// telles opp når favoritter, favorittkategorier eller «sist sett» endres (Library er ikke observerbar selv)
    private(set) var libraryVersion = 0
    @ObservationIgnored private var library: Library?

    let programs = ProgramStore()
    private let cache = TestSupport.listCache
    private let defaults = TestSupport.defaults
    /// lista er forsøkt hentet minst én gang (før det vises «Henter kanalene …» når den er tom)
    private(set) var triedOnce = false
    /// økes for hver innlogging og utlogging, så svar for en tidligere innlogging ikke brukes
    @ObservationIgnored private var generation = 0
    /// innloggingen (generation) listene hentes for akkurat nå
    @ObservationIgnored private var loadingFor: Int?

    var categories: [ChannelCategory] { index.categories }
    var channels: [Channel] { index.channels }
    var byId: [String: Channel] { index.byId }
    func channels(in categoryId: String) -> [Channel] { index.channels(in: categoryId) }

    // ── innlogging ──

    func start() {
        guard phase == .starting else { return }
        if TestSupport.isActive {
            if TestSupport.screen != "login", let test = TestSupport.login {
                use(test)
            } else {
                phase = .signedOut
            }
        } else if let saved = Keychain.load() {
            use(saved)
        } else {
            phase = .signedOut
        }
    }

    /// Logger inn (sjekker innloggingen hos leverandøren først).
    func signIn(server: String, username: String, password: String) async throws {
        let login = Login(server: server, username: username, password: password)
        let client = XtreamClient(login: login)
        let account = try await client.account()
        if !account.status.isEmpty && account.status.lowercased() != "active" {
            throw SourceError(L("Abonnementet er ikke aktivt ({status})", ["status": account.status]))
        }
        if !TestSupport.isActive { Keychain.save(login) }
        use(login)
        self.account = account
    }

    func signOut() {
        if let login { cache.remove(login.id) }
        if !TestSupport.isActive { Keychain.delete() }
        generation += 1
        loadingFor = nil
        loading = false
        login = nil
        client = nil
        library = nil
        libraryVersion += 1
        account = nil
        index = .empty
        allChannels = []
        programs.reset(client: nil)
        phase = .signedOut
    }

    private func use(_ login: Login) {
        generation += 1
        let gen = generation
        self.login = login
        let client = XtreamClient(login: login)
        self.client = client
        triedOnce = false
        error = nil
        index = .empty
        allChannels = []
        library = Library(store: defaults, loginId: login.id)
        libraryVersion += 1
        programs.reset(client: client)
        let cache = cache
        let id = login.id
        Task {
            // lista fra sist leses og pakkes ut i bakgrunnen: med titusenvis av kanaler sto appen ellers stille imens
            let saved = await Task.detached(priority: .userInitiated) { cache.read(id).map(ChannelIndex.init) }.value
            guard gen == generation else { return }
            if let saved { show(saved) }
            phase = .ready
            await reload()
        }
    }

    // ── listene ──

    /// Henter kategoriene og kanalene på nytt (lista fra sist vises imens).
    func reload() async {
        guard let client, loadingFor != generation else { return }
        let gen = generation
        loadingFor = gen
        loading = true
        await fetchLists(client, gen)
        guard loadingFor == gen else { return }
        loadingFor = nil
        loading = false
        triedOnce = true
        if let account = try? await client.account(), gen == generation { self.account = account }
    }

    private func fetchLists(_ client: XtreamClient, _ gen: Int) async {
        do {
            async let cats = client.categories()
            async let chans = client.channels()
            let lists = Lists(categories: try await cats, channels: try await chans)
            guard gen == generation else { return }
            let current = index
            // oppslagene lages i bakgrunnen, og bare når lista er endret: ellers tegnes alt på nytt for ingenting
            let next = await Task.detached(priority: .userInitiated) { () -> ChannelIndex? in
                current.hasSameLists(as: lists) ? nil : ChannelIndex(lists)
            }.value
            guard gen == generation else { return }
            if let next {
                show(next)
                if let id = login?.id {
                    let cache = cache
                    Task.detached(priority: .background) { cache.write(lists, for: id) }
                }
            }
            error = nil
        } catch {
            guard gen == generation else { return }
            self.error = (error as? SourceError)?.message ?? error.localizedDescription
        }
    }

    private func show(_ next: ChannelIndex) {
        index = next
        reorder()
    }

    /// «Alle kanaler» med kanalene i favorittkategoriene først.
    private func reorder() {
        allChannels = index.channels(favoring: library?.favoriteCategories ?? [])
    }

    // ── favoritter og «sist sett» ──

    var favorites: [Channel] {
        _ = libraryVersion
        return FyrlysCore.channels(library?.favorites ?? [], in: byId)
    }

    var recent: [Channel] {
        _ = libraryVersion
        return FyrlysCore.channels(library?.recent ?? [], in: byId)
    }

    func isFavorite(_ channel: Channel) -> Bool {
        _ = libraryVersion
        return library?.isFavorite(channel.id) ?? false
    }

    func toggleFavorite(_ channel: Channel) {
        library?.toggleFavorite(channel.id)
        libraryVersion += 1
    }

    func played(_ channel: Channel) {
        library?.addRecent(channel.id)
        libraryVersion += 1
    }

    // ── favorittkategorier («Dine kategorier») ──

    /// I rekkefølgen brukeren har valgt (de som ikke finnes hos leverandøren lenger, vises ikke).
    var favoriteCategories: [ChannelCategory] {
        _ = libraryVersion
        return (library?.favoriteCategories ?? []).compactMap { index.category($0) }
    }

    func isFavoriteCategory(_ id: String) -> Bool {
        _ = libraryVersion
        return library?.isFavoriteCategory(id) ?? false
    }

    func toggleFavoriteCategory(_ id: String) {
        library?.toggleFavoriteCategory(id)
        libraryVersion += 1
        reorder()
    }

    /// Opp (-1) eller ned (1) blant favorittkategoriene som vises.
    func moveFavoriteCategory(_ id: String, by step: Int) {
        library?.moveFavoriteCategory(id, by: step, shown: Set(favoriteCategories.map(\.id)))
        libraryVersion += 1
        reorder()
    }

    /// Ny rekkefølge for favorittkategoriene som vises (dra og slipp på iPhone).
    func setFavoriteCategoryOrder(_ ids: [String]) {
        library?.setFavoriteCategoryOrder(ids)
        libraryVersion += 1
        reorder()
    }

    /// Søk i kanalnavnene, med kanalene i favorittkategoriene først.
    func search(_ query: String, limit: Int) -> [Channel] {
        _ = libraryVersion
        return index.search(query, favoring: library?.favoriteCategories ?? [], limit: limit)
    }
}

/// Programinfoen for én kanal. Hver kanal er observerbar for seg, så et kort tegnes på nytt bare når programinfoen
/// for den kanalen kommer (med én felles liste ble alle kortene på skjermen tegnet på nytt hver gang).
@MainActor
@Observable
final class ChannelPrograms {
    var list: [Program] = []
    /// svaret er kommet (også et tomt), så kortet kan slutte å vise at det henter
    var loaded = false
}

/// Programinfo for kanalene som vises: hentes når et kort har vært framme litt (høyst fire om gangen, de nyeste
/// først) og tas vare på i fem minutter. Eventkanaler og kanaler uten programinfo hos leverandøren hoppes over, som i
/// Fyrlys på Windows.
@MainActor
final class ProgramStore {
    private var boxes: [String: ChannelPrograms] = [:]
    private var fetched: [String: Date] = [:]
    private var waiting: [Channel] = []
    private var running = 0
    private var client: XtreamClient?
    private var generation = 0
    private var pumpQueued = false

    static let maxRunning = 4
    static let keep: TimeInterval = 300
    /// ventetid før henting, så rask blaing ikke fyller køen med kanaler du bare passerte
    static let settle: Duration = .milliseconds(150)

    func reset(client: XtreamClient?) {
        self.client = client
        for box in boxes.values where !box.list.isEmpty || box.loaded {
            box.list = []
            box.loaded = false
        }
        fetched = [:]
        waiting = []
        running = 0
        generation += 1
    }

    func programs(for channel: Channel) -> [Program] { box(channel.id).list }

    /// Om programinfoen for kanalen er hentet (også når leverandøren ikke hadde noe).
    func isLoaded(_ channel: Channel) -> Bool { box(channel.id).loaded }

    private func box(_ id: String) -> ChannelPrograms {
        if let box = boxes[id] { return box }
        let box = ChannelPrograms()
        boxes[id] = box
        return box
    }

    /// Kanalen vises: hent programinfoen om den ikke er hentet nylig.
    func want(_ channel: Channel) {
        guard channel.wantsEpg else { return }
        if let at = fetched[channel.id], Date().timeIntervalSince(at) < Self.keep { return }
        waiting.removeAll { $0.id == channel.id }
        waiting.append(channel)
        queuePump()
    }

    /// Kanalen er ikke framme lenger: ikke hent den hvis det ikke har begynt.
    func forget(_ channel: Channel) {
        waiting.removeAll { $0.id == channel.id }
    }

    private func queuePump() {
        guard !pumpQueued else { return }
        pumpQueued = true
        Task {
            try? await Task.sleep(for: Self.settle)
            pumpQueued = false
            pump()
        }
    }

    private func pump() {
        guard let client else { return }
        while running < Self.maxRunning, let channel = waiting.popLast() {
            running += 1
            fetched[channel.id] = Date()
            let gen = generation
            Task {
                let result: [Program]?
                do {
                    result = try await client.epg(channel, limit: 10)
                } catch {
                    result = nil
                }
                // etter reset: running er alt satt til 0
                guard gen == generation else { return }
                running -= 1
                if let result {
                    // en tom liste huskes også (leverandøren har ingenting nå), til den er fem minutter gammel
                    let target = self.box(channel.id)
                    if target.list != result { target.list = result }
                    if !target.loaded { target.loaded = true }
                } else {
                    // feil: prøv igjen neste gang kanalen vises
                    fetched[channel.id] = nil
                }
                pump()
            }
        }
    }
}
