# Fyrlys for Apple TV – arbeidsnotater for Claude

Egen app for Apple TV (tvOS 17+), Swift/SwiftUI med AVPlayer, i tillegg til Fyrlys for Windows (eget repo). Logger inn
med Xtream Codes og henter alt rett fra leverandøren. Repoet er **offentlig**: hold appen, koden, testene,
commit-meldingene og disse notatene fri for navn, hjemmenett, maskinnavn, leverandør, brukernavn, hemmeligheter og
e-postadresser (eksempeladresser som iptv.example.com og 192.168.1.10 er greit). Testene bruker bare den falske
leverandøren i `tools/fake_xtream.py`, med oppdiktede kanaler. `README.md` er forsiden på GitHub, skrevet for brukere.

## Arbeidsmåte
- Svar alltid på **norsk**. Commit-meldinger på norsk med prefikset `Fyrlys:`. Push rett til `main`.
- **Xcode kan ikke kjøres i Claude-økta** (ingen Mac). Kjernen (`Core/`, bare Foundation) testes her med Swift for
  Linux: `swift test --package-path Core` (Swift 6.2 ligger i scratchpad-mappen til økta, `swift/usr/bin`, og må
  lastes ned på nytt i en ny økt: swift.org-tarball for Ubuntu 24.04; kjør `swift` fra en mappe som finnes: er
  arbeidsmappen slettet, krasjer swift-driveren med «Illegal instruction»). Appen bygges og testes av GitHub Actions på
  macOS: `gh run list --repo ungerdas/fyrlys-tv`, `gh run watch <id> --repo ungerdas/fyrlys-tv`. Loggene og
  artefaktene kan ikke lastes ned herfra; ved feil legger workflowen feilene og slutten av loggen som merknad:
  `gh api repos/ungerdas/fyrlys-tv/check-runs/<jobb-id>/annotations` (jobb-id fra `gh run view <id> --json jobs`).
- **Skjermbilder**: UI-testene (`UITests/FyrlysUITests.swift`) tar bilder i simulatoren, og workflowen legger dem i
  grenen `skjermbilder` (overskrives hver gang). Hent med `git fetch origin skjermbilder` og
  `git show origin/skjermbilder:02-tv.png > …`, og se på dem med Read. Bilder XCTest tok ved feil heter `feil-*.png`.
- Appen i testmodus: miljøvariablene `FYRLYS_TEST_SERVER` (falsk leverandør, test/test, ingen nøkkelring, egne
  innstillinger og kanalliste som tømmes, unntatt med `FYRLYS_TEST_KEEP`), `FYRLYS_TEST_SCREEN` (login, tv, guide,
  search, settings, player, player-error = kanal 90 som svarer 404) og `FYRLYS_TEST_LANG` (`App/TestSupport.swift`).
  Elementene testene finner, har `accessibilityIdentifier` (`kanal-<id>`, `hylle-…`, `favoritt-<id>`, `seksjon-dine`/
  `-alle`/`-kategorier`, `lagt-overst`, `spiller-feil`, `guide`, `innstillinger`). `focus(app, mål)` i UI-testene
  flytter fokus dit uansett hvor det står. Testen av farten (`test11StorListe`) bruker en stor falsk leverandør
  (`fake_xtream.py --kanaler 25000 --kategorier 450` på port 8898, `FYRLYS_TEST_SERVER_STOR`); tidene står som merknad
  «ytelse» på bygget (simulatoren på en Mac er raskere enn en Apple TV).
- **Utseendet følger Fyrlys på Windows** (eieren 31.10: «så lik som mulig windows appen»), men **fanelinja til Apple TV
  beholdes** (eieren: «jeg liker fanelinja til apple! så behold den»). Fasit for mål og farger er Windows-repoet
  (`ungerdas/fyrlys`, offentlig, kan klones for lesing: `lib/ui/channel_card.dart`, `home_page.dart` (`_sidebar`,
  `_categoryTile`), `theme.dart`), skalert opp for TV (rundt 1,4 ganger pikslene der). Ingen endringer i det repoet
  herfra.
- Swift 5-modus i appen (`SWIFT_VERSION 5.0`); kjernen er swift-tools 5.9. Unngå navn som `Category` (finnes i
  ObjC-kjøretiden) og frie funksjoner med samme navn som View-metoder (`tint`): inne i en View vinner metoden.
- Tekster: `L("norsk tekst", ["navn": verdi])` (`Core/Sources/FyrlysCore/L10n.swift`); norsken er nøkkelen i
  `english`. `L10nTests.testEverythingIsTranslated` finner alle `L("…")` i `Core/Sources` og `App` og krever engelsk
  med de samme `{navnene}`. Tekst som ikke skal oversettes: `Text(verbatim:)`. `appLanguage` settes ved start fra
  språket på Apple TV-en (nb/nn/no = norsk, ellers engelsk).
- **Versjoner**: `MARKETING_VERSION` i `project.yml` (0.1.0 til å begynne med), byggnummeret er `github.run_number`.
  Øk patch-versjonen før hver push som legges ut (når TestFlight er satt opp), og skriv avsnittet i `CHANGELOG.md`.
