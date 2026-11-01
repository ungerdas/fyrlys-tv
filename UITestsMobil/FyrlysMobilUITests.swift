import UIKit
import XCTest

/// Starter appen i iPhone- og iPad-simulatoren mot den falske leverandøren (tools/fake_xtream.py), sjekker sidene og
/// tar skjermbilder (de legges i grenen «skjermbilder-mobil» av bygget på GitHub, med «iphone» eller «ipad» i navnet).
/// iPhone har oppsettet fra Fyrlys-nettsiden (topplinje, kategorifliser, egen side per kategori); iPad har sidemenyen.
final class FyrlysMobilUITests: XCTestCase {
    var server: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_SERVER"] ?? "http://127.0.0.1:8899" }
    /// den falske Plex (tools/fake_plex.py)
    var plex: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_PLEX"] ?? "http://127.0.0.1:8897" }
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// [theme]: mørk som standard, så skjermbildene ikke avhenger av modusen i simulatoren.
    @discardableResult
    func launch(_ screen: String, language: String = "no", theme: String = "dark",
                extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FYRLYS_TEST_SERVER": server,
            "FYRLYS_TEST_SCREEN": screen,
            "FYRLYS_TEST_LANG": language,
            "FYRLYS_TEST_THEME": theme,
            "FYRLYS_TEST_PLEX": plex,
        ].merging(extra) { _, new in new }
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

    /// Trykker på [id] og venter på [target]; trykker én gang til hvis siden ikke kom (et trykk tas av og til ikke i
    /// simulatoren).
    @discardableResult
    func openPage(_ app: XCUIApplication, _ id: String, then target: String, timeout: TimeInterval = 10) -> Bool {
        find(app, id).tap()
        if find(app, target).waitForExistence(timeout: timeout / 2) { return true }
        if find(app, id).exists { find(app, id).tap() }
        return find(app, target).waitForExistence(timeout: timeout)
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
        XCTAssertTrue(openPage(app, "hylle-alle", then: "kanal-1"), "Alle kanaler ble ikke vist")
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
        XCTAssertTrue(openPage(app, "hylle-2", then: "kanal-11"), "Sport ble ikke vist")
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
    /// Filmer: plakatene, siden for en film og spilleren i et ark.
    func test13Filmer() {
        let app = launch("movies")
        XCTAssertTrue(find(app, "vod-501").waitForExistence(timeout: 30), "filmene kom ikke")
        wait(2)
        shot("18-filmer")
        XCTAssertTrue(openPage(app, "vod-501", then: "spill-av", timeout: 15), "siden for filmen kom ikke")
        wait(2)
        shot("19-film")
        find(app, "spill-av").tap()
        XCTAssertTrue(find(app, "vod-spiller").waitForExistence(timeout: 20), "spilleren kom ikke")
        wait(6)
        shot("20-film-spiller")
    }

    /// Serier: siden for en serie med sesongene og episodene.
    func test14Serier() {
        let app = launch("series")
        XCTAssertTrue(find(app, "vod-9001").waitForExistence(timeout: 30), "seriene kom ikke")
        XCTAssertTrue(openPage(app, "vod-9001", then: "episode-900111", timeout: 15), "episodene kom ikke")
        XCTAssertTrue(find(app, "sesong-2").exists, "sesong 2 mangler")
        let next = find(app, "fortsett-serie")
        XCTAssertTrue(next.exists, "knappen til episoden du skal se, mangler")
        XCTAssertTrue(next.label.contains("S1 E1"), "første episode skulle stå på knappen: \(next.label)")
        wait(2)
        shot("21-serie")
    }

    /// TV-arkivet for en kanal: dagene og programmene.
    func test15Arkiv() {
        let app = launch("archive")
        XCTAssertTrue(find(app, "arkiv").waitForExistence(timeout: 30), "arkivet kom ikke")
        let program = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'arkiv-'")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 15), "programmene i arkivet kom ikke")
        wait(2)
        shot("22-arkiv")
    }

    /// En film i mkv spilles med VLC: tiden går, lydsporet og undertekstene kan velges, og krysset lukker.
    func test17Mkv() {
        let app = launch("mkv")
        XCTAssertTrue(find(app, "vod-spiller").waitForExistence(timeout: 30), "spilleren kom ikke")
        let time = find(app, "vod-tid")
        XCTAssertTrue(time.waitForExistence(timeout: 20), "kontrollene til VLC kom ikke")
        var played = false
        for _ in 0..<40 {
            if time.exists, time.label != "0:00" {
                played = true
                break
            }
            wait(1)
        }
        XCTAssertTrue(played, "tiden gikk ikke (VLC spilte ikke filmen)")
        XCTAssertTrue(find(app, "vod-lyd").exists, "valget av lydspor mangler")
        XCTAssertTrue(find(app, "vod-tekst").exists, "valget av undertekster mangler")
        wait(2)
        shot("24-mkv")
        // et trykk på bildet (ikke på knappene) skjuler kontrollene: undertekstene alene, i Apple sin stil
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
        wait(2)
        shot("24-mkv-tekst")
        if !find(app, "lukk-vod").exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
        }
        XCTAssertTrue(find(app, "lukk-vod").waitForExistence(timeout: 5), "kontrollene kom ikke tilbake")
        // iPhone: spilleren står liggende; knappen snur den til stående
        if !isPad {
            let rotate = find(app, "snu-skjermen")
            XCTAssertTrue(rotate.exists, "knappen som snur skjermen, mangler")
            rotate.tap()
            wait(3)
            shot("24-mkv-staende")
        }
        find(app, "lukk-vod").tap()
        let player = find(app, "vod-spiller")
        for _ in 0..<10 where player.exists { wait(1) }
        XCTAssertFalse(player.exists, "krysset lukket ikke spilleren")
    }

