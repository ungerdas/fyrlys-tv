#if os(tvOS)
import FyrlysCore
import SwiftUI

/// TV-fanen på Apple TV, som Fyrlys på iPhone og nettet: «Nå på favorittene» og «Sist sett» som rader med store kort
/// (med det som går nå), og kategoriene som fliser. En kategori åpnes som egen side; Menu-knappen går tilbake. Hold inne
/// på en kategori for å legge den øverst eller flytte den, og på en kanal for å gjøre den til favoritt.
struct TVChannels: View {
    @Binding var path: [Shelf]
    let play: (Channel, [Channel]) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            TVHomePage(play: play)
                .navigationDestination(for: Shelf.self) { shelf in
                    TVShelfPage(shelf: shelf, play: play)
                }
        }
    }
}

/// Forsiden: radene og flisene.
private struct TVHomePage: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            let favorites = model.favorites
            let recent = model.recent.filter { !model.isFavorite($0) }
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    if favorites.isEmpty && recent.isEmpty {
                        TVTip()
                            .padding(.horizontal, Theme.edge)
                    }
                    if !favorites.isEmpty {
                        row(L("Nå på favorittene"), id: "seksjon-favoritter", clock: true, channels: favorites)
                    }
                    if !recent.isEmpty {
                        row(L("Sist sett"), id: "seksjon-sist", clock: favorites.isEmpty, channels: recent)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        TVRowHead(title: L("Kategorier"), clock: false)
                            .accessibilityIdentifier("seksjon-kategorier")
                        TVTiles()
                    }
                    .padding(.horizontal, Theme.edge)
                    .focusSection()
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
                .hidesScrollIndex()
            }
            .scrollIndicators(.never)
            .safeAreaPadding(.bottom, Theme.bottomFocus)
            // rullelistene strekker seg ellers opp under fanelinja
            .clipped()
            // nærmere sidene og helt ned (den trygge sonen til Apple TV ga for mye luft); toppen står under fanelinja
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        }
    }

    /// En rad med store kort sidelengs, helt ut til kantene.
    private func row(_ title: String, id: String, clock: Bool, channels: [Channel]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            TVRowHead(title: title, clock: clock)
                .padding(.horizontal, Theme.edge)
                .accessibilityIdentifier(id)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.bigGap) {
                    ForEach(channels) { channel in
                        BigChannelCard(channel: channel) { play(channel, channels) }
                            .frame(width: Metrics.bigStripWidth)
                    }
                }
                // plass til kortet med fokus, som blir litt større
                .padding(.vertical, 18)
            }
            .contentMargins(.horizontal, Theme.edge, for: .scrollContent)
            .scrollClipDisabled()
            .scrollIndicators(.never)
        }
        .focusSection()
    }
}

/// Kategoriene som fliser: Favoritter og Alle kanaler først, så «Dine kategorier» (i gult, i din rekkefølge) og resten.
private struct TVTiles: View {
    @Environment(AppModel.self) private var model

    private static let columns = [GridItem(.adaptive(minimum: Metrics.tileMin, maximum: 420), spacing: Metrics.bigGap)]

    var body: some View {
        let pinned = model.favoriteCategories
        let pinnedIds = Set(pinned.map(\.id))
        LazyVGrid(columns: Self.columns, spacing: Metrics.bigGap) {
            NavigationLink(value: Shelf.favorites) {
                TVTileFace(title: "★ " + L("Favoritter"), count: model.favorites.count, highlighted: true)
            }
            .buttonStyle(TVTileStyle())
            .accessibilityIdentifier(Shelf.favorites.testId)
            NavigationLink(value: Shelf.all) {
                TVTileFace(title: L("Alle kanaler"), count: model.channels.count, highlighted: false)
            }
            .buttonStyle(TVTileStyle())
            .accessibilityIdentifier(Shelf.all.testId)
            ForEach(Array(pinned.enumerated()), id: \.element.id) { i, category in
                tile(category, pinned: true, first: i == 0, last: i == pinned.count - 1)
            }
            ForEach(model.categories.filter { !pinnedIds.contains($0.id) }) { category in
                tile(category, pinned: false, first: false, last: false)
            }
        }
    }

    /// En kategori: trykk for å åpne den, hold inne for å legge den øverst, flytte den eller ta den bort fra toppen.
    private func tile(_ category: ChannelCategory, pinned: Bool, first: Bool, last: Bool) -> some View {
        NavigationLink(value: Shelf.category(category.id)) {
            TVTileFace(title: category.name, count: model.channels(in: category.id).count, highlighted: pinned)
        }
        .buttonStyle(TVTileStyle())
        .contextMenu {
            if pinned {
                if !first {
                    Button { model.moveFavoriteCategory(category.id, by: -1) } label: {
                        Label(L("Flytt opp"), systemImage: "arrow.up")
                    }
                }
                if !last {
                    Button { model.moveFavoriteCategory(category.id, by: 1) } label: {
                        Label(L("Flytt ned"), systemImage: "arrow.down")
                    }
                }
                Button { model.toggleFavoriteCategory(category.id) } label: {
                    Label(L("Fjern fra toppen"), systemImage: "star.slash")
                }
            } else {
                Button { model.toggleFavoriteCategory(category.id) } label: {
                    Label(L("Legg øverst"), systemImage: "star")
                }
            }
        }
        .accessibilityIdentifier(Shelf.category(category.id).testId)
    }
}

