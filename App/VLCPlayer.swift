import FyrlysCore
import MediaAccessibility
import SwiftUI
#if os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

/// VLC (VLCKit, LGPL) for filmer, episoder og TV-arkiv i filtyper Apples avspiller ikke kan (mkv, avi, MPEG-TS …).
/// Bildet tegnes i [surface]; kontrollene er våre egne (`VLCPlayerScreen`). Brukes én gang: én adresse.
@MainActor
@Observable
final class VLCEngine {
    struct Track: Hashable, Identifiable {
        let id: Int32
        let name: String
    }

    /// der VLC tegner bildet
    let surface: UIView
    /// sekunder
    private(set) var time: Double = 0
    /// sekunder; 0 når lengden ikke er kjent
    private(set) var length: Double = 0
    private(set) var isPlaying = false
    /// tiden har begynt å gå
    private(set) var started = false
    /// lydsporene og undertekstene; VLC har med «av» (id -1) først
    private(set) var audioTracks: [Track] = []
    private(set) var subtitleTracks: [Track] = []
    private(set) var audioTrack: Int32 = -1
    private(set) var subtitleTrack: Int32 = -1

    /// adressen kunne ikke spilles
    @ObservationIgnored var onFail: (() -> Void)?
    /// filmen er ferdig
    @ObservationIgnored var onEnd: (() -> Void)?

    private let player: VLCMediaPlayer
    private let events = VLCEvents()
    @ObservationIgnored private var done = false
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    init() {
        player = VLCMediaPlayer(options: Self.subtitleStyle())
        surface = VLCSurfaceView()
        surface.backgroundColor = .black
        player.drawable = surface
        player.delegate = events
        events.engine = self
    }

    /// Spiller [url] fra [start] sekunder inn. Kommer ikke bildet i gang innen 45 sekunder, regnes det som feil.
    func open(_ url: URL, start: Double) {
        let media = VLCMedia(url: url)
        media.addOption(":http-user-agent=\(xtreamUserAgent)")
        // leverandørene er ofte trege: litt mer i bufferen enn VLC sitt sekund
        media.addOption(":network-caching=3000")
        if start > 5 {
            media.addOption(":start-time=\(Int(start))")
            time = start
        }
        // norske undertekster når filmen har dem (kan slås av i kontrollene)
        if appLanguage == "no" {
            media.addOption(":sub-language=nor,nob,nno,no,nb,norwegian")
        }
        player.media = media
        player.play()
        UIApplication.shared.isIdleTimerDisabled = true
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, !Task.isCancelled, !self.started else { return }
            self.fail()
        }
    }

    func stop() {
        guard !done || player.media != nil else { return }
        done = true
        watchdog?.cancel()
        player.delegate = nil
        player.stop()
        player.media = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func togglePause() {
        guard started else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    /// Til [seconds] sekunder inn (innenfor filmen).
    func seek(to seconds: Double) {
        guard started, player.isSeekable else { return }
        let end = length > 0 ? length - 2 : .infinity
        let target = max(0, min(seconds, end))
        player.time = VLCTime(int: Int32(target * 1000))
        time = target
    }

    func selectAudio(_ id: Int32) {
        player.currentAudioTrackIndex = id
        audioTrack = id
    }

    func selectSubtitle(_ id: Int32) {
        player.currentVideoSubTitleIndex = id
        subtitleTrack = id
    }

    private func fail() {
        guard !done else { return }
        stop()
        onFail?()
    }

    fileprivate func stateChanged() {
        guard !done else { return }
        if player.isPlaying != isPlaying { isPlaying = player.isPlaying }
        switch player.state {
        case .error:
            fail()
        case .ended, .stopped:
            if started {
                done = true
                UIApplication.shared.isIdleTimerDisabled = false
                onEnd?()
            } else {
                fail()
            }
        case .playing, .esAdded:
            refreshTracks()
        default:
            break
        }
    }

    fileprivate func timeChanged() {
        guard !done else { return }
        let t = Double(player.time.intValue) / 1000
        if t > 0, !started {
            started = true
            watchdog?.cancel()
            refreshTracks()
        }
        if abs(t - time) >= 0.25 { time = t }
        let l = Double(player.media?.length.intValue ?? 0) / 1000
        if l != length { length = l }
        if player.isPlaying != isPlaying { isPlaying = player.isPlaying }
    }

    private func refreshTracks() {
        let audio = Self.tracks(player.audioTrackNames, player.audioTrackIndexes)
        let subtitles = Self.tracks(player.videoSubTitlesNames, player.videoSubTitlesIndexes)
        if audio != audioTracks { audioTracks = audio }
        if subtitles != subtitleTracks { subtitleTracks = subtitles }
        audioTrack = player.currentAudioTrackIndex
        subtitleTrack = player.currentVideoSubTitleIndex
    }

    /// Undertekstene i Apple sin stil: hvit tekst på en halvgjennomsiktig mørk boks, uten kant og skygge, i stedet
    /// for VLC sin hvite tekst med tykk svart kant (0.1.17 tok fargene fra «Undertekster og teksting», og der er
    /// bakgrunnen gjennomsiktig som standard, så boksen ble borte). Størrelsen følger fortsatt den innstillingen.
    /// Tittelen VLC ellers viser over bildet i starten, er slått av.
    static func subtitleStyle() -> [String] {
        // VLC: høyden på bildet delt på tallet (18 er litt mindre enn VLC sin standard, som Apple)
        let size = MACaptionAppearanceGetRelativeCharacterSize(.user, nil)
        let relative = Int((18 / max(0.5, min(size > 0 ? size : 1, 2))).rounded())
        return [
            "--freetype-font=Helvetica Neue Medium",
            "--freetype-rel-fontsize=\(relative)",
            "--freetype-color=\(0xFFFFFF)",
            "--freetype-opacity=255",
            "--freetype-background-color=0",
            "--freetype-background-opacity=150",
            "--freetype-outline-thickness=0",
            "--freetype-shadow-opacity=0",
            "--no-video-title-show",
        ]
    }

    private static func tracks(_ names: [Any], _ ids: [Any]) -> [Track] {
        zip(names, ids).compactMap { name, id in
            guard let id = (id as? NSNumber)?.int32Value else { return nil }
            let text = (name as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return Track(id: id, name: id < 0 ? L("Av") : (text.isEmpty ? L("Spor {n}", ["n": id]) : text))
        }
    }
}

/// Hendelsene fra VLC (som kan komme fra en annen tråd) videre til `VLCEngine` på hovedtråden.
private final class VLCEvents: NSObject, VLCMediaPlayerDelegate {
    weak var engine: VLCEngine?

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.engine?.stateChanged() }
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.engine?.timeChanged() }
        }
    }
}

