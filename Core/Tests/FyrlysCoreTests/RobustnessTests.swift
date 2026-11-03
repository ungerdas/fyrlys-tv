@testable import FyrlysCore
import Foundation
import XCTest

/// Det leverandørene og brukerne kan finne på: rare adresser, tall og svar (gjennomgangen 3.11.2026).
final class RobustnessTests: XCTestCase {
    func testBadServerAddressIsAnErrorNotACrash() async throws {
        // bokstaven O i porten: før krasjet appen ved innloggingen
        let bad = XtreamClient(login: Login(server: "iptv.example.com:8O8O", username: "u", password: "p")) { _ in
            XCTFail("skulle ikke spørre")
            return (Data(), 200)
        }
        do {
            _ = try await bad.account()
            XCTFail("ingen feil")
        } catch let error as SourceError {
            XCTAssertTrue(error.message.contains("8O8O"), error.message)
        }
        // mellomrom inni adressen fjernes
        XCTAssertEqual(Login.normalize(" iptv.example.com :8080 "), "http://iptv.example.com:8080")
    }

    func testPlusInPasswordIsEncoded() throws {
        let client = XtreamClient(login: Login(server: "http://iptv.example", username: "kari", password: "a+b&c"))
        let url = try client.apiURL().absoluteString
        XCTAssertTrue(url.contains("password=a%2Bb%26c"), url)
    }

