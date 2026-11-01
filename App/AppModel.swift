import FyrlysCore
import Foundation
import Observation
#if os(tvOS)
import TVServices
#endif

/// Tilstanden i appen: innloggingen, kategoriene og kanalene, favoritter, favorittkategorier og «sist sett», og
/// abonnementet.
@MainActor
@Observable
final class AppModel {
    enum Phase { case starting, signedOut, ready }

    var phase: Phase = .starting
    private(set) var login: Login?
    /// innloggingene som er lagret på enheten, den som er i bruk først
    private(set) var logins: [Login] = []
    /// innloggingssiden vises for å legge til en innlogging (med «Avbryt» tilbake til den som er i bruk)
    var addingLogin = false
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
    /// kanalen TV-arkivet er åpnet for (fra hurtigmenyen på et kort)
    var archiveChannel: Channel?
    /// kanalen Top Shelf ba om (fyrlys://kanal/<id>), spilles når lista er klar
    var pendingPlay: String?
    /// et program fra start (TV-arkivet), vist av HomeView over alt annet
    var replay: VODPlay?
    /// venter på at et ark eller spilleren for direktesendingen er lukket (leverandøren gir ofte bare én
    /// tilkobling, så direktesendingen stoppes først)
    @ObservationIgnored var pendingReplay: VODPlay?
    /// telles opp når «Fortsett å se» endres
    private(set) var continueVersion = 0
    /// hvor langt serverens klokke er foran UTC (for adressene i arkivet), spurt én gang per innlogging
    @ObservationIgnored private var clock: TimeInterval??
    /// filmer og serier (VOD)
    let movies = VODModel(kind: .movies)
    let series = VODModel(kind: .series)
    /// Plex: filmer og serier derfra i stedet for fra IPTV-leverandøren, når det er valgt
    let plex = PlexModel()
    private let cache = TestSupport.listCache
    private let defaults = TestSupport.defaults
    @ObservationIgnored private var cloudStore: CloudStore?

    /// Favorittene og «Dine kategorier» i iCloud, delt mellom enhetene (ikke i testene: de skal begynne tomme).
    private var store: KeyValueStore {
        if TestSupport.isActive { return defaults }
        if let cloudStore { return cloudStore }
        let cloud = CloudStore(local: defaults)
        cloud.observe { [weak self] in
            MainActor.assumeIsolated { self?.libraryChangedElsewhere() }
        }
        cloudStore = cloud
        return cloud
    }
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
        plex.onChange = { [weak self] in self?.refreshVOD() }
        for vod in [movies, series] {
            vod.reconnect = { [weak self] in self?.plex.retry() }
        }
        plex.start()
        loadStreams()
        if TestSupport.isActive {
            if TestSupport.screen != "login", let test = TestSupport.login {
                use(test)
            } else {
                phase = .signedOut
            }
        } else if let saved = Keychain.loadAll().first {
            logins = Keychain.loadAll()
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
        logins = [login] + logins.filter { $0.id != login.id }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
        addingLogin = false
        use(login)
        self.account = account
    }

    /// Bytter til en annen lagret innlogging.
    func switchTo(_ other: Login) {
        guard other.id != login?.id else { return }
        logins = [other] + logins.filter { $0.id != other.id }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
        account = nil
        use(other)
    }

    /// Fjerner en lagret innlogging som ikke er i bruk.
    func remove(_ other: Login) {
        guard other.id != login?.id else { return }
        cache.remove(other.id)
        logins.removeAll { $0.id == other.id }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
    }

    /// Logger ut av den som er i bruk; finnes det flere, brukes den neste.
    func signOut() {
        if let login { cache.remove(login.id) }
        logins.removeAll { $0.id == login?.id }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
        if let next = logins.first {
            account = nil
            use(next)
            return
        }
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
        refreshVOD()
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
        library = Library(store: store, loginId: login.id)
        libraryVersion += 1
        programs.reset(client: client)
        refreshVOD()
        clock = nil
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
        shareFavorites()
    }

    /// «Alle kanaler» med kanalene i favorittkategoriene først.
    private func reorder() {
        allChannels = index.channels(favoring: library?.favoriteCategories ?? [])
    }

    /// Serverens klokke for arkivet (nil: serveren sier ikke noe, og enhetens tidssone brukes).
    func serverClock() async -> TimeInterval? {
        if let clock { return clock }
        guard let client else { return nil }
        let found = await client.serverClock()
        clock = .some(found)
        return found
    }

    /// [program] på [channel] fra start, fra TV-arkivet (nil når kanalen ikke har arkiv).
    func archivePlay(_ channel: Channel, _ program: Program) async -> VODPlay? {
        guard let client, channel.archiveDays > 0 else { return nil }
        let clock = await serverClock()
        return VODPlay.archive(channel, program, client: client, clock: clock)
    }

    /// Et ark eller spilleren er lukket: spill det som ventet.
    func showPendingReplay() {
        guard let next = pendingReplay else { return }
        pendingReplay = nil
        replay = next
    }

