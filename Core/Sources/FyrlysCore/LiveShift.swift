import Foundation

// Pause og tilbakespoling i direktesending (som i Fyrlys for Windows, der mpv tar vare på det siste selv): appen
// henter HLS-strømmen fra leverandøren selv, legger bitene på disken (opptil en halvtime) og gir Apple sin avspiller
// en spilleliste med alt den har (`ShiftBuffer.playlist`). Da kan du pause og spole tilbake i det som er hentet, og
// AVKit viser «direkte» og hvor langt bak du er. Her er spillelistene og bufferet; tjeneren og hentingen er i appen.

/// En variant i en hovedliste (#EXT-X-STREAM-INF).
public struct HLSVariant: Equatable, Sendable {
    public let url: URL
    public let bandwidth: Int
    /// lyden i en egen spilleliste (#EXT-X-MEDIA TYPE=AUDIO med URI): det kan ikke bufferet
    public let separateAudio: Bool
}

/// En bit i en medieliste.
public struct HLSSegment: Equatable, Sendable {
    public let sequence: Int
    public let duration: Double
    public let url: URL
    /// #EXT-X-DISCONTINUITY foran biten
    public let discontinuity: Bool
    /// #EXT-X-KEY som gjelder for biten (med hel adresse), nil uten kryptering
    public let key: String?
    /// #EXT-X-MAP som gjelder for biten (med hel adresse)
    public let map: String?
}

/// En medieliste (bitene i en direktesending).
public struct HLSMedia: Equatable, Sendable {
    public let targetDuration: Int
    public let mediaSequence: Int
    public let segments: [HLSSegment]
    /// #EXT-X-ENDLIST: ikke en direktesending (et opptak eller en film)
    public let ended: Bool
    /// bitene er deler av en fil (#EXT-X-BYTERANGE): det kan ikke bufferet
    public let byteRanges: Bool
}

public enum HLSPlaylist: Equatable, Sendable {
    case master([HLSVariant])
    case media(HLSMedia)
}

/// Attributtene i en HLS-linje (BANDWIDTH=…,URI="…"), med anførselstegnene tatt bort.
func hlsAttributes(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    var key = ""
    var value = ""
    var inValue = false
    var quoted = false
    func flush() {
        let k = key.trimmingCharacters(in: .whitespaces)
        if !k.isEmpty { out[k.uppercased()] = value }
        key = ""
        value = ""
        inValue = false
    }
    for c in text {
        if inValue {
            if c == "\"" {
                quoted.toggle()
            } else if c == ",", !quoted {
                flush()
            } else {
                value.append(c)
            }
        } else if c == "=" {
            inValue = true
        } else if c == "," {
            key = ""
        } else {
            key.append(c)
        }
    }
    if inValue { flush() }
    return out
}

/// [line] (en #EXT-X-KEY eller #EXT-X-MAP) med URI="…" som hel adresse.
func absoluteURI(in line: String, base: URL) -> String {
    guard let start = line.range(of: "URI=\""), let end = line[start.upperBound...].firstIndex(of: "\"") else {
        return line
    }
    let uri = String(line[start.upperBound..<end])
    guard let absolute = URL(string: uri, relativeTo: base)?.absoluteURL else { return line }
    return line.replacingCharacters(in: start.upperBound..<end, with: absolute.absoluteString)
}

/// Leser en HLS-spilleliste; [base] er adressen den kom fra (bitene og variantene står ofte relativt til den).
public func parseHLS(_ text: String, base: URL) -> HLSPlaylist? {
    let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    guard lines.first?.hasPrefix("#EXTM3U") == true else { return nil }
    if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
        var audioWithURI = Set<String>()
        for line in lines where line.hasPrefix("#EXT-X-MEDIA:") {
            let a = hlsAttributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
            if a["TYPE"] == "AUDIO", a["URI"] != nil, let group = a["GROUP-ID"] { audioWithURI.insert(group) }
        }
        var variants: [HLSVariant] = []
        var pending: [String: String]?
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pending = hlsAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            } else if !line.hasPrefix("#"), !line.isEmpty, let attributes = pending {
                pending = nil
                guard let url = URL(string: line, relativeTo: base)?.absoluteURL else { continue }
                variants.append(HLSVariant(url: url, bandwidth: Int(attributes["BANDWIDTH"] ?? "") ?? 0,
                                           separateAudio: attributes["AUDIO"].map { audioWithURI.contains($0) } ?? false))
            }
        }
        return .master(variants)
    }
    var target = 10
    var sequence = 0
    var segments: [HLSSegment] = []
    var duration: Double?
    var discontinuity = false
    var key: String?
    var map: String?
    var ended = false
    var byteRanges = false
    for line in lines {
        if line.hasPrefix("#EXT-X-TARGETDURATION:") {
            target = Int(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? target
        } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
            sequence = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
        } else if line.hasPrefix("#EXTINF:") {
            let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first ?? ""
            duration = Double(value.trimmingCharacters(in: .whitespaces)) ?? Double(target)
        } else if line.hasPrefix("#EXT-X-DISCONTINUITY"), !line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") {
            discontinuity = true
        } else if line.hasPrefix("#EXT-X-KEY:") {
            let method = hlsAttributes(String(line.dropFirst("#EXT-X-KEY:".count)))["METHOD"]
            key = method == nil || method == "NONE" ? nil : absoluteURI(in: line, base: base)
        } else if line.hasPrefix("#EXT-X-MAP:") {
            map = absoluteURI(in: line, base: base)
        } else if line.hasPrefix("#EXT-X-BYTERANGE") {
            byteRanges = true
        } else if line.hasPrefix("#EXT-X-ENDLIST") {
            ended = true
        } else if !line.hasPrefix("#"), !line.isEmpty, let length = duration {
            duration = nil
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL else { continue }
            segments.append(HLSSegment(sequence: sequence + segments.count, duration: length, url: url,
                                       discontinuity: discontinuity, key: key, map: map))
            discontinuity = false
        }
    }
    return .media(HLSMedia(targetDuration: target, mediaSequence: sequence, segments: segments, ended: ended,
                           byteRanges: byteRanges))
}

