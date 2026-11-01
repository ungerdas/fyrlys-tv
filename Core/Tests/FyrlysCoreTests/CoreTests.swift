import Foundation
import XCTest
@testable import FyrlysCore

final class XtreamTests: XCTestCase {
    let login = Login(server: "iptv.example:8080/", username: "kari", password: "hemmelig")

    func testLoginNormalizesServer() {
        XCTAssertEqual(login.server, "http://iptv.example:8080")
        XCTAssertEqual(Login.normalize("https://iptv.example/player_api.php"), "https://iptv.example")
        XCTAssertEqual(Login.normalize(" http://iptv.example:80/get.php "), "http://iptv.example:80")
        XCTAssertEqual(login.id, Login(server: "http://IPTV.example:8080", username: "kari", password: "annet").id)
        XCTAssertNotEqual(login.id, Login(server: "http://iptv.example:8080", username: "ola", password: "x").id)
        XCTAssertEqual(login.label, "kari på iptv.example")
    }

    func testURLs() {
        let client = XtreamClient(login: Login(server: "http://iptv.example", username: "kari nord", password: "p/a#ss"))
        let api = client.apiURL(action: "get_short_epg", ["stream_id": "101", "limit": "4"]).absoluteString
        XCTAssertTrue(api.hasPrefix("http://iptv.example/player_api.php?username=kari%20nord&password=p/a%23ss"))
        XCTAssertTrue(api.hasSuffix("&action=get_short_epg&limit=4&stream_id=101"))
        let channel = Channel(id: "101", name: "NRK 1", categoryId: "1")
        XCTAssertEqual(client.liveURL(channel).absoluteString, "http://iptv.example/live/kari%20nord/p%2Fa%23ss/101.m3u8")
        XCTAssertEqual(client.redact("Failed to open http://iptv.example/live/kari%20nord/p%2Fa%23ss/101.m3u8"),
                       "Failed to open http://iptv.example/live/kari%20nord/p%2Fa%23ss/101.m3u8"
                           .replacingOccurrences(of: "kari%20nord", with: "***"))
        XCTAssertEqual(XtreamClient(login: login).redact("kari og hemmelig"), "*** og ***")
    }

    func testParsesListsWithLooseTypes() throws {
        let cats = parseCategories(try json("""
            [{"category_id": "1", "category_name": "Norge"}, {"category_id": 2, "category_name": " Sport "},
             {"category_id": "1", "category_name": "Dobbel"}, {"category_id": "3", "category_name": ""}]
            """))
        XCTAssertEqual(cats, [ChannelCategory(id: "1", name: "Norge"), ChannelCategory(id: "2", name: "Sport")])

        let chans = parseChannels(try json("""
            [{"stream_id": 101, "name": "NRK 1 HD", "category_id": "1", "num": "1", "stream_icon": "http://logo/1.png",
              "tv_archive": 1, "tv_archive_duration": "7", "epg_channel_id": "nrk1.no"},
             {"stream_id": "102", "name": "TV 2", "category_id": 1, "num": 2, "stream_icon": "", "tv_archive": "0",
              "epg_channel_id": null},
             {"stream_id": "103", "name": "", "category_id": "1"}]
            """))
        XCTAssertEqual(chans.count, 2)
        XCTAssertEqual(chans[0], Channel(id: "101", name: "NRK 1 HD", categoryId: "1", number: 1,
                                         logo: "http://logo/1.png", archiveDays: 7))
        XCTAssertEqual(chans[1].logo, nil)
        XCTAssertEqual(chans[1].categoryId, "1")
        XCTAssertEqual(chans[1].archiveDays, 0)
        // uten epg_channel_id hentes ingen programinfo
        XCTAssertTrue(chans[0].hasEpg)
        XCTAssertFalse(chans[1].hasEpg)
        XCTAssertFalse(chans[1].wantsEpg)
    }

    func testEventChannelsWantNoEpg() {
        XCTAssertTrue(Channel(id: "1", name: "NRK 1 HD", categoryId: "1").wantsEpg)
        XCTAssertFalse(Channel(id: "2", name: "18:30 Bergby IL - Fjordheim FK | Eksempelligaen", categoryId: "1").wantsEpg)
    }