    // ── filmer og serier: fra IPTV-leverandøren eller fra Plex ──

    /// Hvor fanene Filmer og Serier henter fra nå.
    private var vodBackend: VODBackend? {
        if plex.useForVOD && (plex.server != nil || plex.phase != .off) {
            if let client = plex.client { return .plex(client) }
            if case .failed(let message) = plex.phase { return .unavailable(message) }
            return .waiting
        }
        return client.map { .xtream($0) }
    }

    func refreshVOD() {
        let backend = vodBackend
        movies.reset(backend)
        series.reset(backend)
    }

    // ── egne strømmer: adresser som spilles i stedet for leverandørens (i iCloud, delt mellom enhetene) ──

    static let streamsKey = "egne-strommer"
    /// linjene som er lagt inn
    private(set) var streamLines: [String] = []
    @ObservationIgnored private var streamByKey: [String: URL] = [:]

    var streamOverrides: [StreamOverride] { parseStreamOverrides(streamLines.joined(separator: "\n")) }

    private func loadStreams() {
        useStreams(TestSupport.streams ?? store.strings(Self.streamsKey))
    }

    private func useStreams(_ lines: [String]) {
        streamLines = lines
        streamByKey = Dictionary(streamOverrides.map { ($0.key, $0.url) }, uniquingKeysWith: { first, _ in first })
    }

    func setStreams(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !TestSupport.isActive { store.set(lines, for: Self.streamsKey) }
        useStreams(lines)
    }

    /// Adressen kanalen spilles fra: en egen når det er lagt inn en for den, ellers leverandørens.
    func streamURL(_ channel: Channel) -> URL? {
        if !streamByKey.isEmpty, let own = streamByKey[channelKey(channel.name)] { return own }
        return client?.liveURL(channel)
    }

    /// Kanalene hver egen strøm gjelder for (i bakgrunnen: lista kan ha titusenvis av kanaler).
    func streamMatches() async -> [String: [String]] {
        let keys = Set(streamOverrides.map(\.key))
        guard !keys.isEmpty else { return [:] }
        let list = self.channels
        return await Task.detached(priority: .userInitiated) {
            var found: [String: [String]] = [:]
            for channel in list {
                let key = channelKey(channel.name)
                if keys.contains(key) { found[key, default: []].append(channel.name) }
            }
            return found
        }.value
    }

    // ── «Fortsett å se»: filmene og seriene du har begynt på, sist sett først ──

    private var continueKey: String? { login.map { "fortsett@\($0.id)" } }

    func continueItems(_ kind: VODKind) -> [VODItem] {
        _ = continueVersion
        guard let key = continueKey, let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([VODItem].self, from: data) else { return [] }
        return items.filter { $0.kind == kind }
    }

    func rememberContinue(_ item: VODItem) {
        guard let key = continueKey, continueItems(item.kind).first?.progressKey != item.progressKey else { return }
        let all = (continueItems(.movies) + continueItems(.series)).filter { $0.progressKey != item.progressKey }
        save([item] + all.prefix(29), key)
    }

    func forgetContinue(_ item: VODItem) {
        guard let key = continueKey else { return }
        save((continueItems(.movies) + continueItems(.series)).filter { $0.progressKey != item.progressKey }, key)
    }

    private func save(_ items: [VODItem], _ key: String) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
        continueVersion += 1
    }

    // ── hvor langt man har sett filmer og episoder (sekunder, per innlogging, på enheten) ──

    func progress(_ key: String) -> Double {
        guard let login else { return 0 }
        return defaults.double(forKey: "sett@\(login.id)@\(key)")
    }

    /// Sett ferdig (på enheten): for «Neste episode» på seriesiden og «Sett» på episodene (Plex husker det selv).
    func isFinished(_ key: String) -> Bool {
        guard let login else { return false }
        return defaults.bool(forKey: "ferdig@\(login.id)@\(key)")
    }

    func setFinished(_ key: String) {
        guard let login else { return }
        defaults.set(true, forKey: "ferdig@\(login.id)@\(key)")
    }

    /// nil: ferdig sett eller nesten ingenting sett (begynn fra start neste gang)
    func setProgress(_ key: String, _ seconds: Double?) {
        guard let login else { return }
        let k = "sett@\(login.id)@\(key)"
        if let seconds { defaults.set(seconds, forKey: k) } else { defaults.removeObject(forKey: k) }
    }

    // ── favoritter og «sist sett» ──

    /// Favorittene eller «Dine kategorier» er endret på en annen enhet (iCloud).
    private func libraryChangedElsewhere() {
        loadStreams()
        guard let library else { return }
        library.reload()
        libraryVersion += 1
        reorder()
        shareFavorites()
    }

    /// Favorittene til Top Shelf (hjemskjermen til Apple TV).
    func shareFavorites() {
        #if os(tvOS)
        guard !TestSupport.isActive, !index.channels.isEmpty else { return }
        SharedFavorites.save(favorites.map { SharedFavorite(id: $0.id, name: nameParts($0.name).main, logo: $0.logo) })
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }

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
        shareFavorites()
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