- Ikonene lages av `tools/make_icons.py` (cairosvg) fra fyret i Fyrlys-ikonet: tre lag (fyret, strålene, bakgrunnen)
  for parallakse, App Store-ikonet 1280×768 og Top Shelf-bildene. Bakgrunnslaget og Top Shelf må være uten
  gjennomsiktighet.

## Arkitektur
- `project.yml` (XcodeGen; prosjektet og Info.plist lages i bygget og ligger ikke i repoet): målet `Fyrlys`
  (bundle-id `no.fyrlys.tv`, http tillatt fordi leverandørene bruker det, `ITSAppUsesNonExemptEncryption` false) og
  `FyrlysUITests`.
- `Core/Sources/FyrlysCore/`: `Models.swift` (`ChannelCategory`, `Channel`, `Program`, `Account`, `Login` med
  `normalize`, `id` = `stableHash(server|bruker)` uten passordet, `nowAndNext`, `cleanPrograms`; `Channel.hasEpg` fra
  `epg_channel_id` (egen `init(from:)`, så lister lagret uten den leses), `wantsEpg` = har EPG og er ikke eventkanal),
  `Xtream.swift` (`XtreamClient`: player_api.php, `liveURL` = `/live/<bruker>/<passord>/<id>.m3u8`, `redact`, løse
  typer fra leverandøren, EPG i base64; `Fetch` byttes ut i testene), `ChannelIndex.swift` (oppslagene for en liste:
  `byId`, `byCategory`, kategoriene med kanaler, `channels(favoring:)` = favorittkategoriene først, `search(_:favoring:
  limit:)` med navnene i små bokstaver ferdig, `hasSameLists`; lages i bakgrunnen, 25 000 kanaler ≈ 50 ms på Linux),
  `Store.swift` (`Library`: favoritter, favorittkategorier (`moveFavoriteCategory` bytter med naboen som vises, som i
  Windows-appen) og sist sett per innlogging, i minnet og skrevet til UserDefaults ved endring; `search`),
  `ListCache.swift` (kategoriene og kanalene på disk), `Guide.swift` (`GuideTime`: seks timer fra halvtimen før denne),
  `Names.swift` (`nameParts` (regex bare når navnet begynner med et siffer), `logoText` = tre første tegn som i
  Windows-appen, `initials`, `hhmm`), `L10n.swift`.
- `App/`: `AppModel` (@Observable: innlogging i nøkkelringen (`Keychain.swift`), `index` (`ChannelIndex`; lista fra
  disk leses i bakgrunnen før `phase = .ready`, den hentede byttes bare inn når den er endret), `allChannels`
  (favorittkategoriene først), `generation` så svar for en tidligere innlogging ikke brukes, favoritter,
  favorittkategorier og sist sett via `libraryVersion`) og `ProgramStore` (ikke observerbar selv: én `ChannelPrograms`
  per kanal, så bare kortet for kanalen tegnes på nytt; 150 ms før henting, høyst fire om gangen, nyeste først, fem
  minutter, tomt svar huskes, feil prøves igjen; ikke for `!wantsEpg`). `RootView` → `LoginView` eller `HomeView`
  (TabView: TV, TV-guide, Søk, Innstillinger; valgt hylle og søket står i HomeView; spilleren som `fullScreenCover`).
  `ChannelsView` (sidemeny 340 pt: Alle kanaler, Favoritter, Sist sett med ikoner, så «Dine kategorier» og «Alle
  kategorier», eller «Kategorier» med et hint når ingen er lagt øverst; hold inne på en kategori = «Legg øverst» /
  «Flytt opp» / «Flytt ned» / «Fjern fra toppen»; valg ved trykk, ikke ved fokus; `.clipped()` så rullelistene ikke går
  inn under fanelinja; `hidesScrollIndex()` i `ScrollIndex.swift` skrur av hurtigrullingen (`indexDisplayMode`), som
  la seg over tallene og tok fokus), `ChannelGrid` (adaptiv, minst 320 pt: fire kolonner ved siden av sidemenyen) med
  `ChannelCard` (96 pt høyt som Windows-kortet: `ChannelLogo`, klokkeslett i gult, navnet, kampen eller det som går nå
  (`NowPlaying`, `.everyMinute`), nummeret og stjernen; `CardStyle` med lyseblå kant `Theme.focus` og 1,05 i fokus;
  hold inne = favoritt), `GuideView` (6 timer, 4 pt/min, rader 66 pt, så det får plass uten vannrett rulling; fokus
  settes i `GuideSelection`, som bare `GuideHeader` leser, så guiden ikke tegnes på nytt ved hvert steg; egen
  `GuideCellStyle` med `@Environment(\.isFocused)`), `SearchView` (`.searchable`, favorittkategoriene først),
  `SettingsView`, `PlayerView` (`PlayerModel` med AVPlayer, User-Agent som VLC, nye forsøk tre i
  minuttet, så forklaring: alle tilkoblinger i bruk, HTTP-koden fra leverandøren eller AVPlayers melding;
  `AVPlayerViewController` med neste/forrige/favoritt i `transportBarCustomMenuItems` og kanallista i
  `customInfoViewControllers`; programinfo i `externalMetadata`). `Images.swift` (logoer med eget mellomlager,
  `ChannelTile`), `FyrlysMark.swift` (fyret tegnet i Canvas), `Theme.swift` («Fyrlys om natta»).
