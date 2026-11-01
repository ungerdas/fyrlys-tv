import AVKit
import FyrlysCore
import SwiftUI

// ── fanen ──

/// Fanen Filmer eller Serier: kategoriene (sidemeny på Apple TV og iPad, en meny øverst på iPhone) og plakatene. En
/// film eller serie åpnes som egen side (Menu eller tilbake går tilbake).
struct VODTab: View {
    @Environment(AppModel.self) private var app
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let kind: VODKind
    @State private var path: [VODItem] = []

    private var model: VODModel { kind == .movies ? app.movies : app.series }

    var body: some View {
        NavigationStack(path: $path) {
            content
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(for: VODItem.self) { item in
                    VODDetailView(item: item)
                }
        }
        .task { await model.loadCategories() }
    }

    @ViewBuilder
    private var content: some View {
        if !model.loaded {
            if let error = model.error {
                VODMessage(text: error) { Task { await model.loadCategories(force: true) } }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.categories.isEmpty {
            VODMessage(text: kind == .movies ? L("Ingen filmer hos leverandøren.") : L("Ingen serier hos leverandøren."))
        } else {
            #if os(iOS)
            if sizeClass == .compact { phone } else { split }
            #else
            split
            #endif
        }
    }

    /// Apple TV og iPad: kategoriene til venstre, plakatene til høyre.
    private var split: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.categories) { category in
                        Button {
                            model.chosen = category.id
                        } label: {
                            HStack(spacing: 8) {
                                Text(category.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(SidebarStyle(selected: model.chosen == category.id))
                        .accessibilityIdentifier("vodkat-\(category.id)")
                    }
                }
                .padding(.vertical, 6)
                .hidesScrollIndex()
            }
            .scrollIndicators(.never)
            .frame(width: Metrics.sidebarWidth)
            .clipped()
            .tvFocusSection()
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
                .padding(.vertical, 12)
            PosterGrid(model: model, category: model.chosen)
                .tvFocusSection()
        }
        #if os(tvOS)
        .padding(.horizontal, Theme.edge)
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        #else
        .clipped()
        #endif
    }

    #if os(iOS)
    /// iPhone: kategorien i en meny øverst, plakatene under.
    private var phone: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(model.categories) { category in
                    Button(category.name) { model.chosen = category.id }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(model.name(model.chosen))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
            .accessibilityIdentifier("vod-kategori")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            PosterGrid(model: model, category: model.chosen, showsTitle: false)
        }
    }
    #endif
}

/// Plakatene i en kategori (hentes når kategorien velges).
private struct PosterGrid: View {
    let model: VODModel
    let category: String?
    var showsTitle = true

    var body: some View {
        let items = category.flatMap { model.items[$0] }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsTitle {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text(model.name(category))
                            .font(.system(size: Metrics.pageTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let items {
                            Text(verbatim: CountText.of(items.count))
                                .font(.system(size: Metrics.pageCount))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                if let items {
                    if items.isEmpty {
                        Text(L("Ingen her."))
                            .font(.system(size: Metrics.pageCount + 4))
                            .foregroundStyle(Theme.muted)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterMin), spacing: Metrics.posterGap,
                                                     alignment: .top)],
                                  alignment: .leading, spacing: Metrics.posterGap + 8) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    PosterCard(item: item)
                                }
                                .posterButtonStyle()
                                .accessibilityIdentifier("vod-\(item.id)")
                            }
                        }
                    }
                } else if model.error != nil, let category {
                    VODMessage(text: model.error ?? "") { Task { await model.load(category) } }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
            #if os(tvOS)
            .hidesScrollIndex()
            .movesTabBar()
            #endif
        }
        .scrollIndicators(.never)
        #if os(tvOS)
        .safeAreaPadding(.bottom, Theme.bottomFocus)
        #endif
        .task(id: category) {
            if let category { await model.load(category) }
        }
        .id(category)
    }
}

