@testable import FyrlysCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// M3U-lister og TV-guiden (XMLTV), med oppdiktede lister og kanaler.
final class M3UTests: XCTestCase {
    let list = """
    \u{FEFF}#EXTM3U url-tvg="http://iptv.example.com/guide.xml.gz, http://iptv.example.com/reserve.xml" x-tvg-url="http://iptv.example.com/guide.xml.gz"
    #EXTINF:-1 tvg-id="fjord.no" tvg-name="Fjordkanalen" tvg-logo="http://iptv.example.com/logo/1.png" group-title="Nyheter",Fjordkanalen HD
    http://iptv.example.com/strom/1.m3u8
    #EXTINF:-1 tvg-id="" tvg-logo="logo.png" group-title="Nyheter",Kystnytt, 24 timer
    http://iptv.example.com/live/bruker/passord/2.ts
    #EXTINF:-1 tvg-chno="7" tvg-name="Sport 1",
    #EXTGRP:Sport
    http://iptv.example.com/bruker/passord/11
    #EXTINF:-1 group-title="Filmer",Fyret i nord (2021)
    http://iptv.example.com/movie/bruker/passord/501.mkv
    #EXTINF:-1,Uten gruppe
    http://iptv.example.com/strom/9.m3u8?token=abc
    #EXTINF:-1 group-title="Nyheter",Fjordkanalen HD
    http://iptv.example.com/strom/1b.m3u8
    #EXTINF:-1 group-title="Serier",Losene S01E01
    http://iptv.example.com/strom/episode.mp4?x=1

    """

    func testParseM3U() {
        let parsed = parseM3U(list)
        XCTAssertEqual(parsed.guides, ["http://iptv.example.com/guide.xml.gz", "http://iptv.example.com/reserve.xml"])
        XCTAssertEqual(parsed.skippedVOD, 2, "filmen og episoden hoppes over")
        XCTAssertEqual(parsed.entries.map(\.name),
                       ["Fjordkanalen HD", "Kystnytt, 24 timer", "Sport 1", "Uten gruppe", "Fjordkanalen HD"])
        let first = parsed.entries[0]
        XCTAssertEqual(first.tvgId, "fjord.no")
        XCTAssertEqual(first.tvgName, "Fjordkanalen")
        XCTAssertEqual(first.logo, "http://iptv.example.com/logo/1.png")
        XCTAssertEqual(first.group, "Nyheter")
        XCTAssertNil(parsed.entries[1].logo, "en logo uten http tas ikke med")
        XCTAssertEqual(parsed.entries[2].group, "Sport", "#EXTGRP når group-title mangler")
        XCTAssertEqual(parsed.entries[2].number, 7)
        XCTAssertEqual(parsed.entries[2].url, "http://iptv.example.com/bruker/passord/11")
        XCTAssertEqual(parsed.entries[3].group, "")
    }

    func testM3UWithoutHeaderAndWindowsLineEnds() {
        let parsed = parseM3U("#EXTINF:-1 tvg-name=\"A, B\",\r\nhttp://iptv.example.com/a.m3u8\r\n#EXTINF:0,\r\nhttp://x\r\n")
        XCTAssertEqual(parsed.entries.map(\.name), ["A, B"], "navnet fra tvg-name, og uten navn hoppes kanalen over")
        XCTAssertTrue(parsed.guides.isEmpty)
        XCTAssertTrue(parseM3U("<html><body>Ikke her</body></html>").entries.isEmpty)
        XCTAssertFalse(looksLikeM3U(Data("<html></html>".utf8)))
        XCTAssertTrue(looksLikeM3U(Data("#EXTM3U\n".utf8)))
    }

