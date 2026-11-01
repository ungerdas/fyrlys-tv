#if os(tvOS)
import AVFoundation
import AVKit
import FyrlysCore
import SwiftUI

/// Spilleren i fullskjerm. Menyknappen på fjernkontrollen lukker den.
struct PlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerModel?
    let request: PlayRequest

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                if let error = model.error {
                    PlayerError(model: model, message: error) { dismiss() }
                } else {
                    PlayerController(model: model, channelId: model.channel.id, favorite: model.isFavorite,
                                     startOver: model.canStartOver)
                        .ignoresSafeArea()
                }
            }
        }
        // for UI-testene: om spilleren eller feilen står framme (kanalkortene bak finnes i elementtreet også da). Én id
        // for hele spilleren: en id på feilen inne i en beholder med egen id forsvant.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model?.error == nil ? "spiller" : "spiller-feil")
        .onAppear {
            guard model == nil else { return }
            let player = PlayerModel(app: app, channel: request.channel, list: request.list)
            model = player
            player.open(request.channel)
        }
        .onDisappear { model?.stop() }
        .onChange(of: programs) { model?.refreshMetadata() }
        .onChange(of: model?.closeRequested ?? false) { _, close in
            if close { dismiss() }
        }
    }

    private var programs: [Program] {
        guard let model else { return [] }
        return app.programs.programs(for: model.channel)
    }
}

/// Når kanalen ikke kan spilles.
private struct PlayerError: View {
    let model: PlayerModel
    let message: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            FyrlysMark()
                .frame(width: 120)
            Text(nameParts(model.channel.name).main)
                .font(.system(size: 40, weight: .bold))
            Text(L("Kanalen kunne ikke spilles"))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.live)
            Text(message)
                .font(.system(size: 28))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1200)
            HStack(spacing: 40) {
                Button(L("Prøv igjen")) { model.retry() }
                Button(L("Neste kanal")) { model.step(1) }
                Button(L("Lukk"), action: close)
            }
        }
    }
}

/// AVPlayerViewController med neste/forrige kanal og favoritt i kontrollene, kanallista som et eget felt når man
/// sveiper ned, og kanalbytte med opp og ned på fjernkontrollen (AVKits kanalbytte, med forhåndsvisning av kanalen).
struct PlayerController: UIViewControllerRepresentable {
    let model: PlayerModel
    /// (bare så SwiftUI oppdaterer knappene når kanalen eller favoritten endres)
    let channelId: String
    let favorite: Bool
    /// «Se fra start» i kontrollene (kanalen har arkiv, og det er kjent hva som går nå)
    let startOver: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        controller.delegate = context.coordinator
        controller.customInfoViewControllers = [context.coordinator.channels]
        updateButtons(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        updateButtons(controller)
    }

    private func updateButtons(_ controller: AVPlayerViewController) {
        let model = model
        let favorite = favorite
        var items: [UIMenuElement] = []
        if model.canStartOver {
            items.append(UIAction(title: L("Se fra start"), image: UIImage(systemName: "backward.end")) { _ in
                MainActor.assumeIsolated { model.startOver() }
            })
        }
        controller.transportBarCustomMenuItems = items + [
            UIAction(title: L("Forrige kanal"), image: UIImage(systemName: "chevron.down")) { _ in
                MainActor.assumeIsolated { model.step(-1) }
            },
            UIAction(title: L("Neste kanal"), image: UIImage(systemName: "chevron.up")) { _ in
                MainActor.assumeIsolated { model.step(1) }
            },
            UIAction(title: favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"),
                     image: UIImage(systemName: favorite ? "star.fill" : "star")) { _ in
                MainActor.assumeIsolated { model.toggleFavorite() }
            },
        ]
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let model: PlayerModel
        let channels: UIHostingController<ChannelStrip>

        init(model: PlayerModel) {
            self.model = model
            channels = UIHostingController(rootView: ChannelStrip(model: model))
            channels.title = L("Kanaler")
            channels.preferredContentSize = CGSize(width: 1920, height: 330)
            super.init()
        }

        // kanalbytte som på vanlig TV: opp gir neste kanal, ned forrige (når kontrollene er skjult)
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  skipToNextChannel completion: @escaping (Bool) -> Void) {
            model.step(1)
            completion(true)
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  skipToPreviousChannel completion: @escaping (Bool) -> Void) {
            model.step(-1)
            completion(true)
        }

        func nextChannelInterstitialViewController(for playerViewController: AVPlayerViewController)
            -> UIViewController {
            preview(1)
        }

        func previousChannelInterstitialViewController(for playerViewController: AVPlayerViewController)
            -> UIViewController {
            preview(-1)
        }

        /// Det som vises mens man bytter: kanalen og programmet som går nå.
        private func preview(_ delta: Int) -> UIViewController {
            let controller = UIHostingController(rootView: ChannelPreview(model: model, channel: model.neighbor(delta)))
            controller.view.backgroundColor = .black
            return controller
        }
    }
}

/// Forhåndsvisningen ved kanalbytte: logoen, kanalen og programmet som går nå.
private struct ChannelPreview: View {
    let model: PlayerModel
    let channel: Channel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let channel {
                VStack(spacing: 28) {
                    ChannelTile(channel: channel)
                        .frame(width: 480, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text(nameParts(channel.name).main)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let now = model.nowPlaying(channel) {
                        Text(verbatim: "\(hhmm(now.start))–\(hhmm(now.stop))  \(now.title)")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 120)
            }
        }
    }
}

/// Kanalene i lista bortover (feltet «Kanaler» i spilleren).
struct ChannelStrip: View {
    let model: PlayerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 36) {
                    ForEach(model.list) { channel in
                        Button {
                            model.open(channel)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ChannelTile(channel: channel, compact: true)
                                    .frame(width: 280, height: 158)
                                Text(nameParts(channel.name).main)
                                    .font(.system(size: 22, weight: channel.id == model.channel.id ? .bold : .regular))
                                    .foregroundStyle(channel.id == model.channel.id ? Theme.signal : Theme.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(width: 280, alignment: .leading)
                            }
                            .background(Theme.surface)
                        }
                        .buttonStyle(.card)
                        .id(channel.id)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
            }
            .onAppear { proxy.scrollTo(model.channel.id, anchor: .center) }
        }
    }
}
#endif
