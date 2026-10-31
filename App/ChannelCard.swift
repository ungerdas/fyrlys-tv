import FyrlysCore
import SwiftUI

/// Et kanalkort: logoen på kanalens farge, navnet, det som går nå med en strek for hvor langt det har kommet. Hold
/// inne for å legge til eller fjerne favoritt.
struct ChannelCard: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let action: () -> Void

    var body: some View {
        let favorite = model.isFavorite(channel)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ChannelTile(channel: channel, favorite: favorite)
                    .aspectRatio(16 / 9, contentMode: .fit)
                ProgramLines(channel: channel)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.surface)
        }
        .buttonStyle(.card)
        .contextMenu {
            Button {
                model.toggleFavorite(channel)
            } label: {
                Label(favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"),
                      systemImage: favorite ? "star.slash" : "star")
            }
        }
        .accessibilityIdentifier("kanal-\(channel.id)")
        .onAppear { model.programs.want(channel) }
        .onDisappear { model.programs.forget(channel) }
    }
}

/// Navnet og det som går nå (oppdateres hvert halve minutt).
struct ProgramLines: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        let parts = nameParts(channel.name)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let pair = nowAndNext(model.programs.programs(for: channel), at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(parts.main)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let now = pair.now {
                    Text(now.title)
                        .font(.system(size: 21))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    ProgressBar(value: now.progress(at: context.date))
                } else {
                    Text(parts.sub.isEmpty ? L("Ingen programinfo") : parts.sub)
                        .font(.system(size: 21))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    ProgressBar(value: 0).opacity(0)
                }
            }
        }
    }
}

/// En tynn strek for hvor langt programmet har kommet.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(Theme.line)
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.signal)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                }
            }
    }
}

/// Rutenettet med kanalkort (TV-fanen og søket).
struct ChannelGrid: View {
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 296), spacing: 40)], spacing: 46) {
            ForEach(channels) { channel in
                ChannelCard(channel: channel) { play(channel, channels) }
            }
        }
    }
}
