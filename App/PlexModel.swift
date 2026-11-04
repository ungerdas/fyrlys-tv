import FyrlysCore
import Foundation
import Observation
import UIKit

/// Plex-tilkoblingen: koden til plex.tv/link, serveren som er valgt (og adressen som svarte), og om fanene Filmer og
/// Serier henter fra Plex i stedet for IPTV-leverandøren. Nøkkelen og serveren ligger i nøkkelringen.
@MainActor
@Observable
final class PlexModel {
    enum Phase: Equatable {
        case off
        /// venter på at koden skrives inn på plex.tv/link
        case linking(String)
        /// flere servere på kontoen: velg én
        case choosing
        case connecting
        case connected
        case failed(String)
    }

    private(set) var phase: Phase = .off
    private(set) var servers: [PlexServer] = []
    private(set) var server: PlexServer?
    private(set) var client: PlexClient?
    /// filmer og serier fra Plex i stedet for IPTV-leverandøren (når Plex er koblet til)
    var useForVOD: Bool {
        get { storedUse }
        set {
            guard newValue != storedUse else { return }
            storedUse = newValue
            defaults.set(newValue, forKey: Self.useKey)
            onChange?()
        }
    }
    private var storedUse: Bool
    /// fanene Filmer og Serier må hentes på nytt (kilden eller tilkoblingen er endret)
    @ObservationIgnored var onChange: (() -> Void)?

    let device: PlexDevice
    @ObservationIgnored private var account: PlexAccountClient
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var linkTask: Task<Void, Never>?
    /// økes for hver tilkobling, så et sent svar fra en tidligere ikke skriver over en nyere
    @ObservationIgnored private var connectGeneration = 0
    /// leter etter adressen som svarer (se `reprobe`)
    @ObservationIgnored private var probing = false
    /// rapportene til Plex sendes i rekkefølge (timeline og scrobble)
    @ObservationIgnored private var reports: Task<Void, Never>?
    private let defaults = TestSupport.defaults

    private static let useKey = "plex-filmer"

    private struct Saved: Codable {
        var token: String
        var server: PlexServer?
        var uri: String?
    }

    init() {
        let defaults = TestSupport.defaults
        let idKey = "plex-klient"
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        #if os(tvOS)
        let platform = "tvOS"
        #else
        let platform = "iOS"
        #endif
        let device = PlexDevice(clientId: id, platform: platform, deviceName: UIDevice.current.name,
                                version: appVersion)
        self.device = device
        account = PlexAccountClient(device: device, base: TestSupport.plexServer ?? "https://plex.tv")
        storedUse = defaults.bool(forKey: Self.useKey)
    }

