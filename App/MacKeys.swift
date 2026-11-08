#if os(macOS)
import AppKit
import AVKit
import FyrlysCore
import SwiftUI

/// Det tastene og menyen «Avspilling» kan be spilleren om (Mac).
enum PlayerCommand {
    case playPause, forward, back, next, previous, fullScreen, mute, mini
}

extension Notification.Name {
    /// fra menyen «Avspilling» (objektet er en `PlayerCommand`)
    static let fyrlysPlayerCommand = Notification.Name("fyrlysPlayerCommand")
    /// ⌘1–5: TV, TV-guide, Filmer, Serier, Plex (objektet er nummeret)
    static let fyrlysSection = Notification.Name("fyrlysSection")
    /// ⌘F: til søkefeltet i verktøylinja
    static let fyrlysFind = Notification.Name("fyrlysFind")
}

/// Vis-menyen: søket (⌘F) og seksjonene (⌘1–5, i den rekkefølgen de står øverst).
struct SectionCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(L("Søk")) {
                NotificationCenter.default.post(name: .fyrlysFind, object: nil)
            }
            .keyboardShortcut("f")
            Divider()
            section(L("TV"), 1)
            section(L("TV-guide"), 2)
            section(L("Filmer"), 3)
            section(L("Serier"), 4)
            section("Plex", 5)
            Divider()
        }
    }

    private func section(_ title: String, _ number: Int) -> some View {
        Button(title) {
            NotificationCenter.default.post(name: .fyrlysSection, object: number)
        }
        .keyboardShortcut(KeyEquivalent(Character("\(number)")))
    }
}

/// Spilleren som er framme (menyen «Avspilling» er grå ellers).
@MainActor
@Observable
final class MacPlayerState {
    static let shared = MacPlayerState()
    /// direktesending (kanalbytte og minispiller går)
    var live = false
    /// film, episode eller program fra start
    var vod = false
    /// minispilleren er åpen
    var mini = false
}

extension View {
    /// Mac: tastene i spilleren (mellomrom, piltastene, F, M, I) og menyen «Avspilling». [handle] svarer om den
    /// gjorde noe; ellers går tasten videre.
    func playerKeys(_ handle: @escaping (PlayerCommand) -> Bool) -> some View {
        modifier(PlayerKeys(handle: handle))
    }
}

private struct PlayerKeys: ViewModifier {
    let handle: (PlayerCommand) -> Bool
    @State private var box = Box()

    final class Box {
        var handle: (PlayerCommand) -> Bool = { _ in false }
        var monitor: Any?
        /// vinduet spilleren står i (på Mac et ark over hovedvinduet)
        weak var window: NSWindow?
    }

    func body(content: Content) -> some View {
        box.handle = handle
        return content
            .background(WindowProbe(box: box))
            .onAppear {
                guard box.monitor == nil else { return }
                let box = box
                box.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard let window = box.window, event.window === window, window.attachedSheet == nil,
                          let command = Self.command(for: event) else { return event }
                    return box.handle(command) ? nil : event
                }
            }
            .onDisappear {
                if let monitor = box.monitor { NSEvent.removeMonitor(monitor) }
                box.monitor = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .fyrlysPlayerCommand)) { note in
                if let command = note.object as? PlayerCommand { _ = box.handle(command) }
            }
    }

    /// Tasten uten ⌘, ⌃ og ⌥, og ikke mens det skrives i et felt.
    private static func command(for event: NSEvent) -> PlayerCommand? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        if event.window?.firstResponder is NSText { return nil }
        switch event.keyCode {
        case 49: return .playPause        // mellomrom
        case 123: return .back            // ←
        case 124: return .forward         // →
        case 125: return .next            // ↓
        case 126: return .previous        // ↑
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f": return .fullScreen
        case "m": return .mute
        case "i": return .mini
        case "k": return .playPause
        default: return nil
        }
    }

    private struct WindowProbe: NSViewRepresentable {
        let box: Box
        func makeNSView(context: Context) -> NSView { Probe(box: box) }
        func updateNSView(_ view: NSView, context: Context) {}

        final class Probe: NSView {
            let box: Box
            init(box: Box) {
                self.box = box
                super.init(frame: .zero)
            }
            required init?(coder: NSCoder) { nil }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let window {
                    box.window = window
                    // søkefeltet bak spilleren skal ikke ta tastene
                    if window.firstResponder is NSText { window.makeFirstResponder(nil) }
                }
            }
        }
    }
}

/// Menyen «Avspilling» i menylinja. Uten snarveier i menyen (mellomrom og piltastene ville tatt tegnene fra
/// søkefeltet); tastene står i navnet.
struct PlaybackCommands: Commands {
    var body: some Commands {
        CommandMenu(L("Avspilling")) {
            PlaybackMenu()
        }
    }
}

private struct PlaybackMenu: View {
    private var state: MacPlayerState { .shared }

