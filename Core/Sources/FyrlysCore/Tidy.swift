import Foundation

// Ryddigere lister fra leverandører som har land og kvalitet i navnene: «NOR: TV 2 [720p]», «NO: VIAPLAY [PPV EVENTS]
// [1080p]». Landet og kvaliteten tas ut av navnet (kvaliteten blir et merke på kortet når den ikke er den vanlige,
// 1080p), og landet en kategori hører til, brukes til å vise bare de landene du vil se. Som Fyrlys for Windows 2.1.47
// (`lib/core/tidy.dart`).

private func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
}

/// Kvalitet i klammer eller parentes: «[1080p]», «[720p]», «[H265]», «[4K-Q]+», «(HEVC)», «[FHD]».
private let qualityTag =
    regex(#"[\[(]\s*(\d{3,4}[pi]|h\.?26[45]|hevc|uhd|fhd|hd|sd|[48]k[^\])]*)\s*[\])]\+?"#, caseInsensitive: true)

/// Det samme uten klammene (et merke i et kategorinavn).
private let qualityWord =
    regex(#"^(\d{3,4}[pi]|h\.?26[45]|hevc|uhd|fhd|hd|sd|[48]k.*)$"#, caseInsensitive: true)

/// Et merke foran kanalnavnet: «NOR: », «GOLD: », «UK | », «|NO| », «[NO] ».
private let channelPrefix =
    regex(#"^\s*(?:\|\s*[A-Za-z]{2,4}\s*\|\s*|\[\s*[A-Z]{2,4}\s*\]\s*|[A-Z][A-Z0-9+]{1,7}\s*[:|]\s+)"#)

/// Eventer har «LIVE:» og «NEXT:» foran; de står som de er.
private let eventPrefix =
    regex(#"^\s*(live|next|ended|soon|upcoming|replay|coming up)\s*:"#, caseInsensitive: true)

/// Landet foran et kategorinavn: «NO: », «UK | », «|SE| », «[DK] ».
private let codeBefore =
    regex(#"^\s*(?:\|\s*([A-Za-z]{2,4})\s*\|\s*|\[\s*([A-Za-z]{2,4})\s*\]\s*|([A-Z][A-Z0-9+]{1,7})\s*[:|]\s*)"#)

/// Landet skrevet ut foran resten: «Norway - Sport», «Sweden | Film».
private let nameBefore = regex(#"^\s*([A-Za-zÀ-ÿ. ]{2,24}?)\s+[-–|]\s+"#)

/// Landet bak: «Viaplay Sport SE», «HBO Max Sports DK [B]».
private let codeAfter = regex(#"\s([A-Z]{2})(?:\s*\[[^\]]*\])*\s*$"#)

/// Klammer (merker) og teksten mellom dem.
private let segments = regex(#"\[([^\]]*)\]\+?|([^\[]+)"#)

/// Det som står mellom to kvalitetsmerker: «[720p] AND [H265]».
private let joiner = regex(#"^(and|og|&|\+|/|,|-|–)$"#, caseInsensitive: true)


/// Koder som godtas bak navnet (der kunne det ellers vært «TV» eller «HD»).
private let codesAfter: Set<String> = [
    "NO", "SE", "DK", "FI", "IS", "UK", "US", "DE", "NL", "FR", "ES", "IT", "PL", "PT",
    "TR", "BE", "CZ", "GR", "BR", "RO", "AT", "AU", "CH", "HR", "CA", "IE",
]

/// Land skrevet ut, på engelsk og på landets eget språk.
private let countryNames: [String: String] = [
    "norway": "NO", "norge": "NO", "noreg": "NO",
    "sweden": "SE", "sverige": "SE",
    "denmark": "DK", "danmark": "DK",
    "finland": "FI", "suomi": "FI",
    "united kingdom": "UK", "great britain": "UK", "england": "UK", "uk": "UK",
    "usa": "US", "united states": "US", "us": "US", "america": "US",
    "germany": "DE", "deutschland": "DE", "tyskland": "DE",
    "netherlands": "NL", "netherland": "NL", "holland": "NL", "nederland": "NL",
    "france": "FR",
    "spain": "ES", "españa": "ES", "espana": "ES",
    "italy": "IT", "italia": "IT",
    "poland": "PL", "polska": "PL",
    "portugal": "PT",
    "turkey": "TR", "türkiye": "TR", "turkiye": "TR",
    "belgium": "BE", "belgie": "BE", "belgique": "BE",
    "czech": "CZ", "czechia": "CZ", "czech republic": "CZ",
    "greece": "GR",
    "brazil": "BR", "brasil": "BR",
    "romania": "RO",
    "austria": "AT", "österreich": "AT",
    "australia": "AU",
    "switzerland": "CH", "schweiz": "CH", "suisse": "CH",
    "croatia": "HR", "hrvatska": "HR",
    "canada": "CA",
    "ireland": "IE",
]

// ── små hjelpere for NSRegularExpression ──

private extension NSRegularExpression {
    func first(in text: String) -> NSTextCheckingResult? {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func matches(_ text: String) -> Bool { first(in: text) != nil }

    func all(in text: String) -> [NSTextCheckingResult] {
        matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

private extension NSTextCheckingResult {
    /// Gruppen [n] i [text], eller nil når den ikke er med.
    func group(_ n: Int, in text: String) -> String? {
        guard n < numberOfRanges, let range = Range(range(at: n), in: text) else { return nil }
        return String(text[range])
    }

    /// Teksten etter treffet.
    func rest(of text: String) -> String {
        guard let range = Range(range, in: text) else { return text }
        return String(text[range.upperBound...])
    }
}

/// «[1080p]» og «FHD» er det vanlige og får ikke noe merke; ellers «720p», «H265», «4K» …
func qualityLabel(_ tag: String) -> String? {
    let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
    if t.hasPrefix("1080") || t == "fhd" { return nil }
    if t.hasPrefix("4k") || t == "uhd" || t.hasPrefix("2160") { return "4K" }
    if t.hasPrefix("8k") { return "8K" }
    if t == "hevc" || t == "h265" || t == "h.265" { return "H265" }
    if t == "h264" || t == "h.264" { return "H264" }
    if t == "hd" { return "HD" }
    if t == "sd" { return "SD" }
    return t
}

/// Tegnene som blir hengende igjen foran og bak når merkene er tatt bort.
private let looseEndCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":|-–·"))

/// Mellomrom samlet, og det som ble hengende igjen foran og bak («TV 2 -», «: TV 2»). Uten regulære uttrykk: det
/// gjøres for titusenvis av kanaler.
private func tidySpaces(_ s: String) -> String {
    let words = s.split(whereSeparator: { $0.isWhitespace })
    return words.joined(separator: " ").trimmingCharacters(in: looseEndCharacters)
}

/// Kanalnavnet uten merket foran og kvaliteten i klammer: «NOR: TV 2 [720p]» → «TV 2» og «720p»; «GOLD: NRK1
/// [1080p]» → «NRK1» (1080p er det vanlige). Navn uten slike merker står som de er.
public func tidyChannelName(_ name: String) -> (name: String, quality: String?) {
    // de fleste navnene har ingen av tegnene merkene trenger: da slipper de de regulære uttrykkene (titusenvis av
    // kanaler ved hver oppstart)
    var brackets = false
    var separators = false
    for c in name.unicodeScalars {
        switch c {
        case "[", "(": brackets = true
        case ":", "|": separators = true
        default: break
        }
    }
    guard brackets || separators else { return (name, nil) }
    var quality: String?
    var changed = false
    var n = name
    if brackets {
        let tags = qualityTag.all(in: name)
        if !tags.isEmpty {
            changed = true
            // treffene byttes med et mellomrom (uten en runde til med det regulære uttrykket)
            var out = ""
            var at = name.startIndex
            for match in tags {
                guard let range = Range(match.range, in: name) else { continue }
                if quality == nil { quality = match.group(1, in: name).flatMap(qualityLabel) }
                out += name[at..<range.lowerBound]
                out += " "
                at = range.upperBound
            }
            out += name[at...]
            n = out
        }
    }
    if let m = channelPrefix.first(in: n), !eventPrefix.matches(n) {
        n = m.rest(of: n)
        changed = true
    }
    guard changed else { return (name, nil) }
    n = tidySpaces(n)
    return n.isEmpty ? (name.trimmingCharacters(in: .whitespaces), nil) : (n, quality)
}

/// Kategorinavnet uten landet foran og den vanlige kvaliteten: «NO: VIAPLAY [PPV EVENTS] [1080p]» → «VIAPLAY · PPV
/// EVENTS», «NO: SPORT [720p] AND [H265]» → «SPORT · 720p · H265», «NO: [1080p]» → «Norge». Med [keepCountry] (flere
/// land vises) står koden foran: «NO · SPORT · 720p · H265». Navn uten land foran og kvalitet står som de er.
public func tidyCategoryName(_ name: String, keepCountry: Bool = false) -> String {
    let m = codeBefore.first(in: name)
    let code = m.flatMap { m in
        (m.group(1, in: name) ?? m.group(2, in: name) ?? m.group(3, in: name)).map(normalizeCountry)
    }
    let rest = m.map { $0.rest(of: name) } ?? name
    var changed = m != nil
    var parts: [String] = []
    var fromTag: [Bool] = []
    var qualities: [String] = []
    for s in segments.all(in: rest) {
        if let tag = s.group(1, in: rest) {
            let t = tag.trimmingCharacters(in: .whitespaces)
            if qualityWord.matches(t) {
                changed = true
                if let q = qualityLabel(t), !qualities.contains(q) { qualities.append(q) }
            } else if !t.isEmpty {
                parts.append(t)
                fromTag.append(true)
            }
        } else if let between = s.group(2, in: rest) {
            let text = tidySpaces(between)
            if text.isEmpty || joiner.matches(text) { continue }
            parts.append(text)
            fromTag.append(false)
        }
    }
    guard changed else { return name }
    var title = ""
    for (i, part) in parts.enumerated() {
        // et merke helt først hører til teksten etter: «[PLUS] PLAY» → «PLUS PLAY»
        if i > 0 { title += i == 1 && fromTag[0] && !fromTag[1] ? " " : " · " }
        title += part
    }
    var out: [String] = []
    // bare kvalitet («NO: [720p] AND [H265]»): landet er navnet
    if title.isEmpty, let code { out.append(countryLabel(code)) }
    if !title.isEmpty, keepCountry, let code { out.append(code) }
    if !title.isEmpty { out.append(title) }
    out += qualities
    let joined = out.joined(separator: " · ")
    return joined.isEmpty ? name : joined
}

/// Én kode per land, uansett hvordan leverandøren skriver den («NOR» og «NO» er begge Norge).
public func normalizeCountry(_ code: String) -> String {
    switch code.uppercased() {
    case "NOR": return "NO"
    case "SWE": return "SE"
    case "DNK", "DEN": return "DK"
    case "FIN": return "FI"
    case "GBR", "GB", "ENG": return "UK"
    case "USA": return "US"
    case "DEU", "GER": return "DE"
    case "FRA": return "FR"
    case "ESP", "SPA": return "ES"
    case "ITA": return "IT"
    case "NLD", "HOL": return "NL"
    case "POL": return "PL"
    case "PRT", "POR": return "PT"
    case "TUR": return "TR"
    case "BEL": return "BE"
    case "CZE": return "CZ"
    case "GRC", "GRE": return "GR"
    case "BRA": return "BR"
    case "ROU", "ROM": return "RO"
    case "AUT": return "AT"
    case "AUS": return "AU"
    case "CHE", "SUI": return "CH"
    case "HRV", "CRO": return "HR"
    case "CAN": return "CA"
    case "IRL": return "IE"
    case let other: return other
    }
}

/// Landet en kategori hører til: «NO: Sport», «|SE| Film», «[DK] Nyheter», «Norway - Sport», «Viaplay Sport SE»
/// eller bare «Sweden». Nil når navnet ikke sier noe om land.
public func countryOf(_ category: String) -> String? {
    if let m = codeBefore.first(in: category),
       let code = m.group(1, in: category) ?? m.group(2, in: category) ?? m.group(3, in: category) {
        return normalizeCountry(code)
    }
    if let whole = countryNames[category.trimmingCharacters(in: .whitespaces).lowercased()] { return whole }
    if let m = nameBefore.first(in: category), let name = m.group(1, in: category),
       let code = countryNames[name.trimmingCharacters(in: .whitespaces).lowercased()] {
        return code
    }
    if let m = codeAfter.first(in: category), let code = m.group(1, in: category), codesAfter.contains(code) {
        return code
    }
    return nil
}

/// Navnet på landet («Norge»), eller koden slik leverandøren skriver den når den ikke er et kjent land («ARA» er
/// arabisk, men «AS» kan være mye). "" er kategoriene uten land.
public func countryLabel(_ code: String) -> String {
    switch code {
    case "": return L("Uten land")
    case "NO": return L("Norge")
    case "SE": return L("Sverige")
    case "DK": return L("Danmark")
    case "FI": return L("Finland")
    case "UK": return L("Storbritannia")
    case "US": return L("USA")
    case "DE": return L("Tyskland")
    case "NL": return L("Nederland")
    case "FR": return L("Frankrike")
    case "ES": return L("Spania")
    case "IT": return L("Italia")
    case "PL": return L("Polen")
    case "PT": return L("Portugal")
    case "TR": return L("Tyrkia")
    case "BE": return L("Belgia")
    case "CZ": return L("Tsjekkia")
    case "GR": return L("Hellas")
    case "BR": return L("Brasil")
    case "RO": return L("Romania")
    case "AT": return L("Østerrike")
    case "AU": return L("Australia")
    case "CH": return L("Sveits")
    case "HR": return L("Kroatia")
    case "CA": return L("Canada")
    case "IE": return L("Irland")
    case "ARA": return L("Arabisk")
    case "EXYU": return L("Eks-Jugoslavia")
    case "AFRICAN": return L("Afrika")
    case "GLOBAL": return L("Internasjonalt")
    default: return code
    }
}

/// Et land i lista: koden ("" = uten land), hvor mange kategorier og kanaler, og en av kategoriene slik leverandøren
/// skriver den (så en ukjent kode kan kjennes igjen).
public struct CountryGroup: Hashable, Sendable, Identifiable {
    public let code: String
    public let categories: Int
    public let channels: Int
    public let example: String

    public var id: String { code }

    public init(code: String, categories: Int, channels: Int, example: String) {
        self.code = code
        self.categories = categories
        self.channels = channels
        self.example = example
    }

    /// «Norge (NO)», «Uten land», eller koden når den ikke er et kjent land.
    public var title: String {
        let name = countryLabel(code)
        return !code.isEmpty && name != code ? "\(name) (\(code))" : name
    }

    /// «3 kategorier · 120 kanaler», med en av kategoriene når koden ikke er et kjent land.
    public var detail: String {
        let counts = [
            categories == 1 ? L("1 kategori") : L("{n} kategorier", ["n": categories]),
            channels == 1 ? L("1 kanal") : L("{n} kanaler", ["n": channels]),
        ].joined(separator: " · ")
        let known = !code.isEmpty && countryLabel(code) != code
        return known || example.isEmpty ? counts : "\(counts) · «\(example)»"
    }
}

/// Landene i lista, i alfabetisk rekkefølge etter navnet, og «Uten land» sist. Bare land med kanaler, og bare
/// kategoriene med kanaler telles (og gir eksempelet). [countries]: landet hver kategori hører til, når det alt er
/// funnet.
public func countryGroups(_ categories: [ChannelCategory], _ channels: [Channel],
                          countries: [String: String]? = nil) -> [CountryGroup] {
    var inCategory: [String: Int] = [:]
    for channel in channels { inCategory[channel.categoryId, default: 0] += 1 }
    var countryOfCategory: [String: String] = [:]
    var cats: [String: Int] = [:]
    var example: [String: String] = [:]
    for category in categories where countryOfCategory[category.id] == nil {
        let code = countries?[category.id] ?? countryOf(category.name) ?? ""
        countryOfCategory[category.id] = code
        guard inCategory[category.id] != nil else { continue }
        cats[code, default: 0] += 1
        if example[code] == nil { example[code] = category.name }
    }
    var chans: [String: Int] = [:]
    for (id, count) in inCategory {
        chans[countryOfCategory[id] ?? "", default: 0] += count
    }
    return chans.map { CountryGroup(code: $0.key, categories: cats[$0.key] ?? 0, channels: $0.value,
                                    example: example[$0.key] ?? "") }
        .sorted { a, b in
            if a.code.isEmpty != b.code.isEmpty { return !a.code.isEmpty }
            return countryLabel(a.code).lowercased() < countryLabel(b.code).lowercased()
        }
}

/// Lista har kanaler fra flere land (da kan du velge hvilke som vises).
public func hasSeveralCountries(_ groups: [CountryGroup]) -> Bool {
    groups.filter { !$0.code.isEmpty }.count > 1
}

/// «Norge, Sverige og 2 til» / «Alle land».
public func countriesSummary(_ shown: Set<String>?) -> String {
    guard let shown, !shown.isEmpty else { return L("Alle land") }
    let names = shown.map(countryLabel).sorted { $0.lowercased() < $1.lowercased() }
    if names.count <= 3 { return names.joined(separator: ", ") }
    return L("{names} og {n} til", ["names": names.prefix(3).joined(separator: ", "), "n": names.count - 3])
}
