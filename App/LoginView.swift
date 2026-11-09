import FyrlysCore
import SwiftUI

/// Innloggingen: Xtream Codes (server, brukernavn og passord) eller en M3U-lenke (og eventuelt en lenke til
/// TV-guiden), som i Fyrlys for Windows. Side om side på Apple TV, under hverandre på iPhone og iPad.
struct LoginView: View {
    enum Kind: Hashable { case xtream, m3u }

    @Environment(AppModel.self) private var model
    @State private var kind: Kind = TestSupport.screen == "login-m3u" ? .m3u : .xtream
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var link = ""
    @State private var epg = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        #if os(tvOS)
        HStack(alignment: .center, spacing: 100) {
            intro(mark: 180, title: 84, text: 30)
                .frame(width: 640, alignment: .leading)
            form(heading: 44, text: 26)
                .frame(width: 820)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("innlogging")
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                intro(mark: 72, title: 40, text: 16)
                form(heading: 24, text: 14)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // det som rulles forbi, går ikke opp under klokka
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("innlogging")
        #endif
    }

    private func intro(mark: CGFloat, title: CGFloat, text: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: text * 0.9) {
            FyrlysMark()
                .frame(width: mark)
            Text(verbatim: "Fyrlys")
                .font(.system(size: title, weight: .bold))
            Group {
                #if os(tvOS)
                Text(L("Innloggingen fra IPTV-leverandøren din: Xtream Codes eller en M3U-lenke. Den lagres kryptert på Apple TV-en."))
                #else
                Text(L("Innloggingen fra IPTV-leverandøren din: Xtream Codes eller en M3U-lenke. Den lagres kryptert på denne enheten."))
                #endif
            }
                .font(.system(size: text))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func form(heading: CGFloat, text: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: heading * 0.68) {
            Text(L("Logg inn"))
                .font(.system(size: heading, weight: .bold))
            Picker(L("Slag innlogging"), selection: $kind) {
                Text(verbatim: "Xtream Codes").tag(Kind.xtream)
                Text(L("M3U-lenke")).tag(Kind.m3u)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("innloggingstype")
            .onChange(of: kind) { error = nil }
            if kind == .xtream {
                hint(L("Innloggingen du har fått fra IPTV-leverandøren (Xtream Codes)."), size: text)
                TextField(L("Server"), text: $server, prompt: Text(verbatim: "http://iptv.example.com:8080"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .accessibilityIdentifier("server")
                TextField(L("Brukernavn"), text: $username)
                    .textContentType(.username)
                    .accessibilityIdentifier("brukernavn")
                SecureField(L("Passord"), text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("passord")
            } else {
                hint(L("Lenken til kanallista fra leverandøren. Er det en Xtream-lenke (get.php med brukernavn og passord), får du også filmer og serier."),
                     size: text)
                TextField(L("M3U-lenke"), text: $link,
                          prompt: Text(verbatim: "http://iptv.example.com:8080/get.php?…"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .accessibilityIdentifier("m3u-lenke")
                TextField(L("EPG-lenke (valgfri)"), text: $epg, prompt: Text(L("XMLTV, .xml eller .xml.gz")))
                    .keyboardType(.URL)
                    .accessibilityIdentifier("epg-lenke")
                hint(L("Står den tom, brukes EPG-lenken i lista"), size: text)
            }
            if let error {
                Text(error)
                    .font(.system(size: text))
                    .foregroundStyle(Theme.live)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("innlogging-feil")
            }
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 16) {
                    if busy { ProgressView() }
                    Text(busy ? L("Logger inn …") : L("Logg inn"))
                }
                #if os(tvOS)
                .frame(minWidth: 300)
                #else
                .font(.headline)
                .foregroundStyle(Theme.signalInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                #endif
            }
            #if !os(tvOS)
            .buttonStyle(.borderedProminent)
            .tint(Theme.signal)
            #endif
            .disabled(busy)
            .accessibilityIdentifier("logg-inn")
            if model.addingLogin {
                Button(L("Avbryt")) { model.addingLogin = false }
                    #if os(tvOS)
                    .frame(minWidth: 300)
                    #endif
                    .accessibilityIdentifier("avbryt-innlogging")
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func hint(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size * 0.85))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() async {
        if kind == .xtream {
            guard !server.trimmingCharacters(in: .whitespaces).isEmpty, !username.isEmpty, !password.isEmpty else {
                error = L("Fyll inn server, brukernavn og passord.")
                return
            }
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if kind == .xtream {
                try await model.signIn(server: server, username: username, password: password)
            } else {
                try await model.signIn(m3u: link, epg: epg)
            }
        } catch {
            // noe uventet (en adresse som ikke lar seg tolke): en forklaring, ikke en teknisk feil
            self.error = (error as? SourceError)?.message ?? L("Kunne ikke koble til. Sjekk lenken eller adressen.")
        }
    }
}
