import FyrlysCore
import SwiftUI

/// En kanal som skal spilles, og lista den ble valgt fra (for neste og forrige kanal).
struct PlayRequest: Identifiable {
    let id = UUID()
    let channel: Channel
    let list: [Channel]
}

/// Fanene øverst (fanelinja til Apple TV): TV, TV-guide, Søk og Innstillinger. Spilleren legger seg over alt.
struct HomeView: View {
    enum Tab: Hashable { case tv, guide, search, settings }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab
    @State private var playing: PlayRequest?
    @State private var testPlayed = false
    /// det som er valgt i sidemenyen, og søket
    @State private var shelf: Shelf?
    @State private var query = ""

    init() {
        switch TestSupport.screen {
        case "guide": _tab = State(initialValue: .guide)
        case "search": _tab = State(initialValue: .search)
        case "settings": _tab = State(initialValue: .settings)
        default: _tab = State(initialValue: .tv)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            ChannelsView(play: play, chosen: $shelf)
                .tabItem { Text(L("TV")) }
                .tag(Tab.tv)
            GuideView(play: play)
                .tabItem { Text(L("TV-guide")) }
                .tag(Tab.guide)
            SearchView(play: play, query: $query)
                .tabItem { Image(systemName: "magnifyingglass").accessibilityLabel(L("Søk")) }
                .tag(Tab.search)
            SettingsView()
                .tabItem { Text(L("Innstillinger")) }
                .tag(Tab.settings)
        }
        .fullScreenCover(item: $playing) { request in
            PlayerView(request: request)
                .environment(model)
        }
        .onAppear(perform: playForTest)
        .onChange(of: model.channels.count) { playForTest() }
    }

    private func play(_ channel: Channel, _ list: [Channel]) {
        playing = PlayRequest(channel: channel, list: list.isEmpty ? [channel] : list)
    }

    /// Testene: rett til spilleren (player: den første kanalen, player-error: en kanal som ikke virker).
    private func playForTest() {
        guard !testPlayed, let screen = TestSupport.screen, screen.hasPrefix("player"), !model.channels.isEmpty else {
            return
        }
        let channel = screen == "player-error" ? model.byId["90"] : model.channels.first
        guard let channel else { return }
        testPlayed = true
        play(channel, model.channels)
    }
}
