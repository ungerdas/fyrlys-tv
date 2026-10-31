import FyrlysCore
import SwiftUI

/// Et kanalkort som i Fyrlys på Windows: logoen, navnet (eventkanaler med klokkeslettet i gult), kampen eller det som
/// går nå med en strek for hvor langt det har kommet, kanalnummeret og stjernen. Hold inne for å legge til eller fjerne
/// favoritt.
struct ChannelCard: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let action: () -> Void
    @FocusState private var focused: Bool

    static let height: CGFloat = 96

    var body: some View {
        let favorite = model.isFavorite(channel)
        let parts = nameParts(channel.name)
        Button(action: action) {
            HStack(spacing: 14) {
                ChannelLogo(channel: channel)
                    .frame(width: 84, height: 63)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if !parts.time.isEmpty {
                            Text(verbatim: parts.time)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Theme.signal)
                                .fixedSize()
                        }
                        Text(verbatim: parts.main)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    if !parts.sub.isEmpty {
                        Text(verbatim: parts.sub)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    } else if channel.wantsEpg {
                        NowPlaying(channel: channel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let number = channel.number {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 21, weight: favorite ? .semibold : .regular))
                    .foregroundStyle(favorite ? Theme.signal : Theme.muted)
                    .accessibilityIdentifier(favorite ? "favoritt-\(channel.id)" : "ikke-favoritt-\(channel.id)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .frame(height: Self.height)
        }
        .buttonStyle(CardStyle())
        .focused($focused)
        // over naboene, så skyggen og kanten ikke havner under dem
        .zIndex(focused ? 1 : 0)
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

/// Det som går nå, med en strek for hvor langt det har kommet (oppdateres hvert minutt, alle kortene samtidig).
struct NowPlaying: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let now = nowAndNext(model.programs.programs(for: channel), at: context.date).now {
                VStack(alignment: .leading, spacing: 7) {
                    Text(now.title)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    ProgressBar(value: now.progress(at: context.date))
                }
            }
        }
    }
}

/// Logoen fra leverandøren på en mørk flate, eller de tre første tegnene i navnet (som i Fyrlys på Windows).
struct ChannelLogo: View {
    let channel: Channel
    var textSize: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.logoBg)
            .overlay {
                RemoteImage(url: channel.logo.flatMap { URL(string: $0) }) {
                    Text(verbatim: logoText(channel.name))
                        .font(.system(size: textSize, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(6)
            }
    }
}

/// Kortene: mørk flate med tynn kant; med fokus lyseblå kant, litt større og med skygge (som Fyrlys på Windows).
struct CardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct CardBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        label
            .background(shape.fill(focused ? Theme.surface2 : Theme.surface))
            .overlay(shape.strokeBorder(focused ? Theme.focus : Theme.line, lineWidth: focused ? 3 : 1))
            .scaleEffect(focused ? (pressed ? 1.0 : 1.05) : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 18 : 0, y: focused ? 10 : 0)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// En tynn strek for hvor langt programmet har kommet.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        let clamped = min(1, max(0, value))
        Capsule()
            .fill(Theme.line)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                // skalert i stedet for GeometryReader, som koster i hvert kort i et rutenett
                Capsule()
                    .fill(Theme.signal)
                    .scaleEffect(x: max(clamped, 0.001), y: 1, anchor: .leading)
                    .opacity(clamped > 0 ? 1 : 0)
            }
    }
}

/// Rutenettet med kanalkort (TV-fanen og søket): så mange kolonner det er plass til, fire ved siden av sidemenyen.
struct ChannelGrid: View {
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void

    static let columns = [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 18)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 18) {
            ForEach(channels) { channel in
                ChannelCard(channel: channel) { play(channel, channels) }
            }
        }
    }
}
