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
    /// Xtream Codes (nil for en M3U-liste)
    private(set) var client: XtreamClient?
    /// en M3U-liste: lista og TV-guiden (XMLTV)
    @ObservationIgnored private(set) var m3u: M3USource?
    /// kategoriene og kanalene med oppslagene (lages i bakgrunnen og byttes bare når lista er endret)
    private(set) var index = ChannelIndex.empty
    /// alle kanalene, med kanalene i favorittkategoriene først
    private(set) var allChannels: [Channel] = []
    private(set) var account: Account?
    var loading = false
    var error: String?

    /// telles opp når favoritter eller favorittkategorier endres (Library er ikke observerbar selv)
    private(set) var libraryVersion = 0
    /// telles opp når «sist sett» endres (for seg: et kanalbytte skal ikke tegne alle kortene og søket på nytt)
    private(set) var recentVersion = 0
    /// da kanallista sist ble hentet (hentes igjen når appen kommer fram etter noen timer)
    @ObservationIgnored private var listsFetchedAt: Date?
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
    /// telles opp når favorittene i Filmer eller Serier endres (her eller på en annen enhet)
    private(set) var vodFavoritesVersion = 0
    /// favorittene i Filmer og Serier per nøkkel, lest én gang (tømmes når de endres)
    @ObservationIgnored private var vodFavoritesCache: [String: [VODItem]] = [:]
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
        loadHiddenLibraries()
        if TestSupport.isActive {
            // login og login-m3u: innloggingssiden
            if TestSupport.screen?.hasPrefix("login") != true, let test = TestSupport.login {
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
        try await signIn(Login(server: server, username: username, password: password))
    }

    private func signIn(_ xtream: Login) async throws {
        var login = xtream
        // samme konto på nytt: navnet du ga den, står
        login.name = logins.first { $0.id == login.id }?.name
        let client = XtreamClient(login: login)
        let account = try await client.account()
        if !account.status.isEmpty && account.status.lowercased() != "active" {
            throw SourceError(L("Abonnementet er ikke aktivt ({status})", ["status": account.status]))
        }
        save(login)
        use(login)
        self.account = account
    }

    /// Logger inn med en M3U-lenke (og eventuelt en lenke til TV-guiden), som i Fyrlys for Windows: er det en
    /// Xtream-lenke (get.php med brukernavn og passord), prøves den som Xtream Codes først (da kommer filmer, serier og
    /// TV-arkivet med); ellers hentes lista, og den må ha kanaler.
    func signIn(m3u text: String, epg epgText: String) async throws {
        let link = try normalizeLink(text, empty: L("Lim inn M3U-lenken"))
        var epg: String?
        if !epgText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            epg = try normalizeLink(epgText, empty: "")
        }
        if let xtream = xtreamLogin(fromM3U: link) {
            do {
                try await signIn(xtream)
                AppLog.shared.add("Innlogging: M3U-lenken er en Xtream-lenke")
                return
            } catch {
                // ikke en Xtream-server likevel: lista leses som den er
            }
        }
        var login = Login(m3u: link, epg: epg)
        login.name = logins.first { $0.id == login.id }?.name
        let lists = try await M3USource(login: login).lists()
        save(login)
        use(login, fresh: lists)
    }

    /// Den nye (eller oppdaterte) innloggingen først i lista.
    private func save(_ login: Login) {
        logins = [login] + logins.filter { $0.id != login.id }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
        addingLogin = false
    }

    /// Bytter til en annen lagret innlogging.
    func switchTo(_ other: Login) {
        guard other.id != login?.id else { return }
        pendingPlay = nil
        logins = [other] + logins.filter { $0.id != other.id }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
        account = nil
        use(other)
    }

    /// Gir innloggingen [target] et eget navn («Hjemme», «Sport»); tomt gir «bruker på server» igjen.
    func rename(_ target: Login, to name: String) {
        let renamed = target.named(name)
        logins = logins.map { $0.id == target.id ? renamed : $0 }
        if login?.id == target.id { login = renamed }
        if !TestSupport.isActive { Keychain.saveAll(logins) }
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
        pendingPlay = nil
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
        m3u = nil
        library = nil
        libraryVersion += 1
        account = nil
        index = .empty
        allChannels = []
        listsFetchedAt = nil
        programs.reset(source: nil)
        refreshVOD()
        phase = .signedOut
        #if os(tvOS)
        // Top Shelf skal ikke vise favorittene til en innlogging som er borte
        if !TestSupport.isActive {
            SharedFavorites.save([])
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
        #endif
    }

    /// Appen er framme igjen (fra bakgrunnen, eller Apple TV-en har sovet): programinfoen for det som vises, adressen
    /// til Plex, filmene og seriene, og kanallista når den er noen timer gammel (eventkanalene har kampene i navnet).
    func becameActive() {
        guard phase == .ready, login != nil else { return }
        programs.refreshVisible()
        plex.reprobe()
        movies.refreshIfOld()
        series.refreshIfOld()
        if let at = listsFetchedAt, Date().timeIntervalSince(at) > 3 * 3600 {
            Task { await reload() }
        }
    }

    /// Tar i bruk [login]. [fresh]: lista er nettopp hentet (en M3U-liste ved innloggingen), så den hentes ikke igjen.
    private func use(_ login: Login, fresh: Lists? = nil) {
        AppLog.shared.add("Innlogging: \(login.isM3U ? "M3U-liste" : "Xtream Codes") (\(logins.count) lagret)")
        generation += 1
        let gen = generation
        self.login = login
        let source: any ProgramSource
        if login.isM3U {
            let m3u = M3USource(login: login)
            self.m3u = m3u
            client = nil
            source = m3u
        } else {
            let client = XtreamClient(login: login)
            self.client = client
            m3u = nil
            source = client
        }
        triedOnce = false
        error = nil
        index = .empty
        allChannels = []
        listsFetchedAt = nil
        library = Library(store: store, loginId: login.id)
        libraryVersion += 1
        programs.reset(source: source)
        refreshVOD()
        clock = nil
        let cache = cache
        let id = login.id
        let keys = mergeKeys
        let m3uSource = self.m3u
        Task {
            // lista fra sist leses og pakkes ut i bakgrunnen: med titusenvis av kanaler sto appen ellers stille imens
            let lists = fresh
            let saved = await Task.detached(priority: .userInitiated) { () -> ChannelIndex? in
                (lists ?? cache.read(id)).map { ChannelIndex($0, merging: keys) }
            }.value
            guard gen == generation else { return }
            if let saved {
                await m3uSource?.remember(saved.lists)
                guard gen == generation else { return }
                show(saved)
            }
            phase = .ready
            if let fresh {
                listsFetchedAt = Date()
                triedOnce = true
                AppLog.shared.add("Listene: \(fresh.channels.count) kanaler i \(fresh.categories.count) kategorier")
                Task.detached(priority: .background) { cache.write(fresh, for: id) }
            } else {
                await reload()
            }
        }
    }

    // ── listene ──

    /// Henter kategoriene og kanalene på nytt (lista fra sist vises imens).
    func reload() async {
        guard client != nil || m3u != nil, loadingFor != generation else { return }
        let gen = generation
        loadingFor = gen
        loading = true
        await fetchLists(gen)
        guard loadingFor == gen else { return }
        loadingFor = nil
        loading = false
        triedOnce = true
        if let client, let account = try? await client.account(), gen == generation { self.account = account }
    }

    /// Listene fra leverandøren: Xtream (kategoriene og kanalene), eller M3U-lista.
    private func downloadLists() async throws -> Lists {
        if let m3u { return try await m3u.lists() }
        guard let client else { throw SourceError(L("Ikke logget inn")) }
        async let cats = client.categories()
        async let chans = client.channels()
        return Lists(categories: try await cats, channels: try await chans)
    }

    private func fetchLists(_ gen: Int) async {
        do {
            let lists = try await downloadLists()
            guard gen == generation else { return }
            let current = index
            // ingen kanaler i svaret (et uventet svar, eller leverandøren har problemer): lista fra sist står, og
            // den på disken skrives ikke over med en tom
            if lists.channels.isEmpty && !current.lists.channels.isEmpty {
                error = L("IPTV-serveren sendte ingen kanaler. Viser lista fra sist.")
                AppLog.shared.add("Listene: ingen kanaler i svaret, viser lista fra sist")
                return
            }
            AppLog.shared.add("Listene: \(lists.channels.count) kanaler i \(lists.categories.count) kategorier")
            listsFetchedAt = Date()
            let keys = mergeKeys
            // oppslagene lages i bakgrunnen, og bare når lista er endret: ellers tegnes alt på nytt for ingenting
            let next = await Task.detached(priority: .userInitiated) { () -> ChannelIndex? in
                current.hasSameLists(as: lists) && current.mergeKeys == keys ? nil : ChannelIndex(lists, merging: keys)
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
            AppLog.shared.add("Listene feilet: \(self.error ?? "")")
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
        // svarte ikke serveren, spørres det igjen neste gang (ellers ble tidssonen gjettet resten av økta)
        guard let found = try? await client.serverClock() else { return nil }
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
            if plex.phase == .choosing { return .unavailable(L("Velg Plex-serveren under Innstillinger.")) }
            return .waiting
        }
        return client.map { .xtream($0) }
    }

    func refreshVOD() {
        let backend = vodBackend
        let hidden = hiddenSections
        movies.reset(backend, hidden: hidden)
        series.reset(backend, hidden: hidden)
    }

    // ── feilrapporten fra Apple TV til iPhone og iPad (i iCloud) ──

    static let reportKey = "feilrapport-tv"

    /// Apple TV: legger rapporten i iCloud (med tidspunktet), så den kan kopieres eller deles fra iPhone eller iPad.
    func sendReport(_ text: String) {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        store.set([format.string(from: Date()), text], for: Self.reportKey)
    }

    /// iPhone og iPad: rapporten som sist ble sendt fra Apple TV.
    var reportFromTV: (date: String, text: String)? {
        let saved = store.strings(Self.reportKey)
        guard saved.count == 2, !saved[1].isEmpty else { return nil }
        return (saved[0], saved[1])
    }

    // ── Plex: bibliotekene som ikke vises i Filmer og Serier (i iCloud, delt mellom enhetene) ──

    static let hiddenLibrariesKey = "plex-skjulte"
    /// «<server>/<bibliotek>» (som i Fyrlys for Windows)
    private(set) var hiddenLibraries: Set<String> = []

    private func loadHiddenLibraries() {
        hiddenLibraries = Set(store.strings(Self.hiddenLibrariesKey))
    }

    /// nøklene til bibliotekene som er skjult på serveren som er valgt
    var hiddenSections: Set<String> {
        guard let server = plex.server?.id else { return [] }
        let prefix = server + "/"
        return Set(hiddenLibraries.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
    }

    func isHidden(_ library: String) -> Bool { hiddenSections.contains(library) }

    /// Viser eller skjuler biblioteket [library] (på serveren som er valgt): sidemenyen, Hjem, «Fortsett å se» og søket
    /// hentes på nytt.
    func setHidden(_ library: String, _ hidden: Bool) {
        guard let server = plex.server?.id else { return }
        let id = "\(server)/\(library)"
        var set = hiddenLibraries
        if hidden { set.insert(id) } else { set.remove(id) }
        guard set != hiddenLibraries else { return }
        hiddenLibraries = set
        if !TestSupport.isActive { store.set(set.sorted(), for: Self.hiddenLibrariesKey) }
        refreshVOD()
    }

    // ── egne strømmer: adresser som spilles i stedet for leverandørens (i iCloud, delt mellom enhetene) ──

    static let streamsKey = "egne-strommer"
    /// linjene som er lagt inn
    private(set) var streamLines: [String] = []
    /// de innebygde (NRK direkte) brukes (kan slås av i innstillingene)
    var useBuiltInStreams: Bool {
        get { builtInOn }
        set {
            builtInOn = newValue
            defaults.set(!newValue, forKey: "innebygde-strommer-av")
            useStreams(streamLines)
        }
    }
    private var builtInOn = !TestSupport.defaults.bool(forKey: "innebygde-strommer-av")
    @ObservationIgnored private var streamByKey: [String: URL] = [:]

    var streamOverrides: [StreamOverride] { parseStreamOverrides(streamLines.joined(separator: "\n")) }

    private func loadStreams() {
        useStreams(TestSupport.streams ?? store.strings(Self.streamsKey))
    }

    private func useStreams(_ lines: [String]) {
        streamLines = lines
        // de egne går foran de innebygde
        let all = streamOverrides + (builtInOn ? builtInStreams : [])
        streamByKey = Dictionary(all.map { ($0.key, $0.url) }, uniquingKeysWith: { first, _ in first })
        remerge()
    }

    /// Kanalene som spilles fra samme egne strøm (NRK1 HD, NRK1 FHD …), slås sammen til én.
    private var mergeKeys: Set<String> { Set(streamByKey.keys) }

    /// Oppslagene på nytt når de egne strømmene er endret (i bakgrunnen).
    private func remerge() {
        let current = index
        let keys = mergeKeys
        guard current.mergeKeys != keys, !current.lists.channels.isEmpty else { return }
        let gen = generation
        Task {
            let next = await Task.detached(priority: .userInitiated) { ChannelIndex(current.lists, merging: keys) }.value
            guard gen == generation, mergeKeys == keys else { return }
            show(next)
        }
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
        if !streamByKey.isEmpty, let key = index.streamKey(of: channel), let own = streamByKey[key] { return own }
        return providerURLs(channel).first
    }

    /// Leverandørens adresser for kanalen: Xtream som HLS, eller adressen i M3U-lista (en .ts-strøm fra en Xtream-server
    /// først som HLS, se `m3uPlayURLs`).
    func providerURLs(_ channel: Channel) -> [URL] {
        if let m3u = channel.m3u { return m3uPlayURLs(m3u.url) }
        return client.map { [$0.liveURL(channel)] } ?? []
    }

    /// «M3U-liste med TV-guide» (nil for Xtream Codes: der står abonnementet)
    var m3uSummary: String? {
        guard let login, login.isM3U else { return nil }
        let guide = login.epg != nil || !(index.lists.guides ?? []).isEmpty
        return guide ? L("M3U-liste med TV-guide") : L("M3U-liste uten TV-guide")
    }

    /// Filmer og Serier finnes: hos Xtream, eller fra Plex (en M3U-liste har dem ikke, så fanene vises ikke da).
    var hasVOD: Bool {
        client != nil || (plex.useForVOD && (plex.server != nil || plex.phase != .off))
    }

    /// Kanalene hver egen strøm gjelder for (navnene hos leverandøren), fra indeksen.
    var streamMatches: [String: [String]] { index.streamNames }

    // ── «Fortsett å se» fra IPTV-leverandøren (Plex har sin egen): sist sett først, med episoden og hvor langt ──

    private var continueKey: String? { login.map { "fortsett@\($0.id)" } }

    func continueEntries(_ kind: VODKind) -> [VODResume] {
        _ = continueVersion
        return storedContinue().filter { $0.item.kind == kind }
    }

    /// Alle, sist sett først (filmer og serier om hverandre).
    private func storedContinue() -> [VODResume] {
        guard let key = continueKey, let data = defaults.data(forKey: key) else { return [] }
        if let entries = try? JSONDecoder().decode([VODResume].self, from: data) { return entries }
        // lagret før 0.1.24: bare filmen eller serien
        return ((try? JSONDecoder().decode([VODItem].self, from: data)) ?? []).map { VODResume(item: $0) }
    }

    func rememberContinue(_ new: VODResume) {
        guard let key = continueKey else { return }
        let stored = storedContinue()
        var entry = new
        // bildet fra før, når det ikke kom noe nytt
        if entry.image == nil {
            entry.image = stored.first { $0.item.progressKey == entry.item.progressKey }?.image
        }
        // lagres hvert tiende sekund: bare når noe synlig er endret (episoden, eller et par prosent lenger)
        if let first = stored.first, first.item.progressKey == entry.item.progressKey,
           first.episode?.id == entry.episode?.id, abs(first.progress - entry.progress) < 0.02,
           first.image == entry.image {
            return
        }
        // i rekkefølgen de er sett (før: filmene først, så seriene, og da ble seriene kuttet når lista var full)
        saveContinue([entry] + stored.filter { $0.item.progressKey != entry.item.progressKey }.prefix(29), key)
    }

    func forgetContinue(_ item: VODItem) {
        guard let key = continueKey else { return }
        saveContinue(storedContinue().filter { $0.item.progressKey != item.progressKey }, key)
    }

    private func saveContinue(_ entries: [VODResume], _ key: String) {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
        continueVersion += 1
    }

    // ── favorittene i Filmer og Serier (delt med iCloud) ──

    /// Plex-favorittene hører til serveren (de er de samme med en annen IPTV-innlogging), de fra leverandøren til
    /// innloggingen.
    private func vodFavoritesKey(_ kind: VODKind, fromPlex: Bool) -> String? {
        if fromPlex { return plex.server.map { "vodFavorites@plex:\($0.id)@\(kind.rawValue)" } }
        return login.map { "vodFavorites@\($0.id)@\(kind.rawValue)" }
    }

    /// Favorittene, sist lagt til først. Fra Plex bare id-en og navnet: plakatene hentes fra serveren (adressen der
    /// har nøkkelen og kan endre seg).
    func vodFavorites(_ kind: VODKind, fromPlex: Bool) -> [VODItem] {
        _ = vodFavoritesVersion
        guard let key = vodFavoritesKey(kind, fromPlex: fromPlex) else { return [] }
        if let cached = vodFavoritesCache[key] { return cached }
        var seen = Set<String>()
        let items = store.strings(key).compactMap { line -> VODItem? in
            guard let item = try? JSONDecoder().decode(VODItem.self, from: Data(line.utf8)),
                  seen.insert(item.id).inserted else { return nil }
            return item
        }
        vodFavoritesCache[key] = items
        return items
    }

    func isVODFavorite(_ item: VODItem) -> Bool {
        vodFavorites(item.kind, fromPlex: item.isPlex).contains { $0.id == item.id }
    }

    func toggleVODFavorite(_ item: VODItem) {
        guard let key = vodFavoritesKey(item.kind, fromPlex: item.isPlex) else { return }
        var list = vodFavorites(item.kind, fromPlex: item.isPlex)
        if list.contains(where: { $0.id == item.id }) {
            list.removeAll { $0.id == item.id }
        } else {
            list.insert(item.isPlex ? VODItem(id: item.id, kind: item.kind, name: item.name, year: item.year,
                                              source: "plex") : item, at: 0)
        }
        let lines = list.compactMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
        store.set(lines, for: key)
        vodFavoritesCache[key] = nil
        vodFavoritesVersion += 1
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

    func setFinished(_ key: String, _ finished: Bool = true) {
        guard let login else { return }
        let k = "ferdig@\(login.id)@\(key)"
        if finished { defaults.set(true, forKey: k) } else { defaults.removeObject(forKey: k) }
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
        let before = hiddenLibraries
        loadHiddenLibraries()
        if hiddenLibraries != before { refreshVOD() }
        vodFavoritesCache = [:]
        vodFavoritesVersion += 1
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
        _ = recentVersion
        return FyrlysCore.channels(library?.recent ?? [], in: byId)
    }

    /// En sammenslått kanal er favoritt når en av dem er det.
    func isFavorite(_ channel: Channel) -> Bool {
        _ = libraryVersion
        guard let library else { return false }
        return index.ids(of: channel).contains { library.isFavorite($0) }
    }

    func toggleFavorite(_ channel: Channel) {
        guard let library else { return }
        let favorited = index.ids(of: channel).filter { library.isFavorite($0) }
        if favorited.isEmpty {
            library.toggleFavorite(channel.id)
        } else {
            for id in favorited { library.toggleFavorite(id) }
        }
        libraryVersion += 1
        shareFavorites()
    }

    func played(_ channel: Channel) {
        guard library?.recent.first != channel.id else { return }
        library?.addRecent(channel.id)
        recentVersion += 1
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

/// Hvor programinfoen kommer fra: leverandørens programinfo per kanal (Xtream), eller TV-guiden (XMLTV) til en
/// M3U-liste.
protocol ProgramSource: Sendable {
    func programs(for channel: Channel) async throws -> [Program]
}

extension XtreamClient: ProgramSource {
    func programs(for channel: Channel) async throws -> [Program] { try await epg(channel, limit: 10) }
}

extension M3USource: ProgramSource {}

/// Programinfo for kanalene som vises: hentes når et kort har vært framme litt (høyst fire om gangen, de nyeste
/// først) og tas vare på i fem minutter. Eventkanaler og kanaler uten programinfo hos leverandøren hoppes over, som i
/// Fyrlys på Windows. Kanalene som vises (kort, guiderader, kanallista i spilleren), hentes på nytt hvert minutt når
/// det som går nå mangler eller det er en halvtime siden sist, og når appen kommer fram igjen; feil prøves igjen.
@MainActor
final class ProgramStore {
    private var boxes: [String: ChannelPrograms] = [:]
    private var fetched: [String: Date] = [:]
    /// feil på rad per kanal (etter to vises «ingen programinfo» i stedet for at den henter)
    private var failures: [String: Int] = [:]
    /// kanalene som vises, og av hvor mange visninger (samme kanal kan stå i favorittraden og i lista)
    private var visible: [String: (channel: Channel, count: Int)] = [:]
    private var waiting: [Channel] = []
    private var running = 0
    private var source: (any ProgramSource)?
    private var generation = 0
    private var pumpQueued = false
    private var ticker: Task<Void, Never>?

    static let maxRunning = 4
    static let keep: TimeInterval = 300
    /// så gammel programinfoen for en kanal som vises, kan være før den hentes på nytt (selv om den har «nå»)
    static let refreshAfter: TimeInterval = 1800
    /// ventetid før henting, så rask blaing ikke fyller køen med kanaler du bare passerte
    static let settle: Duration = .milliseconds(150)

    func reset(source: (any ProgramSource)?) {
        self.source = source
        for box in boxes.values where !box.list.isEmpty || box.loaded {
            box.list = []
            box.loaded = false
        }
        fetched = [:]
        failures = [:]
        waiting = []
        running = 0
        generation += 1
    }

    func programs(for channel: Channel) -> [Program] { box(channel.id).list }

    /// Om programinfoen for kanalen er hentet (også når leverandøren ikke hadde noe, eller det feilet to ganger).
    func isLoaded(_ channel: Channel) -> Bool { box(channel.id).loaded }

    private func box(_ id: String) -> ChannelPrograms {
        if let box = boxes[id] { return box }
        let box = ChannelPrograms()
        boxes[id] = box
        return box
    }

    /// Kanalen vises (kalles én gang per visning, med `forget` når den forsvinner): hent programinfoen om den ikke er
    /// hentet nylig.
    func want(_ channel: Channel) {
        guard channel.wantsEpg else { return }
        // så mange vises aldri samtidig: har en visning forsvunnet uten å si fra, begynner tellingen på nytt (ellers
        // ble de hentet på nytt hver halvtime for alltid)
        if visible.count > 500 { visible.removeAll() }
        let count = visible[channel.id]?.count ?? 0
        visible[channel.id] = (channel, count + 1)
        refresh(channel)
        startTicker()
    }

    /// Visningen forsvinner: ikke hent kanalen hvis det ikke har begynt (og ingen annen visning viser den).
    func forget(_ channel: Channel) {
        guard let entry = visible[channel.id] else { return }
        if entry.count > 1 {
            visible[channel.id] = (entry.channel, entry.count - 1)
        } else {
            visible[channel.id] = nil
            waiting.removeAll { $0.id == channel.id }
        }
    }

    /// Hent programinfoen for kanalen om den ikke er hentet nylig (spilleren, uten å telle som en visning).
    func refresh(_ channel: Channel) {
        guard channel.wantsEpg else { return }
        if let at = fetched[channel.id], Date().timeIntervalSince(at) < Self.keep { return }
        waiting.removeAll { $0.id == channel.id }
        waiting.append(channel)
        queuePump()
    }

    /// Kanalene som vises og mangler det som går nå, ble hentet for en halvtime siden, eller feilet: hent på nytt.
    func refreshVisible() {
        let now = Date()
        for (id, entry) in visible {
            let age = fetched[id].map { now.timeIntervalSince($0) } ?? .infinity
            let missing = nowAndNext(box(id).list, at: now).now == nil
            if age >= Self.refreshAfter || (missing && age >= Self.keep) || (failures[id] ?? 0) > 0 {
                refresh(entry.channel)
            }
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if self.visible.isEmpty {
                    self.ticker = nil
                    return
                }
                self.refreshVisible()
            }
        }
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
        guard let source else { return }
        while running < Self.maxRunning, let channel = waiting.popLast() {
            running += 1
            fetched[channel.id] = Date()
            let gen = generation
            Task {
                let result: [Program]?
                do {
                    result = try await source.programs(for: channel)
                } catch {
                    result = nil
                }
                // etter reset: running er alt satt til 0
                guard gen == generation else { return }
                running -= 1
                let target = self.box(channel.id)
                if let result {
                    // en tom liste huskes også (leverandøren har ingenting nå), til den er fem minutter gammel
                    failures[channel.id] = nil
                    if target.list != result { target.list = result }
                    if !target.loaded { target.loaded = true }
                } else {
                    // feil: prøves igjen om et minutt så lenge kanalen vises (eller neste gang den vises); etter to
                    // feil på rad slutter kortet å vise at det henter
                    fetched[channel.id] = nil
                    let count = (failures[channel.id] ?? 0) + 1
                    failures[channel.id] = count
                    if count >= 2, !target.loaded { target.loaded = true }
                }
                pump()
            }
        }
    }
}
