import FyrlysCore
import SwiftUI

/// Søk i kanalnavnene (alle ordene må finnes).
struct SearchView: View {
    @Environment(AppModel.self) private var model
    let play: (Channel, [Channel]) -> Void
    @State private var query = ""

    var body: some View {
        let results = FyrlysCore.search(query, in: model.channels, limit: 120)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                        Text(L("Ingen treff."))
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.muted)
                    }
                    ChannelGrid(channels: results, play: play)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
            .searchable(text: $query, prompt: L("Søk etter kanal"))
        }
    }
}
