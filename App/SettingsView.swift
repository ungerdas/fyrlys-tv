#if os(tvOS)
import FyrlysCore
import SwiftUI

/// Innstillinger: abonnementet, hent listene på nytt, logg ut, og versjonen.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        HStack(alignment: .top, spacing: 100) {
            VStack(alignment: .leading, spacing: 24) {
                FyrlysMark()
                    .frame(width: 200)
                Text(verbatim: "Fyrlys")
                    .font(.system(size: 64, weight: .bold))
                Text(L("Versjon {version}", ["version": appVersion]))
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: 420, alignment: .leading)

            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Abonnement"))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    if let login = model.login {
                        row(L("Innlogget som {user}", ["user": login.label]))
                    }
                    if let account = model.account {
                        if let expires = account.expires {
                            row(L("Aktiv til {date}", ["date": longDate(expires)]))
                        }
                        if account.maxConnections > 0 {
                            row(account.maxConnections == 1 ? L("1 tilkobling")
                                : L("{n} tilkoblinger", ["n": account.maxConnections]))
                        }
                    }
                    row(L("{n} kanaler i {c} kategorier", ["n": model.channels.count, "c": model.categories.count]))
                }

                VStack(alignment: .leading, spacing: 24) {
                    Button {
                        Task { await model.reload() }
                    } label: {
                        HStack(spacing: 16) {
                            if model.loading { ProgressView() }
                            Text(L("Hent listene på nytt"))
                        }
                        .frame(minWidth: 520, alignment: .leading)
                    }
                    .disabled(model.loading)
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Text(L("Logg ut"))
                            .frame(minWidth: 520, alignment: .leading)
                    }
                    .accessibilityIdentifier("logg-ut")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.edge + 8)
        .padding(.vertical, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // like nær sidene som TV-siden
        .ignoresSafeArea(.container, edges: .horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("innstillinger")
        .alert(L("Logg ut av {name}?", ["name": model.login?.label ?? ""]), isPresented: $confirmSignOut) {
            Button(L("Logg ut"), role: .destructive) { model.signOut() }
            Button(L("Avbryt"), role: .cancel) {}
        }
    }

    private func row(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30))
    }
}
#endif
