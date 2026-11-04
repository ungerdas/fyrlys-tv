import AVFoundation
import FyrlysCore
import SwiftUI
import UIKit

// Multiview: opptil fire kanaler samtidig, som i Fyrlys for Windows (`lib/ui/multiview_page.dart`). Hvert bilde bruker
// én tilkobling: innloggingene i rekkefølge (den i bruk først), så mange bilder som hver av dem har tilkoblinger til,
// høyst fire. Lyden kommer bare fra det valgte bildet. Ingenting huskes, og kanalene kommer ikke i «Sist sett».

/// Multiview vises (fra hurtigmenyen på et kort, eller fra spilleren), med [channel] i det første bildet.
struct MultiviewRequest: Identifiable {
    let id = UUID()
    let channel: Channel?
}

/// Ett bilde: kanalen, avspilleren og feilen. Prøver adressen to ganger med tre sekunder imellom, så den neste
/// adressen, og så forklaringen; stopper bildet etter at det har kommet i gang, åpnes det igjen etter halvannet
/// sekund (høyst tre ganger i minuttet), så «Kanalen stoppet.».
@MainActor
@Observable
final class MultiviewTile: Identifiable {
    let id: Int
    let login: Login
    private(set) var channel: Channel?
    private(set) var error: String?
    /// programmet som går nå (for en annen innlogging enn den i bruk; ellers fra ProgramStore)
    private(set) var programs: [Program] = []
    let player = AVPlayer()
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var urls: [URL] = []
    @ObservationIgnored private var urlIndex = 0
    @ObservationIgnored private var tries = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var restarts: [Date] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notes: [NSObjectProtocol] = []
    @ObservationIgnored private var stallTimer: Task<Void, Never>?

    init(id: Int, login: Login, app: AppModel) {
        self.id = id
        self.login = login
        self.app = app
        player.isMuted = true
    }

    /// Innloggingen er den som er i bruk (kanallista, programinfoen og de egne strømmene derfra).
    var isActiveLogin: Bool { app?.login?.id == login.id }

    func open(_ channel: Channel) {
        guard let app else { return }
        if isActiveLogin {
            // en egen strøm (NRK) først, så leverandørens
            var found = app.streamURL(channel).map { [$0] } ?? []
            for url in app.providerURLs(channel) where !found.contains(url) { found.append(url) }
            urls = found
        } else if let m3u = channel.m3u {
            urls = m3uPlayURLs(m3u.url)
        } else {
            urls = [XtreamClient(login: login).liveURL(channel)]
        }
        self.channel = channel
        urlIndex = 0
        tries = 0
        restarts = []
        programs = []
        AppLog.shared.add("Multiview: bilde \(id + 1), kanal \(channel.id)")
        play()
        loadPrograms(channel)
    }

    func retry() {
        guard let channel else { return }
        open(channel)
    }

