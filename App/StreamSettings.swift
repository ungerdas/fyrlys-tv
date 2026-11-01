import FyrlysCore
import SwiftUI

/// Egne strømmer i innstillingene: adresser (m3u8) som spilles i stedet for leverandørens for kanalene de gjelder.
/// Kanalen finnes ut fra navnet i adressen («…/nrk1/muxed.m3u8» er NRK1), eller «Kanalnavn = adresse». Linjene deles
/// med iCloud, så det holder å lime dem inn på iPhone eller iPad; Apple TV viser dem og kan legge til én om gangen.
struct StreamSettings: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var matches: [String: [String]] = [:]
    #if os(tvOS)
    @State private var newLine = ""
    #endif

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Egne strømmer"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(help)
                .font(.system(size: 24))
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: 760, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            list
            TextField(L("Legg til: adresse, eller kanalnavn = adresse"), text: $newLine)
                .frame(maxWidth: 760)
                .onSubmit {
                    guard !newLine.isEmpty else { return }
                    model.setStreams((model.streamLines + [newLine]).joined(separator: "\n"))
                    newLine = ""
                }
                .accessibilityIdentifier("ny-strom")
            if !model.streamLines.isEmpty {
                Button(role: .destructive) {
                    model.setStreams("")
                } label: {
                    Label(L("Fjern alle egne strømmer"), systemImage: "trash")
                        .frame(minWidth: 520, alignment: .leading)
                }
            }
        }
        .task(id: model.streamLines) { matches = await model.streamMatches() }
        .task(id: model.channels.count) { matches = await model.streamMatches() }
        #else
        Section {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .accessibilityIdentifier("egne-strommer-tekst")
            Button(L("Lagre")) { model.setStreams(text) }
                .disabled(text == model.streamLines.joined(separator: "\n"))
                .accessibilityIdentifier("lagre-strommer")
            list
        } header: {
            Text(L("Egne strømmer"))
        } footer: {
            Text(help)
        }
        .listRowBackground(Theme.surface)
        .onAppear { text = model.streamLines.joined(separator: "\n") }
        .task(id: model.streamLines) { matches = await model.streamMatches() }
        .task(id: model.channels.count) { matches = await model.streamMatches() }
        #endif
    }

    private var help: String {
        L("Adresser (m3u8) som spilles i stedet for leverandørens, én per linje. Kanalen finnes ut fra navnet i adressen (…/nrk1/… er NRK1), eller skriv «Kanalnavn = adresse». De deles med iCloud.")
    }

    /// Hver egen strøm og kanalene den gjelder for.
    @ViewBuilder
    private var list: some View {
        ForEach(model.streamOverrides, id: \.key) { stream in
            let found = matches[stream.key] ?? []
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: stream.url.host ?? stream.url.absoluteString)
                    .font(.system(size: Self.small))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text(found.isEmpty ? L("Fant ingen kanal for «{key}»", ["key": stream.key])
                     : found.count == 1 ? found[0]
                     : L("{first} og {n} til", ["first": found[0], "n": found.count - 1]))
                    .font(.system(size: Self.normal, weight: .semibold))
                    .foregroundStyle(found.isEmpty ? Theme.live : Theme.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("egen-strom-\(stream.key)")
        }
    }

    #if os(tvOS)
    static let small: CGFloat = 20
    static let normal: CGFloat = 26
    #else
    static let small: CGFloat = 12
    static let normal: CGFloat = 15
    #endif
}

#if os(iOS)
/// iPhone: egne strømmer i et eget ark (fra Konto).
struct StreamSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                StreamSettings()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(L("Egne strømmer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Ferdig")) { dismiss() }
                }
            }
        }
    }
}
#endif
