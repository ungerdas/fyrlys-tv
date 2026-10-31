import FyrlysCore
import Foundation
import Observation

/// Tilstanden i appen: innloggingen, kategoriene og kanalene, favoritter og «sist sett», og abonnementet.
@MainActor
@Observable
final class AppModel {
    enum Phase { case starting, signedOut, ready }

    var phase: Phase = .starting
    private(set) var login: Login?
    private(set) var client: XtreamClient?
    private(set) var categories: [ChannelCategory] = []
    private(set) var channels: [Channel] = []
    private(set) var byId: [String: Channel] = [:]
    private(set) var byCategory: [String: [Channel]] = [:]
    private(set) var account: Account?
    var loading = false
    var error: String?

    /// telles opp når favoritter eller «sist sett» endres (Library er ikke observerbar selv)
    private(set) var libraryVersion = 0
    private var library: Library?

    let programs = ProgramStore()
    private let cache = TestSupport.listCache
    private let defaults = TestSupport.defaults
    /// lista er forsøkt hentet minst én gang (før det vises «Henter kanalene …» når den er tom)
    private(set) var triedOnce = false

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
        login = nil
        client = nil
        library = nil
        account = nil
        apply(Lists(categories: [], channels: []))
        programs.reset(client: nil)
        phase = .signedOut
    }

    private func use(_ login: Login) {
        self.login = login
        let client = XtreamClient(login: login)
        self.client = client
        triedOnce = false
        error = nil
        library = Library(store: defaults, loginId: login.id)
        libraryVersion += 1
        programs.reset(client: client)
        if let saved = cache.read(login.id) { apply(saved) }
        phase = .ready
        Task { await reload() }
    }

    // ── listene ──

    /// Henter kategoriene og kanalene på nytt (lista fra sist vises imens).
    func reload() async {
        guard let client, !loading else { return }
        loading = true
        defer {
            loading = false
            triedOnce = true
        }
        do {
            async let cats = client.categories()
            async let chans = client.channels()
            let lists = Lists(categories: try await cats, channels: try await chans)
            apply(lists)
            error = nil
            if let id = login?.id {
                let cache = cache
                Task.detached(priority: .background) { cache.write(lists, for: id) }
            }
        } catch {
            self.error = (error as? SourceError)?.message ?? error.localizedDescription
        }
        if let account = try? await client.account() { self.account = account }
    }

    private func apply(_ lists: Lists) {
        channels = lists.channels
        byId = Dictionary(lists.channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        byCategory = Dictionary(grouping: lists.channels, by: \.categoryId)
        // bare kategorier med kanaler, i leverandørens rekkefølge
        categories = lists.categories.filter { byCategory[$0.id]?.isEmpty == false }
    }

    func channels(in categoryId: String) -> [Channel] { byCategory[categoryId] ?? [] }

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
}

/// Programinfo for kanalene som vises: hentes når et kort kommer fram (høyst fire om gangen, de nyeste først) og tas
/// vare på i fem minutter.
@MainActor
@Observable
final class ProgramStore {
    private(set) var byChannel: [String: [Program]] = [:]
    @ObservationIgnored private var fetched: [String: Date] = [:]
    @ObservationIgnored private var waiting: [Channel] = []
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var client: XtreamClient?
    @ObservationIgnored private var generation = 0

    static let maxRunning = 4
    static let keep: TimeInterval = 300

    func reset(client: XtreamClient?) {
        self.client = client
        byChannel = [:]
        fetched = [:]
        waiting = []
        running = 0
        generation += 1
    }

    func programs(for channel: Channel) -> [Program] { byChannel[channel.id] ?? [] }

    /// Kanalen vises: hent programinfoen om den ikke er hentet nylig.
    func want(_ channel: Channel) {
        if let at = fetched[channel.id], Date().timeIntervalSince(at) < Self.keep { return }
        waiting.removeAll { $0.id == channel.id }
        waiting.append(channel)
        pump()
    }

    /// Kanalen er ikke framme lenger: ikke hent den hvis det ikke har begynt.
    func forget(_ channel: Channel) {
        waiting.removeAll { $0.id == channel.id }
    }

    private func pump() {
        guard let client else { return }
        while running < Self.maxRunning, let channel = waiting.popLast() {
            running += 1
            fetched[channel.id] = Date()
            let gen = generation
            Task {
                let list = (try? await client.epg(channel, limit: 10)) ?? []
                // etter reset: running er alt satt til 0
                guard gen == self.generation else { return }
                self.running -= 1
                if list.isEmpty {
                    // prøv igjen neste gang den vises
                    self.fetched[channel.id] = nil
                } else {
                    self.byChannel[channel.id] = list
                }
                self.pump()
            }
        }
    }
}
