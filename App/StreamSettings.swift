import FyrlysCore
import SwiftUI

/// Egne strømmer i innstillingene: adresser (m3u8) som spilles i stedet for leverandørens for kanalene de gjelder.
/// Kanalen finnes ut fra navnet i adressen («…/nrk1/muxed.m3u8» er NRK1), eller «Kanalnavn = adresse». Linjene deles
/// med iCloud, så det holder å lime dem inn på iPhone eller iPad; Apple TV viser dem og kan legge til én om gangen.
struct StreamSettings: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    /// kanalene hver strøm gjelder for (fra indeksen)
    private var matches: [String: [String]] { model.streamMatches }
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
            Button {
                model.liveShift.toggle()
            } label: {
                Label(model.liveShift ? L("Pause og spoling i direktesending: på")
                      : L("Pause og spoling i direktesending: av"), systemImage: "gobackward")
                    .frame(minWidth: 520, alignment: .leading)
            }
            .accessibilityIdentifier("tilbakespoling")
            Button {
                model.useBuiltInStreams.toggle()
            } label: {
                Label(model.useBuiltInStreams ? L("NRK direkte: på") : L("NRK direkte: av"),
                      systemImage: "antenna.radiowaves.left.and.right")
                    .frame(minWidth: 520, alignment: .leading)
            }
            .accessibilityIdentifier("nrk-direkte")
            if model.useBuiltInStreams { rows(builtInStreams) }
            rows(model.streamOverrides)
            TextField(L("Legg til: adresse, eller kanalnavn = adresse"), text: $newLine)
                .frame(maxWidth: 760)
                .onSubmit {
                    guard !newLine.isEmpty else { return }
                    model.setStreams((model.streamLines + [newLine]).joined(separator: "\n"))
                    newLine = ""
                }
                .accessibilityIdentifier("ny-strom")
            if !model.streamLines.isEmpty {
                Button {
                    model.setStreams("")
                } label: {
                    // rød tekst, ikke rød knapp (den hadde rød tekst på rødt på Apple TV)
                    Label(L("Fjern alle egne strømmer"), systemImage: "trash")
                        .foregroundStyle(Theme.live)
                        .frame(minWidth: 520, alignment: .leading)
                }
            }
        }
        #else
        Section {
            Toggle(L("Pause og spoling i direktesending"),
                   isOn: Binding(get: { model.liveShift }, set: { model.liveShift = $0 }))
                .accessibilityIdentifier("tilbakespoling")
        } header: {
            Text(L("Direktesending"))
        } footer: {
            Text(L("Fyrlys tar vare på den siste halvtimen av kanalen du ser på, så du kan pause og spole tilbake. Slå det av hvis en kanal ikke vil spille."))
        }
        .listRowBackground(Theme.surface)
        Section {
            Toggle(L("NRK1, NRK2, NRK3 og NRK Super direkte"),
                   isOn: Binding(get: { model.useBuiltInStreams }, set: { model.useBuiltInStreams = $0 }))
                .accessibilityIdentifier("nrk-direkte")
            if model.useBuiltInStreams { rows(builtInStreams) }
        } header: {
            Text(L("NRK direkte"))
        } footer: {
            Text(L("Innebygd i Fyrlys: NRK-kanalene spilles direkte i stedet for fra leverandøren."))
        }
        .listRowBackground(Theme.surface)
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
            rows(model.streamOverrides)
        } header: {
            Text(L("Egne strømmer"))
        } footer: {
            Text(help)
        }
        .listRowBackground(Theme.surface)
        .onAppear { text = model.streamLines.joined(separator: "\n") }
        #endif
    }

    private var help: String {
        L("Adresser (m3u8) som spilles i stedet for leverandørens, én per linje. Kanalen finnes ut fra navnet i adressen (…/nrk1/… er NRK1), eller skriv «Kanalnavn = adresse». De deles med iCloud.")
    }

    /// Hver strøm og kanalene den gjelder for.
    @ViewBuilder
    private func rows(_ streams: [StreamOverride]) -> some View {
        ForEach(streams, id: \.key) { stream in
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

#if !os(tvOS)
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
        // arket vises fra topplinja, utenfor fanene (der fargen er satt)
        .tint(Theme.signal)
    }
}
#endif