/// Plakaten med tittel, år og terningkast.
private struct PosterCard: View {
    let item: VODItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    RemoteImage(url: item.poster.flatMap { URL(string: $0) }, fill: true) {
                        ZStack {
                            LinearGradient(colors: [Theme.surface2, Theme.logoBg], startPoint: .top, endPoint: .bottom)
                            Text(item.name)
                                .font(.system(size: Metrics.posterTitle + 2, weight: .bold))
                                .foregroundStyle(Theme.ink2)
                                .multilineTextAlignment(.center)
                                .padding(10)
                        }
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: Metrics.posterTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(verbatim: meta)
                    .font(.system(size: Metrics.posterTitle - 3))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var meta: String {
        [item.year, item.rating.map { String(format: "★ %.1f", $0) }].compactMap { $0 }.joined(separator: "  ")
    }
}

extension View {
    /// Plakatene som knapp: løftes når de har fokus på Apple TV, vanlige på iPhone og iPad.
    @ViewBuilder
    func posterButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

/// En melding midt på (ingen filmer, feil), eventuelt med «Prøv igjen».
private struct VODMessage: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Text(text)
                .font(.system(size: Metrics.pageCount + 6))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button(L("Prøv igjen"), action: retry)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── siden for en film eller serie ──

/// Plakaten, tittelen, år, sjanger, lengde og terningkast, handlingen og «Spill av» (filmer, med «Fortsett» når du
/// har sett noe), eller sesongene og episodene (serier).
struct VODDetailView: View {
    @Environment(AppModel.self) private var app
    let item: VODItem
    @State private var details: VODDetails?
    @State private var error: String?
    @State private var season: Int?
    @State private var playing: VODPlay?
    /// telles opp når spilleren lukkes, så «Fortsett» viser hvor langt du kom
    @State private var watched = 0

