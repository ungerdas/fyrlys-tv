import FyrlysCore
import SwiftUI

/// Innlogging med Xtream Codes: server, brukernavn og passord. Side om side på Apple TV, under hverandre på iPhone og
/// iPad.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
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
                Text(L("Innloggingen fra IPTV-leverandøren din (Xtream Codes). Den lagres kryptert på Apple TV-en."))
                #else
                Text(L("Innloggingen fra IPTV-leverandøren din (Xtream Codes). Den lagres kryptert på denne enheten."))
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
            TextField(L("Server"), text: $server, prompt: Text(verbatim: "http://iptv.example.com:8080"))
                .keyboardType(.URL)
                .textContentType(.URL)
            TextField(L("Brukernavn"), text: $username)
                .textContentType(.username)
            SecureField(L("Passord"), text: $password)
                .textContentType(.password)
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
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                #endif
            }
            #if os(iOS)
            .buttonStyle(.borderedProminent)
            .tint(Theme.signal)
            #endif
            .disabled(busy)
            .accessibilityIdentifier("logg-inn")
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func submit() async {
        guard !server.trimmingCharacters(in: .whitespaces).isEmpty, !username.isEmpty, !password.isEmpty else {
            error = L("Fyll inn server, brukernavn og passord.")
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.signIn(server: server, username: username, password: password)
        } catch {
            self.error = (error as? SourceError)?.message ?? error.localizedDescription
        }
    }
}
