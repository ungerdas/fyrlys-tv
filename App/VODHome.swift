import FyrlysCore
import SwiftUI

/// «Hjem» i Filmer og Serier, som i Plex og IPTV-appene: «Fortsett å se» (bredbilder med hvor langt du har kommet),
/// favorittene, og så radene fra Plex («Nytt fra …», «Nylig lagt til …») eller kategoriene hos IPTV-leverandøren, med
/// «Se alle». Filmer og serier åpnes som egen side; en episode spilles med en gang der du slapp (hold inne for serien).
struct VODHomeView: View {
    @Environment(AppModel.self) private var app
    let model: VODModel
    /// åpner siden for en film eller serie
    let open: (VODItem) -> Void
    @State private var playing: VODPlay?

    /// toppen av lista: dit den øverste raden ruller når den får fokus, så fanelinja på Apple TV kommer helt fram igjen
    /// (ellers ble lista stående litt nede når man gikk tilbake dit, og fanelinja halvveis ute over kanten)
    static let top = "toppen"

    var body: some View {
        ScrollViewReader { proxy in
            shelves {
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
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
        #endif
        // Plex: favorittene slik serveren har dem (plakatene); på nytt når de endres
        .task(id: "\(app.vodFavoritesVersion)-\(model.version)") {
            guard model.isPlex else { return }
            await model.refreshFavorites(app.vodFavorites(model.kind, fromPlex: true))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vod-hjem")
    }

    private func shelves(_ toTop: @escaping () -> Void) -> some View {
        let resume = model.isPlex ? model.continueRow : app.continueEntries(model.kind)
        let favorites = model.isPlex ? model.favoriteRow : app.vodFavorites(model.kind, fromPlex: false)
        let rows = model.isPlex ? model.rows : []
        let categories = model.isPlex ? [] : model.categories.filter { $0.id != VODModel.home }
        // den øverste raden (den ruller lista helt opp); en tom kategori vises ikke
        let first: String
        if !resume.isEmpty {
            first = "fortsett"
        } else if !favorites.isEmpty {
            first = "favoritter"
        } else if let row = rows.first {
            first = "rad:\(row.id)"
        } else if let category = categories.first(where: { model.items[$0.id]?.isEmpty != true }) {
            first = "kat:\(category.id)"
        } else {
            first = ""
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.homeGap) {
                if !resume.isEmpty {
                    VODShelf(title: L("Fortsett å se")) {
                        ForEach(resume) { entry in
                            resumeCard(entry, top: first == "fortsett" ? toTop : nil)
                        }
                    }
                }
                if !favorites.isEmpty {
                    VODShelf(title: L("Favoritter")) {
                        ForEach(favorites) { item in
                            VODPosterLink(item: item, id: "vodfav-\(item.id)",
                                          onFocus: first == "favoritter" ? toTop : nil)
                                .frame(width: Metrics.rowPoster)
                        }
                    }
                }
                ForEach(rows) { row in
                    VODShelf(title: row.title) {
                        if row.more, row.key != nil {
                            NavigationLink(value: row) {
                                SeeAllLabel()
                            }
                            .seeAllStyle()
                            .accessibilityIdentifier("se-alle-\(row.id)")
                        }
                    } content: {
                        ForEach(row.items) { entry in
                            rowCard(entry, top: first == "rad:\(row.id)" ? toTop : nil)
                                .frame(width: Metrics.rowPoster)
                        }
                    }
                }
                ForEach(categories) { category in
                    CategoryShelf(model: model, category: category,
                                  onTopFocus: first == "kat:\(category.id)" ? toTop : nil)
                }
                if resume.isEmpty && favorites.isEmpty && model.isPlex && rows.isEmpty {
                    Text(L("Her kommer det du har begynt på, og favorittene dine (hold inne på en plakat)."))
                        .font(.system(size: Metrics.pageCount + 2))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
            #if os(tvOS)
            .hidesScrollIndex()
            .movesTabBar()
            #endif
            .id(Self.top)
        }
        .scrollIndicators(.never)
        #if os(tvOS)
        .safeAreaPadding(.bottom, Theme.bottomFocus)
        #else
        .scrollDismissesKeyboard(.immediately)
        #endif
    }

    /// Et kort i «Fortsett å se»: en episode spilles med en gang (hold inne for serien), en film åpnes som egen side.
    @ViewBuilder
    private func resumeCard(_ entry: VODResume, top: (() -> Void)?) -> some View {
        if let episode = entry.episode {
            Button {
                Task { await play(episode, show: entry.item, image: entry.image) }
            } label: {
                ResumeCard(entry: entry)
            }
            .posterButtonStyle()
            .onFocusGained(top)
            .frame(width: Metrics.resumeWidth)
            .accessibilityIdentifier("fortsett-\(entry.id)")
            .contextMenu {
                Button {
                    open(entry.item)
                } label: {
                    Label(L("Gå til serien"), systemImage: "rectangle.stack")
                }
                FavoriteToggle(item: entry.item)
                forgetButton(entry.item)
            }
        } else {
            NavigationLink(value: entry.item) {
                ResumeCard(entry: entry)
            }
            .posterButtonStyle()
            .onFocusGained(top)
            .frame(width: Metrics.resumeWidth)
            .accessibilityIdentifier("fortsett-\(entry.id)")
            .contextMenu {
                FavoriteToggle(item: entry.item)
                forgetButton(entry.item)
            }
        }
    }

    /// Ta ut av «Fortsett å se» (bare det enheten husker; Plex har sin egen liste).
    @ViewBuilder
    private func forgetButton(_ item: VODItem) -> some View {
        if !item.isPlex {
            Button(role: .destructive) {
                app.forgetContinue(item)
            } label: {
                Label(L("Fjern fra «Fortsett å se»"), systemImage: "xmark")
            }
        }
    }

    /// En film eller serie i en rad fra Plex; en episode spilles med en gang (hold inne for serien).
    @ViewBuilder
    private func rowCard(_ entry: VODRowItem, top: (() -> Void)?) -> some View {
        if let episode = entry.episode {
            // id-en på knappen før hurtigmenyen (etter den ble id-en borte av og til på iPhone og iPad)
            Button {
                Task { await play(episode, show: entry.item, image: nil) }
            } label: {
                PosterCard(item: entry.item, episode: episode)
            }
            .posterButtonStyle()
            .onFocusGained(top)
            .accessibilityIdentifier("rad-\(entry.id)")
            .contextMenu {
                Button {
                    open(entry.item)
                } label: {
                    Label(L("Gå til serien"), systemImage: "rectangle.stack")
                }
                FavoriteToggle(item: entry.item)
            }
        } else {
            VODPosterLink(item: entry.item, id: "rad-\(entry.id)", onFocus: top)
        }
    }

    /// En episode der du slapp (hos Plex eller på enheten); forrige og neste episode hentes av spilleren.
    private func play(_ episode: Episode, show: VODItem, image: String?) async {
        // Plex vet hvor langt du har sett (også i de andre Plex-appene), og raden er hentet nettopp
        if episode.source == "plex" {
            app.setProgress(episode.progressKey, episode.resume > 0 ? episode.resume : nil)
        }
        if let play = await model.play(episode, show: show, app: app, image: image, seasons: nil) {
            playing = play
        }
    }

    /// Spilleren er lukket: med Plex «Fortsett å se» og radene på nytt (litt etter, så Plex har fått med seg det
    /// siste); fra leverandøren oppdateres «Fortsett å se» av seg selv.
    private func closed() {
        guard model.isPlex else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await model.refreshContinue()
        }
    }
}

/// En rad på Hjem: tittelen (med «Se alle» til høyre) og kortene bortover.
struct VODShelf<All: View, Content: View>: View {
    let title: String
    @ViewBuilder let all: () -> All
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.shelfTitleGap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: Metrics.shelfTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                all()
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.posterGap) {
                    content()
                }
                .padding(.vertical, Metrics.shelfPad)
            }
            .scrollIndicators(.never)
            #if os(tvOS)
            .scrollClipDisabled()
            .focusSection()
            #endif
        }
    }
}