    /// Lister lagret av 0.1.1 (uten hasEpg) leses fortsatt.
    func testReadsChannelsSavedBeforeHasEpg() throws {
        let old = #"{"id": "101", "name": "NRK 1", "categoryId": "1", "number": 1, "archiveDays": 0}"#
        let channel = try JSONDecoder().decode(Channel.self, from: Data(old.utf8))
        XCTAssertEqual(channel, Channel(id: "101", name: "NRK 1", categoryId: "1", number: 1))
        let again = try JSONDecoder().decode(Channel.self, from: JSONEncoder().encode(
            Channel(id: "102", name: "TV 2", categoryId: "1", hasEpg: false)))
        XCTAssertFalse(again.hasEpg)
    }

    func testParsesShortEPG() throws {
        let b64 = { (s: String) in Data(s.utf8).base64EncodedString() }
        let programs = parseShortEPG(try json("""
            {"epg_listings": [
              {"title": "\(b64("Dagsrevyen"))", "description": "\(b64("Nyheter"))",
               "start_timestamp": "1793050000", "stop_timestamp": "1793051800"},
              {"title": "Ikke base64 ÆØÅ", "start_timestamp": 1793051800, "stop_timestamp": 1793053600},
              {"title": "\(b64("Feil"))", "start_timestamp": "10", "stop_timestamp": "5"}
            ]}
            """))
        XCTAssertEqual(programs.count, 2)
        XCTAssertEqual(programs[0].title, "Dagsrevyen")
        XCTAssertEqual(programs[0].description, "Nyheter")
        XCTAssertEqual(programs[1].title, "Ikke base64 ÆØÅ")
        XCTAssertEqual(programs[0].start, Date(timeIntervalSince1970: 1_793_050_000))
    }