    func testListsFromM3U() {
        let lists = parseM3U(list).lists(hasGuide: true)
        XCTAssertEqual(lists.categories.map(\.id), ["Nyheter", "Sport", ungroupedCategory])
        XCTAssertEqual(lists.categories.last?.name, "Uten kategori")
        XCTAssertEqual(lists.channels.count, 5)
        XCTAssertEqual(lists.guides, parseM3U(list).guides)
        let ids = lists.channels.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "to kanaler med samme navn får hver sin id")
        XCTAssertEqual(ids[0], stableHash("id:fjord.no|Fjordkanalen HD"))
        XCTAssertEqual(ids[1], stableHash("n:Nyheter|Kystnytt, 24 timer"))
        XCTAssertEqual(ids[4], stableHash("n:Nyheter|Fjordkanalen HD"))
        XCTAssertEqual(lists.channels[2].number, 7)
        XCTAssertEqual(lists.channels[3].number, 4, "uten tvg-chno: plassen i lista")
        XCTAssertEqual(lists.channels[0].m3u, M3UChannel(url: "http://iptv.example.com/strom/1.m3u8", tvgId: "fjord.no",
                                                         tvgName: "Fjordkanalen"))
        XCTAssertTrue(lists.channels.allSatisfy { $0.hasEpg && $0.archiveDays == 0 })
        XCTAssertFalse(parseM3U(list).lists(hasGuide: false).channels[0].hasEpg)
        // like id-er neste gang (favorittene følger med)
        XCTAssertEqual(parseM3U(list).lists(hasGuide: true).channels.map(\.id), ids)
        // lagret og lest igjen (lista fra sist): adressen og navnene i guiden følger med
        let decoded = try! JSONDecoder().decode(Lists.self, from: JSONEncoder().encode(lists))
        XCTAssertEqual(decoded.channels, lists.channels)
        XCTAssertEqual(decoded.guides, lists.guides)
        // en kanal delt ut av en annen (NRK 3/SUPER) beholder adressen
        XCTAssertEqual(lists.channels[0].split("Fjord 2", key: "fjord2").m3u, lists.channels[0].m3u)
    }

    func testSameChannelTwice() {
        let twice = parseM3U("""
        #EXTINF:-1 tvg-id="a.no",A
        http://iptv.example.com/a.m3u8
        #EXTINF:-1 tvg-id="a.no",A
        http://iptv.example.com/a2.m3u8
        #EXTINF:-1 tvg-id="a.no",A
        http://iptv.example.com/a3.m3u8
        """).lists(hasGuide: false)
        XCTAssertEqual(twice.channels.map(\.id),
                       [stableHash("id:a.no|A"), stableHash("id:a.no|A#2"), stableHash("id:a.no|A#3")])
        XCTAssertEqual(twice.channels.map { $0.m3u?.url ?? "" },
                       ["http://iptv.example.com/a.m3u8", "http://iptv.example.com/a2.m3u8",
                        "http://iptv.example.com/a3.m3u8"])
    }

    func testOldListsAndLoginsAreRead() {
        let old = #"{"categories":[],"channels":[{"id":"1","name":"A","categoryId":"1"}],"saved":0}"#
        let lists = try! JSONDecoder().decode(Lists.self, from: Data(old.utf8))
        XCTAssertNil(lists.guides)
        XCTAssertNil(lists.channels[0].m3u)
        let login = try! JSONDecoder().decode(Login.self, from: Data(
            #"{"server":"http://iptv.example.com","username":"u","password":"p"}"#.utf8))
        XCTAssertFalse(login.isM3U)
        XCTAssertNil(login.epg)
    }

    func testM3ULogin() {
        let login = Login(m3u: "http://iptv.example.com:8080/liste.m3u?user=a&password=hemmelig", epg: "")
        XCTAssertTrue(login.isM3U)
        XCTAssertNil(login.epg, "et tomt felt er ingen EPG-lenke")
        XCTAssertEqual(login.server, "http://iptv.example.com:8080")
        XCTAssertEqual(login.defaultLabel, "M3U-liste fra iptv.example.com")
        XCTAssertEqual(login.label, login.defaultLabel)
        XCTAssertEqual(login.named("Hjemme").label, "Hjemme")
        // id-en er uten passordet, og den samme når passordet byttes
        XCTAssertEqual(login.id, stableHash("m3u|http://iptv.example.com:8080/liste.m3u?user=a"))
        XCTAssertEqual(login.id, Login(m3u: "http://iptv.example.com:8080/liste.m3u?user=a&password=nytt").id)
        XCTAssertNotEqual(login.id, Login(server: "http://iptv.example.com:8080", username: "", password: "").id)
        XCTAssertEqual(withoutPassword("http://iptv.example.com/a.m3u"), "http://iptv.example.com/a.m3u")
        XCTAssertEqual(withoutPassword("http://iptv.example.com/a.m3u?pwd=x"), "http://iptv.example.com/a.m3u")
        let round = try! JSONDecoder().decode(Login.self, from: JSONEncoder().encode(
            Login(m3u: "http://iptv.example.com/a.m3u", epg: "http://iptv.example.com/guide.xml")))
        XCTAssertEqual(round.m3u, "http://iptv.example.com/a.m3u")
        XCTAssertEqual(round.epg, "http://iptv.example.com/guide.xml")
    }

    func testLinks() throws {
        XCTAssertEqual(try normalizeLink(" iptv.example.com/liste.m3u ", empty: "tom"), "http://iptv.example.com/liste.m3u")
        XCTAssertEqual(try normalizeLink("HTTPS://iptv.example.com/a", empty: "tom"), "HTTPS://iptv.example.com/a")
        XCTAssertThrowsError(try normalizeLink("  ", empty: "tom")) { XCTAssertEqual(($0 as? SourceError)?.message, "tom") }
        XCTAssertThrowsError(try normalizeLink("http://", empty: "tom")) {
            XCTAssertEqual(($0 as? SourceError)?.message, "Ugyldig lenke")
        }
        // en Xtream-lenke blir en Xtream-innlogging
        let xtream = xtreamLogin(fromM3U: "http://iptv.example.com:8080/get.php?username=u&password=p%2Bq&type=m3u_plus")
        XCTAssertEqual(xtream?.server, "http://iptv.example.com:8080")
        XCTAssertEqual(xtream?.username, "u")
        XCTAssertEqual(xtream?.password, "p+q")
        XCTAssertEqual(xtreamLogin(fromM3U: "https://iptv.example.com/tv/player_api.php?username=u&password=p")?.server,
                       "https://iptv.example.com/tv")
        XCTAssertNil(xtreamLogin(fromM3U: "http://iptv.example.com/get.php?username=u"))
        XCTAssertNil(xtreamLogin(fromM3U: "http://iptv.example.com/liste.m3u?username=u&password=p"))
        XCTAssertNil(xtreamLogin(fromM3U: "http://iptv.example.com/forget.php?username=u&password=p"))
    }

    func testPlayURLs() {
        XCTAssertEqual(m3uPlayURLs("http://iptv.example.com/live/u/p/2.ts").map(\.absoluteString),
                       ["http://iptv.example.com/live/u/p/2.m3u8", "http://iptv.example.com/live/u/p/2.ts"])
        XCTAssertEqual(m3uPlayURLs("http://iptv.example.com:8080/u/p/11").map(\.absoluteString),
                       ["http://iptv.example.com:8080/live/u/p/11.m3u8", "http://iptv.example.com:8080/u/p/11"])
        XCTAssertEqual(m3uPlayURLs("http://iptv.example.com/live/u/p/2.m3u8").map(\.absoluteString),
                       ["http://iptv.example.com/live/u/p/2.m3u8"])
        XCTAssertEqual(m3uPlayURLs("http://iptv.example.com/strom/1.m3u8").count, 1)
        XCTAssertEqual(m3uPlayURLs("http://iptv.example.com/u/p/11?token=x").count, 1)
        XCTAssertEqual(m3uPlayURLs("http://iptv.example.com/a/b/navn").count, 1)
        XCTAssertTrue(m3uPlayURLs("").isEmpty)
    }

    func testVODAddresses() {
        XCTAssertTrue(isVODURL("http://iptv.example.com/movie/u/p/1.mkv"))
        XCTAssertTrue(isVODURL("http://iptv.example.com/SERIES/u/p/1"))
        XCTAssertTrue(isVODURL("http://iptv.example.com/a.MP4"))
        XCTAssertTrue(isVODURL("http://iptv.example.com/a.mp4?x=1"))
        XCTAssertFalse(isVODURL("http://iptv.example.com/live/u/p/1.ts"))
        XCTAssertFalse(isVODURL("http://iptv.example.com/mp4kanalen/1.m3u8"))
    }

    // ── XMLTV ──

    /// 2026-11-04 19:10 UTC (20:10 i Norge)
    let now = Date(timeIntervalSince1970: 1_793_819_400)
    /// 18:00, 19:00, 19:30, 20:00 og 22:00 UTC samme dag
    let t1800 = Date(timeIntervalSince1970: 1_793_815_200), t1900 = Date(timeIntervalSince1970: 1_793_818_800)
    let t1930 = Date(timeIntervalSince1970: 1_793_820_600), t2000 = Date(timeIntervalSince1970: 1_793_822_400)
    let t2200 = Date(timeIntervalSince1970: 1_793_829_600)

    var guideXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tv SYSTEM "xmltv.dtd">
        <tv generator-info-name="test">
          <channel id="fjord.no"><display-name lang="no">Fjordkanalen</display-name><display-name>Fjord</display-name></channel>
          <channel id='kyst.no'>
            <display-name>Kystnytt, 24 timer</display-name>
          </channel>
          <channel id="tom.no"/>
          <programme start="20261104190000 +0100" stop="20261104200000 +0100" channel="fjord.no">
            <title lang="no">Gammelt</title>
          </programme>
          <programme start="20261104203000 +0100" stop="20261104213000 +0100" channel="fjord.no">
            <title lang="no">Kveldsnytt &amp; v&#230;ret</title><title lang="en">Evening news</title>
            <desc lang="no"><![CDATA[Nyheter <direkte> fra kysten.]]></desc>
          </programme>
          <programme start="20261104200000 +0100" stop="20261104203000 +0100" channel="fjord.no">
            <title>Dagsrevyen</title><desc>Med &#x00F8;yeblikk &lt;3</desc>
          </programme>
          <programme start="20261104200000" stop="20261104210000" channel="kyst.no"><title>Kysten</title></programme>
          <programme start="20261106200000 +0000" stop="20261106210000 +0000" channel="kyst.no"><title>Langt fram</title></programme>
          <programme start="20261104200000 +0000" stop="20261104210000 +0000" channel="annen.no"><title>Annen</title></programme>
          <programme start="20261104200000 +0000" stop="20261104210000 +0000" channel="kyst.no"/>
          <programme start="20261104210000 +0000" stop="20261104220000 +0000" channel="kyst.no"><title></title></programme>
        </tv>
        """
    }

    func testParseXMLTV() {
        let guide = parseXMLTV(guideXML, now: now)
        XCTAssertEqual(guide.names["fjordkanalen"], "fjord.no")
        XCTAssertEqual(guide.names["fjord"], "fjord.no")
        XCTAssertEqual(guide.names["kystnytt, 24 timer"], "kyst.no")
        let fjord = guide.programs["fjord.no"] ?? []
        XCTAssertEqual(fjord.map(\.title), ["Gammelt", "Dagsrevyen", "Kveldsnytt & været"],
                       "sortert etter start; den første tittelen; &amp; og &#230;")
        XCTAssertEqual(fjord[0].start, t1800)
        XCTAssertEqual(fjord[2].description, "Nyheter <direkte> fra kysten.")
        XCTAssertEqual(fjord[1].description, "Med øyeblikk <3")
        XCTAssertEqual(fjord[1].start, t1900)
        XCTAssertEqual(fjord[1].stop, t1930)
        XCTAssertEqual(guide.programs["kyst.no"]?.map(\.title), ["Kysten"],
                       "uten sone er UTC; mer enn et døgn fram, uten tittel og uten innhold tas ikke med")
        XCTAssertEqual(guide.programs["kyst.no"]?.first?.start, t2000)
        XCTAssertEqual(guide.programs["annen.no"]?.count, 1)
        XCTAssertFalse(guide.isEmpty)
        XCTAssertTrue(parseXMLTV("<html>ikke en guide</html>", now: now).isEmpty)
    }

    func testXMLTVForTheChannelsInTheList() {
        let lists = parseM3U(list).lists(hasGuide: true)
        let wanted = XMLTVWanted(channels: lists.channels)
        XCTAssertTrue(wanted.ids.contains("fjord.no"))
        XCTAssertTrue(wanted.names.contains("kystnytt, 24 timer"))
        let guide = parseXMLTV(guideXML, now: now, wanted: wanted)
        XCTAssertNil(guide.programs["annen.no"], "kanaler som ikke er i lista, tas ikke med")
        XCTAssertEqual(guide.programs(for: lists.channels[0]).count, 3, "etter tvg-id")
        XCTAssertEqual(guide.programs(for: lists.channels[1]).map(\.title), ["Kysten"], "etter navnet")
        XCTAssertTrue(guide.programs(for: lists.channels[2]).isEmpty)
        // tvg-id som ikke finnes i guiden: navnet, så tvg-name
        XCTAssertEqual(guide.programs(tvgId: "ukjent", name: "Noe annet", tvgName: "Fjord").count, 3)
        XCTAssertTrue(guide.programs(for: Channel(id: "x", name: "Fjordkanalen", categoryId: "1")).isEmpty,
                      "bare kanaler fra M3U-lister")
    }

    func testXMLTVTimesAndText() {
        XCTAssertEqual(xmltvDate("20261104203000 +0100"), t1930)
        XCTAssertEqual(xmltvDate("202611042030 -0130"), t2200, "uten sekunder, og en sone med halvtimer")
        XCTAssertEqual(xmltvDate("19700101000000"), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(xmltvDate("20240229120000 +0000"), Date(timeIntervalSince1970: 1_709_208_000), "skuddår")
        XCTAssertNil(xmltvDate("2026-11-04 20:30"))
        XCTAssertNil(xmltvDate("20261304203000"))
        XCTAssertEqual(xmltvText("  <![CDATA[ A & B ]]> "), "A & B")
        XCTAssertEqual(xmltvText("&amp;#228; &#228; &#xE5; &#12ab; &#;"), "&#228; ä å &#12ab; &#;")
        XCTAssertEqual(xmltvText("Tom &quot;og&quot; Jerry&apos;s"), "Tom \"og\" Jerry's")
    }

    func testLatin1Guide() {
        var data = Data(#"<?xml version="1.0" encoding="ISO-8859-1"?><tv><channel id="a"><display-name>"#.utf8)
        data.append(contentsOf: [0x42, 0xE5, 0x74])   // «Båt» i Latin-1
        data.append(Data(#"</display-name></channel><programme start="20261104200000 +0000" stop="20261104210000 +0000" channel="a"><title>S"#.utf8))
        data.append(contentsOf: [0xF8, 0x72])        // «Sør»
        data.append(Data("</title></programme></tv>".utf8))
        let guide = parseXMLTV(data, now: now)
        XCTAssertEqual(guide.names["båt"], "a")
        XCTAssertEqual(guide.programs["a"]?.first?.title, "Sør")
    }

    func testGzipHeader() {
        // gzip med filnavn (FNAME) foran DEFLATE-dataene, og sjekksum og lengde til slutt
        var gz: [UInt8] = [0x1F, 0x8B, 8, 0x08, 0, 0, 0, 0, 0, 3]
        gz += Array("guide.xml".utf8) + [0]
        let deflate: [UInt8] = [0x01, 0x02, 0x00, 0xFD, 0xFF, 0x41, 0x42]   // en lagret blokk med «AB»
        gz += deflate + [0, 0, 0, 0, 2, 0, 0, 0]
        XCTAssertTrue(isGzip(Data(gz)))
        XCTAssertEqual(gzipDeflate(Data(gz)).map { [UInt8]($0) }, deflate)
        XCTAssertNil(gzipDeflate(Data([0x1F, 0x8B, 8, 0])))
        XCTAssertFalse(isGzip(Data("#EXTM3U".utf8)))
        XCTAssertEqual(unpackGzip(Data("#EXTM3U".utf8)), Data("#EXTM3U".utf8), "ikke gzip: som det er")
        #if canImport(Darwin)
        XCTAssertEqual(unpackGzip(Data(gz)), Data("AB".utf8))
        #endif
    }

    // ── kilden ──

    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        func add(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return paths }
    }

    func source(epg: String? = nil, guide: String? = nil, guideStatus: Int = 200, listBody: String? = nil,
                listStatus: Int = 200, requests: Requests = Requests(),
                clock: @escaping @Sendable () -> Date) -> M3USource {
        let body = listBody ?? list
        let xml = guide ?? guideXML
        let fetch: Fetch = { url in
            requests.add(url.path)
            switch url.path {
            case "/liste.m3u": return (Data(body.utf8), listStatus)
            case "/guide.xml.gz", "/egen.xml": return (Data(xml.utf8), guideStatus)
            default: return (Data(), 404)
            }
        }
        return M3USource(login: Login(m3u: "http://iptv.example.com/liste.m3u", epg: epg), fetch: fetch, clock: clock)
    }

    func testSourceListsAndGuide() async throws {
        let requests = Requests()
        let at = now
        let m3u = source(requests: requests, clock: { at })
        let lists = try await m3u.lists()
        XCTAssertEqual(lists.channels.count, 5)
        let programs = await m3u.programs(for: lists.channels[0])
        XCTAssertEqual(programs.map(\.title), ["Dagsrevyen", "Kveldsnytt & været"], "bare det som ikke er slutt")
        let kyst = await m3u.programs(for: lists.channels[1])
        XCTAssertEqual(kyst.map(\.title), ["Kysten"])
        let sport = await m3u.programs(for: lists.channels[2])
        XCTAssertTrue(sport.isEmpty)
        let one = await m3u.programs(for: lists.channels[0], limit: 1)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(requests.all, ["/liste.m3u", "/guide.xml.gz"], "guiden hentes én gang")
    }

    func testSourceOwnGuideAndErrors() async {
        let requests = Requests()
        let at = now
        let own = source(epg: "http://iptv.example.com/egen.xml", requests: requests, clock: { at })
        let lists = try? await own.lists()
        let programs = await own.programs(for: lists!.channels[0])
        XCTAssertEqual(programs.count, 2)
        XCTAssertEqual(requests.all.last, "/egen.xml", "lenken du har oppgitt, går foran den i lista")

        func message(_ source: M3USource) async -> String? {
            do {
                _ = try await source.lists()
                return nil
            } catch {
                return (error as? SourceError)?.message
            }
        }
        let cases: [(M3USource, String)] = [
            (source(listStatus: 403, clock: { at }), "Serveren avviste M3U-lista (HTTP 403)"),
            (source(listStatus: 500, clock: { at }), "Serveren svarte HTTP 500 for M3U-lista"),
            (source(listBody: "<html></html>", clock: { at }), "Lenken ga ikke en M3U-liste"),
            (source(listBody: "#EXTM3U\n", clock: { at }), "Fant ingen kanaler i lista"),
            (source(listBody: "#EXTINF:-1,Film\nhttp://iptv.example.com/movie/1.mkv\n", clock: { at }),
             "Lista har bare filmer og serier, ingen TV-kanaler"),
            (M3USource(login: Login(m3u: "http://iptv.example.com/liste.m3u"),
                       fetch: { _ in throw URLError(.notConnectedToInternet) }),
             "Får ikke hentet M3U-lista: Får ikke kontakt med serveren. Sjekk nettforbindelsen."),
        ]
        for (source, expected) in cases {
            let found = await message(source)
            XCTAssertEqual(found, expected)
        }
    }

    func testGuideIsRetriedAfterAWhile() async throws {
        final class Clock: @unchecked Sendable {
            var now: Date
            init(_ now: Date) { self.now = now }
        }
        let clock = Clock(now)
        let requests = Requests()
        let m3u = source(guideStatus: 500, requests: requests, clock: { clock.now })
        let lists = try await m3u.lists()
        let first = await m3u.programs(for: lists.channels[0])
        let second = await m3u.programs(for: lists.channels[1])
        XCTAssertTrue(first.isEmpty && second.isEmpty)
        XCTAssertEqual(requests.all.filter { $0 == "/guide.xml.gz" }.count, 1, "ikke et nytt forsøk for hvert kort")
        clock.now = now.addingTimeInterval(M3USource.retryAfter + 1)
        _ = await m3u.programs(for: lists.channels[0])
        XCTAssertEqual(requests.all.filter { $0 == "/guide.xml.gz" }.count, 2, "prøvd igjen etter fem minutter")
    }

    func testCachedListGivesTheGuideLinks() async {
        let at = now
        let m3u = source(clock: { at })
        // lista fra sist (før den er hentet på nytt): lenkene til guiden står i den
        let cached = parseM3U(list).lists(hasGuide: true)
        await m3u.remember(cached)
        let programs = await m3u.programs(for: cached.channels[0])
        XCTAssertEqual(programs.count, 2)
    }

    /// En stor liste og guide (som hos en stor leverandør) leses fort nok.
    func testBigListAndGuide() {
        var m3u = "#EXTM3U url-tvg=\"http://iptv.example.com/guide.xml\"\n"
        var xml = "<?xml version=\"1.0\"?><tv>"
        for i in 0..<20_000 {
            m3u += "#EXTINF:-1 tvg-id=\"k\(i)\" tvg-logo=\"http://iptv.example.com/\(i).png\" group-title=\"Gruppe \(i % 300)\",Kanal \(i) HD\n"
            m3u += "http://iptv.example.com/live/u/p/\(i).ts\n"
            xml += "<channel id=\"k\(i)\"><display-name>Kanal \(i)</display-name></channel>"
        }
        for i in 0..<2_000 {
            for h in 0..<12 {
                xml += "<programme start=\"202611042\(h % 4)0000 +0000\" stop=\"202611042\(h % 4)3000 +0000\" "
                xml += "channel=\"k\(i)\"><title>Program \(h)</title><desc>Et oppdiktet program.</desc></programme>"
            }
        }
        xml += "</tv>"
        let started = Date()
        let lists = parseM3U(m3u).lists(hasGuide: true)
        let listTime = Date().timeIntervalSince(started)
        XCTAssertEqual(lists.channels.count, 20_000)
        XCTAssertEqual(lists.categories.count, 300)
        let guideStarted = Date()
        let guide = parseXMLTV(xml, now: now, wanted: XMLTVWanted(channels: lists.channels))
        let guideTime = Date().timeIntervalSince(guideStarted)
        XCTAssertEqual(guide.programs.count, 2_000)
        print("M3U med 20 000 kanaler: \(Int(listTime * 1000)) ms, XMLTV med 24 000 programmer: \(Int(guideTime * 1000)) ms")
    }
}