extension VODShelf where All == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, all: { EmptyView() }, content: content)
    }
}

/// «Se alle» til høyre over en rad.
struct SeeAllLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            Text(L("Se alle"))
            #if os(iOS)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
            #endif
        }
        .font(.system(size: Metrics.pageCount + 1, weight: .semibold))
    }
}

extension View {
    /// «Se alle»: tekst i aksentfargen på iPhone og iPad, en knapp med fokus på Apple TV.
    @ViewBuilder
    func seeAllStyle() -> some View {
        #if os(tvOS)
        buttonStyle(PillStyle(selected: false))
        #else
        buttonStyle(.plain)
            .foregroundStyle(Theme.signal)
        #endif
    }
}

/// En kategori hos IPTV-leverandøren som rad på Hjem (hentes når raden vises), med «Se alle». Tomme kategorier vises
/// ikke.
private struct CategoryShelf: View {
    let model: VODModel
    let category: ChannelCategory
    /// den øverste raden: en plakat fikk fokus
    var onTopFocus: (() -> Void)?
    /// så mange i raden; resten under «Se alle»
    static let shown = 20

    var body: some View {
        let items = model.items[category.id]
        if items?.isEmpty != true {
            VODShelf(title: category.name) {
                Button {
                    model.chosen = category.id
                } label: {
                    SeeAllLabel()
                }
                .seeAllStyle()
                .accessibilityIdentifier("se-alle-\(category.id)")
            } content: {
                if let items {
                    ForEach(items.prefix(Self.shown)) { item in
                        VODPosterLink(item: item, id: "vod-\(item.id)", onFocus: onTopFocus)
                            .frame(width: Metrics.rowPoster)
                    }
                } else {
                    ProgressView()
                        .frame(width: Metrics.rowPoster, height: Metrics.rowPoster * 1.5)
                }
            }
            .task { await model.load(category.id) }
        }
    }
}