    func testAccountAndErrors() async throws {
        let ok = XtreamClient(login: login) { url in
            XCTAssertTrue(url.absoluteString.contains("player_api.php"))
            return (Data(#"{"user_info": {"auth": 1, "status": "Active", "exp_date": "1800000000", "max_connections": "1", "active_cons": 0}}"#.utf8), 200)
        }
        let account = try await ok.account()
        XCTAssertEqual(account.status, "Active")
        XCTAssertEqual(account.maxConnections, 1)
        XCTAssertEqual(account.expires, Date(timeIntervalSince1970: 1_800_000_000))

        let denied = XtreamClient(login: login) { _ in (Data(#"{"user_info": {"auth": 0}}"#.utf8), 200) }
        await assertThrows(L("Serveren avviste innloggingen")) { _ = try await denied.account() }
        let forbidden = XtreamClient(login: login) { _ in (Data(), 403) }
        await assertThrows(L("Serveren avviste innloggingen")) { _ = try await forbidden.categories() }
        let html = XtreamClient(login: login) { _ in (Data("<html>".utf8), 200) }
        await assertThrows(L("Serveren svarte ikke som en Xtream-server")) { _ = try await html.channels() }
        let down = XtreamClient(login: login) { _ in throw URLError(.cannotConnectToHost) }
        await assertThrows(L("Får ikke kontakt med IPTV-serveren")) { _ = try await down.channels() }
    }

    func json(_ s: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(s.utf8))
    }

    func assertThrows(_ message: String, _ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("ingen feil", line: line)
        } catch let e as SourceError {
            XCTAssertEqual(e.message, message, line: line)
        } catch {
            XCTFail("feil av feil slag: \(error)", line: line)
        }
    }
}

final class ProgramTests: XCTestCase {
    func at(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_793_050_000 + minutes * 60) }

    func testNowAndNext() {
        let a = Program(title: "A", start: at(0), stop: at(30))
        let b = Program(title: "B", start: at(30), stop: at(60))
        XCTAssertEqual(nowAndNext([a, b], at: at(10)).now, a)
        XCTAssertEqual(nowAndNext([a, b], at: at(10)).next, b)
        XCTAssertEqual(nowAndNext([a, b], at: at(45)).now, b)
        XCTAssertNil(nowAndNext([a, b], at: at(45)).next)
        XCTAssertNil(nowAndNext([a, b], at: at(-5)).now)
        XCTAssertEqual(nowAndNext([a, b], at: at(-5)).next, a)
        XCTAssertEqual(a.progress(at: at(15)), 0.5, accuracy: 0.001)
    }

    func testCleanProgramsSortsMergesAndCutsOverlap() {
        let a = Program(title: "A", start: at(0), stop: at(40))
        let a2 = Program(title: "A", start: at(0), stop: at(30))
        let b = Program(title: "B", start: at(30), stop: at(60))
        let broken = Program(title: "X", start: at(70), stop: at(70))
        let out = cleanPrograms([b, a2, a, broken])
        XCTAssertEqual(out.map(\.title), ["A", "B"])
        XCTAssertEqual(out[0].stop, at(30))
        XCTAssertEqual(out[1].start, at(30))
    }

    func testGuideTime() {
        // 1_793_050_200 er et helt halvtimesmerke (delelig med 1800)
        let mark = Date(timeIntervalSince1970: 1_793_050_200)
        XCTAssertEqual(GuideTime.start(mark.addingTimeInterval(17 * 60)), mark.addingTimeInterval(-1800))
        XCTAssertEqual(GuideTime.start(mark), mark.addingTimeInterval(-1800))
        let start = GuideTime.start(mark.addingTimeInterval(60))
        XCTAssertEqual(GuideTime.marks(start).count, 12)
        // begynte før guiden: kuttes ved starten
        let early = Program(title: "A", start: start.addingTimeInterval(-600), stop: start.addingTimeInterval(1200))
        XCTAssertEqual(GuideTime.span(of: early, start: start)?.from, 0)
        XCTAssertEqual(GuideTime.span(of: early, start: start)?.length, 20)
        // slutter etter guiden: kuttes ved slutten
        let late = Program(title: "B", start: start.addingTimeInterval(350 * 60), stop: start.addingTimeInterval(400 * 60))
        XCTAssertEqual(GuideTime.span(of: late, start: start)?.length, 10)
        // helt utenfor
        let gone = Program(title: "C", start: start.addingTimeInterval(-3600), stop: start)
        XCTAssertNil(GuideTime.span(of: gone, start: start))
    }
}

final class NameTests: XCTestCase {
    func testNameParts() {
        XCTAssertEqual(nameParts("12:45 Aston Villa - Man City | Premier League"),
                       NameParts(time: "12:45", main: "Aston Villa - Man City", sub: "Premier League"))
        XCTAssertEqual(nameParts("9.30 - Kamp"), NameParts(time: "9:30", main: "Kamp", sub: ""))
        XCTAssertEqual(nameParts("NRK 1 HD"), NameParts(time: "", main: "NRK 1 HD", sub: ""))
        XCTAssertEqual(initials("NRK 1 HD"), "N1")
        XCTAssertEqual(initials("TV 2 Sport"), "T2")
        // navn som begynner med et siffer, men ikke et klokkeslett
        XCTAssertEqual(nameParts("24 Nyheter"), NameParts(time: "", main: "24 Nyheter", sub: ""))
        XCTAssertEqual(nameParts("4K | Kinokanalen"), NameParts(time: "", main: "4K", sub: "Kinokanalen"))
        XCTAssertEqual(nameParts("  20:00 Nordvik - Sørhavn | Cupen "),
                       NameParts(time: "20:00", main: "Nordvik - Sørhavn", sub: "Cupen"))
        XCTAssertEqual(logoText("Viaplay Sport"), "Via")
        XCTAssertEqual(logoText("18:30 Bergby IL - Fjordheim FK | Liga"), "Ber")
        XCTAssertEqual(logoText("TV"), "TV")
        XCTAssertEqual(logoText(" "), "?")
        XCTAssertEqual(hhmm(Date(timeIntervalSince1970: 3600 * 5 + 60 * 7), timeZone: TimeZone(identifier: "UTC")!), "05:07")
    }
}

final class LibraryTests: XCTestCase {
    func testMergeIdsKeepsBothDevicesFavorites() {
        XCTAssertEqual(mergeIds(["1", "2"], ["3", "1", "4"]), ["1", "2", "3", "4"])
        XCTAssertEqual(mergeIds([], ["5"]), ["5"])
        XCTAssertEqual(mergeIds(["5"], []), ["5"])
    }

    func testReloadReadsWhatAnotherDeviceWrote() {
        let store = MemoryStore()
        let library = Library(store: store, loginId: "a")
        _ = library.toggleFavorite("1")
        store.set(["1", "9"], for: "favorites@a")
        store.set(["k2"], for: "favoriteCategories@a")
        library.reload()
        XCTAssertEqual(library.favorites, ["1", "9"])
        XCTAssertTrue(library.isFavorite("9"))
        XCTAssertEqual(library.favoriteCategories, ["k2"])
    }

    func testFavoritesAndRecentPerLogin() {
        let store = MemoryStore()
        let home = Library(store: store, loginId: "a")
        let other = Library(store: store, loginId: "b")
        XCTAssertTrue(home.toggleFavorite("101"))
        XCTAssertTrue(home.toggleFavorite("102"))
        XCTAssertEqual(home.favorites, ["101", "102"])
        XCTAssertFalse(home.toggleFavorite("101"))
        XCTAssertEqual(home.favorites, ["102"])
        XCTAssertTrue(other.favorites.isEmpty)

        for i in 0..<25 { home.addRecent(String(i)) }
        home.addRecent("3")
        XCTAssertEqual(home.recent.count, Library.recentMax)
        XCTAssertEqual(home.recent.first, "3")
        XCTAssertEqual(home.recent.filter { $0 == "3" }.count, 1)

        // holdes i minnet, men er lagret: en ny Library for samme innlogging ser det samme
        let again = Library(store: store, loginId: "a")
        XCTAssertEqual(again.favorites, ["102"])
        XCTAssertTrue(again.isFavorite("102"))
        XCTAssertFalse(again.isFavorite("101"))
        XCTAssertEqual(again.recent.first, "3")
    }

    func testFavoriteCategoriesAreOrdered() {
        let store = MemoryStore()
        let lib = Library(store: store, loginId: "a")
        XCTAssertTrue(lib.toggleFavoriteCategory("no"))
        XCTAssertTrue(lib.toggleFavoriteCategory("se"))
        XCTAssertTrue(lib.toggleFavoriteCategory("dk"))
        XCTAssertEqual(lib.favoriteCategories, ["no", "se", "dk"])
        lib.moveFavoriteCategory("dk", by: -1)
        XCTAssertEqual(lib.favoriteCategories, ["no", "dk", "se"])
        lib.moveFavoriteCategory("no", by: -1) // øverst alt
        lib.moveFavoriteCategory("se", by: 1) // nederst alt
        XCTAssertEqual(lib.favoriteCategories, ["no", "dk", "se"])
        XCTAssertFalse(lib.toggleFavoriteCategory("dk"))
        XCTAssertFalse(lib.isFavoriteCategory("dk"))
        XCTAssertEqual(Library(store: store, loginId: "a").favoriteCategories, ["no", "se"])
        XCTAssertTrue(Library(store: store, loginId: "b").favoriteCategories.isEmpty)

        // en kategori som er borte hos leverandøren, hoppes over når det flyttes
        lib.toggleFavoriteCategory("borte")
        lib.toggleFavoriteCategory("fi")
        XCTAssertEqual(lib.favoriteCategories, ["no", "se", "borte", "fi"])
        lib.moveFavoriteCategory("fi", by: -1, shown: ["no", "se", "fi"])
        XCTAssertEqual(lib.favoriteCategories, ["no", "fi", "borte", "se"])

        // dra og slipp: de som vises i ny rekkefølge, de som ikke vises bakerst, ingen nye
        lib.setFavoriteCategoryOrder(["se", "no", "fi", "ukjent", "se"])
        XCTAssertEqual(lib.favoriteCategories, ["se", "no", "fi", "borte"])
        XCTAssertEqual(Library(store: store, loginId: "a").favoriteCategories, ["se", "no", "fi", "borte"])
    }

    func testSearch() {
        let list = [Channel(id: "1", name: "NRK 1 HD", categoryId: "1"),
                    Channel(id: "2", name: "TV 2 Sport", categoryId: "1"),
                    Channel(id: "3", name: "NRK Super", categoryId: "1")]
        XCTAssertEqual(search("nrk", in: list).map(\.id), ["1", "3"])
        XCTAssertEqual(search("sport tv", in: list).map(\.id), ["2"])
        XCTAssertTrue(search("  ", in: list).isEmpty)
    }

    func testListCacheRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fyrlys-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ListCache(dir: dir)
        XCTAssertNil(cache.read("a"))
        let lists = Lists(categories: [ChannelCategory(id: "1", name: "Norge")],
                          channels: [Channel(id: "101", name: "NRK 1", categoryId: "1", number: 1)])
        cache.write(lists, for: "a")
        XCTAssertEqual(cache.read("a")?.channels, lists.channels)
        cache.remove("a")
        XCTAssertNil(cache.read("a"))
    }
}

final class ChannelIndexTests: XCTestCase {
    let lists = Lists(
        categories: [ChannelCategory(id: "se", name: "Sverige"), ChannelCategory(id: "no", name: "Norge"),
                     ChannelCategory(id: "tom", name: "Tom"), ChannelCategory(id: "dk", name: "Danmark")],
        channels: [Channel(id: "1", name: "SVT 1", categoryId: "se"),
                   Channel(id: "2", name: "NRK 1 HD", categoryId: "no"),
                   Channel(id: "3", name: "SVT Sport", categoryId: "se"),
                   Channel(id: "4", name: "TV 2 Sport", categoryId: "no"),
                   Channel(id: "5", name: "DR 1", categoryId: "dk"),
                   Channel(id: "6", name: "Uten kategori", categoryId: "x")])

