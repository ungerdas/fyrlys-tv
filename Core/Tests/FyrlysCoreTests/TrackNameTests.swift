import XCTest
@testable import FyrlysCore

final class TrackNameTests: XCTestCase {
    override func tearDown() { appLanguage = "no" }

    func testShortNames() {
        appLanguage = "no"
        XCTAssertEqual(shortTrackName("Norsk - [Norwegian]"), "Norsk")
        XCTAssertEqual(shortTrackName("Track 1 - [English]"), "Engelsk")
        XCTAssertEqual(shortTrackName("English - SDH - [English]"), "Engelsk (SDH)")
        XCTAssertEqual(shortTrackName("Norsk (SRT External)"), "Norsk")
        XCTAssertEqual(shortTrackName("English (Forced)"), "Engelsk (Tvungen)")
        XCTAssertEqual(shortTrackName("Swedish"), "Svensk")
        XCTAssertEqual(shortTrackName("Surround 5.1 - [English]"), "Surround 5.1")
        XCTAssertEqual(shortTrackName("Director's Commentary - [English]"), "Director's Commentary")
        XCTAssertEqual(shortTrackName("Spor 3"), "Spor 3")
        XCTAssertEqual(shortTrackName("Track 2"), "Track 2")
    }

    func testEnglishApp() {
        appLanguage = "en"
        XCTAssertEqual(shortTrackName("Norsk - [Norwegian]"), "Norwegian")
        XCTAssertEqual(shortTrackName("Track 1 - [English]"), "English")
        XCTAssertEqual(shortTrackName("English (Forced)"), "English (Forced)")
    }
}
