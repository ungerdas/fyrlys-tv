@testable import FyrlysCore
import Foundation
import XCTest

/// Spillelistene fra leverandøren og bufferet for pause og tilbakespoling i direktesending.
final class LiveShiftTests: XCTestCase {
    let base = URL(string: "http://iptv.example.com/live/u/p/1.m3u8")!

    func testMasterPlaylist() {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Norsk",URI="lyd/index.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        lav/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
        https://cdn.example.com/hoy/index.m3u8?token=a,b
        #EXT-X-STREAM-INF:BANDWIDTH=9000000,AUDIO="aud"
        egen-lyd/index.m3u8
        """
        guard case .master(let variants) = parseHLS(text, base: base) else { return XCTFail("ikke en hovedliste") }
        XCTAssertEqual(variants.map(\.bandwidth), [800_000, 5_000_000, 9_000_000])
        XCTAssertEqual(variants[0].url.absoluteString, "http://iptv.example.com/live/u/p/lav/index.m3u8")
        XCTAssertEqual(variants[1].url.absoluteString, "https://cdn.example.com/hoy/index.m3u8?token=a,b")
        XCTAssertTrue(variants[2].separateAudio, "lyden i en egen spilleliste")
        XCTAssertEqual(chooseVariant(variants)?.bandwidth, 5_000_000, "den beste med lyden i seg")
        XCTAssertNil(chooseVariant([variants[2]]))
        XCTAssertEqual(hlsAttributes(#"BANDWIDTH=1,CODECS="a,b",X=y"#), ["BANDWIDTH": "1", "CODECS": "a,b", "X": "y"])
    }

    func testMediaPlaylist() {
        let text = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:4711
        #EXTINF:10.000,
        4711.ts
        #EXT-X-DISCONTINUITY
        #EXT-X-KEY:METHOD=AES-128,URI="nokkel?id=1",IV=0x01
        #EXTINF:9.6,tittel
        https://cdn.example.com/4712.ts
        #EXT-X-KEY:METHOD=NONE
        #EXTINF:10,
        4713.ts
        """
        guard case .media(let media) = parseHLS(text, base: base) else { return XCTFail("ikke en medieliste") }
        XCTAssertEqual(media.targetDuration, 10)
        XCTAssertEqual(media.mediaSequence, 4711)
        XCTAssertFalse(media.ended)
        XCTAssertFalse(media.byteRanges)
        XCTAssertEqual(media.segments.map(\.sequence), [4711, 4712, 4713])
        XCTAssertEqual(media.segments.map(\.duration), [10, 9.6, 10])
        XCTAssertEqual(media.segments[0].url.absoluteString, "http://iptv.example.com/live/u/p/4711.ts")
        XCTAssertEqual(media.segments[1].url.absoluteString, "https://cdn.example.com/4712.ts")
        XCTAssertEqual(media.segments.map(\.discontinuity), [false, true, false])
        XCTAssertEqual(media.segments[1].key,
                       #"#EXT-X-KEY:METHOD=AES-128,URI="http://iptv.example.com/live/u/p/nokkel?id=1",IV=0x01"#)
        XCTAssertNil(media.segments[2].key)
        XCTAssertNil(parseHLS("<html></html>", base: base))
        guard case .media(let film) = parseHLS("#EXTM3U\n#EXTINF:5,\na.ts\n#EXT-X-ENDLIST\n", base: base) else {
            return XCTFail("ikke en medieliste")
        }
        XCTAssertTrue(film.ended)
    }

    func media(_ first: Int, count: Int = 4, duration: Double = 6) -> HLSMedia {
        HLSMedia(targetDuration: 6, mediaSequence: first,
                 segments: (0..<count).map { i in
                     HLSSegment(sequence: first + i, duration: duration,
                                url: URL(string: "http://iptv.example.com/\(first + i).ts")!,
                                discontinuity: false, key: nil, map: nil)
                 },
                 ended: false, byteRanges: false)
    }

    func testBufferGrowsAndPlaylist() {
        var buffer = ShiftBuffer(maxDuration: 60, maxBytes: 10_000)
        // ved start: de tre siste
        let start = buffer.newSegments(in: media(100, count: 5))
        XCTAssertEqual(start.map(\.sequence), [102, 103, 104])
        for segment in start {
            XCTAssertTrue(buffer.add(segment, file: buffer.nextName(for: segment), bytes: 100, targetDuration: 6).isEmpty)
        }
        XCTAssertEqual(buffer.entries.map(\.file), ["0.ts", "1.ts", "2.ts"])
        XCTAssertEqual(buffer.duration, 18)
        // neste gang: bare de nye
        XCTAssertEqual(buffer.newSegments(in: media(102, count: 5)).map(\.sequence), [105, 106])
        XCTAssertEqual(buffer.playlist(), """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-DISCONTINUITY-SEQUENCE:0
        #EXTINF:6.000,
        0.ts
        #EXTINF:6.000,
        1.ts
        #EXTINF:6.000,
        2.ts

        """)
    }

    func testBufferGapsAndRestarts() {
        var buffer = ShiftBuffer()
        for segment in buffer.newSegments(in: media(10, count: 3)) {
            _ = buffer.add(segment, file: buffer.nextName(for: segment), bytes: 1, targetDuration: 6)
        }
        // et hull (13 og 14 ble aldri hentet): et brudd foran 15
        let after = media(15, count: 2)
        for segment in buffer.newSegments(in: after) {
            _ = buffer.add(segment, file: buffer.nextName(for: segment), bytes: 1, targetDuration: 6)
        }
        XCTAssertEqual(buffer.entries.map(\.discontinuity), [false, false, false, true, false])
        // strømmen startet på nytt (nummeret gikk tilbake): alt er nytt, med et brudd foran
        let restarted = buffer.newSegments(in: media(0, count: 2))
        XCTAssertEqual(restarted.map(\.sequence), [0, 1])
        for segment in restarted {
            _ = buffer.add(segment, file: buffer.nextName(for: segment), bytes: 1, targetDuration: 6)
        }
        XCTAssertEqual(buffer.entries.suffix(2).map(\.discontinuity), [true, false])
        XCTAssertTrue(buffer.playlist().contains("#EXT-X-DISCONTINUITY\n#EXTINF:6.000,\n5.ts"))
    }

    func testBufferDropsTheOldest() {
        var buffer = ShiftBuffer(maxDuration: 30, maxBytes: 1_000_000)
        var removed: [String] = []
        var all: [HLSSegment] = []
        for first in stride(from: 0, to: 20, by: 2) {
            let next = buffer.newSegments(in: media(first, count: 3))
            all += next
            for segment in next {
                removed += buffer.add(segment, file: buffer.nextName(for: segment), bytes: 10, targetDuration: 6)
            }
        }
        XCTAssertLessThanOrEqual(buffer.duration, 30)
        XCTAssertEqual(buffer.entries.count, 5)
        XCTAssertEqual(removed.count, all.count - 5, "det eldste er slettet")
        XCTAssertEqual(removed.first, "0.ts")
        XCTAssertTrue(buffer.playlist().contains("#EXT-X-MEDIA-SEQUENCE:\(buffer.entries[0].sequence)"))
        // etter bytes: høyst 25 bytes, men aldri færre enn de tre siste
        var small = ShiftBuffer(maxDuration: 1000, maxBytes: 25)
        for segment in small.newSegments(in: media(0, count: 3)) {
            _ = small.add(segment, file: small.nextName(for: segment), bytes: 10, targetDuration: 6)
        }
        XCTAssertEqual(small.entries.count, 3)
        for segment in small.newSegments(in: media(1, count: 3)) {
            _ = small.add(segment, file: small.nextName(for: segment), bytes: 10, targetDuration: 6)
        }
        XCTAssertEqual(small.entries.count, 3)
    }

    func testBreakLeavesTheList() {
        var buffer = ShiftBuffer(maxDuration: 24, maxBytes: 1_000_000)
        let first = media(0, count: 3)
        for segment in buffer.newSegments(in: first) {
            _ = buffer.add(segment, file: buffer.nextName(for: segment), bytes: 1, targetDuration: 6)
        }
        // et brudd foran den fjerde, så to til: de eldste fjernes, og bruddet med dem
        let broken = HLSMedia(targetDuration: 6, mediaSequence: 3, segments: [
            HLSSegment(sequence: 3, duration: 6, url: URL(string: "http://iptv.example.com/3.ts")!, discontinuity: true,
                       key: nil, map: nil),
        ], ended: false, byteRanges: false)
        for segment in buffer.newSegments(in: broken) {
            _ = buffer.add(segment, file: buffer.nextName(for: segment), bytes: 1, targetDuration: 6)
        }
        XCTAssertEqual(buffer.entries.map(\.discontinuity), [false, false, false, true])
        XCTAssertTrue(buffer.playlist().contains("#EXT-X-DISCONTINUITY\n#EXTINF:6.000,\n3.ts"))
        for segment in buffer.newSegments(in: media(4, count: 4)) {
            _ = buffer.add(segment, file: buffer.nextName(for: segment), bytes: 1, targetDuration: 6)
        }
        XCTAssertEqual(buffer.entries.map(\.file), ["4.ts", "5.ts", "6.ts", "7.ts"])
        XCTAssertEqual(buffer.discontinuitySequence, 1, "bruddet er fjernet fra lista, så nummeret telles opp")
        XCTAssertFalse(buffer.playlist().contains("#EXT-X-DISCONTINUITY\n"))
        XCTAssertTrue(buffer.playlist().contains("#EXT-X-DISCONTINUITY-SEQUENCE:1"))
    }

    func testFileNames() {
        let buffer = ShiftBuffer()
        let ts = HLSSegment(sequence: 1, duration: 6, url: URL(string: "http://iptv.example.com/a/1.ts?x=1")!,
                            discontinuity: false, key: nil, map: nil)
        let none = HLSSegment(sequence: 1, duration: 6, url: URL(string: "http://iptv.example.com/a/seg")!,
                              discontinuity: false, key: nil, map: nil)
        let m4s = HLSSegment(sequence: 1, duration: 6, url: URL(string: "http://iptv.example.com/a/1.m4s")!,
                             discontinuity: false, key: nil, map: nil)
        XCTAssertEqual(buffer.nextName(for: ts), "0.ts")
        XCTAssertEqual(buffer.nextName(for: none), "0.ts")
        XCTAssertEqual(buffer.nextName(for: m4s), "0.m4s")
    }
}
