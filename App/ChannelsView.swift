import FyrlysCore
import SwiftUI

/// Hva som vises i rutenettet.
enum Shelf: Hashable {
    case favorites, recent, all
    case category(String)

    var testId: String {
        switch self {
        case .favorites: return "hylle-favoritter"
        case .recent: return "hylle-sist"
        case .all: return "hylle-alle"
        case .category(let id): return "hylle-\(id)"
        }
    }
}

/// En linje i sidemenyen.
struct ShelfItem {
    let shelf: Shelf
    let title: String
    let count: Int
    var icon: String?
    /// en kategori (kan legges øverst)
    var pinnable = false
    /// i «Dine kategorier»
    var pinned = false
    var first = false
    var last = false
}

enum SidebarRow: Identifiable {
    case header(id: String, text: String)
    case hint(String)
    case item(ShelfItem)

    var id: String {
        switch self {
        case .header(let id, _): return "seksjon-\(id)"
        case .hint: return "hint"
        case .item(let item): return item.shelf.testId
        }
    }
}

/// TV-fanen som i Fyrlys på Windows: sidemenyen med alle kanaler, favoritter, sist sett, «Dine kategorier» (lagt
/// øverst, i din rekkefølge) og resten av kategoriene, og kanalkortene til høyre (Apple TV og iPad; iPhone har
/// `PhoneTV`). På Apple TV de store kortene, fire i bredden, med «Nå på favorittene» og «Sist sett» øverst i «Alle
/// kanaler» (`TVChannelPanel`), og Fyrlys-merket over sidemenyen; på iPad de smale kortene.
struct ChannelsView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    /// det som er valgt i sidemenyen (står i HomeView, så det huskes når du er innom en annen side)
    @Binding var chosen: Shelf?

    /// Apple TV: «Alle kanaler» (med favorittene øverst); iPad: favorittene hvis det finnes noen.
    private var current: Shelf {
        #if os(tvOS)
        chosen ?? .all
        #else
        chosen ?? (model.favorites.isEmpty ? .all : .favorites)
        #endif
    }

    var body: some View {
        Group {
            if model.channels.isEmpty {
                ListsStatus()
            } else {
                let shelf = current
                split(shelf)
                    // det som vises først, står til man velger noe annet (ellers hopper siden til Favoritter når den
                    // første favoritten legges til)
                    .onAppear { if chosen == nil { chosen = shelf } }
            }
        }
        #if !os(tvOS)
        // fanene på iPad har ellers systemets bakgrunn (svart eller hvit), ikke fargen til Fyrlys
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        #endif
    }

    /// Sidemenyen og rutenettet (Apple TV og iPad).
    private func split(_ shelf: Shelf) -> some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar(rows(), current: shelf)
                .frame(width: Metrics.sidebarWidth)
                #if os(tvOS)
                // sidemenyen ruller ikke opp under Fyrlys-merket over den (kortene til høyre ruller helt opp når
                // fanelinja glir bort)
                .clipped()
                .overlay(alignment: .topLeading) {
                    TVBrand()
                        .alignmentGuide(.top) { $0[.bottom] + Metrics.brandGap }
                }
                #endif
                .tvFocusSection()
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
                .padding(.vertical, 12)
            grid(shelf)
                .tvFocusSection()
        }
        #if os(tvOS)
        .padding(.horizontal, Theme.edge)
        // nærmere sidene og helt ned (den trygge sonen til Apple TV ga for mye luft). Toppen begynner under fanelinja,
        // men kortene klippes ikke der: når fanelinja glir bort, ruller de helt opp (0.1.2–0.1.7 klippet dem, og da ble
        // det en tom stripe øverst med kortene kuttet under)
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        #else
        // rullelistene strekker seg ellers opp under linja øverst og klokka på iPad
        .clipped()
        #endif
    }

    // ── sidemenyen ──

    private func rows() -> [SidebarRow] {
        var rows: [SidebarRow] = [
            .item(ShelfItem(shelf: .all, title: L("Alle kanaler"), count: model.channels.count, icon: "square.grid.2x2")),
            .item(ShelfItem(shelf: .favorites, title: L("Favoritter"), count: model.favorites.count, icon: "star")),
            .item(ShelfItem(shelf: .recent, title: L("Sist sett"), count: model.recent.count,
                            icon: "clock.arrow.circlepath")),
        ]
        let pinned = model.favoriteCategories
        if pinned.isEmpty {
            rows.append(.header(id: "kategorier", text: L("Kategorier")))
            #if os(tvOS)
            rows.append(.hint(L("Hold inne på en kategori for å legge den øverst.")))
            #else
            rows.append(.hint(L("Trykk på stjernen for å legge en kategori øverst.")))
            #endif
        } else {
            rows.append(.header(id: "dine", text: L("Dine kategorier")))
            for (i, category) in pinned.enumerated() {
                rows.append(.item(ShelfItem(shelf: .category(category.id), title: category.name,
                                            count: model.channels(in: category.id).count, pinnable: true,
                                            pinned: true, first: i == 0, last: i == pinned.count - 1)))
            }
            rows.append(.header(id: "alle", text: L("Alle kategorier")))
        }
        let pinnedIds = Set(pinned.map(\.id))
        for category in model.categories where !pinnedIds.contains(category.id) {
            rows.append(.item(ShelfItem(shelf: .category(category.id), title: category.name,
                                        count: model.channels(in: category.id).count, pinnable: true)))
        }
        return rows
    }

    private func sidebar(_ rows: [SidebarRow], current: Shelf) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    switch row {
                    case .header(let id, let text):
                        Text(text.uppercased())
                            .font(.system(size: Metrics.sectionFont, weight: .bold))
                            .tracking(Metrics.sectionFont * 0.075)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, Metrics.sidebarFont + 1)
                            .padding(.top, Metrics.sidebarFont)
                            .padding(.bottom, 6)
                            .accessibilityIdentifier("seksjon-\(id)")
                    case .hint(let text):
                        Text(text)
                            .font(.system(size: Metrics.smallFont))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Metrics.sidebarFont + 1)
                            .padding(.bottom, 8)
                    case .item(let item):
                        SidebarButton(item: item, selected: item.shelf == current) { chosen = item.shelf }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 24)
            .hidesScrollIndex()
        }
        .scrollIndicators(.never)
        #if os(tvOS)
        .safeAreaPadding(.bottom, Theme.bottomFocus)
        #endif
    }

    // ── rutenettet ──

    private func list(_ shelf: Shelf) -> [Channel] {
        switch shelf {
        case .favorites: return model.favorites
        case .recent: return model.recent
        case .all: return model.allChannels
        case .category(let id): return model.channels(in: id)
        }
    }

    private func title(_ shelf: Shelf) -> String {
        switch shelf {
        case .favorites: return L("Favoritter")
        case .recent: return L("Sist sett")
        case .all: return L("Alle kanaler")
        case .category(let id): return model.index.category(id)?.name ?? ""
        }
    }

    private func emptyText(_ shelf: Shelf) -> String {
        shelf == .favorites ? L("Ingen favoritter ennå. Hold inne på en kanal for å legge den til.")
            : shelf == .recent ? L("Du har ikke sett noen kanaler ennå.") : L("Ingen kanaler her.")
    }

    #if os(tvOS)
    private func grid(_ shelf: Shelf) -> some View {
        TVChannelPanel(shelf: shelf, title: title(shelf), channels: list(shelf), emptyText: emptyText(shelf), play: play)
            .id(shelf)
    }
    #else
    private func grid(_ shelf: Shelf) -> some View {
        let channels = list(shelf)
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.gridSpacing + 2) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(title(shelf))
                        .font(.system(size: Metrics.pageTitle, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(channels.count)")
                        .font(.system(size: Metrics.pageCount))
                        .foregroundStyle(Theme.muted)
                }
                if channels.isEmpty {
                    Text(emptyText(shelf))
                        .font(.system(size: Metrics.pageCount + 4))
                        .foregroundStyle(Theme.muted)
                }
                ChannelGrid(channels: channels, play: play)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .hidesScrollIndex()
        }
        .scrollIndicators(.never)
        .refreshable { await model.reload() }
        .id(shelf)
    }
    #endif
}

