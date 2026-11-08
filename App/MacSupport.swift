#if os(macOS)
import AppKit
import FyrlysCore
import SwiftUI

// Mac (fra 0.2.2): navnene fra UIKit som resten av appen bruker, med AppKit under.

typealias UIImage = NSImage
typealias UIColor = NSColor

extension NSImage {
    /// som UIImage.cgImage
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// som UIImage(cgImage:)
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

extension Image {
    /// som Image(uiImage:)
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}
#endif

#if os(macOS)
/// Mac: aldri en telefon som skal legges ned (`Landscape` er for iPhone).
enum Landscape {
    static let isPhone = false
    static let isLandscape = true
    static func set(_ landscape: Bool) {}
}

/// Det UIKit-appen bruker av UIApplication: skjermspareren (en aktivitet som holder skjermen våken mens noe spilles)
/// og «i bakgrunnen» (på Mac aldri: lyden fortsetter når vinduet er skjult, som i andre avspillere på Mac).
final class UIApplication {
    static let shared = UIApplication()
    static let didEnterBackgroundNotification = Notification.Name("no.fyrlys.mac.aldri")
    static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    static let willResignActiveNotification = NSApplication.willResignActiveNotification

    private var activity: NSObjectProtocol?

    var isIdleTimerDisabled: Bool {
        get { activity != nil }
        set {
            if newValue, activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Fyrlys spiller")
            } else if !newValue, let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
        }
    }
}

/// Tastaturtypen og store forbokstaver finnes ikke på Mac (fysisk tastatur).
enum UIKeyboardType {
    case `default`, URL, numberPad, asciiCapable, emailAddress, decimalPad, numbersAndPunctuation
}

struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
}

extension View {
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View { self }
}

extension NSTextContentType {
    static let URL = NSTextContentType(rawValue: "URL")
}
#endif

#if os(macOS)
/// Enheten i feilrapporten.
final class UIDevice {
    static let current = UIDevice()
    let model = "Mac"
    let systemName = "macOS"
    var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// «Kopier» i feilrapporten.
final class UIPasteboard {
    static let general = UIPasteboard()

    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }
}
#endif

#if os(macOS)
import AVFoundation

extension UIDevice {
    /// navnet på Mac-en (Plex viser det i listen over enheter)
    var name: String { Host.current().localizedName ?? "Mac" }
}

extension NSImage {
    /// som UIImage.byPreparingThumbnail(ofSize:): tegnet på nytt i [size] piksler
    func byPreparingThumbnail(ofSize size: CGSize) async -> NSImage? {
        guard let source = cgImage, size.width >= 1, size.height >= 1 else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage().map { NSImage(cgImage: $0) }
    }
}

extension AVPlayerItem {
    /// programinfoen i Apples kontroller finnes ikke på Mac (AVPlayerView viser ikke titler)
    var externalMetadata: [AVMetadataItem] {
        get { [] }
        set {}
    }
}

// Plasseringene og linjene fra iOS, det nærmeste på Mac.
extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension SearchFieldPlacement {
    enum MacDrawerMode { case always, automatic }
    static func navigationBarDrawer(displayMode: MacDrawerMode) -> SearchFieldPlacement { .toolbar }
}

extension ContentShapeKinds {
    static var contextMenuPreview: ContentShapeKinds { .interaction }
}

enum MacTitleDisplayMode { case inline, large, automatic }

/// Redigeringsknappen i lister finnes ikke på Mac (der flyttes rader med musa).
struct EditButton: View {
    var body: some View { EmptyView() }
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: MacTitleDisplayMode) -> some View { self }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }

    /// Spilleren og multiview (fullskjerm på iPhone og iPad): et ark like stort som vinduet.
    func fullScreenCover<Item: Identifiable, Cover: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Cover
    ) -> some View {
        modifier(WindowCover(item: item, onDismiss: onDismiss, cover: content))
    }
}

private struct WindowCover<Item: Identifiable, Cover: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let cover: (Item) -> Cover
    @State private var size = CGSize(width: 1280, height: 800)

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { size = geo.size }
                        .onChange(of: geo.size) { _, new in size = new }
                }
            }
            .sheet(item: $item, onDismiss: onDismiss) { item in
                cover(item)
                    .frame(width: max(640, size.width), height: max(420, size.height))
            }
    }
}
#endif

#if os(macOS)
/// Testene og Claude-økta på Mac-en (uten tillatelse til skjermopptak): med FYRLYS_TEST_SNAPSHOT lagrer appen et bilde
/// av vinduet sitt hvert andre sekund som «vindu.png» i Documents i sandkassen
/// (~/Library/Containers/no.fyrlys.tv/Data/Documents). Videobildet kommer ikke med (det tegnes utenom vinduet).
enum WindowSnapshot {
    @MainActor
    static func startIfRequested() {
        // også uten den falske leverandøren i et Debug-bygg (eieren logget inn selv, bildene blir på Mac-en)
        #if DEBUG
        let allowed = true
        #else
        let allowed = TestSupport.isActive
        #endif
        guard allowed, TestSupport.env["FYRLYS_TEST_SNAPSHOT"] != nil,
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent("vindu.png")
        NSLog("FYRLYS_SNAPSHOT %@", url.path)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { save(to: url) }
        }
    }

    @MainActor
    private static func save(to url: URL) {
        // et ark (spilleren, multiview) er et eget vindu over hovedvinduet: da arket
        guard var window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.sheetParent == nil })
        else {
            NSLog("FYRLYS_SNAPSHOT ingen vindu (%d)", NSApp.windows.count)
            return
        }
        if let sheet = window.attachedSheet { window = sheet }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
        } catch {
            NSLog("FYRLYS_SNAPSHOT %@", "\(error)")
        }
    }
}
#endif

