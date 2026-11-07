import Foundation

// Korte navn på lydspor og undertekster i spilleren. VLC kaller dem «Norsk - [Norwegian]», «Track 1 - [English]» eller
// «English - SDH - [English]», og Plex «Norsk (SRT External)»; i menyen holder det med «Norsk», «Engelsk» og
// «Engelsk (SDH)».

/// Språkene som oftest står i sporene: navnet på engelsk (og norsk) → navnet på norsk og engelsk.
private let trackLanguages: [(names: [String], no: String, en: String)] = [
    (["norwegian", "norwegian bokmal", "norwegian bokmål", "bokmål", "bokmal", "norsk", "norsk bokmål"], "Norsk",
     "Norwegian"),
    (["norwegian nynorsk", "nynorsk"], "Nynorsk", "Norwegian Nynorsk"),
    (["english", "engelsk"], "Engelsk", "English"),
    (["swedish", "svensk", "svenska"], "Svensk", "Swedish"),
    (["danish", "dansk"], "Dansk", "Danish"),
    (["finnish", "finsk", "suomi"], "Finsk", "Finnish"),
    (["icelandic", "islandsk"], "Islandsk", "Icelandic"),
    (["german", "tysk", "deutsch"], "Tysk", "German"),
    (["french", "fransk", "français", "francais"], "Fransk", "French"),
    (["spanish", "spansk", "español", "espanol", "castilian"], "Spansk", "Spanish"),
    (["italian", "italiensk", "italiano"], "Italiensk", "Italian"),
    (["dutch", "nederlandsk", "nederlands", "flemish"], "Nederlandsk", "Dutch"),
    (["portuguese", "portugisisk", "português", "portugues"], "Portugisisk", "Portuguese"),
    (["polish", "polsk", "polski"], "Polsk", "Polish"),
    (["russian", "russisk"], "Russisk", "Russian"),
    (["ukrainian", "ukrainsk"], "Ukrainsk", "Ukrainian"),
    (["turkish", "tyrkisk"], "Tyrkisk", "Turkish"),
    (["greek", "gresk"], "Gresk", "Greek"),
    (["arabic", "arabisk"], "Arabisk", "Arabic"),
    (["hebrew", "hebraisk"], "Hebraisk", "Hebrew"),
    (["hindi"], "Hindi", "Hindi"),
    (["japanese", "japansk"], "Japansk", "Japanese"),
    (["korean", "koreansk"], "Koreansk", "Korean"),
    (["chinese", "kinesisk", "mandarin"], "Kinesisk", "Chinese"),
    (["cantonese", "kantonesisk"], "Kantonesisk", "Cantonese"),
    (["thai"], "Thai", "Thai"),
    (["czech", "tsjekkisk"], "Tsjekkisk", "Czech"),
    (["hungarian", "ungarsk"], "Ungarsk", "Hungarian"),
    (["romanian", "rumensk"], "Rumensk", "Romanian"),
    (["croatian", "kroatisk"], "Kroatisk", "Croatian"),
    (["serbian", "serbisk"], "Serbisk", "Serbian"),
    (["slovenian", "slovensk"], "Slovensk", "Slovenian"),
    (["bulgarian", "bulgarsk"], "Bulgarsk", "Bulgarian"),
    (["estonian", "estisk"], "Estisk", "Estonian"),
    (["latvian", "latvisk"], "Latvisk", "Latvian"),
    (["lithuanian", "litauisk"], "Litauisk", "Lithuanian"),
]

/// Merkene som er verdt å ha med bak språket (det andre i parentesene er filtype og kilde).
private let trackQualifiers: [(words: [String], label: String)] = [
    (["sdh", "hearing impaired", "hørselshemmede", "cc"], "SDH"),
    (["forced", "tvungen", "tvungne"], "Tvungen"),
    (["commentary", "kommentar", "kommentarspor"], "Kommentar"),
]

/// «Norsk - [Norwegian]» → «Norsk», «Track 1 - [English]» → «Engelsk», «English - SDH - [English]» → «Engelsk (SDH)»,
/// «Norsk (SRT External)» → «Norsk». Språknavnene står på språket appen vises på.
public func shortTrackName(_ name: String) -> String {
    var text = name.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return name }
    var language: String?
    var qualifiers: [String] = []

    // [Norwegian], (SRT External), (Forced)
    for (open, close) in [("[", "]"), ("(", ")")] {
        while let start = text.range(of: open, options: .backwards),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
            let inside = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            if open == "[", language == nil, trackLanguage(inside) != nil { language = inside }
            qualifiers += trackQualifier(inside)
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
    }

    var parts: [String] = []
    for raw in text.components(separatedBy: " - ") {
        let part = raw.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–,")))
        guard !part.isEmpty, !isGenericTrackName(part) else { continue }
        let found = trackQualifier(part)
        if !found.isEmpty, found.count == part.split(separator: " ").count || part.count <= 4 {
            qualifiers += found
            continue
        }
        if !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) { parts.append(part) }
    }

    var base: String
    if let first = parts.first {
        base = trackLanguage(first) ?? first
    } else if let language, let translated = trackLanguage(language) {
        base = translated
    } else {
        return name
    }
    if base.count > 28 { base = String(base.prefix(27)) + "…" }
    var seen: [String] = []
    for q in qualifiers where !seen.contains(q) { seen.append(q) }
    if let q = seen.first, !base.localizedCaseInsensitiveContains(q) {
        base += " (\(appLanguage == "en" ? englishQualifier(q) : q))"
    }
    return base
}

/// Navnet på språket på språket appen vises på, når [text] er et språk vi kjenner.
private func trackLanguage(_ text: String) -> String? {
    let key = text.lowercased().trimmingCharacters(in: .whitespaces)
    guard let match = trackLanguages.first(where: { $0.names.contains(key) }) else { return nil }
    return appLanguage == "en" ? match.en : match.no
}

private func trackQualifier(_ text: String) -> [String] {
    let lower = text.lowercased()
    let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
    return trackQualifiers.compactMap { entry in
        entry.words.contains(where: { $0.contains(" ") ? lower.contains($0) : words.contains($0) }) ? entry.label : nil
    }
}

private func englishQualifier(_ label: String) -> String {
    switch label {
    case "Tvungen": return "Forced"
    case "Kommentar": return "Commentary"
    default: return label
    }
}

/// «Track 1», «Spor 2», «Subtitle 3», «Stream #0:2», «und»: ikke et navn.
private func isGenericTrackName(_ text: String) -> Bool {
    let lower = text.lowercased()
    if ["und", "undefined", "undetermined", "unknown", "ukjent", "default", "standard"].contains(lower) { return true }
    let words = ["track", "spor", "subtitle", "subtitles", "undertekst", "undertekster", "audio", "lyd", "stream"]
    for word in words where lower.hasPrefix(word) {
        let rest = lower.dropFirst(word.count).trimmingCharacters(in: CharacterSet(charactersIn: " #:0123456789"))
        if rest.isEmpty { return true }
    }
    return false
}