- `.github/workflows/build.yml`: kjernen på Linux; appen på `macos-15` med høyeste Xcode, XcodeGen, simulator fra
  `tools/simulator.py` (laster ned tvOS-plattformen om den mangler), falsk leverandør, `xcodebuild test`,
  skjermbildene ut med `tools/screenshots.py` (`xcresulttool export attachments`) og inn i grenen `skjermbilder`.
- **TestFlight** (jobbene `oppsett` og `testflight`, bare på main og når hemmelighetene `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8` og `APPLE_TEAM_ID` finnes; Admin-nøkkel laget av eieren): `tools/asc.py check` (nøkkelen, app-id-en
  `no.fyrlys.tv`, appen i App Store Connect), arkiv uten signering (`CODE_SIGNING_ALLOWED=NO`: å signere for en
  Apple TV krever en utviklerprofil, og den krever en registrert enhet), `tools/adhoc_sign.sh` (ad hoc med
  application-identifier og team), `asc.py prepare` (distribusjonssertifikat og `TVOS_APP_STORE`-profil for
  kjøringen gjennom REST-API-et, JWT med openssl, bare standardbiblioteket; egen nøkkelring), `xcodebuild
  -exportArchive` med `destination upload` og API-nøkkelen (laster opp selv), `asc.py wait <byggnummer>` (feiler hvis
  bygget ikke dukker opp i App Store Connect, eller blir INVALID), og `asc.py cleanup` (sletter profilen og trekker
  tilbake sertifikatet; eieren får en e-post om det for hvert bygg). Prøvd og forlatt 31.10: Apples skysignering
  (`-allowProvisioningUpdates` med API-nøkkelen) eksporterte uten feil, men App Store Connect avviste bygget
  («Invalid Signature … Fyrlys.app/Fyrlys»); med `altool --upload-app` forsvant byggene stille (bygg 3 og 4).
  `.github/workflows/status.yml` (startes for hånd: `gh api -X POST
  repos/ungerdas/fyrlys-tv/actions/workflows/status.yml/dispatches -f ref=main`) viser de siste byggene og
  testgruppene som merknad (`asc.py builds`). `gh workflow run` virker ikke herfra (GraphQL er stengt).
  Offentlig repo: loggene og artefaktene er synlige for alle, så ingenting hemmelig skrives ut.

## Status
- 31.10.2026: v0.1.0 (TV, guide, søk, innstillinger, spiller), alle UI-testene grønne i simulatoren, lastet opp til
  TestFlight (eieren registrerte `no.fyrlys.tv`, laget appen i App Store Connect, la inn hemmelighetene og laget den
  interne testgruppen). 0.1.1 (bygg 5) er den første som kom fram (VALID, IN_BETA_TESTING); 0.1.1 rettet at
  TV-siden hoppet til Favoritter ved første favoritt. Ikke prøvd på ekte Apple TV ennå, heller ikke ekte strømmer
  fra leverandøren hans (simulatoren spiller Apples eksempelstrøm).
- 31.10.2026: 0.1.1 installert fra TestFlight på hans Apple TV 4K (virker), med leverandøren hans: 25 153 kanaler.
  Treg start og hakking, og han syntes den var «så zoomet inn» og ville ha den så lik Windows-appen som mulig, med
  favorittkategorier («land») han velger rekkefølgen på; bilder viste sidemenyen rulle inn under fanelinja og
  hurtigrullingen oppå tallene. 0.1.2 (bygg 6, VALID i TestFlight 31.10) retter det (se CHANGELOG); i simulatoren
  med 25 000 kanaler kom første kort etter 6,6 s uten lista fra sist og 4,7 s med (med oppstarten). En topplinje som i
  Windows-appen ble skrevet, men forkastet: han vil beholde fanelinja til Apple TV.
- Åpent (31.10): 0.1.2 er ikke prøvd på Apple TV-en hans ennå (fart med 25 000 kanaler, de nye kortene, «Dine
  kategorier», at ingenting går inn under fanelinja). «Hjem» (startsiden i Windows-appen) finnes ikke i Apple TV-appen.
  Han får en e-post «Your Certificate Has Been Revoked» for hvert bygg (fra `asc.py cleanup`); anbefalt 31.10 i stedet
  for p12-forslaget: bare en privat nøkkel som hemmelighet `DIST_KEY` (`openssl genrsa -out fyrlys-dist.key 2048`), så
  lager `asc.py prepare` sertifikatet med den første gang og finner det igjen hos Apple (lik offentlig nøkkel), og
  `cleanup` sletter bare profilen; uten hemmeligheten som i dag. Ikke besvart, ikke laget.
- Senere (avtalt med eieren: «TV først»): filmer og serier, TV-arkiv, flere innlogginger.
