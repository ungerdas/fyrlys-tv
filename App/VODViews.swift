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
                // på iPad ellers systemets bakgrunn (svart eller hvit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(for: VODItem.self) { item in
                    VODDetailView(item: item)
                }
        }
        // på nytt når kilden byttes (en annen innlogging, eller Plex)
        .task(id: model.version) { await model.loadCategories() }
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
            if model.isPlex {
                VODMessage(text: kind == .movies ? L("Ingen filmbiblioteker på Plex-serveren.")
                           : L("Ingen seriebiblioteker på Plex-serveren."))
            } else {
                VODMessage(text: kind == .movies ? L("Ingen filmer hos leverandøren.")
                           : L("Ingen serier hos leverandøren."))
            }
        } else {
            #if os(iOS)
            if usesPhoneLayout(sizeClass) { phone } else { split }
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
            page(showsTitle: true)
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
            page(showsTitle: false)
        }
    }
    #endif

    /// Plakatene i kategorien, eller «Hjem» med radene fra Plex.
    @ViewBuilder
    private func page(showsTitle: Bool) -> some View {
        if model.chosen == VODModel.home {
            PlexHomeView(model: model) { path.append($0) }
        } else {
            PosterGrid(model: model, category: model.chosen, showsTitle: showsTitle)
        }
    }
}

/// Plakatene i en kategori (hentes når kategorien velges), med «Fortsett å se» øverst.
private struct PosterGrid: View {
    @Environment(AppModel.self) private var app
    let model: VODModel
    let category: String?
    var showsTitle = true