    func testLookups() {
        let index = ChannelIndex(lists)
        XCTAssertEqual(index.channels.map(\.id), ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(index.byId["4"]?.name, "TV 2 Sport")
        XCTAssertEqual(index.channels(in: "no").map(\.id), ["2", "4"])
        XCTAssertTrue(index.channels(in: "tom").isEmpty)
        // bare kategorier med kanaler, i leverandørens rekkefølge
        XCTAssertEqual(index.categories.map(\.id), ["se", "no", "dk"])
        XCTAssertEqual(index.category("no")?.name, "Norge")
        XCTAssertNil(index.category("tom"))
        XCTAssertTrue(ChannelIndex.empty.channels.isEmpty)
    }

    func testFavoriteCategoriesFirst() {
        let index = ChannelIndex(lists)
        XCTAssertEqual(index.channels(favoring: []).map(\.id), ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(index.channels(favoring: ["no"]).map(\.id), ["2", "4", "1", "3", "5", "6"])
        // ukjente og doble hoppes over
        XCTAssertEqual(index.channels(favoring: ["dk", "borte", "no", "dk"]).map(\.id), ["5", "2", "4", "1", "3", "6"])
    }

    func testSearch() {
        let index = ChannelIndex(lists)
        XCTAssertEqual(index.search("sport").map(\.id), ["3", "4"])
        XCTAssertEqual(index.search("sport", favoring: ["no"]).map(\.id), ["4", "3"])
        XCTAssertEqual(index.search("SPORT tv").map(\.id), ["4"])
        XCTAssertEqual(index.search("1", favoring: ["no"], limit: 2).map(\.id), ["2", "1"])
        XCTAssertTrue(index.search("   ").isEmpty)
        // det samme som det gamle søket
        XCTAssertEqual(index.search("nrk").map(\.id), search("nrk", in: lists.channels).map(\.id))
    }

    func testSameLists() {
        let index = ChannelIndex(lists)
        let later = Lists(categories: lists.categories, channels: lists.channels, saved: Date().addingTimeInterval(60))
        XCTAssertTrue(index.hasSameLists(as: later))
        let changed = Lists(categories: lists.categories, channels: Array(lists.channels.dropLast()))
        XCTAssertFalse(index.hasSameLists(as: changed))
    }

    /// En stor leverandør (25 000 kanaler): lages og søkes i på kort tid.
    func testLargeList() {
        var cats: [ChannelCategory] = []
        var chans: [Channel] = []
        for c in 0..<450 { cats.append(ChannelCategory(id: "\(c)", name: "Kategori \(c)")) }
        for i in 0..<25_000 {
            let name = i % 7 == 0 ? "18:30 Lag \(i) - Lag \(i + 1) | Liga \(i % 40)" : "Kanal \(i) HD"
            chans.append(Channel(id: "\(i)", name: name, categoryId: "\(i % 450)", number: i + 1,
                                 logo: "http://iptv.example.com/logo/\(i).png"))
        }
        let big = Lists(categories: cats, channels: chans)
        var start = Date()
        let index = ChannelIndex(big)
        let built = Date().timeIntervalSince(start)
        start = Date()
        let hits = index.search("kanal 12", favoring: ["3", "7"], limit: 120)
        let searched = Date().timeIntervalSince(start)
        start = Date()
        let ordered = index.channels(favoring: ["3", "7"])
        let reordered = Date().timeIntervalSince(start)
        start = Date()
        _ = index.hasSameLists(as: big)
        let compared = Date().timeIntervalSince(start)
        print(String(format: "25 000 kanaler: indeks %.0f ms, søk %.0f ms, rekkefølge %.0f ms, sammenligning %.0f ms",
                     built * 1000, searched * 1000, reordered * 1000, compared * 1000))
        XCTAssertEqual(index.channels.count, 25_000)
        XCTAssertEqual(ordered.count, 25_000)
        XCTAssertEqual(ordered.first?.categoryId, "3")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.categoryId, "3")
        XCTAssertLessThan(built, 5)
        XCTAssertLessThan(searched, 2)
    }
}

final class VODTests: XCTestCase {
    func testItemsWithLooseTypes() {
        let json: Any = [
            ["stream_id": 501, "name": "Fjorden (2021)", "stream_icon": "http://x/p.jpg", "category_id": "7",
             "rating": "7,5", "container_extension": "mkv"],
            ["stream_id": "502", "name": "Uten bilde", "rating_5based": 4, "added": "1700000000"],
            ["stream_id": "501", "name": "dobbel"],
            ["name": "uten id"],
        ]
        let items = parseVODItems(json, kind: .movies)
        XCTAssertEqual(items.map(\.id), ["501", "502"])
        XCTAssertEqual(items[0].year, "2021")
        XCTAssertEqual(items[0].rating, 7.5)
        XCTAssertEqual(items[0].ext, "mkv")
        XCTAssertEqual(items[1].rating, 8)
        XCTAssertNil(items[1].poster)
        let series = parseVODItems([["series_id": 9, "name": "Kysten", "cover": "c.jpg", "releaseDate": "2019-03-01"]],
                                   kind: .series)
        XCTAssertEqual(series.first?.year, "2019")
        XCTAssertEqual(series.first?.poster, "c.jpg")
    }

