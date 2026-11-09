import Darwin
#if os(macOS)
import AppKit
#endif
import FyrlysCore
import Foundation

/// Krasjer Fyrlys, er slutten av loggen fra den gangen med i feilrapporten neste gang (som Fyrlys for Windows 2.1.45).
/// Loggen lagres på enheten (`forrige-logg.txt`, renset som før), et merke står mens appen er framme, og et signal
/// (krasj) skrives i en egen fil. Står merket igjen ved neste start, ble appen ikke avsluttet på vanlig måte.
enum CrashWatch {
    /// fra forrige gang appen krasjet (nil: den gjorde ikke det): når, signalet og slutten av loggen
    private(set) static var lastCrash: (date: Date, signal: Int32?, lines: [String])?

    private static let runningKey = "kjorer-framme"
    private static let queue = DispatchQueue(label: "no.fyrlys.logg", qos: .utility)
    nonisolated(unsafe) private static var signalFile: Int32 = -1
    nonisolated(unsafe) private static var pending: [String]?

    private static var folder: URL {
        // Caches: Apple TV har ikke annen lagring på disken for apper
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fyrlys", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var logFile: URL { folder.appendingPathComponent("forrige-logg.txt") }
    private static var signalPath: URL { folder.appendingPathComponent("signal") }

    static func start() {
        guard !TestSupport.isActive || ProcessInfo.processInfo.environment["FYRLYS_TEST_CRASH"] != nil else { return }
        let defaults = UserDefaults.standard
        let crashed = defaults.object(forKey: runningKey) as? Date
        let signalByte = (try? Data(contentsOf: signalPath))?.first.map { Int32($0) }
        if let crashed {
            let lines = ((try? String(contentsOf: logFile, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isNewline).map(String.init)
            lastCrash = (crashed, signalByte, Array(lines.suffix(60)))
        }
        // signalet (SIGSEGV, SIGABRT …) skrives som én byte i fila; ingenting annet er trygt å gjøre i en signalhåndterer
        signalFile = open(signalPath.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { sig in
                var byte = UInt8(truncatingIfNeeded: sig)
                if CrashWatch.signalFile >= 0 { _ = write(CrashWatch.signalFile, &byte, 1) }
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
        // loggen på disken (høyst hvert halve sekund)
        AppLog.shared.onChange = { lines in
            queue.async {
                let first = pending == nil
                pending = lines
                guard first else { return }
                queue.asyncAfter(deadline: .now() + 0.5) {
                    if let lines = pending {
                        try? lines.joined(separator: "\n").write(to: logFile, atomically: true, encoding: .utf8)
                    }
                    pending = nil
                }
            }
        }
        foreground(true)
        #if os(macOS)
        // ⌘Q: en vanlig avslutning (scenePhase går ikke til bakgrunnen først på Mac)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { _ in foreground(false) }
        #endif
    }

    /// Appen er framme (merket står) eller i bakgrunnen (systemet kan avslutte den der uten at det er et krasj).
    static func foreground(_ on: Bool) {
        guard !TestSupport.isActive || ProcessInfo.processInfo.environment["FYRLYS_TEST_CRASH"] != nil else { return }
        if on {
            UserDefaults.standard.set(Date(), forKey: runningKey)
        } else {
            UserDefaults.standard.removeObject(forKey: runningKey)
        }
    }

    static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGTRAP: return "SIGTRAP (Swift-feil)"
        case SIGABRT: return "SIGABRT"
        case SIGFPE: return "SIGFPE"
        default: return "signal \(sig)"
        }
    }
}