/// Navnet og antallet på en flis.
private struct TVTileFace: View {
    let title: String
    let count: Int
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: Metrics.tileTitle, weight: .bold))
                .foregroundStyle(highlighted ? Theme.signal : Theme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text(verbatim: CountText.of(count))
                .font(.system(size: Metrics.tileCount, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(Metrics.tilePad)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Metrics.tileHeight)
    }
}

/// Flisene: mørk flate med tynn kant; med fokus lyseblå kant, lysere flate, litt større og med skygge.
private struct TVTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVTileBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct TVTileBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
        label
            .background(shape.fill(focused ? Theme.surface2 : Theme.surface))
            .overlay(shape.strokeBorder(focused ? Theme.focus : Theme.line, lineWidth: focused ? 4 : 1))
            .scaleEffect(focused ? (pressed ? 1.0 : 1.05) : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 18 : 0, y: focused ? 10 : 0)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// En kategori (eller Favoritter, Alle kanaler) som egen side: navnet, antallet, stjernen som legger den øverst, og de
/// store kortene. Menu-knappen går tilbake.
private struct TVShelfPage: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf
    let play: (Channel, [Channel]) -> Void

    var body: some View {
        let channels = list
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 22) {
                    Text(title)
                        .font(.system(size: Metrics.pageTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(verbatim: CountText.of(channels.count))
                        .font(.system(size: Metrics.pageCount))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    if case .category(let id) = shelf {
                        let pinned = model.isFavoriteCategory(id)
                        Button {
                            model.toggleFavoriteCategory(id)
                        } label: {
                            Label(pinned ? L("Fjern fra toppen") : L("Legg øverst"), systemImage: pinned ? "star.fill" : "star")
                        }
                        .accessibilityIdentifier("kategori-stjerne")
                    }
                }
                .padding(.horizontal, Theme.edge)
                .focusSection()
                if channels.isEmpty && !model.channels.isEmpty {
                    Text(emptyText)
                        .font(.system(size: Metrics.pageCount + 4))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.edge)
                }
                BigCardGrid(channels: channels, play: play)
                    .padding(.horizontal, Theme.edge)
                    .focusSection()
            }
            .padding(.top, 24)
            .padding(.bottom, 40)
            .hidesScrollIndex()
        }
        .scrollIndicators(.never)
        .safeAreaPadding(.bottom, Theme.bottomFocus)
        .clipped()
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
    }

    private var list: [Channel] {
        switch shelf {
        case .favorites: return model.favorites
        case .recent: return model.recent
        case .all: return model.allChannels
        case .category(let id): return model.channels(in: id)
        }
    }

    private var title: String {
        switch shelf {
        case .favorites: return "★ " + L("Favoritter")
        case .recent: return L("Sist sett")
        case .all: return L("Alle kanaler")
        case .category(let id): return model.index.category(id)?.name ?? ""
        }
    }

    private var emptyText: String {
        switch shelf {
        case .favorites: return L("Ingen favoritter ennå. Hold inne på en kanal for å legge den til.")
        case .recent: return L("Du har ikke sett noen kanaler ennå.")
        default: return L("Ingen kanaler her.")
        }
    }
}

/// De store kortene i et rutenett (en kategori og søket): så mange i bredden det er plass til, fem på en TV.
struct BigCardGrid: View {
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void

    private static let columns = [GridItem(.adaptive(minimum: Metrics.bigGridMin, maximum: 420),
                                           spacing: Metrics.bigGap, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: Metrics.bigGap + 8) {
            ForEach(channels) { channel in
                BigChannelCard(channel: channel) { play(channel, channels) }
            }
        }
    }
}

/// Overskriften over en rad, med klokka til høyre.
private struct TVRowHead: View {
    let title: String
    let clock: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: Metrics.rowTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            if clock {
                TimelineView(.everyMinute) { context in
                    Text(verbatim: hhmm(context.date))
                        .font(.system(size: Metrics.rowClock, weight: .bold))
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Første gang (ingen favoritter og ingenting sett): hvordan favorittene samles her.
private struct TVTip: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: "star.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.signal)
            // fet første setning (markdown i teksten)
            Text(LocalizedStringKey(L("**Samle favorittene dine her.** Hold inne på en kanal og velg «Legg til i favoritter», så ligger den øverst med det som går nå. I TV-guiden ser du hva som kommer senere.")))
                .font(.system(size: 24))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }
}
#endif
