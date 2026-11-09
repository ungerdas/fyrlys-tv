import AVFoundation
import FyrlysCore
import SwiftUI
#if !os(tvOS)
import UserNotifications
#endif

@main
struct FyrlysApp: App {
    @State private var model = AppModel()

    init() {
        appLanguage = TestSupport.language ?? language(ofPreferred: Locale.preferredLanguages)
        #if !os(tvOS)
        // påminnelsene fra guiden
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        #endif
        #if os(macOS)
        // ett vindu: ingen «Vis fanelinje» og «Vis alle faner» i Vis-menyen
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
        #if os(iOS)
        // lyd når telefonen står på lydløs, og bilde-i-bilde og lyd når appen ligger i bakgrunnen
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            RootView()
                .environment(model)
                .modifier(ChosenAppearance())
                // skjemaene (Innstillinger, Plex, egne strømmer) gruppert som i Systeminnstillinger
                .formStyle(.grouped)
                .frame(minWidth: 900, minHeight: 560)
                // størrelsen, plassen og fullskjerm fra sist
                .background(WindowMemory())
            #elseif os(iOS)
            RootView()
                .environment(model)
                .modifier(ChosenAppearance())
            #else
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 880)
        .commands {
            // ⌘, som i andre Mac-apper: innstillingene i vinduet
            CommandGroup(replacing: .appSettings) {
                Button(L("Innstillinger")) {
                    NotificationCenter.default.post(name: .fyrlysOpenSettings, object: nil)
                }
                .keyboardShortcut(",")
            }
            // ⌘F og ⌘1–5 (seksjonene) i Vis-menyen
            SectionCommands()
            PlaybackCommands()
        }
        #endif
    }
}

#if !os(tvOS)
/// Lys eller mørk modus slik den er valgt (sola og månen øverst på iPhone, Innstillinger på iPad), ellers som enheten.
private struct ChosenAppearance: ViewModifier {
    @AppStorage(Appearance.key, store: TestSupport.defaults) private var stored = ""

    func body(content: Content) -> some View {
        content.preferredColorScheme(Appearance.scheme(stored))
    }
}
#endif

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.phase {
            case .starting:
                ProgressView()
            case .signedOut:
                LoginView()
            case .ready:
                if model.addingLogin {
                    LoginView()
                } else {
                    // ny innlogging: ny side (før sto kategorien og stien fra den forrige leverandøren igjen)
                    HomeView()
                        .id(model.login?.id)
                }
            }
        }
        .task {
            model.start()
            CrashWatch.start()
            #if !os(tvOS)
            // Siri: «Spill … i Fyrlys» da appen ble startet
            if let id = IntentInbox.take() { model.pendingPlay = id }
            #endif
            #if os(macOS)
            WindowSnapshot.startIfRequested()
            #endif
        }
        // fram igjen fra bakgrunnen (eller Apple TV-en har sovet): programinfo, Plex, filmer og kanallista
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() }
            // krasj eller ikke: bare når appen var framme
            CrashWatch.foreground(phase != .background)
        }
        #if !os(tvOS)
        .onReceive(NotificationCenter.default.publisher(for: .fyrlysIntentPlay)) { _ in
            if let id = IntentInbox.take() { model.pendingPlay = id }
        }
        #endif
        // Top Shelf: fyrlys://kanal/<id>
        .onOpenURL { url in
            if url.scheme == "fyrlys", url.host == "kanal" {
                model.pendingPlay = url.lastPathComponent
            } else if url.scheme == "fyrlys", url.host == "vod" {
                model.openVOD(url)
            }
        }
    }
}

/// «1. november 2026» / «1 November 2026»
func longDate(_ date: Date) -> String {
    let format = DateFormatter()
    format.locale = Locale(identifier: appLanguage == "no" ? "nb_NO" : "en_GB")
    format.dateStyle = .long
    format.timeStyle = .none
    return format.string(from: date)
}

/// Versjonen fra Info.plist, f.eks. «0.1.0».
var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
}