    func stop() {
        generation += 1
        stallTimer?.cancel()
        stallTimer = nil
        stopObserving()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// Det som går nå på kanalen.
    var now: Program? {
        guard let channel else { return nil }
        let list = isActiveLogin ? (app?.programs.programs(for: channel) ?? []) : programs
        return nowAndNext(list, at: Date()).now
    }

    private func play() {
        guard urlIndex < urls.count else { return }
        error = nil
        started = false
        generation += 1
        let gen = generation
        stopObserving()
        let asset = AVURLAsset(url: urls[urlIndex], options: [AVURLAssetHTTPUserAgentKey: xtreamUserAgent])
        let item = AVPlayerItem(asset: asset)
        observations = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let status = item.status
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    if status == .failed { self.failed() } else if status == .readyToPlay { self.started = true }
                }
            },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    self.playback(status, gen)
                }
            },
        ]
        let center = NotificationCenter.default
        notes = [
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    self.failed()
                }
            },
            // en direktesending skal ikke ta slutt
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self, gen == self.generation else { return }
                    self.failed()
                }
            },
        ]
        player.replaceCurrentItem(with: item)
        player.play()
    }

    /// Bildet venter for lenge (laster eller står fast): som en feil.
    private func playback(_ status: AVPlayer.TimeControlStatus, _ gen: Int) {
        if status == .playing { started = true }
        guard status == .waitingToPlayAtSpecifiedRate else {
            stallTimer?.cancel()
            stallTimer = nil
            return
        }
        guard stallTimer == nil else { return }
        stallTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled, gen == self.generation,
                  self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            self.stallTimer = nil
            self.failed()
        }
    }

    private func failed() {
        guard error == nil else { return }
        stallTimer?.cancel()
        stallTimer = nil
        generation += 1
        let gen = generation
        if started {
            // stoppet etter at det var i gang: på nytt etter halvannet sekund, høyst tre ganger i minuttet
            let now = Date()
            restarts = restarts.filter { now.timeIntervalSince($0) < 60 } + [now]
            guard restarts.count <= 3 else {
                show(L("Kanalen stoppet."))
                return
            }
            after(1.5, gen) { $0.play() }
            return
        }
        tries += 1
        if tries < 2 {
            after(3, gen) { $0.play() }
        } else if urlIndex + 1 < urls.count {
            urlIndex += 1
            tries = 0
            play()
        } else {
            let code = Self.httpCode(player.currentItem)
            show(code.map { L("IPTV-serveren svarte HTTP {code}", ["code": $0]) + "." } ?? L("Kanalen kunne ikke spilles"))
        }
    }

    private func show(_ message: String) {
        player.pause()
        error = message
        AppLog.shared.add("Multiview: bilde \(id + 1): \(message)")
    }

    private func after(_ seconds: Double, _ gen: Int, _ work: @escaping (MultiviewTile) -> Void) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, gen == self.generation else { return }
            work(self)
        }
    }

    private func stopObserving() {
        for observation in observations { observation.invalidate() }
        observations = []
        for note in notes { NotificationCenter.default.removeObserver(note) }
        notes = []
    }

    /// Programinfoen: fra ProgramStore for den som er i bruk, ellers rett fra leverandøren (Xtream).
    private func loadPrograms(_ channel: Channel) {
        guard let app else { return }
        if isActiveLogin {
            app.programs.refresh(channel)
            return
        }
        guard !login.isM3U, channel.wantsEpg else { return }
        let client = XtreamClient(login: login)
        let gen = generation
        Task { [weak self] in
            let found = (try? await client.epg(channel, limit: 4)) ?? []
            guard let self, self.channel?.id == channel.id, gen <= self.generation else { return }
            self.programs = found
        }
    }

    /// HTTP-koden i feilloggen til AVPlayer.
    private static func httpCode(_ item: AVPlayerItem?) -> Int? {
        guard let events = item?.errorLog()?.events else { return nil }
        for event in events.reversed() where (400..<600).contains(event.errorStatusCode) {
            return event.errorStatusCode
        }
        return nil
    }
}

/// Bildene, det valgte (lyden kommer derfra) og det store bildet.
@MainActor
@Observable
final class MultiviewModel {
    enum Phase: Equatable { case connecting, ready, tooFew }

    private(set) var phase: Phase = .connecting
    private(set) var tiles: [MultiviewTile] = []
    /// det valgte bildet (lyden kommer derfra)
    private(set) var selected = 0
    /// det ene bildet over hele skjermen (nil: alle bildene)
    var big: Int?
    private(set) var muted = false
    /// bildene er fra flere innlogginger (navnet står da ved kanalen)
    private(set) var severalLogins = false
    private let app: AppModel

    static let maxTiles = 4

    init(app: AppModel) {
        self.app = app
    }

    /// Spør abonnementene hvor mange tilkoblinger de har, og lager bildene.
    func start(first: Channel?) async {
        let logins = app.multiviewLogins
        let counts = await withTaskGroup(of: (Int, Int).self) { group in
            for (index, login) in logins.enumerated() {
                group.addTask { @MainActor [app] in (index, await app.connections(of: login)) }
            }
            var found = [Int](repeating: 1, count: logins.count)
            for await (index, count) in group { found[index] = count }
            return found
        }
        var made: [MultiviewTile] = []
        for (index, login) in logins.enumerated() {
            for _ in 0..<max(1, counts[index]) where made.count < Self.maxTiles {
                made.append(MultiviewTile(id: made.count, login: login, app: app))
            }
        }
        guard made.count >= 2 else {
            phase = .tooFew
            return
        }
        tiles = made
        severalLogins = Set(made.map(\.login.id)).count > 1
        phase = .ready
        if let first { made[0].open(first) }
        updateAudio()
    }

    func toggleBig(_ index: Int) {
        big = big == index ? nil : index
    }

