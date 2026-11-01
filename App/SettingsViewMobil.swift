#if os(iOS)
import FyrlysCore
import SwiftUI

/// Innstillinger på iPad (iPhone har Konto i topplinja): abonnementet, lys eller mørk modus, hent listene på nytt,
/// logg ut, og versjonen.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.key, store: TestSupport.defaults) private var appearance = ""
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Abonnement")) {
                    if let login = model.login {
                        Text(L("Innlogget som {user}", ["user": login.label]))
                    }
                    if let account = model.account {
                        if let expires = account.expires {
                            Text(L("Aktiv til {date}", ["date": longDate(expires)]))
                        }
                        if account.maxConnections > 0 {
                            Text(account.maxConnections == 1 ? L("1 tilkobling")
                                 : L("{n} tilkoblinger", ["n": account.maxConnections]))
                        }
                    }
                    Text(L("{n} kanaler i {c} kategorier", ["n": model.channels.count, "c": model.categories.count]))
                }
                .listRowBackground(Theme.surface)
                Section(L("Innlogginger")) {
                    ForEach(model.logins.filter { $0.id != model.login?.id }, id: \.id) { other in
                        Button(L("Bytt til {name}", ["name": other.label])) { model.switchTo(other) }
                            .swipeActions {
                                Button(role: .destructive) { model.remove(other) } label: {
                                    Label(L("Fjern"), systemImage: "trash")
                                }
                            }
                    }
                    Button {
                        model.addingLogin = true
                    } label: {
                        Label(L("Legg til innlogging"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("legg-til-innlogging")
                }
                .listRowBackground(Theme.surface)
                PlexSettings()
                StreamSettings()
                Section(L("Utseende")) {
                    Picker(L("Utseende"), selection: $appearance) {
                        Text(L("Som enheten")).tag("")
                        Text(L("Mørk")).tag("dark")
                        Text(L("Lys")).tag("light")
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Theme.surface)
                Section {
                    Button {
                        Task { await model.reload() }
                    } label: {
                        HStack {
                            Text(L("Hent listene på nytt"))
                            Spacer()
                            if model.loading { ProgressView() }
                        }
                    }
                    .disabled(model.loading)
                    Button(L("Logg ut"), role: .destructive) {
                        confirmSignOut = true
                    }
                    .accessibilityIdentifier("logg-ut")
                }
                .listRowBackground(Theme.surface)
                Section {
                    HStack(spacing: 14) {
                        FyrlysMark()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Fyrlys")
                                .font(.headline)
                            Text(L("Versjon {version}", ["version": appVersion]))
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(L("Innstillinger"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("innstillinger")
        .alert(L("Logg ut av {name}?", ["name": model.login?.label ?? ""]), isPresented: $confirmSignOut) {
            Button(L("Logg ut"), role: .destructive) { model.signOut() }
            Button(L("Avbryt"), role: .cancel) {}
        }
    }
}
#endif