    func testMovieInfo() {
        let d = parseMovieInfo(["info": ["plot": "Om fjorden.", "genre": "Drama", "duration": "01:45:00",
                                         "releasedate": "2021-04-01", "backdrop_path": ["", "http://x/b.jpg"]],
                                "movie_data": ["stream_id": 501, "container_extension": "mp4"]])
        XCTAssertEqual(d.plot, "Om fjorden.")
        XCTAssertEqual(d.year, "2021")
        XCTAssertEqual(d.backdrop, "http://x/b.jpg")
        XCTAssertEqual(d.ext, "mp4")
        // info som tom liste
        XCTAssertEqual(parseMovieInfo(["info": [], "movie_data": ["container_extension": "mkv"]]).ext, "mkv")
    }

    func testSeriesInfoAsMapAndAsList() {
        let episodes: [[String: Any]] = [
            ["id": "1002", "episode_num": 2, "title": "To", "container_extension": "mp4", "season": 1],
            ["id": "1001", "episode_num": "1", "title": "", "info": ["plot": "Først", "duration": "45 min"]],
        ]
        let d = parseSeriesInfo(["info": ["name": "Kysten (2019)"], "episodes": ["1": episodes, "2": [["id": "2001"]]]])
        XCTAssertEqual(d.seasons.map(\.number), [1, 2])
        XCTAssertEqual(d.seasons[0].episodes.map(\.id), ["1001", "1002"])
        XCTAssertEqual(d.seasons[0].episodes[0].plot, "Først")
        XCTAssertEqual(d.year, "2019")
        let list = parseSeriesInfo(["episodes": [episodes]])
        XCTAssertEqual(list.seasons.first?.episodes.count, 2)
    }