    var body: some View {
        let any = state.live || state.vod
        item(L("Spill av / pause (mellomrom)"), .playPause).disabled(!any)
        item(L("Spol 10 s tilbake (←)"), .back).disabled(!any)
        item(L("Spol 10 s fram (→)"), .forward).disabled(!any)
        Divider()
        item(L("Forrige kanal (↑)"), .previous).disabled(!state.live)
        item(L("Neste kanal (↓)"), .next).disabled(!state.live)
        Divider()
        item(L("Lyd av / på (M)"), .mute).disabled(!any)
        item(L("Fullskjerm (F)"), .fullScreen).disabled(!any)
        if state.mini {
            Button(L("Tilbake i vinduet")) { MacMiniPlayer.expand() }
            Button(L("Lukk minispilleren")) { MacMiniPlayer.close() }
        } else {
            item(L("Minispiller (I)"), .mini).disabled(!state.live)
        }
    }

    private func item(_ title: String, _ command: PlayerCommand) -> some View {
        Button(title) {
            NotificationCenter.default.post(name: .fyrlysPlayerCommand, object: command)
        }
    }
}

extension AVPlayer {
    /// [seconds] fram eller tilbake, innenfor det som kan spoles i (i en direktesending: bufferet).
    func jump(_ seconds: Double) {
        let now = currentTime().seconds
        guard now.isFinite else { return }
        var target = now + seconds
        if let range = currentItem?.seekableTimeRanges.last?.timeRangeValue {
            let start = range.start.seconds
            let end = range.end.seconds
            if start.isFinite, end.isFinite, end > start {
                target = min(max(target, start), end - 1)
            }
        }
        seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600))
    }

    func togglePlayback() {
        if timeControlStatus == .paused { play() } else { pause() }
    }
}

// MARK: - Minispilleren

/// Mac: direktesendingen i et lite vindu som ligger over alt (også andre apper), mens du blar i Fyrlys eller gjør noe
/// annet. Som minispilleren i Fyrlys for Windows. Én om gangen; en annen kanal, film eller multiview lukker den
/// (leverandøren gir ofte bare én tilkobling).
@MainActor
enum MacMiniPlayer {
    private static var panel: NSPanel?
    private(set) static var model: PlayerModel?
    private static weak var app: AppModel?
    private static var closeObserver: NSObjectProtocol?

    static var isOpen: Bool { panel != nil }

    static func show(_ player: PlayerModel, app: AppModel) {
        close()
        model = player
        self.app = app
        let size = NSSize(width: 448, height: 252)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        panel.minSize = NSSize(width: 288, height: 162)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.setFrameAutosaveName("Fyrlys minispiller")
        panel.contentView = NSHostingView(rootView: MiniPlayerView(model: player).environment(app))
        panel.title = L("Minispiller")
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { closed() }
        }
        self.panel = panel
        panel.orderFrontRegardless()
        MacPlayerState.shared.live = false
        MacPlayerState.shared.mini = true
    }

    /// Lukker vinduet og stopper sendingen.
    static func close() {
        guard let panel else { return }
        panel.close()
        closed()
    }

    /// Tilbake i det store vinduet: spilleren tar over den samme sendingen (den stoppes ikke).
    static func expand() {
        guard let player = model, let app else { return }
        model = nil
        let panel = self.panel
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        self.panel = nil
        panel?.close()
        MacPlayerState.shared.mini = false
        app.reopenPlayer = PlayRequest(channel: player.channel, list: player.list, existing: player)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func closed() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        panel = nil
        MacPlayerState.shared.mini = false
        model?.stop()
        model = nil
    }
}

private struct MiniPlayerView: View {
    let model: PlayerModel
    @State private var hover = false

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerView(player: model.player)
            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(20)
            }
            if hover {
                controls
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onHover { inside in withAnimation(.easeInOut(duration: 0.15)) { hover = inside } }
        .onTapGesture(count: 2) { MacMiniPlayer.expand() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("minispiller")
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 8) {
                Text(verbatim: nameParts(model.channel.name).main)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                button("arrow.up.left.and.arrow.down.right", L("Tilbake i vinduet"), id: "mini-utvid") {
                    MacMiniPlayer.expand()
                }
                button("xmark", L("Lukk"), id: "mini-lukk") { MacMiniPlayer.close() }
            }
            Spacer()
            HStack(spacing: 14) {
                button("backward.fill", L("Forrige"), id: "mini-forrige") { model.step(-1) }
                button(model.player.timeControlStatus == .paused ? "play.fill" : "pause.fill",
                       L("Spill av / pause"), id: "mini-pause") { model.player.togglePlayback() }
                button("forward.fill", L("Neste"), id: "mini-neste") { model.step(1) }
                Spacer(minLength: 0)
                button(model.player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       L("Lyd av / på"), id: "mini-lyd") { model.player.isMuted.toggle() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func button(_ icon: String, _ label: String, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
#endif
