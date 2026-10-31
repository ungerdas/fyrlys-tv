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
    func launch(_ screen: String, language: String = "no", server: String? = nil, keep: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FYRLYS_TEST_SERVER": server ?? self.server,
            "FYRLYS_TEST_SCREEN": screen,
            "FYRLYS_TEST_LANG": language,
        ]
        // lista fra sist og innstillingene står (ellers tømmes de ved start)
        if keep { app.launchEnvironment["FYRLYS_TEST_KEEP"] = "1" }
        app.launch()
        return app
    }

    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Flytter fokus til [target] (et kanalkort, «kanal-…», eller en linje i sidemenyen, «hylle-…»), uansett hvor
    /// fokus står: fra fanelinja ned, mellom sidemenyen og rutenettet, og så opp, ned eller til siden mot målet.
    @discardableResult
    func focus(_ app: XCUIApplication, _ target: XCUIElement, tries: Int = 16) -> Bool {
        let wantsCard = target.identifier.hasPrefix("kanal-")
        for _ in 0..<tries {
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let id = focused.exists ? focused.identifier : ""
            let onCard = id.hasPrefix("kanal-")
            let inSidebar = id.hasPrefix("hylle-")
            if (wantsCard && onCard) || (!wantsCard && inSidebar) {
                let here = focused.frame
                let goal = target.frame
                if goal.midY < here.minY - 4 {
                    remote.press(.up)
                } else if goal.midY > here.maxY + 4 {
                    remote.press(.down)
                } else {
                    remote.press(goal.midX < here.midX ? .left : .right)
                }
            } else if wantsCard {
                remote.press(inSidebar ? .right : .down)
            } else {
                remote.press(onCard ? .left : .down)
            }
            wait(0.8)
        }
        return target.hasFocus
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
        // fokus starter i fanene øverst
        XCTAssertTrue(focus(app, card), "fikk ikke fokus på det første kortet")
        wait(1)
        shot("03-fokus")
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

    /// «Dine kategorier»: hold inne på Sport i sidemenyen, «Legg øverst»; da står den øverst med stjerne, og «Alle
    /// kanaler» begynner med kanalene i Sport.
    func test10DineKategorier() {
        let app = launch("tv")
        let sport = find(app, "hylle-2")
        XCTAssertTrue(sport.waitForExistence(timeout: 30))
        XCTAssertTrue(find(app, "seksjon-kategorier").exists, "«Kategorier» mangler i sidemenyen")
        XCTAssertTrue(focus(app, sport), "fikk ikke fokus på Sport i sidemenyen")
        remote.press(.select, forDuration: 2)
        wait(2)
        shot("14-kategori-meny")
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Legg øverst")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 8), "menyen kom ikke")
        remote.press(.select)
        XCTAssertTrue(find(app, "seksjon-dine").waitForExistence(timeout: 10), "«Dine kategorier» kom ikke")
        XCTAssertTrue(find(app, "lagt-overst").exists, "stjernen ved kategorien mangler")
        let sportFirst = find(app, "kanal-11")
        let news = find(app, "kanal-1")
        XCTAssertTrue(sportFirst.waitForExistence(timeout: 10) && news.exists)
        XCTAssertLessThan(sportFirst.frame.minY, news.frame.minY, "«Alle kanaler» begynner ikke med Sport")
        wait(1)
        shot("15-dine-kategorier")
    }

    /// Den store, oppdiktede lista (25 000 kanaler i 450 kategorier fra tools/fake_xtream.py --kanaler): hvor lang tid
    /// det tar før kortene kommer, uten og med lista fra sist, og å bla. Tidene står i loggen («YTELSE:») og som
    /// merknad på bygget.
    func test11StorListe() throws {
        guard let big = ProcessInfo.processInfo.environment["FYRLYS_TEST_SERVER_STOR"] else {
            throw XCTSkip("ingen stor falsk leverandør")
        }
        var start = Date()
        var app = launch("tv", server: big)
        let first = find(app, "kanal-1000")
        XCTAssertTrue(first.waitForExistence(timeout: 120), "kortene kom ikke")
        let cold = Date().timeIntervalSince(start)
        wait(4)
        shot("16-stor-liste")

        XCTAssertTrue(focus(app, first), "fikk ikke fokus på det første kortet")
        start = Date()
        for _ in 0..<12 { remote.press(.down) }
        for _ in 0..<12 { remote.press(.up) }
        let grid = Date().timeIntervalSince(start)

        remote.press(.left)
        start = Date()
        for _ in 0..<20 { remote.press(.down) }
        let sidebar = Date().timeIntervalSince(start)
        wait(1)
        shot("17-stor-liste-sidemeny")
        app.terminate()

        // igjen, med lista fra sist på disk
        start = Date()
        app = launch("tv", server: big, keep: true)
        XCTAssertTrue(find(app, "kanal-1000").waitForExistence(timeout: 60), "kortene kom ikke med lista fra sist")
        let warm = Date().timeIntervalSince(start)
        print(String(format: "YTELSE: 25 000 kanaler i simulatoren: første kort etter %.1f s uten lista fra sist og "
                     + "%.1f s med; 24 steg i rutenettet %.1f s; 20 steg i sidemenyen %.1f s", cold, warm, grid, sidebar))
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