    /// Lyden fra bildet [index].
    func select(_ index: Int) {
        guard selected != index else { return }
        selected = index
        updateAudio()
    }

    func toggleMute() {
        muted.toggle()
        updateAudio()
    }

    func stop() {
        for tile in tiles { tile.stop() }
    }

    private func updateAudio() {
        for tile in tiles { tile.player.isMuted = muted || tile.id != selected }
    }
}

// ── visningene ──

/// Multiview over hele skjermen: to bilder ved siden av hverandre (over hverandre når skjermen står), tre eller fire i
/// to rader. Apple TV: fokus velger bildet (og lyden), trykk gir stort bilde (eller kanalvalget for et tomt bilde),
/// hold inne for å bytte kanal, Menu tilbake. iPhone og iPad: trykk velger, dobbelttrykk gir stort bilde, hold inne
/// for å bytte kanal.
struct MultiviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: MultiviewRequest
    @State private var model: MultiviewModel?
    @State private var picking: MultiviewTile?
    #if os(tvOS)
    @FocusState private var focus: Int?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                switch model.phase {
                case .connecting:
                    VStack(spacing: 24) {
                        ProgressView()
                        Text(L("Kobler til abonnementene …"))
                            .font(.system(size: Self.text + 4))
                            .foregroundStyle(Theme.muted)
                    }
                case .tooFew:
                    tooFew
                case .ready:
                    grid(model)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("multiview")
        .onAppear {
            guard model == nil else { return }
            let made = MultiviewModel(app: app)
            model = made
            Task { await made.start(first: request.channel) }
        }
        .onDisappear { model?.stop() }
        .sheet(item: $picking) { tile in
            MultiviewPicker(tile: tile, severalLogins: model?.severalLogins ?? false) { channel in
                picking = nil
                if let channel { tile.open(channel) }
            }
            .environment(app)
        }
        #if os(tvOS)
        .onExitCommand {
            if model?.big != nil {
                model?.big = nil
            } else {
                dismiss()
            }
        }
        .onChange(of: focus) { _, now in
            if let now { model?.select(now) }
        }
        #endif
    }

    private var tooFew: some View {
        VStack(spacing: 28) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: Self.text * 3))
                .foregroundStyle(Theme.muted)
            Text(L("Fant bare én tilkobling. Legg til et abonnement til i innstillingene."))
                .font(.system(size: Self.text + 4, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            Button(L("Lukk")) { dismiss() }
                .accessibilityIdentifier("lukk-multiview")
        }
        .padding(40)
    }

    private func grid(_ model: MultiviewModel) -> some View {
        GeometryReader { geometry in
            let frames = Self.frames(in: geometry.size, count: model.tiles.count)
            ZStack(alignment: .topLeading) {
                if model.tiles.count == 3 {
                    // det fjerde feltet er svart
                    let empty = Self.cell(3, of: geometry.size)
                    Color.black.frame(width: empty.width, height: empty.height).offset(x: empty.minX, y: empty.minY)
                }
                ForEach(model.tiles) { tile in
                    let isBig = model.big == tile.id
                    let hidden = model.big != nil && !isBig
                    let frame = isBig ? CGRect(origin: .zero, size: geometry.size) : frames[tile.id]
                    tileView(tile, model: model, big: isBig)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(hidden ? 0 : 1)
                        .disabled(hidden)
                        .zIndex(isBig ? 1 : 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        #if os(tvOS)
        .ignoresSafeArea()
        #else
        .safeAreaInset(edge: .top, spacing: 0) { topBar(model) }
        .ignoresSafeArea(edges: .bottom)
        #endif
    }

    /// Feltene: to ved siden av hverandre (over hverandre når skjermen er høyere enn den er bred), ellers to rader.
    static func frames(in size: CGSize, count: Int) -> [CGRect] {
        let gap: CGFloat = 4
        if count <= 2 {
            if size.height > size.width {
                let h = (size.height - gap) / 2
                return (0..<count).map { CGRect(x: 0, y: CGFloat($0) * (h + gap), width: size.width, height: h) }
            }
            let w = (size.width - gap) / 2
            return (0..<count).map { CGRect(x: CGFloat($0) * (w + gap), y: 0, width: w, height: size.height) }
        }
        return (0..<count).map { cell($0, of: size) }
    }

    /// Felt [index] av fire (to rader).
    static func cell(_ index: Int, of size: CGSize) -> CGRect {
        let gap: CGFloat = 4
        let w = (size.width - gap) / 2, h = (size.height - gap) / 2
        return CGRect(x: CGFloat(index % 2) * (w + gap), y: CGFloat(index / 2) * (h + gap), width: w, height: h)
    }

    @ViewBuilder
    private func tileView(_ tile: MultiviewTile, model: MultiviewModel, big: Bool) -> some View {
        let selected = model.selected == tile.id
        let face = MultiviewTileFace(tile: tile, selected: selected, severalLogins: model.severalLogins,
                                     muted: model.muted)
        #if os(tvOS)
        Button {
            if tile.channel == nil || tile.error != nil {
                picking = tile
            } else {
                model.toggleBig(tile.id)
            }
        } label: {
            face
        }
        .buttonStyle(MultiviewTileStyle())
        .focused($focus, equals: tile.id)
        .contextMenu { menu(tile, model: model) }
        .accessibilityIdentifier("multiview-bilde-\(tile.id)")
        .accessibilityLabel(tile.channel.map { nameParts($0.name).main } ?? L("Velg kanal"))
        #else
        face
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard tile.channel != nil else { return }
                model.select(tile.id)
                model.toggleBig(tile.id)
            }
            .onTapGesture {
                model.select(tile.id)
                if tile.channel == nil { picking = tile }
            }
            .contextMenu { menu(tile, model: model) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("multiview-bilde-\(tile.id)")
            .accessibilityLabel(tile.channel.map { nameParts($0.name).main } ?? L("Velg kanal"))
        #endif
    }

    @ViewBuilder
    private func menu(_ tile: MultiviewTile, model: MultiviewModel) -> some View {
        Button {
            picking = tile
        } label: {
            Label(tile.channel == nil ? L("Velg kanal") : L("Bytt kanal"), systemImage: "list.bullet")
        }
        if tile.channel != nil {
            Button {
                model.select(tile.id)
                model.toggleBig(tile.id)
            } label: {
                Label(model.big == tile.id ? L("Alle bildene") : L("Stort bilde"),
                      systemImage: model.big == tile.id ? "rectangle.split.2x2" : "rectangle.inset.filled")
            }
        }
        if tile.error != nil {
            Button {
                tile.retry()
            } label: {
                Label(L("Prøv igjen"), systemImage: "arrow.clockwise")
            }
        }
        Button {
            model.toggleMute()
        } label: {
            Label(model.muted ? L("Lyd på") : L("Lyd av"),
                  systemImage: model.muted ? "speaker.wave.2" : "speaker.slash")
        }
    }

    #if os(iOS)
    /// Lukk, «Multiview», og lyd av eller på.
    private func topBar(_ model: MultiviewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .accessibilityIdentifier("lukk-multiview")
            .accessibilityLabel(L("Lukk"))
            Text(verbatim: "Multiview")
                .font(.headline)
            Spacer(minLength: 0)
            Text(L("Dobbelttrykk for stort bilde, hold inne for å bytte kanal"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button {
                model.toggleMute()
            } label: {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .accessibilityIdentifier("multiview-lyd")
            .accessibilityLabel(model.muted ? L("Lyd på") : L("Lyd av"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black)
    }
    #endif

    #if os(tvOS)
    static let text: CGFloat = 26
    #else
    static let text: CGFloat = 14
    #endif
}

/// Bildet med kanalnavnet og det som går nå nede til venstre (og innloggingen når bildene er fra flere), en kant rundt
/// det valgte, «Velg kanal» i et tomt bilde og feilen med «Prøv igjen» og «Annen kanal» i hurtigmenyen.
private struct MultiviewTileFace: View {
    let tile: MultiviewTile
    let selected: Bool
    let severalLogins: Bool
    let muted: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            PlayerLayerView(player: tile.player)
            if let error = tile.error {
                message(error, icon: "exclamationmark.triangle", tint: Theme.live)
            } else if tile.channel == nil {
                message(severalLogins ? L("Velg kanal · {name}", ["name": tile.login.label]) : L("Velg kanal"),
                        icon: "plus.circle", tint: Theme.muted)
            }
            if let channel = tile.channel {
                info(channel)
            }
        }
        .overlay {
            Rectangle()
                .strokeBorder(selected ? Theme.focus : Color.clear, lineWidth: 3)
        }
        .clipped()
    }

    private func message(_ text: String, icon: String, tint: Color) -> some View {
        VStack(spacing: MultiviewView.text * 0.6) {
            Image(systemName: icon)
                .font(.system(size: MultiviewView.text * 1.8))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: MultiviewView.text, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(MultiviewView.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func info(_ channel: Channel) -> some View {
        HStack(spacing: 8) {
            if selected {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(Theme.focus)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: nameParts(channel.name).main + (severalLogins ? " · \(tile.login.label)" : ""))
                    .font(.system(size: MultiviewView.text * 0.85, weight: .bold))
                    .lineLimit(1)
                TimelineView(.everyMinute) { _ in
                    if let now = tile.now {
                        Text(verbatim: "\(now.title) · \(hhmm(now.start))–\(hhmm(now.stop))")
                            .font(.system(size: MultiviewView.text * 0.72))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, MultiviewView.text * 0.6)
        .padding(.vertical, MultiviewView.text * 0.35)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(MultiviewView.text * 0.5)
    }
}

#if os(tvOS)
/// En rad i kanalvalget på Apple TV: lys bakgrunn i fokus.
private struct PickerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowFace(configuration: configuration)
    }

    private struct RowFace: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(focused ? Color.black : Theme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(focused ? Color.white : Theme.surface))
                .scaleEffect(focused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Bildene på Apple TV: ingen forstørring eller skygge i fokus (kanten viser det valgte).
private struct MultiviewTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
#endif

/// AVPlayer i et lag uten kontroller.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// Kanalvalget for et bilde: kanalene til innloggingen bildet bruker, med søk og favorittene.
struct MultiviewPicker: View {
    @Environment(AppModel.self) private var app
    let tile: MultiviewTile
    let severalLogins: Bool
    let done: (Channel?) -> Void
    @State private var channels: [Channel]?
    @State private var failed = false
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var favorites = Set<String>()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(severalLogins ? L("Velg kanal · {name}", ["name": tile.login.label]) : L("Velg kanal"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Avbryt")) { done(nil) }
                    }
                }
                #endif
                .searchable(text: $query, prompt: Text(L("Søk etter kanal")))
        }
        .accessibilityIdentifier("multiview-velg")
        .task {
            favorites = Set(app.favoriteIds(of: tile.login))
            do {
                channels = try await app.channels(of: tile.login)
            } catch {
                failed = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let channels {
            let shown = filtered(channels)
            #if os(tvOS)
            // Apple TV: knapper i en rulleliste (fokus står da på knappen selv, ikke på en celle rundt den)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    filter
                    if shown.isEmpty { nothing }
                    ForEach(shown.prefix(500), id: \.id) { channel in
                        Button { done(channel) } label: { row(channel) }
                            .buttonStyle(PickerRowStyle())
                            .accessibilityIdentifier("velg-\(channel.id)")
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            }
            #else
            List {
                filter
                if shown.isEmpty { nothing }
                ForEach(shown.prefix(500), id: \.id) { channel in
                    Button { done(channel) } label: { row(channel) }
                        .accessibilityIdentifier("velg-\(channel.id)")
                }
            }
            #endif
        } else if failed {
            Text(L("Fikk ikke hentet kanalene."))
                .foregroundStyle(Theme.muted)
        } else {
            ProgressView()
        }
    }

    private var filter: some View {
        Picker(L("Vis"), selection: $favoritesOnly) {
            Text(L("★ Favoritter")).tag(true)
            Text(L("Alle kanaler")).tag(false)
        }
        .pickerStyle(.segmented)
    }

    private var nothing: some View {
        Text(L("Fant ingenting."))
            .foregroundStyle(Theme.muted)
    }

    /// En kanal i lista: logoen, navnet og nummeret.
    private func row(_ channel: Channel) -> some View {
        HStack(spacing: 14) {
            ChannelLogo(channel: channel)
                .frame(width: MultiviewView.text * 3.4, height: MultiviewView.text * 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: nameParts(channel.name).main)
                    .lineLimit(1)
                if let number = channel.number {
                    Text(L("Kanal {n}", ["n": number]))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Søket (alle ordene i navnet) og favorittene; høyst 500 vises, så lista ikke blir tung.
    private func filtered(_ channels: [Channel]) -> [Channel] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return channels.filter { channel in
            if favoritesOnly && !favorites.contains(channel.id) { return false }
            guard !words.isEmpty else { return true }
            let name = channel.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
    }
}
