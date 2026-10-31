import FyrlysCore
import Foundation

/// Når appen startes av testene på GitHub: en falsk leverandør (FYRLYS_TEST_SERVER), ingen nøkkelring, egne
/// innstillinger som tømmes, og eventuelt rett til en skjerm (FYRLYS_TEST_SCREEN: login, tv, guide, search, settings,
/// player, player-error).
enum TestSupport {
    static let env = ProcessInfo.processInfo.environment

    static var server: String? { env["FYRLYS_TEST_SERVER"] }

    static var isActive: Bool { server != nil }

    static var login: Login? {
        server.map { Login(server: $0, username: "test", password: "test") }
    }

    /// skjermen appen skal åpne på
    static var screen: String? { env["FYRLYS_TEST_SCREEN"] }

    /// språket (no/en), ellers som Apple TV-en
    static var language: String? { env["FYRLYS_TEST_LANG"] }

    /// Innstillingene: egne for testene, og tomme ved hver start.
    static let defaults: UserDefaults = {
        guard isActive, let test = UserDefaults(suiteName: "fyrlys-test") else { return .standard }
        if env["FYRLYS_TEST_KEEP"] == nil {
            test.removePersistentDomain(forName: "fyrlys-test")
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