#if !os(tvOS)
/// Kategoriene på iPhone, som et ark: alle kanaler, favoritter og sist sett, «Dine kategorier» (dra for å sortere,
/// stjernen tar dem bort fra toppen) og resten av kategoriene (stjernen legger dem øverst), med søk.
struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var chosen: Shelf?
    let current: Shelf
    @State private var filter = ""

    private func matches(_ category: ChannelCategory) -> Bool {
        let text = filter.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || category.name.localizedCaseInsensitiveContains(text)
    }

    var body: some View {
        let pinned = model.favoriteCategories
        let pinnedIds = Set(pinned.map(\.id))
        NavigationStack {
            List {
                if filter.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        row(.all, L("Alle kanaler"), model.channels.count, icon: "square.grid.2x2")
                        row(.favorites, L("Favoritter"), model.favorites.count, icon: "star")
                        row(.recent, L("Sist sett"), model.recent.count, icon: "clock.arrow.circlepath")
                    }
                }
                if !pinned.isEmpty {
                    Section {
                        ForEach(pinned.filter(matches)) { category in
                            categoryRow(category, pinned: true)
                        }
                        .onMove(perform: filter.isEmpty ? move : nil)
                    } header: {
                        Text(L("Dine kategorier"))
                            .accessibilityIdentifier("seksjon-dine")
                    }
                }
                Section {
                    ForEach(model.categories.filter { !pinnedIds.contains($0.id) && matches($0) }) { category in
                        categoryRow(category, pinned: false)
                    }
                } header: {
                    Text(pinned.isEmpty ? L("Kategorier") : L("Alle kategorier"))
                } footer: {
                    if pinned.isEmpty {
                        Text(L("Trykk på stjernen for å legge en kategori øverst."))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $filter, prompt: L("Søk i kategoriene"))
            .navigationTitle(L("Kategorier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !pinned.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Ferdig")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func choose(_ shelf: Shelf) {
        chosen = shelf
        dismiss()
    }

    /// Dine kategorier i ny rekkefølge (dra og slipp).
    private func move(_ from: IndexSet, _ to: Int) {
        var ids = model.favoriteCategories.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        model.setFavoriteCategoryOrder(ids)
    }

    private func row(_ shelf: Shelf, _ title: String, _ count: Int, icon: String) -> some View {
        Button {
            choose(shelf)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(shelf == current ? Theme.signal : Theme.muted)
                    .frame(width: 24)
                Text(title)
                    .fontWeight(shelf == current ? .bold : .regular)
                    .foregroundStyle(shelf == current ? Theme.signal : Theme.ink)
                Spacer()
                Text(verbatim: "\(count)")
                    .foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(shelf.testId)
        .listRowBackground(Theme.surface)
    }

    private func categoryRow(_ category: ChannelCategory, pinned: Bool) -> some View {
        let shelf = Shelf.category(category.id)
        return HStack(spacing: 12) {
            Button {
                choose(shelf)
            } label: {
                HStack(spacing: 12) {
                    Text(category.name)
                        .fontWeight(shelf == current ? .bold : .regular)
                        .foregroundStyle(shelf == current ? Theme.signal : Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(model.channels(in: category.id).count)")
                        .foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(shelf.testId)
            Button {
                model.toggleFavoriteCategory(category.id)
            } label: {
                Image(systemName: pinned ? "star.fill" : "star")
                    .foregroundStyle(pinned ? Theme.signal : Theme.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("stjerne-\(category.id)")
            .accessibilityLabel(pinned ? L("Fjern fra toppen") : L("Legg øverst"))
        }
        .listRowBackground(Theme.surface)
    }
}
#endif

/// En linje i sidemenyen: ikon, navn, antall, og for kategoriene stjernen. Hold inne på en kategori for å legge den
/// øverst, flytte den eller ta den bort fra toppen; på iPad kan du også trykke på stjernen.
private struct SidebarButton: View {
    @Environment(AppModel.self) private var model
    let item: ShelfItem
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        if case .category(let id) = item.shelf {
            row.contextMenu {
                if item.pinned {
                    if !item.first {
                        Button { model.moveFavoriteCategory(id, by: -1) } label: {
                            Label(L("Flytt opp"), systemImage: "arrow.up")
                        }
                    }
                    if !item.last {
                        Button { model.moveFavoriteCategory(id, by: 1) } label: {
                            Label(L("Flytt ned"), systemImage: "arrow.down")
                        }
                    }
                    Button { model.toggleFavoriteCategory(id) } label: {
                        Label(L("Fjern fra toppen"), systemImage: "star.slash")
                    }
                } else {
                    Button { model.toggleFavoriteCategory(id) } label: {
                        Label(L("Legg øverst"), systemImage: "star")
                    }
                }
            }
        } else {
            row
        }
    }

    private var label: some View {
        HStack(spacing: Metrics.sidebarIcon * 0.65) {
            if let icon = item.icon {
                SidebarIcon(name: icon, selected: selected)
            }
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: "\(item.count)")
                .font(.system(size: Metrics.smallFont, weight: .regular))
                .opacity(0.6)
        }
    }

    #if os(tvOS)
    /// Hele linja er én knapp som får fokus; stjernen viser bare om kategorien er lagt øverst.
    private var row: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                label
                if item.pinnable {
                    PinStar(pinned: item.pinned)
                }
            }
        }
        .buttonStyle(SidebarStyle(selected: selected))
        .accessibilityIdentifier(item.shelf.testId)
    }
    #else
    /// Trykk på linja velger, trykk på stjernen legger kategorien øverst eller tar den bort.
    private var row: some View {
        HStack(spacing: 4) {
            Button(action: choose) {
                label
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(item.shelf.testId)
            if case .category(let id) = item.shelf {
                Button {
                    model.toggleFavoriteCategory(id)
                } label: {
                    PinStar(pinned: item.pinned)
                        .frame(width: 30, height: Metrics.sidebarRow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stjerne-\(id)")
                .accessibilityLabel(item.pinned ? L("Fjern fra toppen") : L("Legg øverst"))
            }
        }
        .font(.system(size: Metrics.sidebarFont, weight: selected ? .bold : .medium))
        .foregroundStyle(selected ? Theme.signal : Theme.ink)
        .padding(.leading, 12)
        .padding(.trailing, item.pinnable ? 2 : 12)
        .frame(height: Metrics.sidebarRow)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.surface2 : Color.clear)
        )
        .padding(.horizontal, 8)
    }
    #endif
}

/// Ikonet foran alle kanaler, favoritter og sist sett (og bibliotekene i Plex-fanen): dempet, gult når den er valgt.
struct SidebarIcon: View {
    let name: String
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Image(systemName: name)
            .font(.system(size: Metrics.sidebarIcon, weight: .medium))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.muted))
            .frame(width: Metrics.sidebarIcon * 1.35)
    }
}

/// Stjernen ved kategoriene: gul når den er lagt øverst.
private struct PinStar: View {
    let pinned: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Image(systemName: pinned ? "star.fill" : "star")
            .font(.system(size: Metrics.sidebarIcon * 0.86, weight: pinned ? .semibold : .regular))
            .foregroundStyle(focused ? Theme.bg : (pinned ? Theme.signal : Theme.muted))
            .accessibilityIdentifier(pinned ? "lagt-overst" : "")
    }
}

/// Når lista er tom: henter, feil, eller ingen kanaler.
struct ListsStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Metrics.pageTitle * 0.9) {
            if model.loading || !model.triedOnce {
                ProgressView()
                Text(L("Henter kanalene …"))
                    .font(.system(size: Metrics.pageCount + 8))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(model.error ?? L("Ingen kanaler her."))
                    .font(.system(size: Metrics.pageCount + 8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
                    .padding(.horizontal, 20)
                Button(L("Prøv igjen")) {
                    Task { await model.reload() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Linjene i sidemenyen på Apple TV: lys flate når de har fokus, gul tekst på en litt lysere flate for den som er
/// valgt (som i Fyrlys på Windows).
struct SidebarStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarLabel(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}

private struct SidebarLabel<Label: View>: View {
    let label: Label
    let selected: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .font(.system(size: Metrics.sidebarFont, weight: selected ? .bold : .medium))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.ink))
            .padding(.horizontal, 16)
            .frame(height: Metrics.sidebarRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(focused ? Theme.ink : (selected ? Theme.surface2 : Color.clear))
            )
            .padding(.horizontal, 8)
            .scaleEffect(focused ? (pressed ? 1.0 : 1.03) : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
