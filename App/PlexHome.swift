import FyrlysCore
import SwiftUI

/// «Hjem» i Filmer og Serier med Plex, som Hjem i Plex: «Fortsett å se» og radene derfra («Nytt fra …», «Nylig lagt
/// til …»). Filmer og serier åpnes som egen side; episodene spilles med en gang der du slapp (hold inne for serien).
struct PlexHomeView: View {
    @Environment(AppModel.self) private var app
    let model: VODModel
    /// åpner siden for en film eller serie
    let open: (VODItem) -> Void
    @State private var playing: VODPlay?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if !model.continueRow.isEmpty {
                    row(L("Fortsett å se"), items: model.continueRow.map { VODRowItem(item: $0) }, prefix: "fortsett-")
                }
                ForEach(model.rows) { r in
                    row(r.title, items: r.items, prefix: "rad-")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plex-hjem")
    }

    private func row(_ title: String, items: [VODRowItem], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: Metrics.rowTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.posterGap) {
                    ForEach(items) { entry in
                        card(entry, prefix: prefix)
                            .frame(width: Metrics.posterMin)
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

    @ViewBuilder
    private func card(_ entry: VODRowItem, prefix: String) -> some View {
        if let episode = entry.episode {
            // id-en på knappen selv (etter hurtigmenyen ble den borte av og til på iPhone og iPad)
            Button {
                Task { await play(episode, show: entry.item) }
            } label: {
                PosterCard(item: entry.item, episode: episode)
            }
            .accessibilityIdentifier("\(prefix)\(entry.id)")
            .posterButtonStyle()
            .contextMenu {
                Button {
                    open(entry.item)
                } label: {
                    Label(L("Gå til serien"), systemImage: "rectangle.stack")
                }
            }
        } else {
            NavigationLink(value: entry.item) {
                PosterCard(item: entry.item)
            }
            .posterButtonStyle()
            .accessibilityIdentifier("\(prefix)\(entry.id)")
        }
    }

    /// En episode fra en rad: der du slapp (hos Plex eller på enheten).
    private func play(_ episode: Episode, show: VODItem) async {
        let full = await model.withFile(episode)
        let urls = model.episodeURLs(full)
        guard !urls.isEmpty else { return }
        let start = full.resume > 0 ? full.resume : app.progress(full.progressKey)
        let subtitle = L("Sesong {s}, episode {e}", ["s": full.season, "e": full.number]) + ": " + full.title
        playing = VODPlay(id: full.progressKey, urls: urls, title: show.name, subtitle: subtitle,
                          progressKey: full.progressKey, start: start, item: show, plex: full.id)
    }

    /// Spilleren er lukket: radene og «Fortsett å se» på nytt (litt etter, så Plex har fått med seg det siste).
    private func closed() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await model.refreshContinue()
        }
    }
}