/// Der VLC tegner bildet: VLC legger sin egen visning inni, og den følger alltid størrelsen på denne (arket på iPhone
/// og iPad endrer størrelse når det dras eller telefonen snus).
final class VLCSurfaceView: UIView {
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        subview.frame = bounds
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for view in subviews where view.frame != bounds {
            view.frame = bounds
            view.setNeedsLayout()
        }
    }
}

/// Visningen VLC tegner bildet i.
struct VLCSurface: UIViewRepresentable {
    let engine: VLCEngine

    func makeUIView(context: Context) -> UIView { engine.surface }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// Hvor langt filmen har kommet: streken, med tiden som er gått og det som er igjen under.
private struct VLCProgress: View {
    let time: Double
    let length: Double
    var seeking = false
    /// streken (på iPhone og iPad er den en Slider over)
    var bar = true

    var body: some View {
        VStack(spacing: 8) {
            if bar {
                GeometryReader { geo in
                    let part = length > 0 ? min(1, max(0, time / length)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(seeking ? Theme.gold : Color.white)
                            .frame(width: geo.size.width * part)
                    }
                }
                .frame(height: Self.barHeight)
            }
            HStack {
                Text(verbatim: playTime(time))
                    .accessibilityIdentifier("vod-tid")
                Spacer()
                if length > 0 {
                    Text(verbatim: "-" + playTime(length - time))
                }
            }
            .font(.system(size: Self.font, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.85))
        }
    }

    #if os(tvOS)
    static let barHeight: CGFloat = 10
    static let font: CGFloat = 24
    #else
    static let barHeight: CGFloat = 4
    static let font: CGFloat = 13
    #endif
}

/// Lydsporet som meny (når filmen har flere).
private struct VLCAudioMenu: View {
    let engine: VLCEngine

