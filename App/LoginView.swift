import FyrlysCore
import SwiftUI

/// Innlogging med Xtream Codes: server, brukernavn og passord.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        HStack(alignment: .center, spacing: 100) {
            VStack(alignment: .leading, spacing: 28) {
                FyrlysMark()
                    .frame(width: 180)
                Text(verbatim: "Fyrlys")
                    .font(.system(size: 84, weight: .bold))
                Text(L("Innloggingen fra IPTV-leverandøren din (Xtream Codes). Den lagres kryptert på Apple TV-en."))
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 640, alignment: .leading)

            VStack(alignment: .leading, spacing: 30) {
                Text(L("Logg inn"))
                    .font(.system(size: 44, weight: .bold))
                TextField(L("Server"), text: $server, prompt: Text(verbatim: "http://iptv.example.com:8080"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                TextField(L("Brukernavn"), text: $username)
                    .textContentType(.username)
                SecureField(L("Passord"), text: $password)
                    .textContentType(.password)
                if let error {
                    Text(error)
                        .font(.system(size: 26))
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
                    .frame(minWidth: 300)
                }
                .disabled(busy)
                .accessibilityIdentifier("logg-inn")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(width: 820)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("innlogging")
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
