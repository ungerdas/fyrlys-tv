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

/// Ord i kanalnavn som ikke skiller kanaler fra hverandre: kvalitet, koding og slikt.
let ignoredChannelWords: Set<String> = [
    "hd", "fhd", "uhd", "sd", "4k", "hq", "lq", "hevc", "h265", "h264", "1080p", "1080i", "720p", "50fps", "60fps",
    "fps", "backup", "raw", "ᴴᴰ", "ʰᵈ",
]

/// Nøkkelen en kanal kjennes igjen på: små bokstaver og tall uten landskode foran og uten kvalitet bak.
/// «NO: NRK1 HD», «NO | NRK 1» og «NRK1 FHD» → «nrk1»; «NRK Super» → «nrksuper»; «NRK1 Midtnytt» → «nrk1midtnytt».
public func channelKey(_ name: String) -> String {
    var s = name.lowercased().trimmingCharacters(in: .whitespaces)
    // landskode foran: «no:», «no |», «[no]», «|no|», «no -»
    if let m = s.range(of: #"^[\[\(|]?\s*[a-z]{2,3}\s*([\]\)|:]|\s-\s)\s*"#, options: .regularExpression) {
        s = String(s[m.upperBound...])
    }
    // bare det første av «kanal | noe annet»
    if let bar = s.range(of: " | ") { s = String(s[..<bar.lowerBound]) }
    let words = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    return words.filter { !ignoredChannelWords.contains($0) }.joined()
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
