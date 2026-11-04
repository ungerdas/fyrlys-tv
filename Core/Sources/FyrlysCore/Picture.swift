import Foundation

/// Bildeformatet i spilleren, som i Fyrlys for Windows (`lib/core/picture.dart`): som kanalen sender det, fylt
/// (kantene skjæres bort), strukket, eller tvunget til 16:9 eller 4:3 (for kanaler som sender feil format). Huskes per
/// kanal.
public enum PictureFormat: String, CaseIterable, Sendable {
    case original, zoom, stretch, wide, classic

    /// Det lagrede navnet (ukjent eller nil: original).
    public static func parse(_ name: String?) -> PictureFormat {
        name.flatMap(PictureFormat.init(rawValue:)) ?? .original
    }

    /// det neste i lista
    public var next: PictureFormat {
        let all = PictureFormat.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// forholdet bildet tvinges til (nil: det strømmen sier)
    public var aspectRatio: Double? {
        switch self {
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .original: return L("Original")
        case .zoom: return L("Fyll skjermen")
        case .stretch: return L("Strekk")
        case .wide: return "16:9"
        case .classic: return "4:3"
        }
    }

    public var detail: String {
        switch self {
        case .original: return L("Som kanalen sender det")
        case .zoom: return L("Uten svarte kanter; litt av bildet skjæres bort")
        case .stretch: return L("Uten svarte kanter; bildet strekkes")
        case .wide: return L("For bilder som ser klemt ut")
        case .classic: return L("For bilder som ser strukket ut")
        }
    }
}

/// Bildeformatene som er valgt per kanal (bare de som ikke er «Original»), som tekst til lagringen og tilbake.
public struct PictureFormats: Equatable, Sendable {
    public private(set) var byChannel: [String: PictureFormat] = [:]

    public init(_ stored: [String: String] = [:]) {
        for (channel, name) in stored {
            let format = PictureFormat.parse(name)
            if format != .original { byChannel[channel] = format }
        }
    }

    public func format(for channelId: String) -> PictureFormat { byChannel[channelId] ?? .original }

    public mutating func set(_ format: PictureFormat, for channelId: String) {
        byChannel[channelId] = format == .original ? nil : format
    }

    public var stored: [String: String] { byChannel.mapValues(\.rawValue) }
}

// ── strøminfoen ──

/// «8,1 Mbit/s» (eller «850 kbit/s») fra bit per sekund; desimalpunktum på engelsk.
public func bitrateText(_ bits: Double) -> String {
    if bits >= 1e6 {
        let n = String(format: "%.1f", bits / 1e6)
        return "\(appLanguage == "en" ? n : n.replacingOccurrences(of: ".", with: ",")) Mbit/s"
    }
    return "\(Int((bits / 1e3).rounded())) kbit/s"
}

/// «H.264», «H.265», «AAC», «AC3», «E-AC3» … fra en FourCC («avc1», «hvc1», «mp4a», «ac-3», «ec-3») eller et navn
/// («h264»); ukjente med store bokstaver.
public func codecName(_ code: String) -> String {
    let c = code.trimmingCharacters(in: .whitespaces).lowercased()
    switch c {
    case "avc1", "avc3", "h264", "x264": return "H.264"
    case "hvc1", "hev1", "hevc", "h265", "x265": return "H.265"
    case "dvh1", "dvhe": return "Dolby Vision"
    case "av01", "av1": return "AV1"
    case "vp09", "vp9": return "VP9"
    case "mp2v", "mpeg2video": return "MPEG-2"
    case "mp4a", "aac": return "AAC"
    case "ac-3", "ac3": return "AC3"
    case "ec-3", "eac3": return "E-AC3"
    case "ac-4", "ac4": return "AC-4"
    case ".mp3", "mp3", "mp2": return "MP3"
    case "opus": return "Opus"
    case "flac": return "FLAC"
    default: return code.trimmingCharacters(in: .whitespaces).uppercased()
    }
}

/// «mono», «stereo», «5.1», «7.1» (ellers «6 kanaler»)
public func channelLayout(_ channels: Int) -> String {
    switch channels {
    case 1: return L("mono")
    case 2: return L("stereo")
    case 6: return "5.1"
    case 8: return "7.1"
    default: return L("{n} kanaler", ["n": channels])
    }
}

/// Det avspilleren vet om strømmen, som én linje: «1920×1080 · H.264 · 50 fps · 8,1 Mbit/s · AAC stereo · 3 tapte
/// bilder» (det som ikke er kjent, står ikke).
public struct StreamInfo: Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var videoCodec: String?
    public var fps: Double?
    public var bitrate: Double?
    public var audioCodec: String?
    public var audioChannels: Int?
    public var dropped = 0
    public var stalls = 0

    public init() {}

    public var isEmpty: Bool { line.isEmpty }

    public var line: String {
        var parts: [String] = []
        if let width, let height, width > 0, height > 0 { parts.append("\(width)×\(height)") }
        if let videoCodec, !videoCodec.isEmpty { parts.append(codecName(videoCodec)) }
        if let fps, fps > 0 { parts.append("\(Int(fps.rounded())) fps") }
        if let bitrate, bitrate > 0 { parts.append(bitrateText(bitrate)) }
        if let audioCodec, !audioCodec.isEmpty {
            parts.append(([codecName(audioCodec)] + (audioChannels.map { [channelLayout($0)] } ?? [])).joined(separator: " "))
        }
        if dropped == 1 { parts.append(L("1 tapt bilde")) }
        if dropped > 1 { parts.append(L("{n} tapte bilder", ["n": dropped])) }
        if stalls == 1 { parts.append(L("stoppet 1 gang")) }
        if stalls > 1 { parts.append(L("stoppet {n} ganger", ["n": stalls])) }
        return parts.joined(separator: " · ")
    }
}

/// En FourCC (fra et CMFormatDescription) som tekst: 0x61766331 → «avc1».
public func fourCCText(_ code: UInt32) -> String {
    let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(code) }
    return String(decoding: bytes, as: UTF8.self)
}
