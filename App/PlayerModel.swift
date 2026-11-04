import AVFoundation
import FyrlysCore
import Foundation
import Observation

/// Avspillingen av én kanal om gangen med AVPlayer (HLS rett fra leverandøren, eller en egen strøm). Nye forsøk ved
/// brudd og når bildet står fast, tre i minuttet (etter 2, 5 og 10 sekunder); så en forklaring (alle tilkoblingene i
/// bruk, HTTP-koden, eller det AVPlayer sa). En egen strøm (NRK direkte, egne strømmer) som ikke virker, byttes med
/// leverandørens. Kanalbytte med fjernkontrollen åpner strømmen litt etter, så rask blaing bare åpner den siste
/// (leverandøren gir ofte bare én tilkobling).
@MainActor
@Observable
final class PlayerModel {
    let player = AVPlayer()
    private(set) var channel: Channel
    let list: [Channel]
    private(set) var error: String?
    /// iPhone/iPad: AVKit sin egen fullskjerm er framme (siden under forsvinner da, men spilleren skal ikke stoppes)
    @ObservationIgnored var inFullScreen = false
    /// spilleren skal lukkes (når programmet skal ses fra start)
    private(set) var closeRequested = false
    /// UI-testene: adressene som er prøvd (stien), så testen ser at en egen strøm som ikke virker, byttes med
    /// leverandørens
    private(set) var tried: [String] = []

    private let app: AppModel
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var waitingObservation: NSKeyValueObservation?
    @ObservationIgnored private var notes: [NSObjectProtocol] = []
    @ObservationIgnored private var failures: [Date] = []
    @ObservationIgnored private var generation = 0
    /// bildet venter (laster eller står fast): åpnes på nytt når det har ventet for lenge
    @ObservationIgnored private var stallTimer: Task<Void, Never>?
    /// programinfoen i kontrollene oppdateres når programmet bytter
    @ObservationIgnored private var programTimer: Task<Void, Never>?
    /// kanalbytte: strømmen åpnes litt etter
    @ObservationIgnored private var pendingOpen: Task<Void, Never>?
    /// kanalene der den egne strømmen ikke virket: leverandørens så lenge spilleren er åpen
    @ObservationIgnored private var providerOnly = Set<String>()
    /// det som spilles, er leverandørens strøm (ikke en egen)
    @ObservationIgnored private var playingProvider = true
    /// spilleren er stoppet (lukket)
    @ObservationIgnored private var stopped = false

    static let triesPerMinute = 3
    /// så lenge bildet kan vente (laste eller stå fast) før kanalen åpnes på nytt
    static let stallLimit: Duration = .seconds(25)
    /// ventetiden ved kanalbytte med fjernkontrollen (flere trykk på rad åpner bare den siste)
    static let switchDelay: Duration = .milliseconds(300)

    init(app: AppModel, channel: Channel, list: [Channel]) {
        self.app = app
        self.channel = channel
        self.list = list
    }

    var isFavorite: Bool { app.isFavorite(channel) }

