#if os(iOS)
import AVKit
import FyrlysCore
import SwiftUI

/// Spilleren på iPhone og iPad, som spilleren i Fyrlys på Windows i et smalt vindu: bildet øverst (med bilde-i-bilde
/// og AirPlay i kontrollene), kanalen og programmet, forrige/neste/favoritt, og kanallista under. Liggende iPhone:
/// bare bildet. iPad på tvers: lista ved siden av bildet.
struct PlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vertical
    @State private var model: PlayerModel?
    let request: PlayRequest

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let model {
                    if vertical == .compact {
                        // liggende iPhone: bare bildet, over hele skjermen
                        screen(model)
                            .ignoresSafeArea()
                    } else if geo.size.width > geo.size.height && geo.size.width >= 900 {
                        HStack(spacing: 0) {
                            screen(model)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            PlayerPanel(model: model) { dismiss() }
                                .frame(width: 380)
                        }
                    } else {
                        VStack(spacing: 0) {
                            screen(model)
                                .aspectRatio(16 / 9, contentMode: .fit)
                            PlayerPanel(model: model) { dismiss() }
                        }
                    }
                }
            }
        }
        .statusBarHidden(vertical == .compact)
        .onAppear {
            guard model == nil else { return }
            let player = PlayerModel(app: app, channel: request.channel, list: request.list)
            model = player
            player.open(request.channel)
        }
        .onDisappear { model?.stop() }
        .onChange(of: programs) { model?.refreshMetadata() }
    }

    private var programs: [Program] {
        guard let model else { return [] }
        return app.programs.programs(for: model.channel)
    }

    /// Bildet, og feilen over det når kanalen ikke kan spilles.
    private func screen(_ model: PlayerModel) -> some View {
        ZStack {
            Color.black
            VideoSurface(player: model.player)
            if let error = model.error {
                PlayerErrorMobil(model: model, message: error) { dismiss() }
            }
        }
    }
}

/// AVPlayerViewController i siden (ikke fullskjerm), med bilde-i-bilde.
private struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

/// Kanalen og programmet, knappene og kanallista under bildet.
private struct PlayerPanel: View {
    @Environment(AppModel.self) private var app
    let model: PlayerModel
    let close: () -> Void

    var body: some View {
        let channel = model.channel
        let parts = nameParts(channel.name)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ChannelLogo(channel: channel, textSize: 14)
                    .frame(width: 56, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !parts.time.isEmpty {
                            Text(verbatim: parts.time)
                                .foregroundStyle(Theme.signal)
                        }
                        Text(verbatim: parts.main)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    .font(.headline)
                    TimelineView(.everyMinute) { context in
                        let pair = nowAndNext(app.programs.programs(for: channel), at: context.date)
                        if let now = pair.now {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: "\(hhmm(now.start))–\(hhmm(now.stop))  \(now.title)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                                ProgressBar(value: now.progress(at: context.date))
                                    .frame(maxWidth: 280)
                                if let next = pair.next {
                                    Text(L("Etterpå {time}: {title}", ["time": hhmm(next.start), "title": next.title]))
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                }
                            }
                        } else if !parts.sub.isEmpty {
                            Text(verbatim: parts.sub)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surface2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lukk-spiller")
                .accessibilityLabel(L("Lukk"))
            }
            .padding(16)
            HStack(spacing: 10) {
                panelButton(L("Forrige"), "backward.fill", id: "forrige-kanal") { model.step(-1) }
                panelButton(L("Neste"), "forward.fill", id: "neste-kanal") { model.step(1) }
                panelButton(L("Favoritt"), model.isFavorite ? "star.fill" : "star", id: "spiller-favoritt",
                            highlighted: model.isFavorite) { model.toggleFavorite() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
            ChannelList(model: model)
        }
        .background(Theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spiller")
    }

    private func panelButton(_ title: String, _ icon: String, id: String, highlighted: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Theme.signal : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Kanallista i spilleren (lista du kom fra); trykk for å bytte kanal.
private struct ChannelList: View {
    let model: PlayerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.list) { channel in
                        Button {
                            model.open(channel)
                        } label: {
                            ChannelRow(channel: channel, current: channel.id == model.channel.id)
                        }
                        .buttonStyle(.plain)
                        .id(channel.id)
                    }
                }
                .padding(12)
            }
            .onAppear { proxy.scrollTo(model.channel.id, anchor: .center) }
        }
    }
}

/// En kanal i lista: logoen, navnet, kampen eller det som går nå, og nummeret.
private struct ChannelRow: View {
    @Environment(AppModel.self) private var app
    let channel: Channel
    let current: Bool

    var body: some View {
        let parts = nameParts(channel.name)
        HStack(spacing: 10) {
            ChannelLogo(channel: channel, textSize: 12)
                .frame(width: 48, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !parts.time.isEmpty {
                        Text(verbatim: parts.time)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.signal)
                    }
                    Text(verbatim: parts.main)
                        .fontWeight(.semibold)
                        .foregroundStyle(current ? Theme.signal : Theme.ink)
                        .lineLimit(1)
                }
                .font(.system(size: 15))
                if !parts.sub.isEmpty {
                    Text(verbatim: parts.sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                } else if channel.wantsEpg {
                    NowPlaying(channel: channel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let number = channel.number {
                Text(verbatim: "\(number)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(current ? Theme.surface2 : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(current ? Theme.signal.opacity(0.7) : Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onAppear { app.programs.want(channel) }
        .onDisappear { app.programs.forget(channel) }
    }
}

/// Når kanalen ikke kan spilles: forklaringen og prøv igjen, neste kanal eller lukk.
private struct PlayerErrorMobil: View {
    let model: PlayerModel
    let message: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(L("Kanalen kunne ikke spilles"))
                .font(.headline)
                .foregroundStyle(Theme.live)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(L("Prøv igjen")) { model.retry() }
                Button(L("Neste kanal")) { model.step(1) }
                Button(L("Lukk"), action: close)
            }
            .buttonStyle(.bordered)
            .tint(Theme.signal)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spiller-feil")
    }
}
#endif
