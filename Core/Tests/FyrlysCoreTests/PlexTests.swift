@testable import FyrlysCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// Plex med oppdiktede svar (som fra plex.tv og en Plex-server).
final class PlexTests: XCTestCase {
    let device = PlexDevice(clientId: "fyrlys-test", platform: "tvOS", deviceName: "Stua", version: "0.1.16")

    func json(_ text: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    func container(_ text: String) -> [String: Any] {
        (json(text) as! [String: Any])["MediaContainer"] as! [String: Any]
    }

    var client: PlexClient { PlexClient(base: "http://192.168.1.10:32400/", token: "hemmelig", device: device) }

    /// Plex Home: brukerne med eieren først, PIN-beskyttelse og bildet.
    func testHomeUsers() {
        let users = parseHomeUsers(json("""
        {"users": [
          {"id": 2, "title": "Barna", "friendlyName": "Barna", "admin": false, "protected": false, "restricted": true},
          {"id": 1, "uuid": "abc", "title": "paal", "friendlyName": "Pål", "admin": true, "protected": true, "thumb": "https://plex.tv/u/1"},
          {"title": "Uten id"}]}
        """))
        XCTAssertEqual(users.map(\.id), [1, 2])
        XCTAssertEqual(users[0].name, "Pål")
        XCTAssertEqual(users[0].uuid, "abc")
        XCTAssertNil(users[1].uuid)
        XCTAssertTrue(users[0].protected)
        XCTAssertEqual(users[0].thumb, "https://plex.tv/u/1")
        XCTAssertTrue(users[1].restricted)
        XCTAssertFalse(users[1].protected)
    }

    func testPinAndServers() {
        XCTAssertEqual(parsePin(json(#"{"id": 4242, "code": "FYRL", "authToken": null}"#)),
                       PlexPin(id: 4242, code: "FYRL"))
        XCTAssertNil(parsePin(json(#"{"id": 1}"#)))
        let servers = parseServers(json("""
        [{"name": "Spiller", "provides": "player", "clientIdentifier": "p1", "accessToken": "x", "connections": []},
         {"name": "Hos naboen", "provides": "server", "clientIdentifier": "s2", "accessToken": "t2", "owned": false,
          "connections": [{"uri": "https://b.plex.direct:32400", "local": false, "relay": false}]},
         {"name": "Hjemme", "provides": "server,player", "clientIdentifier": "s1", "accessToken": "t1", "owned": true,
          "connections": [{"uri": "https://relay.plex.direct:8443", "local": false, "relay": true},
                          {"uri": "https://ute.plex.direct:32400", "local": false, "relay": false},
                          {"uri": "http://192.168.1.10:32400", "local": true, "relay": false}]}]
        """))
        XCTAssertEqual(servers.map(\.name), ["Hjemme", "Hos naboen"])
        XCTAssertEqual(servers[0].ordered.map(\.uri), ["http://192.168.1.10:32400", "https://ute.plex.direct:32400",
                                                       "https://relay.plex.direct:8443"])
    }

    func testLibrariesAndItems() {
        let sections = container("""
        {"MediaContainer": {"Directory": [{"key": "1", "type": "movie", "title": "Filmer"},
                                          {"key": "2", "type": "show", "title": "Serier"},
                                          {"key": "3", "type": "artist", "title": "Musikk"}]}}
        """)
        XCTAssertEqual(parseLibraries(sections, kind: .movies), [ChannelCategory(id: "1", name: "Filmer")])
        XCTAssertEqual(parseLibraries(sections, kind: .series), [ChannelCategory(id: "2", name: "Serier")])

        let movies = parseItems(container("""
        {"MediaContainer": {"Metadata": [
          {"ratingKey": "101", "type": "movie", "title": "Fyret", "year": 2021, "thumb": "/library/metadata/101/thumb/1",
           "audienceRating": 7.8, "viewCount": 1,
           "Media": [{"container": "mkv", "Part": [{"key": "/library/parts/9/1/file.mkv", "container": "mkv"}]}]},
          {"ratingKey": "102", "type": "movie", "title": "Uten bilde", "rating": "6,5"},
          {"ratingKey": "103", "type": "collection", "title": "Samling"}]}}
        """), kind: .movies, client: client, library: "1")
        XCTAssertEqual(movies.map(\.id), ["101", "102"])
        XCTAssertEqual(movies[0].ext, "mkv")
        XCTAssertEqual(movies[0].year, "2021")
        XCTAssertEqual(movies[0].rating, 7.8)
        XCTAssertEqual(movies[0].watched, true)
        XCTAssertEqual(movies[0].progressKey, "plex:101")
        XCTAssertTrue(movies[0].isPlex)
        XCTAssertEqual(movies[1].rating, 6.5)
        XCTAssertNil(movies[1].poster)
        let poster = URLComponents(string: movies[0].poster ?? "")!
        XCTAssertEqual(poster.path, "/photo/:/transcode")
        XCTAssertEqual(poster.queryItems?.first { $0.name == "url" }?.value, "/library/metadata/101/thumb/1")
        XCTAssertEqual(poster.queryItems?.first { $0.name == "X-Plex-Token" }?.value, "hemmelig")

        let shows = parseItems(container("""
        {"MediaContainer": {"Metadata": [{"ratingKey": "201", "type": "show", "title": "Losene", "leafCount": 5,
                                          "viewedLeafCount": 2}]}}
        """), kind: .series, client: client, library: "2")
        XCTAssertEqual(shows.map(\.name), ["Losene"])
        XCTAssertEqual(shows[0].watched, false)
    }

    func testDetailsEpisodesAndContinue() {
        let details = parseDetails((container("""
        {"MediaContainer": {"Metadata": [{"ratingKey": "101", "type": "movie", "title": "Fyret", "summary": "Om et fyr.",
          "duration": 6720000, "viewOffset": 754000, "year": 2021, "Genre": [{"tag": "Drama"}, {"tag": "Krim"}],
          "Role": [{"tag": "A", "role": "Vokteren", "thumb": "/library/metadata/101/role/1"}, {"tag": "B"}, {"tag": "A"}],
          "Director": [{"tag": "C"}], "tagline": "Lyset.", "studio": "Fyrlys Film",
          "Image": [{"type": "coverPoster", "url": "/library/metadata/101/thumb/1"},
                    {"type": "clearLogo", "url": "/library/metadata/101/clearLogo/1"}],
          "Media": [{"container": "mp4", "Part": [{"key": "/library/parts/9/1/file.mp4"}]}]}]}}
        """)["Metadata"] as! [[String: Any]])[0], client: client)
        XCTAssertEqual(details.plot, "Om et fyr.")
        XCTAssertEqual(details.genre, "Drama, Krim")
        XCTAssertEqual(details.cast, "A, B, A")
        XCTAssertEqual(details.people.map(\.name), ["A", "B"])
        XCTAssertEqual(details.people[0].role, "Vokteren")
        XCTAssertTrue(details.people[0].image?.contains("role/1") ?? false, details.people[0].image ?? "nil")
        XCTAssertNil(details.people[1].image)
        XCTAssertEqual(details.tagline, "Lyset.")
        XCTAssertEqual(details.studio, "Fyrlys Film")
        XCTAssertTrue(details.logo?.contains("clearLogo/1") ?? false, details.logo ?? "nil")
        XCTAssertTrue(details.logo?.contains("width=1600&height=800&minSize=0&upscale=0") ?? false, details.logo ?? "nil")
        XCTAssertEqual(peopleFromNames("Kari Fyr, Ola Strand,, kari fyr; Siri").map(\.name),
                       ["Kari Fyr", "Ola Strand", "Siri"])
        XCTAssertEqual(details.duration, "1 t 52 min")
        XCTAssertEqual(details.resume, 754)
        XCTAssertEqual(details.ext, "mp4")
        XCTAssertEqual(details.fileKey, "/library/parts/9/1/file.mp4")
        XCTAssertEqual(client.fileURL("/library/parts/9/1/file.mp4")?.absoluteString,
                       "http://192.168.1.10:32400/library/parts/9/1/file.mp4?X-Plex-Token=hemmelig")
        XCTAssertEqual(client.fileURL("/library/parts/9/1/file.mkv")?.pathExtension, "mkv")

        let seasons = parseEpisodes(container("""
        {"MediaContainer": {"Metadata": [
          {"ratingKey": "302", "type": "episode", "title": "Tåka", "parentIndex": 1, "index": 2, "viewCount": 1},
          {"ratingKey": "301", "type": "episode", "title": "Utløpet", "parentIndex": 1, "index": 1,
           "viewOffset": 60000, "Media": [{"Part": [{"key": "/library/parts/31/1/file.mkv", "container": "mkv"}]}]},
          {"ratingKey": "311", "type": "episode", "parentIndex": 2, "index": 1}]}}
        """), client: client)
        XCTAssertEqual(seasons.map(\.number), [1, 2])
        XCTAssertEqual(seasons[0].episodes.map(\.id), ["301", "302"])
        XCTAssertEqual(seasons[0].episodes[0].resume, 60)
        XCTAssertEqual(seasons[0].episodes[0].fileKey, "/library/parts/31/1/file.mkv")
        XCTAssertEqual(seasons[0].episodes[0].progressKey, "plex:301")
        XCTAssertTrue(seasons[0].episodes[1].watched)
        XCTAssertEqual(seasons[1].episodes[0].title, "Episode 1")

        let deck = container("""
        {"MediaContainer": {"Metadata": [
          {"ratingKey": "301", "type": "episode", "title": "Utløpet", "grandparentRatingKey": "201",
           "grandparentTitle": "Losene", "grandparentThumb": "/library/metadata/201/thumb/1",
           "grandparentArt": "/library/metadata/201/art/1", "parentIndex": 1, "index": 3,
           "viewOffset": 600000, "duration": 2400000},
          {"ratingKey": "305", "type": "episode", "title": "Hjem", "grandparentRatingKey": "201",
           "grandparentTitle": "Losene"},
          {"ratingKey": "101", "type": "movie", "title": "Fyret", "thumb": "/library/metadata/101/thumb/1"}]}}
        """)
        let series = parseContinue(deck, kind: .series, client: client)
        XCTAssertEqual(series.map(\.id), ["201"])
        XCTAssertEqual(series[0].item.name, "Losene")
        XCTAssertEqual(series[0].episode?.id, "301")
        XCTAssertEqual(series[0].episode?.season, 1)
        XCTAssertEqual(series[0].episode?.number, 3)
        XCTAssertEqual(series[0].progress, 0.25, accuracy: 0.001)
        // bakgrunnen til serien i bredformat
        XCTAssertTrue(series[0].image?.contains("art") == true, series[0].image ?? "")
        XCTAssertTrue(series[0].image?.contains("width=1280") == true, series[0].image ?? "")
        let movies = parseContinue(deck, kind: .movies, client: client)
        XCTAssertEqual(movies.map(\.item.name), ["Fyret"])
        XCTAssertNil(movies[0].episode)
        XCTAssertEqual(movies[0].progress, 0)
        XCTAssertTrue(movies[0].image?.contains("thumb") == true, "uten bakgrunn: plakaten")
        // Plex-fanen: filmer og serier om hverandre, i rekkefølgen fra Plex (sist sett først)
        let both = parseContinue(deck, kinds: [.movies, .series], client: client)
        XCTAssertEqual(both.map(\.id), ["201", "101"])
        XCTAssertEqual(both.map(\.item.kind), [.series, .movies])
    }

    /// Søket: filmene eller seriene i treffene, ikke episodene og skuespillerne.
    func testSearch() {
        let result = container("""
        {"MediaContainer": {"Hub": [
          {"type": "movie", "Metadata": [{"ratingKey": "101", "type": "movie", "title": "Fyret", "year": 2021}]},
          {"type": "show", "Metadata": [{"ratingKey": "201", "type": "show", "title": "Losene", "leafCount": 2}]},
          {"type": "episode", "Metadata": [{"ratingKey": "301", "type": "episode", "title": "Fyret i tåka"}]},
          {"type": "actor", "Directory": [{"tag": "Kari Fyr"}]}]}}
        """)
        XCTAssertEqual(parseSearch(result, kind: .movies, client: client).map(\.id), ["101"])
        XCTAssertEqual(parseSearch(result, kind: .series, client: client).map(\.name), ["Losene"])
        XCTAssertTrue(parseSearch(container(#"{"MediaContainer": {}}"#), kind: .movies, client: client).isEmpty)
        // Plex-fanen: filmene og seriene, i rekkefølgen fra Plex
        let both = parseSearch(result, kinds: [.movies, .series], client: client)
        XCTAssertEqual(both.map(\.id), ["101", "201"])
        XCTAssertEqual(both.map(\.kind), [.movies, .series])
    }

    /// Radene på Hjem: filmer og serier for hver sin fane, episodene med serien sin, uten «Fortsett å se».
    func testHubs() {
        let hubs = container("""
        {"MediaContainer": {"Hub": [
          {"title": "Fortsett å se", "hubIdentifier": "home.continueWatching", "Metadata": [
            {"ratingKey": "101", "type": "movie", "title": "Fyret"}]},
          {"title": "Nytt fra Kystkanalen", "hubIdentifier": "custom.collection.2.77", "type": "episode", "Metadata": [
            {"ratingKey": "302", "type": "episode", "title": "Tåka", "parentIndex": 1, "index": 2,
             "grandparentRatingKey": "201", "grandparentTitle": "Losene", "grandparentThumb": "/t/201",
             "Media": [{"Part": [{"key": "/library/parts/32/1/file.mkv", "container": "mkv"}]}]},
            {"ratingKey": "303", "type": "episode", "title": "Uten serie"}]},
          {"title": "Nylig lagt til", "hubIdentifier": "home.recentlyAdded", "type": "mixed",
           "key": "/hubs/home/recentlyAdded?type=1", "more": true, "Metadata": [
            {"ratingKey": "102", "type": "movie", "title": "Fjorden", "year": 2020},
            {"ratingKey": "401", "type": "season", "title": "Sesong 2", "parentRatingKey": "202",
             "parentTitle": "Havet", "parentThumb": "/t/202"}]},
          {"title": "Spillelister", "hubIdentifier": "home.playlists", "Directory": [{"title": "Min liste"}]}]}}
        """)
        let series = parseHubs(hubs, kind: .series, client: client)
        XCTAssertEqual(series.map(\.title), ["Nytt fra Kystkanalen", "Nylig lagt til"])
        XCTAssertEqual(series[0].items.map(\.id), ["e302"])
        XCTAssertEqual(series[0].items[0].item.name, "Losene")
        XCTAssertEqual(series[0].items[0].item.id, "201")
        XCTAssertEqual(series[0].items[0].episode?.fileKey, "/library/parts/32/1/file.mkv")
        XCTAssertEqual(series[0].items[0].episode?.progressKey, "plex:302")
        XCTAssertEqual(series[1].items.map(\.item.name), ["Havet"])
        XCTAssertNil(series[0].key)
        XCTAssertFalse(series[0].more)
        let movies = parseHubs(hubs, kind: .movies, client: client)
        XCTAssertEqual(movies.map(\.title), ["Nylig lagt til"])
        // «Se alle»: adressen til hele raden
        XCTAssertEqual(movies[0].key, "/hubs/home/recentlyAdded?type=1")
        XCTAssertTrue(movies[0].more)
        XCTAssertEqual(movies[0].items.map(\.id), ["102"])
        XCTAssertNil(movies[0].items[0].episode)
        // Plex-fanen: radene som i Hjem i Plex, med filmer og serier i samme rad
        let both = parseHubs(hubs, kinds: [.movies, .series], client: client)
        XCTAssertEqual(both.map(\.title), ["Nytt fra Kystkanalen", "Nylig lagt til"])
        XCTAssertEqual(both[1].items.map(\.id), ["102", "202"])
        XCTAssertEqual(both[1].items.map(\.item.kind), [.movies, .series])
    }

    /// Favorittene i Plex-fanen: filmer og serier fra én henting, i rekkefølgen de ble bedt om.
    func testItemsOfBothKinds() {
        let found = parseItems(container("""
        {"MediaContainer": {"Metadata": [
          {"ratingKey": "201", "type": "show", "title": "Losene", "leafCount": 2, "viewedLeafCount": 2},
          {"ratingKey": "101", "type": "movie", "title": "Fyret"},
          {"ratingKey": "301", "type": "episode", "title": "Tåka"}]}}
        """), kinds: [.movies, .series], client: client, library: "")
        XCTAssertEqual(found.map(\.id), ["201", "101"])
        XCTAssertEqual(found.map(\.kind), [.series, .movies])
        XCTAssertEqual(found[0].watched, true)
    }

    /// Den beste tilkoblingen som svarer: hjemmenettet foran utenfra, og relé bare når ingen andre svarer.
    func testReachable() async {
        let server = PlexServer(id: "s1", name: "Hjemme", accessToken: "t1", owned: true, connections: [
            PlexConnection(uri: "https://relay.plex.direct:8443", local: false, relay: true),
            PlexConnection(uri: "https://ute.plex.direct:32400", local: false, relay: false),
            PlexConnection(uri: "http://192.168.1.10:32400", local: true, relay: false),
        ])
        let outsideOnly: RequestFetch = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Token"), "t1")
            return (Data(), request.url?.host == "192.168.1.10" ? 0 : 200)
        }
        let uri = await PlexClient.reachable(server, device: device, fetch: outsideOnly)
        XCTAssertEqual(uri, "https://ute.plex.direct:32400")
        let all: RequestFetch = { _ in (Data(), 200) }
        let home = await PlexClient.reachable(server, device: device, fetch: all)
        XCTAssertEqual(home, "http://192.168.1.10:32400")
        let none: RequestFetch = { _ in throw URLError(.timedOut) }
        let nothing = await PlexClient.reachable(server, device: device, fetch: none)
        XCTAssertNil(nothing)
    }

    /// Ruteren stopper …plex.direct: på hjemmenettet prøves også adressen rett med http (etter https), bare for private
    /// adresser.
    func testLanHTTP() {
        XCTAssertEqual(lanHTTP("https://192-168-1-10.abcdef0123.plex.direct:32400"), "http://192.168.1.10:32400")
        XCTAssertEqual(lanHTTP("https://10-0-0-5.abcdef0123.plex.direct:32401/"), "http://10.0.0.5:32401")
        XCTAssertEqual(lanHTTP("https://172-20-1-2.abcdef0123.plex.direct"), "http://172.20.1.2:32400")
        XCTAssertNil(lanHTTP("https://172-32-1-2.abcdef0123.plex.direct:32400"), "ikke privat")
        XCTAssertNil(lanHTTP("https://203-0-113-7.abcdef0123.plex.direct:32400"), "offentlig adresse")
        XCTAssertNil(lanHTTP("http://192-168-1-10.abcdef0123.plex.direct:32400"), "allerede http")
        XCTAssertNil(lanHTTP("https://192-168-1-10.example.com:32400"), "ikke plex.direct")
        XCTAssertNil(lanHTTP("https://2001-db8--1.abcdef0123.plex.direct:32400"), "IPv6")
        XCTAssertFalse(isPrivateIPv4("192.168.1"))
        XCTAssertFalse(isPrivateIPv4("192.168.1.256"))
        let server = PlexServer(id: "s1", name: "Hjemme", accessToken: "t1", owned: true, connections: [
            PlexConnection(uri: "https://ute.plex.direct:32400", local: false, relay: false),
            PlexConnection(uri: "https://192-168-1-10.abcdef0123.plex.direct:32400", local: true, relay: false),
            // utenfra (ikke local): aldri http
            PlexConnection(uri: "https://10-1-1-1.abcdef0123.plex.direct:32400", local: false, relay: false),
        ])
        XCTAssertEqual(server.ordered.map(\.uri), ["https://192-168-1-10.abcdef0123.plex.direct:32400",
                                                   "http://192.168.1.10:32400", "https://ute.plex.direct:32400",
                                                   "https://10-1-1-1.abcdef0123.plex.direct:32400"])
    }

    /// Markørene (introen og rulleteksten) og undertekstfilene ved siden av fila, og hvilken som velges.
    func testPlayInfo() {
        let meta = (container("""
        {"MediaContainer": {"Metadata": [{"ratingKey": "2102", "type": "episode",
          "Marker": [{"type": "credits", "startTimeOffset": 2400000, "endTimeOffset": 2580000, "final": true},
                     {"type": "intro", "startTimeOffset": 60000, "endTimeOffset": 95000},
                     {"type": "commercial", "startTimeOffset": 1000, "endTimeOffset": 2000},
                     {"type": "intro", "startTimeOffset": 5000, "endTimeOffset": 5000}],
          "Media": [{"Part": [{"key": "/library/parts/9/1/file.mkv", "Stream": [
            {"id": 1, "streamType": 1, "codec": "hevc"},
            {"id": 2, "streamType": 3, "codec": "subrip", "languageCode": "eng", "index": 3},
            {"id": 3, "streamType": 3, "codec": "srt", "key": "/library/streams/3", "languageCode": "nor",
             "displayTitle": "Norsk (SRT External)"},
            {"id": 4, "streamType": 3, "codec": "srt", "key": "/library/streams/4", "languageCode": "nor",
             "forced": true, "displayTitle": "Norsk Forced (SRT External)"},
            {"id": 5, "streamType": 3, "codec": "vobsub", "key": "/library/streams/5", "languageCode": "swe"}]}]}]}]}}
        """)["Metadata"] as! [[String: Any]])[0]
        let info = parsePlayInfo(meta, client: client)
        XCTAssertEqual(info.markers, [PlexMarker(kind: .intro, start: 60, end: 95),
                                      PlexMarker(kind: .credits, start: 2400, end: 2580, final: true)])
        XCTAssertTrue(info.markers[0].covers(60) && info.markers[0].covers(92))
        XCTAssertFalse(info.markers[0].covers(93.5), "for sent å hoppe")
        XCTAssertEqual(info.subtitles.map(\.name), ["Norsk (SRT External)", "Norsk Forced (SRT External)"])
        XCTAssertEqual(info.subtitles[0].url.absoluteString,
                       "http://192.168.1.10:32400/library/streams/3.srt?encoding=utf-8&X-Plex-Token=hemmelig")
        XCTAssertEqual(info.embeddedSubtitleLanguages, ["eng"])
        // norsk fra fila ved siden av (fila selv har bare engelsk), ikke den tvungne
        XCTAssertEqual(info.chosenSubtitle(preferred: norwegianLanguageCodes)?.name, "Norsk (SRT External)")
        XCTAssertNil(info.chosenSubtitle(preferred: []), "engelsk app: ingenting av seg selv")
        var embedded = info
        embedded.embeddedSubtitleLanguages = ["nor"]
        XCTAssertNil(embedded.chosenSubtitle(preferred: norwegianLanguageCodes), "fila har norsk selv")
        var chosenInPlex = info
        chosenInPlex.embeddedSubtitleSelected = true
        XCTAssertNil(chosenInPlex.chosenSubtitle(preferred: norwegianLanguageCodes), "en inni fila er valgt i Plex")
        let empty = parsePlayInfo([:], client: client)
        XCTAssertTrue(empty.markers.isEmpty && empty.subtitles.isEmpty)
        // ingen rulletekst merket «final»: den siste er det
        let old = parsePlayInfo(["Marker": [["type": "credits", "startTimeOffset": 600000, "endTimeOffset": 620000],
                                            ["type": "credits", "startTimeOffset": 2400000, "endTimeOffset": 2500000]],
                                 "Media": [["Part": [["Stream": [["streamType": 3, "codec": "ass",
                                                                  "key": "/library/streams/8"]]]]]]],
                                client: client)
        XCTAssertEqual(old.markers.map(\.final), [false, true])
        XCTAssertEqual(old.subtitles.first?.url.path, "/library/streams/8.ass")
        XCTAssertEqual(old.subtitles.first?.name, "Undertekster")
    }

    /// Et bibliotek side for side (rekkefølgen og sjangeren som spørring), sjangrene og kvaliteten på siden for en film.
    func testLibraryPagesGenresAndQuality() async throws {
        let calls = Calls()
        let fetch: RequestFetch = { request in
            await calls.add(request)
            if request.url?.path.hasSuffix("/genre") == true {
                return (Data(#"{"MediaContainer": {"Directory": [{"key": "12", "title": "Drama"}, {"key": "", "title": "x"}]}}"#.utf8), 200)
            }
            return (Data(#"{"MediaContainer": {"totalSize": 250, "Metadata": [{"ratingKey": "1", "type": "movie", "title": "A"}]}}"#.utf8), 200)
        }
        let client = PlexClient(base: "http://192.168.1.10:32400", token: "hemmelig", device: device, fetch: fetch)
        let page = try await client.page(.series, library: "2", sort: .added, genre: "12", start: 100)
        XCTAssertEqual(page.total, 250)
        let genres = try await client.genres(library: "2")
        XCTAssertEqual(genres.map(\.name), ["Drama"])
        let urls = await calls.urls
        XCTAssertEqual(urls.first, "http://192.168.1.10:32400/library/sections/2/all?type=2&sort=episode.addedAt:desc"
                       + "&includeCollections=0&genre=12&X-Plex-Container-Start=100&X-Plex-Container-Size=100")
        XCTAssertEqual(PlexSort.added.key(.movies), "addedAt:desc")
        XCTAssertEqual(PlexSort.rating.key(.series), "audienceRating:desc")
        let meta = (container("""
        {"MediaContainer": {"Metadata": [{"ratingKey": "9", "type": "movie", "title": "Fjord", "contentRating": "15",
          "Country": [{"tag": "Norge"}],
          "Media": [{"videoResolution": "4k", "videoCodec": "hevc", "audioCodec": "dca", "audioChannels": 8,
                     "Part": [{"key": "/library/parts/9/1/file.mkv", "Stream": [
                       {"streamType": 1, "colorTrc": "smpte2084"}]}]}]}]}}
        """)["Metadata"] as! [[String: Any]])[0]
        let d = parseDetails(meta, client: client)
        XCTAssertEqual(d.age, "15")
        XCTAssertEqual(d.country, "Norge")
        XCTAssertEqual(d.quality, ["4K", "HDR", "H.265", "7.1", "DTS"])
    }

    /// Bibliotekene med filmer og serier (til valget av hvilke som vises).
    func testSections() {
        let sections = parseSections(container("""
        {"MediaContainer": {"Directory": [{"key": "1", "type": "movie", "title": "Filmer"},
          {"key": "3", "type": "artist", "title": "Musikk"}, {"key": "2", "type": "show", "title": "Serier"},
          {"key": "", "type": "movie", "title": "Uten nøkkel"}]}}
        """))
        XCTAssertEqual(sections, [PlexSection(id: "1", name: "Filmer", kind: .movies),
                                  PlexSection(id: "2", name: "Serier", kind: .series)])
    }

    /// «Mer som dette»: den første raden med filmer (eller serier), uten filmen selv.
    func testRelated() {
        let related = parseRelated(container("""
        {"MediaContainer": {"Hub": [
          {"title": "Tom", "Metadata": []},
          {"title": "Mer som dette", "Metadata": [
            {"ratingKey": "1001", "type": "movie", "title": "Seg selv"},
            {"ratingKey": "1002", "type": "movie", "title": "Fjordbyen", "librarySectionID": 1},
            {"ratingKey": "2001", "type": "show", "title": "En serie"},
            {"ratingKey": "1002", "type": "movie", "title": "Fjordbyen"}]},
          {"title": "Med samme skuespiller", "Metadata": [{"ratingKey": "1003", "type": "movie", "title": "Kyst"}]}]}}
        """), kind: .movies, exclude: "1001", client: client)
        XCTAssertEqual(related.map(\.id), ["1002"])
        XCTAssertEqual(related.first?.source, "plex")
        XCTAssertTrue(parseRelated([:], kind: .series, exclude: "1", client: client).isEmpty)
    }

    /// Sett og ikke sett: /:/scrobble og /:/unscrobble, og en feil når serveren ikke svarer ja.
    func testSetWatched() async throws {
        let calls = Calls()
        let fetch: RequestFetch = { request in
            await calls.add(request)
            return (Data(), request.url?.query?.contains("key=9") == true ? 401 : 200)
        }
        let client = PlexClient(base: "http://192.168.1.10:32400", token: "hemmelig", device: device, fetch: fetch)
        try await client.setWatched("2001", true)
        try await client.setWatched("2102", false)
        do {
            try await client.setWatched("9", true)
            XCTFail("401 skulle gitt en feil")
        } catch {}
        let urls = await calls.urls
        XCTAssertEqual(urls.prefix(2), [
            "http://192.168.1.10:32400/:/scrobble?identifier=com.plexapp.plugins.library&key=2001",
            "http://192.168.1.10:32400/:/unscrobble?identifier=com.plexapp.plugins.library&key=2102",
        ])
    }

    /// Koden, nøkkelen når den er skrevet inn, og hodene Plex vil ha.
    func testAccountClient() async throws {
        let calls = Calls()
        let fetch: RequestFetch = { request in
            await calls.add(request)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "fyrlys-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Product"), "Fyrlys")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Language"), "nb")
            if request.httpMethod == "POST" { return (Data(#"{"id": 7, "code": "ABCD"}"#.utf8), 201) }
            return (Data(#"{"id": 7, "code": "ABCD", "authToken": "nøkkel"}"#.utf8), 200)
        }
        let account = PlexAccountClient(device: device, base: "https://plex.example.com", fetch: fetch)
        let pin = try await account.createPin()
        XCTAssertEqual(pin.code, "ABCD")
        let token = try await account.token(for: pin)
        XCTAssertEqual(token, "nøkkel")
        let urls = await calls.urls
        XCTAssertEqual(urls, ["https://plex.example.com/api/v2/pins?strong=false",
                              "https://plex.example.com/api/v2/pins/7"])
    }
}

private actor Calls {
    var urls: [String] = []
    func add(_ request: URLRequest) { urls.append(request.url?.absoluteString ?? "") }
}