/// Varianten som brukes: den med høyest bitrate av dem som har lyden i seg (nil: ingen kan bufferes).
public func chooseVariant(_ variants: [HLSVariant]) -> HLSVariant? {
    variants.filter { !$0.separateAudio }.max { $0.bandwidth < $1.bandwidth }
}

/// Bitene som er hentet, de eldste først, med det spillelista til Apple sin avspiller trenger: lengden, om det er et
/// brudd foran (en ny strøm, eller bitene som mangler etter et hull), krypteringen og filnavnet. Det eldste fjernes når
/// det er mer enn [maxDuration] eller [maxBytes] (så holder det til omtrent en halvtime).
public struct ShiftBuffer: Sendable {
    public struct Entry: Equatable, Sendable {
        public let sequence: Int
        public let duration: Double
        public let discontinuity: Bool
        public let key: String?
        public let map: String?
        public let file: String
        public let bytes: Int
    }

    public private(set) var entries: [Entry] = []
    /// bruddene som er fjernet fra begynnelsen (#EXT-X-DISCONTINUITY-SEQUENCE)
    public private(set) var discontinuitySequence = 0
    /// den siste biten fra leverandøren som er tatt med (nummeret i leverandørens liste)
    public private(set) var lastRemote: Int?
    private var nextLocal = 0
    private var targetDuration = 1
    public let maxDuration: TimeInterval
    public let maxBytes: Int

    /// så mange biter fra slutten tas med når det begynner (rett før direkte)
    public static let startSegments = 3

    public init(maxDuration: TimeInterval = 1800, maxBytes: Int = 1_500_000_000) {
        self.maxDuration = maxDuration
        self.maxBytes = maxBytes
    }

    public var duration: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
    public var bytes: Int { entries.reduce(0) { $0 + $1.bytes } }

    /// Bitene i [media] som ikke er hentet, i rekkefølge: de siste ved start, ellers de etter den siste. Er
    /// leverandørens nummer gått tilbake (strømmen startet på nytt), er alle nye.
    public func newSegments(in media: HLSMedia) -> [HLSSegment] {
        guard let last = lastRemote else { return Array(media.segments.suffix(Self.startSegments)) }
        let newest = media.segments.last?.sequence ?? last
        if newest < last { return media.segments }
        return media.segments.filter { $0.sequence > last }
    }

    /// Legger til en hentet bit (nummeret og filnavnet fra `nextName`), og gir filene som skal slettes (det eldste).
    public mutating func add(_ segment: HLSSegment, file: String, bytes: Int, targetDuration: Int) -> [String] {
        // et hull (biter som aldri ble hentet) eller en ny strøm: et brudd, så spilleren ikke går i stå
        let gap = lastRemote.map { segment.sequence != $0 + 1 } ?? false
        entries.append(Entry(sequence: nextLocal, duration: segment.duration,
                             discontinuity: !entries.isEmpty && (segment.discontinuity || gap),
                             key: segment.key, map: segment.map, file: file, bytes: bytes))
        nextLocal += 1
        lastRemote = segment.sequence
        self.targetDuration = max(self.targetDuration, targetDuration, Int(segment.duration.rounded(.up)))
        var removed: [String] = []
        while entries.count > Self.startSegments, duration > maxDuration || self.bytes > maxBytes {
            let first = entries.removeFirst()
            if entries.first?.discontinuity == true {
                // bruddet foran den nye første forsvinner fra lista
                discontinuitySequence += 1
                let next = entries.removeFirst()
                entries.insert(Entry(sequence: next.sequence, duration: next.duration, discontinuity: false,
                                     key: next.key, map: next.map, file: next.file, bytes: next.bytes), at: 0)
            }
            removed.append(first.file)
        }
        return removed
    }

    /// Filnavnet for den neste biten (med filtypen fra leverandøren: ts, aac, m4s …).
    public func nextName(for segment: HLSSegment) -> String {
        let ext = segment.url.pathExtension.lowercased()
        return "\(nextLocal).\(ext.isEmpty || ext.count > 4 ? "ts" : ext)"
    }

    /// Spillelista til Apple sin avspiller: alt som er hentet (en direktesending, uten slutt).
    public func playlist() -> String {
        var lines = ["#EXTM3U", "#EXT-X-VERSION:\(entries.contains { $0.map != nil } ? 6 : 3)",
                     "#EXT-X-TARGETDURATION:\(targetDuration)",
                     "#EXT-X-MEDIA-SEQUENCE:\(entries.first?.sequence ?? nextLocal)",
                     "#EXT-X-DISCONTINUITY-SEQUENCE:\(discontinuitySequence)"]
        var key: String?
        var map: String?
        for (index, entry) in entries.enumerated() {
            if entry.discontinuity { lines.append("#EXT-X-DISCONTINUITY") }
            if index == 0 || entry.key != key {
                if let k = entry.key {
                    lines.append(k)
                } else if index > 0 {
                    lines.append("#EXT-X-KEY:METHOD=NONE")
                }
                key = entry.key
            }
            if let m = entry.map, index == 0 || m != map {
                lines.append(m)
                map = m
            }
            lines.append("#EXTINF:\(String(format: "%.3f", entry.duration)),")
            lines.append(entry.file)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