    func testAddressesAndPlayableExtensions() {
        let client = XtreamClient(login: Login(server: "http://iptv.example.com", username: "u", password: "p"))
        XCTAssertEqual(client.movieURL("501", ext: "mp4").absoluteString, "http://iptv.example.com/movie/u/p/501.mp4")
        XCTAssertEqual(client.episodeURL(Episode(id: "7", season: 1, number: 1, title: "", ext: "mkv")).absoluteString,
                       "http://iptv.example.com/series/u/p/7.mkv")
        XCTAssertEqual(playableExtensions("MP4"), ["mp4"])
        XCTAssertEqual(playableExtensions(".mkv"), ["mkv"])
        XCTAssertEqual(playableExtensions(nil), ["mp4", "m3u8"])
    }

    /// Apples avspiller for det den kan, VLC for resten, og VLC til slutt når Apples avspiller ikke fikk det til.
    func testPlayAttempts() {
        let base = "http://iptv.example.com/movie/u/p/501"
        let mp4 = URL(string: "\(base).mp4")!, m3u8 = URL(string: "\(base).m3u8")!
        let mkv = URL(string: "\(base).MKV")!, ts = URL(string: "\(base).ts")!
        XCTAssertEqual(playAttempts([mkv]), [PlayAttempt(mkv, .vlc)])
        XCTAssertEqual(playAttempts([mp4]), [PlayAttempt(mp4, .native), PlayAttempt(mp4, .vlc)])
        XCTAssertEqual(playAttempts([mp4, m3u8]),
                       [PlayAttempt(mp4, .native), PlayAttempt(m3u8, .native), PlayAttempt(mp4, .vlc)])
        // TV-arkivet: HLS med Apples avspiller, MPEG-TS med VLC
        XCTAssertEqual(playAttempts([m3u8, ts]), [PlayAttempt(m3u8, .native), PlayAttempt(ts, .vlc)])
        XCTAssertEqual(playAttempts([]), [])
    }
}

final class ArchiveTests: XCTestCase {
    func testServerClockAndTimeFormat() {
        // serveren går 1 time foran UTC (vintertid i Norge)
        let offset = serverClockOffset(["timestamp_now": 1_793_500_000, "time_now": "2026-11-01 03:26:40"])
        XCTAssertEqual(offset, 3600)
        XCTAssertNil(serverClockOffset(["timestamp_now": 1_793_500_000]))
        let t = Date(timeIntervalSince1970: 1_793_500_000)  // 2026-11-01 02:26:40 UTC
        XCTAssertEqual(xtreamTime(t, offset: 3600), "2026-11-01:03-26")
        // serveren går likt med enheten: enhetens sone med sommertid for et tidspunkt i juli
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let july = Date(timeIntervalSince1970: 1_783_000_000)
        XCTAssertEqual(archiveOffset(july, server: 3600, zone: oslo, now: t), 7200)
        // ellers serverens forskjell
        XCTAssertEqual(archiveOffset(july, server: 0, zone: oslo, now: t), 0)
    }

