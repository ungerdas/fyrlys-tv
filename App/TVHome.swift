#if os(tvOS)
import FyrlysCore
import SwiftUI

/// Til høyre for sidemenyen på Apple TV, som Fyrlys-nettsiden på en stor skjerm: i «Alle kanaler» står «Nå på
/// favorittene» og «Sist sett» som rader øverst, så kommer kanalene, fire i bredden. Fanelinja følger denne lista
/// (`movesTabBar`) og glir bort når kortene rulles, og lista klippes ikke under den, så kortene ruller helt opp (de ble
/// før kuttet under en tom stripe der fanelinja hadde vært). Når den øverste raden får fokus, rulles lista helt opp:
/// ellers ble den stående litt nede når man gikk tilbake dit (overskriften over raden kan ikke få fokus), og
/// fanelinja sto halvveis ute over kanten (eieren 4.11: «litt for høy»).
struct TVChannelPanel: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf
    let title: String
    let channels: [Channel]
    let emptyText: String
    let play: (Channel, [Channel]) -> Void

    /// toppen av lista (dit den øverste raden ruller)
    static let top = "toppen"

    var body: some View {
        ScrollViewReader { proxy in
            let toTop = {
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
            list(toTop)
        }
    }

    private func list(_ toTop: @escaping () -> Void) -> some View {
        let strips = shelf == .all && (!model.favorites.isEmpty || !model.recent.isEmpty)
        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if shelf == .all {
                    rows(toTop)
                }
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(title)
                        .font(.system(size: Metrics.pageTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: CountText.of(channels.count))
                        .font(.system(size: Metrics.pageCount))
                        .foregroundStyle(Theme.muted)
                }
                if channels.isEmpty {
                    Text(emptyText)
                        .font(.system(size: Metrics.pageCount + 4))
                        .foregroundStyle(Theme.muted)
                }
                // den øverste raden med kort (over den står bare tipset, som ikke kan få fokus)
                BigCardGrid(channels: channels, columns: Metrics.bigColumns, play: play,
                            onTopFocus: strips ? nil : toTop)
                    .focusSection()
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .hidesScrollIndex()
            .movesTabBar()
            .id(Self.top)
        }
        .scrollIndicators(.never)
        .safeAreaPadding(.bottom, Theme.bottomFocus)
    }

    /// Favorittene og det du har sett sist (som ikke er favoritter), eller hvordan favorittene samles her. Den første
    /// raden ruller lista helt opp når den får fokus.
    @ViewBuilder
    private func rows(_ toTop: @escaping () -> Void) -> some View {
        let favorites = model.favorites
        let recent = model.recent.filter { !model.isFavorite($0) }
        if favorites.isEmpty && recent.isEmpty {
            TVTip()
        }
        if !favorites.isEmpty {
            TVStrip(title: L("Nå på favorittene"), id: "seksjon-favoritter", clock: true, channels: favorites, play: play,
                    onFocus: toTop)
        }
        if !recent.isEmpty {
            TVStrip(title: L("Sist sett"), id: "seksjon-sist", clock: favorites.isEmpty, channels: recent, play: play,
                    onFocus: favorites.isEmpty ? toTop : nil)
        }
    }
}

/// En rad med kort sidelengs, like brede som kortene i rutenettet under (`Metrics.bigColumns` på bredden av raden).
private struct TVStrip: View {
    let title: String
    let id: String
    let clock: Bool
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void
    /// den øverste raden: et kort fikk fokus
    var onFocus: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TVRowHead(title: title, clock: clock)
                .accessibilityIdentifier(id)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.bigGap) {
                    ForEach(channels) { channel in
                        BigChannelCard(channel: channel, action: { play(channel, channels) }, onFocus: onFocus)
                            .containerRelativeFrame(.horizontal, count: Metrics.bigColumns, spacing: Metrics.bigGap)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            // kortet med fokus blir litt større og har skygge: ikke kutt det, men la ikke kortene som er rullet forbi
            // legge seg over sidemenyen
            .scrollClipDisabled()
            .clipShape(StripClip())
        }
        .focusSection()
    }
}

/// Klipper bare litt utenfor sidene (kanten på kortet med fokus), men god plass over og under (skyggen).
private struct StripClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -10, dy: -60))
    }
}

/// De store kortene i et rutenett: [columns] like brede kolonner (ved siden av sidemenyen), ellers så mange det er
/// plass til (søket).
struct BigCardGrid: View {
    let channels: [Channel]
    var columns: Int?
    let play: (Channel, [Channel]) -> Void
    /// et kort i den øverste raden fikk fokus (bare med et fast antall kolonner)
    var onTopFocus: (() -> Void)?

    private var items: [GridItem] {
        if let columns {
            return Array(repeating: GridItem(.flexible(), spacing: Metrics.bigGap, alignment: .top), count: columns)
        }
        return [GridItem(.adaptive(minimum: Metrics.bigGridMin, maximum: 360), spacing: Metrics.bigGap, alignment: .top)]
    }

    var body: some View {
        let top: Set<String> = onTopFocus == nil || columns == nil ? [] : Set(channels.prefix(columns ?? 0).map(\.id))
        LazyVGrid(columns: items, alignment: .leading, spacing: Metrics.bigGap + 6) {
            ForEach(channels) { channel in
                BigChannelCard(channel: channel, action: { play(channel, channels) },
                               onFocus: top.contains(channel.id) ? onTopFocus : nil)
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

/// Fyrlys-merket og navnet øverst til venstre, på linje med fanelinja (som topplinja på iPhone).
struct TVBrand: View {
    var body: some View {
        HStack(spacing: 14) {
            FyrlysMark(background: false)
                .frame(width: Metrics.brandMark, height: Metrics.brandMark)
            Text(verbatim: "Fyrlys")
                .font(.system(size: Metrics.brandFont, weight: .bold))
                .tracking(-Metrics.brandFont * 0.02)
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fyrlys-merke")
    }
}

/// Første gang (ingen favoritter og ingenting sett): hvordan favorittene samles her.
private struct TVTip: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "star.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.signal)
            // fet første setning (markdown i teksten)
            Text(LocalizedStringKey(L("**Samle favorittene dine her.** Hold inne på en kanal og velg «Legg til i favoritter», så ligger den øverst med det som går nå. I TV-guiden ser du hva som kommer senere.")))
                .font(.system(size: 21))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }
}
#endif