    var body: some View {
        Menu {
            Picker(L("Lyd"), selection: Binding(get: { engine.audioTrack }, set: { engine.selectAudio($0) })) {
                ForEach(engine.audioTracks.filter { $0.id >= 0 }) { track in
                    Text(verbatim: track.name).tag(track.id)
                }
            }
        } label: {
            VLCMenuLabel(title: L("Lyd"), icon: "speaker.wave.2")
        }
        .accessibilityIdentifier("vod-lyd")
    }
}

/// Undertekstene som meny (når filmen har noen), med «av» først.
private struct VLCSubtitleMenu: View {
    let engine: VLCEngine

    var body: some View {
        Menu {
            Picker(L("Undertekster"),
                   selection: Binding(get: { engine.subtitleTrack }, set: { engine.selectSubtitle($0) })) {
                ForEach(engine.subtitleTracks) { track in
                    Text(verbatim: track.name).tag(track.id)
                }
            }
        } label: {
            VLCMenuLabel(title: L("Undertekster"), icon: "captions.bubble")
        }
        .accessibilityIdentifier("vod-tekst")
    }
}

private struct VLCMenuLabel: View {
    let title: String
    let icon: String

    var body: some View {
        #if os(tvOS)
        Label(title, systemImage: icon)
            .font(.system(size: 24, weight: .semibold))
        #else
        Image(systemName: icon)
            .font(.system(size: 19, weight: .semibold))
            .frame(width: 44, height: 44)
            .accessibilityLabel(title)
        #endif
    }
}

extension VLCEngine {
    /// mer enn ett lydspor å velge mellom
    var hasAudioChoice: Bool { audioTracks.filter { $0.id >= 0 }.count > 1 }
    var hasSubtitles: Bool { subtitleTracks.contains { $0.id >= 0 } }
}

#if os(tvOS)
/// Apple TV: bildet over hele skjermen. Velg eller spill/pause = pause, venstre og høyre = spol (10 sekunder, mer når
/// du trykker flere ganger etter hverandre), ned = lyd og undertekster, Menu = skjul kontrollene, så lukk.
struct VLCPlayerScreen: View {
    let engine: VLCEngine
    let title: String
    let subtitle: String
    let close: () -> Void

    private enum Field: Hashable { case screen, audio, subtitles }

    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    /// målet for spolingen mens du trykker
    @State private var pending: Double?
    @State private var seekTask: Task<Void, Never>?
    @State private var presses = 0
    @FocusState private var focus: Field?

