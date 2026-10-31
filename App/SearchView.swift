import FyrlysCore
import SwiftUI

/// Søk i kanalnavnene (alle ordene må finnes), med kanalene i «Dine kategorier» først.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    @Binding var query: String

    var body: some View {
        let results = model.search(query, limit: 120)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.gridSpacing + 12) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                        Text(L("Ingen treff."))
                            .font(.system(size: Metrics.pageCount + 8))
                            .foregroundStyle(Theme.muted)
                    }
                    #if os(tvOS)
                    BigCardGrid(channels: results, play: play)
                    #else
                    ChannelGrid(channels: results, play: play)
                    #endif
                }
                #if os(tvOS)
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, 30)
                #else
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                #endif
                .hidesScrollIndex()
            }
            .scrollIndicators(.never)
            #if os(tvOS)
            .safeAreaPadding(.bottom, Theme.bottomFocus)
            // like nær sidene som TV-siden, og helt ned
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            #else
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(L("Søk"))
            #endif
            #if os(iOS)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("Søk etter kanal"))
            #else
            .searchable(text: $query, prompt: L("Søk etter kanal"))
            #endif
        }
    }
}
