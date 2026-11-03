import Foundation

/// Egne strømmer: adresser som spilles i stedet for leverandørens for kanalene de gjelder («…/nrk1/muxed.m3u8» for
/// NRK1): de innebygde (`builtInStreams`) og dem brukeren har lagt inn selv (på enhetene og i iCloud).
public struct StreamOverride: Hashable, Sendable {
    /// kanalnøkkelen (se `channelKey`), f.eks. «nrk1»
    public let key: String
    public let url: URL

    public init(key: String, url: URL) {
        self.key = key
        self.url = url
    }
}

/// Filnavn som ikke sier hvilken kanal det er («…/nrk1/muxed.m3u8»): da gjelder mappen over.
let genericStreamNames: Set<String> = [
    "muxed", "index", "playlist", "master", "manifest", "chunklist", "stream", "live", "main", "mono", "video", "hls",
    "media", "prog_index", "out", "output",
]

/// Ord i kanalnavn som ikke skiller kanaler fra hverandre: kvalitet, koding og slikt, og utgavene med lydtekst og
/// tegnspråk (eieren 1.11.2026: «NRK 2 er en … ikke 3 ulike»).
let ignoredChannelWords: Set<String> = [
    "hd", "fhd", "uhd", "sd", "4k", "hq", "lq", "hevc", "h265", "h264", "1080p", "1080i", "720p", "50fps", "60fps",
    "fps", "backup", "raw", "ᴴᴰ", "ʰᵈ", "lydtekst", "tegnspråk", "tegnsprak",
]

/// Landskoder leverandørene setter bak navnet («NRK 1 HD NO»).
let trailingCountryCodes: Set<String> = [
    "no", "nor", "se", "swe", "dk", "den", "fi", "fin", "is", "uk", "gb", "us", "usa", "de", "ger", "fr", "nl", "be",
    "es", "it", "pl", "pt", "ch", "at", "ie", "ca", "au", "nz", "tr", "ru", "ar", "gr", "hu", "cz", "sk", "ro", "bg",
    "hr", "rs", "si", "ba", "al", "mk", "ee", "lv", "lt", "ua", "il", "in", "pk", "br", "mx", "za", "ex",
]

/// Nøkkelen en kanal kjennes igjen på: små bokstaver og tall uten landskode foran eller bak og uten kvalitet.
/// «NO: NRK1 HD», «NO | NRK 1», «NRK1 FHD» og «NRK 1 HD NO» → «nrk1»; «NRK Super» → «nrksuper»;
/// «NRK 2 Lydtekst HD NO» → «nrk2»; «NRK1 Midtnytt» → «nrk1midtnytt».
public func channelKey(_ name: String) -> String {
    channelKeyAndCountry(name).key
}

/// Nøkkelen (se `channelKey`) og landskoden som sto foran eller bak, når den er kjent: «TV 2 HD DK» → («tv2», «dk»),
/// «NO: NRK1» → («nrk1», «no»), «NRK1» → («nrk1», nil).
public func channelKeyAndCountry(_ name: String) -> (key: String, country: String?) {
    var s = name.lowercased().trimmingCharacters(in: .whitespaces)
    var country: String?
    // landskode foran: «no:», «no |», «[no]», «|no|», «no -»
    if let m = s.range(of: #"^[\[\(|]?\s*[a-z]{2,3}\s*([\]\)|:]|\s-\s)\s*"#, options: .regularExpression) {
        let code = String(s[m].filter { $0.isLetter })
        if trailingCountryCodes.contains(code) { country = code }
        s = String(s[m.upperBound...])
    }
    // bare det første av «kanal | noe annet»
    if let bar = s.range(of: " | ") { s = String(s[..<bar.lowerBound]) }
    var words = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        .filter { !ignoredChannelWords.contains($0) }
    if words.count > 1, let last = words.last, trailingCountryCodes.contains(last) {
        country = country ?? last
        words.removeLast()
    }
    return (words.joined(), country)
}

/// Landene en egen strøm uten land gjelder for: Norge (og kanaler uten landskode). «TV 2 = …» er norsk TV 2, ikke
/// «TV 2 HD DK»; finnes kanalen bare i et annet land (en svensk kanal), gjelder strømmen den.
let homeCountries: Set<String> = ["no", "nor"]

