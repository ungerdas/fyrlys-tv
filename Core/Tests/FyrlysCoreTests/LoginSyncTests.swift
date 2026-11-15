@testable import FyrlysCore
import XCTest

/// Innloggingene i iCloud: flettes, fjernede kommer ikke tilbake, og den i bruk blir stående.
final class LoginSyncTests: XCTestCase {
    let a = Login(server: "http://iptv.example.com:8080", username: "kari", password: "p1")
    let b = Login(server: "http://tv.example.org", username: "ola", password: "p2")
    let c = Login(m3u: "http://iptv.example.net/liste.m3u")

    func testNewFromCloudComeLast() {
        let merged = mergeLogins(local: [a], cloud: SyncedLogins(logins: [b, a]))
        XCTAssertEqual(merged.map(\.id), [a.id, b.id])
    }

    func testRemovedElsewhereGoesAwayButNotTheOneInUse() {
        let cloud = SyncedLogins(logins: [b], removed: [a.id, c.id])
        XCTAssertEqual(mergeLogins(local: [a, c], cloud: cloud, keep: a.id).map(\.id), [a.id, b.id])
        XCTAssertEqual(mergeLogins(local: [c], cloud: cloud).map(\.id), [b.id])
    }

    func testRemovedHereDoesNotComeBack() {
        let merged = mergeLogins(local: [a], cloud: SyncedLogins(logins: [a, b]), removedHere: [b.id])
        XCTAssertEqual(merged.map(\.id), [a.id])
    }

    func testRenamedElsewhereWins() {
        let renamed = a.named("Hjemme")
        let merged = mergeLogins(local: [a], cloud: SyncedLogins(logins: [renamed]))
        XCTAssertEqual(merged.first?.name, "Hjemme")
    }

    func testSyncedDropsRemovedThatCameBack() {
        let synced = syncedLogins([a, b], removed: [b.id, c.id, c.id])
        XCTAssertEqual(synced.removed, [c.id])
        let many = syncedLogins([], removed: (0..<80).map { "id\($0)" })
        XCTAssertEqual(many.removed.count, SyncedLogins.removedLimit)
        XCTAssertEqual(many.removed.last, "id79")
    }

    func testRoundTrip() throws {
        let synced = SyncedLogins(logins: [a, c], removed: ["x"])
        let data = try JSONEncoder().encode(synced)
        XCTAssertEqual(try JSONDecoder().decode(SyncedLogins.self, from: data), synced)
    }
}
