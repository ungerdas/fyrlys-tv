import FyrlysCore
import SwiftUI

/// En kanal som skal spilles, og lista den ble valgt fra (for neste og forrige kanal).
struct PlayRequest: Identifiable {
    let id = UUID()
    let channel: Channel
    let list: [Channel]
    /// Mac: sendingen fra minispilleren, som fortsetter i det store vinduet
    var existing: PlayerModel? = nil
}

/// Fanene øverst (fanelinja til Apple TV): TV, TV-guide, Filmer og Serier (fra IPTV-leverandøren), Plex (når en
/// Plex-server er valgt), Søk og Innstillinger; det samme på iPad. På iPhone som Fyrlys-nettsiden på en telefon
/// (`PhoneHome`, med forsiden og flisene i `PhoneTV`). TV-fanen på Apple TV og iPad er sidemenyen og kortene
/// (`ChannelsView`). Spilleren legger seg over alt.
struct HomeView: View {
    enum Tab: Hashable { case tv, guide, movies, series, plex, search, settings }

    @Environment(AppModel.self) private var model
    #if !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// sidene som er åpnet fra TV-forsiden på iPhone (en kategori)
    @State private var path: [Shelf]
    @State private var tab: Tab
    @State private var playing: PlayRequest?
    @State private var testPlayed = false
    /// det som er valgt i sidemenyen, og søket
    @State private var shelf: Shelf?
    @State private var query = ""
    #if os(macOS)
    /// fanen før søket begynte (Mac: tilbake dit når søkefeltet tømmes)
    @State private var beforeSearch: Tab = .tv
    #endif

    init() {
        switch TestSupport.screen {
        case "guide": _tab = State(initialValue: .guide)
        case "movies": _tab = State(initialValue: .movies)
        case "series": _tab = State(initialValue: .series)
        case "plex", "plex-series", "plex-users", "plex-film", "plex-serie", "plex-ask": _tab = State(initialValue: .plex)
        case "search": _tab = State(initialValue: .search)
        case "settings", "plex-link", "strommer": _tab = State(initialValue: .settings)
        default: _tab = State(initialValue: .tv)
        }
        switch TestSupport.screen {
        case "all":
            _path = State(initialValue: [.all])
            _shelf = State(initialValue: .all)
        case "category":
            _path = State(initialValue: [.category("2")])
            _shelf = State(initialValue: .category("2"))
        default:
            _path = State(initialValue: [])
        }
    }

    var body: some View {
        content
            #if os(tvOS)
            .fullScreenCover(item: archive) { channel in
                ArchiveView(channel: channel)
                    .environment(model)
            }
            #else
            .sheet(item: archive) { channel in
                ArchiveView(channel: channel)
                    .environment(model)
                    .macSheetSize(width: 640, height: 720)
            }
            #endif
            .fullScreenCover(item: $playing, onDismiss: { model.showPendingReplay() }) { request in
                PlayerView(request: request)
                    .environment(model)
                    #if !os(tvOS)
                    // spilleren er alltid mørk, som på nettsiden
                    .preferredColorScheme(.dark)
                    // gjennomsiktig rundt, så TV-siden synes når spilleren dras ned for å lukkes
                    .presentationBackground(.clear)
                    #endif
            }
            // et program fra start (TV-arkivet), fra spilleren eller guiden
            #if !os(iOS)
            .fullScreenCover(item: replay) { play in
                VODPlayerView(play: play)
                    .environment(model)
            }
            #else
            .sheet(item: replay) { play in
                VODPlayerView(play: play)
                    .environment(model)
                    .preferredColorScheme(.dark)
                    .presentationDragIndicator(.visible)
            }
            #endif
            // multiview (fra hurtigmenyen på et kort, eller fra spilleren når den er lukket)
            .fullScreenCover(item: multiview) { request in
                MultiviewView(request: request)
                    .environment(model)
            }
            .onAppear(perform: playForTest)
            .onChange(of: model.channels.count) { playForTest() }
            .onChange(of: model.pendingPlay) { playForTest() }
            #if os(macOS)
            // minispilleren tilbake i vinduet
            .onChange(of: model.reopenPlayer?.id) {
                guard let request = model.reopenPlayer else { return }
                model.reopenPlayer = nil
                playing = request
            }
            #endif
            // Top Shelf: siden for en film eller serie, i fanen den hører til
            .onChange(of: model.pendingVOD?.id, initial: true) {
                guard let item = model.pendingVOD else { return }
                if item.source == "plex" {
                    if model.hasPlex { tab = .plex } else { model.pendingVOD = nil }
                } else if model.hasVOD {
                    tab = item.kind == .movies ? .movies : .series
                } else {
                    model.pendingVOD = nil
                }
            }
            #if os(tvOS)
            // «Fortsett å se» til Top Shelf: også fra Plex, som hentes når Plex er koblet til
            .onChange(of: model.plexVOD.continueRow) { model.shareContinue() }
            .task(id: model.hasPlex) {
                model.shareContinue()
                if model.hasPlex, !TestSupport.isActive { await model.plexVOD.loadCategories() }
            }
            #endif
            // Filmer og Serier ble borte (en annen innlogging med en M3U-liste): tilbake til TV
            .onChange(of: model.hasVOD) { _, has in
                if !has, tab == .movies || tab == .series { tab = .tv }
            }
            // Plex koblet fra: tilbake til TV; testene (plex, plex-series): til Plex-fanen når den kommer
            .onChange(of: model.hasPlex) { _, has in
                if !has, tab == .plex { tab = .tv }
                if has, ["plex", "plex-series", "plex-users", "plex-film", "plex-serie", "plex-ask"].contains(TestSupport.screen ?? "") { tab = .plex }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macHome
        #elseif os(iOS)
        if usesPhoneLayout(sizeClass) {
            PhoneHome(tab: $tab, path: $path, query: $query, play: play)
        } else if #available(iOS 18.0, *) {
            iPadTabs
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            tvTab
                .tabItem { tabLabel(L("TV"), "tv") }
                .tag(Tab.tv)
            GuideView(play: play)
                .tabItem { tabLabel(L("TV-guide"), "calendar.day.timeline.left") }
                .tag(Tab.guide)
            // en M3U-liste har ikke filmer og serier
            if model.hasVOD {
                VODTab(kind: .movies)
                    .tabItem { tabLabel(L("Filmer"), "film") }
                    .tag(Tab.movies)
                VODTab(kind: .series)
                    .tabItem { tabLabel(L("Serier"), "play.rectangle.on.rectangle") }
                    .tag(Tab.series)
            }
            // filmene og seriene fra Plex sammen
            if model.hasPlex {
                VODTab(kind: nil)
                    .tabItem { tabLabel("Plex", "film.stack") }
                    .tag(Tab.plex)
            }
            SearchView(play: play, query: $query)
                .tabItem {
                    #if os(tvOS)
                    Image(systemName: "magnifyingglass").accessibilityLabel(L("Søk"))
                    #else
                    Label(L("Søk"), systemImage: "magnifyingglass")
                    #endif
                }
                .tag(Tab.search)
            SettingsView()
                .tabItem { tabLabel(L("Innstillinger"), "gearshape") }
                .tag(Tab.settings)
        }
        #if !os(tvOS)
        .tint(Theme.signal)
        #endif
    }

