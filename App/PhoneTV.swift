#if os(iOS)
import FyrlysCore
import SwiftUI

/// TV-fanen på iPhone, som Fyrlys-nettsiden på en telefon: søk, favorittene og det du har sett sist (med det som går
/// nå), og kategoriene som fliser. En kategori åpnes som egen side med tilbake-knapp, kategorien (trykk for å bytte) og
/// en stjerne som legger den øverst.
struct PhoneTV: View {
    @Binding var path: [Shelf]
    @Binding var query: String
    let play: (Channel, [Channel]) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            PhoneTVHome(query: $query, play: play)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Shelf.self) { shelf in
                    PhoneShelfPage(shelf: shelf, play: play)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}

/// Forsiden på TV-fanen.
private struct PhoneTVHome: View {
    @Environment(AppModel.self) private var model
    @Binding var query: String
    let play: (Channel, [Channel]) -> Void

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if model.channels.isEmpty {
                ListsStatus()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SearchField(text: $query)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)
                        if searching {
                            results
                        } else {
                            sections
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await model.reload() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .background(SwipeBackEnabler())
    }

    /// Søket: kanalene som passer, med kanalene i «Dine kategorier» først.
    private var results: some View {
        let found = model.search(query, limit: 120)
        return VStack(alignment: .leading, spacing: 12) {
            RowHead(title: L("Treff")) {
                Text(verbatim: CountText.of(found.count))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.muted)
            }
            if found.isEmpty {
                Text(L("Ingen treff."))
                    .foregroundStyle(Theme.muted)
            }
            CardGrid(channels: found, play: play)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var sections: some View {
        let favorites = model.favorites
        let recent = model.recent.filter { !model.isFavorite($0) }
        VStack(alignment: .leading, spacing: 22) {
            if favorites.isEmpty && recent.isEmpty {
                TipBox()
                    .padding(.horizontal, 16)
            }
            if !favorites.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    RowHead(title: L("Nå på favorittene")) { HeadClock() }
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("seksjon-favoritter")
                    Strip(channels: favorites, play: play)
                }
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    RowHead(title: L("Sist sett")) {
                        if favorites.isEmpty { HeadClock() }
                    }
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("seksjon-sist")
                    Strip(channels: recent, play: play)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                RowHead(title: L("Kategorier")) { EmptyView() }
                    .accessibilityIdentifier("seksjon-kategorier")
                Tiles()
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Kategoriene som fliser, to i bredden: Favoritter og Alle kanaler først, så «Dine kategorier» (i gult) og resten.
private struct Tiles: View {
    @Environment(AppModel.self) private var model

    private struct Tile: Identifiable {
        let shelf: Shelf
        let title: String
        let count: Int
        let highlighted: Bool
        var id: String { shelf.testId }
    }

    /// to i bredden stående, flere liggende
    private static let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(tiles()) { tile in
                NavigationLink(value: tile.shelf) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tile.title)
                            .font(.system(size: 17, weight: .bold))
                            .tracking(-0.17)
                            .foregroundStyle(tile.highlighted ? Theme.signal : Theme.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Text(verbatim: CountText.of(tile.count))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 98)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier(tile.id)
            }
        }
    }

    private func tiles() -> [Tile] {
        var tiles = [
            Tile(shelf: .favorites, title: "★ " + L("Favoritter"), count: model.favorites.count, highlighted: true),
            Tile(shelf: .all, title: L("Alle kanaler"), count: model.channels.count, highlighted: false),
        ]
        let pinned = model.favoriteCategories
        let pinnedIds = Set(pinned.map(\.id))
        for category in pinned {
            tiles.append(Tile(shelf: .category(category.id), title: category.name,
                              count: model.channels(in: category.id).count, highlighted: true))
        }
        for category in model.categories where !pinnedIds.contains(category.id) {
            tiles.append(Tile(shelf: .category(category.id), title: category.name,
                              count: model.channels(in: category.id).count, highlighted: false))
        }
        return tiles
    }
}

/// En kategori (eller Favoritter, Sist sett, Alle kanaler) som egen side: tilbake, kategorien i en pille (trykk for å
/// velge en annen) og stjernen, og kortene to i bredden.
struct PhoneShelfPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf
    @State private var picking = false
    let play: (Channel, [Channel]) -> Void

    init(shelf: Shelf, play: @escaping (Channel, [Channel]) -> Void) {
        _shelf = State(initialValue: shelf)
        self.play = play
    }

    var body: some View {
        let channels = list(shelf)
        VStack(spacing: 0) {
            header(count: channels.count)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if channels.isEmpty && !model.channels.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 14)
                    }
                    CardGrid(channels: channels, play: play)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable { await model.reload() }
            .id(shelf)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .background(SwipeBackEnabler())
        .sheet(isPresented: $picking) {
            CategoryPicker(chosen: Binding(get: { shelf }, set: { if let new = $0 { shelf = new } }), current: shelf)
                .environment(model)
        }
    }

    /// Tilbake, pillen med kategorien og stjernen (står fast øverst; kortene ruller under).
    private func header(count: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tilbake")
            .accessibilityLabel(L("Tilbake"))
            Button {
                picking = true
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(verbatim: CountText.of(count))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kategori-velger")
            if case .category(let id) = shelf {
                let pinned = model.isFavoriteCategory(id)
                Button {
                    model.toggleFavoriteCategory(id)
                } label: {
                    Image(systemName: pinned ? "star.fill" : "star")
                        .font(.system(size: 19, weight: pinned ? .semibold : .regular))
                        .foregroundStyle(pinned ? Theme.signal : Theme.ink)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.surface))
                        .overlay(Circle().strokeBorder(pinned ? Theme.signal : Theme.line, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("kategori-stjerne")
                .accessibilityLabel(pinned ? L("Fjern fra toppen") : L("Legg øverst"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bg)
    }

    private func list(_ shelf: Shelf) -> [Channel] {
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
        case .favorites: return L("Ingen favoritter ennå. Trykk på stjernen på en kanal for å legge den til her.")
        case .recent: return L("Du har ikke sett noen kanaler ennå.")
        default: return L("Ingen kanaler her.")
        }
    }
}

/// Kortene to i bredden (kategorisiden og søket); liggende flere (før to kjempekort, og knapt én rad synlig).
private struct CardGrid: View {
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void

    private static let columns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(channels) { channel in
                BigChannelCard(channel: channel) { play(channel, channels) }
            }
        }
    }
}

/// En rad med kort du kan rulle sidelengs, to synlige om gangen (fire liggende) (favorittene og «Sist sett»).
private struct Strip: View {
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void
    @Environment(\.verticalSizeClass) private var vertical

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(channels) { channel in
                    BigChannelCard(channel: channel) { play(channel, channels) }
                        .containerRelativeFrame(.horizontal, count: vertical == .compact ? 4 : 2, spacing: 12)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Overskriften over en del av siden, med noe til høyre (klokka, antallet).
private struct RowHead<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.42)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Klokka ved «Nå på favorittene» (eller «Sist sett»).
private struct HeadClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(verbatim: hhmm(context.date))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink2)
        }
    }
}

/// Første gang (ingen favoritter og ingenting sett): hvordan favorittene samles her.
private struct TipBox: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "star.fill")
                .font(.system(size: 19))
                .foregroundStyle(Theme.signal)
            // fet første setning (markdown i teksten)
            Text(LocalizedStringKey(L("**Samle favorittene dine her.** Trykk på stjernen på kanalene du ser mest, så ligger de øverst med det som går nå. I TV-guiden ser du hva som kommer senere.")))
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
#endif
