import AVKit
import FyrlysCore
import SwiftUI

// ── spilleren for filmer, episoder og TV-arkivet ──

/// Det som spilles: adressene som prøves etter tur (filtypen hos leverandøren; se `playAttempts`), og hvor det skal
/// begynne.
struct VODPlay: Identifiable {
    let id: String
    let urls: [URL]
    let title: String
    let subtitle: String
    let progressKey: String
    let start: Double
    /// filmen eller serien (for «Fortsett å se»); nil for TV-arkivet
    var item: VODItem?
    /// Plex: ratingKey for filmen eller episoden (hvor langt du har sett, sendes til Plex)
    var plex: String?
    /// episoden (til «Fortsett å se», og forrige og neste episode)
    var episode: Episode?
    /// et bredt bilde til «Fortsett å se» (bakgrunnen til filmen eller serien)
    var image: String?
    /// serien: sesongene med episodene (forrige og neste episode); nil: hentes når spilleren åpnes
    var seasons: [Season]?

    /// Et program fra TV-arkivet, fra start.
    static func archive(_ channel: Channel, _ program: Program, client: XtreamClient, clock: TimeInterval?) -> VODPlay {
        let key = "arkiv:\(channel.id):\(Int(program.start.timeIntervalSince1970))"
        return VODPlay(id: key, urls: client.archiveURLs(channel, program, serverClock: clock),
                       title: nameParts(channel.name).main,
                       subtitle: "\(hhmm(program.start))–\(hhmm(program.stop))  \(program.title)",
                       progressKey: key, start: 0)
    }
}

/// Spilleren for en film, episode eller et program i TV-arkivet: prøver adressene etter tur (Apples avspiller for
/// filtypene den kan, ellers VLC, og VLC til slutt om Apples ikke fikk det til), begynner der du slapp, og husker hvor
/// langt du har sett (hvert tiende sekund og når spilleren lukkes; nær slutten glemmes det, så neste gang begynner fra
/// start). En episode: forrige og neste episode, og når den er ferdig, spilles den neste («Neste: …»). Fra Plex også
/// knappen for introen og rulleteksten (markørene) og undertekstfilene ved siden av fila.
@MainActor
@Observable
final class VODPlayerModel {
    let player = AVPlayer()
    let play: VODPlay
    private(set) var error: String?
    /// VLC spiller (mkv, avi, MPEG-TS …); ellers Apples avspiller
    private(set) var vlc: VLCEngine?
    /// ferdig (og ingen episode etter): spilleren lukkes
    private(set) var finished = false
    /// iPhone/iPad: AVKit sin egen fullskjerm er framme (siden under forsvinner da, men spilleren skal ikke stoppes)
    @ObservationIgnored var inFullScreen = false
    /// Plex: introen eller rulleteksten som spilles nå (knappen for å hoppe over den)
    private(set) var marker: PlexMarker?
    /// sesongene i serien (forrige og neste episode); hentes når spilleren åpnes, om de ikke er med
    private(set) var seasons: [Season]?
    /// episoden er ferdig, og den neste begynner straks («Neste: …»)
    private(set) var upNext: Episode?
    /// Plex: markørene og undertekstfilene hentes før avspillingen begynner
    private(set) var preparing = false
    /// bytter til en annen episode (visningen lager en ny spiller for den)
    @ObservationIgnored var switchTo: ((VODPlay) -> Void)?

