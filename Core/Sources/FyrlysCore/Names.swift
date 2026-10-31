import Foundation

/// Kanalnavn fra leverandøren delt i klokkeslett (eventkanaler), kanal eller kamp, og resten.
public struct NameParts: Equatable, Sendable {
    /// klokkeslett for eventkanaler, f.eks. «12:45»
    public let time: String
    /// kanalnavnet eller kampen
    public let main: String
    /// resten, f.eks. liga og land
    public let sub: String
}

/// «12:45 Aston Villa - Man City | Premier League» → «12:45», «Aston Villa - Man City», «Premier League».
public func nameParts(_ name: String) -> NameParts {
    var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var time = ""
    // et klokkeslett først kan bare finnes når navnet begynner med et siffer (de fleste gjør ikke det, og et regulært
    // uttrykk koster for hvert kort som tegnes)
    if let first = n.utf8.first, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(first),
       let m = n.range(of: #"^[0-9]{1,2}[:.][0-9]{2}\s*[-\x{2013}|:]?\s+"#, options: .regularExpression) {
        let head = n[m].trimmingCharacters(in: CharacterSet(charactersIn: " -–|:"))
        time = head.replacingOccurrences(of: ".", with: ":")
        n = String(n[m.upperBound...])
    }
    if let bar = n.range(of: " | ") {
        return NameParts(time: time, main: String(n[..<bar.lowerBound]).trimmingCharacters(in: .whitespaces),
                         sub: String(n[bar.upperBound...]).trimmingCharacters(in: .whitespaces))
    }
    return NameParts(time: time, main: n, sub: "")
}

/// Teksten i logofeltet til en kanal uten logo, som i Fyrlys på Windows: de tre første tegnene i navnet (hele tegn,
/// så et flagg eller en emoji ikke deles): «Viaplay Sport» → «Via».
public func logoText(_ name: String) -> String {
    let main = nameParts(name).main
    return main.isEmpty ? "?" : String(main.prefix(3))
}

/// To-tre bokstaver til en kanal uten logo: «NRK 1 HD» → «N1», «TV 2 Sport» → «T2».
public func initials(_ name: String) -> String {
    let words = nameParts(name).main.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
    var out = ""
    for w in words where out.count < 2 {
        if let c = w.first(where: { $0.isLetter || $0.isNumber }) { out.append(c) }
    }
    return out.uppercased()
}

/// «20:30» i tidssonen til enheten.
public func hhmm(_ date: Date, timeZone: TimeZone = .current) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    let c = cal.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}
