#if !os(tvOS)
import AVKit
import FyrlysCore
import SwiftUI

/// Spilleren på iPhone og iPad, som spilleren i Fyrlys på Windows i et smalt vindu: bildet øverst (med bilde-i-bilde
/// og AirPlay i kontrollene), kanalen og programmet, forrige/neste/favoritt, og kanallista under. Liggende iPhone:
/// bare bildet. iPad på tvers: lista ved siden av bildet. Dra bildet ned for å lukke.
struct PlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vertical
    @State private var model: PlayerModel?
    /// hvor langt spilleren er dratt ned (dra bildet ned for å lukke)
    @State private var drag: CGFloat = 0
    let request: PlayRequest

    #if os(macOS)
    static let panelWidth: CGFloat = 420
    #else
    static let panelWidth: CGFloat = 380
    #endif

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let model {
                    if vertical == .compact {
                        // liggende iPhone: bare bildet, over hele skjermen
                        screen(model, full)
                            .ignoresSafeArea()
                    } else if geo.size.width > geo.size.height && geo.size.width >= 900 {
                        HStack(spacing: 0) {
                            screen(model, full)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            panel(model)
                                .frame(width: Self.panelWidth)
                        }
                    } else {
                        VStack(spacing: 0) {
                            screen(model, full)
                                .aspectRatio(16 / 9, contentMode: .fit)
                            panel(model)
                        }
                    }
                }
            }
            // glir ned med fingeren; det som ligger under (TV-siden), synes over
            .offset(y: drag)
        }
        .statusBarHidden(vertical == .compact)
        #if os(macOS)
        .onExitCommand { dismiss() }
        .playerKeys { command in
            guard let model else { return false }
            switch command {
            case .playPause:
                if let vlc = model.vlc { vlc.togglePause() } else { model.player.togglePlayback() }
            case .back, .forward:
                // VLC: en direktesending i TS kan ikke spoles
                guard model.vlc == nil else { return false }
                model.player.jump(command == .back ? -10 : 10)
            case .next: model.step(1)
            case .previous: model.step(-1)
            case .mute:
                if let vlc = model.vlc { vlc.toggleMute() } else { model.player.isMuted.toggle() }
            case .fullScreen: MacFullScreen.toggle()
            case .mini: toMini(model)
            }
            return true
        }
        #endif
        .onAppear {
            guard model == nil else { return }
            #if os(macOS)
            MacPlayerState.shared.live = true
            if let existing = request.existing {
                // fra minispilleren: den samme sendingen fortsetter
                existing.detached = false
                model = existing
                return
            }
            #endif
            let player = PlayerModel(app: app, channel: request.channel, list: request.list)
            model = player
            player.open(request.channel)
        }
        // ikke når AVKit sin egen fullskjerm legger seg over (da forsvinner siden under, men det spilles videre der),
        // og ikke når sendingen er flyttet til minispilleren (Mac)
        .onDisappear {
            #if os(macOS)
            MacPlayerState.shared.live = false
            MacFullScreen.leaveIfEntered()
            #endif
            if model?.inFullScreen != true && model?.detached != true { model?.stop() }
        }
        .onChange(of: programs) { model?.refreshMetadata() }
        .onChange(of: model?.closeRequested ?? false) { _, close in
            if close { dismiss() }
        }
    }

    private func panel(_ model: PlayerModel) -> PlayerPanel {
        #if os(macOS)
        PlayerPanel(model: model, close: { dismiss() }, mini: { toMini(model) })
        #else
        PlayerPanel(model: model) { dismiss() }
        #endif
    }

    private var programs: [Program] {
        guard let model else { return [] }
        return app.programs.programs(for: model.channel)
    }

    /// Bildet, og feilen over det når kanalen ikke kan spilles. [full] er hele høyden (dit spilleren glir når den
    /// lukkes ved å dra).
    private func screen(_ model: PlayerModel, _ full: CGFloat) -> some View {
        ZStack {
            Color.black
            if let vlc = model.vlc {
                // MPEG-TS med VLC (leverandøren har ikke HLS, eller Apples avspiller kunne ikke spille kanalen)
                VLCSurface(engine: vlc)
                    .id(ObjectIdentifier(vlc))
                    .overlay(alignment: .bottomLeading) { LiveVLCBadge(vlc: vlc) }
            } else {
                VideoSurface(player: model.player,
                             gravity: model.pictureFormat.gravity,
                             dragged: { drag = max(0, $0) },
                             released: { finishDrag($0, velocity: $1, full: full) },
                             fullScreen: { model.inFullScreen = $0 })
                    .modifier(ForcedAspect(ratio: model.pictureFormat.aspectRatio))
            }
            if let error = model.error {
                PlayerErrorMobil(model: model, message: error) { dismiss() }
            }
        }
    }

    #if os(macOS)
    /// Mac: sendingen over i minispilleren, og vinduet tilbake til der du var.
    private func toMini(_ model: PlayerModel) {
        // minispilleren viser Apples avspiller (ikke VLC)
        guard model.vlc == nil else { return }
        model.detached = true
        MacMiniPlayer.show(model, app: app)
        dismiss()
    }
    #endif

    /// Dratt langt nok eller fort nok ned: spilleren glir ut og lukkes. Ellers tilbake på plass.
    private func finishDrag(_ distance: CGFloat, velocity: CGFloat, full: CGFloat) {
        guard distance > 120 || (distance > 20 && velocity > 900) else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drag = 0 }
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { drag = full }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // den er alt ute av skjermen: lukk uten at den glir en gang til
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { dismiss() }
        }
    }
}

