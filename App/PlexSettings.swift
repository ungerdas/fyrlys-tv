import FyrlysCore
import SwiftUI

/// Plex i innstillingene (Apple TV og iPad) og i et eget ark fra Konto (iPhone): koble til med en kode på plex.tv/link,
/// velg server, velg bibliotekene i Plex-fanen, og koble fra.
struct PlexSettings: View {
    @Environment(AppModel.self) private var model
    /// valget av bibliotekene som vises
    @State private var libraries = false

    private var plex: PlexModel { model.plex }

    private var pitch: String {
        L("Se filmene og seriene dine fra Plex i en egen fane, Plex.")
    }

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Plex")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content
        }
        .sheet(isPresented: $libraries) {
            PlexLibrariesSheet()
                .environment(model)
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
        .sheet(isPresented: $libraries) {
            PlexLibrariesSheet()
                .environment(model)
        }
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
            // bibliotekene som vises i Plex-fanen (for eksempel uten «Andre videoer»)
            button(L("Biblioteker"), icon: "books.vertical", id: "plex-biblioteker") { libraries = true }
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

/// Hvilke Plex-biblioteker som vises i Plex-fanen: det som slås av, er borte fra sidemenyen, Hjem, «Fortsett å se» og
/// søket (som i Fyrlys for Windows; delt mellom enhetene med iCloud).
struct PlexLibrariesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sections: [PlexSection]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            // Apple TV: bryterne i en rulleliste (fokus står da på bryteren selv, ikke på en celle rundt den)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toggles
                    Text(L("Det du slår av, vises ikke i sidemenyen, på Hjem eller i søket."))
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(40)
            }
            .navigationTitle(L("Biblioteker"))
            #else
            List {
                Section {
                    toggles
                } footer: {
                    Text(L("Det du slår av, vises ikke i sidemenyen, på Hjem eller i søket."))
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Ferdig")) { dismiss() }
                        .accessibilityIdentifier("biblioteker-ferdig")
                }
            }
            .navigationTitle(L("Biblioteker"))
            #endif
        }
        #if os(iOS)
        .tint(Theme.signal)
        #endif
        .accessibilityIdentifier("plex-bibliotekvalg")
        .task { await load() }
    }

    /// Én bryter per bibliotek (på: vises).
    @ViewBuilder
    private var toggles: some View {
        if let sections {
            if sections.isEmpty {
                Text(L("Ingen biblioteker med filmer eller serier."))
            }
            ForEach(sections) { section in
                Toggle(isOn: Binding(get: { !model.isHidden(section.id) },
                                     set: { model.setHidden(section.id, !$0) })) {
                    Label(section.name, systemImage: section.kind == .movies ? "film" : "tv")
                }
                .accessibilityIdentifier("vis-bibliotek-\(section.id)")
            }
        } else if failed {
            Text(L("Får ikke kontakt med Plex-serveren"))
        } else {
            ProgressView()
        }
    }

    private func load() async {
        guard let client = model.plex.client else {
            failed = true
            return
        }
        do {
            sections = try await client.sections()
        } catch {
            failed = true
        }
    }
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

/// Plex Home: «Hvem ser på?» – brukerne på kontoen, med PIN for dem som har det. Den som velges, får sin egen
/// «Fortsett å se», sett/ikke sett og tilgang til bibliotekene sine.
struct PlexUserSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// brukeren som trenger PIN
    @State private var asking: PlexHomeUser?
    @State private var pin = ""
    @State private var error: String?

    private var plex: PlexModel { model.plex }

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(40)
            }
            .navigationTitle(L("Hvem ser på?"))
            #else
            List {
                content
                    .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(L("Hvem ser på?"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Avbryt")) { dismiss() }
                        .accessibilityIdentifier("bruker-avbryt")
                }
            }
            #endif
        }
        #if os(iOS)
        .tint(Theme.signal)
        #endif
        .accessibilityIdentifier("plex-brukere")
    }

    @ViewBuilder
    private var content: some View {
        if let asking {
            Text(L("PIN for {name}", ["name": asking.name]))
                .font(.headline)
            // fire siffer (som PIN-ene i Plex) bytter med en gang; «Bytt» for dem som har lengre
            SecureField(L("PIN"), text: $pin)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: pin) { _, new in
                    if new.count == 4, !plex.switching {
                        self.error = nil
                        Task { await choose(asking, pin: new) }
                    }
                }
                .onSubmit { if !pin.isEmpty { Task { await choose(asking, pin: pin) } } }
                .accessibilityIdentifier("bruker-pin")
            if let error {
                Text(error)
                    .foregroundStyle(Theme.live)
                    .accessibilityIdentifier("bruker-feil")
            }
            Button(L("Bytt")) { Task { await choose(asking, pin: pin) } }
                .disabled(pin.isEmpty || plex.switching)
                .accessibilityIdentifier("bruker-bytt")
            Button(L("Tilbake")) {
                self.asking = nil
                pin = ""
                self.error = nil
            }
        } else {
            ForEach(plex.users) { user in
                Button {
                    if user.protected {
                        asking = user
                    } else {
                        Task { await choose(user, pin: nil) }
                    }
                } label: {
                    HStack(spacing: 14) {
                        RemoteImage(url: user.thumb.flatMap { URL(string: $0) }, fill: true) {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(width: Self.avatar, height: Self.avatar)
                        .clipShape(Circle())
                        Text(user.name)
                        if user.protected {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        if user.id == plex.user?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.signal)
                        }
                    }
                }
                .disabled(plex.switching)
                .accessibilityIdentifier("bruker-\(user.id)")
            }
            if let error {
                Text(error)
                    .foregroundStyle(Theme.live)
                    .accessibilityIdentifier("bruker-feil")
            }
        }
    }

    private func choose(_ user: PlexHomeUser, pin: String?) async {
        do {
            try await plex.switchUser(user, pin: pin)
            dismiss()
        } catch {
            self.error = pin == nil ? error.localizedDescription : L("Feil PIN. Prøv igjen.")
            // feltet tømmes ikke på Apple TV: da lukkes tastaturet, og det som skrives etterpå, kommer ikke fram
            #if os(iOS)
            self.pin = ""
            #endif
        }
    }

    #if os(tvOS)
    static let avatar: CGFloat = 60
    #else
    static let avatar: CGFloat = 36
    #endif
}
