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

struct ShelfItem: Identifiable {
    let shelf: Shelf
    let title: String
    let count: Int
    var id: Shelf { shelf }
}

/// TV-fanen: favoritter, sist sett, alle kanaler og kategoriene til venstre, kanalkortene til høyre.
struct ChannelsView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    @State private var chosen: Shelf?

    private var current: Shelf { chosen ?? (model.favorites.isEmpty ? .all : .favorites) }

    private var items: [ShelfItem] {
        var out = [ShelfItem(shelf: .favorites, title: L("Favoritter"), count: model.favorites.count)]
        let recent = model.recent
        if !recent.isEmpty { out.append(ShelfItem(shelf: .recent, title: L("Sist sett"), count: recent.count)) }
        out.append(ShelfItem(shelf: .all, title: L("Alle kanaler"), count: model.channels.count))
        out += model.categories.map {
            ShelfItem(shelf: .category($0.id), title: $0.name, count: model.channels(in: $0.id).count)
        }
        return out
    }

    private func list(_ shelf: Shelf) -> [Channel] {
        switch shelf {
        case .favorites: return model.favorites
        case .recent: return model.recent
        case .all: return model.channels
        case .category(let id): return model.channels(in: id)
        }
    }

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            HStack(alignment: .top, spacing: 36) {
                sidebar
                    .focusSection()
                grid
                    .focusSection()
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                Text(L("Kategorier"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                ForEach(items) { item in
                    Button {
                        chosen = item.shelf
                    } label: {
                        HStack(spacing: 12) {
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: "\(item.count)").opacity(0.55)
                        }
                    }
                    .buttonStyle(SidebarStyle(selected: item.shelf == current))
                    .accessibilityIdentifier(item.shelf.testId)
                }
            }
            .padding(.vertical, 30)
        }
        .frame(width: 400)
    }

    private var grid: some View {
        let shelf = current
        let channels = list(shelf)
        let title = items.first { $0.shelf == shelf }?.title ?? ""
        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                if channels.isEmpty {
                    Text(shelf == .favorites ? L("Ingen favoritter ennå. Hold inne på en kanal for å legge den til.")
                         : shelf == .recent ? L("Du har ikke sett noen kanaler ennå.") : L("Ingen kanaler her."))
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.muted)
                }
                ChannelGrid(channels: channels, play: play)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
        }
        .id(shelf)
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

/// Knappene i sidemenyen: lys flate når de har fokus, gul tekst for den som er valgt.
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
            .font(.system(size: 28, weight: selected ? .semibold : .regular))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.ink))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(focused ? Theme.ink : Color.clear))
            .scaleEffect(focused ? (pressed ? 1.0 : 1.04) : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
