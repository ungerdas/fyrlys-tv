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
            Task { await connect(server, preferred: saved.uri) }
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
            } else if found.count == 1 && !choose {
                await connect(found[0])
            } else {
                phase = .choosing
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Kobler til [server]: adressen fra sist hvis den svarer, ellers den beste som svarer (hjemmenettet først).
    func connect(_ server: PlexServer, preferred: String? = nil) async {
        var server = server
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
        self.server = server
        guard let uri else {
            client = nil
            phase = .failed(L("Får ikke kontakt med {name}.", ["name": server.name]))
            save(nil)
            onChange?()
            return
        }
        client = PlexClient(base: uri, token: server.accessToken, device: device)
        phase = .connected
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

    private func save(_ uri: String?) {
        guard !TestSupport.isActive, let token else { return }
        let saved = Saved(token: token, server: server, uri: uri)
        Keychain.savePlex(try? JSONEncoder().encode(saved))
    }

    /// Hvor langt du har sett, tilbake til Plex; [finished]: merk som sett.
    func report(_ ratingKey: String, time: Double, duration: Double, state: PlexClient.PlayState, finished: Bool) {
        guard let client else { return }
        Task.detached {
            await client.timeline(ratingKey, state: state, time: time, duration: duration)
            if finished { await client.scrobble(ratingKey) }
        }
    }
}
