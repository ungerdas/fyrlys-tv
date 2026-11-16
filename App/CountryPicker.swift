import FyrlysCore
import SwiftUI

/// «Land som vises»: landene i lista fra leverandøren (fra kategorinavnene: «NO: …», «Sweden - …») med avkrysning.
/// Kategoriene fra landene som ikke er krysset av, skjules fra kategoriene, «Alle kanaler», søket og TV-guiden.
/// Favorittene og «Sist sett» står som før. Som Fyrlys for Windows 2.1.47 (`lib/ui/country_dialog.dart`).
struct CountryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// landene som er krysset av (alle når ingen er valgt)
    @State private var on: Set<String> = []
    @State private var ready = false
    #if os(tvOS)
    /// «Avbryt» på Apple TV (ellers brukes valget når du går ut med Menu)
    @State private var cancelled = false
    #endif

    private var groups: [CountryGroup] { model.index.countryGroups }
    private var all: Bool { on.count == groups.count }

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Land som vises"))
                        .font(.system(size: 48, weight: .bold))
                    Text(help)
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 900, alignment: .leading)
                    HStack(spacing: 30) {
                        Button(L("Bruk"), action: apply)
                            .disabled(on.isEmpty)
                            .accessibilityIdentifier("land-bruk")
                        Button(L("Alle")) { on = Set(groups.map(\.code)) }
                            .disabled(all)
                            .accessibilityIdentifier("land-alle")
                        Button(L("Ingen")) { on = [] }
                            .disabled(on.isEmpty)
                            .accessibilityIdentifier("land-ingen")
                        Button(L("Avbryt")) {
                            cancelled = true
                            dismiss()
                        }
                        .accessibilityIdentifier("land-avbryt")
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, 10)
                    rows
                }
                .frame(maxWidth: 1000, alignment: .leading)
                .padding(.vertical, 60)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .onDisappear {
                // ut med Menu: valget brukes (som bryterne ellers på Apple TV), men aldri ingen land
                if !cancelled, ready, !on.isEmpty { save() }
            }
            #else
            List {
                Section {
                    HStack(spacing: 20) {
                        Button(L("Alle")) { on = Set(groups.map(\.code)) }
                            .disabled(all)
                            .accessibilityIdentifier("land-alle")
                        Button(L("Ingen")) { on = [] }
                            .disabled(on.isEmpty)
                            .accessibilityIdentifier("land-ingen")
                    }
                    .buttonStyle(.borderless)
                } footer: {
                    Text(help)
                }
                .listRowBackground(Theme.surface)
                Section {
                    rows
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(L("Land som vises"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Avbryt")) { dismiss() }
                        .accessibilityIdentifier("land-avbryt")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Bruk"), action: apply)
                        .disabled(on.isEmpty)
                        .accessibilityIdentifier("land-bruk")
                }
            }
            #endif
        }
        #if !os(tvOS)
        .tint(Theme.signal)
        #endif
        .accessibilityIdentifier("landvalg")
        .onAppear {
            guard !ready else { return }
            // bare de som finnes i lista
            let codes = Set(groups.map(\.code))
            on = model.shownCountries.map { $0.intersection(codes) } ?? codes
            ready = true
        }
    }

    private var help: String {
        L("Kategoriene fra landene du krysser av, vises. Favorittene og «Sist sett» står som før.")
    }

    /// Ett land per rad: navnet, og hvor mange kategorier og kanaler.
    private var rows: some View {
        ForEach(groups) { group in
            Toggle(isOn: Binding(get: { on.contains(group.code) },
                                 set: { if $0 { on.insert(group.code) } else { on.remove(group.code) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: group.title)
                    Text(verbatim: group.detail)
                        .font(.system(size: Self.small))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .accessibilityIdentifier("land-\(group.code.isEmpty ? "-" : group.code)")
        }
    }

    private func apply() {
        save()
        #if os(tvOS)
        cancelled = true
        #endif
        dismiss()
    }

    /// Alle avkrysset: alle land, også de som kommer til senere.
    private func save() {
        guard !on.isEmpty else { return }
        model.setShownCountries(all ? nil : on)
    }

    #if os(tvOS)
    static let small: CGFloat = 20
    #else
    static let small: CGFloat = 12
    #endif
}

/// Kanallista i innstillingene: landene som vises (når lista har flere land) og ryddige kanalnavn.
struct ChannelListSettings: View {
    @Environment(AppModel.self) private var model
    @State private var countries = false

    private var tidyHelp: String {
        L("«NOR: TV 2 [720p]» blir «TV 2» med et lite merke for kvaliteten. Kategoriene ryddes på samme måte.")
    }

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Kanaler"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.muted)
            if model.index.hasCountries {
                Button {
                    countries = true
                } label: {
                    Label(L("Land som vises: {countries}", ["countries": countriesSummary(model.shownCountries)]),
                          systemImage: "globe")
                        .frame(minWidth: 520, alignment: .leading)
                }
                .accessibilityIdentifier("velg-land")
            }
            Button {
                model.tidyNames.toggle()
            } label: {
                Label(model.tidyNames ? L("Ryddige kanalnavn: på") : L("Ryddige kanalnavn: av"),
                      systemImage: "wand.and.stars")
                    .frame(minWidth: 520, alignment: .leading)
            }
            .accessibilityIdentifier("rydd-navn")
            Text(tidyHelp)
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 760, alignment: .leading)
        }
        // hele skjermen: i et ark ble knappene delt på to linjer («Bru-k»)
        .fullScreenCover(isPresented: $countries) {
            CountryPicker()
                .environment(model)
        }
        #else
        Section {
            if model.index.hasCountries {
                Button {
                    countries = true
                } label: {
                    HStack {
                        Label(L("Land som vises"), systemImage: "globe")
                        Spacer()
                        Text(verbatim: countriesSummary(model.shownCountries))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("velg-land")
                // arket på knappen, ikke på seksjonen (i et skjema havner det da på hver rad, og det kom ikke fram)
                .sheet(isPresented: $countries) {
                    CountryPicker()
                        .environment(model)
                        .macSheetSize()
                }
            }
            Toggle(isOn: Binding(get: { model.tidyNames }, set: { model.tidyNames = $0 })) {
                Label(L("Ryddige kanalnavn"), systemImage: "wand.and.stars")
            }
            .accessibilityIdentifier("rydd-navn")
        } header: {
            Text(L("Kanaler"))
        } footer: {
            Text(tidyHelp)
        }
        .listRowBackground(Theme.surface)
        #endif
    }
}

/// Kvaliteten etter navnet («720p», «H265», «4K») når den ikke er den vanlige (se `tidyChannelName`), som et lite
/// merke med kant (som Fyrlys for Windows).
struct QualityBadge: View {
    let text: String
    var size: CGFloat = 10

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.1)
            .overlay(RoundedRectangle(cornerRadius: size * 0.4).strokeBorder(Theme.muted.opacity(0.7), lineWidth: 1))
            .accessibilityIdentifier("kvalitet-\(text)")
    }
}