    var body: some View {
        let items = category.flatMap { model.items[$0] }
        let resume = model.isPlex ? model.continueRow : app.continueItems(model.kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !resume.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Fortsett å se"))
                            .font(.system(size: Metrics.rowTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: Metrics.posterGap) {
                                ForEach(resume) { item in
                                    NavigationLink(value: item) {
                                        PosterCard(item: item)
                                    }
                                    .posterButtonStyle()
                                    .frame(width: Metrics.posterMin)
                                    .accessibilityIdentifier("fortsett-\(item.id)")
                                }
                            }
                            .padding(.vertical, 12)
                        }
                        .scrollIndicators(.never)
                        #if os(tvOS)
                        .scrollClipDisabled()
                        .focusSection()
                        #endif
                    }
                }
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

/// Plakaten med tittel, år og terningkast; for en episode (radene fra Plex) seriens plakat med serien, episoden og
/// sesong og nummer.
struct PosterCard: View {
    let item: VODItem
    var episode: Episode?

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
                .overlay(alignment: .topTrailing) {
                    if episode?.watched ?? (item.watched == true) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .font(.system(size: Metrics.posterTitle + 6, weight: .semibold))
                            .foregroundStyle(Theme.signalInk, Theme.signal)
                            .padding(8)
                            .accessibilityLabel(L("Sett"))
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: Metrics.posterTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(episode == nil ? 2 : 1, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let episode {
                    Text(episode.title)
                        .font(.system(size: Metrics.posterTitle - 2))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
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
        if let episode { return "S\(episode.season) · E\(episode.number)" }
        return [item.year, item.rating.map { String(format: "★ %.1f", $0) }].compactMap { $0 }.joined(separator: "  ")
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
            // til venstre (en smal side ble ellers lagt midt i rullelista)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            .hidesScrollIndex()
            #endif
        }
        .scrollIndicators(.never)
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        #if os(tvOS)
        .fullScreenCover(item: $playing, onDismiss: closed) { play in
            VODPlayerView(play: play)
                .environment(app)
        }
        #else
        .sheet(item: $playing, onDismiss: closed) { play in
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
                } else if let details, let next = nextEpisode(details) {
                    seriesButton(next)
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
            // Plex: fila står på siden, som hentes først (før gjorde knappen ingenting til da)
            .disabled(item.isPlex && details == nil)
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

    /// Episoden du skal se: den du er midt i (når den kommer etter den siste du har sett ferdig), ellers den etter den
    /// siste du har sett, ellers den første. Spesialene (sesong 0) teller ikke med.
    private func nextEpisode(_ details: VODDetails) -> (episode: Episode, seen: Double, after: Bool)? {
        let _ = watched
        let regular = details.seasons.filter { $0.number != 0 }.flatMap(\.episodes)
        let all = regular.isEmpty ? details.seasons.flatMap(\.episodes) : regular
        guard let first = all.first else { return nil }
        let lastSeen = all.lastIndex(where: finished)
        // en gammel, avbrutt episode før den siste du har sett ferdig, er ikke den du skal se
        if let current = all.lastIndex(where: { app.progress($0.progressKey) > 0 }),
           lastSeen.map({ current > $0 }) ?? true {
            return (all[current], app.progress(all[current].progressKey), false)
        }
        if let lastSeen {
            return lastSeen + 1 < all.count ? (all[lastSeen + 1], 0, true) : (first, 0, false)
        }
        return (first, 0, false)
    }

    /// Sett ferdig: Plex vet det selv (og der kan noe merkes som usett igjen); ellers det enheten husker.
    private func finished(_ episode: Episode) -> Bool {
        episode.source == "plex" ? episode.watched : (episode.watched || app.isFinished(episode.progressKey))
    }

    /// «Fortsett S1 E3 (4:45)», «Neste: S1 E4» eller «Spill av S1 E1»: rett til episoden du skal se.
    private func seriesButton(_ next: (episode: Episode, seen: Double, after: Bool)) -> some View {
        let code = "S\(next.episode.season) E\(next.episode.number)"
        let title = next.seen > 0 ? L("Fortsett {episode} ({time})", ["episode": code, "time": playTime(next.seen)])
            : next.after ? L("Neste: {episode}", ["episode": code]) : L("Spill av {episode}", ["episode": code])
        return Button {
            play(next.episode)
        } label: {
            Label(title, systemImage: "play.fill")
        }
        .vodPrimary()
        .accessibilityIdentifier("fortsett-serie")
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
                                EpisodeRow(episode: episode, seen: app.progress(episode.progressKey),
                                           finished: finished(episode))
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
            let found = try await model.details(item)
            if item.isPlex { syncProgress(found) }
            details = found
            error = nil
            // sesongen med episoden du skal se
            if season == nil, let next = nextEpisode(found) { season = next.episode.season }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Plex: hvor langt du har sett, slik Plex har det (også fra de andre Plex-appene).
    private func syncProgress(_ found: VODDetails) {
        if item.kind == .movies {
            // også når filmen er sett før og ses på nytt (da har Plex både «sett» og hvor langt du er kommet)
            app.setProgress(item.progressKey, found.resume > 0 ? found.resume : nil)
        }
        for episode in found.seasons.flatMap(\.episodes) {
            app.setProgress(episode.progressKey, episode.resume > 0 ? episode.resume : nil)
        }
    }

    /// Spilleren er lukket: «Fortsett» og episodene viser hvor langt du kom, og med Plex hentes siden og «Fortsett å
    /// se» på nytt (litt etter, så Plex har fått med seg det siste).
    private func closed() {
        watched += 1
        guard item.isPlex else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if let found = try? await model.details(item) {
                syncProgress(found)
                details = found
                watched += 1
            }
            await model.refreshContinue()
        }
    }

    private func startMovie(at seconds: Double) {
        let urls = model.movieURLs(item, details)
        guard !urls.isEmpty else { return }
        playing = VODPlay(id: item.progressKey, urls: urls, title: item.name, subtitle: meta,
                          progressKey: item.progressKey, start: seconds, item: item,
                          plex: item.isPlex ? item.id : nil)
    }

    private func play(_ episode: Episode) {
        let urls = model.episodeURLs(episode)
        guard !urls.isEmpty else { return }
        let subtitle = L("Sesong {s}, episode {e}", ["s": episode.season, "e": episode.number]) + ": " + episode.title
        playing = VODPlay(id: episode.progressKey, urls: urls, title: item.name, subtitle: subtitle,
                          progressKey: episode.progressKey, start: app.progress(episode.progressKey), item: item,
                          plex: episode.source == "plex" ? episode.id : nil)
    }
}

/// En episode: nummeret, tittelen, handlingen og lengden, og hvor langt du har sett.
private struct EpisodeRow: View {
    let episode: Episode
    let seen: Double
    var finished = false

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
                } else if finished {
                    Label(L("Sett"), systemImage: "checkmark")
                        .font(.system(size: Metrics.detailText - 5, weight: .medium))
                        .foregroundStyle(Theme.muted)
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

    /// Sesong- og dagknappene: den valgte er gul (på Apple TV mørk tekst på lys flate når den har fokus).
    @ViewBuilder
    func vodSeason(selected: Bool) -> some View {
        #if os(iOS)
        buttonStyle(.bordered)
            .tint(selected ? Theme.signal : Theme.muted)
        #else
        buttonStyle(PillStyle(selected: selected))
        #endif
    }
}

#if os(tvOS)
/// En pille på Apple TV: lys med mørk tekst i fokus, ellers gul tekst på en litt lysere flate når den er valgt.
struct PillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}

private struct PillLabel<Label: View>: View {
    let label: Label
    let selected: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .font(.system(size: 26, weight: selected ? .bold : .medium))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.ink))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Capsule().fill(focused ? Theme.ink : (selected ? Theme.surface2 : Theme.surface)))
            .scaleEffect(focused ? (pressed ? 1.0 : 1.06) : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
#endif

/// 1:02:03 eller 12:34.
func playTime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

// ── spilleren ──

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
/// start).
@MainActor
@Observable
final class VODPlayerModel {
    let player = AVPlayer()
    let play: VODPlay
    private(set) var error: String?
    /// VLC spiller (mkv, avi, MPEG-TS …); ellers Apples avspiller
    private(set) var vlc: VLCEngine?
    /// filmen er ferdig (VLC): spilleren lukkes
    private(set) var finished = false
    /// iPhone/iPad: AVKit sin egen fullskjerm er framme (siden under forsvinner da, men spilleren skal ikke stoppes)
    @ObservationIgnored var inFullScreen = false

    private let app: AppModel
    private let attempts: [PlayAttempt]
    @ObservationIgnored private var index = 0
    /// forsøket som pågår, har kommet i gang (Apples avspiller)
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var notes: [NSObjectProtocol] = []
    @ObservationIgnored private var saver: Task<Void, Never>?
    /// Plex: merket som sett (én gang)
    @ObservationIgnored private var scrobbled = false
    /// «stoppet» er sendt til Plex (etter det sendes ingenting mer)
    @ObservationIgnored private var reportedStop = false
    /// der neste forsøk begynner (der du slapp, eller der forbindelsen ble brutt)
    @ObservationIgnored private var resumeAt: Double
    /// brudd midt i (forbindelsen falt): samme adresse prøves igjen der den slapp, to ganger
    @ObservationIgnored private var breaks = 0

    init(app: AppModel, play: VODPlay) {
        self.app = app
        self.play = play
        attempts = playAttempts(play.urls)
        resumeAt = play.start
    }

    func start() {
        open(0)
        saver = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                self.save()
            }
        }
    }

