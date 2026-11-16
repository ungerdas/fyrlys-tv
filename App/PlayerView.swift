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
                } else if let vlc = model.vlc {
                    // MPEG-TS med VLC: leverandøren har ikke HLS, eller Apples avspiller kunne ikke spille kanalen
                    LiveVLCScreen(model: model, vlc: vlc) { dismiss() }
                        .id(ObjectIdentifier(vlc))
                } else {
                    let format = model.pictureFormat
                    PlayerController(model: model, channelId: model.channel.id, favorite: model.isFavorite,
                                     startOver: model.canStartOver, format: format)
                        .modifier(ForcedAspect(ratio: format.aspectRatio))
                        .ignoresSafeArea()
                }
            }
        }
        // for UI-testene: om spilleren eller feilen står framme (kanalkortene bak finnes i elementtreet også da). Én id
        // for hele spilleren: en id på feilen inne i en beholder med egen id forsvant.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model?.error == nil ? "spiller" : "spiller-feil")
        // UI-testene: adressene som er prøvd
        .accessibilityValue(TestSupport.isActive ? Text(verbatim: model?.tried.joined(separator: " ") ?? "") : Text(""))
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

/// Direktesendingen med VLC (Apple TV): bildet over hele skjermen, kanalen og programmet nederst en stund etter hvert
/// bytte. Opp og ned bytter kanal, spill/pause = pause, Menu lukker. Et trykk på bildet gir valgene under infolinja,
/// som i Apples avspiller: kanallista, favoritt, lyd, undertekster, bildeformat, strøminfo, se fra start, TV-arkivet og
/// multiview (Menu eller opp tar dem bort igjen).
private struct LiveVLCScreen: View {
    @Environment(AppModel.self) private var app
    let model: PlayerModel
    let vlc: VLCEngine
    let close: () -> Void

    private enum Field: Hashable {
        case screen, channels, favorite, audio, subtitles, format, info, startOver, archive, multiview
    }

    /// det som vises over knappene
    private enum Shelf { case channels, info }

