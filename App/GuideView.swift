import FyrlysCore
import SwiftUI

/// Et program i guiden (kanal og start), det fokus står på.
struct GuideSlot: Hashable {
    let channel: String
    let start: Date
}

/// TV-guiden: seks timer fra halvtimen før denne halvtimen, favorittkanalene (ellers de første kanalene), med en
/// rød strek for nå. Øverst står programmet du står på.
struct GuideView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    @FocusState private var focus: GuideSlot?

    static let perMinute: CGFloat = 3.8
    static let nameWidth: CGFloat = 330
    static let rowHeight: CGFloat = 78
    static var width: CGFloat { CGFloat(GuideTime.totalMinutes) * perMinute }

    private var rows: [Channel] {
        let favorites = model.favorites
        return favorites.isEmpty ? Array(model.channels.prefix(60)) : favorites
    }

    var body: some View {
        if model.channels.isEmpty {
            ListsStatus()
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let start = GuideTime.start(context.date)
                let shown = rows
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .frame(height: 170, alignment: .topLeading)
                    ruler(start)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(shown) { channel in
                                GuideRow(channel: channel, start: start, now: context.date, focus: $focus) {
                                    play(channel, shown)
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("guide")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let slot = focus, let channel = model.byId[slot.channel],
           let program = model.programs.programs(for: channel).first(where: { $0.start == slot.start }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "\(nameParts(channel.name).main) · \(hhmm(program.start))–\(hhmm(program.stop))")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.signal)
                Text(program.title)
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(1)
                if !program.description.isEmpty {
                    Text(program.description)
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("TV-guide"))
                    .font(.system(size: 42, weight: .bold))
                Text(L("Viser favorittene dine. Har du ingen, vises de første kanalene."))
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func ruler(_ start: Date) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: Self.nameWidth, height: 30)
            ZStack(alignment: .leading) {
                ForEach(GuideTime.marks(start), id: \.self) { mark in
                    Text(verbatim: hhmm(mark))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, CGFloat(GuideTime.minutes(from: start, to: mark)) * Self.perMinute)
                }
            }
            .frame(width: Self.width, alignment: .leading)
        }
    }
}

/// Én kanal i guiden: navnet (spill) og programmene bortover.
private struct GuideRow: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let start: Date
    let now: Date
    let focus: FocusState<GuideSlot?>.Binding
    let play: () -> Void

    var body: some View {
        let programs = model.programs.programs(for: channel)
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 14) {
                    ChannelTile(channel: channel, compact: true)
                        .frame(width: 96, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(nameParts(channel.name).main)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(2)
                }
            }
            .buttonStyle(GuideCellStyle())
            .frame(width: GuideView.nameWidth, height: GuideView.rowHeight)

            ZStack(alignment: .leading) {
                Color.clear
                ForEach(programs, id: \.start) { program in
                    if let span = GuideTime.span(of: program, start: start) {
                        let live = program.start <= now && now < program.stop
                        Button(action: play) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(program.title)
                                    .font(.system(size: 21, weight: .semibold))
                                    .lineLimit(1)
                                Text(verbatim: hhmm(program.start))
                                    .font(.system(size: 17))
                                    .opacity(0.7)
                            }
                        }
                        .buttonStyle(GuideCellStyle(live: live))
                        .frame(width: max(4, CGFloat(span.length) * GuideView.perMinute - 6),
                               height: GuideView.rowHeight)
                        .focused(focus, equals: GuideSlot(channel: channel.id, start: program.start))
                        .padding(.leading, CGFloat(span.from) * GuideView.perMinute)
                    }
                }
                if programs.isEmpty {
                    Text(L("Ingen programinfo"))
                        .font(.system(size: 21))
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
            .padding(.horizontal, 12)
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
