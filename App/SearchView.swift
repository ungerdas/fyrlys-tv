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
                    BigCardGrid(channels: results, columns: nil, play: play)
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
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L("Søk"))
            #endif
            #if !os(tvOS)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("Søk etter kanal"))
            #else
            .searchable(text: $query, prompt: L("Søk etter kanal"))
            #endif
        }
    }
}

#if !os(tvOS)
/// Søkefeltet øverst på TV-siden (og i Filmer og Serier).
struct SearchField: View {
    @Binding var text: String
    var prompt = L("Søk etter kanal")
    var id = "sok"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.muted))
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(id)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Tøm søket"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
#endif
