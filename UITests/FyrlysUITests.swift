import XCTest

/// Starter appen i Apple TV-simulatoren mot den falske leverandøren (tools/fake_xtream.py), sjekker skjermene og tar
/// skjermbilder (de legges i grenen «skjermbilder» av bygget på GitHub).
final class FyrlysUITests: XCTestCase {
    var server: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_SERVER"] ?? "http://127.0.0.1:8899" }
    /// den falske Plex (tools/fake_plex.py)
    var plex: String { ProcessInfo.processInfo.environment["FYRLYS_TEST_PLEX"] ?? "http://127.0.0.1:8897" }
    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    func launch(_ screen: String, language: String = "no", server: String? = nil, keep: Bool = false,
                extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FYRLYS_TEST_SERVER": server ?? self.server,
            "FYRLYS_TEST_SCREEN": screen,
            "FYRLYS_TEST_LANG": language,
            "FYRLYS_TEST_PLEX": plex,
        ].merging(extra) { _, new in new }
        // lista fra sist og innstillingene står (ellers tømmes de ved start)
        if keep { app.launchEnvironment["FYRLYS_TEST_KEEP"] = "1" }
        app.launch()
        return app
    }

    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Flytter fokus til [target] (et kanalkort, «kanal-…», en linje i sidemenyen, «hylle-…», eller noe annet), uansett
    /// hvor fokus står: fra fanelinja ned, mellom sidemenyen og kortene, og så opp, ned eller til siden mot målet (det
    /// rulles fram underveis).
    @discardableResult
    func focus(_ app: XCUIApplication, _ target: XCUIElement, tries: Int = 30) -> Bool {
        let sidebar = { (id: String) in id.hasPrefix("hylle-") || id.hasPrefix("vodkat-") }
        let wantsSidebar = sidebar(target.identifier)
        for _ in 0..<tries {
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let id = focused.exists ? focused.identifier : ""
            let inSidebar = sidebar(id)
            let onCard = ["kanal-", "vod-", "episode-", "rad-", "fortsett-"].contains { id.hasPrefix($0) }
            if !inSidebar && !onCard {
                // i fanelinja (eller ingen fokus): ned
                remote.press(.down)
            } else if wantsSidebar && !inSidebar {
                remote.press(.left)
            } else if !wantsSidebar && inSidebar {
                remote.press(.right)
            } else {
                let here = focused.frame
                let goal = target.frame
                if goal.midY < here.minY - 4 {
                    remote.press(.up)
                } else if goal.midY > here.maxY + 4 {
                    remote.press(.down)
                } else {
                    remote.press(goal.midX < here.midX ? .left : .right)
                }
            }
            wait(0.8)
        }
        return target.hasFocus
    }

    /// [a] står foran [b]: høyere opp, eller på samme linje og til venstre.
    func before(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        a.frame.minY < b.frame.minY - 4 || (abs(a.frame.minY - b.frame.minY) <= 4 && a.frame.minX < b.frame.minX)
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

    /// «Alle kanaler» med sidemenyen og de store kortene, fire i bredden, og Fyrlys-merket øverst til venstre.
    func test02TV() {
        let app = launch("tv")
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 30), "kanalkortene kom ikke")
        XCTAssertTrue(find(app, "fyrlys-merke").exists, "Fyrlys-merket mangler")
        XCTAssertTrue(find(app, "hylle-2").exists, "kategorien Sport mangler i sidemenyen")
        XCTAssertFalse(find(app, "hylle-6").exists, "tomme kategorier skal ikke vises")
        wait(4) // logoer og programinfo
        shot("02-tv")
    }

    /// Hold inne på et kort: «Legg til i favoritter». Da får kortet en stjerne, og kanalen står under «Nå på
    /// favorittene» øverst i «Alle kanaler».
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
        XCTAssertTrue(find(app, "seksjon-favoritter").waitForExistence(timeout: 10), "«Nå på favorittene» kom ikke")
        wait(3)
        shot("04-favoritt")
    }

    /// Fanelinja kommer helt fram igjen når du går tilbake til den øverste raden (eieren 4.11: den sto halvveis ute
    /// over kanten, fordi lista ble stående litt nede): først med kortene øverst, så med «Nå på favorittene».
    func test21Fanelinja() {
        let app = launch("tv")
        let card = find(app, "kanal-1")
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "fanelinja mangler")
        wait(2)
        let rest = bar.frame.minY

        // ned tre rader og opp igjen (kortene øverst er ikke i elementtreet mens lista er rullet ned)
        XCTAssertTrue(focus(app, card), "fikk ikke fokus på det første kortet")
        for _ in 0..<3 {
            remote.press(.down)
            wait(0.8)
        }
        wait(1)
        let away = bar.exists ? bar.frame.minY : .nan
        for _ in 0..<3 {
            remote.press(.up)
            wait(0.8)
        }
        XCTAssertTrue(focused(card, timeout: 5), "fokus kom ikke tilbake til det første kortet")
        wait(2)
        shot("39-fanelinja-tilbake")
        XCTAssertTrue(bar.exists, "fanelinja kom ikke tilbake (i ro \(rest), rullet \(away))")
        XCTAssertEqual(bar.frame.minY, rest, accuracy: 2,
                       "fanelinja kom ikke helt fram igjen (i ro \(rest), rullet \(away), nå \(bar.frame.minY))")

        // med «Nå på favorittene» øverst
        remote.press(.select, forDuration: 2)
        let add = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Legg til i favoritter")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8), "hurtigmenyen kom ikke")
        remote.press(.select)
        let head = find(app, "seksjon-favoritter")
        XCTAssertTrue(head.waitForExistence(timeout: 10), "«Nå på favorittene» kom ikke")
        wait(2)
        // kanal-1 står nå både i raden øverst og blant kortene (fokus er på det i rutenettet): opp til raden, rett under
        // overskriften «Nå på favorittene»
        let focusedCard = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let inStrip = {
            focusedCard.exists && head.exists && focusedCard.frame.minY > head.frame.maxY - 4
                && focusedCard.frame.minY < head.frame.maxY + 120
        }
        for _ in 0..<4 where !inStrip() {
            remote.press(.up)
            wait(0.8)
        }
        XCTAssertTrue(inStrip(), "fikk ikke fokus på raden med favorittene")
        for _ in 0..<3 {
            remote.press(.down)
            wait(0.8)
        }
        wait(1)
        for _ in 0..<3 {
            remote.press(.up)
            wait(0.8)
        }
        wait(2)
        XCTAssertTrue(inStrip(), "fokus kom ikke tilbake til raden med favorittene")
        shot("40-fanelinja-favoritter")
        XCTAssertTrue(bar.exists, "fanelinja kom ikke tilbake over «Nå på favorittene»")
        XCTAssertEqual(bar.frame.minY, rest, accuracy: 2,
                       "fanelinja kom ikke helt fram over «Nå på favorittene» (i ro \(rest), nå \(bar.frame.minY))")
    }

    /// Venter til [element] finnes og har fokus.
    func focused(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.hasFocus { return true }
            wait(0.5)
        } while Date() < end
        return false
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
        XCTAssertTrue(before(sportFirst, news), "«Alle kanaler» begynner ikke med Sport")
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

        // til sidemenyen (fra det første kortet: de raske trykkene kan ha flyttet fokus opp i fanelinja) og nedover
        XCTAssertTrue(focus(app, first), "fikk ikke fokus på det første kortet igjen")
        remote.press(.left)
        wait(1)
        start = Date()
        for _ in 0..<20 { remote.press(.down) }
        let sidebar = Date().timeIntervalSince(start)
        wait(2)
        shot("17-stor-liste-sidemeny")

        // tilbake i kortene og nedover: toppen når fanelinja har glidd bort
        remote.press(.right)
        wait(1)
        for _ in 0..<4 {
            remote.press(.down)
            wait(0.6)
        }
        wait(2)
        shot("18-stor-liste-rullet")
        // Menu: fokus opp i fanelinja (ett trykk; et til ville lukket appen)
        remote.press(.menu)
        wait(2)
        shot("19-stor-liste-fanelinja")
        app.terminate()

        // igjen, med lista fra sist på disk
        start = Date()
        app = launch("tv", server: big, keep: true)
        XCTAssertTrue(find(app, "kanal-1000").waitForExistence(timeout: 60), "kortene kom ikke med lista fra sist")
        let warm = Date().timeIntervalSince(start)
        print(String(format: "YTELSE: 25 000 kanaler i simulatoren: første kort etter %.1f s uten lista fra sist og "
                     + "%.1f s med; 24 steg i kortene %.1f s; 20 steg i sidemenyen %.1f s", cold, warm, grid, sidebar))
    }

    /// Filmer: kategoriene og plakatene, siden for en film og spilleren (Menu lukker den).
    func test12Filmer() {
        let app = launch("movies")
        let movie = find(app, "vod-501")
        XCTAssertTrue(movie.waitForExistence(timeout: 30), "filmene kom ikke")
        XCTAssertTrue(find(app, "vodkat-31").exists, "kategorien mangler")
        wait(2)
        shot("20-filmer")
        XCTAssertTrue(focus(app, movie), "fikk ikke fokus på filmen")
        remote.press(.select)
        XCTAssertTrue(find(app, "vod-side").waitForExistence(timeout: 15), "siden for filmen kom ikke")
        XCTAssertTrue(find(app, "spill-av").waitForExistence(timeout: 15), "«Spill av» mangler")
        wait(2)
        shot("21-film")
        remote.press(.select)
        let player = find(app, "vod-spiller")
        XCTAssertTrue(player.waitForExistence(timeout: 20), "spilleren kom ikke")
        wait(8)
        shot("22-film-spiller")
        for _ in 0..<3 where player.exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertFalse(player.exists, "Menu lukket ikke spilleren")
    }

    /// Serier: siden for en serie med sesongene og episodene.
    func test13Serier() {
        let app = launch("series")
        let series = find(app, "vod-9001")
        XCTAssertTrue(series.waitForExistence(timeout: 30), "seriene kom ikke")
        XCTAssertTrue(focus(app, series), "fikk ikke fokus på serien")
        remote.press(.select)
        XCTAssertTrue(find(app, "episode-900111").waitForExistence(timeout: 15), "episodene kom ikke")
        XCTAssertTrue(find(app, "sesong-2").exists, "sesong 2 mangler")
        let next = find(app, "fortsett-serie")
        XCTAssertTrue(next.exists, "knappen til episoden du skal se, mangler")
        XCTAssertTrue(next.label.contains("S1 E1"), "første episode skulle stå på knappen: \(next.label)")
        wait(2)
        shot("23-serie")
        // favoritt: serien står så under «Favoritter» på Hjem
        let star = find(app, "vod-favoritt")
        XCTAssertTrue(star.exists, "stjernen mangler")
        XCTAssertTrue(focus(app, star), "fikk ikke fokus på stjernen")
        remote.press(.select)
        wait(1)
        remote.press(.menu)
        XCTAssertTrue(find(app, "vodfav-9001").waitForExistence(timeout: 10), "serien står ikke under «Favoritter»")
        wait(2)
        shot("38-serier-hjem")
    }

    /// TV-arkivet for en kanal: dagene og programmene, og et program spilles fra start.
    func test14Arkiv() {
        let app = launch("archive")
        XCTAssertTrue(find(app, "arkiv").waitForExistence(timeout: 30), "arkivet kom ikke")
        let program = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'arkiv-'")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 15), "programmene i arkivet kom ikke")
        wait(2)
        shot("24-arkiv")
    }

    /// En film i mkv spilles med VLC: tiden går, lydsporet og undertekstene kan velges, høyre spoler, og Menu lukker.
    func test15Mkv() {
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
        wait(1)
        shot("25-mkv")
        // Menu skjuler kontrollene: undertekstene alene (i Apple sin stil), mens den første teksten står (1–9 s)
        remote.press(.menu)
        wait(1)
        shot("26-mkv-tekst")
        remote.press(.right)
        wait(3)
        shot("26-mkv-spolt")
        let player = find(app, "vod-spiller")
        for _ in 0..<3 where player.exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertFalse(player.exists, "Menu lukket ikke spilleren")
    }

    /// Venter til teksten i [element] er en annen enn [from] (og ikke «0:00»): tiden i spilleren går.
    func changes(_ element: XCUIElement, from: String, timeout: Int = 40) -> Bool {
        for _ in 0..<timeout {
            if element.exists, element.label != from, element.label != "0:00" { return true }
            wait(1)
        }
        return false
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

    /// Trykker til høyre til [target] har fokus (knappene på en rad).
    func focusRight(_ target: XCUIElement, tries: Int = 6) -> Bool {
        for _ in 0..<tries {
            if target.hasFocus { return true }
            remote.press(.right)
            wait(0.8)
        }
        return target.hasFocus
    }

    /// Episoder fra Plex: «Neste episode» i rulleteksten til slutt går til den neste (markørene fra Plex), «Hopp over
    /// introen» hopper over introen, forrige og neste episode står i kontrollene, og når en episode er ferdig, spilles
    /// den neste («Neste: …»), også i neste sesong.
    func test22PlexEpisoder() {
        let app = launch("plex-series")
        let series = find(app, "rad-2001")
        XCTAssertTrue(series.waitForExistence(timeout: 40), "serien mangler i radene")
        XCTAssertTrue(focus(app, series), "fikk ikke fokus på serien")
        remote.press(.select)
        let resume = find(app, "fortsett-serie")
        XCTAssertTrue(resume.waitForExistence(timeout: 15), "knappen til episoden du skal se, mangler")
        wait(1)
        if !resume.hasFocus { _ = focusRight(resume) }
        remote.press(.select)
        let player = find(app, "vod-spiller")
        XCTAssertTrue(player.waitForExistence(timeout: 20), "spilleren kom ikke")
        XCTAssertTrue(playing(player, "plex:2102", timeout: 20), "episoden kom ikke: \(player.value ?? "")")
        // rulleteksten til slutt (fra 20 s; episoden begynner på 9 s): «Neste episode», med fokus
        let skip = find(app, "hopp-over")
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "knappen i rulleteksten kom ikke")
        XCTAssertEqual(skip.label, "Neste episode")
        wait(1)
        shot("41-plex-rulletekst")
        remote.press(.select)
        XCTAssertTrue(playing(player, "plex:2103", timeout: 20), "den neste episoden kom ikke: \(player.value ?? "")")
        // introen (2–9 s): hopp over den
        XCTAssertTrue(until(25) { skip.exists && skip.label == "Hopp over introen" }, "«Hopp over introen» kom ikke")
        wait(0.5)
        shot("42-plex-intro")
        remote.press(.select)
        let time = find(app, "vod-tid")
        XCTAssertTrue(until(10) { time.exists && seconds(time.label) >= 9 }, "hoppet ikke over introen: \(time.label)")
        XCTAssertTrue(find(app, "forrige-episode").exists, "«Forrige episode» mangler")
        XCTAssertTrue(find(app, "neste-episode").exists, "«Neste episode» mangler")
        // ferdig (30 s): «Neste: …», og så første episode i sesong 2
        XCTAssertTrue(find(app, "neste-om").waitForExistence(timeout: 40), "«Neste: …» kom ikke")
        shot("43-plex-neste")
        XCTAssertTrue(playing(player, "plex:2201", timeout: 20), "neste sesong kom ikke: \(player.value ?? "")")
        for _ in 0..<3 where player.exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertFalse(player.exists, "Menu lukket ikke spilleren")
    }

    /// Flytter fokus fra sidemenyen inn på siden og opp til [target] (menyene over plakatene), og til siden når fokus
    /// står på samme linje.
    func focusUp(_ app: XCUIApplication, _ target: XCUIElement, tries: Int = 10) -> Bool {
        for _ in 0..<tries {
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists, focused.identifier.hasPrefix("vodkat-") {
                remote.press(.right)
            } else if focused.exists, abs(focused.frame.midY - target.frame.midY) < 40 {
                remote.press(focused.frame.midX > target.frame.midX ? .left : .right)
            } else {
                remote.press(.up)
            }
            wait(0.8)
        }
        return target.hasFocus
    }

    /// Velger [label] i menyen som er åpen (ned til den, så velg).
    func choose(_ app: XCUIApplication, _ label: String) -> Bool {
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard option.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<8 where !option.hasFocus {
            remote.press(.down)
            wait(0.6)
        }
        guard option.hasFocus else { return false }
        remote.press(.select)
        return true
    }

    /// Filmer hos leverandøren: «Nylig lagt til» på Hjem, rekkefølgen i en kategori («A–Å»), merkene fra navnet og
    /// kvaliteten på siden for en film, og «Mer fra <kategori>».
    func test24Sortering() {
        let app = launch("movies")
        XCTAssertTrue(find(app, "nylig-501").waitForExistence(timeout: 30), "«Nylig lagt til» mangler på Hjem")
        let docs = find(app, "vodkat-32")
        XCTAssertTrue(focus(app, docs), "fikk ikke fokus på Dokumentarer")
        remote.press(.select)
        let fjord = find(app, "vod-505"), coast = find(app, "vod-503")
        XCTAssertTrue(fjord.waitForExistence(timeout: 15) && coast.exists, "filmene i kategorien kom ikke")
        XCTAssertTrue(before(coast, fjord), "leverandørens rekkefølge: «Kysten fra lufta» først")
        let sort = find(app, "vod-sortering")
        XCTAssertTrue(sort.exists, "valget av rekkefølge mangler")
        XCTAssertTrue(focusUp(app, sort), "fikk ikke fokus på rekkefølgen")
        remote.press(.select)
        XCTAssertTrue(choose(app, "A–Å"), "fant ikke «A–Å» i menyen")
        XCTAssertTrue(until(10) { fjord.exists && coast.exists && before(fjord, coast) }, "A–Å: «Fjordlys» først")
        wait(1)
        shot("45-filmer-a-a")
        XCTAssertTrue(focus(app, fjord), "fikk ikke fokus på filmen")
        remote.press(.select)
        XCTAssertTrue(find(app, "merke-PRE").waitForExistence(timeout: 15), "merket fra navnet mangler")
        for badge in ["2026", "4K", "HDR", "H.265", "5.1", "Dolby Digital+", "12+", "Norge"] {
            XCTAssertTrue(find(app, "merke-\(badge)").exists, "merket «\(badge)» mangler")
        }
        XCTAssertTrue(find(app, "lik-503").waitForExistence(timeout: 10), "«Mer fra Dokumentarer» mangler")
        wait(1)
        shot("46-film-merker")
    }

    /// Plex: et bibliotek med sjanger og rekkefølge (Dokumentar: bare «Fjordbyen»), og kvaliteten på siden for en film.
    func test25PlexSjanger() {
        let app = launch("plex")
        let library = find(app, "vodkat-1")
        XCTAssertTrue(library.waitForExistence(timeout: 40), "biblioteket Filmer mangler")
        XCTAssertTrue(focus(app, library), "fikk ikke fokus på biblioteket")
        remote.press(.select)
        XCTAssertTrue(find(app, "vod-1001").waitForExistence(timeout: 15), "filmene i biblioteket kom ikke")
        let genre = find(app, "vod-sjanger")
        XCTAssertTrue(genre.waitForExistence(timeout: 10), "valget av sjanger mangler")
        XCTAssertTrue(focusUp(app, genre), "fikk ikke fokus på sjangeren")
        remote.press(.select)
        XCTAssertTrue(choose(app, "Dokumentar"), "fant ikke «Dokumentar» i menyen")
        XCTAssertTrue(until(15) { !find(app, "vod-1001").exists && find(app, "vod-1002").exists },
                      "sjangeren ble ikke brukt")
        wait(1)
        shot("47-plex-sjanger")
    }

    /// Plex: «Velg biblioteker» nederst i sidemenyen; et bibliotek som slås av, er borte fra sidemenyen.
    func test27PlexBiblioteker() {
        let app = launch("plex")
        let other = find(app, "vodkat-4")
        XCTAssertTrue(other.waitForExistence(timeout: 40), "biblioteket «Andre videoer» mangler")
        XCTAssertTrue(focus(app, other), "fikk ikke fokus på «Andre videoer»")
        let choose = find(app, "velg-biblioteker")
        XCTAssertTrue(choose.exists, "«Velg biblioteker» mangler")
        for _ in 0..<3 where !choose.hasFocus {
            remote.press(.down)
            wait(0.8)
        }
        XCTAssertTrue(choose.hasFocus, "fikk ikke fokus på «Velg biblioteker»")
        remote.press(.select)
        let toggle = find(app, "vis-bibliotek-4")
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "bibliotekene kom ikke")
        for _ in 0..<6 where !toggle.hasFocus {
            remote.press(.down)
            wait(0.6)
        }
        XCTAssertTrue(toggle.hasFocus, "fikk ikke fokus på «Andre videoer»")
        remote.press(.select)
        wait(1)
        shot("49-plex-biblioteker")
        remote.press(.menu)
        XCTAssertTrue(until(20) { find(app, "vodkat-1").exists && !find(app, "vodkat-4").exists },
                      "«Andre videoer» står fortsatt i sidemenyen")
        wait(1)
        shot("50-plex-skjult")
    }

    /// Feilrapporten nederst i innstillingene: hele teksten på skjermen, og «Send til iPhone».
    func test28Feilrapport() {
        let app = launch("settings")
        XCTAssertTrue(find(app, "innstillinger").waitForExistence(timeout: 30))
        let button = find(app, "feilrapport-knapp")
        XCTAssertTrue(button.waitForExistence(timeout: 10), "«Feilrapport» mangler")
        for _ in 0..<40 where !button.hasFocus {
            remote.press(.down)
            wait(0.4)
        }
        XCTAssertTrue(button.hasFocus, "fikk ikke fokus på «Feilrapport»")
        remote.press(.select)
        XCTAssertTrue(find(app, "send-rapport").waitForExistence(timeout: 10), "feilrapporten kom ikke")
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fyrlys – feilrapport")).firstMatch
        XCTAssertTrue(text.exists, "teksten i rapporten mangler")
        wait(1)
        shot("51-feilrapport")
        remote.press(.menu)
    }

    /// Søket i filmene på Apple TV (øverst i sidemenyen).
    func test26FilmSok() {
        let app = launch("movies")
        let home = find(app, "vodkat-hjem")
        XCTAssertTrue(home.waitForExistence(timeout: 30), "sidemenyen kom ikke")
        XCTAssertTrue(focus(app, home), "fikk ikke fokus på Hjem")
        let search = find(app, "vod-sok")
        XCTAssertTrue(search.exists, "søket mangler i sidemenyen")
        for _ in 0..<3 where !search.hasFocus {
            remote.press(.up)
            wait(0.8)
        }
        XCTAssertTrue(search.hasFocus, "fikk ikke fokus på søket")
        remote.press(.select)
        wait(3)
        app.typeText("fjord")
        XCTAssertTrue(find(app, "sok-505").waitForExistence(timeout: 15), "søket fant ikke «Fjordlys»")
        XCTAssertFalse(find(app, "sok-501").exists, "søket fant en film uten «fjord» i navnet")
        wait(1)
        shot("48-film-sok")
    }

    /// Plex: «Merk som sett» eller «Merk som ikke sett» på siden for en film (merkes på serveren), og «Mer som dette».
    func test23PlexSett() {
        let app = launch("plex")
        let movie = find(app, "rad-1002")
        XCTAssertTrue(movie.waitForExistence(timeout: 40), "filmen mangler i radene")
        XCTAssertTrue(focus(app, movie), "fikk ikke fokus på filmen")
        remote.press(.select)
        let mark = find(app, "merk-sett")
        XCTAssertTrue(mark.waitForExistence(timeout: 15), "«Merk som sett» mangler")
        wait(1)
        let before = mark.label
        XCTAssertTrue(focusRight(mark), "fikk ikke fokus på «\(before)»")
        remote.press(.select)
        XCTAssertTrue(until(15) { mark.exists && mark.label != before }, "knappen byttet ikke (\(before))")
        XCTAssertTrue(find(app, "lik-1001").waitForExistence(timeout: 10), "«Mer som dette» mangler")
        wait(1)
        shot("44-plex-sett")
    }

    /// Plex (koblet til fra før): «Hjem» med radene fra Plex og «Fortsett å se», bibliotekene som kategorier, siden
    /// for en film med «Fortsett» der Plex sier du slapp, og filmen (mkv) spilles rett fra serveren med VLC.
    func test17Plex() {
        let app = launch("plex")
        let movie = find(app, "rad-1001")
        XCTAssertTrue(movie.waitForExistence(timeout: 40), "radene fra Plex kom ikke")
        XCTAssertTrue(find(app, "vodkat-hjem").exists, "«Hjem» mangler")
        XCTAssertTrue(find(app, "vodkat-1").exists, "biblioteket Filmer mangler")
        XCTAssertFalse(find(app, "vodkat-3").exists, "musikkbiblioteket skal ikke vises")
        XCTAssertTrue(find(app, "fortsett-1001").exists, "«Fortsett å se» fra Plex mangler")
        XCTAssertFalse(find(app, "rad-e2102").exists, "episodene skal stå under Serier")
        wait(2)
        shot("28-plex-hjem")
        XCTAssertTrue(focus(app, movie), "fikk ikke fokus på filmen")
        remote.press(.select)
        let play = find(app, "spill-av")
        XCTAssertTrue(play.waitForExistence(timeout: 15), "siden for filmen kom ikke")
        wait(2)
        XCTAssertTrue(play.label.contains("0:12"), "«Fortsett» der Plex sier du slapp mangler: \(play.label)")
        shot("29-plex-film")
        remote.press(.select)
        let time = find(app, "vod-tid")
        XCTAssertTrue(time.waitForExistence(timeout: 20), "spilleren kom ikke")
        let first = time.label
        XCTAssertTrue(changes(time, from: first), "tiden gikk ikke (filmen fra Plex spilte ikke)")
        wait(2)
        shot("30-plex-spiller")
        let player = find(app, "vod-spiller")
        for _ in 0..<3 where player.exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertFalse(player.exists, "Menu lukket ikke spilleren")
    }

    /// Serier med Plex: radene med nye episoder, og en episode spilles med en gang der Plex sier du slapp.
    func test19PlexSerier() {
        let app = launch("plex-series")
        let episode = find(app, "rad-e2102")
        XCTAssertTrue(episode.waitForExistence(timeout: 40), "radene med episoder fra Plex kom ikke")
        wait(2)
        shot("33-plex-serier")
        XCTAssertTrue(focus(app, episode), "fikk ikke fokus på episoden")
        remote.press(.select)
        let time = find(app, "vod-tid")
        XCTAssertTrue(time.waitForExistence(timeout: 20), "episoden startet ikke")
        XCTAssertTrue(changes(time, from: time.label), "tiden gikk ikke (episoden fra Plex spilte ikke)")
        wait(1)
        shot("34-plex-episode")
        let player = find(app, "vod-spiller")
        for _ in 0..<3 where player.exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertFalse(player.exists, "Menu lukket ikke spilleren")
        // seriesiden: knappen går rett til episoden Plex sier du er midt i
        let series = find(app, "rad-2001")
        XCTAssertTrue(series.waitForExistence(timeout: 10), "serien mangler i radene")
        XCTAssertTrue(focus(app, series), "fikk ikke fokus på serien")
        remote.press(.select)
        let next = find(app, "fortsett-serie")
        XCTAssertTrue(next.waitForExistence(timeout: 15), "knappen til episoden du skal se, mangler")
        XCTAssertTrue(next.label.contains("S1 E2"), "episoden du er midt i, skulle stå på knappen: \(next.label)")
        wait(2)
        shot("35-plex-serie")
    }

    /// Koble til Plex under Innstillinger: koden vises, og når den er «skrevet inn» (den falske plex.tv gir nøkkelen
    /// tredje gang), kobles det til serveren som svarer.
    func test18PlexKobling() {
        let app = launch("plex-link")
        let connect = find(app, "koble-til-plex")
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "«Koble til Plex» mangler")
        XCTAssertTrue(focus(app, connect), "fikk ikke fokus på «Koble til Plex»")
        remote.press(.select)
        let code = find(app, "plex-kode")
        XCTAssertTrue(code.waitForExistence(timeout: 15), "koden kom ikke")
        XCTAssertEqual(code.label, "FYRL")
        shot("31-plex-kode")
        XCTAssertTrue(find(app, "plex-tilkoblet").waitForExistence(timeout: 40), "ble ikke koblet til Plex")
        wait(1)
        shot("32-plex-tilkoblet")
    }

    /// En film leverandøren ikke har: VLC gir opp, og forklaringen vises.
    func test16MkvFeil() {
        let app = launch("mkv-feil")
        XCTAssertTrue(find(app, "vod-feil").waitForExistence(timeout: 60), "forklaringen kom ikke")
        wait(1)
        shot("27-mkv-feil")
    }

    func test04Guide() {
        let app = launch("guide")
        XCTAssertTrue(find(app, "guide").waitForExistence(timeout: 30))
        XCTAssertTrue(find(app, "guide-velger").exists, "valget av kanaler i guiden mangler")
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
        let player = find(app, "spiller")
        XCTAssertTrue(player.waitForExistence(timeout: 30), "spilleren kom ikke")
        wait(10)
        shot("09-spiller")
        remote.press(.select) // pause: kontrollene vises
        wait(2)
        shot("10-spiller-kontroller")
        remote.press(.select)
        wait(1)
        // Menyknappen lukker spilleren (først skjules kontrollene). Kortene finnes bak spilleren, så det er spilleren
        // som må være borte.
        for _ in 0..<3 where player.exists {
            remote.press(.menu)
            wait(2)
        }
        XCTAssertFalse(player.exists, "Menu lukket ikke spilleren")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(find(app, "kanal-1").waitForExistence(timeout: 10), "kom ikke tilbake fra spilleren")
        // «Sist sett» øverst i «Alle kanaler» har kanalen nå
        XCTAssertTrue(find(app, "seksjon-sist").exists, "«Sist sett» mangler øverst")
        wait(3)
        shot("09-sist-sett")
    }

    func test07PlayerError() {
        let app = launch("player-error")
        XCTAssertTrue(find(app, "spiller-feil").waitForExistence(timeout: 60), "feilen kom ikke")
        // feilen kommer med en gang, forklaringen (HTTP-koden) like etter
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch
                        .waitForExistence(timeout: 15), "HTTP-koden står ikke i feilen")
        wait(1)
        shot("11-spiller-feil")
    }

    /// Egne strømmer (oppdiktede adresser hos den falske leverandøren): kanalen kjennes igjen ut fra navnet, og
    /// spilleren bruker den egne adressen (den finnes ikke, så feilen vises, mens kanalen ellers spilles).
    static let streams = "Fjordkanalen = http://127.0.0.1:8899/egen/finnes-ikke.m3u8\n"
        + "http://127.0.0.1:8899/egen/kystnytt24/muxed.m3u8\nhttp://127.0.0.1:8899/egen/nrk1/muxed.m3u8"

    func test20EgneStrommer() {
        let app = launch("strommer", extra: ["FYRLYS_TEST_STREAMS": Self.streams])
        let stream = find(app, "egen-strom-kystnytt24")
        XCTAssertTrue(stream.waitForExistence(timeout: 30), "de egne strømmene vises ikke")
        let matched = find(app, "egen-strom-fjordkanalen")
        for _ in 0..<10 where !matched.label.contains("Fjordkanalen") { wait(1) }
        XCTAssertTrue(matched.label.contains("Fjordkanalen"), "kanalen ble ikke funnet: \(matched.label)")
        XCTAssertTrue(find(app, "egen-strom-kystnytt24").label.contains("Kystnytt 24"), "kanalen fra adressen mangler")
        XCTAssertTrue(find(app, "egen-strom-nrk1").exists, "en adresse uten kanal mangler")
        wait(1)
        shot("36-egne-strommer")
        // «Fjordkanalen HD» (91) spilles fra samme egne strøm som «Fjordkanalen» (1): én kanal, 19 i stedet for 20
        let tv = launch("tv", extra: ["FYRLYS_TEST_STREAMS": Self.streams])
        let all = find(tv, "hylle-alle")
        XCTAssertTrue(all.waitForExistence(timeout: 30), "sidemenyen kom ikke")
        for _ in 0..<10 where !all.label.contains("19") { wait(1) }
        XCTAssertTrue(all.label.contains("19"), "kanalene ble ikke slått sammen: \(all.label)")
        // spilleren bruker den egne adressen for kanalen; den finnes ikke, så spilles leverandørens strøm i stedet
        // (før 0.1.23 kom feilen, og kanalen var ikke å se)
        let player = launch("player", extra: ["FYRLYS_TEST_STREAMS": Self.streams])
        let screen = find(player, "spiller")
        XCTAssertTrue(screen.waitForExistence(timeout: 30), "spilleren kom ikke")
        let tried = { (screen.value as? String) ?? "" }
        for _ in 0..<40 where !tried().contains("/live/") { wait(1) }
        XCTAssertTrue(tried().contains("finnes-ikke"), "spilleren brukte ikke den egne adressen: \(tried())")
        XCTAssertTrue(tried().contains("/live/"), "spilleren byttet ikke til leverandørens strøm: \(tried())")
        wait(3)
        XCTAssertFalse(find(player, "spiller-feil").exists, "feilen kom selv om leverandørens strøm virker")
        shot("37-egen-strom-reserve")
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