    func testArchiveListAndURLs() {
        let now = Date(timeIntervalSince1970: 1_793_500_000)
        let json: [String: Any] = ["epg_listings": [
            ["title": "RGFnc3JldnllbiBpIGRhZw==", "start_timestamp": "1793492800", "stop_timestamp": "1793496400",
             "has_archive": 1],
            ["title": "R2FtbWVs", "start_timestamp": "1793300000", "stop_timestamp": "1793303600", "has_archive": 0],
            ["title": "TsOl", "start_timestamp": "1793499000", "stop_timestamp": "1793502600", "has_archive": 0],
            ["title": "U2VuZXJl", "start_timestamp": "1793510000", "stop_timestamp": "1793513600"],
            ["title": "Rm9yIGdhbW1lbA==", "start_timestamp": "1792000000", "stop_timestamp": "1792003600"],
        ]]
        let items = parseArchive(json, now: now, days: 7)
        XCTAssertEqual(items.map(\.program.title), ["Gammel", "Dagsrevyen i dag", "Nå"])
        XCTAssertEqual(items.map(\.available), [false, true, true])
        let client = XtreamClient(login: Login(server: "http://iptv.example.com", username: "u", password: "p"))
        let channel = Channel(id: "11", name: "Kanal", categoryId: "1", archiveDays: 7)
        let urls = client.archiveURLs(channel, items[1].program, from: 90, serverClock: 3600,
                                      zone: TimeZone(identifier: "UTC")!, now: now)
        // fra 90 s inn, rundet ned til minuttet: 59 minutter igjen
        XCTAssertEqual(urls.first?.absoluteString,
                       "http://iptv.example.com/timeshift/u/p/59/2026-11-01:01-28/11.m3u8")
        XCTAssertEqual(urls.last?.pathExtension, "ts")
    }
}

final class L10nTests: XCTestCase {
    override func tearDown() { appLanguage = "no" }

