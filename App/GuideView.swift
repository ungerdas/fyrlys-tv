#if os(tvOS)
import FyrlysCore
import Observation
import SwiftUI

/// Et program i guiden (kanal og start), det fokus står på.
struct GuideSlot: Hashable {
    let channel: String
    let start: Date
}

/// Programmet fokus står på, som vises øverst. Egen observerbar, så bare overskriften tegnes på nytt når fokus flytter
/// seg (før ble hele guiden tegnet på nytt for hvert steg).
@MainActor
@Observable
final class GuideSelection {
    var slot: GuideSlot?
}

/// TV-guiden: seks timer fra halvtimen før denne halvtimen, med en rød strek for nå. Viser favorittene, sist sett,
/// alle kanaler eller en kategori (valget oppe til høyre, lagret som `guide`, som på iPhone; uten valg favorittene,
/// ellers den første av «Dine kategorier», ellers alle). Øverst står programmet du står på.
struct GuideView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    @State private var selection = GuideSelection()
    @AppStorage("guide", store: TestSupport.defaults) private var stored = ""

    /// 300 + 12 + 360 min × 4,2 = 1824 pt: får plass mellom kantene (1920 − 2 × Theme.edge) uten vannrett rulling
    static let perMinute: CGFloat = 4.2
    static let nameWidth: CGFloat = 300
    static let rowHeight: CGFloat = 66
    static var width: CGFloat { CGFloat(GuideTime.totalMinutes) * perMinute }

    private var choice: Shelf {
        if stored == "fav" { return .favorites }
        if stored == "recent" { return .recent }
        if stored == "all" { return .all }
        if stored.hasPrefix("k:") {
            let id = String(stored.dropFirst(2))
            if model.index.category(id) != nil { return .category(id) }
        }
        if !model.favorites.isEmpty { return .favorites }
        if let first = model.favoriteCategories.first { return .category(first.id) }
        return .all
    }

    private var rows: [Channel] {
        switch choice {
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

    /// Hva guiden viser: favorittene, sist sett, alle, «Dine kategorier» og resten av kategoriene.
    private var chooser: some View {
        let current = choice
        let pinned = model.favoriteCategories
        let pinnedIds = Set(pinned.map(\.id))
        return Menu {
            Button { stored = "fav" } label: { Label(L("Favoritter"), systemImage: "star") }
            Button { stored = "recent" } label: { Label(L("Sist sett"), systemImage: "clock.arrow.circlepath") }
            Button { stored = "all" } label: { Label(L("Alle kanaler"), systemImage: "square.grid.2x2") }
            if !pinned.isEmpty {
                Section(L("Dine kategorier")) {
                    ForEach(pinned) { category in
                        Button(category.name) { stored = "k:\(category.id)" }
                    }
                }
            }
            Menu(L("Alle kategorier")) {
                ForEach(model.categories.filter { !pinnedIds.contains($0.id) }) { category in
                    Button(category.name) { stored = "k:\(category.id)" }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(verbatim: "\(title(current)) (\(CountText.of(rows.count)))")
                    .lineLimit(1)
            }
            .font(.system(size: 24, weight: .semibold))
        }
        .accessibilityIdentifier("guide-velger")
    }

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            TimelineView(.everyMinute) { context in
                let start = GuideTime.start(context.date)
                let shown = rows
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 30) {
                        GuideHeader(selection: selection)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        chooser
                    }
                    .frame(height: 124, alignment: .topLeading)
                    .focusSection()
                    ruler(start)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(shown) { channel in
                                GuideRow(channel: channel, start: start, now: context.date, selection: selection) {
                                    play(channel, shown)
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        .hidesScrollIndex()
                    }
                    .scrollIndicators(.never)
                    .safeAreaPadding(.bottom, Theme.bottomFocus)
                    // radene som rulles forbi, skal ikke legge seg over tidslinja og overskriften
                    .clipped()
                }
                .padding(.top, 12)
                .padding(.horizontal, Theme.edge)
                // nærmere sidene og helt ned, som TV-siden
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("guide")
        }
    }

    private func ruler(_ start: Date) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: Self.nameWidth, height: 26)
            ZStack(alignment: .leading) {
                ForEach(GuideTime.marks(start), id: \.self) { mark in
                    Text(verbatim: hhmm(mark))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, CGFloat(GuideTime.minutes(from: start, to: mark)) * Self.perMinute)
                }
            }
            .frame(width: Self.width, alignment: .leading)
        }
    }
}