#if os(macOS)
/// Mac: AVPlayerView med Macens kontroller (fullskjerm, bilde-i-bilde, AirPlay). Esc lukker spilleren.
private struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    let dragged: (CGFloat) -> Void
    let released: (CGFloat, CGFloat) -> Void
    var fullScreen: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = gravity
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        if view.videoGravity != gravity { view.videoGravity = gravity }
    }
}
#else
/// AVPlayerViewController i siden (ikke fullskjerm), med bilde-i-bilde, og dra ned for å lukke.
private struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    /// bildeformatet (fylt, strukket …)
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// mens du drar nedover: hvor langt (punkter)
    let dragged: (CGFloat) -> Void
    /// når du slipper: hvor langt og hvor fort (punkter per sekund)
    let released: (CGFloat, CGFloat) -> Void
    /// AVKit sin fullskjerm kommer eller går
    var fullScreen: (Bool) -> Void = { _ in }

    func makeCoordinator() -> DragDown { DragDown() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = gravity
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(DragDown.pan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        controller.view.addGestureRecognizer(pan)
        controller.delegate = context.coordinator
        context.coordinator.dragged = dragged
        context.coordinator.released = released
        context.coordinator.fullScreen = fullScreen
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        if controller.videoGravity != gravity { controller.videoGravity = gravity }
        context.coordinator.dragged = dragged
        context.coordinator.released = released
        context.coordinator.fullScreen = fullScreen
    }
}

/// Dra bildet ned for å lukke spilleren. Begynner bare når fingeren går mest nedover (ikke når du spoler sidelengs), og
/// virker sammen med kontrollene til AVKit. Sier også fra når AVKit sin fullskjerm kommer og går.
private final class DragDown: NSObject, UIGestureRecognizerDelegate, AVPlayerViewControllerDelegate {
    var dragged: (CGFloat) -> Void = { _ in }
    var released: (CGFloat, CGFloat) -> Void = { _, _ in }
    var fullScreen: (Bool) -> Void = { _ in }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator
                              coordinator: UIViewControllerTransitionCoordinator) {
        fullScreen(true)
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator
                              coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            if !context.isCancelled { self?.fullScreen(false) }
        }
    }

    @objc func pan(_ pan: UIPanGestureRecognizer) {
        // i vinduets koordinater: bildet flytter seg med fingeren
        let y = pan.translation(in: nil).y
        switch pan.state {
        case .began, .changed:
            dragged(y)
        case .ended:
            released(y, pan.velocity(in: nil).y)
        case .cancelled, .failed:
            released(0, 0)
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: nil)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif

/// Kanalen og programmet, knappene og kanallista under bildet.
private struct PlayerPanel: View {
    @Environment(AppModel.self) private var app
    let model: PlayerModel
    let close: () -> Void
    #if os(macOS)
    /// til minispilleren
    var mini: () -> Void = {}
    #endif
    /// strøminfoen under knappene
    @State private var showInfo = false

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
                if model.canStartOver {
                    panelButton(L("Fra start"), "backward.end.fill", id: "fra-start-live") { model.startOver() }
                }
                if model.canMultiview {
                    panelButton(L("Multiview"), "rectangle.split.2x2", id: "multiview-knapp") { model.openMultiview() }
                }
                #if os(macOS)
                panelButton(L("Minispiller"), "pip.exit", id: "minispiller-knapp") { mini() }
                #endif
                more
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            if showInfo {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    let line = model.streamInfo().line
                    Text(verbatim: line.isEmpty ? "…" : line)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .accessibilityIdentifier("strominfo")
                }
            }
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
            ChannelList(model: model)
        }
        .background(Theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spiller")
        // UI-testene: adressene som er prøvd
        .accessibilityValue(TestSupport.isActive ? Text(verbatim: model.tried.joined(separator: " ")) : Text(""))
    }

    /// «Mer»: bildeformatet for kanalen og strøminfoen.
    private var more: some View {
        Menu {
            Picker(selection: Binding(get: { model.pictureFormat }, set: { model.setPictureFormat($0) })) {
                ForEach(PictureFormat.allCases, id: \.self) { format in
                    Text(format.title).tag(format)
                }
            } label: {
                Label(L("Bildeformat"), systemImage: "aspectratio")
            }
            .pickerStyle(.menu)
            Button {
                showInfo.toggle()
            } label: {
                Label(showInfo ? L("Skjul strøminfo") : L("Vis strøminfo"), systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface2))
        }
        #if os(macOS)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
        .accessibilityIdentifier("spiller-mer")
        .accessibilityLabel(L("Mer"))
    }

    private func panelButton(_ title: String, _ icon: String, id: String, highlighted: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            #if os(macOS)
            // Mac: ikonet over teksten (side om side ble teksten delt: «Forri-ge»)
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(highlighted ? Theme.signal : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface2))
            .contentShape(Rectangle())
            #else
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Theme.signal : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface2))
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// VLC i spilleren for direktesendingen: pause og lyd (AVKit-kontrollene finnes ikke da), og hjulet til bildet kommer.
private struct LiveVLCBadge: View {
    let vlc: VLCEngine

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if !vlc.started {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                Button { vlc.togglePause() } label: {
                    Image(systemName: vlc.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .accessibilityIdentifier(vlc.started ? "live-vlc" : "live-vlc-venter")
                .accessibilityLabel(L("Spill av / pause"))
                Button { vlc.toggleMute() } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .accessibilityLabel(L("Lyd av / på"))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(12)
        }
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
                            model.choose(channel)
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
                        .lineLimit(parts.sub.isEmpty && !channel.wantsEpg ? 2 : 1)
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
        #if os(macOS)
        .help(channel.name)
        #endif
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