    private let app: AppModel
    @ObservationIgnored private var attempts: [PlayAttempt]
    @ObservationIgnored private var index = 0
    /// forsøket som pågår, har kommet i gang (Apples avspiller)
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var notes: [NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var saver: Task<Void, Never>?
    /// Plex: merket som sett (én gang)
    @ObservationIgnored private var scrobbled = false
    /// «stoppet» er sendt til Plex (etter det sendes ingenting mer)
    @ObservationIgnored private var reportedStop = false
    /// der neste forsøk begynner (der du slapp, eller der forbindelsen ble brutt)
    @ObservationIgnored private var resumeAt: Double
    /// brudd midt i (forbindelsen falt): samme adresse prøves igjen der den slapp, to ganger
    @ObservationIgnored private var breaks = 0
    /// Plex: markørene, undertekstfilene ved siden av fila og den som vises fra start
    @ObservationIgnored private var markers: [PlexMarker] = []
    @ObservationIgnored private var subtitles: [PlexSubtitle] = []
    @ObservationIgnored private var chosenSubtitle: PlexSubtitle?
    /// en annen episode hentes (forrige eller neste): én om gangen
    @ObservationIgnored private var switching = false
    /// lukket (stop er kalt)
    @ObservationIgnored private var closed = false

    init(app: AppModel, play: VODPlay) {
        self.app = app
        self.play = play
        attempts = playAttempts(play.urls)
        resumeAt = play.start
        seasons = play.seasons
    }

    /// Plex-fanen, eller filmene eller seriene hos leverandøren, som det som spilles, hører til
    private var library: VODModel {
        if play.plex != nil || play.item?.isPlex == true || play.episode?.source == "plex" { return app.plexVOD }
        return play.episode != nil || play.item?.kind == .series ? app.series : app.movies
    }

    func start() {
        saver = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                self.save()
            }
        }
        // forrige og neste episode: sesongene, når spilleren ble åpnet uten dem (fra Hjem)
        let source = library
        if play.episode != nil, seasons == nil, let show = play.item {
            Task { [weak self] in
                let found = try? await source.details(show)
                guard let self, !self.closed, let found else { return }
                self.seasons = found.seasons
            }
        }
        guard let key = play.plex else {
            open(0)
            return
        }
        preparing = true
        Task { [weak self] in
            let info = await source.playInfo(key)
            guard let self, !self.closed else { return }
            if let info { self.use(info) }
            self.preparing = false
            self.open(0)
        }
    }

    /// Plex: markørene, undertekstfilene og den som vises fra start. Trengs en undertekstfil (på norsk, og fila har
    /// ikke norsk selv), spiller VLC også det Apples avspiller kunne spilt: den kan ikke legge til undertekstfiler.
    private func use(_ info: PlexPlayInfo) {
        markers = info.markers
        subtitles = info.subtitles
        chosenSubtitle = info.chosenSubtitle(preferred: appLanguage == "no" ? norwegianLanguageCodes : [])
        if chosenSubtitle != nil, attempts.first?.engine == .native {
            attempts = attempts.filter { $0.engine == .vlc } + attempts.filter { $0.engine == .native }
        }
    }

    private func open(_ i: Int) {
        guard i < attempts.count else { return }
        index = i
        started = false
        let attempt = attempts[i]
        stopObserving()
        AppLog.shared.add("Spiller \(play.progressKey) med \(attempt.engine == .vlc ? "VLC" : "Apples avspiller") "
                          + "(\(attempt.url.pathExtension), fra \(Int(resumeAt)) s)")
        switch attempt.engine {
        case .native:
            let asset = AVURLAsset(url: attempt.url, options: [AVURLAssetHTTPUserAgentKey: xtreamUserAgent])
            let item = AVPlayerItem(asset: asset)
            item.externalMetadata = [Self.meta(.commonIdentifierTitle, play.title),
                                     Self.meta(.iTunesMetadataTrackSubTitle, play.subtitle)]
            observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let status = item.status
                Task { @MainActor in self?.changed(status, i) }
            }
            notes = [
                // brudd midt i filmen (ikke bare at den ikke kom i gang)
                NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.failed(i) }
                },
                // ferdig: den neste episoden, eller lukk (som VLC)
                NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.ended() }
                },
            ]
            if timeObserver == nil {
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                              queue: .main) { [weak self] time in
                    MainActor.assumeIsolated { self?.tick(time.seconds) }
                }
            }
            player.replaceCurrentItem(with: item)
            player.play()
        case .vlc:
            player.replaceCurrentItem(with: nil)
            let engine = VLCEngine()
            engine.onFail = { [weak self] in self?.failed(i) }
            engine.onEnd = { [weak self] in self?.ended() }
            engine.onTime = { [weak self] t in self?.tick(t) }
            vlc = engine
            engine.open(attempt.url, start: resumeAt, subtitles: subtitles, choose: chosenSubtitle)
        }
    }

    private func stopObserving() {
        observation?.invalidate()
        observation = nil
        for note in notes { NotificationCenter.default.removeObserver(note) }
        notes = []
    }

    private func changed(_ status: AVPlayerItem.Status, _ i: Int) {
        guard i == index else { return }
        if status == .readyToPlay, !started {
            started = true
            if resumeAt > 5 {
                player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
            }
        } else if status == .failed {
            failed(i)
        }
    }

    /// Hvor langt den har kommet (0 når det som spilles nå, ikke har kommet i gang).
    private var position: Double {
        if let vlc { return vlc.started ? vlc.time : 0 }
        let t = player.currentTime().seconds
        return started && t.isFinite ? t : 0
    }

    /// Tiden har gått (Apples avspiller hvert halve sekund, VLC oftere): knappen for introen eller rulleteksten.
    private func tick(_ t: Double) {
        let now = error == nil && upNext == nil && t.isFinite && t > 0 ? markers.first(where: { $0.covers(t) }) : nil
        if now != marker { marker = now }
    }

    // ── episodene ──

    /// Episodene før og etter denne (når sesongene er hentet).
    var around: (previous: Episode?, next: Episode?) {
        guard let episode = play.episode, let seasons else { return (nil, nil) }
        return neighbours(of: episode, in: seasons)
    }

    /// Teksten på knappen for [marker]: «Neste episode» for rulleteksten til slutt når det kommer en etter.
    func skipTitle(_ marker: PlexMarker) -> String {
        if marker.kind == .intro { return L("Hopp over introen") }
        return marker.final && around.next != nil ? L("Neste episode") : L("Hopp over rulleteksten")
    }

    /// Knappen for introen eller rulleteksten: til slutten av den. Rulleteksten til slutt med en episode etter: denne er
    /// sett, og den neste spilles (som i Fyrlys for Windows).
    func skip(_ marker: PlexMarker) {
        if marker.kind == .credits, marker.final, let next = around.next {
            save(final: true, finished: true)
            go(next)
        } else {
            seek(to: marker.end)
        }
        self.marker = nil
    }

    func seek(to seconds: Double) {
        if let vlc {
            vlc.seek(to: seconds)
        } else if started {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero,
                        toleranceAfter: .zero)
        }
    }

    /// Til en annen episode i serien, i samme spiller (der du slapp i den, ellers fra start).
    func go(_ episode: Episode) {
        guard let show = play.item, !switching, !closed else { return }
        switching = true
        let known = seasons, image = play.image, source = library
        Task {
            let next = await source.play(episode, show: show, app: self.app, image: image, seasons: known)
            self.switching = false
            guard !self.closed else { return }
            if let next {
                self.switchTo?(next)
            } else if self.upNext != nil {
                // den neste kunne ikke spilles (ingen fil): lukk
                self.finished = true
            }
        }
    }

    /// Ferdig: den neste episoden etter et lite øyeblikk («Neste: …»), ellers lukkes spilleren.
    private func ended() {
        guard !closed, !finished, upNext == nil else { return }
        save(final: true)
        saver?.cancel()
        saver = nil
        guard let next = around.next else {
            finished = true
            return
        }
        marker = nil
        upNext = next
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.closed, self.upNext == next else { return }
            self.go(next)
        }
    }

    // ── feil ──

    /// Adressen kunne ikke spilles: den neste, eller forklaringen. Ble forbindelsen brutt midt i, prøves samme adresse
    /// igjen der den slapp (to ganger), så kommer feilen med «Prøv igjen» (før begynte neste forsøk på nytt fra der
    /// filmen ble åpnet, og hvor langt du hadde sett, ble skrevet over).
    private func failed(_ i: Int) {
        guard i == index, error == nil else { return }
        let reached = position
        // samme brudd kan meldes to ganger (status og varsel): bare én gang
        stopObserving()
        vlc?.stop()
        AppLog.shared.add("Spiller \(play.progressKey): feil ved \(Int(reached)) s (forsøk \(i + 1) av \(attempts.count))")
        if reached > 5 {
            resumeAt = reached
            breaks += 1
            if breaks <= 2 {
                vlc = nil
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard i == self.index, self.error == nil, !self.closed else { return }
                    self.open(i)
                }
                return
            }
            player.pause()
            marker = nil
            error = L("Avspillingen stoppet ved {time}. Prøv igjen for å fortsette der.", ["time": playTime(reached)])
            return
        }
        if i + 1 < attempts.count {
            vlc = nil
            open(i + 1)
        } else {
            player.pause()
            marker = nil
            error = L(
                "Kunne ikke spilles: leverandøren svarte ikke med filen, eller alle tilkoblingene dine er i bruk.")
        }
    }

    /// «Prøv igjen» etter en feil: fra der du slapp, med den første adressen.
    func retry() {
        guard error != nil else { return }
        error = nil
        breaks = 0
        vlc?.stop()
        vlc = nil
        open(0)
    }

    // ── hvor langt ──

    /// Husker hvor langt du har sett (på enheten, og hos Plex for filmer og serier derfra). [final]: spilleren lukkes
    /// (eller en annen episode begynner). [forced]: sett ferdig, uansett hvor langt det er igjen (rulleteksten til
    /// slutt: «Neste episode»).
    func save(final: Bool = false, finished forced: Bool = false) {
        let t: Double, duration: Double, paused: Bool
        if let vlc {
            guard vlc.started else { return }
            t = vlc.time
            duration = vlc.length
            paused = !vlc.isPlaying
        } else {
            guard started else { return }
            t = player.currentTime().seconds
            duration = player.currentItem?.duration.seconds ?? 0
            paused = player.rate == 0
        }
        guard t.isFinite, t > 30 || forced, !reportedStop else { return }
        if final { reportedStop = true }
        let known = duration.isFinite && duration > 0
        let done = forced || (known && duration - t < 120)
        if done {
            app.setProgress(play.progressKey, nil)
            library.finishedHere.insert(play.progressKey)
            // Plex husker selv hva som er sett (og der kan det merkes som usett igjen)
            if play.plex == nil { app.setFinished(play.progressKey) }
            // en ferdig film tas ut av «Fortsett å se»; en serie står med den neste episoden (kortet spiller den
            // med en gang), eller uten episode etter den siste (siden viser hva som er igjen)
            if let item = play.item, !item.isPlex {
                if item.kind == .movies {
                    app.forgetContinue(item)
                } else if let next = around.next {
                    app.rememberContinue(VODResume(item: item, episode: next, progress: 0, image: play.image))
                } else {
                    app.rememberContinue(VODResume(item: item, image: play.image))
                }
            }
        } else {
            app.setProgress(play.progressKey, t)
            if let item = play.item, !item.isPlex {
                let progress = known ? min(1, t / duration) : 0
                app.rememberContinue(VODResume(item: item, episode: play.episode, progress: progress,
                                               image: play.image))
            }
        }
        if let key = play.plex, !(scrobbled && final) {
            let state: PlexClient.PlayState = final ? .stopped : (paused ? .paused : .playing)
            let markWatched = final && done && !scrobbled
            if markWatched { scrobbled = true }
            app.plex.report(key, time: forced && known ? duration : t, duration: known ? duration : 0, state: state,
                            finished: markWatched)
        }
    }

    func stop() {
        closed = true
        // visningen holdt på denne (og denne på visningen)
        switchTo = nil
        save(final: true)
        saver?.cancel()
        saver = nil
        stopObserving()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        vlc?.stop()
    }

    private static func meta(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Filmen eller episoden i fullskjerm (Apple TV: Menu lukker) eller i et ark (iPhone og iPad: dra ned for å lukke),
/// med Apples avspiller eller VLC. Forrige og neste episode spilles i samme visning (en ny spiller for hver).
struct VODPlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let play: VODPlay
    @State private var model: VODPlayerModel?
    #if !os(tvOS)
    /// telefonen sto liggende før spilleren ble åpnet (da står den slik etterpå også)
    @State private var wasLandscape = false
    /// legger telefonen ned når arket har kommet fram (avbrytes om spilleren lukkes før det)
    @State private var turn: Task<Void, Never>?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                if let error = model.error {
                    VStack(spacing: 24) {
                        Text(model.play.title)
                            .font(.system(size: Metrics.detailTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(error)
                            .font(.system(size: Metrics.detailText))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 30) {
                            Button(L("Prøv igjen")) { model.retry() }
                                .accessibilityIdentifier("vod-igjen")
                            Button(L("Lukk")) { dismiss() }
                        }
                    }
                    .padding(40)
                } else if let vlc = model.vlc {
                    VLCPlayerScreen(engine: vlc, model: model) { dismiss() }
                        // en ny visning for hver VLC (nytt forsøk, ny episode): ellers sto bildet fra den forrige
                        .id(ObjectIdentifier(vlc))
                } else if model.preparing {
                    ProgressView()
                        #if os(tvOS)
                        .scaleEffect(1.5)
                        #else
                        .tint(.white)
                        .controlSize(.large)
                        #endif
                } else {
                    NativePlayer(model: model)
                        .id(ObjectIdentifier(model))
                    #if os(macOS)
                        // Mac: AVPlayerView har ingen lukkeknapp (VLC har sin egen)
                        .overlay(alignment: .topLeading) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                            .help(L("Lukk"))
                            .accessibilityLabel(L("Lukk"))
                            .accessibilityIdentifier("lukk-vod")
                            .padding(14)
                        }
                    #endif
                }
            }
        }
        #if os(macOS)
        .onExitCommand { dismiss() }
        .playerKeys { command in
            guard let model, model.error == nil else { return false }
            switch command {
            case .playPause:
                if let vlc = model.vlc { vlc.togglePause() } else { model.player.togglePlayback() }
            case .back, .forward:
                let step: Double = command == .back ? -10 : 10
                if let vlc = model.vlc { vlc.seek(to: vlc.time + step) } else { model.player.jump(step) }
            case .mute:
                if let vlc = model.vlc { vlc.toggleMute() } else { model.player.isMuted.toggle() }
            case .fullScreen:
                MacFullScreen.toggle()
            case .next, .previous, .mini:
                return false
            }
            return true
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model?.error == nil ? "vod-spiller" : "vod-feil")
        // testene: det som spilles (filmen eller episoden)
        .accessibilityValue(TestSupport.isActive ? (model?.play.progressKey ?? "") : "")
        .onAppear {
            guard model == nil else { return }
            #if os(macOS)
            // én sending om gangen: minispilleren stoppes
            MacMiniPlayer.close()
            MacPlayerState.shared.vod = true
            #endif
            #if !os(tvOS)
            // iPhone: liggende, som i Apple TV-appen (også når skjermretningen er låst); når arket har kommet fram
            // (mens det kommer inn, avvises det)
            wasLandscape = Landscape.isLandscape
            turn = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                Landscape.set(true)
            }
            #endif
            begin(play)
        }
        .onChange(of: model?.finished ?? false) { _, done in
            if done { dismiss() }
        }
        .onDisappear {
            // ikke når AVKit sin egen fullskjerm legger seg over (da forsvinner siden under, men det spilles videre)
            guard model?.inFullScreen != true else { return }
            model?.stop()
            #if os(macOS)
            MacPlayerState.shared.vod = false
            MacFullScreen.leaveIfEntered()
            #endif
            #if !os(tvOS)
            turn?.cancel()
            if !wasLandscape {
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    Landscape.set(false)
                }
            }
            #endif
        }
    }

    /// En spiller for [play]; en annen episode (forrige, neste) får en ny, og den gamle stoppes (hvor langt du kom).
    private func begin(_ play: VODPlay) {
        let player = VODPlayerModel(app: app, play: play)
        player.switchTo = { next in
            model?.stop()
            begin(next)
        }
        model = player
        player.start()
    }
}

