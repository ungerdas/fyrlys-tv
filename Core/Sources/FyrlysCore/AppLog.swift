import Foundation

/// Loggen til feilrapporten: de siste 400 linjene, hver med klokkeslettet foran. Alt renses (`scrub`) før det tas vare
/// på, så adresser, brukernavn, passord og e-post aldri ligger her (som i Fyrlys for Windows).
public final class AppLog: @unchecked Sendable {
    public static let shared = AppLog()

    /// så mange linjer tas vare på
    public static let limit = 400

    private let lock = NSLock()
    private var buffer: [String] = []
    private let clock: () -> Date

    public init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// Legger til [message] (renset, hver linje for seg, uten tomme).
    public func add(_ message: String) {
        let time = Self.time.string(from: clock())
        let lines = scrub(message).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "\(time) \($0)" }
        guard !lines.isEmpty else { return }
        lock.lock()
        buffer.append(contentsOf: lines)
        if buffer.count > Self.limit { buffer.removeFirst(buffer.count - Self.limit) }
        lock.unlock()
    }

    /// Linjene, de eldste først.
    public var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock()
        buffer = []
        lock.unlock()
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// Tar bort det som ikke skal stå i loggen eller feilrapporten: vertsnavn i adresser, brukernavn og passord i stien til
/// strømmene og i spørringer, e-postadresser og IP-adresser (reglene fra Fyrlys for Windows, `core/app_log.dart`).
public func scrub(_ text: String) -> String {
    var out = text
    let rules: [(String, String, Bool)] = [
        (#"([a-z][a-z0-9+.-]*://)[^/\s"<>]+"#, "$1***", true),
        (#"/(live|movie|series|timeshift)/[^/\s"]+/[^/\s"]+"#, "/$1/***/***", true),
        (#"\b(username|password|user|pass|passwd|token|key|auth|x-plex-token)=[^&\s"]+"#, "$1=***", true),
        (#"[\w.+-]+@[\w-]+(\.[\w-]+)+"#, "***@***", false),
        (#"\b\d{1,3}(\.\d{1,3}){3}\b"#, "***", false),
    ]
    for (pattern, template, ignoreCase) in rules {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        else { continue }
        out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
    }
    return out
}
