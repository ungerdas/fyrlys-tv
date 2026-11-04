#if os(tvOS)
import FyrlysCore
import SwiftUI

/// Innstillinger: abonnementet, innloggingene, Plex, hent listene på nytt, logg ut, og versjonen.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    /// innloggingen som får et nytt navn
    @State private var renaming: Login?
    @State private var report = false

    var body: some View {
        HStack(alignment: .top, spacing: 70) {
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

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Abonnement"))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        if let login = model.login {
                            row(L("Innlogget som {user}", ["user": login.label]))
                                .accessibilityIdentifier("innlogget-som")
                            Button {
                                renaming = login
                            } label: {
                                Label(L("Gi nytt navn"), systemImage: "pencil")
                                    .frame(minWidth: 520, alignment: .leading)
                            }
                            .accessibilityIdentifier("gi-nytt-navn")
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

                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Innlogginger"))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        ForEach(model.logins.filter { $0.id != model.login?.id }, id: \.id) { other in
                            Button {
                                model.switchTo(other)
                            } label: {
                                Text(L("Bytt til {name}", ["name": other.label]))
                                    .frame(minWidth: 520, alignment: .leading)
                            }
                            .contextMenu {
                                Button {
                                    renaming = other
                                } label: {
                                    Label(L("Gi nytt navn"), systemImage: "pencil")
                                }
                                // uten rolle på Apple TV (rød tekst på rødt var nesten ikke til å lese)
                                Button {
                                    model.remove(other)
                                } label: {
                                    Label(L("Fjern {name}", ["name": other.label]), systemImage: "trash")
                                }
                            }
                        }
                        Button {
                            model.addingLogin = true
                        } label: {
                            Label(L("Legg til innlogging"), systemImage: "plus")
                                .frame(minWidth: 520, alignment: .leading)
                        }
                        .accessibilityIdentifier("legg-til-innlogging")
                    }

                    PlexSettings()

                    StreamSettings()

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
                        Button {
                            confirmSignOut = true
                        } label: {
                            // rød tekst, ikke rød knapp (rød tekst på rødt var nesten ikke til å lese)
                            Text(L("Logg ut"))
                                .foregroundStyle(Theme.live)
                                .frame(minWidth: 520, alignment: .leading)
                        }
                        .accessibilityIdentifier("logg-ut")
                        Button {
                            report = true
                        } label: {
                            Label(L("Feilrapport"), systemImage: "ladybug")
                                .frame(minWidth: 520, alignment: .leading)
                        }
                        .accessibilityIdentifier("feilrapport-knapp")
                    }
                }
                // plass til knappene som vokser når de har fokus (rullelista klipper)
                .padding(.vertical, 24)
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                // inne i rullelista: den finner UIScrollView-en blant foreldrene sine (på rullelista selv gjorde den
                // ingenting)
                .hidesScrollIndex()
            }
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
        .renameLogin($renaming)
        .fullScreenCover(isPresented: $report) {
            ErrorReportView()
                .environment(model)
        }
    }

    private func row(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30))
    }
}
#endif