    @State private var info = true
    /// valgene (knappene) står framme
    @State private var options = false
    @State private var shelf: Shelf?
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focus: Field?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VLCSurface(engine: vlc)
                .ignoresSafeArea()
            Button {
                openOptions()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(BareButtonStyle())
            .focused($focus, equals: .screen)
            .disabled(options)
            .ignoresSafeArea()
            .accessibilityIdentifier(vlc.started ? "live-vlc" : "live-vlc-venter")
            if !vlc.started {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if info || options || !vlc.isPlaying {
                VStack(alignment: .leading, spacing: 0) {
                    if options, let shelf {
                        shelfView(shelf)
                            .transition(.opacity)
                    }
                    infoBar
                    if options {
                        optionRow
                            .transition(.opacity)
                    }
                }
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea())
                .transition(.opacity)
            }
        }
        .defaultFocus($focus, .screen)
        .onAppear {
            focus = .screen
            show()
        }
        .onChange(of: model.channel.id) {
            closeOptions()
            show()
        }
        .onMoveCommand { direction in
            if options {
                // opp fra knappene: bort med valgene (ikke når kanallista står over: dit går fokus)
                if direction == .up, focus != nil, shelf != .channels { closeOptions() }
                return
            }
            switch direction {
            case .up: model.step(-1)
            case .down: model.step(1)
            default: show()
            }
        }
        .onPlayPauseCommand {
            vlc.togglePause()
            show()
        }
        .onExitCommand {
            if options, shelf == .channels, focus == nil {
                // fra kanallista: tilbake til knappene
                withAnimation { shelf = nil }
                focus = .channels
            } else if options {
                closeOptions()
            } else {
                close()
            }
        }
    }

    private var infoBar: some View {
        let channel = model.channel
        return HStack(spacing: 24) {
            ChannelLogo(channel: channel)
                .frame(width: 150, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: nameParts(channel.name).main)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                if let now = nowAndNext(app.programs.programs(for: channel), at: Date()).now {
                    Text(verbatim: "\(hhmm(now.start))–\(hhmm(now.stop))  \(now.title)")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }
                if !options {
                    Text(L("Opp og ned bytter kanal  ·  trykk for flere valg"))
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
            if !vlc.isPlaying && vlc.started {
                Image(systemName: "pause.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 36)
        .padding(.bottom, options ? 18 : 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    /// Valgene: én knapp per valg, i samme rekkefølge som i Apples avspiller der det finnes.
    private var optionRow: some View {
        HStack(spacing: 22) {
            Button {
                withAnimation { shelf = shelf == .channels ? nil : .channels }
            } label: {
                Label(L("Kanaler"), systemImage: "list.bullet")
            }
            .focused($focus, equals: .channels)
            .accessibilityIdentifier("live-kanaler")
            Button {
                model.toggleFavorite()
            } label: {
                Label(model.isFavorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"),
                      systemImage: model.isFavorite ? "star.fill" : "star")
            }
            .focused($focus, equals: .favorite)
            .accessibilityIdentifier("live-favoritt")
            if vlc.hasAudioChoice {
                VLCAudioMenu(engine: vlc, id: "live-lyd")
                    .focused($focus, equals: .audio)
            }
            if vlc.hasSubtitles {
                VLCSubtitleMenu(engine: vlc, id: "live-tekst")
                    .focused($focus, equals: .subtitles)
            }
            Menu {
                Picker(L("Bildeformat"), selection: Binding(get: { model.pictureFormat },
                                                             set: { model.setPictureFormat($0) })) {
                    ForEach(PictureFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
            } label: {
                Label(L("Bildeformat"), systemImage: "aspectratio")
            }
            .focused($focus, equals: .format)
            .accessibilityIdentifier("live-bildeformat")
            Button {
                withAnimation { shelf = shelf == .info ? nil : .info }
            } label: {
                Label(L("Strøminfo"), systemImage: "info.circle")
            }
            .focused($focus, equals: .info)
            .accessibilityIdentifier("live-strominfo")
            if model.canStartOver {
                Button {
                    model.startOver()
                } label: {
                    Label(L("Se fra start"), systemImage: "backward.end")
                }
                .focused($focus, equals: .startOver)
                .accessibilityIdentifier("live-fra-start")
            }
            if model.canArchive {
                Button {
                    model.openArchive()
                } label: {
                    Label(L("TV-arkiv"), systemImage: "clock.arrow.circlepath")
                }
                .focused($focus, equals: .archive)
                .accessibilityIdentifier("live-arkiv")
            }
            if model.canMultiview {
                Button {
                    model.openMultiview()
                } label: {
                    Label(L("Multiview"), systemImage: "rectangle.split.2x2")
                }
                .focused($focus, equals: .multiview)
                .accessibilityIdentifier("live-multiview")
            }
        }
        .font(.system(size: 22, weight: .semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 60)
        .padding(.bottom, 44)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-valg")
    }

    @ViewBuilder
    private func shelfView(_ shelf: Shelf) -> some View {
        Group {
            switch shelf {
            case .channels:
                ChannelStrip(model: model)
                    .frame(height: 300)
                    .focusSection()
            case .info:
                StreamInfoPanel(model: model)
            }
        }
        // mørk bak teksten (over et lyst bilde var den vanskelig å lese)
        .background(Color.black.opacity(0.7))
    }

    private func openOptions() {
        hideTask?.cancel()
        withAnimation {
            info = true
            options = true
        }
        focus = .channels
    }

    private func closeOptions() {
        guard options else { return }
        withAnimation {
            options = false
            shelf = nil
        }
        focus = .screen
        show()
    }

    private func show() {
        withAnimation { info = true }
        hideTask?.cancel()
        guard !TestSupport.isActive else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !options else { return }
            withAnimation { info = false }
        }
    }
}

/// Når kanalen ikke kan spilles. «Send feilrapport» sender rapporten (med loggen fra nå) til iPhone og iPad via
/// iCloud, så årsaken kan finnes.
private struct PlayerError: View {
    @Environment(AppModel.self) private var app
    let model: PlayerModel
    let message: String
    let close: () -> Void
    @State private var sent = false

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
                Button(L("Send feilrapport")) {
                    app.sendReport(ErrorReport.build(app))
                    sent = true
                }
                .disabled(sent)
                .accessibilityIdentifier("send-rapport-spiller")
                Button(L("Lukk"), action: close)
            }
            if sent {
                Text(L("Sendt. Åpne Fyrlys på iPhone eller iPad med samme Apple-ID: Feilrapport, «Fra Apple TV»."))
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1200)
            }
        }
        .onChange(of: message) { sent = false }
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
    /// bildeformatet for kanalen
    let format: PictureFormat

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        controller.delegate = context.coordinator
        controller.customInfoViewControllers = [context.coordinator.channels, context.coordinator.info]
        controller.videoGravity = format.gravity
        updateButtons(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.videoGravity != format.gravity { controller.videoGravity = format.gravity }
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
        if model.canArchive {
            items.append(UIAction(title: L("TV-arkiv"), image: UIImage(systemName: "clock.arrow.circlepath")) { _ in
                MainActor.assumeIsolated { model.openArchive() }
            })
        }
        if model.canMultiview {
            items.append(UIAction(title: L("Multiview"), image: UIImage(systemName: "rectangle.split.2x2")) { _ in
                MainActor.assumeIsolated { model.openMultiview() }
            })
        }
        // bildeformatet for kanalen (huskes)
        let current = format
        items.append(UIMenu(title: L("Bildeformat"), image: UIImage(systemName: "aspectratio"),
                            children: PictureFormat.allCases.map { choice in
            UIAction(title: choice.title, subtitle: choice.detail, state: choice == current ? .on : .off) { _ in
                MainActor.assumeIsolated { model.setPictureFormat(choice) }
            }
        }))
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
        /// strøminfoen (feltet ved siden av «Kanaler»)
        let info: UIHostingController<StreamInfoPanel>

        init(model: PlayerModel) {
            self.model = model
            channels = UIHostingController(rootView: ChannelStrip(model: model))
            channels.title = L("Kanaler")
            channels.preferredContentSize = CGSize(width: 1920, height: 330)
            info = UIHostingController(rootView: StreamInfoPanel(model: model))
            info.title = L("Strøminfo")
            info.preferredContentSize = CGSize(width: 1920, height: 200)
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

/// Strøminfoen i spilleren (sveip ned, «Strøminfo»): oppløsningen, kodekene, bilder i sekundet, bitraten og tapte
/// bilder, og bildeformatet. Oppdateres hvert annet sekund.
struct StreamInfoPanel: View {
    let model: PlayerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let line = model.streamInfo().line
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: line.isEmpty ? "…" : line)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("strominfo")
                Text(L("Bildeformat: {name}", ["name": model.pictureFormat.title]))
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 80)
            .padding(.vertical, 30)
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
                            model.choose(channel)
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