/// Overskriften: programmet fokus står på, ellers en forklaring.
private struct GuideHeader: View {
    @Environment(AppModel.self) private var model
    let selection: GuideSelection

    var body: some View {
        if let slot = selection.slot, let channel = model.byId[slot.channel],
           let program = model.programs.programs(for: channel).first(where: { $0.start == slot.start }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(nameParts(channel.name).main) · \(hhmm(program.start))–\(hhmm(program.stop))")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.signal)
                Text(program.title)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(1)
                if !program.description.isEmpty {
                    Text(program.description)
                        .font(.system(size: 21))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("TV-guide"))
                    .font(.system(size: 36, weight: .bold))
                Text(L("Velg hva guiden viser oppe til høyre: favorittene, alle kanaler eller en kategori."))
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Én kanal i guiden: logoen og navnet (spill) og programmene bortover.
private struct GuideRow: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let start: Date
    let now: Date
    let selection: GuideSelection
    let play: () -> Void

    var body: some View {
        let programs = model.programs.programs(for: channel)
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    ChannelLogo(channel: channel, textSize: 15)
                        .frame(width: 64, height: 46)
                    Text(nameParts(channel.name).main)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(2)
                }
            }
            .buttonStyle(GuideCellStyle())
            .contextMenu {
                if channel.archiveDays > 0 {
                    Button {
                        model.archiveChannel = channel
                    } label: {
                        Label(L("TV-arkiv"), systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .frame(width: GuideView.nameWidth, height: GuideView.rowHeight)

            ZStack(alignment: .leading) {
                Color.clear
                ForEach(programs, id: \.start) { program in
                    if let span = GuideTime.span(of: program, start: start) {
                        GuideProgramCell(program: program, channelId: channel.id,
                                         live: program.start <= now && now < program.stop,
                                         selection: selection, play: play)
                            .contextMenu {
                                if channel.archiveDays > 0 && program.start <= now {
                                    Button {
                                        Task { model.replay = await model.archivePlay(channel, program) }
                                    } label: {
                                        Label(L("Se fra start"), systemImage: "backward.end")
                                    }
                                }
                            }
                            .frame(width: max(4, CGFloat(span.length) * GuideView.perMinute - 6),
                                   height: GuideView.rowHeight)
                            .padding(.leading, CGFloat(span.from) * GuideView.perMinute)
                    }
                }
                if programs.isEmpty {
                    Text(L("Ingen programinfo"))
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 20)
                }
                Rectangle()
                    .fill(Theme.live)
                    .frame(width: 3, height: GuideView.rowHeight)
                    .padding(.leading, CGFloat(GuideTime.minutes(from: start, to: now)) * GuideView.perMinute)
                    .allowsHitTesting(false)
            }
            .frame(width: GuideView.width, height: GuideView.rowHeight, alignment: .leading)
            .clipped()
        }
        .onAppear { model.programs.want(channel) }
        .onDisappear { model.programs.forget(channel) }
    }
}

/// Et program i guiden. Får det fokus, vises det øverst (bare overskriften tegnes på nytt).
private struct GuideProgramCell: View {
    let program: Program
    let channelId: String
    let live: Bool
    let selection: GuideSelection
    let play: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 3) {
                Text(program.title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: hhmm(program.start))
                    .font(.system(size: 15))
                    .opacity(0.7)
            }
        }
        .buttonStyle(GuideCellStyle(live: live))
        .focused($focused)
        .onChange(of: focused) { _, isFocused in
            let slot = GuideSlot(channel: channelId, start: program.start)
            if isFocused {
                selection.slot = slot
            } else if selection.slot == slot {
                selection.slot = nil
            }
        }
    }
}

/// Flatene i guiden: gul når de har fokus, litt lysere for det som går nå.
struct GuideCellStyle: ButtonStyle {
    var live = false

    func makeBody(configuration: Configuration) -> some View {
        GuideCell(label: configuration.label, live: live)
    }
}

private struct GuideCell<Label: View>: View {
    let label: Label
    let live: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(focused ? Theme.bg : Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(focused ? Theme.signal : (live ? Theme.surface2 : Theme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.line, lineWidth: focused ? 0 : 1)
            )
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
#endif
