import Foundation
import XCTest
@testable import FyrlysCore

/// Ryddige navn og landene i kategorinavnene (som testene for Fyrlys for Windows 2.1.47, `test/tidy_test.dart`).
final class TidyTests: XCTestCase {
    /// Slik noen leverandører skriver lista: land foran kategoriene, et merke og kvaliteten i kanalnavnene, og NRK1 i
    /// både 1080p og 720p.
    let categories = [
        ChannelCategory(id: "no720", name: "NO: [720p] AND [H265]"),
        ChannelCategory(id: "no1080", name: "NO:   [1080p]"),
        ChannelCategory(id: "noppv", name: "NO: VIAPLAY [PPV EVENTS] [EXTRA] [1080p]"),
        ChannelCategory(id: "se", name: "SE: SPORT [1080p]"),
    ]
    let channels = [
        Channel(id: "1", name: "NRK1", categoryId: "no720", number: 1),
        Channel(id: "2", name: "NOR: TV 2 [720p]", categoryId: "no720", number: 2),
        Channel(id: "3", name: "NOR: TV 2 [H265]", categoryId: "no720", number: 3),
        Channel(id: "4", name: "VIP: AKVARIUM [1080p]", categoryId: "no1080", number: 4),
        Channel(id: "5", name: "VIP: NRK1 [1080p]", categoryId: "no1080", number: 5),
        Channel(id: "6", name: "VIP: NRK1 ØSTLANDET [1080p]", categoryId: "no1080", number: 6),
        Channel(id: "7", name: "NOR: VIAPLAY EVENT 1 [1080p]", categoryId: "noppv", number: 7),
        Channel(id: "8", name: "SWE: TV 4 [1080p]", categoryId: "se", number: 8),
        Channel(id: "9", name: "SWE: SPORT ULTRA [4K-Q]+", categoryId: "se", number: 9),
    ]

    override func setUp() {
        appLanguage = "no"
    }

    func testChannelNamesWithoutTagAndQuality() {
        func check(_ name: String, _ tidy: String, _ quality: String?, line: UInt = #line) {
            let result = tidyChannelName(name)
            XCTAssertEqual(result.name, tidy, name, line: line)
            XCTAssertEqual(result.quality, quality, name, line: line)
        }
        check("NOR: TV 2 [720p]", "TV 2", "720p")
        check("NOR: TV 2 [H265]", "TV 2", "H265")
        check("VIP: NRK1 ØSTLANDET [1080p]", "NRK1 ØSTLANDET", nil)
        check("NOR: TV 2 DIREKTE  [1080p]", "TV 2 DIREKTE", nil)
        check("NOR: SPORT ULTRA [4K-Q]+", "SPORT ULTRA", "4K")
        check("SWE: TV 4 [480p]", "TV 4", "480p")
        check("UK | BBC One [HD]", "BBC One", "HD")
        check("|NO| TV Norge (1080p)", "TV Norge", nil)
        check("[NO] NRK1", "NRK1", nil)
        // eventer beholder «LIVE:», og navn uten slike merker står som de er
        XCTAssertEqual(tidyChannelName("LIVE: Kamp i dag [1080p]").name, "LIVE: Kamp i dag")
        for name in ["NRK 1 HD", "15:00 Man United - Bournemouth | Premier League", "-= Sweden =-", "TV 2 HD NO"] {
            check(name, name, nil)
        }
        // ingenting igjen: navnet som det var
        XCTAssertEqual(tidyChannelName("NOR: [720p]").name, "NOR: [720p]")
    }

    func testCategoryNamesWithoutCountryAndUsualQuality() {
        XCTAssertEqual(tidyCategoryName("NO: VIAPLAY [PPV EVENTS] [EXTRA] [1080p]"), "VIAPLAY · PPV EVENTS · EXTRA")
        XCTAssertEqual(tidyCategoryName("NO: SPORT [720p] AND [H265]"), "SPORT · 720p · H265")
        XCTAssertEqual(tidyCategoryName("NO: [720p] AND [H265]"), "Norge · 720p · H265")
        XCTAssertEqual(tidyCategoryName("NO:   [1080p]"), "Norge")
        XCTAssertEqual(tidyCategoryName("NO: [PLUS] PLAY [1080p]"), "PLUS PLAY")
        XCTAssertEqual(tidyCategoryName("NO: TV2 PLAY  [1080p]"), "TV2 PLAY")
        // flere land: koden står igjen, så to like kategorier kan skilles
        XCTAssertEqual(tidyCategoryName("SE: SPORT [720p]", keepCountry: true), "SE · SPORT · 720p")
        XCTAssertEqual(tidyCategoryName("USA: NEWS [1080p]", keepCountry: true), "US · NEWS")
        XCTAssertEqual(tidyCategoryName("SE: [1080p]", keepCountry: true), "Sverige")
        for name in ["Viaplay Sport SE [B]", "Sweden - Sport", "Norge", "Sport"] {
            XCTAssertEqual(tidyCategoryName(name), name)
        }
    }