    func open(_ channel: Channel) {
        pendingOpen?.cancel()
        pendingOpen = nil
        // en annen kanal begynner med blanke ark (før kunne feilene på forrige kanal gi feilmelding med en gang)
        if channel.id != self.channel.id { failures = [] }
        let provider = app.client?.liveURL(channel)
        var url = app.streamURL(channel)
        if providerOnly.contains(channel.id), let provider { url = provider }
        guard let url else { return }
        playingProvider = url == provider
        if TestSupport.isActive { tried.append(url.path) }
        AppLog.shared.add("TV: kanal \(channel.id) fra \(playingProvider ? "leverandøren" : "egen strøm") \(url.pathExtension)")
        self.channel = channel
        error = nil
        stopped = false
        generation += 1
        let gen = generation
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: xtreamUserAgent])
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = metadata()
        stopObserving()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed, let self else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor in self.failed(gen, message) }
        }
        waitingObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            let status = player.timeControlStatus
            Task { @MainActor in self.playback(status, gen) }
        }
        let center = NotificationCenter.default
        notes = [
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item,
                               queue: .main) { [weak self] note in
                guard let self else { return }
                let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription
                Task { @MainActor in self.failed(gen, message) }
            },
            // en direktesending skal ikke ta slutt: da åpnes den igjen
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                               queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.failed(gen, nil) }
            },
        ]
        player.replaceCurrentItem(with: item)
        player.play()
        app.played(channel)
        app.programs.refresh(channel)
        scheduleProgramRefresh()
    }

    /// Prøv igjen (knappen etter en feil).
    func retry() {
        failures = []
        open(channel)
    }

    /// Neste (1) eller forrige (-1) kanal i lista.
    func step(_ delta: Int) {
        guard let next = neighbor(delta), next.id != channel.id else { return }
        switchTo(next)
    }

    /// En kanal fra lista i spilleren: den som spilles allerede, åpnes ikke på nytt (bare etter en feil).
    func choose(_ next: Channel) {
        if next.id == channel.id {
            if error != nil || player.currentItem == nil { retry() }
            return
        }
        switchTo(next)
    }

    /// Bytter kanal: navnet og programmet straks, strømmen litt etter (trykkes det flere ganger på rad, åpnes bare den
    /// siste). Den forrige stoppes med en gang, så tilkoblingen hos leverandøren er ledig.
    private func switchTo(_ next: Channel) {
        failures = []
        generation += 1
        stallTimer?.cancel()
        stallTimer = nil
        stopObserving()
        player.replaceCurrentItem(with: nil)
        channel = next
        error = nil
        pendingOpen?.cancel()
        pendingOpen = Task { [weak self] in
            try? await Task.sleep(for: Self.switchDelay)
            guard let self, !Task.isCancelled, !self.stopped, self.channel.id == next.id else { return }
            self.open(next)
        }
    }

    /// Kanalen [delta] plasser fra denne i lista (rundt fra slutten til starten).
    func neighbor(_ delta: Int) -> Channel? {
        guard !list.isEmpty else { return nil }
        let index = list.firstIndex { $0.id == channel.id } ?? 0
        return list[((index + delta) % list.count + list.count) % list.count]
    }

    /// Programmet som går nå på [channel] (for forhåndsvisningen ved kanalbytte).
    func nowPlaying(_ channel: Channel) -> Program? {
        nowAndNext(app.programs.programs(for: channel), at: Date()).now
    }

    func toggleFavorite() { app.toggleFavorite(channel) }

    /// Kanalen har TV-arkiv, og det er kjent hva som går nå.
    var canStartOver: Bool { channel.archiveDays > 0 && nowPlaying(channel) != nil }

    /// Programmet som går nå, fra start: direktesendingen stoppes og spilleren lukkes, så spilles det fra arkivet.
    /// Er spilleren lukket eller kanalen byttet før arkivet har svart, skjer ingenting.
    func startOver() {
        guard let program = nowPlaying(channel) else { return }
        let channel = channel
        Task {
            guard let play = await app.archivePlay(channel, program), !stopped, self.channel.id == channel.id else {
                return
            }
            app.pendingReplay = play
            stop()
            closeRequested = true
        }
    }

    func stop() {
        stopped = true
        generation += 1
        pendingOpen?.cancel()
        pendingOpen = nil
        stallTimer?.cancel()
        stallTimer = nil
        programTimer?.cancel()
        programTimer = nil
        stopObserving()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func stopObserving() {
        statusObservation?.invalidate()
        statusObservation = nil
        waitingObservation?.invalidate()
        waitingObservation = nil
        for note in notes { NotificationCenter.default.removeObserver(note) }
        notes = []
    }

    /// Spilleren venter (laster eller står fast) eller spiller: venter den for lenge, åpnes kanalen på nytt (før sto
    /// bildet fast for alltid når leverandøren sluttet å sende uten å melde feil). Pause stopper ikke noe.
    private func playback(_ status: AVPlayer.TimeControlStatus, _ gen: Int) {
        guard gen == generation else { return }
        guard status == .waitingToPlayAtSpecifiedRate else {
            stallTimer?.cancel()
            stallTimer = nil
            return
        }
        guard stallTimer == nil else { return }
        stallTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.stallLimit)
            guard let self, !Task.isCancelled, gen == self.generation,
                  self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            self.stallTimer = nil
            self.failed(gen, L("Sendingen stoppet opp"))
        }
    }

    private func failed(_ gen: Int, _ message: String?) {
        guard gen == generation, error == nil else { return }
        let now = Date()
        failures = failures.filter { now.timeIntervalSince($0) < 60 } + [now]
        generation += 1
        let next = generation
        stallTimer?.cancel()
        stallTimer = nil
        // en egen strøm som feiler to ganger: leverandørens strøm for kanalen (NRK-strømmen kan være nede eller
        // stengt der du er; før ble kanalen da ikke å se i det hele tatt)
        if !playingProvider, failures.count >= 2, app.client != nil {
            providerOnly.insert(channel.id)
            failures = []
            open(channel)
            return
        }
        if failures.count <= Self.triesPerMinute {
            let wait: [Double] = [2, 5, 10]
            let seconds = wait[min(failures.count, wait.count) - 1]
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard next == self.generation else { return }
                self.open(self.channel)
            }
        } else {
            player.pause()
            // feilen med en gang (med knappene), og forklaringen når den er funnet; overskriften over sier alt at
            // kanalen ikke kunne spilles, så her står bare hvorfor (før sto «Kanalen kunne ikke spilles» to ganger)
            error = message.map { app.client?.redact($0) ?? $0 } ?? L("Sendingen stoppet opp")
            AppLog.shared.add("TV: kanal \(channel.id) kunne ikke spilles: \(error ?? "")")
            let code = Self.httpCode(player.currentItem)
            Task { await explain(next, code) }
        }
    }

    /// Hvorfor: alle tilkoblingene i bruk (leverandørens strøm), eller HTTP-koden fra strømmen.
    private func explain(_ gen: Int, _ code: Int?) async {
        var text: String?
        if playingProvider, let client = app.client {
            let account = await withTimeout(8) { try? await client.account() }
            if let account, account.maxConnections > 0, account.activeConnections >= account.maxConnections {
                text = L("Alle tilkoblingene i abonnementet er i bruk akkurat nå. Ser noen på en annen enhet?")
            }
        }
        if text == nil {
            var status = code
            if status == nil, let url = player.currentItem.flatMap({ ($0.asset as? AVURLAsset)?.url }) {
                status = await withTimeout(8) { await PlayerModel.streamStatus(url) }
            }
            if let status, status >= 400 {
                text = (playingProvider ? L("IPTV-serveren svarte HTTP {code}", ["code": status])
                    : L("Strømmen svarte HTTP {code}", ["code": status])) + "."
            }
        }
        guard gen == generation, error != nil, let text else { return }
        error = text
        AppLog.shared.add("TV: \(text)")
    }

    /// HTTP-koden i feilloggen til AVPlayer («HTTP 404: File Not Found»), uten en ny forespørsel mot strømmen.
    private static func httpCode(_ item: AVPlayerItem?) -> Int? {
        guard let events = item?.errorLog()?.events else { return nil }
        for event in events.reversed() {
            if let comment = event.errorComment,
               let range = comment.range(of: #"HTTP [0-9]{3}"#, options: .regularExpression) {
                return Int(comment[range].dropFirst(5))
            }
            if (400..<600).contains(event.errorStatusCode) { return event.errorStatusCode }
        }
        return nil
    }

    /// Bare svaret (HTTP-koden), ikke selve strømmen.
    private nonisolated static func streamStatus(_ url: URL) async -> Int? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(xtreamUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            bytes.task.cancel()
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    /// Kanalen og programmet som går nå, i infoen til spilleren.
    func metadata() -> [AVMetadataItem] {
        var items = [Self.meta(.commonIdentifierTitle, nameParts(channel.name).main)]
        if let now = nowAndNext(app.programs.programs(for: channel), at: Date()).now {
            items.append(Self.meta(.iTunesMetadataTrackSubTitle, "\(hhmm(now.start))–\(hhmm(now.stop))  \(now.title)"))
            if !now.description.isEmpty {
                items.append(Self.meta(.commonIdentifierDescription, now.description))
            }
        }
        return items
    }

    func refreshMetadata() {
        player.currentItem?.externalMetadata = metadata()
    }

    /// Når programmet som går nå er slutt: ny programinfo i kontrollene (før sto programmet fra da kanalen ble åpnet,
    /// så lenge man så på), og programinfoen hentes på nytt om den er gammel.
    private func scheduleProgramRefresh() {
        programTimer?.cancel()
        programTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.secondsToNextProgram() else { return }
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.refreshMetadata()
                self.app.programs.refresh(self.channel)
            }
        }
    }

    private func secondsToNextProgram() -> Double {
        let now = Date()
        let pair = nowAndNext(app.programs.programs(for: channel), at: now)
        let change = pair.now?.stop ?? pair.next?.start ?? now.addingTimeInterval(300)
        return min(max(change.timeIntervalSince(now) + 2, 10), 900)
    }

    private static func meta(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// [work], men høyst [seconds] sekunder (nil når tiden gikk ut).
func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
