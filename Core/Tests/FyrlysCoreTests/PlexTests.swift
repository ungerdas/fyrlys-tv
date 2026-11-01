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
          "Role": [{"tag": "A"}, {"tag": "B"}], "Director": [{"tag": "C"}],
          "Media": [{"container": "mp4", "Part": [{"key": "/library/parts/9/1/file.mp4"}]}]}]}}
        """)["Metadata"] as! [[String: Any]])[0], client: client)
        XCTAssertEqual(details.plot, "Om et fyr.")
        XCTAssertEqual(details.genre, "Drama, Krim")
        XCTAssertEqual(details.cast, "A, B")
        XCTAssertEqual(details.duration, "112 min")
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
           "grandparentTitle": "Losene", "grandparentThumb": "/library/metadata/201/thumb/1"},
          {"ratingKey": "305", "type": "episode", "title": "Hjem", "grandparentRatingKey": "201",
           "grandparentTitle": "Losene"},
          {"ratingKey": "101", "type": "movie", "title": "Fyret"}]}}
        """)
        XCTAssertEqual(parseContinue(deck, kind: .series, client: client).map(\.id), ["201"])
        XCTAssertEqual(parseContinue(deck, kind: .movies, client: client).map(\.name), ["Fyret"])
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
          {"title": "Nylig lagt til", "hubIdentifier": "home.recentlyAdded", "type": "mixed", "Metadata": [
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
        let movies = parseHubs(hubs, kind: .movies, client: client)
        XCTAssertEqual(movies.map(\.title), ["Nylig lagt til"])
        XCTAssertEqual(movies[0].items.map(\.id), ["102"])
        XCTAssertNil(movies[0].items[0].episode)
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

    /// Koden, nøkkelen når den er skrevet inn, og hodene Plex vil ha.
    func testAccountClient() async throws {
        let calls = Calls()
        let fetch: RequestFetch = { request in
            await calls.add(request)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "fyrlys-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Product"), "Fyrlys")
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
