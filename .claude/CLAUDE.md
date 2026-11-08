# Fyrlys for Apple TV, iPhone og iPad – arbeidsnotater for Claude

Egen app for Apple TV (tvOS 17+) og iPhone/iPad (iOS 17+), Swift/SwiftUI med AVPlayer, i tillegg til Fyrlys for Windows
(eget repo). Apple TV, iPhone og iPad er **én app** i App Store Connect og TestFlight (samme bundle-id, eierens valg
31.10). Logger inn med Xtream Codes og henter alt rett fra leverandøren. Repoet er **offentlig**: hold appen, koden, testene,
commit-meldingene og disse notatene fri for navn, hjemmenett, maskinnavn, leverandør, brukernavn, hemmeligheter og
e-postadresser (eksempeladresser som iptv.example.com og 192.168.1.10 er greit; unntaket er NRK-adressene i
`Core/Sources/FyrlysCore/Streams.swift`, bygget inn etter eierens ønske 1.11.2026). Testene bruker bare den falske
leverandøren i `tools/fake_xtream.py`, med oppdiktede kanaler. `README.md` er forsiden på GitHub, skrevet for brukere.

## Arbeidsmåte
- Svar alltid på **norsk**. Commit-meldinger på norsk med prefikset `Fyrlys:`. Push rett til `main`.
- **Xcode kan ikke kjøres i Claude-økta** (ingen Mac). Kjernen (`Core/`, bare Foundation) testes her med Swift for
  Linux: `swift test --package-path Core` (Swift 6.2 ligger i scratchpad-mappen til økta, `swift/usr/bin`, og må
  lastes ned på nytt i en ny økt: swift.org-tarball for Ubuntu 24.04; kjør `swift` fra en mappe som finnes: er
  arbeidsmappen slettet, krasjer swift-driveren med «Illegal instruction»). Appen bygges og testes av GitHub Actions på
  macOS: `gh run list --repo ungerdas/fyrlys-tv`, `gh run watch <id> --repo ungerdas/fyrlys-tv`. Ved feil legger
  workflowen feilene og slutten av loggen som merknad: `gh api repos/ungerdas/fyrlys-tv/check-runs/<jobb-id>/annotations`
  (jobb-id fra `gh run view <id> --json jobs`). Hele loggen for en jobb kan hentes med `gh api
  repos/ungerdas/fyrlys-tv/actions/jobs/<jobb-id>/logs` (virket 3.11.2026; artefaktene ikke prøvd).
- **På eierens Mac (fra 7.11.2026)**: eieren har nå en Mac med Xcode 26.3 (Intel, macOS Sequoia; 26.3 er den siste
  Xcode for Sequoia) og vil kjøre Claude Code der. Finnes `xcodebuild` i økta, bygg og test lokalt i stedet for å vente
  på GitHub Actions (en runde der tar 45–60 min, og noen ganger får bygget ingen Mac). Byggene til TestFlight går
  fortsatt via GitHub: sertifikatet og hemmelighetene ligger der, og når Apple krever en nyere SDK, kan ikke Mac-en lage
  dem. Oppsettet som i `.github/workflows/build.yml`: `brew install xcodegen`, `tools/vlckit.sh tvOS iOS` (VLCKit til
  `Vendor/`), `xcodegen generate` (→ `Fyrlys.xcodeproj`, skjemaene `Fyrlys` for tvOS og `FyrlysMobil` for iPhone/iPad);
  de falske serverne `python3 tools/fake_xtream.py --port 8899` og `python3 tools/fake_plex.py --port 8897` (fartstesten
  også `--port 8898 --kanaler 25000 --kategorier 450`); én test: `TEST_RUNNER_FYRLYS_TEST_SERVER=http://127.0.0.1:8899
  TEST_RUNNER_FYRLYS_TEST_PLEX=http://127.0.0.1:8897 xcodebuild test -project Fyrlys.xcodeproj -scheme Fyrlys
  -destination 'platform=tvOS Simulator,name=<fra xcrun simctl list devices>'
  -only-testing:FyrlysUITests/FyrlysUITests/test17Plex` (iOS: `-scheme FyrlysMobil`,
  `FyrlysMobilUITests/FyrlysMobilUITests/…`); skjermbilde av simulatoren: `xcrun simctl io booted screenshot <fil>.png`
  (se på det med Read). Ikke gjort ennå: kjøre fra Xcode på hans Apple TV og iPhone. Det krever teamet
  (`DEVELOPMENT_TEAM` er tom i `project.yml`; legg det i en lokal fil som ikke committes) og rettighetene som
  `tools/adhoc_sign.sh` gir TestFlight-byggene (iCloud-nøkkelverdiene, nøkkelring-gruppene for Top Shelf); uten dem
  virker appen, men ikke iCloud-delingen og Top Shelf.
  **Satt opp 7.11.2026**: Xcode ligger i `~/Downloads/Xcode.app` og er ikke valgt med xcode-select (det krever sudo),
  så alle kommandoene trenger `export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer`. Homebrew finnes ikke
  (støtter ikke Intel lenger); XcodeGen 2.44.1 ligger i `~/.local/xcodegen/bin/xcodegen` (fra GitHub-utgivelsen),
  og `gh` 2.103.3 i `~/.local/gh/bin/gh` (logget inn, også for `git push`).
  VLCKit ligger i `Vendor/`. Simulatorer: iOS 26.3 og tvOS 26.2 («Apple TV 4K (3rd generation)», «iPhone 17 Pro
  Max», iPadene). Bruk `-derivedDataPath build/DerivedData`. Første bygg + én UI-test tok rundt 5 min for tvOS og
  10 min for iPhone; første iPhone-test kan feile med «Timed out waiting for AX loaded notification» mens
  simulatoren starter (bare kjør igjen). `swift test --package-path Core` virker også her (99 tester). Hans ekte innlogginger, Plex og adresser brukes bare på
  enhetene, aldri i repoet, testene, loggene som pushes eller commit-meldingene.
- **Skjermbilder**: UI-testene (`UITests/FyrlysUITests.swift`) tar bilder i simulatoren, og workflowen legger dem i
  grenen `skjermbilder` (overskrives hver gang); iPhone og iPad (`UITestsMobil/FyrlysMobilUITests.swift`, «NN-iphone-…»
  og «NN-ipad-…») i grenen `skjermbilder-mobil`. Den grunne klonen trenger en refspec:
  `git fetch --depth 1 origin skjermbilder:refs/remotes/origin/skjermbilder`. Hent med `git fetch origin skjermbilder` og
  `git show origin/skjermbilder:02-tv.png > …`, og se på dem med Read. Bilder XCTest tok ved feil heter `feil-*.png`.
- Appen i testmodus: miljøvariablene `FYRLYS_TEST_SERVER` (falsk leverandør, test/test, ingen nøkkelring, egne
  innstillinger og kanalliste som tømmes, unntatt med `FYRLYS_TEST_KEEP`), `FYRLYS_TEST_SCREEN` (login, tv, guide,
  search, settings, player, player-error = kanal 90 som svarer 404; på iPhone også all = «Alle kanaler» og category =
  Sport åpnet), `FYRLYS_TEST_LANG` og `FYRLYS_TEST_THEME` (light/dark; UI-testene for iPhone/iPad bruker dark, ellers
  ville simulatoren gitt lys modus) (`App/TestSupport.swift`).
  Elementene testene finner, har `accessibilityIdentifier` (`kanal-<id>`, `hylle-…`, `favoritt-<id>`, `seksjon-dine`/
  `-alle`/`-kategorier`, `seksjon-favoritter`/`-sist` (radene øverst), `lagt-overst`, `spiller` (spilleren står
  framme; kortene bak den finnes i elementtreet også da), `spiller-feil` (på Apple TV samme beholder som `spiller`, id-en
  byttes: en beholder med id inne i en annen med id ble borte), `guide`, `innstillinger`). `focus(app, mål)`
  i UI-testene flytter fokus dit uansett hvor det står (fanelinja, sidemenyen, kortene). På iPhone/iPad også
  `kategori-velger`, `stjerne-<kategori>`, `stjerne-kanal-<id>`, `lukk-spiller`, `neste-kanal`, `guide-velger`,
  `til-naa`; bare iPhone: `sok`, `tema`, `konto`, `tilbake`, `kategori-stjerne`, flisene `hylle-…`. Testen av farten (`test11StorListe`) bruker en stor falsk leverandør
  (`fake_xtream.py --kanaler 25000 --kategorier 450` på port 8898, `FYRLYS_TEST_SERVER_STOR`); tidene står som merknad
  «ytelse» på bygget (simulatoren på en Mac er raskere enn en Apple TV).
- **Utseendet følger Fyrlys på Windows** (eieren 31.10: «så lik som mulig windows appen»), men **fanelinja til Apple TV
  beholdes** (eieren: «jeg liker fanelinja til apple! så behold den»). Fasit for mål og farger er Windows-repoet
  (`ungerdas/fyrlys`, offentlig, kan klones for lesing: `lib/ui/channel_card.dart`, `home_page.dart` (`_sidebar`,
  `_categoryTile`), `theme.dart`), skalert opp for TV (rundt 1,4 ganger pikslene der). Ingen endringer i det repoet
  herfra. **iPhone følger nettversjonen** (Docker-versjonen av Fyrlys på telefon; eieren 31.10 med et bilde av den:
  «Ønsker iPhone appen i denne UI!»): fasit er `app/web/fyrlys.css` (reglene under `@media (max-width: 860px)`,
  `.chan`, `.ctile`, `.mhead`, `.tabs`, `.top`, `.gwrap`) og `js/list.js`/`guide.js`/`core.js` (`tintLogo`) i eierens
  private repo for den; det kan legges til økta for lesing. Ingenting derfra (adresser, navn) skal hit.
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
- `project.yml` (XcodeGen; prosjektet og Info.plist lages i bygget og ligger ikke i repoet): målene `Fyrlys` (tvOS) og
  `FyrlysMobil` (iPhone og iPad, `TARGETED_DEVICE_FAMILY` 1,2), begge med bundle-id `no.fyrlys.tv` og produktnavn
  Fyrlys, http tillatt fordi leverandørene bruker det, `ITSAppUsesNonExemptEncryption` false; iOS i tillegg alle
  retninger på iPad (kreves for delt skjerm), `UIBackgroundModes` audio (bilde-i-bilde) og ikonet i
  `App/Mobil.xcassets` (1024 × 1024 uten alfa, `tools/make_icons.py --ios`; tvOS bruker `Assets.xcassets`, og hvert
  mål utelater det andres). `FyrlysUITests` og `FyrlysMobilUITests`, ett skjema per plattform.
- **Felles kode med `#if os(tvOS)`/`#if os(iOS)`**: begge målene tar med hele `App/`. Bare tvOS: `GuideView.swift`,
  `SettingsView.swift`, `PlayerView.swift` (AVPlayerViewController med `transportBarCustomMenuItems`/
  `customInfoViewControllers`), hurtigrullingen i `ScrollIndex.swift`. Bare iOS: `GuideViewMobil.swift` (som nettsiden:
  valg av favoritter/alle/kategori lagret som `guide`, «Til nå» via `scrollPosition(id:)` på halvtimene, tidslinja
  øverst flyttes etter sporene via en preference og `GuideScroll`, sporene har fast bredde (rammen minus
  kanalkolonnen), og tidslinja `frame(minWidth: 0, maxWidth: .infinity)`: med bare `maxWidth` blir en ramme aldri
  smalere enn innholdet (seks timer), så hele guiden ble bredere enn skjermen og radene havnet utenfor i 0.1.6;
  kanalkolonnen er lat og henter programinfoen,
  info-ark med «Se kanalen»), `SettingsViewMobil.swift` (Form, bare iPad; med lys/mørk), `PlayerViewMobil.swift` (bildet
  øverst med bilde-i-bilde, panel og kanalliste under; liggende iPhone bare bildet; iPad på tvers lista ved siden av;
  alltid mørk; dra bildet ned for å lukke: en `UIPanGestureRecognizer` (`DragDown`) på AVPlayerViewController-visningen
  som bare begynner nedover og virker sammen med AVKit, `offset` på hele spilleren og `presentationBackground(.clear)`
  på `fullScreenCover`, så TV-siden synes under). iPhone (alltid på iPhone, også på tvers, og på en smal iPad: `usesPhoneLayout` i `HomeView` og `VODTab`): `PhoneHome.swift` (topplinja med
  fyret, sol/måne og Konto som popover, `TabView` med TV og TV-guide og ikonene tegnet etter nettsiden, `SwipeBackEnabler`
  så sveip tilbake virker med skjult navigasjonslinje), `PhoneTV.swift` (`NavigationStack` med stien i HomeView:
  forsiden med søk, «Nå på favorittene», «Sist sett», flisene; `PhoneShelfPage` med tilbake, pille som åpner
  `CategoryPicker` og stjerne), `BigCard.swift` (de store kortene, `logoTint` = `tintLogo` fra nettsiden, regnet ut i
  `Images.load` og husket per adresse). Lys og mørk: fargene i `Theme` er dynamiske på iOS (`tone`), valget i
  innstillingene som `tema` (tom = som enheten). Felles:
  `PlayerModel.swift`, `AppModel`, kortene og TV-siden, med mål i `Metrics` (`Theme.swift`; tvOS ≈ 1,4 × Windows,
  iOS som Windows) og `tvFocusSection()`. `focusSection`, `indexDisplayMode` og AVKits tvOS-kontroller finnes ikke på
  iOS.
- `Core/Sources/FyrlysCore/`: `Models.swift` (`ChannelCategory`, `Channel`, `Program`, `Account`, `Login` med
  `normalize`, `id` = `stableHash(server|bruker)` uten passordet, `nowAndNext`, `cleanPrograms`; `Channel.hasEpg` fra
  `epg_channel_id` (egen `init(from:)`, så lister lagret uten den leses), `wantsEpg` = har EPG og er ikke eventkanal),
  `Xtream.swift` (`XtreamClient`: player_api.php, `liveURL` = `/live/<bruker>/<passord>/<id>.m3u8`, `redact`, løse
  typer fra leverandøren, EPG i base64; `Fetch` byttes ut i testene), `ChannelIndex.swift` (oppslagene for en liste:
  `byId`, `byCategory`, kategoriene med kanaler, `channels(favoring:)` = favorittkategoriene først, `search(_:favoring:
  limit:)` med navnene i små bokstaver ferdig, `hasSameLists`; lages i bakgrunnen, 25 000 kanaler ≈ 50 ms på Linux),
  `Store.swift` (`Library`: favoritter, favorittkategorier (`moveFavoriteCategory` bytter med naboen som vises, som i
  Windows-appen) og sist sett per innlogging, i minnet og skrevet til lagringen ved endring, `reload()`; `mergeIds`;
  `search`),
  `ListCache.swift` (kategoriene og kanalene på disk), `Guide.swift` (`GuideTime`: seks timer fra halvtimen før denne),
  `Names.swift` (`nameParts` (regex bare når navnet begynner med et siffer), `logoText` = tre første tegn som i
  Windows-appen, `initials`, `hhmm`), `L10n.swift`.