#if os(macOS)
/// Fullskjerm for hovedvinduet (spilleren er et ark like stort som vinduet, så det følger med). Går ut av fullskjerm
/// igjen når spilleren lukkes, hvis det var spilleren som gikk inn.
@MainActor
enum MacFullScreen {
    /// spilleren gikk i fullskjerm (huskes ikke til neste gang appen åpnes)
    private(set) static var enteredForPlayer = false

    static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.contentView != nil && !($0 is NSPanel) }
    }

    static var isOn: Bool { window?.styleMask.contains(.fullScreen) == true }

    static func toggle() {
        enteredForPlayer = !isOn
        window?.toggleFullScreen(nil)
    }

    static func leaveIfEntered() {
        if enteredForPlayer, isOn { window?.toggleFullScreen(nil) }
        enteredForPlayer = false
    }
}

/// Mac: vinduet åpner der det var, like stort, og i fullskjerm hvis det var det da appen ble avsluttet (som Fyrlys
/// for Windows 2.1.38). Ikke i testene.
struct WindowMemory: NSViewRepresentable {
    static let frameKey = "vindu-ramme"
    static let fullScreenKey = "vindu-fullskjerm"

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    /// SwiftUI lagrer rammen under et navn med adresser som endres for hver start, så den ble aldri funnet igjen (og
    /// en ny linje ble lagt i innstillingene hver gang). Her lagres den under ett navn, og de gamle ryddes bort.
    final class Probe: NSView {
        private var done = false
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, let window,
                  !TestSupport.isActive || ProcessInfo.processInfo.environment["FYRLYS_TEST_WINDOW"] != nil
            else { return }
            done = true
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("NSWindow Frame SwiftUI.") && key.contains("unknown context") {
                defaults.removeObject(forKey: key)
            }
            // etter at SwiftUI har satt sin størrelse
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                if let saved = defaults.string(forKey: WindowMemory.frameKey) {
                    window.setFrame(from: saved)
                }
                if defaults.bool(forKey: WindowMemory.fullScreenKey), !window.styleMask.contains(.fullScreen) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.toggleFullScreen(nil) }
                }
                self.watch(window)
            }
        }

        private func watch(_ window: NSWindow) {
            let center = NotificationCenter.default
            let save: (Notification) -> Void = { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window, !window.styleMask.contains(.fullScreen) else { return }
                    UserDefaults.standard.set(window.frameDescriptor, forKey: WindowMemory.frameKey)
                }
            }
            for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification,
                         NSWindow.didResizeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main, using: save))
            }
            observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window,
                                                queue: .main) { _ in
                MainActor.assumeIsolated {
                    // fullskjerm fra spilleren huskes ikke (den går ut igjen når spilleren lukkes)
                    if !MacFullScreen.enteredForPlayer {
                        UserDefaults.standard.set(true, forKey: WindowMemory.fullScreenKey)
                    }
                }
            })
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                                queue: .main) { _ in
                UserDefaults.standard.set(false, forKey: WindowMemory.fullScreenKey)
            })
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

extension View {
    /// Mac: «…» til høyre på en linje når musa står over den, med de samme valgene som hurtigmenyen (høyreklikk), som
    /// ellers er vanskelig å finne (på Apple TV, iPhone og iPad holder man inne).
    func macRowMenu<Menu: View>(@ViewBuilder _ menu: @escaping () -> Menu) -> some View {
        modifier(MacRowMenu(menu: menu))
    }
}

private struct MacRowMenu<Items: View>: ViewModifier {
    let menu: () -> Items
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                Menu {
                    menu()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 8)
                .opacity(hover ? 1 : 0)
                .help(L("Flere valg"))
                .accessibilityLabel(L("Flere valg"))
            }
            .onHover { hover = $0 }
    }
}

/// Knappen i VLC-kontrollene (Apples avspiller har sin egen).
struct MacFullScreenButton: View {
    @State private var on = MacFullScreen.isOn

    var body: some View {
        Button {
            MacFullScreen.toggle()
        } label: {
            Image(systemName: on ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? L("Avslutt fullskjerm") : L("Fullskjerm"))
        .accessibilityLabel(on ? L("Avslutt fullskjerm") : L("Fullskjerm"))
        .accessibilityIdentifier("fullskjerm")
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in on = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in on = false }
    }
}
#endif

#if os(macOS)
extension Notification.Name {
    /// ⌘, (menyen Fyrlys → Innstillinger)
    static let fyrlysOpenSettings = Notification.Name("no.fyrlys.innstillinger")
}

/// Merket øverst til venstre, som i Fyrlys for Windows.
struct MacBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            FyrlysMark()
                .frame(width: 24, height: 24)
            Text(verbatim: "Fyrlys")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fyrlys-merke")
    }
}

/// Sol eller måne: lys eller mørk (lagret som valget i innstillingene).
struct MacThemeButton: View {
    @AppStorage(Appearance.key, store: TestSupport.defaults) private var stored = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            stored = scheme == .dark ? "light" : "dark"
        } label: {
            Image(systemName: scheme == .dark ? "sun.max" : "moon")
        }
        .help(scheme == .dark ? L("Lys") : L("Mørk"))
        .accessibilityIdentifier("tema")
    }
}
#endif

#if os(macOS)
/// Ingen tittel i verktøylinja (merket står der i stedet).
struct NoWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
    }
}
#endif