    private var replay: Binding<VODPlay?> {
        Binding(get: { model.replay }, set: { model.replay = $0 })
    }

    private var multiview: Binding<MultiviewRequest?> {
        Binding(get: { model.multiview }, set: { model.multiview = $0 })
    }

    #if os(macOS)
    /// Mac: som toppen i Fyrlys for Windows, i verktøylinja til vinduet: merket, seksjonene, søket, lys/mørk og
    /// innstillingene. Siden under byttes (ingen TabView).
    private var macHome: some View {
        macPage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .modifier(NoWindowTitle())
            .toolbarBackground(Theme.bg, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    MacBrand()
                }
                ToolbarItem(placement: .principal) {
                    Picker(selection: macSection) {
                        Text(L("TV")).tag(Tab.tv)
                        Text(L("TV-guide")).tag(Tab.guide)
                        if model.hasVOD {
                            Text(L("Filmer")).tag(Tab.movies)
                            Text(L("Serier")).tag(Tab.series)
                        }
                        if model.hasPlex {
                            Text(verbatim: "Plex").tag(Tab.plex)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("seksjoner")
                }
                ToolbarItem(placement: .primaryAction) {
                    SearchField(text: $query, findTarget: true)
                        .frame(width: 260)
                }
                ToolbarItem(placement: .primaryAction) {
                    MacThemeButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        tab = tab == .settings ? beforeSearch : .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help(L("Innstillinger"))
                    .accessibilityIdentifier("innstillinger-knapp")
                }
            }
            // søket i verktøylinja: treffene mens det står noe der, så tilbake dit du var
            .onChange(of: query) { _, text in
                if !text.isEmpty, tab != .search {
                    beforeSearch = tab
                    tab = .search
                } else if text.isEmpty, tab == .search {
                    tab = beforeSearch
                }
            }
            .onChange(of: tab) { old, new in
                if new == .settings, old != .search { beforeSearch = old }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fyrlysOpenSettings)) { _ in
                tab = .settings
            }
            // ⌘1–5: TV, TV-guide, Filmer, Serier, Plex (når de finnes)
            .onReceive(NotificationCenter.default.publisher(for: .fyrlysSection)) { note in
                guard let number = note.object as? Int else { return }
                let all: [Tab] = [.tv, .guide, .movies, .series, .plex]
                guard number >= 1, number <= all.count else { return }
                let wanted = all[number - 1]
                if wanted == .movies || wanted == .series, !model.hasVOD { return }
                if wanted == .plex, !model.hasPlex { return }
                macSection.wrappedValue = wanted
            }
    }

    /// Seksjonen som er valgt øverst (søket og innstillingene er ikke seksjoner: da står den forrige valgt).
    private var macSection: Binding<Tab> {
        Binding(get: { tab == .search || tab == .settings ? beforeSearch : tab },
                set: { new in
                    query = ""
                    tab = new
                })
    }

