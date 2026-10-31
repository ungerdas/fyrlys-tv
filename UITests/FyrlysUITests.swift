import XCTest

/// Starter appen i Apple TV-simulatoren mot den falske leverandøren (tools/fake_xtream.py), sjekker skjermene og tar
/// skjermbilder (de legges i grenen «skjermbilder» av bygget på GitHub).
final class FyrlysUITests: XCTestCase {
    var server: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_SERVER"] ?? "http://127.0.0.1:8899" }
    let remote = XCUIRemote.shared

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

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
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
        XCTAssertTrue(find(app, "hylle-2").exists, "kategorien Sport mangler")
        XCTAssertFalse(find(app, "hylle-6").exists, "tomme kategorier skal ikke vises")
        wait(4) // logoer og programinfo
        shot("02-tv")
    }

    func test03Favorite() {
        let app = launch("tv")
        let card = find(app, "kanal-1")
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        // fokus starter i fanene øverst: ned i sidemenyen, så til høyre til det første kortet
        remote.press(.down)
        wait(1)
        for _ in 0..<3 where !card.hasFocus {
            remote.press(.right)
            wait(1)
        }
        XCTAssertTrue(card.hasFocus, "fikk ikke fokus på det første kortet")
        remote.press(.select, forDuration: 2)
        wait(2)
        shot("03-hurtigmeny")
        // menyvalgene er ikke alltid knapper i elementtreet
        let add = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Legg til i favoritter")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8), "hurtigmenyen kom ikke")
        remote.press(.select)
        XCTAssertTrue(find(app, "favoritt-1").waitForExistence(timeout: 10), "stjernen kom ikke")
        wait(1)
        shot("04-favoritt")
    }

    func test04Guide() {
        let app = launch("guide")
        XCTAssertTrue(find(app, "guide").waitForExistence(timeout: 30))
        wait(5)
        shot("05-guide")
        remote.press(.down)
        wait(1)
        remote.press(.right)
        wait(1)
        remote.press(.right)
        wait(1)
        shot("06-guide-fokus")
    }

    func test05Search() {
        let app = launch("search")
        wait(3)
        // fra fanene ned til tastaturet
        remote.press(.down)
        wait(2)
        shot("07-sok")
        app.typeText("sport")
        XCTAssertTrue(find(app, "kanal-11").waitForExistence(timeout: 15), "fant ikke Nordlys Sport 1")
        XCTAssertFalse(find(app, "kanal-1").exists)
        wait(2)
        shot("08-sok-treff")
    }

    func test06Player() {
        let app = launch("player")
        wait(12)
        shot("09-spiller")
        remote.press(.select) // pause: kontrollene vises
        wait(2)
        shot("10-spiller-kontroller")
        remote.press(.select)
        wait(1)
        // Menyknappen lukker spilleren (først skjules kontrollene)
        for _ in 0..<3 where !find(app, "kanal-1").exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 10), "kom ikke tilbake fra spilleren")
        XCTAssertEqual(app.state, .runningForeground)
        // «Sist sett» har kanalen nå
        XCTAssertTrue(find(app, "hylle-sist").exists, "«Sist sett» mangler")
    }

    func test07PlayerError() {
        let app = launch("player-error")
        XCTAssertTrue(find(app, "spiller-feil").waitForExistence(timeout: 60), "feilen kom ikke")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch.exists,
                      "HTTP-koden står ikke i feilen")
        wait(1)
        shot("11-spiller-feil")
    }

    func test08Settings() {
        let app = launch("settings")
        XCTAssertTrue(find(app, "innstillinger").waitForExistence(timeout: 30))
        wait(3)
        shot("12-innstillinger")
    }

    func test09English() {
        let app = launch("tv", language: "en")
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'All channels'")).firstMatch.exists)
        wait(3)
        shot("13-english")
    }
}