    func testLanguageAndPlaceholders() {
        XCTAssertEqual(language(ofPreferred: ["nb-NO"]), "no")
        XCTAssertEqual(language(ofPreferred: ["nn"]), "no")
        XCTAssertEqual(language(ofPreferred: ["en-US", "nb"]), "en")
        XCTAssertEqual(language(ofPreferred: []), "en")
        XCTAssertEqual(L("Nå: {title}", ["title": "Dagsrevyen"]), "Nå: Dagsrevyen")
        appLanguage = "en"
        XCTAssertEqual(L("Logg ut"), "Sign out")
        XCTAssertEqual(L("finnes ikke"), "finnes ikke")
    }

    /// Alle L("…") i kildene har engelsk, med de samme {navnene}.
    func testEverythingIsTranslated() throws {
        // Core/Tests/FyrlysCoreTests/ → repoet
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var keys: [String: String] = [:]
        for folder in ["Core/Sources", "App"] {
            let dir = root.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                // uten kommentarlinjene (eksemplene der er ikke tekster i appen)
                let src = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
                for key in lKeys(in: src) { keys[key] = file.lastPathComponent }
            }
        }
        XCTAssertGreaterThan(keys.count, 20)
        let placeholders = { (s: String) -> Set<String> in
            Set(s.matches(#"\{(\w+)\}"#))
        }
        for (key, file) in keys.sorted(by: { $0.key < $1.key }) {
            guard let en = english[key] else {
                XCTFail("mangler engelsk (\(file)): \(key)")
                continue
            }
            XCTAssertEqual(placeholders(key), placeholders(en), "ulike {} i \(key)")
        }
    }

    /// Strengene i L("…") (også flere etter hverandre på hver sin linje), ikke de med \( ).
    func lKeys(in src: String) -> [String] {
        var out: [String] = []
        let pattern = #"(?<![\w.])L\(\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = src as NSString
        for m in re.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: m.range(at: 1))
            let parts = body.matches(#""((?:[^"\\]|\\.)*)""#)
            let key = parts.joined().replacingOccurrences(of: #"\""#, with: "\"")
            if !key.contains(#"\("#) { out.append(key) }
        }
        return out
    }
}

extension String {
    /// første gruppe i hvert treff
    func matches(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }
}
