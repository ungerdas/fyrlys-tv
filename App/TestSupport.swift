import FyrlysCore
import Foundation

/// Når appen startes av testene på GitHub: en falsk leverandør (FYRLYS_TEST_SERVER), ingen nøkkelring, egne
/// innstillinger som tømmes, og eventuelt rett til en skjerm (FYRLYS_TEST_SCREEN: login, tv, guide, search, settings,
/// player, player-error, movies, series, archive = TV-arkivet for kanal 1, mkv = filmen 502 i VLC, mkv-feil = en film
/// leverandøren ikke har, plex og plex-series = Plex-fanen (koblet til fra før), plex-link = koble til
/// Plex med koden, strommer = Innstillinger (på iPhone arket) med egne strømmer (FYRLYS_TEST_STREAMS), m3u = logget inn med
/// M3U-lista til den falske leverandøren, login-m3u = innloggingen med M3U-lenke valgt, multiview = multiview med kanal 1
/// og M3U-lista som innlogging nummer to; på iPhone også category = Sport og all = Alle kanaler).
enum TestSupport {
    static let env = ProcessInfo.processInfo.environment

    static var server: String? { env["FYRLYS_TEST_SERVER"] }

    static var isActive: Bool { server != nil }

    /// m3u: M3U-lista hos den falske leverandøren (med TV-guide), ellers Xtream (test/test)
    static var login: Login? {
        guard let server else { return nil }
        if screen == "m3u" { return Login(m3u: server + "/liste.m3u") }
        return Login(server: server, username: "test", password: "test")
    }

    /// innloggingene ved siden av den i bruk (multiview: M3U-lista hos den falske leverandøren)
    static var extraLogins: [Login] {
        guard let server, screen == "multiview" else { return [] }
        return [Login(m3u: server + "/liste.m3u")]
    }

    /// en falsk Plex (plex.tv og serveren, tools/fake_plex.py)
    static var plexServer: String? { isActive ? env["FYRLYS_TEST_PLEX"] : nil }

    /// egne strømmer (linjene, adskilt med linjeskift), i stedet for de lagrede
    static var streams: [String]? {
        guard isActive, let text = env["FYRLYS_TEST_STREAMS"] else { return nil }
        return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    /// skjermen appen skal åpne på
    static var screen: String? { env["FYRLYS_TEST_SCREEN"] }

    /// språket (no/en), ellers som Apple TV-en
    static var language: String? { env["FYRLYS_TEST_LANG"] }

    /// Innstillingene: egne for testene, og tomme ved hver start (med modusen fra FYRLYS_TEST_THEME, light eller
    /// dark, så skjermbildene ikke avhenger av simulatoren).
    static let defaults: UserDefaults = {
        guard isActive, let test = UserDefaults(suiteName: "fyrlys-test") else { return .standard }
        if env["FYRLYS_TEST_KEEP"] == nil {
            test.removePersistentDomain(forName: "fyrlys-test")
        }
        if let theme = env["FYRLYS_TEST_THEME"] {
            test.set(theme, forKey: "tema")
        }
        return test
    }()

    /// Kanallista på disk: egen mappe for testene, tom ved hver start.
    static let listCache: ListCache = {
        guard isActive else { return .standard }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fyrlys-test-lister", isDirectory: true)
        if env["FYRLYS_TEST_KEEP"] == nil { try? FileManager.default.removeItem(at: dir) }
        return ListCache(dir: dir)
    }()
}
