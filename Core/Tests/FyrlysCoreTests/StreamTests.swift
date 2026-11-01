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

    /// Kanaler som spilles fra samme egne strøm, blir én: den med programinfo og logo, i alle kategoriene.
    func testMerging() {
        let cats = [ChannelCategory(id: "1", name: "Norge"), ChannelCategory(id: "2", name: "Norge FHD"),
                    ChannelCategory(id: "3", name: "Sport")]
        let chans = [
            Channel(id: "10", name: "NO: NRK1 HD", categoryId: "1", logo: "a.png", hasEpg: false),
            Channel(id: "11", name: "NO: NRK 1", categoryId: "1", logo: "b.png", hasEpg: true),
            Channel(id: "12", name: "NRK1 FHD", categoryId: "2", hasEpg: false),
            Channel(id: "13", name: "NRK1 Midtnytt", categoryId: "1"),
            Channel(id: "20", name: "NO: NRK2", categoryId: "1"),
            Channel(id: "30", name: "Sportskanalen", categoryId: "3"),
        ]
        let plain = ChannelIndex(Lists(categories: cats, channels: chans))
        XCTAssertEqual(plain.channels.count, 6)
        let index = ChannelIndex(Lists(categories: cats, channels: chans), merging: ["nrk1", "nrk2", "nrksuper"])
        // NRK1 med programinfo (11) beholdes; Midtnytt er en annen kanal, NRK2 har ingen å slås sammen med
        XCTAssertEqual(index.channels.map(\.id), ["11", "13", "20", "30"])
        XCTAssertEqual(index.channels(in: "1").map(\.id), ["11", "13", "20"])
        XCTAssertEqual(index.channels(in: "2").map(\.id), ["11"])
        XCTAssertEqual(index.byId["12"]?.id, "11")
        XCTAssertEqual(index.byId["10"]?.id, "11")
        XCTAssertEqual(index.ids(of: index.byId["11"]!), ["11", "10", "12"])
        XCTAssertEqual(index.channels(favoring: ["2"]).map(\.id), ["11", "13", "20", "30"])
        XCTAssertEqual(index.search("nrk1", favoring: ["2"]).map(\.id), ["11", "13"])
        XCTAssertEqual(index.mergeKeys, ["nrk1", "nrk2", "nrksuper"])
        // favoritter og «sist sett» lagret med id-ene til flere av dem: kanalen én gang
        XCTAssertEqual(channels(["12", "20", "10", "11"], in: index.byId).map(\.id), ["11", "20"])
    }
}