- `App/`: `AppModel` (@Observable: innlogging i nøkkelringen (`Keychain.swift`), `index` (`ChannelIndex`; lista fra
  disk leses i bakgrunnen før `phase = .ready`, den hentede byttes bare inn når den er endret), `allChannels`
  (favorittkategoriene først), `generation` så svar for en tidligere innlogging ikke brukes, favoritter,
  favorittkategorier via `libraryVersion`, «sist sett» via `recentVersion`; `becameActive()` fra `scenePhase` i
  `RootView`: programinfo, `plex.reprobe()`, `refreshIfOld()` for filmer/serier, kanallista etter 3 t; en tom
  kanalliste fra leverandøren erstatter ikke den forrige) og `ProgramStore` (ikke observerbar selv: én
  `ChannelPrograms` per kanal, så bare kortet for kanalen tegnes på nytt; 150 ms før henting, høyst fire om gangen,
  nyeste først, fem minutter, tomt svar huskes; ikke for `!wantsEpg`; fra 0.1.23 telles visningene (`want`/`forget`,
  `visible`), og hvert minutt hentes de som vises på nytt når «nå» mangler, de er 30 min gamle eller feilet
  (`refreshVisible`); etter to feil på rad `loaded`, så «Ingen programinfo» vises). `RootView` → `LoginView` eller `HomeView`
  (TabView: TV, TV-guide, Søk, Innstillinger; valgt hylle og søket står i HomeView; spilleren som `fullScreenCover`).
  `ChannelsView` (sidemeny 340 pt: Alle kanaler, Favoritter, Sist sett med ikoner, så «Dine kategorier» og «Alle
  kategorier», eller «Kategorier» med et hint når ingen er lagt øverst; hold inne på en kategori = «Legg øverst» /
  «Flytt opp» / «Flytt ned» / «Fjern fra toppen»; valg ved trykk, ikke ved fokus; på Apple TV klippes rullelistene
  ikke under fanelinja (fra 0.1.8, se under), på iPad `.clipped()`; `hidesScrollIndex()` i `ScrollIndex.swift` skrur av
  hurtigrullingen (`indexDisplayMode`, via UIScrollView-en rundt), som la seg over tallene og tok fokus),
  `ChannelGrid` (bare iPad; adaptiv, minst 320 pt: fire kolonner ved siden av sidemenyen) med
  `ChannelCard` (96 pt høyt som Windows-kortet: `ChannelLogo`, klokkeslett i gult, navnet, kampen eller det som går nå
  (`NowPlaying`, `.everyMinute`), nummeret og stjernen; `CardStyle` med lyseblå kant `Theme.focus` og 1,05 i fokus;
  hold inne = favoritt), `GuideView` (6 timer, 4,2 pt/min, navn 300 pt, rader 66 pt, så det får plass uten vannrett rulling;
  fra 0.1.11 valget oppe til høyre (`Menu` `guide-velger`: favoritter, sist sett, alle, «Dine kategorier», undermeny
  «Alle kategorier»; lagret som `guide` som på iPhone; fokus
  settes i `GuideSelection`, som bare `GuideHeader` leser, så guiden ikke tegnes på nytt ved hvert steg; egen
  `GuideCellStyle` med `@Environment(\.isFocused)`), `SearchView` (`.searchable`, favorittkategoriene først),
  `SettingsView`, `PlayerView` (`PlayerModel` med AVPlayer, User-Agent som VLC, nye forsøk tre i
  minuttet (etter 2, 5, 10 s), så feilen med en gang og forklaringen etter (`explain`, høyst 8 s: alle tilkoblinger
  i bruk, HTTP-koden fra `errorLog()` eller et eget oppslag); fra 0.1.23 åpnes kanalen på nytt når
  `timeControlStatus` har ventet i 25 s, en egen strøm som feiler to ganger byttes med leverandørens (`providerOnly`),
  kanalbytte (`step`/`choose`) stopper den gamle med en gang og åpner etter 300 ms, programinfoen i kontrollene
  byttes når programmet slutter, og `inFullScreen` (AVKits fullskjerm på iOS) hindrer at `onDisappear` stopper;
  `AVPlayerViewController` med neste/forrige/favoritt i `transportBarCustomMenuItems` og kanallista i
  `customInfoViewControllers`; programinfo i `externalMetadata`; fra 0.1.11 kanalbytte med opp/ned via AVKits
  `skipToNextChannel`/`skipToPreviousChannel` i `AVPlayerViewControllerDelegate` (koordinatoren) med `ChannelPreview`
  som `next/previousChannelInterstitialViewController`). `Images.swift` (logoer med eget mellomlager,
  `ChannelTile`), `FyrlysMark.swift` (fyret tegnet i Canvas), `Theme.swift` («Fyrlys om natta»).
- **Apple TV fra 0.1.8: sidemenyen og de store kortene** (eieren 1.11 om 0.1.7: «rart med den toppen», «uoversiktlig»;
  valgte sidemeny + mindre kort): `ChannelsView` med sidemenyen som før og `TVChannelPanel` (`TVHome.swift`) til
  høyre: i «Alle kanaler» (standard på Apple TV) «Nå på favorittene» og «Sist sett» som rader (`TVStrip`,
  `scrollClipDisabled` + `StripClip`: kortet med fokus kuttes ikke, men kortene rulles ikke inn over sidemenyen), eller
  tipset når begge er tomme, så tittel, antall og `BigCardGrid` med `Metrics.bigColumns` like brede kolonner (fire fra
  0.1.10; eieren syntes seks (0.1.8) og fem (0.1.9) var for små; `.flexible()`; kortene i radene har
  `containerRelativeFrame(count:)` med samme antall, så de er like brede); søket bruker `BigCardGrid(columns: nil)` (adaptiv, minst `bigGridMin`). Ingen `GeometryReader` rundt rullelista (den skal nå toppen av den trygge sonen). Toppen: TV-siden
  begynner under fanelinja, men kortene klippes ikke der (0.1.2–0.1.7 hadde `.clipped()`, og når fanelinja gled
  bort, ble det en tom stripe med kortene kuttet under). Over sidemenyen står Fyrlys-merket (`TVBrand`: `FyrlysMark`
  og «Fyrlys», som topplinja på iPhone; eieren 1.11: «Savner Fyrlys logo») som `overlay` med
  `alignmentGuide(.top)`, så bunnen står `Metrics.brandGap` over sidemenyen, på linje med fanelinja i simulatoren;
  sidemenyen er `.clipped()` under det. Fanelinja følger en rulleliste alene på siden av seg selv
  (0.1.7), men ingen av to ved siden av hverandre: i bygg 21 sto den fast over kortene (`18-…-rullet`). Derfor
  `movesTabBar()` i `ScrollIndex.swift`: UIScrollView-en rundt kortene blir `tabBarObservedScrollView` for fanen
  (barnet av UITabBarController, funnet via responder-kjeden), så UIKit flytter fanelinja i takt med kortene. `BigCard.swift` er felles: på Apple TV er hele kortet én
  knapp (`BigCardStyle`, lyseblå kant og 1,06 i fokus), stjernen bare et merke (`favoritt-<id>`). Målene i `Metrics`
  (`bigColumns`, `big…`, `row…`). 0.1.7 hadde en forside med fliser og egne sider per kategori (`TVChannels`,
  `TVTiles`, `TVShelfPage`); de er tatt bort. UI-testene for Apple TV flytter fokus mot målet med rammene (`focus`);
  `test11StorListe` måler kortene og sidemenyen og tar bilder av toppen (`17-…-sidemeny`, `18-…-rullet`,
  `19-…-fanelinja` etter Menu). Fra 0.1.25 ruller lista helt opp når den øverste raden får fokus (`onFocusGained` i
  `ScrollIndex.swift`, `BigChannelCard.onFocus`, `ScrollViewReader` med id-en `toppen` i `TVChannelPanel`,
  `VODHomeView` og `PosterGrid`): fokusmotoren rullet bare så langt at kortet syntes, så overskriften over (som ikke
  kan få fokus) og fanelinja ble stående halvveis ute over kanten (eieren 4.11 med bilde: «litt for høy»).
  `PosterGrid` har fem faste kolonner på Apple TV (`Metrics.posterColumns`, det det var plass til), så den øverste
  raden er kjent. `test21Fanelinja` (bildene `39-…`, `40-…`) sjekker at fanelinja står der den sto ved start.
- **iCloud fra 0.1.12**: `CloudStore` (`App/CloudStore.swift`) er lagringen til `Library` utenom testene: favorittene
  og favorittkategoriene (nøklene `favorites@…`/`favoriteCategories@…`, per innlogging) i `NSUbiquitousKeyValueStore`
  og UserDefaults, «sist sett» bare lokalt. Første gang per nøkkel og ved `InitialSyncChange` flettes det enheten hadde
  inn (`mergeIds`, merket `icloud-flettet@…`), ellers vinner iCloud; endringer fra andre enheter → `Library.reload()` i
  `AppModel.libraryChangedElsewhere`. `asc.py check` slår på ICLOUD for app-id-en (`ensure_capability`,
  `POST /v1/bundleIdCapabilities`) og setter `ICLOUD_KVS=1` i `GITHUB_ENV`; da tar `adhoc_sign.sh` med
  `com.apple.developer.ubiquity-kvstore-identifier` = `<team>.no.fyrlys.tv` (samme for tvOS og iOS, så de deler).
- **Filmer og serier fra 0.1.12**: `Core/.../VOD.swift` (`VODKind`, `VODItem`, `Episode`, `Season`, `VODDetails`,
  `vodCategories`/`vodItems` (per kategori)/`vodDetails`, `movieURL`/`episodeURL` (`/movie|series/<bruker>/<passord>/
  <id>.<ext>`), `playableExtensions`: filtypen leverandøren oppgir, eller mp4 og m3u8 når den mangler; fra 0.1.15
  `playAttempts` (se VLC under)). `App/VODModel.swift` (`AppModel.movies`/`.series`, kategoriene første gang
  fanen vises, lista per kategori når den velges). `App/VODViews.swift`: `VODTab` (fanene Filmer og Serier; sidemeny
  med `vodkat-<id>` på Apple TV og iPad, meny `vod-kategori` på iPhone; `NavigationStack` med `VODDetailView`),
  plakater `vod-<id>` (`.card` på Apple TV), siden `vod-side` med `spill-av`/`fra-start` eller `sesong-<n>` og
  `episode-<id>`, `VODPlayerView` (`vod-spiller`/`vod-feil`; fullskjerm på Apple TV, ark på iPhone/iPad) med
  `VODPlayerModel`: prøver adressene etter tur, begynner der du slapp, lagrer hvor langt (`AppModel.progress`, nøkkel
  `sett@<innlogging>@<film|episode>`, hvert 10. s og ved lukking; glemmes nær slutten); fra 0.1.23 brudd etter at
  filmen har kommet i gang (`position` > 5 s): samme adresse fra `resumeAt` etter 2 s, to ganger (`breaks`), så
  feilen med `vod-igjen` («Prøv igjen», `retry()`); VLC regner slutt mer enn et minutt før lengden som brudd, og tar
  pause når appen går i bakgrunnen. Falsk leverandør: filmene
  501–503 (502 er mkv: `tools/testdata/stormnatt.mkv`, oppdiktet, 30 s, to lydspor og norske undertekster, med Range)
  og serien 9001; testskjermene `movies`, `series`, `mkv` (502 i VLC) og `mkv-feil` (504.avi, som svarer 404).
- **TV-arkiv fra 0.1.12** (som Fyrlys for Windows, `lib/core/xtream_source.dart`): `Core/.../Archive.swift`
  (`parseArchive` fra `get_simple_data_table` med `has_archive`, de siste `archiveDays` dagene; `serverClockOffset`
  fra `server_info` (`time_now` mot `timestamp_now`, rundet til kvarter); `archiveOffset` (enhetens sone med
  sommertid når serveren går likt, ellers serverens); `xtreamTime` «YYYY-MM-DD:HH-MM»; `archiveURLs` =
  `/timeshift/<bruker>/<passord>/<minutter>/<start>/<id>.m3u8` (+ `.ts`), på minuttet). `App/ArchiveView.swift`:
  dagene og programmene (nyeste først), spilles i `VODPlayerView`; åpnes med «TV-arkiv» i hurtigmenyen på kortene
  (`AppModel.archiveChannel`, vist i `HomeView`; testskjermen `archive` = kanal 1). `AppModel.serverClock()` spør én
  gang per innlogging.
- **Flere innlogginger fra 0.1.12**: `Keychain.saveAll/loadAll` (kontoen `logins`, en JSON-liste med den som er i bruk
  først; den gamle `login` flyttes over), `AppModel.logins`, `switchTo`, `remove`, `addingLogin` (RootView viser
  `LoginView` med `avbryt-innlogging`), `signOut` går til den neste. Innstillinger (Apple TV, iPad) og Konto (iPhone):
  «Bytt til …», «Legg til innlogging» (`legg-til-innlogging`), fjern med hurtigmeny/sveip.
- **Top Shelf fra 0.1.13**: målet `FyrlysTopShelf` (tvOS-utvidelse `com.apple.tv-top-shelf`, app-id
  `no.fyrlys.tv.topshelf`, `TopShelf/ContentProvider.swift`) viser favorittene (`TVTopShelfSectionedContent`, logo,
  navn; trykk = `fyrlys://kanal/<id>` → `AppModel.pendingPlay` → `HomeView` spiller). Favorittene deles i en felles
  nøkkelring-gruppe `<team>.no.fyrlys.tv.shared` (`TopShelf/SharedFavorites.swift`, også i app-målet; prefikset
  finnes fra et element lagret i standardgruppen), skrevet av `AppModel.shareFavorites()` ved endringer.
  `adhoc_sign.sh` signerer utvidelsen først (egen app-id og gruppen) og gir appen `keychain-access-groups` (egen
  gruppe først, så innloggingene blir der de var); `asc.py prepare` registrerer app-id-en og lager en profil til for
  utvidelsen (`EXTENSIONS`), og `ExportOptions-tvOS.plist` har begge.
- **0.1.14**: «Se fra start»: `AppModel.archivePlay(channel, program)` → `VODPlay.archive`; `AppModel.replay` vises av
  `HomeView` (fullskjerm/ark). Fra spilleren for direktesendingen (`PlayerModel.startOver`, `canStartOver`; Apple TV i
  `transportBarCustomMenuItems`, iPhone/iPad `fra-start-live`) og fra infoarket i iPhone-guiden (`se-fra-start`) går
  den via `pendingReplay`: direktesendingen stoppes og lukkes (`closeRequested`), og `showPendingReplay()` i
  `onDismiss` viser den (én tilkobling om gangen). Apple TV-guiden: hurtigmeny på programmer (se fra start) og på
  kanalen (TV-arkiv). «Fortsett å se»: `AppModel.continueItems/rememberContinue/forgetContinue` (JSON i
  `fortsett@<innlogging>`, satt av `VODPlayerModel.save`), raden øverst i `PosterGrid` (`fortsett-<id>`). («Åpne i
  VLC» på iOS fra 0.1.14 er tatt bort i 0.1.15.)
- **VLC fra 0.1.15** (eieren: «andre klienter klarer jo å spille av filmer og serier»): VLCKit 3.7.2 (LGPL 2.1, de
  ferdige rammeverkene fra VideoLAN, dynamiske) hentes av `tools/vlckit.sh` til `Vendor/` (ikke i repoet; sjekksum,
  armv7/i386 tatt bort med lipo, nytt xcframework uten dSYM) og ligger som `framework`-avhengighet med embed i
  `project.yml` (`TVVLCKit` for `Fyrlys`, `MobileVLCKit` for `FyrlysMobil`); i bygget med `actions/cache` (nøkkel =
  hashen av skriptet) og `build/vlckit.log` i feilmerknadene. MPVKit ble valgt bort (forfatteren skriver at den ikke
  er for produksjon; Metal bare som lapp), KSPlayer er GPL. `playAttempts` (Core): Apples avspiller for
  mp4/m4v/mov/m3u8, ellers VLC; er ingen av adressene for VLC, prøves den første med VLC til slutt (TV-arkivet:
  m3u8 med AVPlayer, så .ts med VLC). `App/VLCPlayer.swift`: `VLCEngine` (@Observable; `VLCMediaPlayer` med
  `drawable` = `surface` (`VLCSurfaceView`: VLC sin visning inni får alltid samme ramme), hendelsene via
  `VLCEvents` til hovedtråden; valg per media: `:http-user-agent`,
  `:network-caching=3000`, `:start-time`, `:sub-language=nor,…` når appen er på norsk; fra 0.1.17
  `VLCMediaPlayer(options: subtitleStyle())`: undertekstene i Apple sin stil fra MediaAccessibility
  (`MACaptionAppearance…`: skrift (systemskriften → «Helvetica Neue»), relativ størrelse → `--freetype-rel-fontsize`
  18/størrelse, farge/bakgrunn/opasitet → `--freetype-color`/`-background-color`/`-background-opacity`, kant →
  `--freetype-outline-thickness`/`-shadow-opacity`; eieren: «vil ha teksten i orginal Apple stil»); feil = `.error`, eller
  `.ended`/`.stopped` før tiden har gått, eller ingen tid etter 45 s; skrur av skjermsparer/lås mens den spiller) og
  `VLCPlayerScreen` (egne kontroller: Apple TV en usynlig knapp over hele skjermen med fokus, venstre/høyre spoler 10
  s (30/60 ved flere trykk på rad, hoppet etter 0,7 s), ned = menyene `vod-lyd`/`vod-tekst`, Menu skjuler og så
  lukker; iOS trykk for kontrollene, `lukk-vod`, ±10 s, `vod-pause`, Slider; tiden `vod-tid`; kontrollene skjules
  ikke i testene). `VODPlayerModel.vlc` velger visningen i `VODPlayerView`; `finished` lukker når VLC er ferdig.
  Testene `test15Mkv`/`test16MkvFeil` (Apple TV) og `test17Mkv` (iPhone og iPad). Ikke prøvd på ekte enheter ennå.
- **Plex fra 0.1.16** (eieren: «en Plex fane eller noe, som erstattet Filmer/Serier hvis man ville å koble til Plex.
  Gjerne litt som Plezy», så «Gjør noe med det»; Plezy er GPL/Flutter, bare inspirasjon): `Core/.../Plex.swift`
  (`PlexDevice` = X-Plex-hodene med en fast `clientId` per installasjon (`plex-klient` i innstillingene);
  `PlexAccountClient` mot plex.tv: `POST /api/v2/pins?strong=false` (fire tegn til plex.tv/link), `GET
  /api/v2/pins/<id>` til `authToken` kommer, `GET /api/v2/resources?includeHttps=1&includeRelay=1` (bare
  `provides` server, de du eier først); `PlexClient` mot serveren med `X-Plex-Token` i hodet: `reachable` prøver
  tilkoblingene samtidig og tar den beste som svarer på `/identity` (lokale, så utenfra, så relé), `libraries`
  (`/library/sections`, movie/show), `items` (`/library/sections/<n>/all?sort=addedAt:desc`), `details`
  (`/library/metadata/<id>`, serier + `/allLeaves`), `continueWatching` (`/hubs/continueWatching/items`, ellers
  `/library/onDeck`; episodene blir serien sin), `imageURL` (`/photo/:/transcode`, nøkkelen i adressen), `fileURL`
  (`/library/parts/…/file.<ext>?X-Plex-Token=`, spilles direkte; VLC for mkv), `timeline` (playing/paused/stopped,
  ms) og `scrobble`). `VODItem.source`/`Episode.source` = "plex" (nøklene for hvor langt: `plex:<ratingKey>`), og
  `fileKey`/`resume`/`watched`. `App/PlexModel.swift` (`AppModel.plex`: `Phase` off/linking(kode)/choosing/
  connecting/connected/failed, nøkkelen og serveren i nøkkelringen (`Keychain.savePlex`, konto `plex`) med adressen
  som svarte sist, `report` → timeline/scrobble). `VODModel` har en `VODBackend` (xtream, plex, waiting mens Plex
  kobler til, unavailable(feil)); `AppModel.refreshVOD()` ved innlogging, `refreshPlex()` når Plex endres
  (`onChange`) eller bibliotekene som vises, `VODTab` henter på nytt med `.task(id: model.version)`. (0.1.16–0.1.30
  viste Plex i fanene Filmer og Serier, valgt med `useForVOD`/`plex-filmer`/`vod-kilde`; fra 0.1.31 egen fane, se
  under.) Plex: «Fortsett å se» fra Plex (`continueRow`), hvor langt du har sett hentes ned fra Plex når
  siden åpnes (`syncProgress`) og sendes opp av `VODPlayerModel.save` (hvert 10. s, `stopped` ved lukking, `scrobble`
  én gang nær slutten); siden og raden hentes på nytt 1,5 s etter at spilleren er lukket. `App/PlexSettings.swift`:
  seksjonen i Innstillinger (Apple TV i en rulleliste nå, iPad i Form) og `PlexSheet` fra Konto på iPhone
  (`plex-innstillinger`); id-ene `koble-til-plex`, `plex-kode`, `plex-tilkoblet`, `koble-fra-plex`.
  Falsk Plex: `tools/fake_plex.py` (port 8897, `FYRLYS_TEST_PLEX`; koden FYRL gir nøkkelen tredje gang, serveren
  «Hjemmekino» med en lokal tilkobling som ikke svarer og en som gjør det, filmene 1001–1003, serien 2001), og
  testskjermene `plex`/`plex-series` (koblet til fra før) og `plex-link`; testene `test17Plex`/`test18PlexKobling`
  (Apple TV) og `test18Plex`/`test19PlexKobling` (iPhone og iPad). Ikke prøvd mot en ekte Plex-server ennå.
- **Hjem i Filmer og Serier fra 0.1.24** (eieren 3.11 med et bilde av en IPTV-app på iPhone: «Ønsker litt denne
  stilen på serier fanen»: «Continue watching» med bredbilder og framdrift, «Favorites», «Recently added» med «view
  all», søkefelt øverst): `App/VODHome.swift` (erstatter `PlexHome.swift`): `VODHomeView` for begge kildene, alltid
  først (`VODModel.home` står først i kategoriene når det finnes noen, også hos IPTV-leverandøren, og er valgt fra
  start): «Fortsett å se» (`ResumeCard`, 16:9 med `ResumeBar`, «S1 E3 · tittel»; `fortsett-<id>`; en episode spilles
  med en gang, en film åpner siden), «Favoritter» (`vodfav-<id>`), så radene fra Plex (`rad-…`, «Se alle»
  `se-alle-<hub>` → `VODRowPage` `vod-rad` med `alle-<id>`, når huben har `key` og `more`) eller kategoriene hos
  leverandøren som rader (`CategoryShelf`, hentes når raden vises, 20 plakater `vod-<id>`, «Se alle» `se-alle-<id>`
  velger kategorien). `VODShelf` (tittel, «Se alle», rad), `VODPosterLink` (plakat med hurtigmeny: favoritt),
  `FavoriteToggle`. Kjernen: `VODResume` (Codable: filmen/serien, `Episode` (nå Codable), `progress` 0–1, `image`),
  Plex `parseContinue` → `[VODResume]` (`grandparentArt`/`art`/`thumb` i 640×360, `viewOffset/duration`),
  `items(ids:)` (`/library/metadata/1,2`), `search` (`/hubs/search`, `parseSearch`), `rowItems` (huben sin `key`),
  `VODRow.key`/`more`; Xtream `allVODItems` (uten kategori) og `searchVOD`. «Fortsett å se» fra leverandøren lagres
  som `[VODResume]` (`fortsett@…`; den gamle `[VODItem]` leses fortsatt) av `VODPlayerModel.save` med episoden og
  bildet fra `VODPlay.episode`/`image` (ferdig episode: serien uten episode). Favorittene: `AppModel.vodFavorites/
  isVODFavorite/toggleVODFavorite`, JSON per linje i `vodFavorites@<innlogging>@<movies|series>` eller
  `vodFavorites@plex:<server>@…` (Plex uten plakaten; `VODModel.refreshFavorites` henter dem fra serveren), delt i
  iCloud (`CloudStore.shared`). Stjernen på siden: `vod-favoritt` (verktøylinja på iPhone/iPad, ved knappene på Apple
  TV). Søket (iPhone og iPad): `SearchField` (fra `PhoneTV.swift`, nå med `prompt`/`id`) `vod-sok` under menyen
  (iPad over siden), `VODSearchResults` (`sok-<id>`). Plakatene på iPhone/iPad: teksten under bildet (`PosterCard`;
  på Apple TV som før). Mål: `Metrics.rowPoster`, `resumeWidth`, `shelfTitle` …
- **Episoder og Plex i spilleren fra 0.1.26** (pakken «Plex og episoder» fra Windows-lista; hvordan Windows gjør det,
  står i `ungerdas/fyrlys`: `lib/ui/vod_player_page.dart`, `lib/core/plex/`): spilleren ligger i `App/VODPlayer.swift`
  (`VODPlay` med `seasons`, `VODPlayerModel`, `VODPlayerView`, `NativePlayer`, `SkipButton`, `UpNextCard`,
  `VODPlayerController` med `PlayerButtons`). Forrige og neste: `neighbours(of:in:)` (Core, `VOD.swift`: sesong for
  sesong uten sesong 0, spesialene for seg); sesongene følger med fra siden, ellers henter spilleren dem
  (`details(show)`). En annen episode får en ny `VODPlayerModel` i samme `VODPlayerView` (`switchTo` → `begin`;
  `.id(ObjectIdentifier(vlc))` på VLC-visningen og `.id(ObjectIdentifier(model))` på Apples, ellers sto det gamle
  bildet); `VODModel.play(_:show:app:image:seasons:)` lager det som spilles (hvor langt: det enheten vet, ellers det
  Plex vet, fra start når den er sett ferdig her: `finishedHere`; Hjem setter det Plex vet først). Ferdig (VLC `onEnd`,
  Apples `didPlayToEndTime`): «Neste: S1 E3 · …» (`neste-om`) i 3 s, så den neste, ellers lukkes spilleren (også med
  Apples avspiller nå). Knappene: Apple TV VLC `forrige-episode`/`neste-episode` under streken (ned), Apples avspiller
  i `transportBarCustomMenuItems`; iPhone/iPad VLC ved ±10 s; ikke i Apples avspiller på iPhone/iPad. Plex:
  `playInfo` (`/library/metadata/<id>?includeMarkers=1`, 6 s, før avspillingen begynner): markørene (`PlexMarker`,
  intro/credits, den siste rulleteksten er `final` når ingen er merket) og undertekstfilene (`PlexSubtitle`:
  `streamType` 3 med `key`, ikke vobsub, `<key>.<srt|vtt|sup|codec>?encoding=utf-8&X-Plex-Token=`). Knappen
  `hopp-over` («Hopp over introen», «Hopp over rulleteksten», «Neste episode» for rulleteksten til slutt med en etter:
  episoden meldes sett, `save(final:finished:)`): Apple TV VLC med fokus (`PillStyle`), Apples avspiller på Apple TV
  `contextualActions`, ellers nede til høyre. Undertekstfilene legges til i VLC når filmen er i gang
  (`addPlaybackSlave`), og `chosenSubtitle` (valgt i Plex, ellers norsk når fila ikke har norsk) velges når VLC ikke
  har valgt noen; VLC spiller da også mp4 (Apples avspiller kan ikke legge til undertekstfiler). Sett/ikke sett:
  `PlexClient.setWatched` (`/:/scrobble`, `/:/unscrobble`), på enheten `setFinished(_:_:)`; `merk-sett` (Apple TV ved
  knappene, iPhone/iPad i menyen `vod-mer`), hurtigmeny på episodene. «Mer som dette»: `related`
  (`/hubs/metadata/<id>/related?count=24`, den første raden med noe), `lik-<id>`. Hjemmenettet: `PlexServer.ordered`
  prøver `lanHTTP` (http://<adresse>:<port> fra navnet `a-b-c-d.<id>.plex.direct`, bare private adresser og
  `local`) etter https-adressen hjemme. Falsk Plex: markører og en engelsk undertekstfil på 2102/2103, «Mer som dette»
  for filmene, sett/ikke sett for 1002. Testene `test22PlexEpisoder`/`test23PlexSett` (Apple TV, iPhone; iPad bare
  `test23`). Skjulte biblioteker (Windows 2.1.37; eieren vil ikke se «Andre videoer» og et sportsbibliotek):
  `AppModel.hiddenLibraries` («<server>/<bibliotek>», iCloud-nøkkelen `plex-skjulte`), `hiddenSections`/`setHidden`
  → `refreshPlex()` → `VODModel.reset(_:hidden:)`: bibliotekene og `rows(…libraries:)` (contentDirectoryID) bare de
  som vises, og `visible` filtrerer «Fortsett å se», radene, «Se alle» og søket på `categoryId`
  (librarySectionID); `hiddenAll` gir meldingen med `velg-biblioteker`. `PlexLibrariesSheet` (`PlexSettings.swift`:
  `PlexClient.sections()`, bryterne `vis-bibliotek-<n>`, `biblioteker-ferdig`) fra «Biblioteker» i innstillingene
  (`plex-biblioteker`), nederst i sidemenyen og til slutt i raden på iPhone. Falsk Plex: biblioteket 4 «Andre videoer»
  (tomt). `X-Plex-Language` (nb/en) i `PlexDevice.headers`. Testene `test27PlexBiblioteker` (Apple TV) og
  `test26PlexBiblioteker` (iPhone og iPad).
- **Filmer og serier fra Windows-lista, også i 0.1.26** (pakken «Filmer og serier»; hvordan Windows gjør det:
  `lib/core/vod.dart`, `lib/ui/vod_browser.dart`, `vod_detail_page.dart`, `lib/ui/plex/plex_view.dart`): Core
  `cleanTitle` (merker i [ ] eller ( ) på slutten, høyst 24 tegn: år → året, resten → `VODItem.tags`; navnet uten dem
  i `parseVODItems`), `cleanEpisodeTitle` (uten serien og «S01E03» foran), `VODItem.added` (`added`/`last_modified`),
  `VODSort` og `sortVOD` (leverandørens, nyeste først, A–Å med norsk rekkefølge), `meaningful` («N/A» … er tomt),
  `VODDetails.age`/`country`/`quality` (`qualityBadges`: get_vod_info `video`/`audio`, Plex `Media[0]` og
  `colorTrc`/`DOVIPresent`), Plex `PlexSort` (`added` = `episode.addedAt:desc` for serier), `page` (100 om gangen,
  `X-Plex-Container-Start/Size` i spørringen, `totalSize`) og `genres` (`/library/sections/<n>/genre`; appen bruker
  den ikke fra 0.1.31: eieren 5.11 «Vi trenger ikke sjangermeny.»). `VODModel`:
  «Alle filmer/serier» (`VODModel.all`, alle hentes én gang: `everything`, delt med søket), `recent` («Nylig lagt til»
  på Hjem, de 24 nyeste; tom når ingen har `added`), `sort`/`shown`/`prepareSorted` (sortert utenfor hovedtråden),
  `plexSorts`/`totals`/`loadMore` (en ny side når hjulet nederst vises; en tom side avslutter;
  `requests` per kategori kaster sene svar), `moreFrom` («Mer fra <kategori>», 24, IPTV). Visningene: `VODSortMenu`
  (`vod-sortering`; `ChoiceMenu`: på Apple TV en knapp per valg med hake, på iPhone/iPad en Picker) i overskriften
  over plakatene, merkene på plakatene (høyst to, oppe til venstre),
  `InfoBadge` (`merke-<tekst>`) i en `FlowLayout` på siden, `ratingText` («★ 7,5»), «Mer fra …» som `lik-<id>`, Hjem
  `nylig-<id>` og `se-alle-nylig`. Apple TV: «Søk» øverst i sidemenyen (`vod-sok`) → `VODSearchPage` (`.searchable`,
  `VODSearchResults` på begge plattformene nå, `sok-<id>`). Falsk leverandør: 505 «Fjordlys [PRE] [2026]» med 4K, HDR,
  5.1, 12 og Norge; falsk Plex: sjangrene, sidene, «A–Å» (`titleSort`) og kvaliteten på 1001. Testene
  `test24Sortering`, `test25PlexSortering` (Apple TV, iPhone; iPad bare `test24`) og `test26FilmSok` (Apple TV).
  Menyene på Apple TV i testene: elementet med fokus er raden uten tekst, så `choose` ser på rammen (`focusCovers`).
- **Egne navn og feilrapport fra 0.1.27** (fra «Resten» i Windows-lista; hvordan Windows gjør det:
  `lib/core/app_log.dart`, `lib/core/report.dart`, `lib/ui/report_page.dart`, `lib/ui/settings_page.dart`): `Login.name`
  (Codable, valgfri, så lagrede innlogginger uten navn leses), `label` (navnet, ellers `defaultLabel` «bruker på
  server»), `named(_:)` (tomt: tilbake, høyst 40 tegn); `AppModel.rename` (lagres i nøkkelringen; samme konto på nytt
  beholder navnet). `App/RenameLogin.swift` (`.renameLogin($login)`: varsel med felt, «Lagre»): `gi-nytt-navn` ved
  «Innlogget som» (`innlogget-som`) og i hurtigmenyen på de andre (Apple TV og iPad), blyanten i Konto på iPhone.
  Feilrapporten: Core `AppLog` (de siste 400 linjene, «HH:MM:SS», renset før lagring) og `scrub` (reglene fra Windows,
  pluss X-Plex-Token), logglinjer i `AppModel` (listene, innloggingen), `PlayerModel` (kanalen, feilen og
  forklaringen), `VODPlayerModel` (forsøkene og feilene) og `PlexModel` (koblet til hjemme/utenfra/relé, uten adresse);
  `App/ErrorReport.swift` (`ErrorReport.build`, `ErrorReportView`: «Kopier» `kopier-rapport` og `ShareLink`
  `del-rapport` på iPhone og iPad; Apple TV teksten i biter som får fokus, og «Send til iPhone» `send-rapport` →
  `AppModel.sendReport`, iCloud-nøkkelen `feilrapport-tv`, vist som «Fra Apple TV» (`rapport-fra-tv`) på iPhone og
  iPad). `feilrapport-knapp` nederst i innstillingene (Apple TV, iPad «Hjelp») og i Konto (iPhone). Testene
  `test28Feilrapport` (Apple TV) og `test27NavnOgFeilrapport` (iPhone og iPad).
- **M3U og XMLTV fra 0.1.28** (fra «Resten» i Windows-lista; hvordan Windows gjør det: `lib/core/m3u_source.dart`,
  `lib/core/session.dart` (`loginM3u`), `lib/ui/login_page.dart`): `Core/.../M3U.swift`: `parseM3U` (leser bytene, ikke
  regex: #EXTM3U med url-tvg/x-tvg-url/tvg-url, #EXTINF med attributtene før det første kommaet utenfor anførselstegn,
  #EXTGRP; filmer og episoder hoppes over, `isVODURL`), `M3UList.lists(hasGuide:)` (kategoriene = gruppene,
  `ungroupedCategory` «Uten kategori»; id-ene `stableHash("id:<tvg-id>|<navn>")` eller `"n:<gruppe>|<navn>"`, like får
  #2; `Channel.m3u` = `M3UChannel` med adressen, tvg-id og tvg-name, og `Lists.guides`, så lista fra sist har det),
  `parseXMLTV` (bytene; programmene fra 2 t før til et døgn etter, med `XMLTVWanted` bare for kanalene i lista: tvg-id,
  ellers navnet og tvg-name mot display-name; Latin-1 når fila sier det), `unpackGzip` (hodet leses i Core,
  `NSData.decompressed(.zlib)` bare på Apple), `xtreamLogin(fromM3U:)`, `normalizeLink`, `m3uPlayURLs` (en .ts-adresse
  med Xtream-sti prøves som `/live/…/<id>.m3u8` først), `M3USource` (actor: `lists()`, `remember(lists)`,
  `programs(for:)`; guiden hentes når det trengs og hver 6. time, etter en feil igjen etter 5 min). `Login.m3u`/`epg`
  (`init(m3u:epg:)`, `isM3U`, id `stableHash("m3u|<lenken uten password/pass/pwd>")`, «M3U-liste fra {host}»). Appen:
  `LoginView` med `innloggingstype` (Xtream Codes først, så M3U-lenke), `m3u-lenke`, `epg-lenke`;
  `AppModel.signIn(m3u:epg:)` (en Xtream-lenke prøves som Xtream først), `use(_:fresh:)` (lista fra innloggingen hentes
  ikke igjen), `providerURLs` (spilleren tar den neste etter to feil, `providerStep`), `hasVOD` (Filmer og Serier bare
  med Xtream eller Plex), `m3uSummary` (`m3u-info`); `ProgramStore.reset(source:)` med `ProgramSource` (Xtream eller
  `M3USource`). Falsk leverandør: `/liste.m3u`, `/guide.xml.gz`, `/guide.xml`, `/strom/<id>.m3u8`, `/get.php`;
  testskjermene `m3u` (logget inn med lista) og `login-m3u`; testene `test29M3U` (Apple TV) og `test28M3U` (iPhone og
  iPad). En kanal i lista som ikke er HLS (og ikke har en Xtream-sti), kan ikke spilles med AVPlayer.
- **Multiview fra 0.1.29** (fra «Resten» i Windows-lista; hvordan Windows gjør det: `lib/ui/multiview_page.dart`,
  `lib/core/session.dart` `canMultiview`): `App/Multiview.swift`: `MultiviewModel` (`start(first:)`:
  `AppModel.multiviewLogins` (den i bruk først), `connections(of:)` per innlogging (Xtream: abonnementet, høyst 10 s,
  1 ved feil; M3U 1), så mange bilder som det er tilkoblinger, høyst fire; under to: «Fant bare én tilkobling …»;
  `select` (lyden bare fra det valgte), `toggleBig`, `toggleMute`), `MultiviewTile` (egen AVPlayer, adressene som i
  spilleren for den i bruk (egen strøm, så leverandørens), ellers Xtream eller M3U-adressen; to forsøk med 3 s, så neste
  adresse, så feilen; stopper det etter start: på nytt etter 1,5 s, høyst tre i minuttet, så «Kanalen stoppet.»;
  programinfoen fra ProgramStore, eller rett fra en annen Xtream-innlogging), `MultiviewView` (to ved siden av
  hverandre, over hverandre når skjermen står, tre eller fire i to rader; Apple TV: fokus = valgt, trykk = stort bilde
  eller kanalvalget, hold inne = hurtigmenyen, Menu tilbake; iOS: trykk, dobbelttrykk, hold inne, `lukk-multiview`,
  `multiview-lyd`), `PlayerLayerView` (AVPlayerLayer), `MultiviewPicker` (`multiview-velg`, `velg-<id>`, søk,
  «★ Favoritter»/«Alle kanaler», høyst 500 rader; `AppModel.channels(of:)` fra lista i bruk, fra disken eller fra
  leverandøren, `favoriteIds(of:)`). Inn: «Multiview» i hurtigmenyen på kortene når `multiviewAvailable` (to
  innlogginger, eller `maxConnections` ≥ 2), og i spilleren (`PlayerModel.openMultiview`: `pendingMultiview`, spilleren
  lukkes først, `showPendingReplay` viser den), `multiview-knapp` på iPhone/iPad. Id-ene `multiview`,
  `multiview-bilde-<n>`. Testskjermen `multiview` (M3U-lista som innlogging nummer to, `TestSupport.extraLogins`);
  testene `test30Multiview` (Apple TV) og `test29Multiview` (iPhone og iPad).
- **TV-spilleren fra 0.1.30** (pakken «TV-spilleren» fra Windows-lista; hvordan Windows gjør det: mpv tar vare på det
  siste selv, `lib/ui/player_page.dart`, `lib/ui/playback.dart`, `lib/core/picture.dart`): pause og tilbakespoling i
  direktesending med et buffer på enheten: `Core/.../LiveShift.swift` (`parseHLS`: hovedliste med varianter (lyden for
  seg = `separateAudio`) eller medieliste med bitene, nøkler og MAP med hel adresse; `chooseVariant`; `ShiftBuffer`: de
  tre siste bitene ved start, så de nye, brudd ved hull og når nummeret går tilbake, det eldste fjernes over 30 min
  eller `maxBytes` (aldri under tre), `playlist()` med egne nummer og DISCONTINUITY-SEQUENCE). `App/LiveShift.swift`:
  `LiveShiftSession` (actor: `start()` henter to biter før avspilleren får lista, `run()` henter lista hver halve
  bitlengde, hver tredje feil fra begynnelsen, etter 30 feil slutt; bitene i Caches/tilbakespoling/<id>, tømt ved
  start), `LiveShift` (én sending om gangen, `prepare(url)` gir adressen på enheten, eller nil = spill direkte; samme
  adresse fortsetter etter et nytt forsøk), `ShiftServer` (NWListener bare på 127.0.0.1, GET/HEAD
  `/shift/<id>/index.m3u8` og bitene, ett svar per tilkobling). `PlayerModel.open` bruker det for .m3u8 når
  `AppModel.liveShift` (`tilbakespoling-av`; bryteren `tilbakespoling` i `StreamSettings`), `sourceURL` for
  forklaringen. AVKit viser selv tidslinja og «direkte». Bildeformat per kanal: `PictureFormat` (original, zoom,
  stretch, wide 16:9, classic 4:3) og `PictureFormats` (Core), `AppModel.pictureFormat(for:)`/`setPictureFormat`
  (`bildeformat@<innlogging>`, bare på enheten), `PictureFormat.gravity` og `ForcedAspect` (`Theme.swift`); Apple TV:
  UIMenu «Bildeformat» i `transportBarCustomMenuItems`, iOS: «Mer» (`spiller-mer`) med Picker. Strøminfo: `StreamInfo`
  (Core: «1920×1080 · H.264 · 50 fps · 8,1 Mbit/s · AAC stereo · 3 tapte bilder», `codecName`, `bitrateText`,
  `channelLayout`, `fourCCText`), `PlayerModel.streamInfo()` (presentationSize, accessLog, sporene); Apple TV: feltet
  «Strøminfo» i `customInfoViewControllers` (`StreamInfoPanel`), iOS: «Vis strøminfo» (`strominfo`). Lydforsinkelse
  finnes ikke (AVPlayer kan det ikke). Falsk leverandør: `/hls/<id>/index.m3u8` er en ekte direktesending (bitene i
  `tools/testdata/direkte`, i ring med brudd); testene `test31Tilbakespoling` (Apple TV, iPhone; som egen strøm for
  Fjordkanalen) og `test30Strominfo` (iPhone).
- **Plex-fanen fra 0.1.31** (eieren 4.11: «Der ønsker jeg at Filmer og Serier skal være orginal fra IPTV og at vi får
  egen Fane som heter Plex. hvor det er en hjem skjerm som samler Filmer og serier også rad på siden hvor du kan velge
  filmer eller serier.»): `AppModel.movies`/`series` er alltid IPTV-leverandøren (`hasVOD` = Xtream), og
  `AppModel.plexVOD` = `VODModel(kinds: [.movies, .series])` er Plex-fanen (`HomeView.Tab.plex`, `VODTab(kind: nil)`,
  fanen «Plex» etter Serier når `hasPlex`: en server er valgt, eller en skal velges). `VODModel.kinds`/`mixed`;
  `kind` er det ene slaget for IPTV, og i Plex-fanen har hvert bibliotek sitt (`libraryKinds` fra `sections()`,
  `kind(of:)` til `page`). Kjernen: `continueWatching`, `items(ids:)`, `search`, `rowItems` og `rows` tar
  `Set<VODKind>` (de med ett slag står igjen), `parseContinue`/`parseHubs`/`parseSearch`/`parseItems(kinds:)`,
  `plexKind` («movie»/«show»); Hjem i fanen har altså «Fortsett å se» og radene i rekkefølgen fra Plex, med filmer og
  serier om hverandre. `AppModel.vod(for:)` gir modellen en film eller serie hører til (siden, spilleren:
  `VODPlayerModel.library`). Favorittene: `plexFavorites` = filmene og seriene sammen, sist lagt til først
  (`VODItem.added` = tidspunktet de ble lagt til, for Plex; de fra før står etter). Sidemenyen (Apple TV, iPad):
  «Søk» (Apple TV), Hjem (`house`) og bibliotekene med `SidebarIcon` (`film`/`tv`), «Velg biblioteker» nederst;
  iPhone: `libraryRow`, Hjem og bibliotekene som knapper på en rad (`vodkat-<id>`, kan dras til siden), søket «Søk i
  Plex» (`searchPrompt`) under. Testskjermene `plex`/`plex-series` åpner Plex-fanen (HomeView bytter dit når den
  kommer, `onChange(of: hasPlex)`). Fra 0.1.32 (eieren 5.11 med bilde fra Apple TV-en: «Den velg biblioteker inne i
  plex menyen kan vi ta bort, vil heller kunne holde inne på f.eks filmer å velge skjul ellerno. Vil også kunne justere
  rekkefølgen, slik at vi kan ha TV-serier øverst.»): hurtigmeny på bibliotekene (`libraryActions`: «Flytt opp»/«Flytt
  ned», på iPhone «Flytt til venstre»/«Flytt til høyre», og «Skjul» → `setHidden`), ingen «Velg biblioteker» i
  sidemenyen og raden (bare når alle er skjult; ellers «Biblioteker» under Plex i innstillingene). Rekkefølgen:
  `AppModel.libraryOrder` («<server>/<bibliotek>», iCloud-nøkkelen `plex-rekkefolge`), `orderedSections`,
  `moveLibrary(_:by:among:)` (bytter med naboen som vises; de skjulte beholder plassen bak) → `VODModel.setOrder`
  (uten å hente på nytt) og `reset(…order:)`; `ordered` sorterer bibliotekene, og `arranged` radene på Hjem etter
  biblioteket det meste i raden kommer fra (`library(of:)`; uten `librarySectionID` i svaret, som episodene i den
  falske Plex, det første biblioteket med samme slag i rekkefølgen: fra 0.1.33, i 0.1.32 havnet raden til slutt;
  `plexRows` er radene slik Plex sendte dem; uten valgt rekkefølge står de som i Plex). Testene `test27PlexBiblioteker` (Apple TV) og `test26PlexBiblioteker` (iPhone og iPad).
- **Plex Home fra 0.1.34** (eieren 5.11: «jeg har plex home og vil da gjerne kunne velge hvem som skal se på»):
  Core `PlexAccountClient.homeUsers` (`GET /api/v2/home/users`, `parseHomeUsers`: `PlexHomeUser` id/name/thumb/
  admin/protected/restricted, eieren først) og `switchUser` (`POST /api/v2/home/users/<id>/switch?pin=`, gir
  `authToken`; bare kontonøkkelen kan bytte; adressen må ha `uuid` fra brukerlista, det numeriske `id` ga 404 hos
  eieren 6.11 (0.1.35: uuid først, id som reserve ved 404)). `PlexModel`: `accountToken` (fra plex.tv/link, lagret i `Saved`) ved
  siden av `token` (brukerens), `users`/`user`/`switching`, `loadUsers()` (tom liste uten Plex Home; eieren er valgt
  fra start), `switchUser(_:pin:)` (ny nøkkel → serverne på nytt (hver bruker har sin egen `accessToken` til
  serveren) → `connect` → `onChange` → Plex-fanen hentes på nytt). `PlexUserSheet` (`PlexSettings.swift`,
  `plex-brukere`, `bruker-<id>`, `bruker-pin`, `bruker-bytt`, `bruker-feil`) fra knappen `plex-bruker` øverst i
  sidemenyen/først på raden (bare når `plex.users` ikke er tom). Falsk Plex: brukerne 1 «Eieren» og 2 «Barna» (PIN
  1234, nøkkelen `barna-token`). Testene `test32PlexHome` (Apple TV, iPhone, iPad).
- **Filmsiden fra 0.1.36** (eieren 6.11: «Syntes filmsiden er litt tom, mangler også logo på filmer og serier, plex
  har det nå.»): `VODDetails.logo` (Plex `Image` med `type` «clearLogo», `plexImage`, 800×310 via `imageURL`),
  `tagline`, `studio` (blant merkene) og `people: [VODPerson]` (navn, rolle, bilde; Plex `Role` med `role`/`thumb`
  (`plexPeople`), leverandøren `peopleFromNames(cast)` uten bilder). `VODDetailView`: `backdropLayer` (bakgrunnsbildet
  `Metrics.detailBackdrop` høyt som `.background` på rullelista, står fast, tonet mot `Theme.bg` nedover og mot
  venstre), `titleView` (`RemoteImage` av logoen med tittelen som reserve, `vod-logo`, høyst `Metrics.detailLogo` ×
  0,38), «Regi: …», `peopleRow` («Medvirkende», `medvirkende`; `PersonCard` med sirkelbilde eller forbokstaver; Apple
  TV de første `personCount` på én linje uten fokus, iPhone/iPad en rad som rulles). Falsk Plex: logoen (`logo()`, PNG
  med gjennomsiktighet, `/clearLogo/`), rollene med bilde (`/role/<n>`), slagord og studio på 1001 og 2001. Sjekkes
  i `test17Plex` (Apple TV) og `test18Plex` (iPhone og iPad). **Skarpe bilder fra 0.1.37** (eieren: «oppløsingen
  virker å være lav? gjelder også Postere»): `Images.load(url, maxPixels:)` krympet før alt til 360 piksler (for
  kanallogoene); nå `Images.pixels(for: punkter)` = punkter × `UIScreen.main.scale` (Apple TV 4K 2, iPhone 3), høyst
  2048, og `RemoteImage(maxPoints:)` per sted (`Metrics.posterPoints`, `backdropPoints`, `detailPoster * 1.5`,
  `detailLogo`, `resumeWidth`, `person`, avataren; kanallogoene 180 pt som før). Mellomlageret husker hvor mye et
  bilde er krympet (`Entry.limit`) og henter det på nytt (fra disken, 400 MB) når et sted trenger det større;
  `totalCostLimit` 180 MB. Plex bes om plakater 720 × 1080 (`imageURL` standard), bakgrunn 1920 × 1080, bredbilder
  1280 × 720, episoder 960 × 540, roller 400 × 400 og logoen 1600 × 800 med `fit: true` (`minSize=0&upscale=0`:
  hele logoen innenfor rammen, ikke beskåret som plakatene).
- **Mac fra 0.2.2** (eieren 7.11.2026: «det neste vi skal bygge er app til MacOS»; valgte egen Mac-app (ikke
  Catalyst: MobileVLCKit har ingen del for Catalyst, og iPad-apper kjører ikke på hans Intel-Mac), utseendet som Fyrlys
  for Windows, ut via TestFlight som de andre): målet `FyrlysMac` (macOS 14, samme bundle-id, sandkasse med
  `network.client`/`network.server` (tilbakespolingen), hardened runtime, `CODE_SIGN_IDENTITY -` lokalt), skjemaet
  `FyrlysMac`, VLCKit for Mac (`tools/vlckit.sh macOS`, universell, mappen «VLCKit - binary package»), ikonet i
  `App/Mac.xcassets` fra iPhone-ikonet (`swift tools/mac_icon.swift`; de andre målene utelater det). Koden følger
  iPad: `#if os(iOS)` i den felles koden ble `#if !os(tvOS)` (bare `PhoneHome.swift`/`PhoneTV.swift` og `Landscape` er
  iOS), `usesPhoneLayout` er alltid nei på Mac. `App/MacSupport.swift`: navnene fra UIKit med AppKit under
  (`UIImage`/`UIColor` = NS…, `Image(uiImage:)`, `UIApplication` (bare `isIdleTimerDisabled` via
  `ProcessInfo.beginActivity`; «i bakgrunnen» aldri), `UIDevice`, `UIPasteboard`, `byPreparingThumbnail`,
  `externalMetadata` (tom)) og iOS-modifikatorene (`keyboardType`, `textInputAutocapitalization`,
  `navigationBarTitleDisplayMode`, `statusBarHidden`, `.topBarLeading/.topBarTrailing`, `navigationBarDrawer`,
  `EditButton`) som ikke gjør noe eller det nærmeste; `fullScreenCover` (spilleren, multiview) er et ark like stort som
  vinduet (`WindowCover`). Egne Mac-versjoner: `VLCSurfaceView` (NSView), `PlayerLayerView`, `VODPlayerController` og
  `VideoSurface` i `PlayerViewMobil` (`AVPlayerView`, flytende kontroller, fullskjerm, bilde-i-bilde; Esc lukker),
  `Theme.tone` (`NSColor(name:dynamicProvider:)`), knappene i spillerpanelet (ikon over tekst; panelet 420 bredt).
  `HomeView.macHome`: ingen TabView, siden byttes etter `tab`; verktøylinja som toppen i Windows-appen (`MacBrand`,
  seksjonene som segmentert `Picker` `seksjoner`, `SearchField` (søket viser `SearchView` mens det står noe der, så
  tilbake), `MacThemeButton` `tema`, tannhjulet `innstillinger-knapp`; ⌘, via `.fyrlysOpenSettings`); skjemaene
  `.formStyle(.grouped)`. **Se Mac-appen uten skjermopptak** (Claude har ikke den tillatelsen her): med
  `FYRLYS_TEST_SNAPSHOT` lagrer appen et bilde av vinduet (eller arket) hvert andre sekund i
  `~/Library/Containers/no.fyrlys.tv/Data/Documents/vindu.png` (`WindowSnapshot`; videobildet kommer ikke med). Start
  med `open -n --env FYRLYS_TEST_SERVER=http://127.0.0.1:8899 --env FYRLYS_TEST_SNAPSHOT=1 --env
  FYRLYS_TEST_SCREEN=<skjerm> build/DerivedDataMac/Build/Products/Debug/Fyrlys.app` (å starte programfila direkte
  ga ingen vindu); bygg Mac med `-derivedDataPath build/DerivedDataMac` (ikke samme mappe som et annet bygg som går).
  Workflowen: jobben `mac` bygger og tar bildene (grenen `skjermbilder-mac`, `NN-mac-<skjerm>.png`); TestFlight-jobben
  arkiverer Mac (`MAC_ARCHIVE`), `adhoc_sign.sh` gir Mac-appen `com.apple.application-identifier`, sandkassen og
  nettet, `asc.py`: `MAC_OS` i appen (`ensure_platform(required=False)`), profilen `MAC_APP_STORE`
  (`.provisionprofile`), sertifikatet `MAC_INSTALLER_DISTRIBUTION` (`installer.cer`, samme nøkkel), `ExportOptions-
  macOS.plist` med `installerSigningCertificate`; alt for Mac er valgfritt (`OPTIONAL`): feiler det, en advarsel, og
  `ASC_PLATFORMS` (som `wait` bruker) er uten `MAC_OS`.
  Fra 0.2.3 (eieren prøvde Mac-appen 8.11): filmer og episoder over hele vinduet (`#if !os(iOS)` →
  `fullScreenCover` = `WindowCover`), × og Esc lukker; `MacFullScreen`/`MacFullScreenButton` (`fullskjerm`, går ut
  igjen når spilleren lukkes); VLC-kontrollene på Mac: tiden, lyd og undertekster som piller (`VLCMenuLabel` med
  sporet) og fullskjerm nederst; `macSheetSize` (Theme.swift) på arkene (en List i et ark på Mac ber om nesten ingen
  plass: «Hvem ser på?» ble en tom stripe); `macRowMenu` («…» ved musa) på bibliotekene i Plex; film- og seriesiden
  som Windows-appen (`VODDetailView.macPage`, `macHero`, `MacChip`, `MacButtonStyle`, `MacEpisodeCell` i rutenett
  høyst 760 bredt, «S03E01», `macFraction`; Windows: `lib/ui/vod_detail_page.dart` `DetailHero`,
  `lib/ui/plex/plex_detail_page.dart`). `WindowSnapshot` virker også uten testmodus i et Debug-bygg, så Claude kan se
  appen med eierens ekte innlogging (`open -n --env FYRLYS_TEST_SNAPSHOT=1 …/Debug/Fyrlys.app`; han logger inn selv,
  bildene blir på Mac-en). Testskjermene `plex-users` (arket åpent), `plex-film` (1001) og `plex-serie` (2001).
- **0.2.4** (eieren 8.11: «Hva mer kan vi forbedre?» → «kjør alt»): Mac: `App/MacKeys.swift`: `playerKeys`
  (lokal `NSEvent`-monitor, bare for vinduet spilleren står i: på Mac er `fullScreenCover` et eget arkvindu, så
  `event.window` er arket; ikke mens et `NSText` har fokus), `PlayerCommand`, menyen «Avspilling»
  (`PlaybackCommands`, uten snarveier i menyen: mellomrom og piler ville tatt tegnene fra søkefeltet) og
  `SectionCommands` (⌘F = `.fyrlysFind` til `SearchField(findTarget:)`, ⌘1–5), `MacPlayerState` (live/vod/mini),
  `MacMiniPlayer` (NSPanel `.floating` med `PlayerLayerView`; `PlayerModel.detached` så spilleren ikke stopper når
  den lukkes; «Tilbake i vinduet» = `AppModel.reopenPlayer` med `PlayRequest.existing`; en ny kanal, film eller
  multiview lukker den). `WindowMemory` (MacSupport.swift): rammen i `vindu-ramme` og fullskjerm i
  `vindu-fullskjerm` (SwiftUI lagret rammen under et navn med adresser som endres for hver start, så den ble aldri
  funnet; de gamle nøklene slettes), ikke i testene uten `FYRLYS_TEST_WINDOW`. `NSWindow.allowsAutomaticWindowTabbing
  = false`. Kanalkortene (iPad og Mac): nummeret over stjerna, navnet på to linjer uten linje under, `.help` med hele
  navnet. Plex: `PlexModel.askWhoIsWatching` (`plex-spor-hvem`, bryteren `spor-hvem` og `plex-bytt-bruker` i
  `PlexSettings`; testskjermen `plex-ask`). `App/Shortcuts.swift` (iPhone, iPad, Mac): App Intents
  (`PlayChannelIntent`, `ChannelEntity` fra `ShortcutChannels` = favorittene og de sist sette i UserDefaults
  `snarvei-kanaler`, `FyrlysShortcuts` med norske og engelske fraser), `IntentInbox` → `pendingPlay`; `Reminders`
  («Minn meg på» `paminnelse` i infoarket i guiden, varsel 2 min før, `NotificationRouter` spiller kanalen).
  Widget: målet `FyrlysWidget` (iOS, `Widget/FyrlysWidget.swift`, app-id `no.fyrlys.tv.widget` i
  `asc.py` `EXTENSIONS["iOS"]`), favorittene fra `SharedFavorites` (den felles nøkkelring-gruppen, også i
  `FyrlysMobil` nå), `fyrlys://` registrert på iOS. Top Shelf: «Fortsett å se» (`SharedResume`,
  `SharedFavorites.saveResume`, `AppModel.shareContinue`; Plex-fanen hentes i bakgrunnen på Apple TV når Plex er
  koblet til), `fyrlys://vod/<plex|iptv>/<movies|series>/<id>?navn=` → `AppModel.pendingVOD` → fanen og
  `VODTab` legger siden på stien. iPad (iPadOS 18): `iPadTabs` med `SwiftUI.Tab`, Innstillinger som ikon og Søk med
  `role: .search`. Guiden på iPhone: `neste-program-<kanal>` på det neste programmet (testene). `asc.py wait`:
  `share_external` (eksterne grupper, `betaBuildLocalizations` fra CHANGELOG, `betaAppReviewSubmissions`; navnene på
  gruppene skrives ikke ut). Bygget: simulatoren varmes opp før iOS-testene, `-test-iterations 3`, introen på 2103 i
  den falske Plex 2–14 s. Simulatorverktøyet (MCP) krever `sudo xcode-select -s ~/Downloads/Xcode.app/...`
  (eieren kjører det selv).
- `.github/workflows/build.yml`: kjernen på Linux (`ubuntu-24.04`, som har Swift; `ubuntu-latest` ble Ubuntu 26 uten
  Swift 1.11.2026, og jobben feilet med 127); UI-testene kjøres med `-retry-tests-on-failure -test-iterations 2` (en
  test som feiler, kjøres én gang til: «Timed out while requesting launch progress» og trykk som ikke tas, skjer av og
  til i simulatoren); appen på `macos-15` med høyeste Xcode, XcodeGen, simulator fra
  `tools/simulator.py` (`[plattform] [slag] [variabel]`, f.eks. `iOS iPad IPAD_ID`; laster ned plattformen om den
  mangler), falsk leverandør, `xcodebuild test`, skjermbildene ut med `tools/screenshots.py` (`xcresulttool export
  attachments`) og inn i grenen `skjermbilder`. Jobben `ios` er fra 0.2.1 en matrise (`iphone`, `ipad`)
  som går samtidig: hver bygger (`build-for-testing`) og tester (`test-without-building`; iPad et utvalg) og legger
  bildene som artefakten `skjermbilder-<enhet>`; jobben `skjermbilder-mobil` samler dem i grenen `skjermbilder-mobil`
  (loggene heter `bygg-<enhet>`, `test-<enhet>`, `tider-<enhet>`; feilbildene `feil-<enhet>-…`). Før 0.2.1 testet én
  jobb iPhone og så iPad (rundt 40 min).
- **TestFlight** venter fra 0.2.1 bare på kjernen og `oppsett`, ikke på UI-testene (eieren 7.11.2026 ville ha
  versjonene fortere: før rundt 47 min, nå rundt 10); UI-testene går samtidig, og bygget står som feilet om en av dem
  feiler. Test derfor endringene lokalt før push. (Jobbene `oppsett` og `testflight`, bare på main og når hemmelighetene `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8` og `APPLE_TEAM_ID` finnes; Admin-nøkkel laget av eieren): `tools/asc.py check` (nøkkelen, app-id-en
  `no.fyrlys.tv`, appen i App Store Connect; `ensure_platform` legger IOS til appen med `POST /v1/appStoreVersions`
  første gang), arkiv uten signering for begge plattformene (`CODE_SIGNING_ALLOWED=NO`: å signere for en
  Apple TV krever en utviklerprofil, og den krever en registrert enhet), `tools/adhoc_sign.sh` (ad hoc med
  application-identifier og team), `asc.py prepare` (distribusjonssertifikat og en profil per plattform; med
  hemmeligheten `DIST_KEY` (privat RSA-nøkkel, PKCS#1 eller #8, `DIST_KEY_PATH` i jobben) finnes sertifikatet med
  samme offentlige nøkkel igjen hos Apple (`find_certificate`, sammenligner modulus; går det ut innen to uker, trekkes
  det tilbake og et nytt lages) eller lages første gang, og beholdes; uten den ett per kjøring som `cleanup` trekker
  tilbake,
  `TVOS_APP_STORE` og `IOS_APP_STORE`, med `ExportOptions-tvOS.plist`/`-iOS.plist`, for kjøringen gjennom REST-API-et, JWT med openssl, bare standardbiblioteket; egen nøkkelring), `xcodebuild
  -exportArchive` med `destination upload` og API-nøkkelen per plattform (laster opp selv), `asc.py wait <byggnummer>`
  (venter på bygget for både TV_OS og IOS; feiler hvis ett ikke dukker opp i App Store Connect, eller blir INVALID), og `asc.py cleanup` (sletter profilene og
  trekker tilbake sertifikatet hvis det ble laget for kjøringen; da får eieren en e-post «Your Certificate Has Been
  Revoked» for hvert bygg). Hemmelighetene kan ikke leses eller settes herfra (proxyen stenger `actions/secrets`). Prøvd og forlatt 31.10: Apples skysignering
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
- 31.10.2026: 0.1.3: eieren syntes det var «for mye luft mellom enden av tven og appen». TV-siden, guiden, søket og
  innstillingene ignorerer den trygge sonen til Apple TV på sidene (og nederst, unntatt innstillingene) og bruker
  `Theme.edge` = 40 pt; `safeAreaPadding(.bottom, Theme.bottomFocus)` holder kortet med fokus litt over bunnen. Toppen
  står under fanelinja som før.
- Åpent (31.10): 0.1.2 er ikke prøvd på Apple TV-en hans ennå (fart med 25 000 kanaler, de nye kortene, «Dine
  kategorier», at ingenting går inn under fanelinja). «Hjem» (startsiden i Windows-appen) finnes ikke i Apple TV-appen.
  Han får en e-post «Your Certificate Has Been Revoked» for hvert bygg (fra `asc.py cleanup`; 1.11 spurte han hvordan
  han fikser det). Løst 1.11: han la inn hemmeligheten `DIST_KEY` (se TestFlight under); bygg 24 laget sertifikatet
  som beholdes (utløper 1.11.2027, da lages et nytt: én e-post i året), og oppryddingen sletter bare profilene.
  Merknadene `sertifikat` og `opprydding` på TestFlight-jobben viser det. Et bygg kan startes uten endring med
  `gh api -X POST repos/ungerdas/fyrlys-tv/actions/workflows/build.yml/dispatches -f ref=main`.
- 31.10.2026: eieren laget en ekstern TestFlight-gruppe med offentlig lenke; 0.1.3 (bygg 7) ble sendt til Apples
  beta-gjennomgang (Waiting for Review). Nye versjoner kommer ikke av seg selv til den eksterne gruppa (må legges til
  og gjennomgås); tilbudt å automatisere det i bygget, og en demo-innlogging hvis gjennomgangen stopper på innloggingen.
- 31.10.2026: eieren ville ha en iPhone-app også; valgte samme app som Apple TV og iPhone + iPad. 0.1.4 (bygg 10) er
  den første med iOS: VALID for både TV_OS og IOS i App Store Connect (iOS lagt til appen av `asc.py check`). Alle
  UI-testene grønne (iPhone 10, iPad 6, Apple TV). iPhone/iPad er bare prøvd i simulatoren.
- iOS-jobben i CI: første forsøk (begge simulatorene i samme `xcodebuild test`) gikk ut på tid etter 75 min uten
  merknader (sannsynligvis to iOS-simulatorer samtidig på en maskin med 7 GB). Nå: `build-for-testing` én gang, så
  `test-without-building` på iPhone (alle testene) og iPad (et utvalg, `-only-testing`) etter hverandre, tidsgrense per
  test, en vakthund (`limited <min> <logg> …`) som stopper xcodebuild før jobben går ut på tid, merknaden «tester
  iphone/ipad» med hver test og tiden, og utdrag av loggene (`*-utdrag.txt`, `tider.txt`) i `skjermbilder-mobil`.
  Tilgjengelighet på iOS: et kort med to knapper må ha `.accessibilityElement(children: .contain)`, ellers skriver
  «kanal-…» på kortet over id-ene til knappene.
- 31.10.2026: 0.1.5: på iPhone rullet kortene opp under klokka og Dynamic Island (bilde fra eieren). En ScrollView som
  når toppen av skjermen uten navigasjonslinje tegner det som rulles forbi under statuslinja. Nå står kategorivalget
  fast øverst med lista under (ScrollView-en begynner under det); på iPad (og innloggingen) `.clipped()`, som på Apple
  TV. Under fanelinja nederst ruller innholdet fortsatt, som i Apples egne apper (glass).
- 31.10.2026: 0.1.6: eieren ville ha iPhone-appen lik Fyrlys-nettsiden på telefon (bilde): topplinje, «Sist sett»,
  kategorifliser, store kort med logofarge, fanene nederst. Laget som over (se Arkitektur), også lys modus. Nettsiden
  har Filmer og Serier i fanelinja; de finnes ikke i Apple-appen ennå (avtalt senere). Samme kveld (bilde fra hans
  iPhone med ekte strømmer, spilleren virket): «dra med video vinduet for å lukke» – laget i 0.1.6.
- 0.1.7: guiden på iPhone var tom i 0.1.6 (se Arkitektur; det første forsøket traff feil sted, og det bygget feilet
  også på at et trykk på en flis ikke tok i simulatoren, så testene trykker nå én gang til). `UIUserInterfaceStyle:
  Dark` er tatt ut av iOS-målet, så appen følger enheten til man velger lys eller mørk (Apple TV har den fortsatt).
  Apple TV fikk forsiden og de store kortene (se Arkitektur). 0.1.7 (bygg 20) er i TestFlight for både TV_OS og IOS
  (1.11). Ikke prøvd på ekte Apple TV eller iPhone ennå. Fartstesten: flisene etter 14,7 s uten lista fra sist (før:
  første kort etter 6,2–6,5 s) og 5,4 s med (før 4,1–4,3 s); verdt å se på om oppstarten med 25 000 kanaler er blitt
  tregere. `test06Player` på Apple TV trykket ikke Menu i 0.1.7 («kanal-1» fantes bak spilleren); fra 0.1.8 venter
  den på at `spiller` er borte.
- 1.11.2026: 0.1.8: eieren syntes Apple TV-versjonen 0.1.7 var «rart med den toppen» (bilde: den øverste raden kuttet
  under en tom stripe der fanelinja hadde vært) og «uoversiktlig» (fem store kort i bredden). Valgte «Sidemeny + mindre
  kort»: sidemenyen tilbake, radene øverst i «Alle kanaler», seks kort i bredden, ingen klipping under fanelinja, og
  fanelinja følger kortene (`movesTabBar`, se Arkitektur). 0.1.8 (bygg 22) er i TestFlight, VALID for både TV_OS og IOS
  (1.11); alle UI-testene grønne. Fartstesten: første kort etter 6,7 s uten lista fra sist og 4,4 s med (bygg 21: 4,9
  og 4,0), 24 steg i kortene 5,5 s, 20 steg i sidemenyen 4,3 s. Ikke prøvd på ekte Apple TV ennå.
- 1.11.2026: 0.1.9: eieren hadde 0.1.8 på Apple TV-en og ville ha 4–5 kort i bredden i stedet for seks («større
  brikker»); valgt fem (`Metrics.bigColumns`, med litt større tekst og logo). 0.1.9 (bygg 24) er i TestFlight, VALID for
  TV_OS og IOS; fartstesten 5,5 s uten lista fra sist og 4,2 s med. Samme natt (bilde av «Norway» på iPhone):
  «Liker godt UI på iPhone, så gjerne før over noe av det samme på AppleTV»; spurt hva (større kort/fire i bredden,
  kategoritoppen med stjerne, stjerne på alle kort, forsiden fra iPhone), han ville prøve 0.1.9 først.
- 1.11.2026: 0.1.10: etter å ha prøvd 0.1.9: «Syntes flisene kan være bittelitt større. Savner Fyrlys logo osv» →
  fire kort i bredden og Fyrlys-merket øverst til venstre (se Arkitektur). «osv» ikke avklart (topplinja på iPhone har
  også sol/måne og Konto; Apple TV er alltid mørk og har Innstillinger i fanelinja). 0.1.10 (bygg 25) er i
  TestFlight, VALID for TV_OS og IOS; sertifikatet fra bygg 24 ble brukt igjen (merknaden «Bruker
  distribusjonssertifikatet fra før»), så `DIST_KEY` virker. Fartstesten 5,8 s uten lista fra sist og 4,4 s med.
  Eieren prøvde 0.1.10 på Apple TV-en samme natt: «Syntes dette var konge jeg!» Sidemenyen, fire kort i bredden,
  radene øverst og merket er altså godkjent; ikke endre uten at han ber om det.
- 1.11.2026 kl. 05: eieren spurte «Hva mer kan forbedres?», fikk lista (kanalbytte med fjernkontrollen, valg i guiden
  på Apple TV, felles favoritter via iCloud, Top Shelf, filmer og serier, TV-arkiv, flere innlogginger) og svarte
  «Kjør alt.» 0.1.11 = kanalbytte + guidevalg; 0.1.12 = filmer og serier, TV-arkiv, flere innlogginger og felles
  favoritter via iCloud; Top Shelf til slutt (krever en egen utvidelse med egen app-id og profil i signeringen).
  0.1.11 (bygg 26) og 0.1.12 (bygg 27) er i TestFlight, VALID for TV_OS og IOS; `asc.py check` slo på ICLOUD for
  app-id-en, og eksporten med iCloud-rettigheten gikk. 0.1.12 ble bygget med `workflow_dispatch` etter at koden var
  pushet med [skip ci] (en push under en opplasting avbryter den). Første bygg av 0.1.13 (Top Shelf) ble avvist av
  App Store Connect: utvidelsen må ha `UIRequiredDeviceCapabilities: [arm64]` i Info.plist (signeringen og profilene
  for `no.fyrlys.tv.topshelf` virket). Med det er 0.1.13 (bygg 29) i TestFlight, VALID for TV_OS og IOS: hele lista
  fra «Kjør alt.» er ute. Ikke prøvd på hans enheter ennå: filmer/serier mot leverandøren hans (mkv?), TV-arkivet,
  iCloud-delingen mellom iPhone og Apple TV, Top Shelf (vises logoene over http?), kanalbytte med opp/ned.
- 1.11.2026: eieren spurte «kan du forbedre det du kan?» → 0.1.14 (bygg 30, VALID for TV_OS og IOS): se fra start,
  «Fortsett å se», «Åpne i VLC». Så: «hvorfor kan den ikke spille av MKV? andre klienter klarer jo å spille av filmer
  og serier uten problem» → forklart (AVPlayer kan ikke mkv), foreslått en innebygd avspiller, han svarte «Ja». 0.1.15
  = VLC (se Arkitektur). Samme dag ønsket han Plex i stedet for Filmer/Serier («Gjør noe med det når du har
  mulighet») → 0.1.16. 0.1.15 (bygg 31) er i TestFlight, VALID for TV_OS og IOS; VLC spilte testfilmen riktig i
  simulatorene. (NB: testfilmen `testsrc` har en svart stripe til venstre, som lett ser ut som at bildet er
  forskjøvet; det var det ikke. Sammenlign med en ramme fra ffmpeg før du «retter» noe.) 0.1.16 (bygg 32, Plex) er i
  TestFlight, VALID for TV_OS og IOS; alle UI-testene grønne. Ikke prøvd mot hans Plex-server ennå (tilkoblingen
  utenfra/hjemmenettet, store bibliotek, hvor langt du har sett tilbake til Plex/Tautulli). Eieren prøvde 0.1.16
  samme dag: «Funker fint» (Tautulli viste Fyrlys på Apple TV med Direct Play av HEVC Main 10, EAC3 og norsk SRT),
  «men vil ha teksten i orginal Apple stil» → 0.1.17. Så (bilde av radene i Plex: «Nytt fra TV 2», «Nytt fra
  TVNorge / HBO Max / discovery+», «Nytt fra NRK»): «Ønsker også de radene slik som på plex.» → 0.1.18: «Hjem»
  (`VODModel.home` = "hjem", først i sidemenyen når det finnes rader eller «Fortsett å se») med `PlexHomeView`
  (`App/PlexHome.swift`): «Fortsett å se» (`fortsett-<id>`) og radene (`rad-<id>`, episoder `rad-e<id>`) fra
  `PlexClient.rows` (`/hubs/promoted?contentDirectoryID=<bibliotekene>&pinnedContentDirectoryID=…&count=20&
  excludeContinueWatching=1`, ellers `/hubs/sections/<n>`; `parseHubs`: filmer i Filmer, serier/sesonger/episoder i
  Serier, uten «Fortsett å se» og rader med noe annet). Episodene spilles med en gang (`withFile` henter fila om den
  mangler), hold inne = «Gå til serien». Testene `test17Plex`/`test19PlexSerier` (Apple TV), `test18Plex`/
  `test20PlexSerier` (iPhone og iPad). Ikke sjekket mot hans server: om samlingene hans står i `/hubs/promoted`.
  0.1.17 (bygg 33) og 0.1.18 (bygg 34) er i TestFlight, VALID for TV_OS og IOS. Eieren om 0.1.17 på iPhone (bilde av Mayday): «Teksten er
  ikke Apple stil» (grå tekst uten boks: «Undertekster og teksting» har gjennomsiktig bakgrunn som standard, og
  skyggen bak kontrollene la seg over), «når jeg forsøker å få liggende visning fra stående, så funker ikke det», og
  «ønsker også en fortsett å se knapp på serier som går rett til den episoden jeg skal se» → 0.1.19: fast stil
  (`subtitleStyle`: «Helvetica Neue Medium», hvit, boks svart 150, uten kant/skygge, `--no-video-title-show`; bare
  størrelsen fra MediaAccessibility), `Landscape` (`App/VLCPlayer.swift`: `requestGeometryUpdate` til liggende når
  `VODPlayerView` åpnes på iPhone, tilbake til stående ved lukking hvis den sto slik; knappen `snu-skjermen` i
  VLC-kontrollene), og `fortsett-serie` på seriesiden (`nextEpisode`: den du er midt i, ellers den etter den siste
  sett ferdig (`watched` fra Plex eller `AppModel.isFinished`, satt av `VODPlayerModel.save` nær slutten), ellers den
  første; sesongen velges). Skjermbildene må hete `NN-…` (`tools/screenshots.py`), ikke `26b-…`.
  Samme dag: «Fyrlys skal kun bruke disse m3u8 fra NRK. Det er direkte.» (fire adresser fra et CDN for NRK1, NRK2,
  NRK3 og NRK Super). Adressene skal IKKE inn i repoet eller appen (offentlig repo og offentlig TestFlight-lenke);
  laget i stedet «Egne strømmer» (0.1.19): `Core/.../Streams.swift` (`channelKey(navn)`: små bokstaver og tall uten
  landskode foran og kvalitet bak, «NO: NRK1 HD» → nrk1; `channelKey(of: url)`: filnavnet, eller mappen over når
  filnavnet er generelt (muxed, index, playlist …); `parseStreamOverrides`: «adresse» eller «Kanalnavn = adresse»),
  `AppModel.streamLines`/`setStreams`/`streamURL(channel)` (brukt av `PlayerModel` i stedet for `liveURL`), lagret i
  iCloud-nøkkelen `egne-strommer` (`CloudStore.shared`), `App/StreamSettings.swift` (TextEditor på iPhone/iPad, på
  Apple TV lista og ett felt for én linje), `StreamSheet` fra Konto (`egne-strommer`), id-ene `egen-strom-<nøkkel>`.
  Testskjermen `strommer`, `FYRLYS_TEST_STREAMS`; testene `test20EgneStrommer` (Apple TV, også at spilleren bruker
  adressen) og `test21EgneStrommer` (iPhone og iPad). Eieren svarte så «Bygg inn for alle.» → `builtInStreams` i
  Streams.swift (de fire NRK-adressene), brukt for alle (`AppModel.useBuiltInStreams`, «NRK direkte» av/på i
  innstillingene, lagret som `innebygde-strommer-av`; egne strømmer for samme kanal går foran).
  Første bygg av 0.1.19 (bygg 35): iPad feilet i `test20PlexSerier` (id-en «rad-e…» på en knapp med `.contextMenu`
  ble borte; nå settes id-en før hurtigmenyen) og `test21EgneStrommer` (Form på iPad er lat: testen ruller fram);
  `Landscape.set(true)` i `onAppear` ble avvist mens arket kom inn (knappen virket senere), nå 0,6 s etter.
  0.1.19 (bygg 36) er i TestFlight, VALID for TV_OS og IOS; alle UI-testene grønne (undertekstene i boks på Apple
  TV og iPhone, iPhone åpner spilleren liggende). Ikke prøvd på hans enheter ennå, heller ikke NRK-adressene. Fortsatt bare for
  kanaler leverandøren har (navnet må bli nrk1/nrk2/nrk3/nrksuper), så programinfo, logo og favoritter er som før.
  0.1.20: «Burde vi slå sammen da, NRK er en, NRK 2 er en …» → `ChannelIndex(lists, merging: keys)` (`mergeKeys` =
  nøklene til de egne og innebygde strømmene, `AppModel.remerge()` når de endres): kanaler med samme `channelKey`
  blir én (den med EPG og logo, i alle kategoriene til de andre; `byId` for de andre id-ene peker dit, `ids(of:)`,
  `merged`; søket på alle navnene). Favoritt/ikke favoritt gjelder alle id-ene (`AppModel.isFavorite`/
  `toggleFavorite`), og `channels(_:in:)` tar hver kanal én gang. Falsk leverandør: 91 «Fjordkanalen HD» (i Test),
  slås sammen med 1 i `test20EgneStrommer`/`test21EgneStrommer` («Alle kanaler» 19).
  Bygg 37 feilte bare på iPad i `test01Login` (to ganger; samme kode gikk i bygg 38, så simulatoren). Steget «Merknad
  ved feil» stoppet før merknadene for testene (grep uten treff med pipefail), nå med `set +e`, og
  `test-*-utdrag.txt` begynner med alle «error:»-linjene. 0.1.20 (bygg 38) er i TestFlight, VALID for TV_OS og IOS.
  Fartstesten i bygg 38: 37,2 s uten lista fra sist (bygg 37 med samme kode: 5,6 s), 5,0 s med; trolig en treg
  runner, men se etter om det skjer igjen.
  Eieren sendte samme dag et bilde fra iPhone (0.1.20, kategorien Norway): leverandøren har landskoden bak («NRK 1 HD
  NO», «NRK 1 FHD NO», «NRK 2 Lydtekst HD NO», «NRK 3/SUPER NO», «NRK 3/SUPER HD NO»), så ingenting ble slått sammen.
  0.1.21: `channelKey` tar bort landskoden bak (`trailingCountryCodes`, når det er flere ord) og «lydtekst»/«tegnspråk»;
  `channelAlternatives`/`matchingStreamKeys`: «a/b» i navnet er to kanaler; `ChannelIndex` deler en slik i to når
  begge har en strøm (den første beholder id-en og får navnet «NRK 3 NO», den andre er `Channel.split`: id
  `<id>~<nøkkel>`, `source` = leverandørens id, uten logo; `Channel.streamId` brukes for adressen, EPG og arkivet).
  Delte kanaler taper mot ekte når de slås sammen (poeng 4). Testen `testMergingWithCountryLast`. 0.1.21 (bygg 39) er
  i TestFlight, VALID for TV_OS og IOS (fartstesten 15,1 s uten lista fra sist, 4,9 s med). Ikke prøvd på hans enheter.
- 2.11.2026: «Når jeg forsøker å spille av film/serie, så bare tuller den med å legge seg ned» (iPhone). Årsaken:
  `HomeView` (og `VODTab`) valgte iPhone- eller iPad-oppsett etter `horizontalSizeClass`, og de store iPhonene (Pro
  Max, Plus, Air; skjermbildene hans fra iPhone har sidene til en Pro Max eller en Air) har vanlig bredde på tvers. Når spilleren la seg ned
  (`Landscape.set(true)` fra 0.1.19), byttet hele oppsettet, `PhoneHome` med arket ble revet ned, `onDisappear` snudde
  telefonen tilbake. Trolig var det også det han mente med «fra stående til liggende funker ikke» i 0.1.17.
  0.1.22: `usesPhoneLayout(sizeClass)` (HomeView.swift) = iPhone alltid, iPad når den er smal. Simulatoren for iPhone i
  bygget er nå en Pro Max (`tools/simulator.py iOS "iPhone Max"`); før var det en vanlig Pro, der feilen ikke synes.
  `test17Mkv` snur også telefonen for hånd (`XCUIDevice.shared.orientation`, `setUpWithError` setter stående igjen).
  Bygg 40: `test17Mkv` grønn på Pro Max (filmen blir liggende, også når telefonen snus), men `test18Plex` (to ganger på
  Pro Max) og `test20PlexSerier` (to ganger på iPhone og iPad; flakset alt i bygg 38–39) fikk ikke «Hjem» fra Plex.
  Årsaken ikke funnet ennå; `VODModel.loadCategories` er gjort robust mot at fanens `.task` avbrytes (hentingen er en
  egen `Task` i modellen, `fetchCategories` skriver ikke noe når den er avbrutt), og Plex-testene skriver skjermen i
  loggen når radene ikke kommer (`dumpScreen`: «SKJERM:»-linjer i utdraget og merknaden, og «NN-plex-mangler»-bilder).
  Bygg 41 fikk ingen Mac («not acquired by Runner», startet på nytt med `workflow_dispatch`). Bygg 42: alt grønt, og
  Plex-testene gikk på første forsøk på iPhone og iPad (ikke bevis for at endringen i `VODModel` var årsaken).
  `test17Mkv` feilet én gang på «reist opp»: testfilmen er 30 s, og den var ferdig (spilleren lukkes) før sjekken;
  testen pauser nå før telefonen snus. 0.1.22 (bygg 42) er i TestFlight, VALID for TV_OS og IOS. Ikke prøvd på hans
  Pro Max ennå.
- 3.11.2026: eieren: «Gjerne forbedre appen så mye du kan, prøv å finn feil og gjør den så bra som mulig.» → 0.1.23,
  en gjennomgang (fire agenter på kjernen, spilleren, filmer/Plex og visningene, og skjermbildene). Det som ble gjort,
  står i CHANGELOG; i tillegg til det i Arkitektur: `XtreamClient.apiURL` kaster for en ugyldig adresse og koder «+»
  (PHP leser den som mellomrom), `auth: 0` = avvist, lister som objekter (`objectList`), tall som NaN/uendelig,
  base64 som ikke er det; `nameParts` tar bort et merke foran «|» (`isNameTag`); `channelKeyAndCountry` og
  `homeCountries` (en strøm uten land gjelder de norske); `ChannelIndex.streamKey(of:)`/`streamNames` (strømmen
  slås opp i indeksen); `durationText`/`seasonOrder`; `serverClock()` kaster, så den spørres igjen; `PlexModel`:
  `connectGeneration`, `reprobe()` (beholder den gamle når ingen svarer), rapportene i kø (`reports`),
  `finish` sier fra til fanene; `Images`: logo og farge sammen i `NSCache`, nettfeil prøves igjen etter 30 s;
  `HomeView().id(login)`; iPad: `Theme.bg` bak TV, Søk og Filmer/Serier (var systemets); iPhone: fliser og kort
  `.adaptive(minimum: 160)`, raden fire liggende, Konto i `ViewThatFits` med rulling, `SwipeBack` ikke under en
  overgang; Apple TV: knapper som sletter, uten `role` (rød tekst), `GuideView` med marginene utenpå
  `TimelineView`. Testene: feilen i spilleren vises før forklaringen (testene venter på «404»), og
  `test20EgneStrommer` sjekker reserven via `accessibilityValue` på `spiller` (`PlayerModel.tried`, stiene som er
  prøvd, bare i testene). 0.1.23 (bygg 43) er i TestFlight, VALID for TV_OS og IOS; alle UI-testene grønne
  (`test19PlexKobling` på iPad på andre forsøk), fartstesten 5,6 s uten lista fra sist og 4,9 s med. Ikke prøvd på
  hans enheter. Lagt inn etter bygg 43, kommer med neste versjon: feilteksten i spilleren uten «Kanalen kunne ikke
  spilles» to ganger (overskriften sier det), og rødt ikon på «Koble fra Plex» på iPhone/iPad.
- 3.11.2026 kl. 12: bildet av en annen IPTV-app (serier på iPhone) → 0.1.24, Hjem i Filmer og Serier (se Arkitektur),
  for både Filmer og Serier og alle enhetene (samme fane i koden); Apple TV og iPad beholder sidemenyen. Bygg 44:
  alle testene grønne, men TestFlight-jobben stoppet på et tidsavbrudd hos Apple (`POST /v1/profiles`, 60 s). Nå
  prøver `asc.py` igjen ved tidsavbrudd, brutt forbindelse og 5xx (tre ganger, 90 s), og `make_profile` bruker en
  profil med samme navn som et forsøk kan ha laget likevel. 0.1.24 (bygg 45) er i TestFlight, VALID for TV_OS og IOS;
  alle UI-testene grønne. Ikke prøvd på hans enheter: bakgrunnsbildene fra Plex i «Fortsett å se», «Se alle» på
  radene hans, søket mot hans Plex og leverandøren (alle seriene i ett svar), favorittene via iCloud.
- 3.11.2026: fra Windows/Android-økta kom lista over det Fyrlys for Windows og Android (2.1.35) kan som Apple-appen
  ikke kan (hvordan står i `ungerdas/fyrlys`, `.claude/CLAUDE.md`). Eieren valgte alt, i denne rekkefølgen: «Plex og
  episoder» (neste episode av seg selv og neste/forrige i spilleren, hopp over intro/rulletekst fra markørene,
  undertekstfiler fra Plex inn i VLC, merk sett/usett og «Mer som dette», http til en lokal adresse når ruteren stenger
  plex.direct), «Filmer og serier» (sortering og «Nylig lagt til» hos leverandøren, merker som 4K/HDR/5.1/alder/land,
  «[PRE]»/«[2026]» i navnet, «Mer fra <kategori>», søk på Apple TV, sjanger/sortering/sider i Plex), «Resten»
  (flere kanaler samtidig, M3U og XMLTV, feilrapport, egne navn på innloggingene) og «TV-spilleren» (pause og spol
  tilbake i direktesending med «DIREKTE», strøminfo, bildeformat per kanal). Ikke på Apple: Chromecast, minispiller,
  «Fjern striper», egen oppdatering, kanalnummer med tall.
- 4.11.2026: eieren (bilder av Apple TV-en): «Liker veldig godt visningen på tv-siden, så vil ikke du skal røre den
  noe særlig mer. Men se menyen på toppen, den er nok litt for høy?» Fanelinja sto halvveis ute over kanten fordi
  lista var rullet litt (merket over sidemenyen sto der det står i simulatoren) → 0.1.25 (se Arkitektur). Pakkene over
  kommer etter det.
- 4.11.2026: ny liste fra Windows-økta (2.1.38, med 10 skjule biblioteker og 16 X-Plex-Language); eieren valgte
  «Skjul Plex-biblioteker først» (10 og 16 med i 0.1.26), så «Resten» og «TV-spilleren» som før.
- 4.11.2026: 0.1.26 = pakkene «Plex og episoder» og «Filmer og serier» (se Arkitektur). Ikke prøvd mot hans Plex:
  markørene (krever at Plex har funnet dem: «Intro/Credits detection»), undertekstfilene i VLC over nettet, adressen
  rett i hjemmenettet, sjangrene og sidene i store bibliotek. Igjen fra lista: «Resten» (flere kanaler samtidig, M3U og
  XMLTV, feilrapport, egne navn på innloggingene) og «TV-spilleren» (pause og spol tilbake i direktesending, strøminfo,
  bildeformat).
- 4.11.2026: 0.1.27 (egne navn, feilrapport), 0.1.28 (M3U og XMLTV), 0.1.29 (multiview) og 0.1.30 (pause og
  tilbakespoling i direktesending, bildeformat, strøminfo) er laget: hele lista fra Windows-økta er gjort (lydforsinkelse
  finnes ikke med AVPlayer). Bygg 48 (0.1.25) kom ikke til TestFlight: iPhone-jobben feilet på `test17Mkv` (testfilmen
  på 30 s var ferdig midt i testen; den pauser nå med en gang), og så fikk den ingen Mac. Bygg 50 (0.1.29) kompilerte
  for begge, men fem Apple TV-tester fant ikke fokus (menyene over plakatene står til høyre: overskriften er nå et
  `tvFocusSection`; i en liste i et ark står fokus på cellen, ikke på knappen med id-en: kanalvalget i multiview og
  bibliotekene er knapper og brytere i en rulleliste på Apple TV, og testene har `hasFocus(app, element, label:)` og
  `focusDown`; `test22` begynner fra «Fortsett å se»), og på iPhone fantes «Filmer» både som fane og bibliotek og
  «Lagre» to ganger i varselet. `FlowLayout` fikk slakk (det siste merket på filmsiden havnet oppå teksten under). M3U,
  multiview, feilrapporten og søket på Apple TV virket i simulatorene (bildene 47–54).
- 4.–5.11.2026: bygg 51–55 kom ikke til TestFlight (bare testene på Apple TV, og én på iPhone): fokus i menyene over
  plakatene (`focusedOn`: elementet med fokus ligger oppå menyen), valget i menyen (`focusCovers`: i en meny på Apple TV
  har elementet med fokus verken id eller tekst, men står der valget er; menyene er knapper med hake på Apple TV, ikke
  en Picker), den tredje raden på Hjem på Apple TV (LazyVStack: `reveal` går ned til den), knappen til slutt i raden på
  iPhone (`isHittable` feiler utenfor skjermen: rammen sjekkes), og ned fra menyen til plakatene når ingen står rett
  under (plakatene er en `tvFocusSection`; en ekte feil). Underveis (eieren 4.11 kl. 23): Plex-fanen (se Arkitektur),
  så «Vi trenger ikke sjangermeny.» (tatt bort). 0.1.31 (bygg 56) er i TestFlight, VALID for TV_OS og IOS; alle
  UI-testene grønne. Den første i TestFlight siden 0.1.24 (bygg 45): med 0.1.25–0.1.31. iPad på høykant: sju faner får
  ikke plass i fanelinja (iPadOS 18), Innstillinger står bak pila til høyre (sagt til eieren). Ikke prøvd på hans
  enheter: Plex-fanen mot hans server, pause/tilbakespoling med leverandøren hans, M3U, multiview (trenger to
  innlogginger eller to tilkoblinger), markørene og undertekstfilene fra Plex.
- 5.11.2026: eieren hadde 0.1.31 på Apple TV-en med Plex-fanen mot sin server (bilde: «Fortsett å se» med en serie og
  en film, «Nyeste Filmer», sidemenyen Hjem, Filmer, TV-serier). Ønsket hold inne for å skjule og flytte bibliotekene i
  stedet for «Velg biblioteker» → 0.1.32 (bygg 57, VALID for TV_OS og IOS, alle testene grønne på første forsøk).
  Skjermbildet viste at «Nytt fra Kystkanalen» (episodene uten bibliotek i den falske Plex) havnet til slutt etter
  flyttingen → 0.1.33 (`library(of:)` faller tilbake på slaget; `test26PlexBiblioteker` sjekker radene). 0.1.33
  (bygg 58) er i TestFlight, VALID for TV_OS og IOS; alle testene grønne, også radene i `test26` på iPhone og iPad.
- 5.11.2026 kveld: Plex Home → 0.1.34 (se Arkitektur). Bygg 59–61 feilet bare i `test32PlexHome` på Apple TV: etter
  feil PIN tømte appen feltet, tastaturet på tvOS ble lukket, og `typeText` etterpå kom ikke fram (dumpet skjerm viste
  tastaturet med fokus og tomt felt). Nå tømmes feltet bare på iOS; PIN på fire siffer bytter av seg selv
  (`onChange`), «Bytt» for lengre. 0.1.34 (bygg 62) er i TestFlight, VALID for TV_OS og IOS. `test17Mkv` (iPad) og
  `test22PlexEpisoder` (iPhone) flakset én gang i bygg 61 (timing). Ikke prøvd mot hans Plex Home ennå (brukere med
  begrenset tilgang, PIN, bildene fra plex.tv).
- 6.11.2026: eieren prøvde «Hvem ser på?» på Apple TV-en (bilde: fire brukere med bilder fra plex.tv): byttet ga
  «Plex svarte HTTP 404» → 0.1.35 (uuid i adressen, id som reserve). Bygg 63 i TestFlight, VALID for TV_OS og IOS
  (iPhone-jobben kjørt på nytt: `test22PlexEpisoder` flakset igjen på «Hopp over introen»; bør få lengre
  tidsfrist om det fortsetter). Ikke bekreftet av eieren at byttet virker nå.
- 6.11.2026: «Syntes filmsiden er litt tom, mangler også logo på filmer og serier, plex har det nå.» → 0.1.36 (se
  Arkitektur). 0.1.36 (bygg 64) er i TestFlight, VALID for TV_OS og IOS; alle testene grønne (`test22PlexEpisoder`
  på iPhone på andre forsøk igjen). Ikke prøvd mot hans Plex: om logoene (clearLogo) finnes i `Image` på
  `/library/metadata/<id>` hos ham (Plex legger dem der når metadataagenten har dem), og bildene på rollene.
- 6.11.2026 kl. 18: eieren om 0.1.36 på Apple TV-en: «Liker det, men syntes oppløsingen virker å være lav? gjelder
  også Postere. i vanlig plex app så er de i høy oppløsing.» → 0.1.37 (se Arkitektur: alle bildene ble krympet til
  360 piksler). Bygg 65 fikk ingen Mac; 0.1.37 (bygg 66, startet med `workflow_dispatch`) er i TestFlight, VALID for
  TV_OS og IOS, alle testene grønne på første forsøk. Skarpheten synes ikke i simulatoren (den falske Plex sender
  alltid små, ensfargede bilder); ikke sett på en ekte Apple TV 4K ennå. Logoen bes om med `minSize=0&upscale=0` uten
  `format=`: i 0.1.36 (`minSize=1`, uten `format=`) så logoene riktige ut hos eieren, så Plex beholder
  gjennomsiktigheten; står de med svart boks bak, prøv `format=png`.
- 7.11.2026 (på eierens Mac): 0.2.1 = smalere sidemeny i Filmer/Serier/Plex på Apple TV (`Metrics.vodSidebarWidth`
  220; TV-siden 340 som før), «Fortsett å se» lagrer den neste episoden når en er sett ferdig (leverandøren), og
  episodebildet i episodelista. Bygget fra 0.2.1: TestFlight venter ikke på UI-testene (8 min fra push), iPhone og iPad
  testes samtidig (27 og 16 min). 0.2.1 (bygg 67) er i TestFlight, alle testene grønne. Eieren samler gjerne flere små
  endringer før en push. 0.2.2 = Mac-appen (se Arkitektur); lokalt bygget, kjørt og sett på (TV, guide, filmer,
  innstillinger, spilleren), Release-arkivet universelt og signert ad hoc. Ikke prøvd ennå: opplastingen av Mac til
  App Store Connect (profilen for en app-id registrert som IOS, installasjonssertifikatet), avspilling med lyd og bilde
  på Mac, VLC på Mac, iCloud og nøkkelringen i et signert bygg.
  Mac i TestFlight tok fire bygg: 68 (Apple TV og iPhone/iPad VALID; Mac: installasjonssertifikatet heter
  «3rd Party Mac Developer Installer: …», nå lest av `certificate_kind`), 69 (eksporten ventet i 35 min på tilgang
  til nøkkelen for productbuild: nøkkelen importeres nå med `-T` for productbuild/pkgbuild/productsign, og Mac-eksporten
  har en grense på 15 min med `perl -e 'alarm …'`), 70 (App Store Connect avviste pakken: filer bare root kunne lese,
  fordi steget har `umask 077` for nøklene; nå `umask 022` før eksporten) og **71: 0.2.2 VALID for TV_OS, IOS og
  MAC_OS**. Skjermbildene fra Mac ligger i `skjermbilder-mac` (første gang i bygg 69; i bygg 68 stoppet steget på en
  `pkill` uten treff, nå `|| true`). 8.11.2026: installert fra TestFlight på Mac-en hans (Intel, macOS 15.8; TestFlight-appen fantes
  fra før). Innloggingen og TV-kanalene virket; Plex spilte, men i et lite ark → 0.2.3 (se Arkitektur, Mac), sammen
  med: korte navn på sporene (`shortTrackName` i Core, `Tracks.swift`: «Norsk - [Norwegian]» → «Norsk»), og en
  episode i radene på Hjem og i «Fortsett å se» åpner serien på alle enhetene (eieren 8.11; i 0.2.1–0.2.2 ble
  episoden i «Fortsett å se» spilt med en gang), «Spill av episoden» i hurtigmenyen.
- 8.11.2026: 0.2.3 (bygg 72) i TestFlight, VALID for TV_OS, IOS og MAC_OS (iPad-testene feilet bare på
  oppstarten av simulatoren). Så 0.2.4 (se Arkitektur): lokalt bygget og testet (Mac med tastene, minispilleren og
  vinduet via System Events; påminnelsen og iPad-fanene i simulatoren); ikke prøvd: Siri på en ekte enhet, widgeten
  og Top Shelf-raden (krever signeringen med nøkkelring-gruppen), opplastingen med widgeten og den eksterne
  gruppen (hemmelighetene finnes bare i GitHub). Oppstarten med 25 000 kanaler målt: kjernen bruker ~0,6 s på
  Mac (tolke 0,25, indeks 0,04, lese lista fra sist 0,16); resten av tallet i fartstesten er at XCTest starter appen.
  0.2.4 (bygg 73) er i TestFlight, VALID for TV_OS, IOS og MAC_OS; alle jobbene grønne (også iPad). `asc.py`
  registrerte `no.fyrlys.tv.widget`, og byggene ble lagt til den eksterne gruppa og sendt til gjennomgang.