    var body: some View {
        ZStack(alignment: .bottom) {
            VLCSurface(engine: engine)
                .ignoresSafeArea()
            Button {
                engine.togglePause()
                show()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(BareButtonStyle())
            .focused($focus, equals: .screen)
            .ignoresSafeArea()
            if !engine.started {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if controls || !engine.isPlaying {
                panel
                    .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .defaultFocus($focus, .screen)
        .onAppear {
            focus = .screen
            show()
        }
        .onPlayPauseCommand {
            engine.togglePause()
            show()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left where focus == .screen: skip(-1)
            case .right where focus == .screen: skip(1)
            case .down where focus == .screen:
                show()
                if engine.hasAudioChoice {
                    focus = .audio
                } else if engine.hasSubtitles {
                    focus = .subtitles
                }
            case .up where focus != .screen:
                focus = .screen
                show()
            default: show()
            }
        }
        .onExitCommand {
            if focus != .screen {
                focus = .screen
                show()
            } else if controls && engine.isPlaying {
                hideTask?.cancel()
                withAnimation { controls = false }
            } else {
                close()
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Image(systemName: engine.isPlaying || !engine.started ? "play.fill" : "pause.fill")
                    .font(.system(size: 30, weight: .bold))
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }
            VLCProgress(time: pending ?? engine.time, length: engine.length, seeking: pending != nil)
                .padding(.top, 10)
            HStack(spacing: 24) {
                if engine.hasAudioChoice {
                    VLCAudioMenu(engine: engine)
                        .focused($focus, equals: .audio)
                }
                if engine.hasSubtitles {
                    VLCSubtitleMenu(engine: engine)
                        .focused($focus, equals: .subtitles)
                }
                Spacer(minLength: 0)
                Text(engine.hasAudioChoice || engine.hasSubtitles
                     ? L("◀ ▶ spol  ·  ned: lyd og undertekster") : L("◀ ▶ spol"))
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .focusSection()
        }
        .padding(.horizontal, 90)
        .padding(.top, 140)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    /// Kontrollene fram, og bort igjen etter fem sekunder når filmen går (ikke i testene: de leser tiden).
    private func show() {
        withAnimation { controls = true }
        hideTask?.cancel()
        guard !TestSupport.isActive else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, engine.isPlaying, focus == .screen, pending == nil else { return }
            withAnimation { controls = false }
        }
    }

    /// Spol fram eller tilbake: 10 sekunder, 30 etter tre trykk på rad og et minutt etter seks. Hoppet gjøres når du
    /// slutter å trykke.
    private func skip(_ direction: Double) {
        guard engine.started else { return }
        presses = seekTask == nil ? 1 : presses + 1
        let step: Double = presses > 6 ? 60 : (presses > 3 ? 30 : 10)
        let end = engine.length > 0 ? engine.length - 2 : .infinity
        pending = max(0, min((pending ?? engine.time) + direction * step, end))
        show()
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            if let pending { engine.seek(to: pending) }
            pending = nil
            seekTask = nil
            presses = 0
            show()
        }
    }
}

/// En knapp uten utseende (hele skjermen i spilleren).
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#else
/// iPhone og iPad: trykk på bildet for kontrollene (lukk, lyd og undertekster, 10 sekunder tilbake og fram, pause og
/// streken du kan dra i). De forsvinner etter noen sekunder når filmen går.
struct VLCPlayerScreen: View {
    let engine: VLCEngine
    let title: String
    let subtitle: String
    let close: () -> Void

    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrub: Double?

    var body: some View {
        ZStack {
            VLCSurface(engine: engine)
                .ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    if controls {
                        hideTask?.cancel()
                        withAnimation { controls = false }
                    } else {
                        show()
                    }
                }
            if !engine.started {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            }
            if controls || !engine.isPlaying {
                controlsLayer
                    .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear(perform: show)
    }

    private var controlsLayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("Lukk"))
                .accessibilityIdentifier("lukk-vod")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if engine.hasAudioChoice { VLCAudioMenu(engine: engine) }
                if engine.hasSubtitles { VLCSubtitleMenu(engine: engine) }
                if Landscape.isPhone {
                    Button {
                        Landscape.set(!Landscape.isLandscape)
                        show()
                    } label: {
                        Image(systemName: "rectangle.landscape.rotate")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("Snu skjermen"))
                    .accessibilityIdentifier("snu-skjermen")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            Spacer(minLength: 0)
            HStack(spacing: 56) {
                controlButton("gobackward.10", L("10 sekunder tilbake"), size: 26) { jump(-10) }
                controlButton(engine.isPlaying || !engine.started ? "pause.fill" : "play.fill",
                              engine.isPlaying ? L("Pause") : L("Spill av"), size: 40) {
                    engine.togglePause()
                    show()
                }
                .accessibilityIdentifier("vod-pause")
                controlButton("goforward.10", L("10 sekunder fram"), size: 26) { jump(10) }
            }
            .disabled(!engine.started)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                if engine.length > 0 {
                    Slider(value: Binding(get: { scrub ?? engine.time }, set: { scrub = $0 }),
                           in: 0...max(engine.length, 1)) { editing in
                        if !editing, let scrub {
                            engine.seek(to: scrub)
                            self.scrub = nil
                        }
                        show()
                    }
                    .tint(Theme.gold)
                }
                VLCProgress(time: scrub ?? engine.time, length: engine.length, seeking: scrub != nil, bar: false)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .foregroundStyle(Color.white)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.6), .clear, .clear, Color.black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    private func controlButton(_ icon: String, _ label: String, size: CGFloat,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 1.8, height: size * 1.8)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func jump(_ seconds: Double) {
        engine.seek(to: engine.time + seconds)
        show()
    }

    /// Kontrollene fram, og bort igjen etter fire sekunder når filmen går (ikke i testene: de leser tiden).
    private func show() {
        withAnimation { controls = true }
        hideTask?.cancel()
        guard !TestSupport.isActive else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, engine.isPlaying, scrub == nil else { return }
            withAnimation { controls = false }
        }
    }
}
#endif

#if os(iOS)
/// iPhone: filmer og serier liggende, som i Apple TV-appen (også når skjermretningen er låst), og tilbake når
/// spilleren lukkes. iPad: som den står.
enum Landscape {
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    static var isLandscape: Bool { scene?.interfaceOrientation.isLandscape ?? false }

    static func set(_ landscape: Bool) {
        guard isPhone, let scene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscape : .portrait)) { _ in }
    }
}
#endif