/// Apples avspiller med knappen for introen og rulleteksten og «Neste: …» over. Apple TV: knappen er Apple sin egen
/// (som i Apple TV-appen), og forrige og neste episode står i kontrollene.
private struct NativePlayer: View {
    let model: VODPlayerModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VODPlayerController(player: model.player, buttons: buttons) { model.inFullScreen = $0 }
                .ignoresSafeArea()
            #if !os(tvOS)
            if let marker = model.marker {
                SkipButton(title: model.skipTitle(marker)) { model.skip(marker) }
                    .padding(.trailing, 20)
                    .padding(.bottom, 92)
            }
            #endif
            if let next = model.upNext {
                UpNextCard(episode: next)
            }
        }
    }

    private var buttons: PlayerButtons {
        var buttons = PlayerButtons()
        let player = model
        if let marker = player.marker {
            buttons.skip = (player.skipTitle(marker), { player.skip(marker) })
        }
        let around = player.around
        if let previous = around.previous {
            buttons.previous = { player.go(previous) }
        }
        if let next = around.next {
            buttons.next = { player.go(next) }
        }
        return buttons
    }
}

/// «Hopp over introen», «Hopp over rulleteksten» eller «Neste episode» nede til høyre (iPhone og iPad; Apple TV har
/// sin egen i VLC-spilleren og Apple sin i Apples avspiller).
struct SkipButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "forward.end.fill")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.65), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                .foregroundStyle(Color.white)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hopp-over")
    }
}

