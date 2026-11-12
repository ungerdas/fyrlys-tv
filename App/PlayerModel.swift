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
    /// VLC spiller kanalen (MPEG-TS, eller noe Apples avspiller ikke kan); ellers Apples avspiller
    private(set) var vlc: VLCEngine?
    private(set) var channel: Channel
    let list: [Channel]
    private(set) var error: String?
    /// iPhone/iPad: AVKit sin egen fullskjerm er framme (siden under forsvinner da, men spilleren skal ikke stoppes)
    @ObservationIgnored var inFullScreen = false
    /// Mac: sendingen er flyttet til minispilleren (stoppes ikke når spilleren lukkes)
    @ObservationIgnored var detached = false
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
    /// adressen hos leverandøren som prøves per kanal (en M3U-liste kan ha flere: HLS først, så den i lista)
    @ObservationIgnored private var providerStep: [String: Int] = [:]
    /// det som spilles, er leverandørens strøm (ikke en egen)
    @ObservationIgnored private var playingProvider = true
    /// adressen kanalen spilles fra (også når avspilleren spiller fra bufferet på enheten)
    @ObservationIgnored private var sourceURL: URL?
    /// HLS feilet for kanalen (så TS med VLC prøves; virker det, spilles kanalene som TS heretter)
    @ObservationIgnored private var hlsFailed = false
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
        if channel.id != self.channel.id {
            failures = []
            hlsFailed = false
        }
        let urls = app.providerURLs(channel)
        let provider = urls.isEmpty ? nil : urls[min(providerStep[channel.id] ?? 0, urls.count - 1)]
        var url = app.streamURL(channel)
        if providerOnly.contains(channel.id) || providerStep[channel.id] != nil, let provider { url = provider }
        guard let url else { return }
        playingProvider = url == provider
        if TestSupport.isActive { tried.append(url.path) }
        AppLog.shared.add("TV: kanal \(channel.id) fra \(playingProvider ? "leverandøren" : "egen strøm") \(url.pathExtension)")
        self.channel = channel
        error = nil
        stopped = false
        generation += 1
        let gen = generation
        sourceURL = url
        app.played(channel)
        app.programs.refresh(channel)
        scheduleProgramRefresh()
        // pause og tilbakespoling: HLS hentes og bufres på enheten, og avspilleren spiller derfra (det som ikke kan
        // bufres, spilles rett fra leverandøren som før)
        if app.liveShift, LiveShift.applies(to: url) {
            // den forrige kanalen slipper tilkoblingen med en gang
            stopObserving()
            player.replaceCurrentItem(with: nil)
            Task {
                let local = await LiveShift.shared.prepare(url)
                guard gen == self.generation, !self.stopped else { return }
                if TestSupport.isActive, let local { self.tried.append(local.path) }
                self.play(local ?? url, gen)
            }
            return
        }
        Task { await LiveShift.shared.stop() }
        if isHLS(url) {
            play(url, gen)
        } else {
            playVLC(url, gen)
        }
    }

    /// VLC med [url]: MPEG-TS fra leverandøren (Apples avspiller kan ikke spille det), som i Fyrlys for Windows.
    private func playVLC(_ url: URL, _ gen: Int) {
        stopObserving()
        player.replaceCurrentItem(with: nil)
        vlc?.stop()
        let engine = VLCEngine()
        let channel = self.channel
        let afterHLS = hlsFailed
        engine.onFail = { [weak self] in self?.failed(gen, L("Strømmen kunne ikke spilles.")) }
        // en direktesending skal ikke ta slutt: åpnes igjen
        engine.onEnd = { [weak self] in self?.failed(gen, nil) }
        var started = false
        engine.onTime = { [weak self] _ in
            guard !started, let self, gen == self.generation else { return }
            started = true
            self.failures = []
            self.app.liveWorked(channel, from: url, afterHLSFailed: afterHLS)
            AppLog.shared.add("TV: kanal \(channel.id) spiller med VLC")
        }
        vlc = engine
        engine.open(url, start: 0)
    }

    /// Avspilleren med [url] (fra leverandøren, en egen strøm, eller bufferet på enheten).
    private func play(_ url: URL, _ gen: Int) {
        if let vlc {
            vlc.stop()
            self.vlc = nil
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: ProviderAgent.current])
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
        vlc?.stop()
        vlc = nil
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

    /// Bildeformatet for kanalen (huskes per kanal).
    var pictureFormat: PictureFormat { app.pictureFormat(for: channel) }

    func setPictureFormat(_ format: PictureFormat) { app.setPictureFormat(format, for: channel) }

    /// Det avspilleren vet om strømmen nå: oppløsningen, kodekene, bilder i sekundet, bitraten og tapte bilder.
    func streamInfo() -> StreamInfo {
        var info = StreamInfo()
        guard let item = player.currentItem else { return info }
        let size = item.presentationSize
        if size.width > 0, size.height > 0 {
            info.width = Int(size.width.rounded())
            info.height = Int(size.height.rounded())
        }
        if let event = item.accessLog()?.events.last {
            if event.indicatedBitrate > 0 {
                info.bitrate = event.indicatedBitrate
            } else if event.observedBitrate > 0 {
                info.bitrate = event.observedBitrate
            }
            info.dropped = max(0, event.numberOfDroppedVideoFrames)
            info.stalls = max(0, event.numberOfStalls)
        }
        for track in item.tracks {
            guard let asset = track.assetTrack else { continue }
            let descriptions = asset.formatDescriptions.map { $0 as! CMFormatDescription }
            if asset.mediaType == .video {
                if let first = descriptions.first {
                    info.videoCodec = fourCCText(CMFormatDescriptionGetMediaSubType(first))
                }
                if track.currentVideoFrameRate > 0 { info.fps = Double(track.currentVideoFrameRate) }
            } else if asset.mediaType == .audio, info.audioCodec == nil, track.isEnabled {
                if let first = descriptions.first {
                    info.audioCodec = fourCCText(CMFormatDescriptionGetMediaSubType(first))
                    if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee,
                       basic.mChannelsPerFrame > 0 {
                        info.audioChannels = Int(basic.mChannelsPerFrame)
                    }
                }
            }
        }
        return info
    }

    /// Multiview kan åpnes (to innlogginger, eller et abonnement med flere tilkoblinger).
    var canMultiview: Bool { app.multiviewAvailable }

    /// Multiview med kanalen i det første bildet: direktesendingen stoppes og spilleren lukkes først (den bruker en
    /// tilkobling), og HomeView viser multiview når spilleren er borte.
    func openMultiview() {
        app.pendingMultiview = MultiviewRequest(channel: channel)
        stop()
        closeRequested = true
    }

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
        Task { await LiveShift.shared.stop() }
        pendingOpen?.cancel()
        pendingOpen = nil
        stallTimer?.cancel()
        stallTimer = nil
        programTimer?.cancel()
        programTimer = nil
        stopObserving()
        player.pause()
        player.replaceCurrentItem(with: nil)
        vlc?.stop()
        vlc = nil
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
        if !playingProvider, failures.count >= 2, !app.providerURLs(channel).isEmpty {
            providerOnly.insert(channel.id)
            failures = []
            open(channel)
            return
        }
        // leverandørens adresse feiler to ganger, og det finnes en til (MPEG-TS med VLC når HLS ikke virket, eller
        // adressen i M3U-lista); med en gang når serveren svarte 4xx (HLS er ikke med i abonnementet o.l.)
        let step = providerStep[channel.id] ?? 0
        let refused = vlc == nil && (Self.httpCode(player.currentItem).map { (400..<500).contains($0) } ?? false)
        if playingProvider, failures.count >= 2 || refused, step + 1 < app.providerURLs(channel).count {
            if let url = sourceURL, isHLS(url) { hlsFailed = true }
            AppLog.shared.add("TV: kanal \(channel.id): prøver \(app.providerURLs(channel)[step + 1].pathExtension)")
            providerStep[channel.id] = step + 1
            failures = []
            open(channel)
            return
        }
        if failures.count <= Self.triesPerMinute {
            let wait: [Double] = [2, 5, 10]
            let seconds = wait[min(failures.count, wait.count) - 1]
            vlc?.stop()
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard next == self.generation else { return }
                self.open(self.channel)
            }
        } else {
            player.pause()
            vlc?.stop()
            vlc = nil
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
            if status == nil, let url = sourceURL ?? player.currentItem.flatMap({ ($0.asset as? AVURLAsset)?.url }) {
                status = await withTimeout(8) { await PlayerModel.streamStatus(url) }
            }
            if let status {
                text = channelStatusProblem(status, provider: playingProvider)
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
        request.setValue(ProviderAgent.current, forHTTPHeaderField: "User-Agent")
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