    private var model: VODModel { item.kind == .movies ? app.movies : app.series }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                if item.kind == .series {
                    episodes
                }
            }
            .padding(.horizontal, Metrics.detailPadding)
            .padding(.vertical, Metrics.detailPadding * 0.6)
            #if os(tvOS)
            .hidesScrollIndex()
            #endif
        }
        .scrollIndicators(.never)
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        #if os(tvOS)
        .fullScreenCover(item: $playing, onDismiss: { watched += 1 }) { play in
            VODPlayerView(play: play)
                .environment(app)
        }
        #else
        .sheet(item: $playing, onDismiss: { watched += 1 }) { play in
            VODPlayerView(play: play)
                .environment(app)
                .preferredColorScheme(.dark)
                .presentationDragIndicator(.visible)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vod-side")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Metrics.detailPadding * 0.8) {
            RemoteImage(url: (details?.poster ?? item.poster).flatMap { URL(string: $0) }, fill: true) {
                LinearGradient(colors: [Theme.surface2, Theme.logoBg], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: Metrics.detailPoster, height: Metrics.detailPoster * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name)
                    .font(.system(size: Metrics.detailTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                if !meta.isEmpty {
                    Text(verbatim: meta)
                        .font(.system(size: Metrics.detailText))
                        .foregroundStyle(Theme.signal)
                        .lineLimit(2)
                }
                if let details {
                    if !details.plot.isEmpty {
                        Text(details.plot)
                            .font(.system(size: Metrics.detailText))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !details.cast.isEmpty {
                        Text(L("Med: {cast}", ["cast": details.cast]))
                            .font(.system(size: Metrics.detailText - 3))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                } else if let error {
                    Text(error)
                        .font(.system(size: Metrics.detailText))
                        .foregroundStyle(Theme.muted)
                } else {
                    ProgressView()
                }
                if item.kind == .movies {
                    movieButtons
                        .padding(.top, 10)
                }
            }
        }
    }

    private var meta: String {
        let d = details
        let parts: [String?] = [
            d?.year ?? item.year,
            d.map(\.genre).flatMap { $0.isEmpty ? nil : $0 },
            d.map(\.duration).flatMap { $0.isEmpty ? nil : $0 },
            (d?.rating ?? item.rating).map { String(format: "★ %.1f", $0) },
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var movieButtons: some View {
        let _ = watched
        let saved = app.progress(item.progressKey)
        return HStack(spacing: 24) {
            Button {
                startMovie(at: saved)
            } label: {
                Label(saved > 0 ? L("Fortsett ({time})", ["time": playTime(saved)]) : L("Spill av"),
                      systemImage: "play.fill")
            }
            .vodPrimary()
            .accessibilityIdentifier("spill-av")
            if saved > 0 {
                Button {
                    startMovie(at: 0)
                } label: {
                    Label(L("Fra start"), systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("fra-start")
            }
        }
    }

    @ViewBuilder
    private var episodes: some View {
        if let details {
            if details.seasons.isEmpty {
                Text(L("Ingen episoder."))
                    .font(.system(size: Metrics.detailText))
                    .foregroundStyle(Theme.muted)
            } else {
                let current = season ?? details.seasons[0].number
                VStack(alignment: .leading, spacing: 20) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(details.seasons) { s in
                                Button {
                                    season = s.number
                                } label: {
                                    Text(L("Sesong {n}", ["n": s.number]))
                                        .fontWeight(s.number == current ? .bold : .regular)
                                }
                                .vodSeason(selected: s.number == current)
                                .accessibilityIdentifier("sesong-\(s.number)")
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.never)
                    #if os(tvOS)
                    .scrollClipDisabled()
                    .focusSection()
                    #endif
                    LazyVStack(alignment: .leading, spacing: 14) {
                        let _ = watched
                        ForEach(details.seasons.first { $0.number == current }?.episodes ?? []) { episode in
                            Button {
                                play(episode)
                            } label: {
                                EpisodeRow(episode: episode, seen: app.progress(episode.progressKey))
                            }
                            .posterButtonStyle()
                            .accessibilityIdentifier("episode-\(episode.id)")
                        }
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
    }

    private func load() async {
        guard details == nil else { return }
        do {
            details = try await model.details(item)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startMovie(at seconds: Double) {
        guard let client = app.client else { return }
        let urls = playableExtensions(details?.ext ?? item.ext).map { client.movieURL(item.id, ext: $0) }
        playing = VODPlay(id: item.progressKey, urls: urls, title: item.name, subtitle: meta,
                          progressKey: item.progressKey, start: seconds)
    }

    private func play(_ episode: Episode) {
        guard let client = app.client else { return }
        let urls = playableExtensions(episode.ext).map { client.episodeURL(episode, ext: $0) }
        let subtitle = L("Sesong {s}, episode {e}", ["s": episode.season, "e": episode.number]) + ": " + episode.title
        playing = VODPlay(id: episode.progressKey, urls: urls, title: item.name, subtitle: subtitle,
                          progressKey: episode.progressKey, start: app.progress(episode.progressKey))
    }
}

/// En episode: nummeret, tittelen, handlingen og lengden, og hvor langt du har sett.
private struct EpisodeRow: View {
    let episode: Episode
    let seen: Double

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(verbatim: "\(episode.number)")
                .font(.system(size: Metrics.detailText + 4, weight: .bold))
                .foregroundStyle(Theme.signal)
                .frame(width: Metrics.detailText * 2.2, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.system(size: Metrics.detailText, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !episode.plot.isEmpty {
                    Text(episode.plot)
                        .font(.system(size: Metrics.detailText - 4))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if seen > 0 {
                    Text(L("Sett til {time}", ["time": playTime(seen)]))
                        .font(.system(size: Metrics.detailText - 5, weight: .medium))
                        .foregroundStyle(Theme.signal)
                }
            }
            Spacer(minLength: 0)
            if !episode.duration.isEmpty {
                Text(verbatim: episode.duration)
                    .font(.system(size: Metrics.detailText - 4))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    /// «Spill av»: gul på iPhone og iPad (fokus gjør jobben på Apple TV).
    @ViewBuilder
    func vodPrimary() -> some View {
        #if os(iOS)
        buttonStyle(.borderedProminent)
            .tint(Theme.signal)
            .foregroundStyle(Theme.signalInk)
        #else
        self
        #endif
    }

    /// Sesongknappene: den valgte er gul.
    @ViewBuilder
    func vodSeason(selected: Bool) -> some View {
        #if os(iOS)
        buttonStyle(.bordered)
            .tint(selected ? Theme.signal : Theme.muted)
        #else
        foregroundStyle(selected ? Theme.signal : Theme.ink)
        #endif
    }
}

/// 1:02:03 eller 12:34.
func playTime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

// ── spilleren ──

/// Det som spilles: adressene som prøves etter tur (filtypen hos leverandøren, eller HLS først når AVPlayer ikke kan
/// filtypen), og hvor det skal begynne.
struct VODPlay: Identifiable {
    let id: String
    let urls: [URL]
    let title: String
    let subtitle: String
    let progressKey: String
    let start: Double
}

/// AVPlayer for en film eller episode: prøver adressene etter tur, begynner der du slapp, og husker hvor langt du har
/// sett (hvert tiende sekund og når spilleren lukkes; nær slutten glemmes det, så neste gang begynner fra start).
@MainActor
@Observable
final class VODPlayerModel {
    let player = AVPlayer()
    let play: VODPlay
    private(set) var error: String?

    private let app: AppModel
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?

    init(app: AppModel, play: VODPlay) {
        self.app = app
        self.play = play
    }

    func start() {
        open(0)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    private func open(_ i: Int) {
        guard i < play.urls.count else { return }
        index = i
        let asset = AVURLAsset(url: play.urls[i], options: [AVURLAssetHTTPUserAgentKey: xtreamUserAgent])
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = [Self.meta(.commonIdentifierTitle, play.title),
                                 Self.meta(.iTunesMetadataTrackSubTitle, play.subtitle)]
        observation?.invalidate()
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor in self?.changed(status, i) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func changed(_ status: AVPlayerItem.Status, _ i: Int) {
        guard i == index else { return }
        if status == .readyToPlay, !started {
            started = true
            if play.start > 5 {
                player.seek(to: CMTime(seconds: play.start, preferredTimescale: 600))
            }
        } else if status == .failed {
            if i + 1 < play.urls.count {
                open(i + 1)
            } else {
                player.pause()
                error = L("Kan ikke spilles på denne enheten (filtypen er {ext}).",
                          ["ext": play.urls.last?.pathExtension ?? "?"])
            }
        }
    }

    func save() {
        guard started else { return }
        let t = player.currentTime().seconds
        guard t.isFinite, t > 30 else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        if duration.isFinite, duration > 0, duration - t < 120 {
            app.setProgress(play.progressKey, nil)
        } else {
            app.setProgress(play.progressKey, t)
        }
    }

    func stop() {
        save()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observation?.invalidate()
        observation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private static func meta(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Filmen eller episoden i fullskjerm (Apple TV: Menu lukker) eller i et ark (iPhone og iPad: dra ned for å lukke).
struct VODPlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let play: VODPlay
    @State private var model: VODPlayerModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                if let error = model.error {
                    VStack(spacing: 24) {
                        Text(play.title)
                            .font(.system(size: Metrics.detailTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(error)
                            .font(.system(size: Metrics.detailText))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button(L("Lukk")) { dismiss() }
                    }
                    .padding(40)
                } else {
                    VODPlayerController(player: model.player)
                        .ignoresSafeArea()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model?.error == nil ? "vod-spiller" : "vod-feil")
        .onAppear {
            guard model == nil else { return }
            let player = VODPlayerModel(app: app, play: play)
            model = player
            player.start()
        }
        .onDisappear { model?.stop() }
    }
}

struct VODPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        #if os(iOS)
        controller.allowsPictureInPicturePlayback = true
        #endif
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
