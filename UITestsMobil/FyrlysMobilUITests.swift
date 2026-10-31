import UIKit
import XCTest

/// Starter appen i iPhone- og iPad-simulatoren mot den falske leverandøren (tools/fake_xtream.py), sjekker sidene og
/// tar skjermbilder (de legges i grenen «skjermbilder-mobil» av bygget på GitHub, med «iphone» eller «ipad» i navnet).
final class FyrlysMobilUITests: XCTestCase {
    var server: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_SERVER"] ?? "http://127.0.0.1:8899" }
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    func launch(_ screen: String, language: String = "no") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FYRLYS_TEST_SERVER": server,
            "FYRLYS_TEST_SCREEN": screen,
            "FYRLYS_TEST_LANG": language,
        ]
        app.launch()
        return app
    }

    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// «02-tv» blir «02-iphone-tv» eller «02-ipad-tv».
    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name.prefix(3))\(isPad ? "ipad" : "iphone")-\(name.dropFirst(3))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func wait(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "vent")], timeout: seconds)
    }

    func test01Login() {
        let app = launch("login")
        XCTAssertTrue(find(app, "innlogging").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["logg-inn"].exists)
        wait(1)
        shot("01-innlogging")
    }

    func test02TV() {
        let app = launch("tv")
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30), "kanalkortene kom ikke")
        if isPad {
            XCTAssertTrue(find(app, "hylle-2").exists, "kategorien Sport mangler i sidemenyen")
            XCTAssertFalse(find(app, "hylle-6").exists, "tomme kategorier skal ikke vises")
        } else {
            XCTAssertTrue(find(app, "kategori-velger").exists, "kategorivelgeren mangler")
        }
        wait(3) // logoer og programinfo
        shot("02-tv")
    }

    /// Trykk på stjernen på et kort: kanalen blir favoritt.
    func test03Favorite() {
        let app = launch("tv")
        let star = find(app, "stjerne-kanal-1")
        XCTAssertTrue(star.waitForExistence(timeout: 30), "stjernen på kortet mangler")
        star.tap()
        XCTAssertTrue(find(app, "favoritt-1").waitForExistence(timeout: 10), "stjernen ble ikke gul")
        wait(1)
        shot("03-favoritt")
    }

    /// «Dine kategorier»: stjernen ved Sport (i arket på iPhone, i sidemenyen på iPad), så velg Sport.
    func test04DineKategorier() {
        let app = launch("tv")
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30))
        if !isPad {
            find(app, "kategori-velger").tap()
            XCTAssertTrue(find(app, "stjerne-2").waitForExistence(timeout: 10), "kategoriarket kom ikke")
            wait(1)
            shot("04-kategorier")
        }
        find(app, "stjerne-2").tap()
        XCTAssertTrue(find(app, "seksjon-dine").waitForExistence(timeout: 10), "«Dine kategorier» kom ikke")
        wait(1)
        shot("05-dine-kategorier")
        find(app, "hylle-2").tap()
        XCTAssertTrue(find(app, "kanal-11").waitForExistence(timeout: 10), "Sport ble ikke vist")
        wait(1)
        XCTAssertFalse(find(app, "kanal-1").exists, "viser mer enn Sport")
        shot("06-sport")
    }

    func test05Guide() {
        let app = launch("guide")
        XCTAssertTrue(find(app, "guide").waitForExistence(timeout: 30))
        wait(5)
        shot("07-guide")
    }

    func test06Search() {
        let app = launch("search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30), "søkefeltet mangler")
        field.tap()
        field.typeText("sport")
        XCTAssertTrue(find(app, "kanal-11").waitForExistence(timeout: 15), "fant ikke Nordlys Sport 1")
        XCTAssertFalse(find(app, "kanal-1").exists)
        wait(1)
        shot("08-sok")
    }

    func test07Player() {
        let app = launch("player")
        XCTAssertTrue(find(app, "spiller").waitForExistence(timeout: 30), "spilleren kom ikke")
        wait(10)
        shot("09-spiller")
        find(app, "neste-kanal").tap()
        wait(3)
        find(app, "lukk-spiller").tap()
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 10), "kom ikke tilbake fra spilleren")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func test08PlayerError() {
        let app = launch("player-error")
        XCTAssertTrue(find(app, "spiller-feil").waitForExistence(timeout: 60), "feilen kom ikke")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch.exists,
                      "HTTP-koden står ikke i feilen")
        wait(1)
        shot("10-spiller-feil")
    }

    func test09Settings() {
        let app = launch("settings")
        XCTAssertTrue(find(app, "innstillinger").waitForExistence(timeout: 30))
        wait(2)
        shot("11-innstillinger")
    }

    func test10English() {
        let app = launch("tv", language: "en")
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'All channels'")).firstMatch.exists)
        wait(2)
        shot("12-english")
    }
}