    func testCountryOfCategory() {
        let expected = [
            "NO: Sport": "NO",
            "NOR: Sport": "NO",
            "USA: News": "US",
            "|SE| Film": "SE",
            "[DK] Nyheter": "DK",
            "UK | Sports": "UK",
            "Norway - Sport": "NO",
            "Netherland - Algemeen": "NL",
            "Sweden": "SE",
            "Norge": "NO",
            "Viaplay Sport SE": "SE",
            "HBO Max Sports DK [B]": "DK",
            "ARA: Nyheter": "ARA",
        ]
        for (name, code) in expected { XCTAssertEqual(countryOf(name), code, name) }
        for name in ["World Padel Tour TV", "FIFA+ Events", "Sport", "24/7 Movies"] {
            XCTAssertNil(countryOf(name), name)
        }
        XCTAssertEqual(countryLabel("NO"), "Norge")
        XCTAssertEqual(countryLabel("ARA"), "Arabisk")
        XCTAssertEqual(countryLabel("AS"), "AS")
        XCTAssertEqual(countryLabel(""), "Uten land")
        appLanguage = "en"
        XCTAssertEqual(countryLabel("NO"), "Norway")
        appLanguage = "no"
    }

    func testCountryGroupsWithCountsAlphabeticalAndNoCountryLast() {
        // en tom kategori («Tom») telles ikke og er ikke eksempelet
        let more = [ChannelCategory(id: "t", name: "Tom"), ChannelCategory(id: "x", name: "Sport")]
        let groups = countryGroups(categories + more, channels + [Channel(id: "10", name: "Kanal", categoryId: "x")])
        XCTAssertEqual(groups.map(\.code), ["NO", "SE", ""])
        XCTAssertEqual(groups[0].categories, 3)
        XCTAssertEqual(groups[0].channels, 7)
        XCTAssertEqual(groups[1].channels, 2)
        XCTAssertEqual(groups[0].example, "NO: [720p] AND [H265]")
        XCTAssertEqual(groups[0].title, "Norge (NO)")
        XCTAssertEqual(groups[2].title, "Uten land")
        XCTAssertEqual(groups[2].categories, 1)
        XCTAssertEqual(groups[2].example, "Sport")
        XCTAssertEqual(groups[0].detail, "3 kategorier · 7 kanaler")
        XCTAssertTrue(hasSeveralCountries(groups))
        XCTAssertFalse(hasSeveralCountries(Array(groups.suffix(2))))
        // en kode som ikke er et kjent land, kjennes igjen på en av kategoriene
        let unknown = CountryGroup(code: "AS", categories: 1, channels: 1, example: "AS: Diverse")
        XCTAssertEqual(unknown.title, "AS")
        XCTAssertEqual(unknown.detail, "1 kategori · 1 kanal · «AS: Diverse»")
    }

    func testCountriesSummary() {
        XCTAssertEqual(countriesSummary(nil), "Alle land")
        XCTAssertEqual(countriesSummary([]), "Alle land")
        XCTAssertEqual(countriesSummary(["NO"]), "Norge")
        XCTAssertEqual(countriesSummary(["SE", "NO"]), "Norge, Sverige")
        XCTAssertEqual(countriesSummary(["SE", "NO", "DK", "FI", "UK"]), "Danmark, Finland, Norge og 2 til")
    }