    /// Plex (koblet til fra før): «Hjem» med radene og «Fortsett å se» fra Plex, og siden for en film med «Fortsett».
    func test18Plex() {
        let app = launch("plex")
        XCTAssertTrue(find(app, "rad-1001").waitForExistence(timeout: 40), "radene fra Plex kom ikke")
        XCTAssertTrue(find(app, "fortsett-1001").exists, "«Fortsett å se» fra Plex mangler")
        wait(2)
        shot("25-plex-hjem")
        XCTAssertTrue(openPage(app, "rad-1001", then: "spill-av", timeout: 15), "siden for filmen kom ikke")
        wait(2)
        XCTAssertTrue(find(app, "spill-av").label.contains("0:12"), "«Fortsett» der Plex sier du slapp mangler")
        shot("26-plex-film")
    }

    /// Serier med Plex: radene med nye episoder, og en episode spilles med en gang.
    func test20PlexSerier() {
        let app = launch("plex-series")
        XCTAssertTrue(find(app, "fortsett-2001").waitForExistence(timeout: 40), "«Fortsett å se» fra Plex kom ikke")
        let episode = find(app, "rad-e2102")
        if !episode.waitForExistence(timeout: 10) { shot("29-plex-serier-mangler") }
        XCTAssertTrue(episode.waitForExistence(timeout: 20), "radene med episoder fra Plex kom ikke")
        wait(2)
        shot("29-plex-serier")
        episode.tap()
        let time = find(app, "vod-tid")
        XCTAssertTrue(time.waitForExistence(timeout: 20), "episoden startet ikke")
        let first = time.label
        var played = false
        for _ in 0..<40 {
            if time.exists, time.label != first, time.label != "0:00" {
                played = true
                break
            }
            wait(1)
        }
        XCTAssertTrue(played, "tiden gikk ikke (episoden fra Plex spilte ikke)")
        shot("30-plex-episode")
    }

    /// Egne strømmer (iPhone: arket fra Konto, iPad: Innstillinger): kanalene kjennes igjen ut fra navnet.
    func test21EgneStrommer() {
        let streams = "Fjordkanalen = http://127.0.0.1:8899/egen/finnes-ikke.m3u8\n"
            + "http://127.0.0.1:8899/egen/kystnytt24/muxed.m3u8\nhttp://127.0.0.1:8899/egen/nrk1/muxed.m3u8"
        let app = launch("strommer", extra: ["FYRLYS_TEST_STREAMS": streams])
        let matched = find(app, "egen-strom-fjordkanalen")
        // lista i Innstillinger på iPad lager radene først når de vises: rull fram til dem
        XCTAssertTrue(find(app, "nrk-direkte").waitForExistence(timeout: 30), "innstillingene kom ikke")
        for _ in 0..<8 where !(matched.exists && matched.isHittable) {
            app.swipeUp()
            wait(1.5)
        }
        XCTAssertTrue(matched.waitForExistence(timeout: 10), "de egne strømmene vises ikke")
        for _ in 0..<10 where !matched.label.contains("Fjordkanalen") { wait(1) }
        XCTAssertTrue(matched.label.contains("Fjordkanalen"), "kanalen ble ikke funnet: \(matched.label)")
        XCTAssertTrue(find(app, "egen-strom-kystnytt24").label.contains("Kystnytt 24"), "kanalen fra adressen mangler")
        wait(1)
        shot("31-egne-strommer")
    }

    /// Koble til Plex (iPhone: arket fra Konto, iPad: Innstillinger): koden vises, og så kobles det til serveren.
    func test19PlexKobling() {
        let app = launch("plex-link")
        let connect = find(app, "koble-til-plex")
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "«Koble til Plex» mangler")
        connect.tap()
        let code = find(app, "plex-kode")
        XCTAssertTrue(code.waitForExistence(timeout: 15), "koden kom ikke")
        XCTAssertEqual(code.label, "FYRL")
        shot("27-plex-kode")
        XCTAssertTrue(find(app, "plex-tilkoblet").waitForExistence(timeout: 40), "ble ikke koblet til Plex")
        wait(1)
        shot("28-plex-tilkoblet")
    }

    /// «Fra start» i spilleren (kanal 1 har TV-arkiv): direktesendingen lukkes, og programmet spilles fra arkivet.
    func test16FraStart() {
        let app = launch("player")
        let button = find(app, "fra-start-live")
        XCTAssertTrue(button.waitForExistence(timeout: 30), "«Fra start» mangler i spilleren")
        button.tap()
        XCTAssertTrue(find(app, "vod-spiller").waitForExistence(timeout: 20), "programmet fra start kom ikke")
        wait(5)
        shot("23-fra-start")
    }

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
        XCTAssertTrue(openPage(app, "hylle-alle", then: "kanal-1"), "Alle kanaler ble ikke vist")
        wait(3)
        shot("17-lys-alle")
    }
}
