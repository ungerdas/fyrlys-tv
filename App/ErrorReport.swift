import FyrlysCore
import SwiftUI
import UIKit

/// Feilrapporten, som i Fyrlys for Windows: versjonen, enheten, innstillingene og de siste linjene i loggen, uten
/// passord, brukernavn, adresser og navnet på leverandøren (alt renses med `scrub`, også det som ble lagt til nå).
@MainActor
enum ErrorReport {
    static func build(_ model: AppModel, at now: Date = Date()) -> String {
        var lines: [String] = []
        lines.append(L("Fyrlys – feilrapport"))
        lines.append(L("Laget: {time}", ["time": stamp(now)]))
        lines.append(L("Versjon: Fyrlys {version} (bygg {build})", ["version": appVersion, "build": appBuild]))
        let device = UIDevice.current
        lines.append(L("Enhet: {device} ({model}), {system} {version}",
                       ["device": device.model, "model": machine, "system": device.systemName,
                        "version": device.systemVersion]))
        lines.append(L("Språk: {language}", ["language": appLanguage]))
        lines.append("")
        lines.append(L("Innlogginger: {n}", ["n": max(model.logins.count, model.login == nil ? 0 : 1)]))
        if let login = model.login {
            lines.append(L("Innlogging i bruk: {kind}", ["kind": login.isM3U ? (model.m3uSummary ?? "M3U") : "Xtream Codes"]))
        }
        if let account = model.account {
            lines.append(L("Abonnement: {status} · {max} tilkoblinger · {active} i bruk",
                           ["status": account.status.isEmpty ? "–" : account.status,
                            "max": account.maxConnections, "active": account.activeConnections]))
        }
        lines.append(L("Kanaler: {n} · kategorier: {c} · med TV-arkiv: {a}",
                       ["n": model.channels.count, "c": model.categories.count,
                        "a": model.channels.filter { $0.archiveDays > 0 }.count]))
        if let error = model.error {
            lines.append(L("Feil i listene: {error}", ["error": error]))
        }
        lines.append(L("NRK direkte: {state} · egne strømmer: {n}",
                       ["state": model.useBuiltInStreams ? L("på") : L("av"), "n": model.streamOverrides.count]))
        lines.append(L("Filmer og serier fra: {source}",
                       ["source": model.plex.useForVOD ? "Plex" : L("IPTV-leverandøren")]))
        lines.append(L("Plex: {state}", ["state": plexState(model.plex)]))
        if !model.hiddenSections.isEmpty {
            lines.append(L("Skjulte Plex-biblioteker: {n}", ["n": model.hiddenSections.count]))
        }
        lines.append("")
        lines.append(L("## Logg"))
        let log = AppLog.shared.lines
        lines += log.isEmpty ? ["–"] : log
        return scrub(lines.joined(separator: "\n"))
    }

    private static func plexState(_ plex: PlexModel) -> String {
        switch plex.phase {
        case .off: return L("ikke koblet til")
        case .linking: return L("venter på koden")
        case .choosing: return L("velger server")
        case .connecting: return L("kobler til")
        case .failed(let message): return L("feil: {message}", ["message": message])
        case .connected:
            guard let base = plex.client?.base, let server = plex.server else { return L("koblet til") }
            return L("koblet til ({kind})", ["kind": PlexModel.kind(of: base, in: server)])
        }
    }

    private static func stamp(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.string(from: date)
    }

    /// «AppleTV14,1», «iPhone17,2»
    static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Byggnummeret fra Info.plist.
var appBuild: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
}

/// Feilrapporten på skjermen: hele teksten. iPhone og iPad: «Kopier» og «Del», og den som er sendt fra Apple TV.
/// Apple TV (ingen deling der): «Send til iPhone» legger den i iCloud, så den kan kopieres eller deles fra Fyrlys på
/// iPhone eller iPad.
struct ErrorReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var report = ""
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("Feilrapport"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Ferdig")) { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            UIPasteboard.general.string = report
                            notice = L("Feilrapporten er kopiert. Lim den inn der du melder fra om feilen.")
                        } label: {
                            Label(L("Kopier"), systemImage: "doc.on.doc")
                        }
                        .accessibilityIdentifier("kopier-rapport")
                        ShareLink(item: report, subject: Text(L("Fyrlys – feilrapport"))) {
                            Label(L("Del"), systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("del-rapport")
                    }
                }
                #endif
        }
        #if os(iOS)
        .tint(Theme.signal)
        #endif
        .onAppear { report = ErrorReport.build(model) }
        .accessibilityIdentifier("feilrapport")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Dette er hele rapporten. Passord, brukernavn, adresser og navnet på leverandøren er tatt bort."))
                    .font(.system(size: Self.font + 2))
                    .foregroundStyle(Theme.ink2)
                #if os(tvOS)
                Button {
                    model.sendReport(report)
                    notice = L("Sendt. Åpne Fyrlys på iPhone eller iPad med samme Apple-ID: Feilrapport, «Fra Apple TV».")
                } label: {
                    Label(L("Send til iPhone"), systemImage: "iphone.and.arrow.forward")
                }
                .accessibilityIdentifier("send-rapport")
                #endif
                if let notice {
                    Text(notice)
                        .font(.system(size: Self.font + 1, weight: .semibold))
                        .foregroundStyle(Theme.signal)
                }
                #if os(iOS)
                if let sent = model.reportFromTV {
                    tvReport(sent)
                }
                #endif
                reportText(report)
            }
            .padding(Self.font * 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    /// Teksten. På Apple TV i biter som kan få fokus, så den kan rulles med fjernkontrollen.
    @ViewBuilder
    private func reportText(_ text: String) -> some View {
        #if os(tvOS)
        let lines = text.components(separatedBy: "\n")
        // bitene tett i tett (ellers så det ut som avsnitt midt i rapporten)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stride(from: 0, to: lines.count, by: 12)), id: \.self) { start in
                Text(verbatim: lines[start..<min(start + 12, lines.count)].joined(separator: "\n"))
                    .font(.system(size: Self.font, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusable()
            }
        }
        #else
        Text(verbatim: text)
            .font(.system(size: Self.font, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
        #endif
    }

    #if os(iOS)
    /// Rapporten som er sendt fra Apple TV (via iCloud).
    private func tvReport(_ sent: (date: String, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Fra Apple TV ({time})", ["time": sent.date]))
                .font(.system(size: Self.font + 2, weight: .semibold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = sent.text
                    notice = L("Feilrapporten er kopiert. Lim den inn der du melder fra om feilen.")
                } label: {
                    Label(L("Kopier"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                ShareLink(item: sent.text, subject: Text(L("Fyrlys – feilrapport"))) {
                    Label(L("Del"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rapport-fra-tv")
    }
    #endif

    #if os(tvOS)
    static let font: CGFloat = 22
    #else
    static let font: CGFloat = 12
    #endif
}
