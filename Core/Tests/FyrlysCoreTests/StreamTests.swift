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
        // landskoden bak, og lydtekst/tegnspråk er samme kanal
        XCTAssertEqual(channelKey("NRK 1 HD NO"), "nrk1")
        XCTAssertEqual(channelKey("NRK 1 FHD NO"), "nrk1")
        XCTAssertEqual(channelKey("NRK 2 Lydtekst HD NO"), "nrk2")
        XCTAssertEqual(channelKey("NRK1 Tegnspråk"), "nrk1")
        XCTAssertEqual(channelKey("TV 2 NO"), "tv2")
        XCTAssertEqual(channelKey("NO"), "no")
        XCTAssertEqual(channelAlternatives("NRK 3/SUPER HD NO"), ["NRK 3 HD NO", "NRK SUPER HD NO"])
        XCTAssertEqual(channelAlternatives("NRK1 HD"), ["NRK1 HD"])
        let both = matchingStreamKeys("NRK 3/SUPER NO", in: ["nrk3", "nrksuper"])
        XCTAssertEqual(both.map(\.key), ["nrk3", "nrksuper"])
        XCTAssertEqual(both.map(\.name), ["NRK 3 NO", "NRK SUPER NO"])
        XCTAssertEqual(matchingStreamKeys("NRK 3/SUPER NO", in: ["nrk3"]).map(\.key), ["nrk3"])
        XCTAssertTrue(matchingStreamKeys("Sport 24/7", in: ["nrk3"]).isEmpty)
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

    /// Navnene slik én leverandør har dem: landskoden bak, lydtekst, og NRK3 og NRK Super på samme plass.
    func testMergingWithCountryLast() {
        let cats = [ChannelCategory(id: "1", name: "Norway"), ChannelCategory(id: "2", name: "Norway FHD")]
        let chans = [
            Channel(id: "9", name: "N1 Info & Updates NO", categoryId: "1"),
            Channel(id: "10", name: "NRK 1 HD NO", categoryId: "1", logo: "nrk1.png"),
            Channel(id: "11", name: "NRK 1 FHD NO", categoryId: "2", logo: "nrk1.png"),
            Channel(id: "20", name: "NRK 2 HD NO", categoryId: "1", logo: "nrk2.png"),
            Channel(id: "21", name: "NRK 2 FHD NO", categoryId: "2", logo: "nrk2.png"),
            Channel(id: "22", name: "NRK 2 Lydtekst HD NO", categoryId: "1", logo: "nrk2.png"),
            Channel(id: "30", name: "NRK 3/SUPER NO", categoryId: "1", logo: "nrk3.png", archiveDays: 7),
            Channel(id: "31", name: "NRK 3/SUPER HD NO", categoryId: "1", logo: "nrk3.png"),
            Channel(id: "40", name: "TV 2 Direkte NO", categoryId: "1"),
        ]
        let lists = Lists(categories: cats, channels: chans)
        let index = ChannelIndex(lists, merging: Set(builtInStreams.map(\.key)))
        XCTAssertEqual(index.channels.map(\.id), ["9", "10", "20", "30", "30~nrksuper", "40"])
        XCTAssertEqual(index.channels.map(\.name),
                       ["N1 Info & Updates NO", "NRK 1 HD NO", "NRK 2 HD NO", "NRK 3 NO", "NRK SUPER NO",
                        "TV 2 Direkte NO"])
        XCTAssertEqual(index.channels(in: "2").map(\.id), ["10", "20"])
        // NRK Super er delt ut av NRK 3/SUPER: programinfoen og arkivet derfra, men ikke NRK3-logoen
        let superChannel = index.byId["30~nrksuper"]!
        XCTAssertEqual(superChannel.streamId, "30")
        XCTAssertEqual(superChannel.archiveDays, 7)
        XCTAssertNil(superChannel.logo)
        XCTAssertEqual(index.byId["31~nrksuper"]?.id, "30~nrksuper")
        XCTAssertEqual(index.byId["31"]?.id, "30")
        XCTAssertEqual(index.byId["22"]?.id, "20")
        XCTAssertEqual(index.ids(of: index.byId["20"]!), ["20", "21", "22"])
        XCTAssertEqual(index.search("super", favoring: []).map(\.id), ["30~nrksuper"])
        // adressen hos leverandøren er kanalen den er delt ut av
        let client = XtreamClient(login: Login(server: "http://iptv.example.com", username: "u", password: "p"))
        XCTAssertEqual(client.liveURL(superChannel).lastPathComponent, "30.m3u8")
        // uten egne strømmer er alt som før
        XCTAssertEqual(ChannelIndex(lists).channels.count, chans.count)
    }
}
