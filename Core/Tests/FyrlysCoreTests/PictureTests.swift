@testable import FyrlysCore
import XCTest

/// Bildeformatet per kanal og linja med strøminfo i spilleren.
final class PictureTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(PictureFormat.parse(nil), .original)
        XCTAssertEqual(PictureFormat.parse("zoom"), .zoom)
        XCTAssertEqual(PictureFormat.parse("ukjent"), .original)
        XCTAssertEqual(PictureFormat.classic.next, .original, "rundt")
        XCTAssertEqual(PictureFormat.original.next, .zoom)
        XCTAssertEqual(PictureFormat.wide.aspectRatio, 16.0 / 9.0)
        XCTAssertEqual(PictureFormat.classic.aspectRatio, 4.0 / 3.0)
        XCTAssertNil(PictureFormat.zoom.aspectRatio)
        XCTAssertEqual(PictureFormat.zoom.title, "Fyll skjermen")
        XCTAssertEqual(PictureFormat.wide.title, "16:9")
    }

    func testFormatsPerChannel() {
        var formats = PictureFormats(["1": "zoom", "2": "original", "3": "ukjent", "4": "wide"])
        XCTAssertEqual(formats.format(for: "1"), .zoom)
        XCTAssertEqual(formats.format(for: "9"), .original)
        XCTAssertEqual(formats.stored, ["1": "zoom", "4": "wide"], "bare de som ikke er «Original», lagres")
        formats.set(.original, for: "1")
        formats.set(.classic, for: "5")
        XCTAssertEqual(formats.stored, ["4": "wide", "5": "classic"])
    }

    func testStreamInfo() {
        XCTAssertEqual(bitrateText(8_100_000), "8,1 Mbit/s")
        XCTAssertEqual(bitrateText(850_400), "850 kbit/s")
        XCTAssertEqual(codecName("avc1"), "H.264")
        XCTAssertEqual(codecName("hev1"), "H.265")
        XCTAssertEqual(codecName("ec-3"), "E-AC3")
        XCTAssertEqual(codecName("mp4a"), "AAC")
        XCTAssertEqual(codecName("xyz1"), "XYZ1")
        XCTAssertEqual(channelLayout(2), "stereo")
        XCTAssertEqual(channelLayout(6), "5.1")
        XCTAssertEqual(channelLayout(3), "3 kanaler")
        XCTAssertEqual(fourCCText(0x6176_6331), "avc1")
        XCTAssertEqual(fourCCText(0x6563_2D33), "ec-3")
        XCTAssertEqual(fourCCText(3), "3")
        var info = StreamInfo()
        XCTAssertTrue(info.isEmpty)
        info.width = 1920
        info.height = 1080
        info.videoCodec = "avc1"
        info.fps = 50.0
        info.bitrate = 8_100_000
        info.audioCodec = "mp4a"
        info.audioChannels = 2
        info.dropped = 3
        XCTAssertEqual(info.line, "1920×1080 · H.264 · 50 fps · 8,1 Mbit/s · AAC stereo · 3 tapte bilder")
        info.dropped = 1
        info.stalls = 2
        info.audioChannels = nil
        XCTAssertEqual(info.line, "1920×1080 · H.264 · 50 fps · 8,1 Mbit/s · AAC · 1 tapt bilde · stoppet 2 ganger")
    }
}
