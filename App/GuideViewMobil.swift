#if os(iOS)
import FyrlysCore
import SwiftUI

/// Et program i guiden som vises med info (trykk på et program som ikke går nå).
struct GuidePick: Identifiable {
    let channel: Channel
    let program: Program
    var id: String { "\(channel.id)@\(program.start.timeIntervalSince1970)" }
}

/// TV-guiden på iPhone og iPad, som i Fyrlys på Windows: seks timer fra halvtimen før denne, favorittkanalene
/// (ellers de første kanalene, med «Dine kategorier» først), kanalene til venstre og programmene bortover (rull
/// sidelengs), med en rød strek for nå. Trykk på kanalen eller det som går nå for å spille; et annet program gir info
/// med «Se kanalen».
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let play: (Channel, [Channel]) -> Void
    @State private var picked: GuidePick?

    static let perMinute: CGFloat = 4
    static let rowHeight: CGFloat = 58
    static var width: CGFloat { CGFloat(GuideTime.totalMinutes) * perMinute }

    private var nameWidth: CGFloat { sizeClass == .compact ? 120 : 230 }

    private var rows: [Channel] {
        let favorites = model.favorites
        return favorites.isEmpty ? Array(model.allChannels.prefix(60)) : favorites
    }

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            TimelineView(.everyMinute) { context in
                let start = GuideTime.start(context.date)
                let shown = rows
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("TV-guide"))
                            .font(.system(size: 24, weight: .bold))
                        Text(L("Viser favorittene dine. Har du ingen, vises de første kanalene."))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 6) {
                            VStack(spacing: 6) {
                                Color.clear.frame(height: 22)
                                ForEach(shown) { channel in
                                    nameCell(channel, shown)
                                }
                            }
                            .frame(width: nameWidth)
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ruler(start)
                                    ForEach(shown) { channel in
                                        GuideRowMobil(channel: channel, start: start, now: context.date) { program in
                                            if program.start <= context.date && context.date < program.stop {
                                                play(channel, shown)
                                            } else {
                                                picked = GuidePick(channel: channel, program: program)
                                            }
                                        }
                                    }
                                }
                                .padding(.trailing, 12)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.bottom, 16)
                    }
                    .refreshable { await model.reload() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("guide")
            .sheet(item: $picked) { pick in
                ProgramInfo(pick: pick) {
                    picked = nil
                    play(pick.channel, rows)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func nameCell(_ channel: Channel, _ shown: [Channel]) -> some View {
        Button {
            play(channel, shown)
        } label: {
            HStack(spacing: 8) {
                ChannelLogo(channel: channel, textSize: 12)
                    .frame(width: 44, height: 33)
                Text(nameParts(channel.name).main)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ruler(_ start: Date) -> some View {
        ZStack(alignment: .leading) {
            ForEach(GuideTime.marks(start), id: \.self) { mark in
                Text(verbatim: hhmm(mark))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, CGFloat(GuideTime.minutes(from: start, to: mark)) * Self.perMinute)
            }
        }
        .frame(width: Self.width, height: 22, alignment: .leading)
    }
}

/// Programmene for én kanal bortover.
private struct GuideRowMobil: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let start: Date
    let now: Date
    let tap: (Program) -> Void

    var body: some View {
        let programs = model.programs.programs(for: channel)
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(programs, id: \.start) { program in
                if let span = GuideTime.span(of: program, start: start) {
                    let live = program.start <= now && now < program.stop
                    Button {
                        tap(program)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(verbatim: hhmm(program.start))
                                .font(.system(size: 11))
                                .opacity(0.7)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .frame(width: max(4, CGFloat(span.length) * GuideView.perMinute - 4),
                               height: GuideView.rowHeight, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(live ? Theme.surface2 : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(live ? Theme.signal.opacity(0.6) : Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(span.from) * GuideView.perMinute)
                }
            }
            if programs.isEmpty {
                Text(L("Ingen programinfo"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 12)
            }
            Rectangle()
                .fill(Theme.live)
                .frame(width: 2, height: GuideView.rowHeight)
                .padding(.leading, CGFloat(GuideTime.minutes(from: start, to: now)) * GuideView.perMinute)
                .allowsHitTesting(false)
        }
        .frame(width: GuideView.width, height: GuideView.rowHeight, alignment: .leading)
        .clipped()
        .onAppear { model.programs.want(channel) }
        .onDisappear { model.programs.forget(channel) }
    }
}

/// Info om et program som ikke går nå, med «Se kanalen».
private struct ProgramInfo: View {
    let pick: GuidePick
    let watch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(nameParts(pick.channel.name).main) · \(hhmm(pick.program.start))–\(hhmm(pick.program.stop))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.signal)
            Text(pick.program.title)
                .font(.title2.bold())
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
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.signal))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }
}
#endif