/// «Neste: S1 E3 · Tåkeluren» når en episode er ferdig og den neste begynner straks.
struct UpNextCard: View {
    let episode: Episode

    var body: some View {
        let code = "S\(episode.season) E\(episode.number)"
        HStack(spacing: Self.font * 0.7) {
            ProgressView()
                .tint(.white)
            Text(L("Neste: {episode}", ["episode": episode.title.isEmpty ? code : "\(code) · \(episode.title)"]))
                .font(.system(size: Self.font, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
        }
        .padding(.horizontal, Self.font * 1.1)
        .padding(.vertical, Self.font * 0.8)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(Self.font * 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("neste-om")
    }

    #if os(tvOS)
    static let font: CGFloat = 30
    #else
    static let font: CGFloat = 16
    #endif
}

/// Knappene Apples avspiller får på Apple TV: hopp over introen eller rulleteksten (Apple sin knapp nede til høyre), og
/// forrige og neste episode i kontrollene.
struct PlayerButtons {
    var skip: (title: String, action: () -> Void)?
    var previous: (() -> Void)?
    var next: (() -> Void)?
}

#if os(macOS)
/// Apples avspiller på Mac: AVPlayerView med Macens egne kontroller, fullskjerm og bilde-i-bilde.
struct VODPlayerController: NSViewRepresentable {
    let player: AVPlayer
    var buttons = PlayerButtons()
    var fullScreen: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#else
struct VODPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    var buttons = PlayerButtons()
    /// AVKit sin fullskjerm kommer eller går (iPhone og iPad)
    var fullScreen: (Bool) -> Void = { _ in }

    func makeCoordinator() -> FullScreenWatcher { FullScreenWatcher() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        #if !os(tvOS)
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        #endif
        context.coordinator.changed = fullScreen
        apply(buttons, to: controller, context.coordinator)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.changed = fullScreen
        if controller.player !== player { controller.player = player }
        apply(buttons, to: controller, context.coordinator)
    }

    /// Setter knappene bare når de er endret (ellers blinket Apple sin knapp hvert halve sekund).
    private func apply(_ buttons: PlayerButtons, to controller: AVPlayerViewController, _ state: FullScreenWatcher) {
        #if os(tvOS)
        let skip = buttons.skip?.title
        if state.skipTitle != skip {
            state.skipTitle = skip
            controller.contextualActions = buttons.skip.map { button in
                [UIAction(title: button.title, image: UIImage(systemName: "forward.end.fill")) { _ in button.action() }]
            } ?? []
        }
        let code = (buttons.previous != nil ? 1 : 0) + (buttons.next != nil ? 2 : 0)
        if state.episodeButtons != code {
            state.episodeButtons = code
            var items: [UIMenuElement] = []
            if let previous = buttons.previous {
                items.append(UIAction(title: L("Forrige episode"), image: UIImage(systemName: "backward.end.fill")) { _ in
                    previous()
                })
            }
            if let next = buttons.next {
                items.append(UIAction(title: L("Neste episode"), image: UIImage(systemName: "forward.end.fill")) { _ in
                    next()
                })
            }
            controller.transportBarCustomMenuItems = items
        }
        #endif
    }
}

/// Sier fra når AVKit sin egen fullskjerm kommer og går, og husker knappene som er satt (Apple TV).
final class FullScreenWatcher: NSObject, AVPlayerViewControllerDelegate {
    var changed: (Bool) -> Void = { _ in }
    var skipTitle: String?
    var episodeButtons = 0

    #if !os(tvOS)
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator
                              coordinator: UIViewControllerTransitionCoordinator) {
        changed(true)
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator
                              coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            if !context.isCancelled { self?.changed(false) }
        }
    }
    #endif
}
#endif
