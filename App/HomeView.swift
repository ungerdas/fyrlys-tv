import FyrlysCore
import SwiftUI

/// En kanal som skal spilles, og lista den ble valgt fra (for neste og forrige kanal).
struct PlayRequest: Identifiable {
    let id = UUID()
    let channel: Channel
    let list: [Channel]
}

/// Fanene øverst (fanelinja til Apple TV): TV, TV-guide, Søk og Innstillinger; det samme på iPad. På iPhone som
/// Fyrlys-nettsiden på en telefon (`PhoneHome`, med forsiden og flisene i `PhoneTV`). TV-fanen på Apple TV og iPad er
/// sidemenyen og kortene (`ChannelsView`). Spilleren legger seg over alt.
struct HomeView: View {
    enum Tab: Hashable { case tv, guide, movies, series, search, settings }

    @Environment(AppModel.self) private var model
    #if os(iOS)
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

    init() {
        switch TestSupport.screen {
        case "guide": _tab = State(initialValue: .guide)
        case "movies": _tab = State(initialValue: .movies)
        case "series": _tab = State(initialValue: .series)
        case "search": _tab = State(initialValue: .search)
        case "settings": _tab = State(initialValue: .settings)
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
            }
            #endif
            .fullScreenCover(item: $playing) { request in
                PlayerView(request: request)
                    .environment(model)
                    #if os(iOS)
                    // spilleren er alltid mørk, som på nettsiden
                    .preferredColorScheme(.dark)
                    // gjennomsiktig rundt, så TV-siden synes når spilleren dras ned for å lukkes
                    .presentationBackground(.clear)
                    #endif
            }
            .onAppear(perform: playForTest)
            .onChange(of: model.channels.count) { playForTest() }
            .onChange(of: model.pendingPlay) { playForTest() }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if sizeClass == .compact {
            PhoneHome(tab: $tab, path: $path, query: $query, play: play)
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
            VODTab(kind: .movies)
                .tabItem { tabLabel(L("Filmer"), "film") }
                .tag(Tab.movies)
            VODTab(kind: .series)
                .tabItem { tabLabel(L("Serier"), "play.rectangle.on.rectangle") }
                .tag(Tab.series)
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
        #if os(iOS)
        .tint(Theme.signal)
        #endif
    }

    /// TV-arkivet for kanalen som er valgt i hurtigmenyen på et kort.
    private var archive: Binding<Channel?> {
        Binding(get: { model.archiveChannel }, set: { model.archiveChannel = $0 })
    }

    /// TV-fanen på Apple TV og iPad: sidemenyen og kortene.
    private var tvTab: some View {
        ChannelsView(play: play, chosen: $shelf)
    }

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
        guard screen.hasPrefix("player") else { return }
        let channel = screen == "player-error" ? model.byId["90"] : model.channels.first
        guard let channel else { return }
        testPlayed = true
        play(channel, model.channels)
    }
}