    @ViewBuilder
    private var macPage: some View {
        switch tab {
        case .tv: tvTab
        case .guide: GuideView(play: play)
        case .movies: VODTab(kind: .movies)
        case .series: VODTab(kind: .series)
        case .plex: VODTab(kind: nil)
        case .search: SearchView(play: play, query: $query)
        case .settings: SettingsView()
        }
    }
    #endif

    /// TV-arkivet for kanalen som er valgt i hurtigmenyen på et kort.
    private var archive: Binding<Channel?> {
        Binding(get: { model.archiveChannel }, set: { model.archiveChannel = $0 })
    }

    /// TV-fanen på Apple TV og iPad: sidemenyen og kortene.
    private var tvTab: some View {
        ChannelsView(play: play, chosen: $shelf)
    }

    #if os(iOS)
    /// iPad (iPadOS 18): Søk og Innstillinger som ikoner til høyre, så alle fanene får plass på høykant (med sju
    /// faner sto Innstillinger bak en pil).
    @available(iOS 18.0, *)
    private var iPadTabs: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab(L("TV"), systemImage: "tv", value: Tab.tv) { tvTab }
            SwiftUI.Tab(L("TV-guide"), systemImage: "calendar.day.timeline.left", value: Tab.guide) {
                GuideView(play: play)
            }
            if model.hasVOD {
                SwiftUI.Tab(L("Filmer"), systemImage: "film", value: Tab.movies) { VODTab(kind: .movies) }
                SwiftUI.Tab(L("Serier"), systemImage: "play.rectangle.on.rectangle", value: Tab.series) {
                    VODTab(kind: .series)
                }
            }
            if model.hasPlex {
                SwiftUI.Tab("Plex", systemImage: "film.stack", value: Tab.plex) { VODTab(kind: nil) }
            }
            SwiftUI.Tab(value: Tab.settings) {
                SettingsView()
            } label: {
                Label(L("Innstillinger"), systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            SwiftUI.Tab(value: Tab.search, role: .search) {
                SearchView(play: play, query: $query)
            }
        }
        .tint(Theme.signal)
    }
    #endif

    /// Fanene: bare tekst på Apple TV (som fanelinja der), ikon og tekst nederst på iPhone og iPad.
    @ViewBuilder
    private func tabLabel(_ title: String, _ icon: String) -> some View {
        #if os(tvOS)
        Text(title)
        #else
        Label(title, systemImage: icon)
        #endif
    }

    private func play(_ channel: Channel, _ list: [Channel]) {
        #if os(macOS)
        // én sending om gangen (leverandøren gir ofte bare én tilkobling)
        MacMiniPlayer.close()
        #endif
        playing = PlayRequest(channel: channel, list: list.isEmpty ? [channel] : list)
    }

    /// Testene: rett til spilleren (player: den første kanalen, player-error: en kanal som ikke virker).
    private func playForTest() {
        // kanalen Top Shelf ba om
        if let id = model.pendingPlay, let channel = model.byId[id] {
            model.pendingPlay = nil
            let favorites = model.favorites
            play(channel, favorites.contains(channel) ? favorites : model.channels)
            return
        }
        guard !testPlayed, let screen = TestSupport.screen, !model.channels.isEmpty else { return }
        if screen == "archive", let channel = model.byId["1"] {
            testPlayed = true
            model.archiveChannel = channel
            return
        }
        // multiview med kanal 1 i det første bildet
        if screen == "multiview", let first = model.byId["1"] {
            testPlayed = true
            model.multiview = MultiviewRequest(channel: first)
            return
        }
        // filmen i mkv (VLC), med to lydspor og norske undertekster; mkv-feil: en film leverandøren ikke har
        if screen == "mkv" || screen == "mkv-feil", let client = model.client {
            testPlayed = true
            let id = screen == "mkv" ? "502" : "504"
            model.replay = VODPlay(id: "test-\(id)", urls: [client.movieURL(id, ext: screen == "mkv" ? "mkv" : "avi")],
                                   title: "Stormnatt (2019)", subtitle: "", progressKey: "movies:\(id)", start: 0)
            return
        }
        guard screen.hasPrefix("player") else { return }
        let channel = screen == "player-error" ? model.byId["90"] : model.channels.first
        guard let channel else { return }
        testPlayed = true
        play(channel, model.channels)
    }
}

#if !os(tvOS)
/// Oppsettet for telefon: alltid på iPhone, og på iPad når appen er smal (delt skjerm). Ikke bare etter bredden: de
/// store iPhonene (Pro Max, Plus, Air) har vanlig bredde på tvers, og da byttet hele oppsettet når telefonen ble lagt
/// ned, så arket med filmen (og siden den var åpnet fra) ble borte (0.1.19–0.1.21: «tuller med å legge seg ned»).
func usesPhoneLayout(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
    #if os(macOS)
    // Mac: alltid sidemenyen og kortene (som Fyrlys for Windows), også i et smalt vindu
    false
    #else
    UIDevice.current.userInterfaceIdiom == .phone || sizeClass == .compact
    #endif
}
#endif