    func testDeniedListIsAnError() async {
        // feil passord: noen leverandører svarer med kontoen og auth 0 i stedet for lista
        let denied = XtreamClient(login: Login(server: "http://iptv.example", username: "u", password: "p")) { _ in
            (Data(#"{"user_info": {"auth": 0}}"#.utf8), 200)
        }
        do {
            _ = try await denied.channels()
            XCTFail("ingen feil")
        } catch {
            XCTAssertEqual((error as? SourceError)?.message, L("Serveren avviste innloggingen"))
        }
    }

    func testListAsObject() throws {
        // lista som et objekt med «0», «1», … (i rekkefølgen til nøklene, også 10 etter 9)
        var map: [String: Any] = [:]
        for i in 0..<11 { map[String(i)] = ["stream_id": 100 + i, "name": "Kanal \(i)", "category_id": "1"] }
        XCTAssertEqual(parseChannels(map).map(\.id), (0..<11).map { String(100 + $0) })
        XCTAssertEqual(parseCategories(["1": ["category_id": "7", "category_name": "Sport"]]).map(\.name), ["Sport"])
        XCTAssertTrue(parseChannels(["user_info": ["auth": 1]]).isEmpty)
    }

    func testOddNumbersDoNotCrash() {
        XCTAssertNil(int(Double.nan))
        XCTAssertNil(int(Double.infinity))
        XCTAssertNil(int("nan"))
        XCTAssertNil(int("1e19"))
        XCTAssertEqual(int("12.0"), 12)
        XCTAssertEqual(text(Double.nan), "")
        XCTAssertEqual(text(1e19), "1e+19")
        XCTAssertEqual(text(3.0), "3")
        let series = parseSeriesInfo(["episodes": ["1": [["id": "1", "episode_num": "NaN", "season": "inf"]]]])
        XCTAssertEqual(series.seasons.first?.episodes.first?.number, 0)
    }

    func testPlainTextIsNotDecodedAsBase64() {
        XCTAssertEqual(base64Text("Film"), "Film")
        XCTAssertEqual(base64Text("TBA"), "TBA")
        XCTAssertEqual(base64Text("Sport"), "Sport")
        XCTAssertEqual(base64Text(Data("Dagsrevyen".utf8).base64EncodedString()), "Dagsrevyen")
        XCTAssertEqual(base64Text(Data("Været i dag".utf8).base64EncodedString()), "Været i dag")
    }

    func testDurations() {
        XCTAssertEqual(durationText("01:32:00"), "1 t 32 min")
        XCTAssertEqual(durationText("00:44:40"), "45 min")
        XCTAssertEqual(durationText("02:00:00"), "2 t")
        XCTAssertEqual(durationText("45 min"), "45 min")
        XCTAssertEqual(durationText(""), "")
        XCTAssertEqual(minutes(6_720_000), "1 t 52 min")
        XCTAssertEqual(parseMovieInfo(["info": ["duration": "01:32:00"]]).duration, "1 t 32 min")
    }

    func testSpecialsLast() {
        let d = parseSeriesInfo(["episodes": ["0": [["id": "9", "season": 0, "episode_num": 1]],
                                              "1": [["id": "1", "season": 1, "episode_num": 1]],
                                              "2": [["id": "2", "season": 2, "episode_num": 1]]]])
        XCTAssertEqual(d.seasons.map(\.number), [1, 2, 0])
    }

    func testCountries() {
        XCTAssertEqual(channelKeyAndCountry("TV 2 HD DK").key, "tv2")
        XCTAssertEqual(channelKeyAndCountry("TV 2 HD DK").country, "dk")
        XCTAssertEqual(channelKeyAndCountry("DK: TV 2").country, "dk")
        XCTAssertEqual(channelKeyAndCountry("NRK 1 HD NO").country, "no")
        XCTAssertNil(channelKeyAndCountry("NRK1 HD").country)
        // «TV: noe» er ikke et land
        XCTAssertNil(channelKeyAndCountry("TV: Noe").country)
    }

    func testSlashBothWays() {
        let keys: Set<String> = ["nrk3", "nrksuper"]
        XCTAssertEqual(matchingStreamKeys("NRK3/NRK Super", in: keys).map(\.key), ["nrk3", "nrksuper"])
        XCTAssertEqual(matchingStreamKeys("NRK 3/SUPER NO", in: keys).map(\.key), ["nrk3", "nrksuper"])
        XCTAssertEqual(matchingStreamKeys("NRK Super/NRK3 HD", in: keys).map(\.key), ["nrksuper", "nrk3"])
    }

    /// En egen strøm for «TV 2» gjelder norsk TV 2, ikke den danske; en svensk kanal uten norsk variant får sin.
    func testOwnStreamsStayInTheirCountry() {
        let cats = [ChannelCategory(id: "no", name: "Norge"), ChannelCategory(id: "dk", name: "Danmark"),
                    ChannelCategory(id: "se", name: "Sverige")]
        let chans = [
            Channel(id: "1", name: "TV 2 HD NO", categoryId: "no", logo: "a.png"),
            Channel(id: "2", name: "TV 2 FHD", categoryId: "no"),
            Channel(id: "3", name: "TV 2 HD DK", categoryId: "dk", logo: "b.png"),
            Channel(id: "4", name: "DK: TV 2", categoryId: "dk"),
            Channel(id: "5", name: "SVT1 SE", categoryId: "se"),
        ]
        let index = ChannelIndex(Lists(categories: cats, channels: chans), merging: ["tv2", "svt1"])
        XCTAssertEqual(index.channels.map(\.id), ["1", "3", "4", "5"])
        XCTAssertEqual(index.channels(in: "dk").map(\.id), ["3", "4"])
        XCTAssertEqual(index.streamKey(of: index.byId["1"]!), "tv2")
        XCTAssertEqual(index.streamKey(of: index.byId["2"]!), "tv2")
        XCTAssertNil(index.streamKey(of: index.byId["3"]!))
        XCTAssertNil(index.streamKey(of: index.byId["4"]!))
        XCTAssertEqual(index.streamKey(of: index.byId["5"]!), "svt1")
        XCTAssertEqual(index.streamNames["tv2"], ["TV 2 HD NO", "TV 2 FHD"])
        XCTAssertEqual(index.streamNames["svt1"], ["SVT1 SE"])
    }
}
