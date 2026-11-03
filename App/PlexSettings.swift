import FyrlysCore
import SwiftUI

/// Plex i innstillingene (Apple TV og iPad) og i et eget ark fra Konto (iPhone): koble til med en kode på plex.tv/link,
/// velg server, velg om Filmer og Serier skal komme fra Plex, og koble fra.
struct PlexSettings: View {
    @Environment(AppModel.self) private var model

    private var plex: PlexModel { model.plex }

    private var pitch: String {
        L("Se filmene og seriene dine fra Plex i fanene Filmer og Serier, i stedet for dem fra IPTV-leverandøren.")
    }

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Plex")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content
        }
        #else
        Section {
            content
        } header: {
            Text(verbatim: "Plex")
        } footer: {
            if plex.phase == .off {
                Text(pitch)
            }
        }
        .listRowBackground(Theme.surface)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch plex.phase {
        case .off:
            #if os(tvOS)
            info(pitch)
            #endif
            button(L("Koble til Plex"), icon: "link", id: "koble-til-plex") { plex.link() }
        case .linking(let code):
            info(L("Gå til plex.tv/link på telefonen eller PC-en, logg inn og skriv inn koden:"))
            HStack(spacing: 24) {
                Text(verbatim: code)
                    .font(.system(size: Self.codeSize, weight: .bold, design: .monospaced))
                    .tracking(Self.codeSize / 5)
                    .foregroundStyle(Theme.signal)
                    .accessibilityIdentifier("plex-kode")
                ProgressView()
            }
            button(L("Avbryt"), icon: "xmark", id: "avbryt-plex") { plex.cancelLink() }
        case .connecting:
            HStack(spacing: 16) {
                ProgressView()
                info(L("Kobler til Plex …"))
            }
        case .choosing:
            info(L("Velg Plex-serveren:"))
            ForEach(plex.servers) { server in
                button(server.name, icon: "server.rack", id: "plex-server-\(server.id)") { plex.use(server) }
            }
            button(L("Koble fra Plex"), icon: "xmark", id: "koble-fra-plex", role: .destructive) { plex.disconnect() }
        case .connected:
            info(L("Koblet til {server}", ["server": plex.server?.name ?? "Plex"]))
                .accessibilityIdentifier("plex-tilkoblet")
            #if os(tvOS)
            button(plex.useForVOD ? L("Filmer og serier fra: Plex") : L("Filmer og serier fra: IPTV-leverandøren"),
                   icon: "film", id: "vod-kilde") { plex.useForVOD.toggle() }
            #else
            Picker(L("Filmer og serier fra"), selection: Binding(get: { plex.useForVOD },
                                                                set: { plex.useForVOD = $0 })) {
                Text(verbatim: "Plex").tag(true)
                Text(L("IPTV-leverandøren")).tag(false)
            }
            .accessibilityIdentifier("vod-kilde")
            #endif
            if plex.servers.count > 1 {
                button(L("Bytt server"), icon: "server.rack", id: "bytt-plex-server") { plex.chooseServer() }
            }
            button(L("Koble fra Plex"), icon: "xmark", id: "koble-fra-plex", role: .destructive) { plex.disconnect() }
        case .failed(let message):
            info(message)
            button(L("Prøv igjen"), icon: "arrow.clockwise", id: "plex-igjen") { plex.retry() }
            button(L("Koble fra Plex"), icon: "xmark", id: "koble-fra-plex", role: .destructive) { plex.disconnect() }
        }
    }

    private func info(_ text: String) -> some View {
        #if os(tvOS)
        Text(text)
            .font(.system(size: 28))
            .foregroundStyle(Theme.ink2)
            .frame(maxWidth: 760, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        #else
        Text(text)
            .foregroundStyle(Theme.ink2)
        #endif
    }

    private func button(_ title: String, icon: String, id: String, role: ButtonRole? = nil,
                        action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        // uten rolle på Apple TV: en rød knapp fikk rød tekst og var nesten ikke til å lese; rød tekst i stedet
        return Button(action: action) {
            if role == .destructive {
                Label(title, systemImage: icon)
                    .foregroundStyle(Theme.live)
                    .frame(minWidth: 520, alignment: .leading)
            } else {
                Label(title, systemImage: icon)
                    .frame(minWidth: 520, alignment: .leading)
            }
        }
        .accessibilityIdentifier(id)
        #else
        return Button(role: role, action: action) {
            Label(title, systemImage: icon)
        }
        // ikonet i samme røde som teksten (ellers fikk det aksentfargen)
        .tint(role == .destructive ? Color.red : nil)
        .accessibilityIdentifier(id)
        #endif
    }

    #if os(tvOS)
    static let codeSize: CGFloat = 64
    #else
    static let codeSize: CGFloat = 34
    #endif
}

#if os(iOS)
/// iPhone: Plex i et eget ark (fra Konto).
struct PlexSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                PlexSettings()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(Text(verbatim: "Plex"))
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
