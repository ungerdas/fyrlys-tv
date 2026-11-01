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
        wait(2)
        shot("25-mkv")
        remote.press(.right)
        wait(3)
        shot("26-mkv-spolt")
        // Menu skjuler kontrollene først: undertekstene alene (i Apple sin stil)
        remote.press(.menu)
        wait(2)
        shot("26-mkv-tekst")
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
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '404'")).firstMatch.exists,
                      "HTTP-koden står ikke i feilen")
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
        let player = launch("player", extra: ["FYRLYS_TEST_STREAMS": Self.streams])
        XCTAssertTrue(find(player, "spiller-feil").waitForExistence(timeout: 60),
                      "spilleren brukte ikke den egne adressen")
        wait(1)
        shot("37-egen-strom-feil")
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