    private func open(_ i: Int) {
        guard i < attempts.count else { return }
        index = i
        started = false
        let attempt = attempts[i]
        stopObserving()
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
            // brudd midt i filmen (ikke bare at den ikke kom i gang)
            notes = [NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.failed(i) }
            }]
            player.replaceCurrentItem(with: item)
            player.play()
        case .vlc:
            player.replaceCurrentItem(with: nil)
            let engine = VLCEngine()
            engine.onFail = { [weak self] in self?.failed(i) }
            engine.onEnd = { [weak self] in self?.ended() }
            vlc = engine
            engine.open(attempt.url, start: resumeAt)
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

    /// Adressen kunne ikke spilles: den neste, eller forklaringen. Ble forbindelsen brutt midt i, prøves samme adresse
    /// igjen der den slapp (to ganger), så kommer feilen med «Prøv igjen» (før begynte neste forsøk på nytt fra der
    /// filmen ble åpnet, og hvor langt du hadde sett, ble skrevet over).
    private func failed(_ i: Int) {
        guard i == index, error == nil else { return }
        let reached = position
        // samme brudd kan meldes to ganger (status og varsel): bare én gang
        stopObserving()
        vlc?.stop()
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
            error = L("Avspillingen stoppet ved {time}. Prøv igjen for å fortsette der.", ["time": playTime(reached)])
            return
        }
        if i + 1 < attempts.count {
            vlc = nil
            open(i + 1)
        } else {
            player.pause()
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

    /// lukket (stop er kalt)
    @ObservationIgnored private var closed = false

    private func ended() {
        save(final: true)
        saver?.cancel()
        saver = nil
        finished = true
    }

    /// Husker hvor langt du har sett (på enheten, og hos Plex for filmer og serier derfra). [final]: spilleren lukkes.
    func save(final: Bool = false) {
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
        guard t.isFinite, t > 30, !reportedStop else { return }
        if final { reportedStop = true }
        let done = duration.isFinite && duration > 0 && duration - t < 120
        if done {
            app.setProgress(play.progressKey, nil)
            // Plex husker selv hva som er sett (og der kan det merkes som usett igjen)
            if play.plex == nil { app.setFinished(play.progressKey) }
            // en ferdig film tas ut av «Fortsett å se» (en serie står til neste episode)
            if let item = play.item, item.kind == .movies, !item.isPlex { app.forgetContinue(item) }
        } else {
            app.setProgress(play.progressKey, t)
            if let item = play.item, !item.isPlex { app.rememberContinue(item) }
        }
        if let key = play.plex, !(scrobbled && final) {
            let state: PlexClient.PlayState = final ? .stopped : (paused ? .paused : .playing)
            let markWatched = final && done && !scrobbled
            if markWatched { scrobbled = true }
            app.plex.report(key, time: t, duration: duration.isFinite ? duration : 0, state: state,
                            finished: markWatched)
        }
    }

    func stop() {
        closed = true
        save(final: true)
        saver?.cancel()
        saver = nil
        stopObserving()
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
/// med Apples avspiller eller VLC.
struct VODPlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let play: VODPlay
    @State private var model: VODPlayerModel?
    #if os(iOS)
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
                        Text(play.title)
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
                    VLCPlayerScreen(engine: vlc, title: play.title, subtitle: play.subtitle) { dismiss() }
                } else {
                    VODPlayerController(player: model.player) { model.inFullScreen = $0 }
                        .ignoresSafeArea()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model?.error == nil ? "vod-spiller" : "vod-feil")
        .onAppear {
            guard model == nil else { return }
            #if os(iOS)
            // iPhone: liggende, som i Apple TV-appen (også når skjermretningen er låst); når arket har kommet fram
            // (mens det kommer inn, avvises det)
            wasLandscape = Landscape.isLandscape
            turn = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                Landscape.set(true)
            }
            #endif
            let player = VODPlayerModel(app: app, play: play)
            model = player
            player.start()
        }
        .onChange(of: model?.finished ?? false) { _, done in
            if done { dismiss() }
        }
        .onDisappear {
            // ikke når AVKit sin egen fullskjerm legger seg over (da forsvinner siden under, men det spilles videre)
            guard model?.inFullScreen != true else { return }
            model?.stop()
            #if os(iOS)
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
}

struct VODPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    /// AVKit sin fullskjerm kommer eller går (iPhone og iPad)
    var fullScreen: (Bool) -> Void = { _ in }

    func makeCoordinator() -> FullScreenWatcher { FullScreenWatcher() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        #if os(iOS)
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        #endif
        context.coordinator.changed = fullScreen
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.changed = fullScreen
    }
}

/// Sier fra når AVKit sin egen fullskjerm kommer og går.
final class FullScreenWatcher: NSObject, AVPlayerViewControllerDelegate {
    var changed: (Bool) -> Void = { _ in }

    #if os(iOS)
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
