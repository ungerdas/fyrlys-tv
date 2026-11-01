import AVFoundation
import FyrlysCore
import SwiftUI

@main
struct FyrlysApp: App {
    @State private var model = AppModel()

    init() {
        appLanguage = TestSupport.language ?? language(ofPreferred: Locale.preferredLanguages)
        #if os(iOS)
        // lyd når telefonen står på lydløs, og bilde-i-bilde og lyd når appen ligger i bakgrunnen
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            RootView()
                .environment(model)
                .modifier(ChosenAppearance())
            #else
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
            #endif
        }
    }
}

#if os(iOS)
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
                    HomeView()
                }
            }
        }
        .task { model.start() }
        // Top Shelf: fyrlys://kanal/<id>
        .onOpenURL { url in
            if url.scheme == "fyrlys", url.host == "kanal" {
                model.pendingPlay = url.lastPathComponent
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
