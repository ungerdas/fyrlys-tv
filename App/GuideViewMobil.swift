#if !os(tvOS)
import FyrlysCore
import Observation
import SwiftUI

/// Et program i guiden som vises med info (trykk på et program som ikke går nå).
struct GuidePick: Identifiable {
    let channel: Channel
    let program: Program
    var id: String { "\(channel.id)@\(program.start.timeIntervalSince1970)" }
}

/// TV-guiden på iPhone og iPad, som på Fyrlys-nettsiden: velg favorittene, alle kanaler eller en kategori, «Til nå», og
/// seks timer fra halvtimen før denne i en ramme der tidene står fast øverst og kanalene fast til venstre, med en rød
/// strek for nå. Trykk på kanalen eller det som går nå for å spille; et annet program gir info med «Se kanalen».
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let play: (Channel, [Channel]) -> Void
    /// hva guiden viser («fav», «recent», «all», «k:<kategori>», eller tom: favorittene, ellers den første av «Dine
    /// kategorier», ellers alle)
    @AppStorage("guide", store: TestSupport.defaults) private var stored = ""
    @State private var picking = false
    @State private var shown = GuideView.page
    @State private var picked: GuidePick?
    /// «Se kanalen» i info-arket: spilles når arket er borte (to ark på en gang avvises)
    @State private var watch: (channel: Channel, list: [Channel])?
    /// den halvtimen som står lengst til venstre (rulles dit når guiden vises, og av «Til nå»)
    @State private var mark: Int?
    @State private var scroll = GuideScroll()

    static let perMinute: CGFloat = 4
    static let rowHeight: CGFloat = 66
    static let headHeight: CGFloat = 42
    static let page = 100
    static var width: CGFloat { CGFloat(GuideTime.totalMinutes) * perMinute }

    /// bred nok til at vanlige kanalnavn brytes mellom ordene, ikke midt i dem (112 som på nettsiden ga «Fjordkanale-n»)
    private var nameWidth: CGFloat { sizeClass == .compact ? 128 : 210 }

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            let selection = choice
            let all = channels(selection)
            let rows = Array(all.prefix(shown))
            VStack(alignment: .leading, spacing: 0) {
                tools(selection)
                TimelineView(.everyMinute) { context in
                    let start = GuideTime.start(context.date)
                    GeometryReader { geo in
                        let content = CGFloat(rows.count) * (Self.rowHeight + 1) + (all.count > rows.count ? 64 : 0)
                        box(rows: rows, total: all.count, start: start, now: context.date, width: geo.size.width)
                            .frame(height: min(geo.size.height, Self.headHeight + 1 + max(content, Self.rowHeight)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.bg)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("guide")
            .onChange(of: stored) { shown = Self.page }
            .sheet(isPresented: $picking) {
                CategoryPicker(chosen: Binding(get: { selection }, set: { if let new = $0 { stored = Self.encode(new) } }),
                               current: selection)
                    .environment(model)
                    .macSheetSize()
            }
            .sheet(item: $picked, onDismiss: {
                model.showPendingReplay()
                if let watch {
                    self.watch = nil
                    play(watch.channel, watch.list)
                }
            }) { pick in
                ProgramInfo(pick: pick) {
                    watch = (pick.channel, rows)
                    picked = nil
                } fromStart: {
                    Task {
                        let replay = await model.archivePlay(pick.channel, pick.program)
                        // arket er lukket imens: ikke spill det senere, når et annet ark lukkes
                        guard picked?.id == pick.id else { return }
                        model.pendingReplay = replay
                        picked = nil
                    }
                }
                .presentationDetents([.medium, .large])
                .macSheetSize(width: 520, height: 460)
            }
            // til nå når guiden vises (startverdien i scrollPosition ble ikke brukt, så guiden sto en halvtime eller
            // mer bakover)
            .task {
                try? await Task.sleep(for: .milliseconds(80))
                if mark == nil { mark = 1 }
            }
        }
    }

    // ── valget ──

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

    private static func encode(_ shelf: Shelf) -> String {
        switch shelf {
        case .favorites: return "fav"
        case .recent: return "recent"
        case .all: return "all"
        case .category(let id): return "k:\(id)"
        }
    }

    private func channels(_ shelf: Shelf) -> [Channel] {
        switch shelf {
        case .favorites: return model.favorites
        case .recent: return model.recent
        case .all: return model.allChannels
        case .category(let id): return model.channels(in: id)
        }
    }

    private func title(_ shelf: Shelf) -> String {
        switch shelf {
        case .favorites: return "★ " + L("Favoritter") + " (\(model.favorites.count))"
        case .recent: return L("Sist sett")
        case .all: return L("Alle kanaler")
        case .category(let id): return model.index.category(id)?.name ?? ""
        }
    }

    /// «TV-guide», hva den viser (trykk for å velge) og «Til nå».
    private func tools(_ selection: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("TV-guide"))
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Button {
                    picking = true
                } label: {
                    HStack(spacing: 8) {
                        Text(title(selection))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guide-velger")
                Button {
                    // via nil, så det rulles også når den står på 1 (men du har rullet bort)
                    mark = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(20))
                        withAnimation(.easeOut(duration: 0.3)) { mark = 1 }
                    }
                } label: {
                    Text(L("Til nå"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("til-naa")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // ── rammen ──

    /// Rammen er [width] bred: kanalene til venstre, og sporene får resten (ellers tar de hele bredden på seks timer, og
    /// alt havnet utenfor skjermen).
    private func box(rows: [Channel], total: Int, start: Date, now: Date, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(verbatim: hhmm(now))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.live)
                    .padding(.horizontal, 14)
                    .frame(width: nameWidth, height: Self.headHeight, alignment: .leading)
                Rectangle().fill(Theme.line).frame(width: 1)
                GuideTimes(scroll: scroll, start: start, now: now)
            }
            .frame(height: Self.headHeight)
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { channel in
                                nameCell(channel, rows)
                            }
                        }
                        .frame(width: nameWidth)
                        Rectangle().fill(Theme.line).frame(width: 1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(rows) { channel in
                                        GuideTrack(channel: channel, start: start, now: now) { program in
                                            if program.start <= now && now < program.stop {
                                                play(channel, rows)
                                            } else {
                                                picked = GuidePick(channel: channel, program: program)
                                            }
                                        }
                                        Rectangle().fill(Theme.line).frame(height: 1)
                                    }
                                }
                                // halvtimene, så «Til nå» kan rulle dit
                                HStack(spacing: 0) {
                                    ForEach(0..<(GuideTime.hours * 2), id: \.self) { i in
                                        Color.clear.frame(width: 30 * Self.perMinute, height: 1).id(i)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(key: GuideOffsetKey.self,
                                                           value: geo.frame(in: .named("guide-x")).minX)
                                }
                            }
                        }
                        .coordinateSpace(name: "guide-x")
                        .scrollPosition(id: $mark, anchor: .leading)
                        .onPreferenceChange(GuideOffsetKey.self) { scroll.x = $0 }
                        .frame(width: max(0, width - nameWidth - 1))
                    }
                    if total > rows.count {
                        Button {
                            shown += Self.page
                        } label: {
                            Text(L("Vis flere kanaler ({n} av {total})",
                                   ["n": CountText.of(rows.count), "total": CountText.of(total)]))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                    if rows.isEmpty {
                        Text(choice == .favorites
                             ? L("Ingen favoritter ennå. Trykk på stjernen på en kanal under TV, eller velg en kategori over.")
                             : L("Ingen kanaler her."))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .refreshable { await model.reload() }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// Kanalen til venstre: trykk for å spille (logoen bare når det er plass, som på nettsiden).
    private func nameCell(_ channel: Channel, _ rows: [Channel]) -> some View {
        VStack(spacing: 0) {
            Button {
                play(channel, rows)
            } label: {
                HStack(spacing: 10) {
                    if nameWidth >= 200 {
                        ChannelLogo(channel: channel, textSize: 11)
                            .frame(width: 52, height: 36)
                    }
                    Text(verbatim: nameParts(channel.name).main)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(width: nameWidth, height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guide-kanal-\(channel.id)")
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        // programinfoen hentes for kanalene som er framme (lista til venstre er lat, sporene er det ikke)
        .onAppear { model.programs.want(channel) }
        .onDisappear { model.programs.forget(channel) }
    }
}

/// Hvor langt sporene er rullet sidelengs, så tidene øverst følger med. Bare tidslinja leser den, så resten av guiden
/// tegnes ikke på nytt mens du ruller.
@Observable
final class GuideScroll {
    var x: CGFloat = 0
}

private struct GuideOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Tidene øverst (hver halvtime) og prikken for nå, flyttet like langt som sporene under.
private struct GuideTimes: View {
    let scroll: GuideScroll
    let start: Date
    let now: Date

    var body: some View {
        let nowX = CGFloat(GuideTime.minutes(from: start, to: now)) * GuideView.perMinute
        ZStack(alignment: .topLeading) {
            ForEach(GuideTime.marks(start), id: \.self) { mark in
                let x = CGFloat(GuideTime.minutes(from: start, to: mark)) * GuideView.perMinute
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.line).frame(width: 1)
                    Text(verbatim: hhmm(mark))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink2)
                        .padding(.leading, 8)
                    Spacer(minLength: 0)
                }
                .frame(width: 30 * GuideView.perMinute, height: GuideView.headHeight)
                .offset(x: x)
            }
            Circle()
                .fill(Theme.live)
                .frame(width: 10, height: 10)
                .offset(x: nowX - 5, y: GuideView.headHeight - 10)
        }
        .frame(width: GuideView.width, height: GuideView.headHeight, alignment: .topLeading)
        .offset(x: scroll.x)
        // minWidth 0: ellers blir rammen like bred som tidslinja (seks timer), og hele guiden ble bredere enn skjermen,
        // med radene utenfor
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

/// Programmene for én kanal bortover, med streken for nå. Eventkanaler og kanaler uten programinfo får en linje tekst.
private struct GuideTrack: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let start: Date
    let now: Date
    let tap: (Program) -> Void

    var body: some View {
        let programs = model.programs.programs(for: channel)
        let parts = nameParts(channel.name)
        ZStack(alignment: .topLeading) {
            Color.clear
            if !parts.sub.isEmpty || !parts.time.isEmpty || !channel.hasEpg {
                empty(!parts.sub.isEmpty ? parts.sub
                      : !parts.time.isEmpty ? L("Starter {time}", ["time": parts.time]) : L("Ingen programinfo"))
            } else if programs.isEmpty {
                if model.programs.isLoaded(channel) { empty(L("Ingen programinfo")) }
            } else {
                let next = programs.first { $0.start > now }?.start
                ForEach(programs, id: \.start) { program in
                    if let span = GuideTime.span(of: program, start: start) {
                        block(program, span: span)
                            // testene: det neste programmet på kanalen
                            .accessibilityIdentifier(program.start == next ? "neste-program-\(channel.id)" : "")
                    }
                }
            }
            Rectangle()
                .fill(Theme.live)
                .frame(width: 2, height: GuideView.rowHeight + 1)
                .offset(x: CGFloat(GuideTime.minutes(from: start, to: now)) * GuideView.perMinute - 1)
                .allowsHitTesting(false)
        }
        .frame(width: GuideView.width, height: GuideView.rowHeight, alignment: .topLeading)
    }

    /// En linje tekst der sporet begynner å synes (ved halvtimen før denne).
    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .frame(height: GuideView.rowHeight)
            .offset(x: 30 * GuideView.perMinute + 14)
    }

    private func block(_ program: Program, span: (from: Double, length: Double)) -> some View {
        let width = max(4, CGFloat(span.length) * GuideView.perMinute - 4)
        let tiny = width < 72
        let live = program.start <= now && now < program.stop
        let past = program.stop <= now
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button {
            tap(program)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !tiny {
                    Text(verbatim: "\(hhmm(program.start))–\(hhmm(program.stop))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, tiny ? 4 : 10)
            .frame(width: width, height: GuideView.rowHeight - 12, alignment: .leading)
            .background(shape.fill(live ? Theme.signal.opacity(0.18) : Theme.surface2))
            .overlay(shape.strokeBorder(live ? Theme.signal.opacity(0.55) : Color.clear, lineWidth: 1))
            .clipShape(shape)
            .opacity(past ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(span.from) * GuideView.perMinute + 2, y: 6)
    }
}

/// Info om et program som ikke går nå, med «Se kanalen».
private struct ProgramInfo: View {
    let pick: GuidePick
    let watch: () -> Void
    let fromStart: () -> Void
    /// påminnelsen er satt
    @State private var reminded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(nameParts(pick.channel.name).main) · \(hhmm(pick.program.start))–\(hhmm(pick.program.stop))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.signal)
            Text(pick.program.title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            if !pick.program.description.isEmpty {
                ScrollView {
                    Text(pick.program.description)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            Button(action: watch) {
                Label(L("Se kanalen"), systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.signalInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.signal))
            }
            .buttonStyle(.plain)
            // har begynt, og kanalen har TV-arkiv
            if pick.channel.archiveDays > 0 && pick.program.start <= Date() {
                Button(action: fromStart) {
                    Label(L("Se fra start"), systemImage: "backward.end.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.signal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.signal))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("se-fra-start")
            }
            // ikke begynt ennå: et varsel før det begynner
            if pick.program.start > Date().addingTimeInterval(30) {
                Button {
                    Task { reminded = await Reminders.toggle(pick.channel, pick.program) }
                } label: {
                    Label(reminded ? L("Påminnelse satt") : L("Minn meg på"),
                          systemImage: reminded ? "bell.fill" : "bell")
                        .font(.headline)
                        .foregroundStyle(Theme.signal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.signal))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("paminnelse")
                .task { reminded = await Reminders.isSet(pick.channel, pick.program) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }
}
#endif