    /// Kobler til serveren fra sist (i bakgrunnen). Testene: koblet til den falske serveren fra før, unntatt
    /// «plex-link» (der kobles det til med koden).
    func start() {
        if TestSupport.isActive {
            guard TestSupport.plexServer != nil, let screen = TestSupport.screen, screen.hasPrefix("plex"),
                  screen != "plex-link" else { return }
            // fanene venter på Plex i stedet for å vise IPTV-leverandøren først
            phase = .connecting
            useForVOD = true
            Task { await finish(token: "test-token") }
            return
        }
        guard let data = Keychain.loadPlex(), let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return
        }
        token = saved.token
        // fanene venter på Plex (.waiting) i stedet for å vise IPTV-leverandøren først
        phase = .connecting
        if let server = saved.server {
            self.server = server
            Task {
                await connect(server, preferred: saved.uri)
                // serverne på kontoen (for «Bytt server»), i bakgrunnen
                if servers.isEmpty, let found = try? await account.servers(token: saved.token) { servers = found }
            }
        } else {
            Task { await finish(token: saved.token) }
        }
    }

    /// En kode til plex.tv/link; når den er skrevet inn, hentes serverne.
    func link() {
        linkTask?.cancel()
        phase = .connecting
        linkTask = Task {
            do {
                let pin = try await account.createPin()
                phase = .linking(pin.code)
                // koden gjelder et kvarter
                let deadline = Date().addingTimeInterval(15 * 60)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(2))
                    if let token = try await account.token(for: pin) {
                        await finish(token: token)
                        return
                    }
                }
                phase = .failed(L("Koden gikk ut. Prøv igjen."))
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelLink() {
        linkTask?.cancel()
        linkTask = nil
        phase = client != nil ? .connected : .off
    }

    /// Prøver igjen: serveren fra før, eller koden på nytt.
    func retry() {
        if let server {
            Task { await connect(server) }
        } else if let token {
            Task { await finish(token: token) }
        } else {
            link()
        }
    }

    func disconnect() {
        linkTask?.cancel()
        linkTask = nil
        token = nil
        server = nil
        client = nil
        servers = []
        phase = .off
        if !TestSupport.isActive { Keychain.savePlex(nil) }
        if useForVOD {
            useForVOD = false
        } else {
            onChange?()
        }
    }

    /// Velg en annen av serverne på kontoen.
    func chooseServer() {
        guard let token else { return }
        Task { await finish(token: token, choose: true) }
    }

    private func finish(token: String, choose: Bool = false) async {
        self.token = token
        phase = .connecting
        do {
            let found = try await account.servers(token: token)
            servers = found
            save(nil)
            if found.isEmpty {
                phase = .failed(L("Fant ingen Plex-server på kontoen."))
                onChange?()
            } else if found.count == 1 && !choose {
                await connect(found[0])
            } else {
                phase = .choosing
                onChange?()
            }
        } catch {
            // fanene Filmer og Serier venter på Plex: si fra (før ble de stående og laste)
            phase = .failed(error.localizedDescription)
            onChange?()
        }
    }

    /// Kobler til [server]: adressen fra sist hvis den svarer, ellers den beste som svarer (hjemmenettet først).
    func connect(_ server: PlexServer, preferred: String? = nil) async {
        var server = server
        connectGeneration += 1
        let gen = connectGeneration
        phase = .connecting
        var uri: String?
        if let preferred, await PlexClient(base: preferred, token: server.accessToken, device: device).ping() {
            uri = preferred
        } else {
            uri = await PlexClient.reachable(server, device: device)
        }
        // serveren kan ha fått nye adresser siden sist
        if uri == nil, let token,
           let fresh = try? await account.servers(token: token).first(where: { $0.id == server.id }) {
            server = fresh
            uri = await PlexClient.reachable(fresh, device: device)
        }
        guard gen == connectGeneration else { return }
        self.server = server
        guard let uri else {
            AppLog.shared.add("Plex: får ikke kontakt med serveren (\(server.connections.count) adresser)")
            client = nil
            phase = .failed(L("Får ikke kontakt med {name}.", ["name": server.name]))
            save(nil)
            onChange?()
            return
        }
        client = PlexClient(base: uri, token: server.accessToken, device: device)
        phase = .connected
        AppLog.shared.add("Plex: koblet til (\(Self.kind(of: uri, in: server)))")
        save(uri)
        // første gang: filmer og serier fra Plex (kan byttes tilbake i innstillingene)
        if defaults.object(forKey: Self.useKey) == nil || TestSupport.isActive {
            useForVOD = true
        }
        onChange?()
    }

    func use(_ server: PlexServer) {
        Task { await connect(server) }
    }

    /// Appen er framme igjen: finn adressen som svarer nå (kom du hjem, eller dro du hjemmefra, er en annen bedre), og
    /// bytt til den. Før ble adressen fra da appen startet brukt til appen ble lukket, og ute svarte ingenting.
    func reprobe() {
        guard phase == .connected, let server, !probing else { return }
        probing = true
        let gen = connectGeneration
        let device = device
        Task {
            defer { probing = false }
            var uri = await PlexClient.reachable(server, device: device)
            var found = server
            if uri == nil, let token,
               let fresh = try? await account.servers(token: token).first(where: { $0.id == server.id }) {
                found = fresh
                uri = await PlexClient.reachable(fresh, device: device)
            }
            // svarer ingen (nettet er ikke oppe ennå rett etter at enheten våknet): den gamle står; feiler den, kan
            // fanen prøve igjen, og da letes det på nytt
            guard gen == connectGeneration, phase == .connected, let uri, uri != client?.base else { return }
            self.server = found
            client = PlexClient(base: uri, token: found.accessToken, device: device)
            save(uri)
            onChange?()
        }
    }

    /// «hjemme», «hjemme, http», «utenfra» eller «relé» (til loggen; adressen selv står ikke der).
    static func kind(of uri: String, in server: PlexServer) -> String {
        if let c = server.connections.first(where: { $0.uri == uri }) {
            return c.relay ? "relé" : (c.local ? "hjemme" : "utenfra")
        }
        return uri.hasPrefix("http://") ? "hjemme, http" : "annen adresse"
    }

    private func save(_ uri: String?) {
        guard !TestSupport.isActive, let token else { return }
        let saved = Saved(token: token, server: server, uri: uri)
        Keychain.savePlex(try? JSONEncoder().encode(saved))
    }

    /// Hvor langt du har sett, tilbake til Plex; [finished]: merk som sett.
    func report(_ ratingKey: String, time: Double, duration: Double, state: PlexClient.PlayState, finished: Bool) {
        guard let client else { return }
        // i rekkefølge: før kunne «pause» komme fram etter «stoppet», og økta ble hengende i Plex og Tautulli
        let previous = reports
        reports = Task.detached {
            await previous?.value
            await client.timeline(ratingKey, state: state, time: time, duration: duration)
            if finished { await client.scrobble(ratingKey) }
        }
    }
}