/// En plakat som åpner siden for filmen eller serien; hold inne for å legge den til i favorittene.
struct VODPosterLink: View {
    let item: VODItem
    let id: String
    /// i en rad med episoder: episoden på kortet (siden for serien åpnes)
    var episode: Episode?
    /// Apple TV: plakaten fikk fokus (den øverste raden ruller lista helt opp)
    var onFocus: (() -> Void)?

    var body: some View {
        NavigationLink(value: item) {
            PosterCard(item: item, episode: episode)
        }
        .posterButtonStyle()
        .onFocusGained(onFocus)
        .accessibilityIdentifier(id)
        .contextMenu {
            FavoriteToggle(item: item)
        }
    }
}

/// «Legg til i favoritter» eller «Fjern fra favoritter» i hurtigmenyen.
struct FavoriteToggle: View {
    @Environment(AppModel.self) private var app
    let item: VODItem

    var body: some View {
        let favorite = app.isVODFavorite(item)
        Button {
            app.toggleVODFavorite(item)
        } label: {
            Label(favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"),
                  systemImage: favorite ? "star.slash" : "star")
        }
    }
}

/// Et kort i «Fortsett å se»: bredbildet (bakgrunnen, ellers plakaten) med hvor langt du har kommet, og under det
/// tittelen og episoden (eller året).
struct ResumeCard: View {
    let entry: VODResume

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    RemoteImage(url: (entry.image ?? entry.item.poster).flatMap { URL(string: $0) }, fill: true) {
                        ZStack {
                            LinearGradient(colors: [Theme.surface2, Theme.logoBg], startPoint: .top, endPoint: .bottom)
                            Text(entry.item.name)
                                .font(.system(size: Metrics.posterTitle + 4, weight: .bold))
                                .foregroundStyle(Theme.ink2)
                                .multilineTextAlignment(.center)
                                .padding(12)
                        }
                    }
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    if entry.progress > 0 {
                        ResumeBar(progress: entry.progress)
                            .padding(.horizontal, Metrics.resumeBarInset)
                            .padding(.bottom, Metrics.resumeBarInset)
                    }
                }
                #if os(iOS)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.posterRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metrics.posterRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 0.5))
                #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.name)
                    .font(.system(size: Metrics.posterTitle + 2, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.system(size: Metrics.posterTitle))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            #if os(tvOS)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            #else
            .padding(.top, 7)
            #endif
        }
        #if os(tvOS)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        #else
        .contentShape(Rectangle())
        #endif
    }

    /// «S1 E3 · Tåka» for en episode, ellers året (og ingenting når det ikke er kjent).
    private var subtitle: String {
        if let episode = entry.episode {
            let code = "S\(episode.season) E\(episode.number)"
            return episode.title.isEmpty ? code : "\(code) · \(episode.title)"
        }
        return entry.item.year ?? " "
    }
}

/// Hvor langt du har kommet: en hvit strek på en gjennomsiktig.
private struct ResumeBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.32))
                Capsule().fill(Color.white)
                    .frame(width: max(Metrics.resumeBar, geo.size.width * min(1, progress)))
            }
        }
        .frame(height: Metrics.resumeBar)
        .shadow(color: .black.opacity(0.4), radius: 3)
    }
}

/// «Se alle» for en rad fra Plex: alt i raden som plakater (en episode åpner siden for serien).
struct VODRowPage: View {
    let model: VODModel
    let row: VODRow
    @State private var items: [VODRowItem]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(tvOS)
                Text(row.title)
                    .font(.system(size: Metrics.pageTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                #endif
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterMin), spacing: Metrics.posterGap,
                                             alignment: .top)],
                          alignment: .leading, spacing: Metrics.posterGap + 8) {
                    ForEach(items ?? row.items) { entry in
                        VODPosterLink(item: entry.item, id: "alle-\(entry.id)", episode: entry.episode)
                    }
                }
                if items == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.vertical, 12)
            #if os(tvOS)
            .hidesScrollIndex()
            #endif
        }
        .scrollIndicators(.never)
        .background(Theme.bg.ignoresSafeArea())
        .task { items = await model.rowItems(row) }
        #if os(iOS)
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vod-rad")
    }
}

#if os(iOS)
/// Treffene i søket i filmene eller seriene.
struct VODSearchResults: View {
    let model: VODModel
    let query: String
    @State private var results: [VODItem]?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let results {
                    if results.isEmpty {
                        Text(L("Ingen treff."))
                            .font(.system(size: Metrics.pageCount + 2))
                            .foregroundStyle(Theme.muted)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterMin), spacing: Metrics.posterGap,
                                                     alignment: .top)],
                                  alignment: .leading, spacing: Metrics.posterGap + 8) {
                            ForEach(results) { item in
                                VODPosterLink(item: item, id: "sok-\(item.id)")
                            }
                        }
                    }
                } else if failed {
                    Text(L("Søket virket ikke akkurat nå. Prøv igjen."))
                        .font(.system(size: Metrics.pageCount + 2))
                        .foregroundStyle(Theme.muted)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .scrollDismissesKeyboard(.immediately)
        // litt etter siste tastetrykk; hos leverandøren hentes alle første gang
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await model.search(query)
                guard !Task.isCancelled else { return }
                results = found
                failed = false
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vod-treff")
    }
}
#endif
