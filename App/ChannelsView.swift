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
/// øverst, i din rekkefølge) og resten av kategoriene, og kanalkortene til høyre.
struct ChannelsView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    /// det som er valgt i sidemenyen (står i HomeView, så det huskes når du er innom en annen side)
    @Binding var chosen: Shelf?

    private var current: Shelf { chosen ?? (model.favorites.isEmpty ? .all : .favorites) }

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            let shelf = current
            HStack(alignment: .top, spacing: 0) {
                sidebar(rows(), current: shelf)
                    .frame(width: 340)
                    .focusSection()
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1)
                    .padding(.vertical, 12)
                grid(shelf)
                    .focusSection()
            }
            // rullelistene strekker seg ellers opp under fanelinja, og det som rulles forbi, havnet bak den
            .clipped()
            // det som vises først, står til man velger noe annet (ellers hopper siden til Favoritter når den
            // første favoritten legges til)
            .onAppear { if chosen == nil { chosen = shelf } }
        }
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
            rows.append(.hint(L("Hold inne på en kategori for å legge den øverst.")))
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
                            .font(.system(size: 16, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            .padding(.bottom, 6)
                            .accessibilityIdentifier("seksjon-\(id)")
                    case .hint(let text):
                        Text(text)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    case .item(let item):
                        SidebarButton(item: item, selected: item.shelf == current) { chosen = item.shelf }
                    }
                }
            }
            .padding(.vertical, 16)
            .hidesScrollIndex()
        }
        .scrollIndicators(.never)
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

    private func grid(_ shelf: Shelf) -> some View {
        let channels = list(shelf)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(title(shelf))
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(channels.count)")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.muted)
                }
                if channels.isEmpty {
                    Text(shelf == .favorites ? L("Ingen favoritter ennå. Hold inne på en kanal for å legge den til.")
                         : shelf == .recent ? L("Du har ikke sett noen kanaler ennå.") : L("Ingen kanaler her."))
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.muted)
                }
                ChannelGrid(channels: channels, play: play)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .hidesScrollIndex()
        }
        .scrollIndicators(.never)
        .id(shelf)
    }
}

/// En linje i sidemenyen: ikon, navn, antall, og for kategoriene stjernen. Hold inne på en kategori for å legge den
/// øverst, flytte den eller ta den bort fra toppen.
private struct SidebarButton: View {
    @Environment(AppModel.self) private var model
    let item: ShelfItem
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        let button = Button(action: choose) {
            HStack(spacing: 14) {
                if let icon = item.icon {
                    SidebarIcon(name: icon, selected: selected)
                }
                Text(item.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: "\(item.count)")
                    .font(.system(size: 17, weight: .regular))
                    .opacity(0.6)
                if item.pinnable {
                    PinStar(pinned: item.pinned)
                }
            }
        }
        .buttonStyle(SidebarStyle(selected: selected))
        .accessibilityIdentifier(item.shelf.testId)

        if case .category(let id) = item.shelf {
            button.contextMenu {
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
            button
        }
    }
}

/// Ikonet foran alle kanaler, favoritter og sist sett: dempet, gult når den er valgt.
private struct SidebarIcon: View {
    let name: String
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.muted))
            .frame(width: 28)
    }
}

/// Stjernen ved kategoriene: gul når den er lagt øverst.
private struct PinStar: View {
    let pinned: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Image(systemName: pinned ? "star.fill" : "star")
            .font(.system(size: 18, weight: pinned ? .semibold : .regular))
            .foregroundStyle(focused ? Theme.bg : (pinned ? Theme.signal : Theme.muted))
            .accessibilityIdentifier(pinned ? "lagt-overst" : "")
    }
}

/// Når lista er tom: henter, feil, eller ingen kanaler.
struct ListsStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 30) {
            if model.loading || !model.triedOnce {
                ProgressView()
                Text(L("Henter kanalene …"))
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(model.error ?? L("Ingen kanaler her."))
                    .font(.system(size: 30))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
                Button(L("Prøv igjen")) {
                    Task { await model.reload() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Linjene i sidemenyen: lys flate når de har fokus, gul tekst på en litt lysere flate for den som er valgt (som i
/// Fyrlys på Windows).
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
            .font(.system(size: 23, weight: selected ? .bold : .medium))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.ink))
            .padding(.horizontal, 16)
            .frame(height: 54)
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
