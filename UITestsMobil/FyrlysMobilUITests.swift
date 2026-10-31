import UIKit
import XCTest

/// Starter appen i iPhone- og iPad-simulatoren mot den falske leverandøren (tools/fake_xtream.py), sjekker sidene og
/// tar skjermbilder (de legges i grenen «skjermbilder-mobil» av bygget på GitHub, med «iphone» eller «ipad» i navnet).
/// iPhone har oppsettet fra Fyrlys-nettsiden (topplinje, kategorifliser, egen side per kategori); iPad har sidemenyen.
final class FyrlysMobilUITests: XCTestCase {
    var server: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_SERVER"] ?? "http://127.0.0.1:8899" }
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [theme]: mørk som standard, så skjermbildene ikke avhenger av modusen i simulatoren.
    @discardableResult
    func launch(_ screen: String, language: String = "no", theme: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FYRLYS_TEST_SERVER": server,
            "FYRLYS_TEST_SCREEN": screen,
            "FYRLYS_TEST_LANG": language,
            "FYRLYS_TEST_THEME": theme,
        ]
        app.launch()
        return app
    }

    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Knappen [id] med teksten [label] (for å se at en stjerne har skiftet).
    func button(_ app: XCUIApplication, _ id: String, label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", id, label)).firstMatch
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

    /// Venter til [element] er borte.
    func gone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func test01Login() {
        let app = launch("login")
        XCTAssertTrue(find(app, "innlogging").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["logg-inn"].exists)
        wait(1)
        shot("01-innlogging")
    }

    /// iPhone: søket og kategoriflisene, så «Alle kanaler». iPad: sidemenyen og kortene.
    func test02TV() {
        let app = launch("tv")
        if isPad {
            XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30), "kanalkortene kom ikke")
            XCTAssertTrue(find(app, "hylle-2").exists, "kategorien Sport mangler i sidemenyen")
            XCTAssertFalse(find(app, "hylle-6").exists, "tomme kategorier skal ikke vises")
            wait(3) // logoer og programinfo
            shot("02-tv")
            return
        }
        XCTAssertTrue(find(app, "hylle-alle").waitForExistence(timeout: 30), "kategoriflisene kom ikke")
        XCTAssertTrue(find(app, "hylle-2").exists, "flisen for Sport mangler")
        XCTAssertFalse(find(app, "hylle-6").exists, "tomme kategorier skal ikke vises")
        XCTAssertTrue(find(app, "sok").exists, "søkefeltet mangler")
        XCTAssertTrue(find(app, "konto").exists, "Konto mangler i topplinja")
        wait(2)
        shot("02-tv")
        find(app, "hylle-alle").tap()
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 10), "Alle kanaler ble ikke vist")
        wait(3)
        shot("14-alle")
    }

    /// Trykk på stjernen på et kort: kanalen blir favoritt (og står under «Nå på favorittene» på iPhone).
    func test03Favorite() {
        let app = launch(isPad ? "tv" : "all")
        let star = find(app, "stjerne-kanal-1")
        XCTAssertTrue(star.waitForExistence(timeout: 30), "stjernen på kortet mangler")
        XCTAssertEqual(star.label, "Legg til i favoritter")
        star.tap()
        XCTAssertTrue(button(app, "stjerne-kanal-1", label: "Fjern fra favoritter").waitForExistence(timeout: 10),
                      "kanalen ble ikke favoritt")
        wait(1)
        shot("03-favoritt")
        if !isPad {
            find(app, "tilbake").tap()
            XCTAssertTrue(find(app, "seksjon-favoritter").waitForExistence(timeout: 10), "«Nå på favorittene» kom ikke")
            wait(2)
            shot("15-hjem-favoritter")
        }
    }

    /// «Dine kategorier»: iPhone: stjernen på siden for Sport, arket med kategoriene, og Sport foran Nyheter blant
    /// flisene. iPad: stjernen ved Sport i sidemenyen.
    func test04DineKategorier() {
        let app = launch("tv")
        if isPad {
            XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30))
            find(app, "stjerne-2").tap()
            XCTAssertTrue(find(app, "seksjon-dine").waitForExistence(timeout: 10), "«Dine kategorier» kom ikke")
            wait(1)
            shot("05-dine-kategorier")
            find(app, "hylle-2").tap()
            XCTAssertTrue(find(app, "kanal-11").waitForExistence(timeout: 10), "Sport ble ikke vist")
            wait(1)
            XCTAssertFalse(find(app, "kanal-1").exists, "viser mer enn Sport")
            shot("06-sport")
            return
        }
        XCTAssertTrue(find(app, "hylle-2").waitForExistence(timeout: 30), "flisen for Sport mangler")
        find(app, "hylle-2").tap()
        XCTAssertTrue(find(app, "kanal-11").waitForExistence(timeout: 10), "Sport ble ikke vist")
        XCTAssertFalse(find(app, "kanal-1").exists, "viser mer enn Sport")
        let pin = find(app, "kategori-stjerne")
        XCTAssertTrue(pin.exists, "stjernen for kategorien mangler")
        pin.tap()
        XCTAssertTrue(button(app, "kategori-stjerne", label: "Fjern fra toppen").waitForExistence(timeout: 5),
                      "Sport ble ikke lagt øverst")
        wait(2)
        shot("06-sport")
        find(app, "kategori-velger").tap()
        XCTAssertTrue(find(app, "seksjon-dine").waitForExistence(timeout: 10), "«Dine kategorier» mangler i arket")
        wait(1)
        shot("04-kategorier")
        app.buttons["Ferdig"].tap()
        XCTAssertTrue(find(app, "tilbake").waitForExistence(timeout: 5))
        find(app, "tilbake").tap()
        let sport = find(app, "hylle-2"), news = find(app, "hylle-1")
        XCTAssertTrue(news.waitForExistence(timeout: 10), "flisen for Nyheter mangler")
        let first = sport.frame.minY < news.frame.minY - 1
            || (abs(sport.frame.minY - news.frame.minY) <= 1 && sport.frame.minX < news.frame.minX)
        XCTAssertTrue(first, "Sport står ikke foran Nyheter")
        wait(1)
        shot("05-dine-kategorier")
    }

    func test05Guide() {
        let app = launch("guide")
        XCTAssertTrue(find(app, "guide").waitForExistence(timeout: 30))
        XCTAssertTrue(find(app, "guide-velger").waitForExistence(timeout: 10), "valget i guiden mangler")
        wait(5)
        shot("07-guide")
    }

    func test06Search() {
        let app = launch("search")
        let field = isPad ? app.searchFields.firstMatch : find(app, "sok")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "søkefeltet mangler")
        field.tap()
        field.typeText("sport")
        XCTAssertTrue(find(app, "kanal-11").waitForExistence(timeout: 15), "fant ikke Nordlys Sport 1")
        XCTAssertFalse(find(app, "kanal-1").exists)
        wait(1)
        shot("08-sok")
    }

    /// Spilleren: neste kanal, så dra bildet ned for å lukke.
    func test07Player() {
        let app = launch("player")
        XCTAssertTrue(find(app, "spiller").waitForExistence(timeout: 30), "spilleren kom ikke")
        wait(10)
        shot("09-spiller")
        find(app, "neste-kanal").tap()
        wait(3)
        // bildet står øverst (stående iPhone og iPad) eller til venstre (iPad på tvers): dra det ned
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)))
        XCTAssertTrue(gone(find(app, "spiller"), timeout: 10), "spilleren ble ikke lukket da bildet ble dratt ned")
        // iPad: kortene; iPhone: «Sist sett» på forsiden
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 10), "kom ikke tilbake fra spilleren")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Kanalen som svarer 404: feilen med HTTP-koden, så lukk med knappen.
    func test08PlayerError() {
        let app = launch("player-error")
        XCTAssertTrue(find(app, "spiller-feil").waitForExistence(timeout: 60), "feilen kom ikke")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch.exists,
                      "HTTP-koden står ikke i feilen")
        wait(1)
        shot("10-spiller-feil")
        find(app, "lukk-spiller").tap()
        XCTAssertTrue(gone(find(app, "spiller"), timeout: 10), "spilleren ble ikke lukket med knappen")
    }

    /// iPad: Innstillinger-fanen; iPhone: Konto i topplinja.
    func test09Settings() {
        let app = launch("settings")
        XCTAssertTrue(find(app, "innstillinger").waitForExistence(timeout: 30))
        wait(2)
        shot("11-innstillinger")
    }

    func test10English() {
        let app = launch("tv", language: "en")
        XCTAssertTrue(find(app, isPad ? "kanal-1" : "hylle-alle").waitForExistence(timeout: 30))
        let all = NSPredicate(format: "label CONTAINS 'All channels'")
        XCTAssertTrue(app.buttons.matching(all).firstMatch.exists || app.buttons.containing(all).firstMatch.exists)
        wait(2)
        shot("12-english")
    }

    /// Rull lista: kortene skal forsvinne under kategorivalget (iPhone) eller kanten øverst (iPad), ikke opp under
    /// klokka (skjermbildet viser det).
    func test11Rulling() {
        let app = launch(isPad ? "tv" : "all")
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30))
        wait(2)
        app.swipeUp(velocity: .slow)
        wait(2)
        if !isPad {
            XCTAssertTrue(find(app, "kategori-velger").isHittable, "kategorivalget rullet bort")
        }
        shot("13-rullet")
    }

    /// Lys modus («Nordisk lys»): sola i topplinja på iPhone, valgt i innstillingene på iPad.
    func test12Lys() {
        if isPad {
            let app = launch("tv", theme: "light")
            XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30))
            wait(3)
            shot("16-lys")
            return
        }
        let app = launch("tv")
        XCTAssertTrue(find(app, "hylle-alle").waitForExistence(timeout: 30))
        find(app, "tema").tap()
        wait(2)
        shot("16-lys")
        find(app, "hylle-alle").tap()
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 10))
        wait(3)
        shot("17-lys-alle")
    }
}
