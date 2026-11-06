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
        // iPhone: stående (en test som snur telefonen og feiler, skal ikke ta de neste med seg)
        if !isPad { XCUIDevice.shared.orientation = .portrait }
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

    /// Id-en appen gir en kanal fra en M3U-liste (`stableHash` i kjernen: FNV-1a, 64 bit).
    func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
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

    /// Tilbake fra en side i navigasjonen (knappen oppe til venstre, ellers et sveip fra kanten), til [target].
    func goBack(_ app: XCUIApplication, to target: String) -> Bool {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        if find(app, target).waitForExistence(timeout: 5) { return true }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        return find(app, target).waitForExistence(timeout: 5)
    }

    /// Skriver det som er på skjermen (typen, id-en og teksten til elementene) i loggen («SKJERM:», kommer med i
    /// utdraget og merknaden når bygget feiler), sammen med et skjermbilde [shotName].
    func dumpScreen(_ app: XCUIApplication, _ why: String, shotName: String) {
        shot(shotName)
        print("SKJERM: \(why)")
        for line in app.debugDescription.split(separator: "\n") where line.contains("identifier:") || line.contains("label:") {
            let text = line.trimmingCharacters(in: .whitespaces)
            let kind = text.split(separator: ",").first.map(String.init) ?? ""
            let detail = text.range(of: "identifier:").map { String(text[$0.lowerBound...]) }
                ?? text.range(of: "label:").map { String(text[$0.lowerBound...]) } ?? ""
            print("SKJERM: \(kind) \(detail)".prefix(300))
        }
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
        // feilen kommer med en gang, forklaringen (HTTP-koden) like etter
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch
                        .waitForExistence(timeout: 15), "HTTP-koden står ikke i feilen")
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

    /// Serier: Hjem med kategorien som rad, siden for en serie med sesongene og episodene, stjernen (serien står så
    /// under «Favoritter» på Hjem) og søket.
    func test14Serier() {
        let app = launch("series")
        XCTAssertTrue(find(app, "vod-9001").waitForExistence(timeout: 30), "seriene kom ikke")
        XCTAssertTrue(find(app, "vod-hjem").exists, "Hjem står ikke først")
        XCTAssertTrue(openPage(app, "vod-9001", then: "episode-900111", timeout: 15), "episodene kom ikke")
        XCTAssertTrue(find(app, "sesong-2").exists, "sesong 2 mangler")
        let next = find(app, "fortsett-serie")
        XCTAssertTrue(next.exists, "knappen til episoden du skal se, mangler")
        XCTAssertTrue(next.label.contains("S1 E1"), "første episode skulle stå på knappen: \(next.label)")
        wait(2)
        shot("21-serie")
        // stjernen oppe til høyre (finnes den ikke på id-en i verktøylinja, så på teksten)
        var star = find(app, "vod-favoritt")
        if !star.waitForExistence(timeout: 5) { star = app.buttons["Legg til i favoritter"] }
        XCTAssertTrue(star.exists, "stjernen mangler")
        star.tap()
        wait(1)
        XCTAssertTrue(goBack(app, to: "vod-hjem"), "kom ikke tilbake til Hjem")
        let favorite = find(app, "vodfav-9001")
        if !favorite.waitForExistence(timeout: 10) {
            dumpScreen(app, "serien står ikke under «Favoritter»", shotName: "32-favoritt-mangler")
        }
        XCTAssertTrue(favorite.exists, "serien står ikke under «Favoritter» på Hjem")
        wait(1)
        shot("32-serier-hjem")
        let search = find(app, "vod-sok")
        XCTAssertTrue(search.exists, "søket mangler")
        search.tap()
        search.typeText("lose")
        XCTAssertTrue(find(app, "sok-9001").waitForExistence(timeout: 15), "søket fant ikke serien")
        wait(1)
        shot("33-sok-serier")
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
        // pause med en gang: testfilmen er bare 30 sekunder, og når den er ferdig, lukkes spilleren (i bygg 42 og 48
        // skjedde det midt i testen). Undertekstene står nesten hele tiden, også i pause.
        wait(2)
        let pause = find(app, "vod-pause")
        if pause.exists { pause.tap() }
        wait(1)
        shot("24-mkv")
        // et trykk på bildet (ikke på knappene) skjuler kontrollene: undertekstene alene, i Apple sin stil
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
        wait(2)
        shot("24-mkv-tekst")
        if !find(app, "lukk-vod").exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
        }
        XCTAssertTrue(find(app, "lukk-vod").waitForExistence(timeout: 5), "kontrollene kom ikke tilbake")
        // iPhone: spilleren står liggende; knappen snur den til stående. På de store iPhonene (simulatoren er en Pro
        // Max) byttet hele oppsettet på tvers i 0.1.19–0.1.21, så arket med filmen ble borte med en gang det la seg ned
        if !isPad {
            let rotate = find(app, "snu-skjermen")
            XCTAssertTrue(rotate.exists, "knappen som snur skjermen, mangler")
            rotate.tap()
            wait(3)
            shot("24-mkv-staende")
            XCTAssertTrue(find(app, "vod-spiller").exists, "spilleren ble borte da den ble snudd til stående")
            // telefonen snus for hånd: filmen blir der
            XCUIDevice.shared.orientation = .landscapeLeft
            wait(3)
            XCTAssertTrue(find(app, "vod-spiller").exists, "spilleren ble borte da telefonen ble lagt ned")
            XCTAssertTrue(find(app, "lukk-vod").exists || find(app, "vod-tid").exists, "kontrollene ble borte")
            shot("24-mkv-snudd")
            XCUIDevice.shared.orientation = .portrait
            wait(2)
            XCTAssertTrue(find(app, "vod-spiller").exists, "spilleren ble borte da telefonen ble reist opp")
        }
        find(app, "lukk-vod").tap()
        let player = find(app, "vod-spiller")
        for _ in 0..<10 where player.exists { wait(1) }
        XCTAssertFalse(player.exists, "krysset lukket ikke spilleren")
    }

    /// Plex-fanen (koblet til fra før): «Hjem» med filmer og serier sammen (radene og «Fortsett å se» fra Plex),
    /// bibliotekene (sidemenyen på iPad, knappene øverst på iPhone), og siden for en film med «Fortsett».
    func test18Plex() {
        let app = launch("plex")
        if !find(app, "rad-1001").waitForExistence(timeout: 40) {
            dumpScreen(app, "radene fra Plex kom ikke", shotName: "25-plex-mangler")
        }
        XCTAssertTrue(find(app, "rad-1001").exists, "radene fra Plex kom ikke")
        XCTAssertTrue(find(app, "fortsett-1001").exists, "filmen mangler i «Fortsett å se»")
        XCTAssertTrue(find(app, "fortsett-2001").exists, "serien mangler i «Fortsett å se»")
        XCTAssertTrue(find(app, "vodkat-1").exists && find(app, "vodkat-2").exists, "bibliotekene mangler")
        if !isPad {
            // Filmer og Serier (fra leverandøren) og Plex i fanelinja
            for tab in ["Filmer", "Serier", "Plex"] {
                XCTAssertTrue(app.tabBars.buttons[tab].exists, "fanen «\(tab)» mangler")
            }
        }
        wait(2)
        shot("25-plex-hjem")
        XCTAssertTrue(openPage(app, "rad-1001", then: "spill-av", timeout: 15), "siden for filmen kom ikke")
        wait(2)
        XCTAssertTrue(find(app, "spill-av").label.contains("0:12"), "«Fortsett» der Plex sier du slapp mangler")
        // logoen fra Plex i stedet for tittelen, og de medvirkende med bilde
        XCTAssertTrue(find(app, "vod-logo").exists, "logoen til filmen mangler")
        XCTAssertTrue(find(app, "medvirkende").exists, "«Medvirkende» mangler")
        shot("26-plex-film")
        // «Se alle» for «Nylig lagt til»: hele raden fra Plex (med filmen som ikke står i raden)
        XCTAssertTrue(goBack(app, to: "vod-hjem"), "kom ikke tilbake til Hjem")
        XCTAssertTrue(openPage(app, "se-alle-home.recentlyAdded", then: "alle-1003", timeout: 15),
                      "«Se alle» viste ikke hele raden")
        wait(1)
        shot("34-plex-se-alle")
    }

    /// Serier med Plex: radene med nye episoder, og en episode spilles med en gang.
    func test20PlexSerier() {
        let app = launch("plex-series")
        if !find(app, "fortsett-2001").waitForExistence(timeout: 40) {
            dumpScreen(app, "«Fortsett å se» fra Plex kom ikke", shotName: "29-plex-fortsett-mangler")
        }
        XCTAssertTrue(find(app, "fortsett-2001").exists, "«Fortsett å se» fra Plex kom ikke")
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

    /// Venter til [condition] er sann (hvert halve sekund).
    func until(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            wait(0.5)
        }
        return condition()
    }

    /// Spilleren spiller [key] (filmen eller episoden, «plex:2103»; verdien på `vod-spiller` i testene).
    func playing(_ player: XCUIElement, _ key: String, timeout: TimeInterval) -> Bool {
        until(timeout) { player.exists && (player.value as? String) == key }
    }

    /// Sekundene i «1:05» (tiden i VLC-spilleren).
    func seconds(_ label: String) -> Int {
        label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    /// Episoder fra Plex, fra «Fortsett å se»: «Neste episode» i rulleteksten til slutt (markørene fra Plex), «Hopp
    /// over introen», forrige og neste episode i kontrollene, og den neste spilles når en episode er ferdig, også i
    /// neste sesong.
    func test22PlexEpisoder() {
        let app = launch("plex-series")
        let resume = find(app, "fortsett-2001")
        if !resume.waitForExistence(timeout: 40) {
            dumpScreen(app, "«Fortsett å se» fra Plex kom ikke", shotName: "35-plex-fortsett-mangler")
        }
        XCTAssertTrue(resume.exists, "«Fortsett å se» fra Plex kom ikke")
        resume.tap()
        let player = find(app, "vod-spiller")
        if !player.waitForExistence(timeout: 10), resume.exists { resume.tap() }
        XCTAssertTrue(player.waitForExistence(timeout: 20), "spilleren kom ikke")
        XCTAssertTrue(playing(player, "plex:2102", timeout: 20), "episoden kom ikke: \(player.value ?? "")")
        let skip = find(app, "hopp-over")
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "knappen i rulleteksten kom ikke")
        XCTAssertEqual(skip.label, "Neste episode")
        shot("35-plex-rulletekst")
        skip.tap()
        XCTAssertTrue(playing(player, "plex:2103", timeout: 20), "den neste episoden kom ikke: \(player.value ?? "")")
        XCTAssertTrue(until(25) { skip.exists && skip.label == "Hopp over introen" }, "«Hopp over introen» kom ikke")
        shot("36-plex-intro")
        skip.tap()
        let time = find(app, "vod-tid")
        XCTAssertTrue(until(10) { time.exists && seconds(time.label) >= 9 }, "hoppet ikke over introen: \(time.label)")
        XCTAssertTrue(find(app, "forrige-episode").exists, "«Forrige episode» mangler")
        XCTAssertTrue(find(app, "neste-episode").exists, "«Neste episode» mangler")
        XCTAssertTrue(find(app, "neste-om").waitForExistence(timeout: 40), "«Neste: …» kom ikke")
        shot("37-plex-neste")
        XCTAssertTrue(playing(player, "plex:2201", timeout: 20), "neste sesong kom ikke: \(player.value ?? "")")
        let close = find(app, "lukk-vod")
        if close.waitForExistence(timeout: 10) { close.tap() }
        XCTAssertTrue(gone(player, timeout: 10), "krysset lukket ikke spilleren")
    }

    /// [a] står foran [b]: høyere opp, eller på samme linje og til venstre.
    func before(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        a.frame.minY < b.frame.minY - 4 || (abs(a.frame.minY - b.frame.minY) <= 4 && a.frame.minX < b.frame.minX)
    }

    /// Velger kategorien [id] («[name]»): i sidemenyen på iPad, med knappene øverst i Plex-fanen på iPhone, ellers i
    /// menyen øverst på iPhone.
    func chooseCategory(_ app: XCUIApplication, id: String, name: String) {
        if isPad || find(app, "vodkat-\(id)").exists {
            find(app, "vodkat-\(id)").tap()
        } else {
            find(app, "vod-kategori").tap()
            // ikke fanen med samme navn («Filmer» er både en fane og et Plex-bibliotek)
            let item = app.buttons.matching(NSPredicate(format: "label == %@", name))
            _ = item.firstMatch.waitForExistence(timeout: 5)
            let bar = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .zero
            if let choice = item.allElementsBoundByIndex.first(where: {
                !bar.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }) {
                choice.tap()
            }
        }
    }

    /// Velger [label] i menyen [menu].
    func choose(_ app: XCUIApplication, menu: String, _ label: String) -> Bool {
        find(app, menu).tap()
        let option = app.buttons[label]
        guard option.waitForExistence(timeout: 5) else { return false }
        option.tap()
        return true
    }

    /// Filmer hos leverandøren: «Nylig lagt til» på Hjem, rekkefølgen i en kategori («A–Å»), merkene fra navnet og
    /// kvaliteten på siden for en film, og «Mer fra <kategori>».
    func test24Sortering() {
        let app = launch("movies")
        XCTAssertTrue(find(app, "nylig-501").waitForExistence(timeout: 30), "«Nylig lagt til» mangler på Hjem")
        chooseCategory(app, id: "32", name: "Dokumentarer")
        let fjord = find(app, "vod-505"), coast = find(app, "vod-503")
        XCTAssertTrue(fjord.waitForExistence(timeout: 15) && coast.exists, "filmene i kategorien kom ikke")
        XCTAssertTrue(before(coast, fjord), "leverandørens rekkefølge: «Kysten fra lufta» først")
        XCTAssertTrue(choose(app, menu: "vod-sortering", "A–Å"), "fant ikke «A–Å» i menyen")
        XCTAssertTrue(until(10) { fjord.exists && coast.exists && before(fjord, coast) }, "A–Å: «Fjordlys» først")
        wait(1)
        shot("39-filmer-a-a")
        XCTAssertTrue(openPage(app, "vod-505", then: "merke-PRE", timeout: 15), "merket fra navnet mangler")
        for badge in ["2026", "4K", "HDR", "H.265", "5.1", "Dolby Digital+", "12+", "Norge"] {
            XCTAssertTrue(find(app, "merke-\(badge)").exists, "merket «\(badge)» mangler")
        }
        XCTAssertTrue(find(app, "lik-503").waitForExistence(timeout: 10), "«Mer fra Dokumentarer» mangler")
        wait(1)
        shot("40-film-merker")
    }

    /// Plex: rekkefølgen i et bibliotek («A–Å»: «Fjordbyen» foran «Nordlys over fjorden»), uten valg av sjanger.
    func test25PlexSortering() {
        let app = launch("plex")
        XCTAssertTrue(find(app, "vod-hjem").waitForExistence(timeout: 40), "Hjem fra Plex kom ikke")
        chooseCategory(app, id: "1", name: "Filmer")
        let nordlys = find(app, "vod-1001"), fjordbyen = find(app, "vod-1002")
        XCTAssertTrue(nordlys.waitForExistence(timeout: 15) && fjordbyen.exists, "filmene i biblioteket kom ikke")
        XCTAssertTrue(before(nordlys, fjordbyen), "«Nylig lagt til»: «Nordlys over fjorden» først")
        XCTAssertFalse(find(app, "vod-sjanger").exists, "valget av sjanger skal ikke vises")
        XCTAssertTrue(choose(app, menu: "vod-sortering", "A–Å"), "fant ikke «A–Å» i menyen")
        XCTAssertTrue(until(15) { nordlys.exists && fjordbyen.exists && before(fjordbyen, nordlys) },
                      "A–Å: «Fjordbyen» først")
        wait(1)
        shot("41-plex-a-a")
    }

    /// «Gi nytt navn» på innloggingen, og feilrapporten med «Kopier» (Konto på iPhone, innstillingene på iPad).
    /// Innloggingen med en M3U-lenke (lista hos den falske leverandøren, med TV-guide i gzip): gruppene og kanalene fra
    /// lista med programmene fra guiden, og ingen Filmer og Serier.
    func test28M3U() {
        let app = launch("login-m3u")
        let field = find(app, "m3u-lenke")
        XCTAssertTrue(field.waitForExistence(timeout: 30), "feltet for M3U-lenken mangler")
        XCTAssertTrue(find(app, "epg-lenke").exists, "feltet for EPG-lenken mangler")
        field.tap()
        field.typeText(server + "/liste.m3u\n")
        wait(1)
        shot("46-m3u-innlogging")
        find(app, "logg-inn").tap()
        let fjord = "kanal-\(stableHash("id:fjord.no|Fjordkanalen"))"
        if isPad {
            XCTAssertTrue(find(app, fjord).waitForExistence(timeout: 30), "kanalene fra M3U-lista kom ikke")
            XCTAssertTrue(find(app, "hylle-Kyst og fjord").exists, "gruppen fra lista mangler i sidemenyen")
        } else {
            XCTAssertTrue(find(app, "hylle-Kyst og fjord").waitForExistence(timeout: 30),
                          "gruppene fra M3U-lista kom ikke")
            XCTAssertTrue(find(app, "hylle-Uten kategori").exists, "«Uten kategori» mangler")
            XCTAssertTrue(openPage(app, "hylle-alle", then: fjord, timeout: 15), "Alle kanaler ble ikke vist")
        }
        let guide = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fra guiden"))
            .firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 30), "programmene fra TV-guiden kom ikke")
        XCTAssertFalse(app.tabBars.buttons["Filmer"].exists, "Filmer skal ikke vises for en M3U-liste")
        wait(2)
        shot("47-m3u")
    }

    /// Multiview med to innlogginger (Xtream og M3U-lista hos den falske leverandøren): kanal 1 i det første bildet, en
    /// kanal fra M3U-lista velges i det andre, dobbelttrykk gir stort bilde, og krysset lukker.
    func test29Multiview() {
        let app = launch("multiview")
        let first = find(app, "multiview-bilde-0")
        let second = find(app, "multiview-bilde-1")
        XCTAssertTrue(first.waitForExistence(timeout: 40), "multiview kom ikke")
        XCTAssertTrue(second.exists, "det andre bildet mangler")
        second.tap()
        let row = find(app, "velg-\(stableHash("id:villmark.no|Villmark"))")
        if !row.waitForExistence(timeout: 10), second.exists { second.tap() }
        XCTAssertTrue(row.waitForExistence(timeout: 20), "kanalvalget med kanalene fra M3U-lista kom ikke")
        wait(1)
        shot("48-multiview-velg")
        row.tap()
        let named = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "multiview-bilde-1", "Villmark"))
            .firstMatch
        XCTAssertTrue(named.waitForExistence(timeout: 15), "kanalen kom ikke i det andre bildet")
        wait(8)
        shot("49-multiview")
        first.doubleTap()
        wait(2)
        shot("50-multiview-stort")
        find(app, "lukk-multiview").tap()
        let multiview = find(app, "multiview")
        for _ in 0..<10 where multiview.exists { wait(1) }
        XCTAssertFalse(multiview.exists, "krysset lukket ikke multiview")
    }

    /// «Mer» i spilleren: strøminfoen (oppløsningen og bilder i sekundet fra AVPlayer) og bildeformatet for kanalen.
    func test30Strominfo() {
        let app = launch("player")
        XCTAssertTrue(find(app, "spiller").waitForExistence(timeout: 30), "spilleren kom ikke")
        let more = find(app, "spiller-mer")
        XCTAssertTrue(more.waitForExistence(timeout: 10), "«Mer» mangler i spilleren")
        wait(8)
        more.tap()
        let show = app.buttons["Vis strøminfo"]
        XCTAssertTrue(show.waitForExistence(timeout: 5), "«Vis strøminfo» mangler i menyen")
        show.tap()
        let info = find(app, "strominfo")
        XCTAssertTrue(info.waitForExistence(timeout: 5), "strøminfoen kom ikke")
        var known = false
        for _ in 0..<15 {
            if info.label.contains("×") || info.label.contains("fps") || info.label.contains("bit/s") {
                known = true
                break
            }
            wait(1)
        }
        XCTAssertTrue(known, "strøminfoen sier ingenting om strømmen: \(info.label)")
        more.tap()
        // undermenyen kan ha valget i seg («Bildeformat, Original»)
        let formats = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bildeformat")).firstMatch
        XCTAssertTrue(formats.waitForExistence(timeout: 5), "«Bildeformat» mangler i menyen")
        formats.tap()
        let fill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fyll skjermen")).firstMatch
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "bildeformatene mangler")
        fill.tap()
        wait(2)
        shot("51-strominfo")
    }

    /// Pause og tilbakespoling i direktesending: en ekte direktesending i HLS hos den falske leverandøren (som egen strøm
    /// for Fjordkanalen) spilles fra bufferet på enheten.
    func test31Tilbakespoling() {
        let app = launch("player", extra: ["FYRLYS_TEST_STREAMS": "Fjordkanalen = \(server)/hls/1/index.m3u8"])
        let player = find(app, "spiller")
        XCTAssertTrue(player.waitForExistence(timeout: 30), "spilleren kom ikke")
        let tried = { (player.value as? String) ?? "" }
        for _ in 0..<20 where !tried().contains("/shift/") { wait(1) }
        XCTAssertTrue(tried().contains("/shift/"), "direktesendingen ble ikke spilt fra bufferet: \(tried())")
        wait(10)
        XCTAssertFalse(find(app, "spiller-feil").exists, "direktesendingen fra bufferet kunne ikke spilles")
        shot("52-tilbakespoling")
    }

    func test27NavnOgFeilrapport() {
        let app = launch("settings")
        XCTAssertTrue(find(app, "innstillinger").waitForExistence(timeout: 30))
        let rename = find(app, "gi-nytt-navn")
        XCTAssertTrue(rename.waitForExistence(timeout: 10), "«Gi nytt navn» mangler")
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "feltet for navnet kom ikke")
        field.tap()
        field.typeText("Hjemme")
        app.alerts.buttons["Lagre"].firstMatch.tap()
        let name = find(app, "innlogget-som")
        XCTAssertTrue(until(10) { name.exists && name.label.contains("Hjemme") }, "navnet ble ikke brukt")
        shot("44-nytt-navn")
        let report = find(app, "feilrapport-knapp")
        // innstillingene på iPad er en lat liste: rull fram
        for _ in 0..<6 where !report.exists || !report.isHittable {
            app.swipeUp()
            wait(0.5)
        }
        XCTAssertTrue(report.exists, "«Feilrapport» mangler")
        report.tap()
        XCTAssertTrue(find(app, "kopier-rapport").waitForExistence(timeout: 10), "feilrapporten kom ikke")
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fyrlys – feilrapport")).firstMatch
        XCTAssertTrue(text.exists, "teksten i rapporten mangler")
        wait(1)
        shot("45-feilrapport")
    }

    /// Plex: hold inne på et bibliotek (sidemenyen på iPad, knappene øverst på iPhone): «Flytt opp» eller «Flytt til
    /// venstre» (Serier foran Filmer, også etter at fanen er hentet på nytt) og «Skjul». «Velg biblioteker» står ikke der.
    func test26PlexBiblioteker() {
        let app = launch("plex")
        XCTAssertTrue(find(app, "vod-hjem").waitForExistence(timeout: 40), "Hjem fra Plex kom ikke")
        let movies = find(app, "vodkat-1"), series = find(app, "vodkat-2"), other = find(app, "vodkat-4")
        XCTAssertTrue(series.waitForExistence(timeout: 10) && movies.exists && other.exists, "bibliotekene mangler")
        XCTAssertFalse(find(app, "velg-biblioteker").exists, "«Velg biblioteker» skal ikke stå blant bibliotekene")
        XCTAssertTrue(before(movies, series), "rekkefølgen fra Plex: Filmer først")
        series.press(forDuration: 1.2)
        let up = app.buttons[isPad ? "Flytt opp" : "Flytt til venstre"]
        XCTAssertTrue(up.waitForExistence(timeout: 5), "menyen kom ikke")
        up.tap()
        XCTAssertTrue(until(10) { series.exists && movies.exists && before(series, movies) },
                      "Serier ble ikke flyttet fram")
        // radene på Hjem følger: episodene (fra Serier, uten bibliotek i svaret) foran «Nylig lagt til» (mest Filmer)
        let episodes = app.staticTexts["Nytt fra Kystkanalen"], recent = app.staticTexts["Nylig lagt til"]
        XCTAssertTrue(until(10) { episodes.exists && recent.exists && episodes.frame.minY < recent.frame.minY },
                      "radene på Hjem fulgte ikke rekkefølgen")
        wait(1)
        shot("42-plex-rekkefolge")
        // «Andre videoer» står til slutt i raden på iPhone: dra raden til siden når den står utenfor skjermen
        let screen = app.windows.firstMatch.frame
        for _ in 0..<3 where !isPad && !screen.contains(CGPoint(x: other.frame.midX, y: other.frame.midY)) {
            movies.swipeLeft()
            wait(1)
        }
        other.press(forDuration: 1.2)
        let hide = app.buttons["Skjul"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "«Skjul» mangler i menyen")
        hide.tap()
        XCTAssertTrue(until(20) { movies.exists && !other.exists }, "«Andre videoer» står fortsatt blant bibliotekene")
        // fanen er hentet på nytt (uten det skjulte biblioteket), og rekkefølgen står seg
        XCTAssertTrue(series.exists && before(series, movies), "rekkefølgen ble borte")
        shot("43-plex-skjult")
    }

    /// Plex Home: «Hvem ser på?» (sidemenyen på iPad, første knapp på raden på iPhone); «Barna» har PIN (feil PIN
    /// gir feilmelding, 1234 bytter).
    func test32PlexHome() {
        let app = launch("plex")
        XCTAssertTrue(find(app, "vod-hjem").waitForExistence(timeout: 40), "Hjem fra Plex kom ikke")
        let who = find(app, "plex-bruker")
        XCTAssertTrue(who.waitForExistence(timeout: 10), "«Hvem ser på?» mangler")
        XCTAssertTrue(until(10) { who.label.contains("Eieren") }, "eieren står ikke som den som ser på: \(who.label)")
        who.tap()
        let child = find(app, "bruker-2")
        XCTAssertTrue(child.waitForExistence(timeout: 10), "brukerne kom ikke")
        wait(1)
        shot("46-plex-hvem")
        child.tap()
        let pin = find(app, "bruker-pin")
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "PIN-feltet kom ikke")
        pin.tap()
        pin.typeText("0000")
        XCTAssertTrue(find(app, "bruker-feil").waitForExistence(timeout: 10), "feil PIN ga ingen feilmelding")
        pin.tap()
        pin.typeText("1234")
        XCTAssertTrue(until(20) { who.exists && who.label.contains("Barna") }, "byttet ikke til Barna: \(who.label)")
        wait(1)
        shot("47-plex-barna")
    }

    /// Plex: «Merk som sett» eller «Merk som ikke sett» i menyen på siden for en film (merkes på serveren), og «Mer
    /// som dette».
    func test23PlexSett() {
        let app = launch("plex")
        if !find(app, "rad-1002").waitForExistence(timeout: 40) {
            dumpScreen(app, "radene fra Plex kom ikke", shotName: "38-plex-mangler")
        }
        XCTAssertTrue(openPage(app, "rad-1002", then: "vod-mer", timeout: 15), "siden for filmen kom ikke")
        XCTAssertTrue(find(app, "lik-1001").waitForExistence(timeout: 10), "«Mer som dette» mangler")
        // valget i menyen (id-en kommer ikke alltid med inn i menyen: teksten)
        let labels = ["Merk som sett", "Merk som ikke sett"]
        let item = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        find(app, "vod-mer").tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5), "«Merk som sett» mangler i menyen")
        let before = item.label
        shot("38-plex-meny")
        item.tap()
        var after = before
        for _ in 0..<4 where after == before {
            wait(3)
            find(app, "vod-mer").tap()
            guard item.waitForExistence(timeout: 3) else { continue }
            after = item.label
            // lukk menyen (trykk på tittelen øverst)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        }
        XCTAssertNotEqual(after, before, "menyen byttet ikke")
        wait(1)
        shot("38-plex-sett")
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
        // «Fjordkanalen HD» (91) spilles fra samme egne strøm som «Fjordkanalen» (1): én kanal, 19 i stedet for 20
        let tv = launch("tv", extra: ["FYRLYS_TEST_STREAMS": streams])
        let all = find(tv, "hylle-alle")
        XCTAssertTrue(all.waitForExistence(timeout: 30), "«Alle kanaler» kom ikke")
        for _ in 0..<10 where !all.label.contains("19") { wait(1) }
        XCTAssertTrue(all.label.contains("19"), "kanalene ble ikke slått sammen: \(all.label)")
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