    func testIndexWithTidyNamesNRKMergedAndChosenCountries() {
        let lists = Lists(categories: categories, channels: channels)
        let nrk = Set(builtInStreams.map(\.key))
        let index = ChannelIndex(lists, merging: nrk, tidy: true)
        // to land: koden står foran kategoriene (unntatt der landet er navnet)
        XCTAssertEqual(index.categories.map(\.name),
                       ["Norge · 720p · H265", "Norge", "NO · VIAPLAY · PPV EVENTS · EXTRA", "SE · SPORT"])
        XCTAssertEqual(index.channels.filter { $0.name == "TV 2" }.map(\.quality), ["720p", "H265"])
        let names = index.channels.map(\.name)
        for name in ["AKVARIUM", "NRK1 ØSTLANDET", "TV 4", "SPORT ULTRA"] { XCTAssertTrue(names.contains(name), name) }
        // NRK1 er én kanal (med merket foran), og begge id-ene finner den
        XCTAssertEqual(index.channels.filter { channelKey($0.name) == "nrk1" }.count, 1)
        XCTAssertEqual(index.byId["1"]?.id, index.byId["5"]?.id)
        // lista som leverandøren sendte den
        XCTAssertTrue(index.lists.channels.map(\.name).contains("NOR: TV 2 [720p]"))
        // søket finner det ryddige navnet
        XCTAssertEqual(index.search("tv 2").count, 2)

        // bare Norge: Sverige er borte, og koden foran kategoriene trengs ikke
        let norway = ChannelIndex(lists, merging: nrk, countries: ["NO"], tidy: true)
        XCTAssertEqual(norway.categories.map(\.name), ["Norge · 720p · H265", "Norge", "VIAPLAY · PPV EVENTS · EXTRA"])
        XCTAssertFalse(norway.channels.map(\.name).contains("TV 4"))
        XCTAssertTrue(norway.channels(in: "se").isEmpty)
        XCTAssertTrue(norway.search("tv 4").isEmpty)
        XCTAssertFalse(norway.channels(favoring: []).contains { $0.id == "8" })
        // de skjulte finnes fortsatt (favorittene og «Sist sett»)
        XCTAssertEqual(norway.byId["8"]?.name, "TV 4")
        XCTAssertTrue(norway.hasSameOptions(merging: nrk, countries: ["NO"], tidy: true))
        XCTAssertFalse(norway.hasSameOptions(merging: nrk, countries: nil, tidy: true))

        // navnene som leverandøren skrev dem
        let raw = ChannelIndex(lists, merging: nrk, tidy: false)
        XCTAssertTrue(raw.channels.map(\.name).contains("NOR: TV 2 [720p]"))
        XCTAssertTrue(raw.categories.map(\.name).contains("NO:   [1080p]"))
        XCTAssertEqual(raw.channels.filter { channelKey($0.name) == "nrk1" }.count, 1)
        XCTAssertNil(raw.channels.first { $0.id == "2" }?.quality)
    }

    func testCountriesThatAreGoneShowEverything() {
        let lists = Lists(categories: categories, channels: channels)
        let index = ChannelIndex(lists, countries: ["FI"], tidy: true)
        XCTAssertEqual(index.channels.count, channels.count)
        XCTAssertEqual(index.categories.count, 4)
    }

    func testNRKWithTagInFront() {
        XCTAssertEqual(channelKey("VIP: NRK1 [1080p]"), "nrk1")
        XCTAssertEqual(channelKey("GOLD: NRK1 [1080p]"), "nrk1")
        XCTAssertEqual(channelKey("VIP: NRK1 ØSTLANDET [1080p]"), "nrk1østlandet")
        let keys = Set(builtInStreams.map(\.key))
        XCTAssertEqual(matchingStreamKeys("VIP: NRK3/SUPER [1080p]", in: keys).map(\.key), ["nrk3", "nrksuper"])
        XCTAssertEqual(matchingStreamKeys("VIP: NRK3/SUPER [1080p]", in: keys).map(\.name),
                       ["VIP: NRK3 [1080p]", "VIP: NRK Super [1080p]"])
        XCTAssertEqual(matchingStreamKeys("NRK 3/SUPER NO", in: keys).map(\.key), ["nrk3", "nrksuper"])
        XCTAssertEqual(matchingStreamKeys("GOLD: NRK1 [1080p]", in: keys).map(\.key), ["nrk1"])
        // delt i to, og ryddet
        let lists = Lists(categories: [ChannelCategory(id: "no", name: "NO: [1080p]")],
                          channels: [Channel(id: "7", name: "VIP: NRK3/SUPER [1080p]", categoryId: "no")])
        let index = ChannelIndex(lists, merging: keys, tidy: true)
        XCTAssertEqual(index.channels.map(\.name), ["NRK3", "NRK Super"])
        XCTAssertEqual(index.channels.map(\.id), ["7", "7~nrksuper"])
    }

    /// 25 000 kanaler med merker og kvalitet i navnene: ryddingen skal ikke gjøre oppstarten merkbart tregere.
    func testTidyingManyChannelsIsQuick() {
        var many: [Channel] = []
        for i in 0..<25_000 {
            let name = i % 2 == 0 ? "NOR: Kanal \(i) [720p]" : "Kanal \(i) HD NO"
            many.append(Channel(id: "\(i)", name: name, categoryId: "c\(i % 450)"))
        }
        let cats = (0..<450).map { ChannelCategory(id: "c\($0)", name: $0 % 2 == 0 ? "NO: Sport \($0)" : "SE: Film \($0)") }
        let start = Date()
        let index = ChannelIndex(Lists(categories: cats, channels: many), countries: ["NO"], tidy: true)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(index.categories.count, 225)
        XCTAssertEqual(index.channels.count, 12_500)
        XCTAssertLessThan(seconds, 3, "brukte \(seconds) s")
        print("Ryddet og filtrert 25 000 kanaler på \(String(format: "%.2f", seconds)) s")
    }
}