/// Kanalene et navn kan stå for: «NRK 3/SUPER NO» er både «NRK 3 NO» og «NRK SUPER NO» (to kanaler som deler plass
/// hos leverandøren); uten «a/b» bare navnet selv.
public func channelAlternatives(_ name: String) -> [String] {
    guard name.contains("/"),
          let r = name.range(of: #"[\p{L}\p{N}]+(/[\p{L}\p{N}]+)+"#, options: .regularExpression) else { return [name] }
    return name[r].split(separator: "/").map { name.replacingCharacters(in: r, with: $0) }
}

/// Sidene av skråstreken i hele navnet: «NRK3/NRK Super» → «NRK3» og «NRK Super».
func wholeAlternatives(_ name: String) -> [String] {
    let parts = name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return parts.count > 1 ? parts : [name]
}

/// Strømmene ([keys]) en kanal med [name] spilles fra, med navnet den har for hver: én, flere når navnet er «a/b» og
/// begge har en strøm, eller ingen. «a/b» deles både ord for ord («NRK 3/SUPER NO») og på hele sidene
/// («NRK3/NRK Super»); den måten som gir flest treff, gjelder.
public func matchingStreamKeys(_ name: String, in keys: Set<String>) -> [(key: String, name: String)] {
    func matches(_ alternatives: [String]) -> [(key: String, name: String)] {
        var seen = Set<String>()
        return alternatives.compactMap { alt in
            let key = channelKey(alt)
            guard keys.contains(key), seen.insert(key).inserted else { return nil }
            return (key, alt)
        }
    }
    let byWord = matches(channelAlternatives(name))
    guard name.contains("/") else { return byWord }
    let bySide = matches(wholeAlternatives(name))
    return bySide.count > byWord.count ? bySide : byWord
}

/// Nøkkelen en adresse gjelder for: filnavnet uten filtype, eller mappen over når filnavnet er generelt.
/// «…/nrk1/muxed.m3u8» → «nrk1».
public func channelKey(of url: URL) -> String {
    let parts = url.pathComponents.filter { $0 != "/" }
    for part in parts.reversed() {
        let name = (part as NSString).deletingPathExtension.lowercased()
        if name.isEmpty || genericStreamNames.contains(name) { continue }
        return channelKey(name)
    }
    return ""
}

/// Linjene brukeren har limt inn: «adresse», eller «kanalnavn = adresse» når navnet i adressen ikke er kanalens.
/// Tomme linjer og linjer som begynner med # hoppes over.
public func parseStreamOverrides(_ text: String) -> [StreamOverride] {
    var seen = Set<String>()
    return text.split(whereSeparator: \.isNewline).compactMap { raw in
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"),
              let start = line.range(of: "http", options: .caseInsensitive) else { return nil }
        let address = line[start.lowerBound...].split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return nil }
        let name = line[..<start.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " =:-|\t"))
        let key = name.isEmpty ? channelKey(of: url) : channelKey(name)
        guard !key.isEmpty, seen.insert(key).inserted else { return nil }
        return StreamOverride(key: key, url: url)
    }
}

/// Innebygd for alle (eieren 1.11.2026: «Fyrlys skal kun bruke disse m3u8 fra NRK. Det er direkte.» og «Bygg inn for
/// alle.»): NRK1, NRK2, NRK3 og NRK Super direkte, i stedet for leverandørens strøm for de kanalene. Kan slås av i
/// innstillingene, og en egen strøm for samme kanal går foran.
public let builtInStreams: [StreamOverride] = parseStreamOverrides("""
https://cdn0-47115-liveedge0.dna.contentdelivery.net/47115-liveedge0/nrk1/muxed.m3u8
https://cdn0-47115-liveedge0.dna.contentdelivery.net/47115-liveedge0/nrk2/muxed.m3u8
https://cdn0-47115-liveedge0.dna.contentdelivery.net/47115-liveedge0/nrk3/muxed.m3u8
https://cdn0-47115-liveedge0.dna.contentdelivery.net/47115-liveedge0/nrksuper/muxed.m3u8
""")
