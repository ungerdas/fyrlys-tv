@testable import FyrlysCore
import Foundation
import XCTest

/// Egne strømmer: adressene kjennes igjen på kanalnavnet (oppdiktede adresser).
final class StreamTests: XCTestCase {
    func testChannelKeys() {
        XCTAssertEqual(channelKey("NO: NRK1 HD"), "nrk1")
        XCTAssertEqual(channelKey("NO | NRK 1"), "nrk1")
        XCTAssertEqual(channelKey("[NO] NRK1 FHD"), "nrk1")
        XCTAssertEqual(channelKey("NO - NRK Super"), "nrksuper")
        XCTAssertEqual(channelKey("NRK Super HD"), "nrksuper")
        XCTAssertEqual(channelKey("NRK1 Midtnytt"), "nrk1midtnytt")
        XCTAssertEqual(channelKey("NRK3 | Norge"), "nrk3")
        XCTAssertEqual(channelKey("TV 2 Direkte"), "tv2direkte")
        XCTAssertEqual(channelKey(of: URL(string: "https://cdn.example.com/edge/nrk1/muxed.m3u8")!), "nrk1")
        XCTAssertEqual(channelKey(of: URL(string: "https://cdn.example.com/live/fjordkanalen.m3u8")!), "fjordkanalen")
        XCTAssertEqual(channelKey(of: URL(string: "https://cdn.example.com/nrksuper/index.m3u8?token=1")!), "nrksuper")
    }

    func testBuiltIn() {
        XCTAssertEqual(builtInStreams.map(\.key), ["nrk1", "nrk2", "nrk3", "nrksuper"])
        XCTAssertTrue(builtInStreams.allSatisfy { $0.url.scheme == "https" && $0.url.pathExtension == "m3u8" })
    }

    func testParse() {
        let found = parseStreamOverrides("""
        https://cdn.example.com/edge/nrk1/muxed.m3u8
          https://cdn.example.com/edge/nrk2/muxed.m3u8

        # en kommentar
        NRK Super = https://cdn.example.com/a/b/index.m3u8
        Fjordkanalen: http://192.168.1.10:8080/stream.m3u8
        https://cdn.example.com/edge/nrk1/muxed.m3u8
        ikke en adresse
        """)
        XCTAssertEqual(found.map(\.key), ["nrk1", "nrk2", "nrksuper", "fjordkanalen"])
        XCTAssertEqual(found[2].url.absoluteString, "https://cdn.example.com/a/b/index.m3u8")
        XCTAssertEqual(found[3].url.absoluteString, "http://192.168.1.10:8080/stream.m3u8")
    }
}
