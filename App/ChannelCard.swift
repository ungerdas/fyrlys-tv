import FyrlysCore
import SwiftUI

/// Et kanalkort som i Fyrlys på Windows: logoen, navnet (eventkanaler med klokkeslettet i gult), kampen eller det som
/// går nå med en strek for hvor langt det har kommet, kanalnummeret og stjernen. Hold inne for å legge til eller fjerne
/// favoritt; på iPhone og iPad kan du også trykke på stjernen.
struct ChannelCard: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let favorite = model.isFavorite(channel)
        card(favorite)
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

    #if os(tvOS)
    /// Hele kortet er én knapp som får fokus.
    private func card(_ favorite: Bool) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                details
                Star(favorite: favorite, channelId: channel.id)
            }
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .frame(height: Metrics.cardHeight)
        }
        .buttonStyle(CardStyle())
        .focused($focused)
        // over naboene, så skyggen og kanten ikke havner under dem
        .zIndex(focused ? 1 : 0)
    }
    #else
    /// Trykk på kortet spiller kanalen, trykk på stjernen legger den til eller fjerner den fra favorittene.
    private func card(_ favorite: Bool) -> some View {
        HStack(spacing: 6) {
            Button(action: action) {
                details
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                model.toggleFavorite(channel)
            } label: {
                Star(favorite: favorite, channelId: channel.id)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stjerne-kanal-\(channel.id)")
            .accessibilityLabel(favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: Metrics.cardHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        // ett element med de to knappene i, så «kanal-…» ikke skriver over id-en til stjerneknappen
        .accessibilityElement(children: .contain)
    }
    #endif

    /// Logoen, navnet, kampen eller det som går nå, og nummeret.
    private var details: some View {
        let parts = nameParts(channel.name)
        return HStack(spacing: 12) {
            ChannelLogo(channel: channel)
                .frame(width: Metrics.logo.width, height: Metrics.logo.height)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if !parts.time.isEmpty {
                        Text(verbatim: parts.time)
                            .font(.system(size: Metrics.cardTitle, weight: .bold))
                            .foregroundStyle(Theme.signal)
                            .fixedSize()
                    }
                    Text(verbatim: parts.main)
                        .font(.system(size: Metrics.cardTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                if !parts.sub.isEmpty {
                    Text(verbatim: parts.sub)
                        .font(.system(size: Metrics.cardSub))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                } else if channel.wantsEpg {
                    NowPlaying(channel: channel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let number = channel.number {
                Text(verbatim: "\(number)")
                    .font(.system(size: Metrics.cardSub))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
        }
    }
}

/// Stjernen på kortet: gul når kanalen er favoritt.
private struct Star: View {
    let favorite: Bool
    let channelId: String

    var body: some View {
        Image(systemName: favorite ? "star.fill" : "star")
            .font(.system(size: Metrics.cardTitle, weight: favorite ? .semibold : .regular))
            .foregroundStyle(favorite ? Theme.signal : Theme.muted)
            .accessibilityIdentifier(favorite ? "favoritt-\(channelId)" : "ikke-favoritt-\(channelId)")
    }
}

/// Det som går nå, med en strek for hvor langt det har kommet (oppdateres hvert minutt, alle kortene samtidig).
struct NowPlaying: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let now = nowAndNext(model.programs.programs(for: channel), at: context.date).now {
                VStack(alignment: .leading, spacing: Metrics.cardSub * 0.4) {
                    Text(now.title)
                        .font(.system(size: Metrics.cardSub))
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
    var textSize: CGFloat = Metrics.logoText

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
                .padding(textSize * 0.3)
            }
    }
}

/// Kortene på Apple TV: mørk flate med tynn kant; med fokus lyseblå kant, litt større og med skygge (som Fyrlys på
/// Windows).
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
            .frame(height: Metrics.cardSub * 0.24)
            .overlay(alignment: .leading) {
                // skalert i stedet for GeometryReader, som koster i hvert kort i et rutenett
                Capsule()
                    .fill(Theme.signal)
                    .scaleEffect(x: max(clamped, 0.001), y: 1, anchor: .leading)
                    .opacity(clamped > 0 ? 1 : 0)
            }
    }
}

/// Rutenettet med kanalkort (TV-fanen og søket): så mange kolonner det er plass til; fire ved siden av sidemenyen på
/// Apple TV, én på iPhone.
struct ChannelGrid: View {
    let channels: [Channel]
    let play: (Channel, [Channel]) -> Void

    static let columns = [GridItem(.adaptive(minimum: Metrics.gridMin, maximum: 480), spacing: Metrics.gridSpacing)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: Metrics.gridSpacing) {
            ForEach(channels) { channel in
                ChannelCard(channel: channel) { play(channel, channels) }
            }
        }
    }
}
