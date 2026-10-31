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
              "tv_archive": 1, "tv_archive_duration": "7"},
             {"stream_id": "102", "name": "TV 2", "category_id": 1, "num": 2, "stream_icon": "", "tv_archive": "0"},
             {"stream_id": "103", "name": "", "category_id": "1"}]
            """))
        XCTAssertEqual(chans.count, 2)
        XCTAssertEqual(chans[0], Channel(id: "101", name: "NRK 1 HD", categoryId: "1", number: 1,
                                         logo: "http://logo/1.png", archiveDays: 7))
        XCTAssertEqual(chans[1].logo, nil)
        XCTAssertEqual(chans[1].categoryId, "1")
        XCTAssertEqual(chans[1].archiveDays, 0)
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
        XCTAssertEqual(hhmm(Date(timeIntervalSince1970: 3600 * 5 + 60 * 7), timeZone: TimeZone(identifier: "UTC")!), "05:07")
    }
}

final class LibraryTests: XCTestCase {
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
